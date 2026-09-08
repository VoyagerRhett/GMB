# CitizenSDK 原生核心

当前 Core 为 88 个公开 C 函数；六模块由统一 Rust 装配与门禁决定。
运行期模块选择不裁剪现有正式 full 包或链资产。模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

本目录承载同一 CitizenSDK 产品的统一原生核心：`contracts` 固定类型化依赖语义，`engine`
负责产品无关的能力、runtime、状态导入与交易执行协调，`ffi` 是唯一产品 C ABI，`signer`
提供 sr25519，`smoldot/provider` 实现类型化链合同，`smoldot/ffi` 只保留归档
Dart/smoldot macOS `arm64` 差分测试所需的 legacy 入口，`smoldot/pow` 是公民链 PoW + GRANDPA
轻节点快照。

固定依赖方向为：

```text
语言绑定 -> 产品级唯一 C ABI -> engine -> contracts <- smoldot / signer / OS vault / stores
```

`native/ffi` 与根 `include` 已建立产品级唯一 C ABI，并让其经 Engine 调用真实 smoldot
provider。ABI v1 保持既有结构、数值及默认构造行为，当前共 88 个函数。
`citizensdk_validate_modules` 在平台资源创建前统一验证选择；
`citizensdk_create_with_modules` 按选择装配同一 Core；
`citizensdk_verify_signature` 是无实例纯验签，不需要金库、链或事件订阅。
ABI 不开放任意 RPC、private key、child secret、低层 signer 或钱包裸 signed
extrinsic。

host 组合还固定公开链数据库生命周期：start 在 provider 启动前自动 restore，显式 export 在
返回同一快照前先完成 exact revision CAS，graceful stop 在退订/停止服务/provider 前先
checkpoint。持久化失败不会执行后续 stop 副作用；destroy 不替代 graceful stop。legacy session
构造不启用这三项自动行为。host start/stop/import 采用独占 request admission：先前请求必须
结束，后续请求、回调/订阅控制和 destroy 在该生命周期请求完成前失败关闭；legacy 构造仍沿用
原共享 admission。

第 4.1/4.2 步已经在 `engine`/`contracts`/`signer` 源码实现并组合 finalized 账户余额、同块链上
费用、准确 best `AccountNonceApi_account_nonce`、完整钱包生命周期、准确 signed extrinsic V4
`transfer_with_remark`、广播前 pending 和 finalized 同 index System 终态。创建钱包是
prepare 零持久写入→用户确认备份→commit；删除后的 SecretRef 保留永久 tombstone，整代
Vault generation 被持久退休。钱包秘密只在 Rust `SecretBuffer` 中解锁并交给唯一
`ChainSigner`，没有私钥导出路径。钱包交易只公开不可拆分的 `transfer_with_remark`；
pending CAS 成功后才进入 provider，provider 哈希不一致时失败并保留本地 pending。
finalized 流水拒绝自转，对业务/Balances 双事件精确一对一去重，并由已核验 pending
认领发送方 outgoing；同一原始块重放不能恢复已消费 pending。底层 watch 是
submit-and-watch，组合钱包组件后会在 provider 前关闭 raw 入口。终态 metadata 直接从
provider 的准确 finalized 块取得，持久 runtime cache 只用于性能，不能充当执行证据。第 4.2 步
新增的 Rust 内部 `ProductComposition` 仍固定唯一 provider、准确 Runtime nonce 与 sr25519 实现。
当前模块化构造只装配已选服务：wallet 管理与 SigningService 独立，history 也独立于 transactions。
chain/history 按选择使用 public store，wallet/signing 才需要配套 secure store 与 Vault；
签名只读同宿主已安全建立的账户归属元数据，不开放钱包 UI，也不建立第二份账户或秘密仓库。
首次 provision 仍须钱包流程；未启用模块明确拒绝。五个平台只投影同一 Core 规则。

创建准备会话的助记词仅经绑定 owner instance handle 的 SDK-owned handle 提供给明确备份 UI；
import/add 的恢复词是用户显式输入。Rust 以随机 DEK/nonce 和完整 `SecretRef` AAD 执行
AES-256-GCM，宿主只 wrap/unwrap DEK，unwrap 直接写 Rust-owned 32 字节缓冲区；private key
与 child secret 永不导出。

finalized 历史只按一次 verified finalized 锚进行 parent-header ancestry 证明，每批最多 120 块；
有界 proof-derived cache 只优化回溯长度，不参与安全结论。Engine 的历史操作租约覆盖全部
provider/store await 和最终 CAS，stop/dispose 不能穿越提交窗口。同账户 Pending/InBlock 的持久
single-flight 防止准确 Runtime nonce 在并发构造中被再次使用。

`smoldot/ffi` 只继续服务归档 Dart/smoldot 差分验证；它的 `smoldot_*` 与四个
`citizen_sr25519_*` 是 legacy macOS `arm64` 宿主测试库的真实导出，但不属于产品 `citizensdk_*` ABI，
也不进入任何候选。根 Dart、Android 与 Apple 钱包、交易和秘密处理已经切换到 Rust Engine，
不能把保留源码误写成当前公开运行路径。

Engine 的 `sign_wallet_payload` 是受信任宿主的通用 sr25519 账户签名能力，不是交易专用签名器；
宿主可把返回签名用于 SDK 高层交易路径之外。因此 pending-before-broadcast 只保证 SDK 的
高层钱包交易入口。产品 C ABI 已以 `citizensdk_sign_wallet_payload` 投影该方法，后续绑定
必须如实保留这条信任边界。

高层 `citizensdk_transfer_with_remark` 在独立四线程长观察池中等待完整 Engine terminal
future，不占用短操作池。只有 canonical finalized body、准确块 metadata 与同 index
`System.Events` 形成终态；取消或中断只结束本次观察，durable Pending/InBlock 门保持。

原生轻节点源码闭包、FFI、Dart smoldot 包、来源测试与锁文件已经迁入；当前不存在通过
CitizenApp 或 `shared` 相对路径取得运行时源码的依赖。`android/`、`darwin/`、`linux/` 与
`windows/` 平台目录只负责链接、装载、typed stores 和设备安全能力，不复制链或签名实现。
Linux Host 通过根 `citizensdk_create_with_modules` 按选择注入分离的 public/secure SQLite 和 TPM 2.0
KEK/DEK Vault；其 C++ convenience API 只是根 C ABI 的 header-only RAII 包装。
Linux 的 SQLite 文件身份由 Host 自有 openat VFS 绑定，不经过 `/proc/self/fd` 路径；既有
schema/PRAGMA 与 transaction commit 点必须精确失败关闭。Host closing lease、同步早完成无损
路由、Vault retirement 线性化、GTK parent 销毁退休和 TPM child-template/DA-lockout 检查都
位于 Linux 宿主层；TPM readiness 还通过 `Esys_TestParms` 探测准确 primary/OAEP 参数组合，
不改变 Rust Core 的钱包、交易或签名语义。

`engine` 精确使用官方 `subxt-core = 0.43.0` 解码 metadata 与 `System.Events`，不实现网络
连接或任意 RPC；网络验证只由 `smoldot/provider` 的 `VerifiedChainClient` 提供。Provider
内部使用固定方法 allowlist 取得 smoldot 已验证数据，公开层不能传入方法名。它的 SDK-only
源码与收编快照一起由 `smoldot/SOURCE_SHA256.json` 分类记录，Core/产品 FFI 则由 Release 的
独立反向闭集固定。

Rust 钱包合同固定 wallet index `0`、账户 index `0` 为 `masterAccountId`、账户 index 范围
`0..1989` 和 SS58 prefix `2027`。`WalletState` 分别校验 create/import 的空 previous 与 append
的严格账户列表前缀，并拒绝 cleanup 命中当前 exact secrets、当前 generation KEK 或重复物理
目标。Engine 仅在 `Running` 时开放 `CHAIN_READ` 及其依赖能力；revisioned
`ChainDatabaseStore` 以 CAS 保存 finalized 锚。跨 Engine 或进程防回退只在 store provider
实现共享、耐久、强原子 CAS 时成立；保留的 legacy Dart Preferences store 不具备该保证。

账户/交易、密钥/金库和业务账户协议是三个层次：公民链 AccountId/余额/nonce/交易属于 Core；
sr25519 与安全存储只负责本地秘密和签名；TUYU、员工登录等 challenge、权限与审计属于 SDK
外部业务。它们可以明确复用同一公钥签名，但不能混为同一业务账户。

全节点出块、全节点 identity 私钥、聊天、OpenMLS、TUYU 与产品业务被排除。候选合同打包
Android `arm64-v8a` 产品 Core/JNI 双库，以及由同一 Core 生成的 iOS 设备与模拟器变体和
macOS `CitizenSDK.xcframework`；根 Dart、Android 与 Apple 均使用产品 ABI。
LinuxARM、LinuxAMD 已具备 Host、Flutter adapter、合同测试和安装消费者源码；第 7.4 步把
两种同版安装投影合并进唯一候选合同，并同步默认 Dart 入口和官方 plugin 注册。尚未执行
Linux 实际编译、测试或生成可分发候选，后续由统一 GitHub CI/Release 验证，不宣称 Linux
已运行或发布。Windows 已有原生 Host、Flutter adapter 和独立 C/C++ 安装消费者；
第 8.4 步同步接入默认 Flutter 注册、`CitizenSdk.open()` 及同版候选/Hosted 运行投影。
Windows 安装件精确 21 项，Hosted Windows 输入精确 33 项；不在宿主内重新编译 Core/Host。
Windows 尚未实际编译、运行或正式发布，源码合同不替代后续统一平台验收。此前
Android AAR 与 Apple 单一 XCFramework 构建通过；
框架只含 iOS 设备与模拟器变体及 macOS 三个 Apple `arm64` machine slice。Apple 本机已编译
iOS 的两组测试 bundle；因无
Simulator runtime 未执行 iOS XCTest。macOS Core 50 项和 Flutter adapter 22 项 XCTest
0 失败，1 项真机硬件用例跳过；normal/supervisor smoke 通过。这不代表真机 Apple
金库已验收，也不代表 TataConsole Flow、远程 CI 或正式 Release 已运行。

iOS 设备与模拟器变体是浅层 framework，install ID 为
`@rpath/CitizenSDK.framework/CitizenSDK`；macOS 使用标准 `Versions/A` framework，install
ID 为 `@rpath/CitizenSDK.framework/Versions/A/CitizenSDK`。候选只允许后者标准布局中的
精确五个内部相对符号链接。Android Gradle/Kotlin persistent project state 必须在
TataConsole 中央 work directory，源码 `android/.kotlin` 禁止。

同一真实 Flutter consumer 已构建 Android release APK（ABI `arm64-v8a`）、iOS device Release
no-codesign、iOS 模拟器变体（Rust target `aarch64-apple-ios-sim`）和 macOS Release；这些是 compile/link 结果，不是
移动真机或 Simulator runtime 结果。Flutter SPM 识别警告与 Android built-in Kotlin 迁移提示
延后到第 9 步 Hosted/Flutter 集成处理。

同一本机闭集的根 Rust workspace 285/285、compile-fail 文档测试 1/1、Clippy 与格式检查
通过；完整 Dart 316/316（`--timeout=2m`）、Hosted 17 文件分析 0 问题，Android 原生
Kotlin/Java 单元测试 Gradle 17 个 task 成功。

任何编译状态和原生产物都必须写入源码树外的中央目录。本机成功产物容器是
`/Users/rhett/TATA/tataconsole/target/gmb/citizensdk`，工作状态容器是
`/Users/rhett/TATA/tataconsole/work/gmb/citizensdk`；永久容器保留，只清理本次
有明确归属的子项，不能在产品源码内生成构建记录。

## Windows Host 与同一 Core

第 8.1 步的 `../windows/` 只增加系统 Host。唯一构建器继续从原 `ffi/Cargo.toml` 生成
`citizensdk.dll`，Host 用 import library 链接它；不在 native/ 新建 Engine、signer 或
provider。TPM 只保护 KEK/DEK，sr25519、链协议和交易实现保持字节不变。

第 8.2 步 Windows Flutter adapter 只消费已安装的同版 Host/Core，不在 native 新增绑定、
算法或平台分支。当时固定22方法，第3步扩展为26方法，第4步加入 QR 后五端统一为36方法；秘密不跨Flutter、关闭BUSY可重试；一次性原生
application_id 声明只固定数据命名空间，不改变 Core 身份或 chain ID。第 8.4 步已把
Windows 纳入默认公开平台与唯一候选。唯一构建器在原生及 C/C++ 消费通过后，执行六项
Flutter adapter CTest 与真实公开 Release 消费者，全部通过才复验并导出；本机 macOS
验证不冒充这些 Windows 测试已经运行。公共链、钱包、交易和签名仍只由同一 Core 实现。
