import Foundation

#if os(iOS)
import UIKit
import CoreText

public extension CitizenSdk {
    /// 仅在 SDK 自有安全界面查看账户私钥；公开操作不返回秘密、内部句柄或显示回调。
    @MainActor
    func viewAccountPrivateKey(from presenter: UIViewController, accountID: Data) throws -> CitizenSDKOperation<Void> {
        guard presenter.viewIfLoaded?.window != nil, UIApplication.shared.applicationState == .active else {
            throw CitizenSDKError(.unavailable, "private key view requires a foreground presenter")
        }
        let flow = try CitizenSDKPrivateKeyView(sdk: self, accountID: accountID)
        let controller = CitizenSDKPrivateKeyViewController(flow: flow)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        navigation.isModalInPresentation = true
        presenter.present(navigation, animated: true)
        return flow.operation
    }

    /// Presents the only supported secret-entry/recovery interface. No secret
    /// is an argument or result of this API.
    @MainActor
    func presentWalletFlow(from presenter: UIViewController, request: CitizenSDKWalletFlowRequest,
                           completion: @escaping (CitizenSDKWalletFlowResult) -> Void) throws -> CitizenSDKWalletFlow {
        let request = try citizenSDKValidateWalletFlowRequest(request)
        try citizenSDKRequireWalletUI(capabilities())
        let token = try CitizenSDKWalletFlowRegistry.shared.reserve(self)
        let controller = CitizenSDKWalletViewController(sdk: self, request: request) { [weak self] result in
            guard let self else { return }
            CitizenSDKWalletFlowRegistry.shared.finish(self, token: token)
            completion(result)
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        // Interactive dismissal would bypass prepared-secret cleanup and the
        // registry's exactly-once completion boundary.
        navigation.isModalInPresentation = true
        presenter.present(navigation, animated: true)
        return CitizenSDKWalletFlow { [weak controller] in
            DispatchQueue.main.async { controller?.requestCancel() }
        }
    }
}

/// 私钥不进入 UITextView/UILabel；绘图只临时借用可擦字符与 glyph 数组。
@MainActor
private final class CitizenSDKPrivateKeyContentIOS: UIView {
    let buffer: CitizenSDKPrivateKeyDisplayBuffer
    var onRemoval: (() -> Void)?
    private var wasAttached = false
    init(buffer: CitizenSDKPrivateKeyDisplayBuffer) {
        self.buffer = buffer
        super.init(frame: .zero)
        isOpaque = true; backgroundColor = .systemBackground
        isAccessibilityElement = false; accessibilityElementsHidden = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { wasAttached = true }
        else if wasAttached { onRemoval?() }
    }
    override func draw(_ rect: CGRect) {
        guard !isHidden, let context = UIGraphicsGetCurrentContext() else { return }
        let font = CTFontCreateWithName("Menlo" as CFString, 18, nil)
        context.setFillColor(UIColor.label.cgColor)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        buffer.withCharacters { characters in
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            defer { for index in glyphs.indices { glyphs[index] = 0 } }
            guard CTFontGetGlyphsForCharacters(font, characters.baseAddress!, &glyphs, characters.count) else { return }
            var positions = (0..<characters.count).map {
                CGPoint(x: 8 + ($0 % 22) * 11, y: Int(self.bounds.height) - 28 - ($0 / 22) * 28)
            }
            CTFontDrawGlyphs(font, &glyphs, &positions, characters.count, context)
        }
    }
}

@MainActor
private final class CitizenSDKPrivateKeyViewController: UIViewController {
    private let flow: CitizenSDKPrivateKeyView
    private let content: CitizenSDKPrivateKeyContentIOS
    private let status = UILabel()
    private let reveal = UIButton(type: .system)
    private let done = UIButton(type: .system)
    private var tokens: [NSObjectProtocol] = []
    private var ending = false
    private var ready = false
    private var security: CitizenSDKScreenSecurity?

    init(flow: CitizenSDKPrivateKeyView) {
        self.flow = flow; content = CitizenSDKPrivateKeyContentIOS(buffer: flow.buffer)
        super.init(nibName: nil, bundle: nil)
        content.onRemoval = { [weak flow] in flow?.finish(cancelled: true) }
        flow.onReady = { [weak self] in self?.ready = true; self?.refreshVisibility() }
        flow.onClear = { [weak self] in
            self?.ending = true; self?.content.isHidden = true
            self?.content.setNeedsDisplay(); self?.reveal.isEnabled = false; self?.done.isEnabled = false
        }
        flow.onTerminal = { [weak self] completion in
            guard let self else { completion(); return }
            self.tokens.forEach(NotificationCenter.default.removeObserver); self.tokens.removeAll()
            self.content.isHidden = true
            if self.presentingViewController != nil {
                self.dismiss(animated: false) { [self] in self.security?.finish(); completion() }
            } else { self.security?.finish(); completion() }
            // 只在视图已经退出后移除截图遮盖和观察者。
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad(); title = "查看账户私钥"; view.backgroundColor = .systemBackground
        status.text = "私钥可控制本账户。请确认周围无人、未共享屏幕；不能复制或分享。"
        status.numberOfLines = 0
        content.isHidden = true
        content.heightAnchor.constraint(equalToConstant: 120).isActive = true
        reveal.setTitle("已理解风险，验证身份并查看", for: .normal)
        reveal.addTarget(self, action: #selector(revealPressed), for: .touchUpInside)
        done.setTitle("关闭并清除", for: .normal)
        done.addTarget(self, action: #selector(donePressed), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelPressed))
        let stack = UIStackView(arrangedSubviews: [status, content, reveal, done])
        stack.axis = .vertical; stack.spacing = 20
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
        security = CitizenSDKScreenSecurity(view: view)
        let center = NotificationCenter.default
        tokens = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.content.isHidden = true
                    if !self.flow.isAuthenticating { self.flow.finish(cancelled: true) }
                }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVisibility() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flow.finish(cancelled: true) }
            },
            center.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVisibility() }
            },
        ]
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 被宿主移除不能复活；系统认证的短暂失焦只由通知遮盖，不走此销毁边界。
        if !ending { flow.finish(cancelled: true) }
    }
    private func refreshVisibility() {
        content.isHidden = ending || !ready || UIApplication.shared.applicationState != .active || UIScreen.main.isCaptured
        content.setNeedsDisplay()
    }
    @objc private func revealPressed() {
        guard reveal.isEnabled else { return }
        reveal.isEnabled = false; flow.reveal()
    }
    @objc private func donePressed() { flow.finish(cancelled: !ready) }
    @objc private func cancelPressed() { flow.finish(cancelled: true) }
}

@MainActor
private final class CitizenSDKWalletViewController: UIViewController, UITextViewDelegate {
    private let sdk: CitizenSdk
    private let request: CitizenSDKWalletFlowRequest
    private let completion: (CitizenSDKWalletFlowResult) -> Void
    private let mnemonic = UITextView()
    private let password = UITextField()
    private let wordCount = UISegmentedControl(items: ["12 词", "18 词", "24 词"])
    private let accountMode = UISegmentedControl(items: ["下一个账户", "指定编号"])
    private let accountIndices = UITextField()
    private let wordStatus = UILabel()
    private let suggestions = UIStackView()
    private let action = UIButton(type: .system)
    private let status = UILabel()
    private let backup = UISwitch()
    private let backupLabel = UILabel()
    private var prepared: CitizenSDKPreparedWallet?
    private var phrase: CitizenSDKRecoveryPhrase?
    private var task: Task<Void, Never>?
    private var cancelRequested = false
    private var irreversible = false
    private var finished = false
    private var screenSecurity: CitizenSDKScreenSecurity?

    init(sdk: CitizenSdk, request: CitizenSDKWalletFlowRequest,
         completion: @escaping (CitizenSDKWalletFlowResult) -> Void) {
        self.sdk = sdk
        self.request = request
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "钱包操作"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                            target: self, action: #selector(cancelPressed))
        configureControls()
        screenSecurity = CitizenSDKScreenSecurity(view: view)
    }

    private func configureControls() {
        mnemonic.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        mnemonic.layer.borderWidth = 1
        mnemonic.layer.borderColor = UIColor.separator.cgColor
        mnemonic.layer.cornerRadius = 8
        mnemonic.autocorrectionType = .no
        mnemonic.autocapitalizationType = .none
        mnemonic.spellCheckingType = .no
        mnemonic.smartQuotesType = .no
        mnemonic.smartDashesType = .no
        mnemonic.smartInsertDeleteType = .no
        mnemonic.accessibilityLabel = "助记词"
        mnemonic.delegate = self
        mnemonic.heightAnchor.constraint(equalToConstant: 150).isActive = true

        password.placeholder = "钱包密码（选填）"
        password.isSecureTextEntry = true
        // This SDK-owned password must never be offered to AutoFill/Keychain.
        password.textContentType = nil
        password.autocorrectionType = .no
        password.smartQuotesType = .no
        password.smartDashesType = .no
        password.smartInsertDeleteType = .no
        wordCount.selectedSegmentIndex = 0
        wordCount.addTarget(self, action: #selector(wordCountChanged), for: .valueChanged)
        accountMode.selectedSegmentIndex = 1
        accountMode.addTarget(self, action: #selector(accountModeChanged), for: .valueChanged)
        accountIndices.placeholder = "账户编号 1—1989，逗号分隔"
        accountIndices.keyboardType = .numbersAndPunctuation
        accountIndices.autocorrectionType = .no
        suggestions.axis = .horizontal
        suggestions.distribution = .fillProportionally
        wordStatus.numberOfLines = 0

        status.numberOfLines = 0
        status.textColor = .secondaryLabel
        backupLabel.text = "我已在离线安全位置备份助记词"
        backupLabel.numberOfLines = 0

        action.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        action.configuration = .filled()
        let backupRow = UIStackView(arrangedSubviews: [backup, backupLabel])
        backupRow.axis = .horizontal
        backupRow.spacing = 12
        backupRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [status, wordCount, accountMode, accountIndices, mnemonic, wordStatus, suggestions, password, backupRow, action])
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
        ])

        backupRow.isHidden = true
        accountMode.isHidden = true
        accountIndices.isHidden = true
        status.text = CitizenSDKWalletInput.explanation
        switch request {
        case let .create(words):
            wordCount.selectedSegmentIndex = CitizenSDKWalletInput.wordCounts.firstIndex(of: words) ?? 0
            mnemonic.isHidden = true
            wordStatus.isHidden = true
            action.setTitle("生成钱包", for: .normal)
        case .importWallet:
            action.setTitle("导入钱包", for: .normal)
        case let .addAccounts(indices):
            accountMode.isHidden = false
            accountIndices.isHidden = false
            accountIndices.text = indices.map(String.init).joined(separator: ",")
            action.setTitle("添加账户", for: .normal)
        }
        refreshWords()
    }

    private var selectedWords: UInt32 { CitizenSDKWalletInput.wordCounts[wordCount.selectedSegmentIndex] }
    @objc private func wordCountChanged() { refreshWords() }
    @objc private func accountModeChanged() { accountIndices.isHidden = accountMode.selectedSegmentIndex == 0 }
    func textViewDidChange(_ textView: UITextView) { refreshWords() }
    func textViewDidChangeSelection(_ textView: UITextView) { refreshWords() }

    private func refreshWords() {
        guard prepared == nil else { return }
        let words = mnemonic.text.split(whereSeparator: { $0.isWhitespace })
        wordStatus.text = "\(words.count) / \(selectedWords) 词"
        if words.count == Int(selectedWords) {
            do { try CitizenSDKWalletInput.validateMnemonic(mnemonic.text, wordCount: selectedWords); wordStatus.text! += " · 校验通过" }
            catch { wordStatus.text = citizenSDKFlowError(error).message }
        }
        suggestions.arrangedSubviews.forEach { suggestions.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard mnemonic.isEditable,
              let completion = CitizenSDKWalletInput.completion(mnemonic.text, selection: mnemonic.selectedRange) else { return }
        for candidate in (try? CitizenSDKWalletInput.suggestions(completion.prefix)) ?? [] {
            let button = UIButton(type: .system)
            button.setTitle(candidate, for: .normal)
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.task == nil else { return }
                let text = self.mnemonic.text ?? ""
                guard let current = CitizenSDKWalletInput.completion(text, selection: self.mnemonic.selectedRange),
                      candidate.hasPrefix(current.prefix), let range = Range(current.range, in: text) else { return }
                self.mnemonic.text = text.replacingCharacters(in: range, with: candidate)
                self.mnemonic.selectedRange = NSRange(location: current.range.location + candidate.utf16.count, length: 0)
                self.refreshWords()
            }, for: .touchUpInside)
            suggestions.addArrangedSubview(button)
        }
    }

    private func setInputEnabled(_ enabled: Bool) {
        password.isEnabled = enabled
        mnemonic.isEditable = enabled
        wordCount.isEnabled = enabled
        accountMode.isEnabled = enabled
        accountIndices.isEnabled = enabled
        suggestions.isUserInteractionEnabled = enabled
    }

    @objc private func actionPressed() {
        guard task == nil else { return }
        action.isEnabled = false
        if prepared != nil { commitCreatedWallet(); return }
        do {
            try CitizenSDKWalletInput.validatePassword(password.text ?? "")
            if case .create = request { } else { try CitizenSDKWalletInput.validateMnemonic(mnemonic.text, wordCount: selectedWords) }
            if CitizenSDKWalletInput.requiresRiskConfirmation(password: password.text ?? "", request: request) {
                setInputEnabled(false)
                let alert = UIAlertController(title: "钱包密码风险确认", message: CitizenSDKWalletInput.passwordWarning, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.setInputEnabled(true); self?.action.isEnabled = true })
                alert.addAction(UIAlertAction(title: "已理解，继续", style: .default) { [weak self] _ in
                    guard let self, !self.finished, !self.cancelRequested else { return }
                    self.beginOperation()
                })
                present(alert, animated: true)
            } else { beginOperation() }
        } catch { fail(error) }
    }

    private func beginOperation() {
        do {
            let passwordText = password.text ?? ""
            let passwordBuffer = try citizenSDKSensitiveText(passwordText, label: "password")
            setInputEnabled(false)
            switch request {
            case .create:
                let wordCount = selectedWords
                task = Task { [weak self] in
                    guard let self else { return }
                    defer { self.task = nil }
                    do {
                        if self.cancelRequested { passwordBuffer.clear(); self.finish(.cancelled); return }
                        let prepared = try await self.sdk.prepareWallet(wordCount: wordCount, password: passwordBuffer)
                        passwordBuffer.clear()
                        if self.cancelRequested {
                            self.finish(citizenSDKPreparedCancellationResult { try prepared.release() })
                            return
                        }
                        self.prepared = prepared
                        let phrase = try prepared.recoveryPhrase()
                        self.phrase = phrase
                        try phrase.render { self.mnemonic.text = $0 }
                        self.mnemonic.isEditable = false
                        self.mnemonic.isSelectable = false
                        self.mnemonic.isHidden = false
                        self.password.isHidden = true
                        self.password.text = nil
                        self.wordCount.isHidden = true
                        self.wordStatus.isHidden = true
                        self.suggestions.isHidden = true
                        self.status.text = CitizenSDKWalletInput.explanation
                        self.backup.superview?.isHidden = false
                        self.action.setTitle("确认备份并创建", for: .normal)
                        self.action.isEnabled = true
                    } catch {
                        passwordBuffer.clear(); self.fail(error)
                    }
                }
            case .importWallet:
                let mnemonicBuffer = try citizenSDKSensitiveText(mnemonic.text, label: "mnemonic")
                task = Task { [weak self] in
                    guard let self else { return }
                    defer { mnemonicBuffer.clear(); passwordBuffer.clear(); self.task = nil }
                    do {
                        if self.cancelRequested {
                            citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) { self.finish(.cancelled) }
                            return
                        }
                        self.irreversible = true
                        let profile = try await self.sdk.importWallet(mnemonic: mnemonicBuffer, password: passwordBuffer)
                        citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) {
                            self.finish(.completed(profile))
                        }
                    } catch {
                        citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) { self.fail(error) }
                    }
                }
            case let .addAccounts(indices):
                let mnemonicBuffer = try citizenSDKSensitiveText(mnemonic.text, label: "mnemonic")
                let useNext = accountMode.selectedSegmentIndex == 0
                let selectedIndices = useNext ? indices : try CitizenSDKWalletInput.indices(accountIndices.text ?? "")
                task = Task { [weak self] in
                    guard let self else { return }
                    defer { mnemonicBuffer.clear(); passwordBuffer.clear(); self.task = nil }
                    do {
                        let actualIndices: [UInt32]
                        if useNext {
                            guard let profile = try await self.sdk.walletProfile() else { throw CitizenSDKError(.notFound, "钱包不存在") }
                            actualIndices = try CitizenSDKWalletInput.nextIndex(profile.accounts.map(\.index))
                        } else { actualIndices = selectedIndices }
                        if self.cancelRequested { self.irreversible = false; throw CitizenSDKError(.cancelled, "已取消") }
                        self.irreversible = true
                        let profile = try await self.sdk.addWalletAccounts(
                            mnemonic: mnemonicBuffer, password: passwordBuffer, indices: actualIndices
                        )
                        citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) {
                            self.finish(.completed(profile))
                        }
                    } catch {
                        citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) { self.fail(error) }
                    }
                }
            }
        } catch { fail(error) }
    }

    private func commitCreatedWallet() {
        guard backup.isOn, let prepared else {
            status.text = "请先确认已安全备份助记词。"
            action.isEnabled = true
            return
        }
        mnemonic.text = nil
        phrase?.clear(); phrase = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                if self.cancelRequested { self.finish(citizenSDKPreparedCancellationResult { try prepared.release() }); return }
                self.irreversible = true
                self.finish(.completed(try await self.sdk.commit(prepared)))
            }
            catch { self.fail(error) }
        }
    }

    @objc private func cancelPressed() { requestCancel() }
    func requestCancel() {
        guard !finished else { return }
        cancelRequested = true
        mnemonic.text = nil
        password.text = nil
        phrase?.clear(); phrase = nil
        if task == nil {
            let result = prepared.map { prepared in
                citizenSDKPreparedCancellationResult { try prepared.release() }
            } ?? .cancelled
            prepared = nil
            finish(result)
        } else {
            status.text = "正在安全结束当前钱包操作…"
        }
    }

    private func fail(_ error: Error) {
        if let result = citizenSDKCancellationResult(cancelRequested: cancelRequested,
                                                     irreversible: irreversible, error: error) {
            finish(result); return
        }
        status.text = citizenSDKFlowError(error).message
        // 提交或助记词展示失败后不能复用已消费的准备句柄。
        if let prepared {
            do { try prepared.release() } catch { finish(.failed(citizenSDKFlowError(error))); return }
            self.prepared = nil
            finish(.failed(citizenSDKFlowError(error))); return
        }
        irreversible = false
        setInputEnabled(true)
        action.isEnabled = true
    }

    private func finish(_ result: CitizenSDKWalletFlowResult) {
        guard !finished else { return }
        finished = true
        screenSecurity?.finish(); screenSecurity = nil
        mnemonic.text = nil
        password.text = nil
        phrase?.clear(); phrase = nil
        prepared = nil
        dismiss(animated: true) { self.completion(result) }
    }
}
#endif
