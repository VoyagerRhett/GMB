#if UI_TEST_HOST
import UIKit

/// Xcode UI 测试协议要求测试 bundle 关联一个 App target；本隔离宿主只承载 xctrunner，
/// bundle id 与正式 CitizenApp 完全不同，测试过程不得构建、安装或覆盖 `ios.citizenapp`。
@main
final class RunnerUITestHostAppDelegate: UIResponder, UIApplicationDelegate {}
#else
import XCTest
import UIKit

/// 对设备中已经安装的 Release CitizenApp 做黑盒验收。
///
/// 本 target 不依赖 Runner target，也不参与目标 App 安装；它只用独立 xctrunner 启动
/// `ios.citizenapp`。因此测试失败、Runner 清理或重新运行都不得改变 CitizenApp 数据容器。
final class RunnerUITests: XCTestCase {
  private let targetBundleIdentifier = "ios.citizenapp"


  /// 测试只打开空输入面板并结束；真实助记词和设备认证由用户在测试结束后填写。
  func testOpenAddNextAccount() throws { try openAddAccount("添加下一个账户", stage: "next") }
  func testOpenAddSpecifiedAccount() throws { try openAddAccount("添加指定账户", stage: "specified") }

  private func openAddAccount(_ mode: String, stage: String) throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)
    let my = app.buttons.matching(NSPredicate(format:
      "label CONTAINS %@ AND NOT (label CONTAINS %@)", "我的", "我的通讯录")).firstMatch
    XCTAssertTrue(my.waitForExistence(timeout: 10))
    my.tap()
    let wallet = app.descendants(matching: .any).matching(NSPredicate(format:
      "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@)", "钱包", "钱包", "管理账户")).firstMatch
    XCTAssertTrue(wallet.waitForExistence(timeout: 10))
    wallet.tap()
    let add = app.buttons.matching(NSPredicate(format: "label == %@", "添加账户 / 导入冷钱包")).firstMatch
    XCTAssertTrue(add.waitForExistence(timeout: 10))
    add.tap()
    let choice = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", mode)).firstMatch
    XCTAssertTrue(choice.waitForExistence(timeout: 10))
    choice.tap()
    let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "确认添加")).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 10))
    NSLog("WALLET_APPEND_UI stage=%@ form_ready=1", stage)
  }

  /// 身份展示验收只比较本机内存中的公民号文本，日志仅记录固定步骤和布尔结果。
  func testIdentityLocalDisplayAndRefresh() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    func exact(_ label: String) -> XCUIElement {
      app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    func openIdentity() throws {
      dismissPermissionGuideIfNeeded(in: app)
      try requireMainNavigation(in: app)
      let my = app.buttons.matching(NSPredicate(format:
        "label CONTAINS %@ AND NOT (label CONTAINS %@)", "我的", "我的通讯录")).firstMatch
      XCTAssertTrue(my.waitForExistence(timeout: 10))
      my.tap()
      let entry = app.descendants(matching: .any).matching(NSPredicate(format:
        "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@)", "身份", "身份", "注册与查看")).firstMatch
      XCTAssertTrue(entry.waitForExistence(timeout: 10))
      entry.tap()
      XCTAssertTrue(exact("身份").waitForExistence(timeout: 10))
    }
    func cidLabel() -> String? {
      // 必须取实际号码所在行，不能把空卡片的“公民号”标题误当成持久化数据。
      let fields = app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "公民号")).allElementsBoundByIndex
      for field in fields {
        let lines = field.label.components(separatedBy: .newlines)
        for index in lines.indices where lines[index] == "公民号" && index + 1 < lines.count {
          let value = lines[index + 1]
          if value.rangeOfCharacter(from: .decimalDigits) != nil { return value }
        }
      }
      return nil
    }
    app.launch()
    try openIdentity()
    // 升级后首次没有完整本地快照时，允许显式刷新建立快照；普通进入不能代替用户刷新。
    let hadLocal = cidLabel() != nil
    NSLog("IDENTITY_UI stage=initial cached=%d", hadLocal ? 1 : 0)
    if !hadLocal {
      let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
      let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
      start.press(forDuration: 0.1, thenDragTo: end)
      let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in cidLabel() != nil }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 60), .completed, "显式刷新后应显示实际公民号")
    }
    let before = cidLabel()
    XCTAssertNotNil(before, "必须读取实际公民号后再比较持久化")
    NSLog("IDENTITY_UI stage=local cid_visible=%d", before == nil ? 0 : 1)
    let back = app.buttons.matching(NSPredicate(format: "label IN %@", ["返回", "Back"])).firstMatch
    XCTAssertTrue(back.exists)
    back.tap()
    // 返回“我的”后重新打开；不进入注册、换绑或发布动作。
    let entry = app.descendants(matching: .any).matching(NSPredicate(format:
      "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@)", "身份", "身份", "注册与查看")).firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 5))
    entry.tap()
    XCTAssertTrue(cidLabel() == before, "重进应复用已保存身份")
    NSLog("IDENTITY_UI stage=reenter unchanged=1")
    app.terminate()
    app.launch()
    try openIdentity()
    XCTAssertTrue(cidLabel() == before, "重启后应恢复已保存身份")
    NSLog("IDENTITY_UI stage=relaunch unchanged=1")
    // 只主动刷新公开身份，不触发交易或发布。
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
    start.press(forDuration: 0.1, thenDragTo: end)
    XCTAssertTrue(cidLabel() != nil, "刷新期间仍应保留公民号")
    NSLog("IDENTITY_UI stage=refresh retained=1")
  }

  /// 收款回归只读取方向是否存在；不输出金额、地址、备注或交易身份，不附加画面。
  func testWalletAndTransactionHistoryContainIncomingRecords() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)
    func exact(_ label: String) -> XCUIElement {
      app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    func back() {
      let button = app.buttons.matching(NSPredicate(format: "label IN %@", ["返回", "Back"])).firstMatch
      XCTAssertTrue(button.waitForExistence(timeout: 5))
      button.tap()
    }
    func hasIncome(_ stage: String) -> Bool {
      XCTAssertTrue(exact("交易记录").waitForExistence(timeout: 10))
      let income = app.descendants(matching: .any).matching(
        NSPredicate(format: "label MATCHES %@", #"(?s).*\+[0-9][0-9,]*\.[0-9]{2}.*"#)).firstMatch
      // 补齐是后台任务；以真实列表收到记录为条件，不把固定等待当成成功。
      let present = income.waitForExistence(timeout: 60)
      NSLog("HISTORY_UI stage=%@ incoming=%d", stage, present ? 1 : 0)
      return present
    }
    let transaction = app.buttons.matching(NSPredicate(format:
      "label CONTAINS %@ AND NOT (label CONTAINS %@)", "交易", "选择交易钱包")).firstMatch
    XCTAssertTrue(transaction.waitForExistence(timeout: 20))
    transaction.tap()
    // Flutter 把三个状态与表单合并为同一个语义节点，不存在独立“失败”节点。
    let status = app.descendants(matching: .any).matching(NSPredicate(format:
      "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
      "待确认", "已确认", "失败")).firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 15))
    let frame = status.frame
    app.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: app.frame.maxX - app.frame.width * 0.122,
        dy: frame.maxY - app.frame.width * 0.074)).tap()
    let transactionHasIncome = hasIncome("transaction")
    back()
    let my = app.buttons.matching(NSPredicate(format:
      "label CONTAINS %@ AND NOT (label CONTAINS %@)", "我的", "我的通讯录")).firstMatch
    XCTAssertTrue(my.waitForExistence(timeout: 10))
    my.tap()
    let wallet = app.descendants(matching: .any).matching(NSPredicate(format:
      "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@)", "钱包", "钱包", "管理账户")).firstMatch
    XCTAssertTrue(wallet.waitForExistence(timeout: 10))
    wallet.tap()
    XCTAssertTrue(exact("我的钱包").waitForExistence(timeout: 10))
    // “我的钱包”热账户卡由账户操作按钮定位；钱包选择页才有 wallet-hot-row。
    let accountMenu = app.buttons["账户操作"].firstMatch
    XCTAssertTrue(accountMenu.waitForExistence(timeout: 10))
    app.coordinate(withNormalizedOffset: .zero).withOffset(
      CGVector(dx: app.frame.width * 0.4, dy: accountMenu.frame.midY)).tap()
    let history = exact("交易记录")
    if !history.isHittable { app.swipeUp() }
    XCTAssertTrue(history.waitForExistence(timeout: 10))
    history.tap()
    let walletHasIncome = hasIncome("wallet")
    back()
    XCTAssertTrue(transactionHasIncome, "交易入口未显示收入，需核对恢复进度或账户前置条件")
    XCTAssertTrue(walletHasIncome, "钱包入口未显示收入，需核对恢复进度或账户前置条件")
  }

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

  /// 只读实网观察：只提取公开最终块高度及连接标志，不读取表单、不截图、不发交易。
  /// 界面没有 best，不能用此测试单独推断手机进程内 best == finalized。
  func testChainStatusReadOnlyObservation() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)
    let transactionTab = app.buttons.matching(NSPredicate(format:
      "label CONTAINS %@ AND NOT (label CONTAINS %@)", "交易", "选择交易钱包")).firstMatch
    XCTAssertTrue(transactionTab.waitForExistence(timeout: 20), "交易主导航不可读")
    transactionTab.tap()
    let chainStatus = app.descendants(matching: .any).matching(NSPredicate(format:
      "label BEGINSWITH %@ AND label CONTAINS %@", "公民链", "最终区块")).firstMatch
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      chainStatus.exists && chainStatus.label.contains("连接正常") &&
        self.finalizedHeight(from: chainStatus.label) != nil
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 60), .completed, "真实链状态未就绪")
    let start = Date()
    var previous: UInt64?
    for _ in 0..<12 {
      let label = chainStatus.label
      let height = try XCTUnwrap(finalizedHeight(from: label), "最终块高度不可读")
      let connected = label.contains("连接正常")
      NSLog("CHAIN_OBSERVATION elapsed_s=%.1f finalized=%llu connected=%d",
        Date().timeIntervalSince(start), height, connected ? 1 : 0)
      XCTAssertTrue(connected, "采样期间链连接不可用")
      if let previous { XCTAssertGreaterThanOrEqual(height, previous, "最终块高度回退") }
      previous = height
      Thread.sleep(forTimeInterval: 3)
    }
  }

  /// 只用于用户当场确认的一次真机交易诊断；测试绝不点击最终“确认”。
  /// 由 App 自身校验已填表单；不读取输入值、不截图、不记录交易标识。
  func testUserConfirmedTransferDiagnostic() throws {
    guard ProcessInfo.processInfo.environment["CITIZENAPP_TRANSFER_DIAGNOSTIC"] == "1" else {
      throw XCTSkip("真实交易诊断只允许在用户当场确认的定向测试中启用")
    }
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.activate()
    guard app.wait(for: .runningForeground, timeout: 20) else {
      NSLog("TRANSFER_DIAG stage=app_unavailable")
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    // 前台进程存在不代表 Flutter 首屏已准备完毕；等待已知路由，避免在启动帧
    // 查到短暂导航后立刻点击失效元素，也不能将启动帧误判为未知二级页面。
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      app.buttons["签名交易"].exists ||
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "交易")).count > 0 ||
        app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@",
          ["选择交易钱包", "我的钱包", "钱包详情", "账户详情"])).count > 0
    }, object: nil)
    guard XCTWaiter.wait(for: [ready], timeout: 30) == .completed else {
      NSLog("TRANSFER_DIAG stage=route_not_ready")
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    let keyboardDone = app.keyboards.buttons["完成"].firstMatch
    if keyboardDone.exists { keyboardDone.tap() }
    let sign = app.buttons["签名交易"]
    let knownLabels = ["确认交易", "确认", "取消", "稍后再说", "创建钱包", "交易", "签名交易", "我的", "聊天", "扫码失败"]
    for label in knownLabels {
      let count = app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", label)
      ).count
      if count > 0 { NSLog("TRANSFER_DIAG stage=known_label kind=%@ count=%d", label, count) }
    }
    NSLog("TRANSFER_DIAG stage=element_count all=%d buttons=%d static=%d other=%d alerts=%d",
          app.descendants(matching: .any).count, app.buttons.count, app.staticTexts.count,
          app.otherElements.count, app.alerts.count)
    let transactionTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "交易")
    ).firstMatch
    // 钱包选择页是 Flutter 路由，返回按钮不属于 UIKit navigationBars。
    // 只在标题准确且页面仅有一个按钮时点击，避免误触钱包或交易确认。
    let walletPickerTitle = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "选择交易钱包")
    ).firstMatch
    if walletPickerTitle.exists && app.buttons.count == 1 {
      NSLog("TRANSFER_DIAG stage=return_from_wallet_picker")
      app.buttons.firstMatch.tap()
    } else if !sign.exists && !transactionTab.exists {
      NSLog("TRANSFER_DIAG stage=unknown_nested_page")
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    NSLog("TRANSFER_DIAG stage=surface sign=%d tab=%d keyboard=%d",
          sign.exists ? 1 : 0, transactionTab.exists ? 1 : 0, app.keyboards.count > 0 ? 1 : 0)
    if !sign.exists {
      if transactionTab.exists {
        // Flutter 重建语义树时，按钮惰性查询在 tap 阶段可能失效；使用同次命中的
        // 可见按钮矩形生成 XCTest 坐标，禁止猜坐标或回退点击其他控件。
        let frame = transactionTab.frame
        guard !frame.isEmpty, app.frame.contains(frame) else {
          NSLog("TRANSFER_DIAG stage=transaction_tab_frame_unavailable")
          throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
        }
        app.coordinate(withNormalizedOffset: .zero)
          .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
      }
    }

    // 指标位于表单下方；基线必须全部读到，否则不能把旧交易误认成本次结果。
    app.swipeUp()
    guard let initialPending = transactionCount("待确认", in: app),
          let initialConfirmed = transactionCount("已确认", in: app),
          let initialFailed = transactionCount("失败", in: app) else {
      NSLog("TRANSFER_DIAG stage=baseline_missing")
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    app.swipeDown()
    guard sign.waitForExistence(timeout: 20) else {
      NSLog("TRANSFER_DIAG stage=sign_button_missing tab=%d keyboard=%d",
            transactionTab.exists ? 1 : 0, app.keyboards.count > 0 ? 1 : 0)
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: sign)
    guard XCTWaiter.wait(for: [enabled], timeout: 120) == .completed else {
      NSLog("TRANSFER_DIAG stage=sign_button_disabled")
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    let startedAt = Date()
    NSLog("TRANSFER_DIAG stage=form_ready t=0 pending=%d confirmed=%d failed=%d",
          initialPending, initialConfirmed, initialFailed)
    sign.tap()

    let dialog = app.staticTexts["确认交易"]
    // 余额证明读取有网络等待；观察器必须覆盖该等待，缺失时明确失败。
    guard dialog.waitForExistence(timeout: 120) else {
      NSLog("TRANSFER_DIAG stage=confirmation_not_shown t=%.1f", Date().timeIntervalSince(startedAt))
      for phrase in ["请输入收款地址", "请输入金额", "金额必须大于", "余额不足"] {
        let visible = app.descendants(matching: .any).matching(
          NSPredicate(format: "label CONTAINS %@", phrase)).count > 0
        if visible { NSLog("TRANSFER_DIAG stage=form_validation kind=%@", phrase) }
      }
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    let confirm = app.buttons["确认"].firstMatch
    guard confirm.exists else {
      NSLog("TRANSFER_DIAG stage=confirm_button_missing t=%.1f", Date().timeIntervalSince(startedAt))
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    NSLog("TRANSFER_DIAG stage=awaiting_owner t=%.1f", Date().timeIntervalSince(startedAt))
    let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: dialog)
    guard XCTWaiter.wait(for: [closed], timeout: 300) == .completed else {
      NSLog("TRANSFER_DIAG stage=owner_did_not_confirm")
      throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
    }
    NSLog("TRANSFER_DIAG stage=dialog_closed t=%.1f", Date().timeIntervalSince(startedAt))

    var lastState = "initial"
    var sawConfirmed = false
    var observedFailure = false
    var firstConfirmedAt: Date?
    var scrolledToHistory = false
    let deadline = Date().addingTimeInterval(120)
    while Date() < deadline {
      // 先读提示再滚动，避免滑动操作耗时掩盖短暂拒绝提示；原始语义仅在内存存在。
      let phrases = ["待确认", "已确认", "失败", "签名中", "交易池已拒绝", "交易已完成", "交易已最终失败", "交易发送失败", "交易准备失败", "交易执行失败", "交易异常"]
      let predicate = NSCompoundPredicate(orPredicateWithSubpredicates:
        phrases.map { NSPredicate(format: "label CONTAINS %@", $0) })
      let labels = app.descendants(matching: .any).matching(predicate)
        .allElementsBoundByIndex.map { $0.label }
      let pending = transactionCount("待确认", labels: labels)
      let confirmed = transactionCount("已确认", labels: labels)
      let failed = transactionCount("失败", labels: labels)
      let busy = labels.contains { $0.contains("签名中") }
      let notices = [
        ("pool_rejected", "交易池已拒绝"), ("finalized_success", "交易已完成"),
        ("finalized_failure", "交易已最终失败"), ("send_failure", "交易发送失败"),
        ("prepare_failure", "交易准备失败"), ("execute_failure", "交易执行失败"),
        ("unexpected_failure", "交易异常"),
      ].filter { item in labels.contains { $0.contains(item.1) } }.map { $0.0 }
      if let failed, failed > initialFailed { observedFailure = true }
      if notices.contains("pool_rejected") || notices.contains("finalized_failure") { observedFailure = true }
      // 指标不可见必须明确记为不可读，禁止用基线伪造当前数量。
      let state = "pending=\(pending.map { String($0 - initialPending) } ?? "unreadable"),confirmed=\(confirmed.map { String($0 - initialConfirmed) } ?? "unreadable"),failed=\(failed.map { String($0 - initialFailed) } ?? "unreadable"),busy=\(busy ? 1 : 0),notice=\(notices.isEmpty ? "none" : notices.joined(separator: "+"))"
      if state != lastState {
        NSLog("TRANSFER_DIAG stage=history t=%.1f %@", Date().timeIntervalSince(startedAt), state)
        lastState = state
      }
      if let confirmed, confirmed > initialConfirmed, !sawConfirmed {
        sawConfirmed = true
        firstConfirmedAt = Date()
        NSLog("TRANSFER_DIAG stage=finalized t=%.1f", Date().timeIntervalSince(startedAt))
      }
      // 确认后继续观察十秒，保留终态是否反复变化的证据。
      if let firstConfirmedAt, Date().timeIntervalSince(firstConfirmedAt) >= 10 {
        NSLog("TRANSFER_DIAG stage=observation_complete t=%.1f", Date().timeIntervalSince(startedAt))
        XCTAssertFalse(observedFailure, "交易观察期间出现失败分类或拒绝提示")
        return
      }
      if !scrolledToHistory {
        app.swipeUp()
        scrolledToHistory = true
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    NSLog("TRANSFER_DIAG stage=not_finalized_within_120s")
    throw NSError(domain: "CitizenAppTransferObservationIncomplete", code: 1)
  }

  /// 三处余额的正式包验收：金额只在内存比较，日志仅输出固定步骤与布尔结果。
  /// 不选择新的付款钱包、不触发交易，不附加截图或暴露账户行的原始语义。
  func testWalletBalanceSurfacesReadPersistedValues() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    // 本用例在用户交易观察完成后独立执行，重启以验证持久化并从准确主导航开始。
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

    func tapObserved(_ element: XCUIElement) -> Bool {
      guard element.waitForExistence(timeout: 10) else { return false }
      let frame = element.frame
      let visibleFrame = frame.intersection(app.frame)
      guard !visibleFrame.isEmpty, !visibleFrame.isNull else {
        NSLog("BALANCE_DIAG stage=frame_unavailable x=%.1f y=%.1f width=%.1f height=%.1f app_width=%.1f app_height=%.1f keyboard=%d",
          frame.minX, frame.minY, frame.width, frame.height, app.frame.width, app.frame.height, app.keyboards.count)
        return false
      }
      app.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: visibleFrame.midX, dy: visibleFrame.midY)).tap()
      return true
    }
    func exact(_ text: String) -> XCUIElement {
      app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }
    func back() -> Bool {
      tapObserved(app.buttons.matching(NSPredicate(format: "label IN %@", ["返回", "Back"])).firstMatch)
    }
    func tab(_ label: String) -> XCUIElement? {
      // 排除同词二级入口后要求唯一主Tab；保留惰性查询，不保存会随Flutter重建漂移的列表索引。
      let candidates = app.buttons.matching(NSPredicate(format:
        "label CONTAINS %@ AND NOT (label CONTAINS %@) AND NOT (label CONTAINS %@)",
        label, "我的通讯录", "选择交易钱包"))
      let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        candidates.count == 1
      }, object: nil)
      return XCTWaiter.wait(for: [ready], timeout: 10) == .completed ? candidates.firstMatch : nil
    }
    func decimal(in text: String) -> String? {
      guard let regex = try? NSRegularExpression(pattern: #"[0-9][0-9,]*\.[0-9]{2}"#),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
            let range = Range(match.range, in: text) else { return nil }
      return String(text[range])
    }
    func availableBalance() -> String? {
      let value = app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "钱包可用余额：")).firstMatch
      guard value.waitForExistence(timeout: 15) else { return nil }
      let parts = value.label.components(separatedBy: "钱包可用余额：")
      return parts.count > 1 ? decimal(in: parts[1]) : nil
    }
    func totalBalance() -> String? {
      // 热钱包进入“账户详情”，total显示在“充值”列；冷钱包才使用“链上余额”标题。
      // 已有余额必须在详情出现后直接可读；只检查该列，不轮询金额等待网络补齐。
      for title in ["充值", "链上余额"] {
          let header = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", title)).firstMatch
          guard header.exists else { continue }
          let parts = header.label.components(separatedBy: title)
          if parts.count > 1, let value = decimal(in: parts[1]) {
            return value
          }
          let titleFrame = header.frame
          let values = app.descendants(matching: .any).matching(
            NSPredicate(format: "label MATCHES %@", #"[0-9][0-9,]*\.[0-9]{2}(\s*元)?"#))
            .allElementsBoundByIndex.filter {
              $0.frame.midY > titleFrame.midY &&
              $0.frame.midY - titleFrame.midY < 100 &&
              abs($0.frame.midX - titleFrame.midX) < 50
            }.sorted { $0.frame.midY < $1.frame.midY }
          if let label = values.first?.label, let value = decimal(in: label) {
            return value
          }
      }
      return nil
    }
    func rowBalance(_ row: XCUIElement) -> String? {
      // Flutter 在 iOS 上把有独立标识的金额暴露为并列节点。按实际钱包行矩形
      // 定位唯一金额，不假设无障碍父子关系，不输出金额或用金额构造查询。
      let frame = row.frame
      let values = app.descendants(matching: .any).matching(identifier: "wallet-balance")
        .allElementsBoundByIndex.filter { frame.contains($0.frame) }
      guard values.count == 1 else {
        NSLog("BALANCE_DIAG stage=row_balance_nodes count=%d", values.count)
        return nil
      }
      return decimal(in: values[0].label)
    }
    func waitForDetail() -> Bool {
      app.descendants(matching: .any).matching(NSPredicate(format:
        "label IN %@", ["账户详情", "钱包详情"])).firstMatch.waitForExistence(timeout: 10)
    }

    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "交易"))
      .firstMatch.waitForExistence(timeout: 20))
    XCTAssertTrue(tapObserved(try XCTUnwrap(tab("交易"), "交易Tab不可读")))
    let free = try XCTUnwrap(availableBalance(), "交易余额不可读")
    NSLog("BALANCE_DIAG stage=transaction_available present=1")
    for visit in 0..<2 {
      XCTAssertTrue(tapObserved(app.buttons["选择交易钱包"]))
      XCTAssertTrue(exact("选择交易钱包").waitForExistence(timeout: 10))
      // 只等待钱包行出现；行出现时已有余额必须可读，禁止等待链查询后才判通过。
      let walletRows = app.descendants(matching: .any).matching(NSPredicate(format:
        "identifier IN %@", ["wallet-hot-row", "wallet-cold-row"]))
      XCTAssertTrue(walletRows.firstMatch.waitForExistence(timeout: 10))
      // 钱包行出现后立即读取固定余额节点；不轮询金额，也不把 XCTest 语义查询耗时
      // 当成网络加载耗时。一秒 predicate 等待会在实际相等时仍因查询调度超时报失败。
      let amounts = app.descendants(matching: .any).matching(identifier: "wallet-balance")
        .allElementsBoundByIndex.compactMap { decimal(in: $0.label) }
      let matching = amounts.contains(free)
      NSLog("BALANCE_DIAG stage=picker_rows count=%d matched=%d", amounts.count, matching ? 1 : 0)
      // 只断言布尔结果，禁止XCTAssertEqual将真实金额写入失败消息。
      XCTAssertTrue(matching, "钱包选择页未显示交易余额")
      NSLog("BALANCE_DIAG stage=picker visit=%d matched=1", visit)
      XCTAssertTrue(back())
      XCTAssertTrue(availableBalance() == free, "返回交易页余额不一致")
    }
    XCTAssertTrue(tapObserved(try XCTUnwrap(tab("我的"), "我的Tab不可读")))
    NSLog("BALANCE_DIAG stage=my_tab")
    // 入口的标题与副标题可能合并为一个Flutter语义节点。
    XCTAssertTrue(tapObserved(app.descendants(matching: .any).matching(NSPredicate(format:
      "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@)", "钱包", "钱包", "管理账户")).firstMatch))
    NSLog("BALANCE_DIAG stage=wallet_list")
    XCTAssertTrue(exact("我的钱包").waitForExistence(timeout: 15))
    let defaultRow = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "默认")).firstMatch
    // 冷钱包使用固定类型标识定位，读取金额仅留在内存，不打印真实行内容。
    let coldRow = app.descendants(matching: .any).matching(identifier: "wallet-cold-row").firstMatch
    XCTAssertTrue(coldRow.waitForExistence(timeout: 10), "缺少本次冷钱包余额验收前置条件")
    let coldAmount = try XCTUnwrap(rowBalance(coldRow), "冷钱包卡片首次出现时余额不可读")
    XCTAssertTrue(tapObserved(coldRow))
    XCTAssertTrue(waitForDetail())
    let coldTotal = try XCTUnwrap(totalBalance(), "冷钱包详情已有余额不可读")
    XCTAssertTrue(back())
    XCTAssertTrue(exact("我的钱包").waitForExistence(timeout: 10))
    XCTAssertTrue(rowBalance(coldRow) == coldAmount, "冷钱包列表重进余额不一致")
    XCTAssertTrue(tapObserved(coldRow))
    XCTAssertTrue(waitForDetail())
    XCTAssertTrue(totalBalance() == coldTotal, "冷钱包详情重进余额不一致")
    XCTAssertTrue(back())
    XCTAssertTrue(exact("我的钱包").waitForExistence(timeout: 10))
    NSLog("BALANCE_DIAG stage=cold_wallet_reentry matched=1")
    XCTAssertTrue(tapObserved(defaultRow))
    XCTAssertTrue(waitForDetail())
    let total = try XCTUnwrap(totalBalance(), "充值区域链上余额不可读")
    NSLog("BALANCE_DIAG stage=wallet_total present=1")
    XCTAssertTrue(back())
    XCTAssertTrue(exact("我的钱包").waitForExistence(timeout: 10))
    XCTAssertTrue(tapObserved(defaultRow))
    XCTAssertTrue(waitForDetail())
    XCTAssertTrue(totalBalance() == total, "钱包详情重进余额不一致")
    NSLog("BALANCE_DIAG stage=wallet_reentry matched=1")
    XCTAssertTrue(back())
    // 每次返回先确认准确目标页，避免Flutter转场未结束时连续点中同一个返回按钮。
    XCTAssertTrue(exact("我的钱包").waitForExistence(timeout: 10))
    XCTAssertTrue(back())
    XCTAssertTrue(tapObserved(try XCTUnwrap(tab("交易"), "交易Tab不可读")))
    XCTAssertTrue(availableBalance() == free, "交易Tab重进余额不一致")
    // 重启正式App验证落盘读取；不继承原生诊断环境，不触发新的交易。
    app.launch()
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "交易"))
      .firstMatch.waitForExistence(timeout: 20))
    XCTAssertTrue(tapObserved(try XCTUnwrap(tab("交易"), "重启后交易Tab不可读")))
    XCTAssertTrue(availableBalance() == free, "重启后交易余额不一致")
    NSLog("BALANCE_DIAG stage=relaunch matched=1")
    NSLog("BALANCE_DIAG stage=completed")
  }

  /// 只读取固定状态名后面的整数；不得枚举或输出交易记录的其他语义值。
  private func transactionCount(_ status: String, in app: XCUIApplication) -> Int? {
    let candidates = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", status)
    )
    return transactionCount(status, labels: (0..<min(candidates.count, 12)).map {
      candidates.element(boundBy: $0).label
    })
  }

  /// 同一次采样复用内存语义，避免分别查询三态造成额外采样间隔。
  private func transactionCount(_ status: String, labels: [String]) -> Int? {
    let pattern = NSRegularExpression.escapedPattern(for: status) + #"\s+([0-9]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    for label in labels {
      let fullRange = NSRange(label.startIndex..<label.endIndex, in: label)
      guard let match = regex.firstMatch(in: label, range: fullRange),
            let range = Range(match.range(at: 1), in: label),
            let count = Int(label[range]) else { continue }
      return count
    }
    return nil
  }

  /// 已结束交易的只读回读：仅输出三类状态数量和固定提示是否存在，不再触发签名或广播。
  func testTransferStatusReadOnlyDiagnostic() throws {
    guard ProcessInfo.processInfo.environment["CITIZENAPP_TRANSFER_DIAGNOSTIC"] == "1" else {
      throw XCTSkip("真实交易诊断只允许在用户当场确认的定向测试中启用")
    }
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    // 仅在诊断包更新后的定向验收重启一次，后续交易用例继续复用原进程和表单。
    if ProcessInfo.processInfo.environment["CITIZENAPP_RELAUNCH_DIAGNOSTIC"] == "1" {
      app.launchEnvironment["CITIZENSDK_TRANSACTION_DIAGNOSTICS"] = "1"
      app.launch()
    } else {
      app.activate()
    }
    guard app.wait(for: .runningForeground, timeout: 20) else {
      NSLog("TRANSFER_READBACK stage=app_unavailable")
      return
    }
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      app.buttons["重试"].exists || app.buttons["签名交易"].exists ||
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "交易")).count > 0
    }, object: nil)
    _ = XCTWaiter.wait(for: [ready], timeout: 30)
    // 标题白名单来自产品源码固定文案，只回报序号；未知标签和用户内容永不输出。
    let allowedTitles = (ProcessInfo.processInfo.environment["CITIZENAPP_DIAGNOSTIC_TITLES"] ?? "")
      .components(separatedBy: "\n").filter { !$0.isEmpty }
    let titlePredicate = NSCompoundPredicate(orPredicateWithSubpredicates:
      allowedTitles.map { NSPredicate(format: "label CONTAINS %@", $0) })
    let visibleLabels = app.descendants(matching: .any).matching(titlePredicate)
      .allElementsBoundByIndex.map { $0.label }
    for (index, title) in allowedTitles.enumerated() {
      if visibleLabels.contains(where: { $0.contains(title) }) {
        NSLog("TRANSFER_READBACK title_index=%d", index)
      }
    }
    if let regex = try? NSRegularExpression(pattern: #"CitizenSdkException\(([A-Za-z]+)(?:/([A-Za-z]+))?(?:@([A-Za-z]+))?"#) {
      for label in visibleLabels {
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        if let match = regex.firstMatch(in: label, range: range),
           let code = Range(match.range(at: 1), in: label) {
          NSLog("TRANSFER_READBACK sdk_code=%@", String(label[code]))
          for (index, name) in [(2, "stage"), (3, "method")] {
            if let range = Range(match.range(at: index), in: label) {
              NSLog("TRANSFER_READBACK sdk_%@=%@", name, String(label[range]))
            }
          }
        }
      }
    }
    if visibleLabels.contains(where: { $0.hasPrefix("本地钱包读取失败") }),
       app.buttons.count == 1, app.buttons["重试"].exists {
      NSLog("TRANSFER_READBACK stage=retry_wallet_gate")
      app.buttons["重试"].tap()
      _ = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "交易"))
        .firstMatch.waitForExistence(timeout: 20)
    }
    let walletPickerTitle = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "选择交易钱包")
    ).firstMatch
    if walletPickerTitle.exists && app.buttons.count == 1 {
      app.buttons.firstMatch.tap()
      NSLog("TRANSFER_READBACK stage=return_from_wallet_picker")
    }
    let transactionTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "交易")
    ).firstMatch
    if !app.buttons["签名交易"].exists && transactionTab.exists {
      transactionTab.tap()
      NSLog("TRANSFER_READBACK stage=open_transaction_tab")
    }
    // 三态指标在签名按钮下方；XCTest 只枚举可见无障碍元素，先滚到卡片底部。
    app.swipeUp()
    NSLog("TRANSFER_READBACK stage=surface all=%d buttons=%d static=%d",
          app.descendants(matching: .any).count, app.buttons.count, app.staticTexts.count)
    NSLog("TRANSFER_READBACK stage=controls sign=%d tab=%d picker=%d",
          app.buttons["签名交易"].exists ? 1 : 0, transactionTab.exists ? 1 : 0,
          walletPickerTitle.exists ? 1 : 0)
    for status in ["待确认", "已确认", "失败"] {
      let candidates = app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", status)
      ).count
      NSLog("TRANSFER_READBACK metric_candidates=%@ count=%d", status, candidates)
      if let count = transactionCount(status, in: app) {
        NSLog("TRANSFER_READBACK metric=%@ count=%d", status, count)
      } else {
        NSLog("TRANSFER_READBACK metric=%@ absent=1", status)
      }
    }
    for (kind, phrase) in [
      ("pool_rejected", "交易池已拒绝"),
      ("finalized_success", "交易已完成"),
      ("finalized_failure", "交易已最终失败"),
      ("send_failure", "交易发送失败"),
    ] {
      let visible = app.descendants(matching: .any).matching(
        NSPredicate(format: "label BEGINSWITH %@", phrase)
      ).firstMatch.exists
      NSLog("TRANSFER_READBACK notice=%@ visible=%d", kind, visible ? 1 : 0)
    }
  }

  /// 真机首进扫码页必须持续收到摄像预览；仅在内存比较扫码框中心像素，绝不保存画面。
  /// 临时提示可能在 XCTest 的 tap 返回前消失，因此以白屏和连续帧作为验收依据。
  func testTransactionScannerFirstEntryKeepsLivePreview() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let transactionTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@", "交易")
    ).firstMatch
    XCTAssertTrue(transactionTab.waitForExistence(timeout: 20))
    transactionTab.tap()

    let scanButton = app.buttons["扫码填入收款地址"]
    XCTAssertTrue(scanButton.waitForExistence(timeout: 10))
    scanButton.tap()
    try assertLiveScannerPreview(in: app, title: "扫码填入收款地址")

    // 同一引擎第二次进入仍须可用，防止首个纹理释放遗漏。
    // 扫码页为 Flutter 路由，返回控件属于语义树，不是 UIKit UINavigationBar。
    let backButton = app.buttons.matching(
      NSPredicate(format: "label IN %@", ["返回", "Back"])).firstMatch
    XCTAssertTrue(backButton.waitForExistence(timeout: 10))
    backButton.tap()
    XCTAssertTrue(scanButton.waitForExistence(timeout: 10))
    scanButton.tap()
    try assertLiveScannerPreview(in: app, title: "扫码填入收款地址")
  }

  /// 冷钱包只进入扫码页读取相机预览，不读取或导入任何账户码。
  func testColdWalletImportScannerFirstEntryKeepsLivePreview() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let myTab = app.buttons.matching(NSPredicate(format:
      "label CONTAINS %@ AND NOT (label CONTAINS %@)", "我的", "我的通讯录")).firstMatch
    XCTAssertTrue(myTab.waitForExistence(timeout: 20))
    myTab.tap()
    let walletEntry = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@)",
        "钱包", "钱包", "管理账户")
    ).firstMatch
    XCTAssertTrue(walletEntry.waitForExistence(timeout: 10))
    walletEntry.tap()
    XCTAssertTrue(app.staticTexts["我的钱包"].waitForExistence(timeout: 15))

    let addEntry = app.buttons["添加账户 / 导入冷钱包"]
    if addEntry.waitForExistence(timeout: 5) && addEntry.isEnabled {
      addEntry.tap()
    }
    // 底部 ListTile 将标题和副标题合并为一个可点击语义节点。
    let coldImport = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", "导入冷钱包")).firstMatch
    XCTAssertTrue(coldImport.waitForExistence(timeout: 10))
    coldImport.tap()
    XCTAssertTrue(app.staticTexts["导入冷钱包"].waitForExistence(timeout: 10))
    let scanButton = app.buttons["扫码填入地址"]
    XCTAssertTrue(scanButton.waitForExistence(timeout: 10))
    scanButton.tap()
    try assertLiveScannerPreview(in: app, title: "扫描钱包二维码")
  }

  /// 通讯录只验证扫码页摄像预览，不识别二维码或写联系人关系。
  func testContactScannerFirstEntryKeepsLivePreview() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let myTab = app.buttons.matching(NSPredicate(format:
      "label CONTAINS %@ AND NOT (label CONTAINS %@)", "我的", "我的通讯录")).firstMatch
    XCTAssertTrue(myTab.waitForExistence(timeout: 20))
    myTab.tap()
    let contactsEntry = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "通讯录", "通讯录\n")
    ).firstMatch
    XCTAssertTrue(contactsEntry.waitForExistence(timeout: 10))
    contactsEntry.tap()
    XCTAssertTrue(app.staticTexts["我的通讯录"].waitForExistence(timeout: 15))
    let scanButton = app.buttons["扫码添加联系人"]
    XCTAssertTrue(scanButton.waitForExistence(timeout: 10))
    scanButton.tap()
    try assertLiveScannerPreview(in: app, title: "扫码添加好友")
  }

  /// 三个入口共用同一真机像素门禁；临时提示可能早于 XCTest 的点击回执消失。
  private func assertLiveScannerPreview(in app: XCUIApplication, title: String) throws {
    let page = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", title)).firstMatch
    guard page.waitForExistence(timeout: 10) else {
      // 等待结束后再读取固定前置状态，避免在身份查询尚未返回时漏掉提示。
      // 只报告源码固定文案；禁止操作身份注册或输出未知页面内容。
      for phrase in ["暂时无法验证身份，请稍后重试", "注册身份", "我的通讯录",
                     "导入冷钱包", "扫码添加好友", "扫描钱包二维码"] {
        if app.descendants(matching: .any).matching(
          NSPredicate(format: "label CONTAINS %@", phrase)).firstMatch.exists {
          NSLog("SCANNER_GATE kind=%@", phrase)
        }
      }
      XCTFail("预期扫码页未出现，不能进行相机验收")
      return
    }

    var previous: [UInt8]?
    var liveFrames = false
    var sawFailure = false
    var samples = 0
    var whiteSamples = 0
    var darkSamples = 0
    let deadline = Date().addingTimeInterval(12)
    while Date() < deadline {
      sawFailure = sawFailure || app.staticTexts["扫码失败"].exists
      let current = try scanCenterPixels(in: app)
      samples += 1
      if scanCenterIsWhite(current) { whiteSamples += 1 }
      // 只记录近黑/近白类别与帧数，不记录或导出任何可还原画面的像素。
      let dark = stride(from: 0, to: current.count, by: 4).filter {
        current[$0] < 10 && current[$0 + 1] < 10 && current[$0 + 2] < 10
      }.count
      if dark * 10 >= (current.count / 4) * 9 { darkSamples += 1 }
      if let previous, !scanCenterIsWhite(current), scanCenterChanged(previous, current) {
        liveFrames = true
        break
      }
      previous = current
      Thread.sleep(forTimeInterval: 0.35)
    }
    NSLog("SCANNER_PREVIEW samples=%d white=%d dark=%d changed=%d failure=%d",
          samples, whiteSamples, darkSamples, liveFrames ? 1 : 0, sawFailure ? 1 : 0)
    XCTAssertFalse(sawFailure, "\(title)首次打开显示了设备失败提示")
    XCTAssertTrue(liveFrames, "\(title)首次打开未持续输出摄像头画面")
  }

  /// 只下采样无文字的扫码框中央区域并返回瞬时RGB值；原始画面不进入附件、日志或磁盘。
  private func scanCenterPixels(in app: XCUIApplication) throws -> [UInt8] {
    let image = try XCTUnwrap(app.screenshot().image.cgImage)
    let crop = CGRect(
      x: CGFloat(image.width) * 0.38,
      y: CGFloat(image.height) * 0.41,
      width: CGFloat(image.width) * 0.24,
      height: CGFloat(image.height) * 0.12
    ).integral
    let center = try XCTUnwrap(image.cropping(to: crop))
    let side = 24
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(
        data: bytes.baseAddress,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      context.interpolationQuality = .low
      context.draw(center, in: CGRect(x: 0, y: 0, width: side, height: side))
      return true
    }
    XCTAssertTrue(drawn, "无法在内存中读取扫码框中心像素")
    return pixels
  }

  private func scanCenterIsWhite(_ pixels: [UInt8]) -> Bool {
    let count = pixels.count / 4
    let white = stride(from: 0, to: pixels.count, by: 4).filter {
      pixels[$0] > 245 && pixels[$0 + 1] > 245 && pixels[$0 + 2] > 245
    }.count
    return white * 10 >= count * 9
  }

  private func scanCenterChanged(_ previous: [UInt8], _ current: [UInt8]) -> Bool {
    guard previous.count == current.count else { return false }
    var difference = 0
    for index in stride(from: 0, to: current.count, by: 4) {
      for channel in 0..<3 {
        difference += abs(Int(current[index + channel]) - Int(previous[index + channel]))
      }
    }
    return difference > (current.count / 4) * 2
  }

  /// 正式钱包页只读验收列表、菜单、重命名弹窗及取消；交互属于 App 原页面。
  /// 不读取或改变钱包名称，不执行创建、导入、追加、删除、签名或私钥显示，不保留截图。
  func testWalletPagePreservesPublicSurfaceAndAvailableSdkEntry() throws {
    let app = XCUIApplication(bundleIdentifier: targetBundleIdentifier)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    dismissPermissionGuideIfNeeded(in: app)
    try requireMainNavigation(in: app)

    let myTab = app.buttons.matching(
      NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "我的", "我的通讯录")
    ).firstMatch
    XCTAssertTrue(myTab.waitForExistence(timeout: 20), "找不到我的主导航入口")
    myTab.tap()

    let walletEntry = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@ OR (label CONTAINS %@ AND label CONTAINS %@)",
        "钱包", "钱包", "管理账户")
    ).firstMatch
    XCTAssertTrue(walletEntry.waitForExistence(timeout: 10), "我的页缺少钱包入口")
    walletEntry.tap()
    XCTAssertTrue(app.staticTexts["我的钱包"].waitForExistence(timeout: 15))

    let addEntry = app.buttons["添加账户 / 导入冷钱包"]
    XCTAssertTrue(addEntry.waitForExistence(timeout: 10), "钱包页缺少原添加入口")

    // 热账户与冷钱包的菜单和弹窗分别验证；只取消，不读取输入框现值。
    let hotMenu = app.buttons["账户操作"].firstMatch
    XCTAssertTrue(hotMenu.waitForExistence(timeout: 10), "缺少热账户验收条件")
    hotMenu.tap()
    // Flutter 菜单项可能是 button，而不是 staticText；按固定文案查询全部语义类型。
    XCTAssertTrue(app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "扫一扫")).firstMatch.waitForExistence(timeout: 5))
    let rename = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "重命名")).firstMatch
    XCTAssertTrue(rename.waitForExistence(timeout: 5))
    rename.tap()
    XCTAssertTrue(app.staticTexts["重命名账户"].waitForExistence(timeout: 5))
    app.buttons["取消"].tap()
    XCTAssertTrue(app.staticTexts["我的钱包"].waitForExistence(timeout: 10))
    NSLog("WALLET_UI stage=hot_rename_cancel passed=1")

    let coldRow = app.descendants(matching: .any).matching(identifier: "wallet-cold-row").firstMatch
    XCTAssertTrue(coldRow.waitForExistence(timeout: 10), "缺少冷钱包验收条件")
    let coldFrame = coldRow.frame
    // 原冷钱包卡片右侧仅有一个小尺寸菜单按钮；按已呈现卡片边界定位，禁止按名称查询。
    let coldMenus = app.buttons.allElementsBoundByIndex.filter {
      coldFrame.contains($0.frame) && $0.frame.width < coldFrame.width / 2
    }
    XCTAssertEqual(coldMenus.count, 1, "冷钱包菜单定位不唯一")
    coldMenus[0].tap()
    XCTAssertTrue(rename.waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "删除钱包")).firstMatch.exists)
    rename.tap()
    XCTAssertTrue(app.staticTexts["重命名钱包"].waitForExistence(timeout: 5))
    app.buttons["取消"].tap()
    XCTAssertTrue(app.staticTexts["我的钱包"].waitForExistence(timeout: 10))
    NSLog("WALLET_UI stage=cold_rename_cancel passed=1")

    let back = app.buttons.matching(NSPredicate(format: "label IN %@", ["返回", "Back"])).firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5))
    back.tap()
    XCTAssertTrue(chatTab(in: app).waitForExistence(timeout: 10))
    NSLog("WALLET_UI stage=return_main passed=1")
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
