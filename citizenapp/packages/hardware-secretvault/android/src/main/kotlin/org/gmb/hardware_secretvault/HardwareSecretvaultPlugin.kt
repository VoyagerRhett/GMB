package org.gmb.hardware_secretvault

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

/**
 * 公民与公民钱包共用的 Android 硬件严档金库。
 *
 * RSA-OAEP KEK 必须实际位于 StrongBox 或 TEE，并设置每次使用强生物识别。写入使用公钥
 * 静默封装随机 AES-256-GCM DEK；读取必须由 BiometricPrompt.CryptoObject 原子授权私钥
 * 解包。AAD 由 Dart 统一构造并交给 AES-GCM，跨产品、钱包、账户或机密类型调换必然失败。
 */
class HardwareSecretvaultPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    companion object {
        private const val CHANNEL = "gmb/hardware_secretvault"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val RSA_TRANSFORM = "RSA/ECB/OAEPPadding"
        private const val AES_TRANSFORM = "AES/GCM/NoPadding"
        private const val KEY_ALIAS_PREFIX = "gmb_hardware_secretvault_"
        private const val BLOB_VERSION: Byte = 1
        private const val WRAPPED_KEY_BYTES = 256
        private const val AES_KEY_BYTES = 32
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BYTES = 16
    }

    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private var activity: FragmentActivity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity as? FragmentActivity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "securityStatus" -> result.success(securityStatus())
                "encrypt" -> {
                    val scope = requiredString(call, "scope")
                    val aad = requiredBytes(call, "associatedData")
                    val plaintext = requiredBytes(call, "plaintext")
                    try {
                        result.success(encrypt(scope, aad, plaintext))
                    } finally {
                        aad.fill(0)
                        plaintext.fill(0)
                    }
                }
                "decrypt" -> {
                    val scope = requiredString(call, "scope")
                    val aad = requiredBytes(call, "associatedData")
                    val ciphertext = requiredBytes(call, "ciphertext")
                    decrypt(scope, aad, ciphertext, result)
                }
                "deleteKey" -> {
                    deleteKey(requiredString(call, "scope"))
                    result.success(null)
                }
                "containsKey" -> result.success(containsKey(requiredString(call, "scope")))
                else -> result.notImplemented()
            }
        } catch (error: VaultFailure) {
            result.error(error.code, error.message, null)
        } catch (error: Exception) {
            result.error("vaultFailure", error.message, null)
        }
    }

    private fun securityStatus(): Map<String, Any> {
        val host = activity
        val strong = host != null && BiometricManager.from(host).canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_STRONG,
        ) == BiometricManager.BIOMETRIC_SUCCESS
        return mapOf(
            "supported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && host != null),
            "strongBiometricEnrolled" to strong,
        )
    }

    private fun encrypt(scope: String, aad: ByteArray, plaintext: ByteArray): ByteArray {
        if (aad.isEmpty() || plaintext.isEmpty()) throw VaultFailure("badArgs", "AAD/机密不能为空")
        val alias = aliasFor(scope)
        ensureHardwareKey(alias)
        val aesKey = ByteArray(AES_KEY_BYTES).also(SecureRandom()::nextBytes)
        val iv = ByteArray(GCM_IV_BYTES).also(SecureRandom()::nextBytes)
        try {
            val aes = Cipher.getInstance(AES_TRANSFORM)
            aes.init(Cipher.ENCRYPT_MODE, SecretKeySpec(aesKey, "AES"), GCMParameterSpec(128, iv))
            aes.updateAAD(aad)
            val body = aes.doFinal(plaintext)
            val keyStore = keyStore()
            val publicKey = keyStore.getCertificate(alias)?.publicKey
                ?: throw VaultFailure("keyPermanentlyInvalidated", "硬件密钥不存在")
            val unrestricted = KeyFactory.getInstance(publicKey.algorithm)
                .generatePublic(X509EncodedKeySpec(publicKey.encoded))
            val rsa = Cipher.getInstance(RSA_TRANSFORM)
            rsa.init(Cipher.ENCRYPT_MODE, unrestricted, oaepSpec())
            val wrapped = rsa.doFinal(aesKey)
            if (wrapped.size != WRAPPED_KEY_BYTES) {
                throw VaultFailure("encryptFailed", "硬件密钥封装长度异常")
            }
            return ByteArray(1 + 2 + wrapped.size + iv.size + body.size).also { output ->
                output[0] = BLOB_VERSION
                output[1] = ((wrapped.size ushr 8) and 0xff).toByte()
                output[2] = (wrapped.size and 0xff).toByte()
                wrapped.copyInto(output, 3)
                iv.copyInto(output, 3 + wrapped.size)
                body.copyInto(output, 3 + wrapped.size + iv.size)
            }
        } finally {
            aesKey.fill(0)
        }
    }

    private fun decrypt(
        scope: String,
        aad: ByteArray,
        ciphertext: ByteArray,
        result: MethodChannel.Result,
    ) {
        val parsed = try {
            parseEnvelope(ciphertext)
        } catch (error: Exception) {
            aad.fill(0)
            ciphertext.fill(0)
            throw error
        }
        val alias = aliasFor(scope)
        val privateKey = try {
            val keyStore = keyStore()
            if (!keyStore.containsAlias(alias)) {
                throw VaultFailure("keyPermanentlyInvalidated", "硬件密钥不存在或已失效")
            }
            val key = keyStore.getKey(alias, null) as? PrivateKey
                ?: throw VaultFailure("keyPermanentlyInvalidated", "硬件私钥不可用")
            requireHardwareBacked(alias, key)
            key
        } catch (error: Exception) {
            parsed.clear()
            aad.fill(0)
            ciphertext.fill(0)
            throw error
        }
        val rsa = try {
            Cipher.getInstance(RSA_TRANSFORM).apply {
                init(Cipher.DECRYPT_MODE, privateKey, oaepSpec())
            }
        } catch (error: KeyPermanentlyInvalidatedException) {
            parsed.clear()
            aad.fill(0)
            ciphertext.fill(0)
            throw VaultFailure("keyPermanentlyInvalidated", "生物识别变化，硬件密钥已失效")
        }
        val host = activity ?: run {
            parsed.clear()
            aad.fill(0)
            ciphertext.fill(0)
            throw VaultFailure("unavailable", "当前页面无法发起生物识别")
        }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            private fun clearInputs() {
                parsed.clear()
                aad.fill(0)
                ciphertext.fill(0)
            }

            override fun onAuthenticationError(code: Int, message: CharSequence) {
                clearInputs()
                result.error(mapAuthError(code), message.toString(), code)
            }

            override fun onAuthenticationSucceeded(authentication: BiometricPrompt.AuthenticationResult) {
                var aesKey: ByteArray? = null
                var plaintext: ByteArray? = null
                try {
                    val authenticated = authentication.cryptoObject?.cipher
                        ?: throw VaultFailure("authError", "生物识别未绑定硬件解密")
                    aesKey = authenticated.doFinal(parsed.wrappedKey)
                    if (aesKey.size != AES_KEY_BYTES) {
                        throw VaultFailure("badBlob", "解包后的 AES 密钥长度异常")
                    }
                    val aes = Cipher.getInstance(AES_TRANSFORM)
                    aes.init(
                        Cipher.DECRYPT_MODE,
                        SecretKeySpec(aesKey, "AES"),
                        GCMParameterSpec(128, parsed.iv),
                    )
                    aes.updateAAD(aad)
                    plaintext = aes.doFinal(parsed.body)
                    if (plaintext.isEmpty()) throw VaultFailure("badBlob", "机密明文为空")
                    result.success(plaintext)
                } catch (error: VaultFailure) {
                    result.error(error.code, error.message, null)
                } catch (error: KeyPermanentlyInvalidatedException) {
                    result.error("keyPermanentlyInvalidated", "生物识别变化，硬件密钥已失效", null)
                } catch (error: Exception) {
                    result.error("badBlob", "密文、AAD 或硬件密钥不匹配", null)
                } finally {
                    aesKey?.fill(0)
                    plaintext?.fill(0)
                    clearInputs()
                }
            }
        }
        val prompt = BiometricPrompt(host, ContextCompat.getMainExecutor(host), callback)
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("验证身份")
            .setSubtitle("解锁钱包机密以继续")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .setNegativeButtonText("取消")
            .build()
        prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(rsa))
    }

    internal fun parseEnvelope(raw: ByteArray): ParsedEnvelope {
        val minimum = 1 + 2 + WRAPPED_KEY_BYTES + GCM_IV_BYTES + GCM_TAG_BYTES + 1
        if (raw.size < minimum || raw[0] != BLOB_VERSION) {
            throw VaultFailure("badBlob", "硬件金库密文格式或长度无效")
        }
        val wrappedLength = ((raw[1].toInt() and 0xff) shl 8) or (raw[2].toInt() and 0xff)
        if (wrappedLength != WRAPPED_KEY_BYTES) {
            throw VaultFailure("badBlob", "硬件封装密钥长度无效")
        }
        val wrappedEnd = 3 + wrappedLength
        val ivEnd = wrappedEnd + GCM_IV_BYTES
        if (wrappedEnd < 3 || ivEnd < wrappedEnd || ivEnd + GCM_TAG_BYTES >= raw.size) {
            throw VaultFailure("badBlob", "硬件金库密文边界无效")
        }
        return ParsedEnvelope(
            raw.copyOfRange(3, wrappedEnd),
            raw.copyOfRange(wrappedEnd, ivEnd),
            raw.copyOfRange(ivEnd, raw.size),
        )
    }

    private fun ensureHardwareKey(alias: String) {
        val keyStore = keyStore()
        if (keyStore.containsAlias(alias)) {
            val privateKey = keyStore.getKey(alias, null) as? PrivateKey
                ?: throw VaultFailure("keyPermanentlyInvalidated", "硬件私钥不可用")
            requireHardwareBacked(alias, privateKey)
            return
        }
        val strongBoxAttempted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
        if (strongBoxAttempted) {
            try {
                generateKey(alias, strongBox = true)
            } catch (_: StrongBoxUnavailableException) {
                generateKey(alias, strongBox = false)
            }
        } else {
            generateKey(alias, strongBox = false)
        }
        val privateKey = keyStore().getKey(alias, null) as? PrivateKey
            ?: throw VaultFailure("hardwareUnavailable", "硬件密钥生成失败")
        requireHardwareBacked(alias, privateKey)
    }

    private fun generateKey(alias: String, strongBox: Boolean) {
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .setKeySize(2048)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, KEYSTORE).apply {
            initialize(builder.build())
            generateKeyPair()
        }
    }

    private fun requireHardwareBacked(alias: String, privateKey: PrivateKey) {
        val keyInfo = KeyFactory.getInstance(privateKey.algorithm, KEYSTORE)
            .getKeySpec(privateKey, KeyInfo::class.java)
        val hardwareBacked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            keyInfo.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX ||
                keyInfo.securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT
        } else {
            @Suppress("DEPRECATION")
            keyInfo.isInsideSecureHardware
        }
        if (!hardwareBacked) {
            keyStore().deleteEntry(alias)
            throw VaultFailure("hardwareUnavailable", "设备不提供 StrongBox 或 TEE 钱包密钥")
        }
        val authenticationPerUse = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            keyInfo.userAuthenticationValidityDurationSeconds == 0 &&
                keyInfo.userAuthenticationType == KeyProperties.AUTH_BIOMETRIC_STRONG
        } else {
            @Suppress("DEPRECATION")
            keyInfo.userAuthenticationValidityDurationSeconds == -1
        }
        if (!keyInfo.isUserAuthenticationRequired ||
            !keyInfo.isUserAuthenticationRequirementEnforcedBySecureHardware ||
            !authenticationPerUse
        ) {
            keyStore().deleteEntry(alias)
            throw VaultFailure("hardwareUnavailable", "钱包密钥未由硬件强制逐次生物识别")
        }
    }

    private fun deleteKey(scope: String) {
        val keyStore = keyStore()
        val alias = aliasFor(scope)
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
    }

    private fun containsKey(scope: String): Boolean = keyStore().containsAlias(aliasFor(scope))

    internal fun aliasFor(scope: String): String {
        if (!Regex("^[a-z][a-z0-9]{2,31}:[a-z0-9._:-]{1,80}$").matches(scope)) {
            throw VaultFailure("badArgs", "硬件密钥作用域格式无效")
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(scope.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return KEY_ALIAS_PREFIX + digest
    }

    private fun keyStore() = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun oaepSpec() = OAEPParameterSpec(
        "SHA-256",
        "MGF1",
        MGF1ParameterSpec.SHA1,
        PSource.PSpecified.DEFAULT,
    )

    private fun requiredString(call: MethodCall, name: String): String =
        call.argument<String>(name) ?: throw VaultFailure("badArgs", "$name 缺失")

    private fun requiredBytes(call: MethodCall, name: String): ByteArray =
        call.argument<ByteArray>(name) ?: throw VaultFailure("badArgs", "$name 缺失")

    private fun mapAuthError(code: Int): String = when (code) {
        BiometricPrompt.ERROR_USER_CANCELED,
        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        BiometricPrompt.ERROR_CANCELED -> "userCancelled"
        BiometricPrompt.ERROR_LOCKOUT,
        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
        BiometricPrompt.ERROR_NO_BIOMETRICS,
        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL -> "notEnrolled"
        BiometricPrompt.ERROR_HW_NOT_PRESENT,
        BiometricPrompt.ERROR_HW_UNAVAILABLE -> "hardwareUnavailable"
        else -> "authError"
    }

    internal data class ParsedEnvelope(
        val wrappedKey: ByteArray,
        val iv: ByteArray,
        val body: ByteArray,
    ) {
        fun clear() {
            wrappedKey.fill(0)
            iv.fill(0)
            body.fill(0)
        }
    }

    internal class VaultFailure(val code: String, override val message: String) : Exception(message)
}
