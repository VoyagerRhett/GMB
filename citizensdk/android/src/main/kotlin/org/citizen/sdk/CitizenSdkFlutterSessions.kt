package org.citizen.sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Owns public Flutter session identities without exposing Core ownership IDs. */
internal class CitizenSdkFlutterSequenceGate {
    private var last = 0L
    @Synchronized
    fun accept(next: Long): Boolean {
        if (next != last + 1) return false
        last = next
        return true
    }
}

internal enum class CitizenSdkFlutterCloseAction { STOP_THEN_CLOSE, CLOSE, REJECT_UNSTABLE }

internal fun citizenSdkFlutterCloseAction(lifecycle: CitizenSdkLifecycle): CitizenSdkFlutterCloseAction =
    when (lifecycle) {
        CitizenSdkLifecycle.RUNNING -> CitizenSdkFlutterCloseAction.STOP_THEN_CLOSE
        CitizenSdkLifecycle.CREATED,
        CitizenSdkLifecycle.STOPPED,
        CitizenSdkLifecycle.START_FAILED,
        CitizenSdkLifecycle.DISPOSED,
        -> CitizenSdkFlutterCloseAction.CLOSE
        CitizenSdkLifecycle.STARTING,
        CitizenSdkLifecycle.IMPORTING_STATE,
        -> CitizenSdkFlutterCloseAction.REJECT_UNSTABLE
    }

internal fun citizenSdkFlutterCloseLifecycle(
    lifecycle: CitizenSdkLifecycle,
    stop: () -> CompletableFuture<Void>,
    dispose: () -> Unit,
): CompletableFuture<Void> {
    val prerequisite = when (citizenSdkFlutterCloseAction(lifecycle)) {
        CitizenSdkFlutterCloseAction.STOP_THEN_CLOSE -> stop()
        CitizenSdkFlutterCloseAction.CLOSE -> CompletableFuture.completedFuture(null)
        CitizenSdkFlutterCloseAction.REJECT_UNSTABLE -> CompletableFuture<Void>().also {
            it.completeExceptionally(
                CitizenSdkException(
                    CitizenSdkErrorCode.INVALID_STATE,
                    "CitizenSDK lifecycle did not settle before supervised close",
                ),
            )
        }
    }
    // A running instance reaches dispose only after stop has persisted its
    // checkpoint. A failed stop leaves the instance owned and retryable.
    return prerequisite.thenRun { dispose() }
}

internal fun interface CitizenSdkFlutterRetryScheduler {
    fun schedule(delayMillis: Long, task: () -> Unit)
}

/** Process-owned strong registry for detach cleanup that must survive plugin GC. */
internal class CitizenSdkFlutterOrphanSupervisor<T : Any>(
    private val scheduler: CitizenSdkFlutterRetryScheduler,
    private val close: (T) -> CompletableFuture<Void>,
) {
    private class State(var failures: Int = 0)
    private val entries = ConcurrentHashMap<T, State>()

    fun supervise(value: T) {
        val state = State()
        if (entries.putIfAbsent(value, state) == null) attempt(value, state)
    }

    private fun attempt(value: T, state: State) {
        val future = try {
            close(value)
        } catch (error: Throwable) {
            CompletableFuture<Void>().also { it.completeExceptionally(error) }
        }
        future.whenComplete { _, error ->
            if (error == null) {
                entries.remove(value, state)
                return@whenComplete
            }
            // Retry indefinitely, but keep the counter itself bounded so a
            // permanently unavailable provider cannot overflow it.
            if (state.failures < 128) state.failures++
            val delay = retryDelayMillis(state.failures)
            scheduler.schedule(delay) {
                if (entries[value] === state) attempt(value, state)
            }
        }
    }

    internal fun sizeForTest(): Int = entries.size
    internal fun failuresForTest(value: T): Int? = entries[value]?.failures

    companion object {
        internal fun retryDelayMillis(failures: Int): Long {
            val shift = (failures - 1).coerceIn(0, 7)
            return (250L shl shift).coerceAtMost(30_000L)
        }
    }
}

internal object CitizenSdkFlutterProcessOrphans : CitizenSdkFlutterRetryScheduler {
    private val executor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "citizensdk-flutter-detach").apply { isDaemon = true }
    }
    private val supervisor = CitizenSdkFlutterOrphanSupervisor<CitizenSdkFlutterSessions>(
        CitizenSdkFlutterRetryScheduler { delay, task ->
            executor.schedule({ task() }, delay, TimeUnit.MILLISECONDS)
        },
        CitizenSdkFlutterSessions::closeAll,
    )

    fun supervise(sessions: CitizenSdkFlutterSessions) = supervisor.supervise(sessions)

    override fun schedule(delayMillis: Long, task: () -> Unit) {
        executor.schedule({ task() }, delayMillis, TimeUnit.MILLISECONDS)
    }
}

private data class CitizenSdkFlutterClosePlan(
    val owner: Boolean,
    val outstanding: List<CitizenSdkFlutterOutstanding>,
    val completion: CompletableFuture<Void>,
)

private data class CitizenSdkFlutterOutstanding(
    val future: CompletableFuture<*>,
    val cancel: (() -> Unit)?,
)

internal fun citizenSdkFlutterSettleWithin(
    outstanding: List<CompletableFuture<*>>,
    timeoutMillis: Long,
    scheduler: CitizenSdkFlutterRetryScheduler,
): CompletableFuture<Void> {
    require(timeoutMillis > 0)
    if (outstanding.isEmpty()) return CompletableFuture.completedFuture(null)
    val settlement = CompletableFuture<Void>()
    CompletableFuture.allOf(*outstanding.toTypedArray()).whenComplete { _, _ ->
        settlement.complete(null)
    }
    if (!settlement.isDone) {
        scheduler.schedule(timeoutMillis) {
            settlement.completeExceptionally(
                CitizenSdkException(
                    CitizenSdkErrorCode.TIMEOUT,
                    "CitizenSDK accepted work did not settle before supervised close",
                ),
            )
        }
    }
    return settlement
}

internal class CitizenSdkFlutterSubscriptionGate<T : Any> {
    data class Token<T : Any>(val generation: Long, val value: T)

    private var generation = 0L
    private var current: Token<T>? = null

    @Synchronized
    fun open(value: T): Token<T>? {
        if (current != null || generation == Long.MAX_VALUE) return null
        val token = Token(++generation, value)
        current = token
        return token
    }

    @Synchronized
    fun close() {
        current = null
        if (generation != Long.MAX_VALUE) generation++
    }

    @Synchronized
    fun current(): Token<T>? = current

    @Synchronized
    fun owns(token: Token<T>): Boolean =
        current?.generation == token.generation && current?.value === token.value
}

internal class CitizenSdkFlutterSessions(context: Context) : EventChannel.StreamHandler {

    private inner class Session(val sdk: CitizenSdk) {
        val requests = CitizenSdkFlutterSequenceGate()
        val nextEvent = AtomicLong(1)
        private val stateLock = Any()
        private val inFlight = linkedMapOf<CompletableFuture<*>, CitizenSdkFlutterOutstanding>()
        private var closing = false
        private var closeCompletion: CompletableFuture<Void>? = null

        fun dispatchAccepted(sequence: Long, action: () -> Unit): Boolean = synchronized(stateLock) {
            if (closing || !requests.accept(sequence)) return false
            // Admission, native begin and in-flight registration are one host
            // critical section. Engine detach cannot snapshot between them.
            action()
            true
        }

        fun track(future: CompletableFuture<*>, cancel: (() -> Unit)? = null) {
            val outstanding = CitizenSdkFlutterOutstanding(future, cancel)
            synchronized(stateLock) { inFlight[future] = outstanding }
            future.whenComplete { _, _ -> synchronized(stateLock) { inFlight -= future } }
        }

        fun beginClose(): CitizenSdkFlutterClosePlan = synchronized(stateLock) {
            closeCompletion?.let { return CitizenSdkFlutterClosePlan(false, emptyList(), it) }
            closing = true
            val completion = CompletableFuture<Void>()
            closeCompletion = completion
            CitizenSdkFlutterClosePlan(true, inFlight.values.toList(), completion)
        }

        fun reopenAfterFailedClose() = synchronized(stateLock) {
            closing = false
            closeCompletion = null
        }
    }

    private val applicationContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val sessions = linkedMapOf<String, Session>()
    private val walletFlow = CitizenSdkFlutterWalletFlow()

    @Volatile private var activity: FragmentActivity? = null
    private val subscriptions = CitizenSdkFlutterSubscriptionGate<EventChannel.EventSink>()

    fun attachActivity(value: FragmentActivity) {
        activity = value
        snapshot().forEach { it.sdk.attachActivity(value) }
    }

    /** Configuration changes only replace the UI host; sessions stay alive. */
    fun detachActivity(value: FragmentActivity) {
        if (activity === value) activity = null
        snapshot().forEach { it.sdk.detachActivity(value) }
    }

    fun dispatch(request: CitizenSdkFlutterCodec.Request, result: MethodChannel.Result) {
        if (request is CitizenSdkFlutterCodec.Request.VerifySignature) {
            // 公开验签先于会话、序号和资源装配处理，不要求事件订阅或 Activity。
            try { result.success(verifySignature(request)) }
            catch (error: Throwable) { fail(result, error, request) }
            return
        }
        if (request is CitizenSdkFlutterCodec.Request.Open) {
            open(request.modules, result)
            return
        }
        val sessionRequest = request as CitizenSdkFlutterCodec.Request.SessionRequest
        val session = synchronized(lock) { sessions[sessionRequest.sessionId] }
        if (session == null) {
            fail(result, CitizenSdkErrorCode.NOT_FOUND, "CitizenSDK session was not found", request)
            return
        }
        try {
            if (!session.dispatchAccepted(sessionRequest.requestSequence) {
                    route(session, sessionRequest, result)
                }
            ) {
                fail(
                    result,
                    CitizenSdkErrorCode.CONFLICT,
                    "CitizenSDK request sequence is not the next session sequence",
                    request,
                )
            }
        } catch (error: Throwable) {
            fail(result, error, request)
        }
    }

    /** Engine detach uses the same checkpointed stop-then-destroy path as close. */
    fun closeAll(): CompletableFuture<Void> {
        val futures = snapshot().map { supervisedClose(it) }
        return CompletableFuture.allOf(*futures.toTypedArray())
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (arguments != listOf(CitizenSdkFlutterCodec.PROTOCOL_VERSION)) {
            events.error(
                "citizensdk.invalidArgument",
                "CitizenSDK event subscription tuple is invalid",
                CitizenSdkFlutterCodec.errorDetails(
                    CitizenSdkErrorCode.INVALID_ARGUMENT,
                    "CitizenSDK event subscription tuple is invalid",
                    null,
                    null,
                    "open",
                ),
            )
            return
        }
        if (subscriptions.open(events) == null) {
            events.error(
                "citizensdk.busy",
                "CitizenSDK event subscription is already active",
                CitizenSdkFlutterCodec.errorDetails(
                    CitizenSdkErrorCode.BUSY,
                    "CitizenSDK event subscription is already active",
                    null,
                    null,
                    "open",
                ),
            )
            return
        }
        // Re-subscription gets fresh queryable snapshots; no absent-sink event
        // consumes a Flutter event sequence.
        snapshot().forEach { session ->
            emit(session, "lifecycleChanged", listOf(CitizenSdkFlutterCodec.lifecycle(session.sdk.lifecycle)))
            try {
                emit(
                    session,
                    "capabilitiesChanged",
                    listOf(CitizenSdkFlutterCodec.capabilities(session.sdk.getCapabilities())),
                )
            } catch (_: Throwable) {
                // Capability query failure remains observable through methods;
                // the event stream never transports Throwable details.
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        subscriptions.close()
    }

    private fun open(modules: Int, result: MethodChannel.Result) {
        var sdk: CitizenSdk? = null
        try {
            val opened = CitizenSdk.open(applicationContext, null, modules)
            sdk = opened
            val session = Session(opened)
            opened.setEventListener { event -> onNativeEvent(session, event) }
            activity?.let(opened::attachActivity)
            synchronized(lock) {
                check(sessions.putIfAbsent(opened.sessionId, session) == null)
            }
            success(
                result,
                opened.sessionId,
                0,
                listOf(CitizenSdkFlutterCodec.lifecycle(opened.lifecycle), 1L),
            )
            // The Dart process router subscribes before open and remains the
            // single EventChannel consumer for every session. Emit an explicit
            // per-session baseline because a second Dart listener does not
            // trigger EventChannel.onListen again.
            emit(
                session,
                "lifecycleChanged",
                listOf(CitizenSdkFlutterCodec.lifecycle(opened.lifecycle)),
            )
            try {
                emit(
                    session,
                    "capabilitiesChanged",
                    listOf(CitizenSdkFlutterCodec.capabilities(opened.getCapabilities())),
                )
            } catch (_: Throwable) {
                // Method lookup remains the authoritative observable failure;
                // an unavailable snapshot never transports Throwable details.
            }
        } catch (error: Throwable) {
            sdk?.close()
            fail(result, error, CitizenSdkFlutterCodec.Request.Open(modules))
        }
    }

    private fun route(
        session: Session,
        request: CitizenSdkFlutterCodec.Request.SessionRequest,
        result: MethodChannel.Result,
    ) {
        val sdk = session.sdk
        when (request) {
            is CitizenSdkFlutterCodec.Request.Empty -> when (request.method) {
                "start" -> complete(session, request, result, sdk.start()) {
                    listOf(CitizenSdkFlutterCodec.lifecycle(sdk.lifecycle))
                }
                "stop" -> complete(session, request, result, sdk.stop()) {
                    listOf(CitizenSdkFlutterCodec.lifecycle(sdk.lifecycle))
                }
                "close" -> close(session, request, result)
                "getCapabilities" -> success(
                    result,
                    request.sessionId,
                    request.requestSequence,
                    listOf(CitizenSdkFlutterCodec.capabilities(sdk.getCapabilities())),
                )
                "getFinalizedHead" -> complete(session, request, result, sdk.getFinalizedHead()) {
                    listOf(CitizenSdkFlutterCodec.block(it))
                }
                "getSyncStatus" -> complete(session, request, result, sdk.getSyncStatus()) {
                    listOf(CitizenSdkFlutterCodec.syncStatus(it))
                }
                "getBestHead" -> complete(session, request, result, sdk.getBestHead()) {
                    listOf(CitizenSdkFlutterCodec.block(it))
                }
                "exportState" -> complete(session, request, result, sdk.exportState()) {
                    listOf(CitizenSdkFlutterCodec.chainState(it))
                }
                "getGenesisHash" -> success(result, request.sessionId, request.requestSequence,
                    listOf(CitizenSdkFlutterCodec.encodeHash32(sdk.getGenesisHash())))
                "getFeeSnapshot" -> complete(session, request, result, sdk.getFeeSnapshot()) {
                    listOf(CitizenSdkFlutterCodec.fee(it))
                }
                "getWalletProfile" -> complete(session, request, result, sdk.getWalletProfile()) {
                    listOf(CitizenSdkFlutterCodec.profile(it))
                }
                "getWalletState" -> complete(session, request, result, sdk.getWalletState()) {
                    listOf(CitizenSdkFlutterCodec.walletState(it))
                }
                "importWallet" -> walletFlow(session, request, result)
                "deleteWallet" -> complete(session, request, result, sdk.deleteWallet()) {
                    listOf(CitizenSdkFlutterCodec.profile(it))
                }
                "reconcileWalletCleanup" -> complete(
                    session,
                    request,
                    result,
                    sdk.reconcileWalletCleanup(),
                ) { listOf(CitizenSdkFlutterCodec.profile(it)) }
                else -> throw CitizenSdkException(CitizenSdkErrorCode.UNSUPPORTED, "Unsupported method")
            }
            is CitizenSdkFlutterCodec.Request.Account -> when (request.method) {
                "viewAccountPrivateKey" -> complete(
                    session, request, result,
                    walletFlow.viewAccountPrivateKey(sdk, activity, request),
                ) { emptyList() }
                "getAccountBalance" -> complete(
                    session,
                    request,
                    result,
                    sdk.getAccountBalance(request.accountId),
                ) { listOf(CitizenSdkFlutterCodec.balance(it)) }
                "getAccountNonce" -> complete(
                    session,
                    request,
                    result,
                    sdk.getAccountNonce(request.accountId),
                ) { listOf(CitizenSdkFlutterCodec.nonce(it)) }
                // Core 在同一 mutation 临界区内返回已经提交的原子 profile；
                // 这里不得再查询一次，否则会丢失该结果并扩大并发观察窗口。
                "setActiveWalletAccount" -> complete(
                    session,
                    request,
                    result,
                    sdk.setActiveWalletAccount(request.accountId),
                ) { listOf(CitizenSdkFlutterCodec.profile(it)) }
                "deleteWalletAccount" -> complete(
                    session,
                    request,
                    result,
                    sdk.deleteWalletAccount(request.accountId),
                ) { listOf(CitizenSdkFlutterCodec.profile(it)) }
                "deleteAccount" -> complete(
                    session, request, result, sdk.deleteAccount(request.accountId),
                ) { listOf(CitizenSdkFlutterCodec.walletState(it)) }
                else -> throw CitizenSdkException(CitizenSdkErrorCode.UNSUPPORTED, "Unsupported method")
            }
            is CitizenSdkFlutterCodec.Request.Balances -> complete(
                session, request, result, sdk.getAccountBalances(request.accountIds),
            ) { values -> listOf(values.map(CitizenSdkFlutterCodec::balance)) }
            is CitizenSdkFlutterCodec.Request.BlockNumber -> complete(
                session, request, result, sdk.getFinalizedBlockAt(request.number),
            ) { listOf(CitizenSdkFlutterCodec.block(it)) }
            is CitizenSdkFlutterCodec.Request.ResolveBlock -> complete(
                session, request, result,
                sdk.resolveFinalizedBlock(request.hash, request.number),
            ) { listOf(CitizenSdkFlutterCodec.block(it)) }
            is CitizenSdkFlutterCodec.Request.Block -> {
                when (request.method) {
                    "getBlockHeader" -> complete(
                        session, request, result, sdk.getBlockHeader(request.block),
                    ) { listOf(CitizenSdkFlutterCodec.blockHeader(it)) }
                    "getBlockBody" -> complete(
                        session, request, result, sdk.getBlockBody(request.block),
                    ) { listOf(CitizenSdkFlutterCodec.blockBody(it)) }
                    "getRuntimeContext" -> complete(
                        session, request, result, sdk.getRuntimeContext(request.block),
                    ) { listOf(CitizenSdkFlutterCodec.runtimeContext(it)) }
                    "getSystemEvents" -> complete(
                        session, request, result, sdk.getSystemEvents(request.block),
                    ) { listOf(it) }
                    else -> throw CitizenSdkException(CitizenSdkErrorCode.UNSUPPORTED, "Unsupported block method")
                }
            }
            is CitizenSdkFlutterCodec.Request.Storage -> complete(
                session, request, result, sdk.getStorage(request.block, request.key),
            ) { listOf(it) }
            is CitizenSdkFlutterCodec.Request.StorageBatch -> complete(
                session, request, result, sdk.getStorageBatch(request.block, request.keys),
            ) { listOf(it) }
            is CitizenSdkFlutterCodec.Request.StorageKeysPage -> complete(
                session,
                request,
                result,
                sdk.getStorageKeysPaged(request.block, request.prefix, request.startKey, request.limit),
            ) { listOf(it) }
            is CitizenSdkFlutterCodec.Request.RuntimeApi -> complete(
                session,
                request,
                result,
                sdk.callRuntimeApi(request.block, request.method, request.arguments),
            ) { listOf(it) }
            is CitizenSdkFlutterCodec.Request.ImportState -> complete(
                session, request, result, sdk.importState(request.state),
            ) { emptyList() }
            is CitizenSdkFlutterCodec.Request.CreateWallet -> walletFlow(session, request, result)
            is CitizenSdkFlutterCodec.Request.AddWalletAccounts -> walletFlow(session, request, result)
            // 与 setActiveWalletAccount 相同，直接投影 Core 返回的原子 profile。
            is CitizenSdkFlutterCodec.Request.RenameWalletAccount -> {
                val future = when (request.method) {
                    "renameWalletAccount" -> sdk.renameWalletAccount(request.accountId, request.name)
                        .thenApply<Any> { it }
                    "importColdAccountId" -> sdk.importColdAccount(request.accountId, request.name)
                        .thenApply<Any> { it }
                    else -> sdk.renameAccount(request.accountId, request.name).thenApply<Any> { it }
                }
                complete(session, request, result, future) { value ->
                    listOf(if (value is CitizenWalletProfile) CitizenSdkFlutterCodec.profile(value)
                    else CitizenSdkFlutterCodec.walletState(value as CitizenWalletState))
                }
            }
            is CitizenSdkFlutterCodec.Request.ColdSs58 -> complete(
                session, request, result, sdk.importColdAccount(request.address, request.name),
            ) { listOf(CitizenSdkFlutterCodec.walletState(it)) }
            is CitizenSdkFlutterCodec.Request.ReorderWalletAccounts -> complete(
                session, request, result,
                sdk.reorderWalletAccountsWithoutDefaultChange(request.expectedRevision, request.accountIds),
            ) { listOf(CitizenSdkFlutterCodec.walletState(it)) }
            is CitizenSdkFlutterCodec.Request.SignWalletPayload -> complete(
                session,
                request,
                result,
                sdk.signing.sign(request.accountId, request.payload),
            ) { listOf(CitizenSdkFlutterCodec.signature(it)) }
            is CitizenSdkFlutterCodec.Request.DeriveApplicationKey -> complete(
                session,
                request,
                result,
                sdk.deriveApplicationKey(request.accountId, request.salt, request.info),
            ) { listOf(it) }
            is CitizenSdkFlutterCodec.Request.BeginSigning -> complete(
                session, request, result, sdk.signing.begin(request.intent),
            ) { listOf(CitizenSdkFlutterCodec.signingOutcome(it)) }
            is CitizenSdkFlutterCodec.Request.ExternalSignature -> {
                if (request.method == "consumeExternalSignature") {
                    complete(
                        session, request, result,
                        sdk.signing.consumeExternalSignature(request.signingSessionId, request.response),
                    ) { listOf(CitizenSdkFlutterCodec.signingOutcome(it)) }
                } else {
                    complete(
                        session, request, result,
                        sdk.consumeDefaultAccountChange(request.signingSessionId, request.response),
                    ) { listOf(CitizenSdkFlutterCodec.defaultAccountChangeOutcome(it)) }
                }
            }
            is CitizenSdkFlutterCodec.Request.CancelSigning -> success(
                result, request.sessionId, request.requestSequence,
                listOf(sdk.signing.cancel(request.signingSessionId)),
            )
            is CitizenSdkFlutterCodec.Request.BeginDefaultAccountChange -> complete(
                session, request, result,
                sdk.beginDefaultAccountChange(
                    request.expectedRevision, request.accountIds, request.ttlSeconds,
                ),
            ) { listOf(CitizenSdkFlutterCodec.defaultAccountChangeOutcome(it)) }
            is CitizenSdkFlutterCodec.Request.PrepareTransaction -> complete(
                session,
                request,
                result,
                sdk.prepareTransaction(request.sourceAccountId, request.callData),
            ) { listOf(CitizenSdkFlutterCodec.preparedTransaction(it)) }
            is CitizenSdkFlutterCodec.Request.CancelPreparedTransaction -> {
                sdk.cancelPreparedTransaction(request.preparationId)
                success(
                    result,
                    request.sessionId,
                    request.requestSequence,
                    listOf(null),
                )
            }
            is CitizenSdkFlutterCodec.Request.TransactionExecution -> when (request.method) {
                "executePreparedTransaction" -> complete(
                    session, request, result,
                    sdk.executePreparedTransaction(request.executionId),
                ) { listOf(CitizenSdkFlutterCodec.transactionExecution(it)) }
                "consumePreparedTransactionQrResponse" -> complete(
                    session, request, result,
                    sdk.consumePreparedTransactionQrResponse(request.executionId, request.response!!),
                ) { listOf(CitizenSdkFlutterCodec.transactionExecution(it)) }
                else -> {
                    sdk.cancelPreparedTransactionExecution(request.executionId)
                    success(result, request.sessionId, request.requestSequence, listOf(null))
                }
            }
            is CitizenSdkFlutterCodec.Request.TransactionHistory -> {
                val future = if (request.method == "getTransactionHistory") {
                    sdk.getTransactionHistory(request.beforeExecutionId, request.limit)
                } else {
                    sdk.syncTransactionHistory()
                }
                complete(session, request, result, future) {
                    listOf(CitizenSdkFlutterCodec.transactionHistoryPage(it))
                }
            }
            is CitizenSdkFlutterCodec.Request.Qr -> {
                if (request.method == "qrScan" || request.method == "signQrRequest") {
                    complete(session, request, result, walletFlow.qr(sdk, activity, request)) { listOf(it.coreJson) }
                } else complete(session, request, result,
                    CompletableFuture.supplyAsync { routeQr(sdk, request) },
                ) { it }
            }
        }
    }

    private fun routeQr(
        sdk: CitizenSdk,
        request: CitizenSdkFlutterCodec.Request.Qr,
    ): List<Any?> = when (request.method) {
        "qrParse" -> listOf(sdk.qrParse(request.fields[0] as String).coreJson)
        "qrCreateSignRequest" -> listOf(sdk.qrCreateSignRequest(
            request.fields[0] as Int, request.fields[1] as ByteArray,
            request.fields[2] as ByteArray, request.fields[3] as Long,
        ))
        "qrConsumeSignResponse" -> listOf(sdk.qrConsumeSignResponse(request.fields[0] as String))
        "qrCancelSignRequest" -> listOf(sdk.qrCancelSignRequest(request.fields[0] as String))
        "qrEncodeAccountId" -> listOf(sdk.qrEncodeAccountId(request.fields[0] as ByteArray))
        "qrDecodeLuminance" -> listOf(sdk.qrDecodeLuminance(
            request.fields[0] as ByteArray, (request.fields[1] as Long).toInt(),
            (request.fields[2] as Long).toInt(), (request.fields[3] as Long).toInt(),
        ).coreJson)
        "qrEncode" -> sdk.qrEncode(
            request.fields[0] as String, request.fields[1] as Int,
        ).let { listOf(it.width, it.height, it.luminance()) }
        else -> throw CitizenSdkException(CitizenSdkErrorCode.UNSUPPORTED, "Unsupported QR method")
    }

    private fun walletFlow(
        session: Session,
        request: CitizenSdkFlutterCodec.Request.SessionRequest,
        result: MethodChannel.Result,
    ) = complete(session, request, result, walletFlow.launch(session.sdk, activity, request)) {
        listOf(CitizenSdkFlutterCodec.profile(it))
    }

    private fun close(
        session: Session,
        request: CitizenSdkFlutterCodec.Request.SessionRequest,
        result: MethodChannel.Result,
    ) {
        val future = supervisedClose(session)
        future.whenComplete { _, error ->
            main.post {
                if (error == null) {
                    success(result, request.sessionId, request.requestSequence, listOf("disposed"))
                } else {
                    fail(result, error, request)
                }
            }
        }
    }

    private fun supervisedClose(session: Session): CompletableFuture<Void> {
        val plan = session.beginClose()
        if (!plan.owner) return plan.completion
        walletFlow.cancelSession(session.sdk.sessionId)
        var cancellationError: Throwable? = null
        plan.outstanding.forEach { outstanding ->
            try {
                outstanding.cancel?.invoke()
            } catch (error: Throwable) {
                if (cancellationError == null) cancellationError = error
            }
        }
        val cancelFailure = cancellationError
        val settled = if (cancelFailure == null) {
            citizenSdkFlutterSettleWithin(
                plan.outstanding.map { it.future },
                CLOSE_SETTLEMENT_TIMEOUT_MILLIS,
                CitizenSdkFlutterProcessOrphans,
            )
        } else {
            CompletableFuture<Void>().also { it.completeExceptionally(cancelFailure) }
        }
        settled.thenCompose {
            citizenSdkFlutterCloseLifecycle(
                session.sdk.lifecycle,
                session.sdk::stop,
                session.sdk::close,
            )
        }.thenRun {
            synchronized(lock) { sessions.remove(session.sdk.sessionId, session) }
        }.whenComplete { _, error ->
            if (error == null) {
                plan.completion.complete(null)
            } else {
                session.reopenAfterFailedClose()
                plan.completion.completeExceptionally(error)
            }
        }
        return plan.completion
    }

    private fun onNativeEvent(session: Session, event: CitizenSdkEvents.Event) {
        when (event) {
            is CitizenSdkEvents.Event.HistoryChanged -> emit(session, "historyChanged", emptyList())
            is CitizenSdkEvents.Event.FinalizedBlockChanged -> emit(
                session,
                "finalizedBlockChanged",
                listOf(CitizenSdkFlutterCodec.block(event.finalized)),
            )
            is CitizenSdkEvents.Event.LifecycleChanged -> emit(
                session,
                "lifecycleChanged",
                listOf(CitizenSdkFlutterCodec.lifecycle(event.lifecycle)),
            )
            is CitizenSdkEvents.Event.CapabilitiesChanged -> emit(
                session,
                "capabilitiesChanged",
                listOf(CitizenSdkFlutterCodec.capabilities(event.capabilities)),
            )
        }
    }

    private fun emit(session: Session, type: String, payload: List<Any?>) {
        val subscription = subscriptions.current() ?: return
        main.post {
            if (!subscriptions.owns(subscription)) return@post
            subscription.value.success(
                CitizenSdkFlutterCodec.event(
                    session.sdk.sessionId,
                    session.nextEvent.getAndIncrement(),
                    type,
                    payload,
                ),
            )
        }
    }

    private fun <T> complete(
        session: Session,
        request: CitizenSdkFlutterCodec.Request.SessionRequest,
        result: MethodChannel.Result,
        future: CompletableFuture<T>,
        cancel: (() -> Unit)? = null,
        encode: (T) -> List<Any?>,
    ) {
        session.track(future, cancel)
        future.whenComplete { value, error ->
            main.post {
                if (error == null) {
                    try {
                        success(result, request.sessionId, request.requestSequence, encode(value))
                    } catch (encodingError: Throwable) {
                        fail(result, encodingError, request)
                    }
                } else {
                    fail(result, error, request)
                }
            }
        }
    }

    private fun success(
        result: MethodChannel.Result,
        sessionId: String,
        requestSequence: Long,
        value: List<Any?>,
    ) = result.success(CitizenSdkFlutterCodec.response(sessionId, requestSequence, value))

    private fun fail(
        result: MethodChannel.Result,
        error: Throwable,
        request: CitizenSdkFlutterCodec.Request,
    ) {
        val cause = unwrap(error)
        val sdkError = when (cause) {
            is CitizenSdkException -> cause
            is CitizenSdkFlutterCodec.ContractFailure -> CitizenSdkException(
                CitizenSdkErrorCode.fromValue(cause.errorCode),
                cause.message,
                stage = cause.stage,
            )
            is IllegalArgumentException -> CitizenSdkException(
                CitizenSdkErrorCode.INVALID_ARGUMENT,
                "Invalid CitizenSDK argument",
            )
            is IllegalStateException -> CitizenSdkException(
                CitizenSdkErrorCode.INVALID_STATE,
                "CitizenSDK operation is invalid in the current state",
            )
            else -> CitizenSdkException(CitizenSdkErrorCode.INTERNAL, "CitizenSDK host failure")
        }
        fail(
            result,
            sdkError.code,
            sdkError.message ?: "CitizenSDK failure",
            request,
            sdkError.stage,
        )
    }

    private fun fail(
        result: MethodChannel.Result,
        code: CitizenSdkErrorCode,
        message: String,
        request: CitizenSdkFlutterCodec.Request,
        stage: CitizenSdkFailureStage = CitizenSdkFailureStage.fromErrorCode(code),
    ) = result.error(
        "citizensdk.${CitizenSdkFlutterCodec.errorName(code)}",
        message,
        CitizenSdkFlutterCodec.errorDetails(
            code,
            message,
            request.sessionId,
            if (request is CitizenSdkFlutterCodec.Request.SessionRequest) request.requestSequence else null,
            CitizenSdkFlutterCodec.requestMethod(request),
            stage,
        ),
    )

    private fun snapshot(): List<Session> = synchronized(lock) { sessions.values.toList() }

    private fun unwrap(error: Throwable): Throwable {
        var current = error
        while (current is CompletionException && current.cause != null) current = current.cause!!
        return current
    }

    companion object {
        internal const val CLOSE_SETTLEMENT_TIMEOUT_MILLIS = 30_000L

        /** 只投影公开输入到同一原生验签入口；静态调用不构造会话注册表或宿主资源。 */
        internal fun verifySignature(
            request: CitizenSdkFlutterCodec.Request.VerifySignature,
            verify: (ByteArray, ByteArray, ByteArray) -> Boolean = CitizenSigning::verify,
        ): List<Any?> = listOf(
            CitizenSdkFlutterCodec.PROTOCOL_VERSION,
            verify(request.accountId, request.signature, request.payload),
        )
    }
}
