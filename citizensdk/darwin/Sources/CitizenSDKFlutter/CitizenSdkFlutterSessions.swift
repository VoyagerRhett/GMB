@_spi(CitizenSDKFlutter) import CitizenSDK
import CoreFoundation
import Foundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

/// Process session registry for the fixed Flutter protocol. Native SDK
/// identities and accepted Core request IDs never leave this object.
@MainActor
internal final class CitizenSdkFlutterSessions: NSObject, @preconcurrency FlutterStreamHandler {
    private final class Session {
        let sdk: CitizenSdk
        var nextRequest: Int64 = 1
        var nextEvent: Int64 = 1
        var closing = false
        var outstanding: [UUID: Outstanding] = [:]
        init(_ sdk: CitizenSdk) { self.sdk = sdk }
    }

    private struct Outstanding {
        let task: Task<Void, Never>
        let cancel: (() -> Void)?
    }

    private struct ClosePreparation {
        let session: Session
        let outstanding: [Outstanding]
    }

    private var sessions: [String: Session] = [:]
    private let walletFlow = CitizenSdkFlutterWalletFlow()
    private var sink: FlutterEventSink?
    private let subscriptionEpoch = CitizenSdkFlutterSubscriptionEpoch()
    private var detached = false
    private let verifySignature: (Data, Data, Data) throws -> Bool

    init(verifySignature: @escaping (Data, Data, Data) throws -> Bool = {
        try CitizenSigning.verify(accountID: $0, signature: $1, message: $2)
    }) {
        self.verifySignature = verifySignature
        super.init()
    }

    func dispatch(_ request: CitizenSdkFlutterCodec.Request, result: @escaping FlutterResult) {
        guard !detached, !subscriptionEpoch.isInvalidated else {
            fail(result, .unavailable, "CitizenSDK Flutter engine is detached", request)
            return
        }
        if case let .verify(accountID, signature, payload) = request {
            // 此分支不查会话、不占序号、不启动事件流，也不创建金库或链资源。
            do { result([CitizenSdkFlutterCodec.version, try verifySignature(accountID, signature, payload)]) }
            catch { fail(result, error, request) }
            return
        }
        if case let .open(modules) = request { open(modules, result); return }
        guard let sessionID = request.sessionID, let sequence = request.sequence,
              let session = sessions[sessionID] else {
            fail(result, .notFound, "CitizenSDK session was not found", request)
            return
        }
        guard !session.closing, sequence == session.nextRequest else {
            fail(result, .conflict, "CitizenSDK request sequence is not the next session sequence", request)
            return
        }
        guard session.nextRequest < Int64.max else {
            fail(result, .integrity, "CitizenSDK request sequence space is exhausted", request); return
        }
        session.nextRequest += 1
        route(session, request: request, result: result)
    }

    func closeAll() async {
        // Prepare every session before awaiting any operation. Otherwise one
        // slow session could prevent later sessions from even receiving their
        // cancellation signal during engine detach.
        let prepared = Array(sessions.values).map(prepareForClose)
        await citizenSDKFlutterCancelAndDrain(
            prepared.flatMap(\.outstanding),
            cancel: Self.cancel,
            wait: { await $0.task.value }
        )
        await citizenSDKFlutterCloseEverySession(
            prepared,
            close: { try await self.finishSupervisedClose($0.session) },
            recover: { preparation in
                // Plugin detach must not abandon a live callback/host context.
                // The facade supervisor retains wallet-flow ownership, retries
                // checkpointing stop, then releases only after Core destroy.
                let session = preparation.session
                session.sdk.enqueueForSupervisedClose()
                sessions.removeValue(forKey: session.sdk.sessionID)
            }
        )
    }

    /// Permanently rejects callbacks captured by this Flutter engine. This is
    /// deliberately nonisolated so engine detach can invalidate callback epochs
    /// synchronously before its messenger starts deallocating.
    nonisolated func invalidateEventEpochForDetach() {
        subscriptionEpoch.invalidate()
    }

    /// Drops the engine-owned sink on the main actor. The epoch has already
    /// been invalidated synchronously, so no queued native callback can reach
    /// the sink while this actor hop is pending.
    func detachEventSink() {
        detached = true
        sink = nil
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        guard !detached, !subscriptionEpoch.isInvalidated else {
            return FlutterError(code: "citizensdk.unavailable",
                                message: "CitizenSDK Flutter engine is detached",
                                details: CitizenSdkFlutterCodec.error(.unavailable,
                                    "CitizenSDK Flutter engine is detached", session: nil, sequence: nil, method: "open"))
        }
        guard let tuple = arguments as? [Any?], tuple.count == 1,
              Self.exactProtocolVersion(tuple[0]) else {
            return FlutterError(code: "citizensdk.invalidArgument",
                                message: "CitizenSDK event subscription tuple is invalid",
                                details: CitizenSdkFlutterCodec.error(.invalidArgument,
                                    "CitizenSDK event subscription tuple is invalid", session: nil, sequence: nil, method: "open"))
        }
        guard sink == nil else {
            return FlutterError(code: "citizensdk.busy", message: "CitizenSDK event subscription is already active",
                                details: CitizenSdkFlutterCodec.error(.busy,
                                    "CitizenSDK event subscription is already active", session: nil, sequence: nil, method: "open"))
        }
        do { _ = try subscriptionEpoch.advance() }
        catch {
            return FlutterError(code: "citizensdk.integrity", message: "CitizenSDK event generation is exhausted",
                                details: CitizenSdkFlutterCodec.error(.integrity,
                                    "CitizenSDK event generation is exhausted", session: nil, sequence: nil, method: "open"))
        }
        sink = events
        sessions.values.forEach { session in
            emit(session, type: "lifecycleChanged", payload: [CitizenSdkFlutterCodec.lifecycle(session.sdk.lifecycle)])
            if let value = try? session.sdk.capabilities() {
                emit(session, type: "capabilitiesChanged", payload: [CitizenSdkFlutterCodec.capabilities(value)])
            }
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if detached || subscriptionEpoch.isInvalidated {
            sink = nil
            return nil
        }
        do { _ = try subscriptionEpoch.advance() }
        catch {
            return FlutterError(code: "citizensdk.integrity", message: "CitizenSDK event generation is exhausted",
                                details: CitizenSdkFlutterCodec.error(.integrity,
                                    "CitizenSDK event generation is exhausted", session: nil, sequence: nil, method: "open"))
        }
        sink = nil
        return nil
    }

    private func open(_ modules: CitizenSDKModules, _ result: @escaping FlutterResult) {
        do {
            let sdk = try CitizenSdk.open(modules: modules)
            let session = Session(sdk)
            let epoch = subscriptionEpoch
            _ = try citizenSDKFlutterFinalizeOpen(
                sdk,
                install: { sdk in
                    try sdk.setEventHandler { [weak self, weak session, epoch] event in
                        let generation = epoch.snapshot()
                        Task { @MainActor in
                            guard let self, let session else { return }
                            self.onSDKEvent(session, event, expectedGeneration: generation)
                        }
                    }
                },
                cleanup: { sdk in
                    try? sdk.setEventHandler(nil)
                    citizenSDKFlutterCloseOrSupervise(
                        close: sdk.close,
                        supervise: sdk.enqueueForSupervisedClose
                    )
                }
            )
            sessions[sdk.sessionID] = session
            success(result, session: sdk.sessionID, sequence: 0,
                    value: [CitizenSdkFlutterCodec.lifecycle(sdk.lifecycle), Int64(1)])
            emit(session, type: "lifecycleChanged", payload: [CitizenSdkFlutterCodec.lifecycle(sdk.lifecycle)])
            if let capabilities = try? sdk.capabilities() {
                emit(session, type: "capabilitiesChanged", payload: [CitizenSdkFlutterCodec.capabilities(capabilities)])
            }
        } catch {
            fail(result, error, .open(modules: modules))
        }
    }

    private func route(_ session: Session, request: CitizenSdkFlutterCodec.Request,
                       result: @escaping FlutterResult) {
        switch request {
        case let .empty(method, _, _):
            switch method {
            case "start": run(session, request, result) {
                try await session.sdk.start(); return [CitizenSdkFlutterCodec.lifecycle(session.sdk.lifecycle)]
            }
            case "stop": run(session, request, result) {
                try await session.sdk.stop(); return [CitizenSdkFlutterCodec.lifecycle(session.sdk.lifecycle)]
            }
            case "close": close(session, request, result)
            case "getCapabilities":
                do { success(result, request, [CitizenSdkFlutterCodec.capabilities(try session.sdk.capabilities())]) }
                catch { fail(result, error, request) }
            case "getFinalizedHead": run(session, request, result) {
                [CitizenSdkFlutterCodec.block(try await session.sdk.finalizedHead())]
            }
            case "getSyncStatus": run(session, request, result) {
                [CitizenSdkFlutterCodec.syncStatus(try await session.sdk.syncStatus())]
            }
            case "getBestHead": run(session, request, result) {
                [CitizenSdkFlutterCodec.block(try await session.sdk.bestHead())]
            }
            case "exportState": run(session, request, result) {
                [CitizenSdkFlutterCodec.chainState(try await session.sdk.exportState())]
            }
            case "getGenesisHash":
                do { success(result, request, [CitizenSdkFlutterCodec.hex(try session.sdk.genesisHash())]) }
                catch { fail(result, error, request) }
            case "getFeeSnapshot": run(session, request, result) {
                [CitizenSdkFlutterCodec.fee(try await session.sdk.feeSnapshot())]
            }
            case "getWalletProfile": run(session, request, result) {
                [CitizenSdkFlutterCodec.profile(try await session.sdk.walletProfile())]
            }
            case "getWalletState": run(session, request, result) {
                [CitizenSdkFlutterCodec.walletState(try await session.sdk.walletState())]
            }
            case "importWallet": wallet(session, request, result)
            case "deleteWallet": run(session, request, result) {
                [CitizenSdkFlutterCodec.profile(try await session.sdk.deleteWallet())]
            }
            case "reconcileWalletCleanup": run(session, request, result) {
                [CitizenSdkFlutterCodec.profile(try await session.sdk.reconcileWalletCleanup())]
            }
            default: fail(result, .unsupported, "Unsupported method", request)
            }
        case let .account(method, _, _, accountID):
            switch method {
            case "viewAccountPrivateKey":
                run(session, request, result, cancel: { [walletFlow] in walletFlow.cancelSession(session.sdk.sessionID) }) { [walletFlow] in
                    try await walletFlow.viewAccountPrivateKey(sdk: session.sdk, request: request, accountID: accountID)
                    return []
                }
            case "getAccountBalance": run(session, request, result) {
                [CitizenSdkFlutterCodec.balance(try await session.sdk.accountBalance(accountID: accountID))]
            }
            case "getAccountNonce": run(session, request, result) {
                [CitizenSdkFlutterCodec.nonce(try await session.sdk.accountNonce(accountID: accountID))]
            }
            case "setActiveWalletAccount": run(session, request, result) {
                [CitizenSdkFlutterCodec.profile(try await session.sdk.setActiveWalletAccount(accountID: accountID))]
            }
            case "deleteWalletAccount": run(session, request, result) {
                [CitizenSdkFlutterCodec.profile(try await session.sdk.deleteWalletAccount(accountID: accountID))]
            }
            case "deleteAccount": run(session, request, result) {
                [CitizenSdkFlutterCodec.walletState(try await session.sdk.deleteAccount(accountID: accountID))]
            }
            default: fail(result, .unsupported, "Unsupported method", request)
            }
        case let .balances(_, _, accountIDs): run(session, request, result) {
            [try await session.sdk.accountBalances(accountIDs: accountIDs).map(CitizenSdkFlutterCodec.balance)]
        }
        case let .blockNumber(_, _, number): run(session, request, result) {
            [CitizenSdkFlutterCodec.block(try await session.sdk.finalizedBlock(at: number))]
        }
        case let .resolveBlock(_, _, hash, number): run(session, request, result) {
            [CitizenSdkFlutterCodec.block(try await session.sdk.resolveFinalizedBlock(hash: hash, number: number))]
        }
        case let .block(method, _, _, block):
            switch method {
            case "getBlockHeader": run(session, request, result) {
                [CitizenSdkFlutterCodec.blockHeader(try await session.sdk.blockHeader(block))]
            }
            case "getBlockBody": run(session, request, result) {
                [CitizenSdkFlutterCodec.blockBody(try await session.sdk.blockBody(block))]
            }
            case "getRuntimeContext": run(session, request, result) {
                [CitizenSdkFlutterCodec.runtimeContext(try await session.sdk.runtimeContext(block))]
            }
            case "getSystemEvents": run(session, request, result) {
                [CitizenSdkFlutterCodec.optionalBytes(try await session.sdk.systemEvents(block))]
            }
            default: fail(result, .unsupported, "Unsupported block method", request)
            }
        case let .storage(_, _, block, key): run(session, request, result) {
            [CitizenSdkFlutterCodec.optionalBytes(try await session.sdk.storage(block, key: key))]
        }
        case let .storageBatch(_, _, block, keys): run(session, request, result) {
            [try await session.sdk.storageBatch(block, keys: keys).map(CitizenSdkFlutterCodec.optionalBytes)]
        }
        case let .storageKeysPage(_, _, block, prefix, startKey, limit):
            run(session, request, result) {
                [try await session.sdk.storageKeysPaged(
                    block, prefix: prefix, startKey: startKey, limit: limit)]
            }
        case let .runtimeAPI(_, _, block, method, arguments): run(session, request, result) {
            [try await session.sdk.callRuntimeAPI(block, method: method, arguments: arguments)]
        }
        case let .importState(_, _, state): run(session, request, result) {
            try await session.sdk.importState(state); return []
        }
        case .create, .addAccounts: wallet(session, request, result)
        case let .rename(method, _, _, accountID, name): run(session, request, result) {
            if method == "renameWalletAccount" {
                return [CitizenSdkFlutterCodec.profile(try await session.sdk.renameWalletAccount(accountID: accountID, name: name))]
            }
            if method == "importColdAccountId" {
                return [CitizenSdkFlutterCodec.walletState(try await session.sdk.importColdAccount(accountID: accountID, name: name))]
            }
            return [CitizenSdkFlutterCodec.walletState(try await session.sdk.renameAccount(accountID: accountID, name: name))]
        }
        case let .coldSS58(_, _, address, name): run(session, request, result) {
            [CitizenSdkFlutterCodec.walletState(try await session.sdk.importColdAccount(ss58Address: address, name: name))]
        }
        case let .reorder(_, _, revision, accountIDs): run(session, request, result) {
            [CitizenSdkFlutterCodec.walletState(try await session.sdk.reorderWalletAccountsWithoutDefaultChange(
                expectedRevision: revision, accountIDs: accountIDs))]
        }
        case let .sign(_, _, accountID, payload): run(session, request, result) {
            [CitizenSdkFlutterCodec.signature(try await session.sdk.signing.sign(accountID: accountID, message: payload))]
        }
        case let .deriveApplicationKey(_, _, accountID, salt, info): run(session, request, result) {
            [try await session.sdk.deriveApplicationKey(
                accountID: accountID, salt: salt, info: info)]
        }
        case let .beginSigning(_, _, intent): run(session, request, result) {
            [CitizenSdkFlutterCodec.signingOutcome(try await session.sdk.signing.begin(intent))]
        }
        case let .externalSignature(method, _, _, signingSessionID, response): run(session, request, result) {
            if method == "consumeExternalSignature" {
                return [CitizenSdkFlutterCodec.signingOutcome(
                    try await session.sdk.signing.consumeExternalSignature(
                        sessionID: signingSessionID, response: response))]
            }
            return [CitizenSdkFlutterCodec.defaultAccountChangeOutcome(
                try await session.sdk.consumeDefaultAccountChange(
                    sessionID: signingSessionID, response: response))]
        }
        case let .cancelSigning(_, _, signingSessionID):
            do { success(result, request, [try session.sdk.signing.cancel(sessionID: signingSessionID)]) }
            catch { fail(result, error, request) }
        case let .beginDefaultChange(_, _, revision, accountIDs, ttl): run(session, request, result) {
            [CitizenSdkFlutterCodec.defaultAccountChangeOutcome(
                try await session.sdk.beginDefaultAccountChange(
                    expectedRevision: revision, accountIDs: accountIDs, ttlSeconds: ttl))]
        }
        case let .prepareTransaction(_, _, source, callData): run(session, request, result) {
            [CitizenSdkFlutterCodec.preparedTransaction(
                try await session.sdk.prepareTransaction(
                    sourceAccountID: source, callData: callData))]
        }
        case let .cancelPreparedTransaction(_, _, preparationID):
            do {
                try session.sdk.cancelPreparedTransaction(preparationID: preparationID)
                success(result, request, [nil])
            } catch { fail(result, error, request) }
        case let .transactionExecution(method, _, _, executionID, response):
            if method == "cancelPreparedTransactionExecution" {
                do {
                    try session.sdk.cancelPreparedTransactionExecution(executionID: executionID)
                    success(result, request, [nil])
                } catch { fail(result, error, request) }
            } else {
                run(session, request, result) {
                    let value: CitizenTransactionExecution
                    if method == "executePreparedTransaction" {
                        value = try await session.sdk.executePreparedTransaction(preparationID: executionID)
                    } else {
                        value = .completed(try await session.sdk.consumePreparedTransactionQrResponse(
                            executionID: executionID, response: response!))
                    }
                    return [try CitizenSdkFlutterCodec.transactionExecution(value)]
                }
            }
        case let .transactionHistory(method, _, _, beforeExecutionID, limit):
            run(session, request, result) {
                let page = method == "getTransactionHistory"
                    ? try await session.sdk.getTransactionHistory(
                        beforeExecutionID: beforeExecutionID, limit: limit)
                    : try await session.sdk.syncTransactionHistory()
                return [try CitizenSdkFlutterCodec.transactionHistoryPage(page)]
            }
        case let .qr(method, _, _, fields): run(session, request, result,
            cancel: { [walletFlow] in walletFlow.cancelSession(session.sdk.sessionID) }) {
            switch method {
            case "qrParse":
                return [try session.sdk.qrParse(fields[0] as! String).coreJSON]
            case "qrCreateSignRequest":
                return [try session.sdk.qrCreateSignRequest(
                    action: UInt16(fields[0] as! Int64), signerAccountID: fields[1] as! Data,
                    reviewPayload: fields[2] as! Data, ttlSeconds: UInt64(fields[3] as! Int64))]
            case "qrConsumeSignResponse":
                return [FlutterStandardTypedData(bytes: try session.sdk.qrConsumeSignResponse(fields[0] as! String))]
            case "qrCancelSignRequest":
                return [try session.sdk.qrCancelSignRequest(fields[0] as! String)]
            case "qrEncodeAccountId":
                return [try session.sdk.qrEncodeAccountID(fields[0] as! Data)]
            case "qrDecodeLuminance":
                return [try session.sdk.qrDecodeLuminance(fields[0] as! Data,
                    width: UInt32(fields[1] as! Int64), height: UInt32(fields[2] as! Int64),
                    rowStride: UInt32(fields[3] as! Int64)).coreJSON]
            case "qrEncode":
                let value = try session.sdk.qrEncode(fields[0] as! String,
                    scale: UInt32(fields[1] as! Int64))
                return [Int64(value.width), Int64(value.height),
                        FlutterStandardTypedData(bytes: value.luminance)]
            case "qrScan", "signQrRequest":
                return [try await self.walletFlow.qr(sdk: session.sdk, request: request,
                    signText: method == "signQrRequest" ? fields[0] as? String : nil).coreJSON]
            default: throw CitizenSDKError(.unsupported, "Unsupported QR method")
            }
        }
        case .open, .verify: fail(result, .invalidState, "A stateless request cannot be routed as a session request", request)
        }
    }

    private func wallet(_ session: Session, _ request: CitizenSdkFlutterCodec.Request,
                        _ result: @escaping FlutterResult) {
        run(session, request, result, cancel: { [weak self] in
            if let id = request.sessionID { self?.walletFlow.cancelSession(id) }
        }) { [walletFlow] in
            [CitizenSdkFlutterCodec.profile(try await walletFlow.launch(sdk: session.sdk, request: request))]
        }
    }

    private func run(_ session: Session, _ request: CitizenSdkFlutterCodec.Request,
                     _ result: @escaping FlutterResult, cancel: (() -> Void)? = nil,
                     operation: @escaping () async throws -> [Any?]) {
        let id = UUID()
        let task = Task { [weak self, weak session] in
            guard let self, let session else { return }
            let outcome: Result<[Any?], Error>
            do { outcome = .success(try await operation()) }
            catch { outcome = .failure(error) }
            // Remove ownership before invoking FlutterResult: user test code or
            // the Dart messenger may synchronously reenter `close`.
            _ = citizenSDKFlutterTakeOutstanding(id, from: &session.outstanding)
            // Engine detach revokes the reply channel. The task must still
            // finish so Core can close, but it must not invoke a stale result.
            guard !self.detached, !self.subscriptionEpoch.isInvalidated else { return }
            switch outcome {
            case let .success(value): self.success(result, request, value)
            case let .failure(error): self.fail(result, error, request)
            }
        }
        session.outstanding[id] = Outstanding(task: task, cancel: cancel)
    }

    private func close(_ session: Session, _ request: CitizenSdkFlutterCodec.Request,
                       _ result: @escaping FlutterResult) {
        guard !session.closing else { fail(result, .busy, "CitizenSDK close is already running", request); return }
        session.closing = true
        Task { [weak self, weak session] in
            guard let self, let session else { return }
            do {
                try await self.supervisedClose(session)
                guard !self.detached, !self.subscriptionEpoch.isInvalidated else { return }
                self.success(result, request, ["disposed"])
            } catch {
                if self.detached || self.subscriptionEpoch.isInvalidated {
                    session.sdk.enqueueForSupervisedClose()
                    self.sessions.removeValue(forKey: session.sdk.sessionID)
                    return
                }
                session.closing = false
                self.fail(result, error, request)
            }
        }
    }

    private func supervisedClose(_ session: Session) async throws {
        let prepared = prepareForClose(session)
        await citizenSDKFlutterCancelAndDrain(
            prepared.outstanding,
            cancel: Self.cancel,
            wait: { await $0.task.value }
        )
        try await finishSupervisedClose(session)
    }

    private func prepareForClose(_ session: Session) -> ClosePreparation {
        session.closing = true
        walletFlow.cancelSession(session.sdk.sessionID)
        return ClosePreparation(session: session, outstanding: Array(session.outstanding.values))
    }

    private static func cancel(_ value: Outstanding) {
        value.cancel?()
        value.task.cancel()
    }

    private func finishSupervisedClose(_ session: Session) async throws {
        // The facade's cached lifecycle event may lag behind Core. Its SPI
        // recovery path queries the authoritative C lifecycle, checkpoints a
        // truly running Core, and resumes partial teardown monotonically.
        try await session.sdk.supervisedClose()
        sessions.removeValue(forKey: session.sdk.sessionID)
    }

    private func onSDKEvent(_ session: Session, _ event: CitizenSDKEvent, expectedGeneration: UInt64) {
        guard sessions[session.sdk.sessionID] === session else { return }
        switch event {
        case .historyChanged:
            emit(session, type: "historyChanged", payload: [], expectedGeneration: expectedGeneration)
        case let .finalizedBlockChanged(_, finalized):
            emit(session, type: "finalizedBlockChanged",
                 payload: [CitizenSdkFlutterCodec.block(finalized)],
                 expectedGeneration: expectedGeneration)
        case let .lifecycleChanged(_, lifecycle):
            emit(session, type: "lifecycleChanged", payload: [CitizenSdkFlutterCodec.lifecycle(lifecycle)],
                 expectedGeneration: expectedGeneration)
        case let .capabilitiesChanged(_, capabilities):
            emit(session, type: "capabilitiesChanged", payload: [CitizenSdkFlutterCodec.capabilities(capabilities)],
                 expectedGeneration: expectedGeneration)
        @unknown default: return
        }
    }

    private func emit(_ session: Session, type: String, payload: [Any?], expectedGeneration: UInt64? = nil) {
        guard !detached, subscriptionEpoch.accepts(expectedGeneration),
              let sink, session.nextEvent < Int64.max else { return }
        let sequence = session.nextEvent; session.nextEvent += 1
        guard let encoded = try? CitizenSdkFlutterCodec.event(
            session: session.sdk.sessionID, sequence: sequence, type: type, payload: payload
        ) else { return }
        sink(encoded)
    }

    private func success(_ result: @escaping FlutterResult, _ request: CitizenSdkFlutterCodec.Request,
                         _ value: [Any?]) {
        success(result, session: request.sessionID!, sequence: request.sequence!, value: value)
    }
    private func success(_ result: @escaping FlutterResult, session: String, sequence: Int64, value: [Any?]) {
        result(CitizenSdkFlutterCodec.response(session: session, sequence: sequence, value: value))
    }

    private func fail(_ result: @escaping FlutterResult, _ error: Error,
                      _ request: CitizenSdkFlutterCodec.Request) {
        if let contract = error as? CitizenSdkFlutterCodec.ContractFailure {
            fail(result, contract.code, contract.message, request, session: contract.session,
                 sequence: contract.sequence, stage: contract.stage)
        } else if let sdk = error as? CitizenSDKError {
            fail(result, sdk.code, sdk.message, request, stage: sdk.stage)
        } else if error is CancellationError {
            fail(result, .cancelled, "CitizenSDK operation cancelled", request)
        } else {
            fail(result, .internalFailure, "CitizenSDK host failure", request)
        }
    }
    private func fail(_ result: @escaping FlutterResult, _ code: CitizenSDKErrorCode, _ message: String,
                      _ request: CitizenSdkFlutterCodec.Request, session: String? = nil, sequence: Int64? = nil,
                      stage: CitizenSDKFailureStage? = nil) {
        result(FlutterError(code: "citizensdk.\(CitizenSdkFlutterCodec.errorName(code))", message: message,
                            details: CitizenSdkFlutterCodec.error(code, message,
                                session: session ?? request.sessionID, sequence: sequence ?? request.sequence,
                                method: request.method, stage: stage)))
    }

    internal static func exactProtocolVersion(_ raw: Any?) -> Bool {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number) else { return false }
        return number.int64Value == CitizenSdkFlutterCodec.version
    }
}

/// Thread-safe epoch captured at native callback time, before hopping to the
/// Flutter main actor. Old queued events can never target a replacement sink.
internal final class CitizenSdkFlutterSubscriptionEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64
    private var invalidated = false
    init(_ value: UInt64 = 0) { self.value = value }
    func snapshot() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    var isInvalidated: Bool { lock.lock(); defer { lock.unlock() }; return invalidated }
    func advance() throws -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        guard !invalidated else { throw CitizenSDKError(.invalidState, "event generation is invalidated") }
        guard value < UInt64.max else { throw CitizenSDKError(.integrity, "event generation is exhausted") }
        value += 1
        return value
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        invalidated = true
    }
    func accepts(_ expected: UInt64?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !invalidated && (expected == nil || expected == value)
    }
}

/// Starts a plugin detach exactly once and fixes the synchronous teardown
/// order. Handler revocation happens before epoch invalidation, while the
/// engine messenger is still valid. Session closure is scheduled separately.
internal final class CitizenSdkFlutterDetachCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false

    func begin(
        revokeMethodHandler: () -> Void,
        revokeEventHandler: () -> Void,
        invalidateEventEpoch: () -> Void
    ) -> Bool {
        lock.lock()
        guard !started else { lock.unlock(); return false }
        started = true
        lock.unlock()
        revokeMethodHandler()
        revokeEventHandler()
        invalidateEventEpoch()
        return true
    }
}

/// Closes every snapshotted Flutter session. One failing session cannot skip
/// later sessions; the failure path transfers ownership to Core supervision.
@MainActor
internal func citizenSDKFlutterCloseEverySession<Value>(
    _ values: [Value],
    close: @MainActor (Value) async throws -> Void,
    recover: @MainActor (Value) -> Void
) async {
    for value in values {
        do { try await close(value) }
        catch { recover(value) }
    }
}

/// Cancels every operation before awaiting any one of them. This prevents the
/// first slow operation from keeping later sessions or wallet UI alive without
/// having received their cancellation signal.
@MainActor
internal func citizenSDKFlutterCancelAndDrain<Value>(
    _ values: [Value],
    cancel: @MainActor (Value) -> Void,
    wait: @MainActor (Value) async -> Void
) async {
    values.forEach(cancel)
    for value in values { await wait(value) }
}

/// Production uses this removal before invoking FlutterResult, so a reentrant
/// close can never observe or await the operation that is delivering it.
@MainActor
internal func citizenSDKFlutterTakeOutstanding<Value>(
    _ id: UUID,
    from values: inout [UUID: Value]
) -> Value? {
    values.removeValue(forKey: id)
}

/// Installs Flutter event ownership or closes the freshly-opened SDK before
/// propagating the original installation error.
@MainActor
internal func citizenSDKFlutterFinalizeOpen<Value>(
    _ value: Value,
    install: (Value) throws -> Void,
    cleanup: (Value) -> Void
) throws -> Value {
    do { try install(value); return value }
    catch { cleanup(value); throw error }
}

/// A failed Flutter listener installation still owns a live ABI callback and
/// host context. If synchronous close cannot finish, transfer the facade to
/// the supervised reaper instead of relying on a later `deinit` side effect.
@MainActor
internal func citizenSDKFlutterCloseOrSupervise(
    close: () throws -> Void,
    supervise: () -> Void
) {
    do { try close() }
    catch { supervise() }
}
