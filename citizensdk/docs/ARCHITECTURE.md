# CitizenSDK 技术架构

当前六模块是 wallet、signing、chain、transactions、history、qr，默认 full=63，按位组合并由 Rust
在平台资源创建前验证依赖和编译支持。钱包管理与签名不互相隐式启用，history 独立。
无链组合不构造 smoldot、读取链资产或创建链数据库；未选历史不初始化其服务。
单独 qr=32 只构造 Rust `QR_V1` 协议/会话状态，不创建钱包、金库、链数据库或轻节点。
图像路径是五端共用的 ZXing-C++ 3.1.1 窄包装，平台只提供 8 位亮度帧，不存在第二识别器或回退引擎。
SDK 自有扫描窗口使用 AVFoundation、CameraX、Media Foundation 或 GStreamer 采集，不把扫描界面留给产品实现。
`native/engine/src/qr_review.rs` 复用现有已验证 metadata 做完整链调用审阅；`native/ffi` 持有
不可变、绑定实例、一次消费的审阅结果，确认后调用原有 SigningService。
链调用扫码签名显式依赖 qr、signing、chain；不要求 wallet、transactions 或 history。
普通 signing-only 和 QR-only 保留各自独立能力，不由扫码签名入口隐式启动链。
运行期模块选择不裁剪现有 full 正式包与链资产。模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

## 单一产品原则

第 12 步 P1 加固不改变分层：交易原授权与 Pending 原子持久化、恢复协调及 hook 流水
语义归 Engine/Contracts；有界完成槽位归 FFI；生物识别线程、应用数据命名空间和 SQLite
DMS 归平台 Provider。CI/Release 继续使用中央 citizensdk 唯一流程，不建立第二套构建器。
P2 加固同时固定跨进程 Vault 临界区、持久 revision 解码、准确 capability 原因、唯一交易
hash 名称以及绑定层事件/字节类型合同；这些修复不改变分层或新增业务能力。

CitizenSDK 是一个产品、一个版本和一条分发链。轻节点、钱包和 signer 是内部能力层，
不拆成可独立发布的第二套 SDK。产品级唯一 C ABI 已在第 3 步建立；最终 Flutter/Dart、
Swift、Kotlin/Java 与 C/C++ 都只通过该 ABI 使用 Rust Engine。

依赖方向固定为：

1. 宿主 App 依赖对应官方语言绑定；当前根
   `package:citizen_sdk/citizen_sdk.dart`、Android Kotlin/Java 与 Flutter，以及 Apple 共享 Darwin
   源码的 Swift 与 Flutter 投影已经使用产品 ABI。
2. 语言绑定只依赖已冻结的产品级 C ABI，不实现链、钱包、交易或密码学。
3. C ABI 只调用 `CitizenSDK Core Engine`，固定生命周期、所有权、错误、事件和能力查询。
4. Engine 只依赖类型化 contracts；smoldot、sr25519、系统金库和状态仓储实现这些合同。
5. provider 分别依赖收编的 smoldot PoW、`schnorrkel` 和宿主操作系统安全设施。

上述产品 ABI 与 Engine 路径已经由根 Dart API、Android 以及 iOS/macOS 正式绑定消费。
SDK 自有旧 Dart 轻节点协调、钱包、交易与 Preferences 实现已删除；正式能力和测试由
Rust Core 承接，只保留受保护的 smoldot 来源快照作上游审计输入。

原生核心与产品无关 Dart 层不得反向依赖 CitizenApp、CitizenWallet、TuyuLove、TuyuLife、
TuyuBooking、聊天、广场、TUYU 协议、产品导航或产品数据库。

第 1.9 步用 `test/consumers/` 固化这一依赖方向。reference consumer 同时组合 wallet、signing、
qr、chain、transactions、history 六类公开接口；CitizenApp-shaped 与 third-party-shaped fixture
只在各自测试目录定义业务 key、event decoder 和 RuntimeCall encoder；external signer 只组合
`CitizenSigning` 与 `CitizenQr`。四者均只导入根公开库，不得导入 `lib/src`、内部符号或其它产品源码。

## 目录结构

```text
citizensdk/
├── lib/                    唯一 citizen_sdk 包及内嵌 smoldot Dart 绑定
├── native/
│   ├── contracts/          VerifiedChainClient、signer、vault 与类型化存储合同
│   ├── engine/             产品无关 Core 协调、核验与能力解析
│   ├── ffi/                唯一 citizensdk_* 产品 C ABI
│   ├── signer/             唯一 sr25519 原生实现
│   └── smoldot/
│       ├── provider/       VerifiedChainClient 的真实 smoldot 实现
│       ├── ffi/            仅供 macOS `arm64` 差分测试的 legacy 原生入口
│       └── pow/            PoW + GRANDPA 轻节点 Rust 快照
├── include/                唯一产品 C/C++ 头文件与所有权说明
├── android/                Android 插件与硬件金库
├── darwin/                 iOS/macOS 共享 Apple 投影
│   ├── Sources/CitizenSDK/ Rust Core 的 Swift API、typed stores、Vault 与 SDK-owned UI
│   └── Sources/CitizenSDKFlutter/ 只消费 CitizenSDK.framework 的 Flutter adapter
├── linux/                  LinuxARM/LinuxAMD 共用 Host、C/C++、Flutter adapter 与 TPM Vault
├── assets/
│   ├── README.md           随包静态资产与设备运行状态边界
│   └── citizenchain/       manifest、chain spec 与 #0 light sync state
├── scripts/                外部原生构建与确定性候选工具
├── test/                   根包合同测试及迁入的 smoldot 测试
└── docs/                   产品技术文档和 smoldot 来源记录
```

根 `pubspec.yaml` 是唯一有效包清单，不含仓库本地 `path` 依赖。原 smoldot Dart 生产绑定
机械迁入 `lib/src/smoldot`，测试和夹具迁入 `test/smoldot`，历史包清单与来源说明归档到
`docs/smoldot-dart`。smoldot 只作为 CitizenSDK 内部实现参与同一版本和同一发布，不形成
第二个 SDK 或第二个源码真源。

`native/contracts`、`native/engine` 与 `native/ffi` 是 CitizenSDK 自有 Rust Core/ABI 源码，
由独立反向闭集固定。`native/smoldot/provider` 同样是 SDK-only 适配，但因为它与收编的
smoldot 快照共同演进，所以在 `native/smoldot/SOURCE_SHA256.json` 中单独分类。根 Rust
workspace 管理 contracts、engine、ffi、signer 和 provider；PoW/light-base 保留各自嵌套
workspace 的已验证解析语义。engine 精确固定官方 `subxt-core = 0.43.0`，只用于 SCALE
metadata、`System.Events` 与 extrinsic 哈希语义。

## Rust Core 合同与 Engine

`native/contracts` 冻结以下边界：

- `VerifiedChainClient`：只提供携带 best/finalized 语义的类型化区块、storage、runtime、
  提交、观察和状态导入导出；`resolve_finalized_block(hash,height)` 把不受信任宿主输入解析为
  provider 已证明的历史 finalized canonical 块，不提供任意 `rpc(method, params)`。
- `ChainSigner` 与 `SecretVault`：分别拥有 sr25519 和设备密文/认证职责，不能把 Secure
  Enclave、Keystore 等系统金库冒充为 sr25519 signer。
- `ChainDatabaseStore`、`RuntimeCacheStore`、`WalletProfileStore`、
  `TransactionHistoryStore` 与 `EncryptedSecretBlobStore`：按数据等级隔离，最后一项只能
  接受加密信封。加上 `SecretVault` 共六个隔离边界。
- 十项固定能力的 revisioned snapshot：`CHAIN_READ`、`TRANSACTION_BUILD`、
  `TRANSACTION_SUBMIT`、`TRANSACTION_VERIFY`、`WALLET_PROFILE`、`LOCAL_SIGNING`、
  `HARDWARE_VAULT`、`USER_AUTHENTICATION`、`HISTORY`、`BACKGROUND_SYNC`。每项分别表达
  `supported`、`available`、`enabled`、`ready` 和稳定 reason；能力发现不能替代敏感操作的
  即时复核。
- `WalletState`：固定唯一热 wallet index `0`、Citizen SS58 prefix `2027`；热账户 index `0`
  必须等于 `masterAccountId`，热账户 index 范围为 `0..1989`。仅公钥冷账户从本机 wallet
  index `1` 单调分配且不复用，没有 `SecretRef` 或 generation。热、冷 AccountId 全局唯一，
  `orderedAccountIds` 必须是二者的无重复精确排列，第一项是全局默认账户。create/import provisioning 使用
  空前态并精确拥有目标全部 secrets；append 的前态必须是目标账户列表的严格前缀，既有
  profile 字段与账户逐项不变，计划只拥有新增账户的 exact refs。cleanup/queue 不得命中
  当前 profile 引用的 exact account secret 或当前 generation 的 wallet key；active cleanup
  与 queue 的 operation ID 和物理目标不得重复。`EncryptedSecretBlobStore` 的
  `Vacant -> Sealed -> Tombstone` 单向状态机和 `SecretVault` 的 generation retirement 是
  跨进程迟到写入 fence，进程内 mutex 不能替代。

第 1.1 步的统一钱包实现目录职责固定如下：

- `native/contracts/src/wallet.rs`：热/冷值对象、SS58 严格解析、目录不变量和热生命周期计划。
- `native/contracts/src/store/wallet_profile.rs`：把完整钱包状态冻结为一个无秘密 CAS 单元。
- `native/engine/src/wallet_service.rs`：冷热重复检查、冷账户增删改、全局顺序，以及热钱包变化
  对冷目录的保留规则；冷路径不得调用 Vault。
- `native/engine/src/engine.rs`：仅 Rust 内部调用面；本步骤不形成产品 C ABI。
- `native/ffi/src/host_codec.rs`：wallet typed payload v2 的唯一严格编码/解码；明确拒绝 v1，
  不提供迁移或 fallback。
- `native/contracts/tests`、`native/engine/src/wallet_service_tests.rs`、
  `native/ffi/src/host_codec_tests.rs`：分别验证模型不变量、Engine 行为/零金库调用和持久化格式。

`native/engine` 实现能力依赖收敛、准确区块 runtime context 缓存、仅启动前且不倒退的
状态导入门禁，以及交易执行结论。导入会把本 Engine provisional anchor 与 revisioned
`ChainDatabaseStore` 已持久锚合并，先拒绝回退/冲突，再调用 provider；provider 或 CAS
产生不确定副作用后失败会永久关闭该 Engine。跨 Engine 或进程的防回退保证要求 store
adapter 提供共享、耐久、强原子 CAS。链读取
能力还受 Engine lifecycle 约束，只有 `Running` 才能 ready。持久 `RuntimeCacheStore` 只允许
作为性能缓存，交易终态核验必须直接从 provider 取得目标 finalized 块的 runtime context，
不能把宿主可写缓存提升为执行证据。组件缺失会关闭对应 capability；
当其余 probe 均 ready 时归因为 `host_disabled`。完整签名 extrinsic 先按
Substrate 规则计算哈希，在准确
块体中定位 index，再使用同一块 metadata 解码该 index 的 `System.ExtrinsicSuccess/Failed`；
缺失、畸形、矛盾或跨块证据一律返回未核实。Engine 复用
`test/transaction` 的生产 CitizenChain metadata/events 夹具，没有复制第二份输入。

Core runtime metadata 的功能合同为 64 MiB。进程内准确块 cache 保留 64 项并可承载完整合同；
四个平台的持久 runtime cache 是 8 MiB 完整记录、64 项 FIFO 的可重建性能层，metadata 可持久
部分为 `8 MiB - 111 bytes`。Engine 查询顺序固定为内存、持久 cache、provider。超过持久容量但
不超过 Core 上限的 provider context 正常完成链读取并进入内存，只跳过持久写入；缓存容量不能
反向改变链能力，也不增加旧记录迁移或兼容分支。

host 组合的链数据库生命周期由同一 Engine 原语闭合：start 在 provider start 前执行
typed-store restore；export 使用稳定 finalized 锚导出并以完整 `revision + state` CAS；
graceful stop 在任何退订、服务或 provider 停止副作用前完成同一持久化。失败时保持 Running
可重试。直接 destroy 不等待异步平台 checkpoint，因此宿主必须先 stop；legacy session 仍只
使用显式 import/export。host start/stop/import 共用独占 admission：先前异步请求未完成时不
受理，受理后直到完成都排斥新请求、callback/subscription 控制与 destroy；stop 仅允许当前
独占 request 自己关闭此前已经存在的 capability monitor。

第 4.1/4.2 步建立的 Core 服务在本次将签名单列后，当前职责如下：

- 账户状态：从准确 metadata 生成 finalized `System.Account` storage key，解码
  free/reserved/total；batch 先去重再按原顺序及重复项重建。链上费率、最低费与存在性存款
  绑定同一 best runtime metadata；nonce 只接受同一次
  `AccountNonceApi_account_nonce` Runtime call 携带的账户、hash、高度与值，并复核准确 best
  身份。该值不包含交易池，持久同账户 Pending/InBlock single-flight 防止本地重复使用。
- 钱包管理：English BIP-39 12／18／24 词、可选 NFKD password、`//0..//1989` 派生，以及
  create/import/add/usable/rename/activate/delete/reconcile；并管理仅公钥冷账户的
  AccountId/SS58 导入、改名、删除、统一排序和默认账户。create 固定为 prepare（零持久
  写入、一次性恢复词会话）→用户确认备份→commit，消除持久钱包先于恢复词展示的崩溃窗口；
  `bip39`、password 和 NFKD 临时值均进入 zeroize 生命周期。公开事实先以 revision CAS 保存
  provisioning，generation/owner/operation 精确拥有秘密与 cleanup；写后异常由 exact readback
  收敛。冷账户没有秘密生命周期且不会调用 Vault；金库解锁秘密始终留在 Rust
  `SecretBuffer`，Rust Core 不提供私钥导出。
  产品 ABI 的 prepared-wallet handle 绑定 owner instance，只允许显式创建/备份 UI 复制助记词；
  import/add 的恢复词只能来自用户明确输入，private key 与 child secret 永不导出。
- 独立签名：`SigningIntent` 保存 AccountId、不透明 payload 和 raw/Substrate/domain 三类通用
  transform；Engine 从 WalletState 判定冷热模式。热账户通过 `SigningService`、设备金库和
  强认证签名并自验；冷账户进入可选 external transport，绝不回退读取 Vault。QR_V1 只编码
  任意有界 opaque action，不解析或登记 App 业务。默认账户变更冻结完整目录、revision、genesis、
  expiry 和 nonce，由原默认账户签名后 CAS，Rust 内部也没有绕过授权的 raw setter。
  纯验签是无实例公开工具，既不需要启用签名模块，也不建立 session、订阅或金库。
- 通用安全链读取：同一 `VerifiedChainClient` 公开单快照同步状态、best/finalized 链头、
  finalized canonical 块解析、准确块 Header/Body/Runtime、opaque storage 单项/批量读取、
  finalized `System.Events` 原始字节和显式状态导入导出。Provider 重新核对 block hash/height、
  Header SCALE/Blake2-256、返回顺序和资源上限；Engine 只投影协议级事实。业务 App 根据
  runtime metadata 自己生成 storage key、解释 call/event，SDK 不包含业务 pallet/call DTO。
- 通用交易准备：`prepareTransaction(sourceAccountId, callData)` 把 App 已编码的 opaque SCALE
  RuntimeCall 交给同一 Rust Core。Engine 在一个准确 best block 上读取 metadata、runtime、genesis
  与 source nonce，用 metadata outer-call 类型完整消费并 canonical 回编码，固定采用 immortal era
  与 tip `0`。generation-scoped registry 每个 source 只保留一个一次性准备对象；内部 signer message
  和 extrinsic 模板不跨 ABI，公开层只有不可伪造标识与安全摘要。各 App 的转账、投票、治理等
  业务 call 编码只能把最终 opaque callData 交给这一通用 builder。
- 通用交易执行：一次性 preparation 原子 claim 后重新核对 chain identity、runtime、nonce、signed
  extensions 与完整模板，再按 WalletState 走热钱包强认证或既有 `QR_V1` 冷签。签名只填入冻结槽并
  自验；完整授权记录必须先 CAS、写后回读再创建 provider watch。准确 canonical body 和同 index
  `System.Events` 是唯一 finalized 终态来源；重启只核验并重发同一原始 extrinsic，不重新签名。
- 通用执行历史：构造与恢复材料保持 Engine 私有。Core 先以完整 extrinsic hash 持久化 source、
  callData hash、nonce、opaque callData 和 signed extrinsic，再访问 provider；公开 page 仅白名单
  投影 hash、协议状态、验证块/System 结论与时间。raw pre-signed submit 只供无交易模块的高级
  链客户端；底层 watch 实际是 submit-and-watch，因此组合交易模块后必须先命中内部 pending。
  inBlock/finalized 块锚不等于成功；终态只接受绑定 txHash 与同一 extrinsic index
  `System.ExtrinsicSuccess/Failed` 的私有证据。显式同步一次最多处理 32 条未终态 execution，
  历史索引同时受 4,096 条和 31 MiB durable weight 限制；逐条 weight 只包含 opaque callData、
  signed extrinsic 与通用保守固定开销。冻结模板在签名前确定最终 extrinsic 长度，Engine 先只读
  预检，再在 pending CAS 中复检真实候选。腾挪只按创建时间/ID 驱逐最旧 retention-terminal，
  Pending/InBlock 不可驱逐；资源不足返回 `conflict`，不产生签名、广播或部分历史写入。
  不扫描账户业务流水，也不解释 destination、amount、remark、direction 或业务 pallet/event。
  历史操作代际租约覆盖全部 provider/store await 与最后一次 CAS。
  store 合同是 `load_index`、按 executionId 读取、稳定游标有界分页和原子 mutation；状态更新只
  读取/写回目标 execution，公开页面成本只受 limit（最大 100）约束，启动恢复只查询可协调记录。
  四端 Host 把 opaque Core record 分行保存，索引描述与解码记录由 Core 逐项交叉验证，不允许
  whole-history 缓存或 App 业务列。
  通用交易 C ABI 在独立四线程长观察池中选择完整 terminal future 与 cancellation；取消或
  interrupted/dropped/retracted/timeout 不清 durable Pending/InBlock 门，只有 canonical body、
  准确块 metadata 与同 index `System.Events` 核验才形成 finalized 终态。

`VerifiedBlockRef` 是可序列化值，不是不可伪造令牌。Engine 核验交易前必须调用 provider
解析 finalized hash/height；smoldot 从同步状态机的准确 verified finalized 锚沿 exact parent
hash 逐头回溯，核对响应 hash、完整 SCALE header hash、高度与父链。best/recent cache 和按高度
返回值都不是 finalized 证明；独立有界 proof-derived cache 只降低重复回溯成本。这样既关闭
异步重组 TOCTOU，也允许重启后补扫旧块。

当前产品 C ABI 共 121 个公开函数，既有结构、数值与默认构造行为保持；
新增模块校验、显式模块构造和无实例验签三个入口，另补早期四个链查询/结果入口、九个 QR
协议/会话入口、统一钱包与通用签名入口，并在第 1.4 步增加十个安全链读取入口、第 1.5 步增加
三个通用交易准备入口，并在第 1.6 步增加四个通用交易执行入口。官方绑定使用
`citizensdk_create_with_modules`，旧入口也进入同一私有装配函数，不另设状态机。
chain/history 按选择提供 public store，wallet/signing 才需要配套 secure store/Vault。
依赖实现仍固定，宿主不能注入 signer、nonce、任意 RPC 或任意键值服务。
五端唯一业务逻辑由 Rust 实现，平台差异只在设备安全设施、文件保护与运行架构。

## 唯一原生实现

公开 `CitizenSdk` 位于 `lib/src/api/citizen_sdk.dart`，分别通过 `chain`、`wallet`、`signing`、`transactions`、`history`
调用产品 ABI；静态 `CitizenSigning.verify` 无需实例直接调用公共验签。钱包生命周期、输入派生、交易构造与执行核验在 `native/engine`；
资产校验和系统装配在 `native/ffi`；签名算法在 `native/signer`；
网络、共识和订阅仍由 smoldot 上游实现，`native/smoldot/provider` 只适配类型化合同。

启动时可以读取六秒／64 KiB 限额的 HTTPS 节点建议。严格匹配固定公民链身份后只合并
内存 bootNodes，禁止接收 RPC、checkpoint 或替换随包信任资产；失败继续使用随包节点。
宿主持久组合每分钟检查已验证 finalized 进展，前进时复用原子导出和 CAS，失败不清库。
钱包监控空闲时只读取本地状态；已有 finalized 订阅的通知触发有界补齐，不新增区块订阅实现。

高层转账的观察预算为 20 分钟，收到 finalized 后切换为 30 秒执行核验预算。
同一块体只读一次，暂未取得的事件按一秒间隔重试；超时协作取消并排空已有 CAS／金库操作，
保留 Pending/InBlock，不推断执行失败，不自动重广播。私钥导出不属于 SDK。

交易成功分为三个事实：返回 txHash 只表示本机轻节点接受提交；`inBlock/finalized` 只表示
包含；只有按 txHash 定位同一 extrinsic index 并读到该 index 的
`System.ExtrinsicSuccess` 才是执行成功。`ExtrinsicFailed` 会返回明确失败；未取得明确事件时
返回未核实，不把“没找到失败”猜成成功。后台历史补齐与高层观察均只从 verified finalized
块构造执行证据；inBlock 不触发成功终态。交易池迟到消息和断线不能覆盖已验证链上终态。

runtime version 与 metadata 组成同一准确块的 `RuntimeContext`。缓存键绑定块身份及版本；
构造交易、读取链上费率和解码事件都消费对应 context，防止跨升级拼接旧 metadata 与新
`transactionVersion`。生命周期门、账户集合代际和请求取消共同约束异步完成，不由回调改写链事实。

批量余额先把 AccountId/公民 SS58 规范化为唯一 storage key，通过轻节点已有的 finalized
batch storage 一次读取，再按原始输入顺序和重复项重建不可变结果；传输错误上抛，不能被
“账户不存在即零余额”的规则吞掉。

## 数据与安全隔离

| 数据 | 命名空间 | 内容 |
|---|---|---|
| 钱包公开事实 | 宿主 wallet typed payload v2 | 热 profile、仅公钥冷账户、全局顺序、revision、provisioning、active cleanup、exact cleanup queue，不含秘密；拒绝 v1 |
| 轻节点数据库 | `citizensdk.smoldot.database.v1` | 公开 finalized database |
| 交易公开事实 | `citizensdk.transactions.state.v1` | finalized 流水、pending、逐账户游标，不含秘密 |
| 账户密文 | `citizensdk.wallet.secret.*` | 硬件金库信封 |

Apple 共享 Darwin adapter 将上述逻辑域投影为两套 typed SQLite：public store 保存可重建链状态、
runtime cache 与交易公开事实，secure store 保存钱包公开资料、加密信封和 Vault 引用；两者不
共用一套无类型键值逃生口。iOS 与 macOS 复用相同 schema 和 CAS 语义，但使用各自平台允许的
文件保护能力。

Linux 第 7.1 步 Host 使用同一逻辑分层和两套独立 SQLite 文件，不复用 Apple 平台代码，也不
改变 Rust envelope/schema。公开库承载 chain database、runtime cache 与 transaction history；
安全库承载 wallet profile、encrypted secret envelope 及 TPM 对象引用。Linux store 同样要求
跨进程共享、耐久、强原子 CAS，拒绝符号链接与非普通节点，把目录及 DB/journal/WAL/SHM
分别强制为 `0700`/`0600`，并禁止把 SQLite 后端错误伪装成空记录。CitizenSDK 自有 openat
VFS 将实际 SQLite 主库与 sidecar 操作绑定到已验证目录 fd，不经过 `/proc/self/fd`；Host 还
逐项读回 schema/PRAGMA，并把所有可失败后置条件放在 `COMMIT` 前，使 durable commit 与成功
返回使用同一线性化点。

Apple 绑定对 C ABI 宿主上下文使用显式 +1 retain lease。关闭只能沿
`live -> monitorStopped -> destroyOnly -> closed` 单调前进；callback clear 在首次 destroy
前持久成关闭阶段，后续错误只能重试 destroy。成功 destroy 时先断开 HostBridge
和两个 SQLite store，再且只释放一次 ABI +1。宿主遗忘 close、部分关闭或
Flutter detach 失败都把整个 facade 交给进程级 supervisor 按有界退避继续收口，
不会提前释放借用上下文或恢复为可用状态。

C 回调对 capability/lifecycle 的查询只入队，由专用串行队列离开 C callback 后
调用 Core；回调交付、关闭与队列 claim 在同一门上线性化。Flutter detach 的顺序固定为
撤销 method handler、撤销 event handler、永久使当前 epoch 失效、清空 sink，然后先取消
所有 session 的未完工作再等待任何一个关闭；单 session 失败不得跳过后续 session。

新硬件信封产品标识固定为 `citizensdk`。助记词和母种子不持久化；每个账户只保存 child
mini-secret 的设备密文。libp2p Noise 的连接级临时传输密钥不是钱包、TUYU 或管理员身份，
不进入钱包仓储或平台金库。

Rust 为每个 child 生成随机 32 字节 DEK 与随机 nonce，以 AES-256-GCM 加密，并把 product、
wallet index、generation、owner、AccountId 与 secret kind 构成的完整 `SecretRef` 作为 AAD。
宿主 Vault 只创建/查询/退休 KEK 并 wrap/unwrap DEK；unwrap 最终写入 Rust-owned 的精确
32 字节缓冲区。Apple Security framework 返回的不可变 `CFData` 只在对应 `autoreleasepool`
内短暂存活；桥接层避免生成 Swift `Data`/COW 副本，在不能可靠原地清零的边界下立即复制
精确 32 字节，并由 pool 排空释放。该值不进入 public API 或 Flutter；Rust-owned DEK 与 child
明文仍在使用后清零，助记词或 password 也没有 Flutter tuple 位置。

宿主进程属于信任边界。新 host v1 只暴露五类具名 typed store 和不接触 child 的 DEK Vault，
没有明文 child callback；SDK 不保留可绕过产品 ABI 的 Dart 钱包或秘密注入实现。

架构明确分开三层：公民链账户/余额/nonce/fee/交易；产品无关的 sr25519 派生、金库与本地
签名；TUYU、员工登录等业务账户协议。业务协议可以请求同一公钥签名，但不得把 challenge、
会话、权限和审计并入公民链账户或 SDK Core。

## 原生边界

根 Rust workspace 的 contracts、engine、ffi、signer、provider，以及 legacy FFI/PoW 嵌套
workspace 都是 CitizenSDK 内部构建边界，不是多个 SDK。根 `include/citizensdk.h` 是唯一
产品头文件，只声明 `citizensdk_*`；`native/smoldot/include/smoldot.h` 只描述 macOS `arm64` 差分
测试所需的 legacy 兼容库。产品 ABI 使用固定宽度、`struct_size + abi_version`、单调非零 handle、Rust-owned
result、独立 callback thread、64 项有界事件队列和稳定错误码。异步请求接受后恰有一个完成
事件；raw extrinsic watch 与高层 wallet transfer watch 可取消，其它原子/状态变更操作不会
伪装成可回滚。

失败 result 还保存八项闭集 `FailureStage`。该维度从 Contracts 经 Engine 和 C getter
投影到五端，既不修改 result struct，也不进入 Host vtable 或持久化 schema；平台不得从
message 猜测阶段。Flutter 使用固定 65 个方法，只把 stage 和当前 method 加入固定错误 tuple。

Capability revision 由 Engine 单调持有，链 ready 只读取 smoldot 自身 verified
`is_usable`。Provider 内部固定 RPC allowlist，不对 ABI 暴露方法名。坏导入使当前组合进入
不可复用 `StartFailed`；绑定必须销毁 handle 并新建未导入实例才能从随包 #0 回退，不能在同一
Provider 上重试。完整 ABI 规则见 `C_ABI.md`。

轻客户端不收编全节点 `author` 出块代码，以及 identity keystore/seed phrase 私钥入口；
只保留 JSON-RPC 所需的 `identity::ss58` 公钥地址编解码。全节点 SQLite 数据库源码按上游
快照保留并受 feature 控制，移动轻节点使用 finalized database 序列化。

第 7.1 步 Linux C/C++ 投影仍以根 C ABI 为唯一稳定二进制边界。`libcitizensdk_host.so` 只
组合 HostBridge、typed stores、TPM/认证和 SDK-owned GTK 钱包流程，并且只依赖一次
`libcitizensdk.so`；C++ convenience API 是 header-only RAII 包装，不形成第二个 C++ ABI。
显式 close 失败仍由调用者持有 handle；RAII 析构无法返回错误时通过
`citizensdk_host_abandon` 把完整 Host 交给进程 supervisor，不能静默遗失。该 supervisor
请求 checkpointed stop 后只沿同一 teardown 状态继续重试；析构自身只有有限 clear/destroy
尝试，连 ownership transfer 都失败时以 `std::terminate` 失败关闭。C++ `EventObserver` 只同步
借用 event/result，不能自行 release；trampoline 在 observer 正常或异常返回后 RAII exact-once
释放非零 result。所有公开 API、callback、parent、route、Vault 与钱包 UI 都服从统一的
closing admission/lease fence。显式 destroy 有其它 API lease 时返回 BUSY；provider 以独立
service lease 保持资源存活，不跨 GTK 认证等待持有全局锁，close 对在途 service 返回 BUSY。
abandon 由 supervisor 等既有 lease 退役；不可逆 teardown 后不重开 admission，也不持锁等待
可重入 Core callback。
私有 route 安装期间的同步 completion 对 65+ 和并发突发保持无损。本步没有生成上述 `.so`，也没有
修改 Core、Cargo workspace 或根产品头。
Linux 钱包 flow 对 prepared-handle release 失败保留唯一所有权和 lifecycle lease，由专用
supervisor 重试至 Core 明确确认后才允许 registry 移除和 Host teardown，不能把失败清理静默
丢成孤儿 handle。

第 7.2 步 Flutter adapter 只把既有 22 方法 fixed tuple 映射到上述 Host/Core，不解析交易、
钱包信封或 sr25519。callback 动态范围内把公开 result 复制为纯拥有值，再投递 Flutter UI
线程；`FlValue`、借用 result 和原生句柄均不跨线程。每个请求在 Core 接受前预置 route，
完成事件与公开值复制完成分开记录，禁止早回调使 route 提前退役。钱包变更跨 session/引擎
互斥，Core EMPTY 删除结果串行回读 profile 后才释放互斥。Event sink 以 epoch 隔离取消/重订阅，
detach 先停止接纳，并保活未完成 route 至真实完成后再收口会话。标准 Linux Flutter
`FlValue` 不能无损持有内嵌 NUL 字符串，因此 adapter 通过官方 StandardMessageCodec 扩展点
在内部保留长度；wire 仍是标准 string tag，备注不截断，也不新增 wire 类型。

## CI、Release 与平台边界

CitizenSDK 最终只能接入 GMB/TataConsole 已有的唯一顶层路由，不建第二套
Workflow、缓存或发布系统。目标产品动作为：

- `gmb.citizensdk.sdk.ci`
- `gmb.citizensdk.sdk.release`

CI 与 Release 的目标合同都从干净源码建立隔离构建快照，执行唯一根包依赖锁检查、静态检查、Rust 与
Dart/Flutter 测试、Android/Apple 原生构建和候选验证。smoldot Dart 绑定和来源测试现与根 Flutter
包一起分析和执行。为保留已经验证的 smoldot 行为字节，静态分析继续报告迁入源码的既有
warning/info，但使用 `--no-fatal-infos --no-fatal-warnings` 只让 analyzer error 阻断流程；
格式检查、编译和完整测试仍失败关闭。三个 Rust workspace 都执行锁定测试；PoW workspace
另外使用 `cargo check --workspace --all-targets --locked` 编译包括 Criterion benchmark 在内的
所有 target，但不把使用随机输入的性能基准误当作确定性测试运行。Android 原生双库/AAR 与
Apple XCFramework 注入
同一候选并完成确定性反向校验后，两条流程都从该目录建立逐字节临时验证副本并执行官方
`dart pub publish --dry-run`；
Dart 生成的 `.dart_tool`
因此不会污染正式候选。`.pubignore` 固定 Hosted 运行时闭包，禁止把 GitHub 审计包与 Hosted
包实现成两个源码真源。Release 还会验证指定
成功 CI 的 workflow、显示标题、产品目标、成功状态与准确 source SHA，不读取、下载或比较
CI 资产，并从同一提交重新构建；不以跨 Runner 归档字节必然一致作为发布成立条件。
TataConsole Flow 已同步 Apple 三个技术 slice、单一 XCFramework 与本步测试闭集；
流程接线不等于远程 CI、正式 Release 或 Hosted 上传已经实际运行，运行结果仍以对应记录为准。

测试执行合同要求根 Flutter 包一次发现并执行全部根测试及已经迁入的 smoldot 测试，不再把
历史的 230 项与 51 项当成两套独立门禁；统一使用 `scripts/test.sh flutter --timeout=2m`，以覆盖其中
最长 30 秒的活链订阅窗口。第 2 步隔离副本实际执行结果为 288/288。交易执行确认使用带
`System.Event`、`Phase` 与 `DispatchInfo` 类型的真实 Substrate v14 metadata 夹具，不得退回
只能解常量的最小 metadata。Android 必须真实运行插件 JUnit；正式 CI 还必须在
iOS 模拟器变体上执行 XCTest，并分别验证 iOS 设备变体、iOS 模拟器变体与 macOS
slice；三个 slice 当前 Apple 机器架构值均为 `arm64`。编译成功不等于平台测试执行成功。

本轮本机已构建 Android AAR 与 Apple 单一 XCFramework；框架只含 iOS 设备与模拟器变体及
macOS 三个 Apple `arm64` machine slice。iOS 设备与模拟器变体两组测试 bundle
均已编译；由于本机没有
Simulator runtime，未记录 iOS XCTest 运行成功。macOS 已实际运行 Core 50 项与
Flutter adapter 22 项 XCTest，0 失败，其中 1 项真机硬件用例跳过；最终
normal/supervisor smoke 均通过。本机无真实 Apple 移动设备，不声称 Secure Enclave、
生物认证或 device-only Keychain 已完成真机验收。

真实 Flutter consumer 已完成 Android release APK（ABI `arm64-v8a`）、iOS device Release no-codesign、
iOS 模拟器变体（Rust target `aarch64-apple-ios-sim`）编译和 macOS Release 构建；这些只构成正式配置的 build/link
证据，不构成移动真机或 Simulator runtime 证据。Flutter SPM 识别警告与 Android built-in
Kotlin 迁移提示推迟到第 9 步 Hosted/Flutter 集成处理。

同一本机闭集对 Hosted 精确 17 个 Dart 文件分析为 0 问题，完整 Dart 套件以
`--timeout=2m` 执行 316/316；根 Rust workspace 285/285、compile-fail 文档测试 1/1、
Clippy 与格式检查通过；Android 原生 Kotlin/Java 单元测试 Gradle 17 个 task 成功。
这些结果未经过 TataConsole 远程 Flow，也不是正式 Release、Hosted 上传或 Git 记录。

2026-08-29 包边界重构前的 TataConsole `.work` 隔离快照已实际通过根 Flutter
230/230 和独立 smoldot Dart 51/51。signer Rust 6/6、FFI Rust 5/5、PoW Rust
290/290（另有 3 项上游 ignored、14 个 benchmark 目标成功）、Android JUnit 3/3
与 TataConsole 99/99 是同一次任务中的先前执行记录；这些历史结果不冒充包边界重构后的
验证结论。iOS 的 2 项 XCTest
已编译链接，但本机没有 Simulator runtime，未宣称本地执行成功；正式 workflow
在 GitHub macOS Runner 上要求真实执行并失败关闭。

当前源码的候选合同包含 Android `arm64-v8a` 产品 ABI 投影，以及由共享 `darwin/` 源码生成的
`CitizenSDK.xcframework`。Android 原生 AAR 与 Flutter 插件使用同一 Kotlin facade、JNI、Rust
Core 和逐字节相同的双 SO；Apple 的 Swift 原生 API 与 Flutter adapter 使用同一个 XCFramework，
支持 iOS 设备变体、iOS 模拟器变体和 macOS，当前 Apple 机器架构值均为 `arm64`。Simulator 不提供
Secure Enclave，硬件金库与钱包能力必须报告不可用。Android Core/JNI 的 SONAME 固定为
`libcitizensdk.so` 与
`libcitizensdk_jni.so`，JNI 只能按 Core SONAME 依赖一次，任何含 `/` 的 `DT_NEEDED` 都失败。
Android Gradle/Kotlin persistent project state 只允许位于 TataConsole 中央 work directory；
源码和候选均禁止 `android/.kotlin`。iOS 设备与模拟器变体使用浅层 framework 和
`@rpath/CitizenSDK.framework/CitizenSDK` install ID；macOS 使用标准 `Versions/A` framework
和 `@rpath/CitizenSDK.framework/Versions/A/CitizenSDK` install ID。候选只允许 macOS
framework 标准布局所需的精确五个内部相对符号链接，其他任何符号链接均失败关闭。
LinuxARM、LinuxAMD 已有 Host、Flutter adapter/合同测试及安装消费者源码。第 7.4 步把两种
同版本安装投影、官方 `linux` plugin 注册、默认 `CitizenSdk.open()` 与 manifest 候选合同
原子接入；27 项安装件加 12 项插件输入构成 Hosted 的 39 项 Linux 运行闭集。应用只编译薄
plugin，不重编 Host/Core，也不携带 Host 私有源码。两种机器目标的实际编译/运行仍由后续
统一 GitHub CI 增量缓存、Release 全量构建验证，源码注册不是已交付。Windows 已有原生
Host 和 Flutter 适配；第 8.4 步同时接入默认公开注册、同版候选与正式 Flutter 消费者。
Windows Hosted 固定 22 项安装件与 12 项插件输入，不重新编译 Host/Core；源码登记仍
不代表 Windows/MSVC 或实体 TPM 已实测。
legacy `libsmoldot.dylib` 只允许
作为 macOS `arm64` 差分测试宿主库；其 build-local `LC_ID_DYLIB` 不具分发身份，不得进入候选并须随
本机工作目录清理。

源码中的 Dart pubspec、Android Gradle、`darwin/citizen_sdk.podspec`、
`linux/CMakeLists.txt` 与 `windows/CMakeLists.txt` 五处版本统一冻结为 `1.0.0`。
发布器在复制前拒绝版本不一致，也拒绝 Release 请求版本与源码版本不同；复制后再核对
候选 manifest、pubspec 与平台源码版本。Windows 与其它平台共同进入同一版本的候选合同。
因此 GitHub Release 和 Hosted Package 只能来自同一准确版本提交，
不能在 Runner 中把旧源码临时改号。本步骤不执行 Hosted 上传；Hosted 身份、凭证和首次实际
发布仍需另行明确授权。现有 Release 仍只有 GitHub 正式分发动作，没有新增“发布”按钮。

Linux 完整设计、GNU target、glibc 2.31 基线、TPM fail-closed 规则和第 7 步未验证声明见
`LINUX_PLATFORM.md`。第 7.1/7.2 步只更新 canonical 源码/Release 源文件闭集，未运行 Linux
编译与 CTest、Dart/Flutter/Cargo 测试、Git、远程 CI、Release 或 Hosted 上传；获准执行的
Node Release 来源合同测试与脚本语法检查不等于 Linux 运行验证。第 7.4 步候选合并要求共享
头/资产字节一致，平台库与 CMake package 分别隔离；实际产物、依赖和许可证证据不齐不得
生成可分发候选。没有修改 TataConsole 执行流程。

## 产品外部边界

- TUYU v1 由途遇账户体系编码和验证，可选择调用钱包本地签名，但不进入 SDK。
- 广场和聊天由各产品及其 Cloudflare/服务端边界实现。
- CitizenWallet 冷钱包保持独立。
- CitizenApp 在单独批准切换前继续使用现有实现。

## Windows 原生系统层（第 8.1 步）

`Windows C/C++ → citizensdk_host.dll → citizensdk.dll → 原有 Engine/Contracts/Providers`。
Host 保留 typed records、generation、CAS、事件和关闭语义，只适配 Win32/CNG/HANDLE。
Windows 11、PCP/TPM 2.0、独立设备口令；没有软件降级。无钱包模式不创建 HWND。
第 8.2 步增加 `Flutter → Windows adapter → 已安装 Host/Core`，仅协调标准 codec、
原生环境、公开事件/回复与 Win32 钱包 UI，不重写核心行为。应用身份由一次性
`CITIZENSDK_APPLICATION_ID` 声明，缺失或非法拒绝，不进入 Dart tuple。Host 的 Core
已退休但窗口仍 BUSY 时，只保留关闭重试，不公开虚假 disposed 或再次操作已释放的 Core。
第 8.3/8.4 步补齐原生及 Flutter 消费者、默认注册和候选投影；所有检查只扩展已有构建器
与发布器，不增加第二份核心或流程。实际 Windows 运行和正式发布仍待统一平台验收。
