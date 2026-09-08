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
    const val MAXIMUM_HISTORY_ACCOUNTS = 1990
    const val MAXIMUM_BALANCE_ACCOUNTS = 1990
    const val MAXIMUM_SIGNING_PAYLOAD_BYTES = 16 * 1024 * 1024
    const val MAXIMUM_QR_TEXT_BYTES = 2331
    const val MAXIMUM_QR_REVIEW_BYTES = 1920
    const val MAXIMUM_QR_IMAGE_BYTES = 16 * 1024 * 1024

    val methods: Set<String> = linkedSetOf(
        "open", "start", "stop", "close", "getCapabilities", "getFinalizedHead",
        "getGenesisHash", "getAccountBalance", "getAccountBalances", "getAccountNonce", "getFeeSnapshot", "getWalletProfile", "viewAccountPrivateKey",
        "createWallet", "importWallet", "addWalletAccounts", "setActiveWalletAccount",
        "renameWalletAccount", "deleteWalletAccount", "deleteWallet",
        "reconcileWalletCleanup", "signWalletPayload", "verifySignature", "transferWithRemark",
        "initializeFinalizedHistory", "syncFinalizedHistory",
        "qrParse", "qrCreateSignRequest", "qrConsumeSignResponse", "qrCancelSignRequest", "qrEncodeAccountId",
        "qrEncodeUserTransfer", "qrDecodeLuminance", "qrEncode", "qrScan", "signQrRequest",
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
            override val sessionId: String,
            override val requestSequence: Long,
            val accountId: ByteArray,
            val name: String,
        ) : SessionRequest
        data class SignWalletPayload(
            override val sessionId: String,
            override val requestSequence: Long,
            val accountId: ByteArray,
            val payload: ByteArray,
        ) : SessionRequest
        data class VerifySignature(
            val accountId: ByteArray,
            val signature: ByteArray,
            val payload: ByteArray,
        ) : Request {
            override val sessionId: String? = null
            override val requestSequence: Long = 0
        }
        data class TransferWithRemark(
            override val sessionId: String,
            override val requestSequence: Long,
            val sourceAccountId: ByteArray,
            val destinationAccountId: ByteArray,
            val amountFen: String,
            val remark: ByteArray,
        ) : SessionRequest
        data class History(
            val method: String,
            override val sessionId: String,
            override val requestSequence: Long,
            val accountIds: List<ByteArray>,
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
    ) : IllegalArgumentException(message)

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
                "start", "stop", "close", "getCapabilities", "getFinalizedHead", "getGenesisHash",
                "getFeeSnapshot", "getWalletProfile", "importWallet", "deleteWallet",
                "reconcileWalletCleanup" -> {
                    length(3)
                    Request.Empty(method, sessionId, sequence)
                }
                "getAccountBalance", "getAccountNonce", "setActiveWalletAccount",
                "deleteWalletAccount", "viewAccountPrivateKey" -> {
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
                "renameWalletAccount" -> {
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
                    Request.RenameWalletAccount(sessionId, sequence, hash32(tuple[3]), name)
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
                "transferWithRemark" -> {
                    length(7)
                    val amount = decimal(tuple[5], "amountFen", true)
                    val remark = string(tuple[6], "remark", 0, 99)
                        .toByteArray(StandardCharsets.UTF_8)
                    if (remark.size > 99) badRequest(
                        "remark UTF-8 length exceeds 99 bytes",
                        sessionId,
                        sequence,
                    )
                    Request.TransferWithRemark(
                        sessionId,
                        sequence,
                        hash32(tuple[3]),
                        hash32(tuple[4]),
                        amount,
                        remark,
                    )
                }
                "initializeFinalizedHistory", "syncFinalizedHistory" -> {
                    length(4)
                    val values = tuple[3] as? List<*>
                        ?: badRequest("accountIds must be a tuple", sessionId, sequence)
                    if (values.size !in 1..MAXIMUM_HISTORY_ACCOUNTS) {
                        badRequest("accountIds must contain 1..1990 accounts", sessionId, sequence)
                    }
                    val accounts = values.map(::hash32)
                    if (accounts.map(::encodeHash32).toSet().size != accounts.size) {
                        badRequest("accountIds must be non-empty and unique", sessionId, sequence)
                    }
                    Request.History(method, sessionId, sequence, accounts)
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
                "qrEncodeUserTransfer" -> {
                    length(10)
                    val requestId = string(tuple[3], "requestId", 16, 128)
                    val expiresAt = exactLong(tuple[4], "expiresAt")
                    if (expiresAt <= 0) badRequest("expiresAt must be positive", sessionId, sequence)
                    val amount = utf8Text(tuple[6], "amount", 1, 64)
                    val symbol = utf8Text(tuple[7], "symbol", 1, 16)
                    val memo = utf8Text(tuple[8], "memo", 0, 256)
                    val bank = utf8Text(tuple[9], "bankCidNumber", 1, 32)
                    Request.Qr(method, sessionId, sequence, listOf(
                        requestId, expiresAt, hash32(tuple[5]), amount, symbol, memo, bank,
                    ))
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
            throw ContractFailure(error.stableName, error.errorCode, error.message, sessionId, sequence)
        }
    }

    /** [1, sessionId, requestSequence, method-specific value tuple]. */
    fun response(sessionId: String, requestSequence: Long, value: List<Any?>): List<Any?> =
        listOf(PROTOCOL_VERSION, sessionId, requestSequence, value)

    /** [1, sessionId, eventSequence, type, type-specific payload tuple]. */
    fun event(sessionId: String, eventSequence: Long, type: String, payload: List<Any?>): List<Any?> {
        require(type in setOf("lifecycleChanged", "capabilitiesChanged", "transferProgress", "historyChanged"))
        require(type != "historyChanged" || (eventSequence > 0 && payload.isEmpty()))
        return listOf(PROTOCOL_VERSION, sessionId, eventSequence, type, payload)
    }

    /** [1, sessionId?, requestSequence?, errorCode, errorMessage?]. */
    fun errorDetails(
        code: CitizenSdkErrorCode,
        message: String?,
        sessionId: String?,
        requestSequence: Long?,
    ): List<Any?> = listOf(PROTOCOL_VERSION, sessionId, requestSequence, code.value, message)

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

    fun signature(value: CitizenSignature): ByteArray = value.bytes().also { check(it.size == 64) }

    fun transfer(value: CitizenWalletTransfer): List<Any?> = listOf(
        encodeHash32(value.transactionHash()),
        when (value.resolution) {
            CitizenTransferResolution.FINALIZED_SUCCESS -> "finalizedSuccess"
            CitizenTransferResolution.FINALIZED_FAILED -> "finalizedFailed"
            CitizenTransferResolution.POOL_REJECTED -> "poolRejected"
        },
        value.execution?.let(::execution),
        value.poolRejectionReason,
    )

    fun history(value: CitizenTransactionHistory): List<Any?> = listOf(
        value.revision,
        value.cursors.map(::cursor),
        value.records.map(::record),
        value.transfers.map(::finalizedTransfer),
    )

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

    private fun cursor(value: CitizenHistoryCursor): List<Any?> = listOf(
        encodeHash32(value.accountId()), block(value.trackingStartBlock), block(value.lastSyncedBlock),
    )

    private fun record(value: CitizenHistoryRecord): List<Any?> = listOf(
        encodeHash32(value.accountId()),
        encodeHash32(value.transactionHash()),
        value.nonce,
        encodeHash32(value.destinationAccountId()),
        value.amountFen.decimal,
        when (value.status) {
            CitizenHistoryStatus.PENDING -> "pending"
            CitizenHistoryStatus.IN_BLOCK -> "inBlock"
            CitizenHistoryStatus.POOL_REJECTED -> "poolRejected"
            CitizenHistoryStatus.FINALIZED_SUCCESS -> "finalizedSuccess"
            CitizenHistoryStatus.FINALIZED_FAILED -> "finalizedFailed"
        },
        value.block?.let(::block),
        value.execution?.let(::execution),
        value.createdAtMillis,
        value.updatedAtMillis,
        decodeUtf8(value.remark()),
        value.poolRejectionReason,
    )

    private fun finalizedTransfer(value: CitizenFinalizedTransfer): List<Any?> = listOf(
        encodeHash32(value.trackedAccountId()), encodeHash32(value.fromAccountId()),
        encodeHash32(value.toAccountId()), value.amountFen.decimal, block(value.block),
        value.eventRecordIndex, value.extrinsicIndex,
        if (value.direction == CitizenTransferDirection.OUTGOING) "outgoing" else "incoming",
        value.sourcePallet, value.remarkDisplay, value.remarkBytes(),
    )

    private fun hash32(value: Any?): ByteArray {
        val text = value as? String
            ?: throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "Hash must be a string")
        if (!HASH32.matches(text)) throw failure(CitizenSdkErrorCode.INVALID_ARGUMENT, "Invalid 32-byte hex")
        return ByteArray(32) { index -> text.substring(2 + index * 2, 4 + index * 2).toInt(16).toByte() }
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
    private val DECIMAL = Regex("^(0|[1-9][0-9]{0,38})$")
    private const val MAX_U128_DECIMAL = "340282366920938463463374607431768211455"
    private const val HEX = "0123456789abcdef"
}
