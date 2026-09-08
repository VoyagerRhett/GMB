import Foundation

internal enum CitizenSDKInputLimits {
    static let maximumHistoryAccounts = 1_990
    static let maximumBalanceAccounts = 1_990
    static let maximumSigningPayloadBytes = 16 * 1_024 * 1_024
    static let maximumWalletSecretBytes = 1_024
    static let maximumAdditionalAccounts = 1_989
    static let maximumTransferRemarkBytes = 99
    static let maximumAccountNameUTF16Units = 128

    static func accountID(_ value: Data, label: String = "accountID") throws -> Data {
        try CitizenSDKChecks.require(value.count == 32, "\(label) must contain exactly 32 bytes")
        return value
    }

    static func accountIDs(_ values: [Data]) throws -> [Data] {
        try CitizenSDKChecks.require((1...maximumHistoryAccounts).contains(values.count),
                                     "accountIDs must contain 1...\(maximumHistoryAccounts) entries")
        let checked = try values.map { try accountID($0) }
        try CitizenSDKChecks.require(Set(checked).count == checked.count, "accountIDs must be unique")
        return checked
    }

    /// 批量余额不是历史订阅：允许空列表与重复账户，不排序或去重。
    static func balanceAccountIDs(_ values: [Data]) throws -> [Data] {
        try CitizenSDKChecks.require(values.count <= maximumBalanceAccounts,
                                     "accountIDs must contain 0...\(maximumBalanceAccounts) entries")
        return try values.map { try accountID($0) }
    }

    static func signingPayload(_ value: Data) throws -> Data {
        try CitizenSDKChecks.require(value.count <= maximumSigningPayloadBytes,
                                     "sign payload exceeds \(maximumSigningPayloadBytes) bytes")
        return value
    }

    static func transferRemark(_ value: Data) throws -> Data {
        try CitizenSDKChecks.require(value.count <= maximumTransferRemarkBytes,
                                     "transfer remark exceeds \(maximumTransferRemarkBytes) bytes")
        return value
    }

    static func accountName(_ value: String) throws -> String {
        try CitizenSDKChecks.require((1...maximumAccountNameUTF16Units).contains(value.utf16.count),
                                     "wallet account name input is too long")
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try CitizenSDKChecks.require(normalized == value && (1...30).contains(normalized.unicodeScalars.count),
                                     "wallet account name must contain 1...30 trimmed Unicode scalars")
        try CitizenSDKChecks.require(!normalized.unicodeScalars.contains(where: {
            $0.value <= 0x1f || (0x7f...0x9f).contains($0.value)
        }), "wallet account name must not contain control characters")
        return normalized
    }

    static func additionalIndices(_ values: [UInt32]) throws -> [UInt32] {
        try CitizenSDKChecks.require((1...maximumAdditionalAccounts).contains(values.count),
                                     "wallet index list must contain 1...1989 items")
        try CitizenSDKChecks.require(Set(values).count == values.count && values.allSatisfy { (1...1_989).contains($0) },
                                     "wallet indices must be unique values in 1...1989")
        return values
    }
}
