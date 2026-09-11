# CitizenSDK Core Engine

第 2 步将钱包管理、签名、链、交易和历史显式模块化，所有平台只复用本目录同一业务逻辑。
`WalletService` 负责账户生命周期，`SigningService` 只经安全金库使用已建立账户的密钥；
历史有独立服务和门禁。当前模块化与新增链查询仅完成源码、注释、合同和测试用例更新，尚未完成真实构建、平台测试或硬件验收；下文旧分步运行记录仅为历史证据。

`citizen-sdk-engine` is the product-independent Rust coordination layer for the
single CitizenSDK product. It owns capability resolution, exact-block runtime
context caching, verified state import, and transaction execution conclusions.
It depends only on typed contracts and official SCALE/metadata tooling.

The dependency direction is fixed:

```text
language bindings -> stable C ABI -> engine -> contracts <- providers
```

The engine does not know Flutter, Swift, Kotlin, application navigation,
CitizenApp databases, TUYU, chat, square, shopping, booking, or arbitrary JSON
RPC. `native/smoldot/provider` now implements `VerifiedChainClient`, and
`native/ffi` exposes this Engine through the stable product C ABI. The typed root
Dart API, Android Kotlin/Java and Flutter projections, and shared Darwin
Swift/Flutter projections consume that ABI. Legacy `libsmoldot` is only an
macOS `arm64` differential-test host artifact and never a product runtime.

## Step 4.1/4.2 services and Step 5.1 wallet watch closure

- `AccountStateService` derives `System.Account` keys from exact metadata,
  reads finalized free/reserved/total balances, preserves input order and
  duplicates for batch reads, and binds fee constants to one exact best block.
  Nonces come only from one exact-best `AccountNonceApi_account_nonce` typed
  snapshot; the returned account, hash and height are rechecked. This Runtime
  value is not pool-aware, so durable same-account Pending/InBlock single-flight
  prevents a second local transaction from reusing it.
- `WalletService` implements English BIP-39 12/24-word create/import,
  `//0..//1989` derivation, add/rename/activate/delete, usability verification,
  and cleanup replay. Public profile CAS and exact
  generation/owner/operation identities are persisted before secret writes;
  write-after-error outcomes are decided by readback. Creation is explicitly
  two-phase: prepare returns a zeroizing in-memory recovery-word session with
  zero profile/blob/KEK writes, and commit is allowed only after the user has
  confirmed backup. Deleted secret refs become permanent tombstones and whole
  wallet generations are retired by the Vault. No private-key export exists.
- `TransactionPreparationService` validates application-encoded opaque
  RuntimeCall bytes against exact metadata, requires canonical full decoding,
  and uses official `subxt-core 0.43.0` to build an immortal, tip-zero signed
  extrinsic V4 with the exact best runtime, CitizenChain genesis and nonce.
- `TransactionExecutionService` consumes a preparation once, routes hot
  accounts through the Rust signer and cold accounts through the existing
  `QR_V1` external-signing session, then persists before provider access.
  The unlocked secret stays in `SecretBuffer`; source/public-key equality and
  the resulting sr25519 signature are verified.
- `TransactionHistoryService` stores only SDK-submitted generic executions.
  Public pages whitelist source/call/transaction hashes, protocol status,
  verified block/System outcome and timestamps; recovery callData, nonce,
  signature and signed extrinsic stay private. `InBlock` remains non-terminal.
- Explicit history sync and automatic recovery share the same canonical
  ancestry/body/events proof, CAS and generation fences. `Invalid/Usurped` are
  pool rejections; provider errors, stream end, `Dropped`, `Retracted` and
  timeout retain durable Pending/InBlock state. No transfer/event business
  projection or account-wide chain scan is implemented here.

`native/ffi::ProductComposition` 按已验证 modules 装配同一实现，不为平台或组合复制算法。
仅 chain 构造 smoldot provider、链数据库与 runtime cache，history 仅在被选择时初始化；
wallet 与 signing 各自持有独立服务门禁，并共享职责固定的 secure store/Vault 合同。
签名模块只使用同一宿主已有的 SDK 安全账户资料；首次 provision 必须走 wallet 流程。
无实例纯验签只调用唯一 sr25519 验证实现，不建立 Engine、链或金库。所有构造入口仍进入
同一私有装配函数；既有入口保留其默认组合，不能因此把一个组合的能力冒充整个产品边界。
Apple 的 public/secure SQLite 与其它平台遵守同一数据域合同，Secure Enclave 仅作 KEK，不执行 sr25519。

Finalized history requests one ascending batch of at most 120 blocks. The
provider proves the range from one verified finalized anchor by exact-hash
parent-header ancestry; best/recent caches are not evidence. Strict production
metadata type fingerprints gate every block before event values are trusted.
A generation lease spans all provider/store awaits and the final CAS, so stop
or dispose cannot cross a partially committed history operation.

## Verification rules

- A runtime context binds version and metadata to one exact best or finalized
  block. An older in-flight best request may be cached by its own hash but may
  never replace a newer best identity. The in-memory cache retains at most 64
  exact-block contexts with deterministic FIFO eviction while protecting the
  current best context; an evicted block is verified and fetched again.
- Imported light-client state is accepted only before startup and only after
  chain ID, protocol ID, genesis hash, format, finality, and non-regression
  checks succeed. The Engine owns this lifecycle and the fixed `citizenchain`
  policy; callers cannot claim `Created`. Once provider mutation has begun, a
  failed or cancelled import closes that Engine instead of reopening it.
- Import merges the Engine provisional anchor with the revisioned
  `ChainDatabaseStore` snapshot and persists the exact imported state through
  CAS. Cross-Engine or cross-process rollback protection requires a shared,
  durable, strongly atomic store provider; the retained legacy Dart Preferences
  store does not provide that guarantee.
- `restore_state_from_store` is a pre-start no-op for an empty store and routes
  every non-empty value through the same import, receipt and one-way failure
  gates. `export_and_persist_state` preserves the original `export_state`
  primitive while adding full revisioned-snapshot CAS and exact readback
  convergence for host-composed export and graceful stop.
- Startup rechecks provider identity and the provisional finalized anchor.
  Export is serialized per running generation and is accepted only when the
  verified finalized head is unchanged before and after serialization.
- The Engine owns capability revisions, cross-checks required component
  presence, and rechecks readiness immediately before sensitive provider
  access. `CHAIN_READ` and its dependants can be ready only while lifecycle is
  `Running`; lifecycle transitions and probe updates use one state-first lock
  order so a stale Running snapshot cannot reopen a stopped Engine.
  Provider/component getters are not exposed to upper layers.
- Product bindings use the Engine's typed `best_head`, `finalized_head`, exact
  storage, signed-extrinsic submit and watch methods. These methods repeat the
  lifecycle/capability check immediately before provider access and do not
  expose a provider handle or an arbitrary RPC escape hatch.
- A serialized `VerifiedBlockRef` is not treated as an unforgeable proof.
  Transaction verification first calls the provider's
  `resolve_finalized_block(hash, number)`. The smoldot provider resolves both
  current and historical finalized blocks by walking exact parent headers from
  one verified finalized anchor. It checks every response hash, SCALE header
  hash, number and parent link; best/recent caches and peer height mappings are
  not proof. Catch-up therefore remains possible without trusting a host
  finality bit or a reorg TOCTOU.
- Raw pre-signed submit remains an advanced no-wallet chain-client path. Once
  any wallet transaction component is composed, that hash must already exist
  in internal pending history or no provider broadcast occurs.
- The provider `watch_extrinsic` contract submits as well as watches. Raw
  submit-and-watch is therefore restricted to a pure-chain composition and is
  rejected before provider access whenever any wallet component is present.
  The high-level wallet path calls this provider entry exactly once and never
  calls `submit_extrinsic` first.
- Provider and store `ContractErrorCode` values are preserved by the Engine
  instead of being flattened into text. The stable C ABI therefore retains
  distinctions such as network, timeout, invalid-state, and integrity errors.
- Runtime-context request identities use a non-wrapping `u64` sequence. Once
  exhausted, the cache fails closed permanently instead of reusing an identity
  that could let an old completion replace a newer best-block context.
- A submitted hash or block inclusion is not execution success. The engine
  hashes the complete signed extrinsic, locates the exact block index, then
  accepts only `System.ExtrinsicSuccess` or `System.ExtrinsicFailed` for that
  same index using metadata fetched directly from the provider at that same
  finalized block. A persistent `RuntimeCacheStore` is a performance cache,
  never transaction-execution evidence.
- Missing, malformed, contradictory, or cross-block evidence returns an
  explicit unverified conclusion; it never guesses success.

CitizenChain accounts and transactions, product-independent sr25519/vault
services, and business-account protocols are separate layers. TUYU or employee
authentication may ask the signing service to sign a defined payload, but their
challenge, authorization, session and audit semantics do not enter this Engine.
`sign_wallet_payload` is an advanced trusted-host facility and returns a general
sr25519 signature; a trusted host can technically reuse that result outside the
high-level transaction path. Pending-before-broadcast is therefore an SDK
wallet-transaction guarantee, not a cryptographic restriction on every host
signature use. The product C ABI exposes it as
`citizensdk_sign_wallet_payload`, and the typed Dart/Android/Darwin bindings preserve
the same trusted-host boundary.

Build and test state must be redirected outside this source tree. For local
CitizenSDK work, only
`/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk` is permitted.
