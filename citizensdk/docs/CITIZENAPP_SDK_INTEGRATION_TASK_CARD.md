# CitizenSDK 接管 CitizenApp 区块链底座任务卡

状态：进行中

建立日期：2026-09-10

源码范围：`/Users/rhett/GMB/citizensdk`、`/Users/rhett/GMB/citizenapp`

禁止修改：`/Users/rhett/GMB/citizenwallet`

## 一、目标与固定边界

本任务分三个部分顺序实施：

1. 先使 CitizenSDK 以通用、与消费 App 无关的接口完整具备钱包、签名、交易、轻节点、链读取、交易观察
   和历史等区块链底层能力；CitizenApp 当前需求只是验收样本之一，完成多消费者等价验收后再改进 SDK。
2. 在 SDK 完整验收后，把 CitizenApp 的业务层与旧区块链底座分离；广场、投票、立法、提案、治理等业务仍属于 CitizenApp。
3. 把 CitizenSDK 作为 CitizenApp 唯一的区块链底座接入，删除 App 的旧实现并完成端到端验收。

固定产品边界：

- CitizenSDK 是面向 CitizenApp、途遇旅行、途遇时候、途遇商家端以及任何第三方软件的通用
  CitizenChain 基础 SDK；本任务只把 CitizenApp 作为首个接入项目，不允许因此把 App 业务写进 SDK。
- 每个调用方 App 各自负责页面、业务规则、业务 action、业务 payload/callData、业务 storage key、
  业务 SCALE 编解码、业务展示和业务状态组织。CitizenApp 的广场/投票等规则不得成为其它调用方的依赖，
  其它途遇产品和第三方业务也不得进入 SDK。
- CitizenSDK 只负责热钱包、仅公钥冷账户、账户管理、通用 sr25519 签名/验签、通用冷热签名协调、
  Substrate SigningPayload/signed extrinsic、smoldot、可信链读取、广播、观察、Runtime 结果核验和通用交易事实。
- CitizenWallet 是完全独立的离线钱包产品。任务只保证 SDK 继续使用现有 `QR_V1` 合同与它协作，禁止修改 CitizenWallet 的源码、存储、页面或现有功能。
- 不读取、不迁移、不转换 CitizenApp 的旧钱包秘密、钱包表或交易表；不增加兼容分支。接入后，用户自行重新输入助记词建立热钱包，或重新导入公钥建立冷账户。
- SDK 不实现 Square、Vote、Legislation、Proposal、Governance、CID、旅行、酒店、行程、商家、订单、
  会员等任何调用方业务模块；这些业务只能调用 SDK 的通用底层接口。

通用 SDK 强制判定标准：

- 生产 API、持久状态和 Core 模型不得出现某个 App 的页面、业务实体、业务 action 名、业务字段或业务流程。
- App 可以把任意不透明业务 payload、callData、storage key 和 correlation metadata 传给 SDK；SDK 只验证
  长度、结构边界、密码学绑定、链级格式和生命周期，不解释业务含义。
- SDK 可内置 CitizenChain 的链级事实，例如 SS58 prefix、chain spec、checkpoint、Runtime metadata、
  extrinsic 格式、共识和签名算法；这些是所有接入软件共享的区块链协议，不属于某一个 App 的业务。
- 通用算法通过显式能力或策略选择，例如 raw message、Substrate SigningPayload、调用方给定的有界域分离；
  SDK 不维护“某业务 action 应如何签名”的 App 白名单，不根据 Square/CID/Vote 等名字分支。
- CitizenWallet QR 是可选的外部签名 transport adapter；通用签名核心不依赖 CitizenWallet，也允许未来接入
  其它离线签名器。保持现有 QR_V1 字节互操作不等于兼容 CitizenApp 旧钱包数据。
- 生产源码不得依赖 CitizenApp、任一途遇 App 或第三方仓库。外部产品字节只能复制为冻结测试夹具或来源
  证据，运行时和构建时均不得读取这些产品仓库。
- Public API 至少用一个无业务的 reference consumer 和五种语言绑定验证；CitizenApp 只能作为消费者之一，
  不能成为接口设计真源。

## 二、步骤门禁与完成合同

每一个编号步骤都执行同一门禁：

1. 先提交技术方案，必须列出目标、非目标、接口合同、涉及目录及目录职责注释、状态/失败语义、测试范围和清理清单。
2. 未得到用户明确确认，不修改该步骤的生产实现。
3. 执行时只修改该步骤批准的目录；发现需要扩大范围时停止并重新提交方案。
4. 完成后同步更新任务卡和相关 README/架构/安全/API 文档，补齐公开 API 与复杂不变量注释。
5. 完成后补齐单元、合同、失败路径、并发、平台投影和必要集成测试，并记录实际执行命令与结果。
6. 完成后清理临时兼容代码、重复实现、无调用符号、生成残留和任务临时目录。
7. 最后报告变更、验证证据、未完成风险，并只输出下一个步骤的技术方案，等待再次确认。

## 三、第一部分：CitizenSDK 底层能力完整化及改进

第一部分先用通用能力覆盖 CitizenApp 当前需要的区块链底座，同时证明其它途遇产品和第三方可使用同一接口，
再做改进。功能等价不等于复制 CitizenApp 业务语义；任何只有 CitizenApp 才成立的字段或规则都必须留在 App。

### 1.1 钱包核心合同：热钱包与仅公钥冷账户统一状态

状态：已完成（2026-09-10）。

实施目标：

- 保留现有一只 rootless 热钱包及 `//0..//1989` 多账户合同。
- 增加任意数量的仅公钥冷账户，支持本链 AccountId/SS58 导入。
- 建立热/冷明确类型、全账户稳定顺序、默认账户、重命名、删除和重复账户拒绝规则。
- 冷账户不创建 SecretRef、generation、KEK、DEK 或 cleanup 计划；热钱包安全合同保持不降级。
- 本步骤只完成 Rust 合同、持久状态、Engine 行为和内部 codec；不修改 CitizenWallet，不接入 CitizenApp，不做旧数据兼容。

完成记录：

- `native/contracts/src/wallet.rs` 新增 `WalletSignMode`、`ColdWalletAccount`、Citizen SS58
  严格解析以及完整账户目录不变量；冷账户没有任何秘密字段。
- `WalletState` 现在原子保存热 profile、冷账户、全局账户顺序和单调冷账户 index；热钱包
  原有 provisioning/cleanup 安全合同保持不变。
- `native/engine/src/wallet_service.rs` 和 `engine.rs` 已实现 Rust 内部的 AccountId/SS58 冷账户
  导入、签名模式查询、全局默认/排序、冷账户改名/删除，并确保热钱包变化保留冷账户。
- 冷账户公开事实变更在热钱包计划未完成时失败关闭，且不调用 `SecretVault`、不写密文、
  不创建 cleanup。热、冷 AccountId 重复统一拒绝。
- `native/ffi/src/host_codec.rs` 的钱包 typed payload 直接升级到 v2；v1 返回 unsupported
  version，不存在 fallback、迁移或转换代码。
- 已更新 `WALLET_MODEL.md`、`ARCHITECTURE.md`、`SECURITY.md` 及源码复杂不变量注释。
- 已新增合同、Engine、内部 Engine 调用面和 codec 回归测试；CitizenApp 与 CitizenWallet
  源码零修改，产品 C ABI/Dart/五端公开投影零修改。

验证记录：

- `scripts/test.sh cargo -p citizen-sdk-contracts`：37 项通过。
- `scripts/test.sh cargo -p citizen-sdk-engine -- --test-threads=1`：162 项通过。
- `scripts/test.sh cargo -p citizen-sdk-ffi`：149 项通过。
- `cargo clippy -p citizen-sdk-contracts -p citizen-sdk-engine -p citizen-sdk-ffi --lib --all-features`：
  命令成功；现存 16 个与本步骤无关的基线 warning（Engine 1 个、FFI 15 个）。
- `git diff --check`：通过。
- 并行 Engine 全套曾触发一个既有使用进程级共享钱包门的测试夹具竞争；同一完整套件单线程
  162 项全部通过，定向钱包测试也全部通过。该基线并行隔离问题未用跳过或放宽断言处理。

按“面向所有 App/第三方的通用 SDK”标准复核（2026-09-10）：通过。

- 1.1 新增模型只包含钱包 origin、热/冷 sign mode、AccountId、SS58、名称、派生/钱包 index、顺序、
  revision 和秘密生命周期；没有 CitizenApp、广场、投票、CID、旅行或商家业务字段。
- 冷账户导入、账户去重、默认首项、CAS 排序、改名和删除都是与调用方无关的钱包基础能力；没有按
  App 名称、包名、页面或业务 action 分支。
- prefix 2027、AccountId32、sr25519 与 `//index` 派生属于 CitizenChain 共享链协议/钱包策略，允许作为
  CitizenSDK 链级配置存在；这不把 SDK 限制为 CitizenApp 专用 SDK。
- 1.1 生产代码和构建没有依赖 CitizenApp/CitizenWallet 仓库；v1 拒绝也没有迁移或兼容入口。因此无需
  回滚或返工 1.1。

### 1.2 钱包公开 API 与五端宿主投影

状态：已完成（2026-09-10）。

- 将 1.1 的统一钱包状态投影到 C ABI、Dart、Android、Darwin、Linux 和 Windows。
- 公开冷账户导入、统一列表、默认账户、排序、改名和删除接口。
- 热钱包助记词创建/导入继续只在 SDK-owned 原生安全界面完成；冷账户导入只接受公开数据。
- 补齐五端 codec/session/ownership/输入上限/错误映射测试。

已批准并执行的技术方案：

目标与接口合同：

- 新增统一只读 `WalletState`/`WalletAccount` 公开投影，每个账户明确包含 AccountId、规范 SS58、
  名称、签名模式及热账户派生 index 或冷账户 wallet index；列表顺序即全局顺序，第一项即默认。
- 公开 `importColdAccount`（AccountId 或 SS58 二选一）、
  `reorderAccountsWithoutDefaultChange`、统一 `renameAccount` 和统一 `deleteAccount`；默认账户
  只通过统一列表第一项查询。
- 本步骤不把 Rust 内部的原始 default setter 投影到任何公开绑定。第一项变化必须等 1.3
  完成“原默认账户签名授权”后再公开；第一项不变的普通排序可直接提交。
- 保留现有热钱包创建/助记词导入/追加/active account API；不读取旧 App 钱包，不修改
  CitizenWallet，不加入兼容或迁移。

实施目录与职责注释：

- `include/citizensdk.h`、`native/ffi/src/abi.rs`、`native/ffi/src/wallet_abi.rs`：冻结 C ABI
  结构、输入闭集、异步 result ownership 和错误映射；不暴露内部 lifecycle 计划。
- `native/ffi/tests` 与 `native/ffi/src/wallet_abi_tests.rs`：符号、布局、句柄、短缓冲、非法
  UTF-8/SS58、取消、结果一次消费以及“无未授权 default setter 导出”测试。
- `lib/src/models/citizen_wallet.dart`、`lib/src/api/citizen_wallet.dart`、
  `lib/src/api/citizen_sdk.dart`、`lib/src/platform/citizen_sdk_flutter_codec.dart`：Dart 不可变模型、
  统一钱包 API 与严格 tuple 解码；不得承载秘密或 App 业务字段。
- `android/native/src/main/{kotlin,cpp}`、`android/src/main/kotlin`：Kotlin/JNI 与 Flutter
  方法投影，只转发产品 ABI，不实现第二套钱包状态机。
- `darwin/Sources/CitizenSDK`、`darwin/Sources/CitizenSDKFlutter`：Swift 原生与 Flutter
  投影，保持 operation/session/close 所有权规则。
- `linux/{include,src,test}`、`windows/{include,src,test}`：C++ 模型、Host/Flutter session、
  codec 与消费者测试；公开冷账户操作不得启动认证 UI 或 TPM/PCP 调用。
- `docs/C_ABI.md`、`DART_API.md`、`MOBILE_PLATFORM.md`、`LINUX_PLATFORM.md`、
  `WINDOWS_PLATFORM.md`、`WALLET_MODEL.md`：同步公开合同、平台差异和无迁移边界。

状态与失败语义：

- C ABI 所有集合先 size-query，再一次性复制；长度、数量、指针、UTF-8、AccountId/SS58 和
  permutation 在受理前验证，失败不得部分写 output。
- 重复账户返回 conflict；未知账户返回 not-found；坏 SS58/名称/排列返回 invalid-argument；
  revision 竞争返回 conflict；旧 wallet payload v1 继续明确拒绝。
- 冷账户导入/改名/普通排序/删除不要求硬件认证，不调用 Vault；热账户秘密操作保持原门禁。
- 默认账户变化在 1.3 签名协调完成前不得由任何公开绑定直接提交。

测试与清理：

- Rust ABI、Dart codec/API、Android JVM/JNI、Darwin Swift、Linux/Windows C++/Flutter
  分别覆盖热-only、冷-only、混合顺序、重复、删除默认后的收敛及 short-buffer/取消/关闭竞态。
- 更新公开符号闭集和五端 consumer fixtures；清理旧“profile 等于全部钱包状态”的命名与
  重复 projection helper，但不删除热钱包兼容 API（这是 SDK 当前正式 API，不是 App 数据兼容）。
- 完成后再次更新本任务卡，只提交 1.3 技术方案并等待确认。

完成记录：

- 根 C ABI 新增 `WALLET_STATE=21`、热/冷签名模式、统一 state/account 结构，以及读取状态、
  AccountId/SS58 冷账户导入、revision 重排、统一改名/删除和两项结果读取函数；公开 Core
  闭集从 89 项更新为 97 项，没有导出 default setter。
- `native/engine` 新增带 `expectedRevision` 且强制首项不变的公开重排入口，以及热/冷统一
  改名和删除入口；冷账户路径在 Vault 不可用时仍可工作，并由测试证明零金库/密文副作用。
- Dart 新增 `CitizenWalletState`、`CitizenWalletStateAccount`、`CitizenWalletSignMode` 与六项
  统一钱包 API；Flutter 合同从 36 方法更新为五端一致的 42 方法，状态 tuple 固定为
  `[revision, hotProfile?, accounts]`，账户 tuple 固定为八项。
- Android JNI/Kotlin、Darwin Swift、Linux C++ 和 Windows C++ 均只投影同一 Core 状态；
  各端复核账户闭集、热/冷 index、默认首项、profile 对应关系、revision 和输入上限，不建立
  第二套钱包状态机。
- C ABI 双字符串复制先统一校验两个目标缓冲区，任一 short-buffer 都不部分写另一缓冲区；
  旧 wallet payload v1 仍明确拒绝，没有 fallback、迁移或转换。
- 已同步根 README、C ABI、Dart、钱包、安全、架构、移动/Linux/Windows 和原生打包文档，
  以及发布器的 97 Core/42 Flutter 闭集。CitizenApp 与 CitizenWallet 源码均未修改。

验证记录：

- `scripts/test.sh cargo -p citizen-sdk-contracts`：37 项通过。
- `scripts/test.sh cargo -p citizen-sdk-engine -- --test-threads=1`：162 项通过。
- `scripts/test.sh cargo -p citizen-sdk-ffi --all-features`：149 项通过；仅有既有 unsafe-code 测试 warning。
- `flutter analyze lib test`：0 问题；钱包 API/model/codec 四个定向文件共 40 项通过。
- `scripts/build-native.sh abi-host`：真实 release dylib、C11/C++17 头及 97 项公开导出闭集通过。
- 五端 Flutter 方法源码合同：42 项逐项一致；Swift 变更源码 parse 通过。
- 1.2 相关 Release 来源、文档、ABI、五端方法与 Linux 格式定向门禁：19/19 通过；完整
  `scripts/release.test.mjs` 为 95/99。两个缺少中央环境变量的用例补齐正式路径后定向 2/2 通过；
  余下两个失败是 HEAD 已存在的“测试仍要求 TataConsole 专用目录、构建器已允许独立产品目录”合同不一致，
  本步骤未改其路径逻辑，留待单独批准后处理，不伪报全绿。
- `git diff --check` 通过；SwiftPM 失败尝试生成的 `darwin/.build` 已移入废纸篓；本步骤全部 82 个已跟踪
  变更和一份新任务卡均位于 CitizenSDK，CitizenApp/CitizenWallet 变更为零。
- 本机没有 Android Gradle 工具链、Linux/Windows 目标宿主；仓库内 Apple binary artifact 又
  不完整，因此本步骤不虚报四端完整平台构建或硬件运行。对应源码闭集、平台编译与实机验收
  继续由 1.9 和统一 CI/Release 门禁承担。

按“面向所有 App/第三方的通用 SDK”标准复核（2026-09-10）：通过。

- 1.2 公开模型/API 只投影统一 WalletState、热/冷账户、公钥导入、排序、改名和删除，不包含任何
  CitizenApp 或其它调用方的业务类型、action、payload、storage key 和页面状态。
- C ABI、Dart、Kotlin、Swift、Linux/Windows C++ 五端都只做同一通用 Core 投影；调用方身份不会改变
  钱包行为，没有 CitizenApp 专用初始化、路径、方法或返回字段。
- 公开接口未暴露 default setter、SecretRef、Vault、助记词或私钥材料；任意接入软件都使用相同方法。
- 因此 1.2 无需返工。仓库更早已有的业务化 QR/交易/历史代码不属于 1.1/1.2 新增内容，但已登记进
  新 1.8 通用化清理门禁，在其通用替代能力完成前不得作为最终 SDK 合同验收。

### 1.3 通用签名与冷热签名会话

状态：已完成（2026-09-10）。

设计结论：本步骤不能建立 CitizenApp action 注册表，不能解析 Square/CID/Vote 等业务 payload，也不能把
CitizenWallet 当成唯一签名核心。实现必须分成“通用签名核心”和“可选离线 transport adapter”。

目标与公开合同：

- 定义通用 `SigningIntent`：`accountId + payload + transform + externalTransport? + expiresAt?`。`payload`
  对 SDK 永远是不透明字节；`transform` 只允许通用算法枚举：`raw`、`substrateSigningPayload`、
  `blake2Domain(domainBytes)`。域字节有固定上限并完整进入会话绑定，SDK 不知道域代表哪项业务。
- `beginSigning(intent)` 从 1.2 WalletState 查询真实 sign mode。热账户在 SDK 强认证/Vault 内计算 signing
  message、签名并自验后返回 `completed(signature, payloadHash)`；冷账户返回 transport-neutral
  `pending(sessionId, signer, payloadHash, expiresAt, transportRequest)`，调用方不能伪造冷热类型。
- `consumeExternalSignature(sessionId, response)` 只接受同一 SDK 实例创建的会话，按冻结的 payload、transform、
  signer 和 expiry 自行重建 signing message 并验签；调用方不能提交“已验签=true”或替代 signing message。
- `cancelSigning(sessionId)` 取消未完成会话。会话仅在内存存在，SDK close 后失效；重启必须重新发起，不做
  App 会话迁移或兼容恢复。
- `QR_V1` 作为一个 `ExternalSignerTransport` adapter，只负责把调用方给出的有界 opaque action、payload、
  signer 和 expiry 编码成协议，并解析签名响应。删除“action 必须位于 CitizenApp/CitizenChain 业务白名单”
  和“payload 前两字节必须等于 action”的通用签名限制；是否为合法业务 action 由调用方负责。
- 保留当前热钱包 `sign(message)` 作为明确的 raw primitive；新增统一协调入口不是旧 App 兼容层。现有
  QR 链审阅若保留，只能作为 metadata 驱动的可选链工具：解析实际 pallet/call，不能按业务 action 名或
  固定 allowlist 决定可否签名。

SDK 自身默认账户变更：

- 默认账户属于 SDK 钱包状态，因此提供 `beginDefaultAccountChange(expectedRevision, orderedAccountIds, ttl)`；
  它不是某个 App 的业务 API。
- SDK 冻结 revision、原默认 AccountId、完整目标排列、CitizenChain genesis、expiry 和随机 nonce；签名者
  固定为原默认账户。热默认账户走 Vault，冷默认账户走可用 external transport。
- 为与当前独立 CitizenWallet 互操作，QR adapter 内部可以使用它已支持的 action 12 和既有字节布局；这些
  细节封装在 wallet-mutation protocol adapter 内，不进入通用 `SigningIntent` 的业务判断。
- `consumeDefaultAccountChange` 验签后再次比较 revision、原默认账户、账户闭集与排列并 CAS 提交；不增加
  raw default setter，也不接受外部声称已经授权。

明确非目标：

- 不实现或登记 CitizenApp、途遇产品或第三方的业务 action/payload，不做账户槽业务模板 materialization。
- 不把 `account_data_key_provision k=6`、CID/purpose/context、X25519 用途钥交付收进本步骤；它是 CitizenApp
  业务数据安全流程，继续留在 App。若未来多个产品需要通用安全信封，必须另立产品无关步骤和合同。
- 不构造/提交交易、不运行轻节点、不写历史；分别由 1.4—1.7 完成。
- 不修改 CitizenApp 或 CitizenWallet，不读取其它 App 仓库，不迁移、不兼容旧会话。

状态与失败语义：

- 通用会话：`created -> hotAuthorizing/computingExternalRequest -> verifying -> completed`；`cancelled`、
  `expired`、`consumed`、`closed` 为终态。无效签名不消费；首次有效签名原子消费；取消/close/consume 竞态
  只能产生一个终态。
- 绑定项至少包含 SDK instance、session id、AccountId、sign mode snapshot、原始 payload、transform 全字段、
  payload hash、transport kind 和 expiry；跨实例、跨账户、跨 payload、跨 transform、跨 transport 全部拒绝。
- 未知账户为 not-found；非法 transform/domain/TTL/长度为 invalid-argument；签名错误为 integrity；状态漂移、
  response 不匹配或重复消费为 conflict；能力/transport 不存在为 unsupported。
- 热路径始终要求 LocalSigning、HardwareVault、UserAuthentication，并在认证前后复核 generation、SecretRef
  owner、账户归属和 operation lease；冷路径不得调用 Vault。
- 任何错误不返回部分 signature/QR/output；助记词、seed、SecretRef、解锁明文和 signing-message 临时缓冲
  不进入 Flutter、日志或错误文本。

目录及职责：

- `native/contracts/src/{chain_signer.rs,wallet.rs}`，新增 `signing.rs`：通用 SigningIntent、transform、结果、
  external session 与默认账户授权快照；禁止业务 action enum/字段。
- `native/qr/src/{codec.rs,session.rs}`：实现无业务 allowlist 的 QR_V1 transport；删除
  `chain_actions.rs` 硬编码业务闭集或把链级 review 移为 metadata 派生工具，禁止 action 名分支。
- `native/engine/src/{engine.rs,wallet_service.rs,qr_review.rs}`，新增 `signing_service.rs`：冷热路由、transform
  计算、Vault、自验、session 与默认账户 CAS；不解析 App payload。
- `native/ffi/src/{abi.rs,wallet_abi.rs,qr_abi.rs,ownership.rs,requests.rs}`、`include/citizensdk*.h`：冻结判别
  union、异步 handle、两段复制、取消/销毁和错误；不导出私钥、裸 default setter 或 trust-external-signature。
- `lib/src/{models,api,platform}` 及 Android/Darwin/Linux/Windows 绑定：只投影同一通用合同，不重算密码学，
  不建立平台会话状态机，不出现任何消费 App 名或业务字段。
- `native/{contracts,qr,engine,ffi}/tests`、根/平台测试、`scripts/{build-native.sh,release.mjs,release.test.mjs}`：
  固定算法向量、ABI/方法闭集、consumer 与发布哈希。

测试与验收：

- raw、Substrate 255/256/257 字节边界、任意有界域分离、空/过长域和 payload；同一 intent 热冷验签结果一致。
- 热/冷路由、Vault 调用次数、自验失败、TTL、容量、取消、过期、无效签名可重试、有效响应一次消费、
  跨实例/账户/payload/transform/transport 和 close 并发。
- 用无业务 reference app、CitizenApp 冻结字节、至少一个途遇风格的不同 opaque payload 三组 consumer fixture
  证明生产代码不依赖任何业务 action；fixture 只验证通用算法，不允许反向生成业务分支。
- 默认账户热/冷切换、完整排列、action 12 QR 互操作、revision/闭集漂移、有效签名但 CAS 失败零写入。
- 完成时删除 action allowlist、重复 hash/verify/session helper、未使用符号和生成残留；更新全部文档和发布
  闭集，确认 CitizenApp/CitizenWallet 零修改，然后只提交 1.4 方案等待确认。

完成记录：

- `native/contracts/src/signing.rs` 已实现产品无关的 `SigningIntent`、`SigningTransform` 与
  `SigningCompletion`。payload 始终是不透明字节；只提供 raw、Substrate 256 字节阈值和调用方给定的有界
  Blake2 域分离三种通用变换，不包含任何 App action、业务字段或业务编码器。
- `native/engine/src/{engine.rs,wallet_service.rs}` 已按 WalletState 的真实 sign mode 路由：热账户必须经
  SDK 认证、Vault、generation/owner 复核并自验；冷账户只创建一次性 external session，绝不调用 Vault。
  会话冻结实例、账户、payload、完整 transform、transport 和 expiry；有效响应原子消费，无效签名零写入。
- `native/qr/src/{codec.rs,session.rs}` 已删除 `chain_actions.rs` 和固定业务 action allowlist。QR_V1 现在接受
  任意有界 `u16` opaque action，仅作为可选 external signer transport；核心签名不依赖 CitizenWallet。
- 默认账户变化已实现 SDK-owned 专用授权：冻结原 revision、原默认账户、原账户闭集、完整目标排列、
  CitizenChain genesis、expiry 和 nonce；原默认账户签名验证通过且 CAS 仍成立时才提交。普通重排仍不能
  改第一项，Rust 内部无授权 default setter/reorder 已删除。
- QR_V1 默认账户适配器继续使用独立 CitizenWallet 已有 action 12 和既有线格式，但没有修改
  CitizenWallet；该常量仅属于 wallet-mutation transport adapter，不参与通用业务 action 判断。
- C ABI、Dart、Android、Darwin、Linux、Windows 已投影同一合同。当前产品 ABI 为 104 个 Core 符号、
  4 个内部宿主符号；Flutter MethodChannel 为 47 个方法。绑定只做严格 codec、ownership 和异步会话投影，
  不重算 hash/签名、不解析 payload。
- 已更新 CHANGELOG、架构、安全、钱包、C ABI、Dart、移动端、Linux、Windows、原生打包和来源文档；
  `account_data_key_provision k=6/CID/X25519` 仍明确留在 CitizenApp 业务层。

验证记录：

- `scripts/test.sh cargo --workspace --all-features`：Contracts、Engine、FFI、QR、provider、signer 等 workspace 测试全部通过。
- `scripts/test.sh cargo -p citizen-sdk-ffi signing_and_default_change_results_preflight_and_project_each_variant_exactly --all-features`：通过。
- `flutter analyze`：通过，无问题。
- `scripts/test.sh flutter test/api/citizen_wallet_flow_test.dart test/api/public_api_contract_test.dart test/models/public_models_test.dart test/platform/flutter_codec_test.dart`：40 项通过。
- `scripts/build-native.sh abi-host`：Release dylib、104 个产品符号精确闭集、C11/C++17 公开头编译全部通过；
  构建输出使用任务专用的 TATA cache 目录，没有写入源码树。
- `node --test scripts/release.test.mjs`：99 项中 97 项通过；1.3 涉及的 Core/绑定/文档/测试来源反向闭集、
  五端 47 方法合同、最终 tgz/SHA256SUMS 和 Hosted 完整归档均通过。剩余 2 项是 1.2 已登记的本机构建路径
  测试夹具仍假定 TataConsole 唯一输出根，与现有“任意 SDK 源码树外输出目录”合同不一致，其中一项提取夹具
  还漏带 `sdk_dir` 声明；本步骤未通过放宽断言或改变产品路径策略掩盖该基线问题。
- 原始/255/256/257 字节 Substrate 变换、三类不透明 consumer、热/冷路由、Vault 零调用、默认账户热/冷授权、
  stale/expired/CAS 失败、结果 getter 两段复制和方法/符号闭集均有回归测试。

按“面向所有 App/第三方的通用 SDK”标准复核（2026-09-10）：通过。

- 新生产合同只认识 AccountId、opaque bytes、通用 transform、签名、transport、时间和钱包 revision；没有
  CitizenApp、广场、投票、立法、提案、治理、CID、旅行、商家或订单模型。
- 无业务 reference、CitizenApp 形状的冻结字节和另一种不透明 consumer 使用同一个入口；增加新 App 或新业务
  不需要修改 SDK。业务 action/payload 的生成、校验、展示和关联全部由调用方负责。
- CitizenWallet 仍是完全独立的产品，只通过现有 QR_V1 字节协议担任一种外部签名器；本步骤没有修改
  CitizenApp 或 CitizenWallet。monorepo 中两产品脚本已有的独立未提交改动被原样保留，不属于本步骤。
- 没有旧钱包、旧签名会话或 App 数据迁移/兼容代码；用户仍通过助记词重新建立热钱包或公钥重新导入冷账户。

### 1.4 轻节点与安全链读取等价能力

状态：已完成（2026-09-10）。

设计结论：当前 Core 已有单向 Engine/provider 生命周期、`VerifiedChainClient`、best/finalized head、准确块
storage/runtime context/body、finalized canonical 解析、状态导入导出以及余额/nonce/费率实现；C ABI 也已有其中
一部分低层入口，但 Dart 与五端只公开了少量账户便利读取。本步骤应复用并收口这些能力，补齐缺口和五端投影，
不能重造第二套 light client、把原始 JSON-RPC 暴露给 App，或为 CitizenApp 编写业务查询。

目标与公开合同：

- 公开统一轻节点生命周期与状态：`start`、`stop`、`lifecycle`、`getSyncStatus`。同步状态只返回链级事实：
  provider lifecycle、peer count、isSyncing、isUsable、best block 和 verified finalized block；不得返回节点 URL、
  原始 RPC 或某 App 的同步阶段。
- 公开 `getBestHead`、`getFinalizedHead`、`getFinalizedBlockAt(number)` 和
  `resolveFinalizedBlock(hash, number)`。调用方提供的 hash/height/finality 只是待验证输入，只有 provider 证明位于
  canonical finalized 链后才返回 `CitizenFinalizedBlockRef`。
- 增加 `CitizenBlockHeader`：准确 block ref、parent hash、state root、extrinsics root 和 digest 原始 SCALE；
  `getBlockHeader(block)` 必须重新核对返回 header 的 hash/number。增加 `getBlockBody(block)` 返回同一准确块按顺序
  排列的 opaque extrinsic bytes；SDK 不解码其中业务 call。
- 公开 `getRuntimeContext(block)`，返回同一准确块的 spec version、transaction version 和完整 SCALE metadata；
  metadata 是链协议事实，App 可用它编码/解码自己的 storage key、callData 和业务事件，SDK 不生成业务 DTO。
- 公开 `getStorage(block, key)` 与 `getStorageBatch(block, keys)`。key 是调用方拥有的有界 opaque bytes；batch
  必须在同一 verified block 上原子锚定、保持输入顺序和重复项，并区分“不存在”与空值。增加 finalized-only
  变体或强类型 block 参数，供不可逆业务事实使用，禁止把 best 结果伪装成 finalized。
- 公开 `getSystemEvents(finalizedBlock)` 作为固定 `System.Events` 链级 storage key 的原始字节便利入口；只返回
  block + optional opaque SCALE bytes，不解释 Square、Vote、Legislation、Proposal、Governance、旅行或订单事件。
- 保留并统一现有 `getAccountBalance(s)`、`getAccountNonce`、`getFeeSnapshot`：余额绑定一次 verified finalized
  block；nonce 与费率绑定一次准确 best runtime。便利入口必须委托同一通用读取核心，不建立平行信任路径。
- 公开轻节点状态 `exportState`/启动前 `importState` 的安全宿主流程，用于 SDK 自有公开链数据库恢复；它不是
  CitizenApp 旧数据库迁移接口，不接受旧 App 表、不提供版本兼容转换。

明确非目标：

- 不实现广场、投票、立法、提案、治理、CID、酒店、行程、商家、订单等 storage key、SCALE 解码、查询聚合或
  UI 状态；这些由每个 App 根据 runtime metadata 自己实现，只把有界 key/callData 交给 SDK。
- 不公开 `rpc(method, params)`、RPC URL、任意订阅名、未经验证的 JSON 值或“由调用方声明已验证”的 proof 位；
  App 不能绕过 smoldot/verified-block 边界。
- 不在本步骤构造、签名、广播交易，不推进交易历史状态机；分别由 1.5—1.7 完成。
- 不修改 CitizenApp/CitizenWallet，不读取或迁移它们的轻节点数据库，不为旧 API/旧表增加兼容层。

状态与失败语义：

- 生命周期保持单向：`created -> importingState? -> starting -> running -> stopped -> disposed`；启动失败进入
  `startFailed`，同一实例不能重启。`importState` 只允许在 created，`exportState` 只允许稳定 running；调用方需要
  重启时创建新 SDK 实例，不在 Core 内暗中重建 smoldot。
- `running` 只表示 provider 已启动并核对链身份/genesis；`isUsable` 才表示可服务链读取，`isSyncing` 不允许被
  UI 当作未验证数据可用证明。生命周期、同步状态与 capability snapshot 必须可同时解释。
- 每次读取绑定一个 Engine generation 和一个准确 `VerifiedBlockRef`。stop/close 先取消新请求、排空已取得租约的
  provider/订阅，再释放 smoldot；晚到结果不得跨 generation 写缓存或回调成功。
- 空 key、过长 key/metadata/body、过多 batch、重复之外的形状错误为 invalid-argument；未知 canonical 块为
  not-found/conflict；块/hash/header/runtime/返回长度不一致为 integrity；未同步为 not-ready；网络/超时保持
  network/timeout；stop/close 竞态为 cancelled/conflict。任何失败不返回部分 batch 或部分 body。
- runtime cache 和公开链数据库都是性能/恢复层，不是证明来源；安全读取必须复核 provider 返回的准确块锚，
  finalized 安全结论不能由缓存、调用方 finality 位或稍后的另一链头采样制造。

目录及职责注释：

- `native/contracts/src/chain.rs`：补齐 sync status、verified header/body、读取上限和 finalized-only 类型合同；
  `VerifiedChainClient` 仍是唯一可信链抽象，不加入业务 storage/event 类型。
- `native/smoldot/provider/src/{client.rs,verified_chain_client.rs,legacy.rs}` 及其上游 adapter：从同一 smoldot 实例
  提供状态、canonical finalized、准确 header/body/runtime/storage；原始 RPC 只准留在 provider 私有实现。
- `native/engine/src/{engine.rs,runtime_context.rs,account_state.rs,system_events.rs,state_import.rs}`：统一 capability、
  lifecycle generation、准确块校验、缓存、防晚到完成和状态导入导出；便利读取委托通用核心。
- `native/ffi/src/{lib.rs,abi.rs,ownership.rs,requests.rs,host_codec.rs}`、`include/citizensdk*.h`：投影有界数组、
  optional storage、header/body/runtime/sync/state结果，两段复制和 result ownership；不得增加 JSON/RPC 字符串入口。
- `lib/src/{models/citizen_chain_state.dart,api/citizen_chain.dart,api/citizen_sdk.dart,platform}`：不可变 Dart 模型、
  typed API 和严格 tuple codec；业务 App 只能看见验证后的通用链事实。
- `android`、`darwin`、`linux`、`windows`：投影与 Core 完全相同的方法/枚举/错误/生命周期，不缓存第二份链状态、
  不自行请求网络、不解码业务 SCALE。
- `native/{contracts,engine,ffi,smoldot/provider}/tests`、根/平台测试、`scripts/{build-native.sh,release.mjs,release.test.mjs}`：
  固定 proof/anchor、ABI/方法闭集、多消费者和发布来源；所有新增目录/复杂不变量补充 README 或模块注释。

分步实施顺序：

1. 先建立现有 Core/C ABI/五端能力矩阵，逐项标记“可直接公开、需要安全收口、确实缺失”；冻结名称、上限、
   结果 ownership 和错误码，禁止用重复实现填表。
2. 在 contracts/provider 补齐 sync status、verified header/body 和 finalized canonical API；给所有网络响应增加准确
   hash/height/genesis/返回长度复核，并锁定资源上限。
3. 在 Engine 把通用读取、账户便利读取、runtime cache、导入导出和单向 lifecycle 统一到 generation lease；
   处理 stop/close/订阅排空和晚到完成。
4. 扩展 C ABI 与公开头，先完成布局、符号、短缓冲、空值、取消和一次消费合同测试，再接 Dart 模型/API。
5. 依次投影 Android、Darwin、Linux、Windows；平台层只做 codec/ownership，更新精确方法闭集和消费者测试。
6. 清理重复 RPC/helper、可伪造 finality 入口、业务命名注释、生成残留；同步架构/安全/API/来源文档与发布哈希。

测试与验收：

- lifecycle 全转换、重复 start/stop、start failure、import-before-start、export-running、取消/超时、订阅排空、
  stop/close 与在途读取竞态、晚到结果和缓存代际隔离。
- best/finalized 不混淆；按高度解析、错误 hash/height、reorg、过期 head、伪造 finality、错误 parent/state/
  extrinsics root、跨块 runtime/storage/body、provider 返回长度/顺序错误全部失败关闭。
- storage 空 key 拒绝/缺失/最大 key、batch 空列表拒绝/1/上限/超限/重复 key/同块一致性；System.Events 只返回原始字节；
  metadata/body/digest 体积上限和两段复制短缓冲零部分输出。
- 余额单/批与通用 storage 同块等价，nonce/fee 同一 best runtime；缓存命中不能绕过 block identity，损坏缓存必须
  删除或拒绝且重新从 provider 验证，不能产生安全结论。
- 至少三类互不相关 consumer 使用各自生成的 opaque storage keys 和各自业务解码器，SDK 生产代码不随 consumer
  改动；扫描禁止 CitizenApp/途遇具体业务名进入 Core/API/持久状态。
- 运行 Rust workspace/provider、C ABI C11/C++17、Flutter、Kotlin、Swift、Linux/Windows codec、公开符号/方法
  闭集和 Release 来源反向闭集；确认本步骤未修改 CitizenApp/CitizenWallet。

清理与完成门禁：

- 删除或私有化公开面之外的任意 RPC、重复 block/runtime/storage helper、宿主侧业务解码和不可达旧方法；不保留
  fallback、迁移、兼容 alias 或 App 专用 façade。
- 更新任务卡、CHANGELOG、README、ARCHITECTURE、SECURITY、C_ABI、DART_API、五端平台与来源文档；补齐所有
  public API、unsafe ownership、generation/proof 不变量注释。
- 全部验证完成后只报告 1.4 结果并自动给出第 1.5 步完整技术方案，等待用户明确确认后再实施 1.5。

完成记录（2026-09-10）：

- `native/contracts/src/chain.rs`、`native/smoldot/provider/src/verified_chain_client.rs` 与
  `native/engine/src/engine.rs` 已形成唯一安全读取链路：同步快照、准确 best/finalized 块、按高度查 finalized、
  canonical finalized 解析、header/body/runtime/storage/System.Events、状态导入导出都锚定同一已核对块；header
  会重新 SCALE 编码并执行 Blake2-256 hash 等值校验，storage key/batch、digest、metadata、body 数量与总体积均有上限。
- C ABI 新增 10 个产品符号，产品公开符号闭集由 104 增至 114；新增 result kind 24—26 和 sync/header/body
  有界结果，两段复制保持 extrinsic 顺序、短缓冲不产生部分输出，所有权仍由一次性 result/显式 release 管理。
- Dart 及 Android、Darwin、Linux、Windows 五端新增 12 个完全同形的公开方法，Flutter 方法闭集由 47 增至
  59；模型是不可变值或防御性字节副本，batch 保持输入顺序及 optional 缺失语义，`importState` 会核对 Core
  返回的 finalized receipt 后才投影为 `void`。
- SDK 没有公开任意 JSON-RPC、RPC URL、未经验证的 finality 或业务解码；没有加入广场、投票、立法、提案、
  治理、旅行、商家、订单等业务模型。CitizenApp 和 CitizenWallet 未被本步骤修改，也没有迁移、兼容或旧数据读取。
- 构建/发布门禁已同步到 114 个公开 C ABI、Release 动态库 114 个公开加 4 个内部链接符号、五端 59 方法
  精确闭集；架构、安全、C ABI、Dart API、平台、打包与来源文档均已同步。

验证记录（2026-09-10）：

- Rust workspace 全部单元、集成和 doc tests 通过；最终又经统一源码外入口
  `scripts/test.sh cargo -p citizen-sdk-smoldot-provider` 复跑，smoldot provider 的 42 项分组测试全部通过。
- `flutter analyze`：通过；最终经 `scripts/test.sh flutter test/api test/models test/platform
  test/citizen_sdk_facade_test.dart` 复跑，1.4 直接覆盖的 API、模型、平台 codec 与 façade 共 72 项通过；测试使用
  中央缓存中的一次性符号链接投影直接读取产品源码，结束后源码树没有 `build`、`target` 或 `.build` 残留。
- `scripts/build-native.sh abi-host`：Release dylib、114 个产品符号精确闭集、4 个内部链接符号及 C11/C++17
  公开头编译通过；产物写入源码树外任务专用 TATA cache。
- `scripts/release.test.mjs`：99 项中 97 项通过；1.4 的来源闭集、产品 ABI、五端 59 方法、最终 tgz/SHA256SUMS
  和 Hosted 完整归档均通过。剩余 2 项是 1.2 已登记的本机构建路径测试夹具仍假定旧 TataConsole 唯一输出根，
  其中一项提取夹具还漏带 `sdk_dir` 声明；本步骤未通过放宽产品路径合同掩盖该基线问题。
- 本机没有发布所需 Apple XCFramework/Android ZXing 原生依赖，也不是 Linux/Windows runner，因此本步骤不虚报
  四端真实平台编译；已通过五端精确源码/codec/消费者合同，真机及各目标 runner 发布构建保留到 1.9 总门禁。

### 1.5 不透明 callData 的通用交易构造

状态：已完成（2026-09-10）。

设计结论：本步骤把调用方已经按自己业务编码好的 opaque SCALE `callData` 转为一次有界、一次性、绑定准确链
状态的交易准备对象。SDK 负责链身份、runtime、nonce、signed extensions、SigningPayload 和 extrinsic 模板；
调用方负责业务 action、参数语义、表单校验、展示、correlation id 和业务状态。本步骤只准备交易，不签名、不广播、
不观察交易，也不把内部 payload、签名或 extrinsic 暴露给 App；1.6 才消费准备对象完成冷热签名和提交闭环。
CitizenSDK 禁止设计任何新的协议版本、交易选项版本或版本分支；整个 SDK 唯一允许命名的协议版本只有既有
`QR_V1`。Substrate runtime 的 `spec_version`/`transaction_version` 是从链上读取并参与签名的链协议事实，不是
CitizenSDK 自定义协议版本。

目标与公开合同：

- 新增 `prepareTransaction(sourceAccountId, callData)`。`sourceAccountId` 是 32 字节链账户，`callData` 是
  调用方生成的有界 opaque SCALE RuntimeCall；SDK 不接受 pallet/call 业务名、JSON 参数、CitizenApp action、
  旅行/订单 DTO 或“已校验”标志。
- 当前交易构造固定为 SDK 自动读取 nonce、immortal era 和 tip=0；公开 API 不提供 nonce policy、era policy、tip、
  交易选项对象或协议版本字段。若以后确实需要 mortal era、非零 tip 或其他 signed extension，必须另行出方案
  确认，不得预埋版本分支。
- SDK 在一个准确 best block 快照上取得 genesis、runtime spec/transaction version、metadata 与 source nonce，
  解析 metadata 的 outer RuntimeCall，验证 pallet/call index 存在、整个 `callData` 能按准确类型完整消费到 EOF，
  并通过重新编码等值/长度上限拒绝 trailing、截断、非 canonical 或 runtime 不匹配输入；SDK不解释字段业务含义。
- 内部 `PreparedTransaction` 绑定 source、callData/callDataHash、准确 best block、genesis、runtime、nonce、
  signed-extension 准确顺序与形状、最终 signer message、确定性 extrinsic 模板与 Engine generation；它不持有私钥、
  不产生签名、不保存业务 payload，stop/close、runtime/nonce 冲突后只能失败关闭。
- Dart 只返回不可伪造的 `CitizenPreparedTransaction` 安全摘要：SDK 生成的 `preparationId`、source、callDataHash、
  best block、链上运行时规格号、链上交易格式号和 nonce；原生句柄、SigningPayload、签名字节和 unsigned/signed
  extrinsic 均不得跨公开平台通道。新增 `cancelPreparedTransaction(preparationId)` 用于显式释放。
- 每个 source 同时只允许一个 live preparation，保持当前单账户 nonce single-flight；不同 source 可并发。nonce
  永远由 SDK 在准确链状态中读取，公开 API 不允许调用方指定 nonce，也不允许以缓存值或旧准备对象替代链读取。
- `transferWithRemark` 仅作为 CitizenChain 链级便利函数保留：它只负责按准确 metadata 生成对应 opaque callData，
  随后无条件委托通用 `prepareTransaction`；不得拥有独立 nonce、payload、签名或 extrinsic 路径，也不因旧 API
  兼容而保留。业务化 `UserTransfer/bank_cid_number` 不进入通用交易核心。

明确非目标：

- 不实现广场、投票、立法、提案、治理、旅行、商家、订单等 callData 编码、业务 allowlist、DTO 或业务校验；
  各 App 使用 1.4 的 runtime metadata 自己编码业务调用，再把 opaque bytes 交给 SDK。
- 不公开 raw nonce、SigningPayload、payload hash、extrinsic builder、signed extension 拼装、原生 handle 或任意
  `rpc(method, params)`；调用方不能拆开准备对象后自行拼装另一笔交易。
- 不在 1.5 请求热钱包密钥、启动 QR、调用 CitizenWallet、验证签名、组装 signed extrinsic、提交网络或写交易历史；
  这些由 1.6—1.7 完成。
- 不修改 CitizenApp/CitizenWallet，不读取旧交易草稿，不迁移旧 nonce/session，不添加旧接口 alias/fallback/兼容层。

状态、并发与失败语义：

- 状态机固定为 `preparing -> prepared -> consumed | cancelled | invalidated`；只有 `prepared` 可被 1.6
  原子消费一次。prepare 失败不得留下句柄；cancel/stop/close 要归零敏感临时字节并释放同账户 single-flight。
- registry 由 Engine 实例和 generation 隔离；`preparationId` 使用不可预测随机标识并绑定实例，跨实例、未知、重复
  cancel 或重复消费统一失败关闭，不能把 ID 当作可序列化恢复凭据。准备对象不写持久数据库，进程重启后必须重建。
- 在途 prepare 持有 generation lease；stop/close 先禁止新准备并取消/排空在途工作，晚到 runtime/nonce 响应不得
  注册准备对象。1.6 消费前必须重新核对链身份、runtime、source 与 nonce；任何不一致都使准备对象失效并关闭，
  不通过时间、TTL 或调用方提供的版本字段延长、恢复或转换准备对象。
- 空/超长 callData、错误 AccountId、未知 pallet/call、metadata 解码/类型消费失败、trailing/非 canonical 为
  invalid-argument 或 integrity；未同步为 not-ready；网络/超时保持 network/timeout；同账户已有 live prepare、
  generation/runtime/nonce 变化为 conflict；取消/关闭竞态为 cancelled。任何失败不返回部分 payload/handle。
- 当前链 runtime 不支持 SDK 已实现的 extrinsic/signed-extension 形状时返回 unsupported；不能猜测默认顺序、忽略
  未知 extension 或复用别的 runtime 模板。所有资源上限在 contracts、C ABI、Dart 与五端入口完全一致。

目录及职责注释：

- `native/contracts/src/{transaction_build.rs,transaction_prepare.rs,lib.rs}`：定义 opaque call、callData/registry 资源上限、准确链
  锚、准备摘要/状态、上限和 trait；只出现链协议术语，不出现 App/业务 action。现有专用 build 合同下沉为通用核心。
- `native/engine/src/{transaction_builder.rs,transaction_prepare.rs,engine.rs}`：读取同一 best runtime/nonce/genesis，
  metadata 完整类型校验，构造 signer message/extrinsic 模板，维护 generation-scoped single-flight registry；
  `transferWithRemark` 若保留只能是调用通用 builder 的薄适配。
- `native/engine/src/{metadata.rs,runtime_context.rs,account_state.rs}`：复用 1.4 的准确块读取，提供 outer call 与
  signed extension 类型信息；禁止第二次采样造成 runtime/nonce 跨块拼接。
- `native/ffi/src/{lib.rs,abi.rs,ownership.rs,requests.rs,host_codec.rs}`、`include/citizensdk*.h`：计划新增
  `citizensdk_prepare_transaction`、`citizensdk_prepared_transaction_release`、
  `citizensdk_result_get_prepared_transaction` 三个产品符号、result kind 27，以及仅接收 source AccountId 与
  `callData` 的 opaque prepared handle；产品公开 ABI 计划由 114 个增至 117 个，不增加交易选项或协议版本结构；
  若实现矩阵证明需要改变符号数，必须先回写方案并再次确认，不能执行中扩大公开 ABI。
- `lib/src/{models/citizen_transaction.dart,api/citizen_chain.dart,api/citizen_sdk.dart,platform}`：新增不可变
  prepared summary、`prepareTransaction`、`cancelPreparedTransaction` 和严格二字段请求 tuple codec；不增加
  交易选项或协议版本模型；预计 Flutter 方法闭集由
  59 增至 61，平台通道只传安全摘要和 preparationId。
- `android`、`darwin`、`linux`、`windows`：原生 session map 持有/释放 Core prepared handle，平台层只验证
  tuple、长度与所有权，不缓存 nonce、不构建 payload、不按 App 类型分支。
- `native/{contracts,engine,ffi}/tests`、根及五端测试、`scripts/{build-native.sh,release.mjs,release.test.mjs}`：固定
  metadata/runtime/nonce/EOF/资源/ABI/方法精确闭集和至少三类互不相关 consumer；同步来源哈希和发布反向闭集。

分步实施顺序：

1. 1.5.1：先建立现有 transaction build、metadata、nonce、C ABI 与五端能力矩阵；用 CitizenChain runtime fixture
   冻结准确 signed-extension 顺序、callData/registry 资源上限、错误码、3 个 ABI 符号和 2 个 Flutter 方法，不写实现；
   反向扫描本步骤新增交易 API/Core：除既有 `QR_V1` 适配器与链上运行时规格号/交易格式号外，不得出现任何
   自定义协议版本名、协议版本字段或版本分支。
2. 1.5.2：实现 contracts 的通用 prepared 模型及 metadata outer-call 完整消费验证；先用至少三种无关
   pallet/call fixture 证明同一 API，不加入 action allowlist 或业务参数解释。
3. 1.5.3：实现 Engine 准确块快照、自动 nonce、SigningPayload/extrinsic 模板和按 source single-flight registry；
   将现有专用 transaction builder 收敛为通用核心，链级便利函数只能委托该核心。
4. 1.5.4：扩展 C ABI、公开头和所有权；先通过布局、符号、null/短缓冲、取消/失效、跨实例、一次释放和关闭竞态
   测试，再允许平台绑定接入。
5. 1.5.5：接入 Dart 与 Android/Darwin/Linux/Windows，保持 61 方法、tuple、错误与句柄生命周期精确同形；
   各宿主只保存 opaque handle，不获得 signer message 或 extrinsic。
6. 1.5.6：补齐 Rust/Flutter/五端/release 测试与文档，删除平行 builder、caller nonce、业务 action/QR 耦合和
   构建残留，刷新来源哈希；输出 1.6 完整技术方案并等待明确确认。

测试与验收：

- 三种以上互不相关 RuntimeCall 的合法 fixture 均从同一入口准备；新增第四个 App/业务 fixture 不修改 SDK 生产代码。
- 空/最大/超限 callData，未知 pallet/call，截断、trailing、非 canonical、嵌套/序列上限、错误 metadata/runtime、
  未知 signed extension 全部失败关闭；重新编码与 callDataHash 使用固定向量。
- runtime、genesis、best block、nonce 必须来自一个可解释快照；模拟 reorg/runtime upgrade/nonce 变化、缓存污染、
  provider 晚到响应时不得生成可消费准备对象。
- 同 source 并发只成功一个，不同 source 可并发；cancel/stop/close、重复操作、跨实例 ID、进程重建和 registry
  容量上限均释放资源且不泄漏内部 payload。
- C ABI null/布局/对齐/枚举/result kind/短缓冲/所有权、C11/C++17 头、Release 符号闭集；Dart 与五端 61 方法、
  codec、字节防御复制和 consumer 编译合同精确通过。
- 扫描 Core/API/持久状态禁止 CitizenApp、广场、投票、立法、提案、治理、CID、旅行、商家、订单和业务 action；
  确认 CitizenApp/CitizenWallet 零修改、无迁移、无兼容。

清理与完成门禁：

- 删除/私有化公开面的 caller nonce、raw payload/extrinsic、平行 transaction builder、App action allowlist、业务化
  QR transaction model 和未委托通用核心的便利入口；不保留 alias、fallback、迁移或“暂时兼容”分支。
- 更新任务卡、CHANGELOG、README、ARCHITECTURE、SECURITY、C_ABI、DART_API、五端平台、打包和来源文档；补齐
  metadata 类型消费、prepared registry、unsafe ownership、single-flight 与失效不变量注释。
- 全部门禁完成后报告 1.5 结果，并自动给出 1.6 完整技术方案。

执行记录（2026-09-10）：

- 新增 `transaction_prepare` contracts、metadata 驱动 outer RuntimeCall 校验、准确 best
  runtime/nonce 构造和 generation/source single-flight registry。内部准备对象使用可清零缓冲区保存
  callData、signer message 与 extrinsic 模板；公开摘要不含这些材料。
- 新增 3 个 C ABI 函数与 result kind 27，公开 Core 闭集由 114 增至 117；C 结果只投影
  owner-bound handle 和安全摘要，跨实例、重复释放、stop/close 失效均按一次所有权失败关闭。
- Dart、Android、Darwin、Linux、Windows 已加入完全同形的 `prepareTransaction` 和
  `cancelPreparedTransaction`，Flutter 方法闭集由 59 增至 61。五端平台层只保管原生 handle，
  不缓存 nonce、不构造 payload/extrinsic、不按 App 业务分支。
- `transfer_with_remark` 的底层准确构造已委托通用 prepared builder；本步骤不签名、不广播、不观察、
  不写历史。没有修改 CitizenApp 或 CitizenWallet，也没有迁移、兼容、fallback、旧接口 alias、业务
  action allowlist、caller nonce、交易选项或新的协议版本。
- contracts、Engine、FFI 与 Dart 定向测试已通过；五端源码闭集、发布哈希、原生消费者与完整产品测试结果
  已纳入本步骤最终验收。

验证记录（2026-09-10）：

- `scripts/test.sh cargo -p citizen-sdk-contracts --all-targets --locked`、`-p citizen-sdk-engine`、
  `-p citizen-sdk-ffi` 全部通过；其中 contracts 新增准备合同 2 项、Engine 110 项、FFI 115 项以及各自集成测试
  均通过，metadata 三种无关 RuntimeCall、single-flight/容量、C ABI owner/释放路径已被真实执行。
- `scripts/test.sh flutter test/platform/flutter_codec_test.dart test/api/citizen_transaction_test.dart
  test/api/public_api_contract_test.dart` 的 30 项定向测试全部通过；产品 Dart 切片覆盖 API、模型、五端 codec
  与 façade，排除归档 smoldot 差分目录后 74 项全部通过。
- `scripts/test.sh all` 的 Rust workspace 全部通过；Flutter 部分 105 项产品测试通过，另有 12 个归档 smoldot
  差分用例因 macOS `flutter_tester` 不装载源码树外 `libsmoldot.dylib` 而失败。宿主库本身已由
  `scripts/build-native.sh host` 成功构建到 TATA cache；该归档装载器不属于 CitizenSDK Hosted/产品运行闭包，
  本步骤没有为通过旧差分测试而把兼容库或 fallback 带回产品。
- `scripts/build-native.sh abi-host` 已通过 Release 产品 dylib、117 个产品 ABI 符号精确闭集和 C11/C++17
  公开头编译；`scripts/release.test.mjs` 共 99 项，97 项通过，1.5 来源闭集、五端 61 方法、ABI/消费者和
  最终包合同全部通过。剩余 2 项仍仅为 1.2 已登记的本机构建路径夹具基线，不通过放宽产品路径合同掩盖。
- `git diff --check` 通过；源码树没有 `build`、`target`、`.build` 残留。新增生产代码反向扫描没有 App 业务
  action、caller nonce、交易选项、新协议版本、迁移、兼容、alias 或 fallback；CitizenApp 与 CitizenWallet
  未被第 1.5 步修改。
- 本机任务缓存没有发布所需 Apple XCFramework，也不是 Android/Linux/Windows 正式 runner，因此不虚报五端真机或
  目标平台编译；本步骤已通过五端源码、codec、ABI、方法闭集和消费者合同，正式多 runner 构建与真机验收保留到
  1.9 总门禁。

### 1.6 热钱包与冷钱包通用交易闭环

状态：已完成并复核（2026-09-10）。

设计结论：本步骤原子消费 1.5 的一次性准备对象，依据统一 `WalletState` 的真实 sign mode 完成热钱包
本机强认证签名或冷钱包 `QR_V1` 扫码签名，然后使用同一 prepared extrinsic 模板自验、组装、先持久化
最小通用恢复事实再广播，最后按准确 finalized block 的 body 与 `System.Events` 核验 Runtime 终态。业务
App 只提供 callData 并处理自己的业务状态；SDK 不理解广场、投票、治理、旅行、订单等业务。CitizenWallet
仍是完全独立产品，本步骤只消费它按既有 `QR_V1` 返回的签名响应，不修改其源码或功能。

公开 API 与返回模型：

- 新增 `executePreparedTransaction(preparationId)`：只接收 1.5 返回的一次性标识，不重新接收 callData、
  source、nonce、era、tip、runtime、交易选项或版本字段。SDK 从准备对象和当前 WalletState 决定热/冷路径。
- 热账户完成设备认证、签名、自验、持久化、广播与终态核验后，返回
  `CitizenTransactionExecutionCompleted`。冷账户先返回 `CitizenTransactionExternalSigningPending`，仅包含
  SDK executionId、source、callDataHash、`QR_V1` request、Core 时钟生成的 expiresAt；QR action 只取已验证
  RuntimeCall 的两个协议索引作为 opaque transport metadata，不建立业务 allowlist，期限固定 120 秒。
- 新增 `consumePreparedTransactionQrResponse(executionId, response)`：只接受 pending execution 对应的
  `QR_V1` response，完成 request/session/account/expiry/signature 一致性与 sr25519 自验后继续同一提交闭环。
- 新增 `cancelPreparedTransactionExecution(executionId)`：取消尚未广播的认证/冷签会话并清零材料；若已广播，
  只停止本次观察，不撤回链上交易、不删除已持久化事实，也不把取消伪装成成链上失败。
- 通用完成结果只含 executionId、source、callDataHash、transactionHash、明确的
  `finalizedSuccess | finalizedFailed | poolRejected`、可选 verified block/extrinsic index、原始
  module/error index 和可选 usurped hash。它不返回签名、signer message、SigningPayload、signed extrinsic、
  原生 handle、业务事件、业务对象或业务文案。
- 三个新 Flutter 方法固定为上述名称，方法闭集由 61 增至 64；不得在执行中增删、重载或添加可选参数。
  C ABI 固定新增 execute、QR response consume、execution cancel 和 execution result getter 四个符号，产品
  符号闭集由 117 增至 121，并只新增 result kind 28；若能力矩阵证明该精确合同不可实现，必须停止并回写
  方案重新确认，不得执行中扩张。除既有 `QR_V1` 外不设计或命名任何 SDK 协议版本。

Core 状态机、签名与提交不变量：

- Engine 将 1.5 registry 扩展为
  `prepared -> claiming -> local_authorizing | external_signing -> signed -> persisted -> submitted -> terminal`
  的一次性内部状态机。只有 `prepared` 能原子 claim；重复、跨实例、跨 generation、已取消或已失效标识
  全部失败关闭。任何路径都不能复制出第二个可签名对象。
- claim 后先重新取得同一链 identity 的当前 best runtime 与 source nonce，并逐项核对 preparation 中的 genesis、
  runtime、signed-extension 形状、source、callDataHash 与 nonce。任一漂移立即 invalidated，要求调用方重新
  prepare；不自动重建、不隐式重签、不使用调用方时钟或缓存事实。
- 热账户只通过现有 `SigningService` 和 `SecretVault` 强认证取得短命 `SecretBuffer`；先核对秘密公钥等于
  source，再签内部 signer message 并由同一 sr25519 verifier 自验。冷账户绝不触达 Vault，仅调用既有
  external signing session 与 `QR_V1` adapter；不得热签回退。
- 冷签 response 必须精确绑定 execution、request id、source、expiresAt 和内部 signer message，单次消费；错误
  账户、过期、重放、错 session、错 payload 或无效签名均销毁该 execution，不得转入热签或接受裸签名字节。
- 签名只填充 1.5 已冻结模板的 64 字节槽；Core 重新解析完整 signed extrinsic、核对 callData、nonce、runtime、
  genesis、source 与签名后才计算含 Compact 长度前缀的 Blake2-256 transactionHash。不得二次构造另一份模板。
- 广播前以通用 typed store CAS 持久化最小恢复记录：executionId、source、callDataHash、opaque callData、nonce、
  genesis、runtime、完整 signed extrinsic、transactionHash、构造块和状态；不保存业务 DTO、业务 correlation、
  签名字节字段或展示文案。CAS/写后回读未确认成功前禁止调用 provider。
- submit-and-watch 仍使用唯一 `VerifiedChainClient`。节点返回 hash 必须与本机 hash 相同；Invalid/Usurped 形成
  poolRejected，Ready/Broadcast/InBlock/节点 Finalized 均不是执行成功。finalized 后必须在 canonical body 精确
  定位 extrinsic index，并以同块 metadata 解码同 index 的 `System.ExtrinsicSuccess/Failed` 才形成终态。

生命周期、并发、恢复与失败语义：

- 1.5 的每 source preparation single-flight 与本步骤 execution/persisted pending 门合并：同一 source 任一阶段
  最多一笔；不同 source 可并发。claim 之后立即从 preparation registry 移出并转入 execution registry，两个
  registry 不得同时拥有同一内部材料。
- stop/close 首先拒绝新 claim，再取消未广播认证/QR、排空已进入的 Vault/store/provider await，并清零内存材料；
  已广播记录保持持久 pending/inBlock，不因进程退出丢失。晚到认证、QR response、provider 事件或 CAS completion
  不能复活旧 generation。
- 重启不恢复 1.5 preparation 或未产生签名的冷签会话；用户重新 prepare。只有广播前已完整持久化的通用授权记录
  可恢复：先扫描 finalized 证据，未终态时核对当前链 identity/runtime 与完整字节后只重发原 signed extrinsic，
  绝不重新签名。此恢复是新通用记录本身的正常生命周期，不读取或迁移任何旧 App 数据。
- 取消发生在持久化前则不留记录；发生在 CAS 后保留真实记录；发生在广播后只结束观察。timeout、断网、Dropped、
  Retracted 保持未核实 pending，不能被映射为失败。只有 Runtime Success/Failed 或 pool Invalid/Usurped 是公开终态。
- registry、请求、响应、callData、signed extrinsic 与历史记录均使用既有固定资源上限；所有错误保留
  invalid-argument/not-ready/conflict/cancelled/timeout/network/integrity/unsupported 的稳定语义且不返回部分结果。

目录及职责注释：

- `native/contracts/src/{transaction_prepare.rs,transaction_build.rs,signing.rs,store/transaction_history.rs}`：新增通用
  execution id、external-pending/terminal 摘要、最小恢复记录与状态不变量；字段只描述链协议事实，不出现 App 业务。
- `native/engine/src/{transaction_prepare.rs,wallet_service.rs,transaction_outcome.rs,transaction_history.rs,engine.rs}`：
  实现原子 claim、runtime/nonce 重检、冷热路由、模板签名、自验、pending-before-broadcast、观察和准确终态核验；
  现有 `transfer_with_remark` 只能把链级 callData 送入同一闭环。
- `native/qr/src/{session.rs,codec.rs}` 与 `native/engine/src/qr_review.rs`：只复用现有 `QR_V1` 会话、Core 时钟、
  单次消费和 metadata 审阅；不得添加第二种 QR 格式、协议版本或 CitizenWallet 专用源码依赖。
- `native/ffi/src/{transaction_abi.rs,wallet_abi.rs,abi.rs,ownership.rs,runtime.rs}` 与 `include/citizensdk*.h`：固定
  新增 `citizensdk_execute_prepared_transaction`、`citizensdk_transaction_execution_consume_qr_response`、
  `citizensdk_transaction_execution_cancel`、`citizensdk_result_get_transaction_execution` 四个符号和 result kind 28；
  同一结果结构以显式 kind 投影 external-pending 或 terminal 安全字段，所有原生 handle 绑定 owner 并一次释放，
  内部字节不出 ABI。
- `lib/src/{models/citizen_transaction.dart,api/citizen_transactions.dart,api/citizen_sdk.dart,platform}`：新增三个精确
  公共方法、sealed pending/completed 模型、固定 tuple 与事件映射；不提供 raw signature/extrinsic 或业务 callback。
- `android`、`darwin`、`linux`、`windows`：只实现 execution handle map、`QR_V1` 文本/图像交互、取消和公开值复制；
  不签名、不构造交易、不解析业务 callData，CitizenWallet 不作为编译或运行依赖。
- `native/{contracts,engine,ffi,qr}/tests`、根/五端测试和 `scripts/{build-native.sh,release.mjs,release.test.mjs}`：固定
  C ABI/Flutter 闭集、所有权、恢复、冷热一致性、无业务耦合和发布来源哈希。

实施顺序：

1. 先以任务卡固定的 execution 状态、公开模型、三个 Dart 方法、四个 C ABI 符号、result kind 28、错误映射和
   最小恢复记录建立合同测试；反向扫描
   禁止业务名、caller nonce、raw signature/extrinsic、新协议版本及旧数据入口。
2. 实现 Engine 原子 claim、链状态重检和热钱包强认证签名，证明只消费 1.5 模板并复用唯一 signer。
3. 接通冷账户 `QR_V1` request/response，完成账户/会话/过期/重放/自验门禁；全程不触达热钱包 Vault。
4. 实现通用 CAS 恢复记录、pending-before-broadcast、submit/watch 和准确 Runtime 终态；把链级便利转账收敛到
   同一执行核心。
5. 扩展 C ABI、Dart 与 Android/Darwin/Linux/Windows，逐端通过所有权、tuple、关闭竞态和消费者编译测试。
6. 更新全部文档/注释/测试/发布闭集，删除平行签名/构造/提交路径和构建残留；完整门禁通过后输出 1.7 方案。

测试与验收：

- 用至少三类无关 RuntimeCall 分别覆盖热签与冷签，同一生产实现零业务分支；增加第四类 App call 只新增测试数据。
- 热钱包覆盖认证成功/取消/拒绝、错误 SecretRef、公钥不匹配、signer 失败、自验失败、Vault 迟到完成与 stop/close。
- 冷钱包覆盖 `QR_V1` 正常扫码、错误账户/request/session/payload、过期、重复 response、跨 execution、取消、关闭、
  以及确认整个路径从未调用 Vault；不测试或实现其他协议版本。
- runtime/genesis/nonce/signed-extension/callData/template 任一漂移都在签名前或广播前失败；签之后必须重新 prepare。
- 广播前 CAS、写后异常、进程重启、原字节重发、节点 hash 不一致、Invalid/Usurped、断网、Dropped/Retracted、
  inBlock/finalized 和 Runtime Success/Failed 全部覆盖，证明只有明确证据改变终态。
- 同 source 并发只允许一个 execution，不同 source 并发；重复 execute/consume/cancel、跨实例/跨 generation ID、
  stop/close 与晚到回调不泄漏句柄、不重复签名、不重复广播、不清除真实 pending。
- C ABI null/布局/枚举/短缓冲/一次释放、C11/C++17、五端方法/tuple/event、公开模型防御复制、Release 符号和来源
  反向闭集全部通过；源码树不得生成 build/target/.build。

完成门禁：不修改 CitizenApp、CitizenWallet；不迁移、不兼容、不读取旧钱包/交易；不增加业务 action/DTO/编码；
不公开 nonce、签名、SigningPayload 或 extrinsic；除既有 `QR_V1` 外不设计任何协议版本。得到明确确认后一次完整
执行 1.6，执行完成后更新文档、注释、测试、清理残留并自动输出 1.7 完整技术方案。

执行记录（2026-09-10）：

- `transaction_prepare` 的一次性 preparation 已扩展为 Engine 内部 claim/execution 闭环。执行前重新取得准确
  chain identity、best block、Runtime metadata、signed extensions 与账户 nonce，并与冻结模板逐字节核对；任何漂移
  直接失效，不自动重建、不重签。
- 热账户只走现有 Rust `SigningService`、设备认证、`SecretVault` 和 sr25519 自验；冷账户只产生绑定同一
  preparation 的 external intent，并由 FFI 接入既有 `QR_V1` session。冷路径不调用 Vault，没有热签 fallback，
  也没有添加任何二维码协议名称或版本。
- 新增通用 `TransactionExecutionRecord`，在 provider watch 前以 CAS 持久化 executionId、source、callDataHash、
  opaque callData、准确 runtime/genesis/nonce、完整已签 extrinsic 与本机 transactionHash。写入或写后回读失败时
  禁止广播；公开结果不投影 callData、nonce、签名、SigningPayload 或 signed extrinsic。
- watch 只接受 `Invalid/Usurped` 作为明确池拒绝；finalized 通知必须再次解析 canonical body，精确匹配完整 extrinsic
  与同 index `System.ExtrinsicSuccess/Failed` 才形成链上终态。提前断流、Dropped、Retracted、timeout 或证据缺失
  均保留 durable Pending/InBlock。
- 重启恢复先扫描已经 finalized 的准确字节证据；仍未终态时复核 chain/runtime/call/extrinsic/signature 后，每个
  monitor generation 最多重发一次原已签字节，绝不重新签名。完整 finalized body 任一条目损坏都会 integrity
  失败，不会跳过坏条目继续猜测。
- C ABI 已新增并固定 4 个符号：`citizensdk_execute_prepared_transaction`、
  `citizensdk_transaction_execution_consume_qr_response`、`citizensdk_transaction_execution_cancel`、
  `citizensdk_result_get_transaction_execution`；产品闭集为 121，result kind 为 28。Dart 与五端统一增加 3 个
  方法，方法闭集为 64。
- executionId 现在同时绑定 awaiting QR、admission pending 和 active request 三阶段。取消可以唤醒 provider wait，
  但已进入的 store CAS 必须排空；CAS 后取消保留真实记录且不广播。同步队列拒绝会回滚 QR claim 和 preparation
  所有权，不吞掉调用方仍可重试的会话。
- Dart/Kotlin/Swift/C++ 输入统一使用既有 `QR_V1` 文本上限 2331 UTF-8 字节；公开字节模型均作防御复制。
  CitizenApp 与 CitizenWallet 均未修改；没有旧钱包/旧交易读取、迁移、兼容、alias 或 fallback。

验证记录（2026-09-10）：

- `scripts/test.sh cargo --workspace --all-targets --locked` 覆盖 contracts、Engine、FFI、signer、provider 与全部
  集成合同；新增 Core 热账户 opaque call 执行和冷账户 external-signing/取消用例均通过。feature matrix 的
  no-default、transactions-only、qr-only 编译合同也通过。
- `scripts/test.sh flutter test/platform/flutter_codec_test.dart test/api/citizen_transaction_test.dart
  test/api/public_api_contract_test.dart test/models/public_models_test.dart` 共 38 项通过，覆盖三方法、五端 dispatch、
  pending/completed tuple、终态枚举、错误输入、取消和不可变模型。
- `scripts/build-native.sh abi-host` 已在 TATA cache/target 中完成 Release host 构建，117 个产品符号、C11/C++17
  头与消费者合同通过；所有生成物均位于 CitizenSDK 源码树之外。
- `scripts/test.sh release` 的 100 项全部通过；Release 来源哈希、115 文件 Core 反向闭集、测试/文档/五端源码
  合同已经同步。源码树无 `build`、`target`、`.build` 残留，`git diff --check` 和业务/迁移/兼容/新协议反向
  扫描通过。

### 1.7 通用交易观察与历史

状态：已完成（2026-09-11）。

设计结论：1.7 只公开“由当前 CitizenSDK 实例实际提交过的通用交易授权及其可验证链状态”，不尝试从全链事件
推断某个账户参与了哪些业务。任意入账、投票影响、订单变化、广场内容、治理结果等都需要业务语义，继续由各 App
自己的索引和模型负责。SDK 内部为 1.6 恢复保留 opaque callData 与完整 signed extrinsic，但公共历史只返回 hash
和验证后的状态，不返回这些字节。现有 CitizenApp 专用 transfer 记录、逐账户游标、方向、金额、备注和
`FinalizedTransferRecord` 不迁移、不兼容、不双写；在本步骤直接由通用 execution 历史替换。

公开 Dart API 与模型冻结候选：

- 删除 `transferWithRemark`、`initializeFinalizedHistory(accountIds)` 与
  `syncFinalizedHistory(accountIds)`，不保留 deprecated wrapper、alias 或 fallback；新增
  `getTransactionHistory({String? beforeExecutionId, int limit = 100})` 和
  `syncTransactionHistory()`。三个旧方法换成两个新方法，Flutter 方法闭集由 64 调整为 63。
- `getTransactionHistory` 只读本地 durable store，不启动链扫描；`limit` 固定为 1..100，`beforeExecutionId` 必须是
  当前快照中真实存在的 executionId，否则 NotFound。结果按 `createdAtMillis, executionId` 确定性倒序，返回
  `CitizenTransactionHistoryPage(revision, records, nextBeforeExecutionId)`；revision 用于 UI 丢弃迟到旧页，游标
  只用于翻页，不能授权删除或改写。
- `syncTransactionHistory()` 不接受账户、callData、业务过滤器、区块范围或调用方游标。它对当前 store 中有限批次
  非终态 SDK execution 做一次明确同步，直接返回同步后的第一页，并在事实变化时发出既有 payloadless
  `historyChanged`；无状态变化时不虚增 revision、不发事件。
- 公开 `CitizenTransactionHistoryRecord` 只含 executionId、sourceAccountId、callDataHash、transactionHash、
  `pending | inBlock | poolRejected | finalizedSuccess | finalizedFailed`、created/updated 时间、可选 verified block、
  extrinsicIndex、dispatchVariant、palletIndex/errorIndex、replacementHash 和受限 pool reason。它不含 nonce、
  callData、签名、SigningPayload、signed extrinsic、destination、amount、remark、direction、source pallet、业务
  correlation id、业务事件或业务文案。

C ABI 与五端合同冻结候选：

- 删除旧业务历史 6 个符号：`citizensdk_initialize_finalized_history`、
  `citizensdk_sync_finalized_history_batch`、`citizensdk_result_get_history_info`、
  `citizensdk_result_get_history_cursor`、`citizensdk_result_get_history_record`、
  `citizensdk_result_get_finalized_transfer`；同时删除业务便利交易
  `citizensdk_transfer_with_remark` 与其旧结果 getter `citizensdk_result_get_wallet_transfer`，不保留兼容入口。
- 新增 4 个通用符号：`citizensdk_get_transaction_history`、`citizensdk_sync_transaction_history`、
  `citizensdk_result_get_transaction_history_page`、`citizensdk_result_get_transaction_history_record`。净删除 4 个，
  产品 C ABI 闭集由 121 调整为 117；复用 result kind 17 表示 history page，不增加 result kind，不改变 1.6 的
  transaction execution result kind 28。
- C page getter 只投影 revision、recordCount 和 next-cursor presence；record getter 使用固定 struct、显式
  presence flags 和 caller buffer 复制受限 reason。任何 short buffer 先返回 required length，禁止部分写。
- Android、Darwin、Linux、Windows 只做同一 tuple/struct 的值复制、分页参数校验、异步 request 和事件映射；
  不添加平台数据库、业务筛选器、链解码器、后台定时器或 CitizenWallet 依赖。

Core 状态、同步与保留规则：

- `TransactionHistoryState` 删除旧 `cursors/records/transfers` 三套业务集合，只保留通用 executions；Host wire codec
  直接升级为新的唯一 schema，旧 schema 解码失败，不写迁移器、不做版本 fallback。各 App 如需旧记录，只能继续
  由 App 自己管理，不能要求 SDK 读取。
- 内部 `TransactionExecutionRecord` 继续保存 1.6 恢复必需的 nonce、genesis、runtime、opaque callData、完整
  signed extrinsic 与 transactionHash，并保持 submission facts 不可变；新增公共投影函数必须逐字段白名单复制，
  不能把恢复字节带出 Core。
- store 固定最多 4096 条 execution。写入第 4097 条前，只能按确定性顺序清除最老的明确终态记录；只要没有足够
  终态可清理就返回 Storage/Conflict，绝不驱逐 Pending/InBlock。单次 sync 最多处理 32 条非终态，防止一次公开
  请求占满 provider/store 队列。
- 同步对每条记录先解析最近 finalized canonical body；只有完整 extrinsic 唯一命中且同 index System outcome
  可验证时推进到 finalizedSuccess/Failed。若未找到，则按 1.6 规则验证当前 chain identity/runtime、完整授权和
  sr25519 签名，并在本 Engine generation 尚未重发过时重发原字节一次；绝不重新签名、重新构造或调用 Vault。
- `poolRejected` 仍允许随后被更强的 finalized 证据覆盖；finalizedSuccess/Failed 永久终态。InBlock 不等于成功；
  Dropped/Retracted/timeout/断网/坏 body/坏 events/不唯一匹配都不得制造失败或推进终态。
- get/sync 与自动 monitor 共用 executionId 级 single-flight、同一 CAS 服务和 generation fence。stop/close 拒绝新
  sync，取消 provider 等待但排空已进入的 CAS；晚到结果不能覆盖新 revision，多个 SDK 实例的 CAS 冲突只重读
  有限次，不能 last-write-wins。

目录及职责注释：

- `native/contracts/src/store/transaction_history.rs`、`native/contracts/src/transaction_prepare.rs`：收敛为唯一通用
  execution store schema，增加 4096 保留上限、公共 history record/page 值对象、稳定排序/游标和白名单投影注释；
  删除 transfer、方向、金额、备注与账户扫描游标业务类型。
- `native/engine/src/{transaction_history.rs,transaction_execution.rs,finalized_history_runtime.rs,chain_monitor.rs,
  engine.rs}`：实现分页读取、32 条同步批次、自动恢复与显式同步共用 single-flight、准确 finalized 证明、原字节
  有限重发、CAS/generation/cancel 门禁；删除按 transfer event 归并和自转账展示规则。
- `native/ffi/src/{abi.rs,host_codec.rs,transaction_abi.rs,wallet_abi.rs,runtime.rs}` 与 `include/citizensdk*.h`：实现
  新唯一 store wire schema、4 个通用历史符号、result kind 17 page/record getter 和短缓冲原子复制；删除 6 个旧
  历史符号和旧 structs。
- `lib/src/{models/citizen_transaction.dart,api/citizen_transactions.dart,api/citizen_sdk.dart,platform}`：替换旧历史
  模型和两方法，冻结 page/record tuple、防御复制、分页与事件语义。
- `android`、`darwin`、`linux`、`windows`：同步删除旧业务历史 codec，加入相同的 page/record 投影和消费者合同；
  不实现任何 App 业务映射。
- `native/{contracts,engine,ffi}/tests`、根/五端测试、`docs`、`scripts/{release.mjs,release.test.mjs}`：覆盖 schema
  拒绝、分页、保留、同步、恢复、ABI/方法精确闭集、业务词反向扫描与来源哈希。

实施顺序：

1. 先冻结上述两个 Dart 方法、4 个新增/8 个删除 C 符号、117/63 闭集、公开 page/record 字段、4096/100/32
   上限与错误映射；先写失败的合同、布局、公开面和反向扫描测试。
2. 将 contracts/store 和 Host codec 一次性切换为通用 execution-only schema；删除旧业务集合及编码，不增加旧
   schema loader、迁移器、双写或 fallback。
3. 实现 Core 确定性分页、终态安全驱逐和显式 sync；复用 1.6 的 finalized 证据、原字节恢复、single-flight、
   cancellation 和 CAS，不建立第二套 monitor/提交实现。
4. 替换 C ABI、Dart API/模型及 Android/Darwin/Linux/Windows 投影，确保所有端只返回安全公共字段，并删除旧
   history 路由、模型、tuple 与测试夹具。
5. 更新架构、安全、API、平台、来源和任务卡文档，完善 public/core/wire 注释；反向清理旧 transfer history、
   账户 cursor、自转账展示及遗留 symbol/method 字符串。
6. 只通过 `scripts/test.sh` 执行 Rust workspace、Flutter、Release 与 feature matrix；通过 `build-native.sh abi-host`
   验证 117 符号和 C11/C++17 消费者，检查源码树零生成物，然后报告结果并自动输出 1.8 完整技术方案。

测试与验收：

- 三种无关 RuntimeCall 的 pending/inBlock/poolRejected/finalized success/failure 均产生同形公共记录；新增第四类
  业务只增加 App 测试数据，不修改 SDK 生产实现。
- exact body 零匹配、多匹配、坏 Compact、坏 extrinsic、错 hash、错 index、坏 metadata/events、缺失 System
  outcome 全部失败关闭且不推进状态；poolRejected 后发现 finalized 证据可以单向升级。
- 冷热账户产生完全相同的历史 schema；历史读取和 sync 从不调用 SecretVault、不要求钱包存在、不重新签名，
  不暴露内部 callData/extrinsic/signature/nonce。
- 1/100/101 limit、有效/无效/跨实例 cursor、空页、稳定倒序、并发写入页、revision 迟到、4096 边界、只清理
  最老终态、全为 pending 时拒绝写入、32 条 sync 上限全部覆盖。
- stop/close、并发 get/sync/monitor、CAS 写后报错、进程重启、每 generation 单次重发、provider 断流与迟到回调
  不丢真实记录、不重复广播、不改写终态。
- Host wire 只接受新唯一 schema；旧业务 schema 明确 Decode 失败。C ABI null/布局/枚举/presence/短缓冲/一次释放、
  C11/C++17、五端 63 方法与 tuple、117 符号、发布反向闭集和源码零残留全部通过。

验证记录（2026-09-11）：

- `scripts/test.sh cargo --workspace --all-targets --locked` 全量通过；期间由边界测试发现并修正归并后的
  `twox128("System") ++ twox128("Events")` 固定存储键，finalized success/failure 重新由准确事件证据证明，未降低
  断言或跳过失败用例。
- `scripts/test.sh flutter --timeout=2m` 在隔离工程和外部宿主 smoldot 库下 130 项全部通过；Dart 公开方法闭集为
  63，通用 history page/record 的非法 tuple、分页和防御复制合同通过。
- `scripts/build-native.sh abi-host` 完成最新 Release Core 构建，117 个产品 ABI 符号精确闭集以及 C11/C++17
  消费者编译/链接合同通过；生成物只写入 TATA 外部 cache/target。
- `scripts/build-native.sh apple` 和 `apple-tests` 通过：iOS device、iOS Simulator、macOS 三个 Apple 变体编译；
  Core XCTest 85 项通过（其中 5 项真实窗口测试按既有环境合同跳过），Flutter XCTest 33 项全部通过。
- `scripts/build-native.sh android` 使用中央 Gradle 9.1.0、CMake 3.31.6、Android Studio JDK 和 NDK
  28.2.13676358 完成 ARM64 Core/JNI/AAR Release 编译与产物核验。
- `scripts/test.sh release` 的 101 项全部通过；产品源码、测试、文档、五端绑定、117/63 精确闭集、smoldot
  离线来源、候选归档和 Hosted 消费合同均已纳入同一发布反向门禁。
- CitizenApp 新目录的 `flutter analyze --no-pub` 通过，交易编码、历史扫描/存储/展示与钱包相关 86 项定向测试
  全部通过。仓库级 `scripts/citizenapp-test.sh` 在执行测试前被缺失的 `/Users/rhett/GMB/.github/dependencies.json`
  阻塞；这是现有总入口的环境前置文件缺失，不是本步骤测试失败，也没有通过修改脚本或补造版本清单绕过。
- `native/smoldot/pow/**` 三个既有定制文件保持基线 SHA-256；CitizenWallet 源码、依赖和发布物均未修改。

CitizenApp 业务实现归位记录：

- `lib/transaction/history/data/local_tx_store.dart`：App 自己的 Isar 交易展示实体、目的账户、金额、备注、方向和
  状态合并；SDK 不读取或迁移该表。
- `lib/transaction/history/chain/wallet_transaction_history_sync.dart` 与
  `citizenchain_transaction_event_decoder.dart`：App 自己扫描 finalized 链、按准确 metadata 解码
  `OnchainTransaction`/`Balances` 业务事件并生成收发投影。
- `lib/transaction/history/application/wallet_transaction_history_service.dart`：把 SDK 通用 execution fact 按 txHash
  投影到 App 已有业务记录；不反向把业务字段传给 SDK，也不建立第二套数据库或双写兼容层。
- `lib/transaction/history/presentation/`：交易 Tab/Page 的刷新与展示逻辑；只消费 App 业务记录。
- `lib/transaction/onchain-transaction/citizenchain_transfer_call_encoder.dart`：CitizenChain 转账 RuntimeCall 的
  destination/amount/remark 编码；最终只把 opaque callData 交给通用交易端口。
- `lib/transaction/ports/{transaction_executor.dart,finalized_chain_reader.dart}`：第二、三部分替换底座使用的
  SDK-neutral 边界；接口不暴露 CitizenSDK 类型，当前尚未绑定 SDK 运行时。

旧 `lib/rpc/chain_tx_monitor.dart`、`lib/transaction/shared/{local_tx_store.dart,tx_auto_refresh_mixin.dart}` 和
`lib/wallet/pages/transaction_history_page.dart` 已删除，不保留 wrapper、alias、迁移读取或双写。所有调用和测试已
改为新 App 目录；CitizenWallet 未改动。

完成门禁：SDK 只观察自身提交交易，不声称提供全账户业务历史；不出现 destination/amount/remark/direction/业务
correlation 或任何 App DTO；不迁移、不兼容、不双写旧历史；不公开 callData、nonce、签名、SigningPayload 或
signed extrinsic；CitizenApp 只接收删除前复制出的 App 业务实现和 SDK-neutral 端口，CitizenWallet 不修改；不设计
或命名除既有 `QR_V1` 外的任何协议版本。

### 1.8 现存业务耦合清理与通用性反向门禁

状态：已完成（2026-09-11）。

目标与边界：

- 本步骤清除 SDK 早期遗留的业务 QR schema 和产品命名，使公开/Core/持久化合同只保留钱包、通用签名、
  `QR_V1` 冷签传输、轻节点、opaque 链读取、opaque RuntimeCall 交易和通用 execution 历史。
- `QR_V1` 是唯一协议版本；禁止设计、命名、预留或兼容其它 QR 协议版本。保留的只是 transport/session、
  request/response 绑定、expiry、hash、签名和验签，不保留 UserTransfer、bank CID、金额、币种、备注等业务模型。
- CitizenApp、途遇旅行、途遇时候、途遇商家端或第三方自己构造业务审阅内容和 opaque action/callData；SDK 不为
  任一产品登记 action 名、字段表、页面 DTO、业务白名单或业务文案。
- 不迁移、不兼容、不提供 deprecated wrapper/alias/fallback；删除的业务 QR 输入由消费 App 在后续自己的业务层
  重新编码。CitizenWallet 是独立产品，本步骤不修改其源码、功能、依赖或发布物。
- `native/smoldot/pow/**` 是已定制 CitizenChain PoW 上游快照；只读校验其当前 hash，禁止改动。Provider 继续直接
  复用上游已有 transaction watch、链同步、数据库和验证实现。

公开 API 与协议冻结方案：

- 删除 Dart/五端 `qrEncodeUserTransfer` 及其 UserTransfer 输入/审阅模型；删除 C ABI
  `citizensdk_qr_encode_user_transfer`。不保留原方法名转发到通用接口。
- 删除 `QrAction::UserTransfer`、`bank_cid_number`、amount/symbol/memo 等业务字段和固定业务 review action；
  `QR_V1` envelope、通用签名 request/response、账户公钥导入和 QR 图片编码/扫描能力继续保留。
- 冷交易只通过 1.6 已实现的 `executePreparedTransaction -> CitizenTransactionExternalSigningPending ->
  consumePreparedTransactionQrResponse` 使用 `QR_V1`。SDK 绑定 executionId、source、callData hash、准确 signer
  message、expiry 和签名；App 自己展示 destination/amount/remark 等交易语义。
- 通用非交易载荷签名继续使用 `beginSigning/consumeSigningQrResponse`；调用方传入有界 opaque action bytes，SDK
  不解析其业务含义。若现有 review getter 只能表达 UserTransfer，则直接删除该业务 getter/model；只有能严格
  表达通用 hash/长度/来源/过期时间且不泄露 signer message 的审阅事实才能保留。
- 按实际删除数量一次冻结 Dart 方法闭集、C ABI 符号闭集和各 result kind；先写精确闭集测试再改生产代码。
  删除项导致的数值空洞永久保留，不复用旧枚举值。

目录及职责注释：

- `native/qr/src/{codec.rs,session.rs,lib.rs}`：删除 UserTransfer/bank CID 业务 schema、专用 encode/decode 和 action
  枚举；保留唯一 `QR_V1` envelope、通用请求/响应、expiry/nonce/hash/签名绑定及边界上限。每个公开类型注释
  明确“transport fact，不是业务 DTO”。
- `native/engine/src/{qr_review.rs,qr_review_tests.rs,transaction_execution.rs}`：删除固定 transfer 审阅解释；冷交易
  继续复用通用 prepared execution 的摘要和现有 QR_V1 会话，不复制签名、提交或 watch 状态机。
- `native/ffi/src/{qr_abi.rs,abi.rs,wallet_abi.rs}` 与 `include/citizensdk*.h`：删除业务二维码函数、struct、getter 和
  enum 分支；保留通用 QR 文本/图片、账户导入、签名 request/response 与执行消费接口，完善 owner/short-buffer/
  一次释放注释。
- `lib/src/{api,models,platform}`：删除 Dart UserTransfer DTO、业务 encode/review 方法和 tuple；保留通用冷签、账户
  公钥导入、扫码与 QR 图片工具。所有 byte/list 模型继续防御复制。
- `android`、`darwin`、`linux`、`windows`：删除对应 Kotlin/Swift/C++ 业务模型、输入校验、method dispatch 和测试
  fixture；平台层只做通用 tuple/struct 的值复制，不保存业务状态。
- `test/transaction/`：删除不再被生产合同消费的 UserTransfer QR fixture；如 signed extrinsic 构造测试仍需
  业务 callData，只保留标注为“App-generated opaque callData”的最小向量，不允许它重新进入公共 API。
- `README.md`、`native/**/README.md`、`docs/{ARCHITECTURE,SECURITY,DART_API,C_ABI,WALLET_MODEL,
  SOURCE_PROVENANCE}.md`：统一说明 QR_V1 唯一协议、SDK/消费 App/CitizenWallet 三方边界和删除后的公开面。
- `scripts/{release.mjs,release.test.mjs}`：同步精确方法/符号/文件/哈希闭集，并加入业务标识反向扫描；允许名单仅限
  本任务卡、来源历史说明和明确的 App-generated opaque call fixture。

实施顺序：

1. 只读枚举 UserTransfer、bank CID、amount/symbol/memo、固定 action/review 的公开/Core/五端/测试/文档引用，
   区分必须删除的生产耦合与仍用于 opaque transaction golden 的测试数据；记录 `pow/**` 和 CitizenWallet 基线。
2. 先写失败的精确公开面测试：被删 Dart 方法/C 符号/result getter 必须不存在；QR_V1 通用签名、冷交易、账户
   公钥导入、QR 图片往返仍存在；生产源码业务词扫描必须为零。
3. 自内向外删除 `native/qr` 业务 schema 和 Engine 固定 review，再删除 FFI/header；保持 QR_V1 codec/session 字节
   合同及冷交易 execution binding 不变，不增加第二 codec、第二 signer 或第二 transaction path。
4. 同步删除 Dart、Android、Darwin、Linux、Windows 的业务 API/model/codec/dispatch。所有平台只映射同一个 Core
   结果，错误码、owner、取消、expiry、短缓冲和一次释放语义不漂移。
5. 清理无引用 fixture、dead code、feature gate、依赖、注释和生成声明；更新全部文档、任务卡、Release hash/map
   和公开方法/符号数量。不修改 CitizenWallet，也不把它加入 SDK build/test dependency。
6. 仅通过 `scripts/test.sh` 跑 Rust workspace/all-targets、Flutter、Release/feature matrix；通过
   `scripts/build-native.sh abi-host` 和 Apple/Android 可用的真实消费者门禁验证头文件与绑定。最终检查
   `git diff --check`、源码树零 build/target/.build、业务词反向扫描、pow hash 和 CitizenWallet 未改，然后自动输出
   1.9 完整技术方案。

测试矩阵：

- QR_V1 通用签名 request/response：冷热账户一致的 execution/source/action hash 绑定、expiry 边界、错 owner、
  错 request、错 signer、错 hash、错签名、重复消费、取消、stop/close、乱序响应全部失败关闭。
- 冷交易：App 生成至少三种互不相关 RuntimeCall，只改变 opaque callData；SDK 代码和公开模型不变，扫码签名后
  进入与热钱包相同的 pending-before-broadcast、watch、finalized System outcome 和通用历史。
- 通用 QR 图片与扫描：空/最大/超限文本、Unicode UTF-8 长度、尺寸/stride/像素上限、损坏图像、多码、无 QR、
  short buffer、null pointer 和一次释放合同。
- 账户公钥导入：规范 32-byte AccountId、公钥二维码往返、错误类型/长度/checksum/网络绑定全部覆盖；不访问
  CitizenWallet 实现。
- 反向合同：公开/Core/持久状态/五端生产源码不得出现 UserTransfer、bank_cid_number、destination、amount、
  symbol、memo、Square/Vote/Legislation/Proposal/Governance/旅行/商家等业务 schema；允许的普通英文动词或底层
  ownership transfer 必须用路径与语境白名单，禁止粗暴误报。
- 发布合同：删除后的精确 Dart/C/Android/Swift/C++ 面、数值空洞、feature matrix、C11/C++17 消费者、Apple
  XCFramework/Swift tests、来源 hash 和 SDK 自包含构建全部通过。

完成门禁：SDK 只知道 QR_V1 通用传输事实和密码学绑定，不知道任何 App 的业务 action 或展示字段；冷热交易共用
同一通用 prepared execution；无迁移、兼容、wrapper、alias 或 fallback；CitizenWallet 与 `native/smoldot/pow/**`
零改动；SDK 构建、测试和发布不读取 CitizenApp/CitizenWallet 源码。

完成记录：

- `native/qr` 已删除 `UserTransfer`、历史 kind `4`、bank CID、amount/symbol/memo 和专用业务编解码；kind `4`
  永久保留为空洞且明确拒绝，继续保留的只有唯一 `QR_V1` 下的通用签名 request/response、账户公钥和 QR 图片能力。
- C ABI 已删除 `citizensdk_qr_encode_user_transfer`；Dart、Android、Darwin、Linux、Windows 已同步删除业务 DTO、
  方法、tuple、dispatch、JNI 和审阅投影。当前精确闭集为 116 个 Core 公开 C 符号、4 个内部测试符号、3 个
  Apple QR 图片符号、Linux/Windows 各 17 个 Host 符号和 62 个 Flutter 方法。
- Release 门禁已加入生产源码业务 QR schema 与其它 QR 协议版本反向扫描，所有受固定来源合同约束的改动文件
  已更新 SHA-256；历史文档中的旧数量只作为当时步骤记录保留，不作为当前合同。
- Rust workspace/all-targets 全部通过；Flutter 130 项、Release 102 项通过；`abi-host` 精确验证 116 个产品符号及
  C11/C++17 消费者；Apple Core 85 项与 Flutter 33 项通过（5 项真实窗口测试按既有环境合同跳过）；Android
  ARM64 Core/JNI/AAR 真实构建通过。
- 所有构建输出均位于仓库外部缓存；本步骤没有修改 CitizenApp、CitizenWallet 或 `native/smoldot/pow/**`，也没有
  引入迁移、兼容、wrapper、alias、fallback 或第二套 QR 协议。

### 1.9 公共 API、五端包装与多消费者完整验收

状态：实现与本地可执行验收已完成（2026-09-11）；Apple Flutter adapter/Apple tests 因不得操作用户的 Flutter
下载安装而保留待验收，同源远程 Linux/Windows/移动真机验收待单独授权。

目标与边界：

- 对第 1.1—1.8 步形成的通用 SDK 做完整验收，不增加 CitizenApp 专用能力。验收范围是钱包、冷热签名、唯一
  `QR_V1`、CitizenChain PoW 轻节点、验证后的通用链读取、opaque RuntimeCall 交易和 SDK 自身 execution 历史。
- CitizenApp、途遇系列产品和第三方继续自己拥有业务 storage key、SCALE 业务解码、RuntimeCall 业务编码、页面、
  订单、广场、投票、立法、提案和治理；SDK 只接收通用账户、字节、哈希、链状态与执行参数。
- 不迁移、不兼容、不增加 deprecated wrapper/alias/fallback；禁止设计、命名、预留或兼容除 `QR_V1` 外的任何
  QR 协议版本。
- CitizenWallet 作为完全独立的外部冷签产品和黑盒协议消费者，不成为 SDK 依赖，不修改其源码、功能、依赖或
  发布物。测试另建通用 external signer fixture，证明 SDK 没有绑定 CitizenWallet。
- `native/smoldot/pow/**` 只做基线 SHA-256 校验；轻节点交易提交/watch、同步、验证和数据库能力优先直接复用
  上游现有实现。若验收发现必须修改上游或既有 PoW 定制文件，立即停止并另出方案，取得二次确认后才能修改。

冻结合同：

- Core 产品 C ABI 精确闭集冻结为 116 个公开符号；4 个内部测试符号不得进入产品包；Apple 额外 3 个 QR 图片
  符号；Linux/Windows Host 各 17 个符号；Flutter method channel 精确闭集冻结为 62 个方法。
- Dart、C、Kotlin、Swift、C++ 对同一 Core 结果做薄投影；统一参数边界、防御复制、owner/source、short-buffer、
  一次释放、取消、超时、停止、关闭、异步完成和错误码语义，不在平台层保存第二份业务或密码学状态。
- 六类公共能力固定为钱包、通用签名、`QR_V1` external transport、轻节点/验证链读取、opaque callData 交易、
  通用 execution 历史；任何 consumer 都不得通过 SDK API 传入或取回业务 DTO。
- 热账户与仅公钥冷账户继续共用 prepared execution 和广播后状态机；差异只在签名来源，不能出现第二套交易
  构造、提交、watch 或历史路径。

目录及职责注释：

- `test/consumers/reference/`：建立零业务 reference consumer，只依赖正式公开入口并覆盖六类能力；用于证明 SDK
  不借用 CitizenApp 源码、内部 FFI 或测试专用符号。
- `test/consumers/citizenapp_fixture/`：建立 CitizenApp 形状的消费 fixture。业务 destination/amount/remark、
  storage key、SCALE event 和 RuntimeCall 编码只存在于该目录，交给 SDK 时一律退化为 opaque bytes/hash。
- `test/consumers/third_party_fixture/`：建立与 CitizenApp 完全无关的途遇/第三方风格 fixture，使用不同业务载荷、
  storage 和 RuntimeCall，证明无需修改 SDK 生产代码即可接入。
- `test/consumers/external_signer/`：建立只实现 `QR_V1` 通用 request/response 的测试签名器；仅使用测试密钥，验证
  request 绑定、expiry、owner、source、hash、签名和一次消费，不复制或依赖 CitizenWallet 实现。
- `native/ffi/tests/`：继续维护精确 C ABI、C11/C++17、feature matrix、所有权和错误合同；`test/api/`、
  `test/platform/`、`test/wallet/`、`test/transaction/` 维护 Dart 与五端共享向量和状态机断言。
- `android/`、`darwin/`、`linux/`、`windows/` 的生产目录只允许补充投影合同注释和必要缺失测试；不得新增 Core
  能力的本地实现、业务状态或平台专用协议。
- `scripts/test.sh`、`scripts/build-native.sh`、`scripts/release.mjs`、`scripts/release.test.mjs` 仍是唯一测试、
  构建与发布入口；所有输出写入 `/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk/`，源码树禁止出现 build、
  target、`.build` 或发布产物。
- `/Users/rhett/TATA/tataconsole/flows/gmb/citizensdk/{ci.mjs,release.mjs,remote-jobs.json}` 仅在真实多 runner 验收确有
  必要时做最小调度调整；不在 GMB 仓库新增 `.github` 产品工作流，也不复制中央构建逻辑。
- `README.md`、`CHANGELOG.md`、`native/**/README.md`、`docs/{ARCHITECTURE,SECURITY,DART_API,C_ABI,
  WALLET_MODEL,SOURCE_PROVENANCE}.md` 和本任务卡记录最终合同、证据、限制及三类 consumer 边界。

实施顺序：

1. 只读冻结 116/4/3/17/62 精确闭集、错误码、result kind、生命周期、来源哈希、CitizenWallet 与 PoW 基线；先补
   失败门禁，确保后续验收不能通过扩大 API、放松扫描或使用内部符号绕过。
2. 建立 reference、CitizenApp-shaped、third-party-shaped 三类只依赖发布面的 consumer 和独立 external signer；
   共用同一组 SDK 发布物，业务 fixture 只在各自目录构造 storage key、SCALE payload 与 opaque RuntimeCall。
3. 按六类能力建立跨 consumer 矩阵：钱包创建/导入/删除、热冷签名、`QR_V1`、轻节点与任意验证 storage、热冷
   交易及 execution 历史；验证三类业务变化不导致 SDK 生产代码或公开合同变化。
4. 补齐跨语言失败向量：空值/上限/Unicode、owner/source 错配、short-buffer、错误 kind、过期/取消/重复消费、
   stop/close、回调乱序、广播前后失败、reorg/finalized System outcome 和数据库重开；五端结果必须一致。
5. 仅通过仓库脚本完成 Rust、Flutter、Release、abi-host、Apple、Android、本机 Linux/Windows 合同检查；冻结提交后
   再通过中央流程执行真实 Linux/Windows/macOS/Android runner 和发布闭包，结果必须对应同一提交与来源哈希。
6. 更新文档、注释、测试数量、精确闭集、Release hash/map 和来源记录；清理无引用 fixture、dead code、临时产物
   与过时说明，最后执行 diff、业务词、其它 QR 版本、源码产物、CitizenWallet 和 PoW 零改动审计。

测试矩阵：

- 钱包：12/18/24 词助记词创建与用户手工重新导入、强认证、仅公钥冷账户、同钥去重、错误网络/长度、并发、
  reopen/delete/close；不读取旧 App 钱包，不提供迁移或兼容。
- 签名与 `QR_V1`：热签名、通用 external signer、冷交易 request/response、账户公钥、QR 图片；错误 owner/request/
  signer/hash/signature/expiry/nonce、重复消费和已删除 kind `4` 必须失败；生产面不得出现其它 QR 版本。
- 轻节点与链读取：定制 PoW chain spec、同步/重连/停止、verified storage/proof、header/finality、数据库 reopen；
  交易 submit/watch 直接走既有 Provider/上游路径，不复制网络栈或修改 PoW 文件。
- 交易与历史：至少三种互不相关的 App-generated opaque RuntimeCall 覆盖 prepare、热/冷执行、pending-before-
  broadcast、submit/watch、finalized System outcome、失败恢复、分页、重开和边界；SDK 历史只含自身 execution fact。
- 五端与打包：C11/C++17、Dart、Kotlin/JNI/AAR、Swift/XCFramework、Linux/Windows C++ Host 的精确方法、符号、
  架构、链接、ownership、错误和真实消费者全部验证；测试不得从源码内部路径偷用实现。
- 通用性反向门禁：SDK 生产源码、公开 API、持久状态和发布包不得出现 CitizenApp/途遇/第三方业务 schema、页面
  DTO、action 白名单、业务 storage/call codec、迁移层、兼容层或 CitizenWallet 实现依赖。

完成门禁：三类 consumer 必须使用同一正式 SDK 发布面和发布物完成各自不同业务，不修改 SDK 生产代码；六类能力
和五端真实打包全部通过；当前精确闭集、唯一 `QR_V1`、无业务模型、无迁移兼容、CitizenWallet 与 PoW 零改动均由
自动门禁证明。真实多 runner 涉及提交、推送或远程调度时，须先单独说明将发生的外部状态变更并取得明确授权；
未获授权前只完成本地可验证部分，绝不伪造其它平台结果。得到确认后一次完整执行 1.9。

完成记录：

- 新增 `test/consumers/` 11 文件测试闭集：reference consumer 同时组合 `CitizenChain`、`CitizenWallet`、
  `CitizenSigning`、`CitizenQr`、`CitizenTransactions`、`CitizenHistory`；CitizenApp-shaped 与
  third-party-shaped fixture 各自拥有完全不同的业务 storage key、SCALE 风格事件和 RuntimeCall 编码；generic
  external signer 只组合 `CitizenSigning` 与 `CitizenQr`。四类适配代码只导入根公开库。
- 三种互不相关的 App-generated opaque RuntimeCall 均通过同一 `prepareTransaction` 路径；CitizenApp fixture 的
  destination/amount/remark 和第三方 fixture 的 booking/route/seat 只存在于各自测试目录，未进入 SDK 生产代码、
  公共类型、持久状态或发布包。
- Release 增加多消费者反向门禁并把 SDK 测试来源闭集从 184 项冻结为 195 项；当前公共面仍精确为 116 个 Core
  产品 C 符号、4 个内部测试符号、Apple 3 个 QR 图片符号、Linux/Windows 各 17 个 Host 符号和 62 个 Flutter
  方法，未因消费者增加生产 API。
- Rust workspace/all-targets 全部通过；Flutter 137 项全部通过，其中新增多消费者合同 7 项；Release 103 项全部
  通过；`abi-host` 通过 116 个产品符号和 C11/C++17 消费者；Android ARM64 Core/JNI/AAR 真实构建通过。
- Apple Core 的 iOS device、iOS simulator、macOS 三个 ARM64 slice 及 Core XCFramework 生成已经通过；随后只因
  当前环境缺少可读取的 Flutter Apple engine framework 而停在 Flutter adapter 编译前。按用户明确要求，本步骤
  不再启动、停止、删除、安装或修改任何 Flutter 下载/安装，因此 Apple Flutter adapter、Apple tests 和最终
  XCFramework 复制不宣称通过，待用户已有 Flutter 安装可用后只读消费该安装再验收。
- 未提交、未推送、未触发远程 runner；Linux/Windows 只通过同源 Release 源码、精确闭集和合成失败合同，不冒充
  原生 runner 结果。任务命令未写入 CitizenApp 或 CitizenWallet；`native/smoldot/pow/**` 三个受保护文件摘要保持
  `56e14104...`、`61a9c6d4...`、`e529306b...`，没有修改上游或既有 PoW 定制。

### 1.10 功能等价及通用性验收后的 SDK 改进

状态：1.10.1—1.10.3 已完成；剩余工作已统一并入 1.10.4，合并方案待确认、未执行。

目标与边界：

- 以 1.9 冻结的通用公共面和多消费者证据为基线，先量化审计安全、易用性、性能、数据库增长、后台同步、
  错误可观测性和五端一致性，再按证据实施 SDK 自身改进；不把某个 App 的业务需求当成 SDK 改进。
- CitizenApp、途遇系列产品和第三方继续自己实现 storage key、SCALE 业务解码、RuntimeCall 业务编码、页面和业务
  状态；SDK 只改进钱包、通用签名、唯一 `QR_V1`、轻节点/验证链读取、opaque 交易与 execution 历史。
- 不迁移、不兼容、不增加 wrapper、alias、fallback 或 deprecated 入口；不读取旧 App 钱包/交易数据。用户需要
  旧助记词账户时仍由用户手工输入助记词重新导入。
- CitizenWallet 继续作为完全独立产品，不修改其源码、功能、依赖或发布物；禁止在 SDK 内复制其 UI、相机、扫码
  流程或产品逻辑。
- `native/smoldot/pow/**` 和上游轻节点实现保持只读；优先复用现有同步、验证、数据库、transaction submit/watch
  能力。任何上游或既有 PoW 定制代码改动必须停止本步骤，另列准确文件、原因和替代方案，取得二次确认后执行。
- 117/4/3/17/62 精确闭集现已冻结。只有审计证明确有跨 App 的底层能力缺口时，才为该能力另出子步骤方案；不得
  借“易用性”扩大业务面或预留其它 QR 协议版本。

目录及职责注释：

- `native/contracts/src/`：只承载跨语言稳定的通用配置、能力和限制；新增字段必须能由所有消费者解释，且不得包含
  App 名称、业务 action、页面 DTO、业务 storage/call schema 或迁移状态。
- `native/engine/src/`：改进密钥生命周期、会话取消、轻节点生命周期、交易状态机、execution 历史保留和通用
  诊断事实；仍以单一 Engine 为真源，不建立第二套缓存、提交、watch 或历史实现。
- `native/signer/src/`、`native/qr/src/`：审计敏感内存清理、长度边界、随机数、expiry/nonce/owner/source/hash/
  signature 绑定和一次消费；只允许 `QR_V1`，不得设计任何其它版本。
- `native/smoldot/provider/src/`：只改进 SDK-owned Provider 适配、取消、背压、错误映射和已有上游能力调用；
  `native/smoldot/pow/**` 不改，Provider 不复制上游网络、数据库、交易或验证实现。
- `native/ffi/src/` 与 `include/`：只做通用 Core 能力的稳定 C 投影，完善 owner、short-buffer、一次释放、线程、
  回调和错误注释；不得把内部诊断、密钥或 signer message 暴露为公共数据。
- `lib/src/{api,models,platform}/`：Dart 只提供防御复制后的通用不可变模型和薄 API；平台目录只负责值投影、取消和
  生命周期桥接，不保存第二份状态。
- `android/`、`darwin/`、`linux/`、`windows/`：Kotlin/Swift/C++ 继续做同一 Core 结果的薄包装；改进必须由共享
  向量证明五端一致，禁止平台专用业务语义或协议分叉。
- `test/consumers/`：reference、CitizenApp-shaped、third-party-shaped 和 external signer 作为永久通用性回归；
  各 fixture 的业务编码只留在自己的目录，不能进入 SDK 生产代码。
- `scripts/{test.sh,build-native.sh,release.mjs,release.test.mjs}`：记录性能/大小基线、精确闭集、来源 hash、跨平台
  失败门禁和发布证据；所有生成物继续只写仓库外部 TataConsole 缓存。
- `README.md`、`CHANGELOG.md`、`native/**/README.md`、`docs/{ARCHITECTURE,SECURITY,DART_API,C_ABI,
  WALLET_MODEL,SOURCE_PROVENANCE}.md` 与本任务卡：每个已实施改进同步说明动机、边界、风险、测试和残留限制。

实施顺序与逐项确认门禁：

1. `1.10.1 基线与问题分级`：只读采集钱包/签名/QR/轻节点/交易/历史的延迟、内存、数据库增长、取消耗时、错误
   覆盖和五端差异；输出可复现测量命令、目录、基线值及 P0/P1/P2 排序，不改生产代码。先出本子步骤技术方案，
   用户确认后执行。
2. `1.10.2 安全与资源边界`：仅处理基线确认的敏感内存、输入上限、owner/source 绑定、取消/关闭、并发、背压和
   资源释放问题；先写失败测试，再自 Core 向五端薄投影。涉及公开合同或上游代码时必须另行说明并确认。
3. `1.10.3 通用 API 易用性与错误可观测性`：消除跨端命名/错误映射漂移，提供不含业务语义的阶段、错误类别和
   关联标识；不得暴露密钥、签名原文、未经验证链数据或 App 业务字段，不以 wrapper/alias 保留旧入口。
4. `1.10.4 第一部分最终合并步骤`：一次完成性能与持久化增长、后台同步与生命周期一致性、完整回归与发布冻结。
   原计划的 1.10.5、1.10.6 全部并入本步骤，不再单独确认或执行；确认本步骤后连续完成全部实现、测试、文档、
   注释、Release hash 和残留清理，最后冻结第一部分并直接输出第二部分 2.1 的完整技术方案。策略只能按时间、数量、
   字节和通用状态配置，不能按 pallet/action/App 业务类型分支；同步、交易 submit/watch 和数据库继续复用现有上游
   轻节点能力，平台层不得各自实现同步器或交易观察器。

每个 `1.10.x` 都必须先提交包含准确目录、接口变化、失败向量、回滚边界和验收命令的技术方案，取得确认后才执行。
1.10.4 是第一部分剩余工作的唯一合并步骤：确认后不得再拆成 1.10.5/1.10.6 或要求中途确认；只有实际发现必须修改
`native/smoldot/pow/**`、CitizenWallet、CitizenApp、其它产品，或出现超出本方案批准边界的实现偏差/阻塞时才暂停
沟通。完成后更新全部文档、注释、测试和 hash，清理残留并自动输出 2.1 完整方案，不要求用户再次催促。

测试与完成门禁：

- 功能回归：三类消费者对六类公共能力的行为不变；至少三种互不相关 opaque RuntimeCall 和不同业务 storage key
  无需 SDK 改码；热冷账户继续共用 prepared execution、submit/watch 和历史状态机。
- 安全回归：敏感数据清理、强认证、owner/source/request/hash/signature/expiry 绑定、short-buffer、一次释放、
  取消/关闭/并发/乱序全部有失败测试；日志和公共错误不泄露秘密或未经验证数据。
- 资源回归：建立可重复的延迟、峰值内存、队列、数据库增长与 reopen 基线；优化后不得以丢失 finalized 证明、
  execution 恢复或跨端一致性换取指标。
- 平台与发布：117 个 Core 产品符号、4 个内部测试符号、Apple 3 个 QR 图片符号、Linux/Windows 各 17 个 Host
  符号和 62 个 Flutter 方法若无另行批准保持不变；C11/C++17、Dart、Kotlin、Swift、C++ 与发布消费者全部通过。
- 反向门禁：生产源码和发布包不含 App 业务 schema、迁移/兼容层、CitizenWallet 实现依赖、其它 QR 协议版本或
  新的轻节点网络/交易/数据库副本；CitizenWallet 与 `native/smoldot/pow/**` 的基线 hash 保持不变。

完成门禁：只有经量化问题清单逐项关闭、三类消费者及五端合同全部回归、文档/注释/hash 同步、源码树和外部临时
产物清理完成，1.10 才可标记完成；无法在本机证明的远程/真机结果必须明确标为待授权，禁止用源码扫描替代真实结果。

#### 1.10.1 基线与问题分级技术方案

状态：已确认并完成（2026-09-11）；生产 API/ABI/schema/协议零修改，Flutter 按明确要求未操作。

本步骤只测量、审计和排序，不修改生产代码、公开 API、协议、ABI、平台绑定或数据库 schema；基线发现的问题进入
1.10.2—1.10.4 按任务卡方案处理，不能在本步骤顺手修复。测试只使用独立临时账户、测试密钥、内存 Provider/Store 和
仓库外临时数据库，不读取 CitizenApp、CitizenWallet 或任何用户数据。

输出目录与注释职责：

- `docs/audits/SDK_BASELINE_1_10_1.md`：唯一人工可读审计报告；按“测量环境、命令、样本、结果、风险、证据路径、
  建议归属子步骤”记录，每个结论区分实测、源码事实和推断，禁止把未运行平台写成通过。
- `test/baselines/sdk_1_10_1_contract_test.dart`：冻结公共 Dart 类型、六端口组合、输入上限、防御复制、错误类别和
  三类 consumer 不变性；只断言稳定合同，不把机器相关毫秒数写成脆弱阈值。
- `native/engine/tests/baseline_resource_contract.rs`：用确定性 fake Vault/Store/Provider 测量并断言队列、会话、
  runtime cache、prepared execution、history page 和取消后的资源数量有界；不增加生产 benchmark hook。
- `native/smoldot/provider/tests/baseline_lifecycle_contract.rs`：只通过现有公开 Provider 测试面记录 start/stop、重连、
  submit/watch、数据库 export/import 的阶段和上限；不读取或修改 `native/smoldot/pow/**`。
- `scripts/release.test.mjs`：加入审计报告/基线测试的来源闭集与反向边界，拒绝报告缺项、生产诊断 hook、其它 QR
  版本、业务模型或测试数据越出外部缓存；`scripts/release.mjs` 只同步新文件和 SHA-256 闭集。
- `/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk/step-1-10-1.<随机>/`：保存本轮时间、峰值 RSS、临时数据库、
  事件轨迹和构建大小原始证据；完成后精确移入废纸篓，不把机器路径或生成物写入源码树。

采集与分析顺序：

1. 冻结环境与合同：记录提交状态、Rust/Dart/Flutter/Clang/Swift/Java/NDK/Gradle 版本、116/4/3/17/62 闭集、
   12/18/24 助记词和唯一 `QR_V1`；记录三类 consumer、CitizenWallet、PoW hash 基线。不得安装、更新或停止任何
   工具；缺失工具只标记相应指标未测。
2. 安全基线：逐项追踪助记词、password、DEK、child secret、signer message、signature、QR session 和
   signed extrinsic 的创建、借用、复制、日志与释放；验证强认证、zeroize、owner/source、expiry、nonce、hash、
   取消、重复消费和错误回显边界，输出准确文件与风险等级。
3. 资源与性能基线：在固定样本数和预热规则下分别记录钱包 create/import/sign、QR parse/sign/consume、verified
   storage、prepare/execute/history page 的 wall time、CPU、峰值 RSS、分配/复制热点、队列深度和取消收敛时间；
   至少重复 5 轮并报告中位数、P95、最大值和样本离散度，不承诺跨机器绝对性能。
4. 数据增长基线：以 0、1、100、1,000 个 execution 与 runtime cache 样本记录数据库字节、索引、重开时间、
   retention 后残留和失败恢复；只按通用状态/时间/数量/字节分析，不引入 pallet、action 或 App 业务分类。
5. 生命周期与五端差异：对 Core、Dart、Kotlin、Swift、Linux/Windows C++ 的 start/stop/reopen、前后台、断网、
   submit/watch 恢复、取消、回调顺序和错误映射建立对照表。本机未运行的平台只引用合同证据，单列“待 runner
   验证”，不得用源码扫描代替运行。
6. 分级与交付：P0 仅包含秘密泄漏、验签/验证绕过、持久状态损坏或不可恢复资源失控；P1 为有界性、并发、明显
   性能/增长和跨端语义漂移；P2 为不改变安全语义的易用性与诊断改进。每项必须给出复现、影响、建议目录、是否
   涉及公开合同/上游和对应 1.10.x；没有证据的问题不得进入实施清单。

测试与验收命令：

- 只通过 `scripts/test.sh cargo --workspace --all-targets --locked`、`scripts/test.sh flutter --timeout=2m` 和
  `scripts/test.sh release` 回归；Flutter 不可用时不安装、不下载、不操作其进程，只如实保留该项待验收。
- 使用 `scripts/build-native.sh abi-host` 复核产品符号、C11/C++17 和构建大小；Apple/Android 只在现成受控工具
  可读时执行，不为完成指标修改或安装工具。Linux/Windows 原生 runner 仍需单独远程授权。
- 最终执行 `git diff --check`、生产业务词/其它 QR 版本扫描、源码树 build/target/.build 扫描、195 文件测试闭集、
  PoW hash 以及 CitizenApp/CitizenWallet 零写入审计；任何失败都进入报告，不能删除测试或放宽门禁。

完成门禁：交付完整基线报告、可重复命令、原始证据摘要、P0/P1/P2 清单和逐项归属；生产代码/公开合同/协议/ABI
零变化，CitizenWallet 与 PoW 零写入，无迁移兼容或其它 QR 版本；文档、注释、测试及 Release hash 同步后，自动
输出最高优先级的 1.10.2 安全与资源边界完整技术方案，等待确认后再实施。

执行结果：

- 新增 `docs/audits/SDK_BASELINE_1_10_1.md` 作为唯一人工报告；测量环境、合同闭集、安全链路、5 轮性能、
  0/1/100/1,000 条 execution 数据库增长、retention、生命周期矩阵和未运行平台均已明确区分实测/源码事实/推断。
- 新增 Dart 公共合同基线、Engine 资源基线和 smoldot provider 离线生命周期基线；Rust 基线和完整 workspace 通过。
  Dart/Flutter 基线因“不得操作 Flutter 下载安装/进程”的明确边界未运行，不写成通过。
- ABI host 在明确仓库外 work/output 目录构建通过：21,221,664 bytes，116 个产品符号 + 4 个内部测试符号；
  没有修改或读取 `native/smoldot/pow/**` 生产逻辑。
- 分级为 P0=0、P1=5、P2=2。P1 包含：持久 runtime cache 无淘汰、history 条数与 32 MiB 宿主记录上限不一致、
  runtime metadata 64 MiB 合同与 8 MiB 宿主记录上限不一致、history 单 BLOB O(N)、retention 后 SQLite 文件不缩小。
- 本步骤没有读取用户数据库；临时 SQLite/ABI/测量证据完成摘要后精确清理。CitizenApp、CitizenWallet 和 PoW
  文件树在本步骤前后的内容 diff/hash 不变；不宣称三个工作树原本 clean。

#### 1.10.2 安全与资源边界完整技术方案

状态：已完成并复核（2026-09-11）。

目标与范围：只关闭 1.10.1 已证实的 P1-01、P1-02、P1-03，不把没有证据的“顺手优化”混入本步。SDK 仍只提供
通用钱包、签名、唯一 `QR_V1`、验证链读取、轻节点、opaque 交易和通用历史；不增加 App 业务模型，不改
CitizenWallet，不读取/迁移旧数据，不修改 `native/smoldot/pow/**`。P1-04/P1-05 的结构和压缩优化保留到 1.10.4。

目录与职责：

- `native/contracts/src/chain.rs`：Core 功能合同 `MAX_RUNTIME_METADATA_BYTES = 64 MiB` 保持不变。该上限约束链读取与
  内存中的完整 runtime context，不能因为性能 cache 的单记录容量而降低。
- `native/contracts/src/store/runtime_cache.rs`、`native/contracts/src/lib.rs`：新增内部持久 cache 合同：最多 64 个
  准确 block-hash context；四个平台现有 SQLite 对完整 host record 的上限为 8 MiB，扣除 56-byte envelope 和
  55-byte typed runtime 字段后，单条可持久 metadata 为 `8 MiB - 111 bytes`。这是性能 cache 容量，不是 Core
  功能上限。
- `native/engine/src/engine.rs`：准确块 runtime context 先查 Core 内存，再查宿主持久 cache，最后调用 provider。
  provider 返回 `8 MiB - 111 bytes` 以上、但不超过 64 MiB 的合法 metadata 时，Core 正常返回并保留内存 cache，
  跳过持久 store，不得因 cache 不可写反向使链读取失败；宿主异常超大 cache 记录不作为可信数据，也不触发迁移。
- `native/ffi/src/host_codec.rs`：RuntimeCache codec 的最大完整 encoded record 与平台现有 8 MiB 限制一致；只编码
  满足持久 cache 容量的 context。Host record 格式版本不变。
- `native/contracts/src/store/runtime_cache.rs`：新增通用持久 cache 合同常量 `MAX_PERSISTED_RUNTIME_CONTEXTS = 64`，
  明确 `store` 必须在同一事务中保持至多 64 个准确 block-hash 记录。trait 方法签名不变。
- `android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkPublicStore.kt`、
  `darwin/Sources/CitizenSDK/CitizenSDKPublicStore.swift`、`linux/src/citizen_sdk_public_store.cc`、
  `windows/src/citizen_sdk_public_store.cc`：在现有 `runtime_cache_store` 事务中按 SQLite `rowid` 驱逐最早写入项，
  插入/替换和淘汰原子完成；不新增表、列、索引或数据库文件。固定为通用 FIFO 写入保留策略，不按链业务/App 分支。
- `native/contracts/src/store/transaction_history.rs`：新增通用 durable weight 上限与每条保守固定开销，weight 只由
  callData bytes、signed extrinsic bytes 和 1,024-byte 通用保守固定开销组成；总预算固定为 31 MiB。
  `TransactionHistoryState::try_new` 同时验证 `records <= 4096` 和总 weight，使任何合同合法 state 都能进入现有
  32 MiB host record 并保留至少 1 MiB envelope/编码余量。
- `native/engine/src/{transaction_prepare.rs,transaction_history.rs,engine.rs}`：冻结 extrinsic template 已能在签名前
  精确给出最终 signed-extrinsic 长度。热钱包解锁/签名或冷钱包 `QR_V1` 会话建立前先只读准入；最终持久化仍在
  CAS 门内用真实候选重复检查以关闭并发窗口。按数量或 weight 腾出空间时可重复驱逐“最旧且 retention-terminal”
  的记录，永不驱逐 Pending/InBlock；无法容纳稳定返回 `conflict`，不广播、不产生部分历史写入。
- `native/engine/tests/baseline_resource_contract.rs`：把 1.10.1 “80 条持久 cache 无淘汰”的基线改为目标合同，
  断言 80 次写入后仅保留最新 64；另验证超过持久容量的 metadata 首次由 provider 返回、第二次命中内存，provider
  只调用一次、持久 store 零调用且链读取两次均成功。
- `native/contracts/tests/chain_contract.rs`、`native/contracts/tests/state_store_contract.rs`、
  `native/contracts/tests/transaction_history_contract.rs`（新增）：覆盖 metadata 最大值/+1、history 最大 weight/+1、
  4,096 小记录、15/16 大记录、所有记录均 open 时 fail-closed、终态多条驱逐顺序和状态更新不突破预算。
- `native/ffi/src/host_codec_tests.rs`：验证 `8 MiB - 111 bytes` metadata 编码后的完整 record 恰好为 8 MiB；
  `+1` 仍是 Core 合法内存值，但持久编码明确返回 `payload_too_large`；保留损坏、wrong-domain、short-buffer 和
  hostile host response 拒绝测试。
- `android/native/src/androidTest/**`、`darwin/Tests/CitizenSDKTests/**`、`linux/test/**`、`windows/test/**`：各自直接
  写入 80 个 cache 记录，断言最新 64 可读、最旧 16 不可读；替换已有 hash 后再写一条可证明替换被提升为最新且
  表没有增长。数据库文件、权限、schema 和 transaction 边界保持不变。
- `docs/ARCHITECTURE.md`、`docs/SECURITY.md`、`docs/C_ABI.md`、`docs/DART_API.md`、平台文档及本任务卡：记录
  runtime metadata 单一 admission、持久 cache 上限、history weight/backpressure 和不迁移不兼容边界。
- `scripts/release.mjs`、`scripts/release.test.mjs`：同步测试/文档 hash；新增反向门禁，拒绝 Core 64 MiB 功能上限
  被持久 cache 降低、无界 `runtime_cache_store`、history 仅检查条数、schema 变化、业务分类和 PoW 漂移。
  `native/smoldot/SOURCE_SHA256.json` 只复核、不因本步骤改写上游来源声明。

公开合同与兼容边界：

- 方法、C ABI struct/vtable、116/4/3/17/62 闭集、Host record version、SQLite schema 和唯一 `QR_V1` 均不变。
- `MAX_RUNTIME_METADATA_BYTES` 继续为 64 MiB；公开链读取能力不收紧。新增的 `8 MiB - 111 bytes` 仅是内部可持久
  cache 容量。超过该容量的合法 metadata 仍可被 App 读取和在本进程复用，只是不写性能 cache。
- history 的 4,096 条上限保留，同时新增总 weight 上限；小记录仍可到 4,096，大记录按实际恢复材料触发通用
  backpressure。不会截断/丢弃 open record、callData、signed extrinsic 或 finalized proof。
- 现有 SQLite 表按原 schema 直接执行新写入策略；不扫描、转换或重写旧数据库，不增加迁移代码。若现有表已超过
  64 行，只在下一次正常 cache store 的同一事务内按当前规则收敛，这属于现行写入不变量，不是旧数据迁移。

执行顺序与失败向量：

1. 先把 P1-02/P1-03 的现有复现改为失败测试：Core 64 MiB 不变、持久 metadata `8 MiB-111/+1` 分流；history
   4,096 小记录、15/16 最大记录、weight 边界和 pending-before-broadcast 零副作用。
2. 实现 Core/持久 cache 两个不同职责的明确上限和 history weight；在签名前只读预检，持久化时再次精确准入，
   保证已知资源不足不触发签名、任何失败都不进入网络提交或部分历史写入。
3. 为四个平台 store 先加 80→64、重复键、事务回滚失败测试，再实现同事务 FIFO 淘汰；不得新增平台后台线程、
   定时器或第二套 cache。
4. 运行 Rust、可用原生平台与 Release 闭集，复核 ABI/schema/hash；Flutter 仍只在用户允许且现成环境可用时运行，
   不安装、不下载、不启动或停止其安装流程。
5. 更新文档、注释、hash，清理外部临时产物；输出 1.10.3 完整技术方案并等待确认。

关键失败测试：

- Core metadata 恰好 64 MiB 可创建，`+1` 返回 `invalid_argument`；metadata 恰好 `8 MiB-111` 可持久编码成 8 MiB
  完整记录，持久容量 `+1` 仍可链读取并命中内存，但宿主 store 调用数为 0。
- history 的 4,096 小记录与 15 条最大记录成功，16 条最大记录在 contract admission 失败；全部 open 且资源不足时
  签名前预检返回 `conflict`、历史 CAS 为零，广播为零。
- 64 个不同 block 后全可读；第 65—80 次每次提交后 count 始终 64；最旧被淘汰、最新保留；替换相同 hash 不增长。
- SQLite insert 或 prune 任一步注入失败时整体 rollback，旧 64 条保持；损坏/过大宿主记录继续 fail-closed 且不泄漏内容。
- 并发 store 最终不超过 64；close/cancel 与 store 竞态不越过现有 lease，不产生关闭后回调。

回滚边界：本步骤可整体回滚 contracts/engine/host store/tests/docs/release hash；因为不改 schema、ABI 和记录格式，
不存在迁移回滚。不得只回滚 Core 上限而保留平台策略，或只回滚平台策略而保留合同承诺。任何需要修改
`native/smoldot/pow/**`、CitizenWallet、公开方法/ABI/schema 的新发现都立即停止并单独二次确认。

验收命令与门禁：

- `scripts/test.sh cargo --workspace --all-targets --locked`
- `scripts/test.sh flutter --timeout=2m`（只有在不触碰 Flutter 安装/下载且用户允许时；否则明确保留未运行）
- `scripts/test.sh release`
- 使用 `scripts/build-native.sh abi-host` 的仓库外 work/output 复核 116+4 符号；现有本地工具可用时运行 Apple/
  Android 原生 store 测试，Linux/Windows 继续由授权 runner 验证。
- `git diff --check`、生产业务词/其它 QR 版本、schema、源码树 build/target/.build、CitizenApp/CitizenWallet diff hash、
  `native/smoldot/pow/**` 内容 hash 全部通过；不得以源码扫描冒充未运行平台。

完成门禁：P1-01/P1-02/P1-03 的失败向量全部转绿；任何合同合法 history state 均可被当前宿主编码，Core 合法但
超过持久容量的 metadata 保持完整链读取并只驻留内存；持久 cache 始终有界；pending-before-broadcast、秘密生命周期、
三类 consumer、ABI/QR/schema/PoW/三产品边界不回归；
文档/注释/测试/Release hash 完整同步后才可标记 1.10.2 完成。

执行结果（2026-09-11）：

- P1-01 已关闭：Android、Apple、Linux、Windows 沿用原 `runtime_cache` 表，在原 store transaction 内执行
  `INSERT OR REPLACE` 与 FIFO 淘汰；每次成功提交后最多 64 条，同一 hash 替换会提升为最新。四端合同测试覆盖
  80→64、重复键提升，以及注入 prune 失败后插入与淘汰整体回滚；没有新增表、列、索引、文件或迁移代码。
- P1-03 已关闭且没有收紧 Core：`MAX_RUNTIME_METADATA_BYTES` 仍为 64 MiB；持久 cache metadata 上限单独固定为
  `8 MiB - 111 bytes = 8,388,497 bytes`。边界内完整 host record 恰为 8 MiB；超过持久容量但不超过 64 MiB 的
  metadata 正常完成链读取、进入 Core 内存 cache、跳过宿主 store，连续读取只调用 provider 一次。
- P1-02 已关闭：history 同时受 4,096 条与 31 MiB durable weight 约束；单条 weight 为 1,024 bytes 加原始
  callData 与 signed extrinsic 长度。4,096 条小记录、15 条最大记录通过，16 条最大记录在合同准入时拒绝；Engine
  在热签解锁/签名和冷签 `QR_V1` 会话建立前执行零写入预检，并在最终 CAS 门内用真实候选复检。淘汰只选择最旧
  retention-terminal 记录，Pending/InBlock 永不淘汰，空间不足返回稳定 `conflict` 且不签名、不广播。
- `scripts/test.sh cargo --workspace --all-targets --locked` 全工作区通过；ABI host 在仓库外 work/output 构建通过，
  产物 21,223,632 bytes，导出仍为 116 个公开产品符号 + 4 个内部桥接符号，C11/C++17 头文件通过。公开 C ABI、
  Flutter 62 方法、Apple QR image 3 方法、Linux/Windows Host 17 方法、唯一 `QR_V1` 和 host record version 均未改。
- `scripts/test.sh release` 的 105 项发布合同全部通过；Core Rust 固定闭集由 107 更新为 108 个文件，SDK 测试固定
  闭集由 198 更新为 199 个文件，新增资源合同与全部变更文档/源码/测试摘要均已进入反向门禁。
- 四个平台生产实现与平台测试已完成源码合同；当前机器未运行 Android instrumented、Apple package、Linux 或 Windows
  runner，不把源码扫描写成运行通过。按用户明确边界，本步骤没有调用 Flutter 命令，没有安装、下载、启动、停止或
  配置 Flutter。
- `native/smoldot/pow/**` 内容 hash 仍为
  `ced9bcd7af45c48ce0ddd4dd077fff035ff72c00fa84aa42067bb10e072d5999`；CitizenApp、CitizenWallet 均未由本步骤
  修改。不读取、不迁移、不兼容旧钱包或旧数据库，也没有加入任何 App 业务模型。P1-04/P1-05 仍按计划留给 1.10.4。

#### 1.10.3 通用 API 易用性与错误可观测性完整技术方案

状态：已确认并完成（2026-09-11）。

目标与范围：只处理 1.10.1 的 P2-01 和五端公共错误上下文缺口。现有 22 个稳定错误类别继续作为唯一机器判断；
新增的阶段和关联信息只描述 SDK 通用操作，不描述 transfer、投票、治理、旅行、订单或任何 App 业务。不得记录或
返回助记词、password、payload、callData、签名、extrinsic、metadata/storage 内容、账户私有材料或原生地址。
不改 CitizenApp、CitizenWallet、`native/smoldot/pow/**`，不增加迁移、兼容、alias、wrapper、fallback 或其它 QR 版本。

公开合同选择：新增一项只读 C 结果 getter，而不修改已有 struct 布局、Host vtable、SQLite schema 或 Flutter 方法
数量。Core 产品符号闭集预计由 116 增至 117；Flutter 方法仍为 62、Apple QR image 为 3、Linux/Windows Host 各为
17。该变化只在用户确认本步骤后实施。

目录与职责：

- `native/contracts/src/error.rs`、`native/contracts/src/lib.rs`：新增闭集 `FailureStage`，只允许
  `admission`、`validation`、`authentication`、`persistence`、`provider`、`verification`、`cancellation`、
  `teardown` 八个通用阶段；`ContractError` 保存稳定 error code、stage 和不含输入字节的诊断文本。没有 App operation
  或业务 action。
- `native/engine/src/error.rs` 及钱包、签名、QR、链读取、交易、历史和生命周期入口：在拥有真实语义的边界标注
  stage，禁止 FFI/平台通过 message 文本猜测。错误传播必须保留原 code/stage；跨层转换不能把 storage/network/
  authentication/integrity 等折叠为 unavailable。
- `native/ffi/src/{abi.rs,error.rs,ownership.rs,requests.rs,lib.rs}`、`include/{citizensdk_types.h,citizensdk.h}`：追加
  `citizensdk_failure_stage_t` 与 `citizensdk_result_get_failure_stage`。已有 `citizensdk_result_info_t` 布局不改；getter
  只接受当前 owner 的 ready error result，成功 result、错误 owner、未知/释放后 handle 均失败关闭。同步 admission
  失败由调用入口的已知操作阶段标注，不伪造 request id。
- `lib/src/api/citizen_sdk_error.dart`、`lib/src/platform/{citizen_sdk_flutter_codec.dart,
  citizen_sdk_flutter_sessions.dart}`：`CitizenSdkException` 固定包含 code、stage、公开 SDK method 名和可选
  requestSequence/sessionId。method 名来自 62 方法金标，不接收平台自由文本；异步 completion 使用已有 request sequence
  关联，不创建第二套追踪 ID。
- `android/native/src/main/kotlin/org/citizen/sdk/{CitizenSdkError.kt,CitizenSdkOperation.kt,CitizenSdk.kt}`、
  `darwin/Sources/CitizenSDK/{CitizenSDKError.swift,CitizenSDKOperation.swift,CitizenSDK.swift}`、Linux/Windows
  `include/citizen_sdk/citizen_sdk_error.hpp` 与 session/codec：投影同一八阶段数值和 operation/request 关联。各平台不得
  自定义阶段、重编号错误、输出本地路径或把异常对象序列化进持久状态。
- `native/ffi/tests/{error_contract.rs,request_contract.rs}`、`native/ffi/src/*_tests.rs`：覆盖 22×8 合法/非法映射、同步
  admission、异步 completion、取消、storage/provider/verification、wrong-owner、释放后 handle、short-buffer 和
  panic；断言错误文本与结构中没有敏感 fixture 内容。
- `test/api/**`、`test/platform/**`、Android/Apple/Linux/Windows 对应 error/session 测试：用统一 golden matrix
  断言相同 code/stage/method/requestSequence；三类 consumer 只根据 code/stage 处理，不需要 SDK 知道其业务。
- `docs/{C_ABI,DART_API,ARCHITECTURE,SECURITY,MOBILE_PLATFORM,LINUX_PLATFORM,WINDOWS_PLATFORM}.md`、各公开
  README、本任务卡与 `CHANGELOG.md`：给出每个阶段的准确含义、可否重试边界和禁止记录字段。阶段不是进度事件，
  不能据此推断交易成功、链 finality 或设备认证结果。
- `scripts/release.mjs`、`scripts/release.test.mjs`：把 117/62/3/17 闭集、八阶段和五端 golden 固定为反向门禁；拒绝
  message 解析、自由文本 stage、业务阶段、额外 QR 协议、生产 benchmark hook 与 PoW 漂移。

实施顺序与每步失败向量：

1. 先建立只读矩阵：枚举当前 22 个 code 在 Core/C/Dart/Kotlin/Swift/Linux/Windows 的名称、数值、同步/异步来源；
   不一致项写成失败测试，不先改生产实现。
2. 在 contracts/Engine 标注八阶段并保持原 error code；测试同一错误跨 Contract→Engine→FFI 不丢 code/stage，未知
   数值返回 integrity，不回显原输入。
3. 追加单一 C getter 和 C11/C++17 header/owner/short-buffer 测试；已有结果结构、116 个旧符号及 Host vtable 字节布局
   不改，新增符号只有该 getter。
4. 自 C 真源向 Dart、Android、Apple、Linux、Windows 薄投影；同步拒绝没有 requestSequence，异步错误必须关联原
   requestSequence，session 只在实际存在时携带。删除各端重复的 message 猜测和未使用错误映射残留。
5. 三类 consumer 与 external signer 回归；阶段只能帮助诊断，不能改变重试、签名、广播、历史、QR 单次消费和
   lifecycle 语义。更新文档/hash，清理残留后输出 1.10.4 完整方案。

关键失败测试：同一 storage/network/authentication/integrity/cancel/timeout 错误跨五端 code 与 stage 完全一致；同步
非法参数没有伪 request id；异步完成关联原 request sequence；wrong-owner/released result 不能读取 stage；未知 stage
不能回退为自由文本；任意秘密、payload、callData、signed extrinsic、metadata/storage value 与本机路径均不出现在
错误对象、日志或事件。任何阶段信息都不能把 InBlock/Finalized 通知解释为执行成功。

回滚边界：可整体回滚 FailureStage、单一 C getter、五端投影、测试、文档与 Release hash；不触及数据库/钱包数据，
所以没有迁移回滚。若实施发现必须修改已有 struct/vtable、增加第二个公开 getter、引入日志系统或修改
`native/smoldot/pow/**`，立即停止并重新出方案二次确认。

验收：只通过 `scripts/test.sh cargo --workspace --all-targets --locked`、`scripts/test.sh release`、仓库外
`scripts/build-native.sh abi-host` 及现有可用的原生平台 runner；Flutter 继续不安装、不下载、不启动或停止，未运行就
明确保留。最后复核 `git diff --check`、117/62/3/17、C11/C++17、业务词/其它 QR 版本、schema、源码树生成物、三产品
边界、CitizenWallet diff hash 与 PoW 内容 hash。完成前更新文档/注释/测试/Release hash 并输出 1.10.4 完整方案。

执行结果：

- Contracts、Engine 与 FFI 建立唯一八阶段真源；22 个既有错误码及数值不变。失败 result 保存阶段并只通过新增的
  `citizensdk_result_get_failure_stage` 读取；成功、空输出、未知或释放后 result 均失败关闭。原
  `citizensdk_result_info_t`、Host vtable、result kind 与 SQLite schema 没有变化。
- Dart、Android、Apple、Linux、Windows 已投影同一 code/stage；Flutter 错误固定为
  `[1, sessionId?, requestSequence?, errorCode, failureStage, method, errorMessage?]` 七项 tuple，method 只能来自现有
  62 项公开闭集。异步 Core result 的 stage 来自 C getter，不解析 message；同步宿主拒绝使用固定 code→stage 表。
- 错误对象与注释明确排除助记词、password、payload、callData、签名、signed extrinsic、metadata/storage value、
  私有材料和本机路径；阶段只用于定位 SDK 通用边界，不表示进度、重试承诺、交易成功或 finality。
- 公共闭集现为 117 个 Core 产品符号、4 个内部测试符号、3 个 Apple QR image 符号、Linux/Windows 各 17 个 Host
  符号和五端 62 个 Flutter 方法。唯一二维码协议仍为 `QR_V1`；未加入 App operation、pallet、业务 action、迁移、
  兼容、alias、wrapper 或 fallback。
- Rust workspace/所有 target、117 符号、C11/C++17、Release 来源与反向门禁以及仓库外 Release ABI host 构建均由
  本步骤验收；Flutter 按用户明确边界没有调用、安装、下载、启动、停止或配置，Apple Flutter/移动真机及
  Linux/Windows 原生 runner 继续如实列为未运行。
- 本步骤没有修改 CitizenApp、CitizenWallet 或 `native/smoldot/pow/**`。定制 PoW 内容 hash 保持
  `ced9bcd7af45c48ce0ddd4dd077fff035ff72c00fa84aa42067bb10e072d5999`；源码树未留下 build/target/.build 产物。

#### 1.10.4 第一部分最终合并步骤：性能、持久化、生命周期与发布冻结完整技术方案

状态：已完成并复核（2026-09-11）。原 1.10.5、1.10.6 已全部并入本步骤并取消独立步骤。

合并执行合同：用户确认 1.10.4 后，以一次连续执行完成以下全部内容，中间不再按“性能与持久化”“后台同步与
生命周期”“完整回归与发布冻结”拆步骤，也不再要求用户逐段确认。内部实施顺序只是同一次执行的依赖顺序，不是
新的任务卡步骤。只有发现必须修改 `native/smoldot/pow/**`、CitizenWallet、CitizenApp、其它产品，或者实际实现必须
越过下文已批准的公共合同、数据边界和破坏性操作边界时，才立即暂停并带着准确文件、原因和替代方案沟通。

数据库边界先明确：本步骤所称数据库是 Android、Apple、Linux、Windows 宿主适配器为 CitizenSDK 创建的
`public-state-v1.sqlite3`，不是 CitizenApp 的业务数据库，也不是 CitizenWallet 的数据库，更不是在 Rust Core 中
内嵌一套数据库引擎。Rust Core 只依赖 typed store 合同；四个平台当前选择 SQLite 实现该合同。smoldot 自己的
CitizenChain 状态数据库属于现有上游轻节点能力，本步骤不复制、不替换、不修改。

目标与范围：一次关闭基线 P1-04“execution history 单 BLOB 导致 O(N) 编解码/整包重写”、P1-05“逻辑 retention
不回收 SQLite 物理空间”和 P2-01“操作级资源测量精度不足”；同时关闭 SDK 可由确定性测试证明的 P2-02
生命周期合同缺口，验证 start/stop/close/reopen、宿主前后台驱动、断网/恢复、finalized 订阅重建、交易 watch
中断后的持久恢复、取消、迟到回调和关闭排空；最后完成第一部分全量回归、证据登记和发布候选冻结。SDK 仍只保存
自身提交交易的通用 execution 事实；索引和淘汰只允许使用 executionId、通用状态、时间、数量和字节，不得出现
目的账户、金额、备注、方向、pallet、action、投票、治理、旅行、订单或任何 App 业务字段。不改 CitizenApp、
CitizenWallet、`native/smoldot/pow/**`，不增加迁移、兼容、双读、双写、alias、wrapper、fallback 或其它 QR 协议。

“后台同步”边界：它是 SDK 组合内已经存在的轻节点同步、finalized 订阅、通用 execution reconciliation 和链数据库
快照调度，不是操作系统保证常驻的后台任务，也不是某个 App 的业务同步器。App 仍负责按自己的前后台策略调用公开
start/stop/close；SDK 不接收广场、投票、治理、旅行、订单等业务生命周期，不新增 App 专用前后台 API。Stopped、
StartFailed 和 Disposed 继续是单向生命周期；所谓 reopen 是宿主关闭旧实例、创建新实例并从 SDK 自有持久状态恢复，
不是把已停止实例偷偷重新启动。

发布冻结边界：本步骤冻结的是 CitizenSDK 第一部分的源码、公共合同、平台投影、测试证据和 Release hash，不提交、
不推送、不发布包、不触发未经明确安排的远程 runner，也不拿源码扫描冒充未运行的真机/异系统结果。Flutter 继续
绝对不安装、不下载、不升级、不配置、不启动、不停止，也不调用任何 Flutter 命令；已有 Flutter 安装或缓存同样不动。

必要合同变化与确认边界：要真正消除 Core 的整包 load/CAS，必须把当前 Host public-store 中两个 whole-history
callback 替换为通用索引读取和原子 mutation callback；只在 SQLite 层拆行而仍让 Core收发整包 BLOB 不能关闭
P1-04。因此本步骤会修改公开 header 中 `citizensdk_host_public_store_v1_t` 的宿主侧 C 集成布局和 history callback
类型；它属于平台宿主 ABI，不是应用业务 API。App-facing API、Flutter 方法、result kind 或产品函数均不增加，
117/62/3/17 函数闭集保持。CitizenSDK 1.0 尚未发布，旧
whole-BLOB callback 与旧 history codec 直接删除，不保留兼容入口。SQLite 也只接受新的精确 schema：不读取、不
转换、不迁移旧 whole-BLOB 行；已有开发数据库必须由调用方清除后重新创建，SDK 不自动扫描或搬运。该 Host struct/
schema 变化只有在用户确认本步骤后实施；若要求保持它们逐字节不变，则 P1-04 只能保留，不能伪称已优化。

生命周期合同不新增 App-facing 方法或第二套状态机：继续使用现有 start、stop、close、lifecycle、sync status、
capability/event 和通用 history 接口。只允许修正 Engine/FFI/平台内部的 generation fence、取消、排空、订阅重建、
持久 open execution 恢复和回调顺序；117 个 Core 产品函数、62 个 Flutter 方法、3 个 Apple QR image 函数、
Linux/Windows 各 17 个 Host 函数保持不变。若测试证明确实必须新增或删除公共函数/方法、改变 App-facing DTO、
改变唯一 `QR_V1`，或修改上游/PoW 才能正确实现，则不在本步骤擅自扩大，按合并执行合同暂停说明。

目录与职责：

- `native/contracts/src/store/transaction_history.rs`、`native/contracts/src/lib.rs`：以
  `TransactionHistoryIndex`、`TransactionHistoryCursor`、`TransactionHistoryMutation` 替换 whole-state store 合同。
  typed store 只提供：读取 revision/总数/总 weight/open 数量与 weight、按 executionId 读取、按稳定游标分页、读取
  最旧 retention-terminal 候选、按 expected revision 原子提交 upsert/delete 集合。每条记录仍保存完整恢复材料；
  公开 `TransactionHistoryPage/Record` 字段不变。
- `native/engine/src/transaction_history.rs`、`native/engine/src/{transaction_prepare.rs,engine.rs}`：启动与恢复只读取
  Pending/InBlock 等 open 记录；单次状态更新只加载目标记录，历史页面最多加载公开 limit 条，容量不足时只分页取
  最旧终态候选。Core 对宿主索引元数据与解码后 record 逐项交叉验证；同一 CAS revision 原子提交目标 upsert、终态
  删除和新汇总，继续保证 pending-before-broadcast、open 不驱逐、exact finalized proof 和单账户在途约束。
- `native/engine/src/{engine.rs,chain_monitor.rs,finalized_history_runtime.rs,transaction_execution.rs,state_import.rs}`：把性能
  改造后的逐记录历史接入唯一 lifecycle generation 和 monitor cancellation。start 成功后只恢复 open execution；
  stop/close 先关闭新 admission，再取消 provider 等待、停止 monitor、排空已进入的 store CAS/订阅，最后停止 provider
  和销毁 Engine。断线、Retracted、Dropped、FinalityTimeout、流结束或取消不得伪造失败/成功终态，也不得删除
  Pending/InBlock；新实例 reopen 后从持久记录与最新 verified finalized head 继续通用 reconciliation，绝不重新签名。
- `native/smoldot/provider/src/{client.rs,legacy.rs,verified_chain_client.rs}`：只调用已有 smoldot start/stop、同步状态、
  finalized subscription、transaction submit/watch、chain database export/import 和网络内部重连能力；SDK 适配层仅修正
  订阅资源结束后的有界重订阅、错误投影和排空，不实现 P2P、共识、交易池、数据库或第二套网络重连器。任何必须改动
  `native/smoldot/pow/**` 的发现都属于二次确认门禁，不在本步骤执行。
- `native/ffi/src/{abi.rs,host_providers.rs,host_codec.rs,host_codec_tests.rs}`、
  `include/citizensdk_types.h`：删除 whole-history load/CAS callback，加入固定宽度的通用 history index/query/mutation
  callback、严格数组/short-buffer/owner/operation completion 合同及逐记录 codec。Host 不解码 callData、extrinsic、
  签名或业务字节；Core 验证回传的 executionId、状态、时间和 weight 与 record 一致。公开函数总数不变。
- `native/ffi/src/{runtime.rs,chain_monitor.rs,composition.rs,requests.rs,events.rs,lib.rs}`：维持单一 SDK-owned monitor；固定
  start 成功后服务启动、失败收敛、显式 stop、destroy 和 reopen 的线性顺序。finalized stream 结束后按 1/2/4/8/16/30
  秒封顶重订阅，成功通知后重置退避；普通通知、historyChanged 和 lifecycle/capability 事件仍走已有有界队列。
  关闭期间不接纳新请求，不从回调线程执行阻塞控制，不丢弃已进入宿主事务的 future，所有线程和订阅必须可监督 join。
- `android/native/src/main/kotlin/org/citizen/sdk/internal/CitizenSdkPublicStore.kt`、
  `darwin/Sources/CitizenSDK/CitizenSDKPublicStore.swift`、`linux/src/citizen_sdk_public_store.cc`、
  `windows/src/citizen_sdk_public_store.cc`：把 history 从 `singleton_records` 单 BLOB 改为一行 meta 加按 executionId
  分行的 opaque record 表；索引只含 `created_at_millis`、`updated_at_millis`、`retention_terminal`、`durable_weight`
  等通用字段。expected revision 检查、删除、upsert、汇总更新在一个 SQLite `IMMEDIATE` 事务中完成，任何一步失败
  全部回滚。四个平台 SQL、排序、索引和 PRAGMA 完全一致。
- 四个平台 SQLite open/schema 文件：新建空库时在建表前固定 `auto_vacuum=INCREMENTAL` 并验证实际值。终态淘汰提交
  后，仅由现有串行 store owner 在 freelist 同时超过 16 页和数据库页数 25% 时执行最多 128 页的
  `incremental_vacuum`，随后执行受监督 WAL checkpoint；不运行无界 full `VACUUM`，不增加后台线程/定时器，不在
  wallet、签名或 provider 锁内回收。checkpoint/vacuum 失败返回 persistence stage，已提交数据仍以重开验证决定，
  不能删除或伪造 execution。
- `lib/src/platform/{citizen_sdk_flutter_sessions.dart,citizen_sdk_flutter_codec.dart}`、Android
  `CitizenSdk.kt`/`CitizenSdkFlutterSessions.kt`/`internal/CitizenSdkRequestRouter.kt`、Apple
  `CitizenSDK.swift`/`CitizenSdkFlutterSessions.swift`、Linux/Windows `citizen_sdk_lifecycle.*`、
  `citizen_sdk_flutter_sessions.*`、`citizen_sdk_host_bridge.*`：只投影同一 Core lifecycle、request sequence、事件和
  failure stage；平台前后台只能决定何时调用同一 start/stop/close，不得自行维护链高度、重连计时器、交易 watch 或
  历史真源。close 的可恢复 Busy 必须保留实例可用，进入 teardown-only 后只允许重试 close，不得回到运行状态。
- `native/engine/tests/baseline_resource_contract.rs` 与新增 `native/engine/tests/transaction_history_scaling_contract.rs`：
  记录 0/1/100/1,000 条下的 load/page/update 编解码字节、store 调用、wall time 和峰值分配；预热后至少 20 轮，
  报告中位/P95/max/CV。门禁要求单条状态更新编码字节受单记录上限约束、page 成本受 limit 约束，不随总 N 整包增长；
  测试计时不进入生产 API。
- `native/engine/tests/lifecycle_recovery_contract.rs`、
  `native/smoldot/provider/tests/{baseline_lifecycle_contract.rs,lifecycle_recovery_contract.rs}`、
  `native/ffi/src/{chain_monitor_tests.rs,composition_tests.rs}`：用确定性的 scripted Provider/Store/clock 覆盖 Created→
  Starting→Running→Stopped/Disposed、StartFailed、断线重订阅、退避复位、静默链、通知突发、stop/close 竞态、取消、
  迟到 completion、host CAS 尚未返回、旧 generation 结果和 reopen 恢复。scripted Provider 只模拟合同失败向量，不
  复制 smoldot 实现；真实 smoldot 仍由 provider 层既有合同测试验证。
- Android/Apple/Linux/Windows store tests：覆盖 0/1/100/1,000 行数据库增长和重开、1,000→1 retention 后 freelist/
  物理文件收敛、多页游标、重复时间的 executionId tie-break、并发 CAS、删除/upsert/meta 任一步失败回滚、磁盘满、
  损坏 record、checkpoint/vacuum 失败与关闭竞态。未在本机运行的平台继续标为待 runner，不用源码扫描冒充。
- Android/Apple/Linux/Windows lifecycle/session tests：共享同一状态转换和事件 golden，覆盖快速前台→后台→前台驱动
  下的 stop/close/new-open、重复调用、start 失败、请求完成与 stop 交错、event queue 满、回调内 close、宿主 operation
  orphan、实例替换和 reopen 后旧 session/request 事件隔离。平台测试不得新增自动常驻后台服务，也不得把 UI
  lifecycle 写入 Core 持久状态。
- `test/consumers/**`、`test/api/**`、`test/platform/**`：三类 consumer 与 external signer 继续只组合六类通用能力；
  增加 lifecycle/history fake 合同，证明 CitizenApp-shaped、途遇/第三方-shaped 业务在 stop/reopen 后只通过公开
  execution/history 事实恢复，SDK 不认识其业务字段。Flutter 工具链相关测试仅登记已有证据或待运行状态，本步骤不
  调用 Flutter。
- `docs/audits/SDK_BASELINE_1_10_1.md` 增补优化后的同机对照；新增
  `docs/audits/SDK_PART1_RELEASE_FREEZE_1_10_4.md` 作为第一部分唯一冻结报告，逐项记录 P1-04/P1-05/P2-01/P2-02
  的关闭证据、命令、机器环境、实测/模拟/源码事实分类、未运行平台和残余风险；禁止把未跑结果写成通过。
- `docs/{ARCHITECTURE,SECURITY,C_ABI,DART_API,MOBILE_PLATFORM,LINUX_PLATFORM,WINDOWS_PLATFORM,
  NATIVE_PACKAGING,SOURCE_PROVENANCE,WALLET_MODEL}.md`、根/平台/native README、本任务卡和 `CHANGELOG.md`：同步说明
  store 结构、原子性、物理回收、生命周期、断线恢复、watch 持久语义、关闭顺序和“不迁移/不兼容”边界。文档不得
  把宿主 SQLite 写成 Core 内嵌数据库，不得把后台同步写成 OS 常驻保证，也不得把 InBlock/Finalized 通知写成执行成功。
- `scripts/release.mjs`、`scripts/release.test.mjs`：固定新 Host struct 布局、SQL/schema/index/PRAGMA、117/62/3/17、
  operation-level 基线来源、lifecycle/event golden、三类 consumer、external signer 和四端一致性；反向拒绝
  whole-history callback/codec、旧表双读、业务列、平台私有同步器/watch、生命周期分叉、其它 QR 协议、生产
  benchmark hook、完整 `VACUUM`、PoW 漂移和源码树数据库/构建产物。Release manifest/hash 只在所有本机可执行门禁
  通过后更新，随后再次从干净的仓库外构建目录复验，避免用旧产物计算 hash。

实施顺序与失败向量：

1. 先把 1.10.1 的 0/1/100/1,000 whole-BLOB 基线固化为失败测试，并新增“更新第 500 条时不得编码其余 999 条”、
   “limit=100 不得加载 1,000 条”和“retention 后文件应逐次收敛”的目标门禁；先不改生产实现。
2. 替换 Contracts/Engine store 形状和逐记录 codec；在内存 fake 上证明 revision CAS、stable cursor、open 恢复、
   terminal 淘汰、总 weight 和 pending-before-broadcast 不变量，再改 FFI callback。不得通过缓存整包 state 绕过测试。
3. 四个平台建立完全相同的新 schema 和事务实现；旧 whole-BLOB callback、codec、SQL、测试 fixture 和文档直接删除。
   不加 schema 探测转换、旧行导入、双读或 fallback；旧开发库碰到 schema 不符必须明确失败关闭。
4. 加入有阈值、有单次页数上限的物理回收；先注入 checkpoint/vacuum/磁盘满/崩溃点，证明 mutation 原子性和重开
   结果，再测 1,000→1 多次正常写入后的文件收敛。回收不得延迟 Core completion 到无界时间。
5. 在同一 release 构建与预热规则下复测 operation-level 编码/复制/存储指标；只据同机前后对照报告改善，不设跨机器
   绝对耗时承诺。这里不中止步骤、不输出下一子步骤，继续进入生命周期实现与验证。
6. 先冻结 lifecycle/monitor golden：用 scripted Provider/Store/clock 写出断线、重连、通知突发、静默、start failure、
   stop、close、取消、迟到结果和 reopen 的失败测试；逐项标出哪些是 SDK adapter 行为、哪些由上游 smoldot 提供，
   禁止为了通过测试把上游实现复制进 SDK。
7. 在 Engine 与 FFI 修正测试暴露的通用生命周期问题：所有异步操作绑定 session/request/generation；start 只有在
   provider 身份和 verified finalized head 验证后进入 Running；monitor 只消费现有 finalized 订阅并有界重订阅；
   watch 中断保留 durable open record；stop/close 严格执行 admission→cancel→join/drain→provider stop→Engine dispose。
8. 让 Android、Apple、Linux、Windows 与 Dart session 共享同一转换和事件顺序；删除重复同步器、平台私有重连状态、
   dead callback 和失效 whole-BLOB 残留。模拟前后台只调用公开 start/stop/close/new-open，不增加后台 service、daemon、
   work manager、定时任务或 App 业务 hook。
9. 完成全量回归：先跑受影响 crate/host/store/lifecycle/consumer 定向测试，再跑 Rust workspace、Release、C11/C++17、
   仓库外 ABI build 和本机现有可用原生 runner。真实网络只允许无密钥、无交易广播的 bounded sync/read smoke；
   submit/watch/reconnect 用确定性 provider 合同或明确配置的隔离测试链验证，绝不拿用户钱包或 CitizenChain 真实资产
   做测试。任何环境缺失如实登记，不安装 Flutter、不临时下载工具、不触发未安排的远程 runner。
10. 在所有本机可执行门禁通过后，更新全部注释、README、架构/安全/平台文档、基线对照、冻结报告、manifest 和
    Release SHA-256；再从新的仓库外构建目录复验 hash/符号/headers。清理 dead code、旧 callback/codec/SQL/fixture、
    仓库外临时数据库与构建物（精确移动到废纸篓，不碰任何用户数据或工具链缓存），确认源码树无生成物后将 1.10
    和第一部分标记完成，并直接在任务卡写入和输出第二部分 2.1 的完整技术方案。

关键失败测试：单条 upsert/delete 的 Core 编码与宿主写入不包含其它记录；页面和恢复查询都有硬上限；游标在相同
时间戳、删除和并发状态变化下不重复/不遗漏；旧 revision 的 mutation 零写入；删除、upsert 或 meta 更新任一步失败
全部回滚；Pending/InBlock 永不因 retention 或 vacuum 丢失；restart 仍能使用原 signed extrinsic 恢复且不重新签名；
损坏索引与 record 不一致返回 integrity/verification，不回显内容；磁盘满与 checkpoint/vacuum 失败返回
storage/persistence；1,000→1 后逻辑行立即正确，物理文件在固定的有界回收次数内下降。

生命周期关键失败测试：重复 start/stop/close、Stopped/StartFailed 实例重启、start 完成越过 generation、provider 身份
或 finalized 锚错误、断线时 stream error/结束、指数退避达到 30 秒上限、重订阅成功复位、静默链不忙轮询、通知突发
不突破队列、请求/事件乱序、event queue 满、取消恰逢 provider completion、stop 恰逢 history mutation、host operation
orphan、回调线程内 close、close Busy 后实例继续可用、teardown-only 重试、旧实例事件进入新 session、reopen 丢失
Pending/InBlock、重复签名、重复并发 watch、错误地把 Ready/Broadcast/InBlock/Finalized 通知当作执行成功，全部必须由
失败测试拦截。只有 exact canonical body、同 index System outcome 和 finalized proof 才能写执行终态。

通用性与发布关键失败测试：reference、CitizenApp-shaped、third-party-shaped、external signer 四类消费者在同一公共
合同上通过；任一生产目录出现 Square/Vote/Legislation/Proposal/Governance、booking/order、destination/amount/
remark/direction/pallet/action 等业务 schema，任一兼容/迁移/旧库读取路径，任一 `QR_V1` 之外协议，任一平台私有
链同步器/交易观察器，任一 CitizenWallet 依赖或 `native/smoldot/pow/**` hash 漂移，任一公开闭集 117/62/3/17 变化，
以及源码树遗留数据库、build/target/.build 或打包临时物，均使冻结失败。

回滚边界：本步骤是一个合并变更集，只允许在源码候选层整体回滚新 typed store、Host callback 布局、四端 schema、
逐记录 codec、回收策略、lifecycle/monitor 修正、测试、文档和 Release hash；不能只回滚 schema 而保留新 callback，
也不能只回滚 lifecycle fence 而保留依赖它的 monitor。由于明确不实现迁移/兼容，回滚不读取、转换或承诺恢复任一旧
开发数据库；本步骤也不删除任何用户数据库。执行中的测试数据库和构建目录必须是新建的仓库外明确路径，清理时只
移动该次创建且已核对的精确目录到废纸篓。

若实施中发现必须修改 App-facing 交易/历史 DTO、增加业务字段、改变 117/62/3/17 闭集、改动
`native/smoldot/pow/**`、复制上游网络/数据库/交易能力、修改 CitizenApp/CitizenWallet、保留旧 whole-BLOB 路径、
增加迁移/兼容、执行无界文件重建、安装或操纵 Flutter，立即停止并按合并执行合同报告，不以“第一部分要完成”为由
越权。普通编译错误、测试失败或本方案内的实现调整不算新增步骤，继续修复到门禁通过。

验收命令与环境边界：所有 Rust 测试只通过 `scripts/test.sh cargo ...`，先定向运行 contracts/engine/ffi/provider，最终
运行 `scripts/test.sh cargo --workspace --all-targets --locked`；Release 使用 `scripts/test.sh release`；C ABI 使用明确
仓库外 `CITIZENSDK_WORK_DIR`/`CITIZENSDK_NATIVE_OUTPUT_DIR` 执行 `scripts/build-native.sh abi-host`，并对公开 header 做
C11/C++17 consumer 编译。只运行当前机器已经具备依赖且不会下载工具的 Apple/Android/Linux/Windows runner；缺失
Java、NDK、Apple framework、Linux/Windows 主机或真机时，在冻结报告逐项标为“未运行/发布前门禁”，禁止自动安装、
禁止触发远程任务、禁止以 Release 源码扫描冒充 native runner。任何 `flutter` 命令都不运行，也不改 Flutter 安装、
缓存、进程或配置。

量化验收：0/1/100/1,000 条均记录数据库逻辑 bytes、主文件/WAL/SHM bytes、freelist/page count 和 reopen
median/P95/max/CV；1,000 条中更新任一记录不得编码/读取其余 999 条，history page 成本只受 limit（公开最大 100）
约束，open recovery 只受 open record 数约束；1,000→1 后逻辑行立即正确且物理文件在文档固定的有限次 128-page
incremental vacuum/checkpoint 内下降。数值只与同机 1.10.1 基线比较，不承诺跨机器毫秒 SLA，不为测量增加生产 hook。

生命周期验收：同一 golden 在 Core/FFI/Dart/Kotlin/Swift/Linux/Windows 投影一致；start/stop/close/new-open 全状态、
断网与恢复、subscription 重建、watch 保留与恢复、取消、背压、乱序、迟到回调、host transaction 排空和事件顺序
全部通过确定性测试。可用网络环境仅做无密钥 sync/read smoke；没有隔离测试链和测试资金时绝不广播真实交易，
submit/watch/reconnect 由真实 provider API 的本地合同与 scripted failure vector 共同覆盖，报告明确证据类型。

冻结验收：Host struct 精确布局和新 schema/index/PRAGMA 四端一致，117 个 Core 产品函数、4 个内部测试函数、3 个
Apple QR image 函数、Linux/Windows 各 17 个 Host 函数和 62 个 Flutter 方法保持闭集；三类 consumer、external
signer、C11/C++17、错误 22 类/8 阶段/7 字段、唯一 `QR_V1` 全部纳入 Release 反向门禁。最终复核无 whole-BLOB、
旧 schema、迁移/兼容/业务模型、第二套同步/watch、生产 benchmark、完整 `VACUUM`、源码树数据库/生成物；
CitizenApp、CitizenWallet、其它产品和 `native/smoldot/pow/**` 内容 hash 不变，`git diff --check` 通过。

完成定义：上述实现、所有本机可执行门禁、文档/注释/hash、残留清理和冻结报告一次完成后，1.10.4、1.10 和第一部分
同时标记完成，不再存在 1.10.5/1.10.6。因本机缺少环境而未运行的原生 runner 只作为实际发布前外部门禁留在冻结
报告，不再拆出 SDK 实现步骤，也绝不宣称通过；随后直接输出第二部分 2.1 完整技术方案。本方案已获用户确认并按上述合同执行完成。

完成记录（2026-09-11）：

- Contracts/Engine 已删除 whole-history state 合同，改为 `TransactionHistoryIndex/Cursor/Mutation`、按 executionId
  读取和最多 100 条有界分页。状态更新只读取目标 record；1,000 条中的单条 mutation 实测 store 调用为
  index=1、record=1、page=0、write=1。`TXR1` 每条记录仍包含完整通用恢复材料，`THQ1/THB1/THM1`
  描述与 opaque record 由 Core 交叉验证。
- Host public-store 的旧 history load/CAS callback 直接替换为 query/mutate；C struct 仍为 72 bytes，字段偏移保持
  56/64，产品函数闭集不变。旧 callback、codec、schema 读取入口为零，不存在 alias、wrapper、fallback、迁移、
  兼容、双读或双写。
- Android、Apple、Linux、Windows 统一 public schema v2：`transaction_history_meta`、逐 execution record 和
  newest/retention/reconcile 三个索引；只含 executionId、时间、通用终态标志、资源 weight 与 opaque Core record。
  expected revision、终态 deletes、upserts、meta 在同一事务提交，open execution 禁止删除。新库建表前固定
  incremental auto-vacuum；只在 freelist >16 且超过总页数 25% 时单次回收最多 128 页并监督 checkpoint，绝不
  执行 full `VACUUM`。旧 v1/漂移 schema 明确拒绝且不删除数据库。
- Apple 同 SQL 实际仓库外测量：0/1/100/1,000 行主库为 45,056/45,056/208,896/1,630,208 bytes；20 次重开
  median 为 0.875/0.582/0.521/0.524 ms；1,000 条终态经十个有界 mutation 收敛为 1 条后主库回到 45,056
  bytes、11 pages、freelist=0。完整 median/P95/max/CV、逻辑 bytes 与 WAL/SHM 见
  `docs/audits/SDK_BASELINE_1_10_1.md` 第 11 节。
- finalized stream error 与结束现在都会废弃失效订阅，adapter 按 1/2/4/8/16/30 秒封顶重订阅，成功通知复位；
  网络/P2P/共识/交易池/watch/链数据库继续直接复用既有 smoldot provider，没有复制上游实现或修改 PoW。
- `scripts/test.sh cargo --workspace --all-targets --locked` 全量通过；FFI 当前 117 项单元测试全部通过。
  `scripts/test.sh release` 107/107 通过。仓库外 `scripts/build-native.sh abi-host` Release 构建与产品 ABI、C11/C++17
  consumer 验收通过。Apple public store 通过本机 Swift 6.4 类型检查和实际 SQLite 测量；Android JNI 使用已安装
  NDK 28.2 C++17 `-Wall -Wextra -Werror` 语法检查通过，Kotlin store 子集使用已安装 Android Studio JBR/Kotlin 与
  Android 36 jar 编译通过；Linux public-store C++17 严格语法检查通过。
- Android Gradle/AAR、移动真机、Linux runner、Windows runner 和真实网络交易没有环境证据，已在
  `docs/audits/SDK_PART1_RELEASE_FREEZE_1_10_4.md` 标为发布前外部门禁，未用源码扫描冒充通过。Flutter 全程没有
  调用、安装、下载、升级、配置、启动、停止或清理缓存。
- 本步骤没有修改 CitizenApp、CitizenWallet、其它产品或 `native/smoldot/pow/**`；定制 PoW 内容 hash 继续为
  `ced9bcd7af45c48ce0ddd4dd077fff035ff72c00fa84aa42067bb10e072d5999`。SDK 生产 schema 不含目的账户、金额、
  备注、方向、业务 pallet/action、广场、投票、治理、旅行或订单字段。

第一部分状态：1.1—1.10 全部完成；CitizenSDK 通用底层能力源码候选冻结。原第二部分 2.1—2.6 已撤销并删除
CitizenApp 对应新增目录；重新确认“直接复用 CitizenSDK/定制 smoldot”的技术方案前不修改 CitizenApp。

## 四、第二部分：CitizenApp 业务层与旧底座剥离

纠偏记录（2026-09-11）：原第二部分错误地在 CitizenApp 内重复设计了 CitizenSDK 已经具备的钱包、签名、交易、
history、轻节点读取和状态协调能力，违反“上游已有功能直接复用”的既定原则。用户要求整体删除后，已经彻底删除
`/Users/rhett/GMB/citizenapp/lib/chain`（42 个文件）与 `/Users/rhett/GMB/citizenapp/test/chain`（13 个文件），两个目录
本身也已移除；没有读取、迁移或修改 CitizenApp 旧实现。以下 2.1—2.6 原方案仅保留为撤销记录，不得继续执行，
不得据此重建任何平行 models、ports、controller、gate、reader、history 或 presentation 层。第二部分必须重新出方案，
以 CitizenSDK 和定制 smoldot 的现有公开能力为唯一底座，CitizenApp 只保留自身业务并做最薄直接接入；新方案确认前
不在 CitizenApp 创建任何新目录或文件。

第二部分只修改 CitizenApp，以第一部分已经通过多消费者验收的通用 SDK 合同为前提。所有本次新实现只能写入
`lib/chain/**`；CitizenApp 原钱包、smoldot、签名、交易、监控和历史底座在全部 CitizenSDK 集成与新路径端到端验证
完成前保持原文件、原目录和原字节，不搬动、不改名、不删除。源码暂时共存不等于兼容：禁止 legacy adapter、wrapper、
alias、fallback、双读、双写、数据迁移或运行时新旧选择；新路径不得调用或读取旧实现/旧数据库。最终生产入口只切换
一次到 `lib/chain`，验证通过后在 3.6 一次性彻底删除旧源码、依赖、资产和平台配置。发现 SDK 缺能力时，必须回到
第一部分按通用能力单独出方案，禁止直接为 CitizenApp 增加专用 SDK 方法。

### 2.1 建立 App 区块链端口与目录边界

状态：已撤销；对应 CitizenApp 实现与测试已整体删除（2026-09-11）。

目标：只新增 `/Users/rhett/GMB/citizenapp/lib/chain/**` 与 `/Users/rhett/GMB/citizenapp/test/chain/**`，建立
CitizenApp 最终的 CitizenChain 客户端边界。此步不接入 CitizenSDK 依赖，不修改任何旧实现或旧调用点，不读取、迁移、
转换或兼容用户数据，也不建立旧底座转发层。`lib/chain` 定义最终 models、ports、客户端 `ChainServices` 组合以及
后续新 application/SDK 实现的唯一归属；没有 production default、nullable fallback、旧实现 factory 或临时实现目录。
现有 `WalletManager`、`SmoldotClientManager`、`ChainRpc`、`NativeSr25519`、`SignedExtrinsicBuilder`、
`ChainTxMonitor`、`SecureSeedStore` 连同当前直接引用和历史目录在本步做路径/hash 只读冻结，直到新路径全部验证通过
才允许在 3.6 删除。端口形状必须能由第一部分已冻结的通用 CitizenSDK 逐项实现，不能出现广场、投票、立法、提案、
治理、旅行、订单等 SDK 专用要求。

#### 2.1 目录设计与职责注释

- `lib/chain/models/account.dart`：App 底座中立的账户 ID、SS58、名称、hot/cold、默认项、目录 revision；
  不含助记词、seed、private key、Vault 引用、CitizenSDK 类型或旧 Isar 钱包实体。
- `lib/chain/models/signing.dart`：opaque payload、`raw/substrateSigningPayload/blake2Domain` transform、唯一
  external `qrV1` transport、完成/待外签/取消结果；`opaqueAction` 仍只是 App 提供的不透明 u16，不登记业务 action。
- `lib/chain/models/chain.dart`：best/finalized block ref、sync status、runtime context、header/body、storage
  bytes、账户余额/nonce/fee 等 App 中立值；不加入任意 JSON-RPC method 或业务 storage key。
- `lib/chain/models/transaction.dart`：opaque callData preparation、冷热 execution、pool/finalized 结果和
  SDK 自身 execution history page/record 的 App 中立投影；不含 destination、amount、remark、direction、业务
  pallet/event。它是新的最终定义；当前 `lib/transaction/ports/transaction_executor.dart` 暂时原样保留且不被新路径
  import，待全部集成验证通过后在 3.6 随旧实现一次性删除，不做 re-export 或数据转换。
- `lib/chain/ports/wallet_port.dart`：公开账户目录、创建/用户重新输入助记词导入、追加账户、冷公钥导入、
  重排、默认账户授权、改名、删除和原生安全私钥查看端口；不包含 CID、设备数据钥或 `k=6` 用途钥。
- `lib/chain/ports/signing_port.dart`：通用 sign/begin/consume/cancel/verify 端口，只接收上面的中立 signing
  model；业务服务在端口外构造 payload 和审阅文案。
- `lib/chain/ports/chain_port.dart`：固定链身份、同步状态、best/finalized、安全块解析、header/body/runtime、
  storage 单项/批量、System.Events、余额/nonce/fee 端口；业务 key 与 SCALE 解码继续留在现有业务目录。
- `lib/chain/ports/transaction_port.dart`：prepare/cancel/execute/consume-cold-response/cancel-execution，只接收
  sourceAccountId 与 opaque callData；不允许 caller nonce、完整 SigningPayload 或 signed extrinsic 出端口。
- `lib/chain/ports/history_port.dart`：SDK 自身 execution page/sync/event invalidation 端口，与
  `lib/transaction/history/**` 的 CitizenApp 业务流水明确分离。
- `lib/chain/ports/lifecycle_port.dart`：open/start/stop/close、capability/lifecycle/event 快照的 App 中立端口；
  不增加 OS 常驻后台、App 业务同步或第二套重连状态机。
- `lib/chain/composition/chain_services.dart`：客户端内部一次性持有上述六类端口的不可变依赖集合；根启动代码
  在第三部分获得完整 CitizenSDK 实现后显式创建并注入；构造参数全部 required，没有默认实例、空实现、旧实现
  factory、service locator 或 fallback。本步的 production 不构造不完整 `ChainServices`，测试只用完整 fake 验证合同。
- `lib/chain/application/**`：第二部分新增的 CitizenApp 链应用协调全部放在这里，只组合 ports 与 App 自己生成的
  opaque payload/callData/storage key；不得 import 旧钱包、smoldot、签名器、builder、monitor 或旧数据库。广场、投票、
  治理等业务规则仍留在原业务目录，不复制进这里。
- `lib/chain/sdk/**`：第三部分新增的 CitizenSDK-backed 最终实现全部放在这里；只能调用 `package:citizen_sdk` 公开 API，
  不允许读取旧 App 钱包/交易表、调用旧底座、增加 fallback 或实现 App 业务。
- `lib/security/**`、`lib/citizen/**`、`lib/8964/**`、`lib/votingengine/**`、`lib/my/**`、`lib/chat/**`：继续拥有
  CID、设备子钥、账户数据钥、`k=6` 用途钥、广场、投票、立法、提案、治理和聊天等业务实现。它们可依赖
  `lib/chain/ports/**`，反向依赖禁止。
- `lib/transaction/history/{data,chain,application,presentation}/**`：作为旧实现暂时完整保留，不在 2.1—3.5 搬动、
  改名或删除。CitizenApp 必须继续拥有的目的账户、金额、备注、收发方向、业务 event 解码、Isar 数据与交易 Tab
  在最终删除旧底座时只删除被新实现等价替换的底层部分，业务模型仍归 App；绝不移入 SDK。
- `lib/transaction/onchain-transaction/citizenchain_transfer_call_encoder.dart` 及现有各业务 codec：继续由 App 编码
  RuntimeCall；最终 `Uint8List` 才进入 `transaction_port`。
- `lib/chain/README.md`：记录依赖方向、允许/禁止字段、新旧源码隔离、单次生产切换、无迁移/无兼容和 3.6
  一次性删除路线；明确禁止创建 `legacy/`、旧实现 `adapter/` 或任何临时转发目录。`test/chain/**` 保存永久端口、
  新 application/SDK 实现、导入闭集和 fake consumer 测试。

#### 2.1 分步实施顺序

1. 只读冻结旧实现：用 `rg` 和逐文件 SHA-256 登记钱包事实、App 业务安全钥、链读取、RuntimeCall 编码、交易构造/
   提交、watch/历史和生命周期的源码、依赖、资产、平台配置及生产引用。输出“永久保留业务能力”“验证后 3.6 删除的
   旧底座”“唯一生产切换点”三张清单；2.1—3.5 对冻结旧文件的任何内容/路径变化均失败。
2. 先写失败合同：`test/chain/port_model_contract_test.dart` 证明端口模型防御复制、enum/上限和冷热同形；
   `test/chain/business_boundary_test.dart` 证明 Square/Vote/Governance/第三方形状的 payload/callData 只作为
   opaque bytes 穿过 fake；`test/chain/import_boundary_test.dart` 禁止 `lib/chain` import 旧底座或任何业务模型反向
   进入，新 SDK 实现目录建立前也禁止 `package:citizen_sdk`。
3. 建立 `models` 与六类 `ports`。只使用 Dart 标准值（String、int/BigInt、Uint8List、List、Stream）；所有 bytes
   构造时复制、集合不可变，错误只保留 code/stage/message，不携带助记词、秘密、payload、callData、签名、
   extrinsic、metadata/storage 内容或路径。端口注释逐项标明 SDK 能力映射和 App 业务禁区。
4. 在 `lib/chain` 独立写出最终模型与端口，不移动、改写、import 或 re-export 现有
   `lib/transaction/ports/{transaction_executor.dart,finalized_chain_reader.dart}`；只把旧文件当只读行为清单，避免
   复制旧类型身份或形成兼容入口。新旧类型不能互转，最终只由新实现使用新类型。
5. 建立 `ChainServices` 最终客户端组合类型：六个端口全部为 required final 字段，只允许完整构造；本步不修改
   production `main.dart`，不注入 fake、旧底座或空实现，也不建立全局 singleton。第三部分六类真实 CitizenSDK 实现
   全部完成后，生产根只执行一次切换；构造失败直接失败关闭，不回退旧实现。
6. 本步不修改任何既有业务消费者。只在 `test/chain/**` 用完整 fake 验证 models/ports/`ChainServices`，并建立旧实现
   hash 守卫和新目录反向依赖守卫。2.2—3.5 的所有新增协调与 SDK 实现也只能写入 `lib/chain/**`；需要与既有业务
   交互时新增从业务输入到 opaque bytes 的调用点，不搬动旧底座。
7. 完善所有新增 public/internal 注释和 `lib/chain/README.md`。反向扫描确认旧冻结文件零修改、不存在
   `lib/chain/legacy`、旧实现 adapter、旧 import/re-export、默认 fallback、双读、双写或兼容入口；不修改
   CitizenWallet、CitizenSDK 或 PoW。

#### 2.1 测试与验收门禁

- 钱包端口覆盖 absent、hot/cold 混合目录、revision 冲突、默认账户授权 pending/completed、用户取消和秘密零返回；
  端口没有助记词 getter，也没有旧钱包导入/转换方法。
- 签名端口覆盖 raw/Substrate/domain transform、hot 完成、cold `qrV1` pending/consume、expiry/cancel、错账户/错
  payload hash；增加新业务只改变 opaque fixture，不改变端口。
- 链端口覆盖 lifecycle 未运行、best/finalized 区分、exact block、runtime/storage batch、System.Events、余额/nonce/
  fee、错误阶段；fake 不实现任意 RPC。
- 交易/历史端口覆盖 prepare/cancel、热执行、冷执行待扫码/回扫、Pending/InBlock/PoolRejected/Finalized、分页
  1/100/101、sync 和 historyChanged；业务历史 DTO 不出 `lib/transaction/history`。
- 本步对 `WalletManager`、`SmoldotClientManager`、`ChainRpc`、`NativeSr25519`、`SignedExtrinsicBuilder`、
  `ChainTxMonitor`、`SecureSeedStore` 及其 production 引用建立路径/hash 基线；2.1—3.5 必须保持零修改，不能用
  转发类、移动或改名规避。`lib/chain/**` 永远不得 import 或调用这些旧实现。
- 2.1 的 `lib/chain/**` 与 tests 不 import `package:citizen_sdk`；`pubspec.yaml` 本步不增加 CitizenSDK 依赖。第三部分
  只有 `lib/chain/sdk/**` 可以 import CitizenSDK 公开面，其它 chain 目录仍禁止。CitizenApp 业务词不得进入端口
  类名、方法名、enum 或通用持久字段。
- 全仓不存在 `lib/chain/legacy/**`、`lib/chain/adapter/**`、名称含 Legacy/Compat 的链实现、旧端口 re-export、
  deprecated wrapper、nullable/default port、运行时 fallback 或同时选择新旧实现的分支。
- 本步骤不读取、转换、迁移或删除用户钱包/交易数据，不改 CitizenWallet/CitizenSDK/PoW，不提交、不推送。
  Flutter 继续不调用、不安装、不下载、不升级、不配置、不启动、不停止，也不处理其缓存；当前机器能执行的非
  Flutter 静态/源码合同才记为通过，依赖 Flutter 的 analyze/test 如实列为未运行，不伪造结果。

执行完成定义：上述最终 models/ports/`ChainServices`、测试、注释、文档和新目录残留清理全部完成；旧底座路径/hash
逐项保持不变，临时适配/兼容/数据互转扫描为零，并输出 2.2“在 `lib/chain` 新建钱包侧实现、旧 WalletManager 保持
冻结”的完整方案后，2.1 才可标记完成。本方案已获确认并按上述边界执行完成。

完成记录（2026-09-11）：

- 只新增 `lib/chain/**` 12 个文件：四类最终 models、六类 ports、六端口全部 required 的客户端 `ChainServices` 和
  目录职责文档；没有修改 production `main.dart`、旧调用点或 `pubspec`，没有接入 CitizenSDK。
- `test/chain/**` 新增 7 个文件。冻结清单覆盖原钱包、RPC/smoldot、签名/QR、旧交易端口/历史、原生 signer 及相关
  Android/iOS/依赖配置共 422 个现有文件；路径/字节 SHA-256 门禁 3/3 通过。
- `lib/chain` 反向门禁确认只有 `models/ports/composition` 三个代码目录，不 import WalletManager、smoldot、ChainRpc、
  NativeSr25519、SignedExtrinsicBuilder、ChainTxMonitor、旧 transaction/history 或 `package:citizen_sdk`；不存在
  legacy、旧实现 adapter、wrapper、alias、fallback、迁移、兼容、双读或双写。
- 使用现有独立 Dart 工具（不是 Flutter）完成格式化、`dart analyze lib/chain test/chain/standalone_contract_test.dart`
  和 assertion-enabled standalone 运行合同，全部通过；Node 冻结/边界测试 3/3、现有 Release manifest 4/4 通过。
  Release manifest 首次直接运行因缺少必需的 `TATA_CONSOLE_FLOW_ROOT` 明确失败，补入既有中央 flow 绝对路径后通过，
  没有修改脚本或绕过门禁。由于源码根当前没有
  `.dart_tool/package_config.json`，三个 `flutter_test` 深层合同只完成格式/语法解析并保留为后续 runner 门禁；没有
  为此运行、安装、下载、配置、启动或停止 Flutter，也没有生成 package config。
- `git diff --check` 通过；旧冻结范围对 Git 的内容 diff 为零。CitizenSDK、CitizenWallet、PoW 和其它产品零修改。

### 2.2 新建钱包与 App 业务密钥分离实现（旧 WalletManager 冻结）

状态：已撤销；对应 CitizenApp 实现与测试已整体删除（2026-09-11）。

目标：只在 `lib/chain/application/wallet/**` 新建最终钱包应用层，只依赖 2.1 的 `WalletPort/SigningPort` 和公开模型；
同时只在 `lib/chain/application/account_security/**` 新建 CitizenApp 自有的 CID 绑定、P-256 设备子钥、账户数据钥、
用途钥和 `k=6` 交付职责。两者从类型、存储、生命周期和测试上彻底分开：链钱包秘密永远只属于未来 CitizenSDK，
App 业务密钥永远只属于 CitizenApp。原 `lib/wallet/**`、相关页面/调用、原生通道、旧数据库和冻结 hash 全部不动，
本步不切换 production；不读取、迁移、转换、兼容或双写旧钱包/旧业务密钥。

目录与职责：

- `lib/chain/application/wallet/wallet_controller.dart`：最终钱包应用协调；加载 `ChainWalletState`，调用创建、用户重新
  输入助记词导入、追加账户、冷公钥导入、排序、默认账户授权、改名、删除和安全查看。只持有 `WalletPort`，不持有
  mnemonic、seed、private key、Vault、WalletManager 或平台 channel。
- `lib/chain/application/wallet/wallet_view_state.dart`：页面所需的 loading/ready/authorizing/cancelled/failed 公共状态；
  只含公开账户与 `ChainFailure`，不缓存秘密、payload、QR 原文或旧实体。
- `lib/chain/application/wallet/wallet_operation_gate.dart`：同一 controller 的 mutation single-flight、迟到结果 generation
  fence 和 dispose；不实现 SDK 生命周期、线程、数据库或网络重试。
- `lib/chain/application/wallet/default_account_flow.dart`：热账户完成或冷账户 `QR_V1` pending/consume/cancel 的统一默认
  账户授权协调；App 只展示公开请求，密码学绑定仍由 `WalletPort`。
- `lib/chain/application/account_security/account_binding.dart`：CitizenApp 业务身份绑定值：genesisHash、cidNumber、
  bindingRevision、accountId；严格规范化并作为所有业务密钥 AAD，属于 App，不进入 SDK wallet model。
- `lib/chain/application/account_security/business_key_purpose.dart`：App 自有 purpose/context 闭集（chat、chatIndex、mls、
  attachment、contactsLocal、contactsCloud encryption/index）；它不是 CitizenSDK action/enum。
- `lib/chain/application/account_security/business_key_vault.dart`：App 业务密钥 sealed-blob 抽象，只暴露 create/seal/open/
  contains/delete；物理 key 使用新命名空间 `citizenapp.chain.business-key.v1`，不得探测或读取旧 WalletManager blob。
- `lib/chain/application/account_security/device_subkey.dart`：App 自有 per-CID P-256 hardware key 抽象及 public/sign/delete/
  contains；不使用 sr25519，不进入 WalletPort/CitizenSDK。
- `lib/chain/application/account_security/account_security_service.dart`：按 binding+purpose+context 生成/打开 32-byte App
  数据钥、绑定 AAD、并发 single-flight、回调作用域交付和 finally 清零；不得请求 SDK 私钥或从签名猜测数据钥。
- `lib/chain/application/account_security/binding_authorization.dart`：用 `SigningPort` 对 App 构造的绑定消息做授权，只证明
  account 对 binding 的授权；签名不得作为确定性加密 key 使用。
- `lib/chain/application/account_security/account_data_key_provision.dart`：CitizenApp 自有 `k=6` 用途钥请求/响应与明确
  用户交付流程；只处理 App purpose/context 和密钥信封，不进入 CitizenSDK，不修改 CitizenWallet。冷账户可使用该
  App 协议交付用途钥；热账户的新业务钥由 App 随机生成并封装，二者最终都形成相同 App-owned sealed bundle。
- `lib/chain/application/account_security/account_security_cleanup.dart`：按精确 binding tombstone 先封闭新使用，再删除
  sealed blobs/P-256 key/公开 binding；删除失败保留可重放的新实现 cleanup fact，但绝不读取旧 cleanup 表。
- `test/chain/wallet/**`、`test/chain/account_security/**`：完整 fake、并发、取消、秘密生命周期和业务边界测试；旧测试
  继续原样保留，不改写为新路径测试。

关键安全设计：

- 不能用 sr25519 signature 派生业务数据钥：签名不是稳定 KDF，且会把钱包密码学与 App 加密语义重新耦合。
- 热账户的每个新 binding/purpose/context 使用平台安全随机生成 32-byte App 数据钥，立即由 App business-key vault
  封装；只在 `withDataKeys` 同步/异步作用域内短暂解封，回调结束全量清零。
- 冷账户用途钥继续由 CitizenApp 自己的 `k=6` 业务协议取得；CitizenSDK 只提供通用 QR/signing 能力，不认识 k=6、
  CID 或用途。CitizenWallet 源码和功能零修改。
- 新密钥物理命名空间、AAD 和 binding revision 与旧 WalletManager 完全隔离；旧密文不扫描、不导入、不尝试解封。
  用户使用新路径时建立全新的业务密钥事实，这不是迁移或兼容。
- 账户删除只删除新命名空间中精确归属的 App 业务材料；SDK 钱包删除由 WalletPort 负责。任一侧失败不得猜测另一侧
  已完成，也不得删除旧冻结数据。

实施顺序：

1. 先用冻结清单只读列出 WalletManager 当前“链钱包职责”和“App 业务密钥职责”，建立逐方法对照，但不改旧文件。
2. 先写失败测试：钱包 controller 不得 import `lib/wallet/**`；account-security 不得进入 `ports/models/sdk`；签名结果
   不能充当数据钥；新 vault 命名空间不得读取旧 key/blob；秘密必须 finally 清零。
3. 实现 wallet view state、operation gate、controller 和默认账户流程；全部使用完整 fake WalletPort/SigningPort，
   覆盖热/冷同形、revision 冲突、取消、迟到完成和 dispose。
4. 实现 AccountBinding、purpose/context、AAD 和 sealed-bundle 模型；所有 bytes 防御复制，秘密模型禁止 toString/JSON。
5. 实现 business-key vault/device-subkey 的最终 App 抽象与新物理命名；只允许 `lib/chain/application/account_security`
   使用，不反向塞进 WalletPort。
6. 实现热账户随机业务钥生成、冷账户 k=6 交付、作用域打开、single-flight、binding authorization 和 cleanup；测试
   故障注入覆盖生成、封装、写入、回读、删除各阶段，任何失败无部分可用状态。
7. 加入三类业务 fake（chat/contacts/attachment），证明新增 purpose 只改变 App 层，不改变 WalletPort、CitizenSDK
   或 ChainServices 六端口。
8. 完善注释和 `lib/chain/README.md`，运行独立 Dart/Node 门禁；复核 422 个旧文件 hash 不变、production 未切换、
   无旧数据读取/迁移/兼容/双写，然后输出 2.3 完整方案。

验收门禁：

- 本步所有新增文件只能位于 `lib/chain/application/{wallet,account_security}/**` 和 `test/chain/**`。
- 新代码对 WalletManager、NativeSr25519、SecureSeedStore、旧 DeviceDataKeyVault/DeviceSubkey、旧 QR/数据库的 import
  和字符串物理 key 引用均为零；冻结旧文件路径/hash 422/422 一致。
- 钱包 controller 只接触公开账户事实；创建/导入流程不接收或返回 mnemonic，私钥查看不返回 secret。
- App business key 与 SDK wallet secret 完全分离；hot/cold 最终都只交付 App-owned 32-byte scoped key，离开回调清零。
- k=6/CID/purpose/context 只存在于 account-security App 目录和测试，不进入六类通用 ports、`lib/chain/sdk` 或 CitizenSDK。
- 并发初始化最多一次；AAD 跨 genesis/CID/revision/account/purpose/context 任一字段都不能解封；删除只命中精确 binding。
- 无 migration、compat、legacy、adapter、wrapper、fallback、双读、双写；不修改 production main、旧页面、旧数据、
  CitizenSDK、CitizenWallet 或 PoW。
- Flutter 继续不调用、不安装、不下载、不升级、不配置、不启动、不停止或清理缓存；当前独立 Dart/Node 能运行的门禁
  必须通过，依赖 Flutter package config 的测试如实登记未运行。

完成定义：新钱包应用层与 App account-security 层实现、注释、测试和清理全部完成，旧 WalletManager 及冻结范围
零修改、production 零切换、边界门禁全部通过，并直接写入/输出 2.3“在 `lib/chain/application/read` 新建链读取协调，
旧 smoldot/ChainRpc 保持冻结”的完整技术方案。本方案已获确认并按上述边界执行完成。

完成记录（2026-09-11）：

- 只在 `lib/chain/application/{wallet,account_security}` 新增 12 个生产文件：钱包公开状态/controller、single-flight/
  generation gate、热冷默认账户授权，以及 App-owned binding、purpose/context、业务 vault/store 抽象、P-256 device
  subkey、binding authorization、k=6 X25519 会话合同、热/冷用途钥协调和永久 cleanup tombstone。
- `WalletController` 只依赖 WalletPort/SigningPort；完整 mutation 与写后公开状态刷新处于同一 gate，dispose 后迟到结果
  返回 cancellation 且不发布。没有 mnemonic/seed/private key/Vault/platform channel/旧实体字段。
- `AccountSecurityService` 要求 registry 中精确当前 binding；热账户用 CSPRNG 生成缺失 32-byte key，冷账户验签并解封
  k=6 bundle，二者以相同 sealed snapshot 做 revision CAS。并发相同请求共享一个 future，CAS 冲突重读重试，写后抛错
  只在精确候选已可见时收敛；所有明文 key 在成功、回调抛错和重试路径 finally 清零。
- 新 namespace 固定 `citizenapp.chain.business-key.v1`；AAD 绑定 genesis/CID/revision/account/purpose/context。
  cleanup 先写永久 tombstone，再删精确 binding vault key；只有 registry 当前仍为同一 binding 才删除 per-CID P-256
  key 和公开 binding，旧 revision 不能误删新绑定。旧物理 key/blob 字符串在新源码中为零。
- 新增 3 个独立运行合同，使 `test/chain` 总计 10 个文件。独立 Dart analyze 覆盖完整 `lib/chain` 和四个 standalone
  runner，0 issues；四个 assertion-enabled runner 全部通过，覆盖 wallet busy/late cancellation、热钥 CAS 冲突与
  single-flight、回调异常清零、跨 binding 拒绝、冷 k=6 错签拒绝/成功消费、secret 清零和永久 tombstone。
- Node 冻结/依赖/业务边界门禁 4/4、现有 Release manifest 4/4、格式与 `git diff --check` 全部通过。冻结旧实现
  422/422 路径/hash 一致；production main/pubspec/旧页面/旧数据库、CitizenSDK、CitizenWallet、PoW 零修改。
- Flutter 没有调用、安装、下载、升级、配置、启动、停止或清理缓存；依赖 flutter_test/package config 的旧深层 runner
  继续如实未运行，不影响本步骤独立 Dart/Node 已执行证据。

### 2.3 新建安全链读取协调（旧 smoldot/ChainRpc 冻结）

状态：已撤销；对应 CitizenApp 实现与测试已整体删除（2026-09-11）。

目标：只在 `lib/chain/application/read/**` 新建 CitizenApp 最终链读取应用层，只依赖 2.1 的 `ChainPort/LifecyclePort`
和通用 chain models。它向广场、身份、订阅、投票、立法、提案、多签、资产等业务提供“准确块 + 调用方自有 key/
decoder”的组合能力，但不登记任何业务 storage key、pallet、RuntimeCall 或 DTO。原 `lib/rpc/**`、`smoldot/**`、
ChainRpc/SmoldotClientManager、旧订阅/缓存、业务调用和链资产生命周期继续按 422 文件清单冻结；本步不切换 production，
不调用旧实现，不复制 smoldot，不建立 RPC、cache、subscription 或 reconnect 替身。

目录与职责：

- `lib/chain/application/read/verified_block_bundle.dart`：一个准确 block 上的 ref/header/body/runtime/System.Events 不可分
  bundle；构造时要求所有返回对象 block hash/number/finality 完全一致，bytes 防御复制。
- `lib/chain/application/read/finalized_block_reader.dart`：按高度或精确 hash+height 调用 ChainPort，随后读取 header/body/
  runtime/events 并二次核对同一 finalized 身份；任一错块、best 冒充、字段缺失或中途漂移整体失败，不返回部分 bundle。
- `lib/chain/application/read/finalized_range_reader.dart`：只接受正向连续 1..120 高度；逐块使用同一 finalized reader，
  保持顺序，遇到任一失败整批失败，不猜缺块、不回退 best、不并行突破 provider 背压。
- `lib/chain/application/read/storage_read_request.dart`：调用方生成的 opaque key 及可选标签，仅用于结果关联；key 为
  1..4096 bytes、防御复制，不包含 pallet/storage 名或 JSON-RPC method。
- `lib/chain/application/read/business_storage_reader.dart`：在调用方指定的已验证 block 上执行单项/批量 storage；保持
  输入顺序和重复 key，严格核对返回长度。业务 decoder 由调用方以函数传入并在 App 业务目录实现；本层只交付 bytes，
  不捕获 decoder 为全局注册表，也不返回部分成功。
- `lib/chain/application/read/account_chain_reader.dart`：组合 finalized balance 单项/批量、best nonce 和 fee snapshot；
  核对 accountId、输入顺序、同一 batch finalized block，以及 nonce/fee 的 best block 身份，不自行计算余额或费用。
- `lib/chain/application/read/chain_state_coordinator.dart`：显式 export/import SDK 轻节点 state 的新路径协调；import 只在
  lifecycle created 时允许，回执/后续 finalized 不能回滚或换链。它不是旧 App 数据迁移入口，也不自动导入旧数据库。
- `lib/chain/application/read/chain_read_state.dart`：idle/checking/ready/failed/disposed 页面级公开状态，只含 sync、
  capability、block ref 和 ChainFailure；不缓存 metadata/storage/body 或业务结果。
- `lib/chain/application/read/chain_read_controller.dart`：读取 readiness、sync 和刷新公开状态；使用 generation fence 拒绝
  dispose 后迟到结果。它不启动 timer、P2P、订阅、后台 service 或第二套 lifecycle，真正网络与同步只由未来 SDK。
- `test/chain/read/**`：确定性 fake ChainPort/LifecyclePort、错块/错序/错长度/生命周期失败、范围和 decoder 隔离测试。

关键读取合同：

- `ChainBlockRef` 只是值；finalized reader 必须先通过 ChainPort 的 `getFinalizedBlockAt` 或
  `resolveFinalizedBlock` 得到 provider 验证结果，不能信任业务调用方自报 finality。
- header/body/runtime 中的 block 必须与 resolved ref 完全相同；System.Events 只能用该 finalized ref 读取。
- storage key 与 SCALE decoder 永远由 CitizenApp 业务生成。read 层不得出现 Square/Vote/Legislation/Proposal/
  Governance 等 key 常量、pallet index、call index 或业务模型。
- batch 保留输入顺序和重复项；空 batch 仍调用 ChainPort，使 lifecycle/capability 错误不能被本层绕过。
- range 固定 1..120，不能通过并发分片或递归规避。单次 bundle 内允许复用已经取得的 block/runtime，只是请求局部值，
  不建立跨请求 cache；旧 ChainReadCache 保持冻结且不被调用。
- readiness 只读取 LifecyclePort/ChainPort 的事实；不自行把 peerCount、best 高度或超时猜成 ready。
- provider/network/decode/integrity 错误保持 ChainFailure code/stage，不回显 metadata/storage/body 内容。

实施顺序：

1. 从 422 文件冻结清单只读登记旧 ChainRpc/SmoldotClientManager/ChainEventSubscription/ChainReadCache 的所有调用面和
   业务消费者，不修改任何旧文件；分类为新 ChainPort 已覆盖能力、App 业务 key/decoder、最终 3.6 删除项。
2. 先写失败测试：调用方伪造 finalized、resolved/header/body/runtime 错块、events 错 finality、batch 错长度、范围
   0/121/倒序、空 batch 绕过 lifecycle、迟到完成和 decoder 抛错都必须失败且无部分结果。
3. 实现 VerifiedBlockBundle 与 finalized reader；所有组合结果构造前逐字段核验，bytes/集合防御复制。
4. 实现 storage request/reader；单项和批量共享一个路径，decoder 只作为当前调用栈参数，结束后不保存。
5. 实现 120-block finalized range；严格串行、有界、全有或全无，不复制旧 monitor 的订阅/重试逻辑。
6. 实现 account reader；覆盖单/批余额顺序、重复账户、准确 finalized，nonce/fee 准确 best 及跨块拒绝。
7. 实现 chain-state coordinator 和 read controller；覆盖 created/running/stopped/startFailed/disposed、import 前置、
   generation fence 和 close，不增加生产入口或后台任务。
8. 用 Square-shaped、Vote-shaped、Governance-shaped 和第三方 shaped opaque key/decoder fake 验证同一 read 层；新增业务
   只增加业务测试输入，不修改 read 生产代码。
9. 完善注释和 `lib/chain/README.md`，运行独立 Dart/Node 门禁；复核旧实现 422/422 hash、production main/pubspec、
   CitizenSDK/CitizenWallet/PoW 零修改，无迁移/兼容/双路由，然后输出 2.4 完整方案。

验收门禁：

- 本步新增生产文件只能位于 `lib/chain/application/read/**`，测试只能新增于 `test/chain/read/**`。
- 新 read 代码对 `lib/rpc/**`、`smoldot/**`、ChainRpc、SmoldotClientManager、ChainReadCache、旧 subscription/monitor 的
  import/调用为零；冻结旧文件路径/hash 422/422 一致。
- 生产源码没有任意 RPC method/params、业务 storage key 常量、业务 pallet/call、App DTO 或第二套 SCALE registry。
- 精确 finalized bundle、storage batch、range、account/fee/nonce、state import/export 和生命周期失败向量全部通过。
- 不建立 cache、timer、background service、daemon、P2P、reconnect、subscription 或 transaction watch。
- 不读取或迁移旧 smoldot database；不修改 production 入口、pubspec、旧数据、CitizenSDK、CitizenWallet 或 PoW。
- 无 legacy、旧实现 adapter、wrapper、alias、fallback、双读、双写或运行时新旧选择。
- Flutter 继续不调用、不安装、不下载、不升级、不配置、不启动、不停止或清理缓存；独立 Dart/Node 门禁必须通过，
  依赖 Flutter package config 的测试如实登记未运行。

完成定义：安全链读取 application 层、注释、测试和清理全部完成，旧 smoldot/ChainRpc 与 422 文件冻结范围零修改、
production 零切换、边界门禁全部通过，并直接写入/输出 2.4“在 `lib/chain/application/{signing,transaction}` 新建
通用签名与 opaque RuntimeCall 协调，旧 NativeSr25519/SignedExtrinsicBuilder 冻结”的完整技术方案。本方案已获
确认并按上述边界执行完成。

完成记录（2026-09-11）：

- 只在 `lib/chain/application/read` 新增 9 个生产文件：同块 finalized bundle、按高度/精确 hash 读取、1..120 严格
  串行范围、opaque storage request/单批 reader、账户/nonce/fee reader、created-only state coordinator 和公开
  read controller/state。没有修改 production 或任何旧链文件。
- finalized reader 先取得 ChainPort 已验证 ref，再逐项读取并核对 header/body/runtime 同一 hash/number/finality，
  最后读取该 finalized ref 的 System.Events；错 resolved hash、非 finalized、任一错块整体失败且不返回部分 bundle。
- storage reader 对 1..4096-byte opaque key 防御复制，batch 保持顺序/重复项且空 batch 仍进入 ChainPort；返回长度
  不一致或业务 decoder 抛错时整批失败。range 固定 1..120 严格串行，不能用倒序、121 条或分片绕过。
- account reader 核对单/批账户、顺序和同一 finalized block，nonce/fee 必须为 best；state import 只允许 created，
  不读旧数据库；read controller 只查询 lifecycle/capability/sync，以 single-flight/generation fence 拒绝 busy 和迟到结果。
- 新增 `test/chain/read/read_standalone_test.dart`，使 test/chain 共 11 个文件。独立 Dart analyze 0 issues，执行合同覆盖
  正确/错误 resolved ref、runtime 错块、1/120/121/倒序、storage 防御复制/顺序/重复/空 batch/错长度、decoder 失败、
  余额错序、created-only import、not-running/capability-closed 和 dispose 迟到 cancellation，全部通过。
- Node 冻结/依赖/2.2/2.3 边界门禁 5/5、格式和 `git diff --check` 通过；旧实现 422/422 路径/hash、production、
  pubspec、CitizenSDK/CitizenWallet/PoW 零修改。没有 cache/timer/subscription/P2P/reconnect/watch 或任意 RPC 实现。
- Flutter 没有调用、安装、下载、升级、配置、启动、停止或清理缓存；没有生成 `.dart_tool` 或 package config。

### 2.4 新建通用签名与 opaque RuntimeCall 协调（旧签名/交易底座冻结）

状态：已撤销；对应 CitizenApp 实现与测试已整体删除（2026-09-11）。

目标：只在 `lib/chain/application/signing/**` 与 `lib/chain/application/transaction/**` 新建 CitizenApp 最终调用协调，
分别只依赖 `SigningPort` 和 `TransactionPort`。业务模块继续自己构造 action、opaque payload/callData、storage key、
correlation 和审阅文案；新层只复制/约束字节、维护一次性会话状态并调用端口，不知道业务含义。原 NativeSr25519、
WalletManager.sign、SignedExtrinsicBuilder、TransferRpc、直接 nonce/runtime/submit/watch、旧冷热签名页面和调用保持
422 文件路径/hash 冻结；本步不切换 production，不调用旧实现，不生成或接收完整 SigningPayload/signed extrinsic。

目录与职责：

- `lib/chain/application/signing/signing_command.dart`：App 生成的 accountId、opaque payload、通用 transform、可选
  `qrV1` transport、opaque u16 action 和 ttl；payload 最大 16 MiB、防御复制。可带 App-local correlationId，但调用
  SigningPort 时明确剥离，绝不进入 SDK。
- `lib/chain/application/signing/signing_view_state.dart`：idle/signing/awaitingExternal/completed/cancelled/failed/disposed；
  completed 只含 accountId/payloadHash/signature，pending 只含 sessionId/expiry/公开 transport request。
- `lib/chain/application/signing/signing_operation_gate.dart`：每个 controller 单一 active session、generation fence、
  begin/consume/cancel 线性化和 dispose 排空；不实现密码学、QR codec 或 platform UI。
- `lib/chain/application/signing/signing_controller.dart`：把 command 转成 `ChainSigningIntent`，处理热签完成或冷签 pending，
  只允许当前 session consume/cancel；无状态 verify 直接调用 SigningPort，不改变 controller state。
- `lib/chain/application/transaction/transaction_command.dart`：sourceAccountId 32 bytes、opaque callData 1..1 MiB 和仅 App
  本地 correlationId；不含 destination/amount/remark/pallet 名，不允许 caller nonce/era/tip/runtime/签名/extrinsic。
- `lib/chain/application/transaction/transaction_view_state.dart`：idle/preparing/prepared/executing/awaitingExternal/
  completed/cancelled/failed/disposed；只保存安全公开 preparation/execution 投影和 App-local correlation。
- `lib/chain/application/transaction/transaction_operation_gate.dart`：同一 controller 的 preparation/execution owner、
  source single-flight、claim、取消、迟到完成与 dispose；App 状态不能复用已消费 preparationId/executionId。
- `lib/chain/application/transaction/transaction_controller.dart`：prepare 后只保存安全 summary；execute 只接受当前
  preparationId；热账户直接得到 terminal，冷账户进入 QR_V1 pending；consume/cancel 只命中当前 execution。
- `lib/chain/application/transaction/transaction_result.dart`：把通用 execution 结果与 App-local correlation 组合供业务
  层关联；correlation 不传入端口、不写 SDK history、不改变 transactionHash。
- `test/chain/{signing,transaction}/**`：互不相关 payload/callData、热冷状态机、错 session、重复消费、取消、迟到结果、
  buffer mutation、错误阶段和边界反向扫描。

关键合同：

- SigningController 不解析 payload，不登记 action 白名单；raw/substrateSigningPayload/blake2Domain 原样映射，domain
  仍是 opaque 1..32 bytes。QR 唯一 transport 为既有 `qrV1`，不得设计其它协议版本。
- payload/signature/callData/accountId 在进入 controller 时复制；调用结束后 controller 不持有原 payload/callData。
  pending 只保存公开 request/session/expiry；不保存待签字节、secret 或私有 native handle。
- TransactionController 不读取 ChainPort 的 nonce/runtime，也不拼 SigningPayload/extrinsic；全部由 TransactionPort/
  未来 CitizenSDK 完成。App 无 raw submit、pre-signed submit 或 watch 入口。
- preparationId 一次性：prepare 成功后只能 execute 或 cancel；execute acceptance 后立即从 prepared owner 移出，失败是否
  可重试完全依据端口错误阶段和返回事实，不能自行重建交易。
- cold executionId 只允许当前 pending response consume 或 cancel；错 ID/response、重复/迟到完成不改变新 session。
- Ready/Broadcast/InBlock/Finalized 通知不由本层猜成成功；controller 只接受 TransactionPort 返回的 poolRejected 或
  verified finalizedSuccess/finalizedFailed terminal。
- App-local correlation 只用于把业务记录和通用 executionId/txHash 关联，不进入 ports、SDK、签名 payload 或持久通用历史。

实施顺序：

1. 只读登记旧 WalletManager.sign、NativeSr25519、SignedExtrinsicBuilder、TransferRpc、各业务签名服务和交易页面调用，
   不修改冻结文件；区分 App payload/callData encoder、旧底层构造/签名/提交/watch 和 3.6 删除项。
2. 先写失败测试：payload/callData 越界、caller nonce/runtime/extrinsic 字段、错 session、重复 consume、并发 begin/prepare、
   cancel/consume 竞态、dispose 迟到结果、port 返回畸形 terminal 都必须失败关闭。
3. 实现 signing command/view state/gate/controller；覆盖三种 transform、热完成、冷 pending/consume/cancel 和 verify。
4. 实现 transaction command/result/view state/gate/controller；覆盖 prepare/cancel、热 execute、冷 pending、response consume、
   execution cancel 和 App correlation 隔离。
5. 加入四类无关业务 fixture：转账、广场、投票/治理、第三方；全部使用同一签名/交易代码，生产层不增加分支。
6. 注入 scripted ports 覆盖 admission/validation/authentication/persistence/provider/verification/cancellation/teardown 八阶段；
   controller 只投影通用失败，不回显 payload/callData/signature/extrinsic。
7. 增加反向门禁：新代码不得 import wallet/rpc/signer/qr/旧 transaction，禁止 SigningPayload、SignedExtrinsicBuilder、
   submit/watch/RPC 和 `QR_V1` 外协议；旧实现 422/422 hash 必须不变。
8. 更新 `lib/chain/README.md`、格式、独立 Dart/Node 测试和任务卡；复核 production/pubspec/旧数据、CitizenSDK/
   CitizenWallet/PoW 零修改，无迁移/兼容/双路由，然后输出 2.5 完整方案。

验收门禁：

- 新生产文件只位于 `lib/chain/application/{signing,transaction}/**`，测试只新增 `test/chain/{signing,transaction}/**`。
- 新代码对 WalletManager、NativeSr25519、SignedExtrinsicBuilder、ChainRpc、TransferRpc、旧 QR/transaction/watch 的引用为零；
  旧实现路径/hash 422/422 一致。
- 0/16MiB/16MiB+1 payload，0/1MiB/1MiB+1 callData，domain 0/1/32/33、action/ttl 边界全部覆盖。
- 热签/冷签、热交易/冷交易状态机，错 session/ID、重复消费、取消、迟到结果、并发和 dispose 全部确定性通过。
- controller/API 中不存在 mnemonic、seed、private key、nonce 注入、SigningPayload、signed extrinsic、raw submit/watch。
- App correlation 不进入端口或 SDK；增加新业务 fixture 不修改 production。
- 唯一 QR 协议仍为 `QR_V1`；无迁移、兼容、legacy、旧实现 adapter、wrapper、fallback、双读或双写。
- production 不切换，不修改 pubspec、旧实现/数据、CitizenSDK、CitizenWallet 或 PoW。
- Flutter 继续不调用、不安装、不下载、不升级、不配置、不启动、不停止或清理缓存；独立 Dart/Node 门禁必须通过。

完成定义：通用 signing/transaction application 层、注释、测试和清理全部完成，旧签名/交易底座和 422 文件冻结范围
零修改、production 零切换、边界门禁全部通过，并直接写入/输出 2.5“在 `lib/chain/application/history` 与
`lib/chain/presentation/history` 新建通用 execution/history 协调，旧 LocalTx/ChainTxMonitor 冻结”的完整技术方案。
本方案已获确认并按上述边界完整执行。

完成记录（2026-09-11）：

- 只在 `lib/chain/application/signing` 新增 command/view-state/operation-gate/controller 4 个生产文件，只在
  `lib/chain/application/transaction` 新增 command/result/view-state/operation-gate/controller 5 个生产文件；没有修改
  production 入口、pubspec 或任何旧签名/交易文件。
- signing 在入口防御复制 0..16 MiB opaque payload，完整透传 raw/substrateSigningPayload/blake2Domain 三种通用
  transform，只持有唯一 `QR_V1` 的公开 pending 会话；热签、冷签 consume/cancel、错 session、重复消费、并发拒绝、
  无状态 verify 和 dispose 排空均由同一 controller/gate 线性化。
- transaction 在入口防御复制 32-byte source 和 1..1 MiB opaque callData，只调用 TransactionPort 的 prepare/cancel/
  execute/consume/cancel 方法。preparation 在 execute/cancel acceptance 后永久 claim，冷 execution 失败时保留、成功消费
  或取消后清除；所有返回结果再次核对 source/callData hash/execution owner，未增加 ChainPort、nonce/runtime、raw
  submit/watch 或完整签名交易入口。
- App-local correlation 只保存在 command/view/result 中，端口合同仍无 correlation 字段；转账、广场、投票/治理和第三方
  四种 fixture 走完全相同的生产代码，未加入业务 action 分支、业务模型或持久化。
- 新增 `test/chain/signing/signing_standalone_test.dart` 与
  `test/chain/transaction/transaction_standalone_test.dart`。独立 Dart analyze 0 issues；执行合同覆盖 0/16MiB/16MiB+1、
  0/1MiB/1MiB+1、domain 0/1/32/33、u16/ttl、冷热状态机、一次性 ID、consume/cancel 竞态、八个 failure stage、
  畸形 owner、错误脱敏和 dispose 迟到结果，全部通过。
- Node 依赖/目录/2.2/2.3/2.4 反向门禁与旧实现冻结门禁 6/6 通过；冻结旧实现仍为 422/422 路径/hash 一致。
  `lib/chain` 不引用旧 wallet/rpc/signer/qr/transaction/history，也无其它 QR 协议、迁移、兼容、adapter、wrapper、
  fallback、双读、双写或运行时新旧选择。
- Flutter 没有调用、安装、下载、升级、配置、启动、停止或清理缓存，没有生成 `.dart_tool/package_config.json`；
  CitizenSDK 仅同步本任务卡及 release 文档来源 hash，SDK 生产代码、CitizenWallet 和定制 PoW 均未修改。

### 2.5 剥离交易观察和历史底座

状态：原方案已取消，禁止执行。

目标：只在 `lib/chain/application/history/**` 和 `lib/chain/presentation/history/**` 新建 CitizenApp 对 SDK 自身
execution history 的读取、分页、显式同步、变更失效和通用展示投影。新层只依赖 `HistoryPort` 及已经冻结的通用
history models，不读取 ChainPort、不扫描 finalized block、不确认任意入账或业务事件。目的账户、金额、备注、收发方向、
业务 pallet/event、订单/广场/投票/治理含义和 App 自有记录继续由 CitizenApp 业务目录负责，通过 executionId/txHash
与通用执行事实关联；这些业务字段不进入 HistoryPort、CitizenSDK 或本步骤的通用 history 投影。

目录与职责：

- `lib/chain/application/history/history_query.dart`：首次/刷新查询的 1..100 limit 与可选 opaque execution cursor；
  游标只用于读取，不获得修改、删除或同步权限。
- `lib/chain/application/history/history_snapshot.dart`：不可变的当前 revision、已加载 records 和 next cursor；验证
  newest-first `(createdAtMillis, executionId)` 确定序、executionId/transactionHash 全局唯一、cursor 必须等于页末记录，
  跨页 revision 必须完全一致且 append 不能产生重复或乱序。
- `lib/chain/application/history/history_view_state.dart`：idle/loading/ready/syncing/failed/disposed；ready 只携带通用
  snapshot，failed 可保留最后一个已验证 snapshot，不包含旧 LocalTx、业务详情或数据库实体。
- `lib/chain/application/history/history_operation_gate.dart`：用户 load/refresh/loadMore/sync single-flight、generation
  fence、payloadless change dirty-bit 合并、迟到结果拒绝和 dispose 排空；不用 timer、轮询、后台 daemon 或第二套 monitor。
- `lib/chain/application/history/history_controller.dart`：只调用 HistoryPort 的 `getTransactionHistory`、
  `syncTransactionHistory` 和 `changes`。首次/刷新替换快照，loadMore 只消费当前 cursor，显式 sync 只采用端口返回的第一页；
  change 事件只使本地页失效并合并触发一次只读首屏刷新，绝不把 change 猜成交易成功，也不隐式启动链 sync。
- `lib/chain/presentation/history/execution_history_item.dart`：供新页面消费的通用只读 item，仅含 execution/source/call/tx
  hash、状态、时间、可选 verified block/execution/replacement/pool reason；所有集合和 bytes 保持不可变。
- `lib/chain/presentation/history/execution_history_projector.dart`：从已验证 record/snapshot 做纯投影；不生成目的账户、金额、
  备注、方向、业务 action、业务文案或链上事件解释，不访问端口或数据库。
- `lib/chain/presentation/history/execution_history_presenter.dart`：把 controller 的通用状态投影为页面 load/refresh/
  pagination 状态并保持 revision fence；业务页面在此边界外按 executionId/txHash 组合自己的 App 记录。
- `test/chain/history/**`：独立 scripted HistoryPort、五种状态记录、分页/变更/同步/释放竞态、通用 presentation 投影和
  反向边界测试；不依赖 Flutter package config 或旧数据库。

关键合同：

- history 只包含当前 CitizenSDK 实例实际提交的 opaque RuntimeCall execution；不能接受 account list、业务 filter、
  block range、storage key、pallet/call 或全链扫描参数，不能据此构造“账户全部收支”。
- `getTransactionHistory` 是纯本地只读分页；首次/刷新 cursor 必须为 null，loadMore 只能使用当前已验证
  nextBeforeExecutionId。limit 固定 1..100，调用方不能用并发分页绕过 single-flight。
- 同一 snapshot 的后续页 revision 必须等于首屏 revision；revision 不同、倒退、游标不属于前页、页内/跨页重复 ID/hash、
  乱序或超过 limit 时整页拒绝，既有 snapshot 不发生部分合并。change 到达后丢弃迟到旧代次结果并重新读取首屏。
- `syncTransactionHistory` 只能由显式 sync 调用；controller 不传账户、游标或业务参数，不循环调用、不自行重试、不启动
  provider 扫描。端口的 payloadless changes 只是失效信号，接收后重新读 revisioned page；同 revision 不虚构新状态。
- Pending/InBlock 不等于成功；只有端口返回的 poolRejected/finalizedSuccess/finalizedFailed 通用事实可投影相应终态。
  presentation 不解析 dispatch index 为业务错误，不从 block/extrinsic 推导转入转出或业务动作。
- 新层不持久化 SDK history，不建立 App 通用历史数据库，不读取/转换旧 LocalTx/Isar 数据，不向旧库双写。
  CitizenApp 自己的业务流水仍由业务层持有，第三部分只把此通用 controller 绑定 SDK History API。
- subscription 显式 start/stop 且每个 controller 最多一条；burst change 只设置 dirty bit 并合并为一个 trailing refresh。
  dispose 先停止接收、使 generation 失效、取消订阅、排空当前 Future，之后禁止状态回写或自动重启。

实施顺序：

1. 从 422 文件冻结清单只读登记旧 LocalTxEntity/LocalTxStore/ChainTxMonitor/TxAutoRefreshMixin、交易 tab、账户详情和旧
   Isar collection 的生产调用面；区分必须留在 App 的业务记录/展示、旧底层 monitor/store 和 3.6 一次性删除项，
   不修改任何旧文件。
2. 先写失败测试：limit 0/101、未知/错页 cursor、101 条页、重复 executionId/transactionHash、cursor 非页末、
   newest-first 乱序、revision 倒退/跨页变化、并发 load/sync、change 与 loadMore 竞态、dispose 迟到结果全部失败且无部分合并。
3. 实现 history query/snapshot；对 0/1/100 条、五种通用状态、相同 createdAt 的 executionId tie-break、null/末页 cursor、
   防御复制和多页全局唯一做确定性验证。
4. 实现 gate/view-state/controller；覆盖 first/refresh/loadMore、显式单次 sync、payloadless changes 的 dirty-bit 合并、
   错误阶段保留、subscription 唯一所有权和 dispose 排空。
5. 实现三个无 Flutter 依赖的 presentation 文件；证明通用 item 只投影 SDK execution 事实，业务模块只能在边界外按
   executionId/txHash 组合目的账户、金额、备注、方向和业务文案。
6. 用转账、广场、投票/治理、第三方四类 App 自有 record fixture 与同一组 generic execution item 做外部组合测试；
   新业务只增加测试 fixture，不修改 history 生产代码或 SDK。
7. 增加反向门禁：history 新代码只能 import models/HistoryPort/同目录文件，不得 import ChainPort、rpc、wallet、旧
   transaction/history、Isar、LocalTx、ChainTxMonitor、业务模块或 `package:citizen_sdk`；禁止 timer/polling/block scan、
   migration/compat/fallback/双读/双写，旧实现 422/422 hash 必须不变。
8. 更新 `lib/chain/README.md`、注释、格式、独立 Dart/Node 测试和任务卡；复核 production/pubspec/旧数据、CitizenSDK
   生产代码/CitizenWallet/PoW 零修改，Flutter 零操作，然后直接输出第 2.6 步完整技术方案。

验收门禁：

- 新生产文件只位于 `lib/chain/application/history/**` 与 `lib/chain/presentation/history/**`，测试只新增于
  `test/chain/history/**`；不创建其它 production 目录，不切换入口。
- history 生产代码只调用 HistoryPort 三个既有成员；对 ChainPort、任意 RPC、block/body/events/storage、旧 LocalTx/
  ChainTxMonitor/Isar 和 CitizenSDK 直接 import/调用为零。
- 0/1/100/101 页大小，limit 0/1/100/101，null/有效/未知 cursor，五种状态、顺序、重复、revision 和跨页不变量全部覆盖；
  无效页不能改变最后一个已验证 snapshot。
- load/refresh/loadMore/sync single-flight，change burst 合并、change/loadMore 和 sync/change 竞态、stop/dispose/迟到结果
  全部确定性通过；无 timer、轮询、隐式 sync、后台 monitor 或跨 controller singleton。
- 通用 item/API 中不存在 destination、amount、remark、direction、业务 pallet/event/action/文案、App correlation、
  callData、signature、signed extrinsic 或旧数据库 entity；业务 fixture 不引起生产分支。
- 旧实现路径/hash 422/422 一致；无迁移、兼容、legacy、adapter、wrapper、alias、fallback、双读、双写或运行时新旧选择。
- production、pubspec、旧实现/数据、CitizenSDK 生产代码、CitizenWallet、定制 PoW 零修改；Flutter 不调用、不安装、
  不下载、不升级、不配置、不启动、不停止或清理缓存，独立 Dart/Node 门禁必须通过。

完成定义：通用 history application/presentation、注释、测试和清理全部完成，旧 LocalTx/ChainTxMonitor/页面/数据库与
422 文件冻结范围零修改、production 零切换、全部边界门禁通过，并直接写入/输出 2.6“App 业务边界回归验收及第三部分
接入前唯一调用面/3.6 删除清单”的完整技术方案。用户确认前不执行 2.5。

### 2.6 App 业务边界回归验收

状态：原方案已取消，等待第二部分重新设计。

- 证明 Square、Vote、Legislation、Proposal、Governance、CID 和业务数据钥等仍在 App，且可通过只认识
  opaque bytes 的 fake 端口独立测试。
- 证明 `lib/chain/**` 新路径不依赖任何具体旧链底座实现；旧路径仍按冻结 hash 原样存在但不能被新路径调用。
- 证明 App 的任何业务需求都没有造成 CitizenSDK 新增 App 专用模型/方法；输出第三部分接入前的唯一调用面
  和 3.6 一次性删除清单。

## 五、第三部分：CitizenSDK 接入 CitizenApp

第三部分只在 `lib/chain/sdk/**` 把最终端口绑定到已经冻结的通用 CitizenSDK；正常接入不得修改 SDK 生产 API。
原 CitizenApp 旧实现继续按 2.1 hash 冻结，不得为了接入而搬动、改写或包装。禁止运行时选择、fallback、wrapper、
迁移、兼容、双读或双写：3.1—3.5 先把完整新路径独立实现和验证，全部能力齐备后生产根只执行一次切换到
`ChainServices`，此后新路径绝不调用旧实现；完整端到端验证通过后，3.6 一次性彻底删除冻结旧底座。若确有基础
能力缺口，停止接入并回到第一部分按“其它 App 也可使用”的合同重新提案。

### 3.1 SDK 依赖与唯一运行时

状态：未开始。

- 增加正式 CitizenSDK 依赖和 App 内唯一 runtime owner。
- 对齐 Flutter/Dart 版本、平台插件注册、生命周期、能力事件和 stop-before-close。
- 新 runtime owner 只能位于 `lib/chain/sdk/**`，不 import 或控制旧 smoldot。3.1—3.5 的定向测试直接构造新路径；
  production 在完整切换点之前仍走原路径，切换后只走 SDK，永远没有运行时二选一或失败回退。

### 3.2 钱包与账户页面接入

状态：未开始。

- WalletGate、创建/导入、账户列表、默认账户、改名、删除、私钥安全查看全部使用 SDK。
- 热钱包由用户重新输入助记词；冷账户由用户重新输入或扫描公钥。
- 新实现全部位于 `lib/chain/sdk/wallet/**`，不读取 CitizenApp 旧钱包表和旧金库；旧链钱包/金库源码保持冻结，
  新路径验收通过后在 3.6 删除。

### 3.3 业务链读取接入

状态：未开始。

- 将第二部分的链读取端口绑定到 SDK 通用 finalized/storage/metadata 原语。
- 验证广场、身份、订阅、投票、立法、提案、多签和资产读取结果。
- storage key、SCALE 业务解码、组合查询和展示逻辑全部位于 App；SDK 不新增这些业务查询。
- 新实现全部位于 `lib/chain/sdk/read/**`；App 自带 smoldot、ChainRpc 和链资产生命周期保持冻结且不被新路径引用，
  完整切换验证通过后在 3.6 删除。

### 3.4 热签、冷签与交易接入

状态：未开始。

- 将 App 构造的 opaque SigningIntent/callData 绑定到 SDK 通用签名和交易接口，不向 SDK传业务对象。
- 完成热账户本机签名交易闭环，以及冷账户导入、App 展示请求、CitizenWallet 扫码、App 回扫、SDK
  transport 验签和提交的完整闭环。
- CitizenWallet 零修改。
- 新实现全部位于 `lib/chain/sdk/{signing,transaction}/**`；NativeSr25519、SignedExtrinsicBuilder、直接
  nonce/runtime/submit/watch 和旧冷热签名入口保持冻结且不被新路径引用，3.6 一次性删除。

### 3.5 历史、事件与应用生命周期接入

状态：未开始。

- 页面使用 SDK history/events/capabilities。
- 接入启动、后台、恢复、退出、数据擦除和失败重试流程。
- 旧交易记录不迁移、不双写、不兼容读取。
- 新实现全部位于 `lib/chain/sdk/{history,lifecycle}/**`。当 3.1—3.5 全部通过后，生产根一次性改为只构造完整
  `ChainServices`，随后执行端到端验证；旧 ChainTxMonitor、提交确认路径和数据库仍只读冻结且不参与新运行。

### 3.6 验证后一次性删除旧底座与最终验收

状态：未开始。

- 先确认生产已唯一使用 `lib/chain` 且钱包、冷热签名、链读取、业务交易、history/events/lifecycle 全部端到端通过；
  任一失败立即修复新路径，不能回退或调用旧实现。
- 验证通过后，在一个变更中彻底删除冻结的 App 自带 smoldot、sr25519、旧链钱包金库、完整交易构造器、提交器、
  ChainTxMonitor、旧 execution/history 底层、旧依赖/资产/平台构建配置和全部旧调用；不读取或迁移其数据。
- 全仓确认 App 对 SmoldotClientManager、NativeSr25519、SignedExtrinsicBuilder 和旧 SecureSeedStore 的生产引用为零。
- 完成静态分析、单元测试、集成测试、真机冷热钱包流程和发布构建；同时重跑 SDK reference/第三方 consumer，
  证明 CitizenApp 接入没有把 SDK 收窄为专用实现。
- 更新全部文档并关闭本任务卡。

## 六、当前推进点

- 已完成：只读梳理 CitizenApp 与 CitizenSDK 当前实现和产品边界。
- 已固定：三产品边界、三部分顺序、逐步骤确认门禁、无迁移、无兼容、CitizenWallet 零修改。
- 已完成：第 1.1 步“钱包核心合同：热钱包与仅公钥冷账户统一状态”。
- 已完成：第 1.2 步“钱包公开 API 与五端宿主投影”。
- 已完成：第 1.3 步“通用签名与冷热签名会话”。
- 已复核：1.1、1.2 新增能力符合面向全部 App/第三方的通用 SDK 标准，无需返工。
- 已复核：1.3 新增能力符合通用 SDK 标准；固定 action allowlist 已删除，CitizenWallet 仍为独立外部签名器。
- 已完成并复核：第 1.4 步“轻节点与安全链读取等价能力”；Core/C ABI/Dart/五端只公开验证后的通用链事实，
  未加入业务查询、任意 RPC、迁移或兼容层。
- 已完成：SDK 早期遗留的业务化 QR UserTransfer/bank_cid_number 和 CitizenApp 历史语义已经由 1.5、1.7、1.8
  分别提供通用替代并清理，不再进入最终通用性验收。
- 已完成并复核：第 1.5 步“不透明 callData 的通用交易构造”；`prepareTransaction(sourceAccountId,
  callData)` 和 `cancelPreparedTransaction(preparationId)` 已贯通 Core、C ABI、Dart 与五端，SDK 只处理不透明
  RuntimeCall 和链协议事实，不实现任何 App 业务。
- 已完成并复核：第 1.6 步“热钱包与冷钱包通用交易闭环”；热账户由 SDK 内部强认证签名，冷账户只走既有
  `QR_V1`，两者共同进入通用 pending-before-broadcast、准确 finalized 证明与原字节恢复状态机。C ABI/Flutter
  闭集分别为 121/64，CitizenApp 与 CitizenWallet 零修改。
- 已完成并复核：第 1.7 步“通用交易观察与历史”；SDK 仅保存自身提交的通用 execution 事实，App 专用的目的
  账户、金额、备注、方向、业务 pallet/event 和页面模型已经归位 CitizenApp，不迁移、不兼容、不双写。当前
  步骤当时的 C ABI/Flutter 闭集为 117/63，CitizenWallet 与定制 PoW 上游均未修改。
- 已完成并复核：第 1.8 步“现存业务耦合清理与通用性反向门禁”；UserTransfer、bank CID、金额、币种、备注及
  专用业务二维码编码/审阅投影已经从 SDK 生产面删除，历史 kind `4` 永久为空洞，`QR_V1` 仍是唯一协议。
  当前 C ABI/Flutter 精确闭集为 116/62，CitizenApp、CitizenWallet 与定制 PoW 上游均未修改。
- 已完成：第 1.9 步通用实现、三类消费者、独立 external signer、Rust/Flutter/Release、ABI 与 Android 本地验收；
  Apple Core 三个 slice 已通过。Apple Flutter adapter/Apple tests 按“不得操作 Flutter 下载安装”的最新要求保留
  待验收；未提交、未推送、未触发同源远程 runner，也不伪造 Linux/Windows/移动真机结果。
- 已完成：第 1.10.1 步“基线与问题分级”；生产代码/API/ABI/schema/协议零修改，P0=0、P1=5、P2=2，
  Flutter 按明确要求未操作，CitizenApp、CitizenWallet 与定制 PoW 上游均未被本步骤修改。
- 已完成并复核：第 1.10.2 步“安全与资源边界”；只关闭持久 runtime cache 无界、history 总量不可编码和
  runtime metadata 双重上限三项 P1。Core 64 MiB 功能上限未降低，持久 cache 固定 64 条和 8 MiB 完整记录，
  history 固定 31 MiB durable weight；无迁移、兼容、业务模型、其它 QR 版本、CitizenWallet 或 PoW 改动。
- 已完成并复核：第 1.10.3 步“通用 API 易用性与错误可观测性”；22 个错误码保持原数值，新增八项通用
  failure stage 和唯一只读 result getter，五端 Flutter 错误统一为绑定 62 项公开 method 的七项 tuple。当前闭集为
  117/62/3/17；无业务模型、迁移、兼容、其它 QR 协议、CitizenWallet 或 PoW 改动，Flutter 按明确要求未操作。
- 已完成并复核：第 1.10.4 步“性能、持久化、生命周期与发布冻结”；whole-history BLOB 已由逐 execution
  index/query/mutation 替换，四端 schema v2 与有界回收完成，adapter 订阅退避修正，Rust workspace、Release
  107/107 和仓库外 ABI host 通过。第一部分 1.1—1.10 全部完成；Flutter 未运行或操作，CitizenApp、
  CitizenWallet 和定制 PoW 未修改。
- 已撤销：原第二部分 2.1—2.4 在 CitizenApp 内建立了重复的通用抽象和协调层。按用户要求，
  `citizenapp/lib/chain` 的 42 个文件、`citizenapp/test/chain` 的 13 个文件及两个完整目录已彻底删除；2.5、2.6 原方案
  同时取消。CitizenApp 原钱包、签名、交易、history、smoldot/RPC 和业务源码均未修改，Flutter 未运行或操作。
- 当前推进点：第二部分归零，等待按“CitizenSDK 与定制 smoldot 已有功能直接复用、CitizenApp 仅保留业务并做最薄
  直接接入、不重复 models/ports/controller/gate/reader/history/presentation”的标准重新输出完整技术方案。确认前
  不在 CitizenApp 新建任何目录或文件。
