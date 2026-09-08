# CitizenSDK Dart/Flutter 公共接口

当前公开门面为 `sdk.wallet`、`sdk.signing`、`sdk.chain`、`sdk.transactions`、
`sdk.history`、`sdk.qr`。钱包管理与签名独立，QR 也不与 signing 合并；五端功能逻辑统一由 Rust 实现。
`CitizenSdk.open(modules: CitizenSdkModules.full)` 默认全选；按需使用时组合
`CitizenSdkModules` 的具名常量，组合依赖与编译支持由 Rust 统一验证，数值以唯一 SDK 字典为准。
模块选择只改变运行期资源，不裁剪现有 full 包或链资产。模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

## 当前交付边界

根入口只公开 ABI v1 的类型化 API：

```dart
import 'package:citizen_sdk/citizen_sdk.dart';
```

Android、iOS 与 macOS 已安装正式 binding。iOS 和 macOS 在 `pubspec.yaml` 中共同使用
`sharedDarwinSource: true`，由 `darwin/` 的同一 Swift/Flutter adapter 投影产品 ABI。
第 7.4 步把 LinuxARM/LinuxAMD 同时纳入候选合同、官方 `linux` plugin 注册及默认
`CitizenSdk.open()`，直接使用 `CitizenSdkPlugin` 和同一 transport，不注入内部 platform。
第 8.4 步用同样方式纳入 Windows 默认入口、官方自动注册和同版运行投影。
未支持的 Flutter 平台在进入通道前返回 `CitizenSdkErrorCode.unsupported`；
已支持平台缺少同版原生插件时同样失败关闭，不用另一套实现冒充 session。
Linux/Windows 实际编译、CTest、C/C++/Flutter 与平台 UI/TPM 运行仍由后续统一 GitHub
CI/Release 验证，当前源码注册不是正式发布或这些平台运行通过。
iOS 模拟器变体可运行产品 ABI 与公开链能力，但没有 Secure Enclave；硬件金库、钱包和
依赖它们的签名/交易能力必须通过 capability snapshot 报告不可用。

共享 `citizen/sdk/core/v1` 的 36 方法 tuple 从未定义 mnemonic、password、DEK、child secret、
private key、prepared/result/native handle 或 signed-extrinsic 位置。Android、Darwin、Linux
以及第 8.2 步 Windows adapter 源码都遵守同一秘密不跨 Flutter 的合同。Linux 使用长度保持的标准消息 codec，线上仍是
标准 string tag；内嵌 NUL 的合法备注不得被 GLib 的 NUL 结尾字符串表示截断。

`sdk.qr` 公开严格 `QR_V1` 文本、扫码签名会话、账户/转账编码和亮度图像编解码。
图像统一由 SDK 内 ZXing-C++ 3.1.1 完成。`sdk.qr.scan()` 打开 SDK 自有相机窗口；
已有亮度图像仍可使用 `decodeLuminance`，两者都返回 Core 解析的同一种公开文档。
`CitizenSdkModules.qr` 可单独打开，不启动链、钱包或金库。
`sdk.signing.signQrRequest(text)` 组合 qr、signing、chain，内部完成可信链审阅、原生确认、
设备授权、现有 SigningService 签名和响应编码，返回公开结果及 `qrImage`。
调用方不传时间、待签字节、签名注入或原生审阅句柄。`qr.encode` 是唯一图像生成入口。
无相机、拒绝权限、设备中断、取消或链未就绪都明确失败，不使用第二识别器或降级签名。

Windows adapter 使用官方 StandardMethodCodec 的长度保持字符串。默认 `CitizenSdk.open()`
不需要产品侧包装或别名；宿主在 generated_plugins.cmake 前声明一次
`CITIZENSDK_APPLICATION_ID`，原样作为应用数据命名空间，不是新的 Dart 参数、业务账户
或链身份。不能省略该声明并宣传 Windows 完全零配置。

`lib/src` 中保留的旧 Dart 轻节点、钱包和交易代码是归档差分基线；它们已从
`lib/citizen_sdk.dart` 根入口移除，Android、iOS、macOS、Linux 和 Windows 公开绑定均不可达，也不是新宿主的
公开 API。

Hosted Package 的 Dart 运行时闭包精确为 18 个文件：

```text
lib/citizen_sdk.dart
lib/src/api/citizen_chain.dart
lib/src/api/citizen_qr.dart
lib/src/api/citizen_sdk.dart
lib/src/api/citizen_sdk_error.dart
lib/src/api/citizen_sdk_events.dart
lib/src/api/citizen_transactions.dart
lib/src/api/citizen_wallet.dart
lib/src/crypto/account_codec.dart
lib/src/models/citizen_account.dart
lib/src/models/citizen_capability.dart
lib/src/models/citizen_chain_state.dart
lib/src/models/citizen_transaction.dart
lib/src/models/citizen_wallet.dart
lib/src/platform/citizen_sdk_flutter_codec.dart
lib/src/platform/citizen_sdk_flutter_sessions.dart
lib/src/platform/citizen_sdk_platform.dart
lib/src/platform/flutter_citizen_sdk_platform.dart
```

根包运行依赖只有 Flutter SDK 与 `polkadart_keyring`；legacy/差分源码所需其余依赖只是
dev dependencies，且相应源码由 `.pubignore` 排除，不会成为宿主的运行时闭包。

此前第 6 步本机对当时的 17 文件 Hosted 闭包执行分析为 0 问题；完整 Dart 套件使用
`flutter test --timeout=2m` 执行 316/316。这是历史本地闭集验证，不代表第 7.1 步公开门面
命名统一后重新运行过 Dart 测试，也不代表 Hosted 已上传或 TataConsole 远程 CI 已运行。

真实 Flutter consumer 已从本公开入口完成 Android release APK（ABI `arm64-v8a`）、iOS device Release
no-codesign、iOS 模拟器变体（Rust target `aarch64-apple-ios-sim`）编译和 macOS Release 构建。该结果只证明公开
Dart API、Flutter adapter 与原生投影能够链接成产物；未执行移动真机或 Simulator runtime。
Flutter 对插件 Swift Package Manager 目录的识别警告与 Android built-in Kotlin 迁移提示
留到第 9 步 Hosted/Flutter 集成统一处理。

## 会话与生命周期

`await sdk.wallet.viewAccountPrivateKey(accountId)`启动SDK自有原生安全查看，只需钱包模块。
用户确认后通过现有设备认证；公开结果只有完成、取消或错误，不返回私钥字符串、字节或内部句柄。
关闭、真实后台或锁屏永久结束本次查看，恢复前台不会自动展示；Future等待原生清屏与Core真实排空。

```dart
final sdk = await CitizenSdk.open();
await sdk.start();
final capabilities = await sdk.getCapabilities();
await sdk.stop();
await sdk.close();
```

- `open` 只按 modules 创建独立 Core session，不隐式启动轻节点；未选 chain 不加载链资产或创建链数据库。
- `start` 和 `stop` 是独占生命周期操作；它们等待较早请求收口，期间不接纳
  新操作。
- 普通链、钱包和历史请求可并发；request sequence 只用于精确关联，
  不按返回顺序猜测。
- `close` 首先封闭新请求、取消可取消的交易观察并等待已接纳工作。
  Running session 只能在 checkpoint/stop 成功后 destroy；失败时保留实例供重试。
- Apple 绑定把 callback clear 与 destroy 重试保存为单调关闭阶段。一旦开始部分关闭，
  该 facade 不再恢复接纳请求；显式 close、Flutter detach 或 deinit 未能收口时，整个
  facade 由进程级 supervisor 继续重试，直到 Core destroy 成功后才释放宿主上下文。

## 链读取

`sdk.chain` 只提供 Core 已验证的类型化入口：

```dart
final genesisHash = await sdk.chain.getGenesisHash();
final finalized = await sdk.chain.getFinalizedHead();
final balance = await sdk.chain.getAccountBalance(accountId);
final balances = await sdk.chain.getAccountBalances(accountIds);
final nonce = await sdk.chain.getAccountNonce(accountId);
final fee = await sdk.chain.getFeeSnapshot();
```

- genesisHash 来自 Core 固定链身份，不要求 start 或联网；必须已选择 chain 模块。
- balance 锚定 finalized 块；balances 复用同一 Core 批量读取，所有项锚定同一个 finalized 块。
- 批量输入允许 0..1990 项，保留输入顺序和重复账户；空输入仍送 Core 校验模块、生命周期和链能力。
- 批量查询不依赖钱包、签名或历史，不返回部分成功；有限读取完成前不能通过取消提前释放原生资源。
- nonce 锚定同一准确 best runtime snapshot，不是交易池 nonce 租约。
- fee snapshot 来自同一 best 块的 runtime context。
- 公开 API 没有 `rpc(method, params)`、RPC URL 或预签名 extrinsic 通道。

## 热钱包

```dart
final profile = await sdk.wallet.getProfile();
final created = await sdk.wallet.create(
  wordCount: CitizenWalletWordCount.words24,
);
final imported = await sdk.wallet.importWallet();
final expanded = await sdk.wallet.addAccounts(const <int>[1, 2]);
```

`create`/`importWallet`/`addAccounts` 只启动 SDK 自有的原生安全流程：Android 使用非导出、
`FLAG_SECURE` Activity，Apple 使用共享 Darwin native flow。Dart 方法没有 mnemonic、
password、private key、DEK、prepared
handle、native handle、result handle 或 signed extrinsic 参数/返回槽位。创建的恢复词
只在备份确认前由 SDK 安全界面展示；取消会尝试 release 未提交的准备钱包。若该次释放失败，
native session 仍拥有 handle，后续 `close` 会在 destroy 前重试并在仍失败时关闭失败，不能直接
销毁或把该 handle 遗忘在 Core 外。

其它钱包操作：

```dart
await sdk.wallet.setActiveAccount(accountId);
await sdk.wallet.renameAccount(accountId: accountId, name: '旅行钱包');
await sdk.wallet.deleteAccount(accountId);
await sdk.wallet.delete();
await sdk.wallet.reconcileCleanup();
```

账户名在 Dart 端先修剪，再以 1..30 个 Unicode scalar 的规范形式编码。全钱包删除
必须同时完成密文墓碑与 generation 永久退役；物理清理未完时由
`reconcileCleanup` 重放，不得把空槽视为已安全删除。

## sr25519 本地签名

```dart
final signature = await sdk.signing.sign(
  accountId: accountId,
  payload: Uint8List.fromList(protocolPayload),
);
```

签名仅引用同一宿主已有的 SDK 安全账户与设备金库；首次 provision 仍需钱包安全流程。
签名-only 不开放钱包管理接口，不增加秘密导出。公开纯验签无需 open 或任何模块实例：

```dart
final valid = await CitizenSigning.verify(
  accountId: accountId,
  signature: signature.bytes,
  payload: Uint8List.fromList(protocolPayload),
);
```

payload 长度允许 `0..16 MiB`，空载荷是有效的明确消息。签名 context 固定为 `substrate`。通用 payload
签名把宿主应用视为受信任调用方；TUYU 等业务协议的 domain、challenge、序列化
和服务端授权记录仍由业务协议负责，不是 CitizenSDK 交易协议。

## 链上转账与历史

```dart
final terminal = await sdk.transactions.transferWithRemark(
  sourceAccountId: source,
  destinationAccountId: destination,
  amountFen: BigInt.from(1250),
  remark: '公开备注',
);
```

这是唯一高层钱包交易入口。Core 在 Rust 内完成 nonce/runtime 读取、V4
extrinsic 构造、sr25519 签名、本地 hash、pending-before-broadcast、submit-and-watch
和 finalized 执行核验。Future 只返回下列明确终态：

- `finalizedSuccess`：精确 extrinsic index 存在 `System.ExtrinsicSuccess`。
- `finalizedFailed`：同 index 存在 `System.ExtrinsicFailed`。
- `poolRejected`：交易池明确 `Invalid` 或 `Usurped`。

txHash、`Ready`、`Broadcast`、`InBlock` 或 provider `Finalized` 都不等于链上执行成功。
`sdk.events` 还会返回与 Dart request sequence 精确关联的进度和终态事件；
`Usurped` 保留替代交易哈希。取消、断网、dropped/retracted 或 timeout 不会删除
已持久的 Pending/InBlock 事实。

同账户有未决记录时，以相同 destination、amount 和 remark 再次调用此入口恢复原交易，
不读取新 nonce、不再次解锁或签名。Core 先同步 finalized 历史；原交易已经执行则返回
核验终态，否则仅恢复已持久化的完整授权字节。不同参数返回 Conflict。取消观察不撤销
链上交易；未决交易收敛后，相同参数可以表示另一笔新交易。恢复字节不会返回 Dart。

finalized 历史使用：

```dart
final initial = await sdk.history.initializeFinalizedHistory(accountIds);
final next = await sdk.history.syncFinalizedHistory(accountIds);
```

`accountIds` 必须包含 1..1990 个规范 AccountId，且整份列表不得重复。Dart 在建立 session 请求前
拒绝空列表、超限和重复项；Android Kotlin facade 与 Darwin Swift adapter 在产品 ABI 前独立
执行同一合同，不能依赖下层集合去重后猜测调用方意图。

历史包含逐账户游标、本机 pending/终态记录和经 Runtime metadata 解码的 finalized
转账流水。调用方只获得公开事实，不获得秘密、签名 payload 内部状态或原始
signed extrinsic。

## Flutter 传输协议

Flutter 内部通道固定为：

```text
MethodChannel  citizen/sdk/core/v1
EventChannel   citizen/sdk/events/v1
```

36 个方法的请求、响应、事件、错误及所有嵌套值都是固定长度、固定位置的
`List` tuple。任意层级的 `Map`、未知枚举、额外字段、跨 session 响应、request/event
序号缺口或乱序都失败关闭，没有兼容旁路。该协议是 binding 内部实现细节，
不是业务应用应直接调用的公共 API。
数值布尔位只接受整数 `1`，拒绝浮点 `1.0`等宽松类型；session ID 长度按
1..128 个 UTF-16 code units 计算，Dart、Swift 与 Kotlin 使用同一边界，包含代理项的字符串
不能因语言各自的字符计数方式而分叉。

open 仅接受 `[1, modules]`。无会话 `verifySignature` 仅接受
`[1, accountId, signature, payload]`、返回 `[1, bool]`；错误沿用 PlatformException，
session/sequence 为 null。它直接调用同一 Rust 纯验签，不创建 session、事件订阅、链、数据库
或金库；不接受旧 session 形状。其余 session 方法保持原请求/响应外壳。

新增的 `getGenesisHash` 使用空 fields 请求，返回一个规范 hash；`getAccountBalances`
接收一项账户列表，返回一项既有余额 tuple 列表。五端绑定共同验证数量、逐项账户及同块约束，
不另行查询、合并或计算余额。

需要 session 的调用中，每个 Flutter engine 只有一个 EventChannel router；它在发出 native `open` 前先订阅，
按 session 隔离有界暂存早到事件。`open` 响应携带该 session 的准确 event baseline，Dart
建立 session 后才按序排空；不存在“每个 session 在 open 后另订阅一次”的丢事件窗口。

所有 u64/u128、时间戳与区块高度都以规范非负十进制字符串跨通道；平台 adapter 将 u32 字段
无损投影后由 Dart 再验证其范围。AccountId 与 hash 使用 `0x` 加 64 位小写十六进制字符串；
`Uint8List` 只用于 payload、签名、备注原始字节等真实字节槽。native/prepared/result handle 与
signed extrinsic 没有 tuple 位置。

## 分发状态

源码已使用 `name: citizen_sdk` 和 `version: 1.0.0`，但本步不执行 Hosted Registry
上传。首次正式发布完成前，不得对外宣称 `citizen_sdk: ^1.0.0` 已可下载。
