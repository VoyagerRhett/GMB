# CitizenSDK product C ABI

当前公共 Core 闭集为 88 个函数；ABI v1 既有结构和数值不重解释。

账户私钥查看另有SDK内部四操作链接闭集，声明由构建器生成而非进入公开include。
open不解密，reveal记录一次确认，cancel不丢弃实际认证future，finish仅表示原生已清屏/清零。
全生命周期request必须等原生清理及所有Core工作真实排空才完成；display只同步借用32字节，
settled不是终态。独立动态Core保留精确内部符号供自有Host链接，Apple最终framework隐藏它们。
运行期模块配置只选择同一 Core 服务与资源，正式包装仍为 full 并携带链资产。当前模块化与新增链查询仅完成源码、注释、合同和测试用例更新，尚未完成真实构建、平台测试或硬件验收；下文旧分步运行记录仅为历史证据。

This crate is the only product-level native ABI. Every exported symbol starts
with `citizensdk_`; language bindings do not receive a smoldot handle, an
arbitrary RPC method, a borrowed Rust secret pointer, a raw signer, or an
sr25519 private-key entry point.

The dependency direction is fixed:

```text
C / Dart / Swift / Kotlin
          |
          v
      citizensdk_*
          |
          v
 CitizenEngine -> typed contracts <- smoldot provider
```

The ABI uses fixed-width fields, `struct_size` and `abi_version` prefixes,
monotonic non-zero `uint64_t` handles, stable numeric errors, and owned result
handles. Result bytes are copied into caller memory and every result handle is
released exactly once. An instance cannot be destroyed while requests or
owned results remain, so an accepted request cannot silently lose its one
completion event.

Request acceptance first reserves a unique nonzero result registry slot and a
mandatory completion-event capacity unit. Other events cannot steal that unit;
event sequence values are still assigned at enqueue time so concurrent callback
order remains strictly increasing. Exhaustion rejects the call before a request
ID is returned, and rejection removes placeholders without reusing handles.

Callbacks run only on the instance's dedicated event-dispatch thread and never
while an Engine, registry, callback-state, or result lock is held. Destroying
an instance from inside its own callback is rejected as busy; destruction from
another thread waits for an in-flight callback and guarantees no later call.
Capability subscribe/unsubscribe are also rejected from the callback before
bounded publication or monitor join can wait on that same dispatch thread.
Callback/subscription transitions, request acceptance and destroy share a
per-instance linearization gate, but the gate is released before waiting for
an in-flight callback or monitor. Registration is the commit point; immediate
state notifications are best-effort and remain synchronously queryable.
Completions may race with the accepting ABI return, so bindings route by the
event's request ID. A non-`Busy` failure after destroy starts leaves a
teardown-only, retry-destroy handle instead of reopening partial lifecycle work.
Host-composed start, stop and import reserve that gate exclusively: prior
asynchronous requests must complete before acceptance, and later requests or
controls receive `Busy` through completion. Only the owning stop request may
join a capability monitor that existed before its exclusive reservation.

Long-lived raw-extrinsic watches and high-level wallet-transfer terminal
futures run on a separate bounded four-worker executor. They cannot starve
lifecycle, finite read, import/export, or submit work on the bounded
short-operation executor. Cancelling a wallet transfer drops the active future
and reports `CANCELLED`, but never clears durable Pending/InBlock history.

既有 73 个公共函数保留，新增 `citizensdk_validate_modules`、
`citizensdk_create_with_modules` 与 `citizensdk_verify_signature` 三个函数，
另有创世哈希、批量余额及两个批量结果读取入口，以及八个 QR 协议/会话入口，当前共 88 个。
模块验证在任何平台资源创建前执行；wallet/signing/chain/transactions/history 五位按同一规则
组合，旧构造仍进入同一私有装配函数并保持原默认组合。wallet 管理与签名不互相隐式启用，
history 单独初始化；仅 chain 构造 provider、读取链资产并使用链持久化，
wallet/signing 才需要配套 secure store 与 KEK/DEK Vault。
签名使用同宿主已由 SDK 安全建立的账户归属元数据，不提供首次 provision 或秘密导出旁路。
无实例纯验签不使用 handle、store、金库或事件订阅；签名无效返回 false，参数编码错误单独报告。

启用链且装配持久 store 时，start 在 provider 启动前恢复并验证链数据库，export 返回前持久化
同一精确 revision 快照，stop 在退订/停止依赖前 checkpoint。失败必须保留资源供重试；
destroy 不能替代 checkpoint。未选链的本地模块无需 start 轻节点，也不启动 smoldot。

Accepted host callbacks remain registered as outstanding both before and after
their exactly-once completion claim. The completing phase ends only after the
SDK has validated/copied host memory and delivered the completion; the remaining
extern-callback tail accesses no instance state. Destroy therefore cannot free
instance-owned state in the sensitive interval. Duplicate, rejected and late
completions remain pointer-free no-ops.

Before a non-null completion reads or claims the pending registry, its result
`host_operation_id` must equal the operation ID encoded in the callback token.
A crossed identity pair is ignored without consuming either operation. A null
result remains terminal for the token-selected operation; only a matching
non-null pair may move from Pending to Completing.

Prepared-wallet mnemonic bytes exist only behind an SDK-owned handle bound to
its owner instance and may cross the ABI solely for explicit creation/backup
UI. Import and account expansion accept explicit user mnemonic input. Private
keys and child secrets are never exported. Rust encrypts each child with
AES-256-GCM using a random 32-byte DEK, random nonce and full `SecretRef` AAD;
the host only wraps/unwraps the DEK, and unwrap writes directly into an exact
32-byte Rust-owned buffer.

The typed root Dart API, Android Kotlin/Java and Flutter projections, and the
shared Darwin Swift/Flutter projections use this C ABI and host composition.
The Apple host provides separate typed public/secure SQLite stores and a
KEK-only Secure Enclave vault; no secret or native handle crosses Flutter.

Build and test output must be redirected to
`/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk`. This source directory must
stay free of generated headers and native artifacts; there is intentionally no
`build.rs`.

Imported-state startup failure is a one-way `StartFailed` Engine transition.
Bindings must destroy that handle and create a fresh, never-imported instance
to fall back to the packaged #0 checkpoint; this ABI does not erase a rejected
host cache or retry it automatically.
