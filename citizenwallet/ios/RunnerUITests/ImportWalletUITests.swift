import XCTest

/// 在真机核验导入页词数边界；仅输入非词表占位串，不提交有效助记词。
final class ImportWalletUITests: XCTestCase {
    func testInvalidCountAndTwentyFourWordLimit() {
        let app = XCUIApplication()
        app.launch()
        let homeAction = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "添加钱包", "导入钱包")
        ).firstMatch
        guard homeAction.waitForExistence(timeout: 30) else {
            XCTFail("钱包首页未就绪；请由设备所有者解锁应用")
            return
        }
        // 真机底部菜单把标题、副标题合并为 StaticText；空钱包首页仍是直接按钮。
        let importWallet: XCUIElement
        if homeAction.label == "添加钱包" {
            homeAction.tap()
            importWallet = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "导入钱包")
            ).firstMatch
        } else {
            importWallet = homeAction
        }
        guard importWallet.waitForExistence(timeout: 10) else { XCTFail("导入入口不可用"); return }
        importWallet.tap()

        // 录屏保护生效时必须明确失败，测试不得关闭或绕过钱包的敏感页保护。
        guard !app.staticTexts["安全提醒"].exists else { XCTFail("录屏保护已隐藏导入页"); return }
        let input = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        guard input.waitForExistence(timeout: 10) else { XCTFail("助记词输入框不可见"); return }
        input.tap()
        input.typeText("zzzz")
        app.buttons["导入钱包"].tap()
        // Flutter 提示可能并入父语义节点，按可访问标签核验实际显示内容。
        let countError = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "助记词必须为 12、18 或 24 个单词")
        ).firstMatch
        XCTAssertTrue(countError.waitForExistence(timeout: 5))

        // 第 25 个词必须被输入格式器拒绝；整个串不在 BIP-39 词表内。
        input.tap()
        input.typeText(String(repeating: " zzzz", count: 23))
        XCTAssertEqual((input.value as? String)?.split(separator: " ").count, 24)
        input.typeText(" zzzz")
        XCTAssertEqual((input.value as? String)?.split(separator: " ").count, 24)
    }
}
