import Foundation

/// 同一 Rust 核心的模块集合；这里只投影位值，组合合法性由核心统一校验。
public struct CitizenSDKModules: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let wallet = Self(rawValue: 1)
    public static let signing = Self(rawValue: 2)
    public static let chain = Self(rawValue: 4)
    public static let transactions = Self(rawValue: 8)
    public static let history = Self(rawValue: 16)
    public static let qr = Self(rawValue: 32)
    public static let full: Self = [.wallet, .signing, .chain, .transactions, .history, .qr]

    internal var usesSecrets: Bool { !intersection([.wallet, .signing]).isEmpty }
}

public enum CitizenSDKLifecycle: UInt32, Sendable {
    case created = 1
    case importingState = 2
    case starting = 3
    case running = 4
    case startFailed = 5
    case stopped = 6
    case disposed = 7
}

public enum CitizenFinality: UInt32, Sendable { case best = 1, finalized = 2 }
public enum CitizenWalletOrigin: UInt32, Sendable { case created = 1, imported = 2 }
public enum CitizenTransferResolution: UInt32, Sendable {
    case finalizedSuccess = 1, finalizedFailed = 2, poolRejected = 3
}
public enum CitizenHistoryStatus: UInt32, Sendable {
    case pending = 1, inBlock = 2, poolRejected = 3, finalizedSuccess = 4, finalizedFailed = 5
}
public enum CitizenTransferDirection: UInt32, Sendable { case outgoing = 1, incoming = 2 }
public enum CitizenExecutionStatus: UInt32, Sendable { case success = 1, failed = 2, unverified = 3 }

public enum CitizenCapabilityName: UInt32, CaseIterable, Sendable {
    case chainRead = 1
    case transactionBuild = 2
    case transactionSubmit = 3
    case transactionVerify = 4
    case walletProfile = 5
    case localSigning = 6
    case hardwareVault = 7
    case userAuthentication = 8
    case history = 9
    case backgroundSync = 10
}

public enum CitizenCapabilityReason: UInt32, Sendable {
    case none = 0
    case buildUnsupported = 1
    case deviceUnavailable = 2
    case hostDisabled = 3
    case engineNotRunning = 4
    case dependencyNotReady = 5
    case userAuthenticationRequired = 6
    case vaultLocked = 7
    case chainStarting = 8
    case chainUnsynced = 9
    case storageUnavailable = 10
}

/// Exact unsigned 128-bit integer represented canonically in decimal.
public struct CitizenU128: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let decimal: String
    internal let low: UInt64
    internal let high: UInt64

    public init(_ decimal: String) throws {
        try CitizenSDKChecks.require(!decimal.isEmpty && decimal.count <= 39, "u128 is out of range")
        try CitizenSDKChecks.require(decimal == "0" || (decimal.first != "0" && decimal.allSatisfy(\.isNumber)),
                                     "u128 must be canonical unsigned decimal")
        var high: UInt64 = 0
        var low: UInt64 = 0
        for scalar in decimal.unicodeScalars {
            guard scalar.value >= 48 && scalar.value <= 57 else {
                throw CitizenSDKError(.invalidArgument, "u128 must be canonical unsigned decimal")
            }
            let digit = UInt64(scalar.value - 48)
            let lowProduct = low.multipliedFullWidth(by: 10)
            let highProduct = high.multipliedReportingOverflow(by: 10)
            let highSum = highProduct.partialValue.addingReportingOverflow(lowProduct.high)
            let lowSum = lowProduct.low.addingReportingOverflow(digit)
            let highCarry = highSum.partialValue.addingReportingOverflow(lowSum.overflow ? 1 : 0)
            guard !highProduct.overflow && !highSum.overflow && !highCarry.overflow else {
                throw CitizenSDKError(.invalidArgument, "u128 is out of range")
            }
            high = highCarry.partialValue
            low = lowSum.partialValue
        }
        self.high = high
        self.low = low
        self.decimal = decimal
    }

    internal init(low: UInt64, high: UInt64) {
        self.low = low
        self.high = high
        self.decimal = CitizenU128.decimal(low: low, high: high)
    }

    public var description: String { decimal }

    private static func decimal(low: UInt64, high: UInt64) -> String {
        if high == 0 { return String(low) }
        var highPart = high
        var lowPart = low
        var digits: [UInt8] = []
        repeat {
            let highDivision = highPart.quotientAndRemainder(dividingBy: 10)
            let lowDivision = UInt64(10).dividingFullWidth((high: highDivision.remainder, low: lowPart))
            digits.append(UInt8(lowDivision.remainder) + 48)
            highPart = highDivision.quotient
            lowPart = lowDivision.quotient
        } while highPart != 0 || lowPart != 0
        return String(bytes: digits.reversed(), encoding: .ascii)!
    }
}

public struct CitizenBlockRef: Equatable, Sendable {
    public let hash: Data
    public let number: UInt64
    public let finality: CitizenFinality

    public init(hash: Data, number: UInt64, finality: CitizenFinality) throws {
        try CitizenSDKChecks.require(hash.count == 32, "block hash must contain exactly 32 bytes")
        self.hash = hash
        self.number = number
        self.finality = finality
    }
}

public struct CitizenCapabilityStatus: Equatable, Sendable {
    public let name: CitizenCapabilityName
    public let reason: CitizenCapabilityReason
    public let supported: Bool
    public let available: Bool
    public let enabled: Bool
    public let ready: Bool
}

public struct CitizenSDKCapabilities: Equatable, Sendable {
    public let revision: UInt64
    public let statuses: [CitizenCapabilityStatus]
}

public struct CitizenAccountBalance: Equatable, Sendable {
    public let block: CitizenBlockRef
    public let accountID: Data
    public let freeFen: CitizenU128
    public let reservedFen: CitizenU128
    public let totalFen: CitizenU128
}

public struct CitizenAccountNonce: Equatable, Sendable {
    public let bestBlock: CitizenBlockRef
    public let accountID: Data
    public let nonce: UInt64
}

public struct CitizenFeeSnapshot: Equatable, Sendable {
    public let bestBlock: CitizenBlockRef
    public let feeRateParts: UInt32
    public let minimumFeeFen: CitizenU128
    public let existentialDepositFen: CitizenU128
}

public struct CitizenWalletAccount: Equatable, Sendable {
    public let index: UInt32
    public let accountID: Data
    public let ss58Address: String
    public let name: String?
    public let createdAtMillis: UInt64
    public let active: Bool
}

public struct CitizenWalletProfile: Equatable, Sendable {
    public let origin: CitizenWalletOrigin
    public let walletIndex: UInt32
    public let createdAtMillis: UInt64
    public let masterAccountID: Data
    public let activeAccountID: Data
    public let accounts: [CitizenWalletAccount]
}

public struct CitizenSignature: Equatable, Sendable {
    public let bytes: Data
    internal init(_ bytes: Data) throws {
        try CitizenSDKChecks.require(bytes.count == 64, "sr25519 signature must contain exactly 64 bytes")
        self.bytes = bytes
    }
}

public struct CitizenExecution: Equatable, Sendable {
    public let status: CitizenExecutionStatus
    public let reasonOrDispatchVariant: UInt32
    public let block: CitizenBlockRef?
    public let extrinsicIndex: UInt32?
    public let palletIndex: UInt8?
    public let errorIndex: UInt8?
}

public struct CitizenWalletTransfer: Equatable, Sendable {
    public let transactionHash: Data
    public let resolution: CitizenTransferResolution
    public let execution: CitizenExecution?
    public let poolRejectionReason: String?
}

public struct CitizenHistoryCursor: Equatable, Sendable {
    public let accountID: Data
    public let trackingStartBlock: CitizenBlockRef
    public let lastSyncedBlock: CitizenBlockRef
}

public struct CitizenHistoryRecord: Equatable, Sendable {
    public let accountID: Data
    public let transactionHash: Data
    public let nonce: UInt64
    public let destinationAccountID: Data
    public let amountFen: CitizenU128
    public let status: CitizenHistoryStatus
    public let block: CitizenBlockRef?
    public let execution: CitizenExecution?
    public let createdAtMillis: UInt64
    public let updatedAtMillis: UInt64
    public let remark: Data
    public let poolRejectionReason: String?
}

public struct CitizenFinalizedTransfer: Equatable, Sendable {
    public let trackedAccountID: Data
    public let fromAccountID: Data
    public let toAccountID: Data
    public let amountFen: CitizenU128
    public let block: CitizenBlockRef
    public let eventRecordIndex: UInt32
    public let extrinsicIndex: UInt32?
    public let direction: CitizenTransferDirection
    public let sourcePallet: String
    public let remarkDisplay: String
    public let remarkBytes: Data
}

public struct CitizenTransactionHistory: Equatable, Sendable {
    public let revision: UInt64
    public let cursors: [CitizenHistoryCursor]
    public let records: [CitizenHistoryRecord]
    public let transfers: [CitizenFinalizedTransfer]
}
