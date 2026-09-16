#if UI_TEST_HOST
import UIKit

/// Xcode UI 测试协议要求测试 bundle 关联一个 App target；本隔离宿主只承载 xctrunner，
/// bundle id 与正式 CitizenApp 完全不同，测试过程不得构建、安装或覆盖 `ios.citizenapp`。
@main
final class RunnerUITestHostAppDelegate: UIResponder, UIApplicationDelegate {}
#else
import XCTest

/// 对设备中已经安装的 Release CitizenApp 做黑盒验收。
///
/// 本 target 不依赖 Runner target，也不参与目标 App 安装；它只用独立 xctrunner 启动
/// `ios.citizenapp`。因此测试失败、Runner 清理或重新运行都不得改变 CitizenApp 数据容器。
final class RunnerUITests: XCTestCase {
  private let targetBundleIdentifier = "ios.citizenapp"

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  /// 空钱包正式App必须直接启动CitizenSDK的创建/导入安全窗口；测试只检查公开初始态并取消。
  /// 已存在钱包时门禁本就不可达，只确认主导航存在，不清空真实钱包制造测试条件。
  func testWalletGateLaunchesCitizenSdkCreateAndImportWithoutSecretInput() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)

    let create = walletGateCreate(in: app)
    guard create.waitForExistence(timeout: 10) else {
      XCTAssertTrue(chatTab(in: app).waitForExistence(timeout: 20))
      return
    }
    let importing = app.buttons["已有钱包？导入助记词"]
    XCTAssertTrue(importing.exists, "空钱包门禁缺少助记词导入入口")

    create.tap()
    XCTAssertTrue(app.navigationBars["创建钱包"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.buttons["12 个助记词 · 推荐"].exists)
    XCTAssertTrue(app.buttons["24 个助记词"].exists)
    XCTAssertTrue(app.secureTextFields["钱包密码（选填）"].exists)
    XCTAssertTrue(app.buttons["创建钱包"].exists)
    XCTAssertTrue(app.buttons["取消"].firstMatch.exists)
    app.buttons["取消"].firstMatch.tap()
    XCTAssertTrue(create.waitForExistence(timeout: 10))

    importing.tap()
    XCTAssertTrue(app.navigationBars["输入助记词"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.textViews["助记词"].exists)
    XCTAssertTrue(app.secureTextFields["钱包密码（选填）"].exists)
    XCTAssertTrue(app.buttons["确认导入"].exists)
    XCTAssertTrue(app.buttons["取消"].firstMatch.exists)
    app.buttons["取消"].firstMatch.tap()
    XCTAssertTrue(create.waitForExistence(timeout: 10))
  }

  func testInstalledReleaseLaunchesAndExposesMainNavigation() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 20),
      "设备中已安装的 Release CitizenApp 未进入前台"
    )
    XCTAssertTrue(
      chatTab(in: app).waitForExistence(timeout: 20),
      "CitizenApp 未进入包含五个主导航入口的已登录界面"
    )
    attachScreenshot(app, name: "CitizenApp-主界面")
  }

  /// 长期回归门禁：聊天页必须在 30 秒内离开首帧加载状态。
  ///
  /// 本用例只验证首帧加载上界，禁止用无限转圈掩盖原生回调不返回。
  func testChatLeavesInitialLoadingWithinThirtySeconds() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let chatTab = chatTab(in: app)
    XCTAssertTrue(chatTab.waitForExistence(timeout: 20), "找不到聊天主导航入口")
    chatTab.tap()

    let chatTitle = app.staticTexts["聊天"].firstMatch
    XCTAssertTrue(chatTitle.waitForExistence(timeout: 10), "聊天页没有完成导航")

    let loading = app.staticTexts["正在读取本地会话"]
    if loading.exists {
      let finished = expectation(
        for: NSPredicate(format: "exists == false"),
        evaluatedWith: loading
      )
      let result = XCTWaiter.wait(for: [finished], timeout: 30)
      attachScreenshot(app, name: "CitizenApp-聊天页")
      XCTAssertEqual(result, .completed, "聊天页超过 30 秒仍停在本地会话加载状态")
    } else {
      attachScreenshot(app, name: "CitizenApp-聊天页")
    }
  }

  /// 广场发布文章黑盒验收：菜单必须进入新版文章编辑器，并只暴露统一媒体入口。
  func testArticleComposerExposesUnifiedMediaEntry() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let publish = app.buttons.matching(
      NSPredicate(format: "label == %@", "发布")
    ).firstMatch
    XCTAssertTrue(publish.waitForExistence(timeout: 20), "广场缺少发布按钮")
    publish.tap()

    let publishArticle = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "发布文章")
    ).firstMatch
    XCTAssertTrue(publishArticle.waitForExistence(timeout: 10), "发布圆弧缺少文章入口")
    publishArticle.tap()

    XCTAssertTrue(app.staticTexts["发文章"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["0/50"].waitForExistence(timeout: 10))
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH %@", "正文 ")
      ).firstMatch.exists
    )
    XCTAssertTrue(
      app.buttons["插入图片或视频"].exists,
      "文章编辑器没有统一图片/视频入口"
    )
    XCTAssertFalse(app.buttons["插入视频"].exists, "旧独立视频入口仍有残留")

    let addSection = app.buttons["添加图文框"]
    let cover = app.buttons["选择首图"]
    let inlineMedia = app.buttons["插入图片或视频"]
    XCTAssertTrue(addSection.exists)
    XCTAssertTrue(cover.exists)
    XCTAssertEqual(cover.frame.maxX, addSection.frame.maxX, accuracy: 1.5)
    XCTAssertEqual(inlineMedia.frame.maxX, addSection.frame.maxX, accuracy: 1.5)
    attachScreenshot(app, name: "CitizenApp-发布文章")
  }

  /// iOS 必须直接显示安装包内的完整版本，不能依赖 Android APK 更新接口。
  func testAboutDisplaysCompleteInstalledVersion() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let myTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "我的")
    ).firstMatch
    XCTAssertTrue(myTab.waitForExistence(timeout: 20), "找不到我的主导航入口")
    myTab.tap()

    let settings = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "设置")
    ).firstMatch
    XCTAssertTrue(settings.waitForExistence(timeout: 10), "我的页缺少设置入口")
    settings.tap()
    XCTAssertTrue(app.staticTexts["关于"].waitForExistence(timeout: 10))

    let version = app.descendants(matching: .any).matching(
      NSPredicate(format: "label MATCHES %@", ".*v[0-9]+\\.[0-9]+\\.[0-9]+.*")
    ).firstMatch
    attachScreenshot(app, name: "CitizenApp-iOS完整版本")
    XCTAssertTrue(version.waitForExistence(timeout: 10), "iOS 关于页未显示完整本机版本")
    XCTAssertFalse(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "v...")
      ).firstMatch.exists,
      "iOS 关于页仍显示旧占位版本"
    )
  }

  /// 治理顶部只保留白皮书与国家储委会等高双列，不再显示重复分组标题。
  func testGovernanceTopCardsAreParallelAndEqualHeight() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let citizenTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "公民")
    ).firstMatch
    XCTAssertTrue(citizenTab.waitForExistence(timeout: 20), "找不到公民主导航入口")
    citizenTab.tap()

    let governance = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "治理")
    ).firstMatch
    XCTAssertTrue(governance.waitForExistence(timeout: 10), "公民页缺少治理子 Tab")
    governance.tap()

    let whitepaper = app.staticTexts["《公民链白皮书》"]
    let nationalCouncil = app.staticTexts["国家储委会"]
    XCTAssertTrue(whitepaper.waitForExistence(timeout: 10))
    XCTAssertTrue(nationalCouncil.waitForExistence(timeout: 10))
    XCTAssertEqual(whitepaper.frame.midY, nationalCouncil.frame.midY, accuracy: 3)
    XCTAssertFalse(app.staticTexts["治理机构"].exists, "治理页仍显示重复标题")
    attachScreenshot(app, name: "CitizenApp-治理双列卡片")
  }

  /// 交易Tab必须继续显示原有公民链顶栏，并从真实CitizenSDK链状态得到非递减finalized高度。
  /// 本用例只截取不含输入值的空交易表单，绝不填写账户、金额、备注或签名内容。
  func testTransactionTabPreservesLiveChainHeaderAndEmptyPaymentForm() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let transactionTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "交易")
    ).firstMatch
    XCTAssertTrue(transactionTab.waitForExistence(timeout: 20), "找不到交易主导航入口")
    transactionTab.tap()

    let chainStatus = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "公民链", "最终区块")
    ).firstMatch
    XCTAssertTrue(chainStatus.waitForExistence(timeout: 20), "交易Tab缺少原有公民链状态顶栏")
    let finalized = expectation(
      for: NSPredicate(format: "label MATCHES %@", ".*最终区块 [0-9]+.*"),
      evaluatedWith: chainStatus
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [finalized], timeout: 120),
      .completed,
      "CitizenSDK轻节点在120秒内没有提供真实finalized高度"
    )
    let firstHeight = try XCTUnwrap(finalizedHeight(from: chainStatus.label))
    Thread.sleep(forTimeInterval: 7)
    let secondHeight = try XCTUnwrap(finalizedHeight(from: chainStatus.label))
    XCTAssertGreaterThanOrEqual(secondHeight, firstHeight, "finalized高度发生回退")

    for label in ["请输入账户", "请输入金额", "请输入转账备注（选填）"] {
      XCTAssertTrue(
        app.descendants(matching: .any).matching(
          NSPredicate(format: "label == %@", label)
        ).firstMatch.waitForExistence(timeout: 10),
        "交易Tab缺少原有空表单字段：\(label)"
      )
    }
    XCTAssertTrue(app.buttons["选择交易钱包"].exists, "交易Tab缺少原有钱包选择入口")
    attachScreenshot(app, name: "CitizenApp-交易Tab公民链状态")
  }

  /// 正式App钱包页只验收公开结构和CitizenSDK追加账户窗口的初始遮挡态。
  /// 不输入助记词/密码，不执行创建、导入、追加或私钥显示，也不截图SDK敏感窗口。
  func testWalletPagePreservesPublicSurfaceAndAvailableSdkEntry() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let myTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "我的")
    ).firstMatch
    XCTAssertTrue(myTab.waitForExistence(timeout: 20), "找不到我的主导航入口")
    myTab.tap()

    let walletEntry = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "钱包")
    ).firstMatch
    XCTAssertTrue(walletEntry.waitForExistence(timeout: 10), "我的页缺少钱包入口")
    walletEntry.tap()
    XCTAssertTrue(app.staticTexts["我的钱包"].waitForExistence(timeout: 15))

    let addEntry = app.buttons["添加账户 / 导入冷钱包"]
    let emptyWallet = app.staticTexts["还没有可展示的钱包。热钱包在首启时创建，这里可导入只读的冷钱包。"]
    XCTAssertTrue(
      addEntry.waitForExistence(timeout: 10) || emptyWallet.waitForExistence(timeout: 1),
      "钱包页既没有账户操作入口，也没有确定空态"
    )
    attachScreenshot(app, name: "CitizenApp-我的钱包公开页面")

    guard addEntry.exists && addEntry.isEnabled else { return }
    addEntry.tap()
    XCTAssertTrue(app.staticTexts["导入冷钱包"].waitForExistence(timeout: 10))
    let addNext = app.staticTexts["添加下一个账户"]
    guard addNext.exists else { return }
    addNext.tap()

    XCTAssertTrue(app.navigationBars["添加账户"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.textViews["助记词"].exists)
    XCTAssertTrue(app.secureTextFields["钱包密码（选填）"].exists)
    XCTAssertTrue(app.textFields["账户编号 1—1989，逗号分隔"].exists)
    XCTAssertTrue(app.buttons["确认添加"].exists)
    let cancel = app.buttons["取消"].firstMatch
    XCTAssertTrue(cancel.exists, "CitizenSDK追加账户窗口缺少安全取消入口")
    cancel.tap()
    XCTAssertTrue(app.staticTexts["我的钱包"].waitForExistence(timeout: 10))
  }

  /// 创作者页必须使用「我的」已持有的本地身份/会员展示态立即出首帧，
  /// 不得把 Worker 或链上读取放在路由打开的关键路径。
  func testCreatorPageDisplaysImmediatelyFromMyTab() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let myTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "我的")
    ).firstMatch
    XCTAssertTrue(myTab.waitForExistence(timeout: 20), "找不到我的主导航入口")
    myTab.tap()

    let creatorEntry = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "创作者")
    ).firstMatch
    XCTAssertTrue(creatorEntry.waitForExistence(timeout: 10), "我的页缺少创作者入口")

    creatorEntry.tap()
    let creatorSurface = app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label IN %@",
        ["我的创作者会员", "去订阅平台会员"]
      )
    ).firstMatch
    XCTAssertTrue(
      creatorSurface.waitForExistence(timeout: 1),
      "创作者页没有在 1 秒内显示本地会员或非会员结构"
    )
    XCTAssertFalse(app.staticTexts["正在连接聊天服务"].exists)
    XCTAssertFalse(app.staticTexts["同步中"].exists)
    XCTAssertFalse(app.staticTexts["状态同步中"].exists)
    XCTAssertFalse(app.staticTexts["正在同步会员档"].exists)
    attachScreenshot(app, name: "CitizenApp-创作者首帧")
  }

  private func attachScreenshot(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func finalizedHeight(from label: String) -> UInt64? {
    guard let range = label.range(of: #"最终区块 [0-9]+"#, options: .regularExpression) else {
      return nil
    }
    return UInt64(label[range].split(separator: " ").last ?? "")
  }

  private func walletGateCreate(in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label == %@", "创建钱包")).firstMatch
  }

  private func requireMainNavigation(in app: XCUIApplication) throws {
    if walletGateCreate(in: app).waitForExistence(timeout: 2) {
      throw XCTSkip("正式App尚无钱包；需由用户在CitizenSDK安全窗口直接导入测试钱包后验收主导航")
    }
    XCTAssertTrue(
      chatTab(in: app).waitForExistence(timeout: 20),
      "CitizenApp既未显示钱包门禁，也未进入五主导航"
    )
  }

  /// 首次启动的权限说明不属于创作者流程；黑盒验收只选择稍后授权，
  /// 避免触发系统弹窗，也不更改正式 App 的会员、钱包或身份数据。
  private func dismissPermissionGuideIfNeeded(in app: XCUIApplication) {
    let later = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "稍后再说")
    ).firstMatch
    if later.waitForExistence(timeout: 2) {
      later.tap()
      return
    }
    if walletGateCreate(in: app).exists { return }
    // Flutter 在部分 iOS 版本的首个 semantics frame 不会立即暴露按钮；
    // 只有主导航仍不存在时，才点击权限说明页固定的「稍后再说」位置。
    if !chatTab(in: app).exists {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.91)).tap()
    }
  }

  /// Flutter 的 NavigationDestination 在 iOS 会把“第几个 Tab”等系统语义合并进 label，
  /// 因此必须按按钮标签包含“聊天”定位，不能假定辅助功能标签精确等于可见文案。
  private func chatTab(in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "聊天")
    ).firstMatch
  }
}
#endif
