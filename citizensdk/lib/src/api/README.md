# CitizenSDK 最终 Dart API

五端统一门面为 wallet、signing、chain、transactions、history、qr，可按 modules 组合，默认 full=63。
wallet 管理与 signing 彼此独立；history 独立于 transactions。模块依赖与编译支持由 Rust 校验。
静态 `CitizenSigning.verify` 无需 open 或事件订阅，直接经同一 transport 调用 Rust 纯验签，
不创建钱包、金库、链或数据库；签名只经 `sdk.signing.sign` 使用同宿主已有安全账户。
独立 `sdk.qr` 使用同一 Rust `QR_V1` 协议/会话实现和同一 ZXing-C++ 图像层；
QR-only 不创建钱包、金库、链数据库或轻节点，待签字节必须显式交给 signing。
模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

第 3 步新增 `sdk.chain.getGenesisHash()` 与 `sdk.chain.getAccountBalances(accountIds)`：
前者只读 Core 固定身份，无需 start；后者接收 0..1990 个规范账户，保持顺序和重复项，
所有余额来自同一已验证 finalized 块。空列表仍请求 Core 校验模块/生命周期，不在 Dart 短路。
`sdk.wallet.viewAccountPrivateKey(accountId)` 只启动 SDK 原生安全查看并返回
`Future<void>`，不公开私钥、显示回调或内部句柄。完整五端运行与硬件验收尚未完成。

应用只从 `package:citizen_sdk/citizen_sdk.dart` 使用本目录的公开 API。Android、Darwin、Linux 与
Windows binding 只是稳定 CitizenSDK Core ABI 的类型化投影，不在 Dart 中重写轻节点、钱包、
sr25519 或交易逻辑。第 7.4 步已把 LinuxARM/LinuxAMD 纳入同版候选合同与默认公开入口，
共用官方 `linux` plugin 注册；不需要注入内部 platform 或增加产品侧包装。

`CitizenSdk.open(modules: ...)` 按选择创建隔离 session，默认 full；普通读取、签名和长时转账可以并发，分别使用
单调 request sequence。`start`、`stop` 会等待既有请求并独占新的接纳；`close` 关闭接纳并让
原生协调器取消/收口长时请求。事件使用独立且连续的 event sequence。运行中的 session 必须先
等待 `stop()` 完成 checkpoint，再调用 `close()`；后者等待结果释放、destroy 和已接纳 Dart
调用完成，不能用来绕过有序停止。

钱包创建、导入和追加账户只启动 SDK 自有的平台原生安全界面；Linux 复用已有 GTK 钱包流程。
助记词与可选 password 不得进入 Dart；Dart 只接收创建完成后的公开 `CitizenWalletProfile`。
Linux 实际构建和运行证据由后续统一 GitHub CI（增量缓存）/Release（全量构建）验证；源码
注册不代表已发布。同版插件缺失时返回 `unsupported`，不得替换为 Dart 钱包或另一份 Core。
