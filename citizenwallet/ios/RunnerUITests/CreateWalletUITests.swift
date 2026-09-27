import XCTest

/// 在真机已签名 Release 包上核验创建页；仅切换词数，不生成或读取助记词。
final class CreateWalletUITests: XCTestCase {
    func testWordCountSelectionAndPasswordWidth() {
        let app = XCUIApplication()
        app.launch()
        // 首页有钱包时先展开菜单，无钱包时直接使用页面按钮；设备所有者自行解锁应用。
        let homeAction = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "添加钱包", "创建钱包")
        ).firstMatch
        guard homeAction.waitForExistence(timeout: 30) else {
            XCTFail("钱包首页未就绪；请由设备所有者解锁应用")
            return
        }
        // 真机底部菜单把标题、副标题合并为 StaticText；空钱包首页仍是直接按钮。
        let create: XCUIElement
        if homeAction.label == "添加钱包" {
            homeAction.tap()
            create = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "创建钱包")
            ).firstMatch
        } else {
            create = homeAction
        }
        guard create.waitForExistence(timeout: 10) else { XCTFail("创建入口不可用"); return }
        create.tap()

        let twelve = app.buttons["12 个单词"]
        let eighteen = app.buttons["18 个单词"]
        let twentyFour = app.buttons["24 个单词"]
        guard twelve.waitForExistence(timeout: 10) else { XCTFail("词数选项不可用"); return }

        // Flutter 可把说明合并到父语义节点；在全部可访问标签中查找当前说明。
        func hasCaption(_ caption: String) -> Bool {
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", caption)
            ).firstMatch.exists
        }

        // 用三段选项的总跨度比对唯一密码输入框，不输入任何密码。
        let password = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.secureTextFields.firstMatch
        guard password.exists else { XCTFail("钱包密码输入框不可见"); return }
        let optionWidth = twentyFour.frame.maxX - twelve.frame.minX
        XCTAssertEqual(password.frame.width, optionWidth, accuracy: 2)
        guard hasCaption("128 位熵，标准安全强度") else { XCTFail("12 词说明不可见"); return }

        // Flutter 真机通过当前说明文案核对选择状态；不依赖原生分段控件选中属性。
        eighteen.tap()
        guard hasCaption("192 位熵，词数与安全性平衡") else { XCTFail("18 词说明不可见"); return }
        twentyFour.tap()
        guard hasCaption("256 位熵，安全性更高") else { XCTFail("24 词说明不可见"); return }
        twelve.tap()
        XCTAssertTrue(hasCaption("128 位熵，标准安全强度"))

    }
}
