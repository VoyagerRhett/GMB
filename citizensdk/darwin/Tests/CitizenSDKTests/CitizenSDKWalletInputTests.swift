import XCTest
@testable import CitizenSDK
#if os(macOS)
import AppKit
#endif

/// 真实调用链接的 Rust C ABI，防止界面测试只验证文案或复制另一套密码算法。
final class CitizenSDKWalletInputTests: XCTestCase {
    func testOptionalPasswordAndCoreValidation() throws {
        try CitizenSDKWalletInput.validatePassword("")
        try CitizenSDKWalletInput.validatePassword("六个中性汉字")
        try CitizenSDKWalletInput.validatePassword("abcdef")
        for rejected in ["abcde", String(repeating: "a", count: 31), "abc def", "abcde\n", "abcdef🙂"] {
            XCTAssertThrowsError(try CitizenSDKWalletInput.validatePassword(rejected))
        }
    }

    func testAllThreeWordCountsAndChecksumAreValidatedByCore() throws {
        XCTAssertEqual(CitizenSDKWalletInput.wordCounts, [12, 18, 24])
        // BIP39 公开全零熵测试向量，不是真实用户助记词。
        for (count, checksumWord) in [(12, "about"), (18, "agent"), (24, "art")] {
            let phrase = (Array(repeating: "abandon", count: count - 1) + [checksumWord]).joined(separator: " ")
            try CitizenSDKWalletInput.validateMnemonic(phrase, wordCount: UInt32(count))
            XCTAssertThrowsError(try CitizenSDKWalletInput.validateMnemonic(phrase, wordCount: 15))
            XCTAssertThrowsError(try CitizenSDKWalletInput.validateMnemonic(phrase, wordCount: 21))
            XCTAssertThrowsError(try CitizenSDKWalletInput.validateMnemonic(phrase + " absent", wordCount: UInt32(count)))
        }
        XCTAssertThrowsError(try CitizenSDKWalletInput.validateMnemonic(Array(repeating: "abandon", count: 12).joined(separator: " "), wordCount: 12))
    }

    func testLocalCompletionUsesOnlyOfficialEnglishWords() throws {
        XCTAssertEqual(try CitizenSDKWalletInput.suggestions(""), [])
        XCTAssertEqual(try CitizenSDKWalletInput.suggestions("aban"), ["abandon"])
        let matches = try CitizenSDKWalletInput.suggestions("a")
        XCTAssertEqual(matches.count, 6)
        XCTAssertTrue(matches.allSatisfy { $0.hasPrefix("a") })
        XCTAssertThrowsError(try CitizenSDKWalletInput.suggestions("Ab"))
        XCTAssertThrowsError(try CitizenSDKWalletInput.suggestions("ab cd"))
    }

    func testNextAccountUsesMaximumNotCountAndIndicesAreExplicit() throws {
        XCTAssertEqual(try CitizenSDKWalletInput.nextIndex([0, 7, 2]), [8])
        XCTAssertEqual(try CitizenSDKWalletInput.indices("1，7 1989"), [1, 7, 1989])
        XCTAssertThrowsError(try CitizenSDKWalletInput.nextIndex([1_989]))
        for text in ["", "0", "1990", "1,1", "1,no"] {
            XCTAssertThrowsError(try CitizenSDKWalletInput.indices(text))
        }
    }

    func testCompletionUsesCaretWordWithoutTouchingFollowingWords() throws {
        let text = "aban absent ability"
        let first = try XCTUnwrap(CitizenSDKWalletInput.completion(text, selection: NSRange(location: 4, length: 0)))
        XCTAssertEqual(first.prefix, "aban")
        XCTAssertEqual(first.range, NSRange(location: 0, length: 4))
        let middle = try XCTUnwrap(CitizenSDKWalletInput.completion(text, selection: NSRange(location: 7, length: 0)))
        XCTAssertEqual(middle.prefix, "ab")
        XCTAssertEqual(middle.range, NSRange(location: 5, length: 6))
        XCTAssertNil(CitizenSDKWalletInput.completion(text, selection: NSRange(location: 5, length: 0)))
        XCTAssertNil(CitizenSDKWalletInput.completion(text, selection: NSRange(location: 0, length: 4)))
    }

    func testCancellationBeforeAdmissionClearsBothBuffersBeforeCallback() {
        let mnemonic = CitizenSDKSensitiveBuffer(data: Data([1, 2, 3]))
        let password = CitizenSDKSensitiveBuffer(data: Data([4, 5, 6]))
        var callbacks = 0
        citizenSDKAfterClearingSecrets([mnemonic, password]) {
            XCTAssertTrue(mnemonic.isClearedForTesting)
            XCTAssertTrue(password.isClearedForTesting)
            callbacks += 1
        }
        XCTAssertEqual(callbacks, 1)
    }

    #if os(macOS)
    @MainActor
    func testRealMacOSWalletWindowInputAndRiskCancellation() async throws {
        let (sdk, parent) = try await realMacOSWalletFixture()
        defer { parent.orderOut(nil); try? sdk.close() }
        var terminal: CitizenSDKWalletFlowResult?
        let flow = try sdk.presentWalletFlow(from: parent, request: .create(wordCount: 12)) { terminal = $0 }
        defer { flow.cancel() }
        let sheet = try XCTUnwrap(parent.attachedSheet)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let controls = descendants(try XCTUnwrap(sheet.contentView))
        let selector = try XCTUnwrap(controls.compactMap { $0 as? NSPopUpButton }.first {
            $0.itemTitles == ["12 个助记词 · 推荐", "24 个助记词"]
        })
        for index in 0..<2 { selector.selectItem(at: index); XCTAssertEqual(selector.indexOfSelectedItem, index) }
        let passwords = controls.compactMap { $0 as? NSSecureTextField }
        XCTAssertEqual(passwords.count, 1)
        let password = try XCTUnwrap(passwords.first)
        XCTAssertEqual(password.placeholderString, "钱包密码（选填）")
        password.stringValue = "abcdef" // 公开合成输入，只验证风险取消，不调用钱包创建。
        let generate = try XCTUnwrap(controls.compactMap { $0 as? NSButton }.first { $0.title == "创建钱包" })
        generate.performClick(nil)
        let risk = try XCTUnwrap(sheet.attachedSheet)
        let riskCancel = try XCTUnwrap(descendants(try XCTUnwrap(risk.contentView)).compactMap { $0 as? NSButton }.first { $0.title == "取消" })
        riskCancel.performClick(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(password.stringValue, "abcdef", "风险取消保留明确输入，不能静默切换为空密码")
        XCTAssertTrue(generate.isEnabled)
        let profile = try await sdk.walletProfile()
        XCTAssertNil(profile, "风险取消不得持久化钱包")
        flow.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        if case .cancelled = terminal { } else { XCTFail("窗口应准确返回取消") }
        XCTAssertEqual(password.stringValue, "")
        terminal = nil
        let importing = try sdk.presentWalletFlow(from: parent, request: .importWallet) { terminal = $0 }
        defer { importing.cancel() }
        let importSheet = try XCTUnwrap(parent.attachedSheet)
        let controller = try XCTUnwrap(importSheet.contentViewController as? CitizenSDKWalletViewControllerMacOS)
        let importControls = descendants(try XCTUnwrap(importSheet.contentView))
        let phrase = try XCTUnwrap(importControls.compactMap { $0 as? NSTextView }.first)
        phrase.string = "aban absent ability"
        phrase.setSelectedRange(NSRange(location: 4, length: 0))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: phrase))
        let completion = try XCTUnwrap(descendants(try XCTUnwrap(importSheet.contentView)).compactMap { $0 as? NSButton }.first { $0.title == "abandon" })
        completion.performClick(nil)
        XCTAssertEqual(phrase.string, "abandon absent ability", "补全必须保留后面的单词")
        importing.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(phrase.string, "")
        parent.orderOut(nil)
        try await closeAfterDraining(sdk)
    }

    @MainActor
    func testRealMacOSPrivateKeyViewMissingAccountClearsWindowBeforeCompletion() async throws {
        let (sdk, parent) = try await realMacOSWalletFixture()
        defer { parent.orderOut(nil); try? sdk.close() }
        // 仅传入合成公开账户；隔离资料库没有钱包，Core 必须在认证或解密前返回 NotFound。
        let operation = try sdk.viewAccountPrivateKey(from: parent, accountID: Data(repeating: 0, count: 32))
        let sheet = try XCTUnwrap(parent.attachedSheet)
        XCTAssertEqual(sheet.sharingType, .none)
        XCTAssertFalse(sheet.styleMask.contains(.closable))
        XCTAssertThrowsError(try sdk.close()) { XCTAssertEqual(($0 as? CitizenSDKError)?.code, .busy) }
        do {
            try await operation.value()
            XCTFail("不存在的账户不能成功查看")
        } catch {
            XCTAssertEqual((error as? CitizenSDKError)?.code, .notFound)
        }
        XCTAssertNil(parent.attachedSheet, "公开终态必须晚于窗口分离")
        XCTAssertNil(sheet.contentViewController, "公开终态必须晚于 SDK 显示控件释放")
        XCTAssertFalse(sheet.isVisible)
        XCTAssertEqual(CitizenSDKWalletFlowRegistry.shared.status(sdk), .open)
        let profile = try await sdk.walletProfile()
        XCTAssertNil(profile)
        try await closeAfterDraining(sdk)
    }

    @MainActor
    func testRealMacOSPrivateKeyViewParentCloseAndLateCancellationNeverRestoreWindow() async throws {
        let (sdk, parent) = try await realMacOSWalletFixture()
        defer { parent.orderOut(nil); try? sdk.close() }
        let operation = try sdk.viewAccountPrivateKey(from: parent, accountID: Data(repeating: 0, count: 32))
        let sheet = try XCTUnwrap(parent.attachedSheet)
        var completions = 0
        operation.observe { _ in completions += 1 }
        parent.close() // 真实窗口关闭通知必须终止查看，不能等待重新回到前台再恢复。
        XCTAssertTrue(try operation.cancel())
        do {
            try await operation.value()
            XCTFail("关闭窗口后不能成功查看")
        } catch {
            // Core 保留先发生的错误：空钱包准备与窗口关闭并发时，只有这两个合法失败终态。
            let code = (error as? CitizenSDKError)?.code
            XCTAssertTrue(code == .cancelled || code == .notFound)
        }
        XCTAssertEqual(completions, 1)
        XCTAssertNil(parent.attachedSheet)
        XCTAssertNil(sheet.contentViewController)
        XCTAssertFalse(sheet.isVisible)
        XCTAssertTrue(try operation.cancel())
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(completions, 1, "晚到取消/前台通知不得再次完成或恢复查看")
        XCTAssertNil(parent.attachedSheet)
        XCTAssertFalse(sheet.isVisible)
        XCTAssertEqual(CitizenSDKWalletFlowRegistry.shared.status(sdk), .open)
        try await closeAfterDraining(sdk)
    }

    @MainActor
    func testRealMacOSPrivateKeyViewRejectsHiddenPresenterWithoutOwningWalletUI() async throws {
        let (sdk, parent) = try await realMacOSWalletFixture()
        defer { parent.orderOut(nil); try? sdk.close() }
        parent.orderOut(nil)
        XCTAssertThrowsError(try sdk.viewAccountPrivateKey(from: parent, accountID: Data(repeating: 0, count: 32))) {
            XCTAssertEqual(($0 as? CitizenSDKError)?.code, .unavailable)
        }
        XCTAssertNil(parent.attachedSheet)
        XCTAssertEqual(CitizenSDKWalletFlowRegistry.shared.status(sdk), .open)
        try await closeAfterDraining(sdk)
    }

    @MainActor
    private func realMacOSWalletFixture() async throws -> (CitizenSdk, NSWindow) {
        guard let directory = ProcessInfo.processInfo.environment["CITIZENSDK_WALLET_INPUT_STORAGE"] else {
            throw XCTSkip("真实窗口验收须提供独立中央存储目录和测试 Bundle 身份")
        }
        // 每例只开独立的空钱包模块，不加载链资源，不创建或读取任何真实钱包秘密。
        let root = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sdk = try CitizenSdk.open(storageRoot: root, applicationID: "org.citizen.sdk.wallet-input.tests", modules: .wallet)
        try await sdk.refreshCapabilities()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        // 命令行 XCTest 没有 NSApplicationMain，必须真实完成 AppKit 启动后才能申请前台。
        if !NSRunningApplication.current.isFinishedLaunching { NSApp.finishLaunching() }
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 820), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while !NSApp.isActive && DispatchTime.now().uptimeNanoseconds < deadline {
            // XCTest 只驱动异步任务，不运行 NSApplication.run；真实激活事件仍须交给 AppKit 派发。
            for _ in 0..<256 {
                guard let event = NSApp.nextEvent(matching: .any, until: .distantPast, inMode: .default, dequeue: true) else { break }
                NSApp.sendEvent(event)
            }
            NSApp.updateWindows()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(NSApp.isActive, "已启用的窗口验收必须获得真实前台，不能静默跳过")
        return (sdk, parent)
    }

    @MainActor
    private func closeAfterDraining(_ sdk: CitizenSdk) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while true {
            do { try sdk.close(); return }
            catch let error as CitizenSDKError where error.code == .busy && DispatchTime.now().uptimeNanoseconds < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }
    #endif
}
