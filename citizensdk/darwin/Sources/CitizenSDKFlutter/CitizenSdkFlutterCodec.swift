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
    static let eventTypes: Set<String> = ["lifecycleChanged", "capabilitiesChanged", "transferProgress", "historyChanged"]
    static let methods: Set<String> = [
        "open", "start", "stop", "close", "getCapabilities", "getFinalizedHead",
        "getGenesisHash", "getAccountBalance", "getAccountBalances", "getAccountNonce", "getFeeSnapshot", "getWalletProfile", "viewAccountPrivateKey",
        "createWallet", "importWallet", "addWalletAccounts", "setActiveWalletAccount",
        "renameWalletAccount", "deleteWalletAccount", "deleteWallet", "reconcileWalletCleanup",
        "signWalletPayload", "verifySignature", "transferWithRemark", "initializeFinalizedHistory", "syncFinalizedHistory",
        "qrParse", "qrCreateSignRequest", "qrConsumeSignResponse", "qrCancelSignRequest", "qrEncodeAccountId",
        "qrEncodeUserTransfer", "qrDecodeLuminance", "qrEncode", "qrScan", "signQrRequest",
    ]

    enum Request {
        case open(modules: CitizenSDKModules)
        case empty(method: String, session: String, sequence: Int64)
        case account(method: String, session: String, sequence: Int64, accountID: Data)
        case balances(session: String, sequence: Int64, accountIDs: [Data])
        case create(session: String, sequence: Int64, wordCount: UInt32)
        case addAccounts(session: String, sequence: Int64, indices: [UInt32])
        case rename(session: String, sequence: Int64, accountID: Data, name: String)
        case sign(session: String, sequence: Int64, accountID: Data, payload: Data)
        case verify(accountID: Data, signature: Data, payload: Data)
        case transfer(session: String, sequence: Int64, source: Data, destination: Data,
                      amount: CitizenU128, remark: Data)
        case history(method: String, session: String, sequence: Int64, accountIDs: [Data])
        case qr(method: String, session: String, sequence: Int64, fields: [Any])

        var sessionID: String? {
            switch self {
            case .open, .verify: return nil
            case let .empty(_, value, _), let .account(_, value, _, _), let .create(value, _, _),
                 let .addAccounts(value, _, _), let .rename(value, _, _, _), let .sign(value, _, _, _),
                 let .balances(value, _, _), let .transfer(value, _, _, _, _, _), let .history(_, value, _, _),
                 let .qr(_, value, _, _): return value
            }
        }
        var sequence: Int64? {
            switch self {
            case .open, .verify: return nil
            case let .empty(_, _, value), let .account(_, _, value, _), let .create(_, value, _),
                 let .addAccounts(_, value, _), let .rename(_, value, _, _), let .sign(_, value, _, _),
                 let .balances(_, value, _), let .transfer(_, value, _, _, _, _), let .history(_, _, value, _),
                 let .qr(_, _, value, _): return value
            }
        }
    }

    struct ContractFailure: Error {
        let code: CitizenSDKErrorCode
        let message: String
        let session: String?
        let sequence: Int64?
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
            case "start", "stop", "close", "getCapabilities", "getFinalizedHead", "getGenesisHash", "getFeeSnapshot",
                 "getWalletProfile", "importWallet", "deleteWallet", "reconcileWalletCleanup":
                try length(3); return .empty(method: method, session: session, sequence: sequence)
            case "getAccountBalance", "getAccountNonce", "setActiveWalletAccount", "deleteWalletAccount", "viewAccountPrivateKey":
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
            case "renameWalletAccount":
                try length(5)
                let name = try string(tuple[4], "name", 1...128)
                let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard normalized == name, (1...30).contains(name.unicodeScalars.count),
                      !name.unicodeScalars.contains(where: { $0.value <= 0x1f || (0x7f...0x9f).contains($0.value) }) else {
                    throw failure(.invalidArgument, "name must be trimmed 1...30 Unicode scalars without controls")
                }
                return .rename(session: session, sequence: sequence, accountID: try hash32(tuple[3]), name: name)
            case "signWalletPayload":
                try length(5)
                return .sign(session: session, sequence: sequence, accountID: try hash32(tuple[3]),
                             payload: try bytes(tuple[4], maximum: 16 * 1_024 * 1_024))
            case "transferWithRemark":
                try length(7)
                let amount = try CitizenU128(try string(tuple[5], "amountFen", 1...39))
                guard amount.decimal != "0" else { throw failure(.invalidArgument, "amountFen must be positive") }
                let remarkString = try string(tuple[6], "remark", 0...99)
                let remark = Data(remarkString.utf8)
                guard remark.count <= 99 else { throw failure(.invalidArgument, "remark UTF-8 length exceeds 99 bytes") }
                return .transfer(session: session, sequence: sequence, source: try hash32(tuple[3]),
                                 destination: try hash32(tuple[4]), amount: amount, remark: remark)
            case "initializeFinalizedHistory", "syncFinalizedHistory":
                try length(4)
                guard let raw = tuple[3] as? [Any?], (1...1_990).contains(raw.count) else {
                    throw failure(.invalidArgument, "accountIds must contain 1...1990 accounts")
                }
                let values = try raw.map(hash32)
                guard Set(values).count == values.count else { throw failure(.invalidArgument, "accountIds must be unique") }
                return .history(method: method, session: session, sequence: sequence, accountIDs: values)
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
            case "qrEncodeUserTransfer":
                try length(10)
                let expires = try integer(tuple[4], "expiresAt")
                guard expires > 0 else { throw failure(.invalidArgument, "expiresAt must be positive") }
                return .qr(method: method, session: session, sequence: sequence, fields: [
                    try string(tuple[3], "requestID", 16...128), expires, try hash32(tuple[5]),
                    try utf8Text(tuple[6], "amount", 1...64), try utf8Text(tuple[7], "symbol", 1...16),
                    try utf8Text(tuple[8], "memo", 0...256), try utf8Text(tuple[9], "bankCIDNumber", 1...32),
                ])
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
                                  session: error.session ?? session, sequence: error.sequence ?? sequence)
        } catch let error as CitizenSDKError {
            throw ContractFailure(code: error.code, message: error.message, session: session, sequence: sequence)
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
                      session: String?, sequence: Int64?) -> [Any?] {
        [version, session, sequence, Int64(code.rawValue), message]
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
    static func signature(_ value: CitizenSignature) -> FlutterStandardTypedData { FlutterStandardTypedData(bytes: value.bytes) }
    static func transfer(_ value: CitizenWalletTransfer) throws -> [Any?] {
        [hex(value.transactionHash), transferResolution(value.resolution), try value.execution.map(execution), value.poolRejectionReason]
    }
    static func history(_ value: CitizenTransactionHistory) throws -> [Any?] {
        [String(value.revision), value.cursors.map(cursor), try value.records.map(record), value.transfers.map(finalizedTransfer)]
    }

    private static func capability(_ value: CitizenCapabilityStatus) -> [Any?] {
        [capabilityName(value.name), value.supported, value.available, value.enabled, value.ready, capabilityReason(value.reason)]
    }
    private static func account(_ value: CitizenWalletAccount) -> [Any?] {
        [Int64(value.index), hex(value.accountID), value.ss58Address, value.name ?? "", String(value.createdAtMillis), value.active]
    }
    private static func execution(_ value: CitizenExecution) throws -> [Any?] {
        guard value.status != .unverified, let blockValue = value.block, let extrinsic = value.extrinsicIndex else {
            throw CitizenSDKError(.integrity, "Flutter tuple requires a verified finalized execution")
        }
        return [value.status == .success ? "success" : "failed", block(blockValue),
         Int64(extrinsic), value.status == .failed ? Int64(value.reasonOrDispatchVariant) : nil,
         value.palletIndex.map { Int64($0) }, value.errorIndex.map { Int64($0) }]
    }
    private static func cursor(_ value: CitizenHistoryCursor) -> [Any?] {
        [hex(value.accountID), block(value.trackingStartBlock), block(value.lastSyncedBlock)]
    }
    private static func record(_ value: CitizenHistoryRecord) throws -> [Any?] {
        guard let remark = String(data: value.remark, encoding: .utf8) else {
            throw CitizenSDKError(.integrity, "history remark is not valid UTF-8")
        }
        return [hex(value.accountID), hex(value.transactionHash), String(value.nonce), hex(value.destinationAccountID),
         value.amountFen.decimal, historyStatus(value.status), value.block.map(block), try value.execution.map(execution),
         String(value.createdAtMillis), String(value.updatedAtMillis), remark,
         value.poolRejectionReason]
    }
    private static func finalizedTransfer(_ value: CitizenFinalizedTransfer) -> [Any?] {
        [hex(value.trackedAccountID), hex(value.fromAccountID), hex(value.toAccountID), value.amountFen.decimal,
         block(value.block), Int64(value.eventRecordIndex), value.extrinsicIndex.map { Int64($0) },
         value.direction == .outgoing ? "outgoing" : "incoming", value.sourcePallet, value.remarkDisplay,
         FlutterStandardTypedData(bytes: value.remarkBytes)]
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
    private static func failure(_ code: CitizenSDKErrorCode, _ message: String,
                                _ session: String? = nil, _ sequence: Int64? = nil) -> ContractFailure {
        ContractFailure(code: code, message: message, session: session, sequence: sequence)
    }
    private static func hex(_ value: Data) -> String { "0x" + value.map { String(format: "%02x", $0) }.joined() }
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
    private static func transferResolution(_ value: CitizenTransferResolution) -> String {
        switch value {
        case .finalizedSuccess: return "finalizedSuccess"
        case .finalizedFailed: return "finalizedFailed"
        case .poolRejected: return "poolRejected"
        @unknown default: return "unknown"
        }
    }
    private static func historyStatus(_ value: CitizenHistoryStatus) -> String {
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
