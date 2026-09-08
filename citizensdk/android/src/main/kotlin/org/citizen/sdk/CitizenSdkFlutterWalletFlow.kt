package org.citizen.sdk

import androidx.fragment.app.FragmentActivity
import org.citizen.sdk.ui.CitizenSdkWalletFlowContract
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** One-shot ownership registry whose callback may win before handle binding. */
internal class CitizenSdkFlutterOneShotRegistry<K : Any, H : Any>(
    private val cancelHandle: (H) -> Unit,
) {
    internal class Entry<H : Any> {
        val handle = AtomicReference<H?>()
        val finished = AtomicBoolean(false)
        val cancelRequested = AtomicBoolean(false)
    }

    private val entries = ConcurrentHashMap<K, Entry<H>>()

    fun reserve(key: K): Entry<H>? = Entry<H>().takeIf { entries.putIfAbsent(key, it) == null }

    fun bind(entry: Entry<H>, handle: H) {
        check(entry.handle.compareAndSet(null, handle))
        if (entry.cancelRequested.get()) cancelHandle(handle)
    }

    fun finish(key: K, entry: Entry<H>): Boolean {
        if (!entry.finished.compareAndSet(false, true)) return false
        return entries.remove(key, entry)
    }

    fun cancelWhere(predicate: (K) -> Boolean) {
        entries.entries.filter { predicate(it.key) }.forEach { (_, entry) ->
            if (entry.cancelRequested.compareAndSet(false, true)) {
                entry.handle.get()?.let(cancelHandle)
            }
        }
    }

    internal fun sizeForTest(): Int = entries.size
}

/**
 * Secret-free Flutter projection of the SDK-owned wallet Activity.
 *
 * Flutter selects only the operation, word count, or public derivation
 * indices. Recovery phrases and passwords are entered/rendered by the
 * non-exported FLAG_SECURE Activity and never enter this object.
 */
internal class CitizenSdkFlutterWalletFlow {
    private data class Key(val sessionId: String, val requestSequence: Long)
    private val active = CitizenSdkFlutterOneShotRegistry<Key, () -> Unit> {
        it()
    }

    fun qr(sdk: CitizenSdk, activity: FragmentActivity?, request: CitizenSdkFlutterCodec.Request.Qr): CompletableFuture<CitizenQrDocument> {
        val host = activity ?: return failed(CitizenSdkException(CitizenSdkErrorCode.UNAVAILABLE, "QR 需要前台 FragmentActivity"))
        val key = Key(request.sessionId, request.requestSequence)
        val completion = CompletableFuture<CitizenQrDocument>()
        val owner = active.reserve(key) ?: return failed(CitizenSdkException(CitizenSdkErrorCode.CONFLICT, "QR 请求已存在"))
        try {
            val future: CompletableFuture<CitizenQrDocument>
            if (request.method == "signQrRequest") {
                val operation = sdk.signQrRequest(host, request.fields[0] as String)
                active.bind(owner) { operation.cancel(); Unit }
                future = operation.future.thenApply { it.document }
            } else {
                val operation = sdk.qrScan(host)
                active.bind(owner) { operation.cancel(); Unit }
                future = operation.future
            }
            future.whenComplete { value, error ->
                if (active.finish(key, owner)) {
                    if (error == null) completion.complete(value) else completion.completeExceptionally(error)
                }
            }
        } catch (error: Throwable) { if (active.finish(key, owner)) completion.completeExceptionally(error) }
        return completion
    }

    /** 私钥查看共享会话取消注册；完成值为空，不把内部 buffer 放入通道。 */
    fun viewAccountPrivateKey(sdk: CitizenSdk, activity: FragmentActivity?, request: CitizenSdkFlutterCodec.Request.Account): CompletableFuture<Unit> {
        val host = activity ?: return failed(CitizenSdkException(
            CitizenSdkErrorCode.UNAVAILABLE, "private key view requires a FragmentActivity",
        ))
        val key = Key(request.sessionId, request.requestSequence)
        val completion = CompletableFuture<Unit>()
        val owner = active.reserve(key) ?: return failed(CitizenSdkException(
            CitizenSdkErrorCode.CONFLICT, "wallet flow request already exists",
        ))
        try {
            val operation = sdk.viewAccountPrivateKey(host, request.accountId)
            active.bind(owner) { operation.cancel(); Unit }
            operation.future.whenComplete { _, failure ->
                if (active.finish(key, owner)) {
                    if (failure == null) completion.complete(Unit) else completion.completeExceptionally(failure)
                }
            }
        } catch (failure: Throwable) {
            if (active.finish(key, owner)) completion.completeExceptionally(failure)
        }
        return completion
    }

    fun launch(
        sdk: CitizenSdk,
        activity: FragmentActivity?,
        request: CitizenSdkFlutterCodec.Request.SessionRequest,
    ): CompletableFuture<CitizenWalletProfile?> {
        val host = activity ?: return failed(
            CitizenSdkException(
                CitizenSdkErrorCode.UNAVAILABLE,
                "CitizenSDK wallet UI requires a FragmentActivity",
            ),
        )
        val contract = contractRequest(request)
        val key = Key(request.sessionId, request.requestSequence)
        val completion = CompletableFuture<CitizenWalletProfile?>()
        val owner = active.reserve(key) ?: return failed(
            CitizenSdkException(CitizenSdkErrorCode.CONFLICT, "Wallet flow request already exists"),
        )
        try {
            val coordinator = sdk.launchWalletFlow(host, contract) { result ->
                if (!active.finish(key, owner)) return@launchWalletFlow
                when (result) {
                    is CitizenSdkWalletFlowContract.Result.Completed -> completion.complete(result.profile)
                    CitizenSdkWalletFlowContract.Result.Cancelled -> completion.completeExceptionally(
                        CitizenSdkException(CitizenSdkErrorCode.CANCELLED, "CitizenSDK wallet flow cancelled"),
                    )
                    is CitizenSdkWalletFlowContract.Result.Failed -> completion.completeExceptionally(result.error)
                }
            }
            active.bind(owner) { coordinator.cancel() }
        } catch (error: Throwable) {
            if (active.finish(key, owner)) completion.completeExceptionally(error)
        }
        return completion
    }

    /** Cancels every SDK-owned UI flow before supervised session destruction. */
    fun cancelSession(sessionId: String) {
        active.cancelWhere { it.sessionId == sessionId }
    }

    companion object {
        internal fun contractRequest(
            request: CitizenSdkFlutterCodec.Request.SessionRequest,
        ): CitizenSdkWalletFlowContract.Request = when (request) {
            is CitizenSdkFlutterCodec.Request.CreateWallet ->
                CitizenSdkWalletFlowContract.Request.Create(request.wordCount)
            is CitizenSdkFlutterCodec.Request.AddWalletAccounts ->
                CitizenSdkWalletFlowContract.Request.AddAccounts(request.indices)
            is CitizenSdkFlutterCodec.Request.Empty -> {
                require(request.method == "importWallet")
                CitizenSdkWalletFlowContract.Request.Import()
            }
            else -> throw CitizenSdkException(
                CitizenSdkErrorCode.INVALID_ARGUMENT,
                "Request is not an SDK-owned wallet flow",
            )
        }

        private fun <T> failed(error: Throwable): CompletableFuture<T> =
            CompletableFuture<T>().also { it.completeExceptionally(error) }
    }
}
