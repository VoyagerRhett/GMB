#if os(macOS)
import AppKit
import CoreText

private enum CitizenSDKWalletThemeMacOS {
    static let scaffold = NSColor(calibratedRed: CGFloat(0xF7) / 255, green: CGFloat(0xF9) / 255,
                                  blue: CGFloat(0xFC) / 255, alpha: 1)
    static let surface = NSColor.white
    static let primary = NSColor(calibratedRed: 0, green: CGFloat(0x7A) / 255,
                                 blue: CGFloat(0x74) / 255, alpha: 1)
    static let textPrimary = NSColor(calibratedRed: CGFloat(0x1A) / 255, green: CGFloat(0x2B) / 255,
                                     blue: CGFloat(0x3C) / 255, alpha: 1)
    static let textSecondary = NSColor(calibratedRed: CGFloat(0x5A) / 255, green: CGFloat(0x6B) / 255,
                                       blue: CGFloat(0x7C) / 255, alpha: 1)
    static let danger = NSColor(calibratedRed: CGFloat(0xEF) / 255, green: CGFloat(0x44) / 255,
                                blue: CGFloat(0x44) / 255, alpha: 1)
}

public extension CitizenSdk {
    /// 公开结果只有完成状态；私钥只能由 SDK 自有、禁止共享的窗口显示。
    @MainActor
    func viewAccountPrivateKey(from parent: NSWindow, accountID: Data) throws -> CitizenSDKOperation<Void> {
        guard parent.isVisible, NSApp.isActive, parent.attachedSheet == nil else {
            throw CitizenSDKError(.unavailable, "private key view requires an available foreground window")
        }
        let flow = try CitizenSDKPrivateKeyView(sdk: self, accountID: accountID)
        let controller = CitizenSDKPrivateKeyViewControllerMacOS(flow: flow)
        let window = NSWindow(contentViewController: controller)
        window.title = "查看私钥"; window.setContentSize(NSSize(width: 500, height: 320))
        window.styleMask.remove(.closable); window.sharingType = .none
        controller.attach(parent: parent, window: window)
        parent.beginSheet(window)
        return flow.operation
    }

    @MainActor
    func presentWalletFlow(from parent: NSWindow, request: CitizenSDKWalletFlowRequest,
                           completion: @escaping (CitizenSDKWalletFlowResult) -> Void) throws -> CitizenSDKWalletFlow {
        let request = try citizenSDKValidateWalletFlowRequest(request)
        try citizenSDKRequireWalletUI(capabilities())
        let token = try CitizenSDKWalletFlowRegistry.shared.reserve(self)
        let controller = CitizenSDKWalletViewControllerMacOS(sdk: self, request: request) { [weak self, weak parent] result in
            guard let self else { return }
            CitizenSDKWalletFlowRegistry.shared.finish(self, token: token)
            if let sheet = parent?.attachedSheet { parent?.endSheet(sheet) }
            completion(result)
        }
        let window = NSWindow(contentViewController: controller)
        window.title = switch request {
        case .initialize: "创建钱包"
        case .importColdAccount: "导入冷钱包"
        case .create: "创建钱包"
        case .importWallet: "输入助记词"
        case .addAccounts: "添加账户"
        }
        window.setContentSize(NSSize(width: 620, height: 760))
        // A sheet must terminate only through the SDK cancel/complete path.
        window.styleMask.remove(.closable)
        window.standardWindowButton(.closeButton)?.isEnabled = false
        controller.security = CitizenSDKScreenSecurity(window: window)
        parent.beginSheet(window)
        return CitizenSDKWalletFlow { [weak controller] in
            DispatchQueue.main.async { controller?.requestCancel() }
        }
    }
}

@MainActor
private final class CitizenSDKPrivateKeyContentMacOS: NSView {
    let buffer: CitizenSDKPrivateKeyDisplayBuffer
    var onRemoval: (() -> Void)?
    private var wasAttached = false
    init(buffer: CitizenSDKPrivateKeyDisplayBuffer) {
        self.buffer = buffer; super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { wasAttached = true }
        else if wasAttached { onRemoval?() }
    }
    override func draw(_ dirtyRect: NSRect) {
        CitizenSDKWalletThemeMacOS.danger.withAlphaComponent(0.06).setFill(); bounds.fill()
        guard !isHidden, let context = NSGraphicsContext.current?.cgContext else { return }
        let font = CTFontCreateWithName("Menlo" as CFString, 13, nil)
        context.setFillColor(CitizenSDKWalletThemeMacOS.textPrimary.cgColor)
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
private final class CitizenSDKPrivateKeyViewControllerMacOS: NSViewController {
    private let flow: CitizenSDKPrivateKeyView
    private let content: CitizenSDKPrivateKeyContentMacOS
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private weak var parentWindow: NSWindow?
    private weak var ownedWindow: NSWindow?
    private var ready = false
    private var ending = false
    private let reveal = NSButton(title: "查看", target: nil, action: nil)
    private let done = NSButton(title: "关闭", target: nil, action: nil)

    init(flow: CitizenSDKPrivateKeyView) {
        self.flow = flow; content = CitizenSDKPrivateKeyContentMacOS(buffer: flow.buffer)
        super.init(nibName: nil, bundle: nil)
        content.onRemoval = { [weak flow] in flow?.finish(cancelled: true) }
        flow.onReady = { [weak self] in self?.ready = true; self?.refreshVisibility() }
        flow.onClear = { [weak self] in
            self?.ending = true; self?.content.isHidden = true; self?.content.needsDisplay = true
            self?.reveal.isEnabled = false; self?.done.isEnabled = false
        }
        flow.onTerminal = { [weak self] completion in
            guard let self else { completion(); return }
            self.tokens.forEach { $0.0.removeObserver($0.1) }; self.tokens.removeAll()
            self.content.isHidden = true
            if let window = self.ownedWindow {
                self.parentWindow?.endSheet(window); window.orderOut(nil)
                window.contentViewController = nil
            }
            completion()
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func attach(parent: NSWindow, window: NSWindow) {
        parentWindow = parent; ownedWindow = window
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, object: Any? = nil, action: @escaping @MainActor @Sendable () -> Void) {
            tokens.append((center, center.addObserver(forName: name, object: object, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            }))
        }
        observe(NSApplication.didResignActiveNotification) { [weak self] in
            guard let self else { return }
            self.content.isHidden = true
            if !self.flow.isAuthenticating { self.flow.finish(cancelled: true) }
        }
        observe(NSApplication.didBecomeActiveNotification) { [weak self] in self?.refreshVisibility() }
        observe(NSApplication.didHideNotification) { [weak self] in self?.flow.finish(cancelled: true) }
        observe(NSWindow.willCloseNotification, object: parent) { [weak self] in self?.flow.finish(cancelled: true) }
        observe(NSWindow.willCloseNotification, object: window) { [weak self] in self?.flow.finish(cancelled: true) }
        observe(NSWindow.didMiniaturizeNotification, object: parent) { [weak self] in self?.flow.finish(cancelled: true) }
        let workspace = NSWorkspace.shared.notificationCenter
        tokens.append((workspace, workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flow.finish(cancelled: true) }
        }))
        // 切到另一普通应用是真正后台；认证面板的暂时失焦只遮盖，不依赖窗口焦点作终止判断。
        tokens.append((workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if application?.activationPolicy == .regular, application?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                MainActor.assumeIsolated { self?.flow.finish(cancelled: true) }
            }
        }))
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true; view.layer?.backgroundColor = CitizenSDKWalletThemeMacOS.scaffold.cgColor
        let warning = NSTextField(wrappingLabelWithString: "私钥泄露将导致该账户资产被盗（仅该账户，不影响本钱包其他账户）。\n\n确认要查看吗？")
        let note = NSTextField(wrappingLabelWithString: "请手抄备份，不支持复制；导出即等于该账户控制权")
        note.textColor = CitizenSDKWalletThemeMacOS.danger
        content.isHidden = true; content.heightAnchor.constraint(equalToConstant: 120).isActive = true
        reveal.target = self; reveal.action = #selector(revealPressed)
        done.target = self; done.action = #selector(donePressed)
        let stack = NSStackView(views: [warning, content, note, reveal, done])
        stack.orientation = .vertical; stack.spacing = 12; stack.alignment = .leading
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }
    override func viewDidDisappear() {
        super.viewDidDisappear()
        if !ending { flow.finish(cancelled: true) }
    }
    private func refreshVisibility() {
        content.isHidden = ending || !ready || !NSApp.isActive
        content.needsDisplay = true
    }
    @objc private func revealPressed() {
        guard reveal.isEnabled else { return }
        reveal.isEnabled = false; flow.reveal()
    }
    @objc private func donePressed() { flow.finish(cancelled: !ready) }
}

@MainActor
internal final class CitizenSDKWalletViewControllerMacOS: NSViewController, NSTextViewDelegate {
    let sdk: CitizenSdk
    let request: CitizenSDKWalletFlowRequest
    let completion: (CitizenSDKWalletFlowResult) -> Void
    var security: CitizenSDKScreenSecurity?
    private let mnemonic = NSTextView()
    private let password = NSSecureTextField()
    private let wordCount = NSPopUpButton()
    private let accountMode = NSPopUpButton()
    private let accountIndices = NSTextField()
    private let wordStatus = NSTextField(labelWithString: "")
    private let suggestions = NSStackView()
    private let action = NSButton(title: "", target: nil, action: nil)
    private let importHot = NSButton(title: "", target: nil, action: nil)
    private let importCold = NSButton(title: "", target: nil, action: nil)
    private let cancel = NSButton(title: "取消", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let backup = NSButton(checkboxWithTitle: "我已在离线安全位置备份助记词", target: nil, action: nil)
    private var prepared: CitizenSDKPreparedWallet?
    private var phrase: CitizenSDKRecoveryPhrase?
    private var task: Task<Void, Never>?
    private var cancelRequested = false
    private var irreversible = false
    private var finished = false
    private var initializationContent: CitizenSDKWalletInitializationContent?
    private enum InitializationMode { case create, importHot, importCold }
    private var initializationMode: InitializationMode = .create

    init(sdk: CitizenSdk, request: CitizenSDKWalletFlowRequest,
         completion: @escaping (CitizenSDKWalletFlowResult) -> Void) {
        self.sdk = sdk; self.request = request; self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true; view.layer?.backgroundColor = CitizenSDKWalletThemeMacOS.scaffold.cgColor
        status.maximumNumberOfLines = 0
        status.textColor = CitizenSDKWalletThemeMacOS.textSecondary
        password.placeholderString = "钱包密码（选填）"
        wordCount.addItems(withTitles: ["12 个助记词 · 推荐", "18 个助记词", "24 个助记词"])
        wordCount.target = self; wordCount.action = #selector(wordCountChanged)
        accountMode.addItems(withTitles: ["下一个账户", "指定编号"])
        accountMode.selectItem(at: 1)
        accountMode.target = self; accountMode.action = #selector(accountModeChanged)
        accountIndices.placeholderString = "账户编号 1—1989，逗号分隔"
        let scroll = NSScrollView()
        scroll.documentView = mnemonic
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        mnemonic.isAutomaticQuoteSubstitutionEnabled = false
        mnemonic.isAutomaticDashSubstitutionEnabled = false
        mnemonic.isAutomaticTextReplacementEnabled = false
        mnemonic.isAutomaticSpellingCorrectionEnabled = false
        mnemonic.isContinuousSpellCheckingEnabled = false
        mnemonic.delegate = self
        action.target = self; action.action = #selector(actionPressed)
        importHot.target = self; importHot.action = #selector(importHotPressed)
        importCold.target = self; importCold.action = #selector(importColdPressed)
        action.bezelStyle = .rounded
        cancel.target = self; cancel.action = #selector(cancelPressed)
        let buttons = NSStackView(views: [cancel, action]); buttons.spacing = 12
        let stack = NSStackView(views: [status, wordCount, accountMode, accountIndices, scroll, wordStatus, suggestions, password, backup, buttons, importHot, importCold])
        stack.orientation = .vertical; stack.spacing = 14; stack.alignment = .leading
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            password.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            accountIndices.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        backup.isHidden = true
        accountMode.isHidden = true; accountIndices.isHidden = true
        status.stringValue = CitizenSDKWalletInput.explanation
        switch request {
        case let .initialize(words, content):
            initializationContent = content
            wordCount.selectItem(at: words == 18 ? 1 : words == 24 ? 2 : 0)
            status.stringValue = content.walletAccountRoleText + "\n\n" +
                content.walletAuthorizationText + "\n\n" + content.walletCompletionText
            scroll.isHidden = true; action.title = "创建钱包"; wordStatus.isHidden = true
            importHot.title = "已有钱包？导入助记词"; importCold.title = "导入冷钱包"
            cancel.isHidden = true
        case let .importColdAccount(text):
            initializationMode = .importCold; status.stringValue = text
            wordCount.isHidden = true; wordStatus.isHidden = true; suggestions.isHidden = true
            password.isHidden = true; mnemonic.enclosingScrollView?.isHidden = false
            action.title = "确认导入"
            importHot.title = "扫描钱包二维码"; importHot.action = #selector(scanColdAccount)
            importCold.title = "取消"; importCold.action = #selector(cancelPressed)
        case let .create(words):
            wordCount.selectItem(at: words == 18 ? 1 : words == 24 ? 2 : 0)
            status.stringValue = "请务必妥善保存助记词和钱包密码（如设置），若丢失或遗忘将永久无法找回。"
            scroll.isHidden = true; action.title = "创建钱包"
            wordStatus.isHidden = true
            importHot.isHidden = true; importCold.isHidden = true
        case .importWallet:
            status.isHidden = true; wordCount.isHidden = true
            action.title = "确认导入"
            importHot.isHidden = true; importCold.isHidden = true
        case let .addAccounts(indices):
            status.stringValue = "无根设备不保存助记词或密码，追加账户需重新录入两者校验归属。"
            wordCount.isHidden = true; action.title = "确认添加"
            accountMode.isHidden = false; accountIndices.isHidden = false
            accountIndices.stringValue = indices.map(String.init).joined(separator: ",")
            importHot.isHidden = true; importCold.isHidden = true
        }
        refreshWords()
    }

    private var selectedWords: UInt32 {
        if case .create = request { return UInt32([12, 18, 24][wordCount.indexOfSelectedItem]) }
        if case .initialize = request, initializationMode == .create {
            return UInt32([12, 18, 24][wordCount.indexOfSelectedItem])
        }
        let count = mnemonic.string.split(whereSeparator: { $0.isWhitespace }).count
        return count == 18 || count == 24 ? UInt32(count) : 12
    }
    @objc private func wordCountChanged() { refreshWords() }
    @objc private func accountModeChanged() { accountIndices.isHidden = accountMode.indexOfSelectedItem == 0 }
    @objc private func importHotPressed() {
        guard initializationContent != nil, task == nil else { return }
        initializationMode = .importHot; status.isHidden = true; wordCount.isHidden = true
        mnemonic.enclosingScrollView?.isHidden = false; wordStatus.isHidden = false
        suggestions.isHidden = false; password.isHidden = false; action.title = "确认导入"
        importHot.title = "返回创建钱包"; importHot.action = #selector(returnToInitializationCreate)
        importCold.isHidden = true; refreshWords()
    }
    @objc private func importColdPressed() {
        guard let content = initializationContent, task == nil else { return }
        initializationMode = .importCold; status.isHidden = false; status.stringValue = content.walletColdAccountText
        wordCount.isHidden = true; wordStatus.isHidden = true; suggestions.isHidden = true
        password.isHidden = true; password.stringValue = ""; mnemonic.string = ""
        mnemonic.enclosingScrollView?.isHidden = false; action.title = "确认导入"
        importHot.title = "扫描钱包二维码"; importHot.action = #selector(scanColdAccount)
        importCold.title = "返回"; importCold.action = #selector(returnToInitializationCreate)
    }
    @objc private func returnToInitializationCreate() {
        guard let content = initializationContent, task == nil else { return }
        initializationMode = .create; status.isHidden = false
        status.stringValue = content.walletAccountRoleText + "\n\n" +
            content.walletAuthorizationText + "\n\n" + content.walletCompletionText
        wordCount.isHidden = false; wordStatus.isHidden = true; suggestions.isHidden = true
        mnemonic.string = ""; mnemonic.enclosingScrollView?.isHidden = true
        password.stringValue = ""; password.isHidden = false; action.title = "创建钱包"
        importHot.title = "已有钱包？导入助记词"; importHot.action = #selector(importHotPressed)
        importCold.isHidden = false; importCold.title = "导入冷钱包"; importCold.action = #selector(importColdPressed)
    }
    @objc private func scanColdAccount() {
        guard task == nil, let window = view.window else { return }
        do {
            let operation = try sdk.qrScan(from: window)
            task = Task { [weak self] in
                guard let self else { return }; defer { self.task = nil }
                do {
                    let document = try await operation.value()
                    guard case let .accountID(accountID) = document.content else {
                        throw CitizenSDKError(.invalidArgument, "未识别到可导入的钱包账户地址")
                    }
                    self.mnemonic.string = accountID
                } catch { self.fail(error) }
            }
        } catch { fail(error) }
    }
    func textDidChange(_ notification: Notification) { refreshWords() }
    func textViewDidChangeSelection(_ notification: Notification) { refreshWords() }

    private func refreshWords() {
        guard prepared == nil else { return }
        let words = mnemonic.string.split(whereSeparator: { $0.isWhitespace })
        wordStatus.stringValue = "\(words.count) 个助记词"
        if words.count == Int(selectedWords) {
            do { try CitizenSDKWalletInput.validateMnemonic(mnemonic.string, wordCount: selectedWords); wordStatus.stringValue += " · 校验通过" }
            catch { wordStatus.stringValue = citizenSDKFlowError(error).message }
        }
        suggestions.arrangedSubviews.forEach { suggestions.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard mnemonic.isEditable,
              let completion = CitizenSDKWalletInput.completion(mnemonic.string, selection: mnemonic.selectedRange()) else { return }
        for candidate in (try? CitizenSDKWalletInput.suggestions(completion.prefix)) ?? [] {
            suggestions.addArrangedSubview(NSButton(title: candidate, target: self, action: #selector(selectSuggestion(_:))))
        }
    }

    @objc private func selectSuggestion(_ sender: NSButton) {
        guard task == nil else { return }
        let text = mnemonic.string
        guard let current = CitizenSDKWalletInput.completion(text, selection: mnemonic.selectedRange()),
              sender.title.hasPrefix(current.prefix), let range = Range(current.range, in: text) else { return }
        mnemonic.string = text.replacingCharacters(in: range, with: sender.title)
        mnemonic.setSelectedRange(NSRange(location: current.range.location + sender.title.utf16.count, length: 0))
        refreshWords()
    }

    private func setInputEnabled(_ enabled: Bool) {
        password.isEnabled = enabled; mnemonic.isEditable = enabled
        wordCount.isEnabled = enabled; accountMode.isEnabled = enabled; accountIndices.isEnabled = enabled
        suggestions.arrangedSubviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = enabled }
    }

    @objc private func actionPressed() {
        guard task == nil else { return }
        action.isEnabled = false
        if prepared != nil { commitCreatedWallet(); return }
        do {
            try CitizenSDKWalletInput.validatePassword(password.stringValue)
            if case .create = request { }
            else if case .initialize = request, initializationMode == .create { }
            else if initializationMode != .importCold { try CitizenSDKWalletInput.validateMnemonic(mnemonic.string, wordCount: selectedWords) }
            if CitizenSDKWalletInput.requiresRiskConfirmation(password: password.stringValue, request: request) {
                guard let window = view.window else { throw CitizenSDKError(.invalidState, "钱包窗口未就绪") }
                setInputEnabled(false)
                let alert = NSAlert()
                alert.messageText = "钱包密码风险确认"
                alert.informativeText = CitizenSDKWalletInput.passwordWarning
                alert.addButton(withTitle: "已理解，继续"); alert.addButton(withTitle: "取消")
                alert.beginSheetModal(for: window) { [weak self] response in
                    guard let self, !self.finished, !self.cancelRequested else { return }
                    if response == .alertFirstButtonReturn { self.beginOperation() }
                    else { self.setInputEnabled(true); self.action.isEnabled = true }
                }
            } else { beginOperation() }
        } catch { fail(error) }
    }

    private func beginOperation() {
        do {
            let passwordText = password.stringValue
            let passwordBuffer = try citizenSDKSensitiveText(passwordText, label: "password")
            setInputEnabled(false)
            switch request {
            case .initialize:
                if initializationMode == .create { beginCreate(passwordBuffer) }
                else if initializationMode == .importHot { beginImport(passwordBuffer) }
                else { beginColdImport(passwordBuffer) }
            case .importColdAccount:
                beginColdImport(passwordBuffer)
            case .create:
                beginCreate(passwordBuffer)
            case .importWallet:
                beginImport(passwordBuffer)
            case let .addAccounts(indices):
                let mnemonicBuffer = try citizenSDKSensitiveText(mnemonic.string, label: "mnemonic")
                let useNext = accountMode.indexOfSelectedItem == 0
                let selectedIndices = useNext ? indices : try CitizenSDKWalletInput.indices(accountIndices.stringValue)
                task = Task { [weak self] in
                    guard let self else { return }; defer { mnemonicBuffer.clear(); passwordBuffer.clear(); self.task = nil }
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
        let words = selectedWords
        task = Task { [weak self] in
            guard let self else { return }; defer { self.task = nil }
            do {
                if self.cancelRequested { passwordBuffer.clear(); self.finish(.cancelled); return }
                let prepared = try await self.sdk.prepareWallet(wordCount: words, password: passwordBuffer)
                passwordBuffer.clear()
                if self.cancelRequested {
                    self.finish(citizenSDKPreparedCancellationResult { try prepared.release() }); return
                }
                self.prepared = prepared
                let phrase = try prepared.recoveryPhrase(); self.phrase = phrase
                try phrase.render { self.mnemonic.string = $0 }
                self.mnemonic.isEditable = false; self.mnemonic.isSelectable = false
                self.mnemonic.enclosingScrollView?.isHidden = false
                self.password.isHidden = true; self.password.stringValue = ""; self.backup.isHidden = true
                self.wordCount.isHidden = true; self.wordStatus.isHidden = true; self.suggestions.isHidden = true
                self.importHot.isHidden = true; self.importCold.isHidden = true
                self.status.isHidden = false
                self.status.stringValue = self.initializationContent?.walletBackupText
                    ?? "SDK 不保存助记词，关闭后将无法再次显示。请立即离线手抄备份；设置过钱包密码时，还必须单独备份密码。不支持复制，不支持截屏。"
                self.action.title = "我已备份"; self.action.isEnabled = true
            } catch { passwordBuffer.clear(); self.fail(error) }
        }
    }

    private func beginImport(_ passwordBuffer: CitizenSDKSensitiveBuffer) {
        do {
            let mnemonicBuffer = try citizenSDKSensitiveText(mnemonic.string, label: "mnemonic")
            task = Task { [weak self] in
                guard let self else { return }; defer { mnemonicBuffer.clear(); passwordBuffer.clear(); self.task = nil }
                do {
                    if self.cancelRequested {
                        citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) { self.finish(.cancelled) }; return
                    }
                    self.irreversible = true
                    let profile = try await self.sdk.importWallet(mnemonic: mnemonicBuffer, password: passwordBuffer)
                    citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) { self.finish(.completed(profile)) }
                } catch { citizenSDKAfterClearingSecrets([mnemonicBuffer, passwordBuffer]) { self.fail(error) } }
            }
        } catch { passwordBuffer.clear(); fail(error) }
    }

    private func beginColdImport(_ passwordBuffer: CitizenSDKSensitiveBuffer) {
        passwordBuffer.clear()
        let value = mnemonic.string.trimmingCharacters(in: .whitespacesAndNewlines)
        irreversible = true
        task = Task { [weak self] in
            guard let self else { return }; defer { self.task = nil }
            do {
                if value.hasPrefix("0x"), value.count == 66 {
                    _ = try await self.sdk.importColdAccount(accountID: try Self.accountID(value), name: "冷钱包")
                } else {
                    _ = try await self.sdk.importColdAccount(ss58Address: value, name: "冷钱包")
                }
                self.mnemonic.string = ""; self.finish(.completed(nil))
            } catch { self.fail(error) }
        }
    }

    private static func accountID(_ value: String) throws -> Data {
        guard value.hasPrefix("0x"), value.count == 66 else {
            throw CitizenSDKError(.invalidArgument, "账户标识格式无效")
        }
        var bytes = Data(capacity: 32); var index = value.index(value.startIndex, offsetBy: 2)
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
        mnemonic.string = ""; phrase?.clear(); phrase = nil
        task = Task { [weak self] in
            guard let self else { return }; defer { self.task = nil }
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
        cancelRequested = true; mnemonic.string = ""; password.stringValue = ""
        phrase?.clear(); phrase = nil
        if task == nil {
            let result = prepared.map { prepared in
                citizenSDKPreparedCancellationResult { try prepared.release() }
            } ?? .cancelled
            prepared = nil; finish(result)
        }
        else { status.stringValue = "正在安全结束当前钱包操作…" }
    }

    private func fail(_ error: Error) {
        if let result = citizenSDKCancellationResult(cancelRequested: cancelRequested,
                                                     irreversible: irreversible, error: error) {
            finish(result); return
        }
        status.isHidden = false
        status.textColor = CitizenSDKWalletThemeMacOS.danger
        status.stringValue = citizenSDKFlowError(error).message
        if let prepared {
            do { try prepared.release() } catch { finish(.failed(citizenSDKFlowError(error))); return }
            self.prepared = nil
            finish(.failed(citizenSDKFlowError(error))); return
        }
        irreversible = false
        setInputEnabled(true); action.isEnabled = true
    }

    private func finish(_ result: CitizenSDKWalletFlowResult) {
        guard !finished else { return }; finished = true
        security?.finish(); security = nil
        mnemonic.string = ""; password.stringValue = ""
        phrase?.clear(); phrase = nil
        prepared = nil; completion(result)
    }
}
#endif
