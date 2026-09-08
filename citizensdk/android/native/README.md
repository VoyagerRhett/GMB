# CitizenSDK Android native distribution

当前按 wallet、signing、chain、transactions、history、qr 六模块装配同一 Rust Core，
默认 full。先调用统一模块校验，再仅创建所选服务的资源；chain 未选不加载链资产或创建链数据库，
history 未选不初始化历史，wallet/signing 才使用配套 secure store/Vault。SigningService
仅使用同宿主已有 SDK 安全账户归属资料，首次 provision 仍须钱包安全流程，秘密不导出。
纯验签无需实例、钱包、金库或链；Flutter 五端共用 36 方法，open 仅 `[1, modules]`，
`verifySignature` 请求仅 `[1, accountId, signature, payload]`、响应仅 `[1, bool]`，
不建立 session 或事件订阅。运行期模块选择不裁剪现有正式 full 包及链资产。
JNI 中的十个 QR 入口只是同一 Rust `QR_V1` 与 ZXing-C++ 3.1.1 窄包装的类型化投影，
不调用 Android 第二扫码引擎。
本次第 2 步仅更新源码、注释、合同和测试，尚未执行新的真实构建、平台测试或硬件验收；下文旧分步运行记录保留为历史证据，不代表本次变更已验证。

第 3 步增加 `getGenesisHash()` 与 `getAccountBalances(accountIds)`，仅依赖 chain。
创世哈希不要求启动；批量结果复用现有余额值，保持账户顺序与重复项，空列表仍由 Core 校验状态。
JNI 只负责参数和结果传输，不另行计算余额。
`viewAccountPrivateKey(activity, accountId)` 仅属于 wallet，返回 `CitizenSdkOperation<Unit>`。
SDK 自有 Activity 通过私有四操作接收短期显示借用并复制进可擦字符缓冲，不返回秘密。
公开完成必须等待 UI 清除、Activity 销毁和 Core 请求真实排空；后台或销毁后不恢复显示。
私有声明仅从构建工作目录导入。新的平台运行态及硬件安全验收仍未完成。

This Gradle library is the official Android projection of the single
CitizenSDK Rust Core. It produces the Java/Kotlin AAR and the private JNI
bridge. The Flutter plugin compiles the same Kotlin facade sources and stages
the same two native-library bytes; it must not embed this AAR.

原生 Gradle 模块与 Flutter 插件声明同一组 AndroidX 依赖。直接使用裸 AAR 的宿主须
同时声明 `build.gradle` 中的 biometric、core-ktx、fragment-ktx 及 CameraX
core/camera2/lifecycle；`files("citizensdk.aar")` 本身不携带 Maven 传递依赖信息。
相机权限与非导出扫描 Activity 随 AAR manifest 合并，不需要宿主实现扫描或签名界面。

The module accepts one external Android ABI `arm64-v8a` Core leaf through
`CITIZENSDK_ANDROID_CORE_DIR`. That `arm64-v8a` directory must contain
`libcitizensdk.so`. CMake builds `libcitizensdk_jni.so` and links that one Core;
neither layer exports a second `citizensdk_*` implementation.
The JNI library exports exactly `JNI_OnLoad@@CITIZENSDK_JNI_1.0`; every Java
method is registered from that entry and no name-based JNI method is public.
The shared build entry strips the staged Core once with the pinned NDK before
Gradle runs, so AGP's release packaging preserves the exact standalone/AAR
Core byte identity checked after assembly.
The Core and JNI ELF identities are respectively `libcitizensdk.so` and
`libcitizensdk_jni.so`. JNI must record the Core by SONAME exactly once; an
absolute or relative build-host path in any `DT_NEEDED` entry fails packaging.

`CITIZENSDK_ANDROID_BUILD_DIR` is the absolute shared Android build root. This
module writes only below `<root>/native`; the Flutter host uses `<root>/flutter`.
The release AAR therefore has the stable Gradle location
`<root>/native/outputs/aar/native-release.aar`.
On the maintained workstation it must be below
`/Users/rhett/TATA/tataconsole/work/gmb/citizensdk`; GitHub Actions may use an absolute runner
directory outside the source checkout. Never leave a
`build`, `.gradle`, CMake, binary, database or test artifact in this source
directory.

## Security boundary

- Public and secure records live in separate databases under
  `Context.noBackupFilesDir` and every revisioned write is an exact transaction.
- StrongBox is preferred and hardware TEE is the only fallback. Software keys
  and device-credential authentication are not accepted.
- DEK unwrap writes into a Rust-owned direct buffer after per-use
  `BIOMETRIC_STRONG`; it never becomes a Kotlin `ByteArray`.
- Mnemonics are accepted or displayed only by the SDK-owned, non-exported,
  `FLAG_SECURE` wallet flow. Public Kotlin/Java and Flutter APIs never carry a
  mnemonic, password, prepared-wallet handle, native handle or result handle.
- The secure Activity owns a registry of every mnemonic/password `EditText`.
  Back, cancellation, configuration change and external teardown overwrite and
  clear each mutable `Editable` before dropping the View references.
- Mnemonic and password UTF-8 inputs are bounded to the Core contract's 1024
  bytes before proportional allocation and before JNI. JNI owns each temporary
  copy in an always-zeroizing scope, including partial import/add failures.
- Kotlin-only wallet-flow bridges are emitted `ACC_SYNTHETIC`, while native and
  prepared-wallet constructors are private. Release API validation must run a
  `classes.jar`/`javap` allowlist and reject public Java-source methods whose
  descriptors contain mnemonic/password buffers, prepared tokens or Core
  request/result identities.
- Android application code shares one process and UID with the SDK. The SDK
  blocks accidental Java-source access and never returns secrets, but it cannot
  defend against a deliberately hostile host using reflection, memory
  instrumentation or a modified AAR; such a host is outside the trust boundary.
- Hardware-vault readiness requires both device-backed BIOMETRIC_STRONG support
  and a currently RESUMED `FragmentActivity`. Activity generations restore the
  prior live host after the secure wallet flow, and the flow callback waits for
  the resulting capability refresh before an immediate sign or transfer.
- The coordinator owns an accepted create-prepare future until it transfers or
  releases the prepared handle. Once Core accepts create-commit, import or
  add-accounts, Back, engine detach and Activity recreation wait for that exact
  future and publish its real Completed/Failed outcome; the UI never reports
  Cancelled while storage keeps mutating.
- A rejected native prepared-handle release rolls Kotlin ownership back for an
  exact retry. The Activity retries during teardown and the coordinator retries
  before flow completion. A process-level cleanup supervisor then retains both
  owner and SDK across Flutter flow completion and retries with a bounded
  exponential delay until release succeeds or Core destruction makes cleanup
  terminal; the last owner is never delegated to a future explicit close. A
  successful SDK Core destroy explicitly resolves retained owners for that
  exact SDK identity. `INVALID_HANDLE` from an otherwise live bridge is not
  guessed to mean that secret destruction succeeded.
- Public `CitizenSdk.close()` returns `BUSY` while this SDK still owns an active
  wallet flow. Callers must cancel its coordinator and wait for the terminal
  callback before closing; therefore close cannot return while a secure
  Activity, recovery-phrase buffer or secret input remains SDK-owned. A
  cleanup-supervisor-only owner is already past Activity teardown and may be
  resolved by the exact Core destroy described above.
- Activity registry consumption is a gated claim. Cancellation between
  `consume` and `attach` keeps the close-gate entry and publishes a terminal to
  the eventual Activity; attach after completion immediately finishes without
  constructing any secret UI.
- Secret `EditText` values use a conservative 341 UTF-16-code-unit UI limit
  beneath Core's exact 1024-byte UTF-8 limit. Every terminal and destruction
  path overwrites them in fixed 64-code-unit blocks before clearing the view;
  wipe memory never grows with pasted input.

## Result and concurrency contracts

- JNI result kind 12 is a complete wallet profile; kind 13 is only the exact
  list of accounts returned by add-accounts. Set-active and rename return Core's
  atomic profile directly. Add verifies every returned index and account ID,
  then reads its complete profile while holding the process mutation gate.
- Delete-account, delete-wallet and cleanup-reconciliation also perform their
  resulting profile read inside that same gate. Bindings must encode the profile
  returned by the facade and must not issue a second `getWalletProfile` query.
- JNI text is strict UTF-8 and all malformed envelopes, unknown error codes and
  unsupported result kinds fail with stable `INTEGRITY` semantics.
- Sign payloads are capped at 16 MiB and history batches at 1990 account IDs in
  the facade before clone/flatten/JNI. Add-account indices are capped at 1989
  unique values and transfer remarks at 99 UTF-8 bytes before clone/JNI, with
  the same JNI-side bounds. Raw account names are capped at 128 UTF-16 code
  units before trim/scalar scans, and u128 decimal input at 39 digits before
  regex/`BigInteger`. Both transfer entry points reject zero amount before
  request admission, biometric authentication or JNI. Empty sign payloads and
  remarks remain valid.
