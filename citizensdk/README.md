# 公民SDK（CitizenSDK）

## 当前模块化与链查询合同

五端 iOS、Android、macOS、Windows、Linux 共用同一 Rust 实现，不包含 Web。
`CitizenSdk.open(modules: ...)` 默认完整启用；`CitizenSdkModules` 提供六模块的具名常量，
可按位组合，依赖与编译支持由 Rust 统一验证；数值与跨端合同以唯一 SDK 字典为准。
钱包管理与签名不互相隐式启用，交易和历史各自需要链；完整本地转账仍使用完整组合，保持先持久化 pending 再广播。

Dart 分别使用 `sdk.wallet`、`sdk.signing`、`sdk.chain`、`sdk.transactions`、`sdk.history`、`sdk.qr`；
无状态 `CitizenSigning.verify` 不需 open、事件订阅、链数据库或设备金库。签名模块只使用
同一宿主中已由 SDK 安全建立的账户归属资料与设备金库；首次建立账户仍通过钱包安全流程，
不增加私钥、种子、child secret 或任意秘密导出接口。

`sdk.chain.getGenesisHash()` 读取 Core 固定链身份，不要求启动或联网；
`sdk.chain.getAccountBalances(accountIds)` 复用同一 finalized 批量读取，保留输入顺序和重复项。
两项查询均要求选择 chain 模块，不依赖钱包或签名。
`sdk.wallet.viewAccountPrivateKey(accountId)` 只启动 SDK 原生安全查看，返回完成、取消或错误；
不把账户秘密交给宿主、Flutter 或可替换显示回调。它属于钱包模块，不要求链或签名模块。

`sdk.qr` 是独立的区块链二维码模块：Rust 唯一实现 `QR_V1` 解析、编码、请求会话、
过期/取消/单次消费与响应验签；图像识别和生成五端唯一使用 ZXing-C++ 3.1.1。
`sdk.qr.scan()` 直接打开 SDK 扫描界面，返回 Core 解析后的公开字段。
QR 与 signing 是两个模块：QR-only 不创建钱包、设备金库、链数据库或轻节点。
链调用扫码签名使用 `qr + signing + chain`，调用 `sdk.signing.signQrRequest(text)` 即进入
SDK 自有审阅、用户确认和设备授权，返回签名响应及二维码图像；不要求宿主拼接待签字节。
审阅由 Rust 复用当前已验证链 metadata，不信任二维码展示文案，也不把测试夹具作为生产信任源。
相机只属于 SDK 平台采集层，交付 8 位亮度帧；不接入其他识别器、兼容引擎或回退路径。

模块选择是运行期资源装配，不等于裁剪发布包。现有正式包装仍编译 full 并携带完整链资产；
未选链的实例不加载链资产、不创建链数据库或启动 smoldot，未选历史不初始化历史服务。
模块位为 wallet=1、signing=2、chain=4、transactions=8、history=16、qr=32，full=63。
模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

SDK 原生后台监控复用 smoldot 现有 finalized 订阅；完整钱包组合启动后自动读取本机
钱包账户集合、同步历史，并在没有新块时只读核验待确认交易。不会重新签名或广播。
`historyChanged` 事件只表示历史应刷新，接收方使用已有历史查询；不携带秘密或账户快照。
停止会取消旧代际并排空已进入的存储写入和订阅资源。本地钱包输入不要求启动网络。

当前未发布版本已补充未决交易原授权恢复、有界完成事件预留、Android 关闭/认证边界、
Apple 宿主数据隔离及 Linux SHM 恢复。恢复沿用同一个高层转账入口，不新增业务 API。
本机测试不等于跨平台硬件或正式发布验收，准确结果与未完成项以任务卡为准。

SDK 钱包安全界面统一选择 12／18／24 词，默认 12；“钱包密码（选填）”默认空，非空只
确认一次派生风险，不要求重复输入。创建先准备、展示助记词并确认离线备份，再提交持久化。
SDK 不持久保存助记词，关闭后无法再次显示；非空派生密码须另行记忆，恢复必须保持相同。
这些输入与本地补全在 SDK 原生界面完成，Dart 只获得公开账户结果。

CitizenSDK 是 GMB 根目录下的独立公民链客户端产品，向宿主应用提供同一套公民链轻节点、
无根热钱包、sr25519 本地签名和链上交易能力。源码唯一目录是
`/Users/rhett/GMB/citizensdk`，Dart 包名为 `citizen_sdk`，产品 ID 为 `citizensdk`。

当前源码已经收编 CitizenApp 使用的公民链 smoldot PoW 轻节点闭包、sr25519 signer、链资产与
依赖锁。根公开 Dart API、Android Kotlin/Java 与 Flutter 投影，以及 Apple 共享 Darwin 源码的
Swift 与 Flutter 投影，已经统一通过产品 C ABI 调用 Rust Core，由 Core 实现轻节点生命周期、
finalized 数据库、多账户热钱包、硬件金库、任意协议载荷
签名、钱包完整可用性核验、账户改名、finalized 单/批余额、链上手续费估算，以及
`transfer_with_remark` 的构造、签名、pending-before-broadcast、观察和执行结果核验。
SDK 自有旧 Dart 钱包、交易、轻节点协调及私钥导出已删除；相关行为与测试由正式 Rust
Core 承接。受保护的 smoldot Dart/FFI 来源快照仅供上游审计测试，不是第二套 SDK。
CitizenApp 现有功能和
依赖保持不变；只有在 SDK 稳定后，才会另行设计 CitizenApp 的切换步骤。

Flutter 消费者只从根库打开唯一公开门面：

```dart
import 'package:citizen_sdk/citizen_sdk.dart';

final CitizenSdk sdk = await CitizenSdk.open();
await sdk.start();
// 分别通过 sdk.chain、sdk.wallet、sdk.signing、sdk.transactions、sdk.history 使用功能。
await sdk.stop();
await sdk.close();
```

`open()` 只创建 session，不会隐式启动轻节点；若 session 已处于 `running`，调用 `close()` 前
必须先成功 `stop()`，以完成 checkpoint 和有序停止。

## 完整包验证与分发

CI 使用各平台增量构建，再把同一源码、版本和运行的原生件汇总为一份完整 SDK，最后由
各平台消费同一份 Hosted 包。Release 全量重建同样的闭包，全部验收通过后才形成一次
GitHub Release；正式资产仍为 `citizensdk.tgz`、`citizensdk-release.json`、`SHA256SUMS`。
pub.dev 上传继续通过塔塔控制台的 SDK 发布按钮，不在 GitHub 工作流中保存上传凭据。

最终包检查包括桌面公开消费者运行、Android ARM64 Release APK 的双库字节核对，以及
iOS device Release 宿主和 Simulator ARM64 Swift 链接。移动端构建通过不等于真机验证；
源码中的流程定义也不等于已经发布成功，实际执行结果以对应 CI/Release 记录为准。

Rust 路径已经建立 `native/contracts`、`native/engine`、真实
`native/smoldot/provider` 和产品级唯一 `native/ffi`。根 `include/citizensdk.h` 只公开
`citizensdk_*`。ABI v1 既有 73 个符号、结构布局、数值与默认构造行为不变，
新增模块验证、显式模块构造和无实例验签三个入口，再补充创世哈希、批量余额及两个批量结果读取入口，
QR 公开合同统一为 9 个协议、审阅、签名及结果入口，当前总计 89 个。
原待签字节获取和外部签名拼装入口已删除，不保留兼容接口。图像层另以 3 个稳定 C 函数包装 ZXing-C++。
`citizensdk_create_with_modules` 是官方绑定的模块构造入口；既有构造也进入同一私有装配逻辑，
不建立第二套状态机。链、钱包管理、签名、交易和历史按选择提供，宿主仅补齐所选功能必需的
具名 typed stores 与 KEK/DEK `SecretVault`。仅启用链时 Provider 才直接驱动
已收编的 smoldot 轻节点；任意 JSON-RPC 方法只存在于 crate 私有固定 allowlist，不能由
Dart、Swift、Kotlin 或 C/C++ 传入。启用链的实例创建时 Rust 会再次核对随包资产摘要、正式链身份、
完整 #0 header、genesis 和 state root，随后才构造轻节点。

Engine 固定 `VerifiedChainClient`、`ChainSigner`、`SecretVault`、五类状态仓储、十项能力状态、
准确区块 runtime context、启动前状态导入门禁和同一 extrinsic index 的
`System.ExtrinsicSuccess/Failed` 执行结论。它仅使用官方 `subxt-core = 0.43.0` 解码 metadata
与 `System.Events`。提交时 Provider 还会独立计算完整 signed extrinsic（含 Compact 长度前缀）
的 Blake2-256，节点返回不一致即失败关闭。链身份、生命周期和 capability revision 均由
Engine 持有；`CHAIN_READ`、提交和核验只有在 Engine 为 `Running` 且 smoldot 自身报告
`is_usable` 时才 ready，不能用 peer 数、高度或等待时间猜测。

状态导入触及 Provider 后若失败，同一 Engine/Provider 组合保持不可复用的 `StartFailed`；
导入前还会读取 revisioned `ChainDatabaseStore` 的 finalized 锚，拒绝高度回退和同高度哈希
冲突，并以 CAS/写后回读保存 exact 状态。产品 ABI 当前要求绑定销毁该 handle、创建新实例并
显式处理坏导入后才能重新启动；SDK 不自动删除坏数据库或掩盖防回退失败。
跨 Engine 或进程防回退仍要求 store provider 提供共享、耐久、强原子 CAS。

启用链并装配持久 typed store 的实例使用同一自动链数据库生命周期：`citizensdk_start` 在任何 provider
启动副作用前从 typed store 恢复并复核状态，`citizensdk_export_state` 在返回前 CAS 持久化同一
稳定快照，`citizensdk_stop` 则在退订、停止产品服务和停止 provider 前先完成同一 checkpoint；
持久化失败会保留 Running 状态和全部停止依赖，供宿主重试。直接 `citizensdk_destroy` 不是优雅
checkpoint API，宿主必须先成功 stop；旧 `citizensdk_create` 的显式 import/export 与原 stop
语义保持不变。host 构造的 start/stop/import 还是独占生命周期请求：只有此前异步请求已全部
完成才会受理；受理后，新请求、回调/订阅控制和 destroy 在完成前返回 `BUSY`，因此 checkpoint、
provider stop 与 Engine 状态提交之间不能插入另一项链或钱包工作。

Rust 钱包公开合同同步固定现有热钱包事实：wallet index 为 `0`，账户 index `0` 必须等于
`masterAccountId`，账户范围为 `//0..//1989`，SS58 prefix 为 `2027`。创建/导入 provisioning
的 previous profile 必须为空且拥有目标 profile 全部 exact secret refs；追加账户的 previous
profile 必须是目标账户列表的严格前缀、既有字段逐项不变，且计划只拥有新增 suffix。
active cleanup 与最多 64 项 queue 均不得命中当前 profile 的 exact secrets 或当前 generation
的 wallet key；各计划的 operation ID 与物理目标也不得重叠。

第 4.1/4.2 步已经在 Rust Core 源码内实现并组合账户、钱包、构造和历史行为：finalized
`System.Account` 单读/批读；同一准确 best metadata 的链上费率、最低费与存在性存款；绑定
请求账户和 best 块的 `AccountNonceApi_account_nonce` 准确 Runtime nonce；English BIP-39
12／18／24 词、可选 NFKD password、
`//0..//1989`；钱包创建、导入、追加、可用性核验、改名、切换、删除与清理重放；以及准确
CitizenChain signed extrinsic V4 的 `transfer_with_remark` 构造。创建采用
`prepare_wallet_creation -> 用户确认备份 -> commit_wallet_creation_after_backup` 两阶段合同：
准备阶段对 profile、密文和硬件 KEK 零写入，因而用户看到唯一恢复词前崩溃不会留下不可恢复
钱包。构造固定 pallet `4` / call
`0`、正分金额、最多 99 UTF-8 字节备注、immortal era、tip `0`、正式 genesis 与同块
runtime/transaction version，并采用 Subxt 的长载荷签名规则。source AccountId 必须等于从
金库秘密取得的 sr25519 公钥，生成的签名还会用同一公钥立即复核。

钱包公开事实、产品无关 sr25519 密钥/金库与业务账户协议是三层不同边界。公民链账户及交易
属于 SDK；`SecretVault -> SecretBuffer -> ChainSigner` 只在 Rust 内短暂解锁、签名并清零；
TUYU challenge、TuyuBooking 员工身份及其它业务授权不进入 SDK。业务协议可以请求钱包用
同一用户公钥签一段明确载荷，但不能因此把三套账户、权限或审计记录合并。

产品 C ABI 与 Dart/Android/Apple 官方投影已经落地，Linux 已纳入同版源码候选合同。根 Dart 入口只公开类型化
`CitizenSdk`；Android Flutter 插件与原生 AAR 都调用同一个 Kotlin facade、JNI 和
Rust Core。iOS 与 macOS 共用 `darwin/` 的 Swift、Flutter adapter、typed SQLite stores 与
`SecretVault`，并通过同一个 `CitizenSDK.xcframework` 消费产品 Core；各公开绑定均不运行
legacy Dart 钱包或 legacy `libsmoldot`。模块化构造按需装配唯一 provider、nonce 与 signer，
宿主的 chain database/runtime cache、wallet profile、transaction history、encrypted secret blob
职责仍隔离。chain/history 才创建 public store；wallet/signing 才创建配套 secure store 与
`SecretVault`。未选模块的调用明确拒绝，不因共享设备资源而开放该模块。

第 7.1 步在 `linux/` 新增 LinuxARM、LinuxAMD 共用的 C/C++ Host 源码投影：它只负责
HostBridge、五类 typed store、TPM 2.0 KEK/DEK Vault、SDK-owned GTK 钱包流程和 header-only
C++ convenience API，仍调用上述同一产品 ABI，不复制 Engine、smoldot 或 sr25519。该步骤只
冻结源码和合同。第 7.2 步又增加复用该 Host/Core 的 Flutter plugin 源码、固定 22 方法
codec/session/event/wallet-flow/environment 合同及其测试源码；没有新增 Linux 专用 Dart API。
第 7.3 步已在唯一构建器内接入安装闭集、已安装 C/C++ 消费者和标准 Flutter Release 消费者源码；
新增夹具只验证现有公开能力，不重写 Host/Core，也不新增业务协议。
当前开发以本机 macOS 编译通过为验收标准，不再以用户提供 Linux/TPM 环境作为本步前置条件；
2026-09-03 已通过既有 `abi-host` 与 `apple` 构建：Core/C ABI、Swift/Flutter 原生绑定及单一
XCFramework 验证成功，第 7.3 步该轮没有修改生产实现。跨平台构建与功能验证后续统一进入 GitHub
CI/Release：CI 使用增量缓存，Release 使用全量构建，保持同一 Core commit、SDK 版本、ABI
版本和一个 CitizenSDK Release，不新增平台独立产品或第二套流程。
第 7.4 步已原子更新 `pubspec.yaml` 官方 `linux` 注册、默认 `CitizenSdk.open()`、Hosted 过滤
及 LinuxARM/LinuxAMD 候选 manifest 合同；应用直接使用公开入口，无需内部 platform 注入。
两种机器目标的 `.so` 及真实平台运行验证尚未生成或执行，尚无 Linux 正式分发结果；本机 macOS
通过不能代替 Linux 的运行证据，同版运行件缺失或证据不齐时拒绝生成可分发候选。
Linux typed store 通过自有 openat SQLite VFS 把主库和全部 sidecar 绑定到已验证目录 fd，
并精确核验 schema、PRAGMA、权限、owner、link count、inode 与 durable commit 点；不依赖
`/proc/self/fd` 路径。Host 统一 closing/admission lease、65+ 同步 completion 无损路由、GTK
parent 销毁退休、Vault generation 条件写/退休重验，以及 TPM child template/DA lockout
检查均属于同一第 7.1 步源码合同，尚未构成运行验收。

产品 ABI 不导出 private key、child mini-secret、裸 signer 或钱包 signed extrinsic。创建钱包
唯一允许输出助记词的边界是 SDK 拥有、绑定 owner instance handle 的 prepared-wallet 会话：
宿主只可为明确备份 UI 查询/复制一次并 commit 或 release，另一实例不能读取、释放或消费。
import/add 只接收用户明确输入的恢复词；它们不是秘密导出接口。

finalized 历史每次最多处理 120 个连续高度。provider 从同步状态机的准确 verified finalized
锚按 parent hash 逐头回溯，逐项核对响应 hash、SCALE header hash、高度和父链；它不把 best、
recent cache 或按高度返回的 peer 值提升为 finalized 证明。独立有界 proof-derived cache 只减少
重复回溯，不能改变结论。Engine 在完整 provider/store await 与最后一次 CAS 期间持有代际租约，
stop/dispose 不能跨过提交窗口；同账户处于 Pending/InBlock 时只允许同一交易幂等重放，避免
准确 Runtime nonce 在本地并发交易中被复用。

`assets/README.md` 固定随包资产与设备运行状态的边界，正式链信任资产统一位于
`assets/citizenchain`。SDK 在创建或初始化 smoldot 原生客户端前先验证固定 manifest、
`chain_id = citizenchain`、`protocol_id = citizenchain`、genesis hash、chainspec 摘要和
light sync state 摘要；任何不一致都失败关闭，远端启动清单只能建议 bootnode。

## 当前交付边界

- Android `arm64-v8a` 使用产品 ABI；正式候选同时交付原生 AAR 和供 Flutter 插件使用的
  同字节 `libcitizensdk.so`、`libcitizensdk_jni.so`。
- iOS 同时支持设备变体与模拟器变体，二者当前 Apple 机器架构值均为 `arm64`。Swift 原生 API 与 Flutter adapter 共用
  `darwin/` 生产源码，并从同一个 `CitizenSDK.xcframework` 调用产品 ABI；iOS 模拟器变体无 Secure
  Enclave，硬件金库与钱包能力必须如实报告不可用。
- macOS 与 iOS 共用上述 Darwin 源码、Swift API、Flutter adapter 和
  XCFramework 产品边界；产品名始终只写作 macOS。
- LinuxARM、LinuxAMD 已有 Host、Flutter adapter、安装/消费者源码，并已在第 7.4 步纳入
  同版候选合同和默认 Flutter 入口；尚未实际编译、运行或正式分发。Windows 已有原生 Host
  与 Flutter 适配及独立 C/C++ 安装消费者，第 8.4 步把 Windows 默认 Flutter 入口、
  同版候选/Hosted 运行文件与公开 Flutter 消费者一起纳入。
  源码注册不代表已交付，跨平台实际验证按后续统一 GitHub CI/Release 推进，不阻塞本步
  的 macOS 本机开发验收。
- 聊天、广场、OpenMLS、TUYU 账户签名协议、旅行/生活/商家业务均不属于 CitizenSDK。
- CitizenWallet 冷钱包是独立产品，不属于本 SDK 的能力收编范围。

## 安全边界

- sr25519 context 固定为 `substrate`。`native/signer/src/sr25519.rs` 是 SDK 内唯一算法
  实现；legacy 四个 FFI 原语和类型化 `ChainSigner` 都调用它，不维护第二份密码学逻辑。
- 助记词和母种子不持久化；账户 child mini-secret 只保存为用户设备硬件金库密文并在
  本地解锁、签名。
- Rust 为每个 child 生成随机 32 字节 DEK 和随机 nonce，以 AES-256-GCM 加密并把完整
  `SecretRef` 作为 AAD；宿主金库只 wrap/unwrap DEK。unwrap 直接写入 Rust-owned 的精确
  32 字节缓冲区。Apple Security framework 解封时返回的不可变 `CFData` 只在对应
  `autoreleasepool` 内短暂存活；桥接层避免生成 Swift `Data`/COW 副本，在不能可靠原地清零的
  边界下立即把精确 32 字节复制到 Rust 输出，并由 pool 排空释放。该值不进入 public API 或
  Flutter；Rust-owned DEK 与 child 明文仍在使用后清零。
- Rust Core 不提供私钥导出。Android 的恢复词输入/备份只存在于 SDK-owned、非导出且
  `FLAG_SECURE` 的 Activity；Apple 通过共享 Darwin 的 SDK-owned native flow 处理同一明确
  输入/备份边界。Apple SDK-owned wallet UI 会在流程终态前由文本控件和短期 Swift `String`
  持有恢复词/password；终态会 best-effort 清空控件与 Rust 敏感 buffer，但 Swift `String` 不可
  可靠擦除。它们不得返回 public Swift API、记录、持久化或进入 Flutter。助记词、password、
  DEK、child secret、private key 与 native/result/prepared handle 都
  没有 Flutter tuple 位置；SDK 不保留私钥导出实现。
- Apple 把可重建的链数据库、runtime cache 和交易公开事实放入 typed public SQLite，把钱包
  profile、加密秘密信封及 Vault 引用放入权限更严的 typed secure SQLite。Secure Enclave
  仅保护 generation-scoped KEK，用来 wrap/unwrap 随机 DEK；sr25519 始终由 Rust signer 完成。
- 新硬件金库产品标识固定为 `citizensdk`，宿主不能用产品名创建另一套 SDK 密钥空间。
- 每只钱包使用 CSPRNG 生成的独占 generation，每个账户秘密使用独占 owner；硬件 KEK、
  密文键与 AAD 都绑定这些身份，迟到清理不能命中随后成功的钱包或同 AccountId 的另一代秘密。
- 每个已删除 SecretRef 必须留下不可逆密文墓碑，整钱包删除还必须在系统金库持久退休该
  generation。进程内操作门只是减少冲突；跨进程迟到写入由这两道持久 fence 拒绝，不能把
  “物理删除成空槽”当作删除成功。
- 公开钱包状态在 secret 写入前保存 provisioning，并保存 active cleanup 与 exact
  cleanup queue。平台 typed store 使用独立持久合同。任何 Rust store provider 都必须实现共享、耐久
  CAS、永久墓碑和 generation retirement，不能只依赖进程锁。
- SDK 不包含远程签名或通用远程 RPC；公民链交易由设备内 smoldot 轻节点通过 P2P 广播。
- 宿主进程属于受信任边界；公开接口不提供明文 child 注入或导出通道，SDK 不把同进程
  内存隔离描述为能抵御恶意宿主。

Rust 钱包交易只公开一个 `transfer_with_remark` 高级入口：内部构造对象不可从 Engine 取出，必须先
以本地完整 extrinsic hash 持久化 source/destination/amount/remark/nonce，再向 provider
广播。纯链客户端保留的预签名 raw submit 是无钱包组合的高级迁移入口；一旦注入任一钱包交易
组件，它也必须命中内部 pending，否则广播前失败关闭。底层 watch 实际执行 submit-and-watch；
组合钱包组件后该 raw 入口同样在 provider 前关闭。`inBlock`、`finalized` 或返回 txHash
均不是执行成功；历史只接受由完整 hash/body/event 核验器产生的内部终态令牌，令牌把 txHash
与同一 extrinsic index 的 `System.ExtrinsicSuccess/Failed` 绑定，不能由绑定层伪造或误配。
宿主给出的 finality 位同样不是证明；Engine 先让轻节点把 hash/height 解析到 verified finalized
canonical 链，再直接从 provider 取得该块 runtime context；持久 runtime cache 不是执行证据。
finalized 流水拒绝自转并对业务/Balances 双事件严格一对一配对，本地 pending 认领发送方
outgoing、保留接收方 incoming，同一原始块重放不能恢复已消费 pending。
高层转账的完整 terminal future 使用独立四线程长观察池，不占用短操作 worker；只有经
canonical finalized body、该块准确 metadata 与同 index `System.Events` 核验后才返回终态。
取消、dropped/retracted、timeout、provider 错误或流中断会结束本次观察，但不会清除 durable
Pending/InBlock single-flight 门，后续只能经历史协调继续收敛。
取消使用单笔 `WalletTransferCancellation` 通知 Engine，不取消其它交易或监控；FFI
继续驱动同一 future，直到已进入的存储／金库操作真实返回后才完成请求。取消不是撤回，
不能抹去期间实际写入的 Pending、InBlock 或准确执行结果，也不保证已广播交易不会执行。

`sign_wallet_payload` 仍是受信任宿主可调用的产品无关账户签名能力，可承载 TUYU 等明确协议。
因为它返回通用 sr25519 签名，宿主技术上可以在 SDK 高层交易路径之外使用该结果；上述 pending
保证只覆盖 SDK 自己的高层钱包交易入口。产品 C ABI 已通过
`citizensdk_sign_wallet_payload` 投影该方法；后续语言绑定必须保留这条信任边界，不能宣称
SDK 在密码学上限制了宿主的所有签名用途。

## 构建与分发

根 Rust workspace 现在统一包含 `native/contracts`、`native/engine`、`native/ffi`、
`native/signer` 与 `native/smoldot/provider`；收编的 PoW/light-base 继续使用已验证的嵌套
workspace 语义。`native/smoldot/SOURCE_SHA256.json` 同时分类逐字节来源、适配文件与
SDK-only Provider，canonical Release 对 Core、Provider、产品 ABI、根公共头文件和测试分别
做反向闭集校验。`scripts/build-native.sh abi-host` 只在源码树外构建测试用
`libcitizensdk`，逐项比对公共头文件符号并拒绝泄露 `smoldot_*`、`citizen_sr25519_*` 或
`account_crypto_*`。Android 正式构建使用一个 Core 与一个薄 JNI bridge，并以 AAR/Flutter
双投影字节一致、AAR 不含 Flutter class/reference、无嵌套 AAR、无 `libsmoldot` 验收。
Core 与 JNI 的 ELF SONAME 分别固定为 `libcitizensdk.so` 和 `libcitizensdk_jni.so`；JNI 只能按
Core SONAME 依赖一次，任何包含 `/` 的 `DT_NEEDED` 都会失败关闭，禁止构建机路径进入设备。
Android Gradle/Kotlin 的 persistent project state 只能位于 TataConsole 中央 work directory；
源码 `android/.kotlin` 明确禁止，候选与反向验证也必须拒绝它。
Apple 候选使用一个 `CitizenSDK.xcframework` 封装同一产品 Core 与 Swift API，Flutter adapter
只消费该框架而不重建 Core；
iOS 设备变体、iOS 模拟器变体和 macOS 三个 slice 必须来自同一 Core commit、
ABI version 与 SDK version；其当前 Apple 机器架构值均为 `arm64`。legacy `libsmoldot.dylib` 仅保留为
macOS `arm64` 差分测试宿主库；它的
`LC_ID_DYLIB` 是 build-local 路径，不具分发身份，发布器必须排除并随测试工作目录清理。
iOS 设备和模拟器只是同一 iOS 平台的技术变体，公开平台清单只记录 `iOS` 与 `macOS`；
`aarch64-apple-ios`、`aarch64-apple-ios-sim`、`aarch64-apple-darwin` 只是 Rust 编译 target，
不得变成额外产品名或 macOS 架构后缀。

iOS 设备和模拟器变体使用浅层 `CitizenSDK.framework`，install ID 均固定为
`@rpath/CitizenSDK.framework/CitizenSDK`。macOS 使用 Apple 标准的
`Versions/A` framework 布局，install ID 固定为
`@rpath/CitizenSDK.framework/Versions/A/CitizenSDK`。候选只允许 macOS framework 内部
`Versions/Current -> A`，以及根 `CitizenSDK`、`Headers`、`Modules`、`Resources` 指向
`Versions/Current/...` 的精确五个相对符号链接；iOS 两种变体和候选其他位置不得
出现任何符号链接。

Apple 本机验证已编译 iOS 设备与模拟器变体两组测试 bundle；本机没有
Simulator runtime，因此没有把 iOS XCTest 记为已运行。macOS 实际运行 Core 50 项、
Flutter adapter 22 项 XCTest，0 失败，其中 1 项需要真机硬件的用例跳过；最终
normal/supervisor 消费者 smoke 均通过。本机没有真实 Apple 移动设备，这些结果不代表
Secure Enclave、生物认证或 device-only Keychain 已完成真机验收。

同一真实 Flutter consumer 已完成 Android release APK（ABI `arm64-v8a`）、iOS device Release
no-codesign、iOS 模拟器变体（Rust target `aarch64-apple-ios-sim`）编译和 macOS Release 构建。这里仅声明产物已从
公开 Dart API、Flutter adapter 和对应原生投影成功链接构建；本机没有移动真机或 Simulator
runtime，因此不声称 Android/iOS 真机或 iOS 模拟器运行通过。Flutter 对插件 Swift
Package Manager 目录识别的未来兼容警告，以及 Android built-in Kotlin 的未来迁移提示，统一
留到第 9 步 Hosted/Flutter 集成处理，不在第 6 步建立第二套投影或扩展工具链范围。

同一本机闭集还完成 Android AAR 构建；Hosted 精确 17 个 Dart 文件分析为 0 问题，完整
Dart 套件使用 `--timeout=2m` 执行 316/316；根 Rust workspace 执行 285/285、
compile-fail 文档测试 1/1、Clippy 与格式检查；Android 原生 Kotlin/Java 单元测试 Gradle
共 17 个 task 成功。这些是本地源码闭集结果，不是远程 CI、正式 Release 或发布记录。

CitizenSDK 最终统一流程合同使用 `公民SDK · CI · SDK` 与
`公民SDK · Release · SDK`。Release 会复核指定成功 CI 的 workflow、显示标题、产品目标、
成功状态和准确 `source_sha`，不读取、下载或比较 CI 资产；随后从同一源码提交重新执行依赖
检查、测试、原生构建和候选生成。这是独立重建与重新验证，不把不同 Runner 的归档字节
天然相同作为前提。
TataConsole 现已接通五宿主原生阶段、同源汇总、五宿主同包消费和 Release 发布阶段；
尚未运行的远程 CI 或正式 Release 仍不能写成通过，单个阶段成功也不能冒充完整 SDK 验收。

根包已消除本地 `path`/`git` 依赖，目标 Hosted 依赖形式固定为
`citizen_sdk: ^1.0.0`。统一 CI 与 Release 的目标合同是在 Android/Apple/Linux/Windows 同版原生投影注入唯一正式候选之后执行官方
`dart pub publish --dry-run`；`.pubignore` 只从该候选过滤 Rust 源码、测试、脚本、锁文件和
审计资料，不建立第二份候选或第二条发布流程。因为 Dart 工具会生成 `.dart_tool`，dry-run 在
唯一候选的逐字节临时副本中执行，正式候选保持不可变。Dart、Android、
`darwin/citizen_sdk.podspec`、`linux/CMakeLists.txt` 与 `windows/CMakeLists.txt` 源码版本现已
统一冻结为 `1.0.0`；发布器要求请求版本、候选 manifest 和五处源码版本逐项一致，禁止从旧源码
临时改号发布。当前只冻结首个稳定版源码，不上传 Hosted Package；首次发布完成前仍不得
宣称 `citizen_sdk: ^1.0.0` 已可从 Hosted Registry 获取。

第 9.1 步已在同一个 `scripts/release.mjs` 增加 `--hosted` 与 `--verify-hosted` 本地入口：
先反向验证审计候选，固定官方 Dart 3.12.2 独立执行零 warnings 的 dry-run，再调用官方
本地归档分支。Hosted 归档按完整路径、节点类型、权限与来源字节验真，通过后才写入全新
解包目录；没有第二套候选或上传入口。原审计包保留合法 Apple framework 链接，Hosted
按官方 Pub 行为展开为普通文件，两者不比较 gzip 编码字节。命令及安全边界见
[NATIVE_PACKAGING.md](docs/NATIVE_PACKAGING.md#hosted-本地归档与解包验真第-91-步)。
本机官方工具往返使用跨平台二进制格式夹具，只证明归档工具合同；真实 macOS 安装消费、
全平台最终体积与统一 CI/Release 验收仍须分别完成，不能据此宣称正式包已可安装。

第 9.2 步已补正式包的 macOS Flutter Release 消费验收实现：输入必须来自验真 Hosted
解包包，而不是源码或内部平台注入；公开消费者只验证初始化、能力、空钱包资料、启停、
事件和关闭，不创建钱包、签名或提交交易。Foundation 实际状态路径必须先证明处于中央
独占工作区，不能触及用户原钱包数据。本机 Apple 原生编译及包合同通过；用户确认将
实际 Flutter macOS 安装运行移交第 10 步 GitHub 统一 CI，本机 Xcode/SwiftPM 权限失败
仍如实保留。准确范围见中央任务卡第 35 节；本机开发验收完成不等于 Hosted 安装/运行
通过，也不等于包已在 pub.dev 发布。

第 10.3 步已将同一 macOS Hosted 目录预检用于本机与 GitHub Runner：本机使用上述中央
SDK 工作区，GitHub 仅接受 `RUNNER_TEMP/citizensdk` 下的既存受控输入/输出，且必须与
`GITHUB_WORKSPACE`/SDK 源码完全分离。缺失根、链接、穿越、根目录本身或输入输出交叠
在构建器首次写入前拒绝；真实消费入口复用此预检并传递 Runner 环境。这里只完成路径
合同适配，不代表 GitHub 安装、运行、CI 或 Release 已通过。

第 10.4 步把 Hosted 参数接入既有 CI/Release 动作，由同一 SDK 发布器处理取消和
Dart/Pub 进程组收尾；未确认退出就保留准确目录并失败，不启动下一阶段或误报成功。
Hosted 归档统一由既定 macOS 作业生产，不在 Windows 运行归档工具；这不改变
Windows SDK、解包验真或安装消费者。只完成本地受控调度/来源合同验证，尚未运行
完整平台 CI、正式 Release 或 Hosted 上传。详见 `docs/NATIVE_PACKAGING.md`。

第 10.5 步已固定 LinuxARM/LinuxAMD 的 SQLite 3.53.4、OpenSSL libcrypto 3.5.8、
TPM2-TSS 4.2.0，以及 Windows 的 SQLite 3.53.4。中央既有依赖入口负责准备，SDK 验证
同一静态前缀、来源合同、入口工具和最终运行库证据；三项许可原文/归属随审计与 Hosted 包
保留。只完成本机源码、格式和拒绝路径验证，尚未运行真实 Linux/Windows 编译或完整矩阵。
第 10.6 步已接入 Action/remote-jobs 的五宿主阶段 0：Android、共享 iOS/macOS 的 Apple、
LinuxARM、LinuxAMD、Windows，仍只有 `gmb.citizensdk.sdk.ci` 一条 SDK 路由。
各作业复用统一 CI 增量缓存，缓存 Cargo/Pub 及消费者 Gradle/CMake/Apple module 中间状态；
最终库、消费者程序、证据及安装现场不缓存。
官方工具原件复用中央摘要对象库，Linux 使用固定 Debian 用户态保持 GLIBC 2.31；
不改 SDK 构建器或产品功能。阶段件绑定 run/attempt、源码 SHA 和 SDK version，不能跨轮拼包。
阶段 1 唯一候选/审计、阶段 2 同包消费者及 Release 多宿主编排已经接线；本机受控测试
仍不代表平台真实编译、硬件金库或发布验收。Linux 独立权限策略的实际加载仍须远端确认。

GitHub Release 继续生成 `citizensdk.tgz`、`citizensdk-release.json`、`SHA256SUMS`，其中
tgz 候选合同保留完整源码、测试、锁文件、文档与 Android/iOS/macOS 原生投影，并纳入 Linux
Host 源码及两平台合并的 27 项安装投影、Windows Host/adapter 源码及 22 项安装投影，用于来源审计、校验和离线留档；
Hosted Package 只交付 Flutter 运行时闭包、插件、链资产、Android/Apple/Linux/Windows 原生投影、README 和完整法律声明。
其 Dart 运行闭包精确为 18 个文件：根入口 1 个、`lib/src/api` 7 个、
`lib/src/crypto/account_codec.dart` 1 个、`lib/src/models` 5 个和 `lib/src/platform` 4 个；
SDK 自有旧 Dart 链、钱包、交易及 Preferences 实现已删除；仅上游 smoldot 审计快照由 `.pubignore` 排除。
Android 原生 AAR 只存在于 GitHub 审计候选；Hosted 包明确排除该 AAR、native 测试/C++/构建
输入，但保留根 Flutter 插件直接编译的同一 Kotlin 生产 facade 和两份 `arm64-v8a` SO。两种分发读取
同一源码提交和同一注入后候选。Linux Hosted 精确保留 39 项：27 项安装件及 12 项插件输入，
排除 Host 私有源码、测试及构建模板，不在应用中重编 Host/Core。Windows Hosted 同样精确保留
34 项：22 项安装件及 12 项插件输入。CitizenSDK 使用 TataConsole 的 SDK 发布按钮执行
正式发布流程；不接入公民网下载。

本机 CitizenSDK 最终产物容器固定为
`/Users/rhett/TATA/tataconsole/target/gmb/citizensdk`，工作状态容器固定为
`/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk`。唯一发布器只接受两者的严格
子路径，不允许把永久容器本身作为写入目标；拒绝旧路径、越界、穿越和链接。
第 9.1 步只补发布器的 Hosted 归档验真，不修改原生构建器、控制台事务或 GitHub 流程。
本地打包快照由准确的已提交 Git `HEAD` 导出；
工作区中的未提交修改不会被冒充成该提交。中央目录现有三件套属于其生成时的历史提交，
除非重新完成当前提交的统一构建与核验，否则不得称为当前源码候选。
第 6 步的工作目录和清理结果属于任务卡中的已结束历史记录，不是当前路径指引。
本步只清理获准工作容器内由本任务生成的内容，保留永久容器、已有缓存与历史三件套。
没有执行 Hosted 上传、远程 CI、正式 Release 或 Git 操作。

第 7.1 步没有运行 Linux 编译与 CTest、Dart/Flutter/Cargo 测试、Git、远程 CI、Release 或
Hosted 上传，也没有生成任何 Linux 原生产物；只运行获准的 Node Release 来源合同测试与
脚本语法检查，不能据此声称 Linux 运行验证通过。后续本机 Linux 验证状态只能写入
`/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk` 下的任务独占目录；GitHub runner 使用统一工作流
的 checkout 外独占目录，不照搬本机绝对路径。Linux CTest 配置必须用 `CITIZENSDK_TEST_WORK_DIR`
显式注入对应工作区中已存在、有效 UID 所有且权限
为 `0700` 的绝对工作根；测试不回退到 `/tmp`、当前目录或用户目录。

第 7.3 步的 Linux 安装检查原使用单平台 19 文件技术闭集；第4步加入共享 QR 图像头后，当前每平台 20 项、合并为 27 项唯一安装
投影，重叠头和资产必须逐字节一致。C/C++ 消费者只链接同版已安装 Core/Host；Flutter 消费者
使用候选的正式 plugin 注册与 `CitizenSdk.open()`，运行标准 Release bundle 并检查超时、退出码
和成功标记。上述 Linux 原生执行、编译器与静态依赖身份、许可证、Flutter/Pub 缓存及 GTK/TPM
功能验证归入后续同产品同版本的 GitHub CI 增量缓存、Release 全量构建验证，不再等待用户提供
Linux 环境才完成当前开发步骤。根包源码注册不代表已正式发布；本机 macOS 编译和 Node 合同均不能代替
这些 Linux 运行事实，也不能把未执行项目记录为通过。

详细说明见 `docs/ARCHITECTURE.md`、`docs/C_ABI.md`、`docs/DART_API.md`、`docs/WALLET_MODEL.md`、
`docs/SECURITY.md`、`docs/SOURCE_PROVENANCE.md`、`docs/MOBILE_PLATFORM.md` 与
`docs/NATIVE_PACKAGING.md`；Linux 当前源码边界与未交付状态见 `docs/LINUX_PLATFORM.md`。

## Windows 原生适配（第 8.1 步）

`windows/` 新增原生 C/C++ Host、Win32 自有钱包 UI、PCP/TPM 2.0 金库与类型化存储源码。
最低 Windows 11，公开平台名 Windows，不新增 Core、签名或交易实现。尚未在 Windows
实际编译/运行；第 8.4 步登记默认 Flutter 入口、DLL 候选投影和真实公开消费者，尚未正式分发，
详见 [Windows 平台合同](docs/WINDOWS_PLATFORM.md)。

Windows Flutter 只使用统一双通道和 36 方法，连接同版已安装 Host/Core/QR 图像层。宿主需一次声明
`CITIZENSDK_APPLICATION_ID`，原样作为稳定应用数据命名空间，不是业务账户或 Windows
身份认证；无默认值，不从文件名或展示名推导。公开类型仍只有 `CitizenSdk`，Windows
使用默认平台和官方自动注册；缺少同版插件立即失败，不注入替代实现。宿主仍需这一项
原生身份声明；候选合同不是 Hosted 已发布或 Windows 实际验收已经通过。

第 8.3 步的原生安装合同固定 21 个文件，核验版本、同轮字节和完整 PE 导出后，由独立
C11/C++17 程序仅消费公开头和已安装库，检查运行时 DLL 来源、异步结果所有权、启停及
关闭重试。两个原生消费者关闭钱包和 HWND，不触发 TPM/钱包 UI 或交易。第 8.4 步继续
运行六项 adapter 测试和官方 Flutter Release 消费者，全部通过后才向全新输出位置同卷
导出；已有输出不覆盖。Hosted 精确保留 22 项安装件和 12 项插件输入，Host 私有实现不
进入运行包。Windows/MSVC 运行时由宿主部署环境提供。这些验证沿用唯一构建入口，实际运行仍待
统一 GitHub CI/Release，本机 macOS 检查不替代 Windows 平台证据。
