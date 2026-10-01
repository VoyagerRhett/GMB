package com.crcfrcn.citizenapp

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// Chat、MLS、附件和通讯录用途钥的本机硬件封装边界。
///
/// 本钥与钱包严档 KEK、P-256 设备签名子钥物理分离；不设置用户认证要求，因此不会
/// 弹出 BiometricPrompt。设备未解锁、硬件钥失效或 AAD 不匹配时直接失败，绝不回退
/// 读取钱包账户 child mini-secret。
class DeviceDataKeyVaultBridge {
    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORM = "AES/GCM/NoPadding"
        private const val KEY_BITS = 256
        private const val TAG_BITS = 128
        private const val IV_BYTES = 12

        private fun aliasFor(walletIndex: Int) = "citizen_device_data_key_$walletIndex"
    }

    private fun keyStore() = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun ensureKey(walletIndex: Int): SecretKey {
        require(walletIndex >= 0) { "walletIndex 必须为非负整数" }
        val keyStore = keyStore()
        val alias = aliasFor(walletIndex)
        val existing = keyStore.getKey(alias, null)
        if (existing is SecretKey) return existing

        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(KEY_BITS)
            .setUserAuthenticationRequired(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // 锁屏尚未解开时禁止后台取得用途钥；失败后等待前台恢复，不弹生物识别。
            builder.setUnlockedDeviceRequired(true)
        }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(builder.build())
            generateKey()
        }
    }

    private fun requireKey(walletIndex: Int): SecretKey {
        require(walletIndex >= 0) { "walletIndex 必须为非负整数" }
        val existing = keyStore().getKey(aliasFor(walletIndex), null)
        return existing as? SecretKey
            ?: throw IllegalStateException("设备数据钥不存在或已失效")
    }

    fun seal(walletIndex: Int, plaintext: ByteArray, aad: ByteArray): String {
        require(plaintext.isNotEmpty() && aad.isNotEmpty()) { "plaintext/aad 不能为空" }
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, ensureKey(walletIndex))
        cipher.updateAAD(aad)
        val body = cipher.doFinal(plaintext)
        val iv = cipher.iv
        require(iv.size == IV_BYTES) { "AES-GCM IV 长度异常" }
        val envelope = ByteBuffer.allocate(iv.size + body.size)
            .put(iv)
            .put(body)
            .array()
        return Base64.encodeToString(envelope, Base64.NO_WRAP)
    }

    fun open(walletIndex: Int, blob: String, aad: ByteArray): ByteArray {
        require(blob.isNotBlank() && aad.isNotEmpty()) { "blob/aad 不能为空" }
        val envelope = Base64.decode(blob, Base64.NO_WRAP)
        require(envelope.size > IV_BYTES + TAG_BITS / 8) { "设备数据钥密文损坏" }
        val iv = envelope.copyOfRange(0, IV_BYTES)
        val body = envelope.copyOfRange(IV_BYTES, envelope.size)
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(
            Cipher.DECRYPT_MODE,
            // 日常静默解封只读既有设备钥；不存在时绝不暗中创建新钥或回退钱包 child。
            requireKey(walletIndex),
            GCMParameterSpec(TAG_BITS, iv),
        )
        cipher.updateAAD(aad)
        return cipher.doFinal(body)
    }

    fun delete(walletIndex: Int) {
        val keyStore = keyStore()
        val alias = aliasFor(walletIndex)
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
    }

    /// 只回读指定钱包的设备数据硬件钥是否仍存在，绝不创建新钥。
    fun contains(walletIndex: Int): Boolean {
        require(walletIndex >= 0) { "walletIndex 必须为非负整数" }
        return keyStore().containsAlias(aliasFor(walletIndex))
    }
}
