# CitizenSDK C/C++ headers

当前公共 Core 为 117 个函数；统一钱包状态、通用冷热签名、默认账户授权、安全链读取、通用交易准备与冷热执行闭环及只读失败阶段 getter 已加入，既有 ABI v1
结构和数值保持。当前模块化与新增链查询仅完成源码、注释、合同和测试用例更新，尚未完成真实构建、平台测试或硬件验收；下文旧分步运行记录仅为历史证据。

`citizensdk.h` is the only product header. It includes
`citizensdk_types.h`; it deliberately does not include `smoldot.h` and exposes
no raw smoldot client, arbitrary RPC, mnemonic, mini-secret or private-key
function.

Every extensible structure starts with `struct_size` and `abi_version`. Set
those fields to `sizeof(struct)` and `CITIZENSDK_ABI_VERSION` before passing an
input or output structure. All lengths and handles are fixed-width integers;
CitizenSDK ABI v1 supports the product's 64-bit target architectures.

Typical host order:

1. 先调用 `citizensdk_validate_modules`，由 Rust 检查模块闭集、依赖与编译支持；
2. 仅为所选模块准备资源：chain 才加载链资产与 public 链数据库，history 才初始化历史，
   wallet/signing 才准备配套 secure store 与 Vault，再调用 `citizensdk_create_with_modules`；
3. 需要链时安装回调并调用 start，读取能力；无链的本地模块不启动轻节点；
4. 每个非零事件结果按所有权合同释放一次；
5. 已启动链的实例先成功 stop/checkpoint，再释放结果、清回调并 destroy。

纯 `citizensdk_verify_signature` 直接接受公开账户、64 字节签名与消息，不创建实例或资源；
它与签名模块使用同一 Rust 密码学实现，但不要求启用 signing。

## Host services v1

模块构造复制被选择的 Host vtable，借用上下文直到销毁成功；不改变 Host services ABI v1 布局。
public store 仅在 chain/history 需要时提供；wallet/signing 的 secure store 与 secret vault
必须配套存在。SigningService 只读 SDK 已安全建立账户的归属资料，不等于启用钱包管理或安全
输入 UI；首次 provision 仍经 wallet 流程。宿主不能注入 signer、nonce、任意键值存储或 RPC。

For a host-backed instance, start automatically restores the typed chain
database before provider start; export and graceful stop persist an exact
revisioned snapshot. If persistence fails, stop has not unsubscribed or stopped
any dependency and may be retried. Direct destroy is not a checkpoint and must
follow a successful stop when the latest light-client state matters. Legacy
session instances keep explicit import/export and their original stop behavior.
Host start, stop and import are exclusive asynchronous lifecycle requests:
acceptance requires no earlier pending request, then later requests, callback or
subscription controls, and destroy return `BUSY` until completion. A host stop
may still join the capability monitor it exclusively owns.

Every host operation receives a unique `host_operation_id`. Returning
`CITIZENSDK_OK` accepts the operation and requires exactly one later completion;
returning any other stable error rejects it and forbids completion. Operations
may complete concurrently from background threads. Ordinary input views are
valid only during the operation callback; completion views are valid only
during completion and are copied synchronously by CitizenSDK. The sole input
lifetime exception is `wrap_dek`: its exact 32-byte view remains backed by a
Rust-owned zeroizing buffer until synchronous rejection or the first completion,
so an asynchronous platform bridge can use the native buffer without copying
the plaintext DEK into Swift/Kotlin-managed storage. It must not retain the
view after completion. Every claimed completion remains outstanding until SDK
validation, copying and delivery finish; the remaining callback tail accesses
no instance state, so destroy cannot race that work. Callback contexts remain
host-owned and must stay valid until successful instance destruction returns.
Before any non-null completion reads or claims the pending registry, its
`host_operation_id` must equal the operation ID encoded in the callback token.
A crossed token/result pair is ignored without consuming either operation. A
null result has no second identity and terminates the token-selected operation
with an integrity failure. Only a matching non-null pair may enter the
Pending-to-Completing phase.

The vault owns only generation-scoped hardware KEKs and 32-byte DEK wrapping.
Both `wrap_dek` input and `unwrap_dek` output use Rust-owned zeroizing buffers
whose lifetime ends at rejection/first completion; `unwrap_dek` receives an
exact 32-byte `citizensdk_mutable_bytes_view_t` and reports only status at
completion. It does not return plaintext through a byte-result callback. No
vault callback receives an account mini-secret, private key, recovery phrase or
signing request.

## Account and wallet results

CitizenChain amounts use `citizensdk_u128_t`: the numeric value is
`high * 2^64 + low`. Balance reads bind to an exact finalized block; nonce and
fee snapshots bind to an exact best block. A nonce result is Runtime state, not
a transaction-pool lease. Use `citizensdk_result_estimate_fee` while retaining
the fee-snapshot result to apply CitizenSDK's exact Perbill rounding and minimum
self-pay calculation.

Wallet operations return only public profiles/accounts, 64-byte signatures,
high-level transfer conclusions and typed history. They never return an account
secret or wallet-built signed extrinsic. Password and recovery-phrase inputs
are byte views borrowed only for the accepting call and copied into Rust-owned
zeroizing containers before return.

Wallet creation is two phase:

1. `citizensdk_prepare_wallet_creation` returns a result containing an
   independent, instance-owned `citizensdk_prepared_wallet_handle_t`;
2. the host size-queries/copies the recovery phrase only through
   `citizensdk_prepared_wallet_copy_mnemonic`, confirms backup with the user,
   then consumes the handle with `citizensdk_commit_wallet_creation`.

Release an abandoned prepared handle explicitly. Instance destruction also
drops its remaining prepared sessions. A commit accepted by the request queue
consumes the handle exactly once; a synchronous acceptance failure restores it.
Copy, release and commit all require the owning `citizensdk_handle_t`; another
live instance cannot guess, read, release or consume the recovery phrase.

`citizensdk_prepare_transaction` accepts an application-encoded opaque
RuntimeCall and returns only safe preparation facts. Execution consumes that
preparation once, signs in Rust or completes the existing `QR_V1` cold-signing
exchange, atomically persists the exact recovery authorization before provider
access, then submits and watches. Cancellation does not erase durable state or
withdraw an already broadcast transaction.

`citizensdk_get_transaction_history` reads deterministic newest-first pages of
SDK-submitted generic executions. `citizensdk_sync_transaction_history`
reconciles at most 32 non-terminal records and returns the resulting page.
Getters expose only hashes, protocol status, verified block/System outcome and
timestamps; callData, nonce, signature and signed extrinsic remain private.
Destination, amount, remark, direction and business events belong to the App.

The callback runs on a CitizenSDK dispatch thread. Do not destroy the instance
from inside that callback; the call returns `CITIZENSDK_ERROR_BUSY` without
changing provider or Engine lifecycle. Capability subscribe and unsubscribe
are likewise rejected from inside the callback before they can publish through
the bounded queue or join the monitor. Other SDK calls are reentrant.
Callback changes, subscription changes, request acceptance and destroy are
linearized per instance; a conflicting transition returns `BUSY` without
holding the gate while it waits for callback/monitor completion. Installing a
callback or subscription is the commit point. Its immediate state event is
best-effort because the same snapshot can be queried synchronously.

An asynchronous completion can race with and arrive before its accepting C
function returns. Route it by `event.request_id`; do not assume the host has
observed `out_request_id` first. `BUSY` from destroy is a preflight and leaves
the handle usable. Any other live-handle destroy failure after teardown starts
leaves a teardown-only handle; issue no new work and retry destroy.

Every accepted request has already reserved one nonzero result handle and one
mandatory completion-event capacity unit. If either monotonic space is
exhausted, acceptance fails synchronously without returning a request ID.
Ordinary events cannot consume reserved completion capacity, and rejected work
removes its placeholder without reusing the numeric handle.

Every copy function supports a first `buffer = NULL, capacity = 0` size query
that returns `CITIZENSDK_OK` and writes `out_required`. Returned text is UTF-8
without a trailing NUL byte.

`citizensdk_cancel_request` is effective for the long-lived raw-extrinsic watch
and high-level wallet-transfer watch requests. Atomic reads and other
state-mutating start/import/submit/stop calls return
`CITIZENSDK_ERROR_UNSUPPORTED` after acceptance rather than pretending that an
already executing operation rolled back.

An imported-state startup failure is one-way: the Engine enters `START_FAILED`.
The binding must destroy that handle and create a new, never-imported instance
to fall back to the packaged #0 checkpoint. ABI v1 does not delete a rejected
host cache or retry it automatically.

## Linux C++ projection

The Step 7.1 Linux source projection includes this same root C header and adds a
header-only RAII convenience layer under `linux/include/citizen_sdk`. The C++
layer owns the Host lifetime, carries opaque wallet-flow handles, and releases
result handles delivered through its event trampoline, but does not add a
second binary ABI, provider, signer, wallet model or arbitrary RPC surface. `CitizenSDK::Core` and
`CitizenSDK::Host` are CMake target names; the stable cross-toolchain boundary
remains the functions and fixed-width structures declared here.
The separate Linux Host ABI v1 is a closed set of 13 `citizensdk_host_*`
composition/lifecycle functions; it does not duplicate any of the 70 Core
product functions.

Linux Host 通过 `citizensdk_create_with_modules` 按选择提供具名 stores 与 TPM-backed DEK vault。 It cannot access a child mini-secret through
those callbacks. LinuxARM and LinuxAMD runtime libraries are not stored in the
source tree and were not built or validated in Step 7.1; public platform support
must not be inferred merely from the presence of the convenience headers.
Wallet-flow presentation requires an opened Core; disabled wallet hosting maps
to `CITIZENSDK_ERROR_UNSUPPORTED`, while a configured but unavailable TPM/auth
boundary maps to `CITIZENSDK_ERROR_UNAVAILABLE`, before GTK presentation.
If releasing a prepared-wallet handle fails, the Linux flow retains the sole
handle owner and its lifecycle lease while a dedicated supervisor retries; it
cannot erase the flow or let Host destruction proceed before Core confirms
release.
The Host owns its borrowed Core handle. Explicit close failures leave the Host
handle with the caller for retry; a C++ destructor transfers an otherwise
unreachable handle through `citizensdk_host_abandon` to the Linux process
supervisor instead of silently leaking borrowed Core/store/vault contexts. The
destructor performs only finite clear/destroy attempts; if even the ownership
transfer fails it terminates rather than freeing a callback context still
borrowed by Host. `EventObserver` receives an event/result only as a synchronous
borrow: it must not retain or release the result, because the C++ trampoline
releases every nonzero result exactly once after normal or exceptional return.
Every Host call first acquires a lease under the same closing/admission fence.
Destroy closes admission before waiting for extant API, callback, private-route,
Vault, and wallet-UI leases; callback and parent-window updates share that
linearization boundary. Teardown must not hold a lock needed by a callback that
re-enters the Host API. A synchronous completion burst while a private route is
being installed remains lossless beyond 64 events and under concurrency.

## Windows 平台 Host 头

`../windows/include/citizen_sdk/citizensdk_host.h` 提供 14 项资源装配 API，并不替代
本目录 117 项 Core ABI。C++ Host 为 header-only 所有权包装，不导出 STL ABI。HWND
仅作 UI owner 配置，设备口令、CNG 句柄及秘密不进入公开头。Windows 运行验收尚未执行。
