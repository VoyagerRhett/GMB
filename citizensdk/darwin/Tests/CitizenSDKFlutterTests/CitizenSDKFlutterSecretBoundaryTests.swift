import Foundation
import XCTest
@testable import CitizenSDK
@testable import CitizenSDKFlutter

final class CitizenSDKFlutterSecretBoundaryTests: XCTestCase {
    func testImportTupleHasNoMnemonicOrPasswordPosition() throws {
        let valid: [Any?] = [NSNumber(value: 1), "session", NSNumber(value: 1)]
        if case let .empty(method, _, _) = try CitizenSdkFlutterCodec.decode(
            method: "importWallet", arguments: valid
        ) {
            XCTAssertEqual(method, "importWallet")
        } else {
            XCTFail("import must remain a secret-free UI request")
        }

        XCTAssertThrowsError(try CitizenSdkFlutterCodec.decode(
            method: "importWallet", arguments: valid + ["mnemonic", "password"]
        ))
    }

    func testCreateAndAddTuplesContainOnlySelections() throws {
        if case let .create(_, _, words) = try CitizenSdkFlutterCodec.decode(
            method: "createWallet",
            arguments: [NSNumber(value: 1), "session", NSNumber(value: 2), NSNumber(value: 12)]
        ) {
            XCTAssertEqual(words, 12)
        } else { XCTFail("create tuple drifted") }

        if case let .addAccounts(_, _, indices) = try CitizenSdkFlutterCodec.decode(
            method: "addWalletAccounts",
            arguments: [NSNumber(value: 1), "session", NSNumber(value: 3),
                        [NSNumber(value: 1), NSNumber(value: 2)]]
        ) {
            XCTAssertEqual(indices, [1, 2])
        } else { XCTFail("add-account tuple drifted") }
    }

    func testErrorTupleContainsOnlyStablePublicFields() {
        let tuple = CitizenSdkFlutterCodec.error(.storage, "safe failure", session: "s", sequence: 4,
                                                 method: "getStorage")
        XCTAssertEqual(tuple.count, 7)
        XCTAssertEqual(tuple[1] as? String, "s")
        XCTAssertEqual(tuple[2] as? Int64, 4)
        XCTAssertEqual(tuple[4] as? Int64, Int64(CitizenSDKFailureStage.persistence.rawValue))
        XCTAssertEqual(tuple[5] as? String, "getStorage")
        XCTAssertEqual(tuple[6] as? String, "safe failure")
    }
}
