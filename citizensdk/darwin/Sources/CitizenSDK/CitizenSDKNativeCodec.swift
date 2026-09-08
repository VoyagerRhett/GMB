import Foundation

/// Decodes retained Core result handles into secret-free Swift value types.
internal enum CitizenSDKNativeCodec {
    static func qr(_ result: UInt64, kind: UInt32) throws -> String {
        try inspect(result, kind: kind) {
            var required: UInt64 = 0
            try CitizenSDKChecks.requireOK(citizensdk_result_copy_qr(result, nil, 0, &required), "Core QR result length is invalid")
            guard required > 0, required <= 65_536 else { throw CitizenSDKError(.integrity, "Core QR result exceeds its limit") }
            var output = Data(count: Int(required))
            let capacity = required
            let status = output.withUnsafeMutableBytes {
                citizensdk_result_copy_qr(result, $0.bindMemory(to: UInt8.self).baseAddress, capacity, &required)
            }
            try CitizenSDKChecks.requireOK(status, "Core QR result copy failed")
            guard required == capacity, let json = String(data: output, encoding: .utf8) else {
                throw CitizenSDKError(.integrity, "Core QR result is not exact UTF-8")
            }
            return json
        }
    }

    static func empty(_ result: UInt64) throws {
        try inspect(result, kind: 0) { () }
    }

    static func block(_ result: UInt64) throws -> CitizenBlockRef {
        try inspect(result, kind: 1) {
            var value = citizensdk_block_ref_t()
            prepare(&value.struct_size, &value.abi_version, citizensdk_block_ref_t.self)
            try CitizenSDKChecks.requireOK(citizensdk_result_get_block_ref(result, &value), "Core block result is invalid")
            return try block(value)
        }
    }

    static func balance(_ result: UInt64) throws -> CitizenAccountBalance {
        try inspect(result, kind: 9) {
            var value = citizensdk_account_balance_info_t()
            prepare(&value.struct_size, &value.abi_version, citizensdk_account_balance_info_t.self)
            try CitizenSDKChecks.requireOK(citizensdk_result_get_account_balance(result, &value), "Core balance result is invalid")
            return try balance(value)
        }
    }

    static func balances(_ result: UInt64, accountIDs: [Data]) throws -> [CitizenAccountBalance] {
        try inspect(result, kind: 18) {
            var count: UInt32 = 0
            try CitizenSDKChecks.requireOK(citizensdk_result_get_account_balance_count(result, &count),
                                           "Core balance count is invalid")
            guard count <= 1_990, Int(count) == accountIDs.count else {
                throw CitizenSDKError(.integrity, "Core balance result count differs from the request")
            }
            let values = try (0..<count).map { index in
                var value = citizensdk_account_balance_info_t()
                prepare(&value.struct_size, &value.abi_version, citizensdk_account_balance_info_t.self)
                try CitizenSDKChecks.requireOK(citizensdk_result_get_account_balance_at(result, index, &value),
                                               "Core balance result is invalid")
                return try balance(value)
            }
            return try validateBalances(values, accountIDs: accountIDs)
        }
    }

    /// 只校验跨边界的结果完整性；账户解码、同块查询与余额计算仍唯一归 Rust。
    static func validateBalances(_ values: [CitizenAccountBalance], accountIDs: [Data]) throws -> [CitizenAccountBalance] {
        guard values.count == accountIDs.count, values.count <= 1_990,
              zip(values, accountIDs).allSatisfy({ $0.0.accountID == $0.1 }),
              values.allSatisfy({ $0.block.finality == .finalized && $0.block == values.first?.block }) else {
            throw CitizenSDKError(.integrity, "Core balance results do not match one finalized request")
        }
        return values
    }

    private static func balance(_ value: citizensdk_account_balance_info_t) throws -> CitizenAccountBalance {
        CitizenAccountBalance(block: try block(value.block), accountID: fixed(value.account_id.bytes, 32),
                              freeFen: u128(value.free_fen), reservedFen: u128(value.reserved_fen),
                              totalFen: u128(value.total_fen))
    }

    static func nonce(_ result: UInt64) throws -> CitizenAccountNonce {
        try inspect(result, kind: 10) {
            var value = citizensdk_account_nonce_info_t()
            prepare(&value.struct_size, &value.abi_version, citizensdk_account_nonce_info_t.self)
            try CitizenSDKChecks.requireOK(citizensdk_result_get_account_nonce(result, &value), "Core nonce result is invalid")
            return CitizenAccountNonce(bestBlock: try block(value.best_block),
                                       accountID: fixed(value.account_id.bytes, 32), nonce: value.nonce)
        }
    }

    static func fee(_ result: UInt64) throws -> CitizenFeeSnapshot {
        try inspect(result, kind: 11) {
            var value = citizensdk_fee_snapshot_info_t()
            prepare(&value.struct_size, &value.abi_version, citizensdk_fee_snapshot_info_t.self)
            try CitizenSDKChecks.requireOK(citizensdk_result_get_fee_snapshot(result, &value), "Core fee result is invalid")
            return CitizenFeeSnapshot(bestBlock: try block(value.best_block), feeRateParts: value.fee_rate_parts,
                                      minimumFeeFen: u128(value.minimum_fee_fen),
                                      existentialDepositFen: u128(value.existential_deposit_fen))
        }
    }

    static func profile(_ result: UInt64) throws -> CitizenWalletProfile? {
        try inspect(result, kind: 12) { try walletProfile(result) }
    }

    static func accounts(_ result: UInt64) throws -> [CitizenWalletAccount] {
        try inspect(result, kind: 13) { try walletAccounts(result) }
    }

    static func signature(_ result: UInt64) throws -> CitizenSignature {
        try inspect(result, kind: 14) {
            var bytes = Data(count: 64)
            let code = bytes.withUnsafeMutableBytes {
                citizensdk_result_get_signature(result, $0.bindMemory(to: UInt8.self).baseAddress)
            }
            try CitizenSDKChecks.requireOK(code, "Core signature result is invalid")
            return try CitizenSignature(bytes)
        }
    }

    static func preparedWallet(_ result: UInt64) throws -> UInt64 {
        try inspect(result, kind: 15) {
            var value = citizensdk_prepared_wallet_info_t()
            prepare(&value.struct_size, &value.abi_version, citizensdk_prepared_wallet_info_t.self)
            try CitizenSDKChecks.requireOK(citizensdk_result_get_prepared_wallet(result, &value), "Core prepared wallet result is invalid")
            guard value.prepared_wallet != 0 else { throw CitizenSDKError(.integrity, "Core returned an empty prepared wallet") }
            return value.prepared_wallet
        }
    }

    static func transfer(_ result: UInt64) throws -> CitizenWalletTransfer {
        try inspect(result, kind: 16) {
            var info = citizensdk_wallet_transfer_info_t()
            prepare(&info.struct_size, &info.abi_version, citizensdk_wallet_transfer_info_t.self)
            var required: UInt64 = 0
            try CitizenSDKChecks.requireOK(
                citizensdk_result_get_wallet_transfer(result, &info, nil, 0, &required),
                "Core transfer result is invalid"
            )
            let reason = try copy(required) { pointer, capacity, outRequired in
                citizensdk_result_get_wallet_transfer(result, &info, pointer, capacity, outRequired)
            }
            guard let resolution = CitizenTransferResolution(rawValue: info.resolution) else {
                throw CitizenSDKError(.integrity, "Core returned an unknown transfer resolution")
            }
            return CitizenWalletTransfer(
                transactionHash: fixed(info.transaction_hash, 32),
                resolution: resolution,
                execution: info.has_execution == 0 ? nil : try execution(info.execution),
                poolRejectionReason: reason.isEmpty ? nil : try text(reason)
            )
        }
    }

    static func history(_ result: UInt64) throws -> CitizenTransactionHistory {
        try inspect(result, kind: 17) {
            var info = citizensdk_history_info_t()
            prepare(&info.struct_size, &info.abi_version, citizensdk_history_info_t.self)
            try CitizenSDKChecks.requireOK(citizensdk_result_get_history_info(result, &info), "Core history result is invalid")
            guard info.cursor_count <= 1_990, info.record_count <= 100_000, info.transfer_count <= 100_000 else {
                throw CitizenSDKError(.integrity, "Core history result exceeds the public contract")
            }
            let cursors = try (0..<info.cursor_count).map { index -> CitizenHistoryCursor in
                var value = citizensdk_history_cursor_info_t()
                prepare(&value.struct_size, &value.abi_version, citizensdk_history_cursor_info_t.self)
                try CitizenSDKChecks.requireOK(citizensdk_result_get_history_cursor(result, index, &value), "Core history cursor is invalid")
                return CitizenHistoryCursor(accountID: fixed(value.account_id.bytes, 32),
                                            trackingStartBlock: try block(value.tracking_start_block),
                                            lastSyncedBlock: try block(value.last_synced_block))
            }
            let records = try (0..<info.record_count).map { try historyRecord(result, $0) }
            let transfers = try (0..<info.transfer_count).map { try finalizedTransfer(result, $0) }
            return CitizenTransactionHistory(revision: info.revision, cursors: cursors,
                                             records: records, transfers: transfers)
        }
    }

    static func watch(_ result: UInt64, operationID: String, sequence: UInt64) throws -> CitizenTransferProgress {
        var value = citizensdk_watch_event_info_t()
        prepare(&value.struct_size, &value.abi_version, citizensdk_watch_event_info_t.self)
        try CitizenSDKChecks.requireOK(citizensdk_result_get_watch_event(result, &value), "Core watch result is invalid")
        guard let status = CitizenTransferProgressStatus(rawValue: value.status) else {
            throw CitizenSDKError(.integrity, "Core returned an unknown watch status")
        }
        return CitizenTransferProgress(
            operationID: operationID,
            sequence: sequence,
            status: status,
            block: value.has_block == 0 ? nil : try block(value.block),
            replacementHash: value.has_replacement_hash == 0 ? nil : fixed(value.replacement_hash, 32),
            peerCount: value.peer_count
        )
    }

    static func capabilities(_ snapshot: citizensdk_capability_snapshot_t) throws -> CitizenSDKCapabilities {
        guard snapshot.struct_size >= UInt32(MemoryLayout<citizensdk_capability_snapshot_t>.size),
              snapshot.abi_version == 1, snapshot.count == 10 else {
            throw CitizenSDKError(.integrity, "Core capability snapshot ABI is invalid")
        }
        let statuses: [CitizenCapabilityStatus] = try withUnsafeBytes(of: snapshot.statuses) { bytes in
            let typed = bytes.bindMemory(to: citizensdk_capability_status_t.self)
            guard typed.count >= 10 else { throw CitizenSDKError(.integrity, "Core capability tuple is truncated") }
            return try (0..<10).map { index in
                let value = typed[index]
                guard let name = CitizenCapabilityName(rawValue: value.name),
                      let reason = CitizenCapabilityReason(rawValue: value.reason) else {
                    throw CitizenSDKError(.integrity, "Core returned an unknown capability value")
                }
                return CitizenCapabilityStatus(name: name, reason: reason, supported: try boolean(value.supported),
                                               available: try boolean(value.available), enabled: try boolean(value.enabled),
                                               ready: try boolean(value.ready))
            }
        }
        guard Set(statuses.map(\.name)).count == 10 else {
            throw CitizenSDKError(.integrity, "Core capability snapshot contains duplicate names")
        }
        return CitizenSDKCapabilities(revision: snapshot.revision, statuses: statuses)
    }

    private static func inspect<T>(_ result: UInt64, kind: UInt32, body: () throws -> T) throws -> T {
        var info = citizensdk_result_info_t()
        prepare(&info.struct_size, &info.abi_version, citizensdk_result_info_t.self)
        try CitizenSDKChecks.requireOK(citizensdk_result_get_info(result, &info), "Core result identity is invalid")
        if info.error_code != 0 {
            let message = try resultErrorMessage(result)
            throw CitizenSDKError(.checked(info.error_code), message.isEmpty ? "CitizenSDK operation failed" : message)
        }
        guard info.kind == kind else {
            throw CitizenSDKError(.integrity, "Core returned result kind \(info.kind), expected \(kind)")
        }
        return try body()
    }

    private static func resultErrorMessage(_ result: UInt64) throws -> String {
        var required: UInt64 = 0
        try CitizenSDKChecks.requireOK(citizensdk_result_copy_error_message(result, nil, 0, &required), "Core error text query failed")
        return try text(copy(required) { citizensdk_result_copy_error_message(result, $0, $1, $2) })
    }

    private static func walletProfile(_ result: UInt64) throws -> CitizenWalletProfile? {
        var info = citizensdk_wallet_profile_info_t()
        prepare(&info.struct_size, &info.abi_version, citizensdk_wallet_profile_info_t.self)
        try CitizenSDKChecks.requireOK(citizensdk_result_get_wallet_profile(result, &info), "Core wallet profile is invalid")
        guard info.present == 0 || info.present == 1 else { throw CitizenSDKError(.integrity, "Core profile presence is invalid") }
        if info.present == 0 { return nil }
        guard info.account_count <= 1_990, let origin = CitizenWalletOrigin(rawValue: info.origin) else {
            throw CitizenSDKError(.integrity, "Core wallet profile descriptor is invalid")
        }
        let accounts = try walletAccounts(result)
        guard accounts.count == Int(info.account_count) else { throw CitizenSDKError(.integrity, "Core wallet account count drifted") }
        return CitizenWalletProfile(origin: origin, walletIndex: info.wallet_index,
                                    createdAtMillis: info.created_at_millis,
                                    masterAccountID: fixed(info.master_account_id.bytes, 32),
                                    activeAccountID: fixed(info.active_account_id.bytes, 32), accounts: accounts)
    }

    private static func walletAccounts(_ result: UInt64) throws -> [CitizenWalletAccount] {
        var count: UInt32 = 0
        try CitizenSDKChecks.requireOK(citizensdk_result_get_wallet_account_count(result, &count), "Core wallet account count is invalid")
        guard count <= 1_990 else { throw CitizenSDKError(.integrity, "Core wallet account count exceeds the contract") }
        return try (0..<count).map { index in
            var info = citizensdk_wallet_account_info_t()
            prepare(&info.struct_size, &info.abi_version, citizensdk_wallet_account_info_t.self)
            var ss58Required: UInt64 = 0
            var nameRequired: UInt64 = 0
            try CitizenSDKChecks.requireOK(
                citizensdk_result_get_wallet_account(result, index, &info, nil, 0, &ss58Required, nil, 0, &nameRequired),
                "Core wallet account size query failed"
            )
            let pair = try copyPair(ss58Required, nameRequired) { ss58, ss58Capacity, ss58Out, name, nameCapacity, nameOut in
                citizensdk_result_get_wallet_account(result, index, &info, ss58, ss58Capacity, ss58Out,
                                                     name, nameCapacity, nameOut)
            }
            guard info.is_active == 0 || info.is_active == 1 else { throw CitizenSDKError(.integrity, "Core wallet active flag is invalid") }
            return CitizenWalletAccount(index: info.index, accountID: fixed(info.account_id.bytes, 32),
                                        ss58Address: try text(pair.0), name: pair.1.isEmpty ? nil : try text(pair.1),
                                        createdAtMillis: info.created_at_millis, active: info.is_active == 1)
        }
    }

    private static func historyRecord(_ result: UInt64, _ index: UInt32) throws -> CitizenHistoryRecord {
        var info = citizensdk_history_record_info_t()
        prepare(&info.struct_size, &info.abi_version, citizensdk_history_record_info_t.self)
        var remarkRequired: UInt64 = 0
        var reasonRequired: UInt64 = 0
        try CitizenSDKChecks.requireOK(
            citizensdk_result_get_history_record(result, index, &info, nil, 0, &remarkRequired, nil, 0, &reasonRequired),
            "Core history record size query failed"
        )
        let pair = try copyPair(remarkRequired, reasonRequired) { remark, remarkCapacity, remarkOut, reason, reasonCapacity, reasonOut in
            citizensdk_result_get_history_record(result, index, &info, remark, remarkCapacity, remarkOut,
                                                 reason, reasonCapacity, reasonOut)
        }
        guard let status = CitizenHistoryStatus(rawValue: info.status) else {
            throw CitizenSDKError(.integrity, "Core history status is invalid")
        }
        return CitizenHistoryRecord(
            accountID: fixed(info.account_id.bytes, 32), transactionHash: fixed(info.transaction_hash, 32),
            nonce: info.nonce, destinationAccountID: fixed(info.destination_account_id.bytes, 32),
            amountFen: u128(info.amount_fen), status: status,
            block: info.has_block == 0 ? nil : try block(info.block),
            execution: info.has_execution == 0 ? nil : try execution(info.execution),
            createdAtMillis: info.created_at_millis, updatedAtMillis: info.updated_at_millis,
            remark: pair.0, poolRejectionReason: pair.1.isEmpty ? nil : try text(pair.1)
        )
    }

    private static func finalizedTransfer(_ result: UInt64, _ index: UInt32) throws -> CitizenFinalizedTransfer {
        var info = citizensdk_finalized_transfer_info_t()
        prepare(&info.struct_size, &info.abi_version, citizensdk_finalized_transfer_info_t.self)
        var first: UInt64 = 0, second: UInt64 = 0, third: UInt64 = 0
        try CitizenSDKChecks.requireOK(
            citizensdk_result_get_finalized_transfer(result, index, &info, nil, 0, &first,
                                                     nil, 0, &second, nil, 0, &third),
            "Core finalized transfer size query failed"
        )
        let values = try copyThree(first, second, third) { a, ac, ao, b, bc, bo, c, cc, co in
            citizensdk_result_get_finalized_transfer(result, index, &info, a, ac, ao, b, bc, bo, c, cc, co)
        }
        guard let direction = CitizenTransferDirection(rawValue: info.direction) else {
            throw CitizenSDKError(.integrity, "Core transfer direction is invalid")
        }
        return CitizenFinalizedTransfer(
            trackedAccountID: fixed(info.tracked_account_id.bytes, 32),
            fromAccountID: fixed(info.from_account_id.bytes, 32), toAccountID: fixed(info.to_account_id.bytes, 32),
            amountFen: u128(info.amount_fen), block: try block(info.block), eventRecordIndex: info.event_record_index,
            extrinsicIndex: info.has_extrinsic_index == 0 ? nil : info.extrinsic_index, direction: direction,
            sourcePallet: try text(values.0), remarkDisplay: try text(values.1), remarkBytes: values.2
        )
    }

    private static func block(_ value: citizensdk_block_ref_t) throws -> CitizenBlockRef {
        guard value.struct_size >= UInt32(MemoryLayout<citizensdk_block_ref_t>.size), value.abi_version == 1,
              let finality = CitizenFinality(rawValue: value.finality) else {
            throw CitizenSDKError(.integrity, "Core block reference ABI is invalid")
        }
        return try CitizenBlockRef(hash: fixed(value.hash, 32), number: value.number, finality: finality)
    }

    private static func execution(_ value: citizensdk_execution_info_t) throws -> CitizenExecution {
        guard value.struct_size >= UInt32(MemoryLayout<citizensdk_execution_info_t>.size), value.abi_version == 1,
              let status = CitizenExecutionStatus(rawValue: value.status) else {
            throw CitizenSDKError(.integrity, "Core execution descriptor is invalid")
        }
        return CitizenExecution(status: status, reasonOrDispatchVariant: value.reason_or_dispatch_variant,
                                block: value.has_block == 0 ? nil : try block(value.block),
                                extrinsicIndex: value.has_extrinsic_index == 0 ? nil : value.extrinsic_index,
                                palletIndex: value.has_module == 0 ? nil : value.pallet_index,
                                errorIndex: value.has_module == 0 ? nil : value.error_index)
    }

    private static func u128(_ value: citizensdk_u128_t) -> CitizenU128 {
        CitizenU128(low: value.low, high: value.high)
    }

    private static func prepare<T>(_ size: inout UInt32, _ version: inout UInt32, _ type: T.Type) {
        size = UInt32(MemoryLayout<T>.size)
        version = 1
    }

    private static func fixed<T>(_ value: T, _ count: Int) -> Data {
        withUnsafeBytes(of: value) { Data($0.prefix(count)) }
    }

    private static func boolean(_ value: UInt8) throws -> Bool {
        guard value == 0 || value == 1 else { throw CitizenSDKError(.integrity, "Core boolean is invalid") }
        return value == 1
    }

    private static func text(_ data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else { throw CitizenSDKError(.integrity, "Core UTF-8 text is invalid") }
        return value
    }

    private static func copy(_ required: UInt64,
                             call: (UnsafeMutablePointer<UInt8>?, UInt64, UnsafeMutablePointer<UInt64>) -> Int32) throws -> Data {
        guard required <= UInt64(Int.max) else { throw CitizenSDKError(.integrity, "Core byte result is too large") }
        var output = Data(count: Int(required))
        var confirmed = required
        let code = output.withUnsafeMutableBytes {
            call($0.bindMemory(to: UInt8.self).baseAddress, UInt64($0.count), &confirmed)
        }
        try CitizenSDKChecks.requireOK(code, "Core byte result copy failed")
        guard confirmed == required else { throw CitizenSDKError(.integrity, "Core byte result length changed") }
        return output
    }

    private static func copyPair(
        _ first: UInt64, _ second: UInt64,
        call: (UnsafeMutablePointer<UInt8>?, UInt64, UnsafeMutablePointer<UInt64>,
               UnsafeMutablePointer<UInt8>?, UInt64, UnsafeMutablePointer<UInt64>) -> Int32
    ) throws -> (Data, Data) {
        guard first <= UInt64(Int.max), second <= UInt64(Int.max) else { throw CitizenSDKError(.integrity, "Core pair result is too large") }
        var a = Data(count: Int(first)), b = Data(count: Int(second))
        var ac = first, bc = second
        let code = a.withUnsafeMutableBytes { ap in b.withUnsafeMutableBytes { bp in
            call(ap.bindMemory(to: UInt8.self).baseAddress, UInt64(ap.count), &ac,
                 bp.bindMemory(to: UInt8.self).baseAddress, UInt64(bp.count), &bc)
        } }
        try CitizenSDKChecks.requireOK(code, "Core pair result copy failed")
        guard ac == first, bc == second else { throw CitizenSDKError(.integrity, "Core pair result length changed") }
        return (a, b)
    }

    private static func copyThree(
        _ first: UInt64, _ second: UInt64, _ third: UInt64,
        call: (UnsafeMutablePointer<UInt8>?, UInt64, UnsafeMutablePointer<UInt64>,
               UnsafeMutablePointer<UInt8>?, UInt64, UnsafeMutablePointer<UInt64>,
               UnsafeMutablePointer<UInt8>?, UInt64, UnsafeMutablePointer<UInt64>) -> Int32
    ) throws -> (Data, Data, Data) {
        guard first <= UInt64(Int.max), second <= UInt64(Int.max), third <= UInt64(Int.max) else {
            throw CitizenSDKError(.integrity, "Core triple result is too large")
        }
        var a = Data(count: Int(first)), b = Data(count: Int(second)), c = Data(count: Int(third))
        var ac = first, bc = second, cc = third
        let code = a.withUnsafeMutableBytes { ap in b.withUnsafeMutableBytes { bp in c.withUnsafeMutableBytes { cp in
            call(ap.bindMemory(to: UInt8.self).baseAddress, UInt64(ap.count), &ac,
                 bp.bindMemory(to: UInt8.self).baseAddress, UInt64(bp.count), &bc,
                 cp.bindMemory(to: UInt8.self).baseAddress, UInt64(cp.count), &cc)
        } } }
        try CitizenSDKChecks.requireOK(code, "Core triple result copy failed")
        guard ac == first, bc == second, cc == third else { throw CitizenSDKError(.integrity, "Core triple result length changed") }
        return (a, b, c)
    }
}
