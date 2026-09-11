# CitizenSDK smoldot provider

本 crate 是随包 smoldot 轻节点到 `VerifiedChainClient` 的唯一正式适配层。它直接运行
`native/smoldot/pow/light-base`，并把轻节点已经验证的链事实收口为 exact-block、强类型
CitizenChain 合同。

公开边界只有：

- `SmoldotProviderConfig`：固定 `citizenchain` 链 ID 与协议 ID 的启动配置；
- `SmoldotVerifiedChainClient`：启动、停止、状态和 `VerifiedChainClient` 实现；
- `ProviderLifecycle` / `SmoldotProviderStatus`：供 Engine/ABI 如实生成能力状态。

`legacy.rs` 内的 JSON-RPC 只用于把当前 smoldot 服务适配成类型化合同。它是 crate 私有
allowlist，不公开 `rpc(method, params)`。所有 exact-block 读取先核对目标 header 与本地
canonical hash；finalized 调用还必须落在当前 verified finalized 锚内。runtime version 与
metadata 始终从同一个准确 block hash 读取。

历史 finalized 高度不再由按高度查询、best 通知或 mixed recent block cache 推断。provider 从
light-base 同步状态机的 exact verified finalized 锚开始，沿每个已验证 header 的 parent hash
回溯，核对响应 hash、SCALE header hash、高度与父链后才生成升序 finalized 引用。单批公共合同
最多 120 块，121、反向区间和长度溢出在生命周期/网络访问前拒绝；独立有界 proof-derived cache
只减少重复回溯，不改变验证结论。

`AccountNonceSource` 使用同一次 `AccountNonceApi_account_nonce` Runtime call 返回的账户、nonce、
best hash 与高度 typed snapshot。该值不是交易池感知 RPC；Engine 的持久同账户
Pending/InBlock single-flight 承担本地 nonce 防复用职责。

区块体直接使用 light-base 的 `chain_block_extrinsics(block_hash)` typed API，不再绕回
`chain_getBlock`。批量 storage 的 typed snapshot 同时返回证明实际绑定的 block number/hash
与按请求顺序排列的值；provider 只有在该身份逐字节等于请求块时才接受一次 batch 的结果。
因此链头在异步操作中出现 A→B→A 也不能把 B 的状态冒充 A。历史准确块、调用中观察到不同
块或 finalized surface 与 verified finalized 不一致时，继续逐 key 使用带目标 block hash 的
私有 `state_getStorage`；返回长度错误同样失败关闭，原顺序和重复 key 不做映射或去重。

提交入口会对完整的已签名 SCALE extrinsic（包括 Compact 长度前缀）独立计算
CitizenChain/Substrate Blake2-256；轻节点返回的 hash 必须逐字节一致，否则提交事实按完整性
错误关闭。接受提交仍不等于入块、finalized 或 runtime 执行成功，最终结论继续由 Engine 使用
目标块 body、同块 metadata 与 `System.Events` 核验。

导入状态只允许发生在首次 `start` 之前；数据库正文必须是非空 JSON、至多 256 KiB，并与
CitizenChain 身份、格式版本和 finalized 锚一致。启动时 provider 会检查 smoldot 确实采用
本机数据库锚；导出则在数据库读取前后核对 verified finalized 未移动。

若导入数据库损坏或真实启动锚不匹配，provider 会先销毁已创建的 smoldot chain，再进入
不可复用的 `StartFailed`。低层 provider 不在污染实例上静默重试。需要复现归档 legacy Dart
差分基线的回退行为时，测试宿主必须删除被拒的持久 database，销毁旧 provider/Engine，创建全新的组合，
并且不再调用 `import_state`，让新实例只从 chainspec 随包的 #0 `lightSyncState` 启动。
产品 ABI 若承诺自动回退，必须在其 composition 层原子完成这一流程。

普通 C ABI worker 不处于 Tokio context；它通过 `drive` 在 provider 自有 runtime 上执行
provider/Engine future。`drive` 不公开 runtime handle 或 RPC，且拒绝从 Tokio context
嵌套调用，避免 `tokio::time` 脱离 runtime 或嵌套 block-on panic。

`native/smoldot/ffi` 只保留归档 Dart/smoldot macOS `arm64` 差分测试所需的 legacy
`smoldot_*`/`citizen_sr25519_*` 符号边界。本 crate 不改变其句柄、回调、库名或任意现有
符号；根 Dart、Android 与 Apple 已经通过上层产品级 `citizensdk_*` C ABI 消费本 provider。

第 1.9 步的 CitizenApp-shaped 与 third-party-shaped fixture 各自生成不同 storage key 和 opaque
RuntimeCall，但都只进入同一 `VerifiedChainClient`/Engine 路径。本 provider 不登记这些业务 key、
事件或 call schema；本步骤也不修改 `native/smoldot/pow/**`。
