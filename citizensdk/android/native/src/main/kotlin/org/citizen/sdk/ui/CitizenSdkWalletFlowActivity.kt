package org.citizen.sdk.ui

import android.graphics.Color
import android.app.AlertDialog
import android.os.Bundle
import android.text.Editable
import android.text.InputFilter
import android.text.InputType
import android.text.TextWatcher
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import androidx.activity.OnBackPressedCallback
import androidx.fragment.app.FragmentActivity
import org.citizen.sdk.*
import org.citizen.sdk.internal.CitizenSdkSensitiveBytes
import java.nio.CharBuffer
import java.util.concurrent.CompletionException

/** Non-exported secure recovery-phrase creation/import/account-expansion UI. */
internal class CitizenSdkWalletFlowActivity : FragmentActivity() {
    @get:JvmSynthetic
    internal var flowId: Long = 0
        private set
    private var coordinator: CitizenSdkWalletFlowCoordinator? = null
    private var prepared: CitizenSdkPreparedWallet? = null
    private var phrase: CitizenSdkRecoveryPhrase? = null
    private var recoveryContent: CitizenSdkRecoveryContent? = null
    private var terminalResult: CitizenSdkWalletFlowContract.Result? = null
    private val secretInputs = LinkedHashSet<EditText>()
    private var inputRetry: ((Throwable) -> Unit)? = null
    private var privateKeyHadFocus = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() = finishCancelled()
            },
        )
        flowId = intent.getLongExtra(EXTRA_FLOW_ID, 0)
        coordinator = CitizenSdkWalletFlowCoordinator.consume(flowId)
        val owner = coordinator
        if (flowId == 0L || owner == null) {
            finish()
            return
        }
        owner.attach(this)
        if (isFinishing) return
        owner.sdk.attachActivity(this)
        owner.privateKeyView?.let {
            if (savedInstanceState != null) it.end(cancelled = true) else showPrivateKeyView(it)
            return
        }
        if (savedInstanceState != null) {
            // Recover the existing coordinator before cancelling. Secrets are
            // never saved, but the original caller must still receive exactly
            // one terminal result after its parent Activity resumes.
            if (owner.requestCancellationSettlement()) showMutationInProgress()
            else finishCancelled()
            return
        }
        when (val request = owner.request) {
            is CitizenSdkWalletFlowContract.Request.Create -> showCreate(request.wordCount)
            is CitizenSdkWalletFlowContract.Request.Import -> showRecoveryInput(null)
            is CitizenSdkWalletFlowContract.Request.AddAccounts -> showRecoveryInput(request.indices.toIntArray())
            null -> finishCancelled()
        }
    }

    override fun onDestroy() {
        val owner = coordinator
        if (owner?.privateKeyView != null) {
            recoveryContent?.close(); recoveryContent = null
            owner.privateKeyView.buffer.clear()
            runCatching { owner.sdk.detachActivity(this) }
            super.onDestroy()
            // 配置改变和外部销毁同样终止，绝不复用旧显示会话。
            owner.activityDestroyed(this, isChangingConfigurations)
            return
        }
        var cleanupFailure: Throwable? = null
        // EditText owns a mutable Editable that otherwise survives with the
        // destroyed View until GC. Wipe every registered secret input on Back,
        // cancellation, configuration change and external Activity teardown.
        val inputs = secretInputs.toList()
        secretInputs.clear()
        inputs.forEach { input ->
            runCatching { CitizenSdkSecretEditablePolicy.clear(input.text) }
                .onFailure { cleanupFailure = cleanupFailure ?: it }
        }
        runCatching { recoveryContent?.close() }
            .onFailure { cleanupFailure = cleanupFailure ?: it }
        runCatching { phrase?.close() }.onFailure { cleanupFailure = cleanupFailure ?: it }
        runCatching { owner?.retryPreparedRelease() ?: true }.onFailure {
            cleanupFailure = cleanupFailure ?: it
        }.onSuccess { terminal -> if (terminal) prepared = null }
        runCatching { owner?.sdk?.detachActivity(this) }.onFailure { cleanupFailure = cleanupFailure ?: it }
        owner?.activityDestroyed(this, isChangingConfigurations)
        val result = if (owner?.settlementInFlight() == true) {
            null
        } else if (cleanupFailure != null) {
            CitizenSdkWalletFlowContract.Result.Failed(
                cleanupFailure as? CitizenSdkException ?: CitizenSdkException(
                    CitizenSdkErrorCode.INTERNAL,
                    "CitizenSDK wallet flow cleanup failed",
                    cleanupFailure,
                ),
            )
        } else if (isChangingConfigurations) {
            null
        } else {
            terminalResult ?: if (isFinishing) CitizenSdkWalletFlowContract.Result.Cancelled else null
        }
        super.onDestroy()
        if (result != null) owner?.completeAfterTeardown(result)
    }

    override fun onPause() {
        coordinator?.privateKeyView?.let {
            recoveryContent?.visibility = android.view.View.INVISIBLE
            if (!it.isAuthenticating()) it.end(cancelled = true)
        }
        super.onPause()
    }

    override fun onStop() {
        // BiometricPrompt 的临时焦点变化不等于 onStop；真正后台永久撤销查看。
        coordinator?.privateKeyView?.end(cancelled = true)
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        privateKeyReady()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (coordinator?.privateKeyView != null) {
            if (hasFocus) { privateKeyHadFocus = true; privateKeyReady() }
            else {
                recoveryContent?.visibility = android.view.View.INVISIBLE
                if (privateKeyHadFocus && coordinator?.privateKeyView?.isAuthenticating() != true) {
                    coordinator?.privateKeyView?.end(cancelled = true)
                }
            }
        }
    }

    private fun showPrivateKeyView(owner: CitizenSdkPrivateKeyView) {
        val content = CitizenSdkRecoveryContent(this, owner.buffer)
        recoveryContent = content; content.visibility = android.view.View.INVISIBLE
        val warning = TextView(this).apply {
            text = "私钥可控制本账户。请确认周围无人、未共享屏幕；不能复制或分享。"
        }
        val reveal = Button(this).apply {
            text = "已理解风险，验证身份并查看"
            setOnClickListener { isEnabled = false; owner.reveal() }
        }
        val done = Button(this).apply {
            text = "关闭并清除"; setOnClickListener { owner.end(cancelled = !owner.isReady()) }
        }
        setContentView(layout(title("查看账户私钥"), warning, content, reveal, done))
    }

    @JvmSynthetic
    internal fun privateKeyReady() {
        val owner = coordinator?.privateKeyView ?: return
        recoveryContent?.visibility = if (owner.isReady() && hasWindowFocus() &&
            lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED) && !isFinishing
        ) android.view.View.VISIBLE else android.view.View.INVISIBLE
        recoveryContent?.invalidate()
    }

    @JvmSynthetic
    internal fun clearPrivateKeyAndFinish() {
        recoveryContent?.visibility = android.view.View.INVISIBLE
        recoveryContent?.close()
        finish()
    }

    private fun showCreate(wordCount: Int) {
        val password = secretInput("钱包密码（选填）")
        val words = wordSelector(wordCount)
        val errorText = TextView(this)
        val action = Button(this).apply { text = "生成助记词" }
        val cancel = Button(this).apply { text = "取消"; setOnClickListener { finishCancelled() } }
        setContentView(layout(title("创建钱包"), description(), words, password, errorText, action, cancel))
        inputRetry = { failure ->
            errorText.text = walletInputError(failure)
            password.isEnabled = true
            setSelectorEnabled(words, true)
            action.isEnabled = true
        }
        action.setOnClickListener {
            if (!action.isEnabled) return@setOnClickListener
            action.isEnabled = false
            try {
                CitizenSdkSensitiveBytes.utf8(password.text).use { coordinator!!.sdk.validateWalletPassword(it) }
                password.isEnabled = false
                setSelectorEnabled(words, false)
                confirmPasswordRisk(password.text.isNotEmpty(), {
                    password.isEnabled = true; setSelectorEnabled(words, true); action.isEnabled = true
                }) {
                    if (isFinishing || isDestroyed) return@confirmPasswordRisk
                    try {
                        val future = CitizenSdkSensitiveBytes.utf8(password.text).use { secret ->
                            coordinator!!.sdk.prepareWalletCreation(selectedWordCount(words), secret)
                        }
                        // 准备失败可保留原输入重试；成功进入备份页时统一擦除输入。
                        coordinator!!.acceptPreparation(future)
                    } catch (failure: Throwable) { inputRetry?.invoke(failure) }
                }
            } catch (failure: Throwable) {
                inputRetry?.invoke(failure)
            }
        }
    }

    @JvmSynthetic
    internal fun showBackupFromCoordinator(value: CitizenSdkPreparedWallet) {
        inputRetry = null
        secretInputs.forEach { CitizenSdkSecretEditablePolicy.clear(it.text) }
        prepared = value
        phrase = value.openRecoveryPhrase()
        val content = CitizenSdkRecoveryContent(this)
        recoveryContent = content
        phrase!!.useCharacters(content::replace)
        val warning = TextView(this).apply {
            text = CitizenSdkWalletInputPolicy.EXPLANATION
            setTextColor(Color.RED)
        }
        val confirm = Button(this).apply { text = "我已完成离线备份" }
        val cancel = Button(this).apply { text = "取消并清除"; setOnClickListener { finishCancelled() } }
        setContentView(layout(title("备份助记词"), warning, content, confirm, cancel))
        confirm.setOnClickListener {
            confirm.isEnabled = false
            content.close()
            phrase?.close()
            phrase = null
            val future = try {
                coordinator!!.sdk.commitPreparedWallet(value)
            } catch (error: Throwable) {
                finishFailed(error)
                return@setOnClickListener
            }
            coordinator!!.acceptIrreversible(future)
        }
    }

    private fun showRecoveryInput(indices: IntArray?) {
        val mnemonic = secretInput("助记词（仅本页内存）", multiline = true)
        val password = secretInput("钱包密码（选填）")
        val words = wordSelector(12)
        val counter = TextView(this)
        val suggestions = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val accountMode = RadioGroup(this).apply {
            orientation = RadioGroup.HORIZONTAL
            addView(RadioButton(context).apply { id = 1; text = "下一个账户" })
            addView(RadioButton(context).apply { id = 2; text = "指定编号" })
            check(2)
            visibility = if (indices == null) android.view.View.GONE else android.view.View.VISIBLE
        }
        val accountIndices = EditText(this).apply {
            hint = "账户编号 1—1989，逗号分隔"
            setText(indices?.joinToString(",") ?: "")
            visibility = accountMode.visibility
        }
        accountMode.setOnCheckedChangeListener { _, checked ->
            accountIndices.visibility = if (checked == 2) android.view.View.VISIBLE else android.view.View.GONE
        }
        val errorText = TextView(this)
        val action = Button(this).apply { text = if (indices == null) "导入钱包" else "添加账户" }
        val cancel = Button(this).apply { text = "取消"; setOnClickListener { finishCancelled() } }
        setContentView(layout(title(action.text.toString()), description(), words, accountMode, accountIndices, mnemonic, counter, suggestions, password, errorText, action, cancel))
        fun refreshWords() {
            val text = mnemonic.text
            val count = text.splitToSequence(Regex("\\s+")).count { it.isNotEmpty() }
            counter.text = "$count / ${selectedWordCount(words)} 词"
            if (count == selectedWordCount(words)) {
                try {
                    CitizenSdkSensitiveBytes.utf8(text).use { coordinator!!.sdk.validateWalletMnemonic(it, selectedWordCount(words)) }
                    counter.append(" · 校验通过")
                } catch (failure: Throwable) { counter.text = walletInputError(failure) }
            }
            suggestions.removeAllViews()
            if (!mnemonic.isEnabled) return
            val range = CitizenSdkWalletInputPolicy.completionRange(text, mnemonic.selectionStart, mnemonic.selectionEnd) ?: return
            val matches = runCatching {
                CitizenSdkSensitiveBytes.utf8(CharBuffer.wrap(text, range.first, mnemonic.selectionStart)).use { coordinator!!.sdk.walletWordSuggestions(it) }
            }.getOrDefault(emptyList())
            matches.forEach { word ->
                suggestions.addView(Button(this).apply {
                    this.text = word
                    setOnClickListener {
                        if (!mnemonic.isEnabled) return@setOnClickListener
                        val current = CitizenSdkWalletInputPolicy.completionRange(mnemonic.text, mnemonic.selectionStart, mnemonic.selectionEnd)
                            ?: return@setOnClickListener
                        val prefix = mnemonic.text.subSequence(current.first, mnemonic.selectionStart)
                        if (word.startsWith(prefix)) {
                            mnemonic.text.replace(current.first, current.second, word)
                            mnemonic.setSelection(current.first + word.length)
                        }
                    }
                })
            }
        }
        mnemonic.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) = refreshWords()
        })
        mnemonic.selectionChanged = { refreshWords() }
        words.setOnCheckedChangeListener { _, _ -> refreshWords() }
        refreshWords()
        fun enableInput(enabled: Boolean) {
            mnemonic.isEnabled = enabled; password.isEnabled = enabled
            setSelectorEnabled(words, enabled); setSelectorEnabled(accountMode, enabled)
            accountIndices.isEnabled = enabled
        }
        inputRetry = { failure -> errorText.text = walletInputError(failure); enableInput(true); action.isEnabled = true }
        action.setOnClickListener {
            if (!action.isEnabled) return@setOnClickListener
            action.isEnabled = false
            try {
                CitizenSdkSensitiveBytes.utf8(password.text).use { coordinator!!.sdk.validateWalletPassword(it) }
                CitizenSdkSensitiveBytes.utf8(mnemonic.text).use { coordinator!!.sdk.validateWalletMnemonic(it, selectedWordCount(words)) }
                val useNext = indices != null && accountMode.checkedRadioButtonId == 1
                val specified = if (indices != null && !useNext) CitizenSdkWalletInputPolicy.indices(accountIndices.text) else null
                enableInput(false)
                confirmPasswordRisk(indices == null && password.text.isNotEmpty(), {
                    enableInput(true); action.isEnabled = true
                }) {
                    fun submit(selected: IntArray?) {
                        if (isFinishing || isDestroyed) return
                        try {
                            val future = CitizenSdkSensitiveBytes.utf8(mnemonic.text).use { phraseBytes ->
                                CitizenSdkSensitiveBytes.utf8(password.text).use { passwordBytes ->
                                    if (selected == null) coordinator!!.sdk.importWallet(phraseBytes, passwordBytes)
                                    else coordinator!!.sdk.addWalletAccounts(phraseBytes, passwordBytes, selected)
                                }
                            }
                            // 已接受变更必须报告真实终态，不保留清空后的假重试入口。
                            CitizenSdkSecretEditablePolicy.clear(mnemonic.text)
                            CitizenSdkSecretEditablePolicy.clear(password.text)
                            coordinator!!.acceptIrreversible(future)
                        } catch (failure: Throwable) { inputRetry?.invoke(failure) }
                    }
                    if (useNext) coordinator!!.sdk.getWalletProfile().whenComplete { profile, failure ->
                        runOnUiThread {
                            if (isFinishing || isDestroyed) return@runOnUiThread
                            try {
                                if (failure != null) throw failure
                                requireNotNull(profile) { "钱包不存在" }
                                submit(CitizenSdkWalletInputPolicy.nextIndex(profile.accounts.map { it.index }))
                            } catch (error: Throwable) { inputRetry?.invoke(error) }
                        }
                    } else submit(specified)
                }
            } catch (failure: Throwable) { inputRetry?.invoke(failure) }
        }
    }

    @JvmSynthetic
    internal fun showPreparationFailure(failure: Throwable) {
        inputRetry?.invoke(failure) ?: finishFailed(failure)
    }

    private fun confirmPasswordRisk(required: Boolean, cancelled: () -> Unit, proceed: () -> Unit) {
        if (!required) { proceed(); return }
        AlertDialog.Builder(this).setTitle("钱包密码风险确认")
            .setMessage(CitizenSdkWalletInputPolicy.PASSWORD_WARNING)
            .setNegativeButton("取消") { _, _ -> cancelled() }
            .setPositiveButton("已理解，继续") { _, _ -> proceed() }
            .setOnCancelListener { cancelled() }.show()
    }

    private fun wordSelector(initial: Int) = RadioGroup(this).apply {
        orientation = RadioGroup.HORIZONTAL
        listOf(12, 18, 24).forEach { words -> addView(RadioButton(context).apply { id = words; text = "$words 词" }) }
        check(initial)
    }

    private fun selectedWordCount(selector: RadioGroup) = selector.checkedRadioButtonId
    private fun setSelectorEnabled(selector: RadioGroup, enabled: Boolean) {
        for (index in 0 until selector.childCount) selector.getChildAt(index).isEnabled = enabled
    }
    private fun description() = TextView(this).apply { text = CitizenSdkWalletInputPolicy.EXPLANATION }
    private fun walletInputError(failure: Throwable): String {
        val cause = (failure as? CompletionException)?.cause ?: failure
        return (cause as? CitizenSdkException)?.message ?: "钱包输入无效，请检查后重试。"
    }

    @JvmSynthetic
    internal fun finishWithTerminal(result: CitizenSdkWalletFlowContract.Result) = runOnUiThread {
        val cleanupFailure = coordinator?.settlePreparedForTerminal(result)
        if (cleanupFailure == null) prepared = null
        // Keep the original terminal result while onDestroy performs a second
        // release attempt. Only a repeated failure is reported as cleanup error.
        terminalResult = result
        finish()
    }

    private fun finishCancelled() {
        coordinator?.privateKeyView?.let { it.end(cancelled = true); return }
        if (coordinator?.requestCancellationSettlement() == true) {
            showMutationInProgress()
            return
        }
        if (terminalResult == null) terminalResult = CitizenSdkWalletFlowContract.Result.Cancelled
        finish()
    }

    private fun finishFailed(failure: Throwable) {
        val cause = (failure as? CompletionException)?.cause ?: failure
        val error = cause as? CitizenSdkException ?: CitizenSdkException(
            CitizenSdkErrorCode.INTERNAL,
            "CitizenSDK wallet flow failed",
            cause,
        )
        terminalResult = CitizenSdkWalletFlowContract.Result.Failed(error)
        finish()
    }

    @JvmSynthetic
    internal fun requestCancellation(force: Boolean = false) = runOnUiThread {
        if (force && coordinator?.requiresTruthfulTerminal() != true) {
            terminalResult = CitizenSdkWalletFlowContract.Result.Cancelled
        }
        finishCancelled()
    }

    private fun showMutationInProgress() {
        val status = TextView(this).apply {
            text = "钱包操作已提交，正在等待安全存储完成。完成前不能取消。"
            setTextColor(Color.BLACK)
        }
        setContentView(layout(title("正在完成钱包操作"), status))
    }

    private fun title(value: String) = TextView(this).apply {
        text = value
        textSize = 24f
        setTextColor(Color.BLACK)
    }

    private fun secretInput(hintValue: String, multiline: Boolean = false) =
        CitizenSdkWalletInputEditText(this).apply {
            hint = hintValue
            importantForAutofill = android.view.View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            setAutofillHints(*emptyArray())
            // Core accepts at most 1024 UTF-8 bytes. floor(1024 / 3) UTF-16
            // code units is deliberately stricter, so even all three-byte BMP
            // input stays inside that bound without affecting 24-word phrases.
            filters = arrayOf(
                InputFilter.LengthFilter(
                    CitizenSdkSecretEditablePolicy.MAX_INPUT_UTF16_CODE_UNITS,
                ),
            )
            inputType = if (multiline) {
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                    InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            } else {
                InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            }
            if (multiline) minLines = 4
            imeOptions = imeOptions or android.view.inputmethod.EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        }.also { secretInputs.add(it) }

    private fun layout(vararg children: android.view.View) = ScrollView(this).apply {
        addView(LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(48, 64, 48, 48)
            children.forEach { child ->
                addView(
                    child,
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { bottomMargin = 24 },
                )
            }
        })
    }

    companion object {
        internal const val EXTRA_FLOW_ID = "org.citizen.sdk.wallet.FLOW_ID"
    }
}

/** 仅公开编号与固定提示；密码和 BIP39 算法始终由 Rust Core 校验。 */
internal object CitizenSdkWalletInputPolicy {
    const val EXPLANATION = "热钱包不持久保存助记词，关闭后不能再次显示。请离线备份。钱包密码为选填的派生盐值，不是 App 登录密码；非空密码须单独记住，恢复时必须相同。相同助记词使用不同密码会得到不同账户。"
    const val PASSWORD_WARNING = "钱包密码参与账户派生，不是 App 登录密码。必须同时保管助记词和该密码；密码丢失无法恢复原账户。请确认已理解此风险。"

    fun indices(text: CharSequence): IntArray {
        val values = text.split(Regex("[,，\\s]+")).filter { it.isNotEmpty() }.map {
            it.toIntOrNull() ?: throw CitizenSdkException(CitizenSdkErrorCode.INVALID_ARGUMENT, "账户编号必须为整数")
        }
        return CitizenSdkWalletFlowContract.Request.AddAccounts(values).indices.toIntArray()
    }

    fun nextIndex(indices: List<Long>): IntArray {
        require(indices.all { it in 0L..1989L }) { "账户编号超出范围" }
        val maximum = indices.maxOrNull() ?: 0L
        require(maximum < 1989) { "已到达最大账户编号 1989" }
        return intArrayOf((maximum + 1).toInt())
    }

    fun completionRange(text: CharSequence, selectionStart: Int, selectionEnd: Int): Pair<Int, Int>? {
        if (selectionStart != selectionEnd || selectionStart !in 0..text.length) return null
        var start = selectionStart
        while (start > 0 && !text[start - 1].isWhitespace()) start--
        if (start == selectionStart) return null
        var end = selectionStart
        while (end < text.length && !text[end].isWhitespace()) end++
        return start to end
    }
}

/** 光标移动也刷新本地补全，防止旧按钮修改其他单词。 */
internal class CitizenSdkWalletInputEditText(context: android.content.Context) : EditText(context) {
    var selectionChanged: (() -> Unit)? = null
    override fun onSelectionChanged(start: Int, end: Int) {
        super.onSelectionChanged(start, end)
        selectionChanged?.invoke()
    }
}

/** Overwrites and clears the mutable UI buffer without constructing a secret String. */
internal object CitizenSdkSecretEditablePolicy {
    const val MAX_INPUT_UTF16_CODE_UNITS = CitizenSdkInputLimits.MAX_WALLET_SECRET_BYTES / 3
    private const val WIPE_CHUNK_CODE_UNITS = 64

    @JvmSynthetic
    fun clear(editable: Editable) {
        // Never allocate in proportion to attacker-controlled pasted input.
        // This also handles legacy Editable values that bypassed the filter.
        val zeros = CharArray(WIPE_CHUNK_CODE_UNITS)
        try {
            var offset = 0
            while (offset < editable.length) {
                val count = minOf(WIPE_CHUNK_CODE_UNITS, editable.length - offset)
                editable.replace(
                    offset,
                    offset + count,
                    CharBuffer.wrap(zeros, 0, count),
                )
                offset += count
            }
        } finally {
            zeros.fill('\u0000')
            editable.clear()
        }
    }
}
