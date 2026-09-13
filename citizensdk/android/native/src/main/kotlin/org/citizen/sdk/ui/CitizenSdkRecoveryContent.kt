package org.citizen.sdk.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.TypedValue
import android.view.View
import java.nio.CharBuffer
import java.nio.ByteBuffer
import org.citizen.sdk.CitizenSdkErrorCode

/** 私有 JNI 回调只借用 direct buffer，不复制成 ByteArray/String，不等待 UI 或反调 Core。 */
internal class CitizenSdkPrivateKeyDisplayBuffer {
    private val gate = Any()
    private val characters = CharArray(66)
    private var closed = false
    private var populated = false
    private var viewId = 0L
    private var hostOperationId: Long? = null
    private var registerAuthentication: ((Long) -> Int)? = null
    private var lastCode: Int? = null
    private var listener: ((Int) -> Unit)? = null

    fun bind(id: Long) = synchronized(gate) {
        check(id != 0L && (viewId == 0L || viewId == id)); viewId = id
    }
    fun listen(value: (Int) -> Unit) {
        val code = synchronized(gate) { listener = value; lastCode }
        if (code != null) value(code)
    }
    fun bindAuthenticationRegistry(register: (Long) -> Int) = synchronized(gate) { registerAuthentication = register }
    @JvmSynthetic
    fun authorizing(id: Long, operationId: Long): Int = synchronized(gate) {
        if (closed) return@synchronized CitizenSdkErrorCode.CANCELLED.value
        if (id == 0L || id != viewId || operationId == 0L || hostOperationId != null) {
            return@synchronized CitizenSdkErrorCode.INTEGRITY.value
        }
        val register = registerAuthentication ?: return@synchronized CitizenSdkErrorCode.INTEGRITY.value
        val code = register(operationId)
        if (code == CitizenSdkErrorCode.OK.value) hostOperationId = operationId
        code
    }
    fun authenticationId(): Long? = synchronized(gate) { hostOperationId }
    @JvmSynthetic
    fun display(id: Long, bytes: ByteBuffer): Int = synchronized(gate) {
        if (!bytes.isDirect || bytes.capacity() != 32 || bytes.position() != 0 || bytes.remaining() != 32) {
            return@synchronized CitizenSdkErrorCode.INTEGRITY.value
        }
        if (closed || populated || id != viewId || id == 0L) {
            return@synchronized CitizenSdkErrorCode.CANCELLED.value
        }
        characters[0] = '0'; characters[1] = 'x'
        repeat(32) { index ->
            val byte = bytes.get(index).toInt() and 255
            val high = byte ushr 4; val low = byte and 15
            characters[2 + index * 2] = (if (high < 10) high + 48 else high + 87).toChar()
            characters[3 + index * 2] = (if (low < 10) low + 48 else low + 87).toChar()
        }
        populated = true
        CitizenSdkErrorCode.OK.value
    }
    @JvmSynthetic
    fun settled(id: Long, code: Int) {
        val callback = synchronized(gate) {
            if (id == 0L || (viewId != 0L && id != viewId)) return
            lastCode = code; listener
        }
        callback?.invoke(code)
    }
    fun draw(block: (CharArray) -> Unit) = synchronized(gate) {
        if (!closed && populated) block(characters)
    }
    fun clear() = synchronized(gate) { closed = true; populated = false; characters.fill('\u0000') }
    internal fun isClearedForTest(): Boolean = synchronized(gate) { closed && characters.all { it == '\u0000' } }
}

/** Draws recovery characters without constructing an immutable String. */
internal class CitizenSdkRecoveryContent(
    context: Context,
    private val privateKey: CitizenSdkPrivateKeyDisplayBuffer? = null,
) : View(context), AutoCloseable {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xff1a2b3c.toInt()
        if (privateKey != null) typeface = android.graphics.Typeface.MONOSPACE
        textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            if (privateKey == null) 15f else 13f,
            resources.displayMetrics,
        )
    }
    private var characters = CharArray(0)

    init {
        importantForAutofill = IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        setPadding(dp(14), dp(14), dp(14), dp(14))
        background = android.graphics.drawable.GradientDrawable().apply {
            setColor(if (privateKey == null) 0xffffffff.toInt() else 0x0fef4444)
            setStroke(dp(1), if (privateKey == null) 0xffe2e8f0.toInt() else 0x28ef4444)
            cornerRadius = dp(8).toFloat()
        }
    }

    @JvmSynthetic
    fun replace(source: CharBuffer) {
        characters.fill('\u0000')
        val copy = source.asReadOnlyBuffer()
        characters = CharArray(copy.remaining())
        copy.get(characters)
        requestLayout()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val lines = if (privateKey != null) 3 else (characters.count { it == ' ' } + 3) / 4
        val wanted = paddingTop + paddingBottom + (lines.coerceAtLeast(1) * paint.fontSpacing).toInt()
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), resolveSize(wanted, heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (privateKey != null) {
            // 仅按公开字体度量缩放，窄窗口也完整显示三行，不读取或复制秘密来量宽。
            paint.textScaleX = 1f
            val available = (width - paddingLeft - paddingRight).coerceAtLeast(1).toFloat()
            paint.textScaleX = minOf(1f, available / (paint.measureText("0") * 22))
            privateKey.draw { value ->
                repeat(3) { line ->
                    canvas.drawText(value, line * 22, 22, paddingLeft.toFloat(),
                        paddingTop - paint.ascent() + line * paint.fontSpacing, paint)
                }
            }
            return
        }
        if (characters.isEmpty()) return
        val wordsPerLine = 4
        var word = 0
        var start = 0
        var baseline = paddingTop - paint.ascent()
        for (index in 0..characters.size) {
            if (index == characters.size || characters[index] == ' ') {
                val prefix = charArrayOf(
                    ('0'.code + ((word + 1) / 10)).toChar(),
                    ('0'.code + ((word + 1) % 10)).toChar(),
                    '.',
                    ' ',
                )
                val column = word % wordsPerLine
                val columnWidth = (width - paddingLeft - paddingRight).toFloat() / wordsPerLine
                val x = paddingLeft + column * columnWidth
                canvas.drawText(prefix, 0, prefix.size, x, baseline, paint)
                canvas.drawText(characters, start, index - start, x + paint.measureText(prefix, 0, prefix.size), baseline, paint)
                word += 1
                if (word % wordsPerLine == 0) baseline += paint.fontSpacing
                start = index + 1
            }
        }
    }

    override fun close() {
        privateKey?.clear()
        characters.fill('\u0000')
        characters = CharArray(0)
        invalidate()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
