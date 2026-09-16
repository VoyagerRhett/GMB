# CitizenSDK Apple tests

第 9.2 步新增 `citizen_sdk_flutter_consumer.dart`，供唯一构建器在真实 Hosted 解包包上
编译标准 macOS Flutter Release 工程。消费者只使用公开 CitizenSdk，覆盖初始化、能力、
空钱包、typed error、启停/有序事件、关闭幂等和重开；不创建钱包、签名或提交交易。
宿主必须先证明 Foundation 状态目录位于中央独占工作区且系统 sandbox 已生效，才能注册
插件并进入 Dart 消费者。工具/编译与真实运行分别记录，实施进度见中央任务卡第 35 节；
下文既有 Swift/源码测试的通过记录不能代替这一项。
当前安装验收停在 Xcode Swift Package 解析的目录权限问题；Foundation 诊断程序不是
SDK 消费者。归档、构建与最终运行分别隔离，失败日志保留，不能把前序通过当作完整运行。
用户已确认第 9.2 步按本机原生编译及验收实现收尾；实际 Flutter macOS 安装运行移交
第 10 步 GitHub 统一 CI，仍是必须通过的独立验收，不得用本机开发完成替代运行结果。

The canonical central Apple candidate harness runs these tests in two modes without
writing build state into this source tree. Product workflow integration is
a later step and must not be claimed until that workflow actually invokes the
harness:

1. Public API/consumer tests link the injected `CitizenSDK.xcframework`, which
   is also the only binary consumed by SwiftPM and CocoaPods.
2. Source-internal contract tests compile the approved `Sources/CitizenSDK`
   and `Sources/CitizenSDKFlutter` files into temporary testable targets with
   `ENABLE_TESTABILITY=YES`. This is required for deterministic SQLite failure,
   callback ownership, vault-operation and Flutter-session negative tests;
   `@testable import` cannot inspect a library-evolution binary built without
   testing enabled.

Source-internal lifecycle fixtures fault-inject callback installation,
capability subscription/unsubscription, callback clear, Flutter-open cleanup,
detach recovery and destroy. They prove monotonic phase retry, no early release
of HostBridge or the ABI +1 owner at any failed stage, immediate HostBridge
release plus exactly-once ABI +1 release after destroy,
and eventual supervised recovery without requiring a deliberately corrupted C
Core binary. Recovery-policy fixtures also prove that a delayed Swift lifecycle
event cannot override the authoritative C lifecycle and that partial teardown
never issues another lifecycle/control call.

Flutter-detach fixtures exercise the production teardown helpers directly. They
prove exactly-once handler revocation in method-channel, event-channel, epoch
order; permanent rejection of queued event generations; cancellation of every
unfinished operation before awaiting any one completion; and continued closure
of later sessions when one session must be transferred to the Core supervisor.
Registration publishes the plugin instance on both Apple platforms. iOS then
delivers Flutter's official `detachFromEngine(for:)` callback. The current
FlutterMacOS registrar has `publish` but declares no engine-detach callback, so a
macOS native host may invoke the same idempotent entry point explicitly and
`deinit` remains the final engine-shutdown fallback.

Both modes use the same C header, Rust Core archive, Swift sources and assets as
the release candidate. The temporary Xcode project, test databases, DerivedData
and result bundles belong only under 调用方's central CitizenSDK work
directory. Secure Enclave creation, biometric prompts and Keychain device-only
semantics additionally require real supported Apple hardware and are never
declared proven by simulator-only execution.

The current local execution built the one `CitizenSDK.xcframework` with the iOS
device and simulator variants plus macOS, all with Apple machine architecture
value `arm64`, and compiled both iOS test bundles. This Mac has no installed Simulator
runtime, so no iOS XCTest execution is claimed. On macOS, 50 CitizenSDK Core
and 22 Flutter-adapter XCTest cases ran with zero failures; one
real-hardware-only case was skipped. The final normal
and supervisor consumer smoke processes both passed. No physical Apple mobile
device was available, so Secure Enclave, biometric and device-only Keychain
behavior remains a separate device-validation requirement. No remote CI,
formal Release, Hosted upload or Git operation was run, and the product flow has
not yet integrated this harness.
