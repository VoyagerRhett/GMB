# CitizenSDK Linux 平台合同

扫码窗口由 SDK Host 提供。GStreamer 仅用于设备发现、采集和像素转换，ZXing-C++ 是唯一
二维码识别及生成实现；链调用解析、审阅与签名仍进入 Rust Core。
系统保留 Debian 11 / GLIBC 2.31 基线，使用 GStreamer 1.18 或更高版本、base/good 插件，
不强制提升到新系统。构建需要对应开发包，运行需要相机设备访问权和平台插件；缺少时明确报错。

当前将六模块按统一 Rust 规则装配；钱包管理与签名互不隐式启用，history 和 qr 独立。
签名模块仅使用同一宿主已有 SDK 安全账户与金库，首次 provision 仍须钱包流程。
运行时模块选择不裁剪现有 full 包或链资产。模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

本文固定 CitizenSDK 第 7 步的 LinuxARM、LinuxAMD 平台投影。Linux 平台不会复制或改写
CitizenChain 轻节点、钱包、sr25519、Runtime 或交易实现；它只把根目录当前声明的 121 个
`citizensdk_*` 产品 C ABI 与宿主操作系统能力组合起来。

Linux 错误对象与 Flutter 七项错误 tuple 投影相同的 22 类 code、八类 failure stage、
公开 method 和可选 session/request 关联。Core 异步失败的 stage 只经结果 getter 取得，
不得解析诊断文本；Host 本地同步错误按固定 code→stage 表分类。

## 当前状态

第 7.1 步新增 Linux C/C++ Host、typed stores、TPM 2.0 Vault 和 SDK-owned 钱包流程源码；
第 7.2 步新增复用它们的 Flutter adapter 与合同测试源码，第 7.4 步原子纳入统一候选。当前：

- 根 `pubspec.yaml` 已以官方 `linux`、`CitizenSdkPlugin` 注册插件，默认 `CitizenSdk.open()` 直接使用该绑定；
- LinuxARM、LinuxAMD 已纳入同版本候选 manifest 合同，Hosted 运行闭集与之同步；
- 尚未生成或注入任何 `.so`；
- 尚未运行 Linux 编译、CTest、远程 CI、Release、Hosted 上传或 Git；已完成的 Node 来源合同与脚本语法检查不代表 Linux 运行通过；
- 因而不能把 LinuxARM、LinuxAMD 描述为已经交付的平台。

第 7.2 步的 adapter 已纳入第 7.4 步公开入口；第 7.3 步已补齐安装后 C/C++、Flutter 消费者与唯一构建器
装配源码。当前开发以本机 macOS 编译通过为验收标准；2026-09-03 已通过既有 `abi-host` 与
`apple`，不再等待用户提供 Linux/TPM 环境。跨平台构建与功能验证后续统一进入 GitHub CI/Release：
CI 使用增量缓存，Release 使用全量构建，保持同一 Core commit、SDK 版本、ABI 版本和一个
CitizenSDK Release，不增加平台独立产品或第二套流程。
两种 Linux 机器目标的编译、测试、ELF/ABI 和硬件验收仍未执行；macOS 编译不能替代这些运行
证据。候选投影、pubspec 和默认入口已在第 7.4 步同步修改，后续由统一 CI/Release 检查；
正式发布必须取得真实证据，不把源码注册当作 Linux 已运行或正式交付。

## 平台与工具链

公开平台名称严格限定为：

| 平台 | GNU target triple | ELF machine | 后续统一 CI/Release 验证 |
|---|---|---|---|
| LinuxARM | `aarch64-unknown-linux-gnu` | ELF64 AArch64 | 待构建与验证 |
| LinuxAMD | `x86_64-unknown-linux-gnu` | ELF64 x86-64 | 待构建与验证 |

target triple、ELF machine 和 `CMAKE_SYSTEM_PROCESSOR` 是工具链机器值，不是产品名。目录、
manifest 和面向用户的 API 只能使用 `LinuxARM` 或 `LinuxAMD`，不得从机器字段派生额外平台
名称。Flutter 官方平台源码目录仍按工具约定使用小写 `linux/`。

首版基线是 glibc 2.31；不包含 i386、armhf、musl、riscv64、ppc64 或 s390x。候选验证必须
检查每个动态符号所需的最高 GLIBC version 不超过该基线，而不能只读取构建镜像名称。
Host 与合同测试固定标准 C++17、关闭 GNU C++ 扩展，避免扩展模式的 `linux` 预定义宏改写
内部命名空间；官方工具链 target triple 保持原值。

## 分层与产物

```text
C/C++ App ───────────┐
                     ├── CitizenSDK::Host
Flutter App           │       │
  └─ Linux plugin ────┘       ▼
                     libcitizensdk_host.so
                              │
                              ▼
                       libcitizensdk.so
                              │
                              ▼
                     CitizenSDK Rust Core
```

- `libcitizensdk.so` 是唯一 Rust Core，必须精确导出根产品头声明的114个符号及SDK内部查看的4个链接符号，私有声明不安装。
- `libcitizensdk_host.so` 只实现 HostBridge、typed stores、TPM/认证、SDK-owned 钱包 UI 和
  生命周期装配；不得包含第二份 smoldot、signer、Engine 或 Core 导出。
- CMake 公开导入目标固定为 `CitizenSDK::Core` 和 `CitizenSDK::Host`。
- C++ convenience API 是根 C ABI 上的 header-only RAII 包装；CitizenSDK 不承诺跨编译器的
  C++ 二进制 ABI。
- 第 7.2 步的 Flutter 动态库名固定为 `libcitizen_sdk_plugin.so`，只依赖 Host，不直接复制
  或静态链接第二份 Core。

第 7.4 步统一候选合同的运行库路径为（源码目录不生成运行库）：

```text
linux/lib/LinuxARM/libcitizensdk.so
linux/lib/LinuxARM/libcitizensdk_host.so
linux/lib/LinuxAMD/libcitizensdk.so
linux/lib/LinuxAMD/libcitizensdk_host.so
```

两种平台各 20 项安装投影合并为 27 项：`include/` 下根 C ABI 2 头、QR 图像头与 7 个 Host/C++ 头、
`share/citizensdk/citizenchain/` 的 3 项资产只保留一份；重叠文件必须逐字节一致。每个平台
`lib/<平台>/` 内保留 Core/Host 双库及 `cmake/CitizenSDK/` 的 5 项配置，不能跨平台覆盖。
Hosted Linux 精确为上述 27 项加 12 项 plugin 输入：`CMakeLists.txt`、
`cmake/CitizenSDKFlutter.cmake`、5 个 `.cc`、4 个内部 `.hpp` 和 `citizen_sdk_plugin.h`。
Host 私有实现、测试、文档与原生构建模板只进入源码审计闭集，不进入 Hosted 运行包。
源码校验继续拒绝生成库；只有候选校验准入准确安装投影。缺件、错版本、重叠字节漂移
即拒绝候选。正式分发还要求真实依赖、许可证、构建来源和平台运行证据；这些留后续统一
CI/Release，不能只凭 ELF 结构、头文件或版本声明视为已取得。

这些运行库由发布构造器从源码树外注入；`/Users/rhett/GMB/citizensdk` 永远不保存生成的
`.so`、CMake cache、`build/` 或 `target/`。本机 CitizenSDK 生成状态只能进入
`/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk` 下由任务独占的工作目录；GitHub runner 使用
统一工作流的 checkout 外独占目录，不照搬本机绝对路径。
Linux 合同测试配置必须通过
`-DCITIZENSDK_TEST_WORK_DIR=<绝对路径>` 显式注入其中一个已经存在、有效 UID 所有且权限精确
为 `0700` 的任务目录；CTest 将同名环境变量传给测试进程。测试 helper 逐级 no-follow 验证
后，以系统 CSPRNG 生成 128-bit 随机名称，并只通过已验证目录 fd 的 `mkdirat` 创建子目录；
不允许重新解析根路径或回退到 `/tmp`、当前目录、用户目录。

后续统一 CI/Release 执行 Linux 原生分支时，第 7.3 步工具装配要求显式预装的
`CITIZENSDK_FLUTTER_ROOT` 与 `PUB_CACHE`，按当前平台
核对 snapshot、engine revision 和必要缓存后才复制到本轮中央目录。Flutter/Dart 的所有写状态
必须留在该目录：调用环境既有 `HOME` 必须已隔离到本轮 `CITIZENSDK_WORK_DIR` 下且为当前
用户所有的 `0700` 普通目录；构建器只验证，不修改 `HOME`、创建用户、挂载或建立虚拟机。
XDG、TMP 和工具缓存使用本轮目录，工具命令在预装可用的无特权 user/network namespace 中
禁网执行；缺少缓存、工具或隔离能力即失败，不自动安装下载。实际 bundle 在获准 GTK 会话中
运行；该环境要求不是实体 TPM 验收的替代物，也不是要求用户在当前 macOS 开发步骤提供
Linux 环境。

## Host 与 C ABI

根产品 ABI 当前是89个公开函数。Linux薄Host ABI v1另外精确包含17个
`citizensdk_host_*` 函数，用于 Host 创建、Core 借用、callback、父窗口、Vault 可用性、钱包
流程、单调销毁/监督移交和错误复制；它不增加链、钱包、签名、交易或任意 RPC 的第二套语义。

Linux Host 使用 `citizensdk_create_with_modules`，按选择装配同一五类具名 store 合同：

1. `CHAIN_DATABASE`：可重建的轻节点数据库及 finalized anchor；
2. `RUNTIME_CACHE`：按准确 block hash 绑定的可替换 metadata/runtime cache；
3. `WALLET_PROFILE`：钱包公开 profile、provisioning 与 cleanup 事实；
4. `TRANSACTION_HISTORY`：pending、in-block、finalized 历史和游标；
5. `ENCRYPTED_SECRET_BLOB`：只允许认证加密后的 child-secret envelope。

`CHAIN_DATABASE`、`RUNTIME_CACHE`、`TRANSACTION_HISTORY` 进入 public SQLite；
`WALLET_PROFILE`、`ENCRYPTED_SECRET_BLOB` 及 Vault 对象引用进入独立 secure SQLite。两库
不得合并；仅 chain/history 需要 public store，仅 wallet/signing 需要 secure store/Vault。
未选链时不加载链资产或创建链数据库，未选历史时不初始化历史。所有记录操作必须使用具名 domain 和结构化 key，不提供任意字符串键值逃生口。
Host config 强制要求小写 reverse-DNS `application_id`，实际状态根固定为
`storage_root/<application_id>/citizensdk/v1/{public,secure}`；不同宿主应用不得意外共用数据库，
改变 application ID 也不是隐式迁移入口。
`RUNTIME_CACHE` 的完整记录上限保持 8 MiB，每次 INSERT/REPLACE 与 rowid FIFO 裁剪在同一事务
提交，最多保留最新 64 条；替换已有 hash 不增长并成为最新项。Core 合法但超出该持久容量的
metadata 只进入内存，不调用 Linux store。`TRANSACTION_HISTORY` 在 Host CAS 前已经通过 4,096
条与 31 MiB durable weight 双重准入。history 不再保存 singleton BLOB：public schema v2 使用
`transaction_history_meta`、逐 execution opaque record 与三个稳定排序索引；`THQ1`/`THM1`
只暴露通用索引和原子 mutation。旧 public schema v1 直接拒绝，不迁移、不兼容、不双读。
终态删除后按 `freelist > 16 && freelist/page_count > 25%` 单次执行最多 128 页 incremental vacuum
及受监督 checkpoint；Pending/InBlock 不能删除，且不存在 full `VACUUM`。
CAS 必须跨进程共享、耐久且强原子；
`SQLITE_BUSY`、`SQLITE_ERROR`、`SQLITE_CORRUPT` 等后端错误不能伪装成“不存在”。路径必须
拒绝符号链接、hardlink、非普通文件和越界组件；最终 public/secure 目录及 DB、WAL、SHM
必须由进程有效 UID 拥有，三个文件的 link count 必须精确为 1。目录强制为 `0700`，主 DB、
WAL 与 SHM 的既有普通文件必须经 no-follow fd 收紧为 `0600` 并复核同一 inode 后才可使用。
SHM 使用 SQLite 官方锁区及 DMS 字节：每个连接在映射前取得 OFD 共享 DMS 并保持到
unmap/close。仅首次连接成功取得独占 DMS 后才把 SHM 截为 3 字节，由 SQLite 从 WAL
重建索引；其他活动连接存在时禁止截断。关闭时删除 SHM 也先升级独占并复核 inode。
该过程不删除数据库或 WAL，锁竞争明确返回 busy。
SQLite 只能通过 CitizenSDK 自有的 openat 型 VFS 使用已经验证并持有的目录 fd；主库、rollback
journal、WAL 与 SHM 的创建、打开、访问、删除和锁定都必须相对该 fd 完成，并在使用前后复核
节点类型、有效 UID、link count 和 inode。不得再把 `/proc/self/fd` 路径或其它可被替换的绝对
路径交回默认 VFS，否则路径校验与 SQLite 实际打开对象可能分裂。

既有数据库不能只执行 `CREATE TABLE IF NOT EXISTS` 后即被信任。Host 必须逐项核验
`sqlite_master` 中精确表、列、约束和索引闭集，并设置后读回 `journal_mode=WAL`、
`synchronous=FULL`、`foreign_keys=ON`、`busy_timeout=5000`；secure 库还必须读回
`secure_delete=ON`。未知或漂移 schema、无法成立的 PRAGMA、额外对象及损坏类型都失败关闭。
写事务中的权限、inode 和存储合同检查必须在 `COMMIT` 前完成；`COMMIT` 成功是唯一 durable
成功线性化点，其后不得再执行会让调用者收到失败的动作，避免“已经提交却返回错误”。

Host operation 遵循根 ABI 的 exact-once 合同：同步返回 `CITIZENSDK_OK` 即表示接受，之后
必须且只能完成一次；其它返回值表示拒绝且禁止稍后 completion。completion 中的
`host_operation_id` 必须与 callback token 一致，跨接结果必须忽略而不能夺走另一操作。
私有钱包请求建立 route 期间同步到达的 completion 必须让 Core 专用 dispatch 线程在准入门
等待，并在 route 线性化后仍由该线程交付；实现不缓存 result，也不设置固定事件槽位。65 个
以上的压力波次或并发等待者不能导致 result 被释放、completion 被吞掉或失败被伪造。

C++ `EventObserver` 只在 trampoline 调用期间同步借用 event 和 result；observer 可同步检查或
复制公开结果，但不得保留或自行调用 `citizensdk_result_release`。header-only wrapper 在
observer 正常返回或抛出后都通过 RAII 对每个非零 result 执行一次 release。

## Flutter adapter 源码合同

Linux Flutter adapter 固定 `citizen/sdk/core/v1` 与 `citizen/sdk/events/v1`，精确复用 Dart、
Android、Darwin 的 65 方法和 fixed tuple。open 为 `[1, modules]`；无会话验签为
`[1, accountId, signature, payload]`，返回 `[1, bool]`，在 session 查找及环境工厂前调用纯 Core，
不创建 Host、数据库或金库。其余方法的一个 session 持有一个 Host/Core；Dart 只看见
随机 session ID。请求在 Core 接受前预置 route；callback 动态范围内复制公开 result，只有
纯拥有值经非 inline 的 scheduler 回 UI 线程。原生终态到达与复制完成是两个独立状态；只有
复制完成后才能移除 route。EventChannel cancel 只取消 sink，epoch 防止旧队列污染新订阅。
钱包资料变更使用跨 session/Flutter engine 的进程级互斥；删除账户、删除钱包和清理的 Core
EMPTY 结果必须串行回读公开 profile，期间不释放互斥。detach 撤销原生完成投递和接纳，但
保活未完成 route 及其互斥，等完成值复制并收口后才移交既有 Host 关闭机制，不把请求取消
当作完成。Flutter 待回复句柄保留到 handler 销毁栈退出，再在 UI 队列中逐一回复关闭错误；
不能因通道替换就丢弃未回复句柄，也不能在销毁栈内重入 messenger。

Flutter Linux 的普通 `FlValue` string 以 NUL 结尾，无法直接表示合法备注中的内嵌 NUL。
adapter 通过官方 StandardMessageCodec virtual hook 在内部保存精确长度，并在输出时仍编码为
标准 string tag 7；不增加 wire tag、Map 或兼容旁路。任意其它 custom value、错误类型、超深
或超大值均失败关闭。公开返回值还验证钱包账户闭集、余额/nonce/费用的区块语义、交易执行
终态、watch 字段组合及 finalized history 的唯一键、区块和备注投影；不把 included 当作执行成功。

环境只从标准 Flutter bundle 的 executable-relative
`data/flutter_assets/packages/citizen_sdk/assets/citizenchain` 取资产，从真实 `GApplication`
取 application-id，从 XDG 用户数据根取状态目录，从 registrar view 取得弱父窗口。没有父窗口
仍可做链读取，但不能虚报 GTK 钱包 UI 可展示；无效身份/路径/资产失败关闭，不读 Dart 路径
参数、工作目录、仓库目录或共享 fallback 身份。

每个公开 Host API 调用都必须先在同一个 admission/closing fence 下取得短期 lease。显式
destroy 遇到其它在途 API lease 时返回 `BUSY`，不在当前线程等待；Vault/store provider 通过
独立 service lease 保持资源存活，认证等待期间不持有 Host 全局调用锁，close 遇到在途
service 同样返回 `BUSY`，保证 GTK 主线程仍能处理认证和取消。真正进入 teardown 后才封闭
后续 admission；callback、私有 route、Vault operation 与钱包 UI 必须收口后才能释放资源。
abandon 可将仍有在途 lease 的完整资源图移交 supervisor，由其等待 lease 归还后推进关闭，
调用线程不等待。callback 内部自清除不能等待正在等待该 callback 的另一 setter；关闭也
不得持有重入 API 所需锁等待 Core callback。

关闭与 Core 生命周期保持单调：停止 capability monitor、清除 callback、销毁 Core，失败只重试
当前或后继 teardown 阶段，最终 closed。不可逆 teardown 开始后失败不得重新开放请求，也不得提前释放 Core 借用的 HostBridge、
store 或 vault context。destroy 成功前必须退役 public/secure store 与 Vault、清零其敏感状态，
并确认所有 lease 已归还。Host-backed 实例必须先成功 graceful stop/checkpoint，直接 destroy
不能冒充持久化完成。显式调用者保留失败 handle 并自行重试；C++ RAII 析构等无法再返回错误
的边界只做有限的 callback-clear/destroy 尝试，失败即调用 `citizensdk_host_abandon` 把完整
所有权移交进程级 supervisor，由它先请求 checkpointed stop，再以有上限的退避间隔持续完成
同一单调 teardown。若连所有权移交都无法成立，析构必须 `std::terminate` 失败关闭，禁止释放
仍被 Host 借用的 callback context 或伪装为已经关闭。

## TPM 2.0 SecretVault

Linux 首版的硬件金库合同固定为 TPM 2.0，不以 Secret Service、文件 KEK 或纯软件密钥作为
降级路径。TPM 只保护 generation-scoped KEK，并只 wrap/unwrap 随机 32-byte DEK；child
mini-secret、助记词、展开私钥和 sr25519 请求始终不进入 TPM Host 接口。

每次 unwrap 使用独立的 CitizenSDK 设备金库解锁口令。该口令与 BIP-39 可选 password 是两种
不同秘密：前者只授权本设备的 TPM 对象，后者参与助记词派生。二者不得互换、自动复用或保存。
设备金库口令只可从 SDK-owned GTK 对话框进入受控原生缓冲区，禁止进入 Dart、Flutter tuple、
环境变量、命令行、日志或持久化记录。

TPM 会话要求：

- 使用 TPM2-TSS ESAPI；
- generation 对象不使用全局持久 handle，v1 只持久化 TPM public/private object blobs 和随机
  `auth_salt`；PBKDF2-HMAC-SHA256 与 600000 次迭代由 `secure-state-v1` 实现版本固定，不作为
  可漂移字段另行持久化，未来改变必须显式迁移存储版本；
- RSA-OAEP-SHA256 执行 DEK wrap/unwrap；
- 使用 salted HMAC session 和 parameter encryption，禁止 plaintext password session；
- load/validate/unwrap 前逐字段核对 child public template 的 type、nameAlg、批准 object
  attributes、authPolicy、symmetric、scheme、keyBits 与 exponent；仅比较对象 name 不足以证明
  它仍是 CitizenSDK 允许的解密 KEK；
- 不绑定 PCR，避免正常系统或固件升级无故毁坏仍由用户认证保护的钱包；
- 口令、明文 DEK 和中间 key material 在完成、错误和取消路径均清零。

能力映射必须如实反映运行设备：

| 运行事实 | Vault availability | 钱包结果 |
|---|---|---|
| TPM、认证 UI 和 provider 均可用 | `AVAILABLE` | 操作时再次认证后可用 |
| TPM 存在但无法提供强认证 UI | `NO_STRONG_USER_AUTHENTICATION` | fail-closed |
| 无 TPM 或缺少必需算法 | `UNSUPPORTED` | fail-closed |
| TPM 忙、不可访问或临时故障 | `UNAVAILABLE` | fail-closed，可在事实恢复后重试 |
| 用户取消认证 | 操作错误 | `AUTHENTICATION_CANCELLED` |
| 解锁口令错误 | 操作错误 | `AUTHENTICATION_REQUIRED` |
| TPM 清除、对象丢失或失效 | 操作错误 | `KEY_INVALIDATED` |

TPM availability 不使用算法名称枚举冒充组合能力；它必须检查 owner authorization 未被外部
配置、storage hierarchy 已启用、dictionary-attack 未锁定及计数/间隔/恢复参数有效，并以两次
`Esys_TestParms` 分别真实探测 RSA-2048/AES-128-CFB primary 与
RSA-2048/OAEP-SHA256 child/wrap 参数组合。任一条件不成立都必须报告不支持或不可用，不允许
自动改用软件 KEK、重新建钥或绕过用户恢复流程。无合格 Vault 时，链读取、同步和公开验证仍
可工作；`HARDWARE_VAULT`、
`LOCAL_SIGNING`、`WALLET_PROFILE` 与钱包交易构造不得被标记为 ready。
TPM 错误映射使用官方 TPM2-TSS 层定义：只有 TPM 与 RESMGR_TPM 层可解释 format-1
handle/session/parameter selector；ESAPI、SYS、MU、TCTI 等软件层即使低位相同也保留原调用点
错误分类，不能误报为认证失败、密钥失效或 DA lockout。

## SDK-owned 钱包流程

Linux Host 只为恢复词备份和恢复词/password 输入提供 SDK-owned GTK 界面，不添加 CitizenApp
导航、业务页面或另一套钱包模型。请求进入 UI 前必须完成以下同步校验：

- 创建只接受 12、18 或 24 词；
- 导入与追加的 `word_count` 必须为 `0`，禁止静默忽略其它 flow kind 的字段；
- 追加账户 index 非空、唯一并位于 `1..1989`；账户 `0` 是既有锚点，不能作为追加项；
- 恢复词、BIP-39 password 与设备金库解锁口令分别执行 UTF-8/长度门禁；
- 同一 CitizenSDK instance 的钱包流程与 close admission 原子互斥。

钱包流程只在 Core 已成功打开且显式选择 wallet 后受理；未选 wallet（包括 signing-only）返回
`CITIZENSDK_ERROR_UNSUPPORTED`，已启用但 TPM/认证事实不是 `AVAILABLE` 时返回
`CITIZENSDK_ERROR_UNAVAILABLE`，并且都必须发生在展示 GTK 界面之前。

创建仍是 Core 的 `prepare -> 用户确认备份 -> commit`，取消时必须确认 prepared handle 已
成功 release，不能把 release/storage 失败重标成取消。不可逆提交已经开始后，迟到取消也不能
覆盖真实错误。若 prepared release 暂时失败，flow 必须保留该 handle 和 lifecycle token，以
专用 supervisor 持续重试；只有 Core 确认 release 后才允许从 registry 删除 flow 或让 Host
close 继续。界面终态必须 best-effort 清空文本控件并清零原生敏感 buffer；这些防护不构成
对恶意同进程宿主、桌面录屏或全部内存副本的硬隔离。
generation 准入与 Vault object 条件写必须在同一 secure-store 事务中校验并提交；retire 墓碑
与 provision 必须线性化，使长认证提示期间完成的 retire 能拒绝迟到对象写。unwrap 在长提示
返回并即将交付明文 DEK 前必须重新核验 generation 未退休，失败时清零输出。
GTK widget 只能由创建它的 UI 线程销毁。若 `GMainContext` 被其它线程短暂获取，调度 source
必须保留并等待 owner 恢复；终态最多进行 8 次 source attach 重试。仍无法建立 UI-thread
清理时必须 `std::terminate` 失败关闭，禁止在 worker 线程析构 GTK 或遗留秘密控件后伪报完成。
parent window 的 `destroy` 必须在同一 UI 线程使 parent 引用失效、清空 dialog/password/恢复词
控件、结束等待并唤醒工作线程；禁止认证线程在最长五分钟等待后再解引用已经销毁的 parent。

## 测试和交付门禁

`linux/test` 的第 7.1 步源码测试覆盖公共 ABI 常量与 Host 函数闭集、CMake 构建/安装目标
投影、资产边界、operation exact-once、生命周期、public/secure store 隔离、record-key
namespace、敏感缓冲区、Vault 状态与错误映射、TPM 对象策略、秘密不进入 Linux 新增
Host/C++ 旁路以及钱包流程 admission。根产品 C ABI 的明确备份/恢复边界仍由根测试冻结。
软件 TPM 只能提供确定性集成测试，不能
替代 LinuxARM、LinuxAMD 实体 TPM 验收。

公开 Linux 支持前，后续统一 GitHub CI 增量缓存、Release 全量构建验证还必须覆盖两种目标：

- ELF64 machine、SONAME、GLIBC 基线和 `DT_NEEDED` 闭集；
- Core 精确 70 exports，Host 不重复 Core symbols 且只依赖一次 `libcitizensdk.so`；
- RPATH/RUNPATH 不含绝对构建路径；
- 两种机器目标的 C/C++、Flutter、SQLite、软件 TPM 和实体 TPM 测试；
- 候选、归档和 Hosted dry-run 的逐文件闭集与反向校验。

第 7.3 步增加的安装消费者只包含公开 API 调用：C 使用 Host C API，C++ 使用安装的
header-only Host；第 7.4 步 Flutter 直接使用默认 `CitizenSdk.open()` 与正式注册，不再注入
内部 platform 或临时修改 pubspec。plugin 自己固定 `$ORIGIN`，不依赖测试 runner 代偿。
它们与 12 个 Host、6 个 adapter
合同目标分别验收，不把源码正则或假 readelf 输出作为实际运行结果。后续平台验证中的运行失败
或环境缺失必须保留对应未验收状态，不能以跳过测试产生“Linux 已交付”的结论；这些尚未执行
的 Linux 项目不再阻塞本步以 macOS 本机编译为标准的开发验收。

本文件记录已经确认的设计和源码装配边界，不是上述运行验证的替代品。

## 已知同源缺陷修正（第 8.1.1 步）

两个结构计数查询统一使用 `name NOT GLOB 'sqlite_*'`，下划线只表示字面字符。
初始化前与打开既有库时都检查全部非系统对象，sqlitex 表、索引、视图或触发器不能被
误当作 sqlite_ 系统对象排除。固定 schema、版本、CAS 与 Linux OFD 锁行为不变；
版本 0 已有非系统对象时拒绝初始化，不能先创建业务表再报告错误。

RequestRouter 将已接纳 callback 与空 `std::function` 交换，保证移交后路由立即为空；
不依赖移动源的未指定状态。callback 可重入接纳下一请求，过期 completion 不能消费新路由。
对应测试补直接头依赖及这些回归边界。此修正不改变任何平台、Flutter 方法或 Core ABI；
实际 Linux 存储/UI/TPM 运行证据仍须由后续统一平台验收取得。
