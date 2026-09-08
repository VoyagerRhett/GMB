package org.citizen.sdk.ui

import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.fragment.app.FragmentActivity
import org.citizen.sdk.CitizenSdk
import org.citizen.sdk.CitizenSdkErrorCode
import org.citizen.sdk.CitizenSdkException
import org.citizen.sdk.CitizenSdkPreparedWallet
import org.citizen.sdk.CitizenSdkPreparedReleaseStatus
import org.citizen.sdk.CitizenWalletProfile
import org.citizen.sdk.CitizenSdkOperation
import java.lang.ref.WeakReference
import java.security.SecureRandom
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** One-shot owner connecting the non-exported Activity to an SDK instance. */
class CitizenSdkWalletFlowCoordinator private constructor(
    @get:JvmSynthetic
    internal val sdk: CitizenSdk,
    @get:JvmSynthetic
    internal val request: CitizenSdkWalletFlowContract.Request?,
    private val callback: CitizenSdkWalletFlowContract.Callback?,
    @get:JvmSynthetic
    internal val privateKeyView: CitizenSdkPrivateKeyView? = null,
) : AutoCloseable {
    private var flowActivity = WeakReference<CitizenSdkWalletFlowActivity>(null)
    private val detachCancellation = AtomicBoolean(false)
    private val completionScheduled = AtomicBoolean(false)
    private val finished = AtomicBoolean(false)
    private val operationGate = Any()
    private var preparationInFlight = false
    private var preparationCancelRequested = false
    private var irreversibleInFlight = false
    private var irreversibleAccepted = false
    private var awaitingRecreation = false
    private var pendingTerminal: CitizenSdkWalletFlowContract.Result? = null
    private var teardownTerminal: CitizenSdkWalletFlowContract.Result? = null
    // True only between Activity registry lookup and attach(). It closes the
    // consume -> cancel race without treating a not-yet-attached Activity as
    // safely torn down.
    private var attachmentClaimPending = false
    private var readinessWaiter: AutoCloseable? = null
    private var preparedOwner: CitizenSdkPreparedWallet? = null
    @get:JvmSynthetic
    internal val flowId: Long = nextFlowId()
    private val cleanupScheduled = AtomicBoolean(false)
    private var cleanupAttempt = 0
    private val cleanupRunnable = Runnable {
        cleanupScheduled.set(false)
        val terminal = runCatching { retryPreparedRelease() }.getOrDefault(false)
        if (!terminal) supervisePreparedCleanup()
    }

    fun cancel() {
        privateKeyView?.let { it.end(cancelled = true); return }
        // Engine/session detach is allowed to remove the parent host first.
        // Still wait for the secure Activity teardown, but do not then wait
        // forever for a parent Activity that is intentionally gone.
        detachCancellation.set(true)
        if (!runCatching { retryPreparedRelease() }.getOrDefault(false)) {
            supervisePreparedCleanup()
        }
        val alreadyTornDown = synchronized(operationGate) {
            awaitingRecreation = false
            preparationCancelRequested = true
            teardownTerminal
        }
        if (alreadyTornDown != null) {
            synchronized(operationGate) {
                readinessWaiter.also { readinessWaiter = null }
            }?.close()
            completeNow(
                if (requiresTruthfulTerminal()) alreadyTornDown
                else CitizenSdkWalletFlowContract.Result.Cancelled,
            )
            return
        }
        val settlementRequired = requestCancellationSettlement()
        val attachment = synchronized(operationGate) {
            val current = flowActivity.get()?.takeUnless { it.isDestroyed }
            val awaitClaimedAttachment = current == null && attachmentClaimPending
            if (awaitClaimedAttachment && !settlementRequired && pendingTerminal == null) {
                pendingTerminal = CitizenSdkWalletFlowContract.Result.Cancelled
            }
            current to awaitClaimedAttachment
        }
        when {
            attachment.first != null -> checkNotNull(attachment.first).requestCancellation(force = true)
            attachment.second -> Unit
            !settlementRequired -> completeAfterTeardown(
                CitizenSdkWalletFlowContract.Result.Cancelled,
            )
        }
    }

    override fun close() = cancel()

    /** Completes only after the secure Activity is gone and a parent host resumed. */
    @JvmSynthetic
    internal fun completeAfterTeardown(result: CitizenSdkWalletFlowContract.Result) {
        if (!completionScheduled.compareAndSet(false, true)) return
        val releaseAttempt = runCatching { retryPreparedRelease() }
        val releaseFailure = releaseAttempt.exceptionOrNull()
        if (releaseAttempt.getOrNull() != true) supervisePreparedCleanup()
        val safeResult = if (releaseFailure == null) result else {
            CitizenSdkWalletFlowContract.Result.Failed(
                unwrapWalletFailure(releaseFailure),
            )
        }
        // Publish the terminal under the same gate observed by attach before
        // removing the close-gate registry entry. A claimed Activity can never
        // continue into secret UI after this point.
        synchronized(operationGate) { teardownTerminal = safeResult }
        // The ordinary flow registry can now finish. When release is still
        // pending, CLEANUP_SUPERVISOR independently keeps the owner and SDK
        // strongly reachable until release succeeds or Core is destroyed.
        REGISTRY.remove(flowId, this)
        if (detachCancellation.get()) {
            // Once Core has accepted an irreversible wallet mutation, report
            // its real terminal outcome even when engine detach requested the
            // UI cancellation. Returning Cancelled while storage changes would
            // violate the public contract.
            completeNow(
                if (requiresTruthfulTerminal()) safeResult
                else CitizenSdkWalletFlowContract.Result.Cancelled,
            )
        } else {
            val waiter = sdk.whenActivityReady { readinessFailure ->
                if (readinessFailure == null) {
                    completeNow(safeResult)
                } else {
                    completeNow(
                        CitizenSdkWalletFlowContract.Result.Failed(
                            readinessFailure as? CitizenSdkException ?: CitizenSdkException(
                                CitizenSdkErrorCode.INTERNAL,
                                "CitizenSDK host readiness refresh failed",
                                readinessFailure,
                            ),
                        ),
                    )
                }
            }
            val closeImmediately = synchronized(operationGate) {
                if (finished.get() || detachCancellation.get()) true else {
                    readinessWaiter = waiter
                    false
                }
            }
            if (closeImmediately) {
                waiter.close()
                if (detachCancellation.get()) {
                    completeNow(
                        if (requiresTruthfulTerminal()) safeResult
                        else CitizenSdkWalletFlowContract.Result.Cancelled,
                    )
                }
            }
        }
    }

    private fun completeNow(result: CitizenSdkWalletFlowContract.Result) {
        val deliver = Runnable {
            if (finished.compareAndSet(false, true)) {
                val waiter = synchronized(operationGate) {
                    readinessWaiter.also { readinessWaiter = null }
                }
                waiter?.close()
                callback?.onResult(result)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) deliver.run() else MAIN.post(deliver)
    }

    @JvmSynthetic
    internal fun attach(activity: CitizenSdkWalletFlowActivity) {
        privateKeyView?.let {
            synchronized(operationGate) { attachmentClaimPending = false }
            it.attach(activity)
            return
        }
        val outcome = synchronized(operationGate) {
            attachmentClaimPending = false
            flowActivity = WeakReference(activity)
            awaitingRecreation = false
            val terminal = pendingTerminal ?: teardownTerminal
            terminal to CitizenSdkWalletFlowAttachmentPolicy.finishWithoutContent(
                completionStarted = completionScheduled.get(),
                finished = finished.get(),
                terminalKnown = terminal != null,
            )
        }
        when {
            outcome.first != null -> activity.finishWithTerminal(checkNotNull(outcome.first))
            outcome.second -> activity.finish()
        }
    }

    private fun claimAttachment(): Boolean = synchronized(operationGate) {
        if (!CitizenSdkWalletFlowAttachmentPolicy.canClaim(
                completionStarted = completionScheduled.get(),
                finished = finished.get(),
                terminalKnown = teardownTerminal != null,
                claimPending = attachmentClaimPending,
            )
        ) return@synchronized false
        attachmentClaimPending = true
        true
    }

    /**
     * Owns the accepted prepare request until its handle is either transferred
     * to the current secure Activity or reliably released after cancellation.
     */
    @JvmSynthetic
    internal fun acceptPreparation(
        future: CompletableFuture<CitizenSdkPreparedWallet>,
    ) {
        synchronized(operationGate) {
            check(!preparationInFlight && !irreversibleAccepted && pendingTerminal == null)
            preparationInFlight = true
        }
        future.whenComplete { prepared, failure ->
            MAIN.post {
                val cancelled = synchronized(operationGate) {
                    preparationInFlight = false
                    preparationCancelRequested
                }
                if (failure != null) {
                    val activity = synchronized(operationGate) {
                        flowActivity.get()?.takeUnless { it.isDestroyed || it.isFinishing }
                    }
                    // prepare 没有持久化副作用，原输入仍在 SDK 控件中时才允许原页重试。
                    if (!cancelled && activity != null) {
                        activity.showPreparationFailure(unwrapWalletFailure(failure))
                        return@post
                    }
                    deliverTerminal(
                        if (cancelled) CitizenSdkWalletFlowContract.Result.Cancelled
                        else CitizenSdkWalletFlowContract.Result.Failed(
                            unwrapWalletFailure(failure),
                        ),
                    )
                    return@post
                }
                val value = checkNotNull(prepared)
                retainPrepared(value)
                if (cancelled) {
                    deliverTerminal(CitizenSdkWalletFlowContract.Result.Cancelled)
                    return@post
                }
                val activity = synchronized(operationGate) {
                    flowActivity.get()?.takeUnless { it.isDestroyed || it.isFinishing }
                }
                if (activity == null) {
                    deliverTerminal(CitizenSdkWalletFlowContract.Result.Cancelled)
                } else {
                    try {
                        activity.showBackupFromCoordinator(value)
                    } catch (error: Throwable) {
                        deliverTerminal(
                            CitizenSdkWalletFlowContract.Result.Failed(
                                unwrapWalletFailure(error),
                            ),
                        )
                    }
                }
            }
        }
    }

    /**
     * Owns an accepted import/add/commit future across Activity recreation.
     * Back, detach and onDestroy cannot publish Cancelled until this future has
     * produced its real storage outcome.
     */
    @JvmSynthetic
    internal fun acceptIrreversible(
        future: CompletableFuture<out CitizenWalletProfile?>,
    ) {
        synchronized(operationGate) {
            check(!irreversibleInFlight && pendingTerminal == null) {
                "a wallet mutation is already attached to this flow"
            }
            irreversibleAccepted = true
            irreversibleInFlight = true
        }
        future.whenComplete { profile, failure ->
            MAIN.post {
                val result = when {
                    failure != null -> CitizenSdkWalletFlowContract.Result.Failed(
                        unwrapWalletFailure(failure),
                    )
                    profile == null -> CitizenSdkWalletFlowContract.Result.Failed(
                        CitizenSdkException(
                            CitizenSdkErrorCode.INTEGRITY,
                            "wallet mutation returned no profile",
                        ),
                    )
                    else -> CitizenSdkWalletFlowContract.Result.Completed(profile)
                }
                synchronized(operationGate) { irreversibleInFlight = false }
                deliverTerminal(result)
            }
        }
    }

    private fun deliverTerminal(result: CitizenSdkWalletFlowContract.Result) {
        val (activity, waitForRecreation) = synchronized(operationGate) {
            pendingTerminal = result
            val current = flowActivity.get()?.takeUnless {
                it.isDestroyed || it.isFinishing
            }
            current to CitizenSdkWalletFlowTerminalPolicy.awaitRecreation(
                configurationChange = awaitingRecreation,
                detachCancellation = detachCancellation.get(),
            )
        }
        when {
            activity != null -> activity.finishWithTerminal(result)
            waitForRecreation -> Unit
            else -> completeAfterTeardown(result)
        }
    }

    @JvmSynthetic
    internal fun activityDestroyed(
        activity: CitizenSdkWalletFlowActivity,
        changingConfigurations: Boolean,
    ) {
        privateKeyView?.let { it.destroyed(); return }
        synchronized(operationGate) {
            if (flowActivity.get() === activity) flowActivity = WeakReference(null)
            if (preparationInFlight) preparationCancelRequested = true
            awaitingRecreation = changingConfigurations &&
                (preparationInFlight || irreversibleAccepted)
        }
    }

    @JvmSynthetic
    internal fun requestCancellationSettlement(): Boolean = synchronized(operationGate) {
        if (preparationInFlight) preparationCancelRequested = true
        CitizenSdkWalletFlowTerminalPolicy.settlementRequired(
            preparationInFlight = preparationInFlight,
            irreversibleAccepted = irreversibleAccepted,
        )
    }

    @JvmSynthetic
    internal fun requiresTruthfulTerminal(): Boolean = synchronized(operationGate) {
        irreversibleAccepted
    }

    @JvmSynthetic
    internal fun settlementInFlight(): Boolean = synchronized(operationGate) {
        preparationInFlight || irreversibleInFlight
    }

    @JvmSynthetic
    internal fun settlePreparedForTerminal(
        result: CitizenSdkWalletFlowContract.Result,
    ): Throwable? {
        if (!CitizenSdkWalletFlowTerminalPolicy.releasePrepared(result)) {
            synchronized(operationGate) { preparedOwner = null }
            cleanupResolved()
            return null
        }
        val attempt = runCatching { retryPreparedRelease() }
        if (attempt.getOrNull() != true) supervisePreparedCleanup()
        return attempt.exceptionOrNull()
    }

    @JvmSynthetic
    internal fun retryPreparedRelease(): Boolean {
        val owner = synchronized(operationGate) { preparedOwner }
        if (owner == null) {
            cleanupResolved()
            return true
        }
        if (owner.releaseForCleanup() == CitizenSdkPreparedReleaseStatus.IN_PROGRESS) return false
        synchronized(operationGate) { if (preparedOwner === owner) preparedOwner = null }
        cleanupResolved()
        return true
    }

    private fun retainPrepared(owner: CitizenSdkPreparedWallet) {
        synchronized(operationGate) {
            check(preparedOwner == null || preparedOwner === owner)
            preparedOwner = owner
        }
    }

    /** Process-lifetime owner for cleanup that outlives a completed Flutter flow. */
    private fun supervisePreparedCleanup() {
        CLEANUP_SUPERVISOR.retain(flowId, this)
        if (!cleanupScheduled.compareAndSet(false, true)) return
        val attempt = synchronized(operationGate) {
            cleanupAttempt.also { if (cleanupAttempt != Int.MAX_VALUE) cleanupAttempt += 1 }
        }
        if (!MAIN.postDelayed(
                cleanupRunnable,
                CitizenSdkPreparedCleanupPolicy.delayMillis(attempt),
            )
        ) {
            cleanupScheduled.set(false)
        }
    }

    private fun cleanupResolved() {
        CLEANUP_SUPERVISOR.resolve(flowId, this)
        synchronized(operationGate) { cleanupAttempt = 0 }
        if (cleanupScheduled.compareAndSet(true, false)) {
            MAIN.removeCallbacks(cleanupRunnable)
        }
    }

    /**
     * Drops only the Java owner after a successful Core destroy. Core destroy
     * is the exact operation that zeroizes every still-prepared mnemonic, so
     * no JNI release or INVALID_HANDLE inference is needed on this path.
     */
    private fun preparedDestroyedByCore() {
        synchronized(operationGate) { preparedOwner = null }
        cleanupResolved()
    }

    companion object {
        private val RANDOM = SecureRandom()
        private val REGISTRY = ConcurrentHashMap<Long, CitizenSdkWalletFlowCoordinator>()
        private val CLEANUP_SUPERVISOR =
            CitizenSdkCleanupRetention<CitizenSdkWalletFlowCoordinator>()
        private val MAIN = Handler(Looper.getMainLooper())

        @JvmSynthetic
        internal fun launchPrivateKeyView(sdk: CitizenSdk, activity: FragmentActivity, accountId: ByteArray): CitizenSdkOperation<Unit> {
            check(Looper.myLooper() == Looper.getMainLooper()) { "private key view must start on the main thread" }
            if (REGISTRY.values.any { it.sdk === sdk }) throw CitizenSdkException(
                CitizenSdkErrorCode.BUSY, "CitizenSDK already owns a wallet interface",
            )
            if (activity.isFinishing || activity.isDestroyed) throw CitizenSdkException(
                CitizenSdkErrorCode.UNAVAILABLE, "private key view host is unavailable",
            )
            val view = CitizenSdkPrivateKeyView(sdk, accountId)
            val coordinator = CitizenSdkWalletFlowCoordinator(sdk, null, null, view)
            check(REGISTRY.putIfAbsent(coordinator.flowId, coordinator) == null)
            view.releaseOwner = {
                coordinator.finished.set(true)
                REGISTRY.remove(coordinator.flowId, coordinator)
            }
            try {
                activity.startActivity(Intent(activity, CitizenSdkWalletFlowActivity::class.java)
                    .putExtra(CitizenSdkWalletFlowActivity.EXTRA_FLOW_ID, coordinator.flowId))
            } catch (failure: RuntimeException) {
                view.failToLaunch(failure)
            }
            return view.operation
        }

        @JvmStatic
        fun launch(
            sdk: CitizenSdk,
            activity: FragmentActivity,
            request: CitizenSdkWalletFlowContract.Request,
            callback: CitizenSdkWalletFlowContract.Callback,
        ): CitizenSdkWalletFlowCoordinator {
            // 未选择钱包模块时在 Activity、秘密输入和等待宿主认证之前精确拒绝。
            sdk.requireWalletUI()
            if (REGISTRY.values.any { it.sdk === sdk && it.privateKeyView != null }) throw CitizenSdkException(
                CitizenSdkErrorCode.BUSY, "CitizenSDK owns a private key view",
            )
            val coordinator = CitizenSdkWalletFlowCoordinator(sdk, request, callback)
            check(REGISTRY.putIfAbsent(coordinator.flowId, coordinator) == null)
            try {
                activity.startActivity(
                    Intent(activity, CitizenSdkWalletFlowActivity::class.java)
                        .putExtra(CitizenSdkWalletFlowActivity.EXTRA_FLOW_ID, coordinator.flowId),
                )
            } catch (error: RuntimeException) {
                coordinator.completeAfterTeardown(
                    CitizenSdkWalletFlowContract.Result.Failed(
                        CitizenSdkException(
                            CitizenSdkErrorCode.UNAVAILABLE,
                            "Unable to start the CitizenSDK wallet flow",
                            error,
                        ),
                    ),
                )
            }
            return coordinator
        }

        @JvmSynthetic
        internal fun consume(flowId: Long): CitizenSdkWalletFlowCoordinator? {
            val coordinator = REGISTRY[flowId] ?: return null
            return coordinator.takeIf { it.claimAttachment() }
        }

        /**
         * Public SDK close may destroy Core only after the secure Activity has
         * torn down and removed this SDK's flow from REGISTRY. Cleanup-only
         * supervisor owners are safe to resolve through Core destroy because
         * their Activity and managed UI buffers are already gone.
         */
        @JvmSynthetic
        internal fun requireCloseReady(sdk: CitizenSdk) {
            CitizenSdkWalletFlowClosePolicy.validate(
                REGISTRY.values.any { it.sdk === sdk },
            )
        }

        /**
         * Explicitly terminates retained cleanup after this exact SDK's Core
         * has been successfully destroyed. An arbitrary INVALID_HANDLE while
         * a live bridge exists is deliberately not treated as success.
         */
        @JvmSynthetic
        internal fun onCoreDestroyed(sdk: CitizenSdk) {
            (REGISTRY.values.asSequence() + CLEANUP_SUPERVISOR.snapshot().asSequence())
                .filter { it.sdk === sdk }
                .distinctBy { it.flowId }
                .forEach { it.preparedDestroyedByCore() }
        }

        private fun unwrapWalletFailure(failure: Throwable): CitizenSdkException {
            val cause = (failure as? CompletionException)?.cause ?: failure
            return cause as? CitizenSdkException ?: CitizenSdkException(
                CitizenSdkErrorCode.INTERNAL,
                "CitizenSDK wallet mutation failed",
                cause,
            )
        }

        private fun nextFlowId(): Long {
            while (true) {
                val candidate = RANDOM.nextLong() and Long.MAX_VALUE
                if (candidate != 0L &&
                    !REGISTRY.containsKey(candidate) &&
                    !CLEANUP_SUPERVISOR.contains(candidate)
                ) return candidate
            }
        }
    }
}

/** 私钥查看不重建、不等待父 Activity 恢复；仅在清屏与 Core 真实请求终态后释放 UI 注册。 */
internal class CitizenSdkPrivateKeyView(private val sdk: CitizenSdk, accountId: ByteArray) {
    val buffer = CitizenSdkPrivateKeyDisplayBuffer()
    private val main = Handler(Looper.getMainLooper())
    private val admission = sdk.openPrivateKeyView(accountId, buffer)
    private val viewId = admission.first
    private val core = admission.second
    private val completion = CompletableFuture<Unit>()
    val operation = CitizenSdkOperation(core.operationId, completion) { end(cancelled = true); !completion.isDone }
    var releaseOwner: (() -> Unit)? = null
    private var activity = WeakReference<CitizenSdkWalletFlowActivity>(null)
    private var ending = false
    private var coreDone = false
    private var coreError: Throwable? = null
    private var presentationError: Throwable? = null
    private var uiGone = true
    private var ready = false
    private var revealAccepted = false

    init {
        buffer.bind(viewId)
        buffer.listen { code -> main.post {
            if (!ending) {
                if (code == CitizenSdkErrorCode.OK.value) { ready = true; activity.get()?.privateKeyReady() }
                else end(cancelled = false)
            }
        } }
        core.future.whenComplete { _, failure -> main.post {
            coreDone = true; coreError = failure
            buffer.clear()
            activity.get()?.clearPrivateKeyAndFinish()
            completeIfReady()
        } }
    }

    fun attach(value: CitizenSdkWalletFlowActivity) {
        activity = WeakReference(value); uiGone = false
        if (ending || coreDone) value.clearPrivateKeyAndFinish()
    }
    fun reveal() {
        if (ending || revealAccepted) return
        revealAccepted = true
        try { sdk.revealPrivateKeyView(viewId) } catch (_: Throwable) { end(cancelled = false) }
    }
    fun isReady(): Boolean = ready && !ending
    fun isAuthenticating(): Boolean {
        if (ending) return false
        val current = activity.get() ?: return false
        val id = buffer.authenticationId() ?: return false
        return sdk.isPrivateKeyAuthenticationActive(id, current)
    }
    fun failToLaunch(failure: Throwable) {
        presentationError = CitizenSdkException(CitizenSdkErrorCode.UNAVAILABLE,
            "Unable to start the CitizenSDK private key view", failure)
        end(cancelled = true)
    }
    fun end(cancelled: Boolean) {
        if (Looper.myLooper() != Looper.getMainLooper()) { main.post { end(cancelled) }; return }
        if (ending) return
        ending = true
        // 锁内撤销接收并清零后才通知 Core finish；晚到的认证/display 不得复活 UI。
        buffer.clear(); activity.get()?.clearPrivateKeyAndFinish()
        buffer.authenticationId()?.let(sdk::cancelPrivateKeyAuthentication)
        fun settle() {
            if (coreDone) { completeIfReady(); return }
            try {
                if (cancelled) sdk.cancelPrivateKeyView(viewId)
                sdk.finishPrivateKeyView(viewId)
            } catch (_: Throwable) {
                // 不以异常推定 Core 已释放，保留所有者和取消能力直到真实终态。
                main.postDelayed({ settle() }, 100)
            }
        }
        settle()
    }
    fun destroyed() {
        buffer.clear(); activity = WeakReference(null); uiGone = true
        if (!ending) end(cancelled = true)
        completeIfReady()
    }
    private fun completeIfReady() {
        if (!coreDone || !uiGone || completion.isDone) return
        buffer.clear()
        releaseOwner?.invoke(); releaseOwner = null
        val failure = presentationError ?: coreError
        if (failure == null) completion.complete(Unit) else completion.completeExceptionally(failure)
    }
}

/** Bounded exponential delay; attempts continue until owner cleanup is terminal. */
internal object CitizenSdkPreparedCleanupPolicy {
    @JvmSynthetic
    fun delayMillis(attempt: Int): Long {
        val exponent = attempt.coerceIn(0, 7)
        return minOf(30_000L, 250L shl exponent)
    }
}

/** Pure policy for the registry-lookup -> Activity-attach admission window. */
internal object CitizenSdkWalletFlowAttachmentPolicy {
    @JvmSynthetic
    fun canClaim(
        completionStarted: Boolean,
        finished: Boolean,
        terminalKnown: Boolean,
        claimPending: Boolean,
    ): Boolean = !completionStarted && !finished && !terminalKnown && !claimPending

    @JvmSynthetic
    fun finishWithoutContent(
        completionStarted: Boolean,
        finished: Boolean,
        terminalKnown: Boolean,
    ): Boolean = !terminalKnown && (completionStarted || finished)
}

/** Pure close gate: Core destruction must not outlive SDK-owned secret UI. */
internal object CitizenSdkWalletFlowClosePolicy {
    @JvmSynthetic
    fun validate(activeFlow: Boolean) {
        if (activeFlow) throw CitizenSdkException(
            CitizenSdkErrorCode.BUSY,
            "A CitizenSDK wallet flow must finish before SDK close",
        )
    }
}

/** Strong-reference table whose compare-by-owner removal prevents stale cleanup. */
internal class CitizenSdkCleanupRetention<T : Any> {
    private val owners = ConcurrentHashMap<Long, T>()

    @JvmSynthetic
    fun retain(id: Long, owner: T) {
        val existing = owners.putIfAbsent(id, owner)
        check(existing == null || existing === owner) {
            "cleanup id is already owned by another operation"
        }
    }

    @JvmSynthetic
    fun resolve(id: Long, owner: T): Boolean = owners.remove(id, owner)

    @JvmSynthetic
    fun owns(id: Long, owner: T): Boolean = owners[id] === owner

    @JvmSynthetic
    fun contains(id: Long): Boolean = owners.containsKey(id)

    @JvmSynthetic
    fun snapshot(): List<T> = owners.values.toList()
}

/** Pure cancellation boundary used by the Activity and JVM contract tests. */
internal object CitizenSdkWalletFlowTerminalPolicy {
    enum class CancellationDecision { FINISH_CANCELLED, WAIT_FOR_MUTATION }

    @JvmSynthetic
    fun cancellation(
        irreversibleAccepted: Boolean,
        preparationInFlight: Boolean = false,
    ): CancellationDecision =
        if (settlementRequired(preparationInFlight, irreversibleAccepted)) {
            CancellationDecision.WAIT_FOR_MUTATION
        }
        else CancellationDecision.FINISH_CANCELLED

    @JvmSynthetic
    fun settlementRequired(
        preparationInFlight: Boolean,
        irreversibleAccepted: Boolean,
    ): Boolean = preparationInFlight || irreversibleAccepted

    @JvmSynthetic
    fun awaitRecreation(
        configurationChange: Boolean,
        detachCancellation: Boolean,
    ): Boolean = configurationChange && !detachCancellation

    @JvmSynthetic
    fun releasePrepared(result: CitizenSdkWalletFlowContract.Result): Boolean =
        result !is CitizenSdkWalletFlowContract.Result.Completed
}
