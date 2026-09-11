# CitizenSDK Core Contracts

本 crate 是 CitizenSDK Rust Core 的唯一依赖合同层。它只定义稳定的数据语义和对象安全
接口，不实现轻节点、sr25519、平台金库、Flutter 或任何产品业务。

依赖方向固定为：

```text
Engine -> Contracts <- smoldot / sr25519 / OS vault / typed stores
```

## 安全边界

- `VerifiedChainClient` 只提供带块身份的类型化链能力，不提供任意
  `rpc(method, params)` 逃逸接口。宿主传入的 hash/height/finality 只是未受信任值；
  `resolve_finalized_block` 必须由 provider 把它解析为 finalized canonical 事实，生产实现必须
  支持历史 finalized 块，不能只信任调用方的枚举位。
- `FinalizedAccountBalance` 只接受正式 `citizenchain` 身份和 finalized 块，`free + reserved`
  溢出会以 integrity 错误失败；`AccountNonceSource` 固定同一次准确 best Runtime
  `AccountNonceApi_account_nonce` 的账户、hash、高度和 nonce 快照。它不是交易池感知 RPC；
  Engine 必须以持久的同账户 Pending/InBlock single-flight 防止本地 nonce 复用，也不能拿
  `System.Account.nonce` 冒充该快照。
- `get_finalized_blocks_at` 的唯一公共范围合同最多接受 120 个连续高度；反向区间、121 块和
  长度溢出必须在网络访问及结果分配前失败。
- `OnchainFeePolicy` 把同一 runtime metadata 解出的正 Perbill 和正最低费绑定准确块，费率
  估算逐项复现 Runtime/Dart 的饱和乘加与 half-up 舍入，不提供本地费率兜底。
- `RuntimeContext` 始终把 runtime version、transaction version、metadata 与同一个
  `VerifiedBlockRef` 绑定。
- `SecretVault` 只负责系统金库保护、解锁与密文信封；`ChainSigner` 才负责 sr25519。
- `SecretBuffer` 不实现 `Clone` 或序列化，`Debug` 永远脱敏，底层字节由 `Zeroizing`
  在生命周期结束时擦除。API 只直接借给同步 Rust 闭包；闭包 provider 仍属于受信任
  进程边界，必须审查其不复制秘密，不能把这一接口夸大成同进程硬隔离。
- 五个数据存储合同分别保存轻节点数据库、runtime cache、钱包公开资料、交易历史和
  已加密秘密；加上 `SecretVault` 共六个隔离边界。没有通用 `put(key, bytes)`。
- `RuntimeCacheStore` 只定义可替换的性能缓存，不签发 provider 证明；交易执行核验必须直接
  取得准确 finalized 块的 provider runtime context，不能信任宿主可写缓存中的 metadata。
- 加密秘密状态只能 `Vacant -> Sealed -> Tombstone`，墓碑永久保留且 SecretRef 不复用；
  `SecretVault::delete_wallet_key` 同时必须持久退休 generation。二者共同封死跨进程 late writer，
  不能用进程内 mutex 或“删除后重新出现 Vacant”代替。
- 钱包合同固定 wallet index `0`、账户 index `0 = masterAccountId`、账户范围 `0..1989` 与
  SS58 prefix `2027`；SS58 必须从 AccountId32 重算核对。账户重命名修剪后只接受 1..30 个
  Unicode scalar，active 切换和子账户删除通过 `WalletProfile` 的安全重建方法重新执行全部
  profile 不变量。
- `OpaqueTransactionCall` 只保存有界 opaque RuntimeCall；
  `ImmortalSigningPayload` 要求 runtime context、准确 best Runtime nonce、账户、公钥、正式 genesis
  属于同一构造身份。`PreparedTransaction` 的 signer message 和 extrinsic template 不跨公开边界。
- `TransactionExecutionRecord` 完整保存 SDK 恢复所需的 callData、nonce 与 signed extrinsic，
  但 `TransactionHistoryRecord` 仅按白名单投影 hash、状态、验证块/System 结论和时间。
  `persisted_name` 固定为 `pending`、`inBlock`、`poolRejected`、`finalizedSuccess`、
  `finalizedFailed`；只有 finalized 同块同 index 的明确 Runtime 结论才能进入 Execution。
  store 最多 4096 条，只按确定顺序驱逐最老明确终态，绝不驱逐 Pending/InBlock。合同不含
  destination、amount、remark、direction、业务 pallet/event 或逐账户扫描游标。
- `WalletState::try_from_parts` 要求 create/import 的 previous 为空、计划精确拥有 target 全部
  secrets 并回滚删除 wallet key；append previous 必须是 target 账户列表的严格前缀且计划只
  拥有新增 refs。它还拒绝 provisioning/active cleanup 同时取得所有权、cleanup 命中当前
  secrets/KEK、跨 wallet generation、重复 operation ID 或重复物理目标。
- `EncryptedSecretBlobStore` 的类型系统只接受 `EncryptedSecretEnvelope`，不能接收明文
  助记词、mini-secret 或私钥。

## 三层账户边界

- 公民链层只处理 AccountId/SS58、finalized 余额、链上 fee、准确 best Runtime nonce、call、
  extrinsic 与历史事实。
- 产品无关密钥层只处理 BIP-39 派生、`SecretVault`、短生命周期 `SecretBuffer` 与
  `ChainSigner`；秘密不能成为仓储或语言绑定的公开返回值。
- TUYU、员工登录及其它业务账户协议不进入 contracts。它们可以把明确载荷交给密钥层签名，
  但 challenge、权限、会话和审计仍由各自业务体系定义。

## 异步与对象安全

所有 provider/store trait 返回 `ContractFuture` 或 `ContractStream`，因此可以作为
`dyn Trait` 由 Engine 组合，不依赖 Tokio、Flutter isolate 或某个平台线程模型。错误先使用
Rust 合同类别；稳定 C ABI 数字错误码在后续 `native/ffi` 中单独冻结，不能提前混为一层。

`import_state` 的“仅启动前、身份一致、格式一致、finalized 且不倒退”属于 Engine 必须再次
执行的安全门禁；provider 即使也检查，Engine 也不能信任它替自己完成验证。
`ChainDatabaseStore` 的 revision CAS 是持久状态合同，但跨 Engine 或进程原子性仍取决于具体
provider 是否提供共享、耐久、强原子 CAS；当前 Dart Preferences store 不自动满足该条件。
