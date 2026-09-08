# CitizenSDK 源码来源与同步策略

当前 SDK 自有合同：Core 公开 89 个函数，另有 4 个内部链接函数；Linux/Windows Host 各 17 个函数，
QR 图像窄包装 3 个函数，Flutter 五端统一 36 方法。此次只调整 SDK 自有装配与绑定，
不修改 CitizenChain、CitizenApp、CitizenWallet 或 ZXing-C++ 上游源码。
运行期模块选择不裁剪现有正式 full 包与链资产。模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

当前产品边界：根共享目录已移除。CitizenApp 的签名及用途钥实现归入其 `native/`，CitizenWallet 的实现归入其 `rust/src/` 与 `lib/`，平台金库由钱包宿主直接承接。CitizenSDK 保持独立，不被这两个产品引用。下文旧 shared 路径仅记录历史来源。


## SDK 单源实现与来源界限

SDK 自有旧 Dart 钱包、交易、轻节点协调和 Preferences 实现已删除，相关正式路径只在
Rust Core。受保护的 smoldot Dart/FFI/PoW 及 signer 算法保持原有来源边界；新增启动节点
建议和原生调度属于 SDK 适配代码。完整测试执行、删除清单和差异证据只记录在唯一任务卡。

## 第二步 SDK 自有监控接线（2026-09-05）

`native/smoldot/provider/src/{client,legacy,verified_chain_client}.rs` 只适配既有 smoldot
finalized 订阅、验证型快照和取消接口。上游 `pow/light-base` 的订阅、P2P、同步、PoW
与验证源码未改。SDK 新增 `native/engine/src/chain_monitor.rs` 与
`native/ffi/src/chain_monitor.rs`，以及同目录对应的 `chain_monitor_tests.rs`；它们是
钱包账户代际、取消排空、持久化历史调度及事件转发，不是第二套轻节点实现。
历史和 pending 恢复继续使用原有 finalized block/body/index/System.Events 与 CAS。
本次明确 SDK 边界变化为 HistoryChanged=5 无 payload 事件及可取消监控接线；不宣称
这些 SDK 协调代码与 CitizenApp 逐字节相同，也不改 CitizenApp、CitizenWallet 或 shared。
原有 `wallet_abi.rs` 的整段 future 丢弃式取消已改为单笔 `WalletTransferCancellation`
协作通知并继续等待 Engine 返回。该修复保持所有已进入 store/CAS／金库的操作租约，
在随后边界停止读取或广播，不改变上游订阅算法、交易编码、签名与执行核验规则。
回归覆盖取消前首次 poll、安静 watch、Pending／InBlock／终态 CAS、租约排空及其它请求隔离。

## 现行仓库身份与来源元数据（2026-09-05）

用户明确要求三仓统一清除旧仓库身份；当前第一方身份为 VoyagerRhett，SDK 所属仓库为
https://github.com/VoyagerRhett/GMB。包清单、主页、自有版权署名与来源清单同步更新。
本次 `native/smoldot/ffi/Cargo.toml` 只调整自有作者元数据，
`native/smoldot/pow/lib/src/verify/pow.rs` 只调整第一方版权署名，不改上游算法。
归档 `docs/smoldot-dart/source-pubspec.yaml` 的 repository 已按当前身份规范化，
不再声称该字段仍为初始快照原文；固定依赖提交、版本、协议、签名向量及许可证条款不变。
来源摘要只针对已核实的上述差异更新；同时核对现行 CitizenApp 对应文件。
订阅继续调用 smoldot 已实现的订阅／通知／取消接口，SDK 只负责适配和钱包应用层调度。

## 钱包输入单源与本轮明确差异（2026-09-05）

钱包派生密码语义参照 CitizenApp 和 shared/wallet-password：空值有效、非空 NFKD 与
字符／字素长度校验、一次风险确认；密码参与派生而非 App 登录。本轮不移动或修改这些
来源文件，也不修改 CitizenWallet 或上游依赖。SDK 的校验与派生共用既有 Rust 核心。

新增 `native/engine/src/wallet_input.rs` 直接使用已有 BIP39 依赖的英文词表和校验和；
三个同步 C ABI 只校验或返回最多六个公开词表候选，不启动轻节点，不回显原输入。
各平台 SDK 安全界面调用该实现，宿主 Dart 不接触助记词、派生密码或私钥。

以下是用户明确要求的行为变化，不宣称与 CitizenApp 逐字节相同：允许 12／18／24 词；
创建先准备、确认备份后再提交；各平台取消重复密码输入，非空创建／导入只确认一次风险；
失败重试不隐式改用空密码。原有公开测试向量保留，18 词用公开合成熵补充生命周期回归。
新增与原样来源分开审计，许可证、上游源码和既有链资产不变。

## 固定原生静态依赖来源（第 10.5 步）

下列官方归档已核验实际下载字节；它们不是 CitizenApp 的逐字节收编源码，也不是本机
已编译验证的依赖。完整官方源码只在中央准备工作区解包，SDK 源树没有新增源码副本或产物。

| 组件 | 官方准确归档 | SHA256 |
| --- | --- | --- |
| SQLite 3.53.4 | https://www.sqlite.org/2026/sqlite-amalgamation-3530400.zip | 1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d |
| OpenSSL 3.5.8 | https://github.com/openssl/openssl/releases/download/openssl-3.5.8/openssl-3.5.8.tar.gz | a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2 |
| TPM2-TSS 4.2.0 | https://github.com/tpm2-software/tpm2-tss/releases/download/4.2.0/tpm2-tss-4.2.0.tar.gz | b53f0c5c8c4ce17f05701a410ca9688f725ca380c9bc4640eacd0eadb1fea124 |
| ZXing-C++ 3.1.1 | https://github.com/zxing-cpp/zxing-cpp/releases/download/v3.1.1/zxing-cpp-3.1.1.tar.gz | c3c02c29c0b519de7bd4e25b376e606e87f0761befd1282815642a2246613d14 |

SQLite 官方发布页提供的 SHA3-256 为
628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e；
上表 SQLite SHA256 是对同一通过官方 SHA3 校验的归档另行计算，不冒称官方公布。
OpenSSL/TPM2-TSS SHA256 与官方 GitHub Release asset digest 一致。ZXing-C++ 归档只在 TATA 任务工作区解包，
SDK 源树不复制或修改上游源码；CMake 在执行上游前验证准确构建输入树，不只检查版本字符串。
完整归档的 `core/`、`docs/`、根 `CMakeLists.txt` 和 `zxing.cmake` 共 342 文件，按相对路径排序，
将每项 `路径:SHA256\n` 串接后的 SHA256 为 `47e4950494ae7fef55307846ad47f2586b83a1d4cde381ec3c2ca0215015db3e`。
直接构建官方独立 `core/` 工程，不构建根工程无条件附带的 C 示例及其 stb 依赖；
只关闭上游公开非 QR 格式选项、固定 bundled zint 与 LOCAL 依赖，不执行在线自动取源。顶层 Apache-2.0
`LICENSE` SHA256 为 `c6596eb7be8581c18be736c846fb9173b69eccf6ef94c5135893ec56bd92ba08`；
启用 writer 时所用的上游内置 libzint 文件保留其 BSD-3-Clause 头部声明。

既有 LICENSE 原文保留；追加 SQLite sqlite3.h 的 public-domain 声明、OpenSSL 完整
LICENSE.txt、TPM2-TSS 完整 LICENSE。OpenSSL 原文 SHA256：
7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a；
TPM2-TSS 原文 SHA256：
18c1bf4b1ba1fb2c4ffa7398c234d83c0d55475298e470ae1e5e3a8a8bd2e448。
根 THIRD_PARTY_NOTICES.md 保留所选生产源码/头的版权归属，不能因 TPM2-TSS 根许可
未列版权人而遗漏声明。OpenSSL 没有额外 NOTICE 文件；未交付的 FAPI/SPI/I2C/Policy、
OpenSSL Perl 构建工具不冒充本次运行库闭集。

当前两端使用的 24 个 SQLite 函数均在固定官方 sqlite3.h 中存在；
TPM2-TSS 的 esys_crypto_ossl.c 包含 OpenSSL 3 的正式分支。以上仅证明接口声明和来源，
不代表实际链接或运行通过。准备参数、八个 TSS2 头、142 个 OpenSSL 头、静态对象门禁及
生成证据职责见 NATIVE_PACKAGING.md；中央合同是版本/来源准备唯一入口，SDK 只固定其摘要。


## 权威来源

`/Users/rhett/GMB/citizensdk` 是 CitizenSDK 产品源码、测试、锁文件、文档与打包脚本的唯一
权威目录。CI、Release 和宿主接入不得通过 `../citizenapp`、`../shared` 或其它仓库相对路径
读取运行时源码。

初始收编不改变现有产品：CitizenApp 继续使用自己的轻节点、钱包和交易实现；CitizenApp 与
CitizenWallet 继续使用 `shared/citizen-signer`。CitizenSDK 稳定后如需让 CitizenApp 切换，
必须另立并批准独立切换步骤，不能把当前复制过程反向写入现有 App。

从收编基线起，CitizenSDK 内部改动只在 `citizensdk` 演进。安全或共识修复如需同时回补
CitizenApp、CitizenWallet 或上游 fork，必须列出两侧精确文件、分别审查并用相同向量和行为
测试验证；不做自动双向同步，也不维护 CI 时跨目录复制。

## 版本权威

`pubspec.yaml` 是 CitizenSDK 软件版本入口；`android/build.gradle`、
`darwin/citizen_sdk.podspec`、`linux/CMakeLists.txt` 与 `windows/CMakeLists.txt` 必须保存同一版本。首个稳定源码版本冻结为 `1.0.0`。Release 请求的
software version 必须等于该提交的源码版本，生成后 `citizensdk-release.json`、Dart pubspec、
Android Gradle、Darwin podspec、Linux CMake 和 Windows CMake 还会再次交叉核验。发布器不允许从 `0.1.0` 或其它旧版本源码在
Runner 中临时改号成 `1.0.0`，未来升级也必须先提交准确版本源码。

版本冻结只证明候选身份，不等于 Hosted Registry 已接受该版本；首次不可逆发布必须另行取得
明确授权，并以对应 GitHub Release 的同一候选为输入。

## CitizenSDK 自有 Rust Core 与产品 ABI

第 12 步新增的原授权恢复、事件容量预留、平台线程/宿主隔离和 Linux DMS 修复属于 SDK
自有代码加固，不宣称来自 CitizenApp 的逐字节副本。链资产、sr25519 实现与上游 smoldot
算法源码本批不改；SDK 发布器继续逐项固定实际变更后的自有源码、文档与测试摘要。

`native/contracts`、`native/engine` 与 `native/ffi` 是 CitizenSDK 自有实现，不是 CitizenApp
或 smoldot 上游逐字节副本。contracts 固定 `VerifiedChainClient`、`ChainSigner`、
`SecretVault`、十项能力状态、钱包公开模型与五类职责明确的状态仓储；engine 实现能力解析、
准确区块 runtime context、受约束状态导入、账户/费用/nonce、钱包生命周期、准确 V4 交易
构造、广播前 pending、finalized 历史及同一 extrinsic index 的执行核验；ffi 只把已经装配的
类型化能力投影为唯一 `citizensdk_*` C ABI。依赖方向固定为
`bindings -> ffi -> engine -> contracts <- providers`，不依赖 Flutter 页面、产品数据库或任意
公开远程 RPC。

钱包合同固定 wallet index `0`、账户0锚、SS58 prefix `2027`，并从 AccountId32 重算规范
地址；create/import 与 append 分别使用空 previous 和严格账户列表前缀，provisioning、active
cleanup 与 queue 由 exact secret/KEK 物理身份隔离。创建只能经 prepare 零持久写入→用户备份
确认→commit；删除后的 SecretRef 保留永久 tombstone，整代 Vault generation 持久退休。
Engine 以生命周期覆盖链能力 readiness，
所有生命周期转换和 probe 更新使用 `state -> capabilities` 锁序。导入会合并 revisioned
`ChainDatabaseStore` 的持久化 finalized 锚并无条件 CAS exact 状态；跨 Engine 或进程保证要求
store provider 提供共享、耐久、强原子 CAS；各正式平台使用独立 typed store adapter。
host 组合还由 CitizenSDK 自有 Engine/FFI 实现 start-before-provider restore、export/stop exact
snapshot persistence、失败短路、host lifecycle 独占 admission 与 pending/completing callback
销毁屏障；平台绑定只履行 typed store vtable，不复制状态机或解析私有信封。legacy session 构造
的既有生命周期语义保持不变。

engine 精确使用 crates.io 官方 `subxt-core = 0.43.0` 解析 SCALE metadata、
`System.Events`，构造 signed extrinsic V4 并遵循 Substrate extrinsic 哈希语义；它没有引入
网络客户端或第二个轻节点。
Core/产品 FFI 闭集由 Release 独立反向枚举、固定哈希并拒绝额外 `build.rs`、`src/bin`、
符号链接或未登记文件。根 `include` 三文件同样作为公共 ABI 闭集固定，并拒绝
`smoldot_*`、`citizen_sr25519_*`、`account_crypto_*`、任意 RPC、private-key/child-secret
导出和 raw signer 逃生口；受控 prepared 备份及 import/add 用户输入另按产品 ABI 合同固定。

第 4.1 步的 Rust Core 已实现账户、两阶段钱包创建与完整生命周期、唯一 sr25519 签名路径、
不可拆分的钱包交易和 finalized 历史行为。第 4.2 步又建立 Rust 内部产品组合，固定真实
smoldot provider、准确 Runtime nonce 和唯一 signer，并只接受 typed Vault/stores。第 5.1 步
在未发布 ABI v1 内保留原 36 个符号不变，当时追加 34 个账户、钱包、签名、转账和历史符号；
此前再加入 3 个同步钱包输入接口后为 73 个；第 2 步新增模块校验、模块构造与无实例验签，
随后补充四个链查询/结果入口形成 80 个；QR 统一为九个协议、审阅、签名和结果入口，当前共 89 个。
既有构造保留默认行为并进入同一私有装配，官方绑定改为按 modules 选择服务与资源。
第 5.2 步根 Dart API 与 Android native/Flutter 双投影切换到 Rust Engine；第 6 步又以共享
`darwin/` 源码为 iOS 与 macOS 建立 Swift/Flutter、typed SQLite 与 Apple Vault 投影。旧 Dart
硬件秘密通道和装配已删除；SDK 自有 Dart 轻节点协调、钱包、交易与 Preferences 实现及
相关旧测试同样已删除，正式实现只在 Rust Core。

## 许可证原文

根 `LICENSE` 是 CitizenSDK 组件许可证入口，明确 SDK 自有代码、smoldot Dart/FFI 与
smoldot PoW 的适用许可证边界，SHA-256 为
`e18cd42a76f530deefa3db97a1b2728eccbfc4d24a2057eef36e5eb73c96b58f`；它还完整重现 Apache-2.0
原文，使过滤掉 `native` 源码目录的 Hosted 包仍携带适用条款。正式候选同时保留并固定
两份权威法律原文：`LICENSE-GPL-3.0` 与
`citizenapp/smoldot/pow/LICENSE` 逐字节一致，SHA-256 为
`aab56b4a581fc1c50b7c782eacf2fc8be05a47cd98e4bf4d836dd9b6dd9c86f4`；`LICENSE-MIT`
与 GMB 根 `LICENSE` 逐字节一致，SHA-256 为
`39d4ad97ead876b44da69d6d5a3cdc185cd109e82c508ffa5a29f65897c24e1c`。Release 来源守卫会拒绝
删除或内容替换。Apache-2.0 原文由固定的 `native/smoldot/LICENSE-APACHE-2.0` 提供。
`THIRD_PARTY_NOTICES.md` 是随已审查依赖演进的 CitizenSDK 自有归属清单，不冒充逐字节上游
副本，但始终进入候选文件清单和最终归档哈希。Hosted 过滤合同继续保留根许可入口、两份根
许可证原文和第三方声明；Apache-2.0 原文已内嵌于根许可入口，只把其 byte-identical 的
`native` 来源副本、完整来源记录与锁文件留在 GitHub 审计包。

## sr25519 signer

`shared/citizen-signer` 是最初派生、`substrate` context、签名/验签、FFI 错误、panic 收口与
清理行为的来源，但从收编后 `native/signer` 是 CitizenSDK 权威实现，运行时不反向依赖
shared。第 4.1 步为避免两套密码学逻辑，把算法集中到 `src/sr25519.rs`：`src/lib.rs` 的 legacy
四原语和 `src/chain_signer.rs` 的类型化 `ChainSigner` 都只调用它。因此当前
`native/signer/src/lib.rs` 和 crate 清单不再宣称与 shared 逐字节一致；来源关系由行为向量与
差分合同证明，不能继续使用旧文件哈希冒充当前真源。

本 crate 当前闭集为 `Cargo.toml`、两份 README、三个 `src/*.rs` 与四个 `tests/*.rs`，共 10
个普通文件。测试分别覆盖类型化 signer、legacy FFI、两条入口 parity 与 Substrate 向量；
Release 仍须反向拒绝额外 `build.rs`、`src/bin`、符号链接或未登记文件。

## smoldot Dart 包

`citizenapp/smoldot/dart` 是初始来源。为使根 Flutter 包能够作为单一 Hosted Package 直接
解析，Dart 包边界只做以下机械重排：

- `lib/smoldot.dart` 与 `lib/src/*` 迁入 `lib/src/smoldot/*`；
- 6 个 Dart 测试和两个公开链 fixture 迁入 `test/smoldot`；
- 包清单、锁文件、分析规则、许可证、上游说明和示例迁入 `docs/smoldot-dart` 作为历史记录。

根 `pubspec.yaml` 是唯一有效包清单，运行依赖只有 Flutter SDK 与 `polkadart_keyring`，
不再声明本地 `path` 包。受保护 smoldot 来源测试所需的 `ffi`、`meta`、`path` 仅为开发依赖，
资产测试使用 `crypto`，Flutter 测试和 lint 使用官方工具依赖；不再直接依赖旧钱包或 Preferences 包。
历史清单使用 `source-` 前缀，禁止参与依赖解析。
迁入绑定除 import/export、移动测试夹具路径、移动平台测试加载路径、交付范围注释和根包
formatter 归一外不改行为；发布器继续对迁移闭集逐文件固定哈希，并对
`native/smoldot` Rust/FFI 闭集反向枚举。该 Dart 实现已从根公开入口移除，只作为归档差分
测试基线；Android、iOS 与 macOS 正式绑定均不可达。

历史 `README.md`、`BUILD.md`、`UPSTREAM.md` 中的桌面平台、CitizenApp 路径及源码树内
`target` 命令不代表 CitizenSDK 当前交付合同，也不得作为 SDK 构建指引。CitizenSDK 当前产品
ABI 投影覆盖 Android、iOS 与 macOS。当前 Android ABI 为 `arm64-v8a`；iOS 设备与模拟器变体
及 macOS 的 Apple machine slice 架构值为 `arm64`。本机宿主测试库与全部生成记录只能写入
`/Users/rhett/TATA/tataconsole/work/gmb/citizensdk` 下的任务独占目录；Linux 合同测试由
`CITIZENSDK_TEST_WORK_DIR` 显式接收现有 `0700` 目录且没有 `/tmp` fallback。远程 Runner 也
必须由统一流程显式注入其 checkout 外的任务独占构建根，不能让测试自行选择临时目录。
legacy `libsmoldot.dylib` 仅允许 macOS `arm64` 差分测试；
其 build-local `LC_ID_DYLIB` 不具分发身份，不得进入候选。实际指引以本文件、
根 README 和 `docs/NATIVE_PACKAGING.md` 为准。

## smoldot FFI

FFI 来源是 `citizenapp/smoldot/ffi`。以下文件保持来源字节：

- `rust-toolchain.toml`
- `src/error.rs`
- `src/ffi_types.rs`

以下文件只做 CitizenSDK 产品边界适配：

- `Cargo.toml`：删除 OpenMLS、聊天信封和账户数据加密依赖，signer 指向 SDK 内部路径。
- `build.rs`：删除聊天源文件监控。
- `src/lib.rs`：删除聊天和账户加密导出，保留 `smoldot_*` 与四个 sr25519 入口。

来源独有的 `src/chat_mls.rs` 没有复制。SDK 新增 README、legacy 头文件合同与范围守卫测试。
`native/smoldot/ffi/Cargo.lock` 从 CitizenApp 已验证锁文件机械裁掉 OpenMLS、聊天与账户加密
闭包；所有保留的 registry 包继续使用来源锁中的准确 name/version/checksum。SDK signer 通过
contracts 使用 `blake2 0.10.6`，这是来源 FFI 锁之外唯一新增的 registry 身份，不得误写成
“没有新增身份”。
SDK 锁文件 SHA-256 为
`117c9ca6ad5cb034c8fc5792028d9085dbc6483194e1aae25123b536c8c0cddb`。

该目录只生成归档 Dart/smoldot 差分测试所需的 legacy 兼容宿主库；
`native/smoldot/include/smoldot.h` 是 legacy 头文件。旧的
`native/smoldot/include/citizensdk.h` 已删除，避免让 `smoldot_*`/`citizen_sr25519_*` 与新的
产品 ABI 形成同名聚合边界。

## smoldot VerifiedChainClient provider

`native/smoldot/provider` 是 CitizenSDK SDK-only 适配，不伪装成 CitizenApp 或 smoldot 上游
逐字节来源。它直接依赖收编的 `pow/light-base`，实现类型化 `VerifiedChainClient`：真实
smoldot 生命周期、verified best/finalized、准确块 storage/body/runtime、完整已签名交易
提交/观察和 finalized database 导入导出。任意 JSON-RPC 只存在于 crate 私有固定 allowlist；
公开 Rust 合同和产品 ABI 都不能传入 method/params。

批量 storage 的 typed API 返回本次证明实际绑定的 block number/hash 与有序值列表；Provider
只在该身份精确等于请求块时接收，否则回退到带准确 hash 的读取。这样链头在异步操作期间发生
A→B→A 也不能让 B 的状态冒充 A，同时继续保留重复 key 的位置语义。

Provider 提交时用 `blake2-rfc 0.2.18` 独立计算完整 SCALE extrinsic 的 Blake2-256，并拒绝
节点返回的不一致 hash。`dropped`、`retracted`、`future` 和 `finalityTimeout` 不冒充确定失败；
只有 `invalid`/`usurped` 是交易池确定失败。Provider 自有 Tokio runtime 驱动来自普通 C ABI
worker 的异步调用。导入导致启动失败后实例永久 `StartFailed`，回退必须由上层销毁组合并
创建未导入的新实例，不能复用旧 Provider。
历史块核验通过 `resolve_finalized_block(hash,height)` 完成：Provider 从同步状态机的准确
verified finalized 锚沿 exact parent hash 回溯，逐头核对响应 hash、SCALE header hash、高度与
父链；best/recent cache 或按高度映射不是证明。独立有界 proof-derived cache 只优化回溯，因而
既支持重启后补扫历史块，又不信任宿主自报 finality 或留下反向查询的重组 TOCTOU。

该目录 12 个普通文件作为 `SOURCE_SHA256.json` 的独立 `provider/sdk_only` 单元固定；清单
摘要由 `release.mjs` 固定。Release 还从根锁递归解析 Provider 的 smoldot registry 图，
逐项核对 PoW 已验证锁与下文准确登记的 SDK feature 合并依赖，不修改 PoW 锁文件。

## 产品 C ABI

`native/ffi` 与根 `include` 是 CitizenSDK 自有产品边界，不属于 legacy FFI 或 smoldot 上游。
根头文件只声明 `citizensdk_*`，固定 ABI version、宽度、布局、所有权、错误、异步事件和能力
语义；C11/C++17 合同逐项核对公开结构布局。构建后的产品库真实导出必须与头文件函数集合
相等，并拒绝 `smoldot_*`、`citizen_sr25519_*`、`account_crypto_*`、任意 RPC、raw signer、
private-key/child-secret 导出与持久秘密 callback。
早期原有 36 个符号与当时新增 34 个符号形成 70 个符号，随后增加三个钱包输入接口，
此后新增模块校验、模块构造、纯验签及四个链查询/结果入口，QR 统一为九个入口，当前闭集为 89 个符号；`abi.rs`、`wallet_abi.rs`、对应
合同测试及根 C 头均为 CitizenSDK 自有适配源码，不伪装成 CitizenApp/smoldot 逐字节来源。

`citizensdk_create` 保持既有默认组合与行为，显式 `citizensdk_create_with_modules` 由
Rust 统一检查闭集、依赖和编译支持，随后按选择装配服务。chain/history 才需要 public store；
wallet/signing 才需要配套 secure store 与 Vault。WalletService、SigningService 与 history
服务各自有独立门禁；签名只使用同宿主已有安全账户归属元数据，首次 provision 仍走钱包流程。
纯验签无需实例、订阅或任何平台业务资源。完整组合仍使用唯一 signer、nonce 和 smoldot，
宿主不能注入任意 RPC 或 raw signer；prepared-wallet 资料仅限绑定 owner 的安全 UI，
不增加秘密导出接口。

Android 候选注入 `libcitizensdk.so` 与 `libcitizensdk_jni.so`，并生成无 Flutter 依赖的
原生 AAR；根 Flutter 插件直接编译同一 Kotlin facade 并消费同字节双库。Apple 候选从
`darwin/Sources/CitizenSDK` 与同一 Rust Core 生成一个 `CitizenSDK.xcframework`，只含 iOS
设备与模拟器变体及 macOS 三个 Apple `arm64` machine slice；
`darwin/Sources/CitizenSDKFlutter` 作为薄 Flutter adapter 消费该框架，不重建 Core。legacy
`libsmoldot` 不进入任一正式候选。

## smoldot PoW + GRANDPA

来源是 `citizenapp/smoldot/pow`，上游提交与本地 PoW 改动清单见
`native/smoldot/UPSTREAM.md`。

`pow/light-base/src/platform/default.rs`、`pow/lib/src/chain_spec/tests.rs` 与
`pow/lib/src/sync/warp_sync.rs` 已恢复为当前 CitizenApp 来源的逐字节副本，并以新的目标摘要
固定在 `SOURCE_SHA256.json`。三者不再以格式或 import 顺序差异冒充 byte-identical；
清单自身的现行摘要只由 `scripts/release.mjs` 固定；本说明不重复维护易失效的摘要。

`pow/light-base` 的 18 个生产文件中 17 个逐字节复制；`src/lib.rs` 单独登记为适配文件，集中
实现 typed storage snapshot、准确 best Runtime nonce 和 proof-backed finalized ancestry，
原兼容方法继续返回相同值列表。SDK 另增说明和能力/来源闭集测试。该层保留数据库、网络、JSON-RPC、runtime、
同步、交易池和平台编排。

`pow/lib` 收编轻客户端需要的 chain、chain-spec、finality、header、verify、trie、executor、
database、JSON-RPC、libp2p、network、sync、transactions、公开测试夹具和上游内联测试。
共享生产文件逐字节复制，仅对 Cargo/workspace、crate 模块入口和 `identity` 模块做最小适配。

明确排除的 8 个来源文件是：

```text
src/author.rs
src/author/aura.rs
src/author/build.rs
src/author/runtime.rs
src/author/runtime/example-chain-specs.json
src/author/runtime/tests.rs
src/identity/keystore.rs
src/identity/seed_phrase.rs
```

前 6 个属于全节点出块，后 2 个会形成轻客户端钱包之外的第二条私钥生成/保存路径。保留的
`identity::ss58` 只处理公钥地址。SDK 另加来源 manifest 和轻客户端能力边界测试，用来钉死
排除项与逐字节来源集合。

`native/smoldot/pow/Cargo.lock` 从 CitizenApp 已验证 workspace 锁文件机械裁掉全节点与 WASM
成员不可达闭包；所有保留的 registry 包继续使用来源锁中的准确 name/version/checksum，不
引入新身份。SDK 锁文件 SHA-256 为
`6d832fb629bbf19ff6c2cce589c6285c3367cbcb3b55f4819beb7e733d9e038b`。

根 `Cargo.lock` 还会合并 Engine、FFI 与测试启用的 feature。Release 因此从
`citizen-sdk-smoldot-provider → smoldot-light` 离线遍历完整 registry 闭包，同时核对 package
identity、checksum 与直接依赖边；只允许固定的 `bip39`、`futures`、`pbkdf2` feature 合并边，
以及 HTTPS reqwest 引入的 `getrandom`／`rustls-pki-types` 准确附加边。
`unicode-normalization 0.1.25` 必须直接来自 Engine；`web-time 1.1.0` 必须沿 provider →
`reqwest 0.12.28` → `rustls-pki-types 1.15.1` 的真实依赖边引入，二者均校验固定 checksum。
PoW 中存在而根锁缺失的边、未登记的根锁附加边、
版本或 checksum 漂移都会失败关闭。

Release 门禁把 `native/smoldot` 固定为 234 个普通文件的完整闭集：来源清单自身 1 个、清单
五个单元中的来源/适配/SDK-only 文件 225 个，以及以下 8 个单元外支持文件。迁出的 Dart 生产、测试和
来源记录另由跨目录闭集固定。门禁不仅逐文件校验哈希，还反向枚举目录；新增、删除、符号链接
或单字节变化都会失败关闭。

| 支持文件 | 来源分类 | SHA-256 |
|---|---|---|
| `LICENSE` | 与 `citizenapp/smoldot/pow/LICENSE` 逐字节一致 | `aab56b4a581fc1c50b7c782eacf2fc8be05a47cd98e4bf4d836dd9b6dd9c86f4` |
| `LICENSE-APACHE-2.0` | 与 `citizenapp/smoldot/dart/LICENSE` 逐字节一致 | `4524e4d70a6295dfa882b0411cc49fcca03273e959fea68bbfe7df7ed63e7d78` |
| `README.md` | CitizenSDK smoldot 边界说明 | `f64ec4a0c975e338e9acfcf53b3805c4d3db951b97d0701216a20636624369a1` |
| `UPSTREAM.md` | CitizenSDK 上游与本地改动说明 | `e0953f44b2382f50882acbd3d775ec1fe80b60e8a40b3d74e216e638a9a9b16b` |
| `include/README.md` | legacy smoldot 头文件说明 | `06c704f1d46c36bddde762b5973e2ceaf38d63ec3d963948381b3b6070754ec3` |
| `include/smoldot.h` | CitizenApp 头文件删除聊天/OpenMLS 导出后的边界适配 | `f7c2645588809f73f8aa799975b363a4a7b22e8de7149da9d0b4c2ea20c90a20` |
| `pow/demo-chain-specs/polkadot.json` | CitizenApp 逐字节来源；由 `light-base/examples/basic.rs` 编译引用 | `859c8ade8b740e6a106082e0fdb4ae14075d79f8a277f02124bf9856d8a302aa` |
| `pow/demo-chain-specs/polkadot_asset_hub.json` | CitizenApp 逐字节来源；由 `light-base/examples/basic.rs` 编译引用 | `4909f824189edd0c7c64e444f81a4082fe5bc433861a5ac9e8b00838203a35ab` |

## 链资产、轻节点行为与交易

以下两个固定链资产逐字节来自 CitizenApp，并收敛在 CitizenSDK 独立产品目录：

- `assets/citizenchain/chainspec.json`，SHA-256
  `6ae934933682a8ffca78663dd4391a730b6ae219bd12abfb5d96b4d8154fc2e0`；
- `assets/citizenchain/light_sync_state.json`，SHA-256
  `014802836a0f6e01a9f1bf7173b8e04c9df8fc3f057565f855abdccdc7361ab6`。

CitizenSDK 自有 `assets/README.md` 固定随包静态资产与设备运行状态的边界，SHA-256 为
`647c1d957cb16ae179813ef2d54867459286d024a857f8eb72bcd791d59eb5dd`。
`assets/citizenchain/manifest.json` 固定产品、正式 `citizenchain` 链/协议 ID、
genesis hash 和上述两个摘要，SHA-256 为
`73983825dbefac4a74102c80db9913f0ea27ca952eaa110d276ad1c8854835d8`；相邻 README 记录资产
来源与更新门禁，SHA-256 为
`78f2582c48562bb3b65a224362e285121d58e69353677ae72ba5d69235f5871b`。Release 门禁反向枚举
`assets`，只允许根边界说明与 `citizenchain` 四项文件共五个普通文件，并逐文件固定哈希。
运行时会在创建或初始化 smoldot 原生客户端前重算两个摘要和 genesis hash，并核对 checkpoint
state root。仅验证 JSON 可解析、bootnode 数量、区块高度或字段形状不能替代这些检查。

CitizenApp 的轻节点服务、钱包管理器和交易 RPC 耦合产品单例、Isar、导航与业务数据。
SDK 自有协调层已统一到 Rust Core，不保留第二套 Dart 实现，也不声称跨语言代码逐字节相同：

- `native/engine` 承接输入派生、钱包生命周期、故障恢复、账户和交易历史；`native/signer`
  承接 sr25519。冻结派生、密码、余额费用、交易编码和生产 metadata/events 向量集中于
  `test/wallet` 和 `test/transaction`，移动时保持原始数据字节，Rust 直接读取同一份输入。
- `native/smoldot/provider/src/bootstrap.rs` 承接既有 HTTPS 节点建议协议，六秒与 64 KiB 限额，
  只修改内存 bootNodes；固定网络、genesis、state root、SS58 和币种身份，禁止 RPC/checkpoint。
  服务端共享 fixture 的 wire 资产标识保留原值，不是 SDK 文件路径。
- `native/ffi/src/chain_monitor.rs` 调用既有 smoldot finalized 订阅，定期调用 Engine 原子导出，
  不实现网络订阅、共识、P2P 或同步算法。相同已保存准确块不重写；不清理失败数据库。
- 高层转账沿用 20 分钟观察、finalized 后 30 秒执行核验、一秒事件读取重试；已取块体不重复
  下载，超时协作取消并排空已有存储操作，保持 durable Pending/InBlock，不推断链上结果。
- SDK 不包含产品登录、冷钱包、私钥导出、聊天、广场、业务协议或服务器中继。
  来源中会自动删除坏数据库、导出 child 或直接暴露任意 RPC 的入口按已确认安全边界排除，
  不为了复刻不适用入口而绕过正式 ABI。
- `shared/citizen-signer`、`wallet-password`、`hardware-secretvault` 等现有文件被公民钱包
  或公民 App 实际使用，未发现可以独立移出的热钱包专用文件。本轮不改这些独立产品的依赖；
  SDK 无 shared 路径依赖。这里的单源结论限定 SDK 自身，不伪称三产品已共用一套运行实现。

第 4.1/4.2 步 Rust 实现以这些已验证行为和公开夹具为参照，但目标是 CitizenSDK 自有 Core 源码，
不伪装成 CitizenApp 文件的逐字节副本：账户服务从准确 metadata 生成 `System.Account` key，
读取 finalized 余额及同块链上费率；nonce 使用准确 best
`AccountNonceApi_account_nonce` typed snapshot，并由持久同账户 Pending/InBlock single-flight
防止本地复用。钱包服务以
CAS/provisioning/exact cleanup 实现 prepare/commit create、import/add/delete/reconcile，秘密不离开 Rust
buffer。交易构造固定 pallet `4` / call `0`、V4、immortal、tip `0`、CitizenChain genesis 与
同块 runtime；构造对象保持 Engine 私有，唯一钱包 `transfer_with_remark` 先完整持久化
source/destination/amount/remark/nonce、本地 extrinsic hash、完整 signed extrinsic 及构造
block/runtime_version/genesis_hash，确认 pending CAS 成功后才进入
provider。raw submit-and-watch 仅属于无钱包纯链组合，因为 provider watch 本身会广播；组合
任一钱包组件后该入口在 provider 前关闭。终态令牌不可分离地绑定 txHash 与同 index System
结论；finalized 流水拒绝自转，
对 `OnchainTransaction`/`Balances` 双事件精确一对一去重，并以已核验 pending 认领
发送方 outgoing、保留接收方 incoming，同一原始块重放不能恢复已消费 pending。对终态的安全关键核验直接从 provider 读取目标
finalized 块 runtime context；持久 `RuntimeCacheStore` 只是性能层，不是执行证据源。
`sign_wallet_payload` 是受信任宿主的通用业务载荷签名能力；其返回值可被宿主用于高层交易路径
之外，因此来源文档只对 SDK 内建钱包交易路径承诺 pending-before-broadcast。产品 C ABI 已
通过 `citizensdk_sign_wallet_payload` 投影该能力。

host adapter 在 Rust 内生成随机 32 字节 DEK 与随机 nonce，以完整 `SecretRef` 为 AAD 执行
AES-256-GCM；宿主 Vault 只 wrap/unwrap DEK，unwrap 直接写入 Rust-owned 32 字节缓冲区。
高层 `transfer_with_remark` 的 terminal future 使用独立四线程长观察池；取消或中断保留 durable
Pending/InBlock 门，只有 canonical body、准确 metadata 与同 index `System.Events` 形成终态。

交易执行确认使用
`test/transaction/substrate-v14-system-events-metadata.hex` 中的真实 Substrate v14
runtime metadata 快照，SHA-256 为
`95b368e7907511b28ba283a6741f4be551b56fb917c2f0183b4143dbe0ebf95b`。它逐字节来自 CitizenApp
已验证的 full-node 测试夹具，只为测试提供 `System.Event`、`Phase`、`DispatchInfo` 等 SCALE
类型；CitizenSDK 不因此复制、编译或开放全节点出块能力，也不把该夹具作为运行时信任锚。
Release 来源守卫同时固定该夹具哈希，防止测试和测试输入一起漂移后产生伪通过。

Rust Engine 直接复用相邻
`citizenchain-runtime-v14-metadata.hex` 与 `citizenchain-runtime-system-events.hex` 两份
生产 CitizenChain 成对夹具，核对成功 index 0 与 `BadOrigin` 失败 index 1。它不复制第二份
metadata/events；正式 Rust 测试对同一冻结生产输入核对行为。两份文件的来源、生成方式和
固定 SHA-256 继续以 `test/transaction/README.md` 为准。

第 4.1 步另增加两份公开 JSON 行为向量：

- `citizenchain-transfer-build-v1.json`（SHA-256
  `c43a1f01c22556d2b1e172088fb540358c25b9554c91ffc71f7b483fcd5a469b`）记录 schema、CitizenApp
  `transfer_with_remark`/immortal V4 行为来源、生产 metadata 文件名、正式 network/genesis、
  best runtime/nonce、source/destination/amount/remark、公开钱包向量签名，以及期望
  call data、signing message、完整 signed extrinsic。签名来自公开钱包夹具账户0，不含生产
  秘密。
- `citizenchain-balance-fee-v1.json`（SHA-256
  `2cd5e648703c8cc389c59f07753470b63c034f7cfa63dac8ffa596c8128a0033`）记录 CitizenApp finalized
  `System.Account` 与 metadata fee 行为来源、正式 network/genesis、AccountId/storage key、
  finalized AccountInfo/free/reserved/total、缺失/短值为零语义，以及同一 best 块的 fee rate、
  minimum fee、existential deposit、minimum self-pay 与舍入估算表。

两份 JSON 是 CitizenSDK 对已验证行为的自有向量，不宣称为 CitizenApp 文件逐字节副本，也不
是运行时链状态真源；它们与生产 runtime metadata 和公开 wallet vector 共同约束实现。

CitizenServe 的 `/chain/citizensdk/bootstrap` 使用逐字段投影生成 SDK 独立 wire schema，不把
CitizenApp 的 `chain_name`、`chain_type`、`bootnodes_source` 或产品服务字段泄漏给 exact
parser。服务端测试与 SDK 客户端测试共同读取
`test/node/citizensdk_bootstrap_manifest.json`，分别验证服务端输出和客户端解析，且该夹具
进入 Release 测试源码闭集；它只用于跨端合同，不是运行时链状态真源。

钱包派生合同另外逐值收编 CitizenApp/CitizenWallet 已共同验证的 `//0`、`//1`、`//2`
child mini-secret、AccountId、SS58 与非空 password 金标，并用 `polkadart_keyring` 作外部
Substrate URI 派生参照。password 测试保留共享真源的 6/30 边界、30/31 拒绝、NFKD、空白、
换行、emoji、全角、韩文和西里尔字符边界；仅产品 UI 风险确认框不属于 SDK 密码学测试。
Rust `wallet_derivation` 复用同一金标与边界，并将助记词、master/child mini-secret、NFKD password
临时值保持在 `SecretBuffer`/`Zeroizing`；`bip39` 显式启用 `zeroize`，公开 Rust 服务不提供
child 私钥导出。

## 移动硬件金库与 Apple 状态仓储

Android/Apple 安全语义最初参考 `shared/hardware-secretvault` 与 CitizenApp 稳定装配，但
CitizenSDK 当前平台适配源码位于自己的 `android/` 与共享 `darwin/`，不是逐文件副本，也不
运行时依赖 shared：

- Android：StrongBox/TEE RSA-OAEP KEK、逐次强生物识别、typed stores 与 SDK-owned
  `FLAG_SECURE` Activity。
- Apple：Secure Enclave EC KEK、`biometryCurrentSet + privateKeyUsage`、
  `WhenUnlockedThisDeviceOnly`，以及分离的 typed public/secure SQLite。Secure Enclave 只
  wrap/unwrap 随机 DEK，不执行 sr25519；iOS 模拟器变体没有对应硬件钱包能力。
- Security framework 解封返回的不可变 `CFData` 只在对应 `autoreleasepool` 内短暂存活；桥接层
  避免生成 Swift `Data`/COW 副本，在不能可靠原地清零的边界下立即把精确 32 字节复制到
  Rust-owned buffer，并由 pool 排空释放；Rust-owned 输出在使用后清零。SDK-owned wallet UI
  会在流程终态前由文本控件和短期 Swift `String` 持有恢复词/
  password；终态 best-effort 清空控件与 Rust buffer，但 Swift `String` 不可可靠擦除。这些值
  不得返回 public Swift API、记录、持久化或进入 Flutter；child mini-secret/private key 始终留在 Rust。
- 两端的产品、别名和 AAD 固定为 `citizensdk`，不包含 CitizenApp 别名读取、转换或删除分支。

## Apple 共享源码投影

`darwin/` 是 CitizenSDK 自有 Apple 权威源码，不从任何旧 Apple 平台目录或 CitizenApp 运行时取文件。
`Sources/CitizenSDK` 实现公开 Swift facade、70 符号产品 ABI codec、生命周期与事件、五类 typed
store、分离的 public/secure SQLite、KEK-only `SecretVault`、敏感 buffer、prepared wallet 与
SDK-owned iOS/macOS wallet flow；`Sources/CitizenSDKFlutter` 只实现统一 36 方法 tuple、单一
EventChannel router、session/事件收口和 wallet-flow bridge，不包含第二份 Engine 或秘密通道。

统一原生入口把 `Sources/CitizenSDK`、根产品头、Rust Core、Privacy Manifest 与链资产编成
`CitizenSDK.xcframework`，只允许 iOS 设备与模拟器变体和 macOS 三个 Apple `arm64` machine
slice。Flutter adapter 由 `darwin/citizen_sdk.podspec` 编译并消费该框架；Swift Package 同样只
引用该二进制产品。iOS 与 macOS 在根 pubspec 共用 `sharedDarwinSource: true`，因此没有两份
Apple 插件源码真源。legacy macOS `arm64` `libsmoldot.dylib` 仅用于源码树外差分测试，不能进入框架或
候选。公开平台名只记录 `iOS` 与 `macOS`；iOS 设备和模拟器是同一平台的技术变体。
`aarch64-apple-ios`、`aarch64-apple-ios-sim`、`aarch64-apple-darwin` 是编译 target，不是
产品名或 macOS 后缀。

iOS 设备与模拟器变体使用浅层 framework，install ID 均为
`@rpath/CitizenSDK.framework/CitizenSDK`。macOS 使用标准 `Versions/A` framework，install ID
为 `@rpath/CitizenSDK.framework/Versions/A/CitizenSDK`。Release 归档只允许并保留 macOS
framework 的精确五个标准内部相对符号链接：`Versions/Current -> A`，以及根
`CitizenSDK`、`Headers`、`Modules`、`Resources` 指向 `Versions/Current/...`；其他任何
符号链接均拒绝。Android Gradle/Kotlin persistent project state 只属于 TataConsole 中央
work directory，源码与候选禁止 `android/.kotlin`。

Apple 生产绑定的关闭语义也属于 CitizenSDK 自有源码：显式 ABI +1 retain lease 保护
Core 借用的 HostBridge/callback/store/vault context；关闭从 monitor stop、callback clear 到
destroy-only/closed 单调前进；未收口 facade 整体交给进程级 supervisor。C callback 只
入队而不在回调线程重入 Core。Flutter detach 先撤销两类 handler、废弃 epoch、清空 sink，
然后先取消所有 session 未完工作再等待关闭；iOS 使用 published plugin 的正式 detach
callback，macOS 使用同一幂等显式入口和最终 deinit fallback。

本轮本机已编译 iOS 设备与模拟器变体两组测试 bundle；因本机无 Simulator runtime，
没有声称 iOS XCTest 已运行。macOS 已运行 Core 50 项和 Flutter adapter 22 项 XCTest，
0 失败、1 项真机硬件用例跳过；最终 normal/supervisor smoke 通过。本机无真实 Apple
移动设备，不声称 Secure Enclave、生物认证或 device-only Keychain 已验收。

真实 Flutter consumer 已完成 Android release APK（ABI `arm64-v8a`）、iOS device Release no-codesign、
iOS 模拟器变体（Rust target `aarch64-apple-ios-sim`）编译和 macOS Release 构建；没有移动真机或 Simulator runtime
运行声明。Flutter 对插件 Swift Package Manager 目录的未来识别警告和 Android built-in
Kotlin 迁移提示延后到第 9 步 Hosted/Flutter 集成处理，不在第 6 步引入第二套投影。

## Linux 自有 Host 与 Flutter 投影

`linux/` 是 CitizenSDK 自有 LinuxARM/LinuxAMD Host 源码，不从 CitizenApp、Android、Darwin
或另一个仓库运行时读取文件。它复用的是根产品 C ABI 的语义，不是把 Apple/Kotlin 代码机械
翻译成第二份 Engine：HostBridge、typed SQLite、TPM 2.0 Vault、SDK-owned GTK 钱包流程和
header-only C++ facade 都位于 CitizenSDK 权威目录；链、Runtime、钱包状态机、sr25519 和交易
继续只有 Rust Core 一份真源。

第 7.2 步在同一 `linux/` 权威目录实现 Flutter codec、sessions、wallet-flow bridge、environment
和 plugin。它按根 Dart tuple 及 Android/Darwin 已验证装配合同做平台适配，但不复制三端
源码作为运行依赖，也不复制 Core 行为。Linux 新增生产/测试文件全部进入既有 Release 来源
哈希与目录反向闭集；第 8.2 步后当时的 22 方法表由 Node 来源合同逐项对拍，第3步为 26 方法，第4步当前统一为 36 方法。

Linux store 的 openat SQLite VFS、精确 schema/PRAGMA/commit 合同，Host admission lease 与
无损早完成路由，Vault retirement 条件写/长提示后重验，GTK parent 销毁退休，以及 TPM child
public-template、owner/hierarchy/DA 状态与准确 `Esys_TestParms` 参数探测都是该 Host 自有源码
的一部分。它们不应复制进 Core，也不能以
Android/Apple 适配源码作为运行时依赖。

第 7.1 步没有把 TPM2-TSS、SQLite、GTK 或 C++ runtime 的第三方源码/二进制复制进仓库，
也没有生成 Linux `.so`。这些依赖的最终锁定来源、版本、链接方式、许可证和可重分发闭包必须
由后续统一 GitHub CI/Release 的真实 Linux 构建产物反向得出；不能用设计文档或本机 macOS
编译结果臆测替代。Linux Host 自有源码适用根 MIT
许可证，外部依赖仍适用各自许可证。

第 7.1/7.2 步新增的 `linux/test` 是对应 Host/Flutter adapter 的 canonical 合同测试源码，覆盖同一 ABI/Host
语义和 Linux 专属 store/TPM/UI 边界。该步没有执行这些测试，未验证 LinuxARM/LinuxAMD，
也未修改 Flutter/Hosted 公开平台声明。第 7.2 步同样只写测试源码并执行 Node 来源合同；
源码同步若改变根 ABI 或 Rust envelope/schema，必须
同时更新 Linux Host、测试、本文和 `LINUX_PLATFORM.md`，禁止以平台适配文件反向覆盖 Core
真源。

第 7.3 步的四个消费者输入位于既有 `linux/test/`：`CitizenSDKConsumer.cmake`、
`citizen_sdk_c_consumer.c`、`citizen_sdk_cpp_consumer.cc`、`citizen_sdk_flutter_consumer.dart`。
它们是 SDK 自有验收源码，不是新的绑定、协议或 Core；与修改后的测试 CMake 一起进入既有
测试哈希闭集。安装和临时 Flutter 工程仍由唯一 `scripts/build-native.sh` 装配，不增加工作流。
第 7.4 步原把两种单平台 19 项安装件合并为 26 项；第4步加入共享 QR 图像头后，当前是唯一候选 `linux/` 下的 27 项：根 C ABI 与 7 个
Host/C++ 头、3 个 CitizenChain 资产的重叠必须字节一致；每个平台的双库及 5 项 CMake 包
配置分别隔离。源码树仍只保存 canonical 输入，准确生成投影只在中央候选中存在。
Hosted 精确保留 39 项 Linux 运行输入，即 27 项安装件加 `CMakeLists.txt`、
`cmake/CitizenSDKFlutter.cmake`、5 个 plugin `.cc`、4 个内部 `.hpp` 和 Flutter 注册头。
原生 Host 私有源码、测试和构建模板仍只用于 GitHub 审计闭集，不进入 Hosted。
同轮同步官方 `linux` 注册与默认 `CitizenSdk.open()`；真实 Flutter 消费者不注入内部 platform、
不临时改写 pubspec，也不由 runner 补充 plugin 的 `$ORIGIN`。这些是候选源码合同，不是
Linux 运行或正式发布结果；真实同版产物、依赖与许可证证据不齐不得生成可分发候选。
当前开发以本机 macOS 编译通过为验收标准；2026-09-03 已通过既有 `abi-host` 与 `apple`。
前者验证 Core/C ABI 和 C11/C++17 头，后者完成 iOS 设备、iOS 模拟器及 macOS 的 Swift/Flutter
原生绑定编译和单一 XCFramework 验证；第 7.3 步该轮没有运行平台 XCTest，也没有修改生产实现。
不再等待用户提供 Linux/TPM 环境。跨平台构建与功能验证后续统一进入 GitHub CI/Release，CI 使用
增量缓存，Release 使用全量构建，保持同一 Core commit、SDK 版本、ABI 版本和一个 CitizenSDK
Release，不拆分平台产品或另建流程。
后续 Linux 测试使用的 Flutter 工具和 Dart Hosted 缓存必须来源明确且预先备齐，只能在获准的
中央临时目录内产生工具状态；缺失时失败，不自动下载。静态依赖实际版本、许可证、GTK/TPM
及两种 Linux 运行事实由该统一验证分项记录；目前尚未运行，Node 来源合同与 macOS 编译均不能
证明这些外部运行事实，也不能把 Linux 源码注册写成已正式发布。

## 锁文件与测试收编

CitizenSDK 的受控依赖输入包括：

```text
pubspec.lock
Cargo.lock
native/smoldot/ffi/Cargo.lock
native/smoldot/pow/Cargo.lock
```

唯一根 Dart 包、contracts/engine/ffi/signer/provider 根 workspace、legacy FFI、PoW workspace 都在 CI/Release
使用 locked/enforce-lockfile 模式。`docs/smoldot-dart/source-pubspec.lock` 只保存来源事实，
不参与解析。锁文件属于源码输入，
不是编译产物。Release 还反向固定 Dart/Android/Darwin 生产源码、root/native/平台测试与产品
文档；第 7.1 步再把 Linux Host、Linux 合同测试与 Linux 文档加入对应源码闭集。新增、删除、
单字节漂移或候选混入未登记平台文件都会失败。Release 还逐字节固定根 `Cargo.lock`（当前 SHA-256
`338e8db350d4c5abf9bdcbd9cc067a35f8c77bbe6eafcd125335b5eedaed8b32`）和根
`pubspec.lock`（SHA-256
`892803b0312a36b83f6015e0c9bd26b7fe8d4912bf15d27175b6db11552f8563`）；其中根 Cargo 锁是
CitizenSDK contracts、engine、ffi、signer、provider 统一 workspace 的已审查解析闭包，不
宣称与 CitizenApp 整份锁逐字节相同。当前闭包的密码学核心 `schnorrkel 0.11.5`、
`zeroize 1.9.0` 与已验证来源一致，异步合同统一使用 futures `0.3.34` family。contracts 直接
固定 `bs58 0.5.1` 和 `blake2 0.10.6` 以生成规范 Citizen SS58；engine 的
`subxt-core 0.43.0` 和其 SCALE/metadata 闭包也由该锁固定，该闭包另含 `base58 0.2.0`。
第 4.1 步钱包闭包还固定 `bip39 2.2.2`、`getrandom 0.2.17`、`hmac 0.12.1`、
`pbkdf2 0.12.2`、`sha2 0.10.9`、`unicode-normalization 0.1.25` 与
`unicode-segmentation 1.13.3`；`bip39` 的 `zeroize` feature 属于该已锁依赖闭包的必选语义。
Provider 的递归 smoldot registry name/version/checksum 另外必须与
`native/smoldot/pow/Cargo.lock` 完全一致，根锁不能静默选择另一组“可兼容”版本。
任何依赖升级都必须显式更新哈希与合同测试。
Hosted 候选的 Dart 运行闭包是 18 个普通文件：根 `lib/citizen_sdk.dart`、`lib/src/api`
七个文件、`lib/src/crypto/account_codec.dart`、`lib/src/models` 五个文件和 `lib/src/platform`
四个正式 transport 文件。Release 必须双向核对该闭包，任何 legacy node/smoldot/wallet/
transaction/Preferences 文件进入 Hosted 都是失败。
Release 对 `native/signer` 做 10 个普通文件的逐字节哈希与反向闭集检查；crate 清单、两份
说明、三个生产 `src/*.rs` 和四份合同测试缺一不可，额外 `build.rs`、`src/bin` 或其它文件也
必须失败关闭。

测试来源分三类：上游/CitizenApp 逐字节夹具与内联测试、迁入根套件的 Dart smoldot 测试、
CitizenSDK 新增的来源闭集/能力边界/平台/钱包/轻节点/交易/发布合同测试。文档只记录测试
来源和职责；实际通过数量必须由对应提交的执行报告产生，不能由文件数量或历史候选推断。

Release 反向固定的 SDK 自有测试源码包括根 Dart/smoldot、contracts/engine/ffi/signer/provider、
Android Flutter host、Android native JVM/instrumentation、Darwin Swift/Flutter 与
`scripts/release.test.mjs`。
第 5.2 步 Android 根测试固定 tuple codec、session/orphan 生命周期和 SDK-owned wallet flow；
native 测试固定 Java/Kotlin facade、JNI ABI、typed stores、硬件金库、Activity 秘密边界与取消。
第 6 步 Darwin 闭集要求覆盖共享 Swift/Flutter adapter、typed public/secure SQLite、Apple Vault、
SDK-owned wallet flow、iOS 模拟器 XCTest 与三个 Apple XCFramework slice。
旧 `HardwareSecretVaultTest.kt`/`VaultEnvelopeTest.kt` 根插件测试已经删除，不能重新作为第二套
金库实现进入闭集。文件闭集与运行时测试数量是两项不同合同，均必须满足。

当前完整测试执行合同由根 Flutter 包一次发现并执行全部根测试和已经迁入的 smoldot Dart
测试，不把历史的 230 项与 51 项冻结成当前数量门禁；统一使用
`flutter test --timeout=2m`，不能以默认外层超时截断其中的 30 秒活链订阅窗口。第 2 步隔离
副本实际执行结果为 288/288。Android/Apple 平台合同
还必须在临时宿主中真实运行
Android `:citizen_sdk:testDebugUnitTest` JUnit 与 iOS 模拟器 XCTest；只编译
插件、发现测试或生成测试报告都不能替代执行。上述数量和命令描述测试套件合同，不是尚未完成
的某次最终验收结果。本轮 Apple 执行记录是：iOS 设备与模拟器变体两组测试 bundle
编译通过；本机无 Simulator runtime，因此未执行 iOS XCTest；macOS Core 50 项与 Flutter
adapter 22 项 XCTest 0 失败，1 项真机硬件用例跳过；normal/supervisor smoke 通过。
TataConsole Flow 已集成 Apple/Hosted 与五平台 Release 闭集；本轮仅执行本机闭集，
没有运行远程 CI、正式 Release、Hosted 上传或 Git。

本轮完整本机闭集还包括：Android AAR 构建通过；Apple 单一 XCFramework 的 iOS 设备与
模拟器变体及 macOS 三个 Apple `arm64` machine slice 构建通过；Hosted 17 文件分析 0 问题；完整
Dart 316/316（`--timeout=2m`）；根 Rust 285/285、compile-fail 文档测试 1/1、Clippy 与
格式检查；Android 原生 Kotlin/Java 单元测试 Gradle 17 个 task 成功。

2026-08-29 包边界重构前的 TataConsole `.work` 隔离快照已实际通过根 Flutter
230/230、独立 smoldot Dart 51/51、钱包定向 88/88、交易定向 85/85、signer Rust 6/6、
FFI Rust 5/5、PoW Rust 290/290（另有 3 项上游 ignored、14 个 benchmark 目标成功）、
Android JUnit 3/3、Release 合同 18/18、TataConsole 99/99 与统一数据字典定向合同 2/2；
这些历史结果不冒充本次目录重构后的验证结论。
当时 Android 最终冻结副本与产品真源逐字节目录比较无差异，生成的历史 CitizenSDK AAR 只包含
`arm64-v8a/libsmoldot.so`。iOS 设备 Release App 与 iOS 模拟器测试包（Apple machine value
均为 `arm64`）均完成
编译链接并保留全部 25 个轻节点/sr25519 导出符号；设备与 Simulator 静态归档各有 397 个
可解析 Mach-O 对象，最低系统版本全部不高于 iOS 16.0。本机没有 Simulator runtime，故
没有把 2 项 XCTest 记为本地执行通过。以上全部是改接产品 ABI 前的历史结果，不证明第 5.2
步 Android 双库/AAR 或当前源码已通过；正式 workflow 仍须在准确提交上重新执行。

## 同步流程

1. 选定 CitizenApp 稳定提交和 smoldot 上游基线。
2. 在临时目录生成来源/目标文件闭集、差异与哈希，先核对明确排除项。
3. 逐字节更新来源快照；产品适配文件单独审查，不把适配伪装成上游原文。
4. 同步锁文件、许可证、来源 manifest 和全部相关测试。
5. 在源码树外执行根/嵌套 Dart、三个 Rust workspace、平台原生构建和候选反向验证。
6. 更新本文件的基线提交、排除清单与必要哈希；不得把临时 patch 或构建产物留在 SDK。

任何同步都不得在 CI/Release 时回指 CitizenApp，也不得让一个产品静默覆盖另一个产品的
权威源码。

## Windows 原生 Host 来源与差异（第 8.1 步）

本轮原有 Core/FFI、Engine、signer、smoldot、链资产保持字节不变。平台无关 C++ 包装、
HostRecord、输入上限、Lifecycle、RecordKey、PublicStore、钱包 validation 和流程来自已审查
Linux Host，保留算法并迁移相应测试，平台无关部分仅调整内部 namespace/guard/平台注释。
Operation 同源，但本机 C++ 测试揭示不能依赖 `std::function` 移动后必为空；Windows 改为与
空对象 `swap`，并补测试的直接头依赖。Windows SQLite 的结构闭集改用 `GLOB 'sqlite_*'`
精确识别系统前缀，不能沿用把下划线当通配符的 `LIKE`。第 8.1 步没有反向修改 Linux；
用户另行确认的第 8.1.1 步已将三项必要修正应用到 Linux，并补初始化、既有库和重入测试。
两平台的这些修正是明确登记的 SDK 实现修正，不能写成仍与原始 Linux 基线逐字节一致。
不能称作逐字节复制的必要差异：HWND 和 UTF-8 path、UI 退休握手、Win32 安全输入、
SecureZeroMemory、HANDLE/ACL/SQLite VFS、PCP 持久 KEK 引用与跨实例串行化、MSVC CMake。
唯一 release.mjs 固定新源码、注释、测试与文档闭集；没有新链、交易或签名实现。Windows
仍未实际编译/运行/发布，来源检查和 macOS 编译不能替代平台证据。

## Windows Flutter adapter 来源与差异（第 8.2 步）

统一双通道、36 方法、tuple 语义、公开结果与事件映射沿用现有绑定合同；Windows codec
的请求语义与 Linux 对应段逐段核对，不把平台迁移写成重新设计链或钱包。Windows 使用
官方 EncodableValue 与 StandardMethodCodec，删除 Linux GLib 专用的字符串表示适配。
官方解码前增加有界标准 wire 预检，拒绝截断、尾随及资源超限，但仍由官方 codec 产生
MethodCall；这是明确登记的 Windows 输入安全适配，不改固定方法或合法 tuple 语义。
会话与钱包流程沿用既有所有权规则，增加 Windows Host 已释放 Core、仍等待原生 UI 退休
时的关闭重试守门；初次缺少 Core 或非法生命周期不被放行。这些明确的平台适配差异不能
宣称整个新文件与 Linux 逐字节一致。

环境解析、Win32 UI 队列、官方 BinaryMessenger 注册、BCryptGenRandom 和 MSVC CMake 是
Windows 适配源码，不是上游原文。适配器只连接已安装 Host/Core、调用现有安全钱包 UI，
不包含 Host 私有实现、不重编译密码学或轻节点。原生 Host、Rust/Core/FFI、signer、smoldot、
链资产、Dart .dart 文件和原生构建器均不在本步修改。
Windows 生产来源闭集由 51 增至 62 文件，测试输入由 17 增至 24 文件；新增六项 adapter
测试和一个共享 helper。唯一 release.mjs 同时固定五份绑定与所有获准来源摘要；Windows
默认入口、Hosted 注册与候选投影在第 8.4 步接入；实际平台执行仍留统一 GitHub 验收。

## 本机发布器路径门禁（第 8.2.1 步）

唯一发布器改用中央 `target/GMB/citizensdk/SDK` 与 `target/.work/GMB/citizensdk/SDK`
两个固定永久根，仅接受严格子路径；只核验命中根，不改 GitHub 隔离分支。回归测试提取
生产校验函数原文，在有限文件状态中执行，不复制算法或增加生产测试入口；既有真实
磁盘链接与完整打包测试保留。本步仅修改发布器、其测试和五份 SDK 文档，逐文件来源摘要
同步固定；原生构建器、Core/FFI、钱包、签名、轻节点、各平台实现和候选内容均不变。

## Windows 已安装 C/C++ 消费者（第 8.3 步）

新增两份消费者及独立 CMake 输入，Windows 测试闭集由 24 增至 27，整个 SDK 自有测试
闭集由 192 增至 195。消费者仅使用现有公开 C/C++ API 与已安装同版库；生命周期和结果
所有权沿用现有合同，Windows 路径、等待和 DLL 来源检查使用系统 API，不新增链算法。
唯一原生构建器原增加 21 项安装闭集；第4步加入 QR 图像头后当前为 22 项。保留 14 项原生 CTest，再验证两个
安装消费者，全部成功后才导出全新安装目标。Node 合成安装和 PE 输入测试校验逻辑，
不能作为 Windows 编译、Win32、TPM 或钱包运行证据。

本步不修改 Host/Core/FFI、签名、钱包、轻节点、链资产、Dart 入口或其它平台实现；根
Hosted 与候选当时不开放 Windows，后续接入见第 8.4 步。文档、测试及唯一发布器中的
来源摘要同步固定。

## Windows 正式入口与运行投影（第 8.4 步）

唯一 CitizenSdk 默认平台与 pubspec 官方 Windows 注册一起接入。新 Flutter 消费者沿用
既有公开生命周期、事件、能力和关闭合同，按 Windows Release 环境检查；不复制 Linux
XDG/GTK 路径，不注入内部平台或变更 SDK 副本。Windows 测试输入由 27 增至 28 文件，
SDK 自有测试合同由 195 增至 196，Windows 原有 62 份生产源码不新增算法。

同一发布器当前验证并复制 22 项安装件，七个重叠 Host 头必须与来源相同，其它项精确注入。
Hosted 只保留 34 项 Windows 运行输入，不带入 Host 私有实现；正式候选共享同一 SDK
版本、ABI 和平台集合。PE/COFF、导出/依赖和 CMake/资产结构检查不能证明二进制来自某个
commit，构建来源、许可证和真实 Windows 行为仍由后续统一 CI/Release 提供。

唯一构建器保留 14+2 检查并连接既有六项 adapter CTest 与真实公开 Flutter Release 消费者。
本步不修改 Core、Host、签名、轻节点、链资产或其它平台实现；没有新构建/发布流程。
源码、测试、文档与摘要同一步同步；本机 macOS 与合成夹具不冒称 Windows 实测。

## 官方 Hosted 归档与完整验真（第 9.1 步）

`release.mjs` 的新 Hosted 编排、完整闭集和有界 gzip/tar 校验是 CitizenSDK 自有安全适配，
不是公民链算法移植，也不宣称是 Pub 源码逐字节复制。旧审计候选/归档反向校验保持不变；
不改 `.pubignore`、Core/ABI、平台实现、链资产、钱包或 signer。

依据 Dart 3.12.2 `DEPS`，固定 Pub 来源 revision 为
`74408212b5348003381bc63f3b59274aaa23cfa3`，tar 来源 revision 为
`13479f7c2a18f499e840ad470cfcca8c579f6909`。核对官方 `lish.dart` 的独立 dry-run/local-archive
分支、`io.dart` 的链接展开和权限，以及 tar writer 的 GNU 长名、版本字段和终止记录后，
通过实际官方工具往返验证，而不是只验证自行构造的 tar。版本锁定不等于第三方工具二进制
供应链签名认证；后续统一流程仍须提供自己的受信任工具来源。

来源投影逐路径/类型/模式/字节对应同一候选；Apple convenience links 在审计归档保留身份，
在 Hosted 按已验真目标展开。格式夹具覆盖六个公开平台标签，不能作为真实库构建来源或
体积证明；真实 macOS 安装消费与统一全平台正式产物验证仍未由本步完成。

本机测试在只允许中央工作根写入的外部 sandbox 中执行，额外拒绝 Git 执行、用户 Pub cache
和 Dart 配置/凭据读取；隔离缓存只复制已有 lock 所列依赖及对应 hash 记录，不复制凭据。
未执行原生编译、Hosted 上传、远程 CI/Release、Git 或控制台操作。源码闭集、摘要、准确
成绩和独占临时目录清理记录统一见中央任务卡第 34 节。

## macOS 公开包消费者来源（第 9.2 步本机开发验收完成）

`darwin/Tests/citizen_sdk_flutter_consumer.dart` 从已有 Windows 公开消费者最小适配，
保留同一 CitizenSdk API、Release 真条件、事件/关闭合同和超时，改为 macOS 平台判断与
准确宿主隔离说明。它是测试输入，不进入 Hosted 运行包，不修改 Core、ABI 或绑定。
自有测试来源闭集因此由 196 增至 197；完整候选仍保持一个 SDK 版本和平台集合。

本机真实 Apple 构建、混合格式件的本地测试候选、官方 Hosted 编码和真实 macOS Flutter
运行是不同证据，必须分别记录。既有 Apple Swift smoke 和内部源码测试不是这次正式
Flutter 安装的证明；失败或等待授权时不能写为通过。具体成绩及工具/状态隔离见中央
任务卡第 35 节；没有授权修改 Flutter 官方启动脚本、宿主生产 SDK 或其它平台源码。
用户已确认将实际 Flutter macOS 安装运行移交第 10 步 GitHub 统一 CI，本机保留已通过
的 Apple 原生编译和包合同。原 Xcode/SwiftPM 权限失败仍为失败；范围调整不产生新的
运行成功证据，也不把其它平台格式件升级为真实件或正式发布包。
