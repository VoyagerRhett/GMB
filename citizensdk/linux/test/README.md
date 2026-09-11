# CitizenSDK Linux Host 合同测试

第 3 步增加创世哈希与批量 finalized 余额查询的 codec/session/公开消费者断言，
覆盖无需启动的创世身份、空列表仍经过 Core、重复/顺序、超限、数量不匹配与跨块结果。
这些新增断言尚未执行；不涉及私钥查看。

本次补齐模块构造的合法/非法选择、无链时不读取链资产/创建 public 数据库、独立门面合同，
以及未 open/listen 的纯验签 codec/session/plugin 测试：资源工厂调用必须为零，响应为
`[1, bool]`，拒绝旧会话形状和非法签名字节。本次第 2 步仅更新源码、注释、合同和测试，尚未执行新的真实构建、平台测试或硬件验收；下文旧分步运行记录保留为历史证据，不代表本次变更已验证。

本目录测试 LinuxARM、LinuxAMD 共用 Host/Flutter 投影和已安装包的真实消费者，不复制 Rust
Core 的账户、钱包、轻节点、sr25519 或交易实现。Host 合同目标直接编译对应生产源码；原生
消费者则只能使用安装目录的公开头和同版运行库，不能把私有源码编译进消费者。

第 7.2 步同时增加一组独立的 Flutter adapter 源码合同目标。它们直接编译与正式 plugin 相同的
五个生产实现文件，链接同版已安装 Host/Core，不建立测试专用 adapter、第二份 Host/Core 或
下载测试框架：

- `citizen_sdk_flutter_codec_test.cc`：63 方法、固定 tuple、整数/UTF-8/累计输入预算、标准 wire
  与内嵌 NUL 无损，以及钱包资料、交易终态、进度和历史返回值语义；
- `citizen_sdk_flutter_sessions_test.cc`：全部路由、接受前早完成、失败保留、事件 epoch、关闭
  重试、跨 session/引擎的钱包变更门禁、删除后资料回读与 detach 所有权；
- `citizen_sdk_flutter_wallet_flow_test.cc`：GTK 流程的早完成、重复/迟到完成和取消；
- `citizen_sdk_flutter_environment_test.cc`：标准 bundle、真实身份、XDG 根、资产普通文件与无
  fallback；
- `citizen_sdk_flutter_plugin_test.cc`：公开 Flutter messenger/registrar 接口的真实注册、响应、
  活通道替换和 handler 销毁后的延迟回复；
- `citizen_sdk_flutter_secret_boundary_test.cc`：Dart 不得传入路径、身份、GTK 指针、秘密或裸
  句柄。

测试范围：

- `citizen_sdk_api_contract_test.cc`：ABI 版本、稳定枚举、固定宽度布局、Host 函数闭集、非法
  config、`application_id/citizensdk/v1` 状态隔离，以及构建期/安装期唯一 Core 与
  `CitizenSDK::Host` CMake 导出合同；同时冻结统一 closing admission、公开 API lease、callback/
  parent 线性化和 destroy 前资源退休；
- `citizen_sdk_assets_test.cc`：三项 CitizenChain 资产闭集、普通文件与路径失败关闭；
- `citizen_sdk_host_operation_test.cc`：Core 前预分配 completion handler、接受后无分配绑定、
  exact-once completion、移交即清空、callback 重入接纳下一请求、旧完成不消费新路由、
  96 路并发同步早回调无损路由，以及无人认领 result 释放；
- `citizen_sdk_lifecycle_test.cc`：单调 teardown、失败重试、service lease、认证期间非阻塞关闭、
  callback 自清除与借用上下文存活；
- `citizen_sdk_public_store_test.cc`：chain/history CAS、runtime cache 隔离、openat SQLite VFS
  路径替换抵抗、精确 schema/PRAGMA/COMMIT、0700/0600、符号链接/hardlink/非普通节点拒绝、
  有效 UID 所有权合同和损坏 revision/blob 失败关闭；另验证版本 0 的 sqlitex 表不能触发
  初始化，版本 1 的 sqlitex 表/触发器不能绕过结构闭集；
- `citizen_sdk_record_key_test.cc`：generation/owner/account 与 block hash 的精确 record key，
  并拒绝旧 `citizenapp` 标签；
- `citizen_sdk_secure_store_test.cc`：profile/secret CAS、generation retirement 与条件 Vault
  object 写线性化、openat VFS 和精确 schema/PRAGMA/COMMIT，以及 secure DB/全部 sidecar 的
  私有权限、符号链接/hardlink/非普通节点拒绝和损坏 revision/blob 失败关闭；版本 0/1
  的 sqlitex 表/触发器执行与公共库相同的拒绝合同，不允许失败打开后创建业务表；
- `citizen_sdk_sensitive_buffer_test.cc`：不可复制、移动所有权和显式清零；
- `citizen_sdk_secret_vault_test.cc`：Vault availability、错误 wallet/generation 拒绝、retire 与
  迟到 provision 互斥、长认证提示后 retirement 重验、明文 DEK 输出失败清零与永久退休；
- `citizen_sdk_secret_boundary_test.cc`：Linux 新增的 Host/C++ 公共头闭集不另造助记词、口令、
  DEK 或私钥旁路；根产品 C ABI 的明确备份/恢复合同仍由根测试冻结；
- `citizen_sdk_tpm2_test.cc`：生产纯函数的 TPM/软件错误层及 format-1 selector 映射、
  device-only TPM 对象策略、完整 child public template、DA lockout/
  真实层级 availability、固定 v1 KDF、认证会话、认证 UI 启动/输入超时及无硬件失败关闭；
- `citizen_sdk_wallet_flow_test.cc`：创建/导入/追加 canonical 门禁、Core/Vault/能力拒绝、result
  ownership、取消/close 互斥、GTK owner-thread 终态清理及 parent-destroy 立即退休。

Host 磁盘用例使用 `citizen_sdk_test_support.hpp`；Flutter 用例使用不依赖 Host 私有头的
`citizen_sdk_flutter_test_support.hpp`，两者遵循相同的工作目录安全合同。配置测试时，调用方必须通过
`-DCITIZENSDK_TEST_WORK_DIR=<绝对路径>` 注入一个已经存在、本次任务独占、有效 UID 所有且
权限精确为 `0700` 的工作根；本机该路径必须位于
`/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk` 下。CMake 把同名环境变量注入每个 CTest，
helper 再逐级以 no-follow 方式验证该根，才用系统 CSPRNG 生成 128-bit 随机名称，并只通过
已验证目录 fd 的 `mkdirat` 创建 `0700` 子目录。清理始终持有目录 fd，并只通过
`openat`/`unlinkat` 处理已验证的精确 inode；不存在 `/tmp`、当前
目录或用户目录 fallback，也不会对可预测路径执行递归删除。

## 已安装包消费者

第 7.3 步新增以下四项源码，复用唯一 `scripts/build-native.sh` 和本目录的 CMake 入口：

- `CitizenSDKConsumer.cmake`：独立 C/C++ 消费者配置。严格匹配安装版本、平台、导入库与头
  路径，拒绝跨架构、源码内状态和系统搜索 fallback；不构建第二份 Core 或 Host。
- `citizen_sdk_c_consumer.c`：纯 C Host/ABI 参数、生命周期、能力及真实异步完成。持有一个
  Core 结果验证关闭返回 `BUSY`，唯一释放后再重试关闭，检查失效句柄。
- `citizen_sdk_cpp_consumer.cc`：安装后的 C++ Host 移动所有权、幂等 open、未启动读取拒绝、
  轻节点启停和 checkpoint、运行中关闭拒绝、结果由公开 trampoline 释放及幂等 close。
- `citizen_sdk_flutter_consumer.dart`：标准 Flutter Release runner 的真实 method/event 通道，
  验证能力、事件顺序、启停、关闭和再次建 session。第 7.4 步直接使用候选的官方 plugin 注册和
  公开 `CitizenSdk.open()`，不注入内部 transport、不临时改写 pubspec；不创建钱包、不操作真实
  账户或提交交易。

两种平台的 20 项安装件在同一候选中合并为 27 项，重叠文件必须逐字节一致。Hosted Linux
精确运行集合为 39 项；真实消费者必须消费该同版本边界，不能从源码私有实现补齐缺项。
plugin 的 `$ORIGIN` 由生产 CMake 固定，不允许临时 runner 代偿库查找路径。

后续统一 GitHub Linux 平台验证中，构建器分别精确核对 12 个 Host、6 个 adapter、2 个已安装
原生消费者的 CTest 清单，缺项或零项不是成功。Flutter 夹具不依赖会被 Release 移除的 assert；
必须真实执行 bundle、在限定时间内
以 0 退出并刷新输出唯一成功标记。编译成功、测试源码数量或伪造 ELF 文本均不能替代这些运行结果。

Linux 主流程会以 Release 配置编译合同测试。C/C++ 目标统一使用 `-UNDEBUG`，且每个测试翻译
单元都在发现 `NDEBUG` 时直接编译失败，确保标准 `assert` 不会被 Release 配置静默移除。

第 7.1/7.2 步仅提交这些测试源码，没有运行 CMake、CTest、Linux 编译、软件 TPM、实体 TPM、
Flutter consumer、Git、远程 CI 或 Release。软件 TPM 后续只作为确定性集成覆盖，不能替代
LinuxARM、LinuxAMD 实体 TPM 验收；adapter 测试源码也不能替代后续 Linux 实际运行结果。
第 7.3 步已完成安装/消费者装配源码与本机 Node 合同检查；当前开发以本机 macOS 编译通过为
验收标准；2026-09-03 已通过既有 `abi-host` 与 `apple`，不再等待用户提供 Linux/TPM 环境。跨平台构建与
功能验证后续统一进入同一 Core commit、SDK 版本、ABI 版本的 GitHub CI/Release，CI 使用增量
缓存，Release 使用全量构建，仍为同一个 CitizenSDK 产品和 Release。
以上原生测试均未在 Linux 编译运行；macOS 编译不能替代 Linux 运行结果。GTK 交互取消/父窗
销毁、实体 TPM 缺失/拒绝/成功及钱包/历史仍须在后续验证中单独记录实测结果，不能从无账户
消费者推断其通过。用户数据不进入测试根，不发送真实资金。

第 8.1.1 步修正两个结构计数查询和 RequestRouter 的可移植所有权语义；测试显式包含
HostError 定义头，不依赖其它头文件的间接包含。可在 macOS 执行不依赖 Linux API 的
路由、生命周期、记录键与公开秘密边界合同；磁盘/VFS 用例仍依赖 Linux OFD 锁与 getrandom，
不得用系统 SQLite 内存查询或 macOS 便携合同冒充完整 Linux 存储测试。准确执行结果见任务卡。

第 3 步既有测试补充安全查看的公开账户/空响应合同、Host 钱包模块拒绝、同步复制/重复回调拒绝、
撤销后晚认证不可写入缓冲、真实认证操作关联拒绝、取消等待真实终态，以及 C/C++ 无秘密函数签名。缓冲与协调器测试
不等于系统锁屏、原生窗口清屏或设备认证的实际验收；本轮桌面完整编译与运行仍未完成。
