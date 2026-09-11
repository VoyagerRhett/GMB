# Windows 原生合同测试

第 3 步增加创世哈希与批量 finalized 余额查询的 codec/session/公开消费者断言，
覆盖无需启动的创世身份、空列表仍经过 Core、重复/顺序、超限、数量不匹配与跨块结果。
这些新增断言尚未执行；不涉及私钥查看。

本次补齐模块构造的合法/非法选择、无链时不读取链资产/创建 public 数据库、独立门面合同，
以及未 open/listen 的纯验签 codec/session/plugin 测试：资源工厂调用必须为零，响应为
`[1, bool]`，拒绝旧会话形状和非法签名字节。本次第 2 步仅更新源码、注释、合同和测试，尚未执行新的真实构建、平台测试或硬件验收；下文旧分步运行记录保留为历史证据，不代表本次变更已验证。

14 个 CTest 程序与一份私有测试支撑由本目录 CMake 精确枚举；测试直接编译生产源码，
Release 显式撤销 `NDEBUG`。所有临时状态要求 `CITIZENSDK_TEST_WORK_DIR` 指向本次独占的
中央目录，没有系统临时目录回退。测试支撑按句柄清理自己创建的随机子目录，不批量删密钥。

覆盖范围：C/Host ABI 布局与导出、资产、请求/结果所有权、关闭、目录权限和 reparse、
typed store/CAS/generation、敏感缓冲区、Vault 状态机、CNG 属性与错误、Win32 认证及钱包 UI。
私有依赖注入仅替换 OS 金库/UI 交互，不能用替身证明实体 TPM 或操作系统认证缓存行为。

本机 macOS 不运行这套 Windows CTest。Windows 原生编译、交互桌面、跨进程存储锁与实体
TPM 授权验证留到统一 GitHub CI/Release。TPM 负向口令会影响设备全局字典攻击锁定，
只能在明确隔离且另行开启的测试设备上运行；生产代码不会自动尝试错误口令或清除 TPM。
未开启的硬件测试必须记录为未运行，不能算成硬件通过。普通 CI runner 没有合格 TPM，
不代表公民链或 SDK 可以回退到软件金库。

## 已安装 C/C++ 消费者（第 8.3 步）

`CitizenSDKConsumer.cmake` 在独立分支配置两个程序，提前返回，不链接上面的私有
test_support，也不编译 Host/Core 源文件。`CITIZENSDK_CONSUMER_PREFIX` 和
`CITIZENSDK_CONSUMER_VERSION` 固定本轮安装件，EXACT/NO_DEFAULT_PATH 拒绝其它来源。
两个程序仅包含九个公开头中的所需头，使用已安装的 DLL/import library 和同版链资产。

C11 消费者接收并拥有异步结果，保留结果时核验销毁 BUSY，随后唯一释放并重试；C++17
消费者使用公开所有权包装，回调结果只借用，由包装层释放。两者检查启动前错误、能力、
启动、停止/checkpoint、关闭与失效句柄，等待和关闭重试均有上限，不依赖可被 NDEBUG
删除的 assert。实际加载 DLL 的路径与复制字节都需匹配本轮安装来源。

消费者固定关闭钱包、空 HWND，不使用真实秘密、不触发 TPM/钱包 UI、不提交交易。
CTest 必须命中准确两个名称、退出码、超时和成功标记。它们属于 Windows/MSVC 的真实
平台验收；macOS 的 Node 合成安装/PE 夹具只证明检查器行为，不代表 Windows 已运行。

## Flutter 适配合同（第 8.2 步）

Flutter 构建分支单独枚举六个程序：codec、environment、sessions、wallet_flow、plugin、
secret_boundary。只编译五个正式 adapter 源文件，连接同版已安装 Host/Core；不会落入
原生 14 项测试的 Host 源码编译分支，不下载测试框架，也不删除已有原生测试。

- codec：62 方法、固定 tuple、UTF-8/NUL、u64/u128、账户/载荷、统一钱包状态、通用签名、安全链读取、通用交易准备/执行、二维码协议/图像、公开返回语义及非法值；
  原始 wire 的截断、尾随、巨长声明和超深输入必须在官方 decoder 分配之前拒绝。
- environment：明确声明的 application_id、系统路径/标准资产、有效父窗口与销毁边界。
- sessions/wallet_flow：早完成、错配/重复/迟到回调、重入、全进程变更门禁、取消非终态、
  关闭 BUSY 保留所有权，以及 Core 已退休而 Host 窗口仍需关闭重试。
- plugin：官方 codec/messenger、双通道、监听取消、注册替换、队列与已接纳回复的所有权。
- secret_boundary：公开值与注册头无秘密、裸句柄或任意 RPC；仅此项包含源码边界扫描，
  不能替代前五项的实际行为断言。

适配层自有目标保持 C++17、STL 异常与 /EHsc 一致；Release 仍撤销 NDEBUG。
Windows 原生运行证据仍由统一 GitHub CI/Release 取得；macOS 可移植测试不冒称完整 Windows
CTest 已通过。具体本步运行命令、数量和未运行项只记录在对应任务卡。

## 公开 Flutter Release 消费者（第 8.4 步）

`citizen_sdk_flutter_consumer.dart` 仅导入包根公开 API，要求真实 Windows Release 引擎
与首帧，通过 `CitizenSdk.open()` 使用官方自动注册插件；不接受私有 transport、临时
SDK pubspec 改写或手工注册。检查 NOT_READY、完整能力状态、空 profile、启停、事件
单调性、关闭/重复关闭、失效实例及重开。使用真实条件分支和有界 watchdog，不依赖 assert。
成功标记只能输出一次，调用器同时核对实际退出码、DLL 来源与链资产。

唯一构建器依次保留 14 项原生、2 项 C/C++、6 项 adapter 与本消费者，全部成功后才导出。
正式运行仅在一次性 GitHub Windows 用户环境；命名空间 org.citizensdk.flutterconsumer
由构建器核实不存在，生产 Host 使用系统 Known Folder 创建，退出后按归属精确清理。
消费者不读写机密、不创建钱包、不签名或发送链上交易；无 TPM 时不伪报硬件能力。
本机 macOS 只运行可执行的来源/公开 API 回归和编译，不能冒写本 Windows 程序已运行。

第 3 步既有测试补充安全查看的公开账户/空响应合同、Host 钱包模块拒绝、同步复制/重复回调拒绝、
撤销后晚认证不可写入缓冲、真实认证操作关联拒绝、取消等待真实终态，以及 C/C++ 无秘密函数签名。
原生窗口测试增加锁屏消息和失焦后的永久撤销、错误 Host/操作号拒绝；这些 Win32 消息用例尚未运行。
缓冲与协调器测试
不等于系统锁屏、原生窗口清屏或设备认证的实际验收；本轮桌面完整编译与运行仍未完成。
