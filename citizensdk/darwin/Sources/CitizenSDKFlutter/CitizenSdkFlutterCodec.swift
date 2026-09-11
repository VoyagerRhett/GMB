import CitizenSDK
import CoreFoundation
import Foundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

/// Fixed-position StandardMessageCodec contract shared with Android and Dart.
internal enum CitizenSdkFlutterCodec {
    static let methodChannel = "citizen/sdk/core/v1"
    static let eventChannel = "citizen/sdk/events/v1"
    static let version: Int64 = 1
    static let eventTypes: Set<String> = ["lifecycleChanged", "capabilitiesChanged", "historyChanged"]
    static let methods: Set<String> = [
        "open", "start", "stop", "close", "getCapabilities", "getFinalizedHead",
        "getSyncStatus", "getBestHead", "getFinalizedBlockAt", "resolveFinalizedBlock",
        "getBlockHeader", "getBlockBody", "getRuntimeContext", "getStorage", "getStorageBatch",
        "getSystemEvents", "exportState", "importState",
        "getGenesisHash", "getAccountBalance", "getAccountBalances", "getAccountNonce", "getFeeSnapshot", "getWalletProfile", "viewAccountPrivateKey",
        "getWalletState", "importColdAccountId", "importColdAccountSs58",
        "reorderWalletAccountsWithoutDefaultChange", "renameAccount", "deleteAccount",
        "createWallet", "importWallet", "addWalletAccounts", "setActiveWalletAccount",
        "renameWalletAccount", "deleteWalletAccount", "deleteWallet", "reconcileWalletCleanup",
        "signWalletPayload", "beginSigning", "consumeExternalSignature", "cancelSigning",
        "beginDefaultAccountChange", "consumeDefaultAccountChange",
        "verifySignature", "prepareTransaction", "cancelPreparedTransaction",
        "executePreparedTransaction", "consumePreparedTransactionQrResponse",
        "cancelPreparedTransactionExecution", "getTransactionHistory", "syncTransactionHistory",
        "qrParse", "qrCreateSignRequest", "qrConsumeSignResponse", "qrCancelSignRequest", "qrEncodeAccountId",
        "qrDecodeLuminance", "qrEncode", "qrScan", "signQrRequest",
    ]

    enum Request {
        case open(modules: CitizenSDKModules)
        case empty(method: String, session: String, sequence: Int64)
        case account(method: String, session: String, sequence: Int64, accountID: Data)
        case balances(session: String, sequence: Int64, accountIDs: [Data])
        case blockNumber(session: String, sequence: Int64, number: UInt64)
        case resolveBlock(session: String, sequence: Int64, hash: Data, number: UInt64)
        case block(method: String, session: String, sequence: Int64, block: CitizenBlockRef)
        case storage(session: String, sequence: Int64, block: CitizenBlockRef, key: Data)
        case storageBatch(session: String, sequence: Int64, block: CitizenBlockRef, keys: [Data])
        case importState(session: String, sequence: Int64, state: CitizenChainState)
        case create(session: String, sequence: Int64, wordCount: UInt32)
        case addAccounts(session: String, sequence: Int64, indices: [UInt32])
        case rename(method: String, session: String, sequence: Int64, accountID: Data, name: String)
        case coldSS58(session: String, sequence: Int64, address: String, name: String)
        case reorder(session: String, sequence: Int64, expectedRevision: UInt64, accountIDs: [Data])
        case sign(session: String, sequence: Int64, accountID: Data, payload: Data)
        case beginSigning(session: String, sequence: Int64, intent: CitizenSigningIntent)
        case externalSignature(method: String, session: String, sequence: Int64,
                               signingSessionID: String, response: String)
        case cancelSigning(session: String, sequence: Int64, signingSessionID: String)
        case beginDefaultChange(session: String, sequence: Int64, expectedRevision: UInt64,
                                accountIDs: [Data], ttlSeconds: UInt64)
        case verify(accountID: Data, signature: Data, payload: Data)
        case prepareTransaction(session: String, sequence: Int64, source: Data, callData: Data)
        case cancelPreparedTransaction(session: String, sequence: Int64, preparationID: String)
        case transactionExecution(method: String, session: String, sequence: Int64,
                                  executionID: String, response: String?)
        case transactionHistory(method: String, session: String, sequence: Int64,
                                beforeExecutionID: String?, limit: UInt32)
        case qr(method: String, session: String, sequence: Int64, fields: [Any])

        var sessionID: String? {
            switch self {
            case .open, .verify: return nil
            case let .empty(_, value, _), let .account(_, value, _, _), let .create(value, _, _),
                 let .addAccounts(value, _, _), let .rename(_, value, _, _, _), let .coldSS58(value, _, _, _),
                 let .reorder(value, _, _, _), let .sign(value, _, _, _),
                 let .beginSigning(value, _, _), let .externalSignature(_, value, _, _, _),
                 let .cancelSigning(value, _, _), let .beginDefaultChange(value, _, _, _, _),
                 let .balances(value, _, _),
                 let .prepareTransaction(value, _, _, _), let .cancelPreparedTransaction(value, _, _),
                 let .transactionExecution(_, value, _, _, _),
                 let .transactionHistory(_, value, _, _, _),
                 let .qr(_, value, _, _), let .blockNumber(value, _, _),
                 let .resolveBlock(value, _, _, _), let .block(_, value, _, _),
                 let .storage(value, _, _, _), let .storageBatch(value, _, _, _),
                 let .importState(value, _, _): return value
            }
        }
        var sequence: Int64? {
            switch self {
            case .open, .verify: return nil
            case let .empty(_, _, value), let .account(_, _, value, _), let .create(_, value, _),
                 let .addAccounts(_, value, _), let .rename(_, _, value, _, _), let .coldSS58(_, value, _, _),
                 let .reorder(_, value, _, _), let .sign(_, value, _, _),
                 let .beginSigning(_, value, _), let .externalSignature(_, _, value, _, _),
                 let .cancelSigning(_, value, _), let .beginDefaultChange(_, value, _, _, _),
                 let .balances(_, value, _),
                 let .prepareTransaction(_, value, _, _), let .cancelPreparedTransaction(_, value, _),
                 let .transactionExecution(_, _, value, _, _),
                 let .transactionHistory(_, _, value, _, _),
                 let .qr(_, _, value, _), let .blockNumber(_, value, _),
                 let .resolveBlock(_, value, _, _), let .block(_, _, value, _),
                 let .storage(_, value, _, _), let .storageBatch(_, value, _, _),
                 let .importState(_, value, _): return value
            }
        }
        var method: String {
            switch self {
            case .open: return "open"
            case .verify: return "verifySignature"
            case let .empty(method, _, _), let .account(method, _, _, _),
                 let .block(method, _, _, _), let .rename(method, _, _, _, _),
                 let .externalSignature(method, _, _, _, _),
                 let .transactionExecution(method, _, _, _, _),
                 let .transactionHistory(method, _, _, _, _), let .qr(method, _, _, _): return method
            case .balances: return "getAccountBalances"
            case .blockNumber: return "getFinalizedBlockAt"
            case .resolveBlock: return "resolveFinalizedBlock"
            case .storage: return "getStorage"
            case .storageBatch: return "getStorageBatch"
            case .importState: return "importState"
            case .create: return "createWallet"
            case .addAccounts: return "addWalletAccounts"
            case .coldSS58: return "importColdAccountSs58"
            case .reorder: return "reorderWalletAccountsWithoutDefaultChange"
            case .sign: return "signWalletPayload"
            case .beginSigning: return "beginSigning"
            case .cancelSigning: return "cancelSigning"
            case .beginDefaultChange: return "beginDefaultAccountChange"
            case .prepareTransaction: return "prepareTransaction"
            case .cancelPreparedTransaction: return "cancelPreparedTransaction"
            }
        }
    }

    struct ContractFailure: Error {
        let code: CitizenSDKErrorCode
        let message: String
        let session: String?
        let sequence: Int64?
        let stage: CitizenSDKFailureStage

        init(code: CitizenSDKErrorCode, message: String, session: String? = nil,
             sequence: Int64? = nil, stage: CitizenSDKFailureStage? = nil) {
            self.code = code
            self.message = message
            self.session = session
            self.sequence = sequence
            self.stage = stage ?? .defaultStage(for: code)
        }
    }

    static func decode(method: String, arguments: Any?) throws -> Request {
        guard methods.contains(method) else { throw failure(.unsupported, "Unsupported method") }
        guard let tuple = arguments as? [Any?] else { throw failure(.invalidArgument, "Arguments must be a tuple") }
        guard !tuple.isEmpty, try integer(tuple[0], "protocolVersion") == version else {
            throw failure(.unsupported, "Unsupported protocol version")
        }
        if method == "open" {
            guard tuple.count == 2 else { throw failure(.invalidArgument, "Unexpected open arguments") }
            let modules = try integer(tuple[1], "modules")
            guard modules >= 0, modules <= Int64(UInt32.max) else {
                throw failure(.invalidArgument, "modules must be uint32")
            }
            return .open(modules: CitizenSDKModules(rawValue: UInt32(modules)))
        }
        if method == "verifySignature" {
            // 公开验签没有会话或序号；必须先拒绝旧会话形状，不能误读账户为会话。
            guard tuple.count == 4 else { throw failure(.invalidArgument, "Invalid verification tuple length") }
            let signature = try bytes(tuple[2], maximum: 64)
            guard signature.count == 64 else { throw failure(.invalidArgument, "signature must contain 64 bytes") }
            return .verify(accountID: try hash32(tuple[1]), signature: signature,
                           payload: try bytes(tuple[3], maximum: 16 * 1_024 * 1_024))
        }
        guard tuple.count >= 3 else { throw failure(.invalidArgument, "Truncated request") }
        let session = try string(tuple[1], "sessionId", 1...128)
        let sequence = try integer(tuple[2], "requestSequence")
        guard sequence > 0 else { throw failure(.invalidArgument, "requestSequence must be positive", session, sequence) }
        func length(_ expected: Int) throws {
            guard tuple.count == expected else { throw failure(.invalidArgument, "Invalid request tuple length", session, sequence) }
        }
        do {
            switch method {
            case "start", "stop", "close", "getCapabilities", "getFinalizedHead", "getSyncStatus",
                 "getBestHead", "exportState", "getGenesisHash", "getFeeSnapshot",
                 "getWalletProfile", "getWalletState", "importWallet", "deleteWallet", "reconcileWalletCleanup":
                try length(3); return .empty(method: method, session: session, sequence: sequence)
            case "getFinalizedBlockAt":
                try length(4)
                return .blockNumber(session: session, sequence: sequence,
                                    number: try uint64Decimal(tuple[3], "number"))
            case "resolveFinalizedBlock":
                try length(5)
                return .resolveBlock(session: session, sequence: sequence, hash: try hash32(tuple[3]),
                                     number: try uint64Decimal(tuple[4], "number"))
            case "getBlockHeader", "getBlockBody", "getRuntimeContext", "getSystemEvents":
                try length(4)
                let value = try blockRef(tuple[3])
                guard method != "getSystemEvents" || value.finality == .finalized else {
                    throw failure(.invalidArgument, "getSystemEvents requires a finalized block")
                }
                return .block(method: method, session: session, sequence: sequence, block: value)
            case "getStorage":
                try length(5)
                let key = try bytes(tuple[4], maximum: 4 * 1_024)
                guard !key.isEmpty else { throw failure(.invalidArgument, "storage key is empty") }
                return .storage(session: session, sequence: sequence, block: try blockRef(tuple[3]), key: key)
            case "getStorageBatch":
                try length(5)
                guard let raw = tuple[4] as? [Any?], (1...1_024).contains(raw.count) else {
                    throw failure(.invalidArgument, "storage batch must contain 1...1024 keys")
                }
                let keys = try raw.map { try bytes($0, maximum: 4 * 1_024) }
                guard keys.allSatisfy({ !$0.isEmpty }), keys.reduce(0, { $0 + $1.count }) <= 1_024 * 1_024 else {
                    throw failure(.invalidArgument, "storage batch keys are invalid")
                }
                return .storageBatch(session: session, sequence: sequence,
                                     block: try blockRef(tuple[3]), keys: keys)
            case "importState":
                try length(6)
                let format = try integer(tuple[3], "formatVersion"), finalized = try blockRef(tuple[4])
                let database = try bytes(tuple[5], maximum: 256 * 1_024)
                guard format > 0, format <= Int64(UInt32.max), finalized.finality == .finalized,
                      !database.isEmpty else { throw failure(.invalidArgument, "importState fields are invalid") }
                return .importState(session: session, sequence: sequence,
                    state: try CitizenChainState(formatVersion: UInt32(format), finalized: finalized,
                                                 database: database))
            case "getAccountBalance", "getAccountNonce", "setActiveWalletAccount", "deleteWalletAccount",
                 "deleteAccount", "viewAccountPrivateKey":
                try length(4); return .account(method: method, session: session, sequence: sequence,
                                               accountID: try hash32(tuple[3]))
            case "getAccountBalances":
                try length(4)
                guard let raw = tuple[3] as? [Any?], raw.count <= 1_990 else {
                    throw failure(.invalidArgument, "accountIds must contain 0...1990 accounts")
                }
                // 批量查询必须保留顺序和重复项，不能套用历史订阅的唯一性约束。
                return .balances(session: session, sequence: sequence, accountIDs: try raw.map(hash32))
            case "createWallet":
                try length(4)
                let words = try integer(tuple[3], "wordCount")
                guard words == 12 || words == 18 || words == 24 else { throw failure(.invalidArgument, "wordCount must be 12, 18 or 24") }
                return .create(session: session, sequence: sequence, wordCount: UInt32(words))
            case "addWalletAccounts":
                try length(4)
                guard let raw = tuple[3] as? [Any?], (1...1_989).contains(raw.count) else {
                    throw failure(.invalidArgument, "indices must contain 1...1989 values")
                }
                let values = try raw.map { try integer($0, "indices") }
                guard values.allSatisfy({ (1...1_989).contains($0) }), Set(values).count == values.count else {
                    throw failure(.invalidArgument, "indices must be unique values in 1...1989")
                }
                return .addAccounts(session: session, sequence: sequence, indices: values.map(UInt32.init))
            case "renameWalletAccount", "renameAccount", "importColdAccountId":
                try length(5)
                let name = try string(tuple[4], "name", 1...128)
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalized == name, (1...30).contains(name.unicodeScalars.count),
                      !name.unicodeScalars.contains(where: { $0.value <= 0x1f || (0x7f...0x9f).contains($0.value) }) else {
                    throw failure(.invalidArgument, "name must be trimmed 1...30 Unicode scalars without controls")
                }
                return .rename(method: method, session: session, sequence: sequence,
                               accountID: try hash32(tuple[3]), name: name)
            case "importColdAccountSs58":
                try length(5)
                let address = try string(tuple[3], "ss58Address", 1...64)
                let name = try string(tuple[4], "name", 1...128)
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalized == name, (1...30).contains(name.unicodeScalars.count),
                      !name.unicodeScalars.contains(where: { $0.value <= 0x1f || (0x7f...0x9f).contains($0.value) }) else {
                    throw failure(.invalidArgument, "name must be trimmed 1...30 Unicode scalars without controls")
                }
                return .coldSS58(session: session, sequence: sequence, address: address, name: name)
            case "reorderWalletAccountsWithoutDefaultChange":
                try length(5)
                let revision = try uint64Decimal(tuple[3], "expectedRevision")
                guard let raw = tuple[4] as? [Any?], (1...3_980).contains(raw.count) else {
                    throw failure(.invalidArgument, "accountIds must contain 1...3980 accounts")
                }
                return .reorder(session: session, sequence: sequence, expectedRevision: revision,
                                accountIDs: try raw.map(hash32))
            case "signWalletPayload":
                try length(5)
                return .sign(session: session, sequence: sequence, accountID: try hash32(tuple[3]),
                             payload: try bytes(tuple[4], maximum: 16 * 1_024 * 1_024))
            case "beginSigning":
                try length(10)
                let payload = try bytes(tuple[4], maximum: 16 * 1_024 * 1_024)
                guard !payload.isEmpty else { throw failure(.invalidArgument, "signing payload is empty") }
                let transformText = try string(tuple[5], "transform", 3...32)
                let transform: CitizenSigningTransform = switch transformText {
                case "raw": .raw
                case "substrateSigningPayload": .substrateSigningPayload
                case "blake2Domain": .blake2Domain
                default: throw failure(.invalidArgument, "Unknown signing transform")
                }
                let domain = try bytes(tuple[6], maximum: 32)
                guard (transform == .blake2Domain && !domain.isEmpty) ||
                      (transform != .blake2Domain && domain.isEmpty) else {
                    throw failure(.invalidArgument, "Invalid signing transform/domain")
                }
                let transportText = try string(tuple[7], "transport", 4...8)
                let transport: CitizenExternalSignerTransport? = switch transportText {
                case "none": nil
                case "qrV1": .qrV1
                default: throw failure(.invalidArgument, "Unknown external signer transport")
                }
                let action = try integer(tuple[8], "opaqueAction")
                let ttl = try integer(tuple[9], "ttlSeconds")
                guard action <= 65_535, (1...300).contains(ttl) else {
                    throw failure(.invalidArgument, "Invalid signing action or TTL")
                }
                return .beginSigning(
                    session: session, sequence: sequence,
                    intent: try CitizenSigningIntent(
                        accountID: hash32(tuple[3]), payload: payload, transform: transform,
                        domain: domain, externalSignerTransport: transport,
                        opaqueAction: UInt16(action), ttlSeconds: UInt64(ttl)))
            case "consumeExternalSignature", "consumeDefaultAccountChange":
                try length(5)
                return .externalSignature(
                    method: method, session: session, sequence: sequence,
                    signingSessionID: try string(tuple[3], "signingSessionID", 1...128),
                    response: try qrText(tuple[4], "response"))
            case "cancelSigning":
                try length(4)
                return .cancelSigning(
                    session: session, sequence: sequence,
                    signingSessionID: try string(tuple[3], "signingSessionID", 1...128))
            case "beginDefaultAccountChange":
                try length(6)
                let revision = try uint64Decimal(tuple[3], "expectedRevision")
                guard let raw = tuple[4] as? [Any?], (1...256).contains(raw.count) else {
                    throw failure(.invalidArgument, "accountIDs must contain 1...256 accounts")
                }
                let ttl = try integer(tuple[5], "ttlSeconds")
                guard (1...300).contains(ttl) else {
                    throw failure(.invalidArgument, "Invalid default-account TTL")
                }
                return .beginDefaultChange(
                    session: session, sequence: sequence, expectedRevision: revision,
                    accountIDs: try raw.map(hash32), ttlSeconds: UInt64(ttl))
            case "prepareTransaction":
                try length(5)
                let callData = try bytes(tuple[4], maximum: 1_024 * 1_024)
                guard !callData.isEmpty else {
                    throw failure(.invalidArgument, "callData must contain 1...1 MiB bytes")
                }
                return .prepareTransaction(
                    session: session, sequence: sequence,
                    source: try hash32(tuple[3]), callData: callData)
            case "cancelPreparedTransaction":
                try length(4)
                let preparationID = try string(tuple[3], "preparationID", 34...34)
                guard preparationID.range(
                    of: #"^0x[0-9a-f]{32}$"#,
                    options: .regularExpression
                ) != nil else {
                    throw failure(.invalidArgument, "preparationID is invalid")
                }
                return .cancelPreparedTransaction(
                    session: session, sequence: sequence, preparationID: preparationID)
            case "executePreparedTransaction", "cancelPreparedTransactionExecution":
                try length(4)
                let identifier = try string(tuple[3], "transaction identifier", 34...34)
                guard identifier.range(of: #"^0x[0-9a-f]{32}$"#, options: .regularExpression) != nil else {
                    throw failure(.invalidArgument, "transaction identifier is invalid")
                }
                return .transactionExecution(
                    method: method, session: session, sequence: sequence,
                    executionID: identifier, response: nil)
            case "consumePreparedTransactionQrResponse":
                try length(5)
                let identifier = try string(tuple[3], "executionID", 34...34)
                guard identifier.range(of: #"^0x[0-9a-f]{32}$"#, options: .regularExpression) != nil else {
                    throw failure(.invalidArgument, "executionID is invalid")
                }
                return .transactionExecution(
                    method: method, session: session, sequence: sequence,
                    executionID: identifier,
                    response: try string(tuple[4], "QR_V1 response", 1...65_536))
            case "getTransactionHistory":
                try length(5)
                let before = tuple[3] == nil ? nil
                    : try executionID(tuple[3], "beforeExecutionID")
                let limit = try integer(tuple[4], "limit")
                guard (1...100).contains(limit) else {
                    throw failure(.invalidArgument, "limit must be in 1...100")
                }
                return .transactionHistory(
                    method: method, session: session, sequence: sequence,
                    beforeExecutionID: before, limit: UInt32(limit))
            case "syncTransactionHistory":
                try length(3)
                return .transactionHistory(
                    method: method, session: session, sequence: sequence,
                    beforeExecutionID: nil, limit: 100)
            case "qrParse", "qrConsumeSignResponse", "signQrRequest":
                try length(4)
                return .qr(method: method, session: session, sequence: sequence,
                           fields: [try qrText(tuple[3], "QR text")])
            case "qrScan":
                try length(3)
                return .qr(method: method, session: session, sequence: sequence, fields: [])
            case "qrCreateSignRequest":
                try length(7)
                let action = try integer(tuple[3], "action")
                let ttl = try integer(tuple[6], "ttlSeconds")
                guard (1...65_535).contains(action), (1...300).contains(ttl) else {
                    throw failure(.invalidArgument, "Invalid QR action or TTL")
                }
                let payload = try bytes(tuple[5], maximum: 1_920)
                guard !payload.isEmpty else { throw failure(.invalidArgument, "QR payload is empty") }
                return .qr(method: method, session: session, sequence: sequence,
                           fields: [action, try hash32(tuple[4]), payload, ttl])
            case "qrCancelSignRequest":
                try length(4)
                return .qr(method: method, session: session, sequence: sequence,
                           fields: [try string(tuple[3], "requestID", 16...128)])
            case "qrEncodeAccountId":
                try length(4)
                return .qr(method: method, session: session, sequence: sequence,
                           fields: [try hash32(tuple[3])])
            case "qrDecodeLuminance":
                try length(7)
                let pixels = try bytes(tuple[3], maximum: 16 * 1_024 * 1_024)
                let width = try integer(tuple[4], "width")
                let height = try integer(tuple[5], "height")
                let stride = try integer(tuple[6], "rowStride")
                guard (1...4_096).contains(width), (1...4_096).contains(height), stride >= width,
                      stride <= 4_096, Int64(pixels.count) >= (height - 1) * stride + width else {
                    throw failure(.invalidArgument, "Invalid QR luminance dimensions")
                }
                return .qr(method: method, session: session, sequence: sequence,
                           fields: [pixels, width, height, stride])
            case "qrEncode":
                try length(5)
                let scale = try integer(tuple[4], "scale")
                guard (1...16).contains(scale) else { throw failure(.invalidArgument, "Invalid QR scale") }
                return .qr(method: method, session: session, sequence: sequence,
                           fields: [try qrText(tuple[3], "QR text"), scale])
            default: throw failure(.unsupported, "Unsupported method")
            }
        } catch let error as ContractFailure {
            throw ContractFailure(code: error.code, message: error.message,
                                  session: error.session ?? session, sequence: error.sequence ?? sequence,
                                  stage: error.stage)
        } catch let error as CitizenSDKError {
            throw ContractFailure(code: error.code, message: error.message, session: session,
                                  sequence: sequence, stage: error.stage)
        } catch {
            throw ContractFailure(code: .invalidArgument, message: "Invalid CitizenSDK request",
                                  session: session, sequence: sequence)
        }
    }

    static func response(session: String, sequence: Int64, value: [Any?]) -> [Any?] {
        [version, session, sequence, value]
    }
    static func event(session: String, sequence: Int64, type: String, payload: [Any?]) throws -> [Any?] {
        guard eventTypes.contains(type), sequence > 0,
              type != "historyChanged" || payload.isEmpty else {
            throw CitizenSDKError(.integrity, "Unsupported CitizenSDK event type")
        }
        return [version, session, sequence, type, payload]
    }
    static func error(_ code: CitizenSDKErrorCode, _ message: String,
                      session: String?, sequence: Int64?, method: String,
                      stage: CitizenSDKFailureStage? = nil) -> [Any?] {
        precondition(methods.contains(method))
        let failureStage = stage ?? .defaultStage(for: code)
        return [version, session, sequence, Int64(code.rawValue),
                Int64(failureStage.rawValue), method, message]
    }

    static func errorName(_ code: CitizenSDKErrorCode) -> String {
        switch code {
        case .ok: return "ok"
        case .invalidArgument: return "invalidArgument"
        case .invalidHandle: return "invalidHandle"
        case .invalidState: return "invalidState"
        case .unsupported: return "unsupported"
        case .unavailable: return "unavailable"
        case .notReady: return "notReady"
        case .notFound: return "notFound"
        case .conflict: return "conflict"
        case .integrity: return "integrity"
        case .authenticationCancelled: return "authenticationCancelled"
        case .authenticationRequired: return "authenticationRequired"
        case .keyInvalidated: return "keyInvalidated"
        case .permissionDenied: return "permissionDenied"
        case .storage: return "storage"
        case .network: return "network"
        case .decode: return "decode"
        case .timeout: return "timeout"
        case .busy: return "busy"
        case .queueFull: return "queueFull"
        case .internalFailure: return "internal"
        case .panic: return "panic"
        case .cancelled: return "cancelled"
        @unknown default: return "unknown"
        }
    }

    static func lifecycle(_ value: CitizenSDKLifecycle) -> String {
        switch value {
        case .created: return "created"
        case .importingState: return "importingState"
        case .starting: return "starting"
        case .running: return "running"
        case .startFailed: return "startFailed"
        case .stopped: return "stopped"
        case .disposed: return "disposed"
        @unknown default: return "unknown"
        }
    }

    static func block(_ value: CitizenBlockRef) -> [Any?] {
        [hex(value.hash), String(value.number), value.finality == .best ? "best" : "finalized"]
    }
    static func syncStatus(_ value: CitizenChainSyncStatus) -> [Any?] {
        [String(value.peerCount), value.isSyncing, value.isUsable, block(value.best), block(value.finalized)]
    }
    static func blockHeader(_ value: CitizenBlockHeader) -> [Any?] {
        [block(value.block), hex(value.parentHash), hex(value.stateRoot), hex(value.extrinsicsRoot),
         FlutterStandardTypedData(bytes: value.digest)]
    }
    static func blockBody(_ value: CitizenBlockBody) -> [Any?] {
        [block(value.block), value.extrinsics.map { FlutterStandardTypedData(bytes: $0) }]
    }
    static func runtimeContext(_ value: CitizenRuntimeContext) -> [Any?] {
        [block(value.block), Int64(value.specVersion), Int64(value.transactionVersion),
         FlutterStandardTypedData(bytes: value.metadata)]
    }
    static func chainState(_ value: CitizenChainState) -> [Any?] {
        [Int64(value.formatVersion), block(value.finalized), FlutterStandardTypedData(bytes: value.database)]
    }
    static func optionalBytes(_ value: Data?) -> Any? {
        value.map { FlutterStandardTypedData(bytes: $0) }
    }
    static func capabilities(_ value: CitizenSDKCapabilities) -> [Any?] {
        [String(value.revision), value.statuses.map(capability)]
    }
    static func balance(_ value: CitizenAccountBalance) -> [Any?] {
        [hex(value.accountID), block(value.block), value.freeFen.decimal, value.reservedFen.decimal, value.totalFen.decimal]
    }
    static func nonce(_ value: CitizenAccountNonce) -> [Any?] {
        [hex(value.accountID), block(value.bestBlock), String(value.nonce)]
    }
    static func fee(_ value: CitizenFeeSnapshot) -> [Any?] {
        [block(value.bestBlock), Int64(value.feeRateParts), value.minimumFeeFen.decimal, value.existentialDepositFen.decimal]
    }
    static func profile(_ value: CitizenWalletProfile?) -> [Any?]? {
        value.map { profile in
            [Int64(profile.walletIndex), profile.origin == .created ? "created" : "imported",
             String(profile.createdAtMillis), hex(profile.masterAccountID), hex(profile.activeAccountID),
             profile.accounts.map(account)]
        }
    }
    static func walletState(_ value: CitizenWalletState) -> [Any?] {
        [String(value.revision), profile(value.hotProfile), value.accounts.map(stateAccount)]
    }
    static func signature(_ value: CitizenSignature) -> FlutterStandardTypedData { FlutterStandardTypedData(bytes: value.bytes) }
    static func signingOutcome(_ value: CitizenSigningOutcome) -> [Any?] {
        switch value {
        case let .completed(accountID, payloadHash, signatureValue):
            return ["completed", hex(accountID), hex(payloadHash), signature(signatureValue), nil, nil, nil]
        case let .externalPending(accountID, payloadHash, _, expiresAt, sessionID, request):
            return ["externalPending", hex(accountID), hex(payloadHash), nil,
                    String(expiresAt), sessionID, request]
        }
    }
    static func defaultAccountChangeOutcome(_ value: CitizenDefaultAccountChangeOutcome) -> [Any?] {
        switch value {
        case let .completed(current, payloadHash, revision):
            return ["completed", hex(current), hex(payloadHash), String(revision), nil, nil, nil]
        case let .externalPending(current, payloadHash, _, expiresAt, sessionID, request):
            return ["externalPending", hex(current), hex(payloadHash), nil,
                    String(expiresAt), sessionID, request]
        }
    }
    static func preparedTransaction(_ value: CitizenPreparedTransaction) -> [Any?] {
        [value.preparationID, hex(value.sourceAccountID), hex(value.callDataHash),
         block(value.bestBlock), Int64(value.runtimeSpecNumber),
         Int64(value.transactionFormatNumber), String(value.nonce)]
    }
    static func transactionExecution(_ value: CitizenTransactionExecution) throws -> [Any?] {
        switch value {
        case let .externalSigningPending(pending):
            return [1, pending.executionID, hex(pending.sourceAccountID), hex(pending.callDataHash),
                    nil, String(pending.expiresAt), pending.qrRequest, nil, nil, nil]
        case let .completed(completed):
            let status: Int
            switch completed.resolution {
            case .finalizedSuccess: status = 2
            case .finalizedFailed: status = 3
            case .poolRejected: status = 4
            }
            return [status, completed.executionID, hex(completed.sourceAccountID),
                    hex(completed.callDataHash), hex(completed.transactionHash), nil, nil,
                    try completed.execution.map(execution), completed.poolRejectionReason,
                    completed.replacementHash.map(hex)]
        }
    }
    static func transactionHistoryPage(_ value: CitizenTransactionHistoryPage) throws -> [Any?] {
        [String(value.revision), try value.records.map(transactionHistoryRecord),
         value.nextBeforeExecutionID]
    }

    private static func capability(_ value: CitizenCapabilityStatus) -> [Any?] {
        [capabilityName(value.name), value.supported, value.available, value.enabled, value.ready, capabilityReason(value.reason)]
    }
    private static func account(_ value: CitizenWalletAccount) -> [Any?] {
        [Int64(value.index), hex(value.accountID), value.ss58Address, value.name ?? "", String(value.createdAtMillis), value.active]
    }
    private static func stateAccount(_ value: CitizenWalletStateAccount) -> [Any?] {
        [value.signMode == .hot ? "hot" : "cold", Int64(value.walletIndex),
         value.accountIndex.map { Int64($0) }, hex(value.accountID), value.ss58Address, value.name,
         String(value.createdAtMillis), value.isDefault]
    }
    private static func execution(_ value: CitizenExecution) throws -> [Any?] {
        guard value.status != .unverified, let blockValue = value.block, let extrinsic = value.extrinsicIndex else {
            throw CitizenSDKError(.integrity, "Flutter tuple requires a verified finalized execution")
        }
        return [value.status == .success ? "success" : "failed", block(blockValue),
         Int64(extrinsic), value.status == .failed ? Int64(value.reasonOrDispatchVariant) : nil,
         value.palletIndex.map { Int64($0) }, value.errorIndex.map { Int64($0) }]
    }
    private static func transactionHistoryRecord(_ value: CitizenTransactionHistoryRecord) throws -> [Any?] {
        [value.executionID, hex(value.sourceAccountID), hex(value.callDataHash),
         hex(value.transactionHash), transactionHistoryStatus(value.status),
         value.block.map(block), try value.execution.map(execution), value.replacementHash.map(hex),
         String(value.createdAtMillis), String(value.updatedAtMillis), value.poolRejectionReason]
    }

    private static func hash32(_ raw: Any?) throws -> Data {
        guard let text = raw as? String, text.count == 66, text.hasPrefix("0x"),
              text.dropFirst(2).unicodeScalars.allSatisfy({
                  ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
              }) else {
            throw failure(.invalidArgument, "Invalid 32-byte hex")
        }
        var output = Data(capacity: 32)
        var index = text.index(text.startIndex, offsetBy: 2)
        for _ in 0..<32 {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { throw failure(.invalidArgument, "Invalid 32-byte hex") }
            output.append(byte); index = next
        }
        return output
    }
    private static func executionID(_ raw: Any?, _ label: String) throws -> String {
        guard let value = raw as? String,
              value.range(of: #"^0x[0-9a-f]{32}$"#, options: .regularExpression) != nil else {
            throw failure(.invalidArgument, "\(label) must be a 16-byte lowercase hex identifier")
        }
        return value
    }
    private static func blockRef(_ raw: Any?) throws -> CitizenBlockRef {
        guard let tuple = raw as? [Any?], tuple.count == 3 else {
            throw failure(.invalidArgument, "Invalid block tuple")
        }
        let finality: CitizenFinality
        switch tuple[2] as? String {
        case "best": finality = .best
        case "finalized": finality = .finalized
        default: throw failure(.invalidArgument, "Invalid block finality")
        }
        return try CitizenBlockRef(hash: hash32(tuple[0]), number: uint64Decimal(tuple[1], "block number"),
                                   finality: finality)
    }
    private static func bytes(_ raw: Any?, maximum: Int) throws -> Data {
        guard let value = raw as? FlutterStandardTypedData,
              // FlutterStandardDataTypeUInt8 is the first NS_ENUM case.  Compare
              // the raw value because Flutter SDK releases have exposed
              // different Swift spellings for this Objective-C enum member.
              value.type.rawValue == 0,
              value.data.count <= maximum else {
            throw failure(.invalidArgument, "Invalid byte tuple")
        }
        return value.data
    }
    private static func string(_ raw: Any?, _ label: String, _ range: ClosedRange<Int>) throws -> String {
        guard let value = raw as? String, range.contains(value.utf16.count) else {
            throw failure(.invalidArgument, "Invalid \(label)")
        }
        return value
    }
    private static func utf8Text(_ raw: Any?, _ label: String,
                                 _ range: ClosedRange<Int>) throws -> String {
        let value = try string(raw, label, 0...max(range.upperBound, 1))
        guard range.contains(value.utf8.count) else { throw failure(.invalidArgument, "Invalid \(label) UTF-8 length") }
        return value
    }
    private static func qrText(_ raw: Any?, _ label: String) throws -> String {
        try utf8Text(raw, label, 1...2_331)
    }
    private static func integer(_ raw: Any?, _ label: String) throws -> Int64 {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number), number.int64Value >= 0 else {
            throw failure(.invalidArgument, "Invalid \(label)")
        }
        return number.int64Value
    }
    private static func uint64Decimal(_ raw: Any?, _ label: String) throws -> UInt64 {
        guard let value = raw as? String, !value.isEmpty, value.count <= 20,
              value == "0" || (value.first != "0" && value.allSatisfy(\.isNumber)),
              let parsed = UInt64(value) else {
            throw failure(.invalidArgument, "Invalid \(label)")
        }
        return parsed
    }
    private static func failure(_ code: CitizenSDKErrorCode, _ message: String,
                                _ session: String? = nil, _ sequence: Int64? = nil) -> ContractFailure {
        ContractFailure(code: code, message: message, session: session, sequence: sequence)
    }
    static func hex(_ value: Data) -> String { "0x" + value.map { String(format: "%02x", $0) }.joined() }
    private static func capabilityName(_ value: CitizenCapabilityName) -> String {
        switch value {
        case .chainRead: return "chainRead"; case .transactionBuild: return "transactionBuild"
        case .transactionSubmit: return "transactionSubmit"; case .transactionVerify: return "transactionVerify"
        case .walletProfile: return "walletProfile"; case .localSigning: return "localSigning"
        case .hardwareVault: return "hardwareVault"; case .userAuthentication: return "userAuthentication"
        case .history: return "history"; case .backgroundSync: return "backgroundSync"
        @unknown default: return "unknown"
        }
    }
    private static func capabilityReason(_ value: CitizenCapabilityReason) -> String {
        switch value {
        case .none: return "none"; case .buildUnsupported: return "buildUnsupported"
        case .deviceUnavailable: return "deviceUnavailable"; case .hostDisabled: return "hostDisabled"
        case .engineNotRunning: return "engineNotRunning"; case .dependencyNotReady: return "dependencyNotReady"
        case .userAuthenticationRequired: return "userAuthenticationRequired"; case .vaultLocked: return "vaultLocked"
        case .chainStarting: return "chainStarting"; case .chainUnsynced: return "chainUnsynced"
        case .storageUnavailable: return "storageUnavailable"
        @unknown default: return "unknown"
        }
    }
    private static func transactionHistoryStatus(_ value: CitizenTransactionHistoryStatus) -> String {
        switch value {
        case .pending: return "pending"
        case .inBlock: return "inBlock"
        case .poolRejected: return "poolRejected"
        case .finalizedSuccess: return "finalizedSuccess"
        case .finalizedFailed: return "finalizedFailed"
        @unknown default: return "unknown"
        }
    }
}
