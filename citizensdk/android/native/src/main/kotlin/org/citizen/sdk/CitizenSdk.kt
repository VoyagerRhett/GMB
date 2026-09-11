package org.citizen.sdk

import android.content.Context
import androidx.fragment.app.FragmentActivity
import org.citizen.sdk.internal.CitizenSdkAssets
import org.citizen.sdk.internal.CitizenSdkHostServices
import org.citizen.sdk.internal.CitizenSdkNative
import org.citizen.sdk.internal.CitizenSdkNativeCodec
import org.citizen.sdk.internal.CitizenSdkNativeResult
import org.citizen.sdk.internal.CitizenSdkRequestRouter
import org.citizen.sdk.ui.CitizenSdkWalletFlowContract
import org.citizen.sdk.ui.CitizenSdkWalletFlowCoordinator
import org.citizen.sdk.ui.CitizenSdkPrivateKeyDisplayBuffer
import org.citizen.sdk.ui.CitizenSdkQrCoordinator
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException
import java.util.concurrent.ExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.ConcurrentHashMap

/**
 * Java/Kotlin facade for the one CitizenSDK Core instance.
 *
 * The facade exposes public chain facts and wallet operations. Native handles,
 * result handles, prepared-wallet handles, recovery phrases and passwords are
 * deliberately absent from this surface.
 */
class CitizenSdk private constructor(
    context: Context,
    listener: CitizenSdkEvents.Listener?,
    modules: Int,
) : AutoCloseable {
    val sessionId: String = UUID.randomUUID().toString()

    private val lifecycleGate = Any()
    private val closed = AtomicBoolean(false)
    private val selectedModules = modules
    private val closing = AtomicBoolean(false)
    private var closeActive = false
    private val hostServices = CitizenSdkHostServices(context.applicationContext, modules)
    private val native = CitizenSdkNative.create(
        assets = if (modules and CitizenSdkModules.CHAIN != 0) CitizenSdkAssets.load(context.applicationContext) else null,
        modules = modules,
        hostServices = hostServices,
    )
    private val requests = CitizenSdkRequestRouter(native::cancel) {
        if (it is CitizenSdkNativeResult.QrReview) native.releaseQrReview(it.token)
    }
    /** Only native handles are retained; the public preparation identity is never a Core handle. */
    private val preparedTransactions = ConcurrentHashMap<String, Long>()

    @Volatile
    private var eventListener: CitizenSdkEvents.Listener? = listener

    @Volatile
    var lifecycle: CitizenSdkLifecycle = native.lifecycle()
        private set

    // Dynamic Activity readiness is a generation, not an untracked fire-and-
    // forget request. Edges coalesce; BUSY retries after the accepted request
    // that owns the exclusive Core gate reaches terminal completion.
    private var readinessDesiredGeneration = 0L
    private var readinessAppliedGeneration = 0L
    private var readinessInFlight = false
    private var readinessRetryPending = false
    private var readinessConvergence = CompletableFuture.completedFuture<Void>(null)

    init {
        try {
            native.bind(requests) { event ->
                if (event is CitizenSdkEvents.Event.LifecycleChanged) {
                    lifecycle = event.lifecycle
                }
                eventListener?.onEvent(event)
            }
            hostServices.setActivityReadinessListener {
                readinessChanged()
            }
            readinessChanged()
        } catch (error: Throwable) {
            runCatching { native.close() }
            runCatching { requests.close() }
            runCatching { hostServices.close() }
            closed.set(true)
            throw error
        }
    }

    fun setEventListener(listener: CitizenSdkEvents.Listener?) {
        synchronized(lifecycleGate) {
            requireOpen()
            eventListener = listener
        }
    }

    fun attachActivity(activity: FragmentActivity) {
        synchronized(lifecycleGate) {
            requireOpen()
            hostServices.attachActivity(activity)
        }
    }

    fun detachActivity(activity: FragmentActivity) {
        synchronized(lifecycleGate) {
            if (!closed.get()) hostServices.detachActivity(activity)
        }
    }

    fun start(): CompletableFuture<Void> = exclusiveAfterReadiness { native.start() }

    fun stop(): CompletableFuture<Void> = exclusiveAfterReadiness { native.stop() }

    fun getCapabilities(): CitizenSdkCapabilities {
        return synchronized(lifecycleGate) {
            requireOpen()
            native.capabilities()
        }
    }

    fun getFinalizedHead(): CompletableFuture<CitizenBlockRef> =
        request({ native.getFinalizedHead() }) { (it as CitizenSdkNativeResult.Block).value }

    fun getSyncStatus(): CompletableFuture<CitizenChainSyncStatus> =
        request({ native.getSyncStatus() }) { (it as CitizenSdkNativeResult.SyncStatus).value }

    fun getBestHead(): CompletableFuture<CitizenBlockRef> =
        request({ native.getBestHead() }) { (it as CitizenSdkNativeResult.Block).value }

    fun getFinalizedBlockAt(number: String): CompletableFuture<CitizenBlockRef> {
        requireU64(number, "block number")
        return request({ native.getFinalizedBlockAt(number) }) {
            (it as CitizenSdkNativeResult.Block).value
        }
    }

    fun resolveFinalizedBlock(hash: ByteArray, number: String): CompletableFuture<CitizenBlockRef> {
        requireU64(number, "block number")
        val checkedHash = hash.requireSize(32, "block hash")
        return request({ native.resolveFinalizedBlock(checkedHash, number) }) {
            (it as CitizenSdkNativeResult.Block).value
        }
    }

    fun getBlockHeader(block: CitizenBlockRef): CompletableFuture<CitizenBlockHeader> =
        request({ native.getBlockHeader(block) }) { (it as CitizenSdkNativeResult.BlockHeader).value }

    fun getBlockBody(block: CitizenBlockRef): CompletableFuture<CitizenBlockBody> =
        request({ native.getBlockBody(block) }) { (it as CitizenSdkNativeResult.BlockBody).value }

    fun getRuntimeContext(block: CitizenBlockRef): CompletableFuture<CitizenRuntimeContext> =
        request({ native.getRuntimeContext(block) }) { (it as CitizenSdkNativeResult.RuntimeContext).value }

    fun getStorage(block: CitizenBlockRef, key: ByteArray): CompletableFuture<ByteArray?> {
        CitizenSdkInputLimits.requireStorageKey(key)
        val copied = key.clone()
        return request({ native.getStorage(block, copied) }) {
            (it as CitizenSdkNativeResult.Storage).value?.clone()
        }
    }

    fun getStorageBatch(block: CitizenBlockRef, keys: List<ByteArray>): CompletableFuture<List<ByteArray?>> {
        CitizenSdkInputLimits.requireStorageKeys(keys)
        val copied = keys.map(ByteArray::clone).toTypedArray()
        return request({ native.getStorageBatch(block, copied) }) {
            (it as CitizenSdkNativeResult.StorageBatch).value.map { value -> value?.clone() }
        }
    }

    fun getSystemEvents(finalizedBlock: CitizenBlockRef): CompletableFuture<ByteArray?> {
        require(finalizedBlock.finality == CitizenFinality.FINALIZED) { "System.Events requires finalized block" }
        return request({ native.getSystemEvents(finalizedBlock) }) {
            (it as CitizenSdkNativeResult.Storage).value?.clone()
        }
    }

    fun exportState(): CompletableFuture<CitizenChainState> =
        request({ native.exportState() }) { (it as CitizenSdkNativeResult.ChainState).value }

    fun importState(state: CitizenChainState): CompletableFuture<Void> {
        require(state.formatVersion in 1..0xffff_ffffL) { "chain state formatVersion is invalid" }
        require(state.finalized.finality == CitizenFinality.FINALIZED) { "chain state anchor must be finalized" }
        require(state.database().size in 1..256 * 1024) { "chain state database is invalid" }
        val source = request({ native.importState(state) }) {
            val imported = (it as? CitizenSdkNativeResult.Block)?.value ?: throw CitizenSdkException(
                CitizenSdkErrorCode.INTEGRITY,
                "Core returned a non-block result for state import",
            )
            if (imported.finality != CitizenFinality.FINALIZED ||
                imported.number != state.finalized.number ||
                !imported.hash().contentEquals(state.finalized.hash())
            ) throw CitizenSdkException(
                CitizenSdkErrorCode.INTEGRITY,
                "Core imported-state receipt does not match its finalized anchor",
            )
            Unit
        }
        val target = CompletableFuture<Void>()
        source.whenComplete { _, error ->
            if (error == null) target.complete(null) else target.completeExceptionally(error)
        }
        return target
    }

    /** 返回 Core 固定链身份，不要求轻节点启动或同步，也不读取钱包金库。 */
    fun getGenesisHash(): ByteArray = synchronized(lifecycleGate) {
        requireOpen()
        native.getGenesisHash().requireSize(32, "genesisHash")
    }

    fun getAccountBalance(accountId: ByteArray): CompletableFuture<CitizenAccountBalance> =
        request({ native.getAccountBalance(accountId.requireSize(32, "accountId")) }) {
            (it as CitizenSdkNativeResult.Balance).value
        }

    /** 同一已验证 finalized 块的批量余额；保留顺序和重复项，空列表仍提交 Core。 */
    fun getAccountBalances(accountIds: List<ByteArray>): CompletableFuture<List<CitizenAccountBalance>> {
        CitizenSdkInputLimits.requireBalanceAccountCount(accountIds.size)
        val checked = accountIds.map { it.requireSize(32, "accountId") }.toTypedArray()
        return request({ native.getAccountBalances(checked) }) {
            val values = (it as? CitizenSdkNativeResult.Balances)?.value
                ?: throw CitizenSdkException(CitizenSdkErrorCode.INTEGRITY, "Core returned an invalid balance result kind")
            CitizenSdkNativeCodec.validateBalances(values, checked)
        }
    }

    fun getAccountNonce(accountId: ByteArray): CompletableFuture<CitizenAccountNonce> =
        request({ native.getAccountNonce(accountId.requireSize(32, "accountId")) }) {
            (it as CitizenSdkNativeResult.Nonce).value
        }

    fun getFeeSnapshot(): CompletableFuture<CitizenFeeSnapshot> =
        request({ native.getFeeSnapshot() }) { (it as CitizenSdkNativeResult.Fee).value }

    fun getWalletProfile(): CompletableFuture<CitizenWalletProfile?> =
        request({ native.getWalletProfile() }) { (it as CitizenSdkNativeResult.Profile).value }

    /** Stable secret-free hot/cold catalog; its first item is the default account. */
    fun getWalletState(): CompletableFuture<CitizenWalletState> =
        request({ native.getWalletState() }) { (it as CitizenSdkNativeResult.WalletState).value }

    fun importColdAccount(accountId: ByteArray, name: String): CompletableFuture<CitizenWalletState> {
        val normalized = checkedAccountName(name)
        return walletMutation {
            request({ native.importColdAccountId(accountId.requireSize(32, "accountId"), normalized) }) {
                (it as CitizenSdkNativeResult.WalletState).value
            }
        }
    }

    fun importColdAccount(ss58Address: String, name: String): CompletableFuture<CitizenWalletState> {
        require(ss58Address.isNotEmpty() && ss58Address.toByteArray(Charsets.UTF_8).size <= 64) {
            "cold account SS58 is invalid"
        }
        val normalized = checkedAccountName(name)
        return walletMutation {
            request({ native.importColdAccountSs58(ss58Address, normalized) }) {
                (it as CitizenSdkNativeResult.WalletState).value
            }
        }
    }

    fun reorderWalletAccountsWithoutDefaultChange(
        expectedRevision: String,
        accountIds: List<ByteArray>,
    ): CompletableFuture<CitizenWalletState> {
        require(accountIds.size in 1..3980) { "wallet catalog must contain 1..3980 accounts" }
        val revision = java.lang.Long.parseUnsignedLong(expectedRevision)
        val checked = accountIds.map { it.requireSize(32, "accountId") }.toTypedArray()
        return walletMutation {
            request({ native.reorderWalletAccounts(revision, checked) }) {
                (it as CitizenSdkNativeResult.WalletState).value
            }
        }
    }

    fun renameAccount(accountId: ByteArray, name: String): CompletableFuture<CitizenWalletState> {
        val normalized = checkedAccountName(name)
        return walletMutation {
            request({ native.renameAnyAccount(accountId.requireSize(32, "accountId"), normalized) }) {
                (it as CitizenSdkNativeResult.WalletState).value
            }
        }
    }

    fun deleteAccount(accountId: ByteArray): CompletableFuture<CitizenWalletState> = walletMutation {
        request({ native.deleteAnyAccount(accountId.requireSize(32, "accountId")) }) {
            (it as CitizenSdkNativeResult.WalletState).value
        }
    }

    fun setActiveWalletAccount(accountId: ByteArray): CompletableFuture<CitizenWalletProfile> =
        walletMutation {
            request({ native.setActiveWalletAccount(accountId.requireSize(32, "accountId")) }) {
                requireWalletProfile(it, "set active wallet account")
            }
        }

    fun renameWalletAccount(accountId: ByteArray, name: String): CompletableFuture<CitizenWalletProfile> {
        CitizenSdkInputLimits.requireWalletAccountNameInput(name)
        require(name.codePoints().noneMatch { value ->
            value in 0x00..0x1f || value in 0x7f..0x9f
        }) { "wallet account name must not contain control characters" }
        val normalized = name.trim()
        require(normalized.codePointCount(0, normalized.length) in 1..30) {
            "wallet account name must contain 1..30 Unicode scalars"
        }
        return walletMutation {
            request({
                native.renameWalletAccount(accountId.requireSize(32, "accountId"), normalized)
            }) {
                requireWalletProfile(it, "rename wallet account")
            }
        }
    }

    /** Atomically returns the post-delete profile under the process mutation gate. */
    fun deleteWalletAccount(accountId: ByteArray): CompletableFuture<CitizenWalletProfile?> =
        walletMutationWithProfile {
            native.deleteWalletAccount(accountId.requireSize(32, "accountId"))
        }

    /** Returns `null` only after Core deletion and the same gated profile read complete. */
    fun deleteWallet(): CompletableFuture<CitizenWalletProfile?> =
        walletMutationWithProfile { native.deleteWallet() }

    /** Returns the post-reconciliation profile without a host-side query window. */
    fun reconcileWalletCleanup(): CompletableFuture<CitizenWalletProfile?> =
        walletMutationWithProfile { native.reconcileWalletCleanup() }

    /** 通用签名只接收不透明载荷；应用业务语义不会进入 SDK。 */
    val signing = CitizenSigning.create(
        ::sign,
        ::beginSigning,
        ::consumeExternalSignature,
        ::cancelSigningSession,
    )

    /**
     * SDK 钱包的默认账户变更。完整有序账户集由旧默认账户授权；应用不能指定
     * 签名者、签名域、QR action 或绕过 CAS 直接设置默认账户。
     */
    fun beginDefaultAccountChange(
        expectedRevision: String,
        orderedAccountIds: List<ByteArray>,
        ttlSeconds: Long = 120,
    ): CompletableFuture<CitizenDefaultAccountChangeOutcome> {
        require(orderedAccountIds.size in 1..256) {
            "default-account change must contain 1..256 accounts"
        }
        require(ttlSeconds in 1..300) { "ttlSeconds must be in 1..300" }
        val revision = java.lang.Long.parseUnsignedLong(expectedRevision)
        val checked = orderedAccountIds.map {
            it.requireSize(32, "accountId")
        }.toTypedArray()
        return walletMutation {
            request({ native.beginDefaultAccountChange(revision, checked, ttlSeconds) }) {
                (it as? CitizenSdkNativeResult.DefaultAccountChange)?.value
                    ?: throw CitizenSdkException(
                        CitizenSdkErrorCode.INTEGRITY,
                        "Core returned an invalid default-account-change result kind",
                    )
            }
        }
    }

    fun consumeDefaultAccountChange(
        sessionId: String,
        response: String,
    ): CompletableFuture<CitizenDefaultAccountChangeOutcome> {
        requireExternalSigningText(sessionId, response)
        return walletMutation {
            request({ native.consumeDefaultAccountChange(sessionId, response) }) {
                (it as? CitizenSdkNativeResult.DefaultAccountChange)?.value
                    ?: throw CitizenSdkException(
                        CitizenSdkErrorCode.INTEGRITY,
                        "Core returned an invalid default-account-change result kind",
                    )
            }
        }
    }

    /** QR 协议与会话都由 Rust 处理；图像编解码在五端共同使用 ZXing-C++。 */
    fun qrParse(text: String): CitizenQrDocument =
        synchronized(lifecycleGate) { requireOpen(); native.qrParse(text) }

    fun qrCreateSignRequest(
        action: Int, signerAccountId: ByteArray, reviewPayload: ByteArray, ttlSeconds: Long,
    ): String = synchronized(lifecycleGate) {
        requireOpen()
        native.qrCreateSignRequest(action, signerAccountId.requireSize(32, "signerAccountId"), reviewPayload.clone(), ttlSeconds)
    }

    fun qrConsumeSignResponse(text: String): ByteArray =
        synchronized(lifecycleGate) { requireOpen(); native.qrConsumeSignResponse(text) }

    fun qrCancelSignRequest(requestId: String): Boolean =
        synchronized(lifecycleGate) { requireOpen(); native.qrCancelSignRequest(requestId) }

    fun qrEncodeAccountId(accountId: ByteArray): String =
        synchronized(lifecycleGate) { requireOpen(); native.qrEncodeAccountId(accountId.requireSize(32, "accountId")) }

    fun qrDecodeLuminance(data: ByteArray, width: Int, height: Int, rowStride: Int): CitizenQrDocument =
        synchronized(lifecycleGate) {
            requireOpen(); requireQrModule()
            native.qrDecodeLuminance(data.clone(), width, height, rowStride)
        }

    fun qrEncode(text: String, scale: Int = 4): CitizenQrImage =
        synchronized(lifecycleGate) {
            requireOpen(); requireQrModule()
            native.qrEncode(text, scale)
        }

    /** 完整相机界面只需要 QR 模块；不会初始化钱包、金库或启动轻节点。 */
    fun qrScan(activity: FragmentActivity): CitizenSdkOperation<CitizenQrDocument> = launchQr(activity, null)

    /** SDK 展示完整 Core 审阅、确认后安全签名，并直接提供响应二维码图像。 */
    fun signQrRequest(activity: FragmentActivity, text: String): CitizenSdkOperation<CitizenQrSigned> {
        val operation = launchQr(activity, text)
        return CitizenSdkOperation(operation.operationId, operation.future.thenApply {
            CitizenQrSigned(it, checkNotNull(it.signedImage) { "签名二维码结果缺失" })
        }, operation::cancel)
    }

    private fun launchQr(activity: FragmentActivity, text: String?): CitizenSdkOperation<CitizenQrDocument> =
        synchronized(lifecycleGate) {
            requireOpen(); requireQrModule()
            CitizenSdkWalletFlowCoordinator.requireCloseReady(this)
            CitizenSdkQrCoordinator.launch(this, activity, text)
        }

    @JvmSynthetic
    internal fun reviewQrSignRequest(text: String): CitizenSdkOperation<CitizenSdkQrReview> =
        synchronized(lifecycleGate) {
            requireOpen()
            requests.submitOperation({ native.reviewQrSignRequest(text) }, {
                check(it is CitizenSdkNativeResult.QrReview)
                CitizenSdkQrReview(native, it.token, it.json)
            })
        }

    @JvmSynthetic
    internal fun signQrReview(review: CitizenSdkQrReview): CitizenSdkOperation<CitizenQrDocument> =
        synchronized(lifecycleGate) {
            requireOpen()
            val operation = review.withHandle { token ->
                requests.submitOperation({ native.signQrRequest(token) }, {
                    check(it is CitizenSdkNativeResult.QrSigned); it.value
                })
            }
            review.close()
            operation.future.whenComplete { _, _ -> readinessBoundaryCompleted() }
            operation
        }

    private fun requireQrModule() {
        if (selectedModules and CitizenSdkModules.QR == 0) throw CitizenSdkException(
            CitizenSdkErrorCode.UNSUPPORTED, "CitizenSDK QR module is not enabled",
        )
    }

    private fun sign(accountId: ByteArray, message: ByteArray): CompletableFuture<CitizenSignature> {
        CitizenSdkInputLimits.requireSignPayload(message.size)
        return request({
            native.signWalletPayload(accountId.requireSize(32, "accountId"), message.clone())
        }) { (it as CitizenSdkNativeResult.Signature).value }
    }

    private fun beginSigning(intent: CitizenSigningIntent): CompletableFuture<CitizenSigningOutcome> =
        request({ native.beginSigning(intent) }) {
            (it as? CitizenSdkNativeResult.SigningOutcome)?.value
                ?: throw CitizenSdkException(
                    CitizenSdkErrorCode.INTEGRITY,
                    "Core returned an invalid signing result kind",
                )
        }

    private fun consumeExternalSignature(
        sessionId: String,
        response: String,
    ): CompletableFuture<CitizenSigningOutcome> {
        requireExternalSigningText(sessionId, response)
        return request({ native.consumeExternalSignature(sessionId, response) }) {
            (it as? CitizenSdkNativeResult.SigningOutcome)?.value
                ?: throw CitizenSdkException(
                    CitizenSdkErrorCode.INTEGRITY,
                    "Core returned an invalid signing result kind",
                )
        }
    }

    private fun cancelSigningSession(sessionId: String): Boolean {
        require(sessionId.toByteArray(Charsets.UTF_8).size in 1..128) {
            "external signing sessionId must contain 1..128 UTF-8 bytes"
        }
        return synchronized(lifecycleGate) {
            requireOpen()
            native.cancelSigningSession(sessionId)
        }
    }

    private fun requireExternalSigningText(sessionId: String, response: String) {
        require(sessionId.toByteArray(Charsets.UTF_8).size in 1..128) {
            "external signing sessionId must contain 1..128 UTF-8 bytes"
        }
        require(response.toByteArray(Charsets.UTF_8).size in 1..2331) {
            "external signing response must contain 1..2331 UTF-8 bytes"
        }
    }

    /** Prepares application-owned opaque RuntimeCall bytes without touching wallet secrets. */
    fun prepareTransaction(
        sourceAccountId: ByteArray,
        callData: ByteArray,
    ): CompletableFuture<CitizenPreparedTransaction> {
        require(callData.size in 1..1024 * 1024) { "callData must contain 1..1 MiB bytes" }
        val source = sourceAccountId.requireSize(32, "sourceAccountId")
        val copiedCall = callData.clone()
        return request({ native.prepareTransaction(source, copiedCall) }) { result ->
            val prepared = result as? CitizenSdkNativeResult.PreparedTransaction
                ?: throw CitizenSdkException(
                    CitizenSdkErrorCode.INTEGRITY,
                    "Core returned an invalid prepared transaction result",
                )
            if (!prepared.value.sourceAccountId().contentEquals(source) ||
                preparedTransactions.putIfAbsent(prepared.value.preparationId, prepared.token) != null
            ) {
                runCatching { native.releasePreparedTransaction(prepared.token) }
                throw CitizenSdkException(
                    CitizenSdkErrorCode.INTEGRITY,
                    "Core returned a mismatched or duplicate transaction preparation",
                )
            }
            prepared.value
        }
    }

    /** Cancels exactly one preparation owned by this facade. */
    fun cancelPreparedTransaction(preparationId: String) {
        require(PREPARATION_ID.matches(preparationId)) { "preparationId is invalid" }
        val token = preparedTransactions.remove(preparationId)
            ?: throw CitizenSdkException(
                CitizenSdkErrorCode.NOT_FOUND,
                "Transaction preparation was not found",
            )
        try {
            native.releasePreparedTransaction(token)
        } catch (error: Throwable) {
            preparedTransactions.putIfAbsent(preparationId, token)
            throw error
        }
    }

    fun executePreparedTransaction(preparationId: String): CompletableFuture<CitizenTransactionExecution> {
        require(PREPARATION_ID.matches(preparationId)) { "preparationId is invalid" }
        val token = preparedTransactions.remove(preparationId)
            ?: throw CitizenSdkException(CitizenSdkErrorCode.NOT_FOUND, "Transaction preparation was not found")
        return try {
            request({ native.executePreparedTransaction(token) }) {
                (it as CitizenSdkNativeResult.TransactionExecution).value
            }
        } catch (error: Throwable) {
            // A synchronous admission failure does not consume the Core handle.
            preparedTransactions.putIfAbsent(preparationId, token)
            throw error
        }
    }

    fun consumePreparedTransactionQrResponse(
        executionId: String,
        response: String,
    ): CompletableFuture<CitizenTransactionExecution.Completed> {
        val id = executionIdBytes(executionId)
        require(response.toByteArray(Charsets.UTF_8).size in 1..2331) {
            "response must contain 1..2331 UTF-8 bytes"
        }
        return request({ native.consumePreparedTransactionQrResponse(id, response.toByteArray(Charsets.UTF_8)) }) {
            val value = (it as CitizenSdkNativeResult.TransactionExecution).value
            value as? CitizenTransactionExecution.Completed
                ?: throw CitizenSdkException(CitizenSdkErrorCode.INTEGRITY, "Core did not return a terminal execution")
        }
    }

    fun cancelPreparedTransactionExecution(executionId: String) {
        native.cancelPreparedTransactionExecution(executionIdBytes(executionId))
    }

    private fun executionIdBytes(value: String): ByteArray {
        require(PREPARATION_ID.matches(value)) { "executionId is invalid" }
        return ByteArray(16) { index ->
            value.substring(2 + index * 2, 4 + index * 2).toInt(16).toByte()
        }
    }

    /** Reads a deterministic page containing only SDK-submitted generic transactions. */
    fun getTransactionHistory(
        beforeExecutionId: String? = null,
        limit: Int = 100,
    ): CompletableFuture<CitizenTransactionHistoryPage> {
        require(limit in 1..100) { "limit must be within 1..100" }
        val before = beforeExecutionId?.let(::executionIdBytes)
        return request({ native.getTransactionHistory(before, limit) }) {
            (it as CitizenSdkNativeResult.TransactionHistoryPage).value
        }
    }

    /** Reconciles at most one bounded generic execution batch. */
    fun syncTransactionHistory(): CompletableFuture<CitizenTransactionHistoryPage> =
        request({ native.syncTransactionHistory() }) {
            (it as CitizenSdkNativeResult.TransactionHistoryPage).value
        }

    /** Starts a non-exported FLAG_SECURE flow; no secret is an API argument. */
    fun launchWalletFlow(
        activity: FragmentActivity,
        request: CitizenSdkWalletFlowContract.Request,
        callback: CitizenSdkWalletFlowContract.Callback,
    ): CitizenSdkWalletFlowCoordinator {
        return synchronized(lifecycleGate) {
            requireOpen()
            CitizenSdkQrCoordinator.requireCloseReady(this)
            hostServices.attachActivity(activity)
            CitizenSdkWalletFlowCoordinator.launch(this, activity, request, callback)
        }
    }

    /** 只控制 SDK 自有安全显示界面；操作结果不含私钥、内部句柄或显示回调。 */
    fun viewAccountPrivateKey(activity: FragmentActivity, accountId: ByteArray): CitizenSdkOperation<Unit> =
        synchronized(lifecycleGate) {
            requireOpen()
            val checked = accountId.requireSize(32, "accountId")
            CitizenSdkQrCoordinator.requireCloseReady(this)
            requireWalletUI()
            hostServices.attachActivity(activity)
            CitizenSdkWalletFlowCoordinator.launchPrivateKeyView(this, activity, checked)
        }

    @JvmSynthetic
    internal fun openPrivateKeyView(accountId: ByteArray, buffer: CitizenSdkPrivateKeyDisplayBuffer): Pair<Long, CitizenSdkOperation<Unit>> {
        buffer.bindAuthenticationRegistry(hostServices::registerPrivateKeyAuthentication)
        var identities: LongArray? = null
        val core = synchronized(lifecycleGate) {
            requireOpen()
            requests.submitOperation({
                native.openPrivateKeyView(accountId, buffer).also { identities = it }[0]
            }, {
                check(it is CitizenSdkNativeResult.Empty) { "private key view returned a non-empty result" }
                Unit
            })
        }
        val ids = checkNotNull(identities)
        val drained = core.future.whenComplete { _, _ ->
            // 普通请求已真实排空，才释放 JNI global ref；阶段 settled 绝不能走此路径。
            native.releasePrivateKeyViewContext(ids[2])
            buffer.authenticationId()?.let(hostServices::releasePrivateKeyAuthentication)
            readinessBoundaryCompleted()
        }
        return ids[1] to CitizenSdkOperation(core.operationId, drained, core::cancel)
    }
    @JvmSynthetic internal fun revealPrivateKeyView(viewId: Long) = native.revealPrivateKeyView(viewId)
    @JvmSynthetic internal fun cancelPrivateKeyView(viewId: Long) = native.cancelPrivateKeyView(viewId)
    @JvmSynthetic internal fun finishPrivateKeyView(viewId: Long) = native.finishPrivateKeyView(viewId)
    @JvmSynthetic internal fun isPrivateKeyAuthenticationActive(operationId: Long, activity: FragmentActivity): Boolean =
        hostServices.isPrivateKeyAuthenticationActive(operationId, activity)
    @JvmSynthetic internal fun cancelPrivateKeyAuthentication(operationId: Long) = hostServices.cancelPrivateKeyAuthentication(operationId)

    @JvmSynthetic
    internal fun prepareWalletCreation(wordCount: Int, password: ByteArray): CompletableFuture<CitizenSdkPreparedWallet> =
        request({
            CitizenSdkInputLimits.requireWalletSecret("password", password.size)
            native.prepareWalletCreation(wordCount, password)
        }) {
            CitizenSdkPreparedWallet.create(native, (it as CitizenSdkNativeResult.Prepared).token)
        }

    @JvmSynthetic
    internal fun importWallet(mnemonic: ByteArray, password: ByteArray): CompletableFuture<CitizenWalletProfile?> =
        walletMutation {
            request({
                CitizenSdkInputLimits.requireWalletSecret("mnemonic", mnemonic.size)
                CitizenSdkInputLimits.requireWalletSecret("password", password.size)
                native.importWallet(mnemonic, password)
            }) {
                (it as CitizenSdkNativeResult.Profile).value
            }
        }

    @JvmSynthetic
    internal fun addWalletAccounts(
        mnemonic: ByteArray,
        password: ByteArray,
        indices: IntArray,
    ): CompletableFuture<CitizenWalletProfile> = walletMutation {
        CitizenSdkInputLimits.requireAddAccountIndices(indices)
        request({
            CitizenSdkInputLimits.requireWalletSecret("mnemonic", mnemonic.size)
            CitizenSdkInputLimits.requireWalletSecret("password", password.size)
            native.addWalletAccounts(mnemonic, password, indices)
        }) {
            (it as CitizenSdkNativeResult.Accounts).value
        }.thenCompose { added ->
            if (added.size != indices.size ||
                added.map { it.index }.toSet() != indices.map(Int::toLong).toSet()
            ) {
                return@thenCompose failedFuture<CitizenWalletProfile>(
                    CitizenSdkException(
                        CitizenSdkErrorCode.INTEGRITY,
                        "add accounts result does not match the requested indices",
                    ),
                )
            }
            request({ native.getWalletProfile() }) { result ->
                val profile = requireWalletProfile(result, "add wallet accounts")
                if (added.any { addedAccount ->
                        profile.accounts.none { profileAccount ->
                            profileAccount.accountId().contentEquals(addedAccount.accountId())
                        }
                    }
                ) {
                    throw CitizenSdkException(
                        CitizenSdkErrorCode.INTEGRITY,
                        "updated wallet profile is missing an added account",
                    )
                }
                profile
            }
        }
    }

    @JvmSynthetic
    internal fun commitPreparedWallet(prepared: CitizenSdkPreparedWallet): CompletableFuture<CitizenWalletProfile?> =
        walletMutation {
            request({ prepared.commitRequest() }) { (it as CitizenSdkNativeResult.Profile).value }
        }

    @JvmSynthetic
    internal fun requireWalletUI() = CitizenSdkWalletUiAdmission.check(getCapabilities())

    @JvmSynthetic
    internal fun whenActivityReady(callback: (Throwable?) -> Unit): AutoCloseable =
        hostServices.whenActivityReady {
            val convergence = synchronized(lifecycleGate) { readinessBarrierLocked() }
            convergence.whenComplete { _, failure ->
                callback(failure?.let(::unwrapCompletion))
            }
        }

    /**
     * Destroys only a checkpoint-safe Core state.
     *
     * A RUNNING instance must first complete [stop], which persists the exact
     * host checkpoint. STARTING/IMPORTING or any accepted request fails closed.
     * START_FAILED is intentionally destroyable without stop, as required by
     * the one-way imported-state failure contract. An SDK-owned wallet flow
     * must first be cancelled and reach its callback; close returns BUSY while
     * its secure Activity or managed secret buffers are still owned.
     */
    override fun close() {
        synchronized(lifecycleGate) {
            if (closed.get()) return
            if (closeActive) throw CitizenSdkException(CitizenSdkErrorCode.BUSY, "CitizenSDK close is active")
            // 不在事件回调线程等待后续事件完成；未静止时拒绝，调用方在终态后重试。
            if (readinessInFlight || readinessRetryPending) throw CitizenSdkException(
                CitizenSdkErrorCode.BUSY, "CitizenSDK capability refresh is active",
            )
            if (!closing.get()) {
                requests.requireIdle()
                CitizenSdkWalletFlowCoordinator.requireCloseReady(this)
                CitizenSdkQrCoordinator.requireCloseReady(this)
                CitizenSdkClosePolicy.validate(native.lifecycle())
            }
            closing.set(true)
            closeActive = true
        }
        try {
            // 回调可以同步重入公开门面。屏障期间只保留 closing 状态，不占 lifecycleGate。
            native.close()
            preparedTransactions.clear()
            // Core destroy 是 prepared mnemonic 清理的唯一成功依据。
            CitizenSdkWalletFlowCoordinator.onCoreDestroyed(this)
            requests.close()
            eventListener = null
            try {
                hostServices.close()
            } finally {
                // Native destruction is the irreversible commit point.
                lifecycle = CitizenSdkLifecycle.DISPOSED
                closed.set(true)
            }
        } finally {
            synchronized(lifecycleGate) { closeActive = false }
        }
    }

    private fun unitRequest(
        begin: () -> Long,
        notifyReadinessBoundary: Boolean = true,
    ): CompletableFuture<Void> {
        val source = request(begin, notifyReadinessBoundary) {
            if (it !is CitizenSdkNativeResult.Empty) throw CitizenSdkException(
                CitizenSdkErrorCode.INTEGRITY,
                "Core returned a non-empty result for an empty operation",
            )
            Unit
        }
        val target = CompletableFuture<Void>()
        source.whenComplete { _, error ->
            if (error == null) target.complete(null) else target.completeExceptionally(error)
        }
        return target
    }

    private fun readinessChanged() {
        synchronized(lifecycleGate) {
            if (closed.get() || closing.get()) return
            check(readinessDesiredGeneration != Long.MAX_VALUE) {
                "CitizenSDK readiness generation space is exhausted"
            }
            readinessDesiredGeneration += 1
            if (readinessConvergence.isDone) readinessConvergence = CompletableFuture()
            ensureReadinessRefreshLocked()
        }
    }

    /** Starts at most one refresh and preserves the newest requested edge. */
    private fun ensureReadinessRefreshLocked() {
        if (closed.get() || closing.get() || readinessInFlight ||
            readinessAppliedGeneration == readinessDesiredGeneration
        ) return
        val targetGeneration = readinessDesiredGeneration
        readinessInFlight = true
        readinessRetryPending = false
        val refresh = try {
            unitRequest({ native.refreshCapabilities() }, notifyReadinessBoundary = false)
        } catch (error: Throwable) {
            readinessInFlight = false
            handleReadinessFailureLocked(error)
            return
        }
        refresh.whenComplete { _, failure ->
            synchronized(lifecycleGate) {
                readinessInFlight = false
                if (failure == null) {
                    readinessAppliedGeneration = maxOf(readinessAppliedGeneration, targetGeneration)
                    if (readinessAppliedGeneration == readinessDesiredGeneration) {
                        readinessConvergence.complete(null)
                    } else {
                        ensureReadinessRefreshLocked()
                    }
                } else {
                    handleReadinessFailureLocked(failure)
                }
            }
        }
    }

    private fun handleReadinessFailureLocked(failure: Throwable) {
        val cause = unwrapCompletion(failure)
        if (cause is CitizenSdkException && cause.code == CitizenSdkErrorCode.BUSY) {
            readinessRetryPending = true
        } else {
            readinessConvergence.completeExceptionally(cause)
        }
    }

    private fun readinessBoundaryCompleted() {
        synchronized(lifecycleGate) {
            if (!closed.get() && readinessRetryPending) ensureReadinessRefreshLocked()
        }
    }

    private fun readinessBarrierLocked(): CompletableFuture<Void> {
        ensureReadinessRefreshLocked()
        return readinessConvergence
    }

    private fun readinessSettledLocked(): Boolean =
        !readinessInFlight && !readinessRetryPending &&
            readinessAppliedGeneration == readinessDesiredGeneration

    private fun awaitReadinessBarrier() {
        while (true) {
            val barrier = synchronized(lifecycleGate) {
                if (closed.get()) return
                readinessBarrierLocked()
            }
            try {
                barrier.get()
            } catch (error: ExecutionException) {
                throw unwrapCompletion(error)
            }
            if (synchronized(lifecycleGate) { closed.get() || readinessSettledLocked() }) return
        }
    }

    private fun exclusiveAfterReadiness(begin: () -> Long): CompletableFuture<Void> {
        val result = CompletableFuture<Void>()
        lateinit var attempt: () -> Unit
        attempt = {
            val barrier = synchronized(lifecycleGate) { readinessBarrierLocked() }
            barrier.whenComplete { _, barrierFailure ->
                if (barrierFailure != null) {
                    result.completeExceptionally(unwrapCompletion(barrierFailure))
                } else {
                    val operation = try {
                        synchronized(lifecycleGate) {
                            if (!readinessSettledLocked()) null else unitRequest(begin)
                        }
                    } catch (error: Throwable) {
                        result.completeExceptionally(error)
                        null
                    }
                    if (operation == null && !result.isDone) {
                        attempt()
                    } else {
                        operation?.whenComplete { _, error ->
                            if (error == null) result.complete(null)
                            else result.completeExceptionally(unwrapCompletion(error))
                        }
                    }
                }
            }
        }
        attempt()
        return result
    }

    private fun unwrapCompletion(error: Throwable): Throwable = when (error) {
        is CompletionException, is ExecutionException -> error.cause ?: error
        else -> error
    }

    private fun <T> request(
        begin: () -> Long,
        notifyReadinessBoundary: Boolean = true,
        decode: (CitizenSdkNativeResult) -> T,
    ): CompletableFuture<T> {
        val future = synchronized(lifecycleGate) {
            requireOpen()
            requests.submit(begin, decode)
        }
        if (notifyReadinessBoundary) future.whenComplete { _, _ -> readinessBoundaryCompleted() }
        return future
    }

    /**
     * Admits one process-wide profile mutation sequence. Concurrent sessions
     * fail BUSY instead of interleaving with add-accounts' exact profile read.
     */
    private fun <T> walletMutation(operation: () -> CompletableFuture<T>): CompletableFuture<T> {
        synchronized(walletMutationGate) {
            if (walletMutationActive) return failedFuture(
                CitizenSdkException(CitizenSdkErrorCode.BUSY, "another wallet mutation is active"),
            )
            walletMutationActive = true
        }
        val internal = try {
            operation()
        } catch (error: Throwable) {
            synchronized(walletMutationGate) { walletMutationActive = false }
            throw error
        }
        val outward = CompletableFuture<T>()
        internal.whenComplete { value, error ->
            synchronized(walletMutationGate) { walletMutationActive = false }
            if (error == null) outward.complete(value)
            else outward.completeExceptionally(unwrapCompletion(error))
        }
        return outward
    }

    private fun checkedAccountName(name: String): String {
        CitizenSdkInputLimits.requireWalletAccountNameInput(name)
        require(name.codePoints().noneMatch { value ->
            value in 0x00..0x1f || value in 0x7f..0x9f
        }) { "wallet account name must not contain control characters" }
        return name.trim().also { normalized ->
            require(normalized.codePointCount(0, normalized.length) in 1..30) {
                "wallet account name must contain 1..30 Unicode scalars"
            }
        }
    }

    /** Keeps the mutation and its resulting profile snapshot under one process gate. */
    private fun walletMutationWithProfile(
        begin: () -> Long,
    ): CompletableFuture<CitizenWalletProfile?> = walletMutation {
        unitRequest(begin).thenCompose {
            request({ native.getWalletProfile() }) {
                (it as CitizenSdkNativeResult.Profile).value
            }
        }
    }

    // 仅 SDK 安全 Activity 调用。校验和词表来自同一个 Rust Core，不向 Flutter 导出秘密参数。
    @JvmSynthetic
    internal fun validateWalletPassword(password: ByteArray) = native.validateWalletPassword(password)

    @JvmSynthetic
    internal fun validateWalletMnemonic(mnemonic: ByteArray, wordCount: Int) = native.validateWalletMnemonic(mnemonic, wordCount)

    @JvmSynthetic
    internal fun walletWordSuggestions(prefix: ByteArray): List<String> {
        val bytes = native.walletWordSuggestions(prefix)
        return try { bytes.toString(Charsets.UTF_8).split('\n').filter { it.isNotEmpty() } }
        finally { bytes.fill(0) }
    }

    private fun requireWalletProfile(
        result: CitizenSdkNativeResult,
        operation: String,
    ): CitizenWalletProfile = (result as? CitizenSdkNativeResult.Profile)?.value
        ?: throw CitizenSdkException(
            CitizenSdkErrorCode.INTEGRITY,
            "$operation returned no wallet profile",
        )

    private fun <T> failedFuture(error: Throwable): CompletableFuture<T> =
        CompletableFuture<T>().also { it.completeExceptionally(error) }

    private fun requireOpen() {
        check(!closed.get() && !closing.get()) { "CitizenSdk is closing or closed" }
    }

    companion object {
        private val PREPARATION_ID = Regex("^0x[0-9a-f]{32}$")
        private val walletMutationGate = Any()
        private var walletMutationActive = false

        @JvmStatic
        @JvmOverloads
        fun open(context: Context, listener: CitizenSdkEvents.Listener? = null,
                 modules: Int = CitizenSdkModules.FULL): CitizenSdk {
            // 先执行唯一 Rust 合同，不加载未选模块资产或探测其设备资源。
            CitizenSdkNative.validateModules(modules)
            val sdk = CitizenSdk(context, listener, modules)
            return try {
                sdk.awaitReadinessBarrier()
                sdk
            } catch (error: Throwable) {
                runCatching { sdk.close() }
                throw error
            }
        }
    }
}

/** 只使用核心已经解析的能力，不在平台层复制模块依赖或设备可用性规则。 */
internal object CitizenSdkWalletUiAdmission {
    fun check(snapshot: CitizenSdkCapabilities) {
        val status = snapshot.statuses.singleOrNull { it.name == CitizenCapabilityName.WALLET_PROFILE }
            ?: throw CitizenSdkException(CitizenSdkErrorCode.INTEGRITY, "Core wallet capability is missing or duplicated")
        if (!status.supported || !status.enabled) throw CitizenSdkException(
            CitizenSdkErrorCode.NOT_READY, "wallet_profile is not ready",
        )
    }
}

/** 本地签名始终使用 SDK 金库；静态验签只处理公开数据，不创建 SDK 或访问设备密钥。 */
class CitizenSigning private constructor(
    private val signOperation: (ByteArray, ByteArray) -> CompletableFuture<CitizenSignature>,
    private val beginOperation: (CitizenSigningIntent) -> CompletableFuture<CitizenSigningOutcome>,
    private val consumeOperation: (String, String) -> CompletableFuture<CitizenSigningOutcome>,
    private val cancelOperation: (String) -> Boolean,
) {
    fun sign(accountId: ByteArray, message: ByteArray): CompletableFuture<CitizenSignature> =
        signOperation(accountId, message)

    fun begin(intent: CitizenSigningIntent): CompletableFuture<CitizenSigningOutcome> =
        beginOperation(intent)

    fun consumeExternalSignature(
        sessionId: String,
        response: String,
    ): CompletableFuture<CitizenSigningOutcome> = consumeOperation(sessionId, response)

    fun cancel(sessionId: String): Boolean = cancelOperation(sessionId)

    companion object {
        /** 签名分区只能由 SDK 持有的原生请求入口构造，Java 宿主不能注入替代实现。 */
        @JvmSynthetic
        internal fun create(
            sign: (ByteArray, ByteArray) -> CompletableFuture<CitizenSignature>,
            begin: (CitizenSigningIntent) -> CompletableFuture<CitizenSigningOutcome>,
            consume: (String, String) -> CompletableFuture<CitizenSigningOutcome>,
            cancel: (String) -> Boolean,
        ): CitizenSigning = CitizenSigning(sign, begin, consume, cancel)

        @JvmStatic
        fun verify(accountId: ByteArray, signature: ByteArray, message: ByteArray): Boolean {
            CitizenSdkInputLimits.requireSignPayload(message.size)
            return CitizenSdkNative.verifySignature(
                accountId.requireSize(32, "accountId"), signature.requireSize(64, "signature"), message,
            )
        }
    }
}

/** Bounded input validation applied before every proportional clone/flatten/JNI copy. */
internal object CitizenSdkInputLimits {
    const val MAX_BALANCE_ACCOUNTS = 1990
    const val MAX_SIGN_PAYLOAD_BYTES = 16 * 1024 * 1024
    const val MAX_WALLET_SECRET_BYTES = 1024
    const val MAX_ADD_ACCOUNT_INDICES = 1989
    const val MAX_WALLET_ACCOUNT_NAME_CODE_UNITS = 128
    const val MAX_STORAGE_KEY_BYTES = 4 * 1024
    const val MAX_STORAGE_BATCH_KEYS = 1024
    const val MAX_STORAGE_BATCH_KEY_BYTES = 1024 * 1024

    @JvmSynthetic
    fun requireStorageKey(key: ByteArray) {
        if (key.size !in 1..MAX_STORAGE_KEY_BYTES) throw CitizenSdkException(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            "storage key must contain 1..$MAX_STORAGE_KEY_BYTES bytes",
        )
    }

    @JvmSynthetic
    fun requireStorageKeys(keys: List<ByteArray>) {
        if (keys.size !in 1..MAX_STORAGE_BATCH_KEYS) throw CitizenSdkException(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            "storage batch must contain 1..$MAX_STORAGE_BATCH_KEYS keys",
        )
        var total = 0
        keys.forEach {
            requireStorageKey(it)
            total += it.size
            if (total > MAX_STORAGE_BATCH_KEY_BYTES) throw CitizenSdkException(
                CitizenSdkErrorCode.INVALID_ARGUMENT,
                "storage batch keys exceed $MAX_STORAGE_BATCH_KEY_BYTES bytes",
            )
        }
    }

    @JvmSynthetic
    fun requireBalanceAccountCount(count: Int) {
        if (count !in 0..MAX_BALANCE_ACCOUNTS) throw CitizenSdkException(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            "balance accountIds must contain 0..$MAX_BALANCE_ACCOUNTS entries",
        )
    }

    @JvmSynthetic
    fun requireSignPayload(size: Int) {
        if (size !in 0..MAX_SIGN_PAYLOAD_BYTES) throw CitizenSdkException(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            "sign payload exceeds $MAX_SIGN_PAYLOAD_BYTES bytes",
        )
    }

    @JvmSynthetic
    fun requireWalletSecret(label: String, size: Int) {
        if (size !in 0..MAX_WALLET_SECRET_BYTES) throw CitizenSdkException(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            "$label exceeds $MAX_WALLET_SECRET_BYTES UTF-8 bytes",
        )
    }

    @JvmSynthetic
    fun requireAddAccountIndices(indices: IntArray) {
        if (indices.size !in 1..MAX_ADD_ACCOUNT_INDICES) throw CitizenSdkException(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            "wallet index list must contain 1..$MAX_ADD_ACCOUNT_INDICES items",
        )
        val seen = BooleanArray(MAX_ADD_ACCOUNT_INDICES + 1)
        for (index in indices) {
            if (index !in 1..MAX_ADD_ACCOUNT_INDICES || seen[index]) throw CitizenSdkException(
                CitizenSdkErrorCode.INVALID_ARGUMENT,
                "wallet indices must be unique values in 1..$MAX_ADD_ACCOUNT_INDICES",
            )
            seen[index] = true
        }
    }

    @JvmSynthetic
    fun requireWalletAccountNameInput(name: String) {
        if (name.length !in 1..MAX_WALLET_ACCOUNT_NAME_CODE_UNITS) throw CitizenSdkException(
            CitizenSdkErrorCode.INVALID_ARGUMENT,
            "wallet account name input exceeds $MAX_WALLET_ACCOUNT_NAME_CODE_UNITS UTF-16 code units",
        )
    }
}

/** Content identity for public 32-byte account ids; never owns secret material. */

/** Pure, testable close-state contract shared by the facade and JVM tests. */
internal object CitizenSdkClosePolicy {
    enum class Decision { DESTROY, ALREADY_DISPOSED }

    fun validate(lifecycle: CitizenSdkLifecycle): Decision = when (lifecycle) {
        CitizenSdkLifecycle.CREATED,
        CitizenSdkLifecycle.STOPPED,
        CitizenSdkLifecycle.START_FAILED -> Decision.DESTROY
        CitizenSdkLifecycle.RUNNING -> throw CitizenSdkException(
            CitizenSdkErrorCode.INVALID_STATE,
            "A running CitizenSDK must complete stop/checkpoint before close",
        )
        CitizenSdkLifecycle.STARTING,
        CitizenSdkLifecycle.IMPORTING_STATE -> throw CitizenSdkException(
            CitizenSdkErrorCode.BUSY,
            "CitizenSDK lifecycle transition is still running",
        )
        CitizenSdkLifecycle.DISPOSED -> Decision.ALREADY_DISPOSED
    }
}
