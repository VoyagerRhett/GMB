import Foundation

/// Native Swift facade for one CitizenSDK Core instance.
///
/// C handles, result handles, prepared-wallet handles, mnemonics and passwords
/// are absent from this public surface. Wallet creation/import/add-account
/// secrets are accepted only by the SDK-owned Apple UI.
public final class CitizenSdk: @unchecked Sendable {
    public let sessionID = UUID().uuidString
    private let stateLock = NSLock()
    private let native: CitizenSDKNative
    private var lifecycleValue: CitizenSDKLifecycle
    private var closed = false
    private var eventHandler: ((CitizenSDKEvent) -> Void)?

    private init(native: CitizenSDKNative, lifecycle: CitizenSDKLifecycle) {
        self.native = native
        lifecycleValue = lifecycle
        CitizenSDKWalletFlowRegistry.shared.registerOpen(self)
    }

    /// 未选择链时不读取链资产；钱包、签名和链均由同一核心按模块装配。
    public static func open(modules: CitizenSDKModules = .full) throws -> CitizenSdk {
        try CitizenSDKNative.validateModules(modules)
        let native = try CitizenSDKNative.open(
            assets: modules.contains(.chain) ? CitizenSDKAssets.load() : nil, modules: modules
        )
        return try finishOpen(native)
    }

    internal static func open(storageRoot: URL, applicationID: String? = Bundle.main.bundleIdentifier,
                              assets: CitizenSDKAssets? = nil, modules: CitizenSDKModules = .full) throws -> CitizenSdk {
        try CitizenSDKNative.validateModules(modules)
        let native = try CitizenSDKNative.open(
            assets: modules.contains(.chain) ? (assets ?? CitizenSDKAssets.load()) : nil,
            storageRoot: storageRoot, applicationID: applicationID, modules: modules
        )
        return try finishOpen(native)
    }

    private static func finishOpen(_ native: CitizenSDKNative) throws -> CitizenSdk {
        try finalizeOpen(
            lifecycle: native.lifecycle,
            install: { lifecycle in
            let sdk = CitizenSdk(native: native, lifecycle: lifecycle)
            native.setEventListener { [weak sdk] event in sdk?.receive(event) }
            return sdk
            },
            cleanup: {
            // A freshly created instance is still in the destroyable CREATED
            // state. Preserve the initialization error while closing Core and
            // all host resources best-effort.
            native.setEventListener(nil)
            do { try native.close() }
            catch { native.enqueueForSupervisedClose() }
            }
        )
    }

    deinit {
        stateLock.lock()
        let needsRecovery = !closed
        stateLock.unlock()
        if needsRecovery { native.enqueueForSupervisedClose() }
        CitizenSDKWalletFlowRegistry.shared.forget(self)
    }

    /// One cleanup gate shared by the production constructor and source-level
    /// fault-injection tests. Any lifecycle or listener-install failure must
    /// close the freshly-created Core exactly once while preserving the
    /// original error.
    internal static func finalizeOpen<T>(
        lifecycle: () throws -> CitizenSDKLifecycle,
        install: (CitizenSDKLifecycle) throws -> T,
        cleanup: () -> Void
    ) throws -> T {
        do { return try install(lifecycle()) }
        catch { cleanup(); throw error }
    }

    public var lifecycle: CitizenSDKLifecycle {
        stateLock.lock(); defer { stateLock.unlock() }
        return lifecycleValue
    }

    public func setEventHandler(_ handler: ((CitizenSDKEvent) -> Void)?) throws {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !closed else { throw CitizenSDKError(.invalidState, "CitizenSDK is closed") }
        eventHandler = handler
    }

    public func start() async throws {
        try await native.start().value()
    }

    public func stop() async throws {
        try await native.stop().value()
    }

    public func refreshCapabilities() async throws {
        try await native.refreshCapabilities().value()
    }

    public func capabilities() throws -> CitizenSDKCapabilities { try native.capabilities() }
    public func finalizedHead() async throws -> CitizenBlockRef { try await native.finalizedHead().value() }
    public func syncStatus() async throws -> CitizenChainSyncStatus { try await native.syncStatus().value() }
    public func bestHead() async throws -> CitizenBlockRef { try await native.bestHead().value() }
    public func finalizedBlock(at number: UInt64) async throws -> CitizenBlockRef {
        try await native.finalizedBlock(at: number).value()
    }
    public func resolveFinalizedBlock(hash: Data, number: UInt64) async throws -> CitizenBlockRef {
        try await native.resolveFinalizedBlock(hash: hash, number: number).value()
    }
    public func blockHeader(_ block: CitizenBlockRef) async throws -> CitizenBlockHeader {
        try await native.blockHeader(block).value()
    }
    public func blockBody(_ block: CitizenBlockRef) async throws -> CitizenBlockBody {
        try await native.blockBody(block).value()
    }
    public func runtimeContext(_ block: CitizenBlockRef) async throws -> CitizenRuntimeContext {
        try await native.runtimeContext(block).value()
    }
    public func storage(_ block: CitizenBlockRef, key: Data) async throws -> Data? {
        try await native.storage(block, key: CitizenSDKInputLimits.storageKey(key)).value()
    }
    public func storageBatch(_ block: CitizenBlockRef, keys: [Data]) async throws -> [Data?] {
        try await native.storageBatch(block, keys: CitizenSDKInputLimits.storageKeys(keys)).value()
    }
    public func systemEvents(_ finalizedBlock: CitizenBlockRef) async throws -> Data? {
        guard finalizedBlock.finality == .finalized else {
            throw CitizenSDKError(.invalidArgument, "System.Events requires a finalized block")
        }
        return try await native.systemEvents(finalizedBlock).value()
    }
    public func exportState() async throws -> CitizenChainState { try await native.exportState().value() }
    public func importState(_ state: CitizenChainState) async throws { try await native.importState(state).value() }

    /// 返回 Core 固定链身份的创世哈希；只要求启用 chain，不要求启动或同步轻节点。
    public func genesisHash() throws -> Data { try native.genesisHash() }

    public func accountBalance(accountID: Data) async throws -> CitizenAccountBalance {
        try await native.accountBalance(CitizenSDKInputLimits.accountID(accountID)).value()
    }

    /// 同一已验证 finalized 块的批量余额；保持输入顺序和重复项，空列表仍交由 Core 校验状态。
    public func accountBalances(accountIDs: [Data]) async throws -> [CitizenAccountBalance] {
        try await native.accountBalances(CitizenSDKInputLimits.balanceAccountIDs(accountIDs)).value()
    }

    public func accountNonce(accountID: Data) async throws -> CitizenAccountNonce {
        try await native.accountNonce(CitizenSDKInputLimits.accountID(accountID)).value()
    }

    public func feeSnapshot() async throws -> CitizenFeeSnapshot { try await native.feeSnapshot().value() }
    public func walletProfile() async throws -> CitizenWalletProfile? { try await native.walletProfile().value() }
    public func walletState() async throws -> CitizenWalletState { try await native.walletState().value() }

    public func importColdAccount(accountID: Data, name: String) async throws -> CitizenWalletState {
        let checkedID = try CitizenSDKInputLimits.accountID(accountID)
        let checkedName = try CitizenSDKInputLimits.accountName(name)
        return try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.importColdAccountID(checkedID, name: checkedName).value()
        }
    }

    public func importColdAccount(ss58Address: String, name: String) async throws -> CitizenWalletState {
        guard !ss58Address.isEmpty, ss58Address.utf8.count <= 64 else {
            throw CitizenSDKError(.invalidArgument, "cold account SS58 is invalid")
        }
        let checkedName = try CitizenSDKInputLimits.accountName(name)
        return try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.importColdAccountSS58(ss58Address, name: checkedName).value()
        }
    }

    public func reorderWalletAccountsWithoutDefaultChange(expectedRevision: UInt64,
                                                           accountIDs: [Data]) async throws
        -> CitizenWalletState {
        guard (1...3_980).contains(accountIDs.count) else {
            throw CitizenSDKError(.invalidArgument, "wallet catalog must contain 1...3980 accounts")
        }
        let checkedIDs = try accountIDs.map { try CitizenSDKInputLimits.accountID($0) }
        return try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.reorderWalletAccounts(expectedRevision: expectedRevision,
                                                   accountIDs: checkedIDs).value()
        }
    }

    /// Changes the SDK wallet default only after the old default authorizes the
    /// exact revision and full account permutation. CitizenWallet stays an
    /// independent external signer when the old default is cold.
    public func beginDefaultAccountChange(expectedRevision: UInt64,
                                          accountIDs: [Data],
                                          ttlSeconds: UInt64 = 120) async throws
        -> CitizenDefaultAccountChangeOutcome {
        guard (1...256).contains(accountIDs.count), (1...300).contains(ttlSeconds) else {
            throw CitizenSDKError(.invalidArgument, "default-account change input is invalid")
        }
        let checked = try accountIDs.map { try CitizenSDKInputLimits.accountID($0) }
        return try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.beginDefaultAccountChange(
                expectedRevision: expectedRevision, accountIDs: checked,
                ttlSeconds: ttlSeconds).value()
        }
    }

    public func consumeDefaultAccountChange(sessionID: String,
                                            response: String) async throws
        -> CitizenDefaultAccountChangeOutcome {
        try CitizenSigning.validateExternal(sessionID: sessionID, response: response)
        return try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.consumeDefaultAccountChange(
                sessionID: sessionID, response: response).value()
        }
    }

    public func renameAccount(accountID: Data, name: String) async throws -> CitizenWalletState {
        let checkedID = try CitizenSDKInputLimits.accountID(accountID)
        let checkedName = try CitizenSDKInputLimits.accountName(name)
        return try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.renameAnyAccount(checkedID, name: checkedName).value()
        }
    }

    public func deleteAccount(accountID: Data) async throws -> CitizenWalletState {
        let checkedID = try CitizenSDKInputLimits.accountID(accountID)
        return try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.deleteAnyAccount(checkedID).value()
        }
    }

    public func setActiveWalletAccount(accountID: Data) async throws -> CitizenWalletProfile {
        try await CitizenSDKWalletMutationGate.shared.perform {
            guard let profile = try await native.setActiveAccount(CitizenSDKInputLimits.accountID(accountID)).value() else {
                throw CitizenSDKError(.integrity, "set active account returned no wallet profile")
            }
            return profile
        }
    }

    public func renameWalletAccount(accountID: Data, name: String) async throws -> CitizenWalletProfile {
        let checkedName = try CitizenSDKInputLimits.accountName(name)
        return try await CitizenSDKWalletMutationGate.shared.perform {
            guard let profile = try await native.renameAccount(CitizenSDKInputLimits.accountID(accountID), name: checkedName).value() else {
                throw CitizenSDKError(.integrity, "rename account returned no wallet profile")
            }
            return profile
        }
    }

    /// Returns the post-delete profile under the same process mutation gate.
    public func deleteWalletAccount(accountID: Data) async throws -> CitizenWalletProfile? {
        try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.deleteAccount(CitizenSDKInputLimits.accountID(accountID)).value()
            return try await native.walletProfile().value()
        }
    }

    public func deleteWallet() async throws -> CitizenWalletProfile? {
        try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.deleteWallet().value()
            return try await native.walletProfile().value()
        }
    }

    public func reconcileWalletCleanup() async throws -> CitizenWalletProfile? {
        try await CitizenSDKWalletMutationGate.shared.perform {
            try await native.reconcileWalletCleanup().value()
            return try await native.walletProfile().value()
        }
    }

    /// 签名是独立公开模块，不要求开启钱包管理或轻节点。
    public var signing: CitizenSigning { CitizenSigning(native: native) }

    public func qrParse(_ text: String) throws -> CitizenQRDocument {
        try native.qrParse(text)
    }

    public func qrCreateSignRequest(action: UInt16, signerAccountID: Data,
                                    reviewPayload: Data, ttlSeconds: UInt64 = 120) throws -> String {
        try native.qrCreateSignRequest(action: action, accountID: signerAccountID,
                                       payload: reviewPayload, ttl: ttlSeconds)
    }

    public func qrConsumeSignResponse(_ text: String) throws -> Data {
        try native.qrConsumeSignResponse(text)
    }

    public func qrCancelSignRequest(_ requestID: String) throws -> Bool {
        try native.qrCancelSignRequest(requestID)
    }

    public func qrEncodeAccountID(_ accountID: Data) throws -> String {
        try native.qrEncodeAccountID(accountID)
    }

    public func qrDecodeLuminance(_ data: Data, width: UInt32, height: UInt32,
                                  rowStride: UInt32) throws -> CitizenQRDocument {
        try native.qrDecodeLuminance(data, width: width, height: height, rowStride: rowStride)
    }

    public func qrEncode(_ text: String, scale: UInt32 = 4) throws -> CitizenQRImage {
        try native.qrEncode(text, scale: scale)
    }

    internal func requireQRUI() throws { try native.requireQRModule() }
    internal func reviewQrSignRequest(_ text: String) throws -> CitizenSDKOperation<CitizenSDKQrReview> {
        try native.reviewQrSignRequest(text)
    }
    internal func signQrReview(_ review: CitizenSDKQrReview) throws -> CitizenSDKOperation<CitizenQRDocument> {
        try native.signQrRequest(review)
    }

    // 这些内部接线不进入公开 Swift 接口，私钥内容只由 SDK 自有显示所有者接收。
    internal func openPrivateKeyView(accountID: Data, buffer: CitizenSDKPrivateKeyDisplayBuffer)
        throws -> (UInt64, CitizenSDKOperation<Void>) {
        try native.openPrivateKeyView(accountID: accountID, buffer: buffer)
    }
    internal func revealPrivateKeyView(_ viewID: UInt64) throws { try native.revealPrivateKeyView(viewID) }
    internal func cancelPrivateKeyView(_ viewID: UInt64) throws { try native.cancelPrivateKeyView(viewID) }
    internal func finishPrivateKeyView(_ viewID: UInt64) throws { try native.finishPrivateKeyView(viewID) }
    internal func isPrivateKeyAuthenticationActive(_ operationID: UInt64) -> Bool { native.isPrivateKeyAuthenticationActive(operationID) }
    internal func cancelPrivateKeyAuthentication(_ operationID: UInt64) { native.cancelPrivateKeyAuthentication(operationID) }

    /// Binds one application-encoded opaque RuntimeCall to exact chain state without signing.
    public func prepareTransaction(sourceAccountID: Data,
                                   callData: Data) async throws -> CitizenPreparedTransaction {
        guard (1...1_024 * 1_024).contains(callData.count) else {
            throw CitizenSDKError(.invalidArgument, "callData must contain 1...1 MiB bytes")
        }
        return try await native.prepareTransaction(
            source: CitizenSDKInputLimits.accountID(sourceAccountID, label: "sourceAccountID"),
            callData: callData
        ).value()
    }

    public func cancelPreparedTransaction(preparationID: String) throws {
        guard preparationID.range(
            of: #"^0x[0-9a-f]{32}$"#,
            options: .regularExpression
        ) != nil else {
            throw CitizenSDKError(.invalidArgument, "preparationID is invalid")
        }
        try native.cancelPreparedTransaction(preparationID)
    }

    public func executePreparedTransaction(preparationID: String) async throws
        -> CitizenTransactionExecution {
        try await native.executePreparedTransaction(preparationID).value()
    }

    public func consumePreparedTransactionQrResponse(executionID: String, response: String)
        async throws -> CitizenTransactionExecutionCompleted {
        guard (1...2_331).contains(response.utf8.count) else {
            throw CitizenSDKError(.invalidArgument, "response must contain 1...2331 UTF-8 bytes")
        }
        let value = try await native
            .consumePreparedTransactionQrResponse(executionID, response: response).value()
        guard case let .completed(completed) = value else {
            throw CitizenSDKError(.integrity, "Core did not return a terminal transaction execution")
        }
        return completed
    }

    public func cancelPreparedTransactionExecution(executionID: String) throws {
        try native.cancelPreparedTransactionExecution(executionID)
    }

    /// Reads the local execution-only history. No account or business filtering is inferred.
    public func getTransactionHistory(beforeExecutionID: String? = nil, limit: UInt32 = 100)
        async throws -> CitizenTransactionHistoryPage {
        guard (1...100).contains(limit) else {
            throw CitizenSDKError(.invalidArgument, "limit must be in 1...100")
        }
        return try await native.getTransactionHistory(
            beforeExecutionID: beforeExecutionID,
            limit: limit
        ).value()
    }

    /// Advances a bounded batch of non-terminal SDK-submitted transactions.
    public func syncTransactionHistory() async throws -> CitizenTransactionHistoryPage {
        try await native.syncTransactionHistory().value()
    }

    /// Destroys only checkpoint-safe Core state. A running instance must first
    /// complete `stop`; accepted requests and secure wallet UI fail BUSY.
    public func close() throws {
        stateLock.lock()
        if closed { stateLock.unlock(); return }
        let state = lifecycleValue
        stateLock.unlock()
        switch state {
        case .created, .stopped, .startFailed: break
        case .disposed: return
        case .running:
            throw CitizenSDKError(.invalidState, "A running CitizenSDK must complete stop before close")
        case .starting, .importingState:
            throw CitizenSDKError(.busy, "CitizenSDK lifecycle transition is still running")
        }
        try finishClose()
    }

    private func finishClose() throws {
        let registry = CitizenSDKWalletFlowRegistry.shared
        guard let reservation = try registry.beginClose(self) else {
            commitClosedFacade(reservation: nil)
            return
        }
        do {
            try native.close()
        } catch {
            let requiresSupervisor = registry.failClose(
                self, reservation: reservation, teardownStarted: native.teardownStarted
            )
            if requiresSupervisor { enqueueForSupervisedClose() }
            throw error
        }
        commitClosedFacade(reservation: reservation)
    }

    /// Used only by the detach supervisor. Unlike Native-only recovery this
    /// retains the facade, respects active SDK wallet UI ownership, and runs a
    /// normal checkpointing stop before close when the Core is running.
    @_spi(CitizenSDKFlutter)
    public func supervisedClose() async throws {
        // Recovery must not consult `lifecycleValue`: the Core can complete a
        // stop before its lifecycle event reaches this facade. Native queries
        // the authoritative C lifecycle and resumes any partial ABI teardown.
        let registry = CitizenSDKWalletFlowRegistry.shared
        guard let reservation = try registry.beginClose(self, origin: .supervised) else {
            commitClosedFacade(reservation: nil)
            return
        }
        do {
            try await native.supervisedClose()
        } catch {
            // This method already runs under the lifecycle supervisor, so even
            // a pre-teardown failure stays closing between actor retries.
            _ = registry.failClose(
                self, reservation: reservation, teardownStarted: native.teardownStarted
            )
            throw error
        }
        commitClosedFacade(reservation: reservation)
    }

    /// Official Flutter adapter SPI; not part of the application-facing API.
    @_spi(CitizenSDKFlutter)
    public func enqueueForSupervisedClose() {
        Task { await CitizenSDKLifecycleSupervisor.shared.adopt(self) }
    }

    /// Commits public disposal only after successful Core destruction. The
    /// idempotent gate also makes concurrent explicit/reaper completion commit
    /// the registry tombstone exactly once.
    private func commitClosedFacade(
        reservation: CitizenSDKWalletFlowRegistry.CloseReservation?
    ) {
        // Publish the destroyed tombstone first, without holding `stateLock`,
        // so no wallet UI can enter while facade disposal is being committed.
        CitizenSDKWalletFlowRegistry.shared.commitClosed(self, reservation: reservation)
        stateLock.lock()
        let didCommit = !closed
        if didCommit {
            lifecycleValue = .disposed
            closed = true
            eventHandler = nil
        }
        stateLock.unlock()
    }

    /// Secret-bearing wallet mutation entry points are main-actor isolated:
    /// only the SDK-owned Apple UI may construct their buffers, and the native
    /// admission call borrows them synchronously before the returned operation
    /// is awaited.
    @MainActor
    internal func prepareWallet(wordCount: UInt32, password: CitizenSDKSensitiveBuffer) async throws -> CitizenSDKPreparedWallet {
        guard [12, 18, 24].contains(wordCount) else { throw CitizenSDKError(.invalidArgument, "word count must be 12, 18 or 24") }
        let operation = try native.prepareWallet(wordCount: wordCount, password: password)
        password.clear()
        return CitizenSDKPreparedWallet(native: native, handle: try await operation.value())
    }

    @MainActor
    internal func importWallet(mnemonic: CitizenSDKSensitiveBuffer,
                               password: CitizenSDKSensitiveBuffer) async throws -> CitizenWalletProfile? {
        try CitizenSDKWalletMutationGate.shared.enterWalletUI()
        defer { CitizenSDKWalletMutationGate.shared.leaveWalletUI() }
        // Admission borrows both buffers synchronously on MainActor. Only the
        // Sendable operation result crosses the suspension point.
        let operation = try native.importWallet(mnemonic: mnemonic, password: password)
        mnemonic.clear(); password.clear()
        return try await operation.value()
    }

    @MainActor
    internal func addWalletAccounts(mnemonic: CitizenSDKSensitiveBuffer, password: CitizenSDKSensitiveBuffer,
                                    indices: [UInt32]) async throws -> CitizenWalletProfile {
        let checked = try CitizenSDKInputLimits.additionalIndices(indices)
        try CitizenSDKWalletMutationGate.shared.enterWalletUI()
        defer { CitizenSDKWalletMutationGate.shared.leaveWalletUI() }
        let operation = try native.addAccounts(mnemonic: mnemonic, password: password, indices: checked)
        mnemonic.clear(); password.clear()
        let added = try await operation.value()
        guard added.count == checked.count, Set(added.map(\.index)) == Set(checked) else {
            throw CitizenSDKError(.integrity, "add accounts result does not match requested indices")
        }
        guard let profile = try await native.walletProfile().value(),
              added.allSatisfy({ account in profile.accounts.contains(where: { $0.accountID == account.accountID }) }) else {
            throw CitizenSDKError(.integrity, "updated wallet profile is missing an added account")
        }
        return profile
    }

    @MainActor
    internal func commit(_ prepared: CitizenSDKPreparedWallet) async throws -> CitizenWalletProfile? {
        try CitizenSDKWalletMutationGate.shared.enterWalletUI()
        defer { CitizenSDKWalletMutationGate.shared.leaveWalletUI() }
        return try await prepared.commit()
    }

    private func receive(_ event: CitizenSDKEvent) {
        stateLock.lock()
        if case let .lifecycleChanged(_, lifecycle) = event { lifecycleValue = lifecycle }
        let handler = eventHandler
        stateLock.unlock()
        handler?(event)
    }
}

/// 本地签名始终经核心账户归属检查与设备金库授权；公开验签不创建钱包或访问金库。
public struct CitizenSigning: Sendable {
    private let native: CitizenSDKNative
    internal init(native: CitizenSDKNative) { self.native = native }

    public func sign(accountID: Data, message: Data) async throws -> CitizenSignature {
        try await native.sign(accountID: CitizenSDKInputLimits.accountID(accountID),
                              message: CitizenSDKInputLimits.signingPayload(message)).value()
    }

    public func begin(_ intent: CitizenSigningIntent) async throws -> CitizenSigningOutcome {
        try await native.beginSigning(intent).value()
    }

    public func consumeExternalSignature(sessionID: String,
                                         response: String) async throws -> CitizenSigningOutcome {
        try Self.validateExternal(sessionID: sessionID, response: response)
        return try await native.consumeExternalSignature(
            sessionID: sessionID, response: response).value()
    }

    public func cancel(sessionID: String) throws -> Bool {
        guard (1...128).contains(sessionID.utf8.count) else {
            throw CitizenSDKError(.invalidArgument, "external signing sessionID is invalid")
        }
        return try native.cancelSigningSession(sessionID)
    }

    internal static func validateExternal(sessionID: String, response: String) throws {
        guard (1...128).contains(sessionID.utf8.count),
              (1...2_331).contains(response.utf8.count) else {
            throw CitizenSDKError(.invalidArgument, "external signing response is invalid")
        }
    }

    public static func verify(accountID: Data, signature: Data, message: Data) throws -> Bool {
        try CitizenSDKNative.verify(accountID: CitizenSDKInputLimits.accountID(accountID),
                                    signature: signature,
                                    message: CitizenSDKInputLimits.signingPayload(message))
    }
}

/// Process-wide mutation serialization. Every mutable field is reached only
/// through the synchronous `enter`/`leave` helpers while `lock` is held, so
/// async callers never directly share unprotected state across executors.
private final class CitizenSDKWalletMutationGate: @unchecked Sendable {
    static let shared = CitizenSDKWalletMutationGate()
    private let lock = NSLock()
    private var active = false

    func perform<T>(_ operation: () async throws -> T) async throws -> T {
        try enter()
        defer { leave() }
        return try await operation()
    }

    private func enter() throws {
        lock.lock()
        guard !active else { lock.unlock(); throw CitizenSDKError(.busy, "another wallet mutation is active") }
        active = true
        lock.unlock()
    }

    private func leave() {
        lock.lock(); active = false; lock.unlock()
    }

    /// SDK-owned Apple wallet UI uses an explicit synchronous gate so secret
    /// buffers are admitted on MainActor before any async suspension.
    func enterWalletUI() throws { try enter() }
    func leaveWalletUI() { leave() }
}
