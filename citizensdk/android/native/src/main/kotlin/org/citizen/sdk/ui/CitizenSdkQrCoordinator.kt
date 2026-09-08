@file:kotlin.jvm.JvmSynthetic

package org.citizen.sdk.ui

import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import org.citizen.sdk.*
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicLong

/** SDK 自有 QR 窗口的单次所有权。Intent 只携带随机之外的进程内关联号，不携带载荷或凭证。 */
internal class CitizenSdkQrCoordinator private constructor(
    val sdk: CitizenSdk,
    val signText: String?,
    val id: Long,
) {
    private val main = Handler(Looper.getMainLooper())
    private val completion = CompletableFuture<CitizenQrDocument>()
    val operation = CitizenSdkOperation("qr-$id", completion) {
        main.post { cancel() }; !completion.isDone
    }
    private var activity: CitizenSdkQrActivity? = null
    private var review: CitizenSdkQrReview? = null
    private var reviewing: CitizenSdkOperation<CitizenSdkQrReview>? = null
    private var signing: CitizenSdkOperation<CitizenQrDocument>? = null
    private var readiness: AutoCloseable? = null
    private var result: CitizenQrDocument? = null
    private var failure: Throwable? = null
    private var ending = false
    private var destroyed = false
    private var cameraDrained = false
    private var claimed = false
    var confirmed = false
        private set

    fun attach(value: CitizenSdkQrActivity): Boolean {
        checkMain()
        if (activity != null || destroyed) return false
        activity = value
        if (ending) value.teardown() else if (signText != null) {
            sdk.attachActivity(value)
            // 等当前 Activity 的能力刷新完成；这不是自动启动轻节点。
            readiness = sdk.whenActivityReady { error -> main.post {
                if (!ending) {
                    if (error == null) beginReview() else end(null, error)
                }
            } }
        }
        return !ending
    }

    private fun beginReview() {
        checkMain()
        if (ending || reviewing != null || review != null) return
        try {
            val pending = sdk.reviewQrSignRequest(checkNotNull(signText))
            reviewing = pending
            pending.future.whenComplete { value, error -> main.post {
                reviewing = null
                if (error != null) end(null, error)
                else if (ending) value.close()
                else { review = value; activity?.showReview(value.text) }
                settle()
            } }
        } catch (error: Throwable) { end(null, error) }
    }

    fun confirm() {
        checkMain()
        val credential = review ?: return
        if (ending || confirmed) return
        confirmed = true
        try {
            val pending = sdk.signQrReview(credential)
            review = null; signing = pending
            pending.future.whenComplete { value, error -> main.post {
                signing = null
                if (!ending) {
                    if (error != null) end(null, error)
                    else try { end(value.withSignedImage(sdk.qrEncode(value.canonicalText)), null) }
                    catch (imageError: Throwable) { end(null, imageError) }
                }
                settle()
            } }
        } catch (error: Throwable) { end(null, error) }
    }

    fun scanned(value: CitizenQrDocument) { checkMain(); if (signText == null) end(value, null) }
    fun failed(error: Throwable) { checkMain(); end(null, error) }
    fun cancel() { checkMain(); end(null, CitizenSdkException(CitizenSdkErrorCode.CANCELLED, "扫码或签名窗口已关闭")) }

    private fun end(value: CitizenQrDocument?, error: Throwable?) {
        if (ending) { settle(); return }
        ending = true; result = value; failure = error
        readiness?.close(); readiness = null
        review?.close(); review = null
        reviewing?.let { runCatching { it.cancel() } }
        signing?.let { runCatching { it.cancel() } }
        // finish() 不能提前完成请求。真实认证、帧分析队列及 Activity 均排空才交付结果。
        activity?.teardown()
        settle()
    }

    fun cameraClosed() { checkMain(); cameraDrained = true; settle() }
    fun activityDestroyed(value: CitizenSdkQrActivity) {
        checkMain()
        if (activity !== value) return
        if (signText != null) sdk.detachActivity(value)
        activity = null; destroyed = true
        if (!ending) cancel() else settle()
    }

    private fun settle() {
        if (!ending || !destroyed || !cameraDrained || reviewing != null || signing != null || completion.isDone) return
        synchronized(registry) { registry.remove(id) }
        val error = failure
        if (error != null) completion.completeExceptionally(error)
        else result?.let(completion::complete) ?: completion.completeExceptionally(
            CitizenSdkException(CitizenSdkErrorCode.INTEGRITY, "QR 终态缺失"),
        )
    }

    companion object {
        private val next = AtomicLong(1)
        private val registry = HashMap<Long, CitizenSdkQrCoordinator>()
        private fun checkMain() { check(Looper.myLooper() == Looper.getMainLooper()) { "QR UI 必须在主线程调用" } }
        fun requireCloseReady(sdk: CitizenSdk) = synchronized(registry) {
            if (registry.values.any { it.sdk === sdk }) throw CitizenSdkException(CitizenSdkErrorCode.BUSY, "SDK QR 窗口尚未排空")
        }
        fun launch(sdk: CitizenSdk, activity: FragmentActivity, text: String?): CitizenSdkOperation<CitizenQrDocument> {
            checkMain()
            if (activity.isFinishing || activity.isDestroyed || !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                throw CitizenSdkException(CitizenSdkErrorCode.UNAVAILABLE, "扫码签名需要前台 Activity")
            }
            val owner = synchronized(registry) {
                requireCloseReady(sdk)
                val id = next.getAndIncrement(); check(id > 0)
                CitizenSdkQrCoordinator(sdk, text, id).also { registry[id] = it }
            }
            try { activity.startActivity(Intent(activity, CitizenSdkQrActivity::class.java).putExtra(CitizenSdkQrActivity.EXTRA_ID, owner.id)) }
            catch (error: Throwable) { synchronized(registry) { registry.remove(owner.id) }; throw error }
            return owner.operation
        }
        fun lookup(id: Long): CitizenSdkQrCoordinator? = synchronized(registry) {
            val value = registry[id] ?: return@synchronized null
            // 配置重建或重复 Intent 不能接管旧窗口，也不能提前归还旧窗口的帧/Surface 租约。
            if (value.claimed) null else value.also { it.claimed = true }
        }
    }
}
