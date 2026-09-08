import Foundation

/// 工作线程只在短锁内复制 32 字节；不等待主线程、不反调 Core，也不构造秘密 String。
internal final class CitizenSDKPrivateKeyDisplayBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var characters = [UInt16](repeating: 0, count: 66)
    private var viewID: UInt64 = 0
    private var hostOperationID: UInt64?
    private var registerAuthentication: ((UInt64) -> Int32)?
    private var closed = false
    private var populated = false
    private var lastCode: Int32?
    private var listener: (@Sendable (Int32) -> Void)?

    func bind(_ id: UInt64) {
        lock.lock(); defer { lock.unlock() }
        precondition(id != 0 && (viewID == 0 || viewID == id))
        viewID = id
    }

    func listen(_ value: @escaping @Sendable (Int32) -> Void) {
        lock.lock(); listener = value; let code = lastCode; lock.unlock()
        if let code { value(code) }
    }

    func bindAuthenticationRegistry(_ register: @escaping (UInt64) -> Int32) {
        lock.lock(); defer { lock.unlock() }
        registerAuthentication = register
    }

    /// 只登记本查看真实 unwrap 的身份；其它请求或重复关联不能获得焦点豁免。
    func authorizing(viewID id: UInt64, hostOperationID operationID: UInt64) -> Int32 {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return CitizenSDKErrorCode.cancelled.rawValue }
        guard id != 0, id == viewID, operationID != 0, hostOperationID == nil else {
            return CitizenSDKErrorCode.integrity.rawValue
        }
        guard let registerAuthentication else { return CitizenSDKErrorCode.integrity.rawValue }
        let code = registerAuthentication(operationID)
        guard code == 0 else { return code }
        hostOperationID = operationID
        return 0
    }

    var authenticationID: UInt64? {
        lock.lock(); defer { lock.unlock() }
        return hostOperationID
    }

    func display(viewID id: UInt64, bytes: citizensdk_bytes_view_t) -> Int32 {
        guard bytes.len == 32, let source = bytes.data else { return CitizenSDKErrorCode.integrity.rawValue }
        lock.lock()
        guard !closed, !populated, id != 0, viewID == id else {
            lock.unlock()
            return CitizenSDKErrorCode.cancelled.rawValue
        }
        characters[0] = 48; characters[1] = 120
        for index in 0..<32 {
            let byte = source[index]
            let high = UInt16(byte >> 4), low = UInt16(byte & 15)
            characters[2 + index * 2] = high < 10 ? high + 48 : high + 87
            characters[3 + index * 2] = low < 10 ? low + 48 : low + 87
        }
        populated = true
        lock.unlock()
        return 0
    }

    func settled(viewID id: UInt64, code: Int32) {
        lock.lock()
        guard id != 0, viewID == 0 || viewID == id else { lock.unlock(); return }
        lastCode = code
        let callback = listener
        lock.unlock()
        callback?(code)
    }

    /// 绘图只借用字符数组；调用者不能把它保存在文本控件、剪贴板或无障碍树中。
    func withCharacters(_ body: (UnsafeBufferPointer<UInt16>) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !closed, populated else { return }
        characters.withUnsafeBufferPointer(body)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        closed = true; populated = false
        for index in characters.indices { characters[index] = 0 }
    }

    var isClearedForTesting: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed && characters.allSatisfy { $0 == 0 }
    }

    deinit { clear() }
}

/// 单个 SDK 自有查看的所有权。阶段通知不完成公开操作；必须等 Core 请求与界面均真实结束。
@MainActor
internal final class CitizenSDKPrivateKeyView {
    let buffer = CitizenSDKPrivateKeyDisplayBuffer()
    private let sdk: CitizenSdk
    private let reservation: UUID
    private let viewID: UInt64
    private let core: CitizenSDKOperation<Void>
    private var ending = false
    private var completed = false
    private var cleanup: Task<Void, Never>?
    var onReady: (() -> Void)?
    var onClear: (() -> Void)?
    var onTerminal: ((@escaping () -> Void) -> Void)?
    lazy var operation = CitizenSDKOperation<Void> { [weak self] in
        Task { @MainActor [weak self] in self?.finish(cancelled: true) }
        return true
    }

    init(sdk: CitizenSdk, accountID: Data) throws {
        let accountID = try CitizenSDKInputLimits.accountID(accountID)
        try citizenSDKRequireWalletUI(sdk.capabilities())
        self.sdk = sdk
        reservation = try CitizenSDKWalletFlowRegistry.shared.reserve(sdk)
        do {
            (viewID, core) = try sdk.openPrivateKeyView(accountID: accountID, buffer: buffer)
        } catch {
            CitizenSDKWalletFlowRegistry.shared.finish(sdk, token: reservation)
            throw error
        }
        buffer.bind(viewID)
        buffer.listen { [weak self] code in
            Task { @MainActor [weak self] in
                guard let self, !self.ending else { return }
                if code == 0 { self.onReady?() }
                else { self.finish(cancelled: false) }
            }
        }
        core.observe { [self] result in
            Task { @MainActor [self] in
                self.buffer.clear(); self.onClear?()
                let close = { [self] in
                    guard !self.completed else { return }
                    self.completed = true
                    CitizenSDKWalletFlowRegistry.shared.finish(self.sdk, token: self.reservation)
                    self.operation.complete(result)
                    self.onReady = nil; self.onClear = nil; self.onTerminal = nil
                }
                if let onTerminal = self.onTerminal { onTerminal(close) } else { close() }
            }
        }
    }

    func reveal() {
        guard !ending else { return }
        do { try sdk.revealPrivateKeyView(viewID) }
        catch { finish(cancelled: false) }
    }

    var isAuthenticating: Bool {
        guard !ending, let operationID = buffer.authenticationID else { return false }
        return sdk.isPrivateKeyAuthenticationActive(operationID)
    }

    func finish(cancelled: Bool) {
        guard !ending else { return }
        ending = true
        // 先撤销缓冲接收并清屏；迟到 display 会在同一串行门内被拒绝。
        buffer.clear(); onClear?()
        if let operationID = buffer.authenticationID { sdk.cancelPrivateKeyAuthentication(operationID) }
        cleanup = Task { [self] in
            while !self.completed {
                do {
                    if cancelled { try self.sdk.cancelPrivateKeyView(self.viewID) }
                    try self.sdk.finishPrivateKeyView(self.viewID)
                    return
                } catch {
                    // 控制失败不能伪造终态；保留所有者，直到 Core 接受 finish 或真实请求结束。
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
    }
}

/// 安全界面只读取核心已经解析的模块能力；未启用钱包时禁止创建窗口或接收秘密输入。
internal func citizenSDKRequireWalletUI(_ snapshot: CitizenSDKCapabilities) throws {
    let statuses = snapshot.statuses.filter { $0.name == .walletProfile }
    guard statuses.count == 1, let status = statuses.first else {
        throw CitizenSDKError(.integrity, "Core wallet capability is missing or duplicated")
    }
    guard status.supported && status.enabled else {
        throw CitizenSDKError(.notReady, "wallet_profile is not ready")
    }
}

/// Secret-free selection for the SDK-owned wallet interface.
public enum CitizenSDKWalletFlowRequest: Sendable, Equatable {
    case create(wordCount: UInt32)
    case importWallet
    case addAccounts(indices: [UInt32])
}

public enum CitizenSDKWalletFlowResult: Sendable {
    case completed(CitizenWalletProfile?)
    case cancelled
    case failed(CitizenSDKError)
}

/// One-shot controller for a non-exported Apple wallet window/view controller.
public final class CitizenSDKWalletFlow: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let cancelAction: () -> Void

    internal init(cancel: @escaping () -> Void) { cancelAction = cancel }

    public func cancel() {
        lock.lock()
        let shouldCancel = !cancelled
        cancelled = true
        lock.unlock()
        if shouldCancel { cancelAction() }
    }
}

/// Process ownership prevents Core destroy while secret controls or a prepared
/// mnemonic are still retained by an SDK-owned Apple flow.
/// Wallet admission and close admission share one state machine and one lock,
/// so a flow cannot reserve the interval between a close preflight and Core
/// destruction. No dictionary access is performed outside these methods.
internal final class CitizenSDKWalletFlowRegistry: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case open
        case owned
        case closing
        case closed
    }

    struct CloseReservation: Equatable, Sendable {
        fileprivate let token: UUID
        /// True once a lifecycle supervisor has committed to retrying this
        /// close, including every attempt resumed from persistent closing.
        fileprivate let retryCommitted: Bool
    }

    enum CloseOrigin: Equatable, Sendable {
        case explicit
        case supervised
    }

    private enum State {
        case open
        case owned(UUID)
        /// A token means one close attempt is currently admitted. `nil` means
        /// ABI teardown or supervised recovery has committed to fail-closed
        /// retry, but no attempt currently owns the Native call.
        case closing(CloseReservation?)
        case closed

        var status: Status {
            switch self {
            case .open: return .open
            case .owned: return .owned
            case .closing: return .closing
            case .closed: return .closed
            }
        }
    }

    static let shared = CitizenSDKWalletFlowRegistry()
    private let lock = NSLock()
    private var states: [ObjectIdentifier: State] = [:]

    func registerOpen(_ sdk: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(sdk)
        precondition(states[key] == nil, "CitizenSDK wallet registry identity was reused before deinit")
        states[key] = .open
    }

    func reserve(_ sdk: AnyObject) throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(sdk)
        switch states[key] {
        case .open:
            let token = UUID()
            states[key] = .owned(token)
            return token
        case .owned:
            throw CitizenSDKError(.busy, "a wallet UI flow is already active")
        case .closing:
            throw CitizenSDKError(.busy, "CitizenSDK is closing")
        case .closed:
            throw CitizenSDKError(.invalidState, "CitizenSDK is closed")
        case nil:
            throw CitizenSDKError(.invalidState, "CitizenSDK is not registered")
        }
    }

    func finish(_ sdk: AnyObject, token: UUID) {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(sdk)
        if case let .owned(current) = states[key], current == token { states[key] = .open }
    }

    /// Atomically excludes new wallet UI before any Core teardown call. A
    /// `nil` result means another successful attempt already committed closed.
    func beginClose(_ sdk: AnyObject, origin: CloseOrigin = .explicit) throws -> CloseReservation? {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(sdk)
        switch states[key] {
        case .open:
            let reservation = CloseReservation(
                token: UUID(), retryCommitted: origin == .supervised
            )
            states[key] = .closing(reservation)
            return reservation
        case .owned:
            throw CitizenSDKError(.busy, "CitizenSDK wallet UI must finish before close")
        case .closing(nil):
            // Persistent closing exists only after partial ABI teardown or a
            // supervisor-owned retry. Any caller resuming it inherits that
            // fail-closed recovery commitment.
            let reservation = CloseReservation(token: UUID(), retryCommitted: true)
            states[key] = .closing(reservation)
            return reservation
        case .closing:
            throw CitizenSDKError(.busy, "another CitizenSDK close attempt is active")
        case .closed:
            return nil
        case nil:
            throw CitizenSDKError(.invalidState, "CitizenSDK is not registered")
        }
    }

    /// Ends one failed close attempt. Only a first explicit pre-teardown failure
    /// reopens; partial teardown and every supervisor-owned retry stay closed to
    /// wallet admission until another close attempt succeeds.
    /// The return value tells an explicit caller to hand ownership to the
    /// lifecycle supervisor.
    @discardableResult
    func failClose(_ sdk: AnyObject, reservation: CloseReservation,
                   teardownStarted: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(sdk)
        guard case let .closing(current?) = states[key], current == reservation else { return false }
        let remainsClosing = teardownStarted || reservation.retryCommitted
        states[key] = remainsClosing ? .closing(nil) : .open
        return teardownStarted && !reservation.retryCommitted
    }

    /// Core destruction is the only transition to closed. The closed marker
    /// remains until facade deinit so a still-reachable facade cannot reopen UI.
    func commitClosed(_ sdk: AnyObject, reservation: CloseReservation?) {
        lock.lock(); defer { lock.unlock() }
        let key = ObjectIdentifier(sdk)
        if case .closed = states[key] { return }
        guard let reservation else {
            preconditionFailure("only an existing closed tombstone accepts an idempotent nil commit")
        }
        guard case let .closing(current?) = states[key], current == reservation else {
            preconditionFailure("CitizenSDK close reservation drifted before Core destruction commit")
        }
        states[key] = .closed
    }

    func forget(_ sdk: AnyObject) {
        lock.lock(); states.removeValue(forKey: ObjectIdentifier(sdk)); lock.unlock()
    }

    internal func status(_ sdk: AnyObject) -> Status? {
        lock.lock(); defer { lock.unlock() }
        return states[ObjectIdentifier(sdk)]?.status
    }
}

internal func citizenSDKSensitiveText(_ value: String, label: String) throws -> CitizenSDKSensitiveBuffer {
    // UIKit/AppKit owns the source String and cannot provide an in-place
    // zeroizable buffer. The one SDK-created UTF-8 copy is therefore mutable,
    // copied immediately into the controlled buffer, and cleared on return.
    var bytes = Data(value.utf8)
    defer { bytes.resetBytes(in: 0..<bytes.count) }
    guard bytes.count <= CitizenSDKInputLimits.maximumWalletSecretBytes else {
        throw CitizenSDKError(.invalidArgument, "\(label) exceeds 1024 UTF-8 bytes")
    }
    return CitizenSDKSensitiveBuffer(data: bytes)
}

internal func citizenSDKValidateWalletFlowRequest(_ request: CitizenSDKWalletFlowRequest) throws
    -> CitizenSDKWalletFlowRequest {
    switch request {
    case let .create(wordCount):
        guard [12, 18, 24].contains(wordCount) else {
            throw CitizenSDKError(.invalidArgument, "word count must be 12, 18 or 24")
        }
    case .importWallet:
        break
    case let .addAccounts(indices):
        _ = try CitizenSDKInputLimits.additionalIndices(indices)
    }
    return request
}

/// 两个 Apple 安全界面共用 Core 输入合同；此类型不属于宿主公开 API。
internal enum CitizenSDKWalletInput {
    static let wordCounts: [UInt32] = [12, 18, 24]
    static let explanation = "热钱包不持久保存助记词，关闭后不能再次显示。请离线备份。钱包密码为选填的派生盐值，不是 App 登录密码；非空密码须单独记住，恢复时必须相同。相同助记词使用不同密码会得到不同账户。"
    static let passwordWarning = "钱包密码参与账户派生，不是 App 登录密码。必须同时保管助记词和该密码；密码丢失无法恢复原账户。请确认已理解此风险。"

    static func validatePassword(_ value: String) throws {
        try withInput(value) { try CitizenSDKChecks.requireOK(citizensdk_validate_wallet_password($0), "钱包密码校验失败") }
    }

    static func validateMnemonic(_ value: String, wordCount: UInt32) throws {
        try withInput(value) { try CitizenSDKChecks.requireOK(citizensdk_validate_wallet_mnemonic($0, wordCount), "助记词校验失败") }
    }

    static func suggestions(_ prefix: String) throws -> [String] {
        try withInput(prefix) { input in
            var required: UInt64 = 0
            try CitizenSDKChecks.requireOK(citizensdk_wallet_word_suggestions(input, nil, 0, &required), "单词补全失败")
            guard required <= 128 else { throw CitizenSDKError(.integrity, "单词补全结果超出限制") }
            var output = Data(count: Int(required))
            defer { output.resetBytes(in: 0..<output.count) }
            let code = output.withUnsafeMutableBytes {
                citizensdk_wallet_word_suggestions(input, $0.bindMemory(to: UInt8.self).baseAddress, UInt64($0.count), &required)
            }
            try CitizenSDKChecks.requireOK(code, "单词补全失败")
            return String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
        }
    }

    static func requiresRiskConfirmation(password: String, request: CitizenSDKWalletFlowRequest) -> Bool {
        guard !password.isEmpty else { return false }
        if case .addAccounts = request { return false }
        return true
    }

    static func indices(_ text: String) throws -> [UInt32] {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == "，" || $0.isWhitespace })
        let values = parts.compactMap { UInt32($0) }
        guard values.count == parts.count else { throw CitizenSDKError(.invalidArgument, "账户编号必须为 1—1989 的整数") }
        return try CitizenSDKInputLimits.additionalIndices(values)
    }

    static func nextIndex(_ indices: [UInt32]) throws -> [UInt32] {
        let maximum = indices.max() ?? 0
        guard maximum < 1_989 else { throw CitizenSDKError(.invalidArgument, "已到达最大账户编号 1989") }
        return [maximum + 1]
    }

    /// NSTextView / UITextView 使用 UTF-16 光标；补全只替换光标所属单词，不动其他词。
    static func completion(_ text: String, selection: NSRange) -> (range: NSRange, prefix: String)? {
        guard selection.length == 0, let caret = Range(selection, in: text)?.lowerBound else { return nil }
        let start = text[..<caret].lastIndex(where: { $0.isWhitespace }).map { text.index(after: $0) } ?? text.startIndex
        guard start < caret else { return nil }
        let end = text[caret...].firstIndex(where: { $0.isWhitespace }) ?? text.endIndex
        return (NSRange(start..<end, in: text), String(text[start..<caret]))
    }

    private static func withInput<T>(_ value: String, body: (citizensdk_bytes_view_t) throws -> T) throws -> T {
        let buffer = try citizenSDKSensitiveText(value, label: "wallet input")
        defer { buffer.clear() }
        return try buffer.withUnsafeBytes { bytes in
            var view = citizensdk_bytes_view_t()
            view.data = bytes.bindMemory(to: UInt8.self).baseAddress
            view.len = UInt64(bytes.count)
            return try body(view)
        }
    }
}

internal func citizenSDKFlowError(_ error: Error) -> CitizenSDKError {
    if let sdk = error as? CitizenSDKError { return sdk }
    return CitizenSDKError(.internalFailure, "CitizenSDK wallet interface failed")
}

/// Cancellation can only relabel work that has not crossed an irreversible
/// Core admission/commit point. Once crossed, its real failure must be reported
/// even when the user requested cancellation while waiting.
internal func citizenSDKCancellationResult(
    cancelRequested: Bool,
    irreversible: Bool,
    error: Error
) -> CitizenSDKWalletFlowResult? {
    guard cancelRequested else { return nil }
    return irreversible ? .failed(citizenSDKFlowError(error)) : .cancelled
}

/// A prepared mnemonic is owned by Core until release succeeds. Native keeps
/// failed-release handles in its prepared set so a later `close()` can retry;
/// the UI must report failure instead of claiming cancellation completed.
internal func citizenSDKPreparedCancellationResult(
    release: () throws -> Void
) -> CitizenSDKWalletFlowResult {
    do { try release(); return .cancelled }
    catch { return .failed(citizenSDKFlowError(error)) }
}

/// Establishes the terminal-callback commit point: controlled secrets are
/// cleared before registry release, SDK close, FlutterResult, or host code can
/// reenter from the supplied body.
internal func citizenSDKAfterClearingSecrets<T>(
    _ buffers: [CitizenSDKSensitiveBuffer],
    _ body: () throws -> T
) rethrows -> T {
    buffers.forEach { $0.clear() }
    return try body()
}
