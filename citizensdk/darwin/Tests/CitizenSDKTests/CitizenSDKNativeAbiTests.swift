import Foundation
import XCTest
@testable import CitizenSDK

final class CitizenSDKNativeAbiTests: XCTestCase {
    func testQrOnlyRoundTripRequiresNoWalletVaultOrChain() throws {
        let sdk = try CitizenSdk.open(modules: .qr)
        defer { try? sdk.close() }
        let account = Data(repeating: 7, count: 32)
        let text = try sdk.qrEncodeAccountID(account)
        let document = try sdk.qrParse(text)
        XCTAssertEqual(document.kind, 5)
        XCTAssertEqual(document.content, .accountID("0x" + String(repeating: "07", count: 32)))
        let image = try sdk.qrEncode(text)
        XCTAssertEqual(try sdk.qrDecodeLuminance(image.luminance, width: image.width,
            height: image.height, rowStride: image.width).canonicalText, text)
        XCTAssertEqual(sdk.lifecycle, .created)
        XCTAssertThrowsError(try sdk.genesisHash()) { XCTAssertEqual(($0 as? CitizenSDKError)?.code, .unsupported) }
        let host = try CitizenSDKHostBridge(applicationID: "org.citizen.sdk.qr-tests", modules: .qr)
        host.withServices {
            XCTAssertNil($0.pointee.public_store)
            XCTAssertNil($0.pointee.secure_store)
            XCTAssertNil($0.pointee.secret_vault)
        }
    }

    @MainActor
    func testQrWindowCancellationBeforeStartDoesNotAcquireCameraOrReview() async throws {
        let sdk = try CitizenSdk.open(modules: .qr)
        let flow = try CitizenSDKQrFlow(sdk: sdk, signText: nil)
        var clears = 0; var dismissals = 0
        flow.onClear = { clears += 1 }
        flow.onDismiss = { completion in dismissals += 1; completion() }
        XCTAssertThrowsError(try sdk.close()) { XCTAssertEqual(($0 as? CitizenSDKError)?.code, .busy) }
        flow.cancel(); flow.cancel()
        XCTAssertNil(flow.start())
        do { _ = try await flow.operation.value(); XCTFail("取消不得成功") }
        catch { XCTAssertEqual((error as? CitizenSDKError)?.code, .cancelled) }
        XCTAssertEqual(clears, 1); XCTAssertEqual(dismissals, 1)
        try sdk.close()
    }

    func testRevokedCameraNeverStartsFromALateStartCall() async {
        let closed = expectation(description: "相机串行队列已排空")
        let camera = CitizenSDKQrCapture(frame: { _, _, _, _ in XCTFail("关闭后不得交付帧") },
                                        failure: { _ in XCTFail("关闭后不得重新授权或失败交付") })
        camera.close { closed.fulfill() }
        camera.start()
        await fulfillment(of: [closed], timeout: 2)
    }

    func testCreatedChainRejectsEmptyBatchWithNotReadyBeforeClosing() async throws {
        let sdk = try CitizenSdk.open(modules: .chain)
        XCTAssertEqual(sdk.lifecycle, .created)
        do {
            _ = try await sdk.accountBalances(accountIDs: [])
            XCTFail("Created 状态的空批量不得被平台短路为空成功")
        } catch {
            XCTAssertEqual((error as? CitizenSDKError)?.code, .notReady)
        }
        XCTAssertEqual(sdk.lifecycle, .created)
        // value 返回前已释放 Core 结果；若回调派发还未退出，只重试 BUSY，不能强制销毁。
        for _ in 0..<500 {
            do {
                try sdk.close()
                XCTAssertEqual(sdk.lifecycle, .disposed)
                return
            } catch let error as CitizenSDKError where error.code == .busy {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        try sdk.close()
        XCTAssertEqual(sdk.lifecycle, .disposed)
    }

    func testImportedCoreAbiStructuresAreVersioned() {
        XCTAssertGreaterThan(MemoryLayout<citizensdk_create_options_t>.size, 0)
        XCTAssertGreaterThan(MemoryLayout<citizensdk_host_services_v1_t>.size, 0)
        XCTAssertGreaterThan(MemoryLayout<citizensdk_event_t>.size, 0)
        XCTAssertEqual(CITIZENSDK_HOST_BYTES_WRAPPED_DEK, 1)
        XCTAssertEqual(CITIZENSDK_OK, 0)
        XCTAssertEqual(CITIZENSDK_EXTERNAL_SIGNER_QR_V1, 1)
        XCTAssertEqual(CITIZENSDK_SIGNING_COMPLETED, 1)
    }

    func testHeaderExportsExactUniqueCitizenSdkSymbolsIncludingModulesAndVerify() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let sdkRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let header = sdkRoot.appendingPathComponent("include/citizensdk.h")
        let source = try String(contentsOf: header, encoding: .utf8)
        // 公开数值合同使用Clang可直接导入Swift的字面量宏，不维护第二份Swift常量。
        XCTAssertEqual(CITIZENSDK_RESULT_ACCOUNT_BALANCES, 18)
        let regex = try NSRegularExpression(pattern: #"\bcitizensdk_[a-z0-9_]+\s*\("#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let names = Set(regex.matches(in: source, range: range).compactMap { match -> String? in
            guard let swiftRange = Range(match.range, in: source) else { return nil }
            return source[swiftRange].split(separator: "(").first.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        })
        XCTAssertEqual(names.count, 121)
        XCTAssertTrue(names.isSuperset(of: ["citizensdk_review_qr_sign_request", "citizensdk_sign_qr_request", "citizensdk_result_copy_qr"]))
        XCTAssertFalse(names.contains("citizensdk_qr_signing_bytes"))
        XCTAssertFalse(names.contains("citizensdk_qr_create_sign_response"))
        XCTAssertTrue(names.isSuperset(of: ["citizensdk_validate_modules", "citizensdk_create_with_modules", "citizensdk_verify_signature"]))
        XCTAssertTrue(names.isSuperset(of: ["citizensdk_get_genesis_hash", "citizensdk_get_finalized_account_balances",
            "citizensdk_result_get_account_balance_count", "citizensdk_result_get_account_balance_at"]))
    }
}
