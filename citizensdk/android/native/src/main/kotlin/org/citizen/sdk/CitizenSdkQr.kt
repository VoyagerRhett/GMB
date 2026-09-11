package org.citizen.sdk

import org.json.JSONObject
import org.citizen.sdk.internal.CitizenSdkNative
import java.util.concurrent.atomic.AtomicLong

/** Rust 唯一解析结果；公开结构不暴露可注入签名或内部审阅凭证。 */
class CitizenQrDocument internal constructor(
    val kind: Int,
    val canonicalText: String,
    val content: Content,
    val signRequest: String?,
    @get:JvmSynthetic internal val coreJson: String,
    @get:JvmSynthetic internal val signedImage: CitizenQrImage? = null,
) {
    internal fun withSignedImage(image: CitizenQrImage) = CitizenQrDocument(kind, canonicalText, content, signRequest, coreJson, image)
    sealed class Content {
        data class SignRequest(val requestId: String, val expiresAt: Long, val action: Int,
            val signerAccountId: String, val reviewPayload: String) : Content()
        data class SignResponse(val requestId: String, val expiresAt: Long,
            val signerAccountId: String, val signature: String) : Content()
        data class AccountId(val accountId: String) : Content()
    }
    internal companion object {
        fun parse(json: String): CitizenQrDocument = projection {
            val value = objectValue(json)
            val kind = value.getInt("kind")
            val canonical = value.text("canonical_text").also { check(it.toByteArray(Charsets.UTF_8).size in 1..2331) }
            val content = when (kind) {
                1 -> Content.SignRequest(value.text("request_id"), value.expiration(),
                    value.getInt("action").also { check(it in 1..65535) }, value.hex("signer_account_id", 32), value.hex("review_payload"))
                2 -> Content.SignResponse(value.text("request_id"), value.expiration(),
                    value.hex("signer_account_id", 32), value.hex("signature", 64))
                5 -> Content.AccountId(value.hex("account_id", 32))
                else -> error("unsupported Core QR kind")
            }
            CitizenQrDocument(kind, canonical, content, if (value.has("sign_request")) value.text("sign_request") else null, json)
        }
        fun objectValue(json: String): JSONObject {
            check(json.toByteArray(Charsets.UTF_8).size in 1..65536)
            return JSONObject(json)
        }
        fun JSONObject.text(key: String): String = get(key).let { check(it is String); it }
        fun JSONObject.unsigned(key: String): String = get(key).let {
            check(it is Number); it.toString().also { number -> check(number.toULongOrNull() != null) }
        }
        fun JSONObject.expiration(): Long = get("expires_at").let {
            // Core 统一为正 i64，拒绝 Double 和字符串，禁止平台自行舍入时间。
            check(it is Long || it is Int)
            (it as Number).toLong().also { expiration -> check(expiration > 0) }
        }
        fun JSONObject.hex(key: String, count: Int? = null): String = text(key).also {
            check(it.startsWith("0x") && it.length % 2 == 0 && it.drop(2).all { char -> char in '0'..'9' || char in 'a'..'f' })
            if (count != null) check(it.length == 2 + 2 * count)
        }
        fun <T> projection(body: () -> T): T = try { body() } catch (error: Throwable) {
            throw CitizenSdkException(CitizenSdkErrorCode.INTEGRITY, "Core QR 文档不完整", error)
        }
    }
}

/** Core 结果所有权只在 SDK 内部；确认时传原句柄，成功接纳或关闭后只释放一次。 */
internal class CitizenSdkQrReview(private val native: CitizenSdkNative, result: Long, json: String) : AutoCloseable {
    private val gate = Any()
    private val handle = AtomicLong(result)
    val document = CitizenQrDocument.parse(json)
    val text: String = CitizenQrDocument.projection {
        with(CitizenQrDocument) {
            val value = objectValue(json)
            check(document.kind == 1)
            val spec = value.unsigned("spec_version"); check(spec.toULong() <= UInt.MAX_VALUE.toULong())
            val transaction = value.unsigned("transaction_version"); check(transaction.toULong() <= UInt.MAX_VALUE.toULong())
            // 不截断、不富文本执行参数；把同一凭证里的完整调用及签名域展示给用户。
            listOf(
                "请求" to value.text("request_id"), "有效截止" to (document.content as CitizenQrDocument.Content.SignRequest).expiresAt,
                "签名账户" to value.hex("signer_account_id", 32), "动作" to value.getInt("action").toString(),
                "模块" to value.text("pallet_name"), "调用" to value.text("call_name"), "参数" to value.text("call_arguments"),
                "创世哈希" to value.hex("genesis_hash", 32), "运行时版本" to spec, "交易版本" to transaction,
                "有效期" to value.text("era"), "Nonce" to value.text("nonce"), "Tip" to value.text("tip"),
                "区块哈希" to value.hex("block_hash", 32), "完整载荷" to value.hex("review_payload"),
            ).joinToString("\n\n") { "${it.first}\n${it.second}" }
        }
    }
    fun <T> withHandle(body: (Long) -> T): T = synchronized(gate) {
        val value = handle.get(); check(value != 0L) { "QR 审阅凭证已消费" }; body(value)
    }
    override fun close() = synchronized(gate) {
        val value = handle.getAndSet(0); if (value != 0L) native.releaseQrReview(value)
    }
}

/** ZXing-C++ 生成的 8 位灰度 QR Code Model 2 图像。 */
data class CitizenQrSigned(val document: CitizenQrDocument, val qrImage: CitizenQrImage)

/** ZXing-C++ 生成的 8 位灰度 QR Code Model 2 图像。 */
data class CitizenQrImage(val width: Int, val height: Int, val luminance: ByteArray) {
    fun luminance(): ByteArray = luminance.clone()
}
