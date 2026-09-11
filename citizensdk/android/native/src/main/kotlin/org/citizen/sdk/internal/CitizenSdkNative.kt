@file:kotlin.jvm.JvmSynthetic

package org.citizen.sdk.internal

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import org.citizen.sdk.*
import org.citizen.sdk.ui.CitizenSdkPrivateKeyDisplayBuffer

/** One private JNI owner; no native identity is returned by a public method. */
internal class CitizenSdkNative private constructor(
    assets: CitizenSdkAssets?,
    hostServices: CitizenSdkHostServices,
    modules: Int,
) : AutoCloseable {
    private val calls = CitizenSdkNativeCalls()
    private val bridge = nativeCreate(
        hostServices,
        assets?.manifest ?: byteArrayOf(),
        assets?.chainSpec ?: byteArrayOf(),
        assets?.lightSyncState ?: byteArrayOf(),
        modules,
    )

    @Volatile
    private var router: CitizenSdkRequestRouter? = null

    @Volatile
    private var eventSink: ((CitizenSdkEvents.Event) -> Unit)? = null

    fun bind(router: CitizenSdkRequestRouter, eventSink: (CitizenSdkEvents.Event) -> Unit) {
        check(this.router == null) { "native callback is already bound" }
        this.router = router
        this.eventSink = eventSink
        try {
            call { nativeBind(it) }
        } catch (error: Throwable) {
            this.router = null
            this.eventSink = null
            throw error
        }
    }

    fun lifecycle(): CitizenSdkLifecycle = call { lifecycleFromValue(nativeLifecycle(it)) }
    fun capabilities(): CitizenSdkCapabilities = call {
        CitizenSdkNativeCodec.decodeCapabilities(nativeCapabilities(it))
    }
    fun refreshCapabilities(): Long = call { nativeRefreshCapabilities(it) }
    fun start(): Long = call { nativeStart(it) }
    fun stop(): Long = call { nativeStop(it) }
    fun cancel(coreRequestId: Long): Boolean = call { nativeCancel(it, coreRequestId) }
    fun getFinalizedHead(): Long = call { nativeGetFinalizedHead(it) }
    fun getSyncStatus(): Long = call { nativeGetSyncStatus(it) }
    fun getBestHead(): Long = call { nativeGetBestHead(it) }
    fun getFinalizedBlockAt(number: String): Long = call {
        nativeGetFinalizedBlockAt(it, number.toULong().toLong())
    }
    fun resolveFinalizedBlock(hash: ByteArray, number: String): Long = call {
        nativeResolveFinalizedBlock(it, hash.requireSize(32, "block hash"), number.toULong().toLong())
    }
    fun getBlockHeader(block: CitizenBlockRef): Long = call {
        nativeGetBlockHeader(it, block.hash(), block.number.toULong().toLong(), block.finality.nativeValue())
    }
    fun getBlockBody(block: CitizenBlockRef): Long = call {
        nativeGetBlockBody(it, block.hash(), block.number.toULong().toLong(), block.finality.nativeValue())
    }
    fun getRuntimeContext(block: CitizenBlockRef): Long = call {
        nativeGetRuntimeContext(it, block.hash(), block.number.toULong().toLong(), block.finality.nativeValue())
    }
    fun getStorage(block: CitizenBlockRef, key: ByteArray): Long = call {
        nativeGetStorage(it, block.hash(), block.number.toULong().toLong(), block.finality.nativeValue(), key)
    }
    fun getStorageBatch(block: CitizenBlockRef, keys: Array<ByteArray>): Long = call {
        nativeGetStorageBatch(it, block.hash(), block.number.toULong().toLong(), block.finality.nativeValue(), keys)
    }
    fun getSystemEvents(block: CitizenBlockRef): Long = call {
        nativeGetSystemEvents(it, block.hash(), block.number.toULong().toLong(), block.finality.nativeValue())
    }
    fun exportState(): Long = call { nativeExportState(it) }
    fun importState(state: CitizenChainState): Long = call {
        nativeImportState(
            it, state.formatVersion.toInt(), state.finalized.hash(),
            state.finalized.number.toULong().toLong(), state.finalized.finality.nativeValue(),
            state.database(),
        )
    }
    fun getGenesisHash(): ByteArray = call { nativeGetGenesisHash(it) }
    fun getAccountBalance(accountId: ByteArray): Long = call { nativeGetAccountBalance(it, accountId) }
    fun getAccountBalances(accountIds: Array<ByteArray>): Long =
        call { nativeGetAccountBalances(it, flattenAccounts(accountIds), accountIds.size) }
    fun getAccountNonce(accountId: ByteArray): Long = call { nativeGetAccountNonce(it, accountId) }
    fun getFeeSnapshot(): Long = call { nativeGetFeeSnapshot(it) }
    fun getWalletProfile(): Long = call { nativeGetWalletProfile(it) }
    fun getWalletState(): Long = call { nativeGetWalletState(it) }
    fun importColdAccountId(accountId: ByteArray, name: String): Long =
        call { nativeImportColdAccountId(it, accountId, name.toByteArray(Charsets.UTF_8)) }
    fun importColdAccountSs58(address: String, name: String): Long = call {
        nativeImportColdAccountSs58(it, address.toByteArray(Charsets.UTF_8), name.toByteArray(Charsets.UTF_8))
    }
    fun reorderWalletAccounts(expectedRevision: Long, accountIds: Array<ByteArray>): Long =
        call { nativeReorderWalletAccounts(it, expectedRevision, flattenAccounts(accountIds), accountIds.size) }
    fun renameAnyAccount(accountId: ByteArray, name: String): Long =
        call { nativeRenameAccount(it, accountId, name.toByteArray(Charsets.UTF_8)) }
    fun deleteAnyAccount(accountId: ByteArray): Long = call { nativeDeleteAccount(it, accountId) }
    fun openPrivateKeyView(accountId: ByteArray, buffer: CitizenSdkPrivateKeyDisplayBuffer): LongArray =
        call { nativeOpenPrivateKeyView(it, accountId, buffer) }
    fun revealPrivateKeyView(viewId: Long) = call { nativeRevealPrivateKeyView(it, viewId) }
    fun cancelPrivateKeyView(viewId: Long) = call { nativeCancelPrivateKeyView(it, viewId) }
    fun finishPrivateKeyView(viewId: Long) = call { nativeFinishPrivateKeyView(it, viewId) }
    fun releasePrivateKeyViewContext(context: Long) = call { nativeReleasePrivateKeyViewContext(context) }
    fun validateWalletPassword(password: ByteArray) = call { nativeValidateWalletPassword(password) }
    fun validateWalletMnemonic(mnemonic: ByteArray, wordCount: Int) = call { nativeValidateWalletMnemonic(mnemonic, wordCount) }
    fun walletWordSuggestions(prefix: ByteArray): ByteArray = call { nativeWalletWordSuggestions(prefix) }
    fun setActiveWalletAccount(accountId: ByteArray): Long = call { nativeSetActiveWalletAccount(it, accountId) }
    fun renameWalletAccount(accountId: ByteArray, name: String): Long =
        call { nativeRenameWalletAccount(it, accountId, name.toByteArray(Charsets.UTF_8)) }
    fun deleteWalletAccount(accountId: ByteArray): Long = call { nativeDeleteWalletAccount(it, accountId) }
    fun deleteWallet(): Long = call { nativeDeleteWallet(it) }
    fun reconcileWalletCleanup(): Long = call { nativeReconcileWalletCleanup(it) }
    fun signWalletPayload(accountId: ByteArray, message: ByteArray): Long =
        call { nativeSignWalletPayload(it, accountId, message) }
    fun beginSigning(intent: CitizenSigningIntent): Long = call {
        nativeBeginSigning(
            it,
            intent.accountId(),
            intent.payload(),
            when (intent.transform) {
                CitizenSigningTransform.RAW -> 1
                CitizenSigningTransform.SUBSTRATE_SIGNING_PAYLOAD -> 2
                CitizenSigningTransform.BLAKE2_DOMAIN -> 3
            },
            intent.domain(),
            when (intent.externalSignerTransport) {
                null -> 0
                CitizenExternalSignerTransport.QR_V1 -> 1
            },
            intent.opaqueAction,
            intent.ttlSeconds,
        )
    }
    fun consumeExternalSignature(sessionId: String, response: String): Long = call {
        nativeConsumeExternalSignature(
            it,
            sessionId.toByteArray(Charsets.UTF_8),
            response.toByteArray(Charsets.UTF_8),
        )
    }
    fun cancelSigningSession(sessionId: String): Boolean = call {
        nativeCancelSigningSession(it, sessionId.toByteArray(Charsets.UTF_8))
    }
    fun beginDefaultAccountChange(
        expectedRevision: Long,
        accountIds: Array<ByteArray>,
        ttlSeconds: Long,
    ): Long = call {
        nativeBeginDefaultAccountChange(
            it, expectedRevision, flattenAccounts(accountIds), accountIds.size, ttlSeconds,
        )
    }
    fun consumeDefaultAccountChange(sessionId: String, response: String): Long = call {
        nativeConsumeDefaultAccountChange(
            it,
            sessionId.toByteArray(Charsets.UTF_8),
            response.toByteArray(Charsets.UTF_8),
        )
    }
    fun qrParse(text: String): CitizenQrDocument = call {
        CitizenQrDocument.parse(strictUtf8(nativeQrParse(it, text.toByteArray(Charsets.UTF_8))))
    }
    fun qrCreateSignRequest(action: Int, accountId: ByteArray, payload: ByteArray, ttl: Long): String =
        call { strictUtf8(nativeQrCreateSignRequest(it, action, accountId, payload, ttl)) }
    fun reviewQrSignRequest(text: String): Long = call { nativeReviewQrSignRequest(it, text.toByteArray(Charsets.UTF_8)) }
    fun signQrRequest(token: Long): Long = call { nativeSignQrRequest(it, token) }
    fun releaseQrReview(token: Long) = call { nativeReleaseQrReview(it, token) }
    fun qrConsumeSignResponse(text: String): ByteArray =
        call { nativeQrConsumeSignResponse(it, text.toByteArray(Charsets.UTF_8)).also { bytes -> check(bytes.size == 64) } }
    fun qrCancelSignRequest(requestId: String): Boolean =
        call { nativeQrCancelSignRequest(it, requestId.toByteArray(Charsets.UTF_8)) }
    fun qrEncodeAccountId(accountId: ByteArray): String =
        call { strictUtf8(nativeQrEncodeAccountId(it, accountId)) }
    fun qrEncodeUserTransfer(
        requestId: String, expiresAt: Long, accountId: ByteArray, amount: String,
        symbol: String, memo: String, bankCidNumber: String,
    ): String = call {
        strictUtf8(nativeQrEncodeUserTransfer(
            it, requestId.toByteArray(Charsets.UTF_8), expiresAt, accountId,
            amount.toByteArray(Charsets.UTF_8), symbol.toByteArray(Charsets.UTF_8),
            memo.toByteArray(Charsets.UTF_8), bankCidNumber.toByteArray(Charsets.UTF_8),
        ))
    }
    fun qrDecodeLuminance(data: ByteArray, width: Int, height: Int, rowStride: Int): CitizenQrDocument =
        qrParse(call { strictUtf8(nativeQrDecodeLuminance(it, data, width, height, rowStride)) })
    fun qrEncode(text: String, scale: Int): CitizenQrImage = call {
        val encoded = nativeQrEncode(it, text.toByteArray(Charsets.UTF_8), scale)
        require(encoded.size >= 8) { "QR image result is truncated" }
        val header = ByteBuffer.wrap(encoded, 0, 8).order(ByteOrder.LITTLE_ENDIAN)
        val width = header.int
        val height = header.int
        require(width in 1..4096 && height in 1..4096 && encoded.size - 8 == width * height) {
            "QR image result dimensions are invalid"
        }
        CitizenQrImage(width, height, encoded.copyOfRange(8, encoded.size))
    }
    fun prepareTransaction(source: ByteArray, callData: ByteArray): Long =
        call { nativePrepareTransaction(it, source, callData) }
    fun releasePreparedTransaction(token: Long) =
        call { nativeReleasePreparedTransaction(it, token) }
    fun executePreparedTransaction(token: Long): Long =
        call { nativeExecutePreparedTransaction(it, token) }
    fun consumePreparedTransactionQrResponse(executionId: ByteArray, response: ByteArray): Long =
        call { nativeConsumePreparedTransactionQrResponse(it, executionId, response) }
    fun cancelPreparedTransactionExecution(executionId: ByteArray) =
        call { nativeCancelPreparedTransactionExecution(it, executionId) }
    fun getTransactionHistory(beforeExecutionId: ByteArray?, limit: Int): Long =
        call { nativeGetTransactionHistory(it, beforeExecutionId, limit) }
    fun syncTransactionHistory(): Long = call { nativeSyncTransactionHistory(it) }
    fun prepareWalletCreation(wordCount: Int, password: ByteArray): Long =
        call { nativePrepareWalletCreation(it, wordCount, password) }
    fun importWallet(mnemonic: ByteArray, password: ByteArray): Long =
        call { nativeImportWallet(it, mnemonic, password) }
    fun addWalletAccounts(mnemonic: ByteArray, password: ByteArray, indices: IntArray): Long =
        call { nativeAddWalletAccounts(it, mnemonic, password, indices) }
    fun copyPreparedMnemonic(token: Long): ByteArray = call { nativeCopyPreparedMnemonic(it, token) }
    fun commitPreparedWallet(token: Long): Long = call { nativeCommitPreparedWallet(it, token) }
    fun releasePreparedWallet(token: Long) {
        // 只有成功 destroy 才能把迟到的释放视为已完成；closing 仍明确拒绝。
        if (!calls.isClosed()) call { nativeReleasePreparedWallet(it, token) }
    }

    @Suppress("unused") // Called only by citizensdk_jni.
    private fun onNativeRequestCompleted(coreRequestId: Long, encoded: ByteArray): Boolean {
        var accepted = true
        val decoded = try {
            CitizenSdkNativeCodec.decode(encoded)
        } catch (error: Throwable) {
            accepted = false
            CitizenSdkNativeCodec.Decoded(
                result = null,
                error = CitizenSdkException(
                    CitizenSdkErrorCode.INTEGRITY,
                    "CitizenSDK returned a malformed result envelope",
                    error,
                ),
            )
        }
        val target = router ?: return false
        target.onCompletion(coreRequestId, decoded)
        return accepted
    }

    @Suppress("unused") // Called only by citizensdk_jni.
    private fun onNativeWatch(coreRequestId: Long, sequence: Long, encoded: ByteArray) = Unit

    @Suppress("unused") // Called only by citizensdk_jni.
    private fun onNativeCapabilities(sequence: Long, encoded: ByteArray) {
        eventSink?.invoke(
            CitizenSdkEvents.Event.CapabilitiesChanged(
                java.lang.Long.toUnsignedString(sequence),
                CitizenSdkNativeCodec.decodeCapabilities(encoded),
            ),
        )
    }

    @Suppress("unused") // Called only by citizensdk_jni.
    private fun onNativeLifecycle(sequence: Long, lifecycle: Int) {
        eventSink?.invoke(
            CitizenSdkEvents.Event.LifecycleChanged(
                java.lang.Long.toUnsignedString(sequence),
                lifecycleFromValue(lifecycle),
            ),
        )
    }

    @Suppress("unused") // Called only by citizensdk_jni.
    private fun onNativeHistoryChanged(sequence: Long) {
        if (!calls.isClosed()) eventSink?.invoke(
            CitizenSdkEvents.Event.HistoryChanged(java.lang.Long.toUnsignedString(sequence)),
        )
    }

    override fun close() {
        calls.close {
            nativeDestroy(bridge)
            router = null
            eventSink = null
        }
    }

    /** JNI 调用持有短期 lease；等待 Rust 回调屏障时不持有重入调用需要的锁。 */
    private fun <T> call(block: (Long) -> T): T = calls.call { block(bridge) }

    private fun flattenAccounts(values: Array<ByteArray>): ByteArray =
        ByteArray(values.size * 32).also { output ->
            values.forEachIndexed { index, value -> value.copyInto(output, index * 32) }
        }

    private fun lifecycleFromValue(value: Int): CitizenSdkLifecycle = when (value) {
        1 -> CitizenSdkLifecycle.CREATED
        2 -> CitizenSdkLifecycle.IMPORTING_STATE
        3 -> CitizenSdkLifecycle.STARTING
        4 -> CitizenSdkLifecycle.RUNNING
        5 -> CitizenSdkLifecycle.START_FAILED
        6 -> CitizenSdkLifecycle.STOPPED
        7 -> CitizenSdkLifecycle.DISPOSED
        else -> throw CitizenSdkException(CitizenSdkErrorCode.INTEGRITY, "unknown Core lifecycle $value")
    }

    private fun strictUtf8(value: ByteArray): String = StandardCharsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(value)).toString()

    private external fun nativeCreate(
        hostServices: CitizenSdkHostServices,
        manifest: ByteArray,
        chainSpec: ByteArray,
        lightSyncState: ByteArray,
        modules: Int,
    ): Long
    private external fun nativeBind(bridge: Long)
    private external fun nativeLifecycle(bridge: Long): Int
    private external fun nativeCapabilities(bridge: Long): ByteArray
    private external fun nativeRefreshCapabilities(bridge: Long): Long
    private external fun nativeStart(bridge: Long): Long
    private external fun nativeStop(bridge: Long): Long
    private external fun nativeCancel(bridge: Long, coreRequestId: Long): Boolean
    private external fun nativeGetFinalizedHead(bridge: Long): Long
    private external fun nativeGetSyncStatus(bridge: Long): Long
    private external fun nativeGetBestHead(bridge: Long): Long
    private external fun nativeGetFinalizedBlockAt(bridge: Long, number: Long): Long
    private external fun nativeResolveFinalizedBlock(bridge: Long, hash: ByteArray, number: Long): Long
    private external fun nativeGetBlockHeader(bridge: Long, hash: ByteArray, number: Long, finality: Int): Long
    private external fun nativeGetBlockBody(bridge: Long, hash: ByteArray, number: Long, finality: Int): Long
    private external fun nativeGetRuntimeContext(bridge: Long, hash: ByteArray, number: Long, finality: Int): Long
    private external fun nativeGetStorage(bridge: Long, hash: ByteArray, number: Long, finality: Int, key: ByteArray): Long
    private external fun nativeGetStorageBatch(bridge: Long, hash: ByteArray, number: Long, finality: Int, keys: Array<ByteArray>): Long
    private external fun nativeGetSystemEvents(bridge: Long, hash: ByteArray, number: Long, finality: Int): Long
    private external fun nativeExportState(bridge: Long): Long
    private external fun nativeImportState(bridge: Long, formatVersion: Int, hash: ByteArray, number: Long, finality: Int, database: ByteArray): Long
    private external fun nativeGetGenesisHash(bridge: Long): ByteArray
    private external fun nativeGetAccountBalance(bridge: Long, accountId: ByteArray): Long
    private external fun nativeGetAccountBalances(bridge: Long, accountIds: ByteArray, count: Int): Long
    private external fun nativeGetAccountNonce(bridge: Long, accountId: ByteArray): Long
    private external fun nativeGetFeeSnapshot(bridge: Long): Long
    private external fun nativeGetWalletProfile(bridge: Long): Long
    private external fun nativeGetWalletState(bridge: Long): Long
    private external fun nativeImportColdAccountId(bridge: Long, accountId: ByteArray, name: ByteArray): Long
    private external fun nativeImportColdAccountSs58(bridge: Long, address: ByteArray, name: ByteArray): Long
    private external fun nativeReorderWalletAccounts(bridge: Long, expectedRevision: Long, accountIds: ByteArray, count: Int): Long
    private external fun nativeRenameAccount(bridge: Long, accountId: ByteArray, name: ByteArray): Long
    private external fun nativeDeleteAccount(bridge: Long, accountId: ByteArray): Long
    private external fun nativeOpenPrivateKeyView(bridge: Long, accountId: ByteArray, buffer: CitizenSdkPrivateKeyDisplayBuffer): LongArray
    private external fun nativeRevealPrivateKeyView(bridge: Long, viewId: Long)
    private external fun nativeCancelPrivateKeyView(bridge: Long, viewId: Long)
    private external fun nativeFinishPrivateKeyView(bridge: Long, viewId: Long)
    private external fun nativeReleasePrivateKeyViewContext(context: Long)
    private external fun nativeSetActiveWalletAccount(bridge: Long, accountId: ByteArray): Long
    private external fun nativeRenameWalletAccount(bridge: Long, accountId: ByteArray, name: ByteArray): Long
    private external fun nativeDeleteWalletAccount(bridge: Long, accountId: ByteArray): Long
    private external fun nativeDeleteWallet(bridge: Long): Long
    private external fun nativeReconcileWalletCleanup(bridge: Long): Long
    private external fun nativeSignWalletPayload(bridge: Long, accountId: ByteArray, message: ByteArray): Long
    private external fun nativeBeginSigning(
        bridge: Long,
        accountId: ByteArray,
        payload: ByteArray,
        transform: Int,
        domain: ByteArray,
        externalSignerTransport: Int,
        opaqueAction: Int,
        ttlSeconds: Long,
    ): Long
    private external fun nativeConsumeExternalSignature(
        bridge: Long,
        sessionId: ByteArray,
        response: ByteArray,
    ): Long
    private external fun nativeCancelSigningSession(bridge: Long, sessionId: ByteArray): Boolean
    private external fun nativeBeginDefaultAccountChange(
        bridge: Long,
        expectedRevision: Long,
        accountIds: ByteArray,
        count: Int,
        ttlSeconds: Long,
    ): Long
    private external fun nativeConsumeDefaultAccountChange(
        bridge: Long,
        sessionId: ByteArray,
        response: ByteArray,
    ): Long
    private external fun nativeQrParse(bridge: Long, text: ByteArray): ByteArray
    private external fun nativeQrCreateSignRequest(bridge: Long, action: Int, accountId: ByteArray, payload: ByteArray, ttl: Long): ByteArray
    private external fun nativeReviewQrSignRequest(bridge: Long, text: ByteArray): Long
    private external fun nativeSignQrRequest(bridge: Long, token: Long): Long
    private external fun nativeReleaseQrReview(bridge: Long, token: Long)
    private external fun nativeQrConsumeSignResponse(bridge: Long, text: ByteArray): ByteArray
    private external fun nativeQrCancelSignRequest(bridge: Long, requestId: ByteArray): Boolean
    private external fun nativeQrEncodeAccountId(bridge: Long, accountId: ByteArray): ByteArray
    private external fun nativeQrEncodeUserTransfer(bridge: Long, requestId: ByteArray, expiresAt: Long, accountId: ByteArray, amount: ByteArray, symbol: ByteArray, memo: ByteArray, bankCidNumber: ByteArray): ByteArray
    private external fun nativeQrDecodeLuminance(bridge: Long, data: ByteArray, width: Int, height: Int, rowStride: Int): ByteArray
    private external fun nativeQrEncode(bridge: Long, text: ByteArray, scale: Int): ByteArray
    private external fun nativePrepareTransaction(
        bridge: Long,
        source: ByteArray,
        callData: ByteArray,
    ): Long
    private external fun nativeReleasePreparedTransaction(bridge: Long, token: Long)
    private external fun nativeExecutePreparedTransaction(bridge: Long, token: Long): Long
    private external fun nativeConsumePreparedTransactionQrResponse(
        bridge: Long, executionId: ByteArray, response: ByteArray,
    ): Long
    private external fun nativeCancelPreparedTransactionExecution(bridge: Long, executionId: ByteArray)
    private external fun nativeGetTransactionHistory(bridge: Long, beforeExecutionId: ByteArray?, limit: Int): Long
    private external fun nativeSyncTransactionHistory(bridge: Long): Long
    private external fun nativePrepareWalletCreation(bridge: Long, wordCount: Int, password: ByteArray): Long
    private external fun nativeValidateWalletPassword(password: ByteArray)
    private external fun nativeValidateWalletMnemonic(mnemonic: ByteArray, wordCount: Int)
    private external fun nativeWalletWordSuggestions(prefix: ByteArray): ByteArray
    private external fun nativeImportWallet(bridge: Long, mnemonic: ByteArray, password: ByteArray): Long
    private external fun nativeAddWalletAccounts(
        bridge: Long,
        mnemonic: ByteArray,
        password: ByteArray,
        indices: IntArray,
    ): Long
    private external fun nativeCopyPreparedMnemonic(bridge: Long, token: Long): ByteArray
    private external fun nativeCommitPreparedWallet(bridge: Long, token: Long): Long
    private external fun nativeReleasePreparedWallet(bridge: Long, token: Long)
    private external fun nativeDestroy(bridge: Long)

    companion object {
        init { System.loadLibrary("citizensdk_jni") }

        internal fun create(
            assets: CitizenSdkAssets?,
            hostServices: CitizenSdkHostServices,
            modules: Int = CitizenSdkModules.FULL,
        ): CitizenSdkNative = CitizenSdkNative(assets, hostServices, modules)

        @JvmStatic
        internal external fun validateModules(modules: Int)

        @JvmStatic
        internal external fun verifySignature(accountId: ByteArray, signature: ByteArray, message: ByteArray): Boolean

        @JvmStatic
        internal external fun completeVaultUnwrap(nativeBridge: Long, hostOperationId: Long, errorCode: Int)
    }
}

private fun CitizenFinality.nativeValue(): Int = when (this) {
    CitizenFinality.BEST -> 1
    CitizenFinality.FINALIZED -> 2
}

/** 唯一 native 调用/销毁准入状态。失败后保持 closing，只允许精确重试销毁。 */
internal class CitizenSdkNativeCalls {
    private val gate = Any()
    private var active = 0
    private var closing = false
    private var destroying = false
    private var closed = false

    fun isClosed(): Boolean = synchronized(gate) { closed }

    fun <T> call(body: () -> T): T {
        synchronized(gate) {
            check(!closing && !closed) { "CitizenSDK native bridge is closing or closed" }
            active += 1
        }
        try { return body() }
        finally { synchronized(gate) { active -= 1 } }
    }

    fun close(destroy: () -> Unit) {
        synchronized(gate) {
            if (closed) return
            if (destroying || active != 0) throw CitizenSdkException(
                CitizenSdkErrorCode.BUSY, "CitizenSDK native call or close is active",
            )
            closing = true
            destroying = true
        }
        try {
            // 禁止在 gate 内等待 callback-clear：回调可能同步重入 call/close。
            destroy()
            synchronized(gate) { closed = true }
        } finally {
            synchronized(gate) { destroying = false }
        }
    }
}
