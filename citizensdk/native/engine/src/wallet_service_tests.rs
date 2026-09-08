//! 无根热钱包生命周期、CAS 写后异常与补偿所有权的 Engine 级测试。
//!
//! 内存 fake 刻意把公开 profile、设备密文与硬件钱包密钥分成三个独立事实源，测试
//! 不会因为一个“万能 Map”而掩盖孤儿密文、误删其它实例成功钱包或删除契约遗漏。

#![allow(clippy::expect_used, clippy::unwrap_used)]

use std::{
    collections::{HashMap, HashSet},
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        Arc, Mutex,
    },
};

use crate::{
    error::EngineError,
    wallet_derivation::{WalletEntropySource, WalletWordCount},
    wallet_service::{SigningService, WalletClock, WalletService},
};
use citizen_sdk_contracts::{
    store::{EncryptedSecretBlobStore, WalletProfileStore},
    AccountId32, ChainSigner, ContractError, ContractErrorCode, ContractFuture, ContractResult,
    EncryptedSecretBlobSnapshot, EncryptedSecretBlobState, EncryptedSecretEnvelope, Hash32Bytes,
    SecretBuffer, SecretOwner, SecretRef, SecretVault, VaultAvailability, VaultGeneration,
    WalletCleanupPlan, WalletOrigin, WalletProvisioningPlan, WalletState,
};
use citizen_signer::Sr25519SoftwareSigner;
use futures::{executor::block_on, join};
use zeroize::Zeroizing;

const KNOWN_MNEMONIC: &str =
    "bottom drive obey lake curtain smoke basket hold race lonely fit walk";

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
enum WriteFault {
    #[default]
    None,
    BeforeWrite,
    AfterWrite,
}

#[derive(Debug)]
struct MemoryWalletProfileStore {
    state: Mutex<WalletState>,
    next_fault: Mutex<WriteFault>,
    fail_before_call: Mutex<Option<usize>>,
    cas_calls: AtomicUsize,
}

impl Default for MemoryWalletProfileStore {
    fn default() -> Self {
        Self {
            state: Mutex::new(WalletState::empty()),
            next_fault: Mutex::new(WriteFault::None),
            fail_before_call: Mutex::new(None),
            cas_calls: AtomicUsize::new(0),
        }
    }
}

impl MemoryWalletProfileStore {
    fn fail_next_after_write(&self) {
        *self.next_fault.lock().unwrap() = WriteFault::AfterWrite;
    }

    fn fail_before_exact_call(&self, call: usize) {
        *self.fail_before_call.lock().unwrap() = Some(call);
    }

    fn snapshot(&self) -> WalletState {
        self.state.lock().unwrap().clone()
    }
}

impl WalletProfileStore for MemoryWalletProfileStore {
    fn load(&self) -> ContractFuture<'_, WalletState> {
        Box::pin(async move { Ok(self.state.lock().unwrap().clone()) })
    }

    fn compare_and_swap(
        &self,
        expected_revision: u64,
        next: WalletState,
    ) -> ContractFuture<'_, WalletState> {
        Box::pin(async move {
            let call = self.cas_calls.fetch_add(1, Ordering::SeqCst) + 1;
            let fail_before = {
                let mut planned_call = self.fail_before_call.lock().unwrap();
                if *planned_call == Some(call) {
                    *planned_call = None;
                    true
                } else {
                    false
                }
            };
            if fail_before {
                return Err(storage_error("profile CAS 在写入前失败"));
            }
            let fault = std::mem::replace(&mut *self.next_fault.lock().unwrap(), WriteFault::None);
            if fault == WriteFault::BeforeWrite {
                return Err(storage_error("profile CAS 在写入前失败"));
            }
            let mut state = self.state.lock().unwrap();
            if state.revision() != expected_revision {
                return Err(conflict_error("profile revision 冲突"));
            }
            if next.revision() != expected_revision.saturating_add(1) {
                return Err(storage_error("profile candidate revision 不连续"));
            }
            *state = next.clone();
            if fault == WriteFault::AfterWrite {
                return Err(storage_error("profile CAS 已写入但平台抛错"));
            }
            Ok(next)
        })
    }
}

#[derive(Debug, Default)]
struct MemoryEncryptedSecretStore {
    entries: Mutex<HashMap<SecretRef, EncryptedSecretBlobSnapshot>>,
    next_fault: Mutex<WriteFault>,
    deletion_order: Mutex<Vec<SecretRef>>,
}

impl MemoryEncryptedSecretStore {
    fn fail_next_after_write(&self) {
        *self.next_fault.lock().unwrap() = WriteFault::AfterWrite;
    }

    fn envelope_count(&self) -> usize {
        self.entries
            .lock()
            .unwrap()
            .values()
            .filter(|snapshot| snapshot.envelope().is_some())
            .count()
    }

    fn has_envelope(&self, secret_ref: SecretRef) -> bool {
        self.entries
            .lock()
            .unwrap()
            .get(&secret_ref)
            .is_some_and(|snapshot| snapshot.envelope().is_some())
    }

    fn remove_without_contract(&self, secret_ref: SecretRef) {
        self.entries
            .lock()
            .unwrap()
            .insert(secret_ref, EncryptedSecretBlobSnapshot::empty());
    }

    fn insert_envelope(&self, secret_ref: SecretRef) {
        let snapshot = EncryptedSecretBlobSnapshot::empty()
            .try_advance(EncryptedSecretBlobState::Sealed {
                provisioning_operation_id: [0x61; 16],
                envelope: test_envelope(secret_ref),
            })
            .unwrap();
        self.entries.lock().unwrap().insert(secret_ref, snapshot);
    }
}

impl EncryptedSecretBlobStore for MemoryEncryptedSecretStore {
    fn load(&self, secret_ref: SecretRef) -> ContractFuture<'_, EncryptedSecretBlobSnapshot> {
        Box::pin(async move {
            Ok(self
                .entries
                .lock()
                .unwrap()
                .get(&secret_ref)
                .cloned()
                .unwrap_or_else(EncryptedSecretBlobSnapshot::empty))
        })
    }

    fn compare_and_swap(
        &self,
        secret_ref: SecretRef,
        expected_revision: u64,
        next_state: EncryptedSecretBlobState,
    ) -> ContractFuture<'_, EncryptedSecretBlobSnapshot> {
        Box::pin(async move {
            let fault = std::mem::replace(&mut *self.next_fault.lock().unwrap(), WriteFault::None);
            if fault == WriteFault::BeforeWrite {
                return Err(storage_error("密文 CAS 在写入前失败"));
            }
            let mut entries = self.entries.lock().unwrap();
            let current = entries
                .get(&secret_ref)
                .cloned()
                .unwrap_or_else(EncryptedSecretBlobSnapshot::empty);
            if current.revision() != expected_revision {
                return Err(conflict_error("密文 revision 冲突"));
            }
            let deleted_existing = current.envelope().is_some() && next_state.is_tombstone();
            let next = current.try_advance(next_state)?;
            entries.insert(secret_ref, next.clone());
            if deleted_existing {
                self.deletion_order.lock().unwrap().push(secret_ref);
            }
            if fault == WriteFault::AfterWrite {
                return Err(storage_error("密文 CAS 已写入但平台抛错"));
            }
            Ok(next)
        })
    }
}

#[derive(Debug)]
struct MemorySecretVault {
    availability: Mutex<VaultAvailability>,
    wallet_keys: Mutex<HashSet<(u32, VaultGeneration)>>,
    retired_wallets: Mutex<HashSet<(u32, VaultGeneration)>>,
    delete_wallet_calls: AtomicUsize,
    open_calls: AtomicUsize,
    open_completed: AtomicUsize,
    open_gate: Mutex<Option<futures::channel::oneshot::Receiver<()>>>,
    open_entered: Mutex<Option<futures::channel::oneshot::Sender<()>>>,
}

impl Default for MemorySecretVault {
    fn default() -> Self {
        Self {
            availability: Mutex::new(VaultAvailability::Available),
            wallet_keys: Mutex::new(HashSet::new()),
            retired_wallets: Mutex::new(HashSet::new()),
            delete_wallet_calls: AtomicUsize::new(0),
            open_calls: AtomicUsize::new(0),
            open_completed: AtomicUsize::new(0),
            open_gate: Mutex::new(None),
            open_entered: Mutex::new(None),
        }
    }
}

impl MemorySecretVault {
    fn has_key(&self, wallet_index: u32, generation: VaultGeneration) -> bool {
        self.wallet_keys
            .lock()
            .unwrap()
            .contains(&(wallet_index, generation))
    }
}

impl SecretVault for MemorySecretVault {
    fn availability(&self) -> ContractFuture<'_, VaultAvailability> {
        Box::pin(async move { Ok(*self.availability.lock().unwrap()) })
    }

    fn seal(
        &self,
        _provisioning_operation_id: [u8; 16],
        secret_ref: SecretRef,
        secret: SecretBuffer,
    ) -> ContractFuture<'_, EncryptedSecretEnvelope> {
        Box::pin(async move {
            if self
                .retired_wallets
                .lock()
                .unwrap()
                .contains(&(secret_ref.wallet_index(), secret_ref.generation()))
            {
                return Err(ContractError::new(
                    ContractErrorCode::KeyInvalidated,
                    "测试 generation 已退休",
                ));
            }
            self.wallet_keys
                .lock()
                .unwrap()
                .insert((secret_ref.wallet_index(), secret_ref.generation()));
            let ciphertext = secret.with_secret(ToOwned::to_owned);
            EncryptedSecretEnvelope::try_new(
                1,
                Hash32Bytes::from_bytes(secret_ref_digest(secret_ref)),
                ciphertext,
            )
        })
    }

    fn open(
        &self,
        secret_ref: SecretRef,
        envelope: EncryptedSecretEnvelope,
    ) -> ContractFuture<'_, SecretBuffer> {
        Box::pin(async move {
            self.open_calls.fetch_add(1, Ordering::SeqCst);
            if let Some(entered) = self.open_entered.lock().unwrap().take() {
                let _ = entered.send(());
            }
            let gate = self.open_gate.lock().unwrap().take();
            if let Some(gate) = gate {
                let _ = gate.await;
            }
            self.open_completed.fetch_add(1, Ordering::SeqCst);
            if !self.has_key(secret_ref.wallet_index(), secret_ref.generation()) {
                return Err(ContractError::new(
                    ContractErrorCode::KeyInvalidated,
                    "测试钱包密钥不存在",
                ));
            }
            if envelope.associated_data_digest().as_bytes() != &secret_ref_digest(secret_ref) {
                return Err(ContractError::new(
                    ContractErrorCode::Integrity,
                    "测试密文 AAD 与 SecretRef 不一致",
                ));
            }
            SecretBuffer::try_new(envelope.ciphertext().to_vec())
        })
    }

    fn has_wallet_key(
        &self,
        wallet_index: u32,
        generation: VaultGeneration,
    ) -> ContractFuture<'_, bool> {
        Box::pin(async move { Ok(self.has_key(wallet_index, generation)) })
    }

    fn delete_wallet_key(
        &self,
        _cleanup_operation_id: [u8; 16],
        wallet_index: u32,
        generation: VaultGeneration,
    ) -> ContractFuture<'_, ()> {
        Box::pin(async move {
            self.delete_wallet_calls.fetch_add(1, Ordering::SeqCst);
            self.retired_wallets
                .lock()
                .unwrap()
                .insert((wallet_index, generation));
            self.wallet_keys
                .lock()
                .unwrap()
                .remove(&(wallet_index, generation));
            Ok(())
        })
    }
}

#[derive(Debug, Default)]
struct CountingEntropy(AtomicU64);

impl WalletEntropySource for CountingEntropy {
    fn fill(&self, output: &mut [u8]) -> ContractResult<()> {
        let sequence = self.0.fetch_add(1, Ordering::SeqCst);
        for (offset, byte) in output.iter_mut().enumerate() {
            *byte = sequence.wrapping_add(offset as u64) as u8;
        }
        Ok(())
    }
}

#[derive(Debug)]
struct IncrementingClock(AtomicU64);

impl Default for IncrementingClock {
    fn default() -> Self {
        Self(AtomicU64::new(1_700_000_000_000))
    }
}

impl WalletClock for IncrementingClock {
    fn now_millis(&self) -> ContractResult<u64> {
        Ok(self.0.fetch_add(1, Ordering::SeqCst))
    }
}

struct Harness {
    service: WalletService,
    signer: Arc<Sr25519SoftwareSigner>,
    vault: Arc<MemorySecretVault>,
    profiles: Arc<MemoryWalletProfileStore>,
    secrets: Arc<MemoryEncryptedSecretStore>,
    entropy: Arc<CountingEntropy>,
    clock: Arc<IncrementingClock>,
}

impl Harness {
    fn new() -> Self {
        let signer = Arc::new(Sr25519SoftwareSigner);
        let vault = Arc::new(MemorySecretVault::default());
        let profiles = Arc::new(MemoryWalletProfileStore::default());
        let secrets = Arc::new(MemoryEncryptedSecretStore::default());
        let entropy = Arc::new(CountingEntropy::default());
        let clock = Arc::new(IncrementingClock::default());
        let service = WalletService::new(
            signer.clone(),
            vault.clone(),
            profiles.clone(),
            secrets.clone(),
            entropy.clone(),
            clock.clone(),
        );
        Self {
            service,
            signer,
            vault,
            profiles,
            secrets,
            entropy,
            clock,
        }
    }

    fn signing_service(&self) -> SigningService {
        SigningService::new(
            self.signer.clone(),
            self.vault.clone(),
            self.profiles.clone(),
            self.secrets.clone(),
        )
    }

    fn engine(&self, modules: citizen_sdk_contracts::Modules) -> crate::CitizenEngine {
        let engine = crate::CitizenEngine::new(
            crate::EngineComponents::new(
                None,
                Some(self.signer.clone()),
                Some(self.vault.clone()),
                None,
                None,
                Some(self.profiles.clone()),
                None,
                Some(self.secrets.clone()),
            )
            .with_modules(modules),
        );
        engine
            .update_capabilities(
                citizen_sdk_contracts::CapabilityName::ALL
                    .into_iter()
                    .map(crate::CapabilityProbe::ready)
                    .collect(),
            )
            .expect("模块能力快照");
        engine
    }

    fn second_service(&self) -> WalletService {
        WalletService::new(
            self.signer.clone(),
            self.vault.clone(),
            self.profiles.clone(),
            self.secrets.clone(),
            self.entropy.clone(),
            self.clock.clone(),
        )
    }
}

#[test]
fn signing_guard_rejects_before_auth_without_wallet_management() {
    block_on(async {
        let harness = Harness::new();
        let mnemonic = SecretBuffer::try_new(KNOWN_MNEMONIC.as_bytes().to_vec()).unwrap();
        let profile = harness.service.import(&mnemonic, "").await.unwrap();
        let auth_before = harness.vault.open_calls.load(Ordering::SeqCst);
        let writes_before = harness.profiles.cas_calls.load(Ordering::SeqCst);
        let result = harness.signing_service().sign_guarded(profile.master_account_id(), vec![4, 0], &|| Err(EngineError::Cancelled)).await;
        assert_eq!(result, Err(EngineError::Cancelled));
        assert_eq!(harness.vault.open_calls.load(Ordering::SeqCst), auth_before);
        assert_eq!(harness.profiles.cas_calls.load(Ordering::SeqCst), writes_before);
    });
}

#[test]
fn signing_guard_cancellation_drains_late_auth_and_never_returns_signature() {
    use std::sync::atomic::AtomicBool;
    block_on(async {
        let harness = Harness::new();
        harness.entropy.0.store(224, Ordering::SeqCst);
        let mnemonic = SecretBuffer::try_new(KNOWN_MNEMONIC.as_bytes().to_vec()).unwrap();
        let profile = harness.service.import(&mnemonic, "").await.unwrap();
        let (release, gate) = futures::channel::oneshot::channel();
        *harness.vault.open_gate.lock().unwrap() = Some(gate);
        let (entered, entered_rx) = futures::channel::oneshot::channel();
        *harness.vault.open_entered.lock().unwrap() = Some(entered);
        let cancelled = AtomicBool::new(false);
        let completed = harness.vault.open_completed.load(Ordering::SeqCst);
        let guard = || if cancelled.load(Ordering::SeqCst) { Err(EngineError::Cancelled) } else { Ok(()) };
        let service = harness.signing_service();
        let work = Box::pin(service.sign_guarded(profile.master_account_id(), vec![4, 0], &guard));
        let work = match futures::future::select(work, entered_rx).await {
            futures::future::Either::Right((Ok(()), work)) => work,
            _ => panic!("必须进入真实授权等待"),
        };
        cancelled.store(true, Ordering::SeqCst);
        assert_eq!(harness.vault.open_completed.load(Ordering::SeqCst), completed);
        release.send(()).unwrap();
        assert_eq!(work.await, Err(EngineError::Cancelled));
        assert_eq!(harness.vault.open_completed.load(Ordering::SeqCst), completed + 1);
    });
}

#[test]
fn every_supported_word_count_round_trips_backup_import_accounts_and_deletion() {
    block_on(async {
        for count in [
            WalletWordCount::Words12,
            WalletWordCount::Words18,
            WalletWordCount::Words24,
        ] {
            for password in ["", "abcdef"] {
                let created = Harness::new();
                let prepared = created
                    .service
                    .prepare_create(count, Zeroizing::new(password.to_owned()))
                    .await
                    .unwrap();
                assert!(created.profiles.snapshot().profile().is_none());
                assert_eq!(created.secrets.envelope_count(), 0);
                let backup = prepared.with_mnemonic(|words| {
                    assert_eq!(
                        std::str::from_utf8(words)
                            .unwrap()
                            .split_whitespace()
                            .count(),
                        count.words()
                    );
                    SecretBuffer::try_new(words.to_vec()).unwrap()
                });
                let profile = created
                    .service
                    .commit_create_after_backup(prepared)
                    .await
                    .unwrap();
                let restored = Harness::new();
                let imported = restored.service.import(&backup, password).await.unwrap();
                assert_eq!(profile.master_account_id(), imported.master_account_id());
                let accounts = restored
                    .service
                    .add_accounts(&backup, password, &[1989, 1])
                    .await
                    .unwrap();
                assert_eq!(
                    accounts
                        .iter()
                        .map(|account| account.index())
                        .collect::<Vec<_>>(),
                    vec![1, 1989]
                );
                let before = restored.profiles.snapshot();
                assert!(restored
                    .service
                    .add_accounts(&backup, "wrong!", &[2])
                    .await
                    .is_err());
                assert_eq!(restored.profiles.snapshot(), before);
                restored
                    .service
                    .delete_account(accounts[0].account_id())
                    .await
                    .unwrap();
                restored.service.delete_wallet().await.unwrap();
                assert!(restored.service.profile().await.unwrap().is_none());
                assert_eq!(restored.secrets.envelope_count(), 0);
            }
        }
    });
}

#[test]
fn create_add_accounts_usability_and_local_signing_form_one_complete_lifecycle() {
    block_on(async {
        let harness = Harness::new();
        let (created_profile, mnemonic) =
            create_confirmed(&harness.service, WalletWordCount::Words12, "Aa1!中华").await;
        assert_eq!(created_profile.origin(), WalletOrigin::Created);
        assert_eq!(created_profile.accounts().len(), 1);
        assert_eq!(
            harness.service.usable_profile().await.unwrap(),
            Some(created_profile.clone())
        );

        let master = created_profile.master_account_id();
        let message = b"CitizenSDK wallet signing contract".to_vec();
        let signature = harness
            .signing_service()
            .sign(master, message.clone())
            .await
            .expect("账户0本地签名");
        assert!(harness
            .signer
            .verify(
                citizen_sdk_contracts::Sr25519PublicKey::from_bytes(*master.as_bytes()),
                message,
                signature,
            )
            .await
            .unwrap());

        let added = harness
            .service
            .add_accounts(&mnemonic, "Aa1!中华", &[2, 1])
            .await
            .expect("追加账户按 index 排序");
        assert_eq!(
            added
                .iter()
                .map(|account| account.index())
                .collect::<Vec<_>>(),
            vec![1, 2]
        );
        let child_one = added[0].account_id();
        let active = harness
            .service
            .set_active_account(child_one)
            .await
            .expect("切换 active account");
        assert_eq!(active.active_account_id(), child_one);
        let renamed = harness
            .service
            .rename_account(child_one, " 日常账户 ")
            .await
            .expect("重命名账户");
        assert_eq!(renamed.account_by_id(child_one).unwrap().name(), "日常账户");
        assert_eq!(harness.secrets.envelope_count(), 3);
        assert_eq!(
            harness.service.usable_profile().await.unwrap(),
            Some(renamed)
        );

        let before = harness.profiles.snapshot();
        assert_contract_code(
            harness
                .service
                .add_accounts(&mnemonic, "wrong!", &[3])
                .await
                .expect_err("错误 password 不得追加账户"),
            ContractErrorCode::AuthenticationRequired,
        );
        assert_eq!(harness.profiles.snapshot(), before);
    });
}

#[test]
fn import_uses_the_same_verified_account_and_missing_ciphertext_is_not_usable() {
    block_on(async {
        let harness = Harness::new();
        let mnemonic = known_mnemonic();
        let imported = harness
            .service
            .import(&mnemonic, "")
            .await
            .expect("导入冻结助记词");
        assert_eq!(imported.origin(), WalletOrigin::Imported);
        assert_eq!(
            imported.master_account_id().as_bytes(),
            &decode_fixed_hex::<32>(
                "2afba9278e30ccf6a6ceb3a8b6e336b70068f045c666f2e7f4f9cc5f47db8972"
            )
        );
        assert_eq!(
            harness.service.usable_profile().await.unwrap(),
            Some(imported.clone())
        );

        harness
            .secrets
            .remove_without_contract(imported.accounts()[0].secret_ref());
        assert_eq!(harness.service.usable_profile().await.unwrap(), None);
    });
}

#[test]
fn unavailable_security_never_persists_creation_or_import_side_effects() {
    block_on(async {
        for (availability, code) in [
            (
                VaultAvailability::NoStrongUserAuthentication,
                ContractErrorCode::AuthenticationRequired,
            ),
            (
                VaultAvailability::Unsupported,
                ContractErrorCode::Unsupported,
            ),
            (
                VaultAvailability::Unavailable,
                ContractErrorCode::Unavailable,
            ),
        ] {
            let harness = Harness::new();
            *harness.vault.availability.lock().unwrap() = availability;
            assert_contract_code(
                harness
                    .service
                    .prepare_create(WalletWordCount::Words12, Zeroizing::new(String::new()))
                    .await
                    .unwrap_err(),
                code,
            );
            assert_contract_code(
                harness
                    .service
                    .import(&known_mnemonic(), "")
                    .await
                    .unwrap_err(),
                code,
            );
            assert_eq!(harness.profiles.snapshot(), WalletState::empty());
            assert_eq!(harness.profiles.cas_calls.load(Ordering::SeqCst), 0);
            assert_eq!(harness.secrets.envelope_count(), 0);
            assert!(harness.vault.wallet_keys.lock().unwrap().is_empty());
        }
    });
}

#[test]
fn public_profile_and_rename_need_no_unlock_and_invalid_names_never_commit() {
    block_on(async {
        let harness = Harness::new();
        assert!(harness.service.profile().await.unwrap().is_none());
        assert!(harness.service.usable_profile().await.unwrap().is_none());
        let profile = harness.service.import(&known_mnemonic(), "").await.unwrap();
        *harness.vault.availability.lock().unwrap() = VaultAvailability::Unavailable;
        assert_eq!(
            harness.service.profile().await.unwrap(),
            Some(profile.clone())
        );
        let renamed = harness
            .service
            .rename_account(profile.master_account_id(), " 本地名称 ")
            .await
            .unwrap();
        assert_eq!(renamed.accounts()[0].name(), "本地名称");
        let before = harness.profiles.snapshot();
        for name in ["", "   ", &"a".repeat(257)] {
            assert!(harness
                .service
                .rename_account(profile.master_account_id(), name)
                .await
                .is_err());
        }
        let unknown = AccountId32::from_bytes([0xf1; 32]);
        assert!(harness
            .service
            .rename_account(unknown, "未知")
            .await
            .is_err());
        assert!(harness.service.set_active_account(unknown).await.is_err());
        assert!(harness
            .signing_service()
            .sign(unknown, vec![])
            .await
            .is_err());
        assert_eq!(harness.profiles.snapshot(), before);
        assert_eq!(harness.secrets.envelope_count(), 1);
        assert_eq!(harness.vault.delete_wallet_calls.load(Ordering::SeqCst), 0);
    });
}

#[test]
fn missing_key_or_any_existing_child_blocks_append_before_new_facts() {
    block_on(async {
        for missing_key in [false, true] {
            let harness = Harness::new();
            let mnemonic = known_mnemonic();
            let profile = harness.service.import(&mnemonic, "").await.unwrap();
            let child = harness
                .service
                .add_accounts(&mnemonic, "", &[1])
                .await
                .unwrap();
            if missing_key {
                harness
                    .vault
                    .wallet_keys
                    .lock()
                    .unwrap()
                    .remove(&(profile.wallet_index(), profile.generation()));
            } else {
                harness
                    .secrets
                    .remove_without_contract(child[0].secret_ref());
            }
            let before = harness.profiles.snapshot();
            let count = harness.secrets.envelope_count();
            assert!(harness.service.usable_profile().await.unwrap().is_none());
            assert!(harness
                .service
                .add_accounts(&mnemonic, "", &[2])
                .await
                .is_err());
            assert_eq!(harness.profiles.snapshot(), before);
            assert_eq!(harness.secrets.envelope_count(), count);
        }
    });
}

#[test]
fn mismatched_child_ciphertext_is_not_usable_and_cannot_sign() {
    block_on(async {
        let harness = Harness::new();
        let profile = harness.service.import(&known_mnemonic(), "").await.unwrap();
        harness
            .secrets
            .insert_envelope(profile.accounts()[0].secret_ref());
        let before = harness.profiles.snapshot();
        assert!(harness.service.usable_profile().await.unwrap().is_none());
        assert_contract_code(
            harness
                .signing_service()
                .sign(profile.master_account_id(), b"public test message".to_vec())
                .await
                .unwrap_err(),
            ContractErrorCode::Integrity,
        );
        assert_eq!(harness.profiles.snapshot(), before);
    });
}

#[test]
fn independent_signing_rechecks_device_security_before_opening_a_secret() {
    block_on(async {
        let harness = Harness::new();
        let profile = harness.service.import(&known_mnemonic(), "").await.unwrap();
        for (availability, code) in [
            (
                VaultAvailability::NoStrongUserAuthentication,
                ContractErrorCode::AuthenticationRequired,
            ),
            (
                VaultAvailability::Unsupported,
                ContractErrorCode::Unsupported,
            ),
            (
                VaultAvailability::Unavailable,
                ContractErrorCode::Unavailable,
            ),
        ] {
            *harness.vault.availability.lock().unwrap() = availability;
            let before = harness.profiles.snapshot();
            assert_contract_code(
                harness
                    .signing_service()
                    .sign(profile.master_account_id(), Vec::new())
                    .await
                    .expect_err("设备保护不可用时独立签名必须拒绝"),
                code,
            );
            assert_eq!(harness.profiles.snapshot(), before);
        }
    });
}

#[test]
fn create_converges_when_profile_and_ciphertext_cas_throw_after_writing() {
    block_on(async {
        let harness = Harness::new();
        harness.profiles.fail_next_after_write();
        harness.secrets.fail_next_after_write();

        let prepared = harness
            .service
            .prepare_create(WalletWordCount::Words12, Zeroizing::new(String::new()))
            .await
            .expect("准备创建");
        let profile = harness
            .service
            .commit_create_after_backup(prepared)
            .await
            .expect("写后抛错必须通过完整回读收敛");
        assert_eq!(
            harness.service.profile().await.unwrap(),
            Some(profile.clone())
        );
        assert_eq!(
            harness.service.usable_profile().await.unwrap(),
            Some(profile)
        );
        assert_eq!(harness.secrets.envelope_count(), 1);
    });
}

#[test]
fn incomplete_create_never_exposes_the_uncommitted_target_profile() {
    block_on(async {
        let harness = Harness::new();
        let (profile, _mnemonic) =
            create_confirmed(&harness.service, WalletWordCount::Words12, "").await;
        let plan = WalletProvisioningPlan::try_new(
            [0x77; 16],
            profile.wallet_index(),
            profile.generation(),
            None,
            profile
                .accounts()
                .iter()
                .map(|account| account.secret_ref())
                .collect(),
            true,
        )
        .unwrap();
        let current = harness.profiles.snapshot();
        *harness.profiles.state.lock().unwrap() = WalletState::try_from_parts(
            current.revision() + 1,
            Some(profile.clone()),
            Some(plan),
            None,
            Vec::new(),
        )
        .unwrap();

        assert_eq!(harness.service.profile().await.unwrap(), None);
        assert_eq!(harness.service.usable_profile().await.unwrap(), None);
        assert_contract_code(
            harness
                .signing_service()
                .sign(profile.master_account_id(), b"must stay hidden".to_vec())
                .await
                .expect_err("未完成 create 的目标 profile 不得进入签名路径"),
            ContractErrorCode::NotFound,
        );
    });
}

#[test]
fn failed_create_recovers_orphan_ciphertext_and_owned_wallet_key() {
    block_on(async {
        let harness = Harness::new();
        // 第一次 CAS 取得 provisioning 所有权；第二次 CAS 本应清除 provisioning。
        // 在第二次写入前失败，验证已经写下的密文与本操作 generation 均被补偿清理。
        harness.profiles.fail_before_exact_call(2);
        let prepared = harness
            .service
            .prepare_create(WalletWordCount::Words12, Zeroizing::new(String::new()))
            .await
            .expect("准备创建");
        assert_contract_code(
            harness
                .service
                .commit_create_after_backup(prepared)
                .await
                .expect_err("完成事实写入失败应返回原错误"),
            ContractErrorCode::Storage,
        );

        let recovered = harness.profiles.snapshot();
        assert!(recovered.profile().is_none());
        assert!(recovered.provisioning().is_none());
        assert!(recovered.cleanup().is_none());
        assert!(recovered.cleanup_queue().is_empty());
        assert_eq!(harness.secrets.envelope_count(), 0);
        assert_eq!(harness.vault.wallet_keys.lock().unwrap().len(), 0);
        assert_eq!(harness.vault.delete_wallet_calls.load(Ordering::SeqCst), 1);
    });
}

#[test]
fn concurrent_instances_loser_never_deletes_the_winner_wallet() {
    block_on(async {
        let harness = Harness::new();
        let other = harness.second_service();
        let import_mnemonic = known_mnemonic();
        let prepared = harness
            .service
            .prepare_create(WalletWordCount::Words12, Zeroizing::new(String::new()))
            .await
            .expect("准备创建");
        let (create_result, import_result) = join!(
            harness.service.commit_create_after_backup(prepared),
            other.import(&import_mnemonic, ""),
        );

        let winner = create_result.expect("先取得全局操作所有权的 create 应成功");
        assert_contract_code(
            import_result.expect_err("另一个实例不得覆盖已成功钱包"),
            ContractErrorCode::InvalidState,
        );
        assert_eq!(
            harness.service.usable_profile().await.unwrap(),
            Some(winner.clone())
        );
        assert_eq!(harness.vault.delete_wallet_calls.load(Ordering::SeqCst), 0);
        assert!(harness
            .vault
            .has_key(winner.wallet_index(), winner.generation()));
        assert_eq!(harness.secrets.envelope_count(), 1);
    });
}

#[test]
fn prepared_creation_is_storage_free_until_backup_confirmation() {
    block_on(async {
        let harness = Harness::new();
        let prepared = harness
            .service
            .prepare_create(
                WalletWordCount::Words12,
                Zeroizing::new("Aa1!待清零".to_owned()),
            )
            .await
            .expect("准备一次性创建会话");
        assert!(!prepared.with_mnemonic(|words| words.is_empty()));
        assert_eq!(harness.profiles.snapshot(), WalletState::empty());
        assert_eq!(harness.secrets.envelope_count(), 0);
        assert!(harness.vault.wallet_keys.lock().unwrap().is_empty());

        drop(prepared);
        assert_eq!(harness.profiles.snapshot(), WalletState::empty());
        assert_eq!(harness.secrets.envelope_count(), 0);
        assert!(harness.vault.wallet_keys.lock().unwrap().is_empty());

        let (profile, _backup) =
            create_confirmed(&harness.service, WalletWordCount::Words12, "").await;
        assert_eq!(
            harness.service.usable_profile().await.unwrap(),
            Some(profile)
        );
    });
}

#[test]
fn add_accounts_write_after_errors_preserve_active_and_every_added_account() {
    block_on(async {
        let harness = Harness::new();
        let mnemonic = known_mnemonic();
        let profile = harness.service.import(&mnemonic, "").await.unwrap();
        let first = harness
            .service
            .add_accounts(&mnemonic, "", &[1])
            .await
            .unwrap()
            .remove(0);
        harness
            .service
            .set_active_account(first.account_id())
            .await
            .unwrap();

        harness.profiles.fail_next_after_write();
        harness.secrets.fail_next_after_write();
        let added = harness
            .service
            .add_accounts(&mnemonic, "", &[3, 2])
            .await
            .expect("profile/首个密文写后异常均应收敛");
        assert_eq!(
            added
                .iter()
                .map(|account| account.index())
                .collect::<Vec<_>>(),
            vec![2, 3]
        );

        let current = harness.service.profile().await.unwrap().unwrap();
        assert_eq!(current.master_account_id(), profile.master_account_id());
        assert_eq!(current.active_account_id(), first.account_id());
        assert_eq!(
            current
                .accounts()
                .iter()
                .map(|account| account.index())
                .collect::<Vec<_>>(),
            vec![0, 1, 2, 3]
        );
        assert!(current
            .accounts()
            .iter()
            .all(|account| harness.secrets.has_envelope(account.secret_ref())));
        assert_eq!(
            harness.service.usable_profile().await.unwrap(),
            Some(current)
        );
    });
}

#[test]
fn child_anchor_and_whole_wallet_deletion_honor_exact_ownership() {
    block_on(async {
        let harness = Harness::new();
        let mnemonic = known_mnemonic();
        let base = harness.service.import(&mnemonic, "").await.unwrap();
        let added = harness
            .service
            .add_accounts(&mnemonic, "", &[1, 2])
            .await
            .unwrap();
        let child_one = added[0].clone();
        let child_two = added[1].clone();
        harness
            .service
            .set_active_account(child_one.account_id())
            .await
            .unwrap();

        harness
            .service
            .delete_account(child_one.account_id())
            .await
            .expect("删除 active 子账户");
        let after_child = harness.service.profile().await.unwrap().unwrap();
        assert_eq!(after_child.active_account_id(), base.master_account_id());
        assert!(after_child.account_by_id(child_one.account_id()).is_none());
        assert!(!harness.secrets.has_envelope(child_one.secret_ref()));
        assert!(harness
            .vault
            .has_key(base.wallet_index(), base.generation()));

        assert_contract_code(
            harness
                .service
                .delete_account(base.master_account_id())
                .await
                .expect_err("仍有子账户时锚点不得单独删除"),
            ContractErrorCode::InvalidState,
        );
        harness
            .service
            .delete_account(child_two.account_id())
            .await
            .unwrap();
        harness
            .service
            .delete_account(base.master_account_id())
            .await
            .expect("只剩锚点时该入口等价整钱包删除");
        assert!(harness.service.profile().await.unwrap().is_none());
        assert_eq!(harness.secrets.envelope_count(), 0);
        assert!(!harness
            .vault
            .has_key(base.wallet_index(), base.generation()));

        // 同一设备可建立新生命周期，显式 delete_wallet 也必须清除全部物理目标。
        let replacement = harness.service.import(&mnemonic, "").await.unwrap();
        harness.service.delete_wallet().await.unwrap();
        assert!(harness.service.profile().await.unwrap().is_none());
        assert_eq!(harness.secrets.envelope_count(), 0);
        assert!(!harness
            .vault
            .has_key(replacement.wallet_index(), replacement.generation()));
    });
}

#[test]
fn deleted_generation_and_secret_ref_reject_every_late_writer() {
    block_on(async {
        let harness = Harness::new();
        let profile = harness
            .service
            .import(&known_mnemonic(), "")
            .await
            .expect("建立待删除钱包");
        let secret_ref = profile.accounts()[0].secret_ref();

        harness.service.delete_wallet().await.expect("删除钱包");
        let tombstone = harness.secrets.load(secret_ref).await.unwrap();
        assert!(tombstone.is_tombstone());

        let vault_error = harness
            .vault
            .seal(
                [0xE1; 16],
                secret_ref,
                SecretBuffer::try_new(vec![0xA5; 32]).unwrap(),
            )
            .await
            .expect_err("退休 generation 不得由迟到 seal 复活硬件密钥");
        assert_eq!(vault_error.code(), ContractErrorCode::KeyInvalidated);

        let blob_error = harness
            .secrets
            .compare_and_swap(
                secret_ref,
                tombstone.revision(),
                EncryptedSecretBlobState::Sealed {
                    provisioning_operation_id: [0xE1; 16],
                    envelope: test_envelope(secret_ref),
                },
            )
            .await
            .expect_err("永久墓碑不得由迟到密文写入覆盖");
        assert_eq!(blob_error.code(), ContractErrorCode::Conflict);
        assert!(harness
            .secrets
            .load(secret_ref)
            .await
            .unwrap()
            .is_tombstone());
    });
}

#[test]
fn reconcile_drains_queued_cleanup_before_the_active_cleanup() {
    block_on(async {
        let harness = Harness::new();
        let active_generation = VaultGeneration::from_bytes([0x11; 16]);
        let queued_generation = VaultGeneration::from_bytes([0x22; 16]);
        let active_ref = SecretRef::account_mini_secret(
            0,
            active_generation,
            SecretOwner::from_bytes([0x31; 16]),
            AccountId32::from_bytes([0x41; 32]),
        );
        let queued_ref = SecretRef::account_mini_secret(
            0,
            queued_generation,
            SecretOwner::from_bytes([0x32; 16]),
            AccountId32::from_bytes([0x42; 32]),
        );
        let active =
            WalletCleanupPlan::try_new([0x51; 16], 0, active_generation, vec![active_ref], true)
                .unwrap();
        let queued =
            WalletCleanupPlan::try_new([0x52; 16], 0, queued_generation, vec![queued_ref], true)
                .unwrap();
        harness.secrets.insert_envelope(active_ref);
        harness.secrets.insert_envelope(queued_ref);
        harness
            .vault
            .wallet_keys
            .lock()
            .unwrap()
            .extend([(0, active_generation), (0, queued_generation)]);
        *harness.profiles.state.lock().unwrap() =
            WalletState::try_from_parts(1, None, None, Some(active), vec![queued]).unwrap();

        harness.service.reconcile_cleanup().await.unwrap();
        assert_eq!(
            *harness.secrets.deletion_order.lock().unwrap(),
            vec![queued_ref, active_ref]
        );
        let state = harness.profiles.snapshot();
        assert!(state.cleanup().is_none());
        assert!(state.cleanup_queue().is_empty());
        assert_eq!(harness.secrets.envelope_count(), 0);
        assert!(harness.vault.wallet_keys.lock().unwrap().is_empty());
    });
}

fn known_mnemonic() -> SecretBuffer {
    SecretBuffer::try_new(KNOWN_MNEMONIC.as_bytes().to_vec()).unwrap()
}

async fn create_confirmed(
    service: &WalletService,
    word_count: WalletWordCount,
    password: &str,
) -> (citizen_sdk_contracts::WalletProfile, SecretBuffer) {
    let prepared = service
        .prepare_create(word_count, Zeroizing::new(password.to_owned()))
        .await
        .expect("准备创建钱包");
    // 测试副本模拟用户已完成的离线备份；生产绑定必须用受控一次性展示句柄。
    let backup = prepared.with_mnemonic(|words| SecretBuffer::try_new(words.to_vec()).unwrap());
    let profile = service
        .commit_create_after_backup(prepared)
        .await
        .expect("确认备份后提交钱包");
    (profile, backup)
}

fn assert_contract_code(error: EngineError, expected: ContractErrorCode) {
    match error {
        EngineError::Contract(contract) => assert_eq!(contract.code(), expected),
        other => panic!("期望 typed contract error，实际为 {other:?}"),
    }
}

fn storage_error(message: &str) -> ContractError {
    ContractError::new(ContractErrorCode::Storage, message)
}

fn conflict_error(message: &str) -> ContractError {
    ContractError::new(ContractErrorCode::Conflict, message)
}

fn secret_ref_digest(secret_ref: SecretRef) -> [u8; 32] {
    let mut digest = [0_u8; 32];
    digest[..16].copy_from_slice(secret_ref.generation().as_bytes());
    digest[16..].copy_from_slice(secret_ref.owner().as_bytes());
    for (target, account) in digest.iter_mut().zip(secret_ref.account_id().as_bytes()) {
        *target ^= account;
    }
    digest[0] ^= secret_ref.wallet_index() as u8;
    digest
}

fn test_envelope(secret_ref: SecretRef) -> EncryptedSecretEnvelope {
    EncryptedSecretEnvelope::try_new(
        1,
        Hash32Bytes::from_bytes(secret_ref_digest(secret_ref)),
        vec![0xAA; 32],
    )
    .unwrap()
}

fn decode_fixed_hex<const N: usize>(encoded: &str) -> [u8; N] {
    assert_eq!(encoded.len(), N * 2);
    let mut output = [0_u8; N];
    for (index, byte) in output.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&encoded[index * 2..index * 2 + 2], 16).unwrap();
    }
    output
}

#[cfg(feature = "wallet")]
#[test]
fn private_key_view_requires_confirmation_and_holds_wallet_until_ui_and_notification_finish() {
    use citizen_sdk_contracts::Modules;
    block_on(async {
        let harness = Harness::new();
        harness.entropy.0.store(160, Ordering::SeqCst);
        let mnemonic = SecretBuffer::try_new(KNOWN_MNEMONIC.as_bytes().to_vec()).unwrap();
        let profile = harness.service.import(&mnemonic, "").await.unwrap();
        let engine = harness.engine(Modules::try_new(Modules::WALLET).unwrap());
        let view = engine
            .internal_private_key_view(profile.master_account_id(), None)
            .unwrap();
        let before_auth = harness.vault.open_calls.load(Ordering::SeqCst);
        assert!(view.reserve_work().unwrap());
        view.run_work(|_| panic!("准备阶段不得调用显示"))
            .await
            .unwrap();
        view.release_work().unwrap();
        assert_eq!(harness.vault.open_calls.load(Ordering::SeqCst), before_auth);
        assert!(view.take_notification().unwrap().is_none());
        assert!(view.take_completion().unwrap().is_none());
        assert!(engine.dispose().is_err());
        assert!(harness.second_service().delete_wallet().await.is_err());
        assert!(harness
            .service
            .rename_account(profile.master_account_id(), "禁止变更")
            .await
            .is_err());
        let revision = harness.profiles.snapshot().revision();
        view.confirm().unwrap();
        assert!(view.confirm().is_err(), "用户确认只允许一次");
        assert!(view.reserve_work().unwrap());
        let displayed = AtomicUsize::new(0);
        view.run_work(|bytes| {
            assert_eq!(bytes.len(), 32);
            displayed.fetch_add(1, Ordering::SeqCst);
            Ok(())
        })
        .await
        .unwrap();
        view.release_work().unwrap();
        assert_eq!(displayed.load(Ordering::SeqCst), 1);
        assert_eq!(
            harness.profiles.snapshot().revision(),
            revision,
            "查看不持久写入"
        );
        assert_eq!(view.take_notification().unwrap(), Some(Ok(())));
        view.finish().unwrap();
        assert!(
            view.take_completion().unwrap().is_none(),
            "settled 自身仍未返回"
        );
        view.finish_notification().unwrap();
        assert_eq!(view.take_completion().unwrap(), Some(Ok(())));
        assert!(view.take_completion().unwrap().is_none());
        assert!(view.take_notification().unwrap().is_none());
        assert!(!view.reserve_work().unwrap());
        harness.service.delete_wallet().await.unwrap();
        engine.dispose().unwrap();
    });
}

#[cfg(feature = "wallet")]
#[test]
fn private_key_view_cancel_and_finish_do_not_drop_pending_authentication_or_allow_late_display() {
    use citizen_sdk_contracts::Modules;
    block_on(async {
        let harness = Harness::new();
        harness.entropy.0.store(176, Ordering::SeqCst);
        let mnemonic = SecretBuffer::try_new(KNOWN_MNEMONIC.as_bytes().to_vec()).unwrap();
        let profile = harness.service.import(&mnemonic, "").await.unwrap();
        let engine = harness.engine(Modules::try_new(Modules::WALLET).unwrap());
        let view = engine
            .internal_private_key_view(profile.master_account_id(), None)
            .unwrap();
        view.confirm().unwrap(); // open 准备尚未完成时原生确认可以先排队。
        assert!(view.reserve_work().unwrap());
        let (release, gate) = futures::channel::oneshot::channel();
        *harness.vault.open_gate.lock().unwrap() = Some(gate);
        let before_completed = harness.vault.open_completed.load(Ordering::SeqCst);
        let (entered, entered_rx) = futures::channel::oneshot::channel();
        *harness.vault.open_entered.lock().unwrap() = Some(entered);
        let displayed = AtomicUsize::new(0);
        let work = Box::pin(view.run_work(|_| {
            displayed.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }));
        let work = match futures::future::select(work, entered_rx).await {
            futures::future::Either::Right((Ok(()), work)) => work,
            _ => panic!("必须先真实进入授权等待"),
        };
        view.cancel().unwrap();
        assert_eq!(
            view.take_notification().unwrap(),
            Some(Err(EngineError::Cancelled))
        );
        view.finish().unwrap();
        view.finish_notification().unwrap();
        assert!(
            view.take_completion().unwrap().is_none(),
            "取消不能丢弃实际授权 future"
        );
        assert_eq!(
            harness.vault.open_completed.load(Ordering::SeqCst),
            before_completed
        );
        assert!(harness.service.delete_wallet().await.is_err());
        assert!(engine.dispose().is_err());
        release.send(()).unwrap();
        work.await.unwrap();
        view.release_work().unwrap();
        assert_eq!(displayed.load(Ordering::SeqCst), 0);
        assert_eq!(
            harness.vault.open_completed.load(Ordering::SeqCst),
            before_completed + 1
        );
        assert_eq!(
            view.take_completion().unwrap(),
            Some(Err(EngineError::Cancelled))
        );
        assert!(view.take_notification().unwrap().is_none());
        harness.service.delete_wallet().await.unwrap();
        engine.dispose().unwrap();
    });
}

#[cfg(feature = "wallet")]
#[test]
fn private_key_view_cancel_before_work_never_loads_a_secret_and_missing_account_settles_once() {
    use citizen_sdk_contracts::Modules;
    block_on(async {
        let harness = Harness::new();
        let engine = harness.engine(Modules::try_new(Modules::WALLET).unwrap());
        let missing = AccountId32::from_bytes([0; 32]);
        let view = engine.internal_private_key_view(missing, None).unwrap();
        view.cancel().unwrap();
        assert!(!view.reserve_work().unwrap());
        assert_eq!(
            view.take_notification().unwrap(),
            Some(Err(EngineError::Cancelled))
        );
        view.finish_notification().unwrap();
        view.finish().unwrap();
        assert_eq!(
            view.take_completion().unwrap(),
            Some(Err(EngineError::Cancelled))
        );
        let view = engine.internal_private_key_view(missing, None).unwrap();
        assert!(view.reserve_work().unwrap());
        let failure = view
            .run_work(|_| panic!("缺账户不得显示"))
            .await
            .unwrap_err();
        view.fail(failure).unwrap();
        let error = view.take_notification().unwrap().unwrap().unwrap_err();
        assert_contract_code(error, ContractErrorCode::NotFound);
        view.release_work().unwrap();
        view.finish().unwrap();
        assert!(view.take_completion().unwrap().is_none());
        view.finish_notification().unwrap();
        assert!(view.take_completion().unwrap().unwrap().is_err());
        assert_eq!(harness.vault.open_calls.load(Ordering::SeqCst), 0);
        assert_eq!(harness.profiles.cas_calls.load(Ordering::SeqCst), 0);
        assert!(harness
            .engine(Modules::try_new(Modules::SIGNING).unwrap())
            .internal_private_key_view(missing, None)
            .is_err());
    });
}

#[cfg(feature = "wallet")]
#[test]
fn private_key_view_rechecks_generation_after_pending_authorization() {
    use citizen_sdk_contracts::Modules;
    block_on(async {
        let harness = Harness::new();
        harness.entropy.0.store(192, Ordering::SeqCst);
        let replacement = Harness::new();
        replacement.entropy.0.store(208, Ordering::SeqCst);
        let mnemonic = SecretBuffer::try_new(KNOWN_MNEMONIC.as_bytes().to_vec()).unwrap();
        let profile = harness.service.import(&mnemonic, "").await.unwrap();
        replacement.service.import(&mnemonic, "").await.unwrap();
        let engine = harness.engine(Modules::try_new(Modules::WALLET).unwrap());
        let view = engine
            .internal_private_key_view(profile.master_account_id(), None)
            .unwrap();
        view.confirm().unwrap();
        assert!(view.reserve_work().unwrap());
        let (release, gate) = futures::channel::oneshot::channel();
        *harness.vault.open_gate.lock().unwrap() = Some(gate);
        let (entered, entered_rx) = futures::channel::oneshot::channel();
        *harness.vault.open_entered.lock().unwrap() = Some(entered);
        let work = Box::pin(view.run_work(|_| panic!("换代账户不得显示")));
        // Pending 也可能是钱包门竞争；必须等明确的 vault.open 进入信号后才能模拟换代。
        let work = match futures::future::select(work, entered_rx).await {
            futures::future::Either::Right((Ok(()), work)) => work,
            _ => panic!("必须先真实进入授权等待"),
        };
        // 模拟外部持久层被置换，不绕过 SDK 变更门制造成功路径。
        *harness.profiles.state.lock().unwrap() = replacement.profiles.snapshot();
        release.send(()).unwrap();
        work.await.unwrap();
        view.release_work().unwrap();
        let failure = view.take_notification().unwrap().unwrap().unwrap_err();
        assert_contract_code(failure, ContractErrorCode::Conflict);
        view.finish_notification().unwrap();
        view.finish().unwrap();
        assert!(view.take_completion().unwrap().unwrap().is_err());
        engine.dispose().unwrap();
    });
}

#[cfg(feature = "wallet")]
#[test]
fn private_key_view_rejects_missing_ciphertext_invalidated_key_and_wrong_account_public_key() {
    use citizen_sdk_contracts::Modules;
    block_on(async {
        let harness = Harness::new();
        harness.entropy.0.store(224, Ordering::SeqCst);
        let mnemonic = SecretBuffer::try_new(KNOWN_MNEMONIC.as_bytes().to_vec()).unwrap();
        let profile = harness.service.import(&mnemonic, "").await.unwrap();
        let child = harness
            .service
            .add_accounts(&mnemonic, "", &[1])
            .await
            .unwrap()
            .remove(0);
        let master = profile.account_by_id(profile.master_account_id()).unwrap();
        let master_ref = master.secret_ref();
        let original = harness.secrets.entries.lock().unwrap()[&master_ref].clone();
        let child_envelope = harness.secrets.entries.lock().unwrap()[&child.secret_ref()]
            .envelope()
            .cloned()
            .unwrap();
        let engine = harness.engine(Modules::try_new(Modules::WALLET).unwrap());
        for expected in [
            ContractErrorCode::AuthenticationRequired,
            ContractErrorCode::KeyInvalidated,
            ContractErrorCode::Integrity,
        ] {
            harness
                .secrets
                .entries
                .lock()
                .unwrap()
                .insert(master_ref, original.clone());
            harness
                .vault
                .wallet_keys
                .lock()
                .unwrap()
                .insert((master_ref.wallet_index(), master_ref.generation()));
            match expected {
                ContractErrorCode::AuthenticationRequired => {
                    harness.secrets.remove_without_contract(master_ref)
                }
                ContractErrorCode::KeyInvalidated => {
                    harness.vault.wallet_keys.lock().unwrap().clear();
                }
                ContractErrorCode::Integrity => {
                    // 仅复用已有公开向量派生的另一个 child；不输出或断言秘密内容。
                    let envelope = EncryptedSecretEnvelope::try_new(
                        1,
                        Hash32Bytes::from_bytes(secret_ref_digest(master_ref)),
                        child_envelope.ciphertext().to_vec(),
                    )
                    .unwrap();
                    let swapped = EncryptedSecretBlobSnapshot::empty()
                        .try_advance(EncryptedSecretBlobState::Sealed {
                            provisioning_operation_id: [0x61; 16],
                            envelope,
                        })
                        .unwrap();
                    harness
                        .secrets
                        .entries
                        .lock()
                        .unwrap()
                        .insert(master_ref, swapped);
                }
                _ => unreachable!(),
            }
            let view = engine
                .internal_private_key_view(master.account_id(), None)
                .unwrap();
            view.confirm().unwrap();
            assert!(view.reserve_work().unwrap());
            view.run_work(|_| panic!("无效设备秘密不得进入显示"))
                .await
                .unwrap();
            view.release_work().unwrap();
            assert_contract_code(
                view.take_notification().unwrap().unwrap().unwrap_err(),
                expected,
            );
            view.finish_notification().unwrap();
            view.finish().unwrap();
            assert!(view.take_completion().unwrap().unwrap().is_err());
        }
        engine.dispose().unwrap();
    });
}

#[cfg(all(feature = "wallet", feature = "signing"))]
#[test]
fn wallet_and_signing_modules_are_independent_without_a_chain_or_history() {
    use citizen_sdk_contracts::{CapabilityName, Modules, Sr25519PublicKey};
    block_on(async {
        let harness = Harness::new();
        let wallet = harness.engine(Modules::try_new(Modules::WALLET).unwrap());
        let prepared = wallet
            .prepare_wallet_creation(WalletWordCount::Words12, Zeroizing::new(String::new()))
            .await
            .expect("钱包独立创建不需要公开签名模块");
        let profile = wallet
            .commit_wallet_creation_after_backup(prepared)
            .await
            .expect("钱包独立备份提交");
        assert!(wallet.begin_provider_start().is_err(), "不能伪造轻节点启动");
        assert!(wallet.start_chain_monitor().await.is_err());
        let account_id = profile.master_account_id();
        assert!(wallet
            .sign_wallet_payload(account_id, b"module boundary".to_vec())
            .await
            .is_err());
        assert!(wallet
            .capabilities()
            .unwrap()
            .unwrap()
            .status(CapabilityName::WalletProfile)
            .unwrap()
            .is_ready());
        assert!(!wallet
            .capabilities()
            .unwrap()
            .unwrap()
            .status(CapabilityName::LocalSigning)
            .unwrap()
            .enabled());

        let signing = harness.engine(Modules::try_new(Modules::SIGNING).unwrap());
        assert!(
            signing.wallet_profile().await.is_err(),
            "签名不开放钱包管理"
        );
        assert!(
            signing
                .capabilities()
                .unwrap()
                .unwrap()
                .status(CapabilityName::LocalSigning)
                .unwrap()
                .is_ready(),
            "钱包管理关闭不应关闭独立签名"
        );
        let message = b"module boundary".to_vec();
        let signature = signing
            .sign_wallet_payload(account_id, message.clone())
            .await
            .expect("签名模块读取已有安全账户");
        assert!(harness
            .signer
            .verify(
                Sr25519PublicKey::from_bytes(*account_id.as_bytes()),
                message,
                signature,
            )
            .await
            .unwrap());
        let before = harness.profiles.snapshot();
        assert!(
            signing
                .sign_wallet_payload(AccountId32::from_bytes([0x98; 32]), Vec::new(),)
                .await
                .is_err(),
            "独立签名不得伪造账户归属"
        );
        assert_eq!(harness.profiles.snapshot(), before);

        wallet
            .delete_wallet()
            .await
            .expect("本地删除不需要历史监控");
        assert!(signing
            .sign_wallet_payload(account_id, Vec::new())
            .await
            .is_err());
        signing.dispose().unwrap();
        assert!(
            !signing
                .capabilities()
                .unwrap()
                .unwrap()
                .status(CapabilityName::LocalSigning)
                .unwrap()
                .is_ready(),
            "关闭后本地签名也必须失效"
        );
    });
}
