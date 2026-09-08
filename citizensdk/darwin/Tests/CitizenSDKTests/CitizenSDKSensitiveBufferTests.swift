import Foundation
import XCTest
@testable import CitizenSDK

final class CitizenSDKSensitiveBufferTests: XCTestCase {
    func testPrivateAuthorizationBindsOnlyThisViewAndRejectsLateOrUnrelatedOperations() {
        let display = CitizenSDKPrivateKeyDisplayBuffer()
        display.bind(7)
        var registered: [UInt64] = []
        display.bindAuthenticationRegistry { registered.append($0); return 0 }
        XCTAssertEqual(display.authorizing(viewID: 8, hostOperationID: 19), CitizenSDKErrorCode.integrity.rawValue)
        XCTAssertEqual(display.authorizing(viewID: 7, hostOperationID: 0), CitizenSDKErrorCode.integrity.rawValue)
        XCTAssertNil(display.authenticationID)
        XCTAssertEqual(display.authorizing(viewID: 7, hostOperationID: 19), 0)
        XCTAssertEqual(display.authenticationID, 19)
        XCTAssertEqual(registered, [19])
        XCTAssertEqual(display.authorizing(viewID: 7, hostOperationID: 20), CitizenSDKErrorCode.integrity.rawValue)
        display.clear()
        XCTAssertEqual(display.authorizing(viewID: 7, hostOperationID: 21), CitizenSDKErrorCode.cancelled.rawValue)
        XCTAssertEqual(registered, [19], "late or unrelated authentication must never register")
    }

    func testPrivateViewBufferHasBoundedHexRenderingAndRejectsLateDisplay() {
        let display = CitizenSDKPrivateKeyDisplayBuffer()
        display.bind(7)
        // 仅构造公开合成字节验证显示边界，不创建或读取钱包/真实密钥。
        let source = (0..<32).map(UInt8.init)
        source.withUnsafeBufferPointer { bytes in
            let borrowed = citizensdk_bytes_view_t(data: bytes.baseAddress, len: 32)
            XCTAssertEqual(display.display(viewID: 8, bytes: borrowed), CitizenSDKErrorCode.cancelled.rawValue)
            XCTAssertEqual(display.display(viewID: 7, bytes: borrowed), 0)
            XCTAssertEqual(display.display(viewID: 7, bytes: borrowed), CitizenSDKErrorCode.cancelled.rawValue)
            display.withCharacters { characters in
                XCTAssertEqual(characters.count, 66)
                XCTAssertEqual(characters[0], 48); XCTAssertEqual(characters[1], 120)
                XCTAssertTrue(characters.dropFirst(2).allSatisfy { (48...57).contains($0) || (97...102).contains($0) })
            }
            display.clear()
            XCTAssertTrue(display.isClearedForTesting)
            XCTAssertEqual(display.display(viewID: 7, bytes: borrowed), CitizenSDKErrorCode.cancelled.rawValue)
            var drew = false
            display.withCharacters { _ in drew = true }
            XCTAssertFalse(drew)
        }
    }

    func testPrivateViewBufferRejectsMalformedLengthBeforeReadingAndHandlesEarlySettlement() {
        let display = CitizenSDKPrivateKeyDisplayBuffer()
        display.settled(viewID: 9, code: CitizenSDKErrorCode.notFound.rawValue)
        display.bind(9)
        let notified = expectation(description: "early no-secret settlement")
        display.listen { code in
            XCTAssertEqual(code, CitizenSDKErrorCode.notFound.rawValue)
            notified.fulfill()
        }
        XCTAssertEqual(display.display(viewID: 9, bytes: .init(data: nil, len: 32)), CitizenSDKErrorCode.integrity.rawValue)
        wait(for: [notified], timeout: 1)
        display.clear()
        XCTAssertTrue(display.isClearedForTesting)
    }

    func testControlledBufferCopiesAndClearsBeforeTerminalCallback() {
        let first = CitizenSDKSensitiveBuffer(data: Data([1, 2, 3]))
        let second = CitizenSDKSensitiveBuffer(data: Data([4, 5, 6]))
        XCTAssertEqual(first.copyData(), Data([1, 2, 3]))
        XCTAssertFalse(first.isClearedForTesting)

        var callbackObservedClear = false
        citizenSDKAfterClearingSecrets([first, second]) {
            callbackObservedClear = first.isClearedForTesting && second.isClearedForTesting
        }

        XCTAssertTrue(callbackObservedClear)
    }

    func testSensitiveTextRejectsOversizedUtf8() {
        XCTAssertThrowsError(try citizenSDKSensitiveText(String(repeating: "a", count: 1_025),
                                                         label: "password"))
    }
}
