# CitizenSDK 第一部分发布冻结报告（1.10.4）

日期：2026-09-11。范围：CitizenSDK 第一部分源码候选、通用合同、四端 Host 投影、确定性测试和
本机可执行证据。没有提交、推送或发布包。

## 结论

第一部分的 SDK 通用底层能力候选已经闭合。钱包、通用签名、唯一 `QR_V1` 冷签、opaque
RuntimeCall 交易、SDK 自身 execution 历史、CitizenChain PoW 轻节点和生命周期仍由同一 Rust
Core 负责；CitizenApp、途遇产品和第三方 App 继续自己实现广场、投票、治理、旅行、订单等业务。
SDK 没有这些业务 schema，只为业务 App 提供钱包、签名、交易、轻节点及通用历史事实。

P1-04 已关闭：`TransactionHistoryState` whole-value store 与 whole-history codec 已删除。新合同由
`TransactionHistoryIndex`、`TransactionHistoryCursor`、`TransactionHistoryMutation`、按 ID 读取和
最多 100 条分页构成。状态更新只读取目标 execution；容量腾挪只取最旧 retention-terminal；恢复
只取可协调记录。`TXR1` 保护每条完整 Core 恢复材料，`THQ1/THB1/THM1` 只运输通用索引描述和
opaque record，Core 对描述与记录逐项交叉验证。

P1-05 已关闭：Android、Apple、Linux、Windows 的 `public-state-v1.sqlite3` 统一使用 schema v2，
由 `transaction_history_meta`、`transaction_history_records` 和 newest/retention/reconcile 三个索引
组成。expected revision、终态 deletes、opaque upserts 和 meta 在一个 IMMEDIATE 事务中提交。
新库建表前固定 `auto_vacuum=INCREMENTAL`；freelist 同时超过 16 页和总页数 25% 时，单次最多
回收 128 页并监督 WAL checkpoint。没有 full `VACUUM`、后台回收线程、迁移、兼容、双读或双写。
旧 schema v1/漂移对象直接失败，SDK 不删除用户数据库。

P2-01 已关闭到可验证的 operation 边界：20 轮预热基线记录 page 调用数、返回条数、median/P95/
max/CV；1,000 条中单 execution mutation 为 1 次 index load、1 次 record load、0 次 page load、
1 次 mutation write。Apple 实际 SQLite 的 0/1/100/1,000 行增长、20 次重开和 1,000→1 回收数据
见 `SDK_BASELINE_1_10_1.md` 第 11 节。生产 API 没有计时或 benchmark hook。

P2-02 的 SDK adapter 合同已关闭：finalized stream 的 error 和结束都会废弃旧订阅，按
1/2/4/8/16/30 秒封顶重订阅，成功通知复位到 1 秒。stop/close、exclusive admission、host
operation 排空、取消唤醒、teardown-only、late completion 和 StartFailed/Stopped 单向性由已有
Engine/FFI 生命周期回归与新增确定性退避测试共同覆盖。网络、P2P、共识、交易池、watch 和链
数据库仍直接复用现有 smoldot provider；SDK 没有复制第二套网络状态机。

## 数据边界

history 行只索引 `execution_id`、`created_at_millis`、`updated_at_millis`、`durable_weight`、
`retention_terminal`、`chain_terminal`。opaque record 内只有 SDK 恢复所需的 source、callData hash、
callData、transaction hash、signed extrinsic、链/runtime/nonce、通用状态和时间。生产 schema 没有
destination、amount、remark、direction、pallet、action、投票、治理、旅行或订单字段。

平台 SQLite 是 Host 对 typed store 的一种实现，不是 Rust Core 内嵌数据库，也不是 CitizenApp 或
CitizenWallet 数据库。CitizenWallet 仍是完全独立产品；本步骤没有修改它。用户恢复 SDK 热钱包
仍自行输入助记词，不迁移旧钱包。

## 本机执行证据

- `scripts/test.sh cargo -p citizen-sdk-contracts -p citizen-sdk-engine -p citizen-sdk-ffi --all-targets --locked`：
  通过；包含 116 项 FFI 单元测试、Engine/Contracts 全部定向测试及 ABI/consumer 合同。
- `scripts/test.sh cargo -p citizen-sdk-engine --test baseline_resource_contract --locked -- --nocapture`：
  5/5 通过；输出 operation-level 0/1/100/1,000 指标和单 execution mutation 计数。
- Apple public store 源码使用本机 Swift 6.4 类型检查通过；仓库外测试可执行实际创建 schema v2、
  分批写入、20 次重开及终态回收，具体数值登记在基线报告。
- Android JNI 使用已安装 NDK 28.2 的 arm64 API 24 clang++ 以 C++17、`-Wall -Wextra -Werror`
  语法检查通过；public store/SQLite/record/key Kotlin 子集使用已安装 Android Studio JBR、Kotlin 编译器和
  Android 36 SDK jar 以 JVM 17 编译通过。Gradle/AAR/真机未运行；没有安装或下载工具。
- Linux public-store 生产源以 C++17、`-Wall -Wextra -Werror` 语法检查通过；Linux runner 因本机
  为 macOS 未运行。Windows runner 同样未运行，不能由同源 SQL 或源码扫描冒充通过。
- 根 C11/C++17 ABI layout 由 Rust FFI 测试编译通过；Host struct 保持 72 bytes，history 字段偏移
  仍为 56/64，名称与类型替换为 query/mutate。117 个产品函数、62 个 Flutter 方法、3 个 Apple
  QR image 函数及 Linux/Windows 各 17 个 Host 产品函数数量没有变化。

最终 `scripts/test.sh cargo --workspace --all-targets --locked` 全量通过；`scripts/test.sh release`
107/107 通过；仓库外 `/private/tmp` 新目录中的 `scripts/build-native.sh abi-host` 完成 Release
`libcitizensdk.dylib`、产品符号和 C11/C++17 consumer 验收。任务卡登记相同结果。本报告冻结源码
候选，但仍不是跳过下列真实平台外部门禁的发布许可。

## 明确未运行与残余发布门禁

Flutter 没有运行，也没有被安装、下载、升级、配置、启动、停止或清理缓存；其历史结果不计入本
步骤。Android Gradle/AAR、Android/iOS 真机、Linux 原生 runner、Windows 原生 runner、实体
TPM/Secure Enclave/PCP、真实 CitizenChain 网络 reconnect/submit/watch 均未运行，发布前仍需在
已安排且预装依赖的对应 runner 上执行。测试没有使用用户钱包、助记词、密钥或真实资产广播。

## 不变项与漂移核对

- 没有修改 CitizenApp、CitizenWallet 或其它产品。
- 没有修改 `native/smoldot/pow/**`；定制 CitizenChain PoW 来源 hash 由 Release 门禁继续固定。
- 唯一二维码协议仍为 `QR_V1`，没有 V2、legacy、fallback、alias 或 wrapper。
- 没有迁移/兼容旧钱包或旧 whole-history SQLite；旧开发库由调用方明确清除后新建。
- 源码树不得包含数据库、`build/`、`target/`、`.build/` 或候选临时产物；Cargo 与基准输出位于
  仓库外 调用方 cache 或 `/tmp`，完成后只清理本步骤创建的准确临时目录。
