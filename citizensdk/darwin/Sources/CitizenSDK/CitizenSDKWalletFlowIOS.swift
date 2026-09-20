import Foundation

#if os(iOS)
import UIKit
import CoreText
import LocalAuthentication

private enum CitizenSDKWalletThemeIOS {
    static let scaffold = UIColor(red: CGFloat(0xF7) / 255, green: CGFloat(0xF9) / 255,
                                  blue: CGFloat(0xFC) / 255, alpha: 1)
    static let surface = UIColor.white
    static let primary = UIColor(red: 0, green: CGFloat(0x7A) / 255, blue: CGFloat(0x74) / 255, alpha: 1)
    static let textPrimary = UIColor(red: CGFloat(0x1A) / 255, green: CGFloat(0x2B) / 255,
                                     blue: CGFloat(0x3C) / 255, alpha: 1)
    static let textSecondary = UIColor(red: CGFloat(0x5A) / 255, green: CGFloat(0x6B) / 255,
                                       blue: CGFloat(0x7C) / 255, alpha: 1)
    static let border = UIColor(red: CGFloat(0xE2) / 255, green: CGFloat(0xE8) / 255,
                                blue: CGFloat(0xF0) / 255, alpha: 1)
    static let danger = UIColor(red: CGFloat(0xEF) / 255, green: CGFloat(0x44) / 255,
                                blue: CGFloat(0x44) / 255, alpha: 1)
}

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
        isOpaque = true
        backgroundColor = CitizenSDKWalletThemeIOS.danger.withAlphaComponent(0.06)
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = CitizenSDKWalletThemeIOS.danger.withAlphaComponent(0.16).cgColor
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
        let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)
        context.setFillColor(CitizenSDKWalletThemeIOS.textPrimary.cgColor)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        buffer.withCharacters { characters in
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            defer { for index in glyphs.indices { glyphs[index] = 0 } }
            guard CTFontGetGlyphsForCharacters(font, characters.baseAddress!, &glyphs, characters.count) else { return }
            var positions = (0..<characters.count).map {
                CGPoint(x: 14 + ($0 % 22) * 9, y: Int(self.bounds.height) - 28 - ($0 / 22) * 24)
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
    private let dangerNote = UILabel()
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
        super.viewDidLoad(); title = "查看私钥"; view.backgroundColor = CitizenSDKWalletThemeIOS.scaffold
        status.text = "私钥泄露将导致该账户资产被盗（仅该账户，不影响本钱包其他账户）。\n\n确认要查看吗？"
        status.numberOfLines = 0
        status.textColor = CitizenSDKWalletThemeIOS.textPrimary
        dangerNote.text = "请手抄备份，不支持复制；导出即等于该账户控制权"
        dangerNote.textColor = CitizenSDKWalletThemeIOS.danger
        dangerNote.font = .systemFont(ofSize: 12, weight: .medium)
        dangerNote.numberOfLines = 0
        content.isHidden = true
        content.heightAnchor.constraint(equalToConstant: 120).isActive = true
        reveal.setTitle("查看", for: .normal)
        reveal.tintColor = CitizenSDKWalletThemeIOS.danger
        reveal.addTarget(self, action: #selector(revealPressed), for: .touchUpInside)
        done.setTitle("关闭", for: .normal)
        done.addTarget(self, action: #selector(donePressed), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelPressed))
        let stack = UIStackView(arrangedSubviews: [status, content, dangerNote, reveal, done])
        stack.axis = .vertical; stack.spacing = 12
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
    private let wordCount = UISegmentedControl(items: ["12 个助记词 · 推荐", "18 个助记词", "24 个助记词"])
    private let accountMode = UISegmentedControl(items: ["下一个账户", "指定编号"])
    private let accountIndices = UITextField()
    private let wordStatus = UILabel()
    private let suggestions = UIStackView()
    private let action = UIButton(type: .system)
    private let importHot = UIButton(type: .system)
    private let importCold = UIButton(type: .system)
    private let reprobe = UIButton(type: .system)
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
    private var initializationContent: CitizenSDKWalletInitializationContent?
    private enum InitializationMode { case create, importHot, importCold }
    private var initializationMode: InitializationMode = .create

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
        view.backgroundColor = CitizenSDKWalletThemeIOS.scaffold
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                            target: self, action: #selector(cancelPressed))
        configureControls()
        if case .initialize = request { navigationItem.leftBarButtonItem = nil }
        screenSecurity = CitizenSDKScreenSecurity(view: view)
    }

    private func configureControls() {
        mnemonic.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        mnemonic.layer.borderWidth = 1
        mnemonic.layer.borderColor = CitizenSDKWalletThemeIOS.border.cgColor
        mnemonic.layer.cornerRadius = 12
        mnemonic.backgroundColor = CitizenSDKWalletThemeIOS.surface
        mnemonic.textColor = CitizenSDKWalletThemeIOS.textPrimary
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
        password.borderStyle = .roundedRect
        password.backgroundColor = CitizenSDKWalletThemeIOS.surface
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
        status.textColor = CitizenSDKWalletThemeIOS.textSecondary
        backupLabel.text = "我已备份"
        backupLabel.numberOfLines = 0

        action.addTarget(self, action: #selector(actionPressed), for: .touchUpInside)
        action.configuration = .filled()
        action.tintColor = CitizenSDKWalletThemeIOS.primary
        importHot.addTarget(self, action: #selector(importHotPressed), for: .touchUpInside)
        importCold.addTarget(self, action: #selector(importColdPressed), for: .touchUpInside)
        reprobe.setTitle("重新检测", for: .normal)
        reprobe.addTarget(self, action: #selector(reprobeDeviceSecurity), for: .touchUpInside)
        let backupRow = UIStackView(arrangedSubviews: [backup, backupLabel])
        backupRow.axis = .horizontal
        backupRow.spacing = 12
        backupRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [status, reprobe, wordCount, accountMode, accountIndices, mnemonic, wordStatus, suggestions, password, backupRow, action, importHot, importCold])
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
        reprobe.isHidden = true
        accountMode.isHidden = true
        accountIndices.isHidden = true
        status.text = CitizenSDKWalletInput.explanation
        switch request {
        case let .initialize(words, content):
            initializationContent = content
            title = "创建钱包"
            wordCount.selectedSegmentIndex = words == 18 ? 1 : words == 24 ? 2 : 0
            mnemonic.isHidden = true
            wordStatus.isHidden = true
            status.text = content.walletAccountRoleText + "\n\n" +
                content.walletAuthorizationText + "\n\n" + content.walletCompletionText
            action.setTitle("创建钱包", for: .normal)
            importHot.setTitle("已有钱包？导入助记词", for: .normal)
            importCold.setTitle("导入冷钱包", for: .normal)
            applyDeviceSecurityGate()
        case let .importColdAccount(text):
            initializationMode = .importCold
            title = "导入冷钱包"
            status.text = text
            wordCount.isHidden = true; wordStatus.isHidden = true; suggestions.isHidden = true
            password.isHidden = true; mnemonic.isHidden = false
            mnemonic.isEditable = true; mnemonic.isSelectable = true
            mnemonic.accessibilityLabel = "冷钱包账户地址"
            action.setTitle("确认导入", for: .normal)
            importHot.setTitle("扫描钱包二维码", for: .normal)
            importHot.removeTarget(self, action: #selector(importHotPressed), for: .touchUpInside)
            importHot.addTarget(self, action: #selector(scanColdAccount), for: .touchUpInside)
            importCold.setTitle("取消", for: .normal)
            importCold.removeTarget(self, action: #selector(importColdPressed), for: .touchUpInside)
            importCold.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
        case let .create(words):
            title = "创建钱包"
            wordCount.selectedSegmentIndex = words == 18 ? 1 : words == 24 ? 2 : 0
            mnemonic.isHidden = true
            wordStatus.isHidden = true
            status.text = "请务必妥善保存助记词和钱包密码（如设置），若丢失或遗忘将永久无法找回。"
            action.setTitle("创建钱包", for: .normal)
            importHot.isHidden = true; importCold.isHidden = true
        case .importWallet:
            title = "输入助记词"
            wordCount.isHidden = true
            status.isHidden = true
            action.setTitle("确认导入", for: .normal)
            importHot.isHidden = true; importCold.isHidden = true
        case let .addAccounts(indices):
            title = "添加账户"
            wordCount.isHidden = true
            status.text = "无根设备不保存助记词或密码，追加账户需重新录入两者校验归属。"
            accountMode.isHidden = false
            accountIndices.isHidden = false
            accountIndices.text = indices.map(String.init).joined(separator: ",")
            action.setTitle("确认添加", for: .normal)
            importHot.isHidden = true; importCold.isHidden = true
        }
        refreshWords()
    }

    private var selectedWords: UInt32 {
        if case .create = request { return UInt32([12, 18, 24][wordCount.selectedSegmentIndex]) }
        if case .initialize = request, initializationMode == .create {
            return UInt32([12, 18, 24][wordCount.selectedSegmentIndex])
        }
        let count = mnemonic.text.split(whereSeparator: { $0.isWhitespace }).count
        return count == 18 || count == 24 ? UInt32(count) : 12
    }
    @objc private func wordCountChanged() { refreshWords() }
    @objc private func accountModeChanged() { accountIndices.isHidden = accountMode.selectedSegmentIndex == 0 }
    @objc private func reprobeDeviceSecurity() { applyDeviceSecurityGate() }
    private func applyDeviceSecurityGate() {
        guard initializationContent != nil else { return }
        var error: NSError?
        let secure = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        reprobe.isHidden = secure
        action.isEnabled = secure; importHot.isEnabled = secure; importCold.isEnabled = secure
        if !secure {
            status.isHidden = false
            status.text = "未检测到系统锁屏\n钱包密钥依赖系统锁屏保护。请先在系统设置中开启屏幕锁定（数字密码或生物识别），再返回创建。"
        } else if let content = initializationContent, initializationMode == .create {
            status.text = content.walletAccountRoleText + "\n\n" +
                content.walletAuthorizationText + "\n\n" + content.walletCompletionText
        }
    }
    @objc private func importHotPressed() {
        guard initializationContent != nil, task == nil else { return }
        initializationMode = .importHot
        title = "输入助记词"
        status.isHidden = true; wordCount.isHidden = true
        mnemonic.isHidden = false; mnemonic.isEditable = true; mnemonic.isSelectable = true
        wordStatus.isHidden = false; suggestions.isHidden = false; password.isHidden = false
        action.setTitle("确认导入", for: .normal)
        importHot.setTitle("返回创建钱包", for: .normal)
        importHot.removeTarget(self, action: #selector(importHotPressed), for: .touchUpInside)
        importHot.addTarget(self, action: #selector(returnToInitializationCreate), for: .touchUpInside)
        importCold.isHidden = true
        refreshWords()
    }
    @objc private func importColdPressed() {
        guard let content = initializationContent, task == nil else { return }
        initializationMode = .importCold
        title = "导入冷钱包"
        status.isHidden = false; status.text = content.walletColdAccountText
        wordCount.isHidden = true; wordStatus.isHidden = true; suggestions.isHidden = true
        password.isHidden = true; password.text = nil
        mnemonic.isHidden = false; mnemonic.isEditable = true; mnemonic.isSelectable = true
        mnemonic.text = nil; mnemonic.accessibilityLabel = "冷钱包账户地址"
        action.setTitle("确认导入", for: .normal)
        importHot.setTitle("扫描钱包二维码", for: .normal)
        importHot.removeTarget(self, action: #selector(importHotPressed), for: .touchUpInside)
        importHot.addTarget(self, action: #selector(scanColdAccount), for: .touchUpInside)
        importCold.setTitle("返回", for: .normal)
        importCold.removeTarget(self, action: #selector(importColdPressed), for: .touchUpInside)
        importCold.addTarget(self, action: #selector(returnToInitializationCreate), for: .touchUpInside)
    }
    @objc private func returnToInitializationCreate() {
        guard let content = initializationContent, task == nil else { return }
        initializationMode = .create
        title = "创建钱包"
        status.isHidden = false
        status.text = content.walletAccountRoleText + "\n\n" +
            content.walletAuthorizationText + "\n\n" + content.walletCompletionText
        wordCount.isHidden = false; wordStatus.isHidden = true; suggestions.isHidden = true
        mnemonic.text = nil; mnemonic.isHidden = true
        password.text = nil; password.isHidden = false
        action.setTitle("创建钱包", for: .normal)
        importHot.setTitle("已有钱包？导入助记词", for: .normal)
        importHot.removeTarget(nil, action: nil, for: .allEvents)
        importHot.addTarget(self, action: #selector(importHotPressed), for: .touchUpInside)
        importCold.isHidden = false; importCold.setTitle("导入冷钱包", for: .normal)
        importCold.removeTarget(nil, action: nil, for: .allEvents)
        importCold.addTarget(self, action: #selector(importColdPressed), for: .touchUpInside)
        applyDeviceSecurityGate()
    }
    @objc private func scanColdAccount() {
        guard task == nil else { return }
        do {
            let operation = try sdk.qrScan(from: self)
            task = Task { [weak self] in
                guard let self else { return }
                defer { self.task = nil }
                do {
                    let document = try await operation.value()
                    guard case let .accountID(accountID) = document.content else {
                        throw CitizenSDKError(.invalidArgument, "未识别到可导入的钱包账户地址")
                    }
                    self.mnemonic.text = accountID
                } catch { self.fail(error) }
            }
        } catch { fail(error) }
    }
    func textViewDidChange(_ textView: UITextView) { refreshWords() }
    func textViewDidChangeSelection(_ textView: UITextView) { refreshWords() }

    private func refreshWords() {
        guard prepared == nil else { return }
        let words = mnemonic.text.split(whereSeparator: { $0.isWhitespace })
        wordStatus.text = "\(words.count) 个助记词"
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
            if case .create = request { }
            else if case .initialize = request, initializationMode == .create { }
            else if initializationMode != .importCold { try CitizenSDKWalletInput.validateMnemonic(mnemonic.text, wordCount: selectedWords) }
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
            case .initialize:
                if initializationMode == .create {
                    beginCreate(passwordBuffer)
                } else if initializationMode == .importHot {
                    beginImport(passwordBuffer)
                } else {
                    beginColdImport(passwordBuffer)
                }
            case .importColdAccount:
                beginColdImport(passwordBuffer)
            case .create:
                beginCreate(passwordBuffer)
            case .importWallet:
                beginImport(passwordBuffer)
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

    private func beginCreate(_ passwordBuffer: CitizenSDKSensitiveBuffer) {
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
                self.mnemonic.isEditable = false; self.mnemonic.isSelectable = false
                self.mnemonic.isHidden = false; self.password.isHidden = true; self.password.text = nil
                self.wordCount.isHidden = true; self.wordStatus.isHidden = true; self.suggestions.isHidden = true
                self.importHot.isHidden = true; self.importCold.isHidden = true
                self.status.isHidden = false
                self.status.text = self.initializationContent?.walletBackupText
                    ?? "SDK 不保存助记词，关闭后将无法再次显示。请立即离线手抄备份；设置过钱包密码时，还必须单独备份密码。不支持复制，不支持截屏。"
                self.backup.superview?.isHidden = true
                self.action.setTitle("我已备份", for: .normal); self.action.isEnabled = true
            } catch { passwordBuffer.clear(); self.fail(error) }
        }
    }

    private func beginImport(_ passwordBuffer: CitizenSDKSensitiveBuffer) {
        do {
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
                    citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) { self.finish(.completed(profile)) }
                } catch {
                    citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) { self.fail(error) }
                }
            }
        } catch { passwordBuffer.clear(); fail(error) }
    }

    private func beginColdImport(_ passwordBuffer: CitizenSDKSensitiveBuffer) {
        passwordBuffer.clear()
        let value = mnemonic.text.trimmingCharacters(in: .whitespacesAndNewlines)
        irreversible = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            do {
                if value.hasPrefix("0x"), value.count == 66 {
                    _ = try await self.sdk.importColdAccount(accountID: try Self.accountID(value), name: "冷钱包")
                } else {
                    _ = try await self.sdk.importColdAccount(ss58Address: value, name: "冷钱包")
                }
                self.mnemonic.text = nil
                self.finish(.completed(nil))
            } catch { self.fail(error) }
        }
    }

    private static func accountID(_ value: String) throws -> Data {
        guard value.hasPrefix("0x"), value.count == 66 else {
            throw CitizenSDKError(.invalidArgument, "账户标识格式无效")
        }
        var bytes = Data(capacity: 32)
        var index = value.index(value.startIndex, offsetBy: 2)
        for _ in 0..<32 {
            let end = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<end], radix: 16) else {
                throw CitizenSDKError(.invalidArgument, "账户标识格式无效")
            }
            bytes.append(byte); index = end
        }
        return bytes
    }

    private func commitCreatedWallet() {
        guard let prepared else { return }
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
        status.isHidden = false
        status.textColor = CitizenSDKWalletThemeIOS.danger
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
