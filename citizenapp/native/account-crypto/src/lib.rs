#![allow(unsafe_code)]
// FFI 边界必须解引用调用端传入的裸指针；所有长度均先校验，函数退出前清零秘密副本。

//! citizenapp 内部账户数据用途钥派生与冷钱包加密交付实现。
//!
//! 本 crate 不持有钱包、CID、Chat 或 MLS 状态，只实现四个无状态原语：
//! - 从账户 child mini-secret 和精确 CID 绑定上下文派生 32 字节用途钥；
//! - 从一次性 X25519 私钥计算会话公钥；
//! - 使用 X25519 + HKDF-SHA256 + AES-256-GCM 封装用途钥包；
//! - 使用相同上下文解封用途钥包。
//!
//! `0x22` 是上层对交付结果做 sr25519 授权的公开操作标签，不是本 crate 的秘密
//! 用途钥，也不参与替代 HKDF。所有输入缓冲由调用端持有，本 crate 不保存任何状态。

use aes_gcm::{
    aead::{Aead, Payload},
    Aes256Gcm, KeyInit, Nonce,
};
use hkdf::Hkdf;
use sha2::{Digest, Sha256};
use std::{panic::catch_unwind, slice};
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, Zeroizing};

const KEY_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;
const BINDING_DOMAIN: &[u8] = b"citizenapp.account-data/binding";
const PROVISION_DOMAIN: &[u8] = b"citizenapp.account-data/provision";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CryptoError {
    InvalidInput = 1,
    DeriveFailed = 2,
    EncryptFailed = 3,
    DecryptFailed = 4,
    OutputTooSmall = 5,
    Panic = 255,
}

fn derive_key(
    account_secret: &[u8; KEY_LEN],
    genesis_hash: &[u8; KEY_LEN],
    cid_number: &[u8],
    binding_revision: u64,
    account_id: &[u8; KEY_LEN],
    purpose: &[u8],
    context: &[u8],
) -> Result<[u8; KEY_LEN], CryptoError> {
    if cid_number.is_empty() || cid_number.len() > 32 || purpose.is_empty() || binding_revision == 0
    {
        return Err(CryptoError::InvalidInput);
    }
    let mut salt_material =
        Vec::with_capacity(BINDING_DOMAIN.len() + 1 + 66 + 1 + cid_number.len() + 1 + 20 + 1 + 66);
    salt_material.extend_from_slice(BINDING_DOMAIN);
    salt_material.push(b'|');
    salt_material.extend_from_slice(format_hex32(genesis_hash).as_bytes());
    salt_material.push(b'|');
    salt_material.extend_from_slice(cid_number);
    salt_material.push(b'|');
    salt_material.extend_from_slice(binding_revision.to_string().as_bytes());
    salt_material.push(b'|');
    salt_material.extend_from_slice(format_hex32(account_id).as_bytes());
    let salt = Sha256::digest(&salt_material);
    salt_material.zeroize();

    let mut info = Vec::with_capacity(purpose.len() + context.len() + 1);
    info.extend_from_slice(purpose);
    if !context.is_empty() {
        info.push(b'/');
        info.extend_from_slice(context);
    }
    let hkdf = Hkdf::<Sha256>::new(Some(&salt), account_secret);
    let mut output = [0u8; KEY_LEN];
    hkdf.expand(&info, &mut output)
        .map_err(|_| CryptoError::DeriveFailed)?;
    info.zeroize();
    Ok(output)
}

fn format_hex32(bytes: &[u8; KEY_LEN]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(66);
    output.push_str("0x");
    for byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

fn session_key(
    local_secret: &[u8; KEY_LEN],
    peer_public_key: &[u8; KEY_LEN],
    aad: &[u8],
) -> Result<Zeroizing<[u8; KEY_LEN]>, CryptoError> {
    if aad.is_empty() {
        return Err(CryptoError::InvalidInput);
    }
    let secret = StaticSecret::from(*local_secret);
    let peer = PublicKey::from(*peer_public_key);
    let mut shared = Zeroizing::new(secret.diffie_hellman(&peer).to_bytes());
    if shared.iter().all(|byte| *byte == 0) {
        return Err(CryptoError::InvalidInput);
    }
    let salt = Sha256::digest(aad);
    let hkdf = Hkdf::<Sha256>::new(Some(&salt), shared.as_ref());
    let mut output = Zeroizing::new([0u8; KEY_LEN]);
    hkdf.expand(PROVISION_DOMAIN, output.as_mut())
        .map_err(|_| CryptoError::DeriveFailed)?;
    shared.zeroize();
    Ok(output)
}

fn seal(
    recipient_public_key: &[u8; KEY_LEN],
    sender_secret: &[u8; KEY_LEN],
    nonce: &[u8; NONCE_LEN],
    plaintext: &[u8],
    aad: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    if plaintext.is_empty() {
        return Err(CryptoError::InvalidInput);
    }
    let key = session_key(sender_secret, recipient_public_key, aad)?;
    Aes256Gcm::new_from_slice(key.as_ref())
        .map_err(|_| CryptoError::EncryptFailed)?
        .encrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|_| CryptoError::EncryptFailed)
}

fn open(
    recipient_secret: &[u8; KEY_LEN],
    sender_public_key: &[u8; KEY_LEN],
    nonce: &[u8; NONCE_LEN],
    ciphertext: &[u8],
    aad: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    if ciphertext.len() <= TAG_LEN {
        return Err(CryptoError::InvalidInput);
    }
    let key = session_key(recipient_secret, sender_public_key, aad)?;
    Aes256Gcm::new_from_slice(key.as_ref())
        .map_err(|_| CryptoError::DecryptFailed)?
        .decrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|_| CryptoError::DecryptFailed)
}

unsafe fn fixed<const N: usize>(pointer: *const u8) -> Result<[u8; N], CryptoError> {
    if pointer.is_null() {
        return Err(CryptoError::InvalidInput);
    }
    let mut output = [0u8; N];
    output.copy_from_slice(slice::from_raw_parts(pointer, N));
    Ok(output)
}

unsafe fn bytes<'a>(pointer: *const u8, length: usize) -> Result<&'a [u8], CryptoError> {
    if length == 0 {
        return Ok(&[]);
    }
    if pointer.is_null() {
        return Err(CryptoError::InvalidInput);
    }
    Ok(slice::from_raw_parts(pointer, length))
}

fn ffi_result(operation: impl FnOnce() -> Result<(), CryptoError>) -> i32 {
    match catch_unwind(std::panic::AssertUnwindSafe(operation)) {
        Ok(Ok(())) => 0,
        Ok(Err(error)) => error as i32,
        Err(_) => CryptoError::Panic as i32,
    }
}

/// 在最终移动端动态库内导出账户密码学 C ABI。
#[macro_export]
macro_rules! export_account_crypto_ffi {
    () => {
        #[no_mangle]
        pub unsafe extern "C" fn account_crypto_derive_key(
            account_secret: *const u8,
            genesis_hash: *const u8,
            cid_number: *const u8,
            cid_number_len: usize,
            binding_revision: u64,
            account_id: *const u8,
            purpose: *const u8,
            purpose_len: usize,
            context: *const u8,
            context_len: usize,
            output: *mut u8,
        ) -> i32 {
            $crate::ffi_derive_key(
                account_secret,
                genesis_hash,
                cid_number,
                cid_number_len,
                binding_revision,
                account_id,
                purpose,
                purpose_len,
                context,
                context_len,
                output,
            )
        }

        #[no_mangle]
        pub unsafe extern "C" fn account_crypto_x25519_public_key(
            secret: *const u8,
            output: *mut u8,
        ) -> i32 {
            $crate::ffi_x25519_public_key(secret, output)
        }

        #[no_mangle]
        pub unsafe extern "C" fn account_crypto_seal(
            recipient_public_key: *const u8,
            sender_secret: *const u8,
            nonce: *const u8,
            plaintext: *const u8,
            plaintext_len: usize,
            aad: *const u8,
            aad_len: usize,
            output: *mut u8,
            output_capacity: usize,
            output_len: *mut usize,
        ) -> i32 {
            $crate::ffi_seal(
                recipient_public_key,
                sender_secret,
                nonce,
                plaintext,
                plaintext_len,
                aad,
                aad_len,
                output,
                output_capacity,
                output_len,
            )
        }

        #[no_mangle]
        pub unsafe extern "C" fn account_crypto_open(
            recipient_secret: *const u8,
            sender_public_key: *const u8,
            nonce: *const u8,
            ciphertext: *const u8,
            ciphertext_len: usize,
            aad: *const u8,
            aad_len: usize,
            output: *mut u8,
            output_capacity: usize,
            output_len: *mut usize,
        ) -> i32 {
            $crate::ffi_open(
                recipient_secret,
                sender_public_key,
                nonce,
                ciphertext,
                ciphertext_len,
                aad,
                aad_len,
                output,
                output_capacity,
                output_len,
            )
        }
    };
}

#[doc(hidden)]
#[allow(clippy::too_many_arguments)] // C ABI 固定为扁平参数，不能改成 Rust 结构体布局。
pub unsafe fn ffi_derive_key(
    account_secret: *const u8,
    genesis_hash: *const u8,
    cid_number: *const u8,
    cid_number_len: usize,
    binding_revision: u64,
    account_id: *const u8,
    purpose: *const u8,
    purpose_len: usize,
    context: *const u8,
    context_len: usize,
    output: *mut u8,
) -> i32 {
    ffi_result(|| {
        if output.is_null() {
            return Err(CryptoError::InvalidInput);
        }
        let mut secret = Zeroizing::new(unsafe { fixed::<KEY_LEN>(account_secret)? });
        let mut key = Zeroizing::new(derive_key(
            &secret,
            &unsafe { fixed::<KEY_LEN>(genesis_hash)? },
            unsafe { bytes(cid_number, cid_number_len)? },
            binding_revision,
            &unsafe { fixed::<KEY_LEN>(account_id)? },
            unsafe { bytes(purpose, purpose_len)? },
            unsafe { bytes(context, context_len)? },
        )?);
        unsafe { slice::from_raw_parts_mut(output, KEY_LEN) }.copy_from_slice(key.as_ref());
        key.zeroize();
        secret.zeroize();
        Ok(())
    })
}

#[doc(hidden)]
pub unsafe fn ffi_x25519_public_key(secret: *const u8, output: *mut u8) -> i32 {
    ffi_result(|| {
        if output.is_null() {
            return Err(CryptoError::InvalidInput);
        }
        let mut secret_bytes = Zeroizing::new(unsafe { fixed::<KEY_LEN>(secret)? });
        let public = PublicKey::from(&StaticSecret::from(*secret_bytes)).to_bytes();
        unsafe { slice::from_raw_parts_mut(output, KEY_LEN) }.copy_from_slice(&public);
        secret_bytes.zeroize();
        Ok(())
    })
}

#[doc(hidden)]
#[allow(clippy::too_many_arguments)] // C ABI 固定为扁平参数，不能改成 Rust 结构体布局。
pub unsafe fn ffi_seal(
    recipient_public_key: *const u8,
    sender_secret: *const u8,
    nonce: *const u8,
    plaintext: *const u8,
    plaintext_len: usize,
    aad: *const u8,
    aad_len: usize,
    output: *mut u8,
    output_capacity: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_result(|| {
        if output.is_null() || output_len.is_null() || output_capacity < plaintext_len + TAG_LEN {
            return Err(CryptoError::OutputTooSmall);
        }
        let mut sender = Zeroizing::new(unsafe { fixed::<KEY_LEN>(sender_secret)? });
        let ciphertext = seal(
            &unsafe { fixed::<KEY_LEN>(recipient_public_key)? },
            &sender,
            &unsafe { fixed::<NONCE_LEN>(nonce)? },
            unsafe { bytes(plaintext, plaintext_len)? },
            unsafe { bytes(aad, aad_len)? },
        )?;
        (unsafe { slice::from_raw_parts_mut(output, output_capacity) })[..ciphertext.len()]
            .copy_from_slice(&ciphertext);
        unsafe { *output_len = ciphertext.len() };
        sender.zeroize();
        Ok(())
    })
}

#[doc(hidden)]
#[allow(clippy::too_many_arguments)] // C ABI 固定为扁平参数，不能改成 Rust 结构体布局。
pub unsafe fn ffi_open(
    recipient_secret: *const u8,
    sender_public_key: *const u8,
    nonce: *const u8,
    ciphertext: *const u8,
    ciphertext_len: usize,
    aad: *const u8,
    aad_len: usize,
    output: *mut u8,
    output_capacity: usize,
    output_len: *mut usize,
) -> i32 {
    ffi_result(|| {
        if output.is_null()
            || output_len.is_null()
            || ciphertext_len <= TAG_LEN
            || output_capacity < ciphertext_len - TAG_LEN
        {
            return Err(CryptoError::OutputTooSmall);
        }
        let mut recipient = Zeroizing::new(unsafe { fixed::<KEY_LEN>(recipient_secret)? });
        let mut plaintext = open(
            &recipient,
            &unsafe { fixed::<KEY_LEN>(sender_public_key)? },
            &unsafe { fixed::<NONCE_LEN>(nonce)? },
            unsafe { bytes(ciphertext, ciphertext_len)? },
            unsafe { bytes(aad, aad_len)? },
        )?;
        (unsafe { slice::from_raw_parts_mut(output, output_capacity) })[..plaintext.len()]
            .copy_from_slice(&plaintext);
        unsafe { *output_len = plaintext.len() };
        plaintext.zeroize();
        recipient.zeroize();
        Ok(())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_key_is_stable_and_context_separated() {
        let secret = [7u8; 32];
        let genesis = [8u8; 32];
        let account = [9u8; 32];
        let first = derive_key(
            &secret,
            &genesis,
            b"8964-TEST",
            3,
            &account,
            b"citizenapp.account-data/chat",
            b"",
        );
        let same = derive_key(
            &secret,
            &genesis,
            b"8964-TEST",
            3,
            &account,
            b"citizenapp.account-data/chat",
            b"",
        );
        let other = derive_key(
            &secret,
            &genesis,
            b"8964-TEST",
            3,
            &account,
            b"citizenapp.account-data/mls",
            b"",
        );
        assert!(first.is_ok());
        assert_eq!(first, same);
        assert_ne!(first, other);
    }

    #[test]
    fn x25519_aes_gcm_round_trip_binds_aad() {
        let recipient_secret = [11u8; 32];
        let sender_secret = [22u8; 32];
        let recipient_public = PublicKey::from(&StaticSecret::from(recipient_secret)).to_bytes();
        let sender_public = PublicKey::from(&StaticSecret::from(sender_secret)).to_bytes();
        let nonce = [33u8; 12];
        let plaintext = b"account-data-keys";
        let ciphertext = seal(
            &recipient_public,
            &sender_secret,
            &nonce,
            plaintext,
            b"request-1",
        );
        assert!(ciphertext.is_ok());
        if let Ok(ciphertext) = ciphertext {
            assert_eq!(
                open(
                    &recipient_secret,
                    &sender_public,
                    &nonce,
                    &ciphertext,
                    b"request-1",
                ),
                Ok(plaintext.to_vec()),
            );
            assert_eq!(
                open(
                    &recipient_secret,
                    &sender_public,
                    &nonce,
                    &ciphertext,
                    b"request-2",
                ),
                Err(CryptoError::DecryptFailed),
            );
        }
    }
}
