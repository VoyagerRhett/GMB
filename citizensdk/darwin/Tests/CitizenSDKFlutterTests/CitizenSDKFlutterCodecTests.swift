import Foundation
import XCTest
@testable import CitizenSDK
@testable import CitizenSDKFlutter

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

final class CitizenSDKFlutterCodecTests: XCTestCase {
    func testQrUiRoutesRejectInjectedClockSignatureAndLegacyMethods() throws {
        guard case let .qr(method, _, _, fields) = try CitizenSdkFlutterCodec.decode(method: "qrScan", arguments: [1, "session", 1]) else {
            return XCTFail("扫码必须走唯一会话 QR 请求")
        }
        XCTAssertEqual(method, "qrScan"); XCTAssertTrue(fields.isEmpty)
        for method in ["qrParse", "qrConsumeSignResponse", "signQrRequest"] {
            XCTAssertNoThrow(try CitizenSdkFlutterCodec.decode(method: method, arguments: [1, "session", 2, "{}"]))
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: method, arguments: [1, "session", 2, "{}", 123]))
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: method, arguments: [1, "session", 2, "{}", FlutterStandardTypedData(bytes: Data(count: 64))]))
        }
        for method in ["qrSigningInput", "qrCreateSignResponse", "qrEncodeImage"] {
            XCTAssertFalse(CitizenSdkFlutterCodec.methods.contains(method))
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: method, arguments: [1, "session", 3, "{}"]))
        }
    }

    func testPrivateKeyViewTransportsOnlyOnePublicAccountAndKeepsSessionIdentity() throws {
        let account = "0x" + String(repeating: "11", count: 32)
        let request = try CitizenSdkFlutterCodec.decode(method: "viewAccountPrivateKey", arguments: [1, "session", 7, account])
        guard case let .account(method, session, sequence, accountID) = request else { return XCTFail("expected public account request") }
        XCTAssertEqual(method, "viewAccountPrivateKey"); XCTAssertEqual(session, "session")
        XCTAssertEqual(sequence, 7); XCTAssertEqual(accountID.count, 32)
        for tuple: [Any?] in [[1, "session", 7], [1, "session", 7, account, "extra"],
                             [1, "session", 7, "0X" + String(repeating: "11", count: 32)]] {
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: "viewAccountPrivateKey", arguments: tuple))
        }
    }

    func testChainQueriesKeepSessionShapeAndBatchInputOrder() throws {
        let first = "0x" + String(repeating: "11", count: 32)
        let second = "0x" + String(repeating: "22", count: 32)
        let genesis = try CitizenSdkFlutterCodec.decode(method: "getGenesisHash", arguments: [1, "session", 7])
        XCTAssertEqual(genesis.sessionID, "session")
        XCTAssertEqual(genesis.sequence, 7)
        for accounts in [[], [second, first, second], Array(repeating: first, count: 1_990)] {
            let request = try CitizenSdkFlutterCodec.decode(method: "getAccountBalances", arguments: [1, "session", 8, accounts])
            guard case let .balances(session, sequence, values) = request else { return XCTFail("expected balances") }
            XCTAssertEqual(session, "session")
            XCTAssertEqual(sequence, 8)
            XCTAssertEqual(values.count, accounts.count)
            if accounts.count == 3 { XCTAssertEqual(values, [Data(repeating: 0x22, count: 32), Data(repeating: 0x11, count: 32), Data(repeating: 0x22, count: 32)]) }
        }
        let invalid: [[Any?]] = [
            [1, "session", 8, Array(repeating: first, count: 1_991)],
            [1, "session", 8, ["0x" + String(repeating: "AA", count: 32)]],
            [1, "session", 8, first], [1, "session", 8, [], "extra"],
        ]
        for tuple in invalid {
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: "getAccountBalances", arguments: tuple)) {
                let failure = $0 as? CitizenSdkFlutterCodec.ContractFailure
                XCTAssertEqual(failure?.session, "session")
                XCTAssertEqual(failure?.sequence, 8)
            }
        }
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: "getGenesisHash", arguments: [1, "session", 7, "extra"]))
    }

    func testOpenCarriesExactModuleSelectionAndRejectsOldShape() throws {
        for raw in [1, 2, 4, 12, 20, 31, 32, 63] {
            let request = try CitizenSdkFlutterCodec.decode(method: "open", arguments: [1, raw])
            guard case let .open(modules) = request else { return XCTFail("expected open") }
            XCTAssertEqual(modules.rawValue, UInt32(raw))
        }
        let invalid: [[Any?]] = [[1], [1, true], [1, 1.0], [1, -1], [1, 4_294_967_296], [1, 31, 0]]
        for tuple in invalid {
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: "open", arguments: tuple))
        }
        // 位依赖检查归 Rust；传输层不得另写一套规则或吞掉未知位。
        guard case let .open(modules) = try CitizenSdkFlutterCodec.decode(method: "open", arguments: [1, 32]) else {
            return XCTFail("expected unchanged module value")
        }
        XCTAssertEqual(modules.rawValue, 32)
    }

    func testVerifyHasExactPublicSignatureAndAllowsEmptyMessage() throws {
        let account = "0x" + String(repeating: "11", count: 32)
        let prefix: [Any?] = [1, account]
        let payload = FlutterStandardTypedData(bytes: Data())
        for length in [0, 63, 65] {
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: "verifySignature",
                arguments: prefix + [FlutterStandardTypedData(bytes: Data(repeating: 0, count: length)), payload]))
        }
        let request = try CitizenSdkFlutterCodec.decode(method: "verifySignature",
            arguments: prefix + [FlutterStandardTypedData(bytes: Data(repeating: 0, count: 64)), payload])
        guard case let .verify(_, signature, message) = request else { return XCTFail("expected verify") }
        XCTAssertNil(request.sessionID)
        XCTAssertNil(request.sequence)
        XCTAssertEqual(signature.count, 64)
        XCTAssertTrue(message.isEmpty)
    }

    func testVerifyRejectsSessionShapeAndMalformedPublicValuesWithoutSessionIdentity() {
        let account = "0x" + String(repeating: "11", count: 32)
        let signature = FlutterStandardTypedData(bytes: Data(repeating: 0, count: 64))
        let payload = FlutterStandardTypedData(bytes: Data())
        let invalid: [[Any?]] = [
            [1, "session", 7, account, signature, payload],
            [true, account, signature, payload],
            [1, "0X" + String(repeating: "11", count: 32), signature, payload],
            [1, account, Data(repeating: 0, count: 64), payload],
            [1, account, signature, [1, 2]],
            [1, account, signature, payload, "extra"],
        ]
        for tuple in invalid {
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: "verifySignature", arguments: tuple)) { error in
                guard let failure = error as? CitizenSdkFlutterCodec.ContractFailure else {
                    return XCTFail("expected contract failure")
                }
                XCTAssertNil(failure.session)
                XCTAssertNil(failure.sequence)
            }
        }
    }

    func testHistoryInvalidationHasNoPayload() throws {
        let event = try CitizenSdkFlutterCodec.event(session: "session", sequence: 7, type: "historyChanged", payload: [])
        XCTAssertEqual(event[3] as? String, "historyChanged")
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.event(session: "session", sequence: 7, type: "historyChanged", payload: [1]))
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.event(session: "session", sequence: 0, type: "historyChanged", payload: []))
    }
    func testWalletWordCountsAreExactlyTwelveEighteenTwentyFour() throws {
        for count in [12, 18, 24] {
            let request = try CitizenSdkFlutterCodec.decode(method: "createWallet", arguments: [1, "session", 1, count])
            guard case let .create(_, _, actual) = request else { return XCTFail("expected create request") }
            XCTAssertEqual(actual, UInt32(count))
        }
        for count in [0, 15, 21, 30] {
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(method: "createWallet", arguments: [1, "session", 1, count]))
        }
    }

    func testEveryV1MethodHasOneExactPositionalShape() throws {
        XCTAssertEqual(CitizenSdkFlutterCodec.methodChannel, "citizen/sdk/core/v1")
        XCTAssertEqual(CitizenSdkFlutterCodec.eventChannel, "citizen/sdk/events/v1")
        XCTAssertEqual(CitizenSdkFlutterCodec.version, 1)
        let exactMethods: Set<String> = [
            "open", "start", "stop", "close", "getCapabilities", "getFinalizedHead",
            "getSyncStatus", "getBestHead", "getFinalizedBlockAt", "resolveFinalizedBlock",
            "getBlockHeader", "getBlockBody", "getRuntimeContext", "getStorage", "getStorageBatch",
            "getStorageKeysPaged", "callRuntimeApi",
            "getSystemEvents", "exportState", "importState",
            "getGenesisHash", "getAccountBalance", "getAccountBalances", "getAccountNonce", "getFeeSnapshot", "getWalletProfile",
            "getWalletState", "importColdAccountId", "importColdAccountSs58",
            "reorderWalletAccountsWithoutDefaultChange", "renameAccount", "deleteAccount",
            "viewAccountPrivateKey", "createWallet", "importWallet", "addWalletAccounts", "setActiveWalletAccount",
            "renameWalletAccount", "deleteWalletAccount", "deleteWallet",
            "reconcileWalletCleanup", "signWalletPayload", "deriveApplicationKey",
            "beginSigning", "consumeExternalSignature",
            "cancelSigning", "beginDefaultAccountChange", "consumeDefaultAccountChange",
            "verifySignature", "prepareTransaction", "cancelPreparedTransaction", "executePreparedTransaction",
            "consumePreparedTransactionQrResponse", "cancelPreparedTransactionExecution",
            "getTransactionHistory", "syncTransactionHistory", "qrParse", "qrCreateSignRequest",
            "qrConsumeSignResponse", "qrCancelSignRequest", "qrEncodeAccountId",
            "qrDecodeLuminance", "qrEncode", "qrScan", "signQrRequest",
        ]
        XCTAssertEqual(CitizenSdkFlutterCodec.methods, exactMethods)

        let version = NSNumber(value: 1)
        let sequence = NSNumber(value: 1)
        let account = "0x" + String(repeating: "11", count: 32)
        let destination = "0x" + String(repeating: "22", count: 32)
        var requests: [String: [Any?]] = ["open": [version, NSNumber(value: 63)]]
        for method in [
            "start", "stop", "close", "getCapabilities", "getFinalizedHead", "getSyncStatus",
            "getBestHead", "exportState", "getGenesisHash",
            "getFeeSnapshot", "getWalletProfile", "getWalletState", "importWallet", "deleteWallet",
            "reconcileWalletCleanup",
        ] { requests[method] = [version, "session-1", sequence] }
        let finalizedBlock: [Any?] = [account, "1", "finalized"]
        requests["getFinalizedBlockAt"] = [version, "session-1", sequence, "1"]
        requests["resolveFinalizedBlock"] = [version, "session-1", sequence, account, "1"]
        for method in ["getBlockHeader", "getBlockBody", "getRuntimeContext", "getSystemEvents"] {
            requests[method] = [version, "session-1", sequence, finalizedBlock]
        }
        requests["getStorage"] = [version, "session-1", sequence, finalizedBlock,
                                  FlutterStandardTypedData(bytes: Data([1]))]
        requests["getStorageBatch"] = [version, "session-1", sequence, finalizedBlock, [
            FlutterStandardTypedData(bytes: Data([1])), FlutterStandardTypedData(bytes: Data([2])),
        ]]
        requests["getStorageKeysPaged"] = [version, "session-1", sequence, finalizedBlock,
            FlutterStandardTypedData(bytes: Data([1])), nil, NSNumber(value: 1000)]
        requests["callRuntimeApi"] = [version, "session-1", sequence, finalizedBlock,
            "CitizenApi_items", FlutterStandardTypedData(bytes: Data())]
        requests["importState"] = [version, "session-1", sequence, NSNumber(value: 1), finalizedBlock,
                                   FlutterStandardTypedData(bytes: Data([1]))]
        for method in [
            "getAccountBalance", "getAccountNonce", "viewAccountPrivateKey", "setActiveWalletAccount",
            "deleteWalletAccount", "deleteAccount",
        ] { requests[method] = [version, "session-1", sequence, account] }
        requests["getAccountBalances"] = [version, "session-1", sequence, [account, account]]
        requests["createWallet"] = [version, "session-1", sequence, NSNumber(value: 24)]
        requests["addWalletAccounts"] = [version, "session-1", sequence,
                                          [NSNumber(value: 1), NSNumber(value: 7)]]
        requests["renameWalletAccount"] = [version, "session-1", sequence, account, "main"]
        requests["renameAccount"] = [version, "session-1", sequence, account, "main"]
        requests["importColdAccountId"] = [version, "session-1", sequence, account, "cold"]
        requests["importColdAccountSs58"] = [version, "session-1", sequence,
            "w5CZACAABUbK4jspzPB5be9trhtSgRCRZFafGe7kvFPvxq8M2", "cold"]
        requests["reorderWalletAccountsWithoutDefaultChange"] = [version, "session-1", sequence,
            "7", [account, destination]]
        requests["signWalletPayload"] = [version, "session-1", sequence, account,
                                          FlutterStandardTypedData(bytes: Data([1]))]
        requests["deriveApplicationKey"] = [version, "session-1", sequence, account,
            FlutterStandardTypedData(bytes: Data(repeating: 0, count: 32)),
            FlutterStandardTypedData(bytes: Data([1]))]
        requests["beginSigning"] = [version, "session-1", sequence, account,
            FlutterStandardTypedData(bytes: Data([1])), "raw",
            FlutterStandardTypedData(bytes: Data()), "none", NSNumber(value: 0), NSNumber(value: 120)]
        requests["consumeExternalSignature"] = [version, "session-1", sequence, "signing-session", "{}"]
        requests["cancelSigning"] = [version, "session-1", sequence, "signing-session"]
        requests["beginDefaultAccountChange"] = [version, "session-1", sequence,
            "7", [destination, account], NSNumber(value: 120)]
        requests["consumeDefaultAccountChange"] = [version, "session-1", sequence, "signing-session", "{}"]
        requests["verifySignature"] = [version, account,
                                        FlutterStandardTypedData(bytes: Data(repeating: 0, count: 64)),
                                        FlutterStandardTypedData(bytes: Data())]
        requests["prepareTransaction"] = [version, "session-1", sequence, account,
            FlutterStandardTypedData(bytes: Data([1, 2]))]
        requests["cancelPreparedTransaction"] = [version, "session-1", sequence,
            "0x00112233445566778899aabbccddeeff"]
        requests["executePreparedTransaction"] = [version, "session-1", sequence,
            "0x00112233445566778899aabbccddeeff"]
        requests["consumePreparedTransactionQrResponse"] = [version, "session-1", sequence,
            "0x112233445566778899aabbccddeeff00", "QR_V1"]
        requests["cancelPreparedTransactionExecution"] = [version, "session-1", sequence,
            "0x112233445566778899aabbccddeeff00"]
        requests["getTransactionHistory"] = [version, "session-1", sequence, nil, NSNumber(value: 100)]
        requests["syncTransactionHistory"] = [version, "session-1", sequence]
        requests["qrParse"] = [version, "session-1", sequence, "{}"]
        requests["qrCreateSignRequest"] = [version, "session-1", sequence, NSNumber(value: 0x0400),
            account, FlutterStandardTypedData(bytes: Data([4, 0])), NSNumber(value: 120)]
        requests["qrScan"] = [version, "session-1", sequence]
        requests["signQrRequest"] = [version, "session-1", sequence, "{}"]
        requests["qrConsumeSignResponse"] = [version, "session-1", sequence, "{}"]
        requests["qrCancelSignRequest"] = [version, "session-1", sequence, "abcdefghijklmnop"]
        requests["qrEncodeAccountId"] = [version, "session-1", sequence, account]
        requests["qrDecodeLuminance"] = [version, "session-1", sequence,
            FlutterStandardTypedData(bytes: Data([0])), NSNumber(value: 1), NSNumber(value: 1), NSNumber(value: 1)]
        requests["qrEncode"] = [version, "session-1", sequence, "{}", NSNumber(value: 4)]

        XCTAssertEqual(Set(requests.keys), exactMethods)
        for (method, tuple) in requests {
            XCTAssertNoThrow(try CitizenSdkFlutterCodec.decode(method: method, arguments: tuple), method)
            XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(
                method: method, arguments: tuple + ["forbidden-extra-position"]
            ), method)
        }
    }

    func testWalletStateProjectionKeepsColdModeGlobalOrderAndDefaultFirst() {
        let cold = CitizenWalletStateAccount(signMode: .cold, walletIndex: 1, accountIndex: nil,
            accountID: Data(repeating: 0x22, count: 32),
            ss58Address: "w5CZACAABUbK4jspzPB5be9trhtSgRCRZFafGe7kvFPvxq8M2",
            name: "cold", createdAtMillis: 2, isDefault: true)
        let tuple = CitizenSdkFlutterCodec.walletState(
            CitizenWalletState(revision: 7, hotProfile: nil, accounts: [cold]))
        XCTAssertEqual(tuple[0] as? String, "7")
        XCTAssertNil(tuple[1])
        let accounts = tuple[2] as? [[Any?]]
        XCTAssertEqual(accounts?.first?[0] as? String, "cold")
        XCTAssertEqual(accounts?.first?[1] as? Int64, 1)
        XCTAssertNil(accounts?.first?[2])
        XCTAssertEqual(accounts?.first?[7] as? Bool, true)
    }

    func testHashDecoderRejectsUppercaseAndPreservesCorrelation() {
        let uppercase = "0x" + String(repeating: "AA", count: 32)
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(
            method: "getAccountBalance",
            arguments: [NSNumber(value: 1), "session-a", NSNumber(value: 7), uppercase]
        )) { error in
            guard let failure = error as? CitizenSdkFlutterCodec.ContractFailure else {
                return XCTFail("expected correlated contract failure")
            }
            XCTAssertEqual(failure.code, .invalidArgument)
            XCTAssertEqual(failure.session, "session-a")
            XCTAssertEqual(failure.sequence, 7)
        }
    }

    func testSigningBytesRejectNonUInt8TypedData() throws {
        let account = "0x" + String(repeating: "11", count: 32)
        let prefix: [Any?] = [NSNumber(value: 1), "session", NSNumber(value: 1), account]
        XCTAssertNoThrow(try CitizenSdkFlutterCodec.decode(
            method: "signWalletPayload",
            arguments: prefix + [FlutterStandardTypedData(bytes: Data([1, 2, 3, 4]))]
        ))
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(
            method: "signWalletPayload",
            arguments: prefix + [FlutterStandardTypedData(int32: Data([1, 0, 0, 0]))]
        ))
    }

    func testHistoryCursorFailurePreservesSessionAndSequence() {
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(
            method: "getTransactionHistory",
            arguments: [NSNumber(value: 1), "session-b", NSNumber(value: 8),
                        "0X00112233445566778899aabbccddeeff", NSNumber(value: 100)]
        )) { error in
            let failure = error as? CitizenSdkFlutterCodec.ContractFailure
            XCTAssertEqual(failure?.session, "session-b")
            XCTAssertEqual(failure?.sequence, 8)
            XCTAssertEqual(failure?.code, .invalidArgument)
        }
    }

    func testSessionUsesExactUtf16BoundaryWithoutNormalization() throws {
        let version = NSNumber(value: 1)
        let sequence = NSNumber(value: 1)
        let allowed = String(repeating: "😀", count: 64)
        let request = try CitizenSdkFlutterCodec.decode(
            method: "start", arguments: [version, allowed, sequence]
        )
        XCTAssertEqual(request.sessionID, allowed)
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(
            method: "start",
            arguments: [version, String(repeating: "😀", count: 65), sequence]
        ))

        let decomposed = String(repeating: "e\u{301}", count: 64)
        XCTAssertEqual(decomposed.utf16.count, 128)
        XCTAssertEqual(try CitizenSdkFlutterCodec.decode(
            method: "start", arguments: [version, decomposed, sequence]
        ).sessionID, decomposed)
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(
            method: "start", arguments: [NSNumber(value: 1.0), "session", sequence]
        ))
    }

    func testTransactionHistoryProjectionContainsOnlyGenericExecutionFields() throws {
        let executionID = "0x00112233445566778899aabbccddeeff"
        let record = CitizenTransactionHistoryRecord(
            executionID: executionID,
            sourceAccountID: Data(repeating: 3, count: 32),
            callDataHash: Data(repeating: 4, count: 32),
            transactionHash: Data(repeating: 5, count: 32),
            status: .pending, block: nil, execution: nil, replacementHash: nil,
            createdAtMillis: 1, updatedAtMillis: 1, poolRejectionReason: nil)
        let page = CitizenTransactionHistoryPage(
            revision: 1, records: [record], nextBeforeExecutionID: executionID)
        let tuple = try CitizenSdkFlutterCodec.transactionHistoryPage(page)
        XCTAssertEqual(tuple[0] as? String, "1")
        XCTAssertEqual(tuple[2] as? String, executionID)
        XCTAssertEqual((tuple[1] as? [[Any?]])?.first?.count, 11)
    }

    func testEventVocabularyIsClosed() throws {
        XCTAssertEqual(CitizenSdkFlutterCodec.eventTypes,
                       ["lifecycleChanged", "capabilitiesChanged", "historyChanged",
                        "finalizedBlockChanged"])
        XCTAssertNoThrow(try CitizenSdkFlutterCodec.event(
            session: "s", sequence: 1, type: "lifecycleChanged", payload: ["running"]
        ))
        XCTAssertThrowsError(try CitizenSdkFlutterCodec.event(
            session: "s", sequence: 2, type: "debug", payload: []
        ))
    }
}
