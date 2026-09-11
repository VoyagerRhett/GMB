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

状态：实现完成，最终门禁执行中（2026-09-11）。

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

状态：完整技术方案待确认；未开始实现。

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
零改动；SDK 构建、测试和发布不读取 CitizenApp/CitizenWallet 源码。得到明确确认后一次完整执行 1.8，完成后更新
文档、注释、测试、清理残留并自动输出 1.9 完整技术方案。

### 1.9 公共 API、五端包装与多消费者完整验收

状态：未开始。

- 统一 Dart、C、Kotlin、Swift、C++ 的公开命名、生命周期、异步完成和错误合同，并验证 Android、iOS、
  macOS、Linux、Windows 的源码投影、真实消费者和发布闭包。
- 至少建立三类只使用发布包的 consumer：无业务 reference app、CitizenApp adapter fixture、与 CitizenApp
  payload 完全不同的第三方/途遇风格 fixture；任何一个都不得要求修改 SDK 生产代码。
- 验证钱包、冷热签名、external transport、轻节点、任意 storage、opaque callData 交易和通用历史。
- CitizenWallet 只作为不修改的 QR adapter 外部协议基准；其它 external signer mock 证明核心未绑定 Wallet。

### 1.10 功能等价及通用性验收后的 SDK 改进

状态：未开始。

- 在 1.1—1.9 全部通过后，再评审安全边界、API 易用性、性能、数据库增长、后台同步、错误可观测性、
  transport 扩展性和跨平台一致性。
- 每项改进单独出方案；不得以某个 App 当前需求为由增加业务 API，不修改 CitizenWallet，不引入旧数据兼容。
- 改进后重跑多消费者完整回归，不以 CitizenApp 单一消费者或局部测试代替通用 SDK 验收。

## 四、第二部分：CitizenApp 业务层与旧底座剥离

第二部分只修改 CitizenApp，以第一部分已经通过多消费者验收的通用 SDK 合同为前提。期间允许旧底座作为
开发期实现维持构建，但业务代码必须逐步只依赖 App 内部端口；这不属于用户数据兼容。发现 SDK 缺能力时，
必须回到第一部分按通用能力单独出方案，禁止直接为 CitizenApp 增加专用 SDK 方法。

### 2.1 建立 App 区块链端口与目录边界

状态：未开始。

- 建立钱包、通用签名 intent、链读取、opaque callData 交易和通用历史端口。
- 业务模块只依赖端口，不直接引用 smoldot、NativeSr25519、WalletManager 私钥能力或 SignedExtrinsicBuilder。
- 冻结 App 业务层保留目录、业务 DTO/action/payload/storage codec 清单和旧底座待删除清单；端口形状必须可
  由通用 SDK 实现，不能反向要求 SDK 理解 App 业务类型。

### 2.2 拆分 WalletManager

状态：未开始。

- 分离链钱包职责与 CID/设备子钥/账户数据钥、`k=6` 用途钥交付等 App 业务安全职责。
- 钱包页面改为使用钱包端口；业务数据钥服务保持在 App。
- 不增加旧钱包到 SDK 的迁移、转换或兼容逻辑。

### 2.3 剥离链读取和轻节点依赖

状态：未开始。

- 广场、身份、订阅、投票、立法、提案、多签等业务查询改为调用链读取端口。
- 业务 storage key 和 SCALE 解码保留在原业务目录。
- 隔离并准备删除 SmoldotClientManager、ChainRpc 传输层和 App 链资产生命周期。

### 2.4 剥离签名和交易构造依赖

状态：未开始。

- 业务服务自己构造 action、opaque payload/callData、storage key 和业务展示内容，只把字节与通用
  signing transform/transaction options 交给端口。
- 删除业务代码对 NativeSr25519、完整 SigningPayload、signed extrinsic、nonce/runtime 获取和直接提交的依赖。
- 冷签页面只负责展示/扫描；App 保留业务审阅文案，SDK 端口负责 transport session、密码学绑定和验签。

### 2.5 剥离交易观察和历史底座

状态：未开始。

- 页面改为消费通用交易事件与历史端口。
- App 仅保留业务展示映射，不再自行扫描 finalized 块确认 SDK 提交的交易。
- 旧 LocalTx/ChainTxMonitor 不迁移到 SDK，不建立双写或兼容读取。

### 2.6 App 业务边界回归验收

状态：未开始。

- 证明 Square、Vote、Legislation、Proposal、Governance、CID 和业务数据钥等仍在 App，且可通过只认识
  opaque bytes 的 fake 端口独立测试。
- 证明 App 业务层不再依赖任何具体旧链底座实现。
- 证明 App 的任何业务需求都没有造成 CitizenSDK 新增 App 专用模型/方法；输出第三部分接入前的唯一调用面
  和删除清单。

## 五、第三部分：CitizenSDK 接入 CitizenApp

第三部分只把 CitizenApp 端口绑定到已经冻结的通用 CitizenSDK；正常接入不得修改 SDK 生产 API。若确有
基础能力缺口，停止接入并回到第一部分按“其它 App 也可使用”的合同重新提案。

### 3.1 SDK 依赖与唯一运行时

状态：未开始。

- 增加正式 CitizenSDK 依赖和 App 内唯一 runtime owner。
- 对齐 Flutter/Dart 版本、平台插件注册、生命周期、能力事件和 stop-before-close。
- 禁止 SDK 轻节点与 App 旧 smoldot 同时运行。

### 3.2 钱包与账户页面接入

状态：未开始。

- WalletGate、创建/导入、账户列表、默认账户、改名、删除、私钥安全查看全部使用 SDK。
- 热钱包由用户重新输入助记词；冷账户由用户重新输入或扫描公钥。
- 不读取 CitizenApp 旧钱包表和旧金库。

### 3.3 业务链读取接入

状态：未开始。

- 将第二部分的链读取端口绑定到 SDK 通用 finalized/storage/metadata 原语。
- 验证广场、身份、订阅、投票、立法、提案、多签和资产读取结果。
- storage key、SCALE 业务解码、组合查询和展示逻辑全部位于 App；SDK 不新增这些业务查询。

### 3.4 热签、冷签与交易接入

状态：未开始。

- 将 App 构造的 opaque SigningIntent/callData 绑定到 SDK 通用签名和交易接口，不向 SDK传业务对象。
- 完成热账户本机签名交易闭环，以及冷账户导入、App 展示请求、CitizenWallet 扫码、App 回扫、SDK
  transport 验签和提交的完整闭环。
- CitizenWallet 零修改。

### 3.5 历史、事件与应用生命周期接入

状态：未开始。

- 页面使用 SDK history/events/capabilities。
- 接入启动、后台、恢复、退出、数据擦除和失败重试流程。
- 旧交易记录不迁移、不双写、不兼容读取。

### 3.6 删除旧底座与最终验收

状态：未开始。

- 删除 App 自带 smoldot、sr25519、硬件钱包金库、完整交易构造器、提交器、监控器和不再使用的依赖/资产/平台构建配置。
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
- 已登记：SDK 早期遗留的业务化 QR UserTransfer/bank_cid_number 和 CitizenApp 历史语义由 1.5、1.7、1.8
  分别提供通用替代并清理，不能进入最终通用性验收。
- 已完成并复核：第 1.5 步“不透明 callData 的通用交易构造”；`prepareTransaction(sourceAccountId,
  callData)` 和 `cancelPreparedTransaction(preparationId)` 已贯通 Core、C ABI、Dart 与五端，SDK 只处理不透明
  RuntimeCall 和链协议事实，不实现任何 App 业务。
- 已完成并复核：第 1.6 步“热钱包与冷钱包通用交易闭环”；热账户由 SDK 内部强认证签名，冷账户只走既有
  `QR_V1`，两者共同进入通用 pending-before-broadcast、准确 finalized 证明与原字节恢复状态机。C ABI/Flutter
  闭集分别为 121/64，CitizenApp 与 CitizenWallet 零修改。
- 当前待确认：第 1.7 步“通用交易观察与历史”完整技术方案；未确认前不执行。
