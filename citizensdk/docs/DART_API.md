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

共享 `citizen/sdk/core/v1` 的 65 方法 tuple 从未定义 mnemonic、password、DEK、child secret、
private key、prepared/result/native handle 或 signed-extrinsic 位置。Android、Darwin、Linux
以及第 8.2 步 Windows adapter 源码都遵守同一秘密不跨 Flutter 的合同。Linux 使用长度保持的标准消息 codec，线上仍是
标准 string tag；内嵌 NUL 的合法备注不得被 GLib 的 NUL 结尾字符串表示截断。

`sdk.qr` 公开严格 `QR_V1` 文本、扫码签名会话、账户公钥编码和亮度图像编解码。
图像统一由 SDK 内 ZXing-C++ 3.1.1 完成。`sdk.qr.scan()` 打开 SDK 自有相机窗口；
已有亮度图像仍可使用 `decodeLuminance`，两者都返回 Core 解析的同一种公开文档。
`CitizenSdkModules.qr` 可单独打开，不启动链、钱包或金库。
`sdk.signing.signQrRequest(text)` 组合 qr、signing、chain，内部完成可信链审阅、原生确认、
设备授权、现有 SigningService 签名和响应编码，返回公开结果及 `qrImage`。
调用方不传时间、待签字节、签名注入或原生审阅句柄。`qr.encode` 是唯一图像生成入口。
无相机、拒绝权限、设备中断、取消或链未就绪都明确失败，不使用第二识别器或降级签名。

`test/consumers/` 是公开 Dart 面的反向编译合同。reference、CitizenApp-shaped、third-party-shaped
和 external signer 四类夹具只能导入 `package:citizen_sdk/citizen_sdk.dart`；测试会拒绝任何
`package:citizen_sdk/src`、内部 platform、外部产品实现或其它 QR 版本。消费 App 的字段与 codec
可以不同，但传给 SDK 的始终只是公开账户、storage key、opaque payload/callData 和执行标识。

Windows adapter 使用官方 StandardMethodCodec 的长度保持字符串。默认 `CitizenSdk.open()`
不需要产品侧包装或别名；宿主在 generated_plugins.cmake 前声明一次
`CITIZENSDK_APPLICATION_ID`，原样作为应用数据命名空间，不是新的 Dart 参数、业务账户
或链身份。不能省略该声明并宣传 Windows 完全零配置。

`lib/src` 中保留的旧 Dart 轻节点、钱包和交易代码是归档差分基线；它们已从
`lib/citizen_sdk.dart` 根入口移除，Android、iOS、macOS、Linux 和 Windows 公开绑定均不可达，也不是新宿主的
公开 API。

Hosted Package 的 Dart 运行时闭包精确为 19 个文件：

```text
lib/citizen_sdk.dart
lib/src/api/citizen_chain.dart
lib/src/api/citizen_qr.dart
lib/src/api/citizen_sdk.dart
lib/src/api/citizen_sdk_error.dart
lib/src/api/citizen_sdk_events.dart
lib/src/api/citizen_transactions.dart
lib/src/api/citizen_sdk_wallet.dart
lib/src/crypto/account_codec.dart
lib/src/models/citizen_account.dart
lib/src/models/citizen_capability.dart
lib/src/models/citizen_chain_state.dart
lib/src/models/citizen_signing.dart
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
`scripts/test.sh flutter --timeout=2m` 执行 316/316。这是历史本地闭集验证，不代表第 7.1 步公开门面
命名统一后重新运行过 Dart 测试，也不代表 Hosted 已上传或 TataConsole 远程 CI 已运行。

真实 Flutter consumer 已从本公开入口完成 Android release APK（ABI `arm64-v8a`）、iOS device Release
no-codesign、iOS 模拟器变体（Rust target `aarch64-apple-ios-sim`）编译和 macOS Release 构建。该结果只证明公开
Dart API、Flutter adapter 与原生投影能够链接成产物；未执行移动真机或 Simulator runtime。
Flutter 对插件 Swift Package Manager 目录的识别警告与 Android built-in Kotlin 迁移提示
留到第 9 步 Hosted/Flutter 集成统一处理。

## 会话与生命周期

通用签名不要求调用方声明业务类型。调用方自行编码业务 payload，再显式选择通用变换；SDK
只按钱包目录中的真实冷热模式路由：

```dart
final outcome = await sdk.signing.begin(CitizenSigningIntent(
  accountId: accountId,
  payload: opaqueBusinessBytes,
  transform: CitizenSigningTransform.substrateSigningPayload(),
  externalSignerTransport: CitizenExternalSignerTransport.qrV1,
  opaqueAction: appOwnedAction,
));
```

热账户直接返回 `CitizenSigningCompleted`；冷账户返回带一次性 `sessionId`、过期时间和
`transportRequest` 的 `CitizenExternalSigningPending`，应用展示/传递二维码后调用
`consumeExternalSignature`。`opaqueAction` 只是应用拥有的 QR 传输字段，SDK 不注册或解析
Square、Vote、CID、旅行、订单等业务语义。`cancel(sessionId)` 只取消本实例尚未完成的签名。

默认账户变化使用 `sdk.wallet.beginDefaultAccountChange`。SDK 固定要求原默认账户签完整目标
排列：热账户直接完成，冷账户返回与独立 CitizenWallet 现有 action 12 互操作的 pending；
`consumeDefaultAccountChange` 成功后才返回提交 revision。普通 reorder API 仍禁止改变首项。

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
final sync = await sdk.chain.getSyncStatus();
final best = await sdk.chain.getBestHead();
final finalized = await sdk.chain.getFinalizedHead();
final canonical = await sdk.chain.getFinalizedBlockAt(BigInt.from(100));
final proven = await sdk.chain.resolveFinalizedBlock(
  canonical.hash,
  canonical.number,
);
final header = await sdk.chain.getBlockHeader(proven);
final body = await sdk.chain.getBlockBody(proven);
final runtime = await sdk.chain.getRuntimeContext(proven);
final value = await sdk.chain.getStorage(proven, applicationOwnedStorageKey);
final values = await sdk.chain.getStorageBatch(
  proven,
  applicationOwnedStorageKeys,
);
final keys = await sdk.chain.getStorageKeysPaged(
  proven,
  applicationOwnedPrefix,
  startKey: previousLastKey,
  limit: 1000,
);
final runtimeOutput = await sdk.chain.callRuntimeApi(
  proven,
  applicationOwnedRuntimeApiMethod,
  applicationOwnedArguments,
);
final events = await sdk.chain.getSystemEvents(proven);
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
- sync status 的 best/finalized 来自同一个 typed smoldot 快照；调用方使用 `isUsable` 判断是否
  可读取，不从 peer count 或高度变化自行制造可信状态。
- `getFinalizedBlockAt` 与 `resolveFinalizedBlock` 只返回 provider 已证明的 canonical finalized
  块；调用方传入的 hash/height/finality 不构成证明。
- Header 会由 Core 重建完整 SCALE Header 并核对 Blake2-256；Body 保留 opaque extrinsic 的
  原顺序；runtime context 只提供准确块的版本与完整 SCALE metadata。
- metadata 的公开功能上限保持 64 MiB。超过宿主单条持久 cache 容量的合法 metadata 仍完整
  返回并在进程内缓存，只是不写可重建的 SQLite runtime cache；Dart 不需要分支或重试。
- storage key 由 App 自己根据业务协议生成。SDK 仅执行准确块读取、optional 值与资源边界校验，
  不知道广场、投票、立法、提案、治理、旅行、商家或其它业务含义。
- storage keys page 只接受准确 finalized block、1..4 KiB prefix、可选排他 startKey 和
  1..1000 limit，直接复用上游 `state_getKeysPaged`；SDK 不自动翻页、排序或解释前缀。
- Runtime API 只接受准确 verified block、1..128 ASCII 的 `Trait_method` 与最大 1 MiB opaque
  arguments，直接复用上游 `state_call` 并返回最大 64 MiB opaque bytes；业务方法名和解码属于 App。
- `getSystemEvents` 只接受 finalized block，并只返回 `System.Events` opaque SCALE bytes；业务
  事件解码属于各 App。`exportState`/`importState` 只运输显式 smoldot 状态，不读取旧 App 数据，
  不承担迁移或兼容。
- 公开 API 没有 `rpc(method, params)`、RPC URL 或预签名 extrinsic 通道。

## 统一钱包目录与冷账户

`sdk.wallet.getState()` 是热账户与仅公钥冷账户的统一只读快照。`accounts` 已按全局顺序排列，
第一项就是 `defaultAccount`；每项包含规范 AccountId、Citizen SS58、名称、创建时间、
`CitizenWalletSignMode.hot/cold`、wallet index，以及仅热账户才有的派生 account index。
`hotProfile` 是同一快照内可选的热钱包投影，不代表全部钱包状态。

```dart
final state = await sdk.wallet.getState();
final imported = await sdk.wallet.importColdAccount(
  ss58Address: scannedPublicAddress,
  name: '离线账户',
);
final reordered = await sdk.wallet.reorderAccountsWithoutDefaultChange(
  expectedRevision: imported.revision,
  accountIds: imported.accounts.map((account) => account.accountId).toList(),
);
final renamed = await sdk.wallet.renameAccount(
  accountId: reordered.accounts.last.accountId,
  name: '长期储备',
);
final afterDelete = await sdk.wallet.deleteAccount(
  renamed.accounts.last.accountId,
);
```

冷账户导入的 `accountId` 与 `ss58Address` 必须且只能提供一个。AccountId 导入由 Core 生成
prefix 2027 的规范地址；SS58 导入由 Core 严格校验 prefix、校验和与规范回编码。冷账户操作
只处理公开数据，不打开认证界面、不调用 Vault，也不创建 SecretRef、generation 或 cleanup。
重复热/冷 AccountId 返回 conflict。

重排必须提交完整、无重复的账户排列和当前 `revision`；旧 revision 返回 conflict，且第一项
必须保持不变，因此该接口不能改默认账户。SDK 不公开无授权 default setter；默认账户变化
必须使用原默认账户签名授权入口。此限制不改变热 profile 内既有
`setActiveAccount` 语义，两者不是同一个字段。

CitizenSDK 不读取或迁移 CitizenApp 的旧钱包。用户重新输入助记词建立热钱包，或重新导入
公钥建立冷账户。CitizenWallet 是独立产品，源码与功能不在本步骤修改范围；后续冷签继续使用
双方既有 `QR_V1` 协议。

## 热钱包

```dart
final profile = await sdk.wallet.getProfile();
final created = await sdk.wallet.create(
  wordCount: CitizenWalletWordCount.words24,
);
final imported = await sdk.wallet.importWallet();
final expanded = await sdk.wallet.addAccounts(const <int>[1, 2]);
final applicationKey = await sdk.wallet.deriveApplicationKey(
  accountId: accountId,
  salt: applicationOwnedSalt32,
  info: applicationOwnedDomain,
);
```

`create`/`importWallet`/`addAccounts` 只启动 SDK 自有的原生安全流程：Android 使用非导出、
`FLAG_SECURE` Activity，Apple 使用共享 Darwin native flow。Dart 方法没有 mnemonic、
password、private key、DEK、prepared
handle、native handle、result handle 或 signed extrinsic 参数/返回槽位。创建的恢复词
只在备份确认前由 SDK 安全界面展示；取消会尝试 release 未提交的准备钱包。若该次释放失败，
native session 仍拥有 handle，后续 `close` 会在 destroy 前重试并在仍失败时关闭失败，不能直接
销毁或把该 handle 遗忘在 Core 外。

公开钱包接口类型固定为 `CitizenSdkWallet`，避免与独立 CitizenWallet 产品重名；不保留旧类型、
typedef、转发文件或兼容导出。`deriveApplicationKey` 只接受 SDK 热账户，金库认证后核对
AccountId 再执行 HKDF-SHA256；salt 必须 32 字节、info 为 1..256 字节，输出恰好 32 字节且
不持久化。冷账户由独立外部设备提供对应材料，SDK 不在本机伪造秘密。

其它热钱包与统一账户操作：

```dart
await sdk.wallet.setActiveAccount(accountId);
final state = await sdk.wallet.renameAccount(accountId: accountId, name: '旅行钱包');
final nextState = await sdk.wallet.deleteAccount(accountId);
await sdk.wallet.delete();
await sdk.wallet.reconcileCleanup();
```

`renameAccount`/`deleteAccount` 同时接受热、冷账户并返回新的统一状态；
`setActiveAccount` 只改变热 profile 的 active 账户，不改变全局默认账户。账户名在 Dart 端
先修剪，再以 1..30 个 Unicode scalar 的规范形式编码。全热钱包删除
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

## 通用交易准备

```dart
final prepared = await sdk.transactions.prepareTransaction(source, callData);
await sdk.transactions.cancelPreparedTransaction(prepared.preparationId);
```

`callData` 必须是调用方依据准确 runtime metadata 编码的 1..1 MiB opaque SCALE RuntimeCall。
SDK 只做协议类型、完整 EOF、canonical 编码、链身份、准确 best block、runtime 与 source nonce
校验，不解释广场、投票、治理、旅行、订单等业务。公开方法只有上述两个位置参数，不接受交易
选项、caller nonce、era、tip 或版本字段；当前构造固定为 SDK 自动 nonce、immortal era、tip=0。

返回的 `CitizenPreparedTransaction` 只包含一次性 `preparationId`、source、callData hash、准确
best block、链上运行时规格号、链上交易格式号与 nonce 摘要。待签消息、payload hash、unsigned/
signed extrinsic 和原生 handle 始终留在 Core。准备对象不持久化，按 Engine/generation 隔离，同一
source 同时最多一个；stop/close 会使其失效。本步骤不签名、不广播、不观察、不写交易历史。

## 通用交易执行

```dart
final started = await sdk.transactions.executePreparedTransaction(
  prepared.preparationId,
);
if (started case CitizenTransactionExternalSigningPending pending) {
  // App 负责展示/扫描交互；response 必须来自既有 QR_V1 外部签名器。
  final completed = await sdk.transactions.consumePreparedTransactionQrResponse(
    pending.executionId,
    response,
  );
}
await sdk.transactions.cancelPreparedTransactionExecution(executionId);
```

`executePreparedTransaction` 只接收一次性 preparationId。Core 从统一 WalletState 判定 hot/cold；
热账户完成强认证和本地签名后返回 `CitizenTransactionExecutionCompleted`，冷账户返回
`CitizenTransactionExternalSigningPending`，只含 executionId、source、callData hash、`QR_V1`
request 和 expiry。三个方法不接受 nonce、签名、signed extrinsic、交易选项或业务对象。

`CitizenTransactionExecutionCompleted` 只表示 `finalizedSuccess`、`finalizedFailed` 或
`poolRejected`。所有 `Uint8List` 字段均防御复制并只读；finalized execution 包含准确块、extrinsic
index 和原始 dispatch 索引，pool rejection 可包含 Usurped replacement hash。取消在广播前阻止广播；
广播或持久化后只停止本次观察，不删除真实 Pending/InBlock。断网、Dropped、Retracted、timeout
不会伪装成链上失败。重启恢复只重发 Core 内持久化的原签名字节，不要求 App 提供或保存它们。

## 通用交易历史

```dart
final firstPage = await sdk.history.getTransactionHistory(limit: 100);
final refreshed = await sdk.history.syncTransactionHistory();
final nextPage = firstPage.nextBeforeExecutionId == null
    ? null
    : await sdk.history.getTransactionHistory(
        beforeExecutionId: firstPage.nextBeforeExecutionId,
        limit: 100,
      );
```

历史只包含这个 SDK 实例实际提交过的 opaque RuntimeCall。`getTransactionHistory` 只读本地
durable store，按 `createdAtMillis, executionId` 确定性倒序分页；limit 为 1..100，游标必须来自
当前快照。`syncTransactionHistory` 一次最多协调 32 条未终态记录，并直接返回同步后的第一页。
两者都不接受账户列表、业务筛选器、区块范围或 pallet/call 参数。

这两个 Dart 方法仍是同一公开 API；变化只在 SDK 内部持久层。Core 通过 `THQ1` 读取 index、
目标 execution 或 limit-bounded page，通过 `THM1` 原子写一组 delete/upsert/meta，不再加载或
重写其它 execution。平台 SQLite 是 Host 适配，不是 Dart API，也不是 App 业务数据库。

历史内部同时限制 4,096 条与 31 MiB durable weight。执行前使用冻结 transaction template 的
准确长度做签名前预检，pending 写入时复检；只有最旧终态可被驱逐，Pending/InBlock 不会因资源
压力被删除。无法容纳返回稳定 `conflict`，公开方法不增加容量参数或 App 业务策略。

`CitizenTransactionHistoryRecord` 只含 execution/source/call/transaction hash、状态、时间、可选
verified block、同 index System 执行结论、replacement hash 和受限 pool rejection reason。
它不含 nonce、callData、SigningPayload、签名、signed extrinsic、destination、amount、remark、
direction、业务 pallet/event 或业务文案。

txHash、`Ready`、`Broadcast`、`InBlock` 或 provider `Finalized` 都不等于链上执行成功。只有精确
canonical finalized body 中唯一命中的完整 extrinsic 与同 index
`System.ExtrinsicSuccess/Failed` 才形成最终执行结论；`Invalid/Usurped` 才形成 poolRejected。
取消、断网、dropped/retracted 或 timeout 不删除 Pending/InBlock。目的账户、金额、备注、方向、
转账/投票/治理等业务历史由各消费 App 根据自己的 callData 和业务事件维护。

## Flutter 传输协议

Flutter 内部通道固定为：

```text
MethodChannel  citizen/sdk/core/v1
EventChannel   citizen/sdk/events/v1
```

65 个方法的请求、响应、事件、错误及所有嵌套值都是固定长度、固定位置的
`List` tuple。任意层级的 `Map`、未知枚举、额外字段、跨 session 响应、request/event
序号缺口或乱序都失败关闭，没有兼容旁路。该协议是 binding 内部实现细节，
不是业务应用应直接调用的公共 API。
数值布尔位只接受整数 `1`，拒绝浮点 `1.0`等宽松类型；session ID 长度按
1..128 个 UTF-16 code units 计算，Dart、Swift 与 Kotlin 使用同一边界，包含代理项的字符串
不能因语言各自的字符计数方式而分叉。

错误 tuple 固定为 `[1, sessionId?, requestSequence?, errorCode, failureStage, method,
errorMessage?]`。`CitizenSdkException` 暴露同一 22 类 code、八阶段 stage、固定方法名和
可选关联字段；未知 stage、非 65 项 method 或关联不一致均按 decode/integrity 失败关闭。
阶段仅供诊断和策略选择，不能用来推断链上执行成功。

open 仅接受 `[1, modules]`。无会话 `verifySignature` 仅接受
`[1, accountId, signature, payload]`、返回 `[1, bool]`；错误沿用 PlatformException，
session/sequence 为 null。它直接调用同一 Rust 纯验签，不创建 session、事件订阅、链、数据库
或金库；不接受旧 session 形状。其余 session 方法保持原请求/响应外壳。

新增的 `getGenesisHash` 使用空 fields 请求，返回一个规范 hash；`getAccountBalances`
接收一项账户列表，返回一项既有余额 tuple 列表。五端绑定共同验证数量、逐项账户及同块约束，
不另行查询、合并或计算余额。

链方法与上面的 Dart facade 一一对应。块 tuple 固定为
`[hash, numberDecimal, finality]`；同步状态、Header、Body、Runtime 和导出状态都使用各自的
固定位置 tuple。storage key 必须为 1..4 KiB，batch 必须为 1..1024 项且 key 总量不超过
1 MiB；Header digest 上限 1 MiB，Body/metadata 与 storage batch 响应聚合上限 64 MiB，
状态 database 上限 256 KiB。任何层级类型、长度、顺序、finality 或 import 回执不一致均失败关闭。

公开事件增加 `CitizenSdkFinalizedBlockChanged`，只携带同一 SDK chain monitor 已验证的
finalized block tuple；它复用唯一 smoldot finalized 订阅，不建立轮询或第二订阅。业务 App
收到事件后自行读取、解码和更新自己的业务状态。

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
