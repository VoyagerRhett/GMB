import XCTest
@testable import CitizenSDK
@testable import CitizenSDKFlutter

@MainActor
final class CitizenSDKFlutterWalletFlowTests: XCTestCase {
    func testFlutterRequestsMapOnlyToSdkOwnedWalletFlows() throws {
        for count: UInt32 in [12, 18, 24] {
            XCTAssertEqual(
                try CitizenSdkFlutterWalletFlow.contract(for: .create(session: "s", sequence: 1, wordCount: count)),
                .create(wordCount: count)
            )
        }
        let text = ["账户角色", "授权说明", "完成说明", "备份说明", "冷账户说明"]
        XCTAssertEqual(
            try CitizenSdkFlutterWalletFlow.contract(
                for: .initialize(session: "s", sequence: 2, wordCount: 18, text: text)
            ),
            .initialize(
                wordCount: 18,
                content: CitizenSDKWalletInitializationContent(
                    walletAccountRoleText: text[0], walletAuthorizationText: text[1],
                    walletCompletionText: text[2], walletBackupText: text[3],
                    walletColdAccountText: text[4]
                )
            )
        )
        XCTAssertEqual(
            try CitizenSdkFlutterWalletFlow.contract(
                for: .importColdAccountWithUI(session: "s", sequence: 3, text: "只接受账户码")
            ),
            .importColdAccount(walletColdAccountText: "只接受账户码")
        )
        XCTAssertEqual(
            try CitizenSdkFlutterWalletFlow.contract(for: .empty(method: "importWallet", session: "s", sequence: 4)),
            .importWallet
        )
        XCTAssertEqual(
            try CitizenSdkFlutterWalletFlow.contract(for: .addAccounts(session: "s", sequence: 5, indices: [1, 2])),
            .addAccounts(indices: [1, 2])
        )
    }

    func testNonWalletRequestCannotOpenSecretUi() {
        XCTAssertThrowsError(try CitizenSdkFlutterWalletFlow.contract(
            for: .empty(method: "start", session: "s", sequence: 1)
        )) { error in
            XCTAssertEqual((error as? CitizenSDKError)?.code, .invalidArgument)
        }
    }
}
