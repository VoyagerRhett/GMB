package com.crcfrcn.citizenapp

// P-256 设备子钥原生桥（后台握手用）。
//
// Keystore EC P-256（secp256r1）密钥，`PURPOSE_SIGN`、**无 user-auth** → 静默硬件
// ECDSA 签名，私钥永不出硬件（passkey 式）。这是「会话/设备子钥」，非花钱主钥，
// 故不加生物门禁：它只向后端证明「本设备代表此 CID」，替代原先静默读 sr25519 seed
// 签登录挑战。绑定归属由 sr25519 主钥一次性签名 + 后端注册保证（见 worker
// /auth/device/register）。
//
// 契约：publicKey 返回裸未压缩点 65B（0x04||X||Y）hex；sign 返回平台 DER 签名 hex，
// 由 Dart 侧转成裸 r||s 64B 再上送（后端 Web Crypto ES256 只认 raw）。

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec

class DeviceSubkeyBridge {
    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val CURVE = "secp256r1"
        private const val SIGN_ALG = "SHA256withECDSA"
        private const val COORD_BYTES = 32

        private fun aliasFor(cidNumber: String): String {
            require(cidNumber.toByteArray(Charsets.UTF_8).size in 1..32) {
                "cidNumber UTF-8 长度必须为 1-32 字节"
            }
            val encoded = android.util.Base64.encodeToString(
                cidNumber.toByteArray(Charsets.UTF_8),
                android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING,
            )
            return "citizen_device_subkey_cid_$encoded"
        }

    }

    private fun keyStore() = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun ensureKey(cidNumber: String) {
        val ks = keyStore()
        val alias = aliasFor(cidNumber)
        if (ks.containsAlias(alias)) return
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec(CURVE))
            .setDigests(KeyProperties.DIGEST_SHA256)
            // 无 setUserAuthenticationRequired → 静默硬件签名（会话子钥）。
            .build()
        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE)
        kpg.initialize(spec)
        kpg.generateKeyPair()
    }

    /// 裸未压缩点 65B（0x04 || X(32) || Y(32)）hex。
    fun publicKeyHex(cidNumber: String): String {
        ensureKey(cidNumber)
        val cert = keyStore().getCertificate(aliasFor(cidNumber))
        val pub = cert.publicKey as ECPublicKey
        val x = pub.w.affineX.toFixedBytes(COORD_BYTES)
        val y = pub.w.affineY.toFixedBytes(COORD_BYTES)
        val out = ByteArray(1 + COORD_BYTES * 2)
        out[0] = 0x04
        System.arraycopy(x, 0, out, 1, COORD_BYTES)
        System.arraycopy(y, 0, out, 1 + COORD_BYTES, COORD_BYTES)
        return out.toHex()
    }

    /// 对 [payload] 做 SHA256withECDSA 硬件签名，返回平台 DER 签名 hex（Dart 转 raw）。
    fun signDerHex(cidNumber: String, payload: ByteArray): String {
        ensureKey(cidNumber)
        val priv = keyStore().getKey(aliasFor(cidNumber), null) as PrivateKey
        val signer = Signature.getInstance(SIGN_ALG)
        signer.initSign(priv)
        signer.update(payload)
        return signer.sign().toHex()
    }

    fun delete(cidNumber: String) {
        val ks = keyStore()
        val alias = aliasFor(cidNumber)
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
    }

    /// 只回读当前 CID 的硬件子钥是否仍存在，绝不创建新钥。
    fun contains(cidNumber: String): Boolean = keyStore().containsAlias(aliasFor(cidNumber))

    // 把 BigInteger 坐标定长右对齐成 [len] 字节（去掉可能的符号 0 前导 / 左补 0）。
    private fun BigInteger.toFixedBytes(len: Int): ByteArray {
        val raw = toByteArray()
        val out = ByteArray(len)
        val src = if (raw.size > len) raw.copyOfRange(raw.size - len, raw.size) else raw
        System.arraycopy(src, 0, out, len - src.size, src.size)
        return out
    }

    private fun ByteArray.toHex(): String {
        val chars = "0123456789abcdef"
        val sb = StringBuilder(size * 2)
        for (b in this) {
            val v = b.toInt() and 0xff
            sb.append(chars[v ushr 4]).append(chars[v and 0x0f])
        }
        return sb.toString()
    }
}
