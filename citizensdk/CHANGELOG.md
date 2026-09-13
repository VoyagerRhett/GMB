# Changelog

## 1.0.0 - Unreleased

- 公民软件包接入新任务第 1 步补齐通用底层合同：直接复用已收编 smoldot 的 finalized
  storage keys 分页、准确块 Runtime API 与唯一 finalized 订阅；热账户新增通用
  HKDF-SHA256 应用派生钥。Dart 钱包端口固定为 `CitizenSdkWallet`，不与独立
  CitizenWallet 产品重名。五端安全钱包窗口按 CitizenApp 创建、导入、追加账户和私钥查看
  金标统一，不向宿主返回助记词或私钥。当前闭集为 121 项 Core ABI、65 项 Flutter 方法；
  没有迁移、兼容、任意 RPC、业务模型或 `native/smoldot/pow/**` 改动。测试源码已完善，依照
  总任务门禁尚未运行编译、测试、Flutter、CI 或 Release。

- CitizenApp 接入任务第 1.10.4 步完成候选：通用 execution history 从 whole-history BLOB
  替换为 index/exact/page 查询与原子 delete/upsert/meta mutation；Android、Apple、Linux、Windows
  统一 schema v2、稳定索引和有界 incremental vacuum。旧开发库不迁移、不兼容。finalized
  订阅错误/结束会按 1/2/4/8/16/30 秒重订阅，成功复位；未改 `native/smoldot/pow/**`，未触碰
  CitizenApp/CitizenWallet，也未运行或操纵 Flutter。

- CitizenApp 接入任务第 1.10.3 步新增与业务无关的八阶段失败分类：`admission`、
  `validation`、`authentication`、`persistence`、`provider`、`verification`、
  `cancellation`、`teardown`。22 个错误码保持原数值；新增唯一只读
  `citizensdk_result_get_failure_stage`，既有结果结构、Host vtable、SQLite schema 不变。
  Dart、Android、Apple、Linux、Windows 使用固定 7 字段错误 tuple，并绑定 62 项公开 method；
  不记录或返回秘密、payload、callData、签名、extrinsic、metadata/storage 内容或本机路径。
  当前闭集为 117 项 Core ABI、62 项 Flutter 方法、3 项 QR 图像函数和 Linux/Windows 各
  17 项 Host 函数；唯一二维码协议仍为 `QR_V1`。

- CitizenApp 接入任务第 1.10.2 步关闭三项已量化资源边界：Core runtime metadata 功能上限
  继续为 64 MiB；单条 metadata 超出 8 MiB 持久记录容量时仍可读取并命中进程内 cache，只跳过
  可重建的持久 cache。四个平台在原 SQLite 写事务内以 FIFO 保留最新 64 条 runtime context。
  通用 execution history 新增 31 MiB durable weight，并在热签/冷签前只读预检、广播前 CAS
  复检；只驱逐最旧终态，绝不驱逐 Pending/InBlock。公开 API/ABI、数据库 schema、`QR_V1`、
  CitizenWallet 与定制 PoW 上游均未改变，也没有迁移或兼容逻辑。

- CitizenApp 接入任务第 1.9 步建立多消费者公开面验收：新增无业务 reference、CitizenApp
  形状、第三方旅行形状和独立 `QR_V1` signer 四类测试夹具。所有夹具只导入
  `package:citizen_sdk/citizen_sdk.dart`；业务 storage key、SCALE 事件和 RuntimeCall 编码只留在
  消费夹具。公共合同保持 116 项 Core ABI、五端 62 项 Flutter 方法和唯一 `QR_V1`，未增加
  业务 API、迁移、兼容或外部产品依赖。

- CitizenApp 接入任务第 1.8 步完成：删除 SDK 早期业务化二维码类型、编码入口和五端投影。
  `QR_V1` 仍是唯一二维码协议，只保留通用签名 request/response、账户公钥、会话绑定、
  过期/取消/单次消费和图像编解码；消费 App 自己负责收款及其它业务二维码语义。公开面现为
  116 项 Core ABI、五端 62 项 Flutter 方法；删除项不迁移、不兼容、不复用数值空洞。
  CitizenWallet 和定制 CitizenChain PoW 上游均未修改。

- CitizenApp 接入任务第 1.7 步完成：SDK 历史收敛为自身提交交易的通用 execution fact，
  CitizenApp 的目的账户、金额、备注、方向、业务事件及交易页模型归位 App 自有目录。旧业务
  历史 schema、便利交易及八项 ABI 直接由四项通用历史 ABI 替换，不迁移、不兼容、不双写；
  当步公开面为 117 项 Core ABI、五端 63 项 Flutter 方法。

- CitizenApp 接入任务第 1.6 步完成：通用交易准备现在可由统一 WalletState 原子路由到热钱包
  强认证签名或既有 `QR_V1` 冷签名，签名经同一 sr25519 实现自验后先以 typed store CAS
  持久化完整授权字节，再 submit/watch，并以 canonical finalized body 与同 index
  `System.Events` 形成唯一终态。重启只核验并重发原 signed extrinsic，不重新签名。新增 4 项
  Core ABI、3 项 Flutter 方法和 result kind 28，当前闭集为 121/64；没有 App 业务编码、迁移、
  兼容或其它协议版本，CitizenApp 与 CitizenWallet 均未修改。

- CitizenApp 接入任务第 1.5 步完成：新增产品无关的 opaque SCALE `callData` 交易准备。
  Core 在同一准确 best block 上验证 metadata outer call、读取 nonce/runtime/genesis，固定使用
  immortal era 与 tip=0，并把 signer message 和 extrinsic 模板留在一次性原生准备对象中；公开层
  只返回安全摘要和取消标识。公开面现为 117 项 Core ABI、五端 61 项 Flutter 方法。没有签名、
  广播、历史、业务 DTO、迁移、兼容或新的协议版本；CitizenApp 与 CitizenWallet 均未修改。

- CitizenApp 接入任务第 1.4 步完成：在唯一 smoldot/`VerifiedChainClient` 路径公开同步状态、
  best/finalized 链头、finalized canonical 块解析、准确块 Header/Body/Runtime、通用 storage
  单项/批量读取、finalized `System.Events` 原始字节及显式状态导入导出。所有读取绑定准确块并
  执行大小、顺序、finality 和返回类型校验；SDK 不包含任何 App 业务 key、DTO、SCALE 业务解码、
  任意 RPC、迁移或兼容逻辑。公开面现为 114 项 Core ABI、五端 59 项 Flutter 方法；本轮未修改
  CitizenApp 或 CitizenWallet。

- CitizenApp 接入任务第 1.3 步完成：新增产品无关 `SigningIntent`、raw/Substrate/domain
  三类签名变换、热钱包强认证签名与自验、冷账户外部签名会话，以及由原默认账户授权的
  默认账户 CAS 切换。`QR_V1` 只保留为可选 transport，允许任意 `uint16` opaque action，
  删除 SDK 业务 action 白名单和 payload/action 猜测。公开面现为 104 项 Core ABI、五端
  47 项 Flutter 方法；没有迁移、兼容、业务 payload 解码或 CitizenWallet 源码修改。

- CitizenApp 接入任务第 1.2 步完成：Core 新增统一 `WalletState` 与热/冷账户公开投影、
  仅公钥冷账户 AccountId/SS58 导入、带 revision 且不改变默认账户的全局重排，以及热冷统一
  改名/删除；公开面更新为 97 项 Core ABI 与五端一致的 42 项 Flutter 方法。默认账户仍只由
  全局顺序第一项表达，未导出未授权 default setter；旧钱包 v1 状态继续明确拒绝，不迁移、
  不兼容读取 CitizenApp 数据。本轮只修改 CitizenSDK，CitizenApp 与 CitizenWallet 零修改。

- 二维码作为独立可组合模块纳入 CitizenSDK：`qr=32`，完整模块集合为
  `63`。QR_V1 协议解析、签名请求会话、一次性响应消费和链调用审阅统一由
  Rust Core 实现；二维码图像识别与生成在 iOS、Android、macOS、Windows、Linux
  唯一使用 ZXing-C++ 3.1.1。公开面统一为 97 项 Core ABI 和 42 项 Flutter 方法，
  QR-only 不初始化钱包、设备金库或轻节点。二维码与签名仍是独立模块，调用方可
  单独集成或完整集成 SDK。SDK 自有扫描和扫码签名窗口接入五端；链调用签名
  复用已验证 chain metadata 与已有 signing，删除调用方时钟及外部签名拼装入口。
  本轮未修改 CitizenApp、CitizenWallet、CitizenChain
  上游，也未发布候选。

- 第 12 步 P2 修复：Android/Apple 以进程内锁和 OS 文件锁原子覆盖 generation
  tombstone 与物理 KEK；Apple 拒绝非正整数 revision，能力快照保留明确未就绪原因。
  删除交易 watch 的重复 `hash()` 名称，修复 Android Flutter 进度交错和 Apple Flutter
  非 UInt8 typed-data 接纳。恢复三份 CitizenApp byte-identical 来源，校正锁文件、许可和
  来源摘要。CI 消费构建使用已登记增量目录，Release 仍全量；Hosted 保留现场测试和原生
  双路径零写预检同步加固。不改变 C ABI、链协议、sr25519 或公开平台集合。

- 第 12 步 P1 修复：完整 signed extrinsic 与 Pending 原子保存、同参数恢复原授权；
  支持无 extrinsic index 的合法 Balances hook 流水；完成事件预留真实队列容量。
  修复 Android 生物识别主线程与关闭重入、Apple 宿主数据/金库隔离和可选空密码、
  Linux/Windows 导入参数、Linux WAL/SHM 活锁恢复及 SDK CI/Release 依赖接线。
  不改变公民链算法、签名 context、70 项 Core ABI 或产品平台集合；不代表已发布。

- 第 9.2 步完成官方 Hosted 解包包的 macOS Flutter Release 消费验收实现及本机原生编译。
  新增公开 `CitizenSdk` 消费测试，沿用唯一构建器/发布器；测试来源闭集增至 197 文件。
  归档、构建和消费者分别使用单层隔离；保留失败诊断，插件来源按目录身份核对。
  不改变平台、Core/ABI、钱包或链实现。用户确认将实际 Flutter macOS 安装运行移交
  第 10 步 GitHub 统一 CI；本机 Xcode/SwiftPM 权限失败记录保留，不改记为通过。
  本机开发验收与远程待验收范围以中央任务卡第 35 节为准。

- 第 9.1 步在唯一发布器增加官方 Pub 本地归档与完整安全解包验真。固定 Dart 3.12.2，
  单独要求 dry-run 零 warnings，再生成一个 Hosted 包；来源仍是同版审计候选，不改
  `.pubignore` 或平台集合。覆盖官方 GNU 长名、Apple 合法链接展开、完整路径/类型/
  权限/字节闭集、损坏/越界/资源上限和失败清理。本机官方工具往返使用跨平台格式夹具，
  不代表真实全平台产物、安装运行或正式发布；未执行原生编译、上传、Git 或控制台操作。

- 第 8.4 步把 Windows 官方 Flutter 注册、CitizenSdk 默认入口、21 项同版安装件与
  33 项 Hosted 运行输入一起纳入唯一 SDK。新增公开 Flutter Release 消费者，保留原有
  14+2 测试并接入六项 adapter 检查，全部成功后才导出。核心算法、Host/adapter 生产
  实现和其它平台不变；不改控制台或工作流，Windows 实际运行与正式发布仍待统一验收。

- 第 8.3 步增加独立 Windows C11/C++17 安装消费者，仅使用公开头和同版安装库。
  唯一构建器保留 14 项原生测试，核对 21 项安装闭集、来源字节与 PE 导出，消费验证全部
  通过后才导出全新目标；既有输出不覆盖。新增失败和边界回归，不改 Host/Core、平台
  列表、Dart 默认入口、Hosted 或候选。Windows 实际运行仍留统一 GitHub CI/Release。

- 第 8.2.1 步修正唯一发布器的本机目录门禁，仅接纳中央 `target/GMB/citizensdk/SDK`
  与 `target/.work/GMB/citizensdk/SDK` 的严格子路径，拒绝永久根自身、越界与链接。
  新增执行真实生产函数的路径矩阵回归，保留完整打包测试；GitHub 分支、候选内容、
  原生构建器和平台实现不变。

- 第 8.2 步补齐 Windows Flutter adapter 源码，使用官方 StandardMethodCodec、固定双通道与
  22 方法，连接同版已安装 Host/Core；钱包秘密不进入 Flutter 消息。Windows 宿主需一次
  显式声明稳定的 `CITIZENSDK_APPLICATION_ID`，构建拒绝缺失或非法身份。会话保留 Host
  关闭重试与原生 UI 退休所有权，新增六项 adapter 测试源码；本步不修改 Dart 默认平台、
  pubspec、原生构建器或 Windows 候选。Windows 编译、测试和实际安装消费者仍须后续统一
  GitHub CI/Release 验证，不能把本机 macOS 检查视为 Windows 运行通过。

- 第 7.4 步将 LinuxARM/LinuxAMD 的 26 项合并安装投影、候选 manifest、官方 `linux`
  plugin 注册与默认 `CitizenSdk.open()` 原子纳入同一 SDK 版本。Hosted 精确保留 38 项 Linux
  运行输入，排除 Host 私有源码；真实 Flutter 消费者改用公开入口，不注入内部 platform，
  不临时修改 pubspec 或补 runner RPATH。ABI、22 方法及 Core 实现不变。Linux 实际编译、
  C/C++/Flutter、GTK/TPM 与许可证证据仍待后续统一 GitHub CI/Release，不宣称已运行或发布。

- 第 7.3 步增加 Linux 安装闭集、已安装 C/C++ 消费者和真实 Flutter Release 通道消费者的
  装配源码，全部沿用唯一原生构建入口。安装验收覆盖字节、版本、平台、ELF/ABI/GLIBC；
  消费者覆盖真实异步完成、启停和关闭所有权。当前开发以本机 macOS 编译通过为验收标准，
  不再等待用户提供 Linux/TPM 环境；2026-09-03 已通过 `abi-host` 与 `apple`，包含 Core/C ABI、
  Swift/Flutter 原生绑定和单一 XCFramework 构建验证，本轮未改生产实现。跨平台构建与功能验证
  后续统一进入同产品、同版本的 GitHub CI 增量缓存与 Release 全量构建，仍只交付一个
  CitizenSDK Release。LinuxARM/LinuxAMD 及实体 TPM 尚无本轮运行结果；未改变公开平台、
  Core/Host 实现、移动端、控制台或正式发布流程。

- Added the Step 7.2 source-only Linux Flutter adapter. It maps the same fixed
  22-method `citizen/sdk/core/v1` and `citizen/sdk/events/v1` tuple contract
  onto the installed same-version Linux Host/Core pair, preserves embedded NUL
  bytes in standard-codec strings, confines Flutter values to the GTK thread,
  and keeps wallet secrets inside the existing native GTK/Host/Core path. Its
  CMake, codec, session, wallet-flow, environment, plugin, shutdown, and secret
  boundary tests were source contracts only: that step did not register Linux
  in the public package or Release manifest. Actual LinuxARM/LinuxAMD
  validation belongs to the later unified GitHub CI/Release matrix for the
  same SDK version; local macOS acceptance does not establish Linux support.
- Added the Step 7.1 source-only Linux host projection shared by LinuxARM and
  LinuxAMD: typed public/secure SQLite stores, a TPM 2.0 KEK/DEK vault,
  SDK-owned wallet-flow primitives, a C/C++ host API, and native contract-test
  sources. This step did not build or run those tests, inject Linux shared
  libraries, register the Flutter plugin, or add Linux to the release manifest;
  Linux support is therefore not yet delivered. The test targets explicitly
  keep assertions enabled under the Release build configuration. Linux state
  sources require effective-UID ownership, one-link DB/journal/WAL/SHM files,
  an openat-backed SQLite VFS, exact schema/PRAGMA validation, and a durable
  commit point that cannot report failure after a successful commit. Host
  admission leases, lossless 65+ synchronous completions, parent-destroy UI
  retirement, generation-conditional Vault writes, post-prompt retirement
  checks, exact TPM child templates, owner/hierarchy/DA-state checks, and exact
  `Esys_TestParms` probes are part of the same source contract.
- Completed the Step 7.1 source review follow-up: fixed strict C++ pointer
  conversions and GNU namespace-macro collisions, classified TPM response
  layers using official TPM2-TSS definitions, and added regression-test
  sources. Provider service leases no longer hold the Host mutex while GTK
  authentication waits; explicit destroy returns `BUSY` for concurrent API
  leases, and abandonment hands the complete graph to a lease-aware
  supervisor. Callback self-retirement and a final registry-probe race are
  covered without claiming Linux compilation or runtime validation.
- Froze the first stable CitizenSDK package contract around one product ABI for
  Android, the iOS device and simulator variants, and macOS. The current Android
  ABI is `arm64-v8a`; Apple machine architecture metadata is `arm64`.
- Added the typed Dart public API and fixed tuple-only Flutter protocol. The
  Android Flutter plugin and native AAR share one Kotlin facade, JNI bridge,
  Rust Core, chain assets, version, and release candidate.
- Added one shared Darwin source projection for the native Swift API and
  Flutter adapter. iOS and macOS consume the same product Core through
  `CitizenSDK.xcframework`; the product is named macOS and its current machine
  architecture metadata is `arm64`.
- Kept the iOS device and simulator variants as shallow frameworks with install ID
  `@rpath/CitizenSDK.framework/CitizenSDK`, and made macOS a standard
  `Versions/A` framework with install ID
  `@rpath/CitizenSDK.framework/Versions/A/CitizenSDK`. Release candidates permit
  only the five canonical relative symlinks inside that macOS framework and
  reject every other symlink.
- Made Apple teardown monotonic across monitor stop, callback clear,
  destroy-only retry, and final close. An explicit ABI retain lease keeps every
  borrowed host context alive through successful destroy, while abandoned or
  partially closed facades transfer to a supervised backoff reaper.
- Deferred capability and lifecycle Core queries out of the C callback, made
  callback delivery and close linearizable, and made wallet ownership
  fail-closed across concurrent close, stale reservations, and retry handoff.
- Added one idempotent Flutter detach path that revokes method/event handlers,
  permanently invalidates the event epoch, clears the sink, cancels all
  sessions before awaiting any of them, and transfers failed closes to the
  existing supervisor. iOS uses Flutter's published-object detach callback;
  macOS uses the same explicit entry point with deinit as the final fallback.
- Added separate typed public and secure SQLite stores on Apple. Secure Enclave
  protects only a generation-scoped KEK used to wrap random DEKs; sr25519 stays
  in Rust, and no mnemonic, password, DEK, child secret, private key, or native
  handle has a Flutter-channel representation. The iOS simulator variant
  reports hardware-vault and wallet capabilities unavailable instead of using
  a software security downgrade.
- Made the Android release projection exactly one AAR plus the same
  `libcitizensdk.so` and `libcitizensdk_jni.so` bytes used by Flutter; rejected
  nested AARs, Flutter references in the native AAR, extra ABIs, legacy
  `libsmoldot`, missing facade classes, and chain-asset drift.
- Fixed the two Android ELF SONAMEs, required JNI to depend on the Core SONAME
  exactly once, and rejected every `DT_NEEDED` value containing a build-host
  path.
- Required finalized-history bindings to receive 1 through 1990 unique account
  IDs and reject duplicates before session or JNI admission.
- On Android, added SDK-owned non-exported `FLAG_SECURE` wallet flows so
  mnemonic and password input never crosses the Dart channel, plus supervised
  detach that cancels transfer watches, checkpoints running sessions, and
  retains failed cleanup for bounded-backoff retry.
- Kept the CitizenChain light client, rootless hot wallet, sr25519 local
  signing, and on-chain transaction execution behind one `citizen_sdk` API.
- Required the Hosted Package candidate to be derived from the same audited
  GitHub Release candidate. Publication to a Hosted registry remains a
  separately authorized operation.
- Restricted the Hosted Dart runtime to exactly 17 files: one root entry, six
  typed API files, one public account codec, five models, and four platform
  transport files. Archived Dart light-client, wallet, transaction, smoldot,
  and Preferences implementations remain audit/differential inputs only.
- Built the Android AAR, compiled both iOS product test bundles, and assembled
  the single Apple XCFramework with the iOS device and simulator variants plus
  macOS, all with Apple machine architecture value `arm64`. Ran the macOS native suites: 50 Core and 22 Flutter-adapter
  XCTest cases passed with no failures; one
  real-hardware-only case was skipped. The final normal and supervisor consumer
  smoke processes passed. No local Simulator runtime or physical Apple mobile
  device was available, so this does not claim iOS XCTest execution or device
  Secure Enclave/biometric validation.
- Built a real Flutter consumer as an Android release APK for ABI `arm64-v8a`, an iOS device
  Release app without code signing, a generic iOS simulator variant target using Rust
  target `aarch64-apple-ios-sim`, and a
  macOS Release app. These are build/link results, not physical-device or
  Simulator-runtime claims. Flutter's future Swift Package Manager recognition
  warning and Android's built-in Kotlin migration notice are deferred to the
  Step 9 Hosted/Flutter integration work.
- Moved Android Gradle/Kotlin persistent project state into the TataConsole
  central work directory and made source-tree `android/.kotlin` invalid.
- Analyzed the exact 17-file Hosted Dart closure with zero issues, passed the
  complete Dart suite 316/316 with `--timeout=2m`, passed the root Rust
  workspace 285/285 plus its compile-fail doc test 1/1, Clippy and formatting,
  and completed all 17 Android native Kotlin/Java unit-test Gradle tasks.
- Bound the packaged CitizenChain chain spec and light sync state to an exact
  `citizenchain` identity, genesis hash, and SHA-256 asset manifest.
- Required the complete chain-asset contract to pass before the native
  smoldot client is created or initialized.
- Excluded generated build and tool state from the Hosted Package even when
  validation runs in a previously exercised disposable copy.
- Established the product-independent Rust Core contracts and Engine for
  typed verified-chain access, wallet/vault separation, capability snapshots,
  exact-block runtime contexts, guarded state import, and verified transaction
  outcomes.
- Fixed wallet index 0, the account-zero master anchor, Citizen SS58 prefix
  2027, and strict create/import/append provisioning and cleanup ownership.
- Bound chain capability readiness to the Engine lifecycle, with a state-first
  lock order and an immediate readiness check before provider access.
- Added revisioned chain-database snapshots, exact-state CAS, and persistent
  finalized anchors. Cross-process protection requires a qualifying shared,
  durable, strongly atomic store adapter.
- Made host-composed startup restore the typed chain database before provider
  start, and made host export/graceful stop persist the exact stable snapshot
  by revision CAS. Persistence failure short-circuits every stop side effect;
  direct destroy is not a graceful checkpoint. The legacy session constructor
  retains its original explicit import/export and stop behavior.
- Made host-composed start, stop and import exclusive asynchronous lifecycle
  requests. Earlier work must finish before acceptance, and later requests or
  controls observe `BUSY` until completion; the owning stop request alone may
  join its pre-existing capability monitor. Legacy admission remains shared.
- Kept accepted host operations outstanding through completion validation,
  host-memory copying and delivery; the remaining stateless callback tail
  cannot race destroy or expose an instance pointer to late completions.
- Required every non-null host completion to match its callback token and
  `host_operation_id` before the pending registry is claimed. Crossed identity
  pairs are ignored; null completion remains terminal for its token operation.
- Pinned official `subxt-core` 0.43.0 for metadata and `System.Events`
  decoding without adding a remote RPC client or another light node.
- Added the single stable `citizensdk_*` product C ABI with fixed-width
  versioned structures, monotonic handles, owned results, bounded asynchronous
  events, stable errors and truthful capability discovery.
- Preserved all 36 original ABI symbols, layouts, numeric values and legacy
  `citizensdk_create` single-request semantics, then appended 34 typed account,
  wallet, signing, transfer and history symbols for one exact 70-symbol ABI v1
  surface.
- Kept `citizensdk_create` as the compatible chain-only session constructor and
  added `citizensdk_create_with_host` for the platform-independent full Core
  composition over five named typed stores plus the KEK/DEK vault contract.
- Restricted mnemonic output to an SDK-owned prepared-creation handle bound to
  its owner instance and explicit backup UI. Import and account expansion accept
  only explicit user recovery input; private keys and child secrets are never
  exported by the product ABI.
- Added Rust-owned AES-256-GCM child-secret envelopes with random DEKs/nonces and
  full `SecretRef` AAD. Hosts only wrap or unwrap a DEK, and unwrap writes into
  an exact 32-byte Rust-owned output buffer.
- Added the typed smoldot `VerifiedChainClient` provider for exact-block reads,
  verified finalized state, runtime context, signed-extrinsic submission and
  watch, execution verification, and public light-node state import/export.
- Rejected node-returned transaction hashes that differ from the local
  Blake2-256 of the complete signed extrinsic.
- Kept arbitrary JSON-RPC and the legacy `smoldot_*`/`citizen_sr25519_*`
  surface out of the product header. The typed root Dart, Android, iOS and
  macOS bindings use the product ABI; the legacy path remains only as an
  archived differential-test baseline.
- Implemented the Rust Core account-state, exact-best
  `AccountNonceApi_account_nonce` and on-chain fee
  services; the BIP-39 wallet lifecycle with revision CAS, provisioning and
  exact cleanup; the single native sr25519 signer path; exact signed-extrinsic
  V4 `transfer_with_remark` construction; and atomic pending/finalized history.
- Made wallet creation a two-phase, zero-persistent-write prepare followed by
  explicit post-backup commit; encrypted-secret tombstones and Vault generation
  retirement now permanently fence late writers after deletion.
- Required pending submission facts to be persisted before broadcast and
  allowed a finalized success or failure only from the same extrinsic index's
  `System.ExtrinsicSuccess` or `System.ExtrinsicFailed` event.
- Rejected self-transfer history views, paired business and Balances events
  one-for-one, assigned verified local pending to the sender view, preserved the
  receiver view, and kept same-block replay idempotent after pending consumption.
- Resolved historical finalized blocks through the provider before verification
  and fetched security-critical runtime metadata directly from that finalized
  block; persistent runtime caches are never execution evidence.
- Restricted raw submit-and-watch to pure-chain compositions because the watch
  provider broadcasts; wallet compositions fail closed before provider access.
- Documented that general wallet-payload signing is a trusted-host capability,
  so pending-before-broadcast is guaranteed by the SDK high-level wallet
  transaction path rather than imposed on every possible host use of a signature.
- Added the internal product composition that fixes the smoldot provider,
  exact Runtime nonce source and sole sr25519 software signer while accepting
  only typed host stores and `SecretVault`; wallet dependencies are all-or-none.
- Added proof-backed finalized ancestry batches, bounded proof caches, strict
  production-metadata event decoding, 120-block deterministic history batches,
  durable same-account single-flight, and a lifecycle lease covering every
  provider/store await through the final CAS.
- Moved the complete high-level wallet transfer terminal future to the separate
  four-worker watch pool. Cancellation or watch interruption retains durable
  Pending/InBlock state; only canonical body/metadata/System.Events evidence
  yields a finalized execution result.
- Kept the original `citizensdk_create` composition chain-only while exposing
  the complete host-composed surface through `citizensdk_create_with_host`.
  The typed Dart, Android and shared Darwin bindings use that ABI. Legacy
  smoldot host artifacts remain macOS `arm64` differential-test-only and are excluded
  from release candidates.

## 0.1.0 - 2026-08-29

- Established `citizen_sdk` as the single Flutter package boundary for the
  CitizenChain light client, hot wallet, sr25519 signing, and on-chain
  transactions.
- Added Android `arm64-v8a` and iOS Apple `arm64` machine-library packaging contracts.
- Added a Hosted Package candidate contract derived from the same verified
  GitHub Release candidate. This version remains a pre-1.0 release candidate.

## 第 8.1 步：Windows 原生 Host 源码

- 新增 Windows C/C++ Host、Win32 安全交互、句柄绑定 SQLite 存储与 PCP/TPM 2.0 设备金库。
- 同一 Rust Core、70 项根 ABI 和 13 项薄 Host ABI；现有平台、Flutter 默认入口与 Release 平台列表不变。
- 唯一构建器追加 Windows 目标，唯一发布器只收编审计源码；Hosted 暂不包含 Windows。
- Windows 编译、UI、跨进程存储和真实 TPM 授权尚未执行，不能以 macOS 结果替代。

## 第 8.1.1 步：Linux 同源缺陷修正

- 两处 SQLite 结构计数精确识别 sqlite_ 系统前缀，拒绝 sqlitex 对象绕过初始化/既有库检查。
- RequestRouter 明确清空已移交 callback；补直接头依赖、回调重入与迟到完成回归测试。
- 公共库与密文库分别补版本 0 初始化拒绝和版本 1 表/触发器拒绝用例；不改变 schema、平台、
  Core、钱包、签名、轻节点、交易或构建流程。Linux 原生运行结果仍由统一平台验收取得。
