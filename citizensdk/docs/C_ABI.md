# CitizenSDK C ABI contract

当前闭集为 89 个 Core 函数、Linux/Windows 各 17 个 Host 函数，另有 3 个 ZXing-C++
图像窄包装函数。六模块运行期选择复用
同一 Rust 装配；旧 ABI v1 结构/数值与默认构造保持。模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

异步 admission 在接受请求前预留一个结果和一个真实完成事件槽位；队列容量为 64，
容量用尽返回 `QUEUE_FULL`，不得先接收请求再丢失完成事件。普通事件与完成事件均即时
入队，任何发送都不得持有 enqueue 锁等待宿主回调；结果所有权及一次释放合同不变。
钱包转账恢复复用现有高层调用，不新增 raw extrinsic 返回值、恢复符号或 ABI 布局。

## Boundary

`native/ffi` and root `include` define the one product ABI. Official Dart,
Swift, Kotlin/Java and C/C++ bindings must consume this ABI; they must not
retain a provider or call smoldot JSON-RPC. The typed root Dart API, Android
Kotlin/Java and Flutter projections, and shared Darwin Swift/Flutter projections
consume this ABI. Every exported product
symbol has the `citizensdk_` prefix. Legacy `smoldot_*` and
`citizen_sr25519_*` symbols are not included by the product header.
既有 73 个函数保留，新增 `citizensdk_validate_modules`、
`citizensdk_create_with_modules` 与 `citizensdk_verify_signature`；再补充
`citizensdk_get_genesis_hash`、`citizensdk_get_finalized_account_balances`、
`citizensdk_result_get_account_balance_count`、`citizensdk_result_get_account_balance_at`，以及 9 个
QR 协议、审阅、签名与结果入口，当前共 89 个。
QR 解析和会话时间由 Core 管理；公开结构通过有界 UTF-8 JSON 复制。
异步审阅结果由 `citizensdk_review_qr_sign_request` 创建，由 `citizensdk_sign_qr_request`
一次消费，均使用原结果注册表、事件及释放合同；`citizensdk_result_copy_qr` 只复制公开内容。
旧待签字节 getter 与外部签名拼装入口不再存在。Flutter 不公开审阅结果句柄。
模块验证是无副作用公共入口，必须在平台业务资源创建前调用；模块构造只装配已选择服务。
纯验签无需 handle，直接验证公开账户、64 字节签名与消息；无效签名返回 false，参数编码错误
独立报告。它不创建实例、链数据库、金库或事件订阅。

The Step 7.1 Linux C/C++ Host source projection also consumes this exact ABI.
Its header-only C++ facade does not define another binary contract, and its Host
library must not re-export or duplicate the Core symbols. Step 7.4 includes
the official Linux Flutter registration and both LinuxARM/LinuxAMD projections
in the same-version candidate contract. 当前合同为 89 个 Core 函数、17 个 Host 函数与 3 个 QR 图像函数；
actual platform builds and execution
remain subject to the later unified GitHub CI/Release validation.
源码候选合并 27 项同版安装件；Hosted 只增加 12 项 plugin 输入，不携带 Host 私有实现，
也不创建第二份 Core。公共注册不表示 Linux 已运行或正式发布，缺少运行件不能生成可分发候选。
The Linux Host ABI v1 is a closed set of 17 `citizensdk_host_*` functions that
compose and own the root instance; `citizensdk_host_abandon` is only an ownership-transfer escape hatch
for a destructor that can no longer report a close error. It schedules the same
checkpoint-first monotonic teardown and does not create a second Core ABI.
The C++ destructor makes only finite callback-clear/destroy attempts before that
transfer and terminates if ownership cannot be transferred safely. Its
`EventObserver` only borrows each event/result synchronously; the observer must
not retain or release the result because the wrapper releases every nonzero
result exactly once after normal or exceptional observer return.
Every Host call obtains a lease through one admission/closing fence. Destroy
first closes admission, then waits for API, callback, private-route, Vault and
wallet-UI leases without holding a lock a re-entrant root callback needs;
callback and parent-window installation use the same linearization boundary.
Completions that arrive synchronously while a private route is being installed
remain lossless for 65 or more events and concurrent bursts; a fixed local
buffer limit is never permission to release an otherwise owned result.

仅选择 chain 时加载随包 manifest、chainspec 与 light sync state；Rust 在创建 provider 前复核
身份、SHA-256、完整 genesis #0 header、hash 和 state root，远程配置不能替换这些信任锚。
未选 chain 不创建轻节点或链数据库。现有正式包装仍为 full 并携带链资产，模块选择不缩包。
所有构造入口进入同一私有装配；旧入口保留默认组合，显式模块入口使用同一依赖与编译支持
验证。宿主不得注入 signer、nonce、light client 或任意键值服务。

## Versioning and ownership

账户私钥查看的公开控制位于钱包原生门面和桌面Host，不新增公开Core秘密getter。
独立Core动态库另有精确四个内部链接符号，构建期私有头只供SDK自有视图使用，
不安装、不进入公共模型或Flutter。Apple最终framework隐藏这些内部符号。
原生清屏确认与Core认证/回调真实排空都完成后，公开操作才结束；阶段通知不能当作终态。

创世哈希是同步复制的 32 字节公开值，只读取 Core 固定链身份，不访问网络或钱包。
未编译或未选择 chain 返回 `UNSUPPORTED`；实例必须存活，但不要求 Running 或链同步就绪。
批量余额使用既有异步请求/结果所有权，复用单余额结构和 Core 的同块批量读取。
输入允许 0..1990 项，保留顺序和重复项；空输入仍通过模块、生命周期及链能力门禁，
不产生存储读取。结果为 `ACCOUNT_BALANCES`，通过 count/at 逐项读取；不存在部分成功结果。
该有限读取请求不支持取消，close/destroy 必须等待请求与结果排空，不丢弃正在执行的读取。

- ABI version is `1`; all structures use fixed-width fields and the v1 product
  targets are 64-bit architectures.
- Extensible structures begin with `struct_size` and `abi_version`.
- Instance and result handles are process-wide nonzero monotonic `uint64_t`
  values. Request IDs are nonzero monotonic within one SDK instance; different
  instances may use the same request number, and hosts route it through that
  instance's callback context. No ID is reused inside its stated scope,
  preventing stale-handle ABA.
- Inputs are copied before an asynchronous function returns. Mnemonic and
  password inputs go directly into zeroizing Rust containers; bindings must
  clear their own mutable buffers and UI controls after the call returns.
  Apple text controls necessarily create Swift `String` values that cannot be
  reliably erased in place, so they remain confined to the SDK-owned flow and
  are never returned by public Swift API, logged, persisted, or sent to Flutter.
- Result data stays in a Rust-owned registry and is copied into caller buffers.
  `citizensdk_result_release` removes one handle; a second release returns
  `INVALID_HANDLE` without dereferencing freed memory.
- Destroy returns `BUSY` while any accepted request or owned result remains.

## Asynchrony and events

An accepted request emits exactly one `REQUEST_COMPLETED` event. Completion
delivery uses a bounded queue with backpressure and cannot be silently dropped.
Before acceptance, the runtime reserves both one unique nonzero result handle
and one completion-event sequence capacity unit. Ordinary events and watch
updates cannot consume reserved completion capacity. Concrete sequence numbers
are assigned only when events enter the queue, preserving strict callback order
under concurrent completion. If either monotonic space is exhausted, the call
fails synchronously before returning a request ID; rejected/unqueued requests
remove their reserved registry slot and return the event capacity without ever
reusing a numeric handle. Therefore exhaustion cannot create a zero-result
completion, unreachable owned result, or destroy-blocking orphan.
Watch updates use the same 64-entry bounded queue but fail the watch with stable
`QUEUE_FULL` if the host cannot keep up; the mandatory completion still follows.
The worker may complete before the accepting ABI call has returned, so the
callback can race with `out_request_id` publication. Hosts must route directly
by `event.request_id` and must not assume the return happens first.

Callbacks run on one dedicated per-instance dispatch thread without holding an
Engine, registry, result or callback-state lock. Callback replacement waits for
the old call to return and increments a generation; queued events from the old
generation can never consume the new context. Destroy from the callback returns
`BUSY` before any provider/Engine mutation. Successful destroy waits for an
in-flight callback and guarantees no later callback.
Capability subscribe and unsubscribe are also rejected from the callback before
starting, taking or joining the monitor, preventing bounded-event backpressure
from forming a callback/monitor join cycle.

Callback changes, request acceptance, capability subscription control and
destroy share one linearization gate. While a callback or subscription
transition is waiting, new requests and conflicting controls return `BUSY`;
the gate is not held while waiting for an in-flight callback or monitor thread.
Thus clearing/replacing a callback cannot strand an accepted completion, and an
active capability monitor always retains a registered callback.

For durable chain-backed instances, start, stop and import are
exclusive requests on this gate. They reject acceptance while an earlier
asynchronous request is pending, then reject every later request, callback or
subscription control, and destroy until their result is committed. The current
stop request is the only exception: its own request ID authorizes joining the
capability monitor that predated the reservation. Legacy instances keep their
original shared request admission.

Host-operation reservation has a second per-instance teardown gate. Destroy
closes it atomically with pending insertion, scans for accepted host callbacks,
and reopens it before returning recoverable `BUSY`. Once the scan is empty,
request acceptance stays closed and the capability monitor can be joined
without starting another host callback. This prevents both a missed late
reservation and a main-thread destroy waiting forever on a newly created vault
operation. Exactly-once claim moves an operation from pending to completing;
the completing record remains visible to the destroy scan until validation,
host-memory copying and completion delivery have returned.

Successful callback installation and monitor installation are their respective
commit points. Their immediate capability/lifecycle notifications are
best-effort (the same state is synchronously queryable), so these calls never
return failure after silently retaining a newly committed host context or
monitor. Long-lived raw-extrinsic watches and high-level wallet-transfer
terminal futures use a separate bounded four-worker pool; they cannot consume
the short-operation workers used for lifecycle, reads, state and submit.

Every copy function accepts `buffer = NULL, capacity = 0` as a successful size
query and writes `out_required`. Text payloads are UTF-8 bytes without a
trailing NUL.

Raw extrinsic watch and high-level wallet-transfer watch are cancellable after
acceptance. Cancellation yields one completion with `CANCELLED`; dropping a
wallet transfer future does not clear durable Pending/InBlock state. Start,
stop, import, submit and finite reads are explicitly non-cancellable after
acceptance; cancellation returns `UNSUPPORTED`, so a host is never told that a
side effect was rolled back when its outcome is actually uncertain or already
committed.

Destroy returning `BUSY` is a pure preflight failure and leaves the live handle
usable. If destroy reports another error after teardown has begun, that handle
is teardown-only: new requests, callback changes and subscriptions are rejected,
and the host must retry destroy. This makes partial monitor/provider/dispatcher
cleanup convergent instead of silently reopening a partially disposed runtime.

The shared Apple binding implements this rule with an explicit ABI +1 retain
lease over every borrowed HostBridge, callback, store and vault context. Its
teardown phases are monotonic: live, monitor stopped, callback cleared and
destroy-only, then closed. Callback clear is committed before the first destroy;
after that point only destroy is retried. Successful destroy drops HostBridge
and its SQLite stores first and releases the ABI +1 exactly once. A forgotten
close, a partial teardown or a failed Flutter detach transfers the complete
facade to a process supervisor rather than releasing borrowed contexts early.

Apple capability and lifecycle C callbacks only enqueue work. Core queries and
publication run later on a dedicated serial queue, and callback delivery, queue
claim and close share one linearization rule. This prevents a C callback from
re-entering Core while teardown waits for that callback. Flutter detach revokes
both handlers, permanently invalidates the event epoch, clears the sink, then
cancels every session before waiting for any close; one failed session is handed
to the same supervisor and cannot skip later sessions.

Provider and typed-store `ContractErrorCode` values are preserved through the
Engine and mapped one-to-one to the stable ABI status family. Network, timeout,
invalid-state, integrity, authentication, storage, and decode failures are not
collapsed into a generic unavailable error; diagnostic text remains secondary
and thread-local.

## Host services

The v1 host bundle separates chain database, exact-block runtime cache, wallet
profile, transaction history, encrypted-secret blob storage and KEK/DEK vault
operations. Public and secure stores are separate vtables and every operation
has a named field; there is no public `put(key, bytes)` escape hatch. Rust wraps
typed state in a versioned, domain-bound envelope before calling the host and
validates the full envelope again before reconstructing a contract value.
五类 store 与 Vault 仍是职责隔离合同，但按选择提供：chain/history 需要 public store，
wallet/signing 需要配套 secure store 与 Vault。签名服务只访问同宿主已安全建立账户的归属资料，
不等于启用钱包管理；首次 provision 仍经钱包流程。所有官方绑定采用相同的 public/secure
数据域隔离，不提供任意键值旁路。

The Linux Host implements the same five operations over separate public and
secure SQLite files and combines them with a TPM 2.0 vault. TPM callbacks wrap
or unwrap only a random 32-byte DEK; the SDK-owned device-vault unlock secret,
mnemonic, BIP-39 password, child mini-secret and private key have no public Host
record or result representation. Absence of a qualifying TPM or strong local
authentication must report the corresponding vault availability and keep
wallet/signing capabilities not ready; it must not select a file or Secret
Service software fallback.
Linux wallet-flow presentation first requires an opened public Core, then
returns `UNSUPPORTED` when wallet hosting is disabled or `UNAVAILABLE` when the
configured TPM/authentication facts are not available. These checks happen
before a GTK window can be created.
A failed prepared-wallet release keeps both the handle and wallet-flow
lifecycle lease owned by the flow. Its supervisor retries until Core confirms
release; only then may registry removal and Host teardown continue.

Host operations use acceptance plus exactly-one completion. A callback that
returns a non-OK synchronous status must not later complete; one that accepts
must complete exactly once. Ordinary input pointers are borrowed only for the
callback invocation and completion output is borrowed only for the completion
call. `wrap_dek` is the only input-lifetime exception: its exact 32-byte view is
Rust-owned and remains valid until synchronous rejection or the first
completion, then is zeroized; an asynchronous Swift/Kotlin bridge must use that
native memory directly and must not retain it afterward. The host context must
remain alive until successful SDK destruction.

Every non-null completion repeats `host_operation_id`, and the SDK compares it
with the operation ID encoded by the callback token before reading or claiming
the pending registry. A crossed token/result identity pair is ignored and
cannot cancel, complete, consume, or observe either live operation. A null
result has no second identity and remains the terminal integrity failure for
the operation selected by its token. Only a matching non-null pair may advance
from Pending to Completing.

For a durable chain-backed instance, `citizensdk_start` first loads,
validates and imports the typed chain database before any provider-start side
effect. `citizensdk_export_state` persists the same stable exported snapshot by
exact revision CAS before returning it. `citizensdk_stop` performs that durable
checkpoint before unsubscribe, product-service stop or provider stop; failure
leaves the running dependencies intact for retry. `citizensdk_destroy` cannot
wait on arbitrary asynchronous platform storage and is not a graceful
checkpoint, so a host must successfully stop first. None of these automatic
steps apply to the legacy session constructor.

`SecretVault` is implemented above this host contract. Rust generates a random
32-byte DEK and random nonce, AES-256-GCM encrypts the child mini-secret with the
complete `SecretRef` (product, wallet index, generation, owner, AccountId and
secret kind) as AAD, and asks the OS vault only to wrap that DEK. Both wrap input
and unwrap output remain in Rust-owned zeroizing buffers through completion.
Opening decrypts and signs inside Rust, then zeroizes the DEK and plaintext. The
OS bridge never receives a mnemonic, child mini-secret or sr25519 private key.
Apple Security APIs return an immutable `CFData` unwrap result. The adapter
keeps it inside one short-lived autorelease pool, avoids a bridged Swift
`Data`/copy-on-write copy, and immediately copies exactly 32 bytes into the
Rust-owned output buffer. That Security.framework-owned value cannot be
reliably zeroized in place and is released when the pool drains; it is never
returned by the public Swift API or represented on a Flutter channel. Rust
zeroizes its owned output after use.

## Capability truth

Every snapshot contains exactly these ten entries and a monotonic Engine-owned
revision: chain read, transaction build, transaction submit, transaction
verify, wallet profile, local signing, hardware vault, user authentication,
history and background sync.

The provider's own `SmoldotProviderStatus.is_usable` is the sole runtime input
for chain readiness. Peer count, height and elapsed time are not reinterpreted
by the ABI. Submit and verify depend on chain read. The legacy constructor is a
session-backed chain-only composition and continues to report wallet services
unsupported. 显式模块构造只启用已选服务，钱包管理、SigningService 与 history 独立；
唯一 Runtime nonce 与 sr25519 实现不由平台复制。Construction only reports these
components as supported but not ready; asynchronous worker-side probes determine
actual store, hardware-vault and authentication readiness without blocking an
Android or Apple main thread. Before that first probe, the affected capabilities
use `DependencyNotReady`; they do not misreport an unprobed device as
`DeviceUnavailable`.

`citizensdk_subscribe_capability_changes` starts a single per-instance monitor.
It consumes provider status, updates the Engine snapshot only on semantic
change and emits the new revision. Stop/unsubscribe joins the monitor; destroy
also closes it before stopping the provider.

## Typed chain and transaction surface

Public calls cover exact best/finalized heads, exact-block single/batch storage,
same-block runtime context, balances, exact best Runtime nonce and fee policy,
wallet lifecycle/multi-account management, local payload signing, high-level
`transfer_with_remark`, explicit finalized-history batches, complete externally
signed extrinsic submit/watch for chain-only compositions, exact-block execution
verification, and verified state import/export. There is no `rpc(method,
params)` call. Submission and inclusion remain distinct from runtime execution
success. The wallet transfer call persists Pending before provider access,
consumes submit-and-watch, and only completes with pool rejection or exact
finalized block/index `System.ExtrinsicSuccess/Failed` evidence. A dropped,
retracted, timed-out, disconnected or cancelled watch preserves durable
Pending/InBlock state for later history reconciliation.

State imported through this low-level ABI is provisional until start verifies
the exact local-database anchor. If that start fails, the provider and Engine
enter one-way `START_FAILED`; the binding must destroy the handle, create a new
instance and omit the rejected import to fall back to the packaged #0
checkpoint. Retrying the same mutated provider is forbidden. Automatic cache
deletion/retry exists only in the archived legacy Dart differential baseline;
all official Android, iOS and macOS bindings follow this explicit
destroy-and-recreate rule.

The Linux source adapter is required to follow the same rule. Step 7.1 did not
build or execute its C++ contract tests, so this paragraph records the adapter
contract rather than a Linux runtime verification result.

Private keys and child mini-secrets never cross this ABI. A prepared wallet
result owns its mnemonic in a dedicated Rust handle: the host may size-query and
copy it only for the explicit backup UI, commit consumes the prepared handle,
and release/destroy zeroizes an unused handle. Copy, release and commit all
require the owning live `CitizenSdkHandle`; another instance cannot guess and
read, release or consume the mnemonic. Import and account expansion accept
mnemonic bytes only as explicit user recovery input. This narrow boundary does
not permit a private-key export, raw signer, or persistent secret callback.

## Windows 薄 Host（第 8.1 步）

当前为 89 项公开 Core 根符号，既有数值/布局不变；跨库另有精确四项 SDK 内部查看控制。Windows 另固定 17 项 `citizensdk_host_*`，
配置平台 owner 字段为 `void *hwnd`，配置/钱包请求/公开结果分别为 72/32/16 字节。
Host 独占 Core 所有权；应用不能直接销毁借用 handle 或替换内部事件回调。关闭在 Core
释放后还要等待 UI 线程确认 HWND 退休，BUSY 时保留完整资源图。根 ABI 不增加秘密旁路。
