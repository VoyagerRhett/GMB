import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testPackageInfoUsesInstalledBundleVersion() {
    let info = AppDelegate.packageInfo(
      infoDictionary: [
        "CFBundleShortVersionString": "1.2.3",
        "CFBundleVersion": "456",
      ],
      bundleIdentifier: "com.crcfrcn.citizenapp"
    )
    XCTAssertEqual(info["packageName"] as? String, "com.crcfrcn.citizenapp")
    XCTAssertEqual(info["versionName"] as? String, "1.2.3")
    XCTAssertEqual(info["versionCode"] as? Int, 456)
  }

  func testSquareVideoRequestAcceptsOnlyCanonicalEnvelope() throws {
    let request = try SquareVideoRequest(arguments: squareVideoArguments())
    XCTAssertEqual(request.maxWidth, 854)
    XCTAssertEqual(request.audioSampleRate, 48_000)
    XCTAssertEqual(request.keyFrameIntervalSeconds, 2)

    var invalid = squareVideoArguments()
    invalid["audio_sample_rate"] = 44_100
    XCTAssertThrowsError(try SquareVideoRequest(arguments: invalid))
  }

  func testSquareMediaCapabilitiesAlwaysContainFailClosedFlags() {
    let capabilities = SquareVideoTranscoder().capabilities()
    XCTAssertEqual(Set(capabilities.keys), Set(["can_encode_hevc", "can_decode_hevc"]))
  }

  func testApnsEnvironmentUsesEmbeddedProvisioningProfile() throws {
    XCTAssertEqual(
      try AppDelegate.apnsEnvironment(
        provisioningProfileData: provisioningProfile(environment: "development"),
        hasAppStoreReceipt: false
      ),
      "sandbox"
    )
    XCTAssertEqual(
      try AppDelegate.apnsEnvironment(
        provisioningProfileData: provisioningProfile(environment: "production"),
        hasAppStoreReceipt: false
      ),
      "production"
    )
    XCTAssertThrowsError(
      try AppDelegate.apnsEnvironment(
        provisioningProfileData: provisioningProfile(environment: "sandbox"),
        hasAppStoreReceipt: false
      )
    )
    XCTAssertThrowsError(
      try AppDelegate.apnsEnvironment(
        provisioningProfileData: provisioningProfile(environment: nil),
        hasAppStoreReceipt: false
      )
    )
  }

  func testApnsEnvironmentUsesProductionOnlyForStoreReceiptWithoutProfile() throws {
    XCTAssertEqual(
      try AppDelegate.apnsEnvironment(
        provisioningProfileData: nil,
        hasAppStoreReceipt: true
      ),
      "production"
    )
    XCTAssertThrowsError(
      try AppDelegate.apnsEnvironment(
        provisioningProfileData: nil,
        hasAppStoreReceipt: false
      )
    )
    XCTAssertThrowsError(
      try AppDelegate.apnsEnvironment(
        provisioningProfileData: Data("not-a-profile".utf8),
        hasAppStoreReceipt: true
      )
    )
  }

  private func provisioningProfile(environment: String?) -> Data {
    let environmentEntry = environment.map {
      "<key>aps-environment</key><string>\($0)</string>"
    } ?? ""
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
      <key>Entitlements</key><dict>\(environmentEntry)</dict>
    </dict></plist>
    """
    var profile = Data([0xff, 0x00, 0x01])
    profile.append(Data(plist.utf8))
    profile.append(Data([0x00, 0xfe]))
    return profile
  }

  private func squareVideoArguments() -> [String: Any] {
    [
      "input_path": "/tmp/input.mov",
      "output_path": "/tmp/output.mp4",
      "cover_path": "/tmp/cover.png",
      "max_width": 854,
      "max_height": 480,
      "video_bitrate": 504_000,
      "total_peak_bitrate": 900_000,
      "audio_bitrate": 96_000,
      "audio_sample_rate": 48_000,
      "max_frame_rate": 30,
      "key_frame_interval_seconds": 2,
      "max_duration_seconds": 180,
      "max_bytes": 16_000_000,
      "cover_max_edge": 720,
      "cover_quality": 75,
      "cover_max_bytes": 512_000,
    ]
  }

  func testSecureEnclaveTagsAreStableAndDomainSeparated() throws {
    let deviceA = try SecureEnclaveKeyStore.applicationTag(
      namespace: "device_subkey",
      cidNumber: "CID-A"
    )
    let deviceB = try SecureEnclaveKeyStore.applicationTag(
      namespace: "device_subkey",
      cidNumber: "CID-B"
    )
    let deviceData = try SecureEnclaveKeyStore.applicationTag(
      namespace: "device_data_key",
      walletIndex: 7
    )

    XCTAssertEqual(
      String(data: deviceA, encoding: .utf8),
      "citizenapp.device_subkey.cid.Q0lELUE"
    )
    XCTAssertEqual(
      String(data: deviceData, encoding: .utf8),
      "citizenapp.device_data_key.7"
    )
    XCTAssertNotEqual(deviceA, deviceData)
    XCTAssertNotEqual(deviceA, deviceB)
  }

  func testSecureEnclaveTagRejectsNegativeWalletIndex() {
    XCTAssertThrowsError(
      try SecureEnclaveKeyStore.applicationTag(
        namespace: "device_data_key",
        walletIndex: -1
      )
    )
  }

  func testDevicePublicKeyRequiresUncompressedP256Point() {
    var valid = Data(repeating: 0, count: 65)
    valid[0] = 0x04

    XCTAssertNoThrow(try DeviceSubkeyChannel.validateUncompressedPublicKey(valid))
    XCTAssertThrowsError(
      try DeviceSubkeyChannel.validateUncompressedPublicKey(Data(repeating: 0, count: 65))
    )
    XCTAssertThrowsError(
      try DeviceSubkeyChannel.validateUncompressedPublicKey(Data([0x04]))
    )
  }

  func testLowerHexIsCanonical() {
    XCTAssertEqual(
      SecureEnclaveKeyStore.lowerHex(Data([0x00, 0x0a, 0xfe, 0xff])),
      "000afeff"
    )
  }

  func testDeviceDataEnvelopeRequiresExactAad() throws {
    let aad = Data("binding-a|chat".utf8)
    let plaintext = Data(repeating: 0x5a, count: 32)
    let envelope = DeviceDataKeyVaultChannel.encodeEnvelope(
      aad: aad,
      plaintext: plaintext
    )

    XCTAssertEqual(
      try DeviceDataKeyVaultChannel.decodeEnvelope(envelope, expectedAad: aad),
      plaintext
    )
    XCTAssertThrowsError(
      try DeviceDataKeyVaultChannel.decodeEnvelope(
        envelope,
        expectedAad: Data("binding-b|chat".utf8)
      )
    )
  }

}
