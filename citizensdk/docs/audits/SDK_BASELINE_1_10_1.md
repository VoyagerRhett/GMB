# CitizenSDK 1.10.1 基线与问题分级报告

日期：2026-09-11  
基线提交：`1ffb33c2ca38dc92aae0b350a8504dcfc4abcf53`  
范围：CitizenSDK 通用钱包、签名、唯一 `QR_V1`、验证链读取、轻节点、opaque 交易与通用交易历史。  
结论：本步骤只增加测试、报告和发布闭集，没有修改生产 API、ABI、协议、数据库 schema 或上游 PoW 实现。

## 1. 结论与分级

- P0：未发现。现有证据没有显示秘密泄漏、验签/验证绕过、持久状态损坏或不可恢复资源失控。
- P1：5 项。持久 runtime cache 没有容量淘汰；交易历史条数上限与宿主记录字节上限不一致；runtime metadata
  合同上限与宿主记录上限不一致；历史单 BLOB 编解码/重写为 O(N)；SQLite retention 后物理文件不回收空闲页。
- P2：2 项。现有测试进程级计时无法分离单次 SDK heap/CPU；部分平台和真实网络生命周期仍待受控 runner/真机
  验证。
- 第 1.10.2 步优先处理前三项 P1 的安全与资源边界；后两项 P1 进入 1.10.4。P2 分别进入 1.10.3、
  1.10.4 和 1.10.6。

本报告中的“实测”来自本机重复执行；“源码事实”来自所列生产文件；“推断”不会作为已通过结果。

## 2. 测量环境与边界

| 项目 | 结果 | 类型 |
|---|---:|---|
| 主机 | Darwin 27.0.0, arm64 | 实测 |
| Rust / Cargo | 1.97.1 / 1.97.1 | 实测 |
| Node / SQLite | 25.2.1 / 3.50.6 | 实测 |
| Clang / Swift | Homebrew Clang 22.1.0 / Swift 6.4 | 实测 |
| Java | 本机缺少 Java Runtime | 实测，未安装 |
| Flutter / Dart | 未读取版本、未运行、未启动或停止任何进程 | 遵循用户明确边界 |
| Linux / Windows / Android 真机 / Apple Flutter adapter | 未运行 | 待 runner/真机验证 |

测试生成物全部定向到 `CITIZENSDK_TEST_WORK_DIR指定的源码外测试目录`；本轮临时证据在报告完成后清理，
不进入源码树或发布包。性能数字用于本机相对基线，不是跨机器 SLA。

## 3. 公共合同基线

| 合同 | 基线 |
|---|---|
| 通用模块 | wallet/signing/chain/transactions/history/qr，共 6 个；full bitmask = 63 |
| 能力名称 | 10 |
| 公共错误类别 | 22 |
| Flutter 方法 | 62（源码合同冻结；本轮未运行 Flutter） |
| Core C ABI | 116 个产品符号 + 4 个 `citizensdk_internal_*` 测试符号 |
| Apple QR 图片 ABI | 3（既有 1.9 结果；本轮未重建 Apple Flutter adapter） |
| Linux/Windows Host ABI | 各 17（源码/发布闭集；本轮未运行远程 runner） |
| 助记词 | 12/18/24 words |
| 外部签名 transport | 仅 `CitizenExternalSignerTransport.qrV1` / `QR_V1` |
| 交易 callData | 1..1 MiB opaque bytes |
| 签名 payload | 最大 16 MiB |
| storage | key 4 KiB；batch 1,024 keys / 1 MiB 合计 |
| runtime metadata | Core 合同 64 MiB；当前宿主记录 8 MiB（见 P1-03） |
| 通用交易历史 | 最多 4,096 records；page 100；sync batch 32 |

`test/baselines/sdk_1_10_1_contract_test.dart` 还冻结了公开字节模型的防御复制和三类互不相关 consumer fixture
只能位于测试目录。该 Dart 测试因本轮禁止操作 Flutter 而未执行；它属于 1.10.6 待验收项。

ABI host 构建使用外部 work/output 目录完成，产物 `libcitizensdk.dylib` 为 21,221,664 bytes，`nm` 得到 120 个
`citizensdk_*` 符号，其中 116 个产品符号、4 个内部测试符号。默认脚本首次因 `/var` 的符号链接路径边界被拒绝，
改用明确的仓库外真实路径后成功；没有放宽路径门禁。

## 4. 安全基线

### 4.1 秘密生命周期

- 源码事实：`native/contracts/src/secret_vault.rs` 用 `SecretBuffer`/`Zeroizing` 承载秘密；
  `native/engine/src/engine.rs` 的密码参数使用 `Zeroizing<String>`；钱包 crate 对 mnemonic 启用 zeroize。
- 源码事实：钱包 profile 只持有 `SecretRef`，`native/contracts/src/wallet.rs` 强制每个账户 owner 唯一且不能复用
  wallet generation；加密秘密仓储接口只接受 envelope，不接受明文 `SecretBuffer`。
- 源码事实：私钥安全查看通过强认证宿主、一次性 view、cancel/finish 和关闭屏障；Android recovery phrase、
  Apple/Linux/Windows wallet flow 都有显式清零/关闭路径。
- 实测/回归：完整 Rust workspace 覆盖 mnemonic 12/18/24、强认证失败、owner/source 不匹配、取消、重复释放、
  short-buffer 和关闭竞态；结果见第 9 节。
- 扫描事实：生产 Rust/Dart/Kotlin/Swift/C++ 中未命中 `println!`、`eprintln!`、`NSLog`、Android `Log`、
  `debugPrint` 或 Dart `print` 的秘密输出路径。扫描不是运行时泄漏证明，只作为反向辅助门禁。

### 4.2 签名与 QR 绑定

- 源码事实：`native/contracts/src/signing.rs` 只接收通用 bytes/transform，不含 App action allowlist；外部签名会话
  绑定 account、payload、transform、request、expiry 和 signature。
- 源码事实：`native/qr/src/session.rs` 最多 64 个活跃会话，TTL 最多 300 秒；响应必须匹配 request/expiry，
  验签成功后只能消费一次，验签失败不消耗会话，cancel 明确移除会话。
- 实测/回归：唯一 QR transport 为 `QR_V1`；生产源码未发现 `QR_V2` 或其它版本入口。

### 4.3 交易与验证链事实

- 源码事实：准备项 instance-bound、source-bound、single-use；同一 source 只允许一个 in-flight/prepared，通用上限
  256。热/冷交易共享 pending-before-broadcast、原始 signed extrinsic 恢复和准确 finalized proof 状态机。
- 源码事实：runtime metadata 按准确 block hash 缓存；storage、block body、runtime context 和 finalized execution
  只从 `VerifiedChainClient` 返回，不暴露任意 RPC。
- 实测：离线 smoldot provider 在 Created 状态下 watch 立即 fail-closed；state import 幂等且保持 CitizenChain
  identity。本轮没有网络连接，因此没有把 reconnect/submit/watch 恢复写成通过。

## 5. 资源与性能基线

所有样本为 5 轮；P95 在 5 个样本中等同样本最大值。首轮包含冷启动的项目单列，不将其伪装成热路径。

### 5.1 Core 历史读取与编解码

固定记录为 128-byte opaque callData + 256-byte signed extrinsic。

| records | 编码 bytes | encode 中位/P95/max ms | decode 中位/P95/max ms | decode CV |
|---:|---:|---:|---:|---:|
| 0 | 74 | 0.0087 / 0.9856 / 0.9856 | 0.0085 / 0.1548 / 0.1548 | 155.10%（冷样本） |
| 1 | 684 | 0.0585 / 0.0613 / 0.0613 | 0.0728 / 0.1061 / 0.1061 | 18.08% |
| 100 | 61,074 | 3.1271 / 4.0275 / 4.0275 | 3.8273 / 4.6410 / 4.6410 | 12.00% |
| 1,000 | 610,074 | 19.7908 / 23.0805 / 23.0805 | 24.9460 / 26.1307 / 26.1307 | 2.06% |

公开 history page（最多返回 100 条）中位/P95/max 分别为：0 条 `0.0020/0.0257/0.0257 ms`，1 条
`0.0058/0.0079/0.0079 ms`，100 条 `0.0351/0.0525/0.0525 ms`，1,000 条
`0.1885/0.2670/0.2670 ms`。page 投影成本较低，主要增长在整包持久化编解码。

### 5.2 操作测试进程上界

下表的 wall/RSS 是一个已缓存 Cargo 精确测试进程的整体上界，包含 test harness、动态库和 allocator；不能解释成
单个 SDK API 的净耗时或 SDK heap。

| 路径 | wall 中位/P95 s | RSS 中位/P95 MiB | RSS CV |
|---|---:|---:|---:|
| wallet create + sign | 0.17 / 0.17 | 90.734 / 90.984 | 0.17% |
| wallet import | 0.62 / 0.62 | 90.641 / 90.813 | 0.14% |
| generic sign | 0.11 / 0.12 | 90.922 / 91.719 | 0.45% |
| prepare bound | 0.10 / 0.10 | 90.875 / 90.984 | 0.14% |
| cancellation | 0.09 / 0.10 | 91.125 / 91.797 | 0.42% |
| QR consume | 0.07 / 0.07 | 80.469 / 80.719 | 0.19% |
| verified storage | 0.13 / 0.13 | 104.250 / 104.563 | 0.26% |

### 5.3 离线 provider 生命周期

| 阶段 | 中位/P95/max ms | CV | 说明 |
|---|---:|---:|---|
| create | 0.1266 / 1.2200 / 1.2200 | 126.02% | 首轮冷启动 1.2200 ms |
| start | 0.5821 / 8.6755 / 8.6755 | 147.69% | bootNodes 为空；首轮冷启动 8.6755 ms |
| export | 549 bytes（5/5 相同） | 0 | 已有上游 export_state |
| stop | 0.0113 / 0.0927 / 0.0927 | 120.96% | 首轮冷启动 0.0927 ms |

测试只调用 `native/smoldot/provider` 的公开 provider；没有修改 `native/smoldot/pow/**`，也没有重实现上游
交易、watch 或数据库能力。

## 6. 数据库与增长基线

CitizenSDK 的平台宿主当前内置两个 SQLite 文件，这不是 1.10.1 新增：

- `public-state-v1.sqlite3`：`singleton_records` 保存链数据库快照和整个 execution history BLOB；
  `runtime_cache` 按 block hash 保存 runtime metadata。
- `secure-state-v1.sqlite3`：钱包 profile、加密 secret envelope 和 vault 状态。

本轮只在仓库外构造与生产一致的 public schema/PRAGMA，未读取任何 App、Wallet 或用户数据库。4096-byte page，
WAL 完整 checkpoint 后关闭；重开为 SQLite open + 读取 BLOB 长度，Core decode 时间单列在第 5.1 节。

| executions | 逻辑 BLOB bytes | DB bytes | singleton table bytes | reopen 中位/P95/max ms | CV |
|---:|---:|---:|---:|---:|---:|
| 0（无记录行） | 0 | 16,384 | 4,096 | 0.3631 / 0.3712 / 0.3712 | 6.11% |
| 1 | 684 | 16,384 | 4,096 | 0.3850 / 0.4154 / 0.4154 | 6.23% |
| 100 | 61,074 | 73,728 | 61,440 | 0.3592 / 0.4857 / 0.4857 | 15.24% |
| 1,000 | 610,074 | 626,688 | 614,400 | 0.3496 / 0.4331 / 0.4331 | 10.81% |

“0 条已持久化 history state”的 Core 编码为 74 bytes；表中的 0 是全新数据库里尚无 history 行，两者不是同一状态。
截断 BLOB 被完整性校验拒绝。64 个各 4,096-byte 的 runtime cache 记录逻辑共 262,144 bytes，DB 为
319,488 bytes，表/索引为 299,008/12,288 bytes，重开中位/P95/max 为
`0.3447/0.3907/0.3907 ms`。

retention 实测：把 1,000 条 BLOB 替换为 1 条后，逻辑数据降到 684 bytes，但文件仍为 626,688 bytes，153 页中
149 页进入 freelist；关闭重开仍读到正确的 684 bytes。该结果说明当前普通更新不会归还物理文件空间。

## 7. 生命周期与平台对照

| 层 | start/stop/close 合同 | 本轮运行证据 | 未验证项 |
|---|---|---|---|
| Core Engine | Created → Starting → Running → Stopping → Stopped；running 必须先 stop 再 close | Rust workspace | 真实网络重连 |
| smoldot provider | 复用现有 start/stop/export/import/submit/watch | 离线 start/export/stop、import、prestart watch fail-closed | 联网 submit/watch/reconnect |
| Dart session | open/close 独占；start/stop 顺序；session/request sequence 过滤迟到事件 | 源码合同 | Flutter runtime 未运行 |
| Android Kotlin/JNI | 绑定同一 Core 生命周期和 host store；close 有监督重试 | 源码合同 | Java/Gradle/真机未运行 |
| Apple Swift | actor/lease/close admission；running 必须 stop-before-close | Swift 源码合同；Core ABI 本轮可构建 | Flutter adapter/真机未运行 |
| Linux/Windows C++ | host registry lease；stop-before-close；SQLite public/secure store | 源码合同 | 对应远程 runner 未运行 |

未运行项不能由源码扫描替代；统一留给 1.10.6。前后台切换属于消费 App 生命周期输入，SDK 当前公开 start/stop/close，
没有第二套 App 专用同步器。

## 8. 问题清单

### P1-01：持久 runtime cache 没有容量/字节淘汰

- 复现：`persistent_runtime_cache_currently_grows_past_the_memory_cache_limit` 连续请求 80 个唯一 block；内存 cache
  上限为 64，但持久 store 为 80，delete 调用为 0。
- 源码事实：`native/engine/src/engine.rs::runtime_context_at` 在 miss 后 `store(context)`，没有与内存 LRU 淘汰联动；
  各平台 `runtime_cache` 表只提供按 hash load/store/delete。
- 影响：长期跟随新区块可无界增加 `public-state-v1.sqlite3`，属于通用 SDK 资源边界问题。
- 归属：1.10.2。建议在 Core 中建立与准确 block 身份一致、按数量与总字节双重限制的持久 cache 淘汰合同，再由
  宿主执行 Core 指定的 delete；不按 App/pallet/action 分类。
- 合同/上游：可能新增内部 store 枚举/批量删除能力；不需要修改公开 App API，不需要修改 smoldot PoW 上游。
- 1.10.2 最终处置：不扩展 store ABI；四个平台在现有 store 事务内按 rowid FIFO 收敛为 64 条，Core/PoW 不改。

### P1-02：历史 record 数量上限与宿主字节上限不一致

- 复现：每条记录使用合法的 1 MiB callData 和 1 MiB + 512 bytes signed extrinsic。15 条编码为 31,468,424 bytes；
  16 条在仍远低于公开 4,096 条上限时被 33,554,488-byte host record 上限拒绝。
- 影响：调用方遵守所有单字段和记录数合同仍可能在持久化阶段失败，pending-before-broadcast 无法可靠承诺到
  4,096 条最大尺寸记录。
- 归属：1.10.2。先定义总恢复材料字节预算和 admission/backpressure，再决定记录数/字段上限是否需要公开合同变更；
  禁止静默截断 signed extrinsic、callData 或 finalized 证明。
- 合同/上游：如果更改公开上限或错误语义，必须在 1.10.2 方案中单列确认；不涉及 smoldot PoW 上游。
- 1.10.2 最终处置：保留 4,096 条并新增 31 MiB durable weight；签名前只读预检、pending CAS 复检，
  只驱逐最旧终态，open record 不可驱逐。

### P1-03：runtime metadata 合同上限与宿主记录上限不一致

- 复现：Core `RuntimeContext::try_new` 接受 8 MiB metadata（公开合同允许到 64 MiB），但加上 typed headers 后，
  `encode_runtime_context` 已超过 8,388,664-byte host record 上限并返回 `PayloadTooLarge`。
- 影响：provider 返回符合 Core 合同的 metadata 后，首次调用可以成功，但写持久 cache 失败并反向使整个
  `runtime_context_at` 失败；公开上限 64 MiB 与可持久上限不一致。
- 归属：1.10.2。Core 功能上限与可重建持久 cache 容量必须按职责分开，不能让 cache 写失败反向阻断合法链读取。
- 合同/上游：公开 Core 上限继续为 64 MiB；完整持久记录保持 8 MiB，metadata 可持久部分为
  `8 MiB - 111 bytes`。更大的合法值只进内存、不调用宿主 store；不修改 smoldot PoW 上游。

### P1-04：execution history 单 BLOB 为 O(N) 编解码与整包重写

- 复现：代表性 1,000 条记录 Core encode/decode 中位数为 19.79/24.95 ms；每次 load/CAS 都处理整个 state。
- 影响：数量和恢复材料尺寸增加时，单次历史读取/更新复制、内存峰值和写放大线性增长。
- 归属：1.10.4。按通用 execution id/status/time/byte budget 设计分页或分片持久化；不得加入业务字段。
- 合同/上游：会涉及宿主内部 schema 时必须单独列出且不做旧数据迁移/兼容；不涉及公开业务 API 或 PoW。

### P1-05：retention 不回收 SQLite 物理文件

- 复现：626,688-byte DB 从 1,000 条缩到 1 条后大小不变，149/153 页空闲。
- 影响：逻辑 retention 不能控制长期磁盘占用。
- 归属：1.10.4。评估受监督 checkpoint/incremental vacuum 或有界重建，必须保留原子性、权限和损坏恢复门禁。
- 合同/上游：仅平台内部持久化策略；不涉及公开 API 或 PoW。

### P2-01：操作级资源测量精度不足

- 证据：当前 RSS 是测试进程整体上界，不能分离 SDK heap；冷启动使 provider 5 样本 P95/CV 显著偏大。
- 归属：1.10.3 提供不含秘密/业务语义的阶段标识；1.10.4 建立 release 构建、预热后 operation-level 测量。
- 合同：若新增公开诊断事件或字段，必须单独确认；不得增加生产 benchmark hook。

### P2-02：真实网络和跨端运行矩阵不完整

- 证据：Flutter 按用户要求未操作；本机 Java 缺失；Linux/Windows 和移动真机没有本轮 runner 授权；离线 provider
  不覆盖 reconnect/submit/watch recovery。
- 归属：1.10.5 完善生命周期合同测试，1.10.6 在已有工具或授权 runner 上执行。未授权前保持“待验证”。

## 9. 可重复命令与验收结果

所有 Rust/Release 命令都通过唯一入口，且 Cargo target 位于外部缓存：

```text
scripts/test.sh cargo -p citizen-sdk-engine --test baseline_resource_contract --locked -- --nocapture
scripts/test.sh cargo -p citizen-sdk-smoldot-provider --test baseline_lifecycle_contract --locked -- --nocapture
scripts/test.sh cargo -p citizen-sdk-ffi execution_history_codec_has_repeatable_growth_and_decode_samples --locked -- --nocapture
scripts/test.sh cargo -p citizen-sdk-ffi execution_history_record_limit_exceeds_the_current_host_record_byte_limit --locked -- --nocapture
scripts/test.sh cargo -p citizen-sdk-ffi runtime_metadata_contract_limit_exceeds_the_current_host_record_limit --locked -- --nocapture
scripts/test.sh cargo --workspace --all-targets --locked
scripts/test.sh release
```

原生 ABI 使用明确的仓库外路径：

```text
CITIZENSDK_WORK_DIR=<external>/abi-work \
CITIZENSDK_NATIVE_OUTPUT_DIR=<external>/abi-output \
scripts/build-native.sh abi-host
```

结果：基线 Rust 测试、完整 Rust workspace、ABI host 构建与 Release 闭集通过；`git diff --check`、业务词、其它
QR 版本、源码树 build/target/.build、CitizenWallet/PoW 零写入复核通过。Flutter 测试未运行，不计为通过。

## 10. 保护边界与后续

- CitizenApp 与 CitizenWallet 在本步骤开始前已有各自未提交修改；本步骤对两者 diff hash 保持不变，不宣称仓库 clean。
- `native/smoldot/pow/**` 文件树内容 hash 保持不变；本步骤只增加 provider 外围黑盒测试。
- 没有新增迁移、兼容层、App 业务模型、业务 pallet/action 分支或其它 QR 协议版本。
- 下一步只按第 1.10.2 技术方案处理 P1-01、P1-02、P1-03 及相关 fail-closed 资源门禁；生产修复需再次确认后执行。

## 11. 1.10.4 同机优化后对照（2026-09-11）

P1-04 已由合同形状关闭：Core 的 store 不再存在 `TransactionHistoryState` whole-value load/CAS；
页面每轮只发生一次 index load 与一次最多 100 条 page load，单条状态 mutation 只发生一次 index
load、一次目标 record load 和一次 mutation write。仓库外 debug 基线预热后 20 轮结果如下；计时
只作同机描述，不设跨机器阈值：

| execution 总数 | page 返回 | median | P95 | max | CV |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 2.750 µs | 4.542 µs | 6.250 µs | 0.352212 |
| 1 | 1 | 3.541 µs | 7.709 µs | 8.125 µs | 0.382544 |
| 100 | 100 | 131.542 µs | 136.792 µs | 144.417 µs | 0.024701 |
| 1,000 | 100 | 108.375 µs | 181.583 µs | 204.042 µs | 0.234283 |

P1-05 使用 Apple 与四端相同 SQL/schema 的实际 SQLite 仓库外测量。每条 opaque 测试 record 为
1,024 bytes；每个规模重开 20 次：

| 行数 | 逻辑 record bytes | main/WAL/SHM bytes | page/freelist | reopen median/P95/max | CV |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 45,056 / 0 / 0 | 11 / 0 | 0.875 / 1.196 / 1.448 ms | 0.229578 |
| 1 | 1,024 | 45,056 / 0 / 32,768 | 11 / 0 | 0.582 / 0.852 / 0.899 ms | 0.150902 |
| 100 | 102,400 | 208,896 / 0 / 32,768 | 51 / 0 | 0.521 / 0.691 / 0.803 ms | 0.150351 |
| 1,000 | 1,024,000 | 1,630,208 / 0 / 32,768 | 398 / 0 | 0.524 / 0.721 / 0.825 ms | 0.162507 |

1,000 条终态按十个有界 mutation 收敛为 1 条后，main 回到 45,056 bytes、11 pages、freelist=0；
每次只在 freelist 超过 16 页且超过总页数 25% 时执行最多 128 页 incremental vacuum 和受监督
checkpoint，没有 full `VACUUM`。这是 Apple 本机实测；Android/Linux/Windows runner 未运行，
不能由同 SQL 源码等同为对应平台实测。

P2-01 的生产边界没有新增 benchmark hook。P2-02 的 adapter 重订阅由确定性时钟测试固定为
1/2/4/8/16/30 秒封顶并在成功通知后复位；stream error 与结束都废弃旧订阅。真实 P2P 重连、
交易池和链数据库仍复用 smoldot provider，上游 PoW 未修改。Flutter 依用户边界仍未运行或操作。
