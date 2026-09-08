package org.citizen.sdk.ui

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.os.Bundle
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.camera.core.CameraSelector
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import org.citizen.sdk.*
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** 不导出的 SDK 窗口；CameraX 只提供帧，所有码识别仍调用共同的 ZXing 和 Rust。 */
internal class CitizenSdkQrActivity : FragmentActivity(), TextureView.SurfaceTextureListener {
    private var owner: CitizenSdkQrCoordinator? = null
    private val revoked = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor { task -> Thread(task, "citizensdk-qr-frame") }
    private var provider: ProcessCameraProvider? = null
    private var previewUseCase: Preview? = null
    private var analysisUseCase: ImageAnalysis? = null
    private lateinit var preview: TextureView
    private lateinit var content: LinearLayout
    private lateinit var reviewText: TextView
    private lateinit var confirm: Button
    private var permissionPending = false
    private var hadFocus = false
    private var lastFrame = 0L
    private var surfaceRequest: SurfaceRequest? = null
    private val surfaceUsers = HashMap<SurfaceTexture, Int>()
    private val deferredTextures = HashSet<SurfaceTexture>()
    private val drain = CitizenSdkQrOwnedDrain()
    private var cameraReported = false
    private var destructionStarted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        owner = CitizenSdkQrCoordinator.lookup(intent.getLongExtra(EXTRA_ID, 0))
        val current = owner
        if (current == null) { executor.shutdown(); finish(); return }
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 24, 24, 24) }
        preview = TextureView(this).apply { surfaceTextureListener = this@CitizenSdkQrActivity }
        reviewText = TextView(this).apply { text = "正在核验已终结链元数据…"; setTextIsSelectable(false) }
        val scroll = ScrollView(this).apply { addView(reviewText) }
        val frame = FrameLayout(this).apply {
            addView(preview, FrameLayout.LayoutParams(-1, -1))
            addView(scroll, FrameLayout.LayoutParams(-1, -1))
        }
        content.addView(frame, LinearLayout.LayoutParams(-1, 0, 1f))
        confirm = Button(this).apply {
            text = "我已核对完整内容，确认签名"; visibility = View.GONE
            setOnClickListener { isEnabled = false; current.confirm() }
        }
        content.addView(confirm)
        content.addView(Button(this).apply { text = "取消并关闭"; setOnClickListener { current.cancel() } })
        setContentView(content)
        window.decorView.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) = Unit
            override fun onViewDetachedFromWindow(view: View) {
                if (destructionStarted) owner?.activityDestroyed(this@CitizenSdkQrActivity)
            }
        })
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { current.cancel() }
        })
        scroll.visibility = if (current.signText == null) View.GONE else View.VISIBLE
        preview.visibility = if (current.signText == null) View.VISIBLE else View.GONE
        if (!current.attach(this)) return
        if (savedInstanceState != null) { current.cancel(); return }
        if (current.signText == null) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) startCamera()
            else { permissionPending = true; requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION) }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION) return
        permissionPending = false
        if (revoked.get()) return
        if (grantResults.size == 1 && grantResults[0] == PackageManager.PERMISSION_GRANTED) startCamera()
        else owner?.failed(CitizenSdkException(CitizenSdkErrorCode.PERMISSION_DENIED, "相机权限未授予"))
    }

    private fun startCamera() {
        if (revoked.get()) return
        try {
            val pending = ProcessCameraProvider.getInstance(this)
            pending.addListener({
                if (revoked.get()) return@addListener
                try {
                    val cameraProvider = pending.get()
                    val selector = when {
                        cameraProvider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) -> CameraSelector.DEFAULT_BACK_CAMERA
                        cameraProvider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) -> CameraSelector.DEFAULT_FRONT_CAMERA
                        else -> throw CitizenSdkException(CitizenSdkErrorCode.UNAVAILABLE, "没有可用相机")
                    }
                    val cameraPreview = Preview.Builder().build().also {
                        it.setSurfaceProvider(ContextCompat.getMainExecutor(this)) { request ->
                            if (revoked.get()) request.willNotProvideSurface()
                            else {
                                surfaceRequest?.willNotProvideSurface()
                                surfaceRequest = request
                                request.addRequestCancellationListener(ContextCompat.getMainExecutor(this)) {
                                    if (surfaceRequest === request) surfaceRequest = null
                                }
                                providePreviewSurface()
                            }
                        }
                    }
                    val analysis = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888).build()
                    provider = cameraProvider; previewUseCase = cameraPreview; analysisUseCase = analysis
                    analysis.setAnalyzer(executor, ::analyze)
                    val camera = cameraProvider.bindToLifecycle(this, selector, cameraPreview, analysis)
                    camera.cameraInfo.cameraState.observe(this) { state ->
                        if (state.error != null && !revoked.get()) owner?.failed(CitizenSdkException(CitizenSdkErrorCode.UNAVAILABLE, "相机被中断或不可用"))
                    }
                } catch (error: Throwable) { owner?.failed(cameraFailure(error)) }
            }, ContextCompat.getMainExecutor(this))
        } catch (error: Throwable) { owner?.failed(cameraFailure(error)) }
    }

    private fun analyze(image: ImageProxy) {
        try {
            if (revoked.get()) return
            val now = System.nanoTime()
            if (now >= lastFrame && now - lastFrame < 100_000_000) return
            lastFrame = now
            check(image.format == ImageFormat.YUV_420_888)
            val width = image.width; val height = image.height
            check(width in 1..4096 && height in 1..4096)
            val plane = image.planes[0]; val input = plane.buffer.duplicate()
            val row = plane.rowStride; val pixel = plane.pixelStride
            check(pixel > 0 && row >= (width - 1) * pixel + 1)
            val base = input.position()
            check((height - 1L) * row + (width - 1L) * pixel + 1 <= input.remaining())
            // 只压紧 8 位亮度平面，不改变内容、编码图片、落盘或保留跨会话缓存。
            val luminance = ByteArray(width * height)
            for (y in 0 until height) for (x in 0 until width) luminance[y * width + x] = input.get(base + y * row + x * pixel)
            val current = owner ?: return
            val document = current.sdk.qrDecodeLuminance(luminance, width, height, width)
            runOnUiThread { if (!revoked.get()) current.scanned(document) }
        } catch (error: CitizenSdkException) {
            if (error.code != CitizenSdkErrorCode.NOT_FOUND) runOnUiThread { if (!revoked.get()) owner?.failed(error) }
        } catch (error: Throwable) {
            runOnUiThread { if (!revoked.get()) owner?.failed(cameraFailure(error)) }
        } finally { image.close() }
    }

    fun showReview(text: String) {
        if (revoked.get()) return
        reviewText.text = text; confirm.visibility = View.VISIBLE
    }

    fun teardown() {
        if (!revoked.compareAndSet(false, true)) return
        drain.revoke()
        if (::content.isInitialized) { content.visibility = View.INVISIBLE; reviewText.text = ""; confirm.isEnabled = false }
        runCatching { analysisUseCase?.clearAnalyzer() }
        surfaceRequest?.willNotProvideSurface(); surfaceRequest = null
        previewUseCase?.setSurfaceProvider(null)
        // 只解绑本次窗口拥有的用例，绝不停止宿主或另一产品自己的相机用例。
        val owned = listOfNotNull(previewUseCase, analysisUseCase)
        if (owned.isNotEmpty()) runCatching { provider?.unbind(*owned.toTypedArray()) }
        previewUseCase = null; analysisUseCase = null; provider = null
        executor.shutdown()
        Thread({
            // 不在主线程等待，仍须等已借用的 ImageProxy/ZXing 调用真实返回。
            while (!executor.awaitTermination(1, TimeUnit.SECONDS)) { /* 排空当前有界帧 */ }
            runOnUiThread { drain.framesReturned(); settleCamera() }
        }, "citizensdk-qr-close").start()
        finish()
    }

    private fun settleCamera() {
        if (!drain.isReady() || cameraReported) return
        cameraReported = true
        owner?.cameraClosed()
    }

    private fun providePreviewSurface() {
        if (revoked.get() || !preview.isAvailable) return
        val request = surfaceRequest ?: return
        val texture = preview.surfaceTexture ?: return
        surfaceRequest = null
        texture.setDefaultBufferSize(request.resolution.width, request.resolution.height)
        val surface = Surface(texture)
        surfaceUsers[texture] = (surfaceUsers[texture] ?: 0) + 1
        drain.surfaceBorrowed()
        // SurfaceRequest 的结果回调只归还本次 Preview 的表面租约，不依赖共享物理相机是否 CLOSED。
        request.provideSurface(surface, ContextCompat.getMainExecutor(this)) {
            surface.release()
            val remaining = checkNotNull(surfaceUsers[texture]) - 1
            if (remaining == 0) {
                surfaceUsers.remove(texture)
                if (deferredTextures.remove(texture)) texture.release()
            } else { surfaceUsers[texture] = remaining }
            drain.surfaceReturned(); settleCamera()
        }
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) { providePreviewSurface() }
    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit
    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        if (surfaceUsers.containsKey(surface)) { deferredTextures.add(surface); return false }
        return true
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hadFocus = true
        else if (hadFocus && !permissionPending && owner?.confirmed == false && !revoked.get()) owner?.cancel()
    }
    override fun onPause() {
        // 系统认证临时抢焦点只能隐藏；真正退后台由 onStop 确定终止。
        if (::content.isInitialized) content.visibility = View.INVISIBLE
        if (!permissionPending && owner?.confirmed == false && !revoked.get()) owner?.cancel()
        super.onPause()
    }
    override fun onResume() {
        super.onResume()
        if (::content.isInitialized && !revoked.get()) content.visibility = View.VISIBLE
    }
    override fun onStop() { if (!revoked.get()) owner?.cancel(); super.onStop() }
    override fun onDestroy() {
        teardown()
        destructionStarted = true
        super.onDestroy()
        // Activity.onDestroy 可能早于窗口实际移除，必须等 decorView 脱离后再释放 UI 所有权。
        if (!window.decorView.isAttachedToWindow) owner?.activityDestroyed(this)
    }
    private fun cameraFailure(error: Throwable): CitizenSdkException = error as? CitizenSdkException
        ?: CitizenSdkException(CitizenSdkErrorCode.UNAVAILABLE, "无法采集相机帧", error)
    companion object { const val EXTRA_ID = "citizensdk.qr.flow"; private const val PERMISSION = 7132 }
}

/** 只核对 SDK 拥有的帧与 Surface 租约；不读取或终止别的用例仍使用的物理相机。 */
internal class CitizenSdkQrOwnedDrain {
    private var revoked = false
    private var framesReturned = false
    private var surfaces = 0
    fun surfaceBorrowed() { check(!revoked); surfaces += 1 }
    fun surfaceReturned() { check(surfaces > 0); surfaces -= 1 }
    fun revoke() { revoked = true }
    fun framesReturned() { framesReturned = true }
    fun isReady(): Boolean = revoked && framesReturned && surfaces == 0
}
