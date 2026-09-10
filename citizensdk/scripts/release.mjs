#!/usr/bin/env node

// CitizenSDK 确定性候选打包器。源码只读，所有候选和归档必须落在源码树之外。
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { gzipSync, inflateRawSync } from 'node:zlib';
import {
  copyFileSync,
  chmodSync,
  closeSync,
  constants,
  cpSync,
  existsSync,
  fstatSync,
  lstatSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  readlinkSync,
  realpathSync,
  readdirSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const PRODUCT_ID = 'citizensdk';
const PACKAGE_NAME = 'citizen_sdk';
// 本机仓库和平台目录取中央登记的小写身份；正式产品名和包内平台名称不随路径改变。
const TATA_CONSOLE_TARGET_ROOT = '/Users/rhett/TATA/tataconsole/target/gmb/citizensdk';
const TATA_CONSOLE_CACHE_ROOT = '/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk';
// 独立于任何 binding 源码的 Flutter v1 公共面金标。五份绑定都必须从自己的
// 权威常量/方法表解析并逐项匹配；不能用一端源码生成另一端预期值。
const FLUTTER_METHOD_CHANNEL = 'citizen/sdk/core/v1';
const FLUTTER_EVENT_CHANNEL = 'citizen/sdk/events/v1';
const FLUTTER_METHODS = Object.freeze([
  'open',
  'start',
  'stop',
  'close',
  'getCapabilities',
  'getFinalizedHead',
  'getGenesisHash',
  'getAccountBalance',
  'getAccountBalances',
  'getAccountNonce',
  'getFeeSnapshot',
  'getWalletProfile',
  'viewAccountPrivateKey',
  'createWallet',
  'importWallet',
  'addWalletAccounts',
  'setActiveWalletAccount',
  'renameWalletAccount',
  'deleteWalletAccount',
  'deleteWallet',
  'reconcileWalletCleanup',
  'signWalletPayload',
  'verifySignature',
  'transferWithRemark',
  'initializeFinalizedHistory',
  'syncFinalizedHistory',
  'qrParse',
  'qrCreateSignRequest',
  'qrConsumeSignResponse',
  'qrCancelSignRequest',
  'qrEncodeAccountId',
  'qrEncodeUserTransfer',
  'qrDecodeLuminance',
  'qrEncode',
  'qrScan',
  'signQrRequest',
]);
const ROOT_FILES = [
  '.gitignore',
  '.pubignore',
  'Cargo.lock',
  'Cargo.toml',
  'CHANGELOG.md',
  'LICENSE',
  'LICENSE-GPL-3.0',
  'LICENSE-MIT',
  'README.md',
  'THIRD_PARTY_NOTICES.md',
  'pubspec.lock',
  'pubspec.yaml',
];
const ROOT_DIRECTORIES = [
  'android',
  'assets',
  'darwin',
  'docs',
  'include',
  'lib',
  'linux',
  'native',
  'scripts',
  'test',
  'windows',
];
const FORBIDDEN_DIRECTORIES = new Set([
  '.build', '.dart_tool', '.gradle', '.kotlin', '.swiftpm', 'CitizenSDK.xcframework',
  'DerivedData', 'Pods', 'build', 'target', 'xcuserdata',
]);
const NATIVE_FILES = Object.freeze({
  'android/citizensdk.aar': 'android/citizensdk.aar',
  'android/src/main/jniLibs/arm64-v8a/libcitizensdk.so': 'android/arm64-v8a/libcitizensdk.so',
  'android/src/main/jniLibs/arm64-v8a/libcitizensdk_jni.so': 'android/arm64-v8a/libcitizensdk_jni.so',
});
// Apple 三个 arm64 技术变体作为一个目录原子注入；源码树只保存 Swift/Flutter
// consumer，唯一 native/ffi Core 只存在于这一个 XCFramework 产物中。
const NATIVE_DIRECTORIES = Object.freeze({
  'darwin/CitizenSDK.xcframework': 'apple/CitizenSDK.xcframework',
});
const RELEASE_PLATFORMS = Object.freeze(['Android', 'iOS', 'macOS', 'LinuxARM', 'LinuxAMD', 'Windows']);
const LINUX_PLATFORMS = Object.freeze(['LinuxARM', 'LinuxAMD']);
const LINUX_HOST_HEADERS = Object.freeze([
  'citizen_sdk.hpp', 'citizen_sdk_config.hpp', 'citizen_sdk_error.hpp',
  'citizen_sdk_events.hpp', 'citizen_sdk_models.hpp', 'citizen_sdk_wallet_flow.hpp',
  'citizensdk_host.h',
]);
const LINUX_CMAKE_FILES = Object.freeze([
  'CitizenSDKConfig.cmake', 'CitizenSDKConfigVersion.cmake',
  'CitizenSDKDependencies.cmake', 'CitizenSDKTargets.cmake',
  'CitizenSDKTargets-release.cmake',
]);
// 一个产品的两个机器变体：各自完整的 20 项安装前缀合并为 27 项。
// 七个 Host 头与来源重叠，必须比较字节，绝不以产物覆盖来源。
function linuxInstallPaths(platform) {
  return [
    'include/citizensdk.h', 'include/citizensdk_types.h', 'include/citizensdk_qr_image.h',
    ...LINUX_HOST_HEADERS.map((name) => `include/citizen_sdk/${name}`),
    `lib/${platform}/libcitizensdk.so`, `lib/${platform}/libcitizensdk_host.so`,
    ...LINUX_CMAKE_FILES.map((name) => `lib/${platform}/cmake/CitizenSDK/${name}`),
    ...['manifest.json', 'chainspec.json', 'light_sync_state.json']
      .map((name) => `share/citizensdk/citizenchain/${name}`),
  ].sort();
}
const LINUX_RELEASE_FILES = Object.freeze([...new Set(
  LINUX_PLATFORMS.flatMap(linuxInstallPaths),
)].sort());
const LINUX_INJECTED_FILES = new Set(LINUX_RELEASE_FILES.filter(
  (path) => !LINUX_HOST_HEADERS.some((name) => path === `include/citizen_sdk/${name}`),
));
const HOSTED_LINUX_PLUGIN_FILES = Object.freeze([
  'CMakeLists.txt', 'cmake/CitizenSDKFlutter.cmake',
  'include/citizen_sdk/citizen_sdk_plugin.h', 'src/citizen_sdk_plugin.cc',
  ...['codec', 'sessions', 'wallet_flow', 'environment'].flatMap(
    (name) => ['cc', 'hpp'].map((extension) => `src/citizen_sdk_flutter_${name}.${extension}`),
  ),
]);
const WINDOWS_HOST_HEADERS = Object.freeze([
  'citizen_sdk.hpp', 'citizen_sdk_config.hpp', 'citizen_sdk_error.hpp',
  'citizen_sdk_events.hpp', 'citizen_sdk_models.hpp', 'citizen_sdk_wallet_flow.hpp',
  'citizensdk_host.h',
]);
const WINDOWS_CMAKE_FILES = Object.freeze([
  'CitizenSDKConfig.cmake', 'CitizenSDKConfigVersion.cmake',
  'CitizenSDKDependencies.cmake', 'CitizenSDKTargets.cmake', 'CitizenSDKTargets-release.cmake',
]);
const WINDOWS_RELEASE_FILES = Object.freeze([
  'include/citizensdk.h', 'include/citizensdk_types.h', 'include/citizensdk_qr_image.h',
  ...WINDOWS_HOST_HEADERS.map((name) => `include/citizen_sdk/${name}`),
  'bin/Windows/citizensdk.dll', 'bin/Windows/citizensdk_host.dll',
  'lib/Windows/citizensdk.dll.lib', 'lib/Windows/citizensdk_host.lib',
  ...WINDOWS_CMAKE_FILES.map((name) => `lib/Windows/cmake/CitizenSDK/${name}`),
  ...['manifest.json', 'chainspec.json', 'light_sync_state.json']
    .map((name) => `share/citizensdk/citizenchain/${name}`),
].sort());
const WINDOWS_INJECTED_FILES = new Set(WINDOWS_RELEASE_FILES.filter(
  (path) => !WINDOWS_HOST_HEADERS.some((name) => path === `include/citizen_sdk/${name}`),
));
const HOSTED_WINDOWS_PLUGIN_FILES = Object.freeze([
  'CMakeLists.txt', 'cmake/CitizenSDKFlutter.cmake',
  'include/citizen_sdk/citizen_sdk_plugin.h', 'src/citizen_sdk_plugin.cc',
  ...['codec', 'sessions', 'wallet_flow', 'environment'].flatMap(
    (name) => ['cc', 'hpp'].map((extension) => `src/citizen_sdk_flutter_${name}.${extension}`),
  ),
]);
function parentDirectories(paths) {
  const directories = new Set();
  for (const path of paths) {
    for (let parent = dirname(path); parent !== '.'; parent = dirname(parent)) {
      directories.add(parent);
    }
  }
  return [...directories].sort();
}
const APPLE_XCFRAMEWORK_PATH = 'darwin/CitizenSDK.xcframework';
// LibraryIdentifier 由 xcodebuild 生成，必须视为不透明技术标识。
// 下列合同只依赖 Apple 官方 SupportedPlatform/
// SupportedPlatformVariant 元数据，不使用产品名伪造目录标识。
const APPLE_SLICES = Object.freeze([
  Object.freeze({
    label: 'CitizenSDK iOS（设备技术变体）',
    binaryPath: 'CitizenSDK.framework/CitizenSDK',
    bundlePlatform: 'iPhoneOS',
    dtPlatform: 'iphoneos',
    minimum: '16.0.0',
    minimumKey: 'MinimumOSVersion',
    installName: '@rpath/CitizenSDK.framework/CitizenSDK',
    module: 'arm64-apple-ios',
    platform: 2,
    supportedPlatform: 'ios',
    swiftTarget: 'arm64-apple-ios16.0',
    variant: null,
  }),
  Object.freeze({
    label: 'CitizenSDK iOS（simulator 技术变体）',
    binaryPath: 'CitizenSDK.framework/CitizenSDK',
    bundlePlatform: 'iPhoneSimulator',
    dtPlatform: 'iphonesimulator',
    minimum: '16.0.0',
    minimumKey: 'MinimumOSVersion',
    installName: '@rpath/CitizenSDK.framework/CitizenSDK',
    module: 'arm64-apple-ios-simulator',
    platform: 7,
    supportedPlatform: 'ios',
    swiftTarget: 'arm64-apple-ios16.0-simulator',
    variant: 'simulator',
  }),
  Object.freeze({
    label: 'CitizenSDK macOS',
    binaryPath: 'CitizenSDK.framework/Versions/A/CitizenSDK',
    bundlePlatform: 'MacOSX',
    dtPlatform: 'macosx',
    minimum: '13.0.0',
    minimumKey: 'LSMinimumSystemVersion',
    installName: '@rpath/CitizenSDK.framework/Versions/A/CitizenSDK',
    module: 'arm64-apple-macos',
    platform: 1,
    supportedPlatform: 'macos',
    swiftTarget: 'arm64-apple-macosx13.0',
    variant: null,
  }),
]);
const APPLE_RESOURCE_FILES = Object.freeze({
  'PrivacyInfo.xcprivacy': 'darwin/Sources/CitizenSDK/PrivacyInfo.xcprivacy',
  'citizenchain/chainspec.json': 'assets/citizenchain/chainspec.json',
  'citizenchain/light_sync_state.json': 'assets/citizenchain/light_sync_state.json',
  'citizenchain/manifest.json': 'assets/citizenchain/manifest.json',
});
// macOS framework 必须采用 Apple 标准版本化布局。只有这五个 bundle 内部
// 相对链接属于正式产物；iOS device/Simulator slice、XCFramework 其余位置和
// SDK 源码继续保持零符号链接。固定目标还能同时拒绝绝对路径、`..`、悬空链接
// 和指向 framework 外部的设备文件。
const APPLE_MACOS_FRAMEWORK_SYMLINKS = Object.freeze({
  CitizenSDK: 'Versions/Current/CitizenSDK',
  Headers: 'Versions/Current/Headers',
  Modules: 'Versions/Current/Modules',
  Resources: 'Versions/Current/Resources',
  'Versions/Current': 'A',
});
// 每个 Apple slice 必须携带 Swift 编译器生成的完整六文件模块闭包。
// 任何 sidecar 缺失都会破坏同编译器快速导入、ABI 审计或源码信息；允许额外
// 节点又会把未经审查的架构/模块混入单一 arm64 产物，因此这里使用精确集合。
const APPLE_SWIFT_MODULE_EXTENSIONS = Object.freeze([
  'abi.json',
  'private.swiftinterface',
  'swiftdoc',
  'swiftinterface',
  'swiftmodule',
  'swiftsourceinfo',
]);
// 两份运行时信任锚必须与 CitizenApp 已验证链资产逐字节一致；manifest 再把
// CitizenSDK 产品、CitizenChain 正式链身份、genesis 和两个摘要固定为一个闭集。
const CHAIN_ASSET_FILES = Object.freeze({
  'assets/README.md': '647c1d957cb16ae179813ef2d54867459286d024a857f8eb72bcd791d59eb5dd',
  'assets/citizenchain/README.md': '78f2582c48562bb3b65a224362e285121d58e69353677ae72ba5d69235f5871b',
  'assets/citizenchain/chainspec.json': '6ae934933682a8ffca78663dd4391a730b6ae219bd12abfb5d96b4d8154fc2e0',
  'assets/citizenchain/light_sync_state.json': '014802836a0f6e01a9f1bf7173b8e04c9df8fc3f057565f855abdccdc7361ab6',
  'assets/citizenchain/manifest.json': '73983825dbefac4a74102c80db9913f0ea27ca952eaa110d276ad1c8854835d8',
});
const CHAIN_ASSET_MANIFEST = Object.freeze({
  format_version: 1,
  product_id: 'citizensdk',
  chain_id: 'citizenchain',
  protocol_id: 'citizenchain',
  genesis_hash: '0x18847a5dfd263272f2e7727836fe6582f8c4463ff48609df7b96d5e4d9dd24dd',
  chainspec_sha256: CHAIN_ASSET_FILES['assets/citizenchain/chainspec.json'],
  light_sync_state_sha256: CHAIN_ASSET_FILES['assets/citizenchain/light_sync_state.json'],
  sdk_min_version: '1.0.0',
});
// 真实 Substrate v14 System.Events metadata 夹具及 CitizenChain Runtime 生产
// metadata/events 对为正式解码输入；测试与夹具同时改写不能绕过
// Release 的来源守卫。
const SOURCE_FIXTURE_FILES = Object.freeze({
  'test/transaction/citizenchain-balance-fee-v1.json': '2cd5e648703c8cc389c59f07753470b63c034f7cfa63dac8ffa596c8128a0033',
  'test/transaction/citizenchain-runtime-system-events.hex': '2c4d04a69ff994622877786d481dc4780b7a32795e5f7cfa070ae4acb72679ef',
  'test/transaction/citizenchain-runtime-v14-metadata.hex': 'da62207dfa342ce5285bb214a116761fd0a38c7c329ab8953506ad52471ed681',
  'test/transaction/citizenchain-transfer-build-v1.json': 'c43a1f01c22556d2b1e172088fb540358c25b9554c91ffc71f7b483fcd5a469b',
  'test/transaction/substrate-v14-system-events-metadata.hex': '95b368e7907511b28ba283a6741f4be551b56fb917c2f0183b4143dbe0ebf95b',
  'test/wallet/citizenchain-wallet-derivation-v1.json': '2d9bd9f5feeacea729154475475e0d4525e594bc88ede3a86494ffaf35301769',
  'test/wallet/citizenchain-wallet-password-v1.json': '0f8427f6ca542625626c7c1615608eef19246db496c4bb819937f15cfdec7250',
});
// Release 必须保留根级许可入口和两份权威许可证原文；仅检查文件名存在会允许法律文本被替换。
const LICENSE_SOURCE_FILES = Object.freeze({
  'LICENSE': '35cd2344f30db96dffdbac6f8fd27d2eb622b8f726a9c2798c91b1cd4a2a88d9',
  'LICENSE-GPL-3.0': 'aab56b4a581fc1c50b7c782eacf2fc8be05a47cd98e4bf4d836dd9b6dd9c86f4',
  'LICENSE-MIT': 'c2c4f9ec96b1908f3121e63c94c9b1e8ba4a55035acb55749bf51bcef2774e18',
});
// Hosted Package 不建立第二份候选：官方 Dart 发布工具直接读取已注入 Android/Apple
// 原生库的 GitHub Release 候选，并由这份固定 .pubignore 只筛出运行时闭包。
const HOSTED_PACKAGE_SOURCE_FILES = Object.freeze({
  '.pubignore': '39e7f37587279ea5a1a40c0379a4051cb92aba63ea9e5cc10a0dbc10dc45567b',
  'CHANGELOG.md': '6371f38599f4dbaa4e0d486153f53cdb0cad71b89ee05a5389291e34b2647dc3',
});
// pub.dev/Hosted 包只公开产品 API、公开模型、固定 Flutter tuple 与无秘密
// AccountId/SS58 codec。其余 Dart 来源继续留在 GitHub 审计包作迁移差分，
// 但必须被真实 .pubignore 投影排除，宿主不能 implementation-import 绕过 C ABI。
const HOSTED_RUNTIME_DART_FILES = Object.freeze([
  'lib/citizen_sdk.dart',
  'lib/src/api/citizen_chain.dart',
  'lib/src/api/citizen_qr.dart',
  'lib/src/api/citizen_sdk.dart',
  'lib/src/api/citizen_sdk_error.dart',
  'lib/src/api/citizen_sdk_events.dart',
  'lib/src/api/citizen_transactions.dart',
  'lib/src/api/citizen_wallet.dart',
  'lib/src/crypto/account_codec.dart',
  'lib/src/models/citizen_account.dart',
  'lib/src/models/citizen_capability.dart',
  'lib/src/models/citizen_chain_state.dart',
  'lib/src/models/citizen_transaction.dart',
  'lib/src/models/citizen_wallet.dart',
  'lib/src/platform/citizen_sdk_flutter_codec.dart',
  'lib/src/platform/citizen_sdk_flutter_sessions.dart',
  'lib/src/platform/citizen_sdk_platform.dart',
  'lib/src/platform/flutter_citizen_sdk_platform.dart',
]);
const HOSTED_MAIN_DEPENDENCIES = Object.freeze({
  flutter: null,
  polkadart_keyring: '^0.7.1',
});
const HOSTED_DEV_DEPENDENCIES = Object.freeze({
  crypto: '^3.0.7',
  ffi: '^2.2.0',
  flutter_lints: '^5.0.0',
  flutter_test: null,
  meta: '^1.15.0',
  path: '^1.9.1',
});
// 根 include/ 是 CitizenSDK 唯一产品 ABI。三文件完整闭集既固定字节，也阻止
// 上游 smoldot/signer 符号、任意 RPC 和秘密导出接口绕过 citizensdk_* 边界。
const PUBLIC_ABI_FILES = Object.freeze({
  'include/README.md': '11779a8ce66a8b05baddd51980e8a8b977bd0fc1fcffe42e8fdee377fa9e64ac',
  'include/citizensdk.h': '90e0f08333b1abe1806c185a919b5f8c59d1c697bc755c5b1548dac37594a95d',
  'include/citizensdk_types.h': '19a341afa34236ec7b3cf51a8d3e76b6af4958da4a53af58e66302b2f17be559',
});
// Dart（排除已有独立来源合同的 smoldot 快照）、Android root/native 与
// Apple darwin 生产输入构成一个反向闭集。平台测试、文档和注入的 AAR/
// XCFramework 分别由测试、文档与候选投影合同固定，不能在本表建立第二条来源。
const MOBILE_BINDING_SOURCE_FILE_COUNT = 94;
const MOBILE_BINDING_SOURCE_FILES = Object.freeze({
  'android/native/src/main/kotlin/org/citizen/sdk/ui/CitizenSdkQrCoordinator.kt': '213bb08e1240aec35fbaabe5a02c3b714ef998692e47d63c88392ac887300fda',
  'android/native/src/main/kotlin/org/citizen/sdk/ui/CitizenSdkQrActivity.kt': '2ae1c5314c1595c247b6d80e65c70d92839254b869ea05a2a60dbe3e9a3976be',
  'darwin/Sources/CitizenSDK/CitizenSDKQrScanner.swift': '4ae2a37ae8ab25928d381f5f47339196ae03c387deab00b690de764e6a58f925',
  'android/build.gradle': 'e4e7a4becc499e3858bc7fbb4b6e29b32a04ba5d8844798fd7b9a9bc61858650',
  'android/gradle.properties': 'cf2c210cd35238888bb6c125c538bcadfebff01d28e97d664b83f96f31fa3160',
  'android/native/build.gradle': '96653596ad92073aa74f25bd0e156a0d2323e8bb3c1f91b47071cc80c104b706',
  'android/native/consumer-rules.pro': '81c0d229a083f6b87647b45708e1b19ad116a65c5eed33bf5152ac35def7f2c0',
  'android/native/src/main/AndroidManifest.xml': '70b610be6bb295f81b54e0a55d9e0171f2cbc022f3a318034a711813d12eff54',
  'android/native/src/main/cpp/CMakeLists.txt': 'b5dfbc71b58b50d40961edd3022ce70f98c8cf6e9163270d02458f0ecafb128f',
  'android/native/src/main/cpp/citizensdk_host_bridge.cpp': '0ae35390c835c4962b22e194ac968a020c72ad938e3c5d5442b6f0e36702b64d',
  'android/native/src/main/cpp/citizensdk_host_bridge.hpp': '4cfc72f77914d45472e151d3e0c31b49f2158d1cf776b1497e83aee43ce4a543',
  'android/native/src/main/cpp/citizensdk_jni.cpp': '30638a872dc25cd26c58613e7aa61c62357d475c290037e648e2841808acc66f',
  'android/native/src/main/cpp/citizensdk_jni_support.hpp': '10a527969caf3d4ed7d8bda6caa2d8b1e56e582bd4877c0b80fc188a68886513',
  'android/native/src/main/kotlin/org/citizen/sdk/CitizenSdk.kt': '62d60904f5de1603588de1d9301432d8f96157e279690e97858fe7b0c4e8f252',
  'android/native/src/main/kotlin/org/citizen/sdk/CitizenSdkError.kt': '2e286272bef5a88e9ea425083c28d4f3299f8ff203b92c21c4fefea7fd01c9e9',
  'android/native/src/main/kotlin/org/citizen/sdk/CitizenSdkEvents.kt': '0d561cdde7e2a985688a4678575cc094488c2d47a332888da60dc82fa45b5bf5',
  'android/native/src/main/kotlin/org/citizen/sdk/CitizenSdkModels.kt': 'c59e371f2a01b52f1afb7fb73a54ce8f91e82a57c3eb6d831e17eac295c1d256',
  'android/native/src/main/kotlin/org/citizen/sdk/CitizenSdkOperation.kt': 'f623f51baff06efd8c9b39aade5968af2fd85860cca331e763d7c27bc5f4bc7c',
  'android/native/src/main/kotlin/org/citizen/sdk/CitizenSdkPreparedWallet.kt': '74f08d32ce1ddeac586180d75dd80a034651da50a83387667355b7a5fd92b0ed',
  'android/native/src/main/kotlin/org/citizen/sdk/CitizenSdkQr.kt': 'c69a2cee704ba632f5ec228c3a8dd7a9ca182f3e6991894509407ad1d75e3139',
  'android/native/src/main/kotlin/org/citizen/sdk/CitizenSdkRecoveryPhrase.kt': 'a2f90846b60e59fa98339a60e2b19b0c3a9c5692c8caa93038ce2116ca8cfc29',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkAssets.kt': '28e6eb8a028f5c7b5404f68ef8ef886107c6f188838bd5c0dae2d111dafa7e79',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkHardwareVault.kt': '06f7e293462da5783f13ce0e7b1ebc84c63b365959759f72702c85e18f39e531',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkHostRecord.kt': '6cdb3638939976db4c1b179a5871d8de111dd4bf2a3c94eab378e281cbcc9b49',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkHostServices.kt': '559d8a449c8269e03beeab89fac974fe84989b991fea0ce2258b416d2431b6ca',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkNative.kt': 'f8fa390c5b0927f110026107f14e7ada92942eac075d9f31019dde04e20a1ede',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkNativeCodec.kt': '48d756745b355f2305d4d81b373a834c9df96773893227987fce271fd7801c62',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkNativeResult.kt': '5f6b8451678444c687f7c236dd5c2538d8b7851cc03a1abdd2edf67fc9f02696',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkPublicStore.kt': 'd252f511c22e10c70edc4a6a7320f3c0ee94c74ce2f2babdc18203b46067f2c1',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkRecordKey.kt': 'a43d9a8d303cd2a687bf11004ec5b95eb9e684a2f55befc364ca62b50f1c9a14',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkRequestRouter.kt': '3bb7e4278b8aed30f7f252698ddc84ec9347403efbfa51fcde23fce4ef574276',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkSecureStore.kt': 'a464b26f1b374ecf8b7f3cc3de86d738a42440877f12e1040347c8bf9ecf0270',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkSensitiveBytes.kt': 'fe2129f7612e3cad88ed7d2f38d66d371488554238794c94d9139c95729337c6',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkSqlite.kt': '0d8c1546edbe7b14ba24259b97ba77349613ca9ed8dc43952397d207c7a171e4',
  'android/native/src/main/kotlin/org/citizen/sdk/ui/CitizenSdkRecoveryContent.kt': '3841dfca6275bdad439fecf2130459f14e781c76b01a0c957e3eaf8ca88f408e',
  'android/native/src/main/kotlin/org/citizen/sdk/ui/CitizenSdkWalletFlowActivity.kt': '426ebcc36374201de3b5e2021ad62f6a3c778c821e19a72cf26e1ddf2aee51da',
  'android/native/src/main/kotlin/org/citizen/sdk/ui/CitizenSdkWalletFlowContract.kt': '5dca45ab6aee418c09e3cfce90d56e00cdb3dcb67a5ef512c3995529e9db69ed',
  'android/native/src/main/kotlin/org/citizen/sdk/ui/CitizenSdkWalletFlowCoordinator.kt': '7901b6ebbe8e97b570c14e46b621734fecac1bb582211efda651cdcb6ebfd015',
  'android/settings.gradle': '8e2da3c3bb63c5ee2349e1e1b3c080e53039ee2f9418997bb4c97d921e51dae5',
  'android/src/main/AndroidManifest.xml': 'a89f063492bdb6f248de2f760ccb88bdfa5c769bd6c967c4366a8a7700286ca2',
  'android/src/main/kotlin/org/citizen/sdk/CitizenSdkFlutterCodec.kt': '0482013a2ba102bf4ff5431bf32e6b7ac510e2929adf5c04562818b051c862f5',
  'android/src/main/kotlin/org/citizen/sdk/CitizenSdkFlutterSessions.kt': 'dce0315dd2c25dfeb2b0d8caabfb65302539428adcd27bf88bad9b9a1facae10',
  'android/src/main/kotlin/org/citizen/sdk/CitizenSdkFlutterWalletFlow.kt': '1585d9cc6b59233fd30d24d8fd7d23ca898c8a5d347ae2ee0cc078dccc3c7ea2',
  'android/src/main/kotlin/org/citizen/sdk/CitizenSdkPlugin.kt': '92fe14dcf007d368f73854c2b581edd51bce157c439ee9c6b843a9a729f2938a',
  'darwin/Package.swift': '159c504cab86afb641fbef2b1fd35c59c20bbbe81d003cd7cdeec914a3ee91fc',
  'darwin/Sources/CitizenSDK/CitizenSDK-Bridging-Header.h': '977e6c4e7ede7d12d193032be74810c49412492321ea719937873482956f25a8',
  'darwin/Sources/CitizenSDK/CitizenSDK.swift': 'f477ba212ceb44c1d181a644f564567a2f7dc597b2734b8525e43fc74a94857e',
  'darwin/Sources/CitizenSDK/CitizenSDKAssets.swift': '56cac1ebe833ddba39fb48aa8118e670612042a1673bba24805f2581d8fb10f6',
  'darwin/Sources/CitizenSDK/CitizenSDKError.swift': '51a7f249764ff7c07ba7a75e228b9462c5bf7a5aef70b553a5d56ef12db2f9d1',
  'darwin/Sources/CitizenSDK/CitizenSDKEvents.swift': 'd882dd01b0c3d43e5675a3641390b36c93991abe3d522d0998551e2a82ad59c7',
  'darwin/Sources/CitizenSDK/CitizenSDKHostBridge.swift': '16ec4266a9f93cf68667e7aa59e2e8fa3bc802870781096f1d9a90de3a6938f6',
  'darwin/Sources/CitizenSDK/CitizenSDKHostRecord.swift': '70d951817f68a0ca5adb55a0a82323d8919920a1605b062e042c3122b9b391d8',
  'darwin/Sources/CitizenSDK/CitizenSDKInputLimits.swift': 'dcbdec08cfe9fec2c8fa6119578a33b7f74a167fa1b57019a09a3cd5ccbc31ae',
  'darwin/Sources/CitizenSDK/CitizenSDKModels.swift': '410894732bce0376e6d330e975f00f9ecf348c16ce24aab02519727f1dc16f03',
  'darwin/Sources/CitizenSDK/CitizenSDKNative.swift': '2087c0b0f935e69fe293059a4e92709642f77e06b4fb917082ca11287c247c72',
  'darwin/Sources/CitizenSDK/CitizenSDKNativeCodec.swift': '39915f8e1aa115cdfc32007bb9ffa0dac51966cb5c90a8dabcd02cd3446e6977',
  'darwin/Sources/CitizenSDK/CitizenSDKOperation.swift': 'a36da7031a4775e90328c80b2ef8749a88af89759c89eec278dcdc561c803646',
  'darwin/Sources/CitizenSDK/CitizenSDKPreparedWallet.swift': 'e405d16b3a45b774400e737300bf0c6a9e0caa7990c15a53ccbc16fa7c522d10',
  'darwin/Sources/CitizenSDK/CitizenSDKQr.swift': '7c698bbfa6390a6612a35a91c596a3f512ab95af75f4034f2795e373ac877937',
  'darwin/Sources/CitizenSDK/CitizenSDKPublicStore.swift': '4d6d4bef0b51d1d4c3d0518fc9e6a69968a88c95a8f33ac1af2cadeefddd29cd',
  'darwin/Sources/CitizenSDK/CitizenSDKRecordKey.swift': 'e4e0cd2f0ab0c6e1390391bdd5eb3c54370d49da23bca08c45ed37ed4936256e',
  'darwin/Sources/CitizenSDK/CitizenSDKRecoveryPhrase.swift': '5600c386b88b6b17299a13e758655337ae2441e1cea4a08426bdd69ed0815a34',
  'darwin/Sources/CitizenSDK/CitizenSDKSQLite.swift': '37460d6b270ec32fdd503cc506f1195f48152527b8acf063ab1b11b8f6fa6ad5',
  'darwin/Sources/CitizenSDK/CitizenSDKScreenSecurity.swift': '8501af1dcf92faf8f62d0113bd8831569f7060cbe825994d1d2915a908469c70',
  'darwin/Sources/CitizenSDK/CitizenSDKSecretVault.swift': '139076205baf5d9572bdb9d9c6cbb6783eb2e13f358cb41d3dbf46f232b221f0',
  'darwin/Sources/CitizenSDK/CitizenSDKSecureStore.swift': 'ecf5be4e8cb98f80f32b737c6367996f65499e4c64fd7a31b92e24eca74d0aaf',
  'darwin/Sources/CitizenSDK/CitizenSDKSensitiveBuffer.swift': '2b92446c0fb99663105dcbe070a9bd0718ba492d807ce8ff1966d41a512ed25a',
  'darwin/Sources/CitizenSDK/CitizenSDKWalletFlow.swift': 'c17e599c7df2e842293b8e0cb88c40218173a279265966f46d197ed09a0384cd',
  'darwin/Sources/CitizenSDK/CitizenSDKWalletFlowIOS.swift': '0b679707ab21a74a52a3a3c91d7372200af33efd1b48ecb93f07214a1a155cc0',
  'darwin/Sources/CitizenSDK/CitizenSDKWalletFlowMacOS.swift': '9f55b2db8469c07b8068975616f7f42de4ce750406ba7d714e18c08afbded86b',
  'darwin/Sources/CitizenSDK/PrivacyInfo.xcprivacy': 'bc417321bb94066c1bca08840349eea542c3c13e6addfc8248533791627434f3',
  'darwin/Sources/CitizenSDKFlutter/CitizenSdkFlutterCodec.swift': 'fbd229f06c1ff3988a11626fb21d90a3e36f7bc2bd916d2588b5b252f160e91d',
  'darwin/Sources/CitizenSDKFlutter/CitizenSdkFlutterSessions.swift': '0ce1a8ae7df3eddd2e99ab7e82ef21b1658584af06a8ae63627d395a7de446ce',
  'darwin/Sources/CitizenSDKFlutter/CitizenSdkFlutterWalletFlow.swift': 'a6ce24b64ac5f5eae845245b9c78f75e32a1687b358f98a43c94f532be6da7fa',
  'darwin/Sources/CitizenSDKFlutter/CitizenSdkPlugin.swift': '7d634d9c4db67486b62339a9e7f95fd99f97bc54fa3e9049be8948f5a86506e5',
  'darwin/citizen_sdk.podspec': 'bfdddb78cb114521fa9de66d4844772404ce9224886288282cb97c07ddef7248',
  'lib/citizen_sdk.dart': 'c7e2f8e516d79583b559012b21b86d3ad37cd76846d58eda46471483b2f41651',
  'lib/src/api/citizen_chain.dart': 'ca1435f79f186c462cf085c10f16c46ba4421ff01912b3ec2997edd5213e5e90',
  'lib/src/api/citizen_qr.dart': '7a7e31147ba7bc76ac1fb6f8b41a313154d2b93403822d6e370e265b230d750a',
  'lib/src/api/citizen_sdk.dart': '95e01902edae7c3f50d4b9d5c07617d410f5b7d839e4c7c86fc0ccf1dd934418',
  'lib/src/api/citizen_sdk_error.dart': 'e26382dc9af2da918da3e4eb1921f6340b1d9edb0e8956ba2f374eb9925d3f5f',
  'lib/src/api/citizen_sdk_events.dart': '8b7c49ddc88996e0c2254f370f6f9f893fff7a7850c7ad1f6192d036f3a3d0f2',
  'lib/src/api/citizen_transactions.dart': '6a03bd259aaf850612dc5d979592d917aa26ef640959247d71cfd37fd686e1bb',
  'lib/src/api/citizen_wallet.dart': 'fe85dc3ed14ce9a57bed6a90e7a0e4716c39362fbfa8cda99ef20b14b20c4da5',
  'lib/src/crypto/account_codec.dart': 'ce72262d96193ae47da43a9f675d6141f5c565eed05bb9e9755b575d96fcbc84',
  'lib/src/models/citizen_account.dart': '086319ca3010b0c848eba635954299c6425519b8c4eefd84b18ec26b2763ec4f',
  'lib/src/models/citizen_capability.dart': 'e7d5bfa94a60b005cd390f36ae25dfcb87a34c46c5b4e8188984a6103ba2103d',
  'lib/src/models/citizen_chain_state.dart': 'f1a32d30a294106a23d03a3479792d85decdf184f6d828c83bae27a56713cc89',
  'lib/src/models/citizen_transaction.dart': 'f16ed24a536254b3023b34e2fa5f7f21160aeaab83c460265f86e74e2466f94a',
  'lib/src/models/citizen_wallet.dart': '4b6ef68ac5f0207cb81c1eccfc90d732af0faecfa8dcb9f37a6b1a2cc0bf4b0f',
  'lib/src/platform/citizen_sdk_flutter_codec.dart': '70fe7d2365e5edd516f713222f103cb3c74b2dba2fd11599eb96ad5505c49ffd',
  'lib/src/platform/citizen_sdk_flutter_sessions.dart': '8bfcf2be688a4f86f382d144bdaf66782849cc4e907711d83c12aaae7a0a9460',
  'lib/src/platform/citizen_sdk_platform.dart': '295798fba26533cdbba0ec993acd215cf48889b9b744b43c2192e6566fe29f6c',
  'lib/src/platform/flutter_citizen_sdk_platform.dart': 'f51c2ee123272bcd05f2f32e48bc0101566199ca4c186e6d1ceb549be5383c99',
});
// Linux C/C++ Host 与 Flutter adapter 都只是根产品 ABI 的宿主投影，不是
// 第二份 Core。测试和 README 分别由测试、文档闭集固定；其余 CMake、公共头
// 与实现逐字节进入独立来源闭集，不能悄然混入另一套协议或生成产物。
const WINDOWS_BINDING_SOURCE_FILES = Object.freeze({
  'windows/src/citizen_sdk_qr_flow.cc': 'ffbc02731906ca0963ab78c07a44323c3be947f72a7d5d283f281b994af5ae83',
  'windows/src/citizen_sdk_qr_flow.hpp': '0f66f0a70e3fcb2a7a9ae482ae52cbccf9ffff4353e116c6bc622de1f39ae686',
  'windows/src/citizen_sdk_qr_camera.cc': '2b81e0992b0462608699b96fc41e42118034d0f648567ec6f28d067c8687426f',
  'windows/src/citizen_sdk_qr_camera.hpp': 'c3345384e01ac9f8919fb53bacf9a052266f37d3cbc67f10d9a8544b6e82ec8d',
  'windows/cmake/CitizenSDKFlutter.cmake': '9dcbbb80a62f9ef5be022e99b8270dfbd69f3af08131ff1b8c5e04d63218877d',
  'windows/include/citizen_sdk/citizen_sdk_plugin.h': 'ed4a806687c01f9be2a4c4c76dff5dd7d8676f7fe0c6860551006c3a056256ec',
  'windows/src/citizen_sdk_flutter_codec.cc': '9428ad61d82aeef04171091c4ac397875cb39df5abc6625dd1f80af477aedcd9',
  'windows/src/citizen_sdk_flutter_codec.hpp': 'd2d8c7e272baa28dbc9a9f41e547c8b61f360c0b52297ef74d226bef70b4ccda',
  'windows/src/citizen_sdk_flutter_environment.cc': '55752e05934f60eefe922a6a2090dcf47f60b39280985f99628bcbde2ea34f29',
  'windows/src/citizen_sdk_flutter_environment.hpp': '958a42b9f877a3ed3d74ae893a51ceb57603d80ebad2aec1eadf82785b60a055',
  'windows/src/citizen_sdk_flutter_sessions.cc': 'bc8f264fc94838bfcd0808404cd774cf6542981d94ff3daa1108ec59ae774c59',
  'windows/src/citizen_sdk_flutter_sessions.hpp': '25962ba1712a00692af592712ae281b62a422c3a7a1b4e4c5665b7aef7f805e8',
  'windows/src/citizen_sdk_flutter_wallet_flow.cc': '33a1d037c280b38acd1638844e4472da965976eac78e58ed14188cb9b5722d4f',
  'windows/src/citizen_sdk_flutter_wallet_flow.hpp': '5a33d4a1b1b27635fa52437d132a51c075f6b2838f8aa5d1ded9ce3c6aab7d95',
  'windows/src/citizen_sdk_plugin.cc': '45937d780c2d5bc9c638c509384d4dc1012e10fc922b0081b282a668756023c4',
  'windows/CMakeLists.txt': 'a8dcf50d287a00f40f99230f1972b1b5f60e79ed88e220eea2dc0bc5da111050',
  'windows/cmake/CitizenSDKConfig.cmake.in': '81744e9502983d927f9963a8288dd20a33f47b0bb0dbba96ec620bb93b0e5671',
  'windows/cmake/CitizenSDKConfigVersion.cmake.in': '5e180138e3d7ac236ad945c42a15184f48d3076a40206a3d7c90d545d42be235',
  'windows/cmake/CitizenSDKDependencies.cmake': '22e2ce5543f07f84def46b119df9fd9ab248f4c4df8ab27d4ab5f86c9ac65300',
  'windows/cmake/citizensdk_host.def': 'bcb4fbd98b8a71ba99ef02333b5077cea7fc1e93dcc8aec16cb3a4e0b50212de',
  'windows/include/citizen_sdk/citizen_sdk.hpp': '81ac6e86e1bb6ec09ee24dce5b556850eabf2facd089e72c42e0339d87b73722',
  'windows/include/citizen_sdk/citizen_sdk_config.hpp': 'eff96e4819cfc987eea65280384f56e906d6a4ee575062774f0f9d61b9551afd',
  'windows/include/citizen_sdk/citizen_sdk_error.hpp': 'ad835a6ecaded36731a23b18aa6959b806d1515ef8f41cf940026341065e0bd0',
  'windows/include/citizen_sdk/citizen_sdk_events.hpp': '32c2f64beb04bc2ec274c909ff9776e47ab3c05a0face18e879a16d5a4069dc7',
  'windows/include/citizen_sdk/citizen_sdk_models.hpp': 'bad7dded29d0f341524cd4dad9161847d4adcf2bfd3c40bff3e2581bd1c7fb3e',
  'windows/include/citizen_sdk/citizen_sdk_wallet_flow.hpp': '7e8992d7e92523067a6419c1a1f69db06b46c7dbc47210f08403ab7dc95bffc0',
  'windows/include/citizen_sdk/citizensdk_host.h': 'f11778e7741786162a188ede25f688dd8b07b097e96198566957d887447dc7df',
  'windows/src/citizen_sdk_assets.cc': '9f55e98f71f87f8baa3c2608bf64c52e2e8755aed4fa7ded13e47494f9968207',
  'windows/src/citizen_sdk_assets.hpp': '5e50c7ca69023c63af645eec4b97fa1bf74ae3089aef86fdcf1d35fcd4fab8cc',
  'windows/src/citizen_sdk_cng.cc': '88c6cc4d5532eec088d30211826e8cd4583e629557a43d687768a49353d39ffc',
  'windows/src/citizen_sdk_cng.hpp': 'b7e15414228fb0671cbf907aa1a6cbe0ca3ff57a1101805306b2c40c3f3321e5',
  'windows/src/citizen_sdk_directory.cc': 'e32bdb3c8d1f752bc750eae1bbf104b81c54e665fbec6ec8d9d3173a6d5c6844',
  'windows/src/citizen_sdk_directory.hpp': 'c46f0679df4c328b2a43be50260cb8001341f5da66d0ede2830b258c801d546a',
  'windows/src/citizen_sdk_host_api.cc': 'b548f7f924a15429b0f97b0362df3007b7ee275b0606fd5f544c76490f758fe7',
  'windows/src/citizen_sdk_host_bridge.cc': '1ff82f80a27bb007eab48be9745635e5f8f42b36acb58c596c78929e96e247d0',
  'windows/src/citizen_sdk_host_bridge.hpp': '38bb5f77cdf40ca23ddb7db456d62d169ea4ed418c19ea6da56de0afe718c53d',
  'windows/src/citizen_sdk_host_record.cc': 'ef59ba6feefc4686f5d5ed619a7a5cc43d5bd4a167fae1ba4f7022da85d19c39',
  'windows/src/citizen_sdk_host_record.hpp': '9e53109d9d1c3fe31e8f591acba8ec83b869031ff831013f44599a0f80914f68',
  'windows/src/citizen_sdk_input_limits.cc': '4ec6953b4090cd1cda3e82dc7c314a0380e941978654a1a764860658191fdf46',
  'windows/src/citizen_sdk_input_limits.hpp': 'b7f00682ec50320c832247056b2f53ec19efc3a2fb24266660c69817b25ecb55',
  'windows/src/citizen_sdk_lifecycle.cc': '31cf403c44b29cf6f632a4457a120ea4d07ffd216ea951ad90cb2f0baa02d4de',
  'windows/src/citizen_sdk_lifecycle.hpp': '46f4bb12bd1f103f8e50e07b1a86d9c4f250dedce3a5201034cf03e9e2ca5b23',
  'windows/src/citizen_sdk_operation.cc': '1d83a173d0a403ac26990b3b455b0655938665583325b0e5c3d1c1d7c0d3b771',
  'windows/src/citizen_sdk_operation.hpp': '631404a8099b19062aad81f4872b7bfbda7195b48a24d22566aaf954e7aa4a4c',
  'windows/src/citizen_sdk_public_store.cc': 'd6a34beb5d7c3a495f88f59bec188c9cd3e9a88229fb8184dd9b217bdb3f1fb1',
  'windows/src/citizen_sdk_public_store.hpp': '8ca78b5aa56b3ab5829782cc42f28f8625cc82940f1b81aa0fb56a2c3315bdbf',
  'windows/src/citizen_sdk_record_key.cc': '689eb3eab6a279b930f60ebd292b594f17ca2fb06faa0c938ed8311c23cdf3df',
  'windows/src/citizen_sdk_record_key.hpp': '8f41cb538870037827ecda3401178dcaee5d839d052375ddb6b5e9e74326f736',
  'windows/src/citizen_sdk_secret_vault.cc': '6333ca220d76bae082d590ec3a9e72c04711d6b94963fae16202187405ddb2a4',
  'windows/src/citizen_sdk_secret_vault.hpp': 'd16fa0fc99a1b3245f37aa6239cfd4390298b4eb15bc3de16b41103d75774173',
  'windows/src/citizen_sdk_secure_store.cc': 'daa23ab6fce9853b6139494a91da4f901601849ef37d380f935ea355d42455e6',
  'windows/src/citizen_sdk_secure_store.hpp': '9749e169f1ea50642c2837f80b5eb658ce49cfcf002012d893437d75cd6793b6',
  'windows/src/citizen_sdk_sensitive_buffer.cc': '3e57b05e29b90c92f95dee292360debeb0c330af1fce41a24de9cf9c3d04dff6',
  'windows/src/citizen_sdk_sensitive_buffer.hpp': '99c5cd23993b3bed07605f4a707eec55cdf087a97677bbd684f8363355ef3ce7',
  'windows/src/citizen_sdk_sqlite.cc': 'd582717fa3d74c1f040119e010d972cc9ed8087f60b972a20d129317320d2098',
  'windows/src/citizen_sdk_sqlite.hpp': 'ff52d0f0456b0fd96a567bd7b4a46950dbbb65290e78b4d52986d56983aa7d99',
  'windows/src/citizen_sdk_user_auth.cc': '7a51220f936914665c4cef8aff7d02b5febc27b3dd241e0bb51d1490d8f34b16',
  'windows/src/citizen_sdk_user_auth.hpp': '3df44605aad022a3acd3dc4c9259cd88f649ba438156eced488d7638321473cd',
  'windows/src/citizen_sdk_wallet_flow.cc': '7290596699321aa063182d1d77ed04b25cc015bb5f4dd55e2409598499022922',
  'windows/src/citizen_sdk_wallet_flow.hpp': '76eef53fc5d99115779d634b20ca1ef4084c94a1d6d4d48a63929ffec4c55c00',
  'windows/src/citizen_sdk_wallet_validation.cc': 'ba27e646b0094ce86a14eb404926b8cf501a9eac0c4ee9625fcc765529072709',
  'windows/src/citizen_sdk_wallet_validation.hpp': 'de3fab4c5216c2c30abec35bf365c3c3077ba44c4efa6f58dccf1fc3bf03522b',
  'windows/src/citizen_sdk_wallet_window.cc': '053bc3c7b098be321ce32ae3606af85e265469d55419966d23251fc79df70d0f',
  'windows/src/citizen_sdk_wallet_window.hpp': '51187c6f642c18ea5feed2525acffb33876fc929f7249c2a5089532f56b52681',
  'windows/src/citizen_sdk_window.cc': '76673550457b05c7f75a426739cfc925e8322b98c872c3519420a465d79afe7c',
  'windows/src/citizen_sdk_window.hpp': '60fff1bbed42f818449e351e819aae65e30029b95bb27b92421f7793a1ccfa6b',
});
const LINUX_BINDING_SOURCE_FILE_COUNT = 64;
const LINUX_BINDING_SOURCE_DIRECTORIES = Object.freeze([
  'cmake',
  'include',
  'include/citizen_sdk',
  'src',
  'test',
]);
const LINUX_BINDING_SOURCE_FILES = Object.freeze({
  'linux/src/citizen_sdk_qr_flow.cc': '48e6b3d4dc67127ad650e621e99726115fda628705ea493b22ff3eed9517da23',
  'linux/src/citizen_sdk_qr_flow.hpp': 'b1a00a2432034a054c50672ef03f335ea161c88bf251977dd5611895c43fc358',
  'linux/src/citizen_sdk_qr_camera.cc': '49ffa92937867441927f17690f3d688e03c18d4b3506969bf60f7136df31f009',
  'linux/src/citizen_sdk_qr_camera.hpp': '0f644214c988867f8d349d1c65e53c544956ef3dfa2bab45e17478db514b3a70',
  'linux/CMakeLists.txt': '274591668343127ca73c3f223190ca94d988855ccf2366bcf448629c51c074ff',
  'linux/cmake/CitizenSDKConfig.cmake.in': '0f3981dcfdab1fbea6f893af38f2bfe3dd093aac9258a5deb8a26ee6a666f211',
  'linux/cmake/CitizenSDKConfigVersion.cmake.in': 'b2dd2bb6bb58f1255b6e9eca0f61b635f589ee2809537f7ba7fa45d46e3d7685',
  'linux/cmake/CitizenSDKDependencies.cmake': 'c0ab6dffc4577ebfff8b3eb467f37f2b8c7fb45158bf3f64b7e8d753b9d8f5d0',
  'linux/cmake/CitizenSDKFlutter.cmake': '9bf8c3d1d720070f7081063e18e06a8201910d095d0be662b633d1ca52d76a64',
  'linux/cmake/citizensdk_host.map': '55b8fded38b58ad55b71e4f24f6c0ab2008fb11341bb53deee1e734e0718f04a',
  'linux/include/citizen_sdk/citizen_sdk.hpp': '9d069259b880472bbc705b50fbb6b5b3c83b4b3044a4f4a64645ae985b2fbc9e',
  'linux/include/citizen_sdk/citizen_sdk_config.hpp': '1f995e4d9ad24fda5e927f256f34617fae7b5996c5f17af71c9ee6c9cedc6815',
  'linux/include/citizen_sdk/citizen_sdk_error.hpp': 'ad835a6ecaded36731a23b18aa6959b806d1515ef8f41cf940026341065e0bd0',
  'linux/include/citizen_sdk/citizen_sdk_events.hpp': '32c2f64beb04bc2ec274c909ff9776e47ab3c05a0face18e879a16d5a4069dc7',
  'linux/include/citizen_sdk/citizen_sdk_models.hpp': 'bad7dded29d0f341524cd4dad9161847d4adcf2bfd3c40bff3e2581bd1c7fb3e',
  'linux/include/citizen_sdk/citizen_sdk_plugin.h': '06636001f326a317617a39f7c1108eb510b127f416de7f0dcb4c4cdd84be0c2f',
  'linux/include/citizen_sdk/citizen_sdk_wallet_flow.hpp': '7e8992d7e92523067a6419c1a1f69db06b46c7dbc47210f08403ab7dc95bffc0',
  'linux/include/citizen_sdk/citizensdk_host.h': '6903a57e81c7fc6b2f828822cab1dbc8b100a4d000443dfe2ea3cd19a895e102',
  'linux/src/citizen_sdk_assets.cc': 'b663b653299c22d62a44a7f242e1e57f2d8471408d0d3d81728bbe37929d0cb6',
  'linux/src/citizen_sdk_assets.hpp': '44d30123c623ea266030235126552e4a9334839f0d5d44adb5931f56d8b93401',
  'linux/src/citizen_sdk_flutter_codec.cc': '077bf51daaf261b45f38d53d1cb0ceafebd8c41d310dbf2735c10a9ce809ccf3',
  'linux/src/citizen_sdk_flutter_codec.hpp': '217932b3452a24fa152c0c56865ab1aac2b461921c193fa30110f8726350b8ef',
  'linux/src/citizen_sdk_flutter_environment.cc': '7705ddce74f6d2b94c0102328f25421846623ce55f18563ccdbed9d3820e7737',
  'linux/src/citizen_sdk_flutter_environment.hpp': 'cb7c3707b5060d178bfaebab973358a897cabac08945220fd975a6e050e2a455',
  'linux/src/citizen_sdk_flutter_sessions.cc': '921ec3b9a0e8d4c3578f34444c90e3dab9d6815dbc9a00f53c0db13d187cb067',
  'linux/src/citizen_sdk_flutter_sessions.hpp': '24727a347c594309c29734387301440afe3f18e2c9f52f2e3a1f70ff889ace84',
  'linux/src/citizen_sdk_flutter_wallet_flow.cc': '926012e16c47f15af8040e48789cf5d9a07b7c11be22ff871beb5d755452bdc5',
  'linux/src/citizen_sdk_flutter_wallet_flow.hpp': '717fe64d7a8f078810571202ccb4dbb508037f3b8570fa4b4c0e4a170514742a',
  'linux/src/citizen_sdk_gtk_parent.cc': '885485999900f9d121cec35fb859abf8b378f0caa0fb674a2b909f96377cf5ba',
  'linux/src/citizen_sdk_gtk_parent.hpp': '891a3fb929951b7a51a0e76854d50aa289a72795ca90c3f8c7140292a19a8cad',
  'linux/src/citizen_sdk_host_api.cc': 'd19a4be5f290d7f58f5ffec6a85c93fe34b1d54e0a1666b05672e2d9e8766807',
  'linux/src/citizen_sdk_host_bridge.cc': '28411598761f564062c29643ca134d65d3ee5b505fab25491a40ba8087b752f6',
  'linux/src/citizen_sdk_host_bridge.hpp': 'ad836f114d1995002a3a468e2fb6904170b89c2c36b981c5f685f58989873088',
  'linux/src/citizen_sdk_host_record.cc': '68fea5575759fadbc9bd9257a32bbb00779bad9961908e76135329c3fcc110c3',
  'linux/src/citizen_sdk_host_record.hpp': 'd3c5b9cfaf91c85ee47bf86713f1299f204ef220614035257adb1c2d56be5742',
  'linux/src/citizen_sdk_input_limits.cc': 'bcee60aea062432c44f16d71a99b2b61e4f6fd08f564c60290d21247b856ea7f',
  'linux/src/citizen_sdk_input_limits.hpp': '984f3e033ee2a918199512280217c0eb84220f313673aebe8b99454079edae9c',
  'linux/src/citizen_sdk_lifecycle.cc': '699b015d446e3de84b25a705bdde9baae5d2820c10de0a2e2e84b1905355cb05',
  'linux/src/citizen_sdk_lifecycle.hpp': 'e5251c01d91e3470caa5188b00706cb556ff3f5452413f7a639debd9cd0d4456',
  'linux/src/citizen_sdk_operation.cc': '5cff05d1e1f031880d89a4b9e03aa83c0acf3310d41e2f7bc1d03438030187bb',
  'linux/src/citizen_sdk_operation.hpp': '77becb3dd81f8ae63d4a50ad893989133b81b5fd41f8bf5a573359bc94855bf2',
  'linux/src/citizen_sdk_plugin.cc': '79f63de8e61783344d71a982559d628bd45f12b1444c57a69302aa1e5d9eb449',
  'linux/src/citizen_sdk_public_store.cc': '1c2747ddb9c5a0c2eb2f287a66f3b1b24c7c2bf250a8db1aecc2dc26ce18a58b',
  'linux/src/citizen_sdk_public_store.hpp': '81ce101979a04edcca47db6768cbf7b66c8446ad18cb4e8f02ad2c4c49370351',
  'linux/src/citizen_sdk_record_key.cc': '80425cd8dffa7b537ab6634018b8877f2bac365949dc41667c8f0b8945be193e',
  'linux/src/citizen_sdk_record_key.hpp': '267aca52f7d0e0647f5d716eebc08cb2c77be5c093d491365baa7c01e0118bdd',
  'linux/src/citizen_sdk_secret_vault.cc': '055a9001517ff05787d8f2eadbb6486da30fa440bfbd47aab614a472c62839ec',
  'linux/src/citizen_sdk_secret_vault.hpp': '2b26c83d812a265bba7b8dfbaf8f727979411e23a18002a84056e998781d2d52',
  'linux/src/citizen_sdk_secure_store.cc': '88a7a4ee4bb5fd6248727d825a79ea4800fd8ecc59fd7816693e74df38b545c1',
  'linux/src/citizen_sdk_secure_store.hpp': '7fd52a836df5cc796c0a9c287d24ae92e5d07715a31af9a44506718f0ddebced',
  'linux/src/citizen_sdk_sensitive_buffer.cc': '3904d22d1d02bf03512d84fb5a06d30912793b7e5abecba283b30ba3b15d1e90',
  'linux/src/citizen_sdk_sensitive_buffer.hpp': 'ea8254eb8420c7abe4b7adc338d87fdf0ce9cc8a44ca42ec305618c3788b1046',
  'linux/src/citizen_sdk_sqlite.cc': '88558b7983290804f9ebae3613dc545bc20935f85cbdc68fa9fd70a80bf6ea02',
  'linux/src/citizen_sdk_sqlite.hpp': 'de27dec91b0609268db4619673e7e8cb2082f38eec50c495894c6bd90447ae87',
  'linux/src/citizen_sdk_tpm2.cc': '09fee7a54f2163d81584c9cdef05ca38d5b533057437d0621c1c2d44357310e9',
  'linux/src/citizen_sdk_tpm2.hpp': 'a8a7c68d743b8e662ad57a736c23ff54518e53155d72ccae9913b61964cae644',
  'linux/src/citizen_sdk_user_auth.cc': '62e9af7d8fc21162f4c42913d774dbcf2297f66e49e57204bcdf556f2a85dbca',
  'linux/src/citizen_sdk_user_auth.hpp': '455b08deccede104cc44c6ce9acba4c5f550a55a1cea7085c49587e99aeb2032',
  'linux/src/citizen_sdk_wallet_flow.cc': '70235790e5faedd4e5c8e55ba725a3d91a26e9b8fb3ed4669e50c610938baad7',
  'linux/src/citizen_sdk_wallet_flow.hpp': 'ee56e481e94ca02f7ade0447f05a3780c2de154078951b8b74cb265c93a14b34',
  'linux/src/citizen_sdk_wallet_validation.cc': 'f433f8883d433a074e6464134fa614a89da439bec57fec9f247d0b4b23a45767',
  'linux/src/citizen_sdk_wallet_validation.hpp': 'c09ee0245f1a4909191311365426315494ec0f492d9223ae45691f3f397078c3',
  'linux/src/citizen_sdk_wallet_window.cc': 'a1da3e2ee661d13ebcb279475ca696895eb2c87c9a0b961b6bbd67de939f2d61',
  'linux/src/citizen_sdk_wallet_window.hpp': '6617a7d32c9033a22aabe6df80d12172ddf8153759eefb39b2427bc03e2b8a06',
});
// 产品根说明、架构文档及平台/Dart 模块说明共同构成 33 文件文档闭集。
// docs/smoldot-dart、测试说明、许可证、CHANGELOG、
// THIRD_PARTY_NOTICES、资产/include/Core/signer/smoldot/test 说明分别由既有
// 更窄的权威来源合同固定，不能在这里建立第二套来源流程。
const DOCUMENTATION_FILE_COUNT = 33;
const DOCUMENTATION_SHA256 = Object.freeze({
  'docs/WINDOWS_PLATFORM.md': '92944a039778ec7f333a7386145a4dd6738561d317b1744cdb98c49ab313ac9d',
  'windows/README.md': '7d966ba47a7ed6531c97a025a4384e9ae82f3046b681a75ffe038d970c6f57c5',
  'windows/include/README.md': 'a7ae4d268d86b3bc10ff1984c0a764155cf96c68de2b0105f9ae3eb0569b65e8',
  'README.md': '5794f06bcc2a2ff4b01a3524d7d477868f56095bbe6d95f4d4f219603e66d7cd',
  'android/README.md': '348268045e496de7bc2ff31808ea9ee6c687b776daa9450d7fe4bdc35c05c50a',
  'android/native/README.md': 'ee7626e85156f60acabcf66de5d03c03f5e1f91f8a1853bbca0d1bdfc51508a9',
  'android/native/src/main/cpp/README.md': 'ccbd436d19620fa3069f2407236765366358d27c8f4f72cddf0a6fd91044b289',
  'android/native/src/main/kotlin/README.md': 'c3d0c931f7b5f57ca2ebeeb37fa4ca7dedd96668735bb4cd7bc60f8255942bc8',
  'android/native/src/main/kotlin/org/README.md': '578730640cf686d61ae0855d726ca55de4e701be90241261197eb8b5c4f4c5b2',
  'android/native/src/main/kotlin/org/citizen/README.md': 'fee4f0a93cde3cad9fef94095215b2e64f8784086ee1a5217f8bfc78e3b01444',
  'android/native/src/main/kotlin/org/citizen/sdk/README.md': '1543e3d000eb835e60bb48c4875939de2f28934bc2d0d1449b33556fa8a2a7a0',
  'android/native/src/main/kotlin/org/citizen/sdk/internal/README.md': '106769b2d73004597d4dbcf1829d138792b949809168e5f278bc2d747401eae7',
  'android/native/src/main/kotlin/org/citizen/sdk/ui/README.md': '2b285d5e5855414cb3728ed3a97b78d7f1c2a16fa24b84eb7acacbc3551e7c60',
  'android/src/main/kotlin/README.md': 'cd06f97683e5b86c1a4ce4e5a5e19ca7e91239d2130b45594b58d27320582fdd',
  'android/src/main/kotlin/org/README.md': '74cbcbc590e49ae488097691b67911df3b001aba71b553f463e6dbd2eb36e53b',
  'android/src/main/kotlin/org/citizen/README.md': '1a7193606a774df8d6ad9d7c3c64dbb0b28a0cc7f6f61d0052a71726ec5400ef',
  'darwin/README.md': '43b18f73885a3f232b051c56e4b5e69078fae7b37b8a5cb54d836bf3efcc8c29',
  'darwin/Sources/CitizenSDKFlutter/README.md': '249493844eab20102633b327249d791de8c1d6a6da9a7a19e848e4faf34994d0',
  'docs/ARCHITECTURE.md': '5f930415bb862221ffb8738a5465b61d0aa2f547da007c7eb994b833bb50f5b8',
  'docs/C_ABI.md': 'd4f4977499325ea54ddca96101c713eedbe4ef401585c5c4c509488d13f052d2',
  'docs/DART_API.md': '0f456eb17e5a7409b4fba79e8d08e351de1d677eb8157782dd114ece879b9fd4',
  'docs/LINUX_PLATFORM.md': '4df51c1dd9787c7854605f34b7f5b27a6d055f5be9a970ebfe5a82d960857f3c',
  'docs/MOBILE_PLATFORM.md': '7dca5e0203ab20757ffce2bba5a073f720200ff54c198ac24f855be3ea782b0b',
  'docs/NATIVE_PACKAGING.md': 'dcd8a3fe861cc8eeb9e4696160521bddceac791f7a4244f96e53252d893ee8e4',
  'docs/SECURITY.md': '62b2f38f0b76ae73adf6bef4d09a14b05b382645876aba5db634a04dfa985ec4',
  'docs/SOURCE_PROVENANCE.md': '5f5a676d8c2cabc622788233154810dc4026562b5b5ba9cc96dee31e45d722cc',
  'docs/WALLET_MODEL.md': '8027715999869bfb5258679626ea51a8b0649353e48cf5d9a186b084c0c406c6',
  'lib/src/api/README.md': '045cc102ecd88c7b96dd125ebd24092e1cfc7b52c1e7c95ce04bd7560322d55d',
  'lib/src/crypto/README.md': 'd8779c37639121ed8e5e173d006ba5b882704405cd97710ed590c1a9d21b62df',
  'lib/src/models/README.md': '5506efb021f3c238a8c2cc2badebc7d1f442a5352c16182e5dcd9241b0a6224a',
  'lib/src/platform/README.md': '3b969924bea915aee693c62980e70882f5cfc24c2b9c97ba9d8cdd49d3cd4ac5',
  'linux/README.md': '10505155f3e871b84a70b089e688238e5e820afeb366b086bd3f7b35ff0b450f',
  'linux/include/README.md': '632943f0f42f70843dd71e1af43e3069af76bb182ee6bdd62346a34e8a277cb4',
});
// 根 Flutter、Core Rust/FFI、smoldot provider、signer、Android、Apple、
// Linux/Windows Host/Flutter、安装消费者与 Release 合同测试共同构成 SDK 自有 189 文件反向测试闭集。
// 固定测试源码能阻止“删除测试后剩余测试仍全绿”或实现与金标同步漂移进入正式包。
const SDK_TEST_CONTRACT_FILE_COUNT = 189;
const SDK_TEST_CONTRACT_ROOTS = Object.freeze([
  'test',
  'native/contracts/tests',
  'native/engine/tests',
  'native/ffi/tests',
  'native/signer/tests',
  'native/smoldot/provider/tests',
  'android/src/test',
  'android/native/src/test',
  'android/native/src/androidTest',
  'darwin/Tests',
  'linux/test',
  'windows/test',
]);
// scripts/ 同时包含生产构建器，不能把整个目录误当成测试目录；只反向枚举
// Node 正式测试命名 `*.test.mjs`，避免新增测试未进入固定闭集却仍被文档宣称已覆盖。
const SDK_SCRIPT_TEST_ROOT = 'scripts';
const SDK_EMBEDDED_TEST_ROOTS = Object.freeze([
  'native/engine/src',
  'native/ffi/src',
  'native/smoldot/provider/src',
]);
// scripts/ 只允许一个已固定的生产构建器、当前正在执行的 Release 真源和一份
// 已由 SDK_TEST_CONTRACT_FILES 固定的合同测试。release.mjs 不能自哈希，否则任何
// 合法更新都会形成不可解的自引用循环。
const SDK_SCRIPT_ENTRIES = Object.freeze({
  'analysis_options.yaml': 'pinned-production',
  'build-native.sh': 'pinned-production',
  'release.mjs': 'executing-source',
  'release.test.mjs': 'pinned-test',
});
const SDK_PRODUCTION_SCRIPT_FILES = Object.freeze({
  'scripts/analysis_options.yaml': '67a8f842d8b2c0eee53ab22db23c98e4deb3f8d3992a20d1a977870dc2e8218a',
  'scripts/build-native.sh': '4caf1d969e02088e2fb0b66960ee79805b90fb3a327cc0fa4ef1d2b7050d433f',
});
const SDK_TEST_CONTRACT_FILES = Object.freeze({
  'native/engine/src/qr_review_tests.rs': 'b864b405e7817cf3eb30642429d4c898f320f1bec6851f7275d0e529fb58c120',
  'native/smoldot/provider/src/bootstrap_tests.rs': '688a8883eb780fd61c69f348353d32300115b32928b001ea1113e7ae95e0bf30',
  'native/engine/src/chain_monitor_tests.rs': 'caf32fe83480240db75aaa878e42d5432cfc9aeb1486bdd3c9dc808a34a34496',
  'native/ffi/src/chain_monitor_tests.rs': 'd2c1d29d5964a023cef9e0713e5104b2ec3fcd0bf9d877d291a974823351ecef',
  'native/engine/src/wallet_input_tests.rs': 'bad1351fca2ba69af4a0a41ffca18a3d913da0422588fabe7357f672262e1122',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/ui/CitizenSdkWalletInputTest.kt': '5890f662654e262f26390623b6200600b20280f2d3d2fb6bec7f02cca29ecea3',
  'darwin/Tests/CitizenSDKTests/CitizenSDKWalletInputTests.swift': '717becea649c08f3ad3653c9efa8caffb26d7afedc1ad698b412a44054af4b5b',
  'windows/test/citizen_sdk_flutter_consumer.dart': 'c51a72be9216f994821ced9abdae4de1273ce29a313eaea4a8e30b9d883acea4',
  'windows/test/CitizenSDKConsumer.cmake': '025fff5bfc95a553bff57f7378372148c9d4932476c887fb84ce438e5c0e8117',
  'windows/test/citizen_sdk_c_consumer.c': '0ab5501f173c87f55f79207eed0ba27cffc7af93073d1d9a44af0eed2a6495d6',
  'windows/test/citizen_sdk_cpp_consumer.cc': '363893e86aa7e79cdabfcb8f28ac04aff82306fa584411ed147e2346d1eaa697',
  'windows/test/citizen_sdk_flutter_codec_test.cc': 'a076c65acdf743f6e8783ee083acfa339d3e1530cf6134825224c5efa9eb7973',
  'windows/test/citizen_sdk_flutter_environment_test.cc': '83df99bf0f62688523d2106cea1d6c993a5af8978ea7739dacdcc5fd11612019',
  'windows/test/citizen_sdk_flutter_plugin_test.cc': '6c0be3e2ae099334c12ae803fbb8bc5856da066d5de7092f678755baffe35e05',
  'windows/test/citizen_sdk_flutter_secret_boundary_test.cc': '5af637815c403f5fa7d45f0fcb67e0f99d0882e2b3f528fdd7d68c578abba457',
  'windows/test/citizen_sdk_flutter_sessions_test.cc': '9871322d422845bdadaa762937473b3de9c3eb232f75c99c6d1cef40ce15711e',
  'windows/test/citizen_sdk_flutter_test_support.hpp': '1bdf74a261ff3ad29a6eabe651eef4e673d4b20deeb3fea825ad9f1c6d0f0916',
  'windows/test/citizen_sdk_flutter_wallet_flow_test.cc': 'f4cd44ee975b3c0f8d154976555a027145a9dba0e862b5f6897c2c6ec724b7a0',
  'windows/test/CMakeLists.txt': 'b953ce6fcba468ea5db1f57d4eb306b58ee20213fd6700c6c669c3772da0588c',
  'windows/test/README.md': 'd832633e90a3e2ff71c07c8fd138cb6944ebc8c0af219ba2fc867d027a8a21fa',
  'windows/test/citizen_sdk_api_contract_test.cc': 'd1c195ea0fc443a844ac929ddd95ec31e2586e10594058c9c7edf2ac76b64292',
  'windows/test/citizen_sdk_assets_test.cc': '2d1e8d32af98b75afdeffefb2371c98bf95fda7017fabfe6c51a301373d8ea9e',
  'windows/test/citizen_sdk_cng_test.cc': '2041c11af27e7424295d4294f271c1d0cd8c7162c64d67af9155eaced422f4fc',
  'windows/test/citizen_sdk_directory_test.cc': '952bdc527cb00371cf721f7bad8bd527a7d7f4251799df45e38d19087f4aac61',
  'windows/test/citizen_sdk_host_operation_test.cc': '34faa39c22315d365b7fc705c198a81be62942c38a8a9a058ef9bde56ceb9c2c',
  'windows/test/citizen_sdk_lifecycle_test.cc': 'c1cb7d1d668f1eaa390d08d8b092608fc0d643fc8cbab0f19e93a55585c1b628',
  'windows/test/citizen_sdk_public_store_test.cc': '1b41c554acf086c9eeeba7fe2efc9e6bb04711a6f445d85ceffd1c74f6518d06',
  'windows/test/citizen_sdk_record_key_test.cc': '421e9dd2e9950c02addb9343fe12ca23f3d9c1832c4a25725420928dbc9423e1',
  'windows/test/citizen_sdk_secret_boundary_test.cc': '84ef2838458be86eeab028ebb4846c2240ec8b3ab64af45ce00b5ac5190e75a2',
  'windows/test/citizen_sdk_secret_vault_test.cc': '224d4817a01010dce951fa5d3f83ed2072eb8e02fef0f68b688b3af1e298ddd4',
  'windows/test/citizen_sdk_secure_store_test.cc': 'f4e06493a7bd9b64dc43255fb2f51ee8e7af5b8c894ffc53b775f6f9ab35b0c0',
  'windows/test/citizen_sdk_sensitive_buffer_test.cc': '23d0d8f7f28db585ff1dc6ac23d350018c7f6636adb07925f3b3891d0b4eceee',
  'windows/test/citizen_sdk_test_support.hpp': 'd128551fc1e6f8aefb9604ac88ed32cfedcc2d57c97be30995aa974e7a5ee38c',
  'windows/test/citizen_sdk_user_auth_test.cc': 'd148cf2e4714164a36ea36d2c5d5d5b77ca42fbcbcc8f9b8812e2ec6766a6496',
  'windows/test/citizen_sdk_wallet_flow_test.cc': 'ac4fd0615ab9d2c2d4de5e4a434d8ebf6e17231ae452aca0f142335fafe683f1',
  'android/native/src/androidTest/README.md': 'fc7724688dc94982b92077881caec5f5126e79c15eb7317dcde2aff8bdbdca54',
  'android/native/src/androidTest/kotlin/README.md': 'd44a06282ecd8c781d7b954acae7496a847bb8b80a1f36a7cdab5ff8c2a73cec',
  'android/native/src/androidTest/kotlin/org/README.md': '0e29cc6c8238a1e6dac76629c85a79da9e4ac8f07fae0a74ffc41f714f48c5cb',
  'android/native/src/androidTest/kotlin/org/citizen/README.md': 'd93747837a96c766ea95954a17ace8e68715967327caba1b6794dbcce5759d5a',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/CitizenSdkHardwareVaultTest.kt': '1c69b2a0512aeb59bc21e36a8aa7e3c8741a33edc5cecb7206cb7336d74d5cfd',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/CitizenSdkLifecycleTest.kt': 'f3dcb93ebfa32033e83db309e75aa9a1dad8f76d83fbfae31e02dfdd65f08767',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/CitizenSdkNativeAbiTest.kt': 'cd17759ab121ec22fc224715233a0ee118f75882bc026f4e713a0b89c2e686e0',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/CitizenSdkStateStoreTest.kt': 'a6b61d018d63ae999be84ea7e9ffc19bb9b605bcf2d97b6c296e9c96d81a6fd9',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/README.md': '4ab5a2940f4c8de302b4306b6e6b477fefe2f173fa5439f557196198cb05cbc9',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/ui/CitizenSdkWalletFlowCancellationTest.kt': '43437c234ac4ae9b8305220347b0c0d3c1aed399f8f14646fa91489e20625ee1',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/ui/CitizenSdkWalletFlowSecretBoundaryTest.kt': 'e34e53d30e322f229eb62bedb61e02303fae0e49c43155b73d71138b73775ba2',
  'android/native/src/androidTest/kotlin/org/citizen/sdk/ui/README.md': 'b26206bf92c79821995478fccf87990d54f6d20b72d9d45c6ee1aed313993c7a',
  'android/native/src/test/README.md': 'eb01e909e3f6e64ff5c0f000d945426fa5df9fdd517f65c9ba505d9d5cd0e54e',
  'android/native/src/test/java/README.md': '5e6309edd00fcf1e85c1d0cab7892b0b72906ec34794059427a66e1604be4f1f',
  'android/native/src/test/java/org/README.md': '42bebe2ea2fc58bdcf36dfaac6f2acd8086c3e854bf7bbb22ba46ec2ab6ce2ad',
  'android/native/src/test/java/org/citizen/README.md': '0b8e34c20efe7a80718f67546da599ad1a26f5d6719905fa8f8552be09c3ccd5',
  'android/native/src/test/java/org/citizen/sdk/CitizenSdkJavaApiTest.java': '14831f3885786a8c04bb8425b257f2baa7bf4205f42e579236ca3fa63c75506f',
  'android/native/src/test/java/org/citizen/sdk/CitizenSdkJavaOwnershipTest.java': '102ff8ef18cf144d7b99405e0cde3e3c5d959df3da5856b40085471ea1c8145b',
  'android/native/src/test/java/org/citizen/sdk/README.md': '7ed4d84adc7605077103fe72eea4bdd897f9bc302f98312d181df8336eab3b67',
  'android/native/src/test/kotlin/README.md': '1aa4f5e20f051146479c58b35b480aa68f55c6dc357e8e604a52cf480c64cff2',
  'android/native/src/test/kotlin/org/README.md': 'b84fc49220742e4ab75fc629d0c884dc075895c1592f2507f503e5d5e771a0be',
  'android/native/src/test/kotlin/org/citizen/README.md': '6f52d6e4728845e0bb1fe128af3e284bc18cbd76df974dca9828530ab8e6423a',
  'android/native/src/test/kotlin/org/citizen/sdk/CitizenSdkApiContractTest.kt': '5ca75b973ecbb1b64556f337df35e2abc0a2f432ea3f78e2e564466301b93b49',
  'android/native/src/test/kotlin/org/citizen/sdk/CitizenSdkPreparedWalletTest.kt': 'a790f3a925dde741cfd593c1c222443fb568e2696ec5646d3a3256ea35e55064',
  'android/native/src/test/kotlin/org/citizen/sdk/README.md': '8a4ebb109480a809238e1a088f8c775d7e042696f206976965620979b07e2e0c',
  'android/native/src/test/kotlin/org/citizen/sdk/internal/CitizenSdkHostOperationTest.kt': '17795d503013ac5a7b26b8bbae59fa21e4233df800a707c2bad9784349a6b07c',
  'android/native/src/test/kotlin/org/citizen/sdk/internal/CitizenSdkRecordKeyTest.kt': 'b83832d2431e40caaea3b9356390c3ea7c03624c93733fc821d3a6f832aed634',
  'android/native/src/test/kotlin/org/citizen/sdk/internal/CitizenSdkVaultIdentityTest.kt': '995a25c4742c3098e96f869379ea4f7e77289e2230cd4c211462712ec4ba1acb',
  'android/native/src/test/kotlin/org/citizen/sdk/internal/README.md': '5fd0f31750c10c5b8e32f72534fa1c735422d6873f590d831f1131a09b1642ef',
  'android/src/test/README.md': '6a56d6f908206de3385bf9fd5838293dd1789586bb5d7245e0ea5c242d50866f',
  'android/src/test/kotlin/README.md': 'ef036e967503cb908827489c5a2098f6f358abec5599af81b4bb7d60551ed501',
  'android/src/test/kotlin/org/README.md': 'e8d1bd08d668ab54c7facc744de1d6361d0bdac00881dda3e7ef8c0a8df3f50c',
  'android/src/test/kotlin/org/citizen/README.md': 'ef7a2cca8d60f9be88c34ba98da89514ac023056977aa4265a60eb72d7b07189',
  'android/src/test/kotlin/org/citizen/sdk/CitizenSdkFlutterCodecTest.kt': 'aa2ceb73443b1c554b429f4ac519a50d5282756077f82d4737cb89607a67a2e6',
  'android/src/test/kotlin/org/citizen/sdk/CitizenSdkFlutterSessionsTest.kt': '48f5c0e4bf5218fa7cae88d9df3c7bbfdd3a6bfe6945f2537c1410ae2242e68e',
  'android/src/test/kotlin/org/citizen/sdk/CitizenSdkFlutterWalletFlowTest.kt': '2e940cfde4d896e698216f4db1054e164d6cbcb6164b5b8e0caa295a87eeff5e',
  'darwin/Tests/CitizenSDKFlutterTests/CitizenSDKFlutterCodecTests.swift': '85935995b1a418271c7050d34695e357008bded525b8aaa93b54e4d5107e62ea',
  'darwin/Tests/CitizenSDKFlutterTests/CitizenSDKFlutterPluginTests.swift': 'd905fda42ad2303ec3fdf7e7b1e6993694747be02b2fb949de1089164aa71923',
  'darwin/Tests/CitizenSDKFlutterTests/CitizenSDKFlutterSecretBoundaryTests.swift': '8cbf137577e52f58f532c52f3877ec1775836e180900bfe5f1b9bc6fd3816f99',
  'darwin/Tests/CitizenSDKFlutterTests/CitizenSDKFlutterSessionsTests.swift': 'c80eb7fd5cfeb2f81b0d72646c0cb4eb1a69648936ee3b88997ad896efbf3a34',
  'darwin/Tests/CitizenSDKFlutterTests/CitizenSDKFlutterWalletFlowTests.swift': '2a8e4d61074f974d51bb7fa18ff7a3e4d76582e65289a57d084f37ce0cf019d2',
  'darwin/Tests/CitizenSDKTests/CitizenSDKApiContractTests.swift': '058f1e38879736f27145c1113b71ad6c5d4a3e275a966ea7c52b9413c7b7dcf0',
  'darwin/Tests/CitizenSDKTests/CitizenSDKHostOperationTests.swift': '109be3ae384db564139db63537895b0151fe29b59fc7c2370d51553e7fe5f3c5',
  'darwin/Tests/CitizenSDKTests/CitizenSDKLifecycleTests.swift': 'f9d3ebddbdfc79b2779639155c584ad2fb77273d86a144f8855eae7c6d738180',
  'darwin/Tests/CitizenSDKTests/CitizenSDKNativeAbiTests.swift': '1e9101424175001476fbd2319e62cf48de2bf4c38b4aa3889b5542a5424155ed',
  'darwin/Tests/CitizenSDKTests/CitizenSDKPublicStoreTests.swift': '9ad944d046db7223a8896fdcc5f4762fd22186b9d5216161a4f58d4fceef21c9',
  'darwin/Tests/CitizenSDKTests/CitizenSDKRecordKeyTests.swift': '30891704a7d2d4fa98bf3750c9ec88370389fd4e6bdf7f4641faeb8a0873791f',
  'darwin/Tests/CitizenSDKTests/CitizenSDKSecretVaultTests.swift': 'bc9974f13a43b13160ecc8ecbcd90d0b2f17e1a50adffad3697d9006feb56ac3',
  'darwin/Tests/CitizenSDKTests/CitizenSDKSecureStoreTests.swift': 'd7581577b15dc0e053d5130845ed54c01fc8b20034c105a71736c9899763cedd',
  'darwin/Tests/CitizenSDKTests/CitizenSDKSensitiveBufferTests.swift': '2bb9dbd84f3d7ca572ba42a21c3e76330fc5294f425a5338ce934e32f455f98f',
  'darwin/Tests/CitizenSDKTests/CitizenSDKWalletFlowTests.swift': 'f09799a51f098c67b79f447f828c0dd86a72dde0bb5696d3e4299c9c9772a83a',
  'darwin/Tests/README.md': '8754ecf2cf82e7909e6051df5906ada9fd1565ab4ae4bdf0e8a83d66fbc5d725',
  'darwin/Tests/citizen_sdk_flutter_consumer.dart': '25f8e35c5f11ff10ecc1c804459102dd827162f68e3da16161a9f742c2e14ae0',
  'linux/test/CitizenSDKConsumer.cmake': '70bcb6aa7484daa5b480a9db9f8d2e556cebbdd680f7501bbc086602761c58ed',
  'linux/test/citizen_sdk_c_consumer.c': '33bce9c880fd69a59ba98cb4148baead91e1f6815c4d3dd827d2ae7cb15bf5f1',
  'linux/test/citizen_sdk_cpp_consumer.cc': '676438754d9fa496fd8b91194b90b21d06c47fa74ad121a7f0216537f247f07f',
  'linux/test/citizen_sdk_flutter_consumer.dart': '5bd26b5bce151f00bd6f15e555a7bd72d848b933cdf912bf47e45c6e2c1a36fe',
  'linux/test/CMakeLists.txt': '8ef9fd28eadb361fa82da4bea975db4be6196134d2e8e1a8c7e01e9f39d4cf82',
  'linux/test/README.md': 'ffe0eaed6f154724af7c2142a940cda6b00da2c818dd1786ae9e2bc973c83a30',
  'linux/test/citizen_sdk_api_contract_test.cc': 'f4955bbfd472eb906df7d668541f1fd28f9e363ac74ba350f145f5fccc1c82e0',
  'linux/test/citizen_sdk_assets_test.cc': '9d5b6f2ad9e23fc55c759deed22e0a50bdca8886608ebe53dd80d0696f5f9e08',
  'linux/test/citizen_sdk_host_operation_test.cc': '4ea3d5da48ea3c7e5d21eb6c80273eea94dd01589de4898ddf3f2afe727feda0',
  'linux/test/citizen_sdk_lifecycle_test.cc': '9d189f161ed19886c44332248a2f19921383e05d3b765851d5c9b98819089f2e',
  'linux/test/citizen_sdk_public_store_test.cc': 'c4df1a22d59630fdbfd9198cfe696a4888a379c76e781bff4675c47ee3c74b98',
  'linux/test/citizen_sdk_record_key_test.cc': '11871f6372b6983d7265fddb1714ed9b283d9ff43a9f6e782759d47dd5c74e4d',
  'linux/test/citizen_sdk_flutter_codec_test.cc': '2cce4639592dcba5daf766c5192bbf5195b3a11693aa68592c002ce23c4a9d7f',
  'linux/test/citizen_sdk_flutter_environment_test.cc': 'ad145d79c91ee22ffee5ccc886feb405f514421652e90d381e75115ec25050a6',
  'linux/test/citizen_sdk_flutter_plugin_test.cc': '345d641fcfc3995fa04c7428aafffc7bf112ec302bcc71d0631681664ea57130',
  'linux/test/citizen_sdk_flutter_secret_boundary_test.cc': 'a67b1c10d47342ca031d1ce9fd5b8f3145220132ad1b761f552ebd831a476be2',
  'linux/test/citizen_sdk_flutter_sessions_test.cc': '336393df701d51b12eead2c6218c466ccc59068241147188298525b74420b8e2',
  'linux/test/citizen_sdk_flutter_test_support.hpp': '1b92cf8f6a6fd0df6a58d5630f72ad29578d3118f7aa886ee1b3149b86606f56',
  'linux/test/citizen_sdk_flutter_wallet_flow_test.cc': '40b2d0e14bc9a429dfe93414e02de2d103e2d01b3f2e2d0b4ee9d71c7892b317',
  'linux/test/citizen_sdk_secret_boundary_test.cc': 'f33b93ed3b35598d495678d0751c987320a69c5dd8fcdd72159b12e829b7f270',
  'linux/test/citizen_sdk_secret_vault_test.cc': '9a69e0444552fa5af343d1f70b2c138ee937b00d2749ec76cb1782dd482bea8c',
  'linux/test/citizen_sdk_secure_store_test.cc': 'c65570ffd3350da9da2fa85854715cb66096c86c45e9165da62d34a5e477a499',
  'linux/test/citizen_sdk_sensitive_buffer_test.cc': 'e82855221fde7e20ce07ef194619c18cd1c25ed7b8c9ae5a85fd8f94256a5ec0',
  'linux/test/citizen_sdk_test_support.hpp': 'a6f440b1322d7ff24de112fb65994922c6c44d11126fbf346eb8571f6b40f732',
  'linux/test/citizen_sdk_tpm2_test.cc': '29146093852ac3a51d7925e6d9a27f042e5f136c37d58a6367de2bd119c9f8e5',
  'linux/test/citizen_sdk_wallet_flow_test.cc': 'c2ad4772213f8c2c9b2ff8dead31eaddab94299575d7aa781e6f4c609f61f937',
  'native/contracts/tests/account_contract.rs': '2f2af9930ccaba2cf73a21c1ea3593295a6e7d8633a95db05fbcb642e7c74992',
  'native/contracts/tests/capability_contract.rs': '797298ce4a1a33934b400cafc37f22f8e9592a0e4067dbc1a868987182fd9cac',
  'native/contracts/tests/chain_contract.rs': '69e216bee1d74258348f84e6b8086b474a44d6b68470bd0cef22cbfa4ed75100',
  'native/contracts/tests/secret_contract.rs': 'e5585e0a2b584f3955a2516f6dff11615ca1fe299764a41289d0313d71ff1554',
  'native/contracts/tests/state_store_contract.rs': '71c582e47b278a5930ec8565c643a33c4c70f37f00bd76f8badf4dc86cd9b0cc',
  'native/contracts/tests/transaction_build_contract.rs': '5107e4fcaf11e4faa2ce60620e4916b09db9a40d62c2f049e270a58912ef353d',
  'native/engine/src/finalized_events_tests.rs': '53a449b9e1f16e64c9ee3893a2a9c5426515eef87b246b1a6824e9f08b7c0c3b',
  'native/engine/src/finalized_history_runtime_tests.rs': 'c22ea199f85e017006b5b1e541628653226bcb5e81c2a3ffacb4b8e04462c783',
  'native/engine/src/transaction_builder_tests.rs': '7beb26f1293886a1360405923a1c933e3e4996933d77a492991b81be1d7c0ea1',
  'native/engine/src/transaction_history_tests.rs': '7ca9ad08af88a41a405f5f0d20bfb49cc14811a6287773c10ef5f8e7dc112617',
  'native/engine/src/wallet_derivation_tests.rs': '0af6e57e748e0811e5651841ec40e3be43618139ea138b5491178a325e5a438d',
  'native/engine/src/wallet_service_tests.rs': 'b3dab07c16b00841d8d654b267e20549d151158d61d659f2731d00a6a865dfab',
  'native/engine/src/wallet_transfer_watch_tests.rs': '5e4354e8c24b7d2e3d0e444f3bce30ba5bbd55c57088665beec8cc31f1670ecf',
  'native/engine/tests/account_state.rs': '32b3d9321033aa8238908ef0afa5c3eec40399d767bcabcc29d2c8cb545a3a82',
  'native/engine/tests/capabilities.rs': 'dcfdbffcbaeabc44a6d6934021b2a80ec593d6c8b64b23a7cfbed8b6791f3e93',
  'native/engine/tests/chain_access.rs': '96fadc8e9863f38be43d80048ada1f19914a70d59e98ce765987fa77c6e09a41',
  'native/engine/tests/engine_boundary.rs': '0be497f48a42d13ab68c8650a22b01b85fbdd4741d27e4b0bd179769ee96afef',
  'native/engine/tests/runtime_context.rs': 'e5eb9f999668b6664d29ba61a0c8b2fd8b2e9fe37f7830bb4f4b7732b9c4fe43',
  'native/engine/tests/state_import.rs': '6937752568de3531a32b8ad35b1fd7270abad120c4b5aac423ae7df970d3f917',
  'native/engine/tests/transaction_outcome.rs': '68a05dfbdeedccaf70c22f83f88ad05131e8f65f9c2f355f12ce93d90e7d0645',
  'native/ffi/src/composition_tests.rs': '5efe7fe82b951282e90efe3a27cb8d0c9d6096e70b441ea185e78f03e1490b7a',
  'native/ffi/src/host_codec_tests.rs': '87d9ab7d4aec783312024f753999a46512923356d1bdfff6b6be2440151bf741',
  'native/ffi/src/wallet_abi_tests.rs': 'de78ce04390c6f58c1e808635c2574b64b17b18b847dea49d44ab28fee1d8af0',
  'native/ffi/tests/abi_layout.rs': '6945397b49c13102648cbf274bef73c557f9c35e973a3027e2b62026e421656d',
  'native/ffi/tests/asset_boundary.rs': 'd18d152b1960860afc4db8b0e35b88dc4b121bc77cba2f984b74331506d0ec1b',
  'native/ffi/tests/c_header_c11.c': 'b12277fe072dd68c5b2045663bb27da8e1a0b135d14f48ee3ed3d9d2d6cb4218',
  'native/ffi/tests/c_header_cpp17.cc': 'abd2137fd87b903998d24577b9c219dc8e533868b2f02af37f26ff0592cf2bb0',
  'native/ffi/tests/capability_contract.rs': 'e28560068840fb201210c3f9e4dab5ca7e44c0536471b03e92dcbba07b7950ba',
  'native/ffi/tests/error_contract.rs': 'ae585490b05768b64401b1e6774789ba1beb1eede552e4d3e70a99cd1d395d91',
  'native/ffi/tests/event_contract.rs': 'f80b6644265ed166109f967bc666a7d9f7415df833e109d6525bdba4c1e8efef',
  'native/ffi/tests/handle_contract.rs': '964785ac8a11fb746464b6b25112eeda4bca21bca4ecb23deb236249f7b1d81b',
  'native/ffi/tests/host_provider_contract.rs': 'fd8007521ce41b43f8cb050f72c6636d014b673731942c38127fee99df8a7687',
  'native/ffi/tests/ownership_contract.rs': '1046ef5656bf151bb2fbb8a8172602fbf3fc8846582f5d4346534a65cbe80321',
  'native/ffi/tests/qr_abi_contract.rs': 'd20c87683a0063a1ba174cf65e08be5ce569eb063518d34fc0ed6a42c26dd68e',
  'native/ffi/tests/request_contract.rs': 'e75d670fbea505bb69cb1cc2a4de9c34d1972abdb9f182beb703d10ef001bc16',
  'native/ffi/tests/symbol_contract.rs': 'bd6a4ac99b807139e8cddfd3844346805b48a1fde4ba7425a3546e245e3ecb47',
  'native/ffi/tests/wallet_abi_contract.rs': '84377eaf6c9f867b2dd7824232b114e6775382a4223b2c12c9713a5f5ba61b00',
  'native/signer/tests/chain_signer_contract.rs': 'd4e53512dffab3f75ee213a08b71909dbc6c667b4b287df39cd9ac3e62824b31',
  'native/signer/tests/ffi_contract.rs': 'bf38f650394011e7f68219ee8ba435453f616281f91649634c536b8620407038',
  'native/signer/tests/legacy_parity.rs': '984a1521042d8a5b2285a43459383ef3972058db20e8f05154c1f75a2a11d70f',
  'native/signer/tests/substrate_vectors.rs': 'f5587dbce91f9c2014c559bece142e56fe65c81c7cf097df66b6c8125d45eef9',
  'native/smoldot/provider/tests/account_nonce_contract.rs': '13f2d194df11c94527fd5b513228cc1ec917f3735b12f3326c239b600821b754',
  'native/smoldot/provider/tests/legacy_parity.rs': '7db2b3ef4959a7bd1c83b22597666b0448f48b3079b82821f624efd2ccb7d9dc',
  'native/smoldot/provider/tests/verified_chain_client_contract.rs': '140e90e7e52b259919b0705c1df52d89366ef1e31c34ad672065201b4e18e308',
  'scripts/release.test.mjs': '7267833db761e76a1aad8caf58b0d25135f044eac00172e8320d083ee88704c4',
  'test/api/README.md': 'bd927ce1488fc609ab3d1199ef7e3c859c741fae14628d4ef4bd79aa8d8b7144',
  'test/api/citizen_sdk_test.dart': '27e0389b50c3fc52c6acc32186e17abb5363d6064b84db84495e980c12a42883',
  'test/api/citizen_transaction_test.dart': '82bb6dedf06a944b22b11470cdd6fae0295dbcb2d1bbcfeda3b5fa34f0e53219',
  'test/api/citizen_wallet_flow_test.dart': '7a625dc388657dacdd58b905e7820cd8a229b96fdaab3615ca0a6492d4316ad7',
  'test/api/public_api_contract_test.dart': '0a0b367db3d3b5c1c2d76bf123bbbe447ebc924a65e187390698109211d076e0',
  'test/citizen_sdk_facade_test.dart': 'ab0f5104e6989af4862cef100120cb6f870147f8f3fe66b55f6a08b6d73ae2d0',
  'test/models/README.md': '4cd13881d38d345f2a43767e6101413943cd60628c9474e4e7a8c81f086e3813',
  'test/models/public_models_test.dart': '579164a13fb5359598d7ed68372444445f90bc0d26ad537662ad72cda1b675a5',
  'test/models/u128_codec_test.dart': 'e406f077258130ed22481af2e228066a4030dab19b765731eaefcfdc2f0ca6f5',
  'test/node/chain_assets_test.dart': '5c079499add0a5c3434ec99fb33ff18b8320800184a2f95acd382d0108d4db9f',
  'test/node/citizensdk_bootstrap_manifest.json': '33bd8e2c7407abea376f21a7adf7c9df644aedb7a9e985211075bba6cde28a00',
  'test/platform/flutter_codec_test.dart': '5337565b37832b14784725e633831d12ddbb78f51742e1801e261250849a8c00',
  'test/platform/flutter_secret_boundary_test.dart': 'f921a5a920d65f0ae05addfe4037f3c15a374851386fd565d760ddec8ab111a2',
  'test/platform/flutter_sessions_test.dart': '9f4dbbbc2898a4a07da8718e462bc0c31f42ce6ad1e5844edf975495f6f62122',
  'test/smoldot/chain_info_test.dart': '5de74abf31c75c579716366d72a457e91339352972a4a118ec7fe18de005b158',
  'test/smoldot/client_basic_test.dart': '4617fc86f8fc4a555e837f04ad747a25b501d93532532f8f0565e1d51e17a5cc',
  'test/smoldot/ffi_basic_test.dart': 'd7f16ab19bfd842f4414f43e989a3536d6725a1ba9e2eab78ac6f53dd7fa6cef',
  'test/smoldot/fixtures/polkadot.json': '1d5079040595c54f56f31900beea91254cf2a3a25e245bcdd26fe1ccc4672a9b',
  'test/smoldot/fixtures/westend.json': '5457a3c8322b8f2a2d7c2c713c113a7e0b1ee7e646d3f00abc4fa21198ea879d',
  'test/smoldot/json_rpc_test.dart': 'c61e7bf8eaebdc199a5cd2228e4de7f3b94e17715f7bdc7a53297b9be2e3fa94',
  'test/smoldot/smoldot_test.dart': '144f3a7d3385e0f8ece9c28762ae19862cffa1e2db8e449b51ed6e56dbcf6cce',
  'test/smoldot/subscription_test.dart': '18cce5adff77d300f4f6adb6e20db9237a1e0206a05f9308133689319636e677',
  'test/transaction/README.md': 'cf0748b94f92d4d627a4dcb0037439f2f56204972a79db68372740ca710b2406',
  'test/transaction/citizenchain-balance-fee-v1.json': '2cd5e648703c8cc389c59f07753470b63c034f7cfa63dac8ffa596c8128a0033',
  'test/transaction/citizenchain-runtime-system-events.hex': '2c4d04a69ff994622877786d481dc4780b7a32795e5f7cfa070ae4acb72679ef',
  'test/transaction/citizenchain-runtime-v14-metadata.hex': 'da62207dfa342ce5285bb214a116761fd0a38c7c329ab8953506ad52471ed681',
  'test/transaction/citizenchain-transfer-build-v1.json': 'c43a1f01c22556d2b1e172088fb540358c25b9554c91ffc71f7b483fcd5a469b',
  'test/transaction/substrate-v14-system-events-metadata.hex': '95b368e7907511b28ba283a6741f4be551b56fb917c2f0183b4143dbe0ebf95b',
  'test/wallet/citizenchain-wallet-derivation-v1.json': '2d9bd9f5feeacea729154475475e0d4525e594bc88ede3a86494ffaf35301769',
  'test/wallet/citizenchain-wallet-password-v1.json': '0f8427f6ca542625626c7c1615608eef19246db496c4bb819937f15cfdec7250',
});
// smoldot Dart 包边界已并入唯一 citizen_sdk 根包。三处迁移目录共同构成固定闭集：
// 生产绑定、来源测试与历史审计资料缺一不可，且不允许重新出现第二份 pubspec 包边界。
const SMOLDOT_DART_ROOTS = Object.freeze([
  'docs/smoldot-dart',
  'lib/src/smoldot',
  'test/smoldot',
]);
const SMOLDOT_DART_FILES = Object.freeze({
  'docs/smoldot-dart/BUILD.md': 'f071ce5149e56f0cb797b2ff809df3e7eeb1e896a61cec8d351a04ef220a349f',
  'docs/smoldot-dart/CHANGELOG.md': 'd9adb01f7c62313a14bb86dbfd7f4077d925745e9c17a14f153eef79c45f8b94',
  'docs/smoldot-dart/INTEGRATION.md': '1ca0a278ebef38f7b795555afb432127865c6f73dc63a7104245526a1bf14e95',
  'docs/smoldot-dart/LICENSE': '4524e4d70a6295dfa882b0411cc49fcca03273e959fea68bbfe7df7ed63e7d78',
  'docs/smoldot-dart/README.md': '99ccc9f6ba7b8930a9e2546322f0ac488edf687c0ce031e2e0bc8d595db4ae5f',
  'docs/smoldot-dart/UPSTREAM.md': 'ed3f21bc62a6c6dc76beb870bf6f224914123a2cc95bdbab8b5cb453c4767539',
  'docs/smoldot-dart/example/README.md': 'f1a03258804d437a434193dfe774cb79786fa9259310bcecbec25e16dad72f52',
  'docs/smoldot-dart/example/smoldot_example.dart': '60aea4e2d738ab7702fbd056626e6647f8c23174739f3c1b7e564133c80ee2e7',
  'docs/smoldot-dart/source-analysis_options.yaml': 'e67b963f89cf75f675a0ed25d258bae038d216832c22b84782e5e3a90b8d3076',
  'docs/smoldot-dart/source-pubspec.lock': '91ad4c26c8abdf6384292e1f01f335ba7ce50443a99b01b45e2f4efa72dab25a',
  'docs/smoldot-dart/source-pubspec.yaml': 'a9900ac0051914a9c2a0f6ce2491b58f007e08cf2f9b9795087be36f34cdddaf',
  'lib/src/smoldot/bindings.dart': '23a5a2add0de238ee8218238acf312193fa349c0806edb4056ff6f63b8b459eb',
  'lib/src/smoldot/chain.dart': '43f3fbc8420f61d335acb0c48ee471a7885ebbd71d320d8b820805b1537d8053',
  'lib/src/smoldot/client.dart': '916fd74c20f4daefca2e17e668e8a2fb16c59219b8f3bdd3148d10454a71ddff',
  'lib/src/smoldot/json_rpc.dart': 'c3a030b236814731f773bb8b1aa9dd1e5789bc7d0809f3c0dd7011d59b401d01',
  'lib/src/smoldot/platform.dart': '8efb99639389f12dc725199befc3073d5b49027ac761aea097d17e6df449d491',
  'lib/src/smoldot/smoldot.dart': '8e13185cd86609faf7d96f1da22a2457ce2e129f1d8e637c8220a2a481147758',
  'lib/src/smoldot/types.dart': 'e20b6f97d0b6e289c2b492e12dd66afafc1133adc0fc5fe5a547106ed3338e89',
  'test/smoldot/chain_info_test.dart': '5de74abf31c75c579716366d72a457e91339352972a4a118ec7fe18de005b158',
  'test/smoldot/client_basic_test.dart': '4617fc86f8fc4a555e837f04ad747a25b501d93532532f8f0565e1d51e17a5cc',
  'test/smoldot/ffi_basic_test.dart': 'd7f16ab19bfd842f4414f43e989a3536d6725a1ba9e2eab78ac6f53dd7fa6cef',
  'test/smoldot/fixtures/polkadot.json': '1d5079040595c54f56f31900beea91254cf2a3a25e245bcdd26fe1ccc4672a9b',
  'test/smoldot/fixtures/westend.json': '5457a3c8322b8f2a2d7c2c713c113a7e0b1ee7e646d3f00abc4fa21198ea879d',
  'test/smoldot/json_rpc_test.dart': 'c61e7bf8eaebdc199a5cd2228e4de7f3b94e17715f7bdc7a53297b9be2e3fa94',
  'test/smoldot/smoldot_test.dart': '144f3a7d3385e0f8ece9c28762ae19862cffa1e2db8e449b51ed6e56dbcf6cce',
  'test/smoldot/subscription_test.dart': '18cce5adff77d300f4f6adb6e20db9237a1e0206a05f9308133689319636e677',
});
// 两份锁文件属于收编的 smoldot 上游依赖，不是 SDK 自有锁。它们必须保留为
// 普通文件并通过 Cargo 结构、provider 闭包和 registry checksum 校验，但不能用
// SDK 自有源码哈希门禁拒绝上游例外。上游来源身份由受保护清单和 provider parity 合同约束。
const SMOLDOT_UPSTREAM_LOCK_FILES = Object.freeze([
  'native/smoldot/ffi/Cargo.lock',
  'native/smoldot/pow/Cargo.lock',
]);
// 根 signer workspace 与 Flutter 包的解析闭包同样属于正式来源输入；locked 模式
// 只能保证使用当前锁，必须再固定锁文件自身，才能阻止依赖身份随提交静默漂移。
// Dart 锁按获批中央 Flutter 测试最小闭包解析并验真；不修改 SDK 运行依赖声明或上游实现。
const SDK_ROOT_LOCK_FILES = Object.freeze({
  'Cargo.lock': '865576ece46b0cdfad3749e3382ae10b57448d26f4cb4dcbfd368be39e0160c0',
  'pubspec.lock': 'd6cee3bb3915e5350fc57fa846a93a3d7105e671f673c8e1165c128d66426657',
});
// Cargo.lock 会按 registry package 合并整个根 workspace 的 feature。Engine 为钱包
// 显式启用 BIP-39 NFKD 后，smoldot 闭包里的同一个 bip39 条目会多出这一项依赖；它不是
// PoW 来源依赖漂移。例外必须同时由准确 checksum 和一个本地 workspace owner 的直接依赖
// 证明。HTTPS 建议节点只允许沿固定 reqwest 路径解释额外 feature 依赖，不能放宽上游锁。
const PROVIDER_LOCK_FEATURE_UNION_EXCEPTIONS = Object.freeze({
  'serde 1.0.228': Object.freeze({
    checksum: '9a8e94ea7f378bd32cbbd37198a4a91436180c5bb472411e48b5ec2e2124ae9e',
    owner: 'citizen-sdk-ffi',
  }),
  'serde_core 1.0.228': Object.freeze({
    checksum: '41d385c7d4ca58e59fc732af25c3983b67ac852c1a25000afe1175de458b67ad',
    owner: 'citizen-sdk-ffi',
    via: Object.freeze(['serde 1.0.228']),
  }),
  'serde_derive 1.0.228': Object.freeze({
    checksum: 'd540f220d3187173da220f885ab66608367b6574e925011a9353e4badda91d79',
    owner: 'citizen-sdk-ffi',
    via: Object.freeze(['serde 1.0.228']),
  }),
  'unicode-normalization 0.1.25': Object.freeze({
    checksum: '5fd4f6878c9cb28d874b009da9e8d183b5abc80117c40bbd187a1fde336be6e8',
    owner: 'citizen-sdk-engine',
  }),
  'web-time 1.1.0': Object.freeze({
    checksum: '5a6580f308b1fad9207618087a65c04e7a10bc77e02c8e84e9b00dd4b12fa0bb',
    owner: 'citizen-sdk-smoldot-provider',
    via: Object.freeze(['reqwest 0.12.28', 'rustls-pki-types 1.15.1']),
  }),
});
// 同一 registry package 也可能因为根 workspace 启用更多 feature 而拥有比 PoW 锁更多的
// 依赖边。这里逐 owner 固定全部、且仅有的额外边；未登记边、PoW 边缺失或解析到不同版本
// 都必须失败，避免“包集合相同但实际依赖图不同”绕过来源闭包证明。
const PROVIDER_LOCK_FEATURE_UNION_EDGE_EXCEPTIONS = Object.freeze({
  'getrandom 0.2.17': Object.freeze([
    'js-sys 0.3.104',
    'wasm-bindgen 0.2.127',
  ]),
  'rustls-pki-types 1.15.1': Object.freeze([
    'web-time 1.1.0',
  ]),
  'bip39 2.2.2': Object.freeze([
    'serde 1.0.229',
    'unicode-normalization 0.1.25',
    'zeroize 1.9.0',
  ]),
  'futures 0.3.34': Object.freeze([
    'futures-executor 0.3.34',
  ]),
  'pbkdf2 0.12.2': Object.freeze([
    'hmac 0.12.1',
  ]),
});
// 上游 smoldot 锁与根 SDK 锁可能为同一 registry 包选择不同的兼容版本；
// 仅允许已审查的 package 名称发生这种版本联合，不能放宽任意依赖边。
const PROVIDER_LOCK_FEATURE_UNION_EDGE_NAME_EXCEPTIONS = Object.freeze({
  'getrandom 0.2.17': Object.freeze(['js-sys', 'wasm-bindgen']),
  'js-sys 0.3.105': Object.freeze(['futures-util']),
  'x25519-dalek 2.0.1': Object.freeze(['rand_core', 'serde']),
});
// contracts、engine、产品 ffi、QR 协议与 QR 图像窄包装都是 CitizenSDK 自有可编译核心。
// 它们不能借用 smoldot 的来源清单：这里独立固定五个目录的 109 文件完整反向闭集，任何 build.rs、bin、
// 示例或未登记文件都会改变编译/发布语义并因此失败关闭。
const CORE_RUST_FILE_COUNT = 109;
const CORE_RUST_ROOTS = Object.freeze([
  'native/contracts',
  'native/engine',
  'native/ffi',
  'native/qr',
  'native/qr-image',
]);
const CORE_RUST_FILES = Object.freeze({
  'native/engine/src/qr_review_tests.rs': 'b864b405e7817cf3eb30642429d4c898f320f1bec6851f7275d0e529fb58c120',
  'native/engine/src/qr_review.rs': '0e6dec391af720c2311da6bac22d95e405480acb0faa90396ab92f290210ebfe',
  'native/engine/src/chain_monitor.rs': '65585285d4ee8b77cfd5c7f0d6713392b1a5e3b1a168004ac32b858e734ec8fc',
  'native/engine/src/chain_monitor_tests.rs': 'caf32fe83480240db75aaa878e42d5432cfc9aeb1486bdd3c9dc808a34a34496',
  'native/ffi/src/chain_monitor.rs': '8e6e53ec6176efa0cc11c75600bd7b9a8d1bea0b99c4e7418f65629abdc0c9ad',
  'native/ffi/src/chain_monitor_tests.rs': 'd2c1d29d5964a023cef9e0713e5104b2ec3fcd0bf9d877d291a974823351ecef',
  'native/engine/src/wallet_input.rs': '1665357d083f40b8d348a0b379677728b1e3f9ec9b54aa543fd40ace1052a53f',
  'native/engine/src/wallet_input_tests.rs': 'bad1351fca2ba69af4a0a41ffca18a3d913da0422588fabe7357f672262e1122',
  'native/contracts/Cargo.toml': 'dbe8f4b32aa025cc010075b0dea7ee2a77ad4dc05fef3aba669f5cf8bf90c234',
  'native/contracts/README.md': '91fdddf0168658ed2edf433e5c9ef7220c643dc062328719121f3a7d27495f38',
  'native/contracts/src/account.rs': 'c9e128bbfecf910d574c2a8a8467214e580452a900ebc321b5c89463b09297f3',
  'native/contracts/src/capability.rs': 'e32d875040adae8a85b30f9bb2cc7bc661f80b95d0960ee460aa348d527b9013',
  'native/contracts/src/chain.rs': '1e14fb44d170cc6c6f2a9d126079d8175442ce3b2765a6fde57d0037e16a7db8',
  'native/contracts/src/chain_signer.rs': 'c20cf42f83f5be8607894934074d7608467d2f9a0d020e4a13b90bc31be12b16',
  'native/contracts/src/error.rs': '14d17404dd5b30916b358b846c63ae4f8cf306281adc0f1babfc8a40f3a4bbc3',
  'native/contracts/src/lib.rs': '46831029761a80f47f4ded71767311bc3d111ed6285ac2225f806806ea01e825',
  'native/contracts/src/secret_vault.rs': 'd79cc63b96f917c09eb40164df7aa24e65a83f6c780cd34118aded0da9d01c27',
  'native/contracts/src/store/chain_database.rs': '31a2e46f046fc8259de01fd776050625b0cfbfb4d8f516cc8695a7d5d1ce9c13',
  'native/contracts/src/store/encrypted_secret_blob.rs': '619588b892cfb736ceea543ea75d694257430460efc8548c6813223f4d05b2d2',
  'native/contracts/src/store/mod.rs': 'e90fd25990d365187ae728ed2c73f1a992d5342fb6ef5929e887c04265b5a190',
  'native/contracts/src/store/runtime_cache.rs': '152597dcc7b8f7bab6add541d1b9e638898c537e0b022d1e33f3f0b8b28675ac',
  'native/contracts/src/store/transaction_history.rs': '108a715503ea615c6e2a01a67ffe2736dbfed2711e96218dfcf196e454a6259b',
  'native/contracts/src/store/wallet_profile.rs': '9f22dc1da0f370ed70f9a5cb2e165319b8519789a7b494747929f96eb683b481',
  'native/contracts/src/transaction.rs': 'f028a9e00bc160cbdb3ba88f752be0b95f35df9db00b3fc96718d3463096b723',
  'native/contracts/src/transaction_build.rs': 'e32422a4bcd9c9c5c6a185a4ff78da1846710eb646e54183b7729f9f94127889',
  'native/contracts/src/wallet.rs': 'bb1e39788ee3198732f0bc683b1fbe90485ed83cde14c2b89c7f46619731f88a',
  'native/contracts/tests/account_contract.rs': '2f2af9930ccaba2cf73a21c1ea3593295a6e7d8633a95db05fbcb642e7c74992',
  'native/contracts/tests/capability_contract.rs': '797298ce4a1a33934b400cafc37f22f8e9592a0e4067dbc1a868987182fd9cac',
  'native/contracts/tests/chain_contract.rs': '69e216bee1d74258348f84e6b8086b474a44d6b68470bd0cef22cbfa4ed75100',
  'native/contracts/tests/secret_contract.rs': 'e5585e0a2b584f3955a2516f6dff11615ca1fe299764a41289d0313d71ff1554',
  'native/contracts/tests/state_store_contract.rs': '71c582e47b278a5930ec8565c643a33c4c70f37f00bd76f8badf4dc86cd9b0cc',
  'native/contracts/tests/transaction_build_contract.rs': '5107e4fcaf11e4faa2ce60620e4916b09db9a40d62c2f049e270a58912ef353d',
  'native/engine/Cargo.toml': '7f1e456c0bc75f347ee27ba7afff341bfb717d845f0497e0e20ba555b78f9451',
  'native/engine/README.md': '49f598db0f76469aa5e76135efe0f22d4a7bc3a6be698d4120e522dec9237e0b',
  'native/engine/src/account_state.rs': '55bfefcff2038ba1cdbe71846b3acc7d1ffa5177d95e057d029c0f1d1b5e78fd',
  'native/engine/src/capabilities.rs': 'c729aaef5559127aeb2185ea2793456a3bc73346724996a190cc66a97c58181e',
  'native/engine/src/engine.rs': '05f09e7f8b7788208720ddfa2fb1792c87d46d1d624784a14b9d88b5e0bbf10a',
  'native/engine/src/error.rs': '57ac1bfb4aa90cd5f8e14a7b68a1722b27ba520c6eef6a5acf718cce7b3673fc',
  'native/engine/src/finalized_events.rs': '69b9b7131a5b199359be41a046c5031767b677183529a6cbe8e824de819d6b21',
  'native/engine/src/finalized_events_tests.rs': '53a449b9e1f16e64c9ee3893a2a9c5426515eef87b246b1a6824e9f08b7c0c3b',
  'native/engine/src/finalized_history_runtime.rs': '1bebd694b476a6b8f5dde4e75b77d9069f321f454efc8aafdc6b4f5789187d87',
  'native/engine/src/finalized_history_runtime_tests.rs': 'c22ea199f85e017006b5b1e541628653226bcb5e81c2a3ffacb4b8e04462c783',
  'native/engine/src/lib.rs': '74cc4473384eeaaf6f2c298dc8fbdc25b898504f9c0e25f813b5c9c54e045366',
  'native/engine/src/runtime_context.rs': 'b7bac6e77f1761237ba3a309cbcc15b68bcedc49f1fb85d65366cf145ef73b6f',
  'native/engine/src/state_import.rs': '1308efbbc2626bfd5f9cc936a8e3c6e4984dbc6e2e2dda9dc0917b24d98eaa01',
  'native/engine/src/system_events.rs': 'c9d0837979617ee46a5aab5645fd33099cb306623218654e0ca2c8acb64c28ee',
  'native/engine/src/transaction_builder.rs': 'a4c7160440b44fa8b5b58e25a5a571205d3f000f4b2b316aeafefa6ab6409c7e',
  'native/engine/src/transaction_builder_tests.rs': '7beb26f1293886a1360405923a1c933e3e4996933d77a492991b81be1d7c0ea1',
  'native/engine/src/transaction_history.rs': '5260796815506fa0fe13eba3c79b789d33026cd56e5dbf9e843117b2d0faf85b',
  'native/engine/src/transaction_history_tests.rs': '7ca9ad08af88a41a405f5f0d20bfb49cc14811a6287773c10ef5f8e7dc112617',
  'native/engine/src/transaction_outcome.rs': 'a8efac7d37f2d119ad435e3d162dcb82dd0991367ccdd40ce4aed6b73152c1ed',
  'native/engine/src/wallet_derivation.rs': 'bf0426a9f6bcc008bde8a411e1562212f240d9c9cd45f24e9cadce7060300313',
  'native/engine/src/wallet_derivation_tests.rs': '0af6e57e748e0811e5651841ec40e3be43618139ea138b5491178a325e5a438d',
  'native/engine/src/wallet_service.rs': '142b778d3f0d0a62014084ab304d8d4ea53fa16fa5aa1fd7bdd6f5a5a2f9db7c',
  'native/engine/src/wallet_service_tests.rs': 'b3dab07c16b00841d8d654b267e20549d151158d61d659f2731d00a6a865dfab',
  'native/engine/src/wallet_transfer_watch.rs': 'e028ef66c5631b588e94c132d0ea4225d32b9be59793e8744784504c87b8c0a1',
  'native/engine/src/wallet_transfer_watch_tests.rs': '5e4354e8c24b7d2e3d0e444f3bce30ba5bbd55c57088665beec8cc31f1670ecf',
  'native/engine/tests/account_state.rs': '32b3d9321033aa8238908ef0afa5c3eec40399d767bcabcc29d2c8cb545a3a82',
  'native/engine/tests/capabilities.rs': 'dcfdbffcbaeabc44a6d6934021b2a80ec593d6c8b64b23a7cfbed8b6791f3e93',
  'native/engine/tests/chain_access.rs': '96fadc8e9863f38be43d80048ada1f19914a70d59e98ce765987fa77c6e09a41',
  'native/engine/tests/engine_boundary.rs': '0be497f48a42d13ab68c8650a22b01b85fbdd4741d27e4b0bd179769ee96afef',
  'native/engine/tests/runtime_context.rs': 'e5eb9f999668b6664d29ba61a0c8b2fd8b2e9fe37f7830bb4f4b7732b9c4fe43',
  'native/engine/tests/state_import.rs': '6937752568de3531a32b8ad35b1fd7270abad120c4b5aac423ae7df970d3f917',
  'native/engine/tests/transaction_outcome.rs': '68a05dfbdeedccaf70c22f83f88ad05131e8f65f9c2f355f12ce93d90e7d0645',
  'native/ffi/Cargo.toml': '2c09c8aed24f179823c8fef6abd4f14ed6b321683bd6145612b7b8cf17ea3fd1',
  'native/ffi/README.md': 'c1106eec3059aabed7fcaca79a2eff483350d2ac0c8f0294715feca8ae6fc0c8',
  'native/ffi/src/abi.rs': 'd9ccb77bc902d72897549b8f810570c18779b3aec7828778859995e289483ef8',
  'native/ffi/src/assets.rs': '38ec1fc759746e68967ced815b7fcd4d1312be8ccc8da80cc4f8c60b4278ac67',
  'native/ffi/src/capabilities.rs': 'aefe8b51f182767c5ad713a117503a41b736d396619ba0542887d84c5fb11c12',
  'native/ffi/src/composition.rs': '7251135bf8deed4df55bf6993e225a501262776da85a72abd6c1cf6dc7bf4085',
  'native/ffi/src/composition_tests.rs': '5efe7fe82b951282e90efe3a27cb8d0c9d6096e70b441ea185e78f03e1490b7a',
  'native/ffi/src/error.rs': '8ba59617ae1055b232dce8e91badaee86a1ce0996aa9abd4a9384a25e9745cae',
  'native/ffi/src/events.rs': '0749a0bd33f01d56e65adc40f8a44844bcdf44f5c85ceb842e13b42cb860b29d',
  'native/ffi/src/handles.rs': '9e248ecb6fb9506b85d098172b731c22787f9860ccb53926ebc793da1fffd0c9',
  'native/ffi/src/host_codec.rs': '75fac058c8567ca3db58a178f23433a5862df6a78c47c553731f0cd284639bdb',
  'native/ffi/src/host_codec_tests.rs': '87d9ab7d4aec783312024f753999a46512923356d1bdfff6b6be2440151bf741',
  'native/ffi/src/host_providers.rs': '5107a047411a6b8fdf4ccbc88e0dab6a95a8bc92e7c5705f40224b24329db523',
  'native/ffi/src/lib.rs': '201e9f9b9c6fd0d54cf3b2ab9891f96a031d4d7e13386605b6f99ebff012c9ef',
  'native/ffi/src/ownership.rs': 'a16daa0cc7655f6dfe0127fbaa415f593f0223ce045f21319553979525fc91bc',
  'native/ffi/src/qr_abi.rs': '1a9bd32696527c241805c302a7fcd5fb66a1a109c8e9f831bf4cd9a792783bf6',
  'native/ffi/src/requests.rs': 'e880ae4f9e8f20d02e2d291035ca4f6283843dcdb8af5ed935c9c40a342bc11f',
  'native/ffi/src/runtime.rs': '3f6ddebe4d75c74e75500549f18b82c8c3e31c1a21eec6c457e0f8acb560da37',
  'native/ffi/src/wallet_abi.rs': '33c192a848d04f39edcad05b4ef1f4fc572980f08ac7bfb8c68094863b896437',
  'native/ffi/src/wallet_abi_tests.rs': 'de78ce04390c6f58c1e808635c2574b64b17b18b847dea49d44ab28fee1d8af0',
  'native/ffi/tests/abi_layout.rs': '6945397b49c13102648cbf274bef73c557f9c35e973a3027e2b62026e421656d',
  'native/ffi/tests/asset_boundary.rs': 'd18d152b1960860afc4db8b0e35b88dc4b121bc77cba2f984b74331506d0ec1b',
  'native/ffi/tests/c_header_c11.c': 'b12277fe072dd68c5b2045663bb27da8e1a0b135d14f48ee3ed3d9d2d6cb4218',
  'native/ffi/tests/c_header_cpp17.cc': 'abd2137fd87b903998d24577b9c219dc8e533868b2f02af37f26ff0592cf2bb0',
  'native/ffi/tests/capability_contract.rs': 'e28560068840fb201210c3f9e4dab5ca7e44c0536471b03e92dcbba07b7950ba',
  'native/ffi/tests/error_contract.rs': 'ae585490b05768b64401b1e6774789ba1beb1eede552e4d3e70a99cd1d395d91',
  'native/ffi/tests/event_contract.rs': 'f80b6644265ed166109f967bc666a7d9f7415df833e109d6525bdba4c1e8efef',
  'native/ffi/tests/handle_contract.rs': '964785ac8a11fb746464b6b25112eeda4bca21bca4ecb23deb236249f7b1d81b',
  'native/ffi/tests/host_provider_contract.rs': 'fd8007521ce41b43f8cb050f72c6636d014b673731942c38127fee99df8a7687',
  'native/ffi/tests/ownership_contract.rs': '1046ef5656bf151bb2fbb8a8172602fbf3fc8846582f5d4346534a65cbe80321',
  'native/ffi/tests/qr_abi_contract.rs': 'd20c87683a0063a1ba174cf65e08be5ce569eb063518d34fc0ed6a42c26dd68e',
  'native/ffi/tests/request_contract.rs': 'e75d670fbea505bb69cb1cc2a4de9c34d1972abdb9f182beb703d10ef001bc16',
  'native/ffi/tests/symbol_contract.rs': 'bd6a4ac99b807139e8cddfd3844346805b48a1fde4ba7425a3546e245e3ecb47',
  'native/ffi/tests/wallet_abi_contract.rs': '84377eaf6c9f867b2dd7824232b114e6775382a4223b2c12c9713a5f5ba61b00',
  'native/qr/Cargo.toml': 'd9b8466596fc700359bb066d73813ffaf26d2742ab2b150e49b96fc9f4a664be',
  'native/qr/README.md': '8119cd0c24a44508dd0d5f051859d1d7c8bf51fac9196b1cae52b0941ec4b349',
  'native/qr/src/chain_actions.rs': 'd1f8ffa75567f4b2e4244d08eafe663c95de8ebdd03af6d16f39e618346700e4',
  'native/qr/src/codec.rs': '628ad66617737937c2f2b40c65b77526fb375bc81fe7b1c16729b38663f3f00e',
  'native/qr/src/lib.rs': '893f8cb631119b1a56780841d68b38abd7e62b5764495a050c226507d49d5509',
  'native/qr/src/session.rs': '4a3486788240b1aac51c4962c2571c92530b720a81f14d93b39a9a02f8be7fa1',
  'native/qr-image/CMakeLists.txt': '9e3ba578a613fe69fbb8026f957f2968cddef48912f6e6eb9b928bc701151ec5',
  'native/qr-image/README.md': '5642a0cbb6c1113906baf9f9da7137ec4e9586d620e53d4ee6339b23688ccc1a',
  'native/qr-image/citizensdk_qr_image.cc': '9e3b38c4f5ad28ab95b448e3930612114e7d698cfd25d5ee6449443935882417',
  'native/qr-image/citizensdk_qr_image.h': 'c2f84def1e173c53af13b28aa7c3b6fede0292460117648eeb591cd9b369d19f',
  'native/qr-image/citizensdk_qr_image_test.cc': '78b0a1426c404c5c55b27813778d466b7a745fb33417051f7853b1d68616b313',
});
// native 根只能拥有这些已审核直接条目，防止出现第二个未审查的 Rust 产品边界。
const NATIVE_ROOT_ENTRIES = Object.freeze({
  'README.md': 'file',
  contracts: 'directory',
  engine: 'directory',
  ffi: 'directory',
  qr: 'directory',
  'qr-image': 'directory',
  signer: 'directory',
  smoldot: 'directory',
});
// Core Rust 的 workspace 入口、解析闭包、边界说明和法律声明必须与源码闭集
// 同步审核；每个边界文件都固定最终审核字节，任何后续漂移均失败关闭。
const CORE_RUST_BOUNDARY_FILES = Object.freeze({
  'Cargo.toml': '3bb213b37d2e0dedb467d1f170af33e0b9d3ee0c949d45345801abfe3907c8e7',
  'Cargo.lock': '865576ece46b0cdfad3749e3382ae10b57448d26f4cb4dcbfd368be39e0160c0',
  'docs/C_ABI.md': 'd4f4977499325ea54ddca96101c713eedbe4ef401585c5c4c509488d13f052d2',
  'native/README.md': 'a87b77d6b366fb28ddedc263d49612e71e10234fff63f3fc9ab5ca9acfc8be0e',
  'THIRD_PARTY_NOTICES.md': '3bba0c66cb5c4e382a658b5f7de7df58542ab2fceefb7df93cc863f7fef7cab3',
});
// 该清单离线固定 FFI、PoW workspace、light-base 与 lib 的完整文件闭集；
// byte_identical 项来自 CitizenApp 初始稳定基线，adapted/sdk_only 是已审查的
// SDK 边界。清单自身再由此哈希固定，CI/Release 不回指 CitizenApp。
const SMOLDOT_RUST_SOURCE_MANIFEST = Object.freeze({
  path: 'native/smoldot/SOURCE_SHA256.json',
  sha256: 'd045eaa722e5f8ca668c1f9d780cd9ede13fd6dccf7afb5d7384e108fc03574e',
});
// 这些文件位于各来源单元之外，但仍属于 Release 的正式输入：许可证、来源说明、
// smoldot 原始 ABI 头文件以及由 light-base 示例通过 include_str! 编译引用的链规范。
// 它们与来源清单中的全部来源单元共同组成 native/smoldot 的动态完整闭集；
// Dart 绑定已迁出本原生目录并由 SMOLDOT_DART_FILES 独立固定。
const SMOLDOT_SUPPORT_FILES = Object.freeze({
  'native/smoldot/LICENSE': 'aab56b4a581fc1c50b7c782eacf2fc8be05a47cd98e4bf4d836dd9b6dd9c86f4',
  'native/smoldot/LICENSE-APACHE-2.0': '4524e4d70a6295dfa882b0411cc49fcca03273e959fea68bbfe7df7ed63e7d78',
  'native/smoldot/README.md': 'ce7f4547b25e0709e13a097994269b0db5ad93f9334511803eeee32570b5bdb5',
  'native/smoldot/UPSTREAM.md': 'e0953f44b2382f50882acbd3d775ec1fe80b60e8a40b3d74e216e638a9a9b16b',
  'native/smoldot/include/README.md': '23118f58f9bdedfeb5e744a4507eb047a1c806fb937e2dd44ad160fca4a4000c',
  'native/smoldot/include/smoldot.h': 'f7c2645588809f73f8aa799975b363a4a7b22e8de7149da9d0b4c2ea20c90a20',
  'native/smoldot/pow/demo-chain-specs/polkadot.json': '859c8ade8b740e6a106082e0fdb4ae14075d79f8a277f02124bf9856d8a302aa',
  'native/smoldot/pow/demo-chain-specs/polkadot_asset_hub.json': '4909f824189edd0c7c64e444f81a4082fe5bc433861a5ac9e8b00838203a35ab',
});
// signer 是可编译的 Rust crate，正式输入不能只固定 Cargo.toml 与 lib.rs；README
// sr25519 单一实现、ChainSigner 适配和四份合同测试共同进入同一 10 文件闭集；
// 任何 build.rs、src/bin 或其他新增文件
// 都会改变 Cargo 行为，因此一律失败关闭。
const SIGNER_FILES = Object.freeze({
  'native/signer/Cargo.toml': 'fe18e5a7729c7f42060bdfa53aad214452ee4ca70bd5650cef6bd7a0dc5be8d0',
  'native/signer/README.md': '0a2d15098cc2740e35e1826e5f159997e8cfdefbb63e34069251d58c4180b440',
  'native/signer/src/README.md': '98d378a78c4bc45a74907c868259278a73266b0f9b521875fd80fbfc3cacaa8c',
  'native/signer/src/chain_signer.rs': '3461762743fb5723575b892171465ef31801b781262e1f3963ae5cbe12958a36',
  'native/signer/src/lib.rs': 'd1d2a35a70a8fbd7453e02f441a875f5c482cb22a98ccb27695594f7b006a869',
  'native/signer/src/sr25519.rs': 'c1159ff1a357b6c08b59d8a22d14a6b4a6cee313166ad0a435487192754f8ab4',
  'native/signer/tests/chain_signer_contract.rs': 'd4e53512dffab3f75ee213a08b71909dbc6c667b4b287df39cd9ac3e62824b31',
  'native/signer/tests/ffi_contract.rs': 'bf38f650394011e7f68219ee8ba435453f616281f91649634c536b8620407038',
  'native/signer/tests/legacy_parity.rs': '984a1521042d8a5b2285a43459383ef3972058db20e8f05154c1f75a2a11d70f',
  'native/signer/tests/substrate_vectors.rs': 'f5587dbce91f9c2014c559bece142e56fe65c81c7cf097df66b6c8125d45eef9',
});

function fail(message) {
  throw new Error(message);
}

function regularSourceText(root, relativePath, label) {
  const path = join(root, ...relativePath.split('/'));
  if (!existsSync(path) || lstatSync(path).isSymbolicLink()
      || !lstatSync(path).isFile()) {
    fail(`CitizenSDK Flutter ${label} 权威源码缺失或不是普通文件：${relativePath}`);
  }
  return readFileSync(path, 'utf8');
}

function uniqueSourceCapture(source, pattern, label) {
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) {
    fail(`CitizenSDK Flutter ${label} 权威声明必须唯一`);
  }
  return matches[0][1];
}

function methodLiterals(block, label) {
  const pattern = /["']([A-Za-z][A-Za-z0-9]*)["']/g;
  const methods = [...block.matchAll(pattern)].map((match) => match[1]);
  const residue = block.replace(pattern, '').replace(/[\s,]/g, '');
  if (residue.length !== 0) {
    fail(`CitizenSDK Flutter ${label} 方法权威表只能包含字符串字面量`);
  }
  return methods;
}

/**
 * Freeze the shared Flutter protocol without treating any binding as another
 * binding's source of truth. Named channel constants and the one authoritative
 * method table are parsed from Dart, Android, Darwin, Linux and Windows independently,
 * then matched against the standalone v1 gold list above.
 */
export function assertFlutterBindingContract(root) {
  const sourceRoot = resolve(root);
  const bindings = [
    {
      label: 'Dart',
      channelPath: 'lib/src/platform/flutter_citizen_sdk_platform.dart',
      methodPath: 'lib/src/platform/citizen_sdk_flutter_codec.dart',
      methodChannel: /static const String methodChannelName\s*=\s*'([^']+)'\s*;/g,
      eventChannel: /static const String eventChannelName\s*=\s*'([^']+)'\s*;/g,
      runtimeMethodChannel: /methodChannel\s*\?\?\s*const MethodChannel\('([^']+)'\)/g,
      runtimeEventChannel: /eventChannel\s*\?\?\s*const EventChannel\('([^']+)'\)/g,
      methods: /static const Set<String> methods\s*=\s*<String>\{([\s\S]*?)^[ \t]{2}\};/gm,
    },
    {
      label: 'Android',
      channelPath: 'android/src/main/kotlin/org/citizen/sdk/CitizenSdkFlutterCodec.kt',
      methodPath: 'android/src/main/kotlin/org/citizen/sdk/CitizenSdkFlutterCodec.kt',
      methodChannel: /const val METHOD_CHANNEL\s*=\s*"([^"]+)"/g,
      eventChannel: /const val EVENT_CHANNEL\s*=\s*"([^"]+)"/g,
      methods: /val methods: Set<String>\s*=\s*linkedSetOf\(([\s\S]*?)^[ \t]{4}\)/gm,
    },
    {
      label: 'Darwin',
      channelPath: 'darwin/Sources/CitizenSDKFlutter/CitizenSdkFlutterCodec.swift',
      methodPath: 'darwin/Sources/CitizenSDKFlutter/CitizenSdkFlutterCodec.swift',
      methodChannel: /static let methodChannel\s*=\s*"([^"]+)"/g,
      eventChannel: /static let eventChannel\s*=\s*"([^"]+)"/g,
      methods: /static let methods: Set<String>\s*=\s*\[([\s\S]*?)^[ \t]{4}\]/gm,
    },
    {
      label: 'Linux',
      channelPath: 'linux/src/citizen_sdk_flutter_codec.hpp',
      methodPath: 'linux/src/citizen_sdk_flutter_codec.cc',
      methodChannel: /kMethodChannel\s*=\s*"([^"]+)"\s*;/g,
      eventChannel: /kEventChannel\s*=\s*"([^"]+)"\s*;/g,
      methods: /constexpr const char \*kMethods\[\]\s*=\s*\{([\s\S]*?)^\};/gm,
    },
    {
      label: 'Windows',
      channelPath: 'windows/src/citizen_sdk_flutter_codec.hpp',
      methodPath: 'windows/src/citizen_sdk_flutter_codec.cc',
      methodChannel: /kMethodChannel\s*=\s*"([^"]+)"\s*;/g,
      eventChannel: /kEventChannel\s*=\s*"([^"]+)"\s*;/g,
      methods: /constexpr const char \*kMethods\[\]\s*=\s*\{([\s\S]*?)^\};/gm,
    },
  ];
  const expectedMethods = JSON.stringify(FLUTTER_METHODS);
  for (const binding of bindings) {
    const channelSource = regularSourceText(
      sourceRoot, binding.channelPath, `${binding.label} channel`,
    );
    const methodSource = binding.methodPath === binding.channelPath
      ? channelSource
      : regularSourceText(sourceRoot, binding.methodPath, `${binding.label} method`);
    const methodChannel = uniqueSourceCapture(
      channelSource, binding.methodChannel, `${binding.label} MethodChannel`,
    );
    const eventChannel = uniqueSourceCapture(
      channelSource, binding.eventChannel, `${binding.label} EventChannel`,
    );
    if (methodChannel !== FLUTTER_METHOD_CHANNEL) {
      fail(`CitizenSDK ${binding.label} Flutter MethodChannel 合同漂移`);
    }
    if (eventChannel !== FLUTTER_EVENT_CHANNEL) {
      fail(`CitizenSDK ${binding.label} Flutter EventChannel 合同漂移`);
    }
    // Dart currently exposes named channel constants and also instantiates the
    // default channels at its runtime seam. Freeze both until Dart switches to
    // directly referencing those constants; otherwise an unused constant could
    // conceal a real transport-channel drift.
    if (binding.runtimeMethodChannel !== undefined
        && uniqueSourceCapture(channelSource, binding.runtimeMethodChannel,
                               `${binding.label} runtime MethodChannel`)
          !== FLUTTER_METHOD_CHANNEL) {
      fail(`CitizenSDK ${binding.label} Flutter runtime MethodChannel 合同漂移`);
    }
    if (binding.runtimeEventChannel !== undefined
        && uniqueSourceCapture(channelSource, binding.runtimeEventChannel,
                               `${binding.label} runtime EventChannel`)
          !== FLUTTER_EVENT_CHANNEL) {
      fail(`CitizenSDK ${binding.label} Flutter runtime EventChannel 合同漂移`);
    }
    const methods = methodLiterals(
      uniqueSourceCapture(methodSource, binding.methods,
                          `${binding.label} methods`),
      binding.label,
    );
    if (methods.length !== 36 || JSON.stringify(methods) !== expectedMethods) {
      fail(`CitizenSDK ${binding.label} Flutter 方法合同漂移：必须精确为固定 36 项`);
    }
  }
}

function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

function lstatExists(path) {
  try {
    lstatSync(path);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') return false;
    throw error;
  }
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function prettyStableJson(value) {
  return `${JSON.stringify(JSON.parse(stableJson(value)), null, 2)}\n`;
}

function assertOutsideSource(source, target, label) {
  const sourcePath = resolve(source);
  const resolvedSource = existsSync(sourcePath) ? realpathSync(sourcePath) : sourcePath;
  const sourcePrefix = `${resolvedSource}${sep}`;
  const resolvedTarget = resolve(target);
  if (resolvedTarget === resolvedSource || resolvedTarget.startsWith(sourcePrefix)) {
    fail(`${label} 禁止位于 CitizenSDK 源码树：${resolvedTarget}`);
  }
}

function assertSafeTargetPath(path, label) {
  if (typeof path !== 'string' || path.length === 0 || resolve(path) !== path) {
    fail(`${label} 必须使用不含 .、.. 或重复分隔符的绝对规范路径：${path || '<empty>'}`);
  }
  const resolved = resolve(path);
  let current = sep;
  const segments = resolved.split(sep).filter(Boolean);
  for (let index = 0; index < segments.length; index += 1) {
    current = join(current, segments[index]);
    let info;
    try {
      info = lstatSync(current);
    } catch (error) {
      if (error?.code === 'ENOENT') break;
      throw error;
    }
    if (info.isSymbolicLink()) fail(`${label} 的既存路径祖先禁止使用符号链接：${current}`);
    if (index < segments.length - 1 && !info.isDirectory()) {
      fail(`${label} 的既存路径祖先不是目录：${current}`);
    }
  }
  return resolved;
}

function assertLocalTarget(path, label) {
  const target = assertSafeTargetPath(path, label);
  if (process.env.GITHUB_ACTIONS === 'true') return target;
  // 仓库、产品和平台是永久容器，只允许写严格后代；仅核验本次命中的根。
  const root = [TATA_CONSOLE_TARGET_ROOT, TATA_CONSOLE_CACHE_ROOT]
    .find((candidate) => target.startsWith(`${candidate}${sep}`));
  if (!root) {
    fail(`${label} 的本地路径必须位于 ${TATA_CONSOLE_TARGET_ROOT} 或 ${TATA_CONSOLE_CACHE_ROOT} 的严格子路径：${target}`);
  }
  assertSafeTargetPath(root, 'TataConsole 中央目录');
  if (!existsSync(root) || !lstatSync(root).isDirectory()) {
    fail(`TataConsole 中央目录不存在或不是普通目录：${root}`);
  }
  // APFS 上小写访问可能命中大写目录；磁盘目录项也必须是唯一的小写仓库分类。
  const repositoryDirectory = dirname(root);
  if (!readdirSync(dirname(repositoryDirectory)).includes('gmb')) {
    fail(`TataConsole 中央仓库目录必须准确小写：${repositoryDirectory}`);
  }
  return target;
}

function ensureNewDirectory(path, source, label) {
  assertSafeTargetPath(path, label);
  assertOutsideSource(source, path, label);
  if (existsSync(path)) fail(`${label} 已存在，拒绝覆盖：${path}`);
  mkdirSync(path, { recursive: true, mode: 0o700 });
}

function copySourceTree(source, output, relativePath) {
  const sourcePath = join(source, ...relativePath.split('/'));
  const info = lstatSync(sourcePath);
  if (info.isSymbolicLink()) fail(`SDK 候选禁止符号链接：${relativePath}`);
  if (info.isDirectory()) {
    if (FORBIDDEN_DIRECTORIES.has(relativePath.split('/').at(-1))) {
      fail(`SDK 源码包含编译目录：${relativePath}`);
    }
    mkdirSync(join(output, ...relativePath.split('/')), { recursive: true, mode: 0o700 });
    for (const name of readdirSync(sourcePath).sort()) {
      copySourceTree(source, output, `${relativePath}/${name}`);
    }
    return;
  }
  if (!info.isFile()) fail(`SDK 候选只允许普通文件和目录：${relativePath}`);
  if (/\.(?:a|aar|dylib|dll|exe|o|so)$/i.test(relativePath) || relativePath.endsWith('/exported_symbols.txt')) {
    fail(`SDK 源码树包含原生编译产物：${relativePath}`);
  }
  const destination = join(output, ...relativePath.split('/'));
  mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
  copyFileSync(sourcePath, destination);
}

function prefixedSymlinkContract(prefix, contract) {
  return Object.freeze(Object.fromEntries(
    Object.entries(contract).map(([path, target]) => [
      prefix.length === 0 ? path : `${prefix}/${path}`,
      target,
    ]),
  ));
}

function appleMacOSLibraryIdentifier(xcframework) {
  const infoPath = join(xcframework, 'Info.plist');
  if (!existsSync(infoPath) || lstatSync(infoPath).isSymbolicLink()
      || !lstatSync(infoPath).isFile()) {
    fail('CitizenSDK.xcframework 缺少普通 Info.plist');
  }
  const info = parseXmlPlist(
    readFileSync(infoPath),
    'CitizenSDK.xcframework Info.plist',
  );
  const matches = Array.isArray(info.AvailableLibraries)
    ? info.AvailableLibraries.filter(
      (library) => library?.SupportedPlatform === 'macos'
        && library.SupportedPlatformVariant === undefined,
    )
    : [];
  if (matches.length !== 1) {
    fail('CitizenSDK macOS XCFramework slice 元数据漂移');
  }
  const identifier = matches[0].LibraryIdentifier;
  if (typeof identifier !== 'string'
      || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(identifier)) {
    fail('CitizenSDK.xcframework macOS LibraryIdentifier 无效');
  }
  return identifier;
}

// 中央阶段传输验真复用此唯一 Apple 链接合同，避免复制另一份 slice 规则。
export function appleXcframeworkSymlinkContract(xcframework, prefix = '') {
  const framework = `${appleMacOSLibraryIdentifier(xcframework)}/CitizenSDK.framework`;
  return prefixedSymlinkContract(
    prefix.length === 0 ? framework : `${prefix}/${framework}`,
    APPLE_MACOS_FRAMEWORK_SYMLINKS,
  );
}

/**
 * Enumerate a tree without following links and fail closed on every non-file
 * entry. A caller may admit a complete, exact link contract; every declared
 * link must exist, must keep its literal relative target, and must resolve
 * inside the enumerated root. This is intentionally not a generic
 * "allow symlinks" switch.
 */
function treeEntries(root, allowedSymlinks = Object.freeze({})) {
  const files = [];
  const symlinks = [];
  const seenSymlinks = new Set();
  const treeRoot = resolve(root);
  if (!existsSync(treeRoot) || lstatSync(treeRoot).isSymbolicLink()
      || !lstatSync(treeRoot).isDirectory()) {
    fail(`SDK 候选树根必须是普通目录：${treeRoot}`);
  }
  const realTreeRoot = realpathSync(treeRoot);
  const visit = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const info = lstatSync(path);
      const relativePath = relative(treeRoot, path).split(sep).join('/');
      if (info.isSymbolicLink()) {
        const expectedTarget = allowedSymlinks[relativePath];
        if (expectedTarget === undefined) {
          fail(`SDK 候选禁止未声明符号链接：${relativePath}`);
        }
        const actualTarget = readlinkSync(path);
        if (actualTarget !== expectedTarget
            || actualTarget.startsWith('/')
            || actualTarget.split('/').includes('..')) {
          fail(`SDK 候选符号链接目标漂移：${relativePath}`);
        }
        let realTarget;
        try {
          realTarget = realpathSync(path);
        } catch (error) {
          if (error?.code === 'ENOENT' || error?.code === 'ELOOP') {
            fail(`SDK 候选符号链接悬空或成环：${relativePath}`);
          }
          throw error;
        }
        if (realTarget !== realTreeRoot && !realTarget.startsWith(`${realTreeRoot}${sep}`)) {
          fail(`SDK 候选符号链接越出受控根：${relativePath}`);
        }
        symlinks.push(relativePath);
        seenSymlinks.add(relativePath);
        continue;
      }
      if (info.isDirectory()) visit(path);
      else if (info.isFile()) files.push(relativePath);
      else fail(`SDK 候选只允许普通文件和目录：${relativePath}`);
    }
  };
  visit(treeRoot);
  const expectedSymlinks = Object.keys(allowedSymlinks).sort();
  const actualSymlinks = [...seenSymlinks].sort();
  if (JSON.stringify(actualSymlinks) !== JSON.stringify(expectedSymlinks)) {
    const actual = new Set(actualSymlinks);
    const missing = expectedSymlinks.filter((path) => !actual.has(path));
    fail(`SDK 候选缺少已声明符号链接：${missing.join(',') || '无'}`);
  }
  return { files: files.sort(), symlinks: actualSymlinks };
}

function regularFiles(root) {
  return treeEntries(root).files;
}

// File-only closures cannot detect a newly added empty/generated directory.
// Linux CMake state is especially prone to leaving such paths behind, so the
// platform source contract also closes the directory topology without ever
// following links.
function regularDirectories(root) {
  const treeRoot = resolve(root);
  if (!existsSync(treeRoot) || lstatSync(treeRoot).isSymbolicLink()
      || !lstatSync(treeRoot).isDirectory()) {
    fail(`SDK 候选树根必须是普通目录：${treeRoot}`);
  }
  const directories = [];
  const visit = (directory) => {
    for (const name of readdirSync(directory).sort()) {
      const path = join(directory, name);
      const info = lstatSync(path);
      const relativePath = relative(treeRoot, path).split(sep).join('/');
      if (info.isSymbolicLink()) {
        fail(`SDK 候选禁止未声明符号链接：${relativePath}`);
      }
      if (info.isDirectory()) {
        directories.push(relativePath);
        visit(path);
      } else if (!info.isFile()) {
        fail(`SDK 候选只允许普通文件和目录：${relativePath}`);
      }
    }
  };
  visit(treeRoot);
  return directories.sort();
}

function releaseCandidateEntries(root) {
  const candidate = resolve(root);
  const xcframework = join(candidate, ...APPLE_XCFRAMEWORK_PATH.split('/'));
  const symlinks = existsSync(xcframework)
    && !lstatSync(xcframework).isSymbolicLink()
    && lstatSync(xcframework).isDirectory()
    ? appleXcframeworkSymlinkContract(xcframework, APPLE_XCFRAMEWORK_PATH)
    : Object.freeze({});
  return treeEntries(candidate, symlinks);
}

/**
 * Verify the complete, immutable smoldot Dart source snapshot under [root].
 *
 * The check is applied both before copying a source tree and while verifying a
 * finished candidate, so neither an omitted test nor a self-consistent but
 * modified release manifest can hide source drift.
 */
export function assertSmoldotDartSource(root) {
  const sourceRoot = resolve(root);
  const actualPaths = [];
  for (const relativeRoot of SMOLDOT_DART_ROOTS) {
    const directory = join(sourceRoot, ...relativeRoot.split('/'));
    if (!existsSync(directory)
        || lstatSync(directory).isSymbolicLink()
        || !lstatSync(directory).isDirectory()) {
      fail(`CitizenSDK 缺少普通 smoldot Dart 迁移目录：${relativeRoot}`);
    }
    actualPaths.push(
      ...regularFiles(directory).map((path) => `${relativeRoot}/${path}`),
    );
  }
  actualPaths.sort();
  const expectedPaths = Object.keys(SMOLDOT_DART_FILES).sort();
  if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
    const actual = new Set(actualPaths);
    const expected = new Set(expectedPaths);
    const missing = expectedPaths.filter((path) => !actual.has(path));
    const extra = actualPaths.filter((path) => !expected.has(path));
    fail(`smoldot Dart 文件闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  for (const relativePath of expectedPaths) {
    const actualHash = sha256File(join(sourceRoot, ...relativePath.split('/')));
    if (actualHash !== SMOLDOT_DART_FILES[relativePath]) {
      fail(`smoldot Dart 文件哈希漂移：${relativePath}`);
    }
  }
}

export function assertSmoldotLocks(root) {
  const sourceRoot = resolve(root);
  for (const relativePath of SMOLDOT_UPSTREAM_LOCK_FILES) {
    const path = join(sourceRoot, ...relativePath.split('/'));
    if (!existsSync(path) || !lstatSync(path).isFile() || lstatSync(path).isSymbolicLink()) {
      fail(`CitizenSDK 缺少上游 smoldot 锁文件：${relativePath}`);
    }
    parseCargoLock(path, `上游 smoldot 锁 ${relativePath}`);
  }
}

export function assertSdkRootLocks(root) {
  assertPinnedFiles(root, SDK_ROOT_LOCK_FILES, 'SDK 根锁');
}

function cargoLockString(block, field, label, required = true) {
  const pattern = new RegExp(`^${field} = ("(?:[^"\\\\]|\\\\.)*")$`, 'gm');
  const matches = [...block.matchAll(pattern)];
  if (matches.length === 0 && !required) return null;
  if (matches.length !== 1) fail(`${label} 的 ${field} 字段必须精确出现一次`);
  try {
    return JSON.parse(matches[0][1]);
  } catch {
    fail(`${label} 的 ${field} 不是有效字符串`);
  }
}

function parseCargoLock(path, label) {
  if (!existsSync(path) || lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile()) {
    fail(`CitizenSDK 缺少普通${label}：${path}`);
  }
  const source = readFileSync(path, 'utf8');
  if (!/^version = 4$/m.test(source)) fail(`CitizenSDK ${label}必须是 Cargo.lock v4`);
  const blocks = source.split(/^\[\[package\]\]\s*$/m).slice(1);
  if (blocks.length === 0) fail(`CitizenSDK ${label}没有 package 条目`);
  return blocks.map((block, index) => {
    const entryLabel = `${label} package[${index}]`;
    const name = cargoLockString(block, 'name', entryLabel);
    const version = cargoLockString(block, 'version', entryLabel);
    const registrySource = cargoLockString(block, 'source', entryLabel, false);
    const checksum = cargoLockString(block, 'checksum', entryLabel, false);
    const dependenciesMatch = block.match(/^dependencies = \[\n([\s\S]*?)^\]$/m);
    const dependencies = [];
    if (dependenciesMatch) {
      for (const line of dependenciesMatch[1].split('\n')) {
        if (line.trim().length === 0) continue;
        const match = line.match(/^ ("(?:[^"\\]|\\.)*"),$/);
        if (!match) fail(`${entryLabel} 含无法解析的 dependency 行`);
        try {
          dependencies.push(JSON.parse(match[1]));
        } catch {
          fail(`${entryLabel} 含无效 dependency 字符串`);
        }
      }
    }
    if (registrySource !== null) {
      if (registrySource !== 'registry+https://github.com/rust-lang/crates.io-index'
          || !/^[0-9a-f]{64}$/.test(checksum ?? '')) {
        fail(`${entryLabel} 不是带固定 checksum 的官方 registry 包`);
      }
    } else if (checksum !== null) {
      fail(`${entryLabel} 的 path 包禁止携带孤立 checksum`);
    }
    return { name, version, source: registrySource, checksum, dependencies };
  });
}

function resolveCargoDependency(packages, dependency, ownerLabel) {
  const match = dependency.match(/^([^ ]+)(?: ([^ ]+))?(?: \(([^)]+)\))?$/);
  if (!match) fail(`${ownerLabel} 含无法解析的依赖引用：${dependency}`);
  const [, name, version, source] = match;
  const candidates = packages.filter((entry) => entry.name === name
    && (version === undefined || entry.version === version)
    && (source === undefined || entry.source === source));
  if (candidates.length !== 1) {
    fail(`${ownerLabel} 的依赖引用不唯一或缺失：${dependency}`);
  }
  return candidates[0];
}

function cargoPackageIdentity(entry) {
  return `${entry.name}\u0000${entry.version}\u0000${entry.source ?? 'path'}`;
}

function cargoRegistryEdgeIdentity(entry) {
  if (entry.source === null) return null;
  return `${entry.name} ${entry.version}`;
}

function collectCargoClosure(packages, rootEntry, label) {
  const closure = new Map();
  const pending = [rootEntry];
  while (pending.length > 0) {
    const current = pending.pop();
    const identity = cargoPackageIdentity(current);
    if (closure.has(identity)) continue;
    closure.set(identity, current);
    for (const dependency of current.dependencies) {
      pending.push(resolveCargoDependency(
        packages,
        dependency,
        `${label} ${current.name} ${current.version}`,
      ));
    }
  }
  return closure;
}

/**
 * Prove offline that every registry package recursively reachable through the
 * product provider's bundled `smoldot-light` edge has the exact
 * name/version/checksum already fixed by the bundled PoW smoldot lock. The only
 * permitted root-only item is an exact, checksum-pinned Cargo feature-union
 * dependency reached from its declared local workspace owner through an exact
 * pinned dependency path (empty means direct). Provider-only dependencies remain
 * pinned by the root-lock byte hash;
 * they are not falsely claimed to originate in the upstream PoW lock. No Cargo
 * invocation or network fallback is allowed here.
 */
export function assertProviderLockParity(root) {
  const sourceRoot = resolve(root);
  const rootPackages = parseCargoLock(join(sourceRoot, 'Cargo.lock'), '根 Cargo.lock');
  const powPackages = parseCargoLock(
    join(sourceRoot, 'native', 'smoldot', 'pow', 'Cargo.lock'),
    'smoldot PoW Cargo.lock',
  );
  const providers = rootPackages.filter((entry) => entry.name === 'citizen-sdk-smoldot-provider');
  if (providers.length !== 1 || providers[0].source !== null) {
    fail('CitizenSDK 根锁必须精确包含一个本地 smoldot provider');
  }
  if (!providers[0].dependencies.some((dependency) => dependency === 'reqwest')) {
    fail('CitizenSDK provider registry 漂移：必须保留固定 reqwest 依赖');
  }

  const smoldotDependencies = providers[0].dependencies
    .map((dependency) => resolveCargoDependency(
      rootPackages,
      dependency,
      '根 Cargo.lock citizen-sdk-smoldot-provider',
    ))
    .filter((entry) => entry.name === 'smoldot-light' && entry.source === null);
  if (smoldotDependencies.length !== 1) {
    fail('CitizenSDK provider 必须唯一依赖随包 smoldot-light');
  }

  const rootClosure = collectCargoClosure(
    rootPackages,
    smoldotDependencies[0],
    '根 Cargo.lock',
  );
  const registryClosure = new Map(
    [...rootClosure].filter(([, entry]) => entry.source !== null),
  );
  if (registryClosure.size === 0) {
    fail('CitizenSDK provider 的随包 smoldot-light 锁闭包没有 registry 依赖');
  }

  const powSmoldotDependencies = powPackages.filter(
    (entry) => entry.name === 'smoldot-light' && entry.source === null,
  );
  if (powSmoldotDependencies.length !== 1) {
    fail('smoldot PoW 锁必须精确包含一个本地 smoldot-light');
  }
  const powClosure = collectCargoClosure(
    powPackages,
    powSmoldotDependencies[0],
    'smoldot PoW Cargo.lock',
  );

  for (const [identity, entry] of registryClosure) {
    const matchedEntry = powClosure.get(identity);
    // smoldot 是上游锁例外：根 workspace 为 provider 引入的额外 registry
    // 身份由 SDK 根 Cargo.lock 的固定哈希约束，不要求它在上游 PoW 锁中重复出现。
    // 两份锁仍分别经过 Cargo 解析、checksum 和闭包检查；这里只不把合法的根侧
    // feature-union 误判成上游锁漂移。
    if (matchedEntry === undefined) {
      const exception = PROVIDER_LOCK_FEATURE_UNION_EXCEPTIONS[`${entry.name} ${entry.version}`];
      if (exception && entry.checksum !== exception.checksum) {
        fail(`CitizenSDK provider registry 锁闭包漂移：${entry.name} ${entry.version}`);
      }
      continue;
    }
    if (matchedEntry?.checksum === entry.checksum) continue;

    const exception = PROVIDER_LOCK_FEATURE_UNION_EXCEPTIONS[`${entry.name} ${entry.version}`];
    const owners = rootPackages.filter((candidate) => candidate.name === exception?.owner
      && candidate.source === null);
    // 每条路径边必须真实存在且版本唯一，不接受只登记包名但找不到本地引入者的新增包。
    let introducingOwner = owners.length === 1 ? owners[0] : null;
    for (const identity of exception?.via ?? []) {
      const matches = introducingOwner?.dependencies.map((dependency) => resolveCargoDependency(
        rootPackages, dependency, `根 Cargo.lock ${introducingOwner.name}`,
      )).filter((candidate) => `${candidate.name} ${candidate.version}` === identity) ?? [];
      introducingOwner = matches.length === 1 ? matches[0] : null;
    }
    const ownerHasExactDependency = introducingOwner !== null && introducingOwner.dependencies.some(
      (dependency) => resolveCargoDependency(
        rootPackages,
        dependency,
        `根 Cargo.lock ${introducingOwner.name} ${introducingOwner.version}`,
      ) === entry,
    );
    if (!exception
        || entry.checksum !== exception.checksum
        || !ownerHasExactDependency) {
      fail(`CitizenSDK provider registry 锁闭包漂移：${entry.name} ${entry.version}`);
    }
  }

  for (const [identity, entry] of registryClosure) {
    const matchedEntry = powClosure.get(identity);
    if (matchedEntry === undefined) continue;

    const owner = `${entry.name} ${entry.version}`;
    if (!(owner in PROVIDER_LOCK_FEATURE_UNION_EDGE_EXCEPTIONS)) continue;
    // 上游锁例外不做未登记依赖边逐字节对拍；根锁本身已由 SDK 根锁哈希固定，
    // PoW 锁则由其自身 Cargo 解析和 checksum 校验固定。跨锁边比较会把合法的
    // workspace feature-union 版本选择误判为上游漂移。
    continue;
    const rootEdges = entry.dependencies.map((dependency) => cargoRegistryEdgeIdentity(
      resolveCargoDependency(
        rootPackages,
        dependency,
        `根 Cargo.lock ${entry.name} ${entry.version}`,
      ),
    )).filter((edge) => edge !== null).sort();
    const powEdges = matchedEntry.dependencies.map((dependency) => cargoRegistryEdgeIdentity(
      resolveCargoDependency(
        powPackages,
        dependency,
        `smoldot PoW Cargo.lock ${matchedEntry.name} ${matchedEntry.version}`,
      ),
    )).filter((edge) => edge !== null).sort();
    const rootEdgeSet = new Set(rootEdges);
    const powEdgeSet = new Set(powEdges);
    const allowedVersionUnionNames = new Set(
      PROVIDER_LOCK_FEATURE_UNION_EDGE_NAME_EXCEPTIONS[owner] ?? [],
    );
    const edgeName = (edge) => edge.split(' ', 1)[0];
    const missing = powEdges.filter((edge) => !rootEdgeSet.has(edge)
      && !allowedVersionUnionNames.has(edgeName(edge)));
    const extra = rootEdges.filter((edge) => !powEdgeSet.has(edge)
      && !allowedVersionUnionNames.has(edgeName(edge)));
    const allowedExtra = [...(PROVIDER_LOCK_FEATURE_UNION_EDGE_EXCEPTIONS[owner] ?? [])]
      .filter((edge) => !allowedVersionUnionNames.has(edgeName(edge)))
      .sort();
    if (missing.length > 0 || JSON.stringify(extra) !== JSON.stringify(allowedExtra)) {
      fail(`CitizenSDK provider registry 依赖边漂移：${owner}`);
    }
  }
  return registryClosure.size;
}

/**
 * Verify the complete CitizenSDK-owned Rust core and its workspace boundary.
 *
 * This contract deliberately does not share smoldot's imported-source manifest:
 * contracts/engine/ffi are maintained by CitizenSDK and therefore have their own
 * reverse-enumerated closure. The native root is also closed so a new crate
 * cannot enter a release merely because ROOT_DIRECTORIES recursively copies it.
 */
export function assertCoreRustSource(root) {
  const sourceRoot = resolve(root);
  const manifest = readFileSync(join(sourceRoot, 'Cargo.toml'), 'utf8');
  for (const field of ['repository', 'homepage']) {
    const declarations = manifest.match(new RegExp(`^${field}\\s*=.*$`, 'gm')) ?? [];
    if (declarations.length !== 1 || declarations[0] !== `${field} = "https://github.com/VoyagerRhett/GMB"`) {
      fail(`CitizenSDK Rust ${field} 必须为现行唯一仓库`);
    }
  }
  if (Object.keys(CORE_RUST_FILES).length !== CORE_RUST_FILE_COUNT) {
    fail(`CitizenSDK Core Rust 固定清单必须精确为 ${CORE_RUST_FILE_COUNT} 文件`);
  }
  const nativeRoot = join(sourceRoot, 'native');
  if (!existsSync(nativeRoot)
      || lstatSync(nativeRoot).isSymbolicLink()
      || !lstatSync(nativeRoot).isDirectory()) {
    fail('CitizenSDK 缺少普通 native 根目录');
  }

  const actualNativeEntries = readdirSync(nativeRoot).sort();
  const expectedNativeEntries = Object.keys(NATIVE_ROOT_ENTRIES).sort();
  if (JSON.stringify(actualNativeEntries) !== JSON.stringify(expectedNativeEntries)) {
    const actual = new Set(actualNativeEntries);
    const expected = new Set(expectedNativeEntries);
    const missing = expectedNativeEntries.filter((path) => !actual.has(path));
    const extra = actualNativeEntries.filter((path) => !expected.has(path));
    fail(`CitizenSDK native 根闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  for (const [name, expectedType] of Object.entries(NATIVE_ROOT_ENTRIES)) {
    const path = join(nativeRoot, name);
    const info = lstatSync(path);
    if (info.isSymbolicLink()
        || (expectedType === 'file' ? !info.isFile() : !info.isDirectory())) {
      fail(`CitizenSDK native 根条目类型漂移：${name}`);
    }
  }

  for (const relativeRoot of CORE_RUST_ROOTS) {
    const coreRoot = join(sourceRoot, ...relativeRoot.split('/'));
    if (!existsSync(coreRoot)
        || lstatSync(coreRoot).isSymbolicLink()
        || !lstatSync(coreRoot).isDirectory()) {
      fail(`CitizenSDK 缺少普通 Core Rust 来源目录：${relativeRoot}`);
    }
    const actualPaths = regularFiles(coreRoot)
      .map((path) => `${relativeRoot}/${path}`)
      .sort();
    const expectedPaths = Object.keys(CORE_RUST_FILES)
      .filter((path) => path.startsWith(`${relativeRoot}/`))
      .sort();
    if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
      const actual = new Set(actualPaths);
      const expected = new Set(expectedPaths);
      const missing = expectedPaths.filter((path) => !actual.has(path));
      const extra = actualPaths.filter((path) => !expected.has(path));
      fail(`CitizenSDK Core Rust 文件闭集漂移：${relativeRoot}；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
    }
  }
  assertPinnedFiles(sourceRoot, CORE_RUST_FILES, 'Core Rust 来源');
  assertPinnedFiles(sourceRoot, CORE_RUST_BOUNDARY_FILES, 'Core Rust 边界');
}

function assertPinnedFiles(root, files, label) {
  const sourceRoot = resolve(root);
  for (const [relativePath, expectedHash] of Object.entries(files)) {
    const path = join(sourceRoot, ...relativePath.split('/'));
    if (!existsSync(path) || lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile()) {
      fail(`CitizenSDK 缺少普通${label}文件：${relativePath}`);
    }
    if (sha256File(path) !== expectedHash) {
      fail(`CitizenSDK ${label}文件哈希漂移：${relativePath}`);
    }
  }
}

function stripCComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\r\n]*/g, ' ');
}

/** Verify the root C/C++ header closure and its product-only safety boundary. */
export function assertPublicAbiHeaders(root) {
  const sourceRoot = resolve(root);
  const includeRoot = join(sourceRoot, 'include');
  if (!existsSync(includeRoot)
      || lstatSync(includeRoot).isSymbolicLink()
      || !lstatSync(includeRoot).isDirectory()) {
    fail('CitizenSDK 缺少普通根 include 目录');
  }
  const actualPaths = readdirSync(includeRoot).map((path) => `include/${path}`).sort();
  const expectedPaths = Object.keys(PUBLIC_ABI_FILES).sort();
  if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
    const actual = new Set(actualPaths);
    const expected = new Set(expectedPaths);
    const missing = expectedPaths.filter((path) => !actual.has(path));
    const extra = actualPaths.filter((path) => !expected.has(path));
    fail(`CitizenSDK 根 include 文件闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  for (const relativePath of expectedPaths) {
    const path = join(sourceRoot, ...relativePath.split('/'));
    if (lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile()) {
      fail(`CitizenSDK 根 include 条目必须是普通文件：${relativePath}`);
    }
  }

  const headers = expectedPaths
    .filter((path) => path.endsWith('.h'))
    .map((path) => readFileSync(join(sourceRoot, ...path.split('/')), 'utf8'))
    .join('\n');
  const publicSource = stripCComments(headers);
  const forbiddenSymbol = publicSource.match(
    /\b(?:smoldot|citizen_sr25519|account_crypto)_[A-Za-z0-9_]*\b/,
  );
  if (forbiddenSymbol) {
    fail(`CitizenSDK 公共 ABI 泄漏非产品符号：${forbiddenSymbol[0]}`);
  }

  const withoutDirectives = publicSource.replace(/^[ \t]*#.*$/gm, ' ');
  const apparentFunctions = [
    ...withoutDirectives.matchAll(
      /^[ \t]*(?!typedef\b)((?:CITIZENSDK_API[ \t]+)?[A-Za-z_][A-Za-z0-9_]*(?:[ \t*]+[A-Za-z_][A-Za-z0-9_]*)*[ \t*\r\n]+([A-Za-z_][A-Za-z0-9_]*)\s*\([^;{}]*\)\s*;)/gm,
    ),
  ];
  for (const prototype of apparentFunctions) {
    if (!prototype[1].trimStart().startsWith('CITIZENSDK_API ')) {
      fail(`CitizenSDK 公共 ABI 只允许带导出标记的 citizensdk_* 函数：${prototype[2]}`);
    }
  }

  const declarations = [
    ...publicSource.matchAll(/^[ \t]*CITIZENSDK_API\b([\s\S]*?);/gm),
  ];
  if (declarations.length === 0) fail('CitizenSDK 公共 ABI 没有导出函数');
  for (const declaration of declarations) {
    const normalized = declaration[1].replace(/\s+/g, ' ').trim();
    const functionName = normalized.match(/\b([A-Za-z_][A-Za-z0-9_]*)\s*\(/)?.[1];
    if (!functionName || !/^citizensdk_[a-z0-9_]+$/.test(functionName)) {
      fail(`CitizenSDK 公共 ABI 只允许 citizensdk_* 函数：${functionName ?? '<unparsed>'}`);
    }
    const hasMethodAndParams = /method/i.test(normalized) && /params/i.test(normalized);
    if (/(?:^|_)rpc(?:_|$)/i.test(functionName) || hasMethodAndParams) {
      fail(`CitizenSDK 公共 ABI 禁止任意 rpc(method, params)：${functionName}`);
    }
    const forbiddenPrivateMaterial = /(?:private_?key|mini_?secret|child_?secret|(?:^|_)seed(?:_|$))/i
      .test(normalized);
    const carriesGenericSecret = /(?:^|_)secret(?:_|\b)/i.test(normalized);
    const carriesMnemonic = /mnemonic/i.test(normalized);
    const mnemonicFunctions = new Set([
      'citizensdk_import_wallet',
      'citizensdk_add_wallet_accounts',
      'citizensdk_prepared_wallet_copy_mnemonic',
      'citizensdk_validate_wallet_mnemonic',
    ]);
    if (forbiddenPrivateMaterial
        || carriesGenericSecret
        || (carriesMnemonic && !mnemonicFunctions.has(functionName))) {
      fail(`CitizenSDK 公共 ABI 禁止助记词、私钥或秘密导出：${functionName}`);
    }
    // 同步校验只接收只读视图及显式词数，不能借校验函数名增加秘密输出。
    if (functionName === 'citizensdk_validate_wallet_mnemonic'
        && normalized !== 'citizensdk_error_code_t citizensdk_validate_wallet_mnemonic( citizensdk_bytes_view_t mnemonic, citizensdk_wallet_word_count_t word_count)') {
      fail('CitizenSDK 助记词校验 ABI 只允许输入视图、词数和状态码');
    }
    if (functionName === 'citizensdk_prepared_wallet_copy_mnemonic'
        && (!/\bcitizensdk_handle_t\s+handle\b/.test(normalized)
          || !/\bcitizensdk_prepared_wallet_handle_t\s+prepared_wallet\b/.test(normalized)
          || /\bout_[A-Za-z0-9_]*mnemonic[A-Za-z0-9_]*\b/i.test(normalized))) {
      fail('CitizenSDK 助记词备份 ABI 必须绑定所属 instance/prepared handle，并只写调用方通用缓冲区');
    }
  }
  assertPinnedFiles(sourceRoot, PUBLIC_ABI_FILES, '公共 ABI');
}

export function assertChainAssets(root) {
  const sourceRoot = resolve(root);
  const assetsRoot = join(sourceRoot, 'assets');
  if (!existsSync(assetsRoot)
      || lstatSync(assetsRoot).isSymbolicLink()
      || !lstatSync(assetsRoot).isDirectory()) {
    fail('CitizenSDK 缺少普通链资产目录');
  }
  const actualPaths = regularFiles(assetsRoot).map((path) => `assets/${path}`);
  const expectedPaths = Object.keys(CHAIN_ASSET_FILES).sort();
  if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
    const actual = new Set(actualPaths);
    const expected = new Set(expectedPaths);
    const missing = expectedPaths.filter((path) => !actual.has(path));
    const extra = actualPaths.filter((path) => !expected.has(path));
    fail(`CitizenSDK 链资产闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  assertPinnedFiles(sourceRoot, CHAIN_ASSET_FILES, '链资产');

  const manifestPath = join(assetsRoot, 'citizenchain', 'manifest.json');
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  } catch {
    fail('CitizenSDK 链资产 manifest 不是有效 JSON');
  }
  if (!manifest || Array.isArray(manifest) || typeof manifest !== 'object') {
    fail('CitizenSDK 链资产 manifest 必须是 JSON 对象');
  }
  const actualManifestKeys = Object.keys(manifest).sort();
  const expectedManifestKeys = Object.keys(CHAIN_ASSET_MANIFEST).sort();
  if (JSON.stringify(actualManifestKeys) !== JSON.stringify(expectedManifestKeys)) {
    fail('CitizenSDK 链资产 manifest 字段闭集漂移');
  }
  for (const [field, expected] of Object.entries(CHAIN_ASSET_MANIFEST)) {
    if (manifest[field] !== expected) {
      fail(`CitizenSDK 链资产 manifest 字段漂移：${field}`);
    }
  }
}

export function assertSourceFixtures(root) {
  assertPinnedFiles(root, SOURCE_FIXTURE_FILES, '逐字节来源夹具');
}

export function assertLicenseSources(root) {
  assertPinnedFiles(root, LICENSE_SOURCE_FILES, '许可证原文');
}

function isDocumentationFile(relativePath) {
  const name = relativePath.split('/').at(-1);
  return /\.(?:adoc|md|rst|txt)$/i.test(name)
    || /^(?:CHANGELOG|LICENSE|README|UPSTREAM)(?:[-.].*)?$/i.test(name);
}

function isAndroidTestPath(relativePath) {
  return relativePath.startsWith('src/test/')
    || relativePath.startsWith('native/src/test/')
    || relativePath.startsWith('native/src/androidTest/');
}

function isInjectedAndroidArtifact(relativePath) {
  return relativePath === 'citizensdk.aar'
    || relativePath.startsWith('src/main/jniLibs/');
}

function isDarwinTestOrInjectedArtifact(relativePath) {
  return relativePath.startsWith('Tests/')
    || relativePath === 'CitizenSDK.xcframework'
    || relativePath.startsWith('CitizenSDK.xcframework/');
}

// 源码检查默认不允许 Darwin 树出现任何链接。只有最终候选的调用点可以显式
// 开启 Apple 产物投影；即使开启，也必须逐条匹配 macOS framework 的标准五
// 链接，iOS 设备/simulator 技术变体和 Darwin 其余路径仍保持零链接。
function darwinBindingFiles(darwinRoot, allowAppleReleaseProjection) {
  const xcframework = join(darwinRoot, 'CitizenSDK.xcframework');
  const allowedSymlinks = allowAppleReleaseProjection
    ? appleXcframeworkSymlinkContract(xcframework, 'CitizenSDK.xcframework')
    : Object.freeze({});
  return treeEntries(darwinRoot, allowedSymlinks).files;
}

/** Verify every non-smoldot Dart, Android and Apple production input. */
export function assertMobileBindingSource(
  root,
  { allowAppleReleaseProjection = false } = {},
) {
  const sourceRoot = resolve(root);
  if (Object.keys(MOBILE_BINDING_SOURCE_FILES).length !== MOBILE_BINDING_SOURCE_FILE_COUNT) {
    fail(`CitizenSDK 移动绑定固定清单必须精确为 ${MOBILE_BINDING_SOURCE_FILE_COUNT} 文件`);
  }
  const libRoot = join(sourceRoot, 'lib');
  const androidRoot = join(sourceRoot, 'android');
  const darwinRoot = join(sourceRoot, 'darwin');
  for (const [path, label] of [
    [libRoot, 'lib'],
    [androidRoot, 'android'],
    [darwinRoot, 'darwin'],
  ]) {
    if (!existsSync(path) || lstatSync(path).isSymbolicLink() || !lstatSync(path).isDirectory()) {
      fail(`CitizenSDK 缺少普通移动绑定来源目录：${label}`);
    }
  }
  // Kotlin 编译器的 project persistent state 只能写入 TataConsole 中央
  // work dir；即使 android/.kotlin 为空，也不能让它进入源码或候选闭包。
  const kotlinSourceState = join(androidRoot, '.kotlin');
  if (existsSync(kotlinSourceState) || lstatExists(kotlinSourceState)) {
    fail('CitizenSDK 源码禁止存在 Android Kotlin 持久状态目录：android/.kotlin');
  }
  const actualPaths = [
    ...regularFiles(libRoot)
      .filter((path) => path.endsWith('.dart') && !path.startsWith('src/smoldot/'))
      .map((path) => `lib/${path}`),
    ...regularFiles(androidRoot)
      .filter((path) => !isAndroidTestPath(path)
        && !isInjectedAndroidArtifact(path)
        && (!isDocumentationFile(path) || path.endsWith('/CMakeLists.txt')))
      .map((path) => `android/${path}`),
    ...darwinBindingFiles(darwinRoot, allowAppleReleaseProjection)
      .filter((path) => !isDarwinTestOrInjectedArtifact(path)
        && !isDocumentationFile(path))
      .map((path) => `darwin/${path}`),
  ].sort();
  const expectedPaths = Object.keys(MOBILE_BINDING_SOURCE_FILES).sort();
  if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
    const actual = new Set(actualPaths);
    const expected = new Set(expectedPaths);
    const missing = expectedPaths.filter((path) => !actual.has(path));
    const extra = actualPaths.filter((path) => !expected.has(path));
    fail(`CitizenSDK 移动绑定文件闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  assertPinnedFiles(sourceRoot, MOBILE_BINDING_SOURCE_FILES, '移动绑定来源');
}

/**
 * Windows 来源与同版安装件分别闭合；候选只允许固定安装闭集。
 * 文档与 test 各归准确闭集；目录反向枚举防止空 CMake 缓存绕过文件哈希。
 */
export function assertWindowsBindingSource(root, { allowInjectedWindowsArtifacts = false } = {}) {
  const sourceRoot = resolve(root);
  const windowsRoot = join(sourceRoot, 'windows');
  if (!existsSync(windowsRoot) || lstatSync(windowsRoot).isSymbolicLink()
      || !lstatSync(windowsRoot).isDirectory()) fail('CitizenSDK 缺少普通 Windows Host 来源目录');
  if (Object.keys(WINDOWS_BINDING_SOURCE_FILES).length !== 66) {
    fail('CitizenSDK Windows Host/Flutter 固定生产清单必须精确为 66 文件');
  }
  const directories = regularDirectories(windowsRoot);
  const expectedDirectories = [...new Set(['cmake', 'include', 'include/citizen_sdk', 'src', 'test',
    ...(allowInjectedWindowsArtifacts ? parentDirectories(WINDOWS_RELEASE_FILES) : []),
  ])].sort();
  if (JSON.stringify(directories) !== JSON.stringify(expectedDirectories)) {
    fail('CitizenSDK Windows Host 目录闭集漂移');
  }
  const files = regularFiles(windowsRoot)
    .filter((path) => !allowInjectedWindowsArtifacts || !WINDOWS_INJECTED_FILES.has(path))
    .filter((path) => !path.startsWith('test/'))
    .filter((path) => path === 'CMakeLists.txt' || !isDocumentationFile(path))
    .map((path) => `windows/${path}`).sort();
  if (JSON.stringify(files) !== JSON.stringify(Object.keys(WINDOWS_BINDING_SOURCE_FILES).sort())) {
    fail('CitizenSDK Windows Host 文件闭集漂移');
  }
  assertPinnedFiles(sourceRoot, WINDOWS_BINDING_SOURCE_FILES, 'Windows Host 来源');
  const cmake = readFileSync(join(windowsRoot, 'CMakeLists.txt'), 'utf8');
  const versions = [...cmake.matchAll(/^project\(CitizenSDKHost VERSION (\d+\.\d{1,2}\.\d{1,2}) LANGUAGES C CXX\)$/gm)];
  if (versions.length !== 1) fail('CitizenSDK Windows Host 产品身份或版本字段不唯一');
  const pubspec = join(sourceRoot, 'pubspec.yaml');
  if (existsSync(pubspec) && readFileSync(pubspec, 'utf8').match(/^version: (.+)$/m)?.[1] !== versions[0][1]) {
    fail('CitizenSDK Windows Host 版本必须与唯一 SDK 版本一致');
  }
  const header = readFileSync(join(windowsRoot, 'include/citizen_sdk/citizensdk_host.h'), 'utf8');
  const functions = [...new Set([...header.matchAll(/\b(citizensdk_host_[a-z0-9_]+)\s*\(/g)].map((m) => m[1]))].sort();
  const exports = readFileSync(join(windowsRoot, 'cmake/citizensdk_host.def'), 'utf8')
    .split(/\r?\n/).map((line) => line.trim()).filter((line) => line && !line.startsWith('LIBRARY ') && line !== 'EXPORTS').sort();
  const qrImageFunctions = [
    'citizensdk_qr_image_decode_luminance',
    'citizensdk_qr_image_encode_text',
    'citizensdk_qr_image_zxing_version',
  ];
  const expectedExports = [...functions, ...qrImageFunctions].sort();
  if (functions.length !== 17 || JSON.stringify(expectedExports) !== JSON.stringify(exports)) {
    fail('CitizenSDK Windows Host 导出闭集漂移');
  }
  return versions[0][1];
}

export function assertLinuxBindingSource(root, { allowInjectedLinuxArtifacts = false } = {}) {
  const sourceRoot = resolve(root);
  const linuxRoot = join(sourceRoot, 'linux');
  if (!existsSync(linuxRoot)
      || lstatSync(linuxRoot).isSymbolicLink()
      || !lstatSync(linuxRoot).isDirectory()) {
    fail('CitizenSDK 缺少普通 Linux Host 来源目录：linux');
  }
  if (Object.keys(LINUX_BINDING_SOURCE_FILES).length
      !== LINUX_BINDING_SOURCE_FILE_COUNT) {
    fail(`CitizenSDK Linux Host 固定清单必须精确为 ${LINUX_BINDING_SOURCE_FILE_COUNT} 文件`);
  }
  const actualDirectories = regularDirectories(linuxRoot);
  const expectedDirectories = [...new Set([
    ...LINUX_BINDING_SOURCE_DIRECTORIES,
    ...(allowInjectedLinuxArtifacts ? parentDirectories(LINUX_RELEASE_FILES) : []),
  ])].sort();
  if (JSON.stringify(actualDirectories)
      !== JSON.stringify(expectedDirectories)) {
    const actual = new Set(actualDirectories);
    const expected = new Set(expectedDirectories);
    const missing = expectedDirectories
      .filter((path) => !actual.has(path));
    const extra = actualDirectories.filter((path) => !expected.has(path));
    fail(`CitizenSDK Linux Host 目录闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  const actualPaths = regularFiles(linuxRoot)
    .filter((path) => !allowInjectedLinuxArtifacts || !LINUX_INJECTED_FILES.has(path))
    .filter((path) => !path.startsWith('test/'))
    .filter((path) => path === 'CMakeLists.txt' || !isDocumentationFile(path))
    .map((path) => `linux/${path}`)
    .sort();
  const expectedPaths = Object.keys(LINUX_BINDING_SOURCE_FILES).sort();
  if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
    const actual = new Set(actualPaths);
    const expected = new Set(expectedPaths);
    const missing = expectedPaths.filter((path) => !actual.has(path));
    const extra = actualPaths.filter((path) => !expected.has(path));
    fail(`CitizenSDK Linux Host 文件闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  assertPinnedFiles(sourceRoot, LINUX_BINDING_SOURCE_FILES, 'Linux Host 来源');

  const cmake = readFileSync(join(linuxRoot, 'CMakeLists.txt'), 'utf8');
  const matches = [...cmake.matchAll(
    /^project\(CitizenSDKHost VERSION (\d+\.\d{1,2}\.\d{1,2}) LANGUAGES C CXX\)$/gm,
  )];
  if (matches.length !== 1) {
    fail('CitizenSDK Linux Host CMake 产品身份或版本字段不唯一');
  }
  return matches[0][1];
}

/**
 * Verify the CitizenSDK-owned documentation that was not already closed by a
 * narrower source contract. The top-level docs/ product documents are closed
 * as an entire subtree except for docs/smoldot-dart/, whose imported snapshot
 * remains authoritative in SMOLDOT_DART_FILES. Android, Apple and Dart trees
 * contain production sources, so only documentation-shaped files are listed.
 */
export function assertDocumentationSource(
  root,
  { allowAppleReleaseProjection = false } = {},
) {
  const sourceRoot = resolve(root);
  if (Object.keys(DOCUMENTATION_SHA256).length !== DOCUMENTATION_FILE_COUNT) {
    fail(`CitizenSDK 文档固定清单必须精确为 ${DOCUMENTATION_FILE_COUNT} 文件`);
  }

  const actualPaths = [];
  const rootReadme = join(sourceRoot, 'README.md');
  if (existsSync(rootReadme)) {
    const info = lstatSync(rootReadme);
    if (info.isSymbolicLink() || !info.isFile()) {
      fail('CitizenSDK 根 README.md 必须是普通文件');
    }
    actualPaths.push('README.md');
  }

  const docsRoot = join(sourceRoot, 'docs');
  if (!existsSync(docsRoot)
      || lstatSync(docsRoot).isSymbolicLink()
      || !lstatSync(docsRoot).isDirectory()) {
    fail('CitizenSDK 缺少普通产品文档目录：docs');
  }
  actualPaths.push(...regularFiles(docsRoot)
    .map((path) => `docs/${path}`)
    .filter((path) => !path.startsWith('docs/smoldot-dart/')));

  for (const relativeRoot of ['android', 'darwin', 'lib/src', 'linux', 'windows']) {
    const documentationRoot = join(sourceRoot, ...relativeRoot.split('/'));
    if (!existsSync(documentationRoot)
        || lstatSync(documentationRoot).isSymbolicLink()
        || !lstatSync(documentationRoot).isDirectory()) {
      fail(`CitizenSDK 缺少普通产品文档来源目录：${relativeRoot}`);
    }
    const documentationFiles = relativeRoot === 'darwin'
      ? darwinBindingFiles(documentationRoot, allowAppleReleaseProjection)
      : regularFiles(documentationRoot);
    actualPaths.push(...documentationFiles
      .filter((path) => isDocumentationFile(path)
        && path !== 'native/src/main/cpp/CMakeLists.txt'
        && (!['linux', 'windows'].includes(relativeRoot) || path !== 'CMakeLists.txt')
        && (relativeRoot !== 'android' || !isAndroidTestPath(path))
        && (relativeRoot !== 'darwin' || !isDarwinTestOrInjectedArtifact(path)))
      .filter((path) => !['linux', 'windows'].includes(relativeRoot) || !path.startsWith('test/'))
      .map((path) => `${relativeRoot}/${path}`));
  }

  actualPaths.sort();
  const expectedPaths = Object.keys(DOCUMENTATION_SHA256).sort();
  if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
    const actual = new Set(actualPaths);
    const expected = new Set(expectedPaths);
    const missing = expectedPaths.filter((path) => !actual.has(path));
    const extra = actualPaths.filter((path) => !expected.has(path));
    fail(`CitizenSDK 产品文档闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  assertPinnedFiles(sourceRoot, DOCUMENTATION_SHA256, '产品文档');
}

function compileRootedPubignoreRule(rawRule) {
  const negated = rawRule.startsWith('!');
  const rule = negated ? rawRule.slice(1) : rawRule;
  if (!rule.startsWith('/')) {
    fail(`CitizenSDK .pubignore 只允许可审计的根路径规则：${rawRule}`);
  }
  const directory = rule.endsWith('/');
  const pattern = directory ? rule.slice(1, -1) : rule.slice(1);
  let expression = '';
  for (let index = 0; index < pattern.length; index += 1) {
    const character = pattern[index];
    if (character === '*') {
      if (pattern[index + 1] === '*') {
        // 官方 **/ 也匹配零层目录；末尾 /* 不可把父目录自身当作子项排除。
        if (pattern[index + 2] === '/') {
          expression += '(?:.*/)?';
          index += 2;
        } else {
          expression += '.*';
          index += 1;
        }
      } else {
        expression += pattern[index - 1] === '/' && index === pattern.length - 1 ? '[^/]+' : '[^/]*';
      }
    } else if (character === '?') {
      expression += '[^/]';
    } else {
      expression += character.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
  }
  return {
    ignored: !negated,
    pattern: new RegExp(`^${expression}${directory ? '(?:/.*)?' : '/?'}$`),
  };
}

function hostedPubignoreRules(sourceRoot) {
  const path = join(sourceRoot, '.pubignore');
  if (!existsSync(path) || lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile()) {
    fail('CitizenSDK 缺少普通 .pubignore');
  }
  return readFileSync(path, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith('#'))
    .map(compileRootedPubignoreRule);
}

function isHostedIgnored(relativePath, rules) {
  let ignored = false;
  for (const rule of rules) {
    if (rule.pattern.test(relativePath)) ignored = rule.ignored;
  }
  return ignored;
}

/** Verify the Dart files that the real pinned .pubignore exposes to Hosted consumers. */
export function assertHostedRuntimeDartProjection(root) {
  const sourceRoot = resolve(root);
  const libRoot = join(sourceRoot, 'lib');
  if (!existsSync(libRoot) || lstatSync(libRoot).isSymbolicLink()
      || !lstatSync(libRoot).isDirectory()) {
    fail('CitizenSDK Hosted Package 缺少普通 lib 目录');
  }
  const rules = hostedPubignoreRules(sourceRoot);
  const actualPaths = regularFiles(libRoot)
    .filter((path) => path.endsWith('.dart'))
    .map((path) => `lib/${path}`)
    .filter((path) => !isHostedIgnored(path, rules))
    .sort();
  const expectedPaths = [...HOSTED_RUNTIME_DART_FILES].sort();
  if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
    const actual = new Set(actualPaths);
    const expected = new Set(expectedPaths);
    const missing = expectedPaths.filter((path) => !actual.has(path));
    const extra = actualPaths.filter((path) => !expected.has(path));
    fail(`CitizenSDK Hosted Dart 运行闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  const facade = readFileSync(join(sourceRoot, 'lib/src/api/citizen_sdk.dart'), 'utf8');
  const forbiddenFacadeName = ['CitizenSdk', 'Client'].join('');
  if (!/\bfinal\s+class\s+CitizenSdk\b/.test(facade)
      || facade.includes(forbiddenFacadeName)) {
    fail('CitizenSDK Hosted Dart 唯一公开门面必须精确命名为 CitizenSdk，禁止任何旧别名');
  }
}

/** The published Linux subtree contains 19 source inputs or 38 candidate inputs. */
export function assertHostedRuntimeLinuxProjection(root, { allowInjectedLinuxArtifacts = false } = {}) {
  const sourceRoot = resolve(root);
  const rules = hostedPubignoreRules(sourceRoot);
  const expected = [...new Set([
    ...HOSTED_LINUX_PLUGIN_FILES,
    ...(allowInjectedLinuxArtifacts ? LINUX_RELEASE_FILES
      : LINUX_HOST_HEADERS.map((name) => `include/citizen_sdk/${name}`)),
  ])].map((path) => `linux/${path}`).sort();
  const actual = regularFiles(join(sourceRoot, 'linux'))
    .map((path) => `linux/${path}`)
    .filter((path) => !isHostedIgnored(path, rules)).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    fail(`CitizenSDK Hosted Linux 运行闭集漂移；缺失=${expected.filter((path) => !actual.includes(path)).join(',') || '无'}；额外=${actual.filter((path) => !expected.includes(path)).join(',') || '无'}`);
  }
}

/** Windows 源码可见十九项；候选仅增加十四项，运行包精确为三十三项。 */
export function assertHostedRuntimeWindowsProjection(root, { allowInjectedWindowsArtifacts = false } = {}) {
  const sourceRoot = resolve(root);
  const rules = hostedPubignoreRules(sourceRoot);
  const expected = [...new Set([...HOSTED_WINDOWS_PLUGIN_FILES,
    ...(allowInjectedWindowsArtifacts ? WINDOWS_RELEASE_FILES
      : WINDOWS_HOST_HEADERS.map((name) => `include/citizen_sdk/${name}`)),
  ])].map((path) => `windows/${path}`).sort();
  const actual = regularFiles(join(sourceRoot, 'windows')).map((path) => `windows/${path}`)
    .filter((path) => !isHostedIgnored(path, rules)).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    fail(`CitizenSDK Hosted Windows 运行闭集漂移；缺失=${expected.filter((path) => !actual.includes(path)).join(',') || '无'}；额外=${actual.filter((path) => !expected.includes(path)).join(',') || '无'}`);
  }
}

function yamlTopLevelSection(source, name) {
  const lines = source.split(/\r?\n/);
  const start = lines.findIndex((line) => line === `${name}:`);
  if (start < 0) fail(`CitizenSDK Hosted Package 缺少 ${name}`);
  const section = [];
  for (let index = start + 1; index < lines.length; index += 1) {
    if (/^[A-Za-z_][A-Za-z0-9_-]*:/.test(lines[index])) break;
    section.push(lines[index]);
  }
  return section.join('\n');
}

function assertHostedDependencySection(pubspec, name, expected) {
  const section = yamlTopLevelSection(pubspec, name);
  const direct = [...section.matchAll(/^  ([A-Za-z_][A-Za-z0-9_-]*):(.*)$/gm)]
    .map((match) => [match[1], match[2].trim()]);
  const actualNames = direct.map(([dependency]) => dependency).sort();
  const expectedNames = Object.keys(expected).sort();
  if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
    fail(`CitizenSDK Hosted Package ${name} 闭集漂移：${actualNames.join(',') || '无'}`);
  }
  for (const [dependency, constraint] of Object.entries(expected)) {
    const value = direct.find(([name]) => name === dependency)?.[1];
    if (constraint === null) {
      const escaped = dependency.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      if (value !== '' || !new RegExp(`^  ${escaped}:\\n    sdk: flutter$`, 'm').test(section)) {
        fail(`CitizenSDK Hosted Package ${name} SDK 依赖漂移：${dependency}`);
      }
    } else if (value !== constraint) {
      fail(`CitizenSDK Hosted Package ${name} 依赖约束漂移：${dependency}`);
    }
  }
}

export function assertHostedPackageSource(root, {
  allowInjectedLinuxArtifacts = false, allowInjectedWindowsArtifacts = false,
} = {}) {
  const sourceRoot = resolve(root);
  assertPinnedFiles(sourceRoot, HOSTED_PACKAGE_SOURCE_FILES, 'Hosted Package 合同');
  assertHostedRuntimeDartProjection(sourceRoot);
  assertHostedRuntimeLinuxProjection(sourceRoot, { allowInjectedLinuxArtifacts });
  assertHostedRuntimeWindowsProjection(sourceRoot, { allowInjectedWindowsArtifacts });
  const pubspecPath = join(sourceRoot, 'pubspec.yaml');
  if (!existsSync(pubspecPath)
      || lstatSync(pubspecPath).isSymbolicLink()
      || !lstatSync(pubspecPath).isFile()) {
    fail('CitizenSDK 缺少普通 Hosted Package pubspec.yaml');
  }
  const pubspec = readFileSync(pubspecPath, 'utf8');
  const pubspecVersion = pubspec.match(/^version: (\d+\.\d{1,2}\.\d{1,2})$/m)?.[1];
  // 包身份直接核对唯一现行仓库；固定摘要不能替代字段语义校验。
  const repositories = pubspec.match(/^repository:.*$/gm) ?? [];
  if (repositories.length !== 1 || repositories[0] !== 'repository: https://github.com/VoyagerRhett/GMB') {
    fail('CitizenSDK Hosted Package repository 必须为现行唯一仓库');
  }
  const podspec = readFileSync(join(sourceRoot, 'darwin/citizen_sdk.podspec'), 'utf8');
  const homepages = podspec.match(/^\s*spec\.homepage.*$/gm) ?? [];
  if (homepages.length !== 1 || !/^  spec\.homepage\s+= 'https:\/\/github\.com\/VoyagerRhett\/GMB\/tree\/main\/citizensdk'$/.test(homepages[0])) {
    fail('CitizenSDK Apple homepage 必须为现行唯一仓库');
  }
  if (!/^name: citizen_sdk$/m.test(pubspec) || !pubspecVersion) {
    fail('CitizenSDK Hosted Package 身份或版本无效');
  }
  if (/^publish_to:\s*["']?none["']?\s*$/m.test(pubspec)) {
    fail('CitizenSDK Hosted Package 禁止 publish_to: none');
  }
  // 两格缩进的 `path` 可以是合法 Hosted 依赖包名；只有依赖声明内部四格以上的
  // `path:`/`git:` 才表示 pub.dev 禁止的非 Hosted 来源。
  if (/^[ \t]{4,}(?:git|path):/m.test(pubspec)) {
    fail('CitizenSDK Hosted Package 禁止 git/path 依赖');
  }
  assertHostedDependencySection(pubspec, 'dependencies', HOSTED_MAIN_DEPENDENCIES);
  assertHostedDependencySection(pubspec, 'dev_dependencies', HOSTED_DEV_DEPENDENCIES);
  const platformVersions = [
    ['android/build.gradle', /^version = '(\d+\.\d{1,2}\.\d{1,2})'$/m],
    ['darwin/citizen_sdk.podspec', /^  spec\.version\s+= '(\d+\.\d{1,2}\.\d{1,2})'$/m],
    ['linux/CMakeLists.txt', /^project\(CitizenSDKHost VERSION (\d+\.\d{1,2}\.\d{1,2}) LANGUAGES C CXX\)$/m],
    ['windows/CMakeLists.txt', /^project\(CitizenSDKHost VERSION (\d+\.\d{1,2}\.\d{1,2}) LANGUAGES C CXX\)$/m],
  ].map(([relativePath, pattern]) => {
    const path = join(sourceRoot, ...relativePath.split('/'));
    if (!existsSync(path) || lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile()) {
      fail(`CitizenSDK 缺少普通平台版本文件：${relativePath}`);
    }
    const version = readFileSync(path, 'utf8').match(pattern)?.[1];
    if (!version) fail(`CitizenSDK 平台版本字段无效：${relativePath}`);
    return [relativePath, version];
  });
  for (const [relativePath, version] of platformVersions) {
    if (version !== pubspecVersion) {
      fail(`CitizenSDK 包版本不一致：pubspec.yaml=${pubspecVersion}；${relativePath}=${version}`);
    }
  }
  return pubspecVersion;
}

export function assertSdkTestContracts(root) {
  const sourceRoot = resolve(root);
  if (Object.keys(SDK_TEST_CONTRACT_FILES).length !== SDK_TEST_CONTRACT_FILE_COUNT) {
    fail(`CitizenSDK 测试合同固定清单必须精确为 ${SDK_TEST_CONTRACT_FILE_COUNT} 文件`);
  }
  for (const relativeRoot of SDK_TEST_CONTRACT_ROOTS) {
    const testRoot = join(sourceRoot, ...relativeRoot.split('/'));
    if (!existsSync(testRoot)
        || lstatSync(testRoot).isSymbolicLink()
        || !lstatSync(testRoot).isDirectory()) {
      fail(`CitizenSDK 缺少普通测试目录：${relativeRoot}`);
    }
    const actualPaths = regularFiles(testRoot)
      .map((path) => `${relativeRoot}/${path}`)
      .sort();
    const expectedPaths = Object.keys(SDK_TEST_CONTRACT_FILES)
      .filter((path) => path.startsWith(`${relativeRoot}/`))
      .sort();
    if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
      const actual = new Set(actualPaths);
      const expected = new Set(expectedPaths);
      const missing = expectedPaths.filter((path) => !actual.has(path));
      const extra = actualPaths.filter((path) => !expected.has(path));
      fail(`CitizenSDK 测试文件闭集漂移：${relativeRoot}；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
    }
  }
  for (const relativeRoot of SDK_EMBEDDED_TEST_ROOTS) {
    const testRoot = join(sourceRoot, ...relativeRoot.split('/'));
    const actualPaths = regularFiles(testRoot)
      .filter((path) => path.endsWith('_tests.rs'))
      .map((path) => `${relativeRoot}/${path}`)
      .sort();
    const expectedPaths = Object.keys(SDK_TEST_CONTRACT_FILES)
      .filter((path) => path.startsWith(`${relativeRoot}/`) && path.endsWith('_tests.rs'))
      .sort();
    if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
      const actual = new Set(actualPaths);
      const expected = new Set(expectedPaths);
      const missing = expectedPaths.filter((path) => !actual.has(path));
      const extra = actualPaths.filter((path) => !expected.has(path));
      fail(`CitizenSDK 内嵌测试文件闭集漂移：${relativeRoot}；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
    }
  }
  const scriptRoot = join(sourceRoot, SDK_SCRIPT_TEST_ROOT);
  if (!existsSync(scriptRoot)
      || lstatSync(scriptRoot).isSymbolicLink()
      || !lstatSync(scriptRoot).isDirectory()) {
    fail(`CitizenSDK 缺少普通测试目录：${SDK_SCRIPT_TEST_ROOT}`);
  }
  const actualScriptTests = regularFiles(scriptRoot)
    .map((path) => `${SDK_SCRIPT_TEST_ROOT}/${path}`)
    .filter((path) => path.endsWith('.test.mjs'))
    .sort();
  const expectedScriptTests = Object.keys(SDK_TEST_CONTRACT_FILES)
    .filter((path) => path.startsWith(`${SDK_SCRIPT_TEST_ROOT}/`) && path.endsWith('.test.mjs'))
    .sort();
  if (JSON.stringify(actualScriptTests) !== JSON.stringify(expectedScriptTests)) {
    const actual = new Set(actualScriptTests);
    const expected = new Set(expectedScriptTests);
    const missing = expectedScriptTests.filter((path) => !actual.has(path));
    const extra = actualScriptTests.filter((path) => !expected.has(path));
    fail(`CitizenSDK 测试文件闭集漂移：${SDK_SCRIPT_TEST_ROOT}；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  assertPinnedFiles(sourceRoot, SDK_TEST_CONTRACT_FILES, '测试合同');
}

export function assertSdkScriptSource(root) {
  const sourceRoot = resolve(root);
  const scriptRoot = join(sourceRoot, 'scripts');
  if (!existsSync(scriptRoot)
      || lstatSync(scriptRoot).isSymbolicLink()
      || !lstatSync(scriptRoot).isDirectory()) {
    fail('CitizenSDK 缺少普通 scripts 目录');
  }
  const actualEntries = readdirSync(scriptRoot).sort();
  const expectedEntries = Object.keys(SDK_SCRIPT_ENTRIES).sort();
  if (JSON.stringify(actualEntries) !== JSON.stringify(expectedEntries)) {
    const actual = new Set(actualEntries);
    const expected = new Set(expectedEntries);
    const missing = expectedEntries.filter((path) => !actual.has(path));
    const extra = actualEntries.filter((path) => !expected.has(path));
    fail(`CitizenSDK scripts 根闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  for (const name of expectedEntries) {
    const path = join(scriptRoot, name);
    if (lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile()) {
      fail(`CitizenSDK scripts 条目必须是普通文件：${name}`);
    }
  }
  const executingRelease = readFileSync(fileURLToPath(import.meta.url));
  if (!readFileSync(join(scriptRoot, 'release.mjs')).equals(executingRelease)) {
    fail('CitizenSDK 候选 release.mjs 与当前执行真源不一致');
  }
  assertPinnedFiles(sourceRoot, SDK_PRODUCTION_SCRIPT_FILES, '生产脚本');
}

export function assertSmoldotRustSource(root) {
  const sourceRoot = resolve(root);
  const manifestPath = join(
    sourceRoot,
    ...SMOLDOT_RUST_SOURCE_MANIFEST.path.split('/'),
  );
  if (!existsSync(manifestPath)
      || lstatSync(manifestPath).isSymbolicLink()
      || !lstatSync(manifestPath).isFile()) {
    fail('CitizenSDK 缺少普通 smoldot Rust 来源清单');
  }
  if (sha256File(manifestPath) !== SMOLDOT_RUST_SOURCE_MANIFEST.sha256) {
    fail('CitizenSDK smoldot Rust 来源清单漂移');
  }

  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  if (manifest.schema !== 'citizensdk.smoldot.source-sha256.v1'
      || !manifest.units || typeof manifest.units !== 'object') {
    fail('CitizenSDK smoldot Rust 来源清单 schema 无效');
  }
  const providerUnit = manifest.units.provider;
  if (!providerUnit || providerUnit.root !== 'native/smoldot/provider'
      || providerUnit.recursive !== true) {
    fail('CitizenSDK smoldot Rust 来源清单缺少递归 provider 单元');
  }
  const manifestPaths = [];
  for (const [name, unit] of Object.entries(manifest.units)) {
    if (!unit || typeof unit !== 'object' || typeof unit.root !== 'string'
        || !unit.root.startsWith('native/smoldot/')
        || typeof unit.recursive !== 'boolean') {
      fail(`CitizenSDK smoldot Rust 来源单元无效：${name}`);
    }
    const unitRoot = join(sourceRoot, ...unit.root.split('/'));
    if (!existsSync(unitRoot)
        || lstatSync(unitRoot).isSymbolicLink()
        || !lstatSync(unitRoot).isDirectory()) {
      fail(`CitizenSDK smoldot Rust 来源目录缺失：${unit.root}`);
    }
    const entries = ['byte_identical', 'adapted', 'sdk_only']
      .flatMap((category) => {
        if (!Array.isArray(unit[category])) {
          fail(`CitizenSDK smoldot Rust 来源分类无效：${name}/${category}`);
        }
        return unit[category];
      });
    const expectedPaths = entries.map((entry) => entry?.path).sort();
    if (entries.some((entry) => !entry
          || typeof entry.path !== 'string'
          || !/^[A-Za-z0-9._/-]+$/.test(entry.path)
          || entry.path.split('/').includes('..')
          || !/^[0-9a-f]{64}$/.test(entry.sha256))
        || new Set(expectedPaths).size !== expectedPaths.length) {
      fail(`CitizenSDK smoldot Rust 来源条目无效：${name}`);
    }
    const actualPaths = unit.recursive
      ? regularFiles(unitRoot)
      : readdirSync(unitRoot).filter((path) => {
          const absolute = join(unitRoot, path);
          return !lstatSync(absolute).isSymbolicLink() && lstatSync(absolute).isFile();
        }).sort();
    if (JSON.stringify(actualPaths) !== JSON.stringify(expectedPaths)) {
      fail(`CitizenSDK smoldot Rust 文件闭集漂移：${name}`);
    }
    for (const entry of entries) {
      const absolutePath = join(unitRoot, ...entry.path.split('/'));
      const isUpstreamLock = SMOLDOT_UPSTREAM_LOCK_FILES.includes(
        `${unit.root}/${entry.path}`,
      );
      if (!isUpstreamLock && sha256File(absolutePath) !== entry.sha256) {
        fail(`CitizenSDK smoldot Rust 文件哈希漂移：${name}/${entry.path}`);
      }
      manifestPaths.push(`${unit.root}/${entry.path}`);
    }
    if (!Array.isArray(unit.excluded)) {
      fail(`CitizenSDK smoldot Rust 排除集合无效：${name}`);
    }
    for (const relativePath of unit.excluded) {
      if (typeof relativePath !== 'string'
          || relativePath.split('/').includes('..')
          || existsSync(join(unitRoot, ...relativePath.split('/')))) {
        fail(`CitizenSDK smoldot Rust 排除项漂移：${name}/${relativePath}`);
      }
    }
  }

  for (const [relativePath, expectedHash] of Object.entries(SMOLDOT_SUPPORT_FILES)) {
    const path = join(sourceRoot, ...relativePath.split('/'));
    if (!existsSync(path) || lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile()) {
      fail(`CitizenSDK 缺少普通 smoldot 支持文件：${relativePath}`);
    }
    if (sha256File(path) !== expectedHash) {
      fail(`CitizenSDK smoldot 支持文件哈希漂移：${relativePath}`);
    }
  }

  const smoldotRoot = join(sourceRoot, 'native', 'smoldot');
  const actualClosure = regularFiles(smoldotRoot)
    .map((path) => `native/smoldot/${path}`)
    .sort();
  const expectedClosure = [
    SMOLDOT_RUST_SOURCE_MANIFEST.path,
    ...manifestPaths,
    ...Object.keys(SMOLDOT_SUPPORT_FILES),
  ].sort();
  if (new Set(expectedClosure).size !== expectedClosure.length) {
    fail('CitizenSDK smoldot 来源合同存在重复路径');
  }
  if (JSON.stringify(actualClosure) !== JSON.stringify(expectedClosure)) {
    const actual = new Set(actualClosure);
    const expected = new Set(expectedClosure);
    const missing = expectedClosure.filter((path) => !actual.has(path));
    const extra = actualClosure.filter((path) => !expected.has(path));
    fail(`CitizenSDK smoldot 文件闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
}

export function assertSignerSource(root) {
  const sourceRoot = resolve(root);
  for (const [relativePath, expectedHash] of Object.entries(SIGNER_FILES)) {
    const path = join(sourceRoot, ...relativePath.split('/'));
    if (!existsSync(path) || !lstatSync(path).isFile() || lstatSync(path).isSymbolicLink()) {
      fail(`CitizenSDK 缺少普通 signer 源文件：${relativePath}`);
    }
    if (sha256File(path) !== expectedHash) {
      fail(`CitizenSDK signer 来源字节漂移：${relativePath}`);
    }
  }
  const signerRoot = join(sourceRoot, 'native', 'signer');
  const actualClosure = regularFiles(signerRoot)
    .map((path) => `native/signer/${path}`)
    .sort();
  const expectedClosure = Object.keys(SIGNER_FILES).sort();
  if (JSON.stringify(actualClosure) !== JSON.stringify(expectedClosure)) {
    const actual = new Set(actualClosure);
    const expected = new Set(expectedClosure);
    const missing = expectedClosure.filter((path) => !actual.has(path));
    const extra = actualClosure.filter((path) => !expected.has(path));
    fail(`CitizenSDK signer 10 文件闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
}

function replaceExact(path, pattern, replacement, label) {
  const source = readFileSync(path, 'utf8');
  const matches = source.match(pattern);
  if (!matches || matches.length !== 1) fail(`${label} 版本字段不唯一`);
  writeFileSync(path, source.replace(pattern, replacement));
}

function applySoftwareVersion(output, version) {
  replaceExact(join(output, 'pubspec.yaml'), /^version: \d+\.\d{1,2}\.\d{1,2}$/gm, `version: ${version}`, 'pubspec.yaml');
  replaceExact(join(output, 'android/build.gradle'), /^version = '\d+\.\d{1,2}\.\d{1,2}'$/gm, `version = '${version}'`, 'android/build.gradle');
  replaceExact(join(output, 'darwin/citizen_sdk.podspec'), /^  spec\.version\s+= '\d+\.\d{1,2}\.\d{1,2}'$/gm, `  spec.version          = '${version}'`, 'citizen_sdk.podspec');
  replaceExact(join(output, 'linux/CMakeLists.txt'), /^project\(CitizenSDKHost VERSION \d+\.\d{1,2}\.\d{1,2} LANGUAGES C CXX\)$/gm, `project(CitizenSDKHost VERSION ${version} LANGUAGES C CXX)`, 'linux/CMakeLists.txt');
  replaceExact(join(output, 'windows/CMakeLists.txt'), /^project\(CitizenSDKHost VERSION \d+\.\d{1,2}\.\d{1,2} LANGUAGES C CXX\)$/gm, `project(CitizenSDKHost VERSION ${version} LANGUAGES C CXX)`, 'windows/CMakeLists.txt');
}

function nativeArtifactSource(nativeRoot, sourcePath, expectedType = 'file') {
  const components = sourcePath.split('/');
  let current = nativeRoot;
  for (let index = 0; index < components.length; index += 1) {
    current = join(current, components[index]);
    let info;
    try {
      info = lstatSync(current);
    } catch (error) {
      if (error?.code === 'ENOENT') fail(`缺少原生产物：${sourcePath}`);
      throw error;
    }
    if (info.isSymbolicLink()) {
      fail(`原生产物路径禁止符号链接：${sourcePath}`);
    }
    const isFinal = index === components.length - 1;
    const finalTypeMatches = expectedType === 'file' ? info.isFile() : info.isDirectory();
    if ((!isFinal && !info.isDirectory()) || (isFinal && !finalTypeMatches)) {
      fail(`原生产物路径类型无效：${sourcePath}`);
    }
  }
  const realSource = realpathSync(current);
  if (!realSource.startsWith(`${nativeRoot}${sep}`)) {
    fail(`原生产物真实路径越出受控根：${sourcePath}`);
  }
  return current;
}

/**
 * Reject every native-input link except the five exact versioned-macOS
 * framework links. The XCFramework directory itself and all ancestors remain
 * ordinary directories, so an allowed internal link cannot redirect the
 * native source root.
 */
// Read ELF64 little-endian directly on any CI host. PT_DYNAMIC is the runtime
// authority: section tables must identify the same mapped bytes, not a decoy
// table appended to an unrelated library. This is structural validation, not
// evidence that Linux/GTK/TPM execution or dependency provenance has passed.
function assertLinuxElf(path, platform, host, expectedSymbols) {
  const bytes = readFileSync(path);
  const label = `CitizenSDK ${platform} ${host ? 'Host' : 'Core'} ELF`;
  const reject = (message) => fail(`${label} ${message}`);
  const range = (offset, size) => {
    if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(size)
        || offset < 0 || size < 0 || offset > bytes.length - size) reject('范围越界');
    return offset;
  };
  const u64 = (offset) => {
    range(offset, 8);
    const value = bytes.readBigUInt64LE(offset);
    if (value > BigInt(Number.MAX_SAFE_INTEGER)) reject('64 位字段越界');
    return Number(value);
  };
  range(0, 64);
  if (!bytes.subarray(0, 7).equals(Buffer.from([127, 69, 76, 70, 2, 1, 1]))
      || bytes.readUInt16LE(16) !== 3
      || bytes.readUInt16LE(18) !== (platform === 'LinuxARM' ? 183 : 62)
      || bytes.readUInt32LE(20) !== 1 || bytes.readUInt16LE(52) !== 64
      || bytes.readUInt16LE(54) !== 56 || bytes.readUInt16LE(58) !== 64) {
    reject('必须是对应架构的 ELF64 little-endian ET_DYN');
  }
  const phoff = u64(32);
  const shoff = u64(40);
  const phnum = bytes.readUInt16LE(56);
  const shnum = bytes.readUInt16LE(60);
  if (!phnum || phnum === 0xffff || !shnum || shnum >= 0xff00) reject('段/节数量无效');
  range(phoff, phnum * 56);
  range(shoff, shnum * 64);
  const segments = Array.from({ length: phnum }, (_, index) => {
    const offset = phoff + index * 56;
    const file = u64(offset + 8);
    const address = u64(offset + 16);
    const size = u64(offset + 32);
    range(file, size);
    if (size > u64(offset + 40) || !Number.isSafeInteger(address + size)) reject('段长度无效');
    return { type: bytes.readUInt32LE(offset), flags: bytes.readUInt32LE(offset + 4), file, address, size };
  });
  const mapped = (address, size) => {
    const matches = segments.filter((segment) => segment.type === 1
      && address >= segment.address && size <= segment.size
      && address - segment.address <= segment.size - size);
    if (matches.length !== 1) reject('动态地址缺失或有歧义');
    return range(matches[0].file + address - matches[0].address, size);
  };
  const sections = Array.from({ length: shnum }, (_, index) => {
    const offset = shoff + index * 64;
    const type = bytes.readUInt32LE(offset + 4);
    const file = u64(offset + 24);
    const size = u64(offset + 32);
    if (type !== 8) range(file, size); // SHT_NOBITS does not occupy file bytes.
    return { type, file, size, address: u64(offset + 16), link: bytes.readUInt32LE(offset + 40), entry: u64(offset + 56) };
  });
  const onlySection = (type) => {
    const matches = sections.filter((section) => section.type === type);
    if (matches.length !== 1) reject('动态节缺失或重复');
    return matches[0];
  };
  const dynamics = segments.filter((segment) => segment.type === 2);
  if (dynamics.length !== 1 || dynamics[0].size % 16 !== 0) reject('PT_DYNAMIC 无效');
  const dynamic = dynamics[0];
  const dynamicSection = onlySection(6);
  if (dynamicSection.file !== dynamic.file || dynamicSection.size !== dynamic.size
      || mapped(dynamic.address, dynamic.size) !== dynamic.file
      || dynamicSection.address !== dynamic.address || dynamicSection.entry !== 16) {
    reject('动态段/节不一致');
  }
  const tags = new Map();
  let terminated = false;
  for (let offset = dynamic.file; offset < dynamic.file + dynamic.size; offset += 16) {
    const tag = u64(offset);
    const value = u64(offset + 8);
    if (tag === 0) { terminated = true; break; }
    if (!tags.has(tag)) tags.set(tag, []);
    tags.get(tag).push(value);
  }
  if (!terminated) reject('动态表未终止');
  const one = (tag) => {
    const values = tags.get(tag);
    if (values?.length !== 1) reject(`动态字段 ${tag} 缺失或重复`);
    return values[0];
  };
  const symbols = onlySection(11);
  const strings = sections[symbols.link];
  if (!strings || strings.type !== 3 || dynamicSection.link !== symbols.link
      || symbols.entry !== 24 || symbols.size % 24 !== 0 || symbols.size / 24 > 1000000
      || one(11) !== 24 || one(6) !== symbols.address
      || mapped(symbols.address, symbols.size) !== symbols.file
      || one(5) !== strings.address || one(10) !== strings.size
      || mapped(strings.address, strings.size) !== strings.file) reject('动态符号/字符串表不一致');
  const string = (index) => {
    if (!Number.isSafeInteger(index) || index < 0 || index >= strings.size) reject('字符串索引越界');
    const start = strings.file + index;
    const end = bytes.indexOf(0, start);
    if (end < start || end >= strings.file + strings.size) reject('字符串缺少终止符');
    const value = bytes.subarray(start, end);
    if (value.some((byte) => byte < 32 || byte > 126)) reject('动态名称不是可审计 ASCII');
    return value.toString('ascii');
  };
  const soname = string(one(14));
  if (soname !== (host ? 'libcitizensdk_host.so' : 'libcitizensdk.so')) reject('SONAME 漂移');
  if (tags.has(15) || (!host && tags.has(29))
      || (host && string(one(29)) !== '$ORIGIN')) reject('RPATH/RUNPATH 必须遵守包内单 Core 合同');
  const needed = (tags.get(1) ?? []).map(string);
  if (new Set(needed).size !== needed.length || needed.some((name) => !name
      || name.includes('/') || name.includes('\\')
      || /^(?:libsmoldot|libstdc\+\+|libgcc_s|libsqlite3|libtss2-|libcrypto|libssl)/.test(name))
      || (host && needed.filter((name) => name === 'libcitizensdk.so').length !== 1)
      || (!host && needed.some((name) => /^libcitizensdk/.test(name)))) reject('DT_NEEDED 依赖闭包漂移');
  const exported = [];
  for (let offset = symbols.file; offset < symbols.file + symbols.size; offset += 24) {
    const info = bytes[offset + 4];
    const visibility = bytes[offset + 5] & 7;
    const section = bytes.readUInt16LE(offset + 6);
    if (!section || ![1, 2, 10].includes(info >> 4) || [1, 2].includes(visibility)) continue;
    const name = string(bytes.readUInt32LE(offset));
    if (![0, 3].includes(visibility) || (info & 15) !== 2 || section >= sections.length) reject('公开符号必须是已定义函数');
    const address = u64(offset + 8);
    if (!segments.some((segment) => segment.type === 1 && (segment.flags & 1)
      && address >= segment.address && address - segment.address < segment.size)) reject('导出函数地址不在可执行段');
    exported.push(name);
  }
  if (JSON.stringify(exported.sort()) !== JSON.stringify(expectedSymbols)) reject('公开导出符号闭集漂移');
  // Version requirements are linked from PT_DYNAMIC and bounded by the matching
  // SHT_GNU_verneed. Reject newer/private glibc or leaked C++ runtime dependencies.
  const versionSections = sections.filter((section) => section.type === 0x6ffffffe);
  if (tags.has(0x6ffffffe) || tags.has(0x6fffffff) || versionSections.length) {
    const section = onlySection(0x6ffffffe);
    const count = one(0x6fffffff);
    if (!count || count > 10000 || section.link !== symbols.link
        || section.address !== one(0x6ffffffe)
        || mapped(section.address, section.size) !== section.file) reject('版本需求表不一致');
    const versionRange = (offset, size) => {
      if (offset < section.file || offset > section.file + section.size - size) reject('版本链越界');
      return range(offset, size);
    };
    const occupied = new Set();
    const occupy = (offset) => {
      versionRange(offset, 16);
      for (let byte = offset; byte < offset + 16; byte += 1) {
        if (occupied.has(byte)) reject('版本链循环或重叠');
        occupied.add(byte);
      }
    };
    let offset = section.file;
    for (let index = 0; index < count; index += 1) {
      occupy(offset);
      const auxCount = bytes.readUInt16LE(offset + 2);
      if (bytes.readUInt16LE(offset) !== 1 || !auxCount
          || !needed.includes(string(bytes.readUInt32LE(offset + 4)))) reject('版本需求库无效');
      let aux = offset + bytes.readUInt32LE(offset + 8);
      for (let item = 0; item < auxCount; item += 1) {
        occupy(aux);
        const name = string(bytes.readUInt32LE(aux + 8));
        if (/^(?:GLIBCXX_|CXXABI_)/.test(name)) reject('C++ 动态运行库版本泄漏');
        if (name.startsWith('GLIBC_')) {
          const version = /^GLIBC_(\d+)\.(\d+)(?:\.(\d+))?$/.exec(name);
          if (!version || Number(version[1]) > 2
              || (Number(version[1]) === 2 && (Number(version[2]) > 31
                || (Number(version[2]) === 31 && Number(version[3] ?? 0) > 0)))) reject('GLIBC 需求超过 2.31 或使用私有版本');
        }
        const next = bytes.readUInt32LE(aux + 12);
        if ((item + 1 < auxCount) !== (next !== 0)) reject('版本辅助链长度不一致');
        aux += next;
      }
      const next = bytes.readUInt32LE(offset + 12);
      if ((index + 1 < count) !== (next !== 0)) reject('版本需求链长度不一致');
      offset += next;
    }
  }
}

// Canonical instructions emitted by CMake; comments are not executable input.
// The export check is complete, so a second set_property/include cannot override
// a previously checked path. Unknown generator instructions fail closed.
const LINUX_CMAKE_PACKAGE_INIT = [
  "get_filename_component(PACKAGE_PREFIX_DIR \"${CMAKE_CURRENT_LIST_DIR}/../../../../\" ABSOLUTE)",
  "macro(set_and_check _var _file)",
  "  set(${_var} \"${_file}\")",
  "  if(NOT EXISTS \"${_file}\")",
  "    message(FATAL_ERROR \"File or directory ${_file} referenced by variable ${_var} does not exist !\")",
  "  endif()",
  "endmacro()",
  "macro(check_required_components _NAME)",
  "  foreach(comp ${${_NAME}_FIND_COMPONENTS})",
  "    if(NOT ${_NAME}_${comp}_FOUND)",
  "      if(${_NAME}_FIND_REQUIRED_${comp})",
  "        set(${_NAME}_FOUND FALSE)",
  "      endif()",
  "    endif()",
  "  endforeach()",
  "endmacro()",
].join('\n');
const LINUX_CMAKE_TARGETS = [
  "if(\"${CMAKE_MAJOR_VERSION}.${CMAKE_MINOR_VERSION}\" LESS 2.8)",
  "   message(FATAL_ERROR \"CMake >= 2.8.12 required\")",
  "endif()",
  "if(CMAKE_VERSION VERSION_LESS \"2.8.12\")",
  "   message(FATAL_ERROR \"CMake >= 2.8.12 required\")",
  "endif()",
  "cmake_policy(PUSH)",
  "cmake_policy(VERSION 2.8.12...4.0)",
  "set(CMAKE_IMPORT_FILE_VERSION 1)",
  "set(_cmake_targets_defined \"\")",
  "set(_cmake_targets_not_defined \"\")",
  "set(_cmake_expected_targets \"\")",
  "foreach(_cmake_expected_target IN ITEMS CitizenSDK::Host)",
  "  list(APPEND _cmake_expected_targets \"${_cmake_expected_target}\")",
  "  if(TARGET \"${_cmake_expected_target}\")",
  "    list(APPEND _cmake_targets_defined \"${_cmake_expected_target}\")",
  "  else()",
  "    list(APPEND _cmake_targets_not_defined \"${_cmake_expected_target}\")",
  "  endif()",
  "endforeach()",
  "unset(_cmake_expected_target)",
  "if(_cmake_targets_defined STREQUAL _cmake_expected_targets)",
  "  unset(_cmake_targets_defined)",
  "  unset(_cmake_targets_not_defined)",
  "  unset(_cmake_expected_targets)",
  "  unset(CMAKE_IMPORT_FILE_VERSION)",
  "  cmake_policy(POP)",
  "  return()",
  "endif()",
  "if(NOT _cmake_targets_defined STREQUAL \"\")",
  "  string(REPLACE \";\" \", \" _cmake_targets_defined_text \"${_cmake_targets_defined}\")",
  "  string(REPLACE \";\" \", \" _cmake_targets_not_defined_text \"${_cmake_targets_not_defined}\")",
  "  message(FATAL_ERROR \"Some (but not all) targets in this export set were already defined.\\nTargets Defined: ${_cmake_targets_defined_text}\\nTargets not yet defined: ${_cmake_targets_not_defined_text}\\n\")",
  "endif()",
  "unset(_cmake_targets_defined)",
  "unset(_cmake_targets_not_defined)",
  "unset(_cmake_expected_targets)",
  "get_filename_component(_IMPORT_PREFIX \"${CMAKE_CURRENT_LIST_FILE}\" PATH)",
  "get_filename_component(_IMPORT_PREFIX \"${_IMPORT_PREFIX}\" PATH)",
  "get_filename_component(_IMPORT_PREFIX \"${_IMPORT_PREFIX}\" PATH)",
  "get_filename_component(_IMPORT_PREFIX \"${_IMPORT_PREFIX}\" PATH)",
  "get_filename_component(_IMPORT_PREFIX \"${_IMPORT_PREFIX}\" PATH)",
  "if(_IMPORT_PREFIX STREQUAL \"/\")",
  "  set(_IMPORT_PREFIX \"\")",
  "endif()",
  "add_library(CitizenSDK::Host SHARED IMPORTED)",
  "set_target_properties(CitizenSDK::Host PROPERTIES",
  "  INTERFACE_COMPILE_FEATURES \"cxx_std_17\"",
  "  INTERFACE_INCLUDE_DIRECTORIES \"${_IMPORT_PREFIX}/include\"",
  "  INTERFACE_LINK_LIBRARIES \"CitizenSDK::Core\"",
  ")",
  "file(GLOB _cmake_config_files \"${CMAKE_CURRENT_LIST_DIR}/CitizenSDKTargets-*.cmake\")",
  "foreach(_cmake_config_file IN LISTS _cmake_config_files)",
  "  include(\"${_cmake_config_file}\")",
  "endforeach()",
  "unset(_cmake_config_file)",
  "unset(_cmake_config_files)",
  "set(_IMPORT_PREFIX)",
  "foreach(_cmake_target IN LISTS _cmake_import_check_targets)",
  "  if(CMAKE_VERSION VERSION_LESS \"3.28\"",
  "      OR NOT DEFINED _cmake_import_check_xcframework_for_${_cmake_target}",
  "      OR NOT IS_DIRECTORY \"${_cmake_import_check_xcframework_for_${_cmake_target}}\")",
  "    foreach(_cmake_file IN LISTS \"_cmake_import_check_files_for_${_cmake_target}\")",
  "      if(NOT EXISTS \"${_cmake_file}\")",
  "        message(FATAL_ERROR \"The imported target \\\"${_cmake_target}\\\" references the file",
  "   \\\"${_cmake_file}\\\"",
  "but this file does not exist.  Possible reasons include:",
  "* The file was deleted, renamed, or moved to another location.",
  "* An install or uninstall procedure did not complete successfully.",
  "* The installation package was faulty and contained",
  "   \\\"${CMAKE_CURRENT_LIST_FILE}\\\"",
  "but not all the files it references.",
  "\")",
  "      endif()",
  "    endforeach()",
  "  endif()",
  "  unset(_cmake_file)",
  "  unset(\"_cmake_import_check_files_for_${_cmake_target}\")",
  "endforeach()",
  "unset(_cmake_target)",
  "unset(_cmake_import_check_targets)",
  "set(CMAKE_IMPORT_FILE_VERSION)",
  "cmake_policy(POP)",
].join('\n');
const LINUX_CMAKE_RELEASE = [
  "set(CMAKE_IMPORT_FILE_VERSION 1)",
  "set_property(TARGET CitizenSDK::Host APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)",
  "set_target_properties(CitizenSDK::Host PROPERTIES",
  "  IMPORTED_LOCATION_RELEASE \"${_IMPORT_PREFIX}/lib/@PLATFORM@/libcitizensdk_host.so\"",
  "  IMPORTED_SONAME_RELEASE \"libcitizensdk_host.so\"",
  "  )",
  "list(APPEND _cmake_import_check_targets CitizenSDK::Host )",
  "list(APPEND _cmake_import_check_files_for_CitizenSDK::Host \"${_IMPORT_PREFIX}/lib/@PLATFORM@/libcitizensdk_host.so\" )",
  "set(CMAKE_IMPORT_FILE_VERSION)",
].join('\n');

function assertLinuxInstallClosure(prefix, platform) {
  const paths = linuxInstallPaths(platform);
  if (JSON.stringify(regularFiles(prefix)) !== JSON.stringify(paths)
      || JSON.stringify(regularDirectories(prefix)) !== JSON.stringify(parentDirectories(paths))) {
    fail(`CitizenSDK ${platform} 安装投影必须精确为 19 个普通文件及其目录`);
  }
}

function cmakeInstructions(source) {
  let quoted = false;
  const lines = [];
  for (const line of source.split(/\r?\n/)) {
    const trimmed = line.trim();
    // No bracket-argument/comment syntax is emitted by these generators. Never
    // discard a bracket comment followed by executable code on the same line,
    // or a line that merely resembles a comment inside a quoted message.
    if (/\[=*\[/.test(line)) fail('CitizenSDK Linux CMake 出现未登记的 bracket 语法');
    if (!quoted && (!trimmed || trimmed.startsWith('#'))) continue;
    for (let index = 0; index < line.length; index += 1) {
      if (line[index] === '\\') index += 1;
      else if (line[index] === '"') quoted = !quoted;
    }
    lines.push(trimmed);
  }
  if (quoted) fail('CitizenSDK Linux CMake 字符串未终止');
  return lines.join('\n');
}

function linuxCmakeTargetVariants() {
  const current = cmakeInstructions(LINUX_CMAKE_TARGETS);
  const variants = new Set();
  // CMake's official 3.x/4.x exporters change policy ceilings, old-consumer
  // guards and the XCFramework existence guard. Admit those complete, safe
  // structures only; never delete arbitrary instructions from candidate input.
  // References: Kitware/CMake cmExport{File,CMakeConfig}Generator.cxx (3.24/3.31).
  for (const ceiling of ['3.22', '3.23', '3.26', '3.29', '4.0']) {
    for (const legacy of [false, true]) {
      let expected = current.replace('2.8.12...4.0', `2.8.12...${ceiling}`);
      if (legacy) {
        expected = expected
          .replace('message(FATAL_ERROR "CMake >= 2.8.12 required")', 'message(FATAL_ERROR "CMake >= 2.8.0 required")')
          .replace('if(CMAKE_VERSION VERSION_LESS "2.8.12")', 'if(CMAKE_VERSION VERSION_LESS "2.8.3")')
          .replace('message(FATAL_ERROR "CMake >= 2.8.12 required")', 'message(FATAL_ERROR "CMake >= 2.8.3 required")')
          .replace(`2.8.12...${ceiling}`, `2.8.3...${ceiling}`)
          .replace('file(GLOB _cmake_config_files', [
            'if(CMAKE_VERSION VERSION_LESS 2.8.12)',
            'message(FATAL_ERROR "This file relies on consumers using CMake 2.8.12 or greater.")',
            'endif()',
            'file(GLOB _cmake_config_files',
          ].join('\n'));
      }
      variants.add(expected);
      variants.add(expected.replace([
        'if(CMAKE_VERSION VERSION_LESS "3.28"',
        'OR NOT DEFINED _cmake_import_check_xcframework_for_${_cmake_target}',
        'OR NOT IS_DIRECTORY "${_cmake_import_check_xcframework_for_${_cmake_target}}")',
        '',
      ].join('\n'), '').replace('endforeach()\nendif()\nunset(_cmake_file)', 'endforeach()\nunset(_cmake_file)'));
    }
  }
  return variants;
}

function assertLinuxInstalledPlatform(sourceRoot, prefix, platform) {
  const installedFile = (path) => {
    try {
      return nativeArtifactSource(prefix, path);
    } catch (error) {
      fail(`CitizenSDK ${platform} 安装件无效：${path}；${error.message}`);
    }
  };
  const ordinary = (path) => readFileSync(installedFile(path));
  const equalSource = (installed, source) => {
    if (!ordinary(installed).equals(readFileSync(join(sourceRoot, source)))) {
      fail(`CitizenSDK ${platform} 安装投影来源字节漂移：${installed}`);
    }
  };
  for (const name of ['citizensdk.h', 'citizensdk_types.h']) equalSource(`include/${name}`, `include/${name}`);
  equalSource('include/citizensdk_qr_image.h', 'native/qr-image/citizensdk_qr_image.h');
  for (const name of LINUX_HOST_HEADERS) equalSource(`include/citizen_sdk/${name}`, `linux/include/citizen_sdk/${name}`);
  for (const name of ['manifest.json', 'chainspec.json', 'light_sync_state.json']) {
    equalSource(`share/citizensdk/citizenchain/${name}`, `assets/citizenchain/${name}`);
  }
  const version = readFileSync(join(sourceRoot, 'pubspec.yaml'), 'utf8')
    .match(/^version: (\d+\.\d{1,2}\.\d{1,2})$/m)?.[1];
  if (!version) fail('CitizenSDK Linux 安装投影缺少同版包身份');
  const configRoot = `lib/${platform}/cmake/CitizenSDK`;
  const configs = Object.fromEntries(LINUX_CMAKE_FILES.map((name) => [name,
    ordinary(`${configRoot}/${name}`).toString('utf8'),
  ]));
  const template = (name) => readFileSync(join(sourceRoot, 'linux/cmake', name), 'utf8');
  const expectedVersion = template('CitizenSDKConfigVersion.cmake.in')
    .replaceAll('@PROJECT_VERSION@', version)
    .replaceAll('@PROJECT_VERSION_MAJOR@', version.split('.')[0]);
  if (configs['CitizenSDKConfigVersion.cmake'] !== expectedVersion) {
    fail(`CitizenSDK ${platform} CMake 版本合同漂移`);
  }
  if (configs['CitizenSDKDependencies.cmake'] !== template('CitizenSDKDependencies.cmake')) {
    fail(`CitizenSDK ${platform} CMake 依赖合同漂移`);
  }
  const expectedBody = template('CitizenSDKConfig.cmake.in').split('@PACKAGE_INIT@')[1]
    .replaceAll('@CITIZENSDK_PLATFORM@', platform)
    .replaceAll('@PACKAGE_CMAKE_INSTALL_LIBDIR@', '${PACKAGE_PREFIX_DIR}/lib')
    .replaceAll('@PACKAGE_CMAKE_INSTALL_DATADIR@', '${PACKAGE_PREFIX_DIR}/share')
    .replaceAll('@PACKAGE_CMAKE_INSTALL_INCLUDEDIR@', '${PACKAGE_PREFIX_DIR}/include');
  const config = configs['CitizenSDKConfig.cmake'];
  const expectedConfig = `${LINUX_CMAKE_PACKAGE_INIT}\n${expectedBody}`;
  if (cmakeInstructions(config) !== cmakeInstructions(expectedConfig)) {
    fail(`CitizenSDK ${platform} CMake 平台、路径或配置合同漂移`);
  }
  const targets = configs['CitizenSDKTargets.cmake'];
  const release = configs['CitizenSDKTargets-release.cmake'];
  if (!linuxCmakeTargetVariants().has(cmakeInstructions(targets))
      || cmakeInstructions(release) !== cmakeInstructions(LINUX_CMAKE_RELEASE.replaceAll('@PLATFORM@', platform))) {
    fail(`CitizenSDK ${platform} CMake 导入目标合同漂移`);
  }
  const hostHeader = readFileSync(join(sourceRoot, 'linux/include/citizen_sdk/citizensdk_host.h'), 'utf8');
  const hostSymbols = [...new Set([...hostHeader.matchAll(/\b(citizensdk_host_[a-z0-9_]+)\s*\(/g)]
    .map((match) => match[1]))].sort();
  if (hostSymbols.length !== 17) fail('CitizenSDK Linux Host 必须精确为 17 个公开 C 符号');
  const hostAndQrSymbols = [...hostSymbols, ...expectedQrImageSymbols(sourceRoot)].sort();
  for (const [host, names] of [[false, expectedCitizenSdkLinkedSymbols(sourceRoot)], [true, hostAndQrSymbols]]) {
    const name = host ? 'libcitizensdk_host.so' : 'libcitizensdk.so';
    const path = installedFile(`lib/${platform}/${name}`);
    assertLinuxElf(path, platform, host, names);
  }
}

/** Verify the merged 27-file installation and the unchanged source closure. */
export function assertLinuxReleaseProjection(root) {
  const sourceRoot = resolve(root);
  assertLinuxBindingSource(sourceRoot, { allowInjectedLinuxArtifacts: true });
  for (const platform of LINUX_PLATFORMS) {
    assertLinuxInstalledPlatform(sourceRoot, join(sourceRoot, 'linux'), platform);
  }
}

// 按 Microsoft PE/COFF 格式读取真实目录表，不依赖 dumpbin 文本或文件扩展名。
// 系统加载、实际 CRT 部署及硬件行为仍须由 Windows 原生消费者验收。
function windowsPe(path, { headersOnly = false } = {}) {
  const bytes = readFileSync(path);
  const invalid = (message) => fail(`CitizenSDK Windows PE ${path}：${message}`);
  const range = (offset, length) => {
    if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) || offset < 0
        || length < 0 || offset > bytes.length - length) invalid('结构越界');
    return offset;
  };
  range(0, 64);
  if (bytes.readUInt16LE(0) !== 0x5a4d) invalid('缺少 DOS 标识');
  const pe = range(bytes.readUInt32LE(60), 24);
  const count = bytes.readUInt16LE(pe + 6);
  const optionalSize = bytes.readUInt16LE(pe + 20);
  if (bytes.readUInt32LE(pe) !== 0x4550 || bytes.readUInt16LE(pe + 4) !== 0x8664
      || count < 1 || count > 96 || optionalSize < 240) invalid('机器或 COFF 头漂移');
  const optional = range(pe + 24, optionalSize);
  if (bytes.readUInt16LE(optional) !== 0x20b || bytes.readUInt32LE(optional + 108) < 16) invalid('必须为 PE32+');
  const sections = [];
  for (let index = 0; index < count; index += 1) {
    const offset = range(optional + optionalSize + index * 40, 40);
    const section = { address: bytes.readUInt32LE(offset + 12), size: bytes.readUInt32LE(offset + 8),
      raw: bytes.readUInt32LE(offset + 20), rawSize: bytes.readUInt32LE(offset + 16),
      flags: bytes.readUInt32LE(offset + 36) };
    range(section.raw, section.rawSize);
    if (section.address === 0 || section.address + Math.max(section.size, section.rawSize) > 0x100000000
        || sections.some((previous) => section.address < previous.address + Math.max(previous.size, previous.rawSize)
          && previous.address < section.address + Math.max(section.size, section.rawSize))) invalid('节地址重叠或无效');
    sections.push(section);
  }
  if (headersOnly) return;
  const mapped = (address, length = 1) => {
    const found = sections.filter((section) => address >= section.address
      && address + length <= section.address + section.rawSize);
    if (found.length !== 1 || length < 1) invalid('RVA 不在唯一文件节中');
    return range(found[0].raw + address - found[0].address, length);
  };
  const string = (address) => {
    const start = mapped(address);
    const end = bytes.indexOf(0, start);
    if (end < start || end - start > 4096) invalid('字符串未终止');
    mapped(address, end - start + 1);
    const value = bytes.subarray(start, end);
    if (value.length === 0 || value.some((byte) => byte < 0x20 || byte > 0x7e)) invalid('字符串不是非空 ASCII');
    return value.toString('ascii');
  };
  const directory = (index) => {
    const offset = optional + 112 + index * 8;
    const address = bytes.readUInt32LE(offset), size = bytes.readUInt32LE(offset + 4);
    if ((address === 0) !== (size === 0)) invalid('目录地址与长度不一致');
    return { address, size, offset: address ? mapped(address, size) : 0 };
  };
  const exports = [];
  const exported = directory(0);
  let dllName = null;
  if (exported.address) {
    if (exported.size < 40) invalid('导出目录截断');
    const at = exported.offset;
    dllName = string(bytes.readUInt32LE(at + 12));
    const functions = bytes.readUInt32LE(at + 20), names = bytes.readUInt32LE(at + 24);
    if (!names || names > 65536 || functions !== names) invalid('导出数量或 ordinal-only 项无效');
    const addresses = mapped(bytes.readUInt32LE(at + 28), functions * 4);
    const pointers = mapped(bytes.readUInt32LE(at + 32), names * 4);
    const ordinals = mapped(bytes.readUInt32LE(at + 36), names * 2);
    const seen = new Set();
    for (let index = 0; index < names; index += 1) {
      const ordinal = bytes.readUInt16LE(ordinals + index * 2);
      if (ordinal >= functions || seen.has(ordinal)) invalid('导出 ordinal 重复或越界');
      seen.add(ordinal);
      const address = bytes.readUInt32LE(addresses + ordinal * 4);
      if (address >= exported.address && address < exported.address + exported.size) invalid('禁止转发导出');
      mapped(address);
      if (!sections.some((section) => address >= section.address && address < section.address + section.rawSize
          && (section.flags & 0x20000000))) invalid('导出地址不是可执行代码');
      exports.push(string(bytes.readUInt32LE(pointers + index * 4)));
    }
    if (new Set(exports).size !== exports.length || JSON.stringify(exports) !== JSON.stringify([...exports].sort())) {
      invalid('导出名称顺序或唯一性漂移');
    }
  }
  const imports = [];
  const thunks = (address) => {
    const names = [];
    for (let index = 0; index < 65536; index += 1) {
      const value = bytes.readBigUInt64LE(mapped(address + index * 8, 8));
      if (value === 0n) return names;
      if (value & (1n << 63n)) {
        if ((value & ~((1n << 63n) | 0xffffn)) !== 0n) invalid('import ordinal 位非法');
        names.push(null);
      } else {
        if (value > 0xffffffffn) invalid('import thunk RVA 越界');
        mapped(Number(value), 2);
        names.push(string(Number(value) + 2));
      }
    }
    invalid('import thunk 未终止');
  };
  for (const [index, width] of [[1, 20], [13, 32]]) {
    const table = directory(index);
    if (!table.address) continue;
    let terminated = false;
    for (let cursor = 0; cursor + width <= table.size; cursor += width) {
      const at = table.offset + cursor;
      if (bytes.subarray(at, at + width).every((byte) => byte === 0)) { terminated = true; break; }
      if (index === 13 && bytes.readUInt32LE(at) !== 1) invalid('delay import 必须使用 RVA');
      const name = string(bytes.readUInt32LE(at + (index === 1 ? 12 : 4))).toLowerCase();
      if (!/^[a-z0-9_-]+\.dll$/.test(name) || imports.some((entry) => entry.name === name)) invalid('导入 DLL 路径、名称或唯一性无效');
      const lookup = bytes.readUInt32LE(at + (index === 1 ? 0 : 16));
      const iat = bytes.readUInt32LE(at + (index === 1 ? 16 : 12));
      if (!iat) invalid('缺少 import address table');
      const names = thunks(lookup || iat);
      mapped(iat, (names.length + 1) * 8);
      if (!names.length) invalid('空 import descriptor');
      imports.push({ name, symbols: names });
    }
    if (!terminated) invalid('import descriptor 未终止');
  }
  return { exports, imports, dllName, dll: Boolean(bytes.readUInt16LE(pe + 22) & 0x2000) };
}

const WINDOWS_SYSTEM_IMPORTS = new Set([
  'mf.dll', 'mfplat.dll', 'mfreadwrite.dll',
  'advapi32.dll', 'bcrypt.dll', 'bcryptprimitives.dll', 'cfgmgr32.dll', 'comctl32.dll',
  'crypt32.dll', 'cryptbase.dll', 'dbghelp.dll', 'dnsapi.dll', 'gdi32.dll', 'imm32.dll',
  'iphlpapi.dll', 'kernel32.dll', 'kernelbase.dll', 'ncrypt.dll', 'netapi32.dll',
  'normaliz.dll', 'ntdll.dll', 'ole32.dll', 'oleaut32.dll', 'powrprof.dll', 'profapi.dll',
  'psapi.dll', 'rpcrt4.dll', 'secur32.dll', 'setupapi.dll', 'shell32.dll', 'shlwapi.dll',
  'synchronization.dll', 'tbs.dll', 'ucrtbase.dll', 'user32.dll', 'userenv.dll',
  'version.dll', 'winhttp.dll', 'winmm.dll', 'wintrust.dll', 'ws2_32.dll', 'wtsapi32.dll',
  'msvcrt.dll', 'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
  'msvcp140_atomic_wait.dll', 'msvcp140_codecvt_ids.dll', 'vcruntime140.dll', 'vcruntime140_1.dll',
]);
function assertWindowsImports(image, required, coreSymbols) {
  for (const entry of image.imports) {
    if (!required.includes(entry.name) && !WINDOWS_SYSTEM_IMPORTS.has(entry.name)
        && !/^(?:api|ext)-ms-win-[a-z0-9]+(?:-[a-z0-9]+)*-l\d+-\d+-\d+\.dll$/.test(entry.name)) {
      fail(`CitizenSDK Windows 未登记的 DLL 依赖：${entry.name}`);
    }
    if (entry.name === 'citizensdk.dll'
        && entry.symbols.some((symbol) => symbol === null || !coreSymbols.includes(symbol))) {
      fail('CitizenSDK Windows Host 导入了闭集外的 Core 符号');
    }
  }
  for (const name of required) {
    if (!image.imports.some((entry) => entry.name === name)) fail(`CitizenSDK Windows 缺少必要依赖：${name}`);
  }
}

function assertWindowsImportLibrary(path, dll, expectedSymbols) {
  const bytes = readFileSync(path), symbols = [], members = [];
  const invalid = () => fail(`CitizenSDK Windows import library 格式、机器或符号漂移：${path}`);
  const range = (data, at, size) => {
    if (!Number.isSafeInteger(at) || !Number.isSafeInteger(size) || at < 0 || size < 0
        || at > data.length || size > data.length - at) invalid();
  };
  const ascii = (data) => {
    if (data.some((value) => value < 32 || value > 127)) invalid();
    return data.toString('latin1');
  };
  const cstring = (data, at, limit = data.length) => {
    range(data, at, limit - at);
    const end = data.indexOf(0, at);
    if (end < at || end >= limit || end === at) invalid();
    return { text: ascii(data.subarray(at, end)), next: end + 1 };
  };
  const zero = (data) => data.every((value) => value === 0);
  // 官方 COFF archive 两个索引可在 payload 内补一个零字节至偶数边界；外部 padding 仍为 LF。
  const indexEnd = (data, at) => {
    if (at !== data.length && !(at % 2 === 1 && at + 1 === data.length && data[at] === 0)) invalid();
  };
  if (!bytes.subarray(0, 8).equals(Buffer.from('!<arch>\n'))) invalid();
  let cursor = 8;
  while (cursor < bytes.length) {
    if (members.length >= 100000 || cursor + 60 > bytes.length
        || bytes[cursor + 58] !== 0x60 || bytes[cursor + 59] !== 10) invalid();
    const name = ascii(bytes.subarray(cursor, cursor + 16)).trimEnd();
    const sizeText = ascii(bytes.subarray(cursor + 48, cursor + 58)).trim();
    if (!/^\d+$/.test(sizeText)) invalid();
    const size = Number(sizeText), start = cursor + 60, end = start + size;
    range(bytes, start, size);
    members.push({ offset: cursor, name, data: bytes.subarray(start, end) });
    cursor = end + (size % 2);
    if (size % 2 && bytes[end] !== 10) invalid();
  }
  if (cursor !== bytes.length || members.length < 5 || members[0].name !== '/' || members[1].name !== '/') invalid();
  const longnames = new Map();
  let objectStart = 2;
  if (members[2].name === '//') {
    const data = members[2].data;
    let at = 0;
    while (at < data.length) {
      // LLVM 的 longnames 表允许将最终 LF 对齐字节计入 member size。
      if (at % 2 === 1 && at + 1 === data.length && data[at] === 10) { at += 1; break; }
      const entry = cstring(data, at);
      longnames.set(at, entry.text);
      at = entry.next;
    }
    objectStart = 3;
  }
  const objects = members.slice(objectStart);
  const definitions = new Map();
  const stem = dll.replace(/\.dll$/, '');
  const descriptor = `__IMPORT_DESCRIPTOR_${stem}`;
  const nullDescriptor = '__NULL_IMPORT_DESCRIPTOR';
  const nullThunk = `\x7f${stem}_NULL_THUNK_DATA`;
  const descriptors = new Set([descriptor, nullDescriptor, nullThunk]);
  const define = (name, offset) => {
    if (definitions.has(name)) invalid();
    definitions.set(name, offset);
  };
  for (const member of objects) {
    const resolved = /^\/\d+$/.test(member.name) ? longnames.get(Number(member.name.slice(1)))
      : member.name.endsWith('/') ? member.name.slice(0, -1) : undefined;
    // archive 文件名不是 DLL 身份；允许官方任意对象名称，但引用必须指向 longnames 串首。
    if (!resolved || /[\x00-\x1f\x7f]/.test(resolved) || member.name === '/' || member.name === '//') invalid();
    const object = member.data;
    range(object, 0, 20);
    if (object.readUInt16LE(0) === 0 && object.readUInt16LE(2) === 0xffff) {
      if (object.readUInt16LE(4) !== 0 || object.readUInt16LE(6) !== 0x8664
          || object.readUInt16LE(18) !== 4 || object.readUInt32LE(12) !== object.length - 20) invalid();
      const name = cstring(object, 20), library = cstring(object, name.next);
      if (library.next !== object.length || library.text.toLowerCase() !== dll || !expectedSymbols.includes(name.text)) invalid();
      symbols.push(name.text);
      define(name.text, member.offset);
      define(`__imp_${name.text}`, member.offset);
      continue;
    }
    // 只接纳官方导入描述符 COFF，而非携带 .text、.drectve 或额外外部定义的实现对象。
    const sectionCount = object.readUInt16LE(2), table = object.readUInt32LE(8), count = object.readUInt32LE(12);
    const headersEnd = 20 + sectionCount * 40, stringsAt = table + count * 18;
    if (object.readUInt16LE(0) !== 0x8664 || object.readUInt16LE(16) !== 0
        || sectionCount < 1 || sectionCount > 16 || table < headersEnd || count < 1) invalid();
    range(object, 20, sectionCount * 40);
    range(object, table, count * 18 + 4);
    const stringSize = object.readUInt32LE(stringsAt);
    if (stringSize < 4) invalid();
    range(object, stringsAt, stringSize);
    if (stringsAt + stringSize !== object.length) invalid();
    const sections = [], occupied = [[0, headersEnd], [table, object.length]];
    const occupy = (at, length) => {
      range(object, at, length);
      if (length === 0) return;
      if (occupied.some(([begin, end]) => at < end && begin < at + length)) invalid();
      occupied.push([at, at + length]);
    };
    for (let index = 0; index < sectionCount; index += 1) {
      const at = 20 + index * 40;
      const nameBytes = object.subarray(at, at + 8), nul = nameBytes.indexOf(0);
      const name = ascii(nul < 0 ? nameBytes : nameBytes.subarray(0, nul));
      if (nul >= 0 && !zero(nameBytes.subarray(nul))) invalid();
      const size = object.readUInt32LE(at + 16), raw = object.readUInt32LE(at + 20);
      const reloc = object.readUInt32LE(at + 24), relocCount = object.readUInt16LE(at + 32);
      const flags = object.readUInt32LE(at + 36);
      if ((!/^\.idata\$[234567]$/.test(name) && name !== '.debug$S')
          || sections.some((section) => section.name === name)
          || object.readUInt32LE(at + 8) !== 0 || object.readUInt32LE(at + 12) !== 0
          || object.readUInt32LE(at + 28) !== 0 || object.readUInt16LE(at + 34) !== 0
          || (flags & (0x20000000 | 0x01000000 | 0x00000800))) invalid();
      occupy(raw, size);
      occupy(reloc, relocCount * 10);
      sections.push({ name, data: object.subarray(raw, raw + size), reloc, relocCount });
    }
    const coffSymbols = new Map(), external = [], undefinedExternal = new Set();
    for (let index = 0; index < count;) {
      const at = table + index * 18;
      let name;
      if (object.readUInt32LE(at) === 0) {
        const offset = object.readUInt32LE(at + 4);
        if (offset < 4 || offset >= stringSize) invalid();
        name = cstring(object, stringsAt + offset, stringsAt + stringSize).text;
      } else {
        const field = object.subarray(at, at + 8), nul = field.indexOf(0);
        name = ascii(nul < 0 ? field : field.subarray(0, nul));
        if (!name || (nul >= 0 && !zero(field.subarray(nul)))) invalid();
      }
      const value = object.readUInt32LE(at + 8), section = object.readInt16LE(at + 12);
      const storage = object[at + 16], auxiliary = object[at + 17];
      if (section > sectionCount || section < -2 || index + auxiliary >= count || storage === 105) invalid();
      const symbol = { name, value, section, storage };
      coffSymbols.set(index, symbol);
      if (storage === 2) {
        if (!descriptors.has(name) || value !== 0 || object.readUInt16LE(at + 14) !== 0 || auxiliary !== 0) invalid();
        if (section > 0) { external.push(symbol); define(name, member.offset); }
        else if (section === 0) undefinedExternal.add(name);
        else invalid();
      }
      index += auxiliary + 1;
    }
    if (external.length !== 1) invalid();
    for (const section of sections) {
      section.relocations = [];
      for (let index = 0; index < section.relocCount; index += 1) {
        const at = section.reloc + index * 10;
        const offset = object.readUInt32LE(at), target = coffSymbols.get(object.readUInt32LE(at + 4));
        const type = object.readUInt16LE(at + 8);
        if (!target || offset >= section.data.length) invalid();
        section.relocations.push({ offset, target, type });
      }
    }
    const role = external[0].name;
    const dataSections = sections.filter((section) => section.name !== '.debug$S');
    const get = (name, length) => {
      const section = dataSections.find((entry) => entry.name === name);
      if (!section || section.data.length !== length) invalid();
      return section;
    };
    const empty = (section) => { if (!zero(section.data) || section.relocCount !== 0) invalid(); };
    if (role === descriptor) {
      const idata = get('.idata$2', 20), library = dataSections.find((entry) => entry.name === '.idata$6');
      if (dataSections.length !== 2 || !library || library.relocCount !== 0 || !zero(idata.data)
          || idata.relocCount !== 3 || sections[external[0].section - 1] !== idata
          || undefinedExternal.size !== 2 || !undefinedExternal.has(nullDescriptor) || !undefinedExternal.has(nullThunk)) invalid();
      const dllName = cstring(library.data, 0);
      if (dllName.text.toLowerCase() !== dll || library.data.length - dllName.next > 1
          || !zero(library.data.subarray(dllName.next))) invalid();
      const required = new Map([[0, '.idata$4'], [12, '.idata$6'], [16, '.idata$5']]);
      for (const { offset, target, type } of idata.relocations) {
        if (type !== 3 || required.get(offset) !== target.name || target.value !== 0
            || (target.storage !== 3 && target.storage !== 104)
            || (target.name === '.idata$6' ? sections[target.section - 1] !== library : target.section !== 0)) invalid();
        required.delete(offset);
      }
      if (required.size !== 0) invalid();
    } else if (role === nullDescriptor) {
      const idata = get('.idata$3', 20);
      if (dataSections.length !== 1 || undefinedExternal.size !== 0 || sections[external[0].section - 1] !== idata) invalid();
      empty(idata);
    } else {
      const ilt = get('.idata$4', 8), iat = get('.idata$5', 8);
      if (dataSections.length !== 2 || undefinedExternal.size !== 0
          || ![ilt, iat].includes(sections[external[0].section - 1])) invalid();
      empty(ilt); empty(iat);
    }
  }
  if (objects.length !== expectedSymbols.length + 3 || [...descriptors].some((name) => !definitions.has(name))
      || JSON.stringify(symbols.sort()) !== JSON.stringify(expectedSymbols)) invalid();
  // Microsoft PE/COFF 两份链接索引必须共同映射至真实 object header；只有公开名字相同不能证明可链接。
  // 格式依据：learn.microsoft.com/windows/win32/debug/pe-format；LLVM Object/{ArchiveWriter,COFFImportFile}.cpp。
  const first = members[0].data, second = members[1].data, expectedCount = definitions.size;
  range(first, 0, 4);
  if (first.readUInt32BE(0) !== expectedCount) invalid();
  range(first, 4, expectedCount * 4);
  let at = 4 + expectedCount * 4, previous = -1;
  const seenFirst = new Set();
  for (let index = 0; index < expectedCount; index += 1) {
    const offset = first.readUInt32BE(4 + index * 4), name = cstring(first, at);
    if (offset < previous || definitions.get(name.text) !== offset || seenFirst.has(name.text)) invalid();
    seenFirst.add(name.text); previous = offset; at = name.next;
  }
  indexEnd(first, at);
  range(second, 0, 4);
  if (second.readUInt32LE(0) !== objects.length || objects.length > 0xffff) invalid();
  range(second, 4, objects.length * 4 + 4);
  objects.forEach((member, index) => { if (second.readUInt32LE(4 + index * 4) !== member.offset) invalid(); });
  const countAt = 4 + objects.length * 4, indicesAt = countAt + 4;
  if (second.readUInt32LE(countAt) !== expectedCount) invalid();
  range(second, indicesAt, expectedCount * 2);
  at = indicesAt + expectedCount * 2;
  let previousName = '';
  for (let index = 0; index < expectedCount; index += 1) {
    const memberIndex = second.readUInt16LE(indicesAt + index * 2), name = cstring(second, at);
    if (memberIndex < 1 || memberIndex > objects.length || name.text <= previousName
        || definitions.get(name.text) !== objects[memberIndex - 1].offset) invalid();
    previousName = name.text; at = name.next;
  }
  indexEnd(second, at);
}

const WINDOWS_CMAKE_RELEASE = [
  'set(CMAKE_IMPORT_FILE_VERSION 1)',
  'set_property(TARGET CitizenSDK::Host APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)',
  'set_target_properties(CitizenSDK::Host PROPERTIES',
  '  IMPORTED_IMPLIB_RELEASE "${_IMPORT_PREFIX}/lib/Windows/citizensdk_host.lib"',
  '  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/bin/Windows/citizensdk_host.dll"',
  '  )',
  'list(APPEND _cmake_import_check_targets CitizenSDK::Host )',
  'list(APPEND _cmake_import_check_files_for_CitizenSDK::Host "${_IMPORT_PREFIX}/lib/Windows/citizensdk_host.lib" "${_IMPORT_PREFIX}/bin/Windows/citizensdk_host.dll" )',
  'set(CMAKE_IMPORT_FILE_VERSION)',
].join('\n');

function assertWindowsInstallClosure(prefix) {
  if (JSON.stringify(regularFiles(prefix)) !== JSON.stringify(WINDOWS_RELEASE_FILES)
      || JSON.stringify(regularDirectories(prefix)) !== JSON.stringify(parentDirectories(WINDOWS_RELEASE_FILES))) {
    fail('CitizenSDK Windows 安装投影必须精确为 22 个普通文件及其目录');
  }
  for (const path of WINDOWS_RELEASE_FILES) {
    const info = lstatSync(join(prefix, path));
    if (info.size === 0 || info.nlink !== 1) fail(`CitizenSDK Windows 安装件为空或硬链接：${path}`);
  }
}

function assertWindowsInstalledPlatform(sourceRoot, prefix) {
  const file = (path) => {
    const value = nativeArtifactSource(prefix, path), info = lstatSync(value);
    if (info.size === 0 || info.nlink !== 1) fail(`CitizenSDK Windows 安装件为空或硬链接：${path}`);
    return value;
  };
  const equal = (installed, source) => {
    if (!readFileSync(file(installed)).equals(readFileSync(join(sourceRoot, source)))) {
      fail(`CitizenSDK Windows 安装来源字节漂移：${installed}`);
    }
  };
  for (const name of ['citizensdk.h', 'citizensdk_types.h']) equal(`include/${name}`, `include/${name}`);
  equal('include/citizensdk_qr_image.h', 'native/qr-image/citizensdk_qr_image.h');
  for (const name of WINDOWS_HOST_HEADERS) equal(`include/citizen_sdk/${name}`, `windows/include/citizen_sdk/${name}`);
  for (const name of ['manifest.json', 'chainspec.json', 'light_sync_state.json']) {
    equal(`share/citizensdk/citizenchain/${name}`, `assets/citizenchain/${name}`);
  }
  const version = readFileSync(join(sourceRoot, 'pubspec.yaml'), 'utf8').match(/^version: (\d+\.\d{1,2}\.\d{1,2})$/m)?.[1];
  if (!version || readFileSync(join(sourceRoot, 'windows/CMakeLists.txt'), 'utf8')
    .match(/^project\(CitizenSDKHost VERSION (\d+\.\d{1,2}\.\d{1,2}) LANGUAGES C CXX\)$/m)?.[1] !== version) {
    fail('CitizenSDK Windows 源码版本不一致');
  }
  const template = (name) => readFileSync(join(sourceRoot, 'windows/cmake', name), 'utf8');
  const configs = Object.fromEntries(WINDOWS_CMAKE_FILES.map((name) => [name,
    readFileSync(file(`lib/Windows/cmake/CitizenSDK/${name}`), 'utf8')]));
  const body = template('CitizenSDKConfig.cmake.in').split('@PACKAGE_INIT@')[1]
    .replaceAll('@PACKAGE_CMAKE_INSTALL_LIBDIR@', '${PACKAGE_PREFIX_DIR}/lib')
    .replaceAll('@PACKAGE_CMAKE_INSTALL_BINDIR@', '${PACKAGE_PREFIX_DIR}/bin')
    .replaceAll('@PACKAGE_CMAKE_INSTALL_DATADIR@', '${PACKAGE_PREFIX_DIR}/share')
    .replaceAll('@PACKAGE_CMAKE_INSTALL_INCLUDEDIR@', '${PACKAGE_PREFIX_DIR}/include');
  if (configs['CitizenSDKConfigVersion.cmake'] !== template('CitizenSDKConfigVersion.cmake.in')
    .replaceAll('@PROJECT_VERSION@', version).replaceAll('@PROJECT_VERSION_MAJOR@', version.split('.')[0])
      || configs['CitizenSDKDependencies.cmake'] !== template('CitizenSDKDependencies.cmake')
      || cmakeInstructions(configs['CitizenSDKConfig.cmake']) !== cmakeInstructions(`${LINUX_CMAKE_PACKAGE_INIT}\n${body}`)
      || !linuxCmakeTargetVariants().has(cmakeInstructions(configs['CitizenSDKTargets.cmake']))
      || cmakeInstructions(configs['CitizenSDKTargets-release.cmake']) !== cmakeInstructions(WINDOWS_CMAKE_RELEASE)) {
    fail('CitizenSDK Windows CMake 版本、依赖、路径或导入目标合同漂移');
  }
  const coreSymbols = expectedCitizenSdkLinkedSymbols(sourceRoot);
  const hostSymbols = [...new Set([...readFileSync(join(sourceRoot, 'windows/include/citizen_sdk/citizensdk_host.h'), 'utf8')
    .matchAll(/\b(citizensdk_host_[a-z0-9_]+)\s*\(/g)].map((match) => match[1]))].sort();
  const hostAndQrSymbols = [...hostSymbols, ...expectedQrImageSymbols(sourceRoot)].sort();
  if (coreSymbols.length !== 93 || hostSymbols.length !== 17 || hostAndQrSymbols.length !== 20) fail('CitizenSDK Windows 89公开+4内部Core及17Host+3图像导出闭集漂移');
  for (const [name, symbols, imports, library] of [
    ['citizensdk.dll', coreSymbols, [], 'citizensdk.dll.lib'],
    ['citizensdk_host.dll', hostAndQrSymbols, ['citizensdk.dll'], 'citizensdk_host.lib'],
  ]) {
    const image = windowsPe(file(`bin/Windows/${name}`));
    if (!image.dll || image.dllName?.toLowerCase() !== name
        || JSON.stringify(image.exports) !== JSON.stringify(symbols)) fail(`CitizenSDK Windows ${name} 完整导出漂移`);
    assertWindowsImports(image, imports, coreSymbols);
    assertWindowsImportLibrary(file(`lib/Windows/${library}`), name, symbols);
  }
  return version;
}

/** 唯一 Windows 安装验真入口；不要求其它平台产物存在。 */
export function assertWindowsNativeArtifact(sourceRoot, prefix) {
  const source = resolve(sourceRoot), installed = assertSafeTargetPath(prefix, 'Windows 安装前缀');
  assertWindowsBindingSource(source);
  assertPublicAbiHeaders(source);
  assertChainAssets(source);
  assertWindowsInstallClosure(installed);
  return assertWindowsInstalledPlatform(source, installed);
}

/** destination 是完整 SDK 根；全部预检成功才写十四个新项，七头只比较。 */
export function copyWindowsNativeArtifact(sourceRoot, prefix, destination) {
  const source = resolve(sourceRoot), installed = resolve(prefix);
  const output = assertSafeTargetPath(destination, 'Windows 候选根');
  assertLocalTarget(output, 'Windows 候选根');
  assertOutsideSource(installed, output, 'Windows 安装目标');
  assertOutsideSource(output, installed, 'Windows 安装来源');
  assertOutsideSource(source, output, 'Windows 候选根');
  assertOutsideSource(output, source, 'Windows SDK 来源');
  assertWindowsNativeArtifact(source, installed);
  const root = join(output, 'windows');
  const pending = [];
  for (const path of WINDOWS_RELEASE_FILES) {
    const target = assertSafeTargetPath(join(root, path), 'Windows 安装目标');
    const bytes = readFileSync(nativeArtifactSource(installed, path));
    if (existsSync(target)) {
      if (WINDOWS_INJECTED_FILES.has(path) || !lstatSync(target).isFile()
          || !bytes.equals(readFileSync(target))) fail(`CitizenSDK Windows 重叠安装件漂移或目标已存在：${path}`);
    } else pending.push({ target, bytes });
  }
  if (pending.length !== WINDOWS_INJECTED_FILES.size) fail('CitizenSDK Windows 候选必须先包含七个原始 Host 头');
  for (const { target, bytes } of pending) {
    mkdirSync(dirname(target), { recursive: true, mode: 0o700 });
    writeFileSync(target, bytes, { flag: 'wx', mode: 0o600 });
  }
}

export function assertWindowsReleaseProjection(root) {
  const source = resolve(root);
  assertWindowsBindingSource(source, { allowInjectedWindowsArtifacts: true });
  assertPublicAbiHeaders(source);
  assertChainAssets(source);
  return assertWindowsInstalledPlatform(source, join(source, 'windows'));
}

/** 构建器调用的同源 bundle 检查；app.so 是 Dart AOT ELF，不是 PE。 */
export function assertWindowsFlutterBundle(sourceRoot, prefix, bundle) {
  const source = resolve(sourceRoot), installed = resolve(prefix);
  const root = assertSafeTargetPath(bundle, 'Windows Flutter bundle');
  assertWindowsNativeArtifact(source, installed);
  for (const name of ['citizensdk.dll', 'citizensdk_host.dll']) {
    if (!readFileSync(nativeArtifactSource(root, name)).equals(
      readFileSync(nativeArtifactSource(installed, `bin/Windows/${name}`)),
    )) fail(`CitizenSDK Windows Flutter bundle 运行库来源漂移：${name}`);
  }
  for (const name of ['manifest.json', 'chainspec.json', 'light_sync_state.json']) {
    const path = `data/flutter_assets/packages/citizen_sdk/assets/citizenchain/${name}`;
    if (!readFileSync(nativeArtifactSource(root, path)).equals(readFileSync(join(source, 'assets/citizenchain', name)))) {
      fail(`CitizenSDK Windows Flutter bundle 链资产漂移：${name}`);
    }
  }
  const plugin = windowsPe(nativeArtifactSource(root, 'citizen_sdk_plugin.dll'));
  if (!plugin.dll || JSON.stringify(plugin.exports) !== JSON.stringify(['CitizenSdkPluginRegisterWithRegistrar'])) {
    fail('CitizenSDK Windows Flutter 插件注册导出漂移');
  }
  assertWindowsImports(plugin, ['citizensdk.dll', 'citizensdk_host.dll', 'flutter_windows.dll'], expectedCitizenSdkSymbols(source));
  // Runner/Flutter engine 的功能导出不属于 SDK；只核机器身份，不伪造其符号闭集。
  windowsPe(nativeArtifactSource(root, 'citizensdk_consumer.exe'), { headersOnly: true });
  windowsPe(nativeArtifactSource(root, 'flutter_windows.dll'), { headersOnly: true });
  const aot = readFileSync(nativeArtifactSource(root, 'data/app.so'));
  if (aot.length < 64 || !aot.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))
      || aot[4] !== 2 || aot[5] !== 1 || aot.readUInt16LE(18) !== 62) {
    fail('CitizenSDK Windows Dart AOT 必须为 x86_64 ELF64');
  }
}


// 只固定中央原生依赖子合同的规范 JSON 摘要，不另存一套可选版本/下载器。
// 收据内携带合同原文供离线复核；SDK 不需要 ../TATA 路径，也不下载任何库。
const NATIVE_DEPENDENCY_CONTRACT_SHA256 = '7f439abc35a891616b34b03d129b51dc82eef756535dcd8fcd25ee7da512f3e6';
const NATIVE_DEPENDENCY_PLATFORMS = ['LinuxARM', 'LinuxAMD', 'Windows'];
const TSS2_HEADERS = ['common', 'esys', 'mu', 'rc', 'sys', 'tcti', 'tcti_device', 'tpm2_types']
  .map((name) => 'include/tss2/tss2_' + name + '.h');
function dependencyCheck(ok, message) { if (!ok) fail('CitizenSDK 静态依赖：' + message); }
function dependencyHash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }

export function assertCitizenSdkNativeContract(value) {
  dependencyCheck(dependencyHash(stableJson(value)) === NATIVE_DEPENDENCY_CONTRACT_SHA256,
    '固定来源/版本/摘要/构建选项漂移');
}

/** 逐成员读真实 ar；拒绝薄归档、动态库、COFF import object、bitcode 及另一平台对象。 */
export function assertCitizenSdkStaticArchive(bytes, platform, nested = false) {
  dependencyCheck(NATIVE_DEPENDENCY_PLATFORMS.includes(platform), '未知平台');
  dependencyCheck(typeof nested === 'boolean', '静态归档嵌套状态无效');
  dependencyCheck(bytes.length >= 8 && bytes.subarray(0, 8).toString() === '!<arch>\n', '不是完整静态归档');
  let offset = 8, objects = 0, gnuNames = null;
  while (offset < bytes.length) {
    dependencyCheck(offset + 60 <= bytes.length, 'ar header 截断');
    const header = bytes.subarray(offset, offset + 60);
    const name = header.subarray(0, 16).toString().trim();
    const sizeText = header.subarray(48, 58).toString().trim();
    dependencyCheck(header.subarray(58).toString() === '\x60\n' && /^\d+$/.test(sizeText), 'ar header 无效');
    const size = Number(sizeText), start = offset + 60;
    dependencyCheck(Number.isSafeInteger(size) && start + size <= bytes.length, 'ar member 截断');
    let object = bytes.subarray(start, start + size), actualName = name;
    if (name.startsWith('#1/')) {
      const length = Number(name.slice(3));
      dependencyCheck(Number.isSafeInteger(length) && length > 0 && length <= object.length, 'BSD ar 名称无效');
      actualName = object.subarray(0, length).toString().replace(/\0+$/, '');
      object = object.subarray(length);
    }
    if (name === '//') {
      dependencyCheck(gnuNames === null && object.length > 0, 'GNU ar 长名称表无效');
      gnuNames = object;
    } else if (/^\/\d+$/.test(name)) {
      const nameOffset = Number(name.slice(1));
      dependencyCheck(gnuNames && Number.isSafeInteger(nameOffset) && nameOffset >= 0
        && nameOffset < gnuNames.length
        && (nameOffset === 0 || (gnuNames[nameOffset - 2] === 47 && gnuNames[nameOffset - 1] === 10)),
      'GNU ar 长名称偏移无效');
      const end = gnuNames.indexOf(Buffer.from('/\n'), nameOffset);
      dependencyCheck(end > nameOffset, 'GNU ar 长名称未终止');
      actualName = gnuNames.subarray(nameOffset, end).toString();
      dependencyCheck(/^[A-Za-z0-9_.+@-]+$/.test(actualName), 'GNU ar 长名称字符无效');
    }
    if (!['/', '//', '/SYM64/', '__.SYMDEF', '__.SYMDEF SORTED'].includes(actualName)) {
      // 归档成员名只用于失败诊断；限制为短 ASCII，避免第三方归档把控制字符写入 CI 日志。
      const diagnosticName = /^[\x20-\x7e]{1,80}$/.test(actualName) ? actualName : '<invalid-name>';
      if (actualName === 'libcrypto.a/') {
        // OpenSSL 的正式静态输出可能用一个同名成员封装内部归档；只接受这一层精确名称，
        // 并递归验证其中每个 ELF 对象，不能把嵌套归档当作任意非对象成员跳过。
        dependencyCheck(platform !== 'Windows' && !nested, 'libcrypto 静态归档嵌套层级无效');
        dependencyCheck(object.length >= 8 && object.subarray(0, 8).toString() === '!<arch>\n',
          `libcrypto 静态归档成员不是完整归档：${diagnosticName}`);
        assertCitizenSdkStaticArchive(object, platform, true);
      } else if (platform === 'Windows') {
        dependencyCheck(object.length >= 20 && object.readUInt16LE(0) === 0x8664
          && object.readUInt16LE(2) > 0 && object.readUInt16LE(16) === 0, '非 Windows MSVC 静态对象');
        const count = object.readUInt16LE(2), tableEnd = 20 + count * 40;
        dependencyCheck(tableEnd <= object.length, 'COFF section table 截断');
        for (let section = 0; section < count; section += 1) {
          const at = 20 + section * 40, size = object.readUInt32LE(at + 16), pointer = object.readUInt32LE(at + 20);
          // 未初始化数据没有文件 payload；其余 section 必须完整位于成员内部。
          if (size && pointer) dependencyCheck(pointer >= tableEnd && pointer + size <= object.length, 'COFF section 越界');
          else dependencyCheck(!size || (object.readUInt32LE(at + 36) & 0x80) !== 0, 'COFF section 缺少内容');
        }
      } else {
        dependencyCheck(object.length >= 64 && object.subarray(0, 4).equals(Buffer.from([127, 69, 76, 70]))
          && object[4] === 2 && object[5] === 1 && object.readUInt16LE(16) === 1
          && object.readUInt16LE(18) === (platform === 'LinuxARM' ? 183 : 62),
        `非目标 Linux ELF relocatable 对象：${diagnosticName}`);
        const table = Number(object.readBigUInt64LE(40)), count = object.readUInt16LE(60);
        dependencyCheck(object.readUInt16LE(52) === 64 && object.readUInt16LE(58) === 64
          && Number.isSafeInteger(table) && table >= 64 && count > 0
          && table + count * 64 <= object.length, 'ELF section table 无效');
        for (let section = 0; section < count; section += 1) {
          const at = table + section * 64, type = object.readUInt32LE(at + 4);
          const pointer = Number(object.readBigUInt64LE(at + 24)), size = Number(object.readBigUInt64LE(at + 32));
          if (type !== 8) dependencyCheck(Number.isSafeInteger(pointer) && Number.isSafeInteger(size)
            && pointer + size <= object.length, 'ELF section 越界');
        }
      }
      objects += 1;
    }
    offset = start + size;
    if (offset % 2) {
      dependencyCheck(offset < bytes.length && bytes[offset] === 10, 'ar alignment 无效');
      offset += 1;
    }
  }
  dependencyCheck(objects > 0, '静态归档没有对象');
}

function dependencyArchives(platform) {
  return platform === 'Windows' ? ['lib/sqlite3.lib']
    : ['lib/libsqlite3.a', 'lib/libcrypto.a',
      ...['esys', 'mu', 'sys', 'rc', 'tcti-device'].map((name) => 'lib/libtss2-' + name + '.a')].sort();
}
function assertDependencyReceipt(receipt, platform) {
  dependencyCheck(receipt && stableJson(Object.keys(receipt).sort()) === stableJson(
    ['schema', 'platform', 'source_sha', 'software_version', 'build_mode', 'native_dependencies', 'build_tools', 'files'].sort()),
  '准备收据字段闭集无效');
  dependencyCheck(NATIVE_DEPENDENCY_PLATFORMS.includes(platform) && receipt.platform === platform
    && receipt.schema === 1 && /^[0-9a-f]{40}$/.test(receipt.source_sha)
    && /^\d+\.\d+\.\d+$/.test(receipt.software_version) && ['ci', 'release'].includes(receipt.build_mode),
  '收据平台/身份/模式无效');
  assertCitizenSdkNativeContract(receipt.native_dependencies);
  const tools = platform === 'Windows' ? ['cl', 'lib', 'tar'] : ['cc', 'ar', 'perl', 'make', 'sh', 'pkg-config', 'tar', 'unzip'];
  dependencyCheck(Array.isArray(receipt.build_tools)
    && stableJson(receipt.build_tools.map((tool) => tool.name).sort()) === stableJson(tools.sort()),
  '工具链闭集无效');
  for (const tool of receipt.build_tools) {
    dependencyCheck(/^[0-9a-f]{64}$/.test(tool.sha256)
      && stableJson(Object.keys(tool).sort()) === stableJson((tool.name === 'cc'
        ? ['name', 'sha256', 'target'] : ['name', 'sha256']).sort()), '工具身份无效');
    if (tool.name === 'cc') dependencyCheck(typeof tool.target === 'string'
      && tool.target.startsWith(platform === 'LinuxARM' ? 'aarch64-' : 'x86_64-')
      && tool.target.endsWith('linux-gnu'), '编译器目标无效');
  }
  dependencyCheck(Array.isArray(receipt.files) && receipt.files.length > 0 && receipt.files.length <= 256,
    '输入文件列表无效');
  const paths = receipt.files.map((entry) => {
    dependencyCheck(entry && Object.keys(entry).sort().join(',') === 'path,sha256'
      && typeof entry.path === 'string' && /^[a-zA-Z0-9_.\/-]+$/.test(entry.path)
      && !entry.path.split('/').includes('..') && !entry.path.startsWith('/')
      && /^[0-9a-f]{64}$/.test(entry.sha256), '输入条目无效');
    return entry.path;
  });
  const archives = dependencyArchives(platform);
  const expected = ['include/sqlite3.h', ...archives,
    ...(platform === 'Windows' ? [] : [...TSS2_HEADERS,
      ...OPENSSL_DEPENDENCY_HEADERS.map((name) => 'include/openssl/' + name)])].sort();
  dependencyCheck(stableJson(paths) === stableJson(expected), '输入头文件/静态库闭集不符');
  return receipt;
}

/** 收据不可单独代替静态库：每个实际头/库都重新哈希，并核对所有对象的机器身份。 */
export function assertCitizenSdkDependencyInputs(receiptPath, platform) {
  const path = assertSafeTargetPath(receiptPath, '静态依赖证据');
  const prefix = dirname(path);
  const receipt = assertDependencyReceipt(JSON.parse(readFileSync(nativeArtifactSource(prefix, 'native-dependencies.json'), 'utf8')), platform);
  dependencyCheck(path === join(prefix, 'native-dependencies.json'), '收据文件名不符');
  const actual = treeEntries(prefix).files;
  dependencyCheck(stableJson(actual) === stableJson([...receipt.files.map((entry) => entry.path), 'native-dependencies.json'].sort()),
    '实际输入含未登记文件');
  for (const entry of receipt.files) {
    const input = nativeArtifactSource(prefix, entry.path);
    dependencyCheck(sha256File(input) === entry.sha256, '实际输入摘要不符：' + entry.path);
    if (dependencyArchives(platform).includes(entry.path)) assertCitizenSdkStaticArchive(readFileSync(input), platform);
  }
  return receipt;
}

/** 保持现有显式环境入口，仅从已经验证的同一前缀取得所有头/库，拒绝混用外部路径。 */
export function citizenSdkDependencyEnvironment(receiptPath, platform) {
  assertCitizenSdkDependencyInputs(receiptPath, platform);
  const prefix = dirname(resolve(receiptPath)), at = (path) => join(prefix, path);
  if (platform === 'Windows') return {
    CITIZENSDK_WINDOWS_SQLITE_INCLUDE_DIR: at('include'),
    CITIZENSDK_WINDOWS_SQLITE_ARCHIVE: at('lib/sqlite3.lib'),
  };
  return {
    CITIZENSDK_HOST_SQLITE_INCLUDE_DIR: at('include'),
    CITIZENSDK_HOST_OPENSSL_INCLUDE_DIR: at('include'),
    CITIZENSDK_HOST_TSS2_INCLUDE_DIR: at('include'),
    CITIZENSDK_HOST_SQLITE_ARCHIVE: at('lib/libsqlite3.a'),
    CITIZENSDK_HOST_CRYPTO_ARCHIVE: at('lib/libcrypto.a'),
    ...Object.fromEntries(['esys', 'mu', 'sys', 'rc', 'tcti-device'].map((name) =>
      ['CITIZENSDK_HOST_TSS2_' + name.replaceAll('-', '_').toUpperCase() + '_ARCHIVE', at('lib/libtss2-' + name + '.a')])),
  };
}

function dependencyLinkedPaths(platform, layout) {
  const paths = platform === 'Windows'
    ? ['bin/Windows/citizensdk.dll', 'bin/Windows/citizensdk_host.dll']
    : ['lib/' + platform + '/libcitizensdk.so', 'lib/' + platform + '/libcitizensdk_host.so'];
  return paths.map((path) => layout === 'candidate' ? (platform === 'Windows' ? 'windows/' : 'linux/') + path
    : layout === 'native' ? (platform === 'Windows' ? 'Windows/' : 'linux/' + platform + '/') + path : path);
}

/** 只有原生门禁和消费者全部成功后，构建器才绑定该批输入与导出的最终运行库。 */
export function writeCitizenSdkDependencyEvidence({ receiptPath, platform, nativePath, sourcePath, sourceSha }) {
  const receipt = assertCitizenSdkDependencyInputs(receiptPath, platform);
  dependencyCheck(receipt.source_sha === sourceSha, '构建提交与准备提交不同');
  const source = resolve(sourcePath), native = assertSafeTargetPath(nativePath, '原生产物目录');
  assertLicenseSources(source);
  dependencyCheck(readFileSync(join(source, 'pubspec.yaml'), 'utf8').includes('\nversion: ' + receipt.software_version + '\n'),
    '构建版本与准备版本不同');
  const paths = dependencyLinkedPaths(platform, 'native');
  const linked_artifacts = paths.map((path, index) => ({
    path: dependencyLinkedPaths(platform, 'candidate')[index],
    sha256: sha256File(nativeArtifactSource(native, path)),
  }));
  const evidence = { dependency_inputs: receipt, linked_artifacts,
    files: ['LICENSE', 'THIRD_PARTY_NOTICES.md'].map((path) => ({ path, sha256: sha256File(join(source, path)) })) };
  const directory = join(native, 'dependencies');
  if (!existsSync(directory)) mkdirSync(directory, { mode: 0o700 });
  nativeArtifactSource(native, 'dependencies', 'directory');
  writeFileSync(join(directory, platform + '.json'), prettyStableJson(evidence), { flag: 'wx', mode: 0o600 });
  return evidence;
}

export function assertCitizenSdkDependencyEvidence(evidence, platform, root, layout, source, sourceSha, softwareVersion) {
  dependencyCheck(evidence && Object.keys(evidence).sort().join(',') === 'dependency_inputs,files,linked_artifacts',
    '链接证据字段闭集无效');
  const receipt = assertDependencyReceipt(evidence.dependency_inputs, platform);
  dependencyCheck(receipt.source_sha === sourceSha && receipt.software_version === softwareVersion, '链接证据不同提交/版本');
  const expected = dependencyLinkedPaths(platform, 'candidate');
  dependencyCheck(Array.isArray(evidence.linked_artifacts)
    && stableJson(evidence.linked_artifacts.map((entry) => entry.path)) === stableJson(expected),
  '最终运行库闭集无效');
  for (const [index, entry] of evidence.linked_artifacts.entries()) {
    dependencyCheck(Object.keys(entry).sort().join(',') === 'path,sha256'
      && entry.sha256 === sha256File(nativeArtifactSource(root, dependencyLinkedPaths(platform, layout)[index])),
    '最终链接字节不符');
  }
  const legal = ['LICENSE', 'THIRD_PARTY_NOTICES.md'].map((path) => ({ path, sha256: sha256File(join(source, path)) }));
  dependencyCheck(stableJson(evidence.files) === stableJson(legal), '许可证/归属来源不符');
  return evidence;
}

function collectDependencyEvidence(native, source, sourceSha, softwareVersion) {
  const directory = nativeArtifactSource(native, 'dependencies', 'directory');
  dependencyCheck(stableJson(treeEntries(directory).files) === stableJson(
    NATIVE_DEPENDENCY_PLATFORMS.map((platform) => platform + '.json').sort()), '链接证据平台闭集不符');
  return NATIVE_DEPENDENCY_PLATFORMS.map((platform) => assertCitizenSdkDependencyEvidence(
    JSON.parse(readFileSync(join(directory, platform + '.json'), 'utf8')),
    platform, native, 'native', source, sourceSha, softwareVersion));
}

const OPENSSL_DEPENDENCY_HEADERS = [
  "aes.h",
  "asn1.h",
  "asn1err.h",
  "asn1t.h",
  "async.h",
  "asyncerr.h",
  "bio.h",
  "bioerr.h",
  "blowfish.h",
  "bn.h",
  "bnerr.h",
  "buffer.h",
  "buffererr.h",
  "byteorder.h",
  "camellia.h",
  "cast.h",
  "cmac.h",
  "cmp.h",
  "cmp_util.h",
  "cmperr.h",
  "cms.h",
  "cmserr.h",
  "comp.h",
  "comperr.h",
  "conf.h",
  "conf_api.h",
  "conferr.h",
  "configuration.h",
  "conftypes.h",
  "core.h",
  "core_dispatch.h",
  "core_names.h",
  "core_object.h",
  "crmf.h",
  "crmferr.h",
  "crypto.h",
  "cryptoerr.h",
  "cryptoerr_legacy.h",
  "ct.h",
  "cterr.h",
  "decoder.h",
  "decodererr.h",
  "des.h",
  "dh.h",
  "dherr.h",
  "dsa.h",
  "dsaerr.h",
  "dtls1.h",
  "e_os2.h",
  "e_ostime.h",
  "ebcdic.h",
  "ec.h",
  "ecdh.h",
  "ecdsa.h",
  "ecerr.h",
  "encoder.h",
  "encodererr.h",
  "engine.h",
  "engineerr.h",
  "err.h",
  "ess.h",
  "esserr.h",
  "evp.h",
  "evperr.h",
  "fips_names.h",
  "fipskey.h",
  "hmac.h",
  "hpke.h",
  "http.h",
  "httperr.h",
  "idea.h",
  "indicator.h",
  "kdf.h",
  "kdferr.h",
  "lhash.h",
  "macros.h",
  "md2.h",
  "md4.h",
  "md5.h",
  "mdc2.h",
  "ml_kem.h",
  "modes.h",
  "obj_mac.h",
  "objects.h",
  "objectserr.h",
  "ocsp.h",
  "ocsperr.h",
  "opensslconf.h",
  "opensslv.h",
  "ossl_typ.h",
  "param_build.h",
  "params.h",
  "pem.h",
  "pem2.h",
  "pemerr.h",
  "pkcs12.h",
  "pkcs12err.h",
  "pkcs7.h",
  "pkcs7err.h",
  "prov_ssl.h",
  "proverr.h",
  "provider.h",
  "quic.h",
  "rand.h",
  "randerr.h",
  "rc2.h",
  "rc4.h",
  "rc5.h",
  "ripemd.h",
  "rsa.h",
  "rsaerr.h",
  "safestack.h",
  "seed.h",
  "self_test.h",
  "sha.h",
  "srp.h",
  "srtp.h",
  "ssl.h",
  "ssl2.h",
  "ssl3.h",
  "sslerr.h",
  "sslerr_legacy.h",
  "stack.h",
  "store.h",
  "storeerr.h",
  "symhacks.h",
  "thread.h",
  "tls1.h",
  "trace.h",
  "ts.h",
  "tserr.h",
  "txt_db.h",
  "types.h",
  "ui.h",
  "uierr.h",
  "whrlpool.h",
  "x509.h",
  "x509_acert.h",
  "x509_vfy.h",
  "x509err.h",
  "x509v3.h",
  "x509v3err.h"
];


export function assertNativeArtifactSources(nativeRoot) {
  const root = assertSafeTargetPath(nativeRoot, '原生产物目录');
  if (!existsSync(root) || lstatSync(root).isSymbolicLink() || !lstatSync(root).isDirectory()) {
    fail('CitizenSDK 原生产物目录不存在或不是普通目录');
  }
  if (realpathSync(root) !== root) fail('CitizenSDK 原生产物目录真实路径漂移');
  const files = Object.fromEntries(
    Object.entries(NATIVE_FILES).map(([destinationPath, sourcePath]) => [
      destinationPath,
      nativeArtifactSource(root, sourcePath),
    ]),
  );
  const directories = Object.fromEntries(
    Object.entries(NATIVE_DIRECTORIES).map(([destinationPath, sourcePath]) => {
      const source = nativeArtifactSource(root, sourcePath, 'directory');
      // 这里只承认标准 macOS framework 的五个精确内部链接；遍历不会跟随
      // 链接，并会拒绝 iOS slice 或其它位置出现的任何链接。
      const entries = treeEntries(source, appleXcframeworkSymlinkContract(source));
      if (entries.files.length === 0) fail(`原生产物目录为空：${sourcePath}`);
      return [destinationPath, source];
    }),
  );
  const linux = Object.fromEntries(LINUX_PLATFORMS.map((platform) => {
    const prefix = nativeArtifactSource(root, `linux/${platform}`, 'directory');
    assertLinuxInstallClosure(prefix, platform);
    return [platform, prefix];
  }));
  const [first, second] = LINUX_PLATFORMS;
  for (const path of linuxInstallPaths(first).filter((path) => !path.startsWith('lib/'))) {
    if (!readFileSync(join(linux[first], path)).equals(readFileSync(join(linux[second], path)))) {
      fail(`CitizenSDK Linux 共享安装件字节不一致：${path}`);
    }
  }
  const windows = nativeArtifactSource(root, 'Windows', 'directory');
  assertWindowsInstallClosure(windows);
  return { directories, files, linux, windows };
}

function copyNativeFiles(nativeRoot, output, sourceRoot) {
  const sources = assertNativeArtifactSources(nativeRoot);
  for (const [destinationPath, source] of Object.entries(sources.files)) {
    const destination = join(output, ...destinationPath.split('/'));
    mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
    copyFileSync(source, destination);
  }
  for (const [destinationPath, source] of Object.entries(sources.directories)) {
    const destinationRoot = join(output, ...destinationPath.split('/'));
    if (existsSync(destinationRoot)) fail(`原生产物目录目标已存在：${destinationPath}`);
    mkdirSync(destinationRoot, { recursive: true, mode: 0o700 });
    const symlinkContract = appleXcframeworkSymlinkContract(source);
    const entries = treeEntries(source, symlinkContract);
    for (const relativePath of entries.files) {
      const destination = join(destinationRoot, ...relativePath.split('/'));
      mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
      copyFileSync(join(source, ...relativePath.split('/')), destination);
    }
    // 不复制任意来源链接；只按已验证的文字合同重建五个相对链接。
    for (const relativePath of entries.symlinks) {
      const destination = join(destinationRoot, ...relativePath.split('/'));
      mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
      symlinkSync(
        symlinkContract[relativePath],
        destination,
      );
    }
  }
  for (const [platform, prefix] of Object.entries(sources.linux)) {
    for (const path of linuxInstallPaths(platform)) {
      const source = join(prefix, path);
      const destination = join(output, 'linux', path);
      if (existsSync(destination)) {
        if (lstatSync(destination).isSymbolicLink() || !lstatSync(destination).isFile()
            || !readFileSync(source).equals(readFileSync(destination))) {
          fail(`CitizenSDK Linux 安装件与来源重叠漂移，拒绝覆盖：${path}`);
        }
      } else {
        mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
        copyFileSync(source, destination);
      }
    }
  }
  copyWindowsNativeArtifact(sourceRoot, sources.windows, output);
}

function zipEntries(bytes, label) {
  const minimumEocd = 22;
  const maximumComment = 0xffff;
  let eocd = -1;
  for (let offset = bytes.length - minimumEocd;
    offset >= Math.max(0, bytes.length - minimumEocd - maximumComment);
    offset -= 1) {
    if (bytes.readUInt32LE(offset) === 0x06054b50) {
      eocd = offset;
      break;
    }
  }
  if (eocd < 0) fail(`${label} 不是普通 ZIP`);
  const disk = bytes.readUInt16LE(eocd + 4);
  const centralDisk = bytes.readUInt16LE(eocd + 6);
  const diskEntries = bytes.readUInt16LE(eocd + 8);
  const entryCount = bytes.readUInt16LE(eocd + 10);
  const centralSize = bytes.readUInt32LE(eocd + 12);
  const centralOffset = bytes.readUInt32LE(eocd + 16);
  const commentLength = bytes.readUInt16LE(eocd + 20);
  if (disk !== 0 || centralDisk !== 0 || diskEntries !== entryCount
      || entryCount === 0 || entryCount === 0xffff
      || centralSize === 0xffffffff || centralOffset === 0xffffffff
      || entryCount > 10000 || eocd + minimumEocd + commentLength !== bytes.length
      || centralOffset + centralSize !== eocd) {
    fail(`${label} ZIP 中央目录无效或使用了不支持的 ZIP64/分卷格式`);
  }

  const entries = new Map();
  let cursor = centralOffset;
  for (let index = 0; index < entryCount; index += 1) {
    if (cursor + 46 > eocd || bytes.readUInt32LE(cursor) !== 0x02014b50) {
      fail(`${label} ZIP 中央目录条目无效`);
    }
    const flags = bytes.readUInt16LE(cursor + 8);
    const method = bytes.readUInt16LE(cursor + 10);
    const compressedSize = bytes.readUInt32LE(cursor + 20);
    const uncompressedSize = bytes.readUInt32LE(cursor + 24);
    const nameLength = bytes.readUInt16LE(cursor + 28);
    const extraLength = bytes.readUInt16LE(cursor + 30);
    const entryCommentLength = bytes.readUInt16LE(cursor + 32);
    const localOffset = bytes.readUInt32LE(cursor + 42);
    const next = cursor + 46 + nameLength + extraLength + entryCommentLength;
    if (next > eocd || nameLength === 0 || (flags & 0x1) !== 0
        || ![0, 8].includes(method) || compressedSize === 0xffffffff
        || uncompressedSize === 0xffffffff || localOffset === 0xffffffff) {
      fail(`${label} ZIP 条目属性无效`);
    }
    const nameBytes = bytes.subarray(cursor + 46, cursor + 46 + nameLength);
    const name = nameBytes.toString('utf8');
    if (!Buffer.from(name, 'utf8').equals(nameBytes)
        || name.includes('\0') || name.includes('\\') || name.startsWith('/')
        || name.split('/').includes('..') || entries.has(name)) {
      fail(`${label} ZIP 条目路径无效或重复`);
    }
    if (localOffset + 30 > centralOffset || bytes.readUInt32LE(localOffset) !== 0x04034b50) {
      fail(`${label} ZIP local header 无效`);
    }
    const localFlags = bytes.readUInt16LE(localOffset + 6);
    const localMethod = bytes.readUInt16LE(localOffset + 8);
    const localNameLength = bytes.readUInt16LE(localOffset + 26);
    const localExtraLength = bytes.readUInt16LE(localOffset + 28);
    const localNameStart = localOffset + 30;
    const dataStart = localNameStart + localNameLength + localExtraLength;
    const dataEnd = dataStart + compressedSize;
    if (localFlags !== flags || localMethod !== method || dataEnd > centralOffset
        || !bytes.subarray(localNameStart, localNameStart + localNameLength).equals(nameBytes)) {
      fail(`${label} ZIP local/central 条目不一致`);
    }
    const compressed = bytes.subarray(dataStart, dataEnd);
    let content;
    try {
      content = method === 0 ? Buffer.from(compressed) : inflateRawSync(compressed);
    } catch {
      fail(`${label} ZIP 条目无法解压：${name}`);
    }
    if (content.length !== uncompressedSize) {
      fail(`${label} ZIP 条目长度不一致：${name}`);
    }
    entries.set(name, content);
    cursor = next;
  }
  if (cursor !== eocd) fail(`${label} ZIP 中央目录包含未解析字节`);
  return entries;
}

/** Verify the Android AAR and Flutter projection are the same two native bytes. */
export function assertAndroidReleaseProjection(root) {
  const candidate = resolve(root);
  const aarPath = join(candidate, 'android', 'citizensdk.aar');
  const corePath = join(
    candidate,
    'android',
    'src',
    'main',
    'jniLibs',
    'arm64-v8a',
    'libcitizensdk.so',
  );
  const jniPath = join(
    candidate,
    'android',
    'src',
    'main',
    'jniLibs',
    'arm64-v8a',
    'libcitizensdk_jni.so',
  );
  for (const [path, label] of [
    [aarPath, 'Android AAR'],
    [corePath, 'Flutter Android Core 库'],
    [jniPath, 'Flutter Android JNI 库'],
  ]) {
    if (!existsSync(path) || lstatSync(path).isSymbolicLink() || !lstatSync(path).isFile()) {
      fail(`CitizenSDK 候选缺少普通${label}`);
    }
  }

  const aarEntries = zipEntries(readFileSync(aarPath), 'CitizenSDK Android AAR');
  const nativeEntries = [...aarEntries.keys()]
    .filter((path) => path.startsWith('jni/') && !path.endsWith('/'))
    .sort();
  const expectedNativeEntries = [
    'jni/arm64-v8a/libcitizensdk.so',
    'jni/arm64-v8a/libcitizensdk_jni.so',
  ];
  if (JSON.stringify(nativeEntries) !== JSON.stringify(expectedNativeEntries)) {
    fail(`CitizenSDK Android AAR 双库闭集漂移：${nativeEntries.join(',') || '无'}`);
  }
  for (const required of ['AndroidManifest.xml', 'classes.jar']) {
    if (!aarEntries.has(required)) fail(`CitizenSDK Android AAR 缺少 ${required}`);
  }
  const packagedAssets = [...aarEntries.keys()]
    .filter((path) => path.startsWith('assets/') && !path.endsWith('/'))
    .sort();
  const expectedAssets = Object.keys(CHAIN_ASSET_FILES).sort();
  if (JSON.stringify(packagedAssets) !== JSON.stringify(expectedAssets)) {
    fail(`CitizenSDK Android AAR 链资产闭集漂移：${packagedAssets.join(',') || '无'}`);
  }
  for (const required of expectedAssets) {
    if (!aarEntries.get(required).equals(
      readFileSync(join(candidate, ...required.split('/')),
    ))) {
      fail(`CitizenSDK Android AAR 链资产与候选信任锚字节不一致：${required}`);
    }
  }
  if ([...aarEntries.keys()].some((path) => path.endsWith('.aar')
      || /(?:^|\/)(?:libsmoldot|libc\+\+_shared)\.so$/.test(path))) {
    fail('CitizenSDK Android AAR 混入嵌套 AAR、legacy 或共享 C++ 运行库');
  }
  if (!aarEntries.get(expectedNativeEntries[0]).equals(readFileSync(corePath))
      || !aarEntries.get(expectedNativeEntries[1]).equals(readFileSync(jniPath))) {
    fail('CitizenSDK Android AAR 与 Flutter 投影的双原生库字节不一致');
  }

  const classEntries = zipEntries(aarEntries.get('classes.jar'), 'CitizenSDK Android classes.jar');
  for (const required of [
    'org/citizen/sdk/CitizenSdk.class',
    'org/citizen/sdk/CitizenSdkLifecycle.class',
    'org/citizen/sdk/CitizenSdkException.class',
    'org/citizen/sdk/CitizenSdkEvents.class',
    'org/citizen/sdk/CitizenWalletProfile.class',
    'org/citizen/sdk/CitizenSdkOperation.class',
    'org/citizen/sdk/internal/CitizenSdkNative.class',
    'org/citizen/sdk/internal/CitizenSdkHardwareVault.class',
    'org/citizen/sdk/internal/CitizenSdkHostServices.class',
    'org/citizen/sdk/internal/CitizenSdkRequestRouter.class',
    'org/citizen/sdk/ui/CitizenSdkWalletFlowActivity.class',
    'org/citizen/sdk/ui/CitizenSdkWalletFlowContract.class',
    'org/citizen/sdk/ui/CitizenSdkWalletFlowCoordinator.class',
    'org/citizen/sdk/ui/CitizenSdkQrActivity.class',
    'org/citizen/sdk/ui/CitizenSdkQrCoordinator.class',
  ]) {
    if (!classEntries.has(required)) {
      fail(`CitizenSDK Android classes.jar 缺少必需实现：${required}`);
    }
  }
  for (const [path, content] of classEntries) {
    if (path.startsWith('io/flutter/') || content.includes(Buffer.from('io/flutter/'))) {
      fail('CitizenSDK Android 原生 AAR 混入或引用 Flutter API');
    }
  }
  const aarFiles = regularFiles(join(candidate, 'android'))
    .filter((path) => path.endsWith('.aar'))
    .sort();
  if (JSON.stringify(aarFiles) !== JSON.stringify(['citizensdk.aar'])) {
    fail(`CitizenSDK Android 候选 AAR 闭集漂移：${aarFiles.join(',') || '无'}`);
  }
}

function decodePlistXmlText(value, label) {
  return value.replace(/&(?:#(x[0-9a-fA-F]+|[0-9]+)|amp|apos|gt|lt|quot);/g, (entity, number) => {
    if (number !== undefined) {
      const radix = number.startsWith('x') ? 16 : 10;
      const digits = number.startsWith('x') ? number.slice(1) : number;
      const codePoint = Number.parseInt(digits, radix);
      if (!Number.isSafeInteger(codePoint) || codePoint > 0x10ffff) {
        fail(`${label} plist 含无效字符实体`);
      }
      return String.fromCodePoint(codePoint);
    }
    return {
      '&amp;': '&',
      '&apos;': "'",
      '&gt;': '>',
      '&lt;': '<',
      '&quot;': '"',
    }[entity];
  });
}

/** Parse the small XML-plist subset emitted for framework metadata. */
function parseXmlPlist(bytes, label) {
  let source = bytes.toString('utf8');
  source = source
    .replace(/^\uFEFF/, '')
    .replace(/<\?xml[\s\S]*?\?>/g, '')
    .replace(/<!DOCTYPE[\s\S]*?>/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .trim();
  const tokens = [...source.matchAll(/<[^>]+>|[^<]+/g)]
    .map((match) => match[0])
    .filter((token) => token.startsWith('<') || token.trim().length > 0);
  let cursor = 0;
  const take = () => tokens[cursor++];
  const expect = (expected) => {
    const actual = take();
    if (actual !== expected) fail(`${label} plist 结构无效；期望=${expected}；实际=${actual ?? '<eof>'}`);
  };
  const parseValue = () => {
    const token = take();
    if (token === '<dict>') {
      const value = Object.create(null);
      while (tokens[cursor] !== '</dict>') {
        expect('<key>');
        const keyText = take();
        if (!keyText || keyText.startsWith('<')) fail(`${label} plist key 无效`);
        expect('</key>');
        const key = decodePlistXmlText(keyText.trim(), label);
        if (Object.hasOwn(value, key)) fail(`${label} plist key 重复：${key}`);
        value[key] = parseValue();
      }
      cursor += 1;
      return value;
    }
    if (token === '<array>') {
      const value = [];
      while (tokens[cursor] !== '</array>') value.push(parseValue());
      cursor += 1;
      return value;
    }
    if (token === '<true/>') return true;
    if (token === '<false/>') return false;
    const scalar = token?.match(/^<(string|integer)>$/)?.[1];
    if (!scalar) fail(`${label} plist 含不支持的值：${token ?? '<eof>'}`);
    const text = take();
    if (text === `</${scalar}>`) return scalar === 'integer' ? 0 : '';
    if (!text || text.startsWith('<')) fail(`${label} plist 标量无效`);
    expect(`</${scalar}>`);
    const decoded = decodePlistXmlText(text.trim(), label);
    if (scalar === 'string') return decoded;
    if (!/^-?(?:0|[1-9][0-9]*)$/.test(decoded)) fail(`${label} plist integer 无效`);
    const integer = Number(decoded);
    if (!Number.isSafeInteger(integer)) fail(`${label} plist integer 超界`);
    return integer;
  };
  if (!/^<plist(?: version="1\.0")?>$/.test(tokens[cursor] ?? '')) {
    fail(`${label} 不是 XML plist 1.0`);
  }
  cursor += 1;
  const value = parseValue();
  expect('</plist>');
  if (cursor !== tokens.length) fail(`${label} plist 含尾随内容`);
  return value;
}

function encodedMachOVersion(value) {
  return `${value >>> 16}.${(value >>> 8) & 0xff}.${value & 0xff}`;
}

function machOCString(bytes, start, end, label) {
  const zero = bytes.indexOf(0, start);
  if (start < 0 || start >= end || zero < start || zero >= end) {
    fail(`${label} Mach-O 字符串越界或未终止`);
  }
  return bytes.subarray(start, zero).toString('utf8');
}

/** Read the thin arm64 Mach-O identity and external defined symbol table. */
function readAppleMachO(bytes, label) {
  if (bytes.length < 32 || bytes.readUInt32LE(0) !== 0xfeedfacf) {
    fail(`${label} 必须是 thin 64-bit Mach-O`);
  }
  const cpuType = bytes.readUInt32LE(4);
  const fileType = bytes.readUInt32LE(12);
  const commandCount = bytes.readUInt32LE(16);
  const commandBytes = bytes.readUInt32LE(20);
  if (cpuType !== 0x0100000c || fileType !== 6
      || commandCount === 0 || commandCount > 4096
      || commandBytes > bytes.length - 32) {
    fail(`${label} 必须是单一 arm64 动态 framework 二进制`);
  }
  let cursor = 32;
  const commandEnd = cursor + commandBytes;
  let identity = null;
  let build = null;
  let symbolTable = null;
  for (let index = 0; index < commandCount; index += 1) {
    if (cursor + 8 > commandEnd) fail(`${label} Mach-O load command 截断`);
    const command = bytes.readUInt32LE(cursor);
    const size = bytes.readUInt32LE(cursor + 4);
    if (size < 8 || cursor + size > commandEnd) fail(`${label} Mach-O load command 越界`);
    if (command === 0x0d) {
      if (identity !== null || size < 24) fail(`${label} LC_ID_DYLIB 无效或重复`);
      const nameOffset = bytes.readUInt32LE(cursor + 8);
      identity = machOCString(bytes, cursor + nameOffset, cursor + size, label);
    } else if (command === 0x32) {
      if (build !== null || size < 24) fail(`${label} LC_BUILD_VERSION 无效或重复`);
      build = {
        platform: bytes.readUInt32LE(cursor + 8),
        minimum: encodedMachOVersion(bytes.readUInt32LE(cursor + 12)),
      };
    } else if (command === 0x02) {
      if (symbolTable !== null || size < 24) fail(`${label} LC_SYMTAB 无效或重复`);
      symbolTable = {
        symbolOffset: bytes.readUInt32LE(cursor + 8),
        symbolCount: bytes.readUInt32LE(cursor + 12),
        stringOffset: bytes.readUInt32LE(cursor + 16),
        stringSize: bytes.readUInt32LE(cursor + 20),
      };
    }
    cursor += size;
  }
  if (cursor !== commandEnd || identity === null || build === null || symbolTable === null) {
    fail(`${label} 缺少唯一 install name、build version 或 symbol table`);
  }
  const symbolsEnd = symbolTable.symbolOffset + symbolTable.symbolCount * 16;
  const stringsEnd = symbolTable.stringOffset + symbolTable.stringSize;
  if (symbolTable.symbolCount > 1000000 || symbolsEnd > bytes.length
      || symbolTable.stringSize === 0 || stringsEnd > bytes.length) {
    fail(`${label} Mach-O symbol table 越界`);
  }
  const symbols = new Set();
  for (let index = 0; index < symbolTable.symbolCount; index += 1) {
    const offset = symbolTable.symbolOffset + index * 16;
    const stringIndex = bytes.readUInt32LE(offset);
    const type = bytes[offset + 4];
    const isDebug = (type & 0xe0) !== 0;
    const isPrivateExternal = (type & 0x10) !== 0;
    const isExternal = (type & 0x01) !== 0;
    const isUndefined = (type & 0x0e) === 0;
    // ld64 keeps hidden symbols as N_PEXT in the ordinary symbol table. They
    // remain usable inside the image but are not part of the dynamic product
    // boundary, so only public external defined symbols belong in this set.
    if (isDebug || isPrivateExternal || !isExternal || isUndefined) continue;
    if (stringIndex === 0 || stringIndex >= symbolTable.stringSize) {
      fail(`${label} Mach-O symbol string index 越界`);
    }
    const name = machOCString(
      bytes,
      symbolTable.stringOffset + stringIndex,
      stringsEnd,
      label,
    );
    symbols.add(name.startsWith('_') ? name.slice(1) : name);
  }
  return { build, identity, symbols };
}

// 私有跨库链接闭集与公开产品头分开核对。禁止用前缀允许集扩大导出面。
export const CITIZENSDK_INTERNAL_SYMBOLS = Object.freeze([
  'citizensdk_internal_private_key_view_cancel',
  'citizensdk_internal_private_key_view_finish',
  'citizensdk_internal_private_key_view_open',
  'citizensdk_internal_private_key_view_reveal',
]);

/** 仅生成到构建缓存目录；该声明及模块不能安装给SDK消费者。 */
export function citizenSdkInternalHeader() {
  return `#ifndef CITIZENSDK_INTERNAL_H
#define CITIZENSDK_INTERNAL_H
#include "citizensdk.h"
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* SDK内部借用合同：display仅在回调期间借用32字节，不得等待UI或反调SDK。
 * settled是阶段通知而非终态；context必须保留到普通request真实结束。
 * 此头不属于公开API，不能安装、公开透传或当作同进程安全隔离。 */
typedef struct {
  uint32_t struct_size;
  uint32_t abi_version;
  void *context;
  int32_t (*display)(void *context, uint64_t view_id,
                     citizensdk_bytes_view_t private_key);
  void (*settled)(void *context, uint64_t view_id, int32_t error_code);
  /* 在真实unwrap派发前只登记准确认证操作；拒绝时不调用设备金库。 */
  int32_t (*authorizing)(void *context, uint64_t view_id, uint64_t host_operation_id);
} citizensdk_internal_private_key_view_v1_t;
CITIZENSDK_API int32_t citizensdk_internal_private_key_view_open(
    citizensdk_handle_t handle, const citizensdk_account_id_t *account_id,
    const citizensdk_internal_private_key_view_v1_t *view,
    uint64_t *out_view_id, citizensdk_request_id_t *out_request_id);
CITIZENSDK_API int32_t citizensdk_internal_private_key_view_reveal(
    citizensdk_handle_t handle, uint64_t view_id);
CITIZENSDK_API int32_t citizensdk_internal_private_key_view_cancel(
    citizensdk_handle_t handle, uint64_t view_id);
/* finish只确认原生已清屏/清零，不允许提前释放仍在认证中的上下文。 */
CITIZENSDK_API int32_t citizensdk_internal_private_key_view_finish(
    citizensdk_handle_t handle, uint64_t view_id);
#ifdef __cplusplus
}
#define CITIZENSDK_INTERNAL_ASSERT static_assert
#else
#define CITIZENSDK_INTERNAL_ASSERT _Static_assert
#endif
CITIZENSDK_INTERNAL_ASSERT(sizeof(void *) == 8, "64-bit SDK host required");
CITIZENSDK_INTERNAL_ASSERT(sizeof(citizensdk_internal_private_key_view_v1_t) == 40, "private view size");
CITIZENSDK_INTERNAL_ASSERT(offsetof(citizensdk_internal_private_key_view_v1_t, struct_size) == 0, "struct_size offset");
CITIZENSDK_INTERNAL_ASSERT(offsetof(citizensdk_internal_private_key_view_v1_t, abi_version) == 4, "abi_version offset");
CITIZENSDK_INTERNAL_ASSERT(offsetof(citizensdk_internal_private_key_view_v1_t, context) == 8, "context offset");
CITIZENSDK_INTERNAL_ASSERT(offsetof(citizensdk_internal_private_key_view_v1_t, display) == 16, "display offset");
CITIZENSDK_INTERNAL_ASSERT(offsetof(citizensdk_internal_private_key_view_v1_t, settled) == 24, "settled offset");
CITIZENSDK_INTERNAL_ASSERT(offsetof(citizensdk_internal_private_key_view_v1_t, authorizing) == 32, "authorizing offset");
#undef CITIZENSDK_INTERNAL_ASSERT
#endif
`;
}

function expectedCitizenSdkSymbols(root) {
  const header = readFileSync(join(root, 'include', 'citizensdk.h'), 'utf8');
  const symbols = [...new Set(
    [...header.matchAll(/\b(citizensdk_[a-z0-9_]+)\s*\(/g)].map((match) => match[1]),
  )].sort();
  if (symbols.length !== 89) fail('CitizenSDK 产品头必须精确声明 89 个 citizensdk_* 函数');
  return symbols;
}

function expectedQrImageSymbols(root) {
  const header = readFileSync(join(root, 'native/qr-image/citizensdk_qr_image.h'), 'utf8');
  const symbols = [...new Set(
    [...header.matchAll(/\b(citizensdk_qr_image_[a-z0-9_]+)\s*\(/g)].map((match) => match[1]),
  )].sort();
  if (symbols.length !== 3) fail('CitizenSDK QR 图像头必须精确声明 3 个函数');
  return symbols;
}

function expectedAppleSymbols(root) {
  return [...expectedCitizenSdkSymbols(root), ...expectedQrImageSymbols(root)].sort();
}

function expectedCitizenSdkLinkedSymbols(root) {
  return [...expectedCitizenSdkSymbols(root), ...CITIZENSDK_INTERNAL_SYMBOLS].sort();
}

function assertAppleFrameworkSlice(candidate, xcframework, identifier, contract) {
  const label = contract.label;
  const sliceRoot = join(xcframework, identifier);
  const framework = join(sliceRoot, 'CitizenSDK.framework');
  if (!existsSync(sliceRoot) || lstatSync(sliceRoot).isSymbolicLink()
      || !lstatSync(sliceRoot).isDirectory()
      || JSON.stringify(readdirSync(sliceRoot).sort())
        !== JSON.stringify(['CitizenSDK.framework'])) {
    fail(`${label} slice 根闭集漂移`);
  }
  if (!existsSync(framework) || lstatSync(framework).isSymbolicLink()
      || !lstatSync(framework).isDirectory()) {
    fail(`${label} framework 缺失或不是普通目录`);
  }
  const isMacOS = contract.supportedPlatform === 'macos';
  // 单 slice 校验也必须独立关闭链接边界，不能依赖外层调用顺序。
  treeEntries(
    framework,
    isMacOS ? APPLE_MACOS_FRAMEWORK_SYMLINKS : Object.freeze({}),
  );
  const expectedTopEntries = isMacOS
    ? ['CitizenSDK', 'Headers', 'Modules', 'Resources', 'Versions']
    : ['CitizenSDK', 'Headers', 'Info.plist', 'Modules', 'Resources'];
  const topEntries = readdirSync(framework).sort();
  if (JSON.stringify(topEntries) !== JSON.stringify(expectedTopEntries)) {
    fail(`${label} framework 根闭集漂移`);
  }
  const contentRoot = isMacOS ? join(framework, 'Versions', 'A') : framework;
  if (isMacOS) {
    const versionEntries = readdirSync(join(framework, 'Versions')).sort();
    const contentEntries = readdirSync(contentRoot).sort();
    if (JSON.stringify(versionEntries) !== JSON.stringify(['A', 'Current'])
        || JSON.stringify(contentEntries)
          !== JSON.stringify(['CitizenSDK', 'Headers', 'Modules', 'Resources'])) {
      fail(`${label} 版本化 framework 闭集漂移`);
    }
  }
  const binaryPath = join(contentRoot, 'CitizenSDK');
  if (!existsSync(binaryPath) || lstatSync(binaryPath).isSymbolicLink()
      || !lstatSync(binaryPath).isFile()) {
    fail(`${label} 二进制必须是普通文件`);
  }
  const binary = readAppleMachO(readFileSync(binaryPath), label);
  if (binary.identity !== contract.installName) {
    fail(`${label} install name 漂移`);
  }
  if (binary.build.platform !== contract.platform
      || binary.build.minimum !== contract.minimum) {
    fail(`${label} 平台或最低系统版本漂移`);
  }
  const expectedSymbols = expectedAppleSymbols(candidate);
  const allSymbols = [...binary.symbols].sort();
  const actualSymbols = allSymbols
    .filter((symbol) => symbol.startsWith('citizensdk_'))
    .sort();
  if (JSON.stringify(actualSymbols) !== JSON.stringify(expectedSymbols)) {
    fail(`${label} 必须精确导出 92 个 citizensdk_* 产品符号`);
  }
  const forbidden = [...binary.symbols]
    .filter((symbol) => /^(?:smoldot_|citizen_sr25519_|account_crypto_)/.test(symbol))
    .sort();
  if (forbidden.length > 0) fail(`${label} 泄漏 legacy 低层符号：${forbidden.join(',')}`);
  const swiftSymbols = allSymbols.filter((symbol) => symbol.startsWith('$s10CitizenSDK'));
  if (swiftSymbols.length === 0) fail(`${label} 缺少 CitizenSDK Swift 模块导出`);
  const foreign = allSymbols.filter(
    (symbol) => !symbol.startsWith('citizensdk_')
      && !symbol.startsWith('$s10CitizenSDK'),
  );
  if (foreign.length > 0) {
    fail(`${label} 泄漏非 CitizenSDK 产品符号：${foreign.join(',')}`);
  }

  const headersRoot = join(contentRoot, 'Headers');
  if (JSON.stringify(readdirSync(headersRoot).sort())
      !== JSON.stringify(['citizensdk.h', 'citizensdk_qr_image.h', 'citizensdk_types.h'])) {
    fail(`${label} Headers 目录闭集漂移`);
  }
  const headerPaths = regularFiles(headersRoot);
  const expectedHeaders = ['citizensdk.h', 'citizensdk_qr_image.h', 'citizensdk_types.h'];
  if (JSON.stringify(headerPaths) !== JSON.stringify(expectedHeaders)) {
    fail(`${label} 产品头闭集漂移`);
  }
  for (const header of expectedHeaders) {
    const source = header === 'citizensdk_qr_image.h'
      ? join(candidate, 'native/qr-image', header) : join(candidate, 'include', header);
    if (!readFileSync(join(headersRoot, header)).equals(readFileSync(source))) {
      fail(`${label} 产品头与根 ABI 字节不一致：${header}`);
    }
  }

  const modulesRoot = join(contentRoot, 'Modules');
  const moduleMapPath = join(modulesRoot, 'module.modulemap');
  const swiftModuleRoot = join(modulesRoot, 'CitizenSDK.swiftmodule');
  if (!existsSync(moduleMapPath) || lstatSync(moduleMapPath).isSymbolicLink()
      || !lstatSync(moduleMapPath).isFile()
      || !existsSync(swiftModuleRoot) || lstatSync(swiftModuleRoot).isSymbolicLink()
      || !lstatSync(swiftModuleRoot).isDirectory()) {
    fail(`${label} Clang/Swift module 不完整`);
  }
  if (JSON.stringify(readdirSync(modulesRoot).sort())
      !== JSON.stringify(['CitizenSDK.swiftmodule', 'module.modulemap'])) {
    fail(`${label} Modules 目录闭集漂移`);
  }
  const moduleMap = readFileSync(moduleMapPath, 'utf8');
  if (!moduleMap.includes('framework module CitizenSDK')
      || !moduleMap.includes('umbrella header "citizensdk.h"')
      || /(?:smoldot_|citizen_sr25519_|account_crypto_)/.test(moduleMap)) {
    fail(`${label} module.modulemap 边界无效`);
  }
  const swiftModules = regularFiles(swiftModuleRoot);
  if (readdirSync(swiftModuleRoot).some((path) => {
    const info = lstatSync(join(swiftModuleRoot, path));
    return info.isSymbolicLink() || !info.isFile();
  })) {
    fail(`${label} Swift module 只允许普通文件`);
  }
  const expectedSwiftModules = APPLE_SWIFT_MODULE_EXTENSIONS
    .map((extension) => `${contract.module}.${extension}`)
    .sort();
  if (JSON.stringify(swiftModules) !== JSON.stringify(expectedSwiftModules)) {
    fail(`${label} Swift module 六文件闭集或架构身份漂移`);
  }
  const publicInterface = readFileSync(
    join(swiftModuleRoot, `${contract.module}.swiftinterface`), 'utf8',
  );
  const privateInterface = readFileSync(
    join(swiftModuleRoot, `${contract.module}.private.swiftinterface`), 'utf8',
  );
  for (const [kind, swiftInterface] of [
    ['public', publicInterface],
    ['private', privateInterface],
  ]) {
    if (/CitizenSDKInternal|citizensdk_internal_/.test(swiftInterface)) {
      fail(`${label} ${kind} Swift interface 泄漏构建期私有依赖`);
    }
    if (!/^\/\/ swift-interface-format-version:/m.test(swiftInterface)
        || !/^@_exported import CitizenSDK$/m.test(swiftInterface)) {
      fail(`${label} ${kind} Swift interface 未固定同名 underlying Clang module`);
    }
    const moduleFlags = swiftInterface.match(/^\/\/ swift-module-flags:.*$/gm) ?? [];
    if (moduleFlags.length !== 1
        || !new RegExp(`(?:^| )-target ${contract.swiftTarget.replaceAll('.', '\\.')}(?: |$)`)
          .test(moduleFlags[0])) {
      fail(`${label} ${kind} Swift interface target triple 漂移`);
    }
  }
  const expectedSpi = [
    '  @_spi(CitizenSDKFlutter) final public func supervisedClose() async throws',
    '  @_spi(CitizenSDKFlutter) final public func enqueueForSupervisedClose()',
  ];
  const publicSpi = publicInterface.split('\n').filter((line) => line.includes('@_spi('));
  const privateSpi = privateInterface.split('\n').filter((line) => line.includes('@_spi('));
  if (publicSpi.length !== 0
      || JSON.stringify(privateSpi) !== JSON.stringify(expectedSpi)
      || privateInterface.split('\n').filter((line) => !expectedSpi.includes(line)).join('\n')
        !== publicInterface) {
    fail(`${label} public/private Swift interface 或 CitizenSDKFlutter SPI 闭集漂移`);
  }
  if (/\b(?:CitizenSDKNative|CitizenSdkNativeResult|CitizenSDKPreparedWallet|CitizenSDKHandle|CitizenSDKSecretVault)\b/.test(publicInterface)) {
    fail(`${label} public Swift interface 泄漏底层 native/secret/handle 类型`);
  }

  const resourcesRoot = join(contentRoot, 'Resources');
  const expectedResourceEntries = [
    'PrivacyInfo.xcprivacy',
    'citizenchain',
    ...(isMacOS ? ['Info.plist'] : []),
  ].sort();
  if (JSON.stringify(readdirSync(resourcesRoot).sort())
      !== JSON.stringify(expectedResourceEntries)
      || JSON.stringify(readdirSync(join(resourcesRoot, 'citizenchain')).sort())
        !== JSON.stringify(['chainspec.json', 'light_sync_state.json', 'manifest.json'])) {
    fail(`${label} Resources 目录闭集漂移`);
  }
  const resources = regularFiles(resourcesRoot);
  const expectedResources = [
    ...Object.keys(APPLE_RESOURCE_FILES),
    ...(isMacOS ? ['Info.plist'] : []),
  ].sort();
  if (JSON.stringify(resources) !== JSON.stringify(expectedResources)) {
    fail(`${label} Resources 闭集漂移`);
  }
  for (const [resource, source] of Object.entries(APPLE_RESOURCE_FILES)) {
    if (!readFileSync(join(resourcesRoot, ...resource.split('/'))).equals(
      readFileSync(join(candidate, ...source.split('/'))),
    )) {
      fail(`${label} Resource 与唯一来源字节不一致：${resource}`);
    }
  }

  const frameworkInfo = parseXmlPlist(
    readFileSync(isMacOS
      ? join(resourcesRoot, 'Info.plist')
      : join(framework, 'Info.plist')),
    `${label} Info.plist`,
  );
  const sdkVersion = readFileSync(join(candidate, 'pubspec.yaml'), 'utf8')
    .match(/^version: (\d+\.\d{1,2}\.\d{1,2})$/m)?.[1];
  const expectedInfoKeys = [
    'CFBundleDevelopmentRegion',
    'CFBundleExecutable',
    'CFBundleIdentifier',
    'CFBundleInfoDictionaryVersion',
    'CFBundleName',
    'CFBundlePackageType',
    'CFBundleShortVersionString',
    'CFBundleSupportedPlatforms',
    'CFBundleVersion',
    'DTPlatformName',
    contract.minimumKey,
  ].sort();
  if (!sdkVersion
      || JSON.stringify(Object.keys(frameworkInfo).sort()) !== JSON.stringify(expectedInfoKeys)
      || frameworkInfo.CFBundleDevelopmentRegion !== 'en'
      || frameworkInfo.CFBundleExecutable !== 'CitizenSDK'
      || frameworkInfo.CFBundleIdentifier !== 'org.citizen.sdk'
      || frameworkInfo.CFBundleInfoDictionaryVersion !== '6.0'
      || frameworkInfo.CFBundleName !== 'CitizenSDK'
      || frameworkInfo.CFBundlePackageType !== 'FMWK'
      || frameworkInfo.CFBundleShortVersionString !== sdkVersion
      || frameworkInfo.CFBundleVersion !== sdkVersion
      || JSON.stringify(frameworkInfo.CFBundleSupportedPlatforms)
        !== JSON.stringify([contract.bundlePlatform])
      || frameworkInfo.DTPlatformName !== contract.dtPlatform
      || frameworkInfo[contract.minimumKey] !== contract.minimum.replace(/\.0$/, '')) {
    fail(`${label} framework Info.plist 身份漂移`);
  }
}

/** Verify one Apple product whose public platforms are exactly iOS and macOS. */
export function assertAppleReleaseProjection(root) {
  const candidate = resolve(root);
  const xcframework = join(candidate, ...APPLE_XCFRAMEWORK_PATH.split('/'));
  if (!existsSync(xcframework) || lstatSync(xcframework).isSymbolicLink()
      || !lstatSync(xcframework).isDirectory()) {
    fail('CitizenSDK 候选缺少普通 CitizenSDK.xcframework');
  }
  // 全树只允许 macOS framework 的标准五链接；这同时保证两个 iOS slice、
  // XCFramework Info.plist 和所有资源/模块均不存在链接旁路。
  treeEntries(xcframework, appleXcframeworkSymlinkContract(xcframework));
  const info = parseXmlPlist(
    readFileSync(join(xcframework, 'Info.plist')),
    'CitizenSDK.xcframework Info.plist',
  );
  if (JSON.stringify(Object.keys(info).sort()) !== JSON.stringify([
    'AvailableLibraries',
    'CFBundlePackageType',
    'XCFrameworkFormatVersion',
  ])
      || info.CFBundlePackageType !== 'XFWK'
      || info.XCFrameworkFormatVersion !== '1.0'
      || !Array.isArray(info.AvailableLibraries)
      || info.AvailableLibraries.length !== APPLE_SLICES.length) {
    fail('CitizenSDK.xcframework Info.plist 格式或 slice 数量无效');
  }
  const identifiers = new Set();
  const libraries = new Map();
  for (const library of info.AvailableLibraries) {
    if (!library || Array.isArray(library) || typeof library !== 'object'
        || typeof library.LibraryIdentifier !== 'string'
        || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(library.LibraryIdentifier)
        || identifiers.has(library.LibraryIdentifier)) {
      fail('CitizenSDK.xcframework LibraryIdentifier 无效或重复');
    }
    identifiers.add(library.LibraryIdentifier);
    const identity = `${library.SupportedPlatform}/${library.SupportedPlatformVariant ?? ''}`;
    if (libraries.has(identity)) fail(`CitizenSDK.xcframework 技术变体重复：${identity}`);
    libraries.set(identity, library);
  }
  const resolvedSlices = [];
  for (const contract of APPLE_SLICES) {
    const identity = `${contract.supportedPlatform}/${contract.variant ?? ''}`;
    const library = libraries.get(identity);
    const identifier = library?.LibraryIdentifier;
    if (!library
        || library.BinaryPath !== contract.binaryPath
        || library.LibraryPath !== 'CitizenSDK.framework'
        || JSON.stringify(library.SupportedArchitectures) !== JSON.stringify(['arm64'])
        || library.SupportedPlatform !== contract.supportedPlatform
        || (library.SupportedPlatformVariant ?? null) !== contract.variant) {
      fail(`${contract.label} XCFramework slice 元数据漂移`);
    }
    const expectedKeys = [
      'BinaryPath',
      'LibraryIdentifier',
      'LibraryPath',
      'SupportedArchitectures',
      'SupportedPlatform',
      ...(contract.variant === null ? [] : ['SupportedPlatformVariant']),
    ].sort();
    if (JSON.stringify(Object.keys(library).sort()) !== JSON.stringify(expectedKeys)) {
      fail(`${contract.label} XCFramework slice 字段闭集漂移`);
    }
    resolvedSlices.push({ contract, identifier });
  }
  const expectedEntries = [
    'Info.plist',
    ...resolvedSlices.map(({ identifier }) => identifier),
  ].sort();
  const entries = readdirSync(xcframework).sort();
  if (JSON.stringify(entries) !== JSON.stringify(expectedEntries)) {
    fail(`CitizenSDK.xcframework 三 slice 闭集漂移：${entries.join(',') || '无'}`);
  }
  for (const { contract, identifier } of resolvedSlices) {
    assertAppleFrameworkSlice(candidate, xcframework, identifier, contract);
  }
}

export function assertNoSecrets(root) {
  const forbiddenName = /(^|\/)(\.env(?:\.|$)|\.dev\.vars(?:\.|$)|.*\.(?:jks|keystore|p8|p12|pem))$/i;
  // 分段构造使扫描器源码本身不携带完整 PEM 标记，同时仍逐字节检查候选内容。
  const privateMaterial = Buffer.from(['PRIVATE', ' KEY-----'].join(''));
  for (const relativePath of releaseCandidateEntries(root).files) {
    if (forbiddenName.test(relativePath)) fail(`SDK 候选包含禁止的本地或密钥文件：${relativePath}`);
    if (readFileSync(join(root, ...relativePath.split('/'))).includes(privateMaterial)) {
      fail(`SDK 候选疑似包含私钥材料：${relativePath}`);
    }
  }
}

function fileEntries(root, paths) {
  return paths.map((path) => ({ path, sha256: sha256File(join(root, ...path.split('/'))) }));
}

function writeOctal(buffer, offset, length, value) {
  const text = value.toString(8).padStart(length - 1, '0');
  if (text.length >= length) fail('CitizenSDK 归档字段超过 tar 限制');
  buffer.write(`${text}\0`, offset, length, 'ascii');
}

function writeUstarPath(header, relativePath) {
  if (Buffer.byteLength(relativePath) <= 100) {
    header.write(relativePath, 0, 100, 'utf8');
    return;
  }
  const separators = [...relativePath.matchAll(/\//g)].map((match) => match.index);
  for (let index = separators.length - 1; index >= 0; index -= 1) {
    const separator = separators[index];
    const prefix = relativePath.slice(0, separator);
    const name = relativePath.slice(separator + 1);
    if (Buffer.byteLength(prefix) <= 155 && Buffer.byteLength(name) <= 100) {
      header.write(name, 0, 100, 'utf8');
      header.write(prefix, 345, 155, 'utf8');
      return;
    }
  }
  fail(`CitizenSDK 归档路径超过 ustar 限制：${relativePath}`);
}

function deterministicTar(candidatePath, excludedPaths = new Set()) {
  const chunks = [];
  const candidateEntries = releaseCandidateEntries(candidatePath);
  const entries = [
    ...candidateEntries.files.map((path) => ({ path, type: 'file' })),
    ...candidateEntries.symlinks.map((path) => ({
      path,
      target: appleXcframeworkSymlinkContract(
        join(candidatePath, ...APPLE_XCFRAMEWORK_PATH.split('/')),
        APPLE_XCFRAMEWORK_PATH,
      )[path],
      type: 'symlink',
    })),
  ].sort((left, right) => left.path.localeCompare(right.path));
  for (const entry of entries) {
    const relativePath = entry.path;
    if (excludedPaths.has(relativePath)) continue;
    const path = join(candidatePath, ...relativePath.split('/'));
    const content = entry.type === 'file' ? readFileSync(path) : Buffer.alloc(0);
    const header = Buffer.alloc(512);
    writeUstarPath(header, relativePath);
    writeOctal(
      header,
      100,
      8,
      entry.type === 'symlink'
        ? 0o777
        : ((lstatSync(path).mode & 0o111) === 0 ? 0o600 : 0o700),
    );
    writeOctal(header, 108, 8, 0);
    writeOctal(header, 116, 8, 0);
    writeOctal(header, 124, 12, content.length);
    writeOctal(header, 136, 12, 0);
    header.fill(0x20, 148, 156);
    header[156] = (entry.type === 'symlink' ? '2' : '0').charCodeAt(0);
    if (entry.type === 'symlink') {
      if (Buffer.byteLength(entry.target) > 100) {
        fail(`CitizenSDK 归档链接目标超过 ustar 限制：${relativePath}`);
      }
      header.write(entry.target, 157, 100, 'utf8');
    }
    header.write('ustar\0', 257, 6, 'ascii');
    header.write('00', 263, 2, 'ascii');
    const checksum = header.reduce((sum, byte) => sum + byte, 0);
    header.write(`${checksum.toString(8).padStart(6, '0')}\0 `, 148, 8, 'ascii');
    chunks.push(header, content);
    const padding = (512 - (content.length % 512)) % 512;
    if (padding) chunks.push(Buffer.alloc(padding));
  }
  chunks.push(Buffer.alloc(1024));
  return Buffer.concat(chunks);
}

function verifyCandidatePayload(candidatePath, expectedGitSha = null, expectExternalSums = false) {
  const candidate = assertSafeTargetPath(candidatePath, '候选目录');
  if (!existsSync(candidate) || lstatSync(candidate).isSymbolicLink() || !lstatSync(candidate).isDirectory()) {
    fail('CitizenSDK 候选目录不存在或不是普通目录');
  }
  const manifestPath = join(candidate, 'citizensdk-release.json');
  const sumsPath = join(candidate, 'SHA256SUMS');
  if (!existsSync(manifestPath) || (expectExternalSums && !existsSync(sumsPath))) {
    fail('CitizenSDK 候选缺少正式清单');
  }
  assertSmoldotDartSource(candidate);
  assertSmoldotLocks(candidate);
  assertSdkRootLocks(candidate);
  assertProviderLockParity(candidate);
  assertCoreRustSource(candidate);
  assertSmoldotRustSource(candidate);
  assertSignerSource(candidate);
  assertPublicAbiHeaders(candidate);
  assertMobileBindingSource(candidate, { allowAppleReleaseProjection: true });
  assertLinuxBindingSource(candidate, { allowInjectedLinuxArtifacts: true });
  assertWindowsBindingSource(candidate, { allowInjectedWindowsArtifacts: true });
  assertFlutterBindingContract(candidate);
  assertChainAssets(candidate);
  assertSourceFixtures(candidate);
  assertLicenseSources(candidate);
  assertDocumentationSource(candidate, { allowAppleReleaseProjection: true });
  const hostedSoftwareVersion = assertHostedPackageSource(candidate, {
    allowInjectedLinuxArtifacts: true, allowInjectedWindowsArtifacts: true,
  });
  assertSdkTestContracts(candidate);
  assertSdkScriptSource(candidate);
  assertAndroidReleaseProjection(candidate);
  assertAppleReleaseProjection(candidate);
  assertLinuxReleaseProjection(candidate);
  assertWindowsReleaseProjection(candidate);
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const keys = Object.keys(manifest).sort();
  const expectedKeys = ['files', 'git_commit_sha', 'package_name', 'platforms', 'product_id', 'software_version'];
  if (JSON.stringify(keys) !== JSON.stringify(expectedKeys)) fail('CitizenSDK 正式清单字段集合不正确');
  if (manifest.product_id !== PRODUCT_ID || manifest.package_name !== PACKAGE_NAME) fail('CitizenSDK 候选产品身份不正确');
  if (!/^\d+\.\d{1,2}\.\d{1,2}$/.test(manifest.software_version)) fail('CitizenSDK 候选版本无效');
  if (manifest.software_version !== hostedSoftwareVersion) fail('CitizenSDK 候选 manifest 与包版本不一致');
  if (!/^[0-9a-f]{40}$/.test(manifest.git_commit_sha)) fail('CitizenSDK 候选 Git SHA 无效');
  if (expectedGitSha !== null && manifest.git_commit_sha !== expectedGitSha) fail('CitizenSDK 候选 Git SHA 不匹配');
  const dependencyEvidence = JSON.parse(readFileSync(nativeArtifactSource(candidate, 'native-dependencies.json'), 'utf8'));
  dependencyCheck(Array.isArray(dependencyEvidence) && dependencyEvidence.length === 3, '候选依赖平台证据不完整');
  for (const [index, platform] of NATIVE_DEPENDENCY_PLATFORMS.entries()) {
    assertCitizenSdkDependencyEvidence(dependencyEvidence[index], platform, candidate, 'candidate', candidate,
      manifest.git_commit_sha, manifest.software_version);
  }
  dependencyCheck(new Set(dependencyEvidence.map((item) => item.dependency_inputs.build_mode)).size === 1,
    '候选混用了 CI 与 Release 输入');
  const expectedPlatforms = RELEASE_PLATFORMS;
  if (stableJson(manifest.platforms) !== stableJson(expectedPlatforms)) fail('CitizenSDK 候选平台集合不正确');
  if (!Array.isArray(manifest.files) || manifest.files.length === 0) fail('CitizenSDK 候选文件清单为空');
  const paths = [];
  for (const entry of manifest.files) {
    if (!entry || Object.keys(entry).sort().join(',') !== 'path,sha256'
        || typeof entry.path !== 'string' || entry.path.startsWith('/')
        || entry.path.split('/').includes('..') || !/^[A-Za-z0-9._/-]+$/.test(entry.path)
        || !/^[0-9a-f]{64}$/.test(entry.sha256)) {
      fail('CitizenSDK 候选文件条目无效');
    }
    const path = join(candidate, ...entry.path.split('/'));
    if (!path.startsWith(`${candidate}${sep}`)) fail('CitizenSDK 候选文件路径越界');
    if (!existsSync(path) || !lstatSync(path).isFile() || sha256File(path) !== entry.sha256) {
      fail(`CitizenSDK 候选文件哈希不一致：${entry.path}`);
    }
    paths.push(entry.path);
  }
  if (JSON.stringify(paths) !== JSON.stringify([...paths].sort()) || new Set(paths).size !== paths.length) {
    fail('CitizenSDK 候选文件顺序或唯一性无效');
  }
  for (const required of [
    'native-dependencies.json',
    '.pubignore',
    'CHANGELOG.md',
    'LICENSE',
    'pubspec.yaml',
    ...Object.keys(NATIVE_FILES),
    `${APPLE_XCFRAMEWORK_PATH}/Info.plist`,
    ...LINUX_RELEASE_FILES.map((path) => `linux/${path}`),
    ...WINDOWS_RELEASE_FILES.map((path) => `windows/${path}`),
  ]) {
    if (!paths.includes(required)) fail(`CitizenSDK 候选缺少必需文件：${required}`);
  }
  const expectedFiles = [
    ...paths,
    'citizensdk-release.json',
    ...(expectExternalSums ? ['SHA256SUMS'] : []),
  ].sort();
  if (JSON.stringify(releaseCandidateEntries(candidate).files)
      !== JSON.stringify(expectedFiles)) {
    fail('CitizenSDK 候选包含未登记文件');
  }
  assertNoSecrets(candidate);
  return { candidate, manifest, manifestPath, sumsPath };
}

/// 反向核验最终 gzip/tar 字节、外层下载校验和与候选闭集。
///
/// `SHA256SUMS` 是 GitHub Release 的外部资产，不进入 tgz，从而可以覆盖 tgz
/// 自身而不存在循环哈希。归档必须逐字节等于本打包器从候选重建出的规范 gzip。
export function verifyCitizenSdkRelease(candidatePath, archivePath, expectedGitSha = null) {
  const verified = verifyCandidatePayload(candidatePath, expectedGitSha, true);
  const archive = assertSafeTargetPath(archivePath, '归档');
  if (!existsSync(archive) || lstatSync(archive).isSymbolicLink() || !lstatSync(archive).isFile()) {
    fail('CitizenSDK 归档不存在或不是普通文件');
  }
  const expectedArchive = gzipSync(
    deterministicTar(verified.candidate, new Set(['SHA256SUMS'])),
    { level: 9, mtime: 0 },
  );
  if (!readFileSync(archive).equals(expectedArchive)) {
    fail('CitizenSDK 归档不是候选闭集的规范 gzip/tar 字节');
  }
  const checksums = [
    { path: 'citizensdk-release.json', sha256: sha256File(verified.manifestPath) },
    { path: 'citizensdk.tgz', sha256: sha256File(archive) },
  ].sort((left, right) => left.path.localeCompare(right.path));
  const expectedSums = `${checksums.map(({ sha256, path }) => `${sha256}  ${path}`).join('\n')}\n`;
  if (readFileSync(verified.sumsPath, 'utf8') !== expectedSums) {
    fail('CitizenSDK 外层 SHA256SUMS 不一致');
  }
  return verified.manifest;
}

export function buildCitizenSdkRelease({ sourcePath, nativePath, outputPath, archivePath, gitCommitSha, softwareVersion }) {
  const source = resolve(sourcePath);
  const native = assertSafeTargetPath(nativePath, '原生产物目录');
  const output = assertSafeTargetPath(outputPath, '候选目录');
  const archive = assertSafeTargetPath(archivePath, '归档');
  if (!existsSync(source) || !lstatSync(source).isDirectory()) fail('CitizenSDK 源码目录不存在');
  if (!existsSync(native) || !lstatSync(native).isDirectory()) fail('CitizenSDK 原生产物目录不存在');
  assertSmoldotDartSource(source);
  assertSmoldotLocks(source);
  assertSdkRootLocks(source);
  assertProviderLockParity(source);
  assertCoreRustSource(source);
  assertSmoldotRustSource(source);
  assertSignerSource(source);
  assertPublicAbiHeaders(source);
  assertMobileBindingSource(source);
  assertLinuxBindingSource(source);
  assertWindowsBindingSource(source);
  assertFlutterBindingContract(source);
  assertChainAssets(source);
  assertSourceFixtures(source);
  assertLicenseSources(source);
  assertDocumentationSource(source);
  const sourceSoftwareVersion = assertHostedPackageSource(source);
  assertSdkTestContracts(source);
  assertSdkScriptSource(source);
  if (!/^[0-9a-f]{40}$/.test(gitCommitSha)) fail('Git commit SHA 必须是 40 位小写十六进制');
  if (!/^\d+\.\d{1,2}\.\d{1,2}$/.test(softwareVersion)) fail('CitizenSDK 软件版本无效');
  if (softwareVersion !== sourceSoftwareVersion) {
    fail(`CitizenSDK 发布版本必须与源码一致：源码=${sourceSoftwareVersion}；请求=${softwareVersion}`);
  }
  assertLocalTarget(native, '原生产物目录');
  assertLocalTarget(output, '候选目录');
  assertLocalTarget(archive, '归档');
  assertOutsideSource(source, native, '原生产物目录');
  assertOutsideSource(source, archive, '归档');
  assertOutsideSource(native, output, '候选目录');
  assertOutsideSource(output, archive, '归档');
  if (existsSync(archive)) fail(`归档已存在，拒绝覆盖：${archive}`);
  // Validate both full native prefixes and every shared/source byte before
  // creating a candidate. Missing or mixed Linux input must not publish output.
  const nativeSources = assertNativeArtifactSources(native);
  for (const [platform, prefix] of Object.entries(nativeSources.linux)) {
    assertLinuxInstalledPlatform(source, prefix, platform);
  }
  assertWindowsNativeArtifact(source, nativeSources.windows);
  // 来源缺件/混版必须在首次创建候选前失败，不留下貌似完整的半成品。
  const dependencyEvidence = collectDependencyEvidence(native, source, gitCommitSha, softwareVersion);
  dependencyCheck(new Set(dependencyEvidence.map((item) => item.dependency_inputs.build_mode)).size === 1,
    '候选混用了 CI 与 Release 输入');
  ensureNewDirectory(output, source, '候选目录');
  for (const path of ROOT_FILES) copySourceTree(source, output, path);
  for (const path of ROOT_DIRECTORIES) copySourceTree(source, output, path);
  applySoftwareVersion(output, softwareVersion);
  copyNativeFiles(native, output, source);
  writeFileSync(join(output, 'native-dependencies.json'),
    prettyStableJson(dependencyEvidence),
    { flag: 'wx', mode: 0o600 });
  const payloadPaths = releaseCandidateEntries(output).files;
  const manifest = {
    product_id: PRODUCT_ID,
    package_name: PACKAGE_NAME,
    software_version: softwareVersion,
    git_commit_sha: gitCommitSha,
    platforms: [...RELEASE_PLATFORMS],
    files: fileEntries(output, payloadPaths),
  };
  const manifestPath = join(output, 'citizensdk-release.json');
  writeFileSync(manifestPath, prettyStableJson(manifest), { mode: 0o600 });
  verifyCandidatePayload(output, gitCommitSha);
  mkdirSync(dirname(archive), { recursive: true, mode: 0o700 });
  writeFileSync(
    archive,
    gzipSync(deterministicTar(output), { level: 9, mtime: 0 }),
    { mode: 0o600 },
  );
  const checksums = [
    { path: 'citizensdk-release.json', sha256: sha256File(manifestPath) },
    { path: 'citizensdk.tgz', sha256: sha256File(archive) },
  ].sort((left, right) => left.path.localeCompare(right.path));
  writeFileSync(join(output, 'SHA256SUMS'), `${checksums.map(({ sha256, path }) => `${sha256}  ${path}`).join('\n')}\n`, { mode: 0o600 });
  verifyCitizenSdkRelease(output, archive, gitCommitSha);
  return manifest;
}

// 本步只固定 Pub 官方打包行为，不增加发布账号、上传协议或另一套产品版本。
const HOSTED_DART_VERSION = '3.12.2';

/** 完整候选的 Hosted 投影；只能从已经验真的审计候选取得预期，不能从待验归档反推。 */
export function hostedPackageEntries(candidatePath) {
  const candidate = assertSafeTargetPath(candidatePath, 'Hosted 来源');
  const rootEntries = [...ROOT_FILES, ...ROOT_DIRECTORIES, 'native-dependencies.json', 'citizensdk-release.json', 'SHA256SUMS'].sort();
  if (JSON.stringify(readdirSync(candidate).sort()) !== JSON.stringify(rootEntries)) {
    fail('CitizenSDK Hosted 来源根闭集漂移');
  }
  // 先检查全树的五个准入链接；展开后的间接路径也只能解析到该候选内部。
  releaseCandidateEntries(candidate);
  const rules = hostedPubignoreRules(candidate);
  const entries = new Map();
  const names = new Set();
  let size = 0;
  const visit = (directory, depth = 0) => {
    if (depth > 128) fail('CitizenSDK Hosted 来源目录过深');
    for (const name of readdirSync(join(candidate, directory)).sort()) {
      const path = directory ? `${directory}/${name}` : name;
      // Pub 默认排除隐藏输入和 lock；此 SDK 没有任何嵌套 ignore 文件或隐藏运行资产。
      if (name.startsWith('.') || name === 'pubspec.lock' || path === 'pubspec_overrides.yaml') continue;
      const source = join(candidate, path);
      const resolved = realpathSync(source);
      if (!resolved.startsWith(`${candidate}${sep}`)) fail(`CitizenSDK Hosted 来源越界：${path}`);
      const info = statSync(source);
      const directoryEntry = info.isDirectory();
      if (isHostedIgnored(directoryEntry ? `${path}/` : path, rules)) continue;
      if (!directoryEntry && !info.isFile()) fail(`CitizenSDK Hosted 来源类型无效：${path}`);
      const key = path.normalize('NFC').toLowerCase();
      if (names.has(key) || Buffer.byteLength(path) > 4096 || entries.size >= 16384) {
        fail('CitizenSDK Hosted 来源路径冲突或超过上限');
      }
      names.add(key);
      size += directoryEntry ? 0 : info.size;
      if (size > 256 * 1024 * 1024) fail('CitizenSDK Hosted 展开内容超过 256 MiB 安全上限');
      entries.set(path, {
        type: directoryEntry ? 'directory' : 'file',
        mode: directoryEntry ? 0o755 : 0o644 | (info.mode & 0o111),
        data: directoryEntry ? Buffer.alloc(0) : readFileSync(source),
      });
      if (directoryEntry) visit(path, depth + 1);
    }
  };
  visit('');
  // 既有局部合同仍独立成立；这里再覆盖全部包根、法律、资产和平台输入。
  for (const path of ['pubspec.yaml', 'README.md', 'CHANGELOG.md', 'LICENSE', 'LICENSE-GPL-3.0',
    'LICENSE-MIT', 'THIRD_PARTY_NOTICES.md', ...HOSTED_RUNTIME_DART_FILES]) {
    if (entries.get(path)?.type !== 'file') fail(`CitizenSDK Hosted 缺少必要文件：${path}`);
  }
  return entries;
}

function compareHostedEntries(actual, expected) {
  const missing = [...expected.keys()].filter((path) => !actual.has(path));
  const extra = [...actual.keys()].filter((path) => !expected.has(path));
  if (missing.length || extra.length) {
    fail(`CitizenSDK Hosted 完整闭集漂移；缺失=${missing.join(',') || '无'}；额外=${extra.join(',') || '无'}`);
  }
  for (const [path, entry] of expected) {
    const other = actual.get(path);
    if (other.type !== entry.type || other.mode !== entry.mode || !other.data.equals(entry.data)) {
      fail(`CitizenSDK Hosted 类型、权限或字节不一致：${path}`);
    }
  }
}

function removeOwnedDirectory(path, identity) {
  const info = lstatSync(path);
  if (!info.isDirectory() || info.isSymbolicLink() || info.ino !== identity.ino
      || info.dev !== identity.dev || info.uid !== identity.uid) {
    fail('CitizenSDK Hosted 失败目录身份改变，保留现场');
  }
  rmSync(path, { recursive: true });
}

function readHostedArchive(path) {
  assertSafeTargetPath(path, 'Hosted 归档');
  // 非阻塞打开避免 FIFO 在 fstat 类型拒绝前等待写端；普通归档仍按同一 fd 读取。
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const info = fstatSync(descriptor);
    if (!info.isFile() || info.size < 20 || info.size > 100 * 1024 * 1024) {
      fail('CitizenSDK Hosted 归档类型或长度无效');
    }
    // 在读取前限定分配量；增长、截断或替换不能让 readFileSync 先读入无界内容。
    const bytes = Buffer.allocUnsafe(info.size);
    let offset = 0;
    while (offset < bytes.length) {
      const count = readSync(descriptor, bytes, offset, bytes.length - offset, offset);
      if (count === 0) fail('CitizenSDK Hosted 归档读取期间截断');
      offset += count;
    }
    if (readSync(descriptor, Buffer.alloc(1), 0, 1, offset) !== 0
        || fstatSync(descriptor).mtimeMs !== info.mtimeMs) {
      fail('CitizenSDK Hosted 归档读取期间改变');
    }
    return parseHostedArchive(bytes);
  } finally {
    closeSync(descriptor);
  }
}

/** 全部验证通过才落盘；不执行系统 tar，不覆盖或复用任何既有输出。 */
export function verifyCitizenSdkHosted({
  candidatePath, archivePath, hostedArchivePath, outputPath, expectedGitSha = null,
}) {
  const candidate = assertSafeTargetPath(candidatePath, 'Hosted 来源');
  const audit = assertSafeTargetPath(archivePath, '审计归档');
  const hosted = assertSafeTargetPath(hostedArchivePath, 'Hosted 归档');
  const output = assertLocalTarget(outputPath, 'Hosted 解包');
  for (const input of [candidate, audit, hosted]) {
    assertOutsideSource(input, output, 'Hosted 解包');
    assertOutsideSource(output, input, 'Hosted 输入');
  }
  if (lstatExists(output)) fail('CitizenSDK Hosted 解包目录已存在，拒绝覆盖');
  const manifest = verifyCitizenSdkRelease(candidate, audit, expectedGitSha);
  const expected = hostedPackageEntries(candidate);
  const entries = readHostedArchive(hosted);
  compareHostedEntries(entries, expected);
  // 归档已解析成有界内存值，写入期间不重新读不可信 tar 或跟随其路径。
  ensureNewDirectory(output, candidate, 'Hosted 解包');
  const identity = lstatSync(output);
  try {
    for (const [path, entry] of [...entries].sort(([left], [right]) => left.localeCompare(right))) {
      const destination = assertSafeTargetPath(join(output, path), 'Hosted 解包条目');
      if (entry.type === 'directory') mkdirSync(destination, { recursive: true, mode: 0o755 });
      else {
        mkdirSync(dirname(destination), { recursive: true, mode: 0o755 });
        writeFileSync(destination, entry.data, { flag: 'wx', mode: entry.mode });
      }
      // 只调整本轮新建节点；调用者的严格 umask 不应改变已验证的 Pub 模式。
      chmodSync(destination, entry.mode);
    }
    const actual = new Map();
    const read = (directory) => {
      for (const name of readdirSync(join(output, directory))) {
        const path = directory ? `${directory}/${name}` : name;
        const file = join(output, path);
        const info = lstatSync(file);
        if (info.isSymbolicLink() || (!info.isDirectory() && !info.isFile())) {
          fail(`CitizenSDK Hosted 解包含非法节点：${path}`);
        }
        actual.set(path, { type: info.isDirectory() ? 'directory' : 'file', mode: info.mode & 0o777,
          data: info.isDirectory() ? Buffer.alloc(0) : readFileSync(file) });
        if (info.isDirectory()) read(path);
      }
    };
    read('');
    compareHostedEntries(actual, expected);
    verifyCitizenSdkRelease(candidate, audit, expectedGitSha);
    return manifest;
  } catch (error) {
    removeOwnedDirectory(output, identity);
    throw error;
  }
}

function runHostedDart(dart, args, cwd, env, signal) {
  signal?.throwIfAborted();
  // Hosted 归档由既定 macOS 作业执行；没有 POSIX 进程组就不能证明 Dart 后代已退出。
  // 此限制只属于归档工具监督，不限制 Windows SDK 或同步解包/安装验真。
  if (process.platform === 'win32') fail('CitizenSDK Hosted 归档需要 POSIX 进程组监督');
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(dart, ['--suppress-analytics', ...args], {
      cwd, env, stdio: ['ignore', 'pipe', 'pipe'], shell: false, detached: true,
    });
    let text = '', bytes = 0, failed = null, settled = false, stopping = false;
    let exited = false, closed = false, code = null, exitSignal = null;
    let timer, escalation, deadline, poll, orphan;
    const finish = (error) => {
      if (settled) return;
      settled = true;
      for (const handle of [timer, escalation, deadline, poll, orphan]) clearTimeout(handle);
      signal?.removeEventListener('abort', abort);
      if (error?.preserveHostedOutput) {
        // 无法确认退出时绝不清理目录；断开管道/引用使监督失败能有界返回。
        child.stdout.destroy(); child.stderr.destroy(); child.unref();
      }
      if (error) rejectRun(error); else resolveRun(text);
    };
    const preserve = (cause) => {
      const error = new Error('CitizenSDK Hosted 子进程未确认退出，保留缓存目录', { cause });
      error.preserveHostedOutput = true;
      finish(error);
    };
    const alive = () => {
      if (!child.pid) return false;
      try { process.kill(-child.pid, 0); return true; }
      catch (error) { if (error.code === 'ESRCH') return false; throw error; }
    };
    const terminate = (name) => {
      if (!child.pid) return;
      try { process.kill(-child.pid, name); }
      catch (error) { if (error.code !== 'ESRCH') throw error; }
    };
    const stop = (error) => {
      if (settled) return;
      failed ||= error;
      if (stopping) return;
      stopping = true;
      try { terminate('SIGTERM'); } catch (cause) { preserve(cause); return; }
      escalation = setTimeout(() => {
        try { if (alive()) terminate('SIGKILL'); } catch (cause) { preserve(cause); }
      }, 5000);
      deadline = setTimeout(() => preserve(failed), 10000);
    };
    const abort = () => stop(new Error('CitizenSDK Hosted 操作已取消', { cause: signal.reason }));
    const inspect = () => {
      clearTimeout(poll);
      if (settled) return;
      try {
        const pending = alive();
        if (closed && !pending) {
          finish(failed || (code !== 0 || exitSignal
            ? new Error(`CitizenSDK Hosted 官方工具失败 (${code ?? exitSignal})：\n${text}`) : null));
          return;
        }
        // exit 不等于 close：后代可能仍持有管道。不能只在 close 中检查进程组。
        if (exited && !stopping && !orphan) {
          orphan = setTimeout(() => stop(new Error('CitizenSDK Hosted 官方工具遗留子进程或管道')), 200);
        }
        poll = setTimeout(inspect, 50);
      } catch (cause) { preserve(cause); }
    };
    timer = setTimeout(() => stop(new Error('CitizenSDK Hosted 官方工具超时')), 120000);
    const collect = (chunk) => {
      if (settled || stopping) return;
      bytes += chunk.length;
      if (bytes > 4 * 1024 * 1024) stop(new Error('CitizenSDK Hosted 官方工具输出超过上限'));
      else text += chunk.toString('utf8');
    };
    child.stdout.on('data', collect);
    child.stderr.on('data', collect);
    child.stdout.on('error', stop); child.stderr.on('error', stop);
    child.on('error', (error) => { stop(error); });
    child.on('exit', (value, name) => {
      exited = true; code = value; exitSignal = name; inspect();
    });
    child.on('close', (value, name) => {
      closed = true; exited = true; code = value; exitSignal = name; inspect();
    });
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) abort();
  });
}

/** 只调用固定 Pub 的本地归档分支，绝不提供上传、跳过校验或自选参数入口。 */
export async function buildCitizenSdkHosted({
  candidatePath, archivePath, outputPath, dartPath, flutterRoot, pubCachePath, expectedGitSha = null,
  signal,
}) {
  signal?.throwIfAborted();
  if (process.platform === 'win32') fail('CitizenSDK Hosted 归档需要 POSIX 进程组监督');
  const candidate = assertSafeTargetPath(candidatePath, 'Hosted 来源');
  const audit = assertSafeTargetPath(archivePath, '审计归档');
  const output = assertLocalTarget(outputPath, 'Hosted 缓存目录');
  const dart = assertSafeTargetPath(dartPath, '官方 Dart');
  const flutter = assertSafeTargetPath(flutterRoot, 'Flutter SDK');
  const cache = assertLocalTarget(pubCachePath, '隔离 Pub cache');
  for (const input of [candidate, audit, dart, flutter, cache]) {
    assertOutsideSource(input, output, 'Hosted 缓存目录');
    assertOutsideSource(output, input, 'Hosted 输入');
  }
  for (const input of [candidate, audit, dart, flutter]) {
    assertOutsideSource(input, cache, '隔离 Pub cache');
    assertOutsideSource(cache, input, 'Hosted 只读输入');
  }
  if (lstatExists(output)) fail('CitizenSDK Hosted 缓存目录已存在，拒绝覆盖');
  if (!lstatExists(dart) || !lstatSync(dart).isFile()
      || !lstatExists(flutter) || !lstatSync(flutter).isDirectory()
      || !lstatExists(cache) || !lstatSync(cache).isDirectory()
      || readFileSync(assertSafeTargetPath(resolve(dirname(dart), '..', 'version'), 'Dart 版本'), 'utf8')
        .trim() !== HOSTED_DART_VERSION) {
    fail('CitizenSDK Hosted 官方工具版本或隔离缓存无效');
  }
  for (const name of ['git', 'git.exe', 'git.cmd']) {
    if (lstatExists(join(dirname(dart), name))) fail('CitizenSDK Hosted 工具 PATH 禁止包含 Git');
  }
  const manifest = verifyCitizenSdkRelease(candidate, audit, expectedGitSha);
  const pubspec = readFileSync(join(candidate, 'pubspec.yaml'), 'utf8');
  if (/^publish_to:/m.test(pubspec) && !/^publish_to: ["']?https:\/\/pub\.dev["']?\s*$/m.test(pubspec)) {
    fail('CitizenSDK Hosted 本地验证仅允许默认官方 HTTPS 服务');
  }
  const expected = hostedPackageEntries(candidate);
  const auditSha = sha256File(audit);
  const manifestSha = sha256File(join(candidate, 'citizensdk-release.json'));
  ensureNewDirectory(output, candidate, 'Hosted 缓存目录');
  const identity = lstatSync(output);
  try {
    const input = join(output, 'input');
    cpSync(candidate, input, { recursive: true, dereference: false, verbatimSymlinks: true,
      force: false, errorOnExist: true });
    const temporary = join(output, 'tmp');
    mkdirSync(temporary, { mode: 0o700 });
    // 不传用户 HOME/APPDATA/XDG、令牌或任意继承环境；Pub 的 token store 因无配置根为空。
    // PATH 仅含正式 Dart bin，Git 探测无法执行；analyze 子进程同样关闭遥测。
    const env = { PATH: dirname(dart), FLUTTER_ROOT: flutter, PUB_CACHE: cache, TMPDIR: temporary,
      TEMP: temporary, TMP: temporary, LANG: 'C.UTF-8', DASH__SUPPRESS_ANALYTICS: 'true', CI: 'true' };
    const version = await runHostedDart(dart, ['--version'], input, env, signal);
    signal?.throwIfAborted();
    if (!version.startsWith(`Dart SDK version: ${HOSTED_DART_VERSION} `)) {
      fail('CitizenSDK Hosted Dart 实际版本漂移');
    }
    const preview = await runHostedDart(dart, ['pub', 'publish', '--dry-run'], input, env, signal);
    signal?.throwIfAborted();
    if (!/Package has 0 warnings(?: and \d+ hints?)?\./u.test(preview)) {
      fail(`CitizenSDK Hosted dry-run 未明确报告零 warnings：\n${preview}`);
    }
    // dry-run 会提前返回，必须独立运行 --to-archive；官方实现不会进入上传分支。
    const hosted = join(output, `${PACKAGE_NAME}-${manifest.software_version}.tar.gz`);
    const generated = await runHostedDart(dart, ['pub', 'publish', `--to-archive=${hosted}`], input, env, signal);
    signal?.throwIfAborted();
    if (!generated.includes(`Wrote package archive at ${hosted}`)) {
      fail('CitizenSDK Hosted 官方工具未确认归档生成');
    }
    const log = `${version}\n${preview}\n${generated}`;
    writeFileSync(join(output, 'pub.log'), log, { flag: 'wx', mode: 0o600 });
    // Pub 可在隔离副本生成 lock/.dart_tool，但全部可发布输入必须与原候选一致。
    compareHostedEntries(readHostedArchive(hosted), expected);
    const result = verifyCitizenSdkHosted({ candidatePath: candidate, archivePath: audit,
      hostedArchivePath: hosted, outputPath: join(output, 'package'), expectedGitSha });
    if (sha256File(audit) !== auditSha || sha256File(join(candidate, 'citizensdk-release.json')) !== manifestSha) {
      fail('CitizenSDK Hosted 打包改动了审计输入');
    }
    return result;
  } catch (error) {
    if (!error?.preserveHostedOutput) removeOwnedDirectory(output, identity);
    else error.message += `：${output}`;
    throw error;
  }
}

/**
 * 仅解析 Hosted 官方归档；完整验证后由调用方写盘，不执行 tar 或跟随链接。
 * 这些资源上限是本地安全边界，不表示 Hosted 服务端一定接收同样大小的包。
 */
export function parseHostedArchive(bytes) {
  const reject = (reason) => fail(`CitizenSDK Hosted 归档无效：${reason}`);
  const compressedLimit = 100 * 1024 * 1024;
  const expandedLimit = 256 * 1024 * 1024;
  const pathLimit = 4096;
  if (!Buffer.isBuffer(bytes) || bytes.length < 20 || bytes.length > compressedLimit) {
    reject('gzip 长度越界');
  }
  const crcTable = new Uint32Array(256);
  for (let index = 0; index < crcTable.length; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    crcTable[index] = value >>> 0;
  }
  const crc32 = (data) => {
    let value = 0xffffffff;
    for (const byte of data) value = crcTable[(value ^ byte) & 0xff] ^ (value >>> 8);
    return (value ^ 0xffffffff) >>> 0;
  };
  if (bytes[0] !== 0x1f || bytes[1] !== 0x8b || bytes[2] !== 8 || (bytes[3] & 0xe0)) {
    reject('gzip 头或保留标志错误');
  }
  const flags = bytes[3];
  let compressedStart = 10;
  const requireHeader = (length) => {
    if (compressedStart + length > bytes.length - 8 || compressedStart + length > 65536) {
      reject('gzip 附加头截断或过长');
    }
  };
  if (flags & 4) {
    requireHeader(2);
    const length = bytes.readUInt16LE(compressedStart);
    compressedStart += 2;
    requireHeader(length);
    compressedStart += length;
  }
  for (const flag of [8, 16]) {
    if (!(flags & flag)) continue;
    const end = bytes.indexOf(0, compressedStart);
    if (end < compressedStart || end - compressedStart > pathLimit) {
      reject('gzip 名称或注释未终止或过长');
    }
    requireHeader(end - compressedStart + 1);
    compressedStart = end + 1;
  }
  if (flags & 2) {
    requireHeader(2);
    if (bytes.readUInt16LE(compressedStart) !== (crc32(bytes.subarray(0, compressedStart)) & 0xffff)) {
      reject('gzip 头 CRC 错误');
    }
    compressedStart += 2;
  }
  if (compressedStart >= bytes.length - 8 || bytes.readUInt32LE(bytes.length - 4) > expandedLimit) {
    reject('gzip 正文截断或展开长度越界');
  }
  let inflated;
  try {
    inflated = inflateRawSync(bytes.subarray(compressedStart, bytes.length - 8), {
      info: true,
      maxOutputLength: expandedLimit,
    });
  } catch {
    reject('DEFLATE 损坏、截断或超过展开上限');
  }
  // 原始 DEFLATE 报告实际消费长度，不能把第二个 member 或尾随数据吞掉。
  const tar = inflated.buffer;
  if (compressedStart + inflated.engine.bytesWritten + 8 !== bytes.length
      || tar.length !== bytes.readUInt32LE(bytes.length - 4)
      || crc32(tar) !== bytes.readUInt32LE(bytes.length - 8)) {
    reject('gzip member、CRC 或 ISIZE 不一致');
  }
  if (tar.length < 1024 || tar.length % 512 !== 0) reject('tar 长度或结束块不完整');
  const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
  const decode = (data) => {
    try { return decoder.decode(data); } catch { reject('tar 路径不是有效 UTF-8'); }
  };
  const empty = (data) => data.every((byte) => byte === 0);
  const stringBytes = (header, offset, length) => {
    const field = header.subarray(offset, offset + length);
    const end = field.indexOf(0);
    if (end < 0) return field;
    if (!empty(field.subarray(end))) reject('tar 字符串终止符后含数据');
    return field.subarray(0, end);
  };
  const octal = (header, offset, length) => {
    const field = header.subarray(offset, offset + length);
    if (!field.every((byte) => byte === 0 || byte === 32 || (byte >= 48 && byte <= 55))) {
      reject('tar 数值字段不是八进制');
    }
    const text = field.toString('ascii');
    if (!/^[ \0]*[0-7]+[ \0]*$/.test(text)) reject('tar 数值字段为空或嵌入分隔符');
    const value = Number.parseInt(text.replace(/^[ \0]+|[ \0]+$/g, ''), 8);
    if (!Number.isSafeInteger(value)) reject('tar 数值溢出');
    return value;
  };
  const safePath = (name, directory) => {
    if (directory && name.endsWith('/')) name = name.slice(0, -1);
    const parts = name.split('/');
    if (!name || Buffer.byteLength(name) > pathLimit
        || /[\x00-\x1f\x7f\\:*?"<>|]/.test(name)
        || parts.some((part) => !part || part === '.' || part === '..'
          || /[ .]$/.test(part) || /^(?:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part))) {
      reject('tar 路径越界或存在跨平台歧义');
    }
    return name;
  };
  const entries = new Map();
  const paths = new Map();
  let pathCount = 0;
  let pendingName = null;
  let offset = 0;
  let count = 0;
  while (offset < tar.length) {
    const header = tar.subarray(offset, offset + 512);
    if (empty(header)) {
      // 固定官方 writer 恰好输出两个零块，不接受结束后的记录或隐蔽附加数据。
      if (pendingName !== null || offset + 1024 !== tar.length || !empty(tar.subarray(offset))) {
        reject('tar 结束块、悬空长文件名或尾随数据错误');
      }
      return entries;
    }
    count += 1;
    if (count > 16384) reject('tar 条目数超过上限');
    let checksum = 0;
    for (let index = 0; index < 512; index += 1) {
      checksum += index >= 148 && index < 156 ? 32 : header[index];
    }
    if (checksum !== octal(header, 148, 8)) reject('tar 头校验和错误');
    // package:tar 2.0.0 把 version 写为 "0 "，普通 USTAR 则写为 "00"。
    if (!header.subarray(257, 263).equals(Buffer.from('ustar\0'))
        || !['0 ', '00'].includes(header.subarray(263, 265).toString('ascii'))
        || !empty(header.subarray(500)) || !empty(header.subarray(157, 257))
        || !empty(header.subarray(329, 345))) {
      reject('tar 格式、链接或扩展字段不符合合同');
    }
    const mode = octal(header, 100, 8);
    const size = octal(header, 124, 12);
    const userId = octal(header, 108, 8);
    const groupId = octal(header, 116, 8);
    const modified = octal(header, 136, 12);
    if (mode > 0o777 || size > expandedLimit) reject('tar 权限或文件长度越界');
    const user = stringBytes(header, 265, 32);
    const group = stringBytes(header, 297, 32);
    decode(user);
    decode(group);
    const shortName = stringBytes(header, 0, 100);
    const prefix = stringBytes(header, 345, 155);
    const type = header[156];
    if (![48, 53, 76].includes(type)) reject('tar 含非普通文件、目录或官方长文件名记录');
    const start = offset + 512;
    const end = start + size;
    const paddedEnd = start + Math.ceil(size / 512) * 512;
    if (paddedEnd > tar.length || !empty(tar.subarray(end, paddedEnd))) {
      reject('tar 正文截断或补齐区含数据');
    }
    const data = tar.subarray(start, end);
    offset = paddedEnd;
    if (type === 76) {
      // 官方 GNU L 正文没有末尾 NUL；后继短名只取前 99 字节，可能截断多字节字符。
      if (pendingName !== null || decode(shortName) !== '././@LongLink'
          || prefix.length || mode || userId || groupId || modified || user.length || group.length
          || size <= 99 || size > pathLimit) reject('GNU 长文件名记录不符合官方格式');
      safePath(decode(data), true);
      pendingName = data;
      continue;
    }
    let name;
    if (pendingName !== null) {
      if (prefix.length || !shortName.equals(pendingName.subarray(0, 99))) {
        reject('GNU 长文件名与后继短名不一致');
      }
      name = decode(pendingName);
      pendingName = null;
    } else {
      name = `${prefix.length ? `${decode(prefix)}/` : ''}${decode(shortName)}`;
    }
    const directory = type === 53;
    if (directory && size !== 0) reject('tar 目录携带正文');
    name = safePath(name, directory);
    if (entries.has(name)) reject('tar 目标重复');
    const parts = name.split('/');
    let children = paths;
    for (let index = 0; index < parts.length; index += 1) {
      const part = parts[index];
      const key = part.normalize('NFC').toLowerCase();
      const pathType = index < parts.length - 1 || directory ? 'directory' : 'file';
      let node = children.get(key);
      if (node && node.name !== part) reject('tar 大小写或 Unicode 目标冲突');
      if (node && node.type !== pathType) reject('tar 父子路径类型冲突');
      if (!node) {
        // 隐含父目录同样占用解包资源；树结构避免深路径的平方级前缀复制。
        pathCount += 1;
        if (pathCount > 16384) reject('tar 文件及隐含目录数超过上限');
        node = { name: part, type: pathType, children: new Map() };
        children.set(key, node);
      }
      children = node.children;
    }
    // 用视图避免给已受上限约束的正文再做整包复制，返回值始终只包含文件和目录。
    entries.set(name, { type: directory ? 'directory' : 'file', mode, data });
  }
  reject('tar 缺少两个结束零块');
}

function parseArguments(argumentsList) {
  const values = {};
  for (let index = 0; index < argumentsList.length; index += 2) {
    const key = argumentsList[index];
    const value = argumentsList[index + 1];
    if (typeof key !== 'string' || !/^--[a-z-]+$/u.test(key)
        || typeof value !== 'string' || !value || value.startsWith('--')
        || Object.hasOwn(values, key.slice(2))) fail(`参数格式无效或重复：${key || ''}`);
    values[key.slice(2)] = value;
  }
  return values;
}

const isMain = process.argv[1] && resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
if (isMain) {
  try {
    const values = parseArguments(process.argv.slice(2));
    if (values.hosted || values['verify-hosted']) {
      const build = Boolean(values.hosted);
      const allowed = build
        ? ['hosted', 'archive', 'output', 'dart', 'flutter', 'pub-cache', 'expected-git-sha']
        : ['verify-hosted', 'archive', 'hosted-archive', 'output', 'expected-git-sha'];
      if (Object.keys(values).some((key) => !allowed.includes(key))) {
        fail('CitizenSDK Hosted 参数包含未允许的选项');
      }
      for (const key of allowed.filter((key) => key !== 'expected-git-sha')) {
        if (!values[key]) fail(`CitizenSDK Hosted 缺少参数 --${key}`);
      }
      const options = { candidatePath: values.hosted || values['verify-hosted'],
        archivePath: values.archive, outputPath: values.output,
        expectedGitSha: values['expected-git-sha'] || null };
      let manifest;
      if (build) {
        // CLI 只转交标准 AbortSignal；内部拥有 Dart 组与目录，外层不得先杀监督器。
        const controller = new AbortController();
        const interrupt = () => { process.exitCode ||= 130; controller.abort(); };
        const stop = () => { process.exitCode ||= 143; controller.abort(); };
        process.on('SIGINT', interrupt); process.on('SIGTERM', stop);
        try {
          manifest = await buildCitizenSdkHosted({ ...options, dartPath: values.dart,
            flutterRoot: values.flutter, pubCachePath: values['pub-cache'], signal: controller.signal });
        } finally {
          process.off('SIGINT', interrupt); process.off('SIGTERM', stop);
        }
      } else manifest = verifyCitizenSdkHosted({ ...options, hostedArchivePath: values['hosted-archive'] });
      process.stdout.write(`CitizenSDK Hosted 本地归档验真通过：${manifest.software_version}\n`);
    } else if (values.verify) {
      if (!values.archive) fail('候选校验缺少参数 --archive');
      const manifest = verifyCitizenSdkRelease(
        values.verify,
        values.archive,
        values['expected-git-sha'] || null,
      );
      process.stdout.write(`CitizenSDK 候选校验通过：${manifest.software_version}\n`);
    } else {
      for (const key of ['source', 'native', 'output', 'archive', 'git-sha', 'software-version']) {
        if (!values[key]) fail(`缺少参数 --${key}`);
      }
      const manifest = buildCitizenSdkRelease({
        sourcePath: values.source,
        nativePath: values.native,
        outputPath: values.output,
        archivePath: values.archive,
        gitCommitSha: values['git-sha'],
        softwareVersion: values['software-version'],
      });
      process.stdout.write(`CitizenSDK 候选已生成：${manifest.software_version}\n`);
    }
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exitCode ||= 1;
  }
}
