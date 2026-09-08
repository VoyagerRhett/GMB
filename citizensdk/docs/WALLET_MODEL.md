# CitizenSDK 钱包模型

第 2 步钱包模块只管理热钱包和账户，签名单列 `SigningService`，两者不互相隐式启用。
签名-only 仅使用同一宿主中已由 SDK 安全建立的账户归属资料与设备金库；首次 provision
仍经钱包安全流程，不生成另一套身份或秘密存储，不提供秘密导出。纯验签无需钱包或实例。
模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

Apple 创建、导入及追加账户界面均允许空的可选 BIP-39 password；创建时两次输入必须相同。
非空值继续执行 Core 的既有规范化与长度规则，设备金库认证与派生密码相互独立。

## 固定模型

CitizenSDK 在一台设备上管理一只无根热钱包，wallet index 固定为 `0`，钱包内支持账户
`//0` 至 `//1989`。账户 index `0` 是锚点，其 AccountId 同时是 `masterAccountId`；存在兄弟
账户时不能单独删除账户0。Citizen 地址使用 SS58 prefix `2027`，公开 profile 中的 SS58
必须由 AccountId32 重新计算并核对，不能信任调用方传入的地址文本。
CitizenWallet 冷钱包是独立产品，不属于 SDK。

## Rust Core 模型边界

`native/contracts` 固定了与当前钱包语义一致的公开模型：wallet index 为 `0`，
账户范围仍是 `//0..//1989`，账户0必须等于 `masterAccountId`，profile、provisioning、
cleanup 与 exact secret reference 分离。create/import provisioning 的 previous profile 必须
为空，计划必须精确拥有 target profile 的全部账户 refs，并在回滚时删除本代 wallet key；
append 的 previous profile 必须是 target 账户列表的严格前缀，wallet identity、origin、时间、
active account 与已有账户逐项不变，计划只拥有新增账户 refs 且不得删除 wallet key。
provisioning 与 active cleanup 互斥；cleanup refs 必须非空、唯一且属于同一 generation，active
cleanup 与最多 64 项 queue 的 operation ID 和物理目标不得重叠，也不得命中当前 profile 的
exact secrets 或当前 generation 的 wallet key。`WalletProfileStore` 只保存公开事实，
`EncryptedSecretBlobStore` 只能保存加密信封，`SecretVault` 单独承担设备金库与认证。
`ChainSigner` 是独立的 sr25519 合同，不能与系统金库合并成同一业务接口。

第 4.1 步已经在 Rust Engine 实现钱包派生和完整生命周期：English BIP-39 12／18／24 词、可选
NFKD password、`//0..//1989`，以及 create/import/add/usable/rename/activate/delete/
reconcile；通用签名当前由独立 SigningService 承担。create 不是“先落盘再返回助记词”的单阶段调用，而是
`prepare_wallet_creation`（profile/密文/KEK 零写入）→用户确认备份→
`commit_wallet_creation_after_backup`；准备会话中的助记词和 password 析构清零。
`WalletProfileStore` 以 revision CAS 在秘密写入前持久化 provisioning；
`EncryptedSecretBlobStore` 与 `SecretVault` 使用 generation/owner/operation 的 exact 物理身份；
正常写入和写后抛错都由回读事实收敛。失败方只有先取得自己的 cleanup 所有权才可删除，未完
清理进入最多 64 项的可重放队列，不能命中当前钱包或另一代秘密。

产品 C ABI v1 当前共 89 个函数，既有结构、数值与默认构造保持。新增模块校验、显式模块构造
和无实例纯验签入口，以及四个链查询/结果入口；所有构造都进入同一私有装配。官方绑定按 modules 创建同一 Rust 服务，
chain/history 才需要 public store，wallet/signing 才需要配套 secure store 与 KEK/DEK Vault。
未选 wallet 的调用必须在访问钱包管理服务或展示 UI 前拒绝。
Apple 的分离 typed public/secure SQLite 与五端遵守同一合同；Secure Enclave 仅保护
generation-scoped KEK，不执行 sr25519。

Linux 第 7.1 步 Host 使用同一 `citizensdk_create_with_host` 和同一 Rust 钱包状态机，并以
分离的 public/secure SQLite 与 TPM 2.0 generation-scoped KEK 实现平台合同。它不复制派生、
provisioning、cleanup 或签名逻辑。该步只提交源码与合同测试，没有运行 Linux 编译/测试，
也没有交付 Linux 钱包。

同一 host 构造在 start 前自动恢复公开链数据库，并在 export/graceful stop 时 exact-CAS
checkpoint；这只处理可重建的公开轻节点状态，不把钱包 profile、密文或 Vault 引用混入链库。
checkpoint 失败会阻止后续 stop 副作用，直接 destroy 不替代 graceful stop。host start/stop/import
采用独占 request admission，保证生命周期切换不能与另一项钱包/链异步请求穿插。

## 派生与存储

账户私钥查看属于 wallet，不属于 signing。原生入口仅启动 SDK 自有安全界面；Flutter
`sdk.wallet.viewAccountPrivateKey(accountId)` 只返回完成、取消或错误，不返回秘密。
查看内容保持当前热钱包的 32 字节 child mini-secret 语义，不改为展开私钥或母种子。
用户确认后才访问原设备金库，Core 重新验证账户、公钥与钱包代际。期间相关钱包修改和实例
销毁不得越过活跃查看；关闭必须先清屏、清零原生缓冲，再等待真实认证和 Core 请求排空。
回前台不会自动恢复已取消的秘密展示。平台差异仅在设备保护和原生控件，不另写钱包逻辑。

```text
BIP-39 English mnemonic + optional NFKD password
        │
        ▼ substrate_bip39
master mini-secret（仅在内存短暂存在）
        │
        ▼ schnorrkel hard junction //index
child mini-secret ──设备硬件金库──► 本地 sr25519 签名
        │
        └────────────► public key / AccountId / SS58（公开仓储）
```

助记词和母种子从不进入仓储。创建只经一次性 prepared 备份边界显示助记词；SDK 不提供再次
导出。恢复和追加账户要求用户重新输入原助记词及可选 password。追加还会校验派生账户0等于当前
`masterAccountId`，并在改写公开事实前确认钱包 KEK 和所有既有账户 child 完整存在。该确认
不是只看密文存在：服务会实际解密账户0 child、重新派生公钥/AccountId、与公开锚点逐字节
比对并立即清零明文字节；生物集合变化、失效 KEK 或错配锚点都在提交公开事实前失败。

产品 C ABI 的创建结果不是普通 result 字符串，而是绑定 owner SDK instance 的 prepared-wallet
handle；只有明确备份 UI 能 size-query/copy，commit/release/destroy 后清零，另一实例不能读取、
释放或消费。import/add 的恢复词仅为用户显式输入。Rust 为每个 child 生成随机 32 字节 DEK
和随机 nonce，以完整 `SecretRef` 作为 AAD 执行 AES-256-GCM；宿主只 wrap/unwrap DEK，unwrap
直接写入 Rust-owned 的精确 32 字节缓冲区。

Linux 的 CitizenSDK 设备金库解锁口令仅授权 TPM 对象 unwrap，与上述 BIP-39 可选 password
不同。两者不得互换或自动复用；设备口令不参与账户派生，BIP-39 password 也不能冒充每次
Vault 强认证。无合格 TPM/认证 UI 时保留链读取能力，但钱包创建、导入、追加、签名与钱包
交易构造失败关闭，禁止自动改用文件 KEK、Secret Service 或软件密钥。

## 双存储一致性

公开事实仓储与硬件金库不能共享平台事务。Rust Core 与归档 legacy Dart 差分路径共享以下
行为合同；Rust 使用类型化 store/Vault，legacy Dart 使用
`WalletRepository`/`SecureSeedStore`：

1. 创建、导入或追加先生成 CSPRNG 128 位 `walletGeneration`、每账户 `secretOwner` 和
   `operationId`。它们不使用时钟或 revision 充当唯一身份。
2. 以 expected revision 执行 compare-and-swap，在任何秘密写入前持久化并回读完整 profile、
   revision 和 `WalletProvisioningPlan`。计划包含 previous profile 与本操作全部精确秘密引用。
   仓储若在真实写入后抛错，也必须以回读的精确持久事实判断该次 CAS 是否已经成功，避免
   `addAccounts` 把已经提交的当前账户漏出后续处理。
3. 只有 provisioning 胜者可以写账户 child。KEK 由 `walletGeneration` 独占；child 密文由
   `walletGeneration + secretOwner + AccountId` 精确定位。AAD 还认证秘密类型。
4. 每次写后由安全存储适配回读密文，整批完成后服务再次逐项确认持久计划、账户密文和本代
   钱包 KEK；随后以 CAS 清除 provisioning。完成提交的写后抛错由回读事实收敛为成功。
5. 写入或确认失败时，失败方先以 CAS 把自身 provisioning 转成相同 operation/generation/
   owner 的 cleanup，取得计划后才删除。若越出默认单 isolate 合同的另一执行者先完成
   清理而 secret 后落地，还在运行的失败方会把同一 exact cleanup 加入与当前事实不相交的
   `cleanupQueue`，再只删除自身物理身份。
6. 清理无法确认时保留 cleanup 供重放。追加失败只处理新批 owner，绝不删除原钱包账户0
   child 或钱包 KEK。

创建在上述持久协议之前还有一个硬门：`prepare` 只生成内存会话，用户实际看到并确认备份
恢复词后才允许进入第 1 项。准备期间进程终止只会清零会话，不会留下设备钱包；提交开始后
用户已经持有恢复词，因此即使进程终止也可由 provisioning 重放或由恢复词重新导入。

删除采用持久计划：先提交删除后的公开事实和 `WalletCleanupPlan`，再把计划中的每个
SecretRef 永久推进为 `Tombstone`；整钱包删除还在 `SecretVault` 持久退休 generation，旧
provisioning operation 此后不得重建 KEK。删除接口必须幂等，每项操作后回读；任一失败都
保留计划，下一次钱包写操作或 `reconcileCleanup()` 会重放。active cleanup 与
`cleanupQueue` 中每项都必须结构完整、
操作标识唯一、物理目标不重复，且不得删除当前 profile 的 KEK 或引用其中任何
exact account secret。队列最多 64 项，超限状态失败关闭。

Rust 钱包变更和 `sign` 使用进程内统一操作门；legacy Dart 路径使用同一 isolate 内跨实例的
静态队列。签名解锁 child 后会再次确认 exact generation/owner 与目标账户仍存在，并在签名
成功、公钥不匹配或异常路径中统一清零。进程内门不扩大成跨进程锁；默认合同的进程中断会
保留 secret 写入前已持久化的 provisioning，
新实例据此恢复。真正的跨进程晚写保护来自共享耐久 CAS、永久 SecretRef tombstone 和 Vault
generation retirement；CSPRNG generation/owner 再保证物理清理不越权命中另一代秘密。
标准 Preferences 装配不自动满足这些 Rust provider 合同，legacy Dart 也仍只承诺单 isolate。

`usableProfile` / `isUsable` 也进入同一队列：它们不把公开 profile 存在误当成热钱包可用，
而是验证账户0锚点、钱包 KEK，并逐个解密 profile 的全部 child、重算 sr25519 公钥与
AccountId，最后回读并核对 profile、provisioning 与 active cleanup 的语义事实，防止长认证
窗口返回过期事实。不存在或秘密缺失/错配返回不可用，安全存储和仓储后端异常继续上抛；
所有读取的 child 都在 `finally` 清零。

账户名称是本机公开事实。`renameAccount` 只提交修剪后 1..30 个 Unicode scalar 的名称，使用
相同 revision CAS 与精确回读；未知账户、遗留 cleanup plan 或并发删除均失败关闭，不读取、
改写或恢复任何密文。

## API 与宿主边界

Android 与 Apple 标准装配使用固定 `citizensdk` 硬件金库与产品 typed Vault；根公共 API 不
允许注入 `SecureSeedStore`。该接口只存在于归档差分基线，供受控测试使用；自定义实现
可以观察 child mini-secret，因此使用该内部路径的宿主属于可信计算基。不能把“SDK 默认不
上传”误写为“任意宿主都无法读取”。

SDK 不读取、转换或删除其它产品的密文。普通读取只访问
`citizensdk.wallet.secret.*`；任何其它产品的数据切换都必须单独设计和批准。

Linux Host 同样固定 `citizensdk` 命名空间；TPM public/private object blobs、随机 `auth_salt`
与安全库记录只属于本 SDK。v1 的 PBKDF2-HMAC-SHA256 与 600000 次迭代由 `secure-state-v1`
实现版本固定，不另存为可漂移 KDF 字段。Host 层不能接收 child mini-secret，unwrap 目标仍是 Rust-owned
32-byte buffer。SDK-owned GTK 钱包流程是恢复词/password 唯一展示或输入例外，其终态必须
best-effort 清空控件和原生敏感缓冲区。创建只接受 12／18／24 词，导入/追加的无关 `word_count`
必须为 0，追加 index 只接受唯一 `1..1989`。Core 未打开、wallet 未启用或 Vault 不可用时
必须在展示 GTK 前分别失败关闭；GTK 终态只能在 owner UI thread 清理，有限调度重试仍失败
时 terminate，不能从 worker 析构。parent 销毁必须立即在该 UI 线程清空并退休 dialog、恢复词
和 password 控件、使 parent 引用失效并唤醒等待线程。
prepared handle 的 release 失败不得清空唯一所有权或提前结束 wallet lifecycle；Linux flow
保留 handle 并由专用 supervisor 重试，直到 Core 确认 release 后才移除 flow，使 Host close
在整个清理窗口保持 `BUSY`。

Linux generation 准入与 Vault object 条件写必须在同一 secure-store 事务内成立，确保 retire
墓碑与并发/迟到 provision 线性化；unwrap 在可能持续数分钟的认证提示返回后、明文交付前再次
核验 generation 未退休，失败则清零输出。TPM load/unwrap 还必须验证完整批准 child public
template；availability 必须检查 owner authorization、storage hierarchy 与 DA 状态，并通过
`Esys_TestParms` 探测准确 primary 和 OAEP-SHA256 参数组合。第 7.1 步尚无
实体 TPM 或两种 Linux 机器运行证明。

Rust Core 不提供私钥导出。金库解锁的 child 只进入 `SecretBuffer -> ChainSigner`，不得经过
Dart、Swift、Kotlin 或产品 C ABI；创建结果中的助记词只保留在待受控备份 UI 消费的 Rust
秘密缓冲区。Apple SDK-owned wallet UI 会在流程终态前由文本控件和短期 Swift `String` 持有
恢复词/password；终态 best-effort 清空控件与 Rust 敏感 buffer，但 Swift `String` 不可可靠
擦除。它们不返回 public Swift API、不记录、不持久化且不进入 Flutter。

Rust Engine 的 `sign_wallet_payload` 是受信任宿主的通用账户签名能力，可供 TUYU 等明确协议
签署业务载荷。它返回通用 sr25519 签名，因此宿主技术上能够在 SDK 高层钱包交易路径之外使用
该结果；SDK 的 pending-before-broadcast 保证只覆盖内建 `transfer_with_remark` 路径。产品
C ABI 已以 `citizensdk_sign_wallet_payload` 投影该方法，后续绑定不得把它描述成只能签
challenge 的受限密码学原语。

高层 `citizensdk_transfer_with_remark` 在独立四线程长观察池等待完整 terminal future；取消或
provider 中断不会清除 durable Pending/InBlock single-flight。只有 canonical finalized body、
准确块 metadata 与同 index `System.Events` 核验才能形成成功/失败终态。

归档 legacy Dart `getAccountPrivateKey` 可在其内部测试路径返回所选 child 的
`0x` 小写十六进制 `String`。这是历史兼容行为，不是新 Rust 产品接口；宿主必须继续提供风险
确认、防截屏和即时展示，禁止把结果写入日志、默认剪贴板、磁盘或网络，后续绑定不得移植它。

## 三种账户边界

- 公民链账户由公钥、AccountId、SS58 和链上状态定义。
- TUYU 账户授权可以选择同一公钥并调用独立签名模块，但 challenge、授权记录和服务端会话属于
  TUYU 账户体系。
- TuyuBooking 员工登录属于商家上游员工账户体系，不因设备存在钱包而自动成为链账户或
  管理员。

允许同一用户复用一把 sr25519 密钥，不等于合并三套业务账户、权限和审计记录。
