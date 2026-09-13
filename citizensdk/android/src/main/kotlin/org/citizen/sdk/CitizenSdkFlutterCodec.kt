package org.citizen.sdk

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/**
 * Fixed-position StandardMessageCodec projection for CitizenSDK protocol v1.
 *
 * Maps are forbidden: StandardMessageCodec collapses duplicate map keys before
 * Kotlin can validate them. Every request, response, event, error and nested
 * public value is a fixed-length tuple. Secret material and native ownership
 * handles have no tuple position.
 */
internal object CitizenSdkFlutterCodec {
    const val METHOD_CHANNEL = "citizen/sdk/core/v1"
    const val EVENT_CHANNEL = "citizen/sdk/events/v1"
    const val PROTOCOL_VERSION = 1
    const val MAXIMUM_ADDITIONAL_WALLET_ACCOUNTS = 1989
    const val MAXIMUM_WALLET_CATALOG_ACCOUNTS = 3980
    const val MAXIMUM_DEFAULT_ACCOUNT_CHANGE_ACCOUNTS = 256
    const val MAXIMUM_BALANCE_ACCOUNTS = 1990
    const val MAXIMUM_SIGNING_PAYLOAD_BYTES = 16 * 1024 * 1024
    const val MAXIMUM_STORAGE_KEY_BYTES = 4 * 1024
    const val MAXIMUM_STORAGE_BATCH_KEYS = 1024
    const val MAXIMUM_STORAGE_BATCH_KEY_BYTES = 1024 * 1024
    const val MAXIMUM_EXPORTED_STATE_BYTES = 256 * 1024
    const val MAXIMUM_QR_TEXT_BYTES = 2331
    const val MAXIMUM_QR_REVIEW_BYTES = 1920
    const val MAXIMUM_QR_IMAGE_BYTES = 16 * 1024 * 1024
    const val MAXIMUM_TRANSACTION_CALL_DATA_BYTES = 1024 * 1024

    val methods: Set<String> = linkedSetOf(
        "open", "start", "stop", "close", "getCapabilities", "getFinalizedHead",
        "getSyncStatus", "getBestHead", "getFinalizedBlockAt", "resolveFinalizedBlock",
        "getBlockHeader", "getBlockBody", "getRuntimeContext", "getStorage", "getStorageBatch",
        "getStorageKeysPaged", "callRuntimeApi",
        "getSystemEvents", "exportState", "importState",
        "getGenesisHash", "getAccountBalance", "getAccountBalances", "getAccountNonce", "getFeeSnapshot", "getWalletProfile", "viewAccountPrivateKey",
        "getWalletState", "importColdAccountId", "importColdAccountSs58",
        "reorderWalletAccountsWithoutDefaultChange", "renameAccount", "deleteAccount",
        "createWallet", "importWallet", "addWalletAccounts", "setActiveWalletAccount",
        "renameWalletAccount", "deleteWalletAccount", "deleteWallet",
        "reconcileWalletCleanup", "signWalletPayload", "deriveApplicationKey",
        "beginSigning", "consumeExternalSignature", "cancelSigning",
        "beginDefaultAccountChange", "consumeDefaultAccountChange",
        "verifySignature", "prepareTransaction", "cancelPreparedTransaction",
        "executePreparedTransaction", "consumePreparedTransactionQrResponse",
        "cancelPreparedTransactionExecution", "getTransactionHistory",
        "syncTransactionHistory",
        "qrParse", "qrCreateSignRequest", "qrConsumeSignResponse", "qrCancelSignRequest", "qrEncodeAccountId",
        "qrDecodeLuminance", "qrEncode", "qrScan", "signQrRequest",
    )

    sealed interface Request {
        val sessionId: String?
        val requestSequence: Long

        data class Open(val modules: Int) : Request {
            override val sessionId: String? = null
            override val requestSequence: Long = 0
        }

        sealed interface SessionRequest : Request { override val sessionId: String }
        data class Empty(val method: String, override val sessionId: String, override val requestSequence: Long) : SessionRequest
        data class Account(
            val method: String,
            override val sessionId: String,
            override val requestSequence: Long,
            val accountId: ByteArray,
        ) : SessionRequest
        data class Balances(
            override val sessionId: String,
            override val requestSequence: Long,
            val accountIds: List<ByteArray>,
        ) : SessionRequest
        data class BlockNumber(
            override val sessionId: String,
            override val requestSequence: Long,
            val number: String,
        ) : SessionRequest
        data class ResolveBlock(
            override val sessionId: String,
            override val requestSequence: Long,
            val hash: ByteArray,
            val number: String,
        ) : SessionRequest
        data class Block(
            val method: String,
            override val sessionId: String,
            override val requestSequence: Long,
            val block: CitizenBlockRef,
        ) : SessionRequest
        data class Storage(
            override val sessionId: String,
            override val requestSequence: Long,
            val block: CitizenBlockRef,
            val key: ByteArray,
        ) : SessionRequest
        data class StorageBatch(
            override val sessionId: String,
            override val requestSequence: Long,
            val block: CitizenBlockRef,
            val keys: List<ByteArray>,
        ) : SessionRequest
        data class StorageKeysPage(
            override val sessionId: String,
            override val requestSequence: Long,
            val block: CitizenBlockRef,
            val prefix: ByteArray,
            val startKey: ByteArray?,
            val limit: Int,
        ) : SessionRequest
        data class RuntimeApi(
            override val sessionId: String,
            override val requestSequence: Long,
            val block: CitizenBlockRef,
            val method: String,
            val arguments: ByteArray,
        ) : SessionRequest
        data class ImportState(
            override val sessionId: String,
            override val requestSequence: Long,
            val state: CitizenChainState,
        ) : SessionRequest
        data class CreateWallet(
            override val sessionId: String,
            override val requestSequence: Long,
            val wordCount: Int,
        ) : SessionRequest
        data class AddWalletAccounts(
            override val sessionId: String,
            override val requestSequence: Long,
            val indices: List<Int>,
        ) : SessionRequest
        data class RenameWalletAccount(
            val method: String,
            override val sessionId: String,
            override val requestSequence: Long,
            val accountId: ByteArray,
            val name: String,
        ) : SessionRequest
        data class ColdSs58(
            override val sessionId: String,
            override val requestSequence: Long,
            val address: String,
            val name: String,
        ) : SessionRequest
        data class ReorderWalletAccounts(
            override val sessionId: String,
            override val requestSequence: Long,
            val expectedRevision: String,
            val accountIds: List<ByteArray>,
        ) : SessionRequest
        data class SignWalletPayload(
            override val sessionId: String,
            override val requestSequence: Long,
            val accountId: ByteArray,
            val payload: ByteArray,
        ) : SessionRequest
        data class DeriveApplicationKey(
            override val sessionId: String,
            override val requestSequence: Long,
            val accountId: ByteArray,
            val salt: ByteArray,
            val info: ByteArray,
        ) : SessionRequest
        data class BeginSigning(
            override val sessionId: String,
            override val requestSequence: Long,
            val intent: CitizenSigningIntent,
        ) : SessionRequest
        data class ExternalSignature(
            val method: String,
            override val sessionId: String,
            override val requestSequence: Long,
            val signingSessionId: String,
            val response: String,
        ) : SessionRequest
        data class CancelSigning(
            override val sessionId: String,
            override val requestSequence: Long,
            val signingSessionId: String,
        ) : SessionRequest
        data class BeginDefaultAccountChange(
            override val sessionId: String,
            override val requestSequence: Long,
            val expectedRevision: String,
            val accountIds: List<ByteArray>,
            val ttlSeconds: Long,
        ) : SessionRequest
        data class VerifySignature(
            val accountId: ByteArray,
            val signature: ByteArray,
            val payload: ByteArray,
        ) : Request {
            override val sessionId: String? = null
            override val requestSequence: Long = 0
        }
        data class PrepareTransaction(
            override val sessionId: String,
            override val requestSequence: Long,
            val sourceAccountId: ByteArray,
            val callData: ByteArray,
        ) : SessionRequest
        data class CancelPreparedTransaction(
            override val sessionId: String,
            override val requestSequence: Long,
            val preparationId: String,
        ) : SessionRequest
        data class TransactionExecution(
            val method: String,
            override val sessionId: String,
            override val requestSequence: Long,
            val executionId: String,
            val response: String?,
        ) : SessionRequest
        data class TransactionHistory(
            val method: String,
            override val sessionId: String,
            override val requestSequence: Long,
            val beforeExecutionId: String?,
            val limit: Int,
        ) : SessionRequest
        data class Qr(
            val method: String,
            override val sessionId: String,
            override val requestSequence: Long,
            val fields: List<Any>,
        ) : SessionRequest
    }

    class ContractFailure(
        val stableName: String,
        val errorCode: Int,
        override val message: String,
        val sessionId: String? = null,
        val requestSequence: Long? = null,
        val stage: CitizenSdkFailureStage = CitizenSdkFailureStage.fromErrorCode(
            CitizenSdkErrorCode.fromValue(errorCode),
        ),
    ) : IllegalArgumentException(message)

    fun requestMethod(request: Request): String = when (request) {
        is Request.Open -> "open"
        is Request.VerifySignature -> "verifySignature"
        is Request.Empty -> request.method
        is Request.Account -> request.method
        is Request.Balances -> "getAccountBalances"
        is Request.BlockNumber -> "getFinalizedBlockAt"
        is Request.ResolveBlock -> "resolveFinalizedBlock"
        is Request.Block -> request.method
        is Request.Storage -> "getStorage"
        is Request.StorageBatch -> "getStorageBatch"
        is Request.StorageKeysPage -> "getStorageKeysPaged"
        is Request.RuntimeApi -> "callRuntimeApi"
        is Request.ImportState -> "importState"
        is Request.CreateWallet -> "createWallet"
        is Request.AddWalletAccounts -> "addWalletAccounts"
        is Request.RenameWalletAccount -> request.method
        is Request.ColdSs58 -> "importColdAccountSs58"
        is Request.ReorderWalletAccounts -> "reorderWalletAccountsWithoutDefaultChange"
        is Request.SignWalletPayload -> "signWalletPayload"
        is Request.DeriveApplicationKey -> "deriveApplicationKey"
        is Request.BeginSigning -> "beginSigning"
        is Request.ExternalSignature -> request.method
        is Request.CancelSigning -> "cancelSigning"
        is Request.BeginDefaultAccountChange -> "beginDefaultAccountChange"
        is Request.PrepareTransaction -> "prepareTransaction"
        is Request.CancelPreparedTransaction -> "cancelPreparedTransaction"
        is Request.TransactionExecution -> request.method
        is Request.TransactionHistory -> request.method
        is Request.Qr -> request.method
    }

    /** open 与公开验签无会话；其他请求保留版本、会话、序号和固定字段位置。 */
    fun decode(method: String, rawArguments: Any?): Request {
        if (method !in methods) throw failure(CitizenSdkErrorCode.UNSUPPORTED, "Unsupported method")
        val tuple = rawArguments as? List<*>
            ?: throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "Arguments must be a tuple")
        if (tuple.isEmpty() || exactLong(tuple[0], "protocolVersion") != PROTOCOL_VERSION.toLong()) {
            throw failure(CitizenSdkErrorCode.UNSUPPORTED, "Unsupported protocol version")
        }
        if (method == "open") {
            requireLength(tuple, 2, null, null)
            val modules = exactLong(tuple[1], "modules")
            if (modules !in 0..0xffff_ffffL) throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "modules must be uint32")
            return Request.Open(modules.toInt())
        }
        if (method == "verifySignature") {
            // 必须在会话字段解析前验证唯一无会话形状，旧形状一律拒绝。
            requireLength(tuple, 4, null, null)
            val signature = bytes(tuple[2], "signature", false, 64)
            if (signature.size != 64) throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "signature must contain 64 bytes")
            return Request.VerifySignature(hash32(tuple[1]), signature,
                bytes(tuple[3], "payload", true, MAXIMUM_SIGNING_PAYLOAD_BYTES))
        }
        if (tuple.size < 3) throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "Truncated request")
        val sessionId = string(tuple[1], "sessionId", 1, 128)
        val sequence = exactLong(tuple[2], "requestSequence")
        if (sequence <= 0) throw badRequest("requestSequence must be positive", sessionId, sequence)
        fun length(expected: Int) = requireLength(tuple, expected, sessionId, sequence)
        return try {
            when (method) {
                "start", "stop", "close", "getCapabilities", "getFinalizedHead", "getSyncStatus",
                "getBestHead", "exportState", "getGenesisHash",
                "getFeeSnapshot", "getWalletProfile", "getWalletState", "importWallet", "deleteWallet",
                "reconcileWalletCleanup" -> {
                    length(3)
                    Request.Empty(method, sessionId, sequence)
                }
                "getFinalizedBlockAt" -> {
                    length(4)
                    Request.BlockNumber(sessionId, sequence, unsigned64Decimal(tuple[3], "number"))
                }
                "resolveFinalizedBlock" -> {
                    length(5)
                    Request.ResolveBlock(
                        sessionId, sequence, hash32(tuple[3]), unsigned64Decimal(tuple[4], "number"),
                    )
                }
                "getBlockHeader", "getBlockBody", "getRuntimeContext", "getSystemEvents" -> {
                    length(4)
                    val block = blockRef(tuple[3])
                    if (method == "getSystemEvents" && block.finality != CitizenFinality.FINALIZED) {
                        badRequest("getSystemEvents requires a finalized block", sessionId, sequence)
                    }
                    Request.Block(method, sessionId, sequence, block)
                }
                "getStorage" -> {
                    length(5)
                    Request.Storage(
                        sessionId, sequence, blockRef(tuple[3]),
                        bytes(tuple[4], "storage key", false, MAXIMUM_STORAGE_KEY_BYTES),
                    )
                }
                "getStorageBatch" -> {
                    length(5)
                    val rawKeys = tuple[4] as? List<*>
                        ?: badRequest("storage keys must be a tuple", sessionId, sequence)
                    if (rawKeys.size !in 1..MAXIMUM_STORAGE_BATCH_KEYS) {
                        badRequest("storage batch must contain 1..1024 keys", sessionId, sequence)
                    }
                    var total = 0
                    val keys = rawKeys.map {
                        bytes(it, "storage key", false, MAXIMUM_STORAGE_KEY_BYTES).also { key ->
                            total += key.size
                            if (total > MAXIMUM_STORAGE_BATCH_KEY_BYTES) {
                                badRequest("storage batch keys exceed 1 MiB", sessionId, sequence)
                            }
                        }
                    }
                    Request.StorageBatch(sessionId, sequence, blockRef(tuple[3]), keys)
                }
                "getStorageKeysPaged" -> {
                    length(7)
                    val block = blockRef(tuple[3])
                    if (block.finality != CitizenFinality.FINALIZED) {
                        badRequest("storage keys page requires finalized block", sessionId, sequence)
                    }
                    val prefix = bytes(tuple[4], "storage key prefix", false, MAXIMUM_STORAGE_KEY_BYTES)
                    val start = tuple[5]?.let {
                        bytes(it, "storage start key", false, MAXIMUM_STORAGE_KEY_BYTES)
                    }
                    val limit = exactLong(tuple[6], "storage keys page limit")
                    if (limit !in 1..1000) {
                        badRequest("storage keys page limit must be 1..1000", sessionId, sequence)
                    }
                    Request.StorageKeysPage(sessionId, sequence, block, prefix, start, limit.toInt())
                }
                "callRuntimeApi" -> {
                    length(6)
                    val name = string(tuple[4], "runtime API method", 1, 128)
                    if (!Regex("^[A-Za-z][A-Za-z0-9_]*_[A-Za-z0-9_]+$").matches(name)) {
                        badRequest("runtime API method is invalid", sessionId, sequence)
                    }
                    Request.RuntimeApi(
                        sessionId,
                        sequence,
                        blockRef(tuple[3]),
                        name,
                        bytes(tuple[5], "runtime API arguments", true, 1024 * 1024),
                    )
                }
                "importState" -> {
                    length(6)
                    val formatVersion = exactLong(tuple[3], "formatVersion")
                    val finalized = blockRef(tuple[4])
                    val database = bytes(tuple[5], "database", false, MAXIMUM_EXPORTED_STATE_BYTES)
                    if (formatVersion !in 1..0xffff_ffffL || finalized.finality != CitizenFinality.FINALIZED) {
                        badRequest("importState fields are invalid", sessionId, sequence)
                    }
                    Request.ImportState(
                        sessionId, sequence, CitizenChainState(formatVersion, finalized, database),
                    )
                }
                "getAccountBalance", "getAccountNonce", "setActiveWalletAccount",
                "deleteWalletAccount", "deleteAccount", "viewAccountPrivateKey" -> {
                    length(4)
                    Request.Account(method, sessionId, sequence, hash32(tuple[3]))
                }
                "getAccountBalances" -> {
                    length(4)
                    val values = tuple[3] as? List<*>
                        ?: badRequest("accountIds must be a tuple", sessionId, sequence)
                    if (values.size > MAXIMUM_BALANCE_ACCOUNTS) {
                        badRequest("accountIds must contain 0..1990 accounts", sessionId, sequence)
                    }
                    // 不去重、不排序；空列表也交由 Core 做模块与生命周期校验。
                    Request.Balances(sessionId, sequence, values.map(::hash32))
                }
                "createWallet" -> {
                    length(4)
                    val wordCount = exactInt(tuple[3], "wordCount")
                    if (wordCount != 12 && wordCount != 18 && wordCount != 24) badRequest(
                        "wordCount must be 12, 18 or 24",
                        sessionId,
                        sequence,
                    )
                    Request.CreateWallet(sessionId, sequence, wordCount)
                }
                "addWalletAccounts" -> {
                    length(4)
                    val values = tuple[3] as? List<*>
                        ?: badRequest("indices must be a tuple", sessionId, sequence)
                    if (values.size !in 1..MAXIMUM_ADDITIONAL_WALLET_ACCOUNTS) {
                        badRequest("indices must contain 1..1989 values", sessionId, sequence)
                    }
                    val indices = values.map { exactInt(it, "indices") }
                    if (indices.any { it !in 1..1989 } ||
                        indices.toSet().size != indices.size
                    ) badRequest("indices must be unique values in 1..1989", sessionId, sequence)
                    Request.AddWalletAccounts(sessionId, sequence, indices)
                }
                "renameWalletAccount", "renameAccount", "importColdAccountId" -> {
                    length(5)
                    val rawName = string(tuple[4], "name", 1, 128)
                    val name = rawName.trim()
                    if (rawName != name ||
                        name.codePointCount(0, name.length) !in 1..30 ||
                        name.any { character ->
                            character.code <= 0x1f || character.code in 0x7f..0x9f
                        }
                    ) {
                        badRequest(
                            "name must be trimmed, contain 1..30 Unicode scalars, and contain no control characters",
                            sessionId,
                            sequence,
                        )
                    }
                    Request.RenameWalletAccount(method, sessionId, sequence, hash32(tuple[3]), name)
                }
                "importColdAccountSs58" -> {
                    length(5)
                    val address = utf8Text(tuple[3], "ss58Address", 1, 64)
                    val rawName = string(tuple[4], "name", 1, 128)
                    val name = checkedAccountName(rawName, sessionId, sequence)
                    Request.ColdSs58(sessionId, sequence, address, name)
                }
                "reorderWalletAccountsWithoutDefaultChange" -> {
                    length(5)
                    val revision = unsigned64Decimal(tuple[3], "expectedRevision")
                    val values = tuple[4] as? List<*>
                        ?: badRequest("accountIds must be a tuple", sessionId, sequence)
                    if (values.size !in 1..MAXIMUM_WALLET_CATALOG_ACCOUNTS) {
                        badRequest("accountIds must contain 1..3980 accounts", sessionId, sequence)
                    }
                    Request.ReorderWalletAccounts(sessionId, sequence, revision, values.map(::hash32))
                }
                "signWalletPayload" -> {
                    length(5)
                    val payload = bytes(
                        tuple[4],
                        "payload",
                        true,
                        MAXIMUM_SIGNING_PAYLOAD_BYTES,
                    )
                    Request.SignWalletPayload(
                        sessionId,
                        sequence,
                        hash32(tuple[3]),
                        // Core/sr25519 明确允许签名空消息；这里必须与 C ABI
                        // 和 Dart codec 保持完全相同，避免 decoder 拒绝已消耗的序号。
                        payload,
                    )
                }
                "deriveApplicationKey" -> {
                    length(6)
                    val salt = bytes(tuple[4], "application key salt", false, 32)
                    if (salt.size != 32) {
                        badRequest("application key salt must be 32 bytes", sessionId, sequence)
                    }
                    Request.DeriveApplicationKey(
                        sessionId,
                        sequence,
                        hash32(tuple[3]),
                        salt,
                        bytes(tuple[5], "application key info", false, 256),
                    )
                }
                "beginSigning" -> {
                    length(10)
                    val payload = bytes(tuple[4], "payload", false, MAXIMUM_SIGNING_PAYLOAD_BYTES)
                    val transform = when (string(tuple[5], "transform", 3, 32)) {
                        "raw" -> CitizenSigningTransform.RAW
                        "substrateSigningPayload" -> CitizenSigningTransform.SUBSTRATE_SIGNING_PAYLOAD
                        "blake2Domain" -> CitizenSigningTransform.BLAKE2_DOMAIN
                        else -> badRequest("unknown signing transform", sessionId, sequence)
                    }
                    val domain = bytes(tuple[6], "domain", true, 32)
                    if ((transform == CitizenSigningTransform.BLAKE2_DOMAIN && domain.isEmpty()) ||
                        (transform != CitizenSigningTransform.BLAKE2_DOMAIN && domain.isNotEmpty())
                    ) badRequest("signing transform/domain combination is invalid", sessionId, sequence)
                    val transport = when (string(tuple[7], "transport", 4, 8)) {
                        "none" -> null
                        "qrV1" -> CitizenExternalSignerTransport.QR_V1
                        else -> badRequest("unknown external signer transport", sessionId, sequence)
                    }
                    val action = exactInt(tuple[8], "opaqueAction")
                    val ttl = exactLong(tuple[9], "ttlSeconds")
                    if (action !in 0..0xffff || ttl !in 1..300) {
                        badRequest("signing action or ttl is invalid", sessionId, sequence)
                    }
                    Request.BeginSigning(
                        sessionId, sequence,
                        CitizenSigningIntent(hash32(tuple[3]), payload, transform, domain, transport, action, ttl),
                    )
                }
                "consumeExternalSignature", "consumeDefaultAccountChange" -> {
                    length(5)
                    Request.ExternalSignature(
                        method, sessionId, sequence,
                        string(tuple[3], "signingSessionId", 1, 128),
                        qrText(tuple[4], "response"),
                    )
                }
                "cancelSigning" -> {
                    length(4)
                    Request.CancelSigning(
                        sessionId, sequence, string(tuple[3], "signingSessionId", 1, 128),
                    )
                }
                "beginDefaultAccountChange" -> {
                    length(6)
                    val revision = unsigned64Decimal(tuple[3], "expectedRevision")
                    val values = tuple[4] as? List<*>
                        ?: badRequest("accountIds must be a tuple", sessionId, sequence)
                    if (values.size !in 1..MAXIMUM_DEFAULT_ACCOUNT_CHANGE_ACCOUNTS) {
                        badRequest("accountIds must contain 1..256 accounts", sessionId, sequence)
                    }
                    val ttl = exactLong(tuple[5], "ttlSeconds")
                    if (ttl !in 1..300) badRequest("ttlSeconds must be 1..300", sessionId, sequence)
                    Request.BeginDefaultAccountChange(
                        sessionId, sequence, revision, values.map(::hash32), ttl,
                    )
                }
                "prepareTransaction" -> {
                    length(5)
                    Request.PrepareTransaction(
                        sessionId,
                        sequence,
                        hash32(tuple[3]),
                        bytes(
                            tuple[4],
                            "callData",
                            false,
                            MAXIMUM_TRANSACTION_CALL_DATA_BYTES,
                        ),
                    )
                }
                "cancelPreparedTransaction" -> {
                    length(4)
                    val preparationId = string(tuple[3], "preparationId", 34, 34)
                    if (!PREPARATION_ID.matches(preparationId)) {
                        badRequest("preparationId must be 16-byte lowercase hex", sessionId, sequence)
                    }
                    Request.CancelPreparedTransaction(sessionId, sequence, preparationId)
                }
                "executePreparedTransaction", "cancelPreparedTransactionExecution" -> {
                    length(4)
                    val id = string(tuple[3], "transaction id", 34, 34)
                    if (!PREPARATION_ID.matches(id)) badRequest("transaction id is invalid", sessionId, sequence)
                    Request.TransactionExecution(method, sessionId, sequence, id, null)
                }
                "consumePreparedTransactionQrResponse" -> {
                    length(5)
                    val id = string(tuple[3], "executionId", 34, 34)
                    if (!PREPARATION_ID.matches(id)) badRequest("executionId is invalid", sessionId, sequence)
                    Request.TransactionExecution(
                        method, sessionId, sequence, id, qrText(tuple[4], "QR_V1 response"),
                    )
                }
                "getTransactionHistory" -> {
                    length(5)
                    val before = tuple[3]?.let {
                        string(it, "beforeExecutionId", 34, 34).also { value ->
                            if (!PREPARATION_ID.matches(value)) {
                                badRequest("beforeExecutionId is invalid", sessionId, sequence)
                            }
                        }
                    }
                    val limit = exactLong(tuple[4], "limit")
                    if (limit !in 1..100) badRequest("limit must be 1..100", sessionId, sequence)
                    Request.TransactionHistory(method, sessionId, sequence, before, limit.toInt())
                }
                "syncTransactionHistory" -> {
                    length(3)
                    Request.TransactionHistory(method, sessionId, sequence, null, 100)
                }
                "qrParse", "qrConsumeSignResponse", "signQrRequest" -> {
                    length(4)
                    Request.Qr(method, sessionId, sequence, listOf(qrText(tuple[3], "$method.text")))
                }
                "qrScan" -> { length(3); Request.Qr(method, sessionId, sequence, emptyList()) }
                "qrCreateSignRequest" -> {
                    length(7)
                    val action = exactInt(tuple[3], "action")
                    if (action !in 1..0xffff) badRequest("action must be uint16", sessionId, sequence)
                    val payload = bytes(tuple[5], "reviewPayload", false, MAXIMUM_QR_REVIEW_BYTES)
                    val ttl = exactLong(tuple[6], "ttlSeconds")
                    if (ttl !in 1..300) badRequest("ttlSeconds must be 1..300", sessionId, sequence)
                    Request.Qr(method, sessionId, sequence,
                        listOf(action, hash32(tuple[4]), payload, ttl))
                }
                "qrCancelSignRequest" -> {
                    length(4)
                    Request.Qr(method, sessionId, sequence,
                        listOf(string(tuple[3], "requestId", 16, 128)))
                }
                "qrEncodeAccountId" -> {
                    length(4)
                    Request.Qr(method, sessionId, sequence, listOf(hash32(tuple[3])))
                }
                "qrDecodeLuminance" -> {
                    length(7)
                    val pixels = bytes(tuple[3], "luminance", false, MAXIMUM_QR_IMAGE_BYTES)
                    val width = positiveDimension(tuple[4], "width")
                    val height = positiveDimension(tuple[5], "height")
                    val stride = positiveDimension(tuple[6], "rowStride")
                    val required = (height - 1L) * stride + width
                    if (stride < width || pixels.size.toLong() < required) {
                        badRequest("luminance dimensions are invalid", sessionId, sequence)
                    }
                    Request.Qr(method, sessionId, sequence, listOf(pixels, width, height, stride))
                }
                "qrEncode" -> {
                    length(5)
                    val scale = exactInt(tuple[4], "scale")
                    if (scale !in 1..16) badRequest("scale must be 1..16", sessionId, sequence)
                    Request.Qr(method, sessionId, sequence,
                        listOf(qrText(tuple[3], "text"), scale))
                }
                else -> throw failure(CitizenSdkErrorCode.UNSUPPORTED, "Unsupported method")
            }
        } catch (error: ContractFailure) {
            if (error.sessionId != null) throw error
            throw ContractFailure(
                error.stableName,
                error.errorCode,
                error.message,
                sessionId,
                sequence,
                error.stage,
            )
        }
    }

    /** [1, sessionId, requestSequence, method-specific value tuple]. */
    fun response(sessionId: String, requestSequence: Long, value: List<Any?>): List<Any?> =
        listOf(PROTOCOL_VERSION, sessionId, requestSequence, value)

    /** [1, sessionId, eventSequence, type, type-specific payload tuple]. */
    fun event(sessionId: String, eventSequence: Long, type: String, payload: List<Any?>): List<Any?> {
        require(type in setOf(
            "lifecycleChanged", "capabilitiesChanged", "historyChanged", "finalizedBlockChanged",
        ))
        require(eventSequence > 0)
        require(type != "historyChanged" || (eventSequence > 0 && payload.isEmpty()))
        require(type != "finalizedBlockChanged" || payload.size == 1)
        return listOf(PROTOCOL_VERSION, sessionId, eventSequence, type, payload)
    }

    /** [1, sessionId?, requestSequence?, errorCode, failureStage, method, errorMessage?]. */
    fun errorDetails(
        code: CitizenSdkErrorCode,
        message: String?,
        sessionId: String?,
        requestSequence: Long?,
        method: String,
        stage: CitizenSdkFailureStage = CitizenSdkFailureStage.fromErrorCode(code),
    ): List<Any?> {
        require(method in methods) { "error method must be public" }
        return listOf(
            PROTOCOL_VERSION,
            sessionId,
            requestSequence,
            code.value,
            stage.value,
            method,
            message,
        )
    }

    fun errorName(code: CitizenSdkErrorCode): String = when (code) {
        CitizenSdkErrorCode.OK -> "ok"
        CitizenSdkErrorCode.INVALID_ARGUMENT -> "invalidArgument"
        CitizenSdkErrorCode.INVALID_HANDLE -> "invalidHandle"
        CitizenSdkErrorCode.INVALID_STATE -> "invalidState"
        CitizenSdkErrorCode.UNSUPPORTED -> "unsupported"
        CitizenSdkErrorCode.UNAVAILABLE -> "unavailable"
        CitizenSdkErrorCode.NOT_READY -> "notReady"
        CitizenSdkErrorCode.NOT_FOUND -> "notFound"
        CitizenSdkErrorCode.CONFLICT -> "conflict"
        CitizenSdkErrorCode.INTEGRITY -> "integrity"
        CitizenSdkErrorCode.AUTHENTICATION_CANCELLED -> "authenticationCancelled"
        CitizenSdkErrorCode.AUTHENTICATION_REQUIRED -> "authenticationRequired"
        CitizenSdkErrorCode.KEY_INVALIDATED -> "keyInvalidated"
        CitizenSdkErrorCode.PERMISSION_DENIED -> "permissionDenied"
        CitizenSdkErrorCode.STORAGE -> "storage"
        CitizenSdkErrorCode.NETWORK -> "network"
        CitizenSdkErrorCode.DECODE -> "decode"
        CitizenSdkErrorCode.TIMEOUT -> "timeout"
        CitizenSdkErrorCode.BUSY -> "busy"
        CitizenSdkErrorCode.QUEUE_FULL -> "queueFull"
        CitizenSdkErrorCode.INTERNAL -> "internal"
        CitizenSdkErrorCode.PANIC -> "panic"
        CitizenSdkErrorCode.CANCELLED -> "cancelled"
    }

    fun lifecycle(value: CitizenSdkLifecycle): String = when (value) {
        CitizenSdkLifecycle.CREATED -> "created"
        CitizenSdkLifecycle.IMPORTING_STATE -> "importingState"
        CitizenSdkLifecycle.STARTING -> "starting"
        CitizenSdkLifecycle.RUNNING -> "running"
        CitizenSdkLifecycle.START_FAILED -> "startFailed"
        CitizenSdkLifecycle.STOPPED -> "stopped"
        CitizenSdkLifecycle.DISPOSED -> "disposed"
    }

    fun block(value: CitizenBlockRef): List<Any?> = listOf(
        encodeHash32(value.hash()),
        value.number,
        if (value.finality == CitizenFinality.BEST) "best" else "finalized",
    )

    fun syncStatus(value: CitizenChainSyncStatus): List<Any?> = listOf(
        value.peerCount, value.isSyncing, value.isUsable, block(value.best), block(value.finalized),
    )

    fun blockHeader(value: CitizenBlockHeader): List<Any?> = listOf(
        block(value.block), encodeHash32(value.parentHash()), encodeHash32(value.stateRoot()),
        encodeHash32(value.extrinsicsRoot()), value.digest(),
    )

    fun blockBody(value: CitizenBlockBody): List<Any?> =
        listOf(block(value.block), value.extrinsics())

    fun runtimeContext(value: CitizenRuntimeContext): List<Any?> = listOf(
        block(value.block), value.specVersion, value.transactionVersion, value.metadata(),
    )

    fun chainState(value: CitizenChainState): List<Any?> = listOf(
        value.formatVersion, block(value.finalized), value.database(),
    )

    fun capabilities(value: CitizenSdkCapabilities): List<Any?> = listOf(
        value.revision,
        value.statuses.map(::capabilityStatus),
    )

    fun balance(value: CitizenAccountBalance): List<Any?> = listOf(
        encodeHash32(value.accountId()), block(value.block), value.freeFen.decimal,
        value.reservedFen.decimal, value.totalFen.decimal,
    )

    fun nonce(value: CitizenAccountNonce): List<Any?> =
        listOf(encodeHash32(value.accountId()), block(value.bestBlock), value.nonce)

    fun fee(value: CitizenFeeSnapshot): List<Any?> = listOf(
        block(value.bestBlock), value.feeRateParts, value.minimumFeeFen.decimal,
        value.existentialDepositFen.decimal,
    )

    fun profile(value: CitizenWalletProfile?): List<Any?>? = value?.let { profile ->
        listOf(
            profile.walletIndex,
            if (profile.origin == CitizenWalletOrigin.CREATED) "created" else "imported",
            profile.createdAtMillis,
            encodeHash32(profile.masterAccountId()),
            encodeHash32(profile.activeAccountId()),
            profile.accounts.map(::walletAccount),
        )
    }

    fun walletState(value: CitizenWalletState): List<Any?> = listOf(
        value.revision,
        profile(value.hotProfile),
        value.accounts.map { account ->
            listOf(
                if (account.signMode == CitizenWalletSignMode.HOT) "hot" else "cold",
                account.walletIndex,
                account.accountIndex,
                encodeHash32(account.accountId()),
                account.ss58Address,
                account.name,
                account.createdAtMillis,
                account.isDefault,
            )
        },
    )

    fun signature(value: CitizenSignature): ByteArray = value.bytes().also { check(it.size == 64) }

    fun signingOutcome(value: CitizenSigningOutcome): List<Any?> = when (value) {
        is CitizenSigningOutcome.Completed -> listOf(
            "completed", encodeHash32(value.accountId()), encodeHash32(value.payloadHash()),
            signature(value.signature), null, null, null,
        )
        is CitizenSigningOutcome.ExternalPending -> listOf(
            "externalPending", encodeHash32(value.accountId()), encodeHash32(value.payloadHash()),
            null, value.expiresAt, value.sessionId, value.transportRequest,
        )
    }

    fun defaultAccountChangeOutcome(value: CitizenDefaultAccountChangeOutcome): List<Any?> = when (value) {
        is CitizenDefaultAccountChangeOutcome.Completed -> listOf(
            "completed", encodeHash32(value.currentDefaultAccountId()), encodeHash32(value.payloadHash()),
            value.committedRevision, null, null, null,
        )
        is CitizenDefaultAccountChangeOutcome.ExternalPending -> listOf(
            "externalPending", encodeHash32(value.currentDefaultAccountId()), encodeHash32(value.payloadHash()),
            null, value.expiresAt, value.sessionId, value.transportRequest,
        )
    }

    fun transactionHistoryPage(value: CitizenTransactionHistoryPage): List<Any?> = listOf(
        value.revision,
        value.records.map(::transactionHistoryRecord),
        value.nextBeforeExecutionId()?.let(::encodeId16),
    )

    fun preparedTransaction(value: CitizenPreparedTransaction): List<Any?> = listOf(
        value.preparationId,
        encodeHash32(value.sourceAccountId()),
        encodeHash32(value.callDataHash()),
        block(value.bestBlock),
        value.runtimeSpecNumber,
        value.transactionFormatNumber,
        value.nonce,
    )

    fun transactionExecution(value: CitizenTransactionExecution): List<Any?> = when (value) {
        is CitizenTransactionExecution.ExternalSigningPending -> listOf(
            1, value.executionId, encodeHash32(value.sourceAccountId()), encodeHash32(value.callDataHash()),
            null, value.expiresAt, value.qrRequest, null, null, null,
        )
        is CitizenTransactionExecution.Completed -> listOf(
            when (value.resolution) {
                CitizenTransactionResolution.FINALIZED_SUCCESS -> 2
                CitizenTransactionResolution.FINALIZED_FAILED -> 3
                CitizenTransactionResolution.POOL_REJECTED -> 4
            },
            value.executionId, encodeHash32(value.sourceAccountId()), encodeHash32(value.callDataHash()),
            encodeHash32(value.transactionHash()), null, null, value.execution?.let(::execution),
            value.poolRejectionReason, value.replacementHash()?.let(::encodeHash32),
        )
    }

    fun encodeHash32(bytes: ByteArray): String {
        require(bytes.size == 32)
        return buildString(66) {
            append("0x")
            bytes.forEach { byte ->
                append(HEX[(byte.toInt() ushr 4) and 0xf])
                append(HEX[byte.toInt() and 0xf])
            }
        }
    }

    fun encodeId16(bytes: ByteArray): String {
        require(bytes.size == 16)
        return buildString(34) {
            append("0x")
            bytes.forEach { byte ->
                append(HEX[(byte.toInt() ushr 4) and 0xf])
                append(HEX[byte.toInt() and 0xf])
            }
        }
    }

    private fun capabilityStatus(value: CitizenCapabilityStatus): List<Any?> = listOf(
        when (value.name) {
            CitizenCapabilityName.CHAIN_READ -> "chainRead"
            CitizenCapabilityName.TRANSACTION_BUILD -> "transactionBuild"
            CitizenCapabilityName.TRANSACTION_SUBMIT -> "transactionSubmit"
            CitizenCapabilityName.TRANSACTION_VERIFY -> "transactionVerify"
            CitizenCapabilityName.WALLET_PROFILE -> "walletProfile"
            CitizenCapabilityName.LOCAL_SIGNING -> "localSigning"
            CitizenCapabilityName.HARDWARE_VAULT -> "hardwareVault"
            CitizenCapabilityName.USER_AUTHENTICATION -> "userAuthentication"
            CitizenCapabilityName.HISTORY -> "history"
            CitizenCapabilityName.BACKGROUND_SYNC -> "backgroundSync"
        },
        value.supported, value.available, value.enabled, value.ready,
        when (value.reason) {
            CitizenCapabilityReason.NONE -> "none"
            CitizenCapabilityReason.BUILD_UNSUPPORTED -> "buildUnsupported"
            CitizenCapabilityReason.DEVICE_UNAVAILABLE -> "deviceUnavailable"
            CitizenCapabilityReason.HOST_DISABLED -> "hostDisabled"
            CitizenCapabilityReason.ENGINE_NOT_RUNNING -> "engineNotRunning"
            CitizenCapabilityReason.DEPENDENCY_NOT_READY -> "dependencyNotReady"
            CitizenCapabilityReason.USER_AUTHENTICATION_REQUIRED -> "userAuthenticationRequired"
            CitizenCapabilityReason.VAULT_LOCKED -> "vaultLocked"
            CitizenCapabilityReason.CHAIN_STARTING -> "chainStarting"
            CitizenCapabilityReason.CHAIN_UNSYNCED -> "chainUnsynced"
            CitizenCapabilityReason.STORAGE_UNAVAILABLE -> "storageUnavailable"
        },
    )

    private fun walletAccount(value: CitizenWalletAccount): List<Any?> = listOf(
        value.index, encodeHash32(value.accountId()), value.ss58Address, value.name ?: "",
        value.createdAtMillis, value.active,
    )

    private fun execution(value: CitizenExecution): List<Any?> {
        check(value.status != CitizenExecutionStatus.UNVERIFIED)
        return listOf(
            if (value.status == CitizenExecutionStatus.SUCCESS) "success" else "failed",
            block(checkNotNull(value.block)),
            checkNotNull(value.extrinsicIndex),
            if (value.status == CitizenExecutionStatus.FAILED) value.reasonOrDispatchVariant else null,
            value.palletIndex,
            value.errorIndex,
        )
    }

    private fun transactionHistoryRecord(value: CitizenTransactionHistoryRecord): List<Any?> = listOf(
        encodeId16(value.executionId()),
        encodeHash32(value.sourceAccountId()),
        encodeHash32(value.callDataHash()),
        encodeHash32(value.transactionHash()),
        when (value.status) {
            CitizenTransactionHistoryStatus.PENDING -> "pending"
            CitizenTransactionHistoryStatus.IN_BLOCK -> "inBlock"
            CitizenTransactionHistoryStatus.POOL_REJECTED -> "poolRejected"
            CitizenTransactionHistoryStatus.FINALIZED_SUCCESS -> "finalizedSuccess"
            CitizenTransactionHistoryStatus.FINALIZED_FAILED -> "finalizedFailed"
        },
        value.block?.let(::block),
        value.execution?.let(::execution),
        value.replacementHash()?.let(::encodeHash32),
        value.createdAtMillis,
        value.updatedAtMillis,
        value.poolRejectionReason,
    )

    private fun hash32(value: Any?): ByteArray {
        val text = value as? String
            ?: throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "Hash must be a string")
        if (!HASH32.matches(text)) throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "Invalid 32-byte hex")
        return ByteArray(32) { index -> text.substring(2 + index * 2, 4 + index * 2).toInt(16).toByte() }
    }

    private fun blockRef(value: Any?): CitizenBlockRef {
        val tuple = value as? List<*>
            ?: throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "block must be a tuple")
        if (tuple.size != 3) throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "block tuple length is invalid")
        val finality = when (tuple[2]) {
            "best" -> CitizenFinality.BEST
            "finalized" -> CitizenFinality.FINALIZED
            else -> throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "block finality is invalid")
        }
        return CitizenBlockRef(hash32(tuple[0]), unsigned64Decimal(tuple[1], "block number"), finality)
    }

    private fun bytes(
        value: Any?,
        label: String,
        allowEmpty: Boolean,
        maximum: Int = Int.MAX_VALUE,
    ): ByteArray {
        val result = value as? ByteArray
            ?: throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label must be Uint8List")
        if (!allowEmpty && result.isEmpty()) {
            throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label must not be empty")
        }
        if (result.size > maximum) {
            throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label exceeds $maximum bytes")
        }
        return result.clone()
    }

    private fun decimal(value: Any?, label: String, positive: Boolean): String {
        val text = value as? String
            ?: throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label must be a decimal string")
        if (!DECIMAL.matches(text) ||
            (text.length == MAX_U128_DECIMAL.length && text > MAX_U128_DECIMAL) ||
            (positive && text == "0")
        ) {
            throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label is not canonical")
        }
        return text
    }

    private fun unsigned64Decimal(value: Any?, label: String): String {
        val text = value as? String
            ?: throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label must be a decimal string")
        if (!DECIMAL.matches(text) || text.length > 20) {
            throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label is not canonical uint64")
        }
        try {
            java.lang.Long.parseUnsignedLong(text)
        } catch (_: NumberFormatException) {
            throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label is not uint64")
        }
        return text
    }

    private fun checkedAccountName(rawName: String, sessionId: String, sequence: Long): String {
        val name = rawName.trim()
        if (rawName != name || name.codePointCount(0, name.length) !in 1..30 ||
            name.any { it.code <= 0x1f || it.code in 0x7f..0x9f }) {
            badRequest("name must be trimmed, contain 1..30 Unicode scalars, and contain no control characters",
                sessionId, sequence)
        }
        return name
    }

    private fun string(value: Any?, label: String, minimum: Int, maximum: Int): String {
        val text = value as? String
            ?: throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label must be a string")
        if (text.length !in minimum..maximum) {
            throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label length is invalid")
        }
        return text
    }

    private fun utf8Text(value: Any?, label: String, minimum: Int, maximum: Int): String {
        val text = string(value, label, 0, maximum)
        val size = text.toByteArray(StandardCharsets.UTF_8).size
        if (size !in minimum..maximum) {
            throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label UTF-8 length is invalid")
        }
        return text
    }

    private fun qrText(value: Any?, label: String): String =
        utf8Text(value, label, 1, MAXIMUM_QR_TEXT_BYTES)

    private fun nonNegativeLong(value: Any?, label: String): Long =
        exactLong(value, label).also {
            if (it < 0) throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label must be non-negative")
        }

    private fun positiveDimension(value: Any?, label: String): Long =
        exactLong(value, label).also {
            if (it !in 1..4096) throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label must be 1..4096")
        }

    private fun exactInt(value: Any?, label: String): Int {
        val result = exactLong(value, label)
        if (result !in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
            throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label is outside int32")
        }
        return result.toInt()
    }

    private fun exactLong(value: Any?, label: String): Long = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "$label must be an integer")
    }

    private fun requireLength(tuple: List<*>, expected: Int, sessionId: String?, sequence: Long?) {
        if (tuple.size != expected) throw ContractFailure(
            errorName(CitizenSdkErrorCode.INVALID_ARGUMENT),
            CitizenSdkErrorCode.INVALID_ARGUMENT.value,
            "Request tuple length is invalid",
            sessionId,
            sequence,
        )
    }

    private fun decodeUtf8(value: ByteArray): String = try {
        StandardCharsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(value))
            .toString()
    } catch (_: Exception) {
        throw failure(CitizenSdkErrorCode.INTEGRITY, "Core returned invalid UTF-8 remark")
    }

    private fun failure(code: CitizenSdkErrorCode, message: String): ContractFailure =
        ContractFailure(errorName(code), code.value, message)

    private fun badRequest(message: String, sessionId: String, sequence: Long): Nothing =
        throw ContractFailure(
            errorName(CitizenSdkErrorCode.INVALID_ARGUMENT),
            CitizenSdkErrorCode.INVALID_ARGUMENT.value,
            message,
            sessionId,
            sequence,
        )

    private val HASH32 = Regex("^0x[0-9a-f]{64}$")
    private val PREPARATION_ID = Regex("^0x[0-9a-f]{32}$")
    private val DECIMAL = Regex("^(0|[1-9][0-9]{0,38})$")
    private const val MAX_U128_DECIMAL = "340282366920938463463374607431768211455"
    private const val HEX = "0123456789abcdef"
}
