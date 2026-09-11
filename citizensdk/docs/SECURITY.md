# CitizenSDK 安全模型

当前安全边界按 wallet、signing、chain、transactions、history、qr 六模块装配，未选功能失败关闭。
钱包管理和签名彼此独立；签名模块仅使用同宿主已由 SDK 安全建立的账户归属资料与设备金库，
首次 provision 仍走钱包安全流程；任何模式都不向宿主公开 API、业务层或 Flutter 返回种子、
私钥或 child secret。SDK 自有原生查看界面的受控显示边界见下文，不等于公开秘密导出。
无实例纯验签只处理公开值，不创建链、数据库或金库。QR-only 也不创建钱包、金库、链数据库或轻节点；
它仅处理公开文档和响应验签，不解锁或导出私钥。ZXing-C++ 层只接受有界的单平面亮度图，拒绝多码、无效 UTF-8、超大图像和过长文本。
链调用审阅复用已验证链 metadata，完整解码 SCALE 参数并核对链身份和 runtime context。
原生确认只消费 Core 持有、绑定实例且不可更改的一次性审阅结果；不能由宿主换入另一组字节。
签名前再次检查期限、账户及当前链上下文，复用现有设备金库授权与 SigningService。
取消、真实后台、锁屏或窗口销毁永久终止此次交互，已进入的设备授权仍须真实排空后释放上下文。
这些界面与句柄边界不构成对恶意同进程宿主的硬隔离，也不改变现有普通签名功能。
模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

## CitizenChain 随包信任资产

`assets/README.md` 规定随包静态资产不得混入设备数据库、缓存或秘密；
`assets/citizenchain` 是 SDK 唯一随包链信任目录。`manifest.json` 使用精确字段闭集固定
`product_id = citizensdk`、`chain_id = citizenchain`、`protocol_id = citizenchain`、
genesis hash 和两个资产 SHA-256。SDK 先验证摘要，再从 `#0` header 重算 genesis hash，
并核对 chainspec state root；失败时不得创建或初始化 smoldot 原生客户端。

远端 `/chain/citizensdk/bootstrap` 只提供经过边界校验的 bootnode 建议，不能下发 RPC、
checkpoint、manifest 或链资产摘要覆盖。本版本没有在线链资产替换通道。

## sr25519 固定口径

- 唯一实现是 `native/signer` 中的 `schnorrkel`，不增加纯 Dart 或自研实现。
- mini-secret 扩展模式固定为 `ExpansionMode::Ed25519`。
- 签名 context 固定为字节串 `substrate`。
- 硬派生 chain code 按 Substrate junction 规则生成。
- mini-secret、展开后的 SecretKey 和签名临时字节在作用域结束时清零。
- signer FFI 用 `catch_unwind` 把 panic 转为错误码；FFI Release profile 不允许破坏该契约。

## 通用签名意图与外部签名会话

`SigningIntent` 只绑定 AccountId、不透明 payload 和显式通用 transform。raw 逐字节签名；
Substrate SigningPayload 只在长度大于 256 字节时取 blake2_256；domain 模式签
`blake2_256(domain || payload)`，domain 必须为 1..32 字节。SDK 不根据 action、App、页面、
CID 或业务实体选择 transform，调用方必须在自己的业务协议中决定编码和域。

热账户必须通过 `LocalSigning + HardwareVault + UserAuthentication`，签名后再以原账户和冻结
transform 自验。冷账户在 WalletState 路由完成后立即转 external transport，不调用 Vault。
`QR_V1` 会话绑定 SDK 实例、随机 session、账户、原 payload、transform、opaque action、transport
和 expiry；任意 `uint16` action 均可传输，Core 不再持有业务 allowlist，也不从 payload 前两字节
猜 action。无效响应保持会话可重试；首个有效响应原子消费；取消、过期或 close 后不能复活。

默认账户授权额外冻结 CitizenChain genesis、wallet revision、原默认账户、变更前完整排列、
目标完整排列、expiry 与 16 字节随机 nonce。签名者固定为原默认账户，验签成功后仍必须在同一
钱包锁内复核 revision、原默认账户和账户闭集再 CAS。action 12 只存在于与独立 CitizenWallet
互操作的默认账户 transport adapter，不是通用签名业务规则。公开层没有绕过授权的 setter。

## Rust Core 的秘密与 provider 合同

`native/contracts` 已经把 `ChainSigner` 与 `SecretVault` 分开：前者负责 sr25519 派生、签名与
验签，后者只负责设备密文、硬件保护、解锁和用户认证。Android Keystore、Apple Secure
Enclave 及 Windows/Linux 金库都是 `SecretVault` provider，不冒充能够原生执行 sr25519 的
硬件 signer。

合同层的 `SecretBuffer` 由 `Zeroizing` 持有字节，不实现 `Clone` 或序列化，`Debug` 始终
脱敏，并只把借用交给同步 Rust 闭包。这个设计缩短 Rust Core 内明文生命周期，但不是同进程
硬隔离：受信任闭包仍可主动复制字节，因此 signer/Vault provider 必须继续审计。五类状态仓储
分别承载轻节点数据库、runtime cache、钱包公开资料、交易历史和加密信封；加密信封仓储的
类型不能接收明文秘密，系统金库仍是独立的第六边界。

`WalletAccount` 会从 `AccountId32` 重算 SS58 prefix `2027` 的规范地址；`WalletProfile` 固定
热 wallet index `0` 和账户0锚。`ColdWalletAccount` 只包含非零本机 index、AccountId、规范
SS58、名称和创建时间，不存在 `SecretRef`、generation 或密钥字段。`WalletState` 原子保存
冷热账户的精确全局排列，第一项为默认账户；热冷 AccountId 重复、顺序缺项/重复/越集和冷
index 回退均失败关闭。`WalletState` 同时携带 provisioning 的 target profile：
create/import 精确拥有全部 target refs 并在回滚时删除本代 wallet key；append 的 previous
profile 是 target 账户列表的严格前缀，既有字段逐项不变，计划只拥有新增 refs。provisioning
与 active cleanup 互斥；cleanup refs 非空、唯一且属于同一 generation，queue 最多 64 项，
各计划的 operation ID 与物理目标不得重叠，也不得命中当前 secrets 或当前 generation KEK。
冷账户操作在任何热 provisioning/cleanup 未完成时拒绝写入，不会以“顺便恢复”为由调用
`SecretVault`。wallet typed payload 直接使用 v2 并拒绝 v1；没有旧钱包解析、迁移或兼容分支。

第 4.1 步的 Rust 钱包服务已经实现 BIP-39 派生、创建/导入/追加、可用性核验、切换、改名、
签名、删除和清理重放。助记词、master 与 child 只以可清零 Rust 缓冲区参与派生或金库调用；
`bip39` 显式启用 `zeroize`，NFKD password 临时值及 Engine 持有的 password 使用
`Zeroizing<String>`。
`native/signer/src/sr25519.rs` 是唯一算法实现，legacy FFI 与类型化 `ChainSigner` 都调用它。
Rust Core 没有公开私钥返回接口；内部原生显示只提供本次查看的同步敏感借用，不形成普通结果。

产品级 `citizensdk_*` C ABI v1 保留既有构造的默认行为，新增显式模块构造
`citizensdk_create_with_modules`，全部进入同一 Rust 私有装配逻辑。
宿主只能补齐所选模块需要的具名 store 与 KEK/DEK 金库，不能注入 signer、任意 RPC 或 nonce。
Rust 在平台资源创建前统一校验 modules；wallet/signing 各有独立门禁，不因共享 secure
store/Vault 而开放钱包 UI。chain 未选择时不构造 provider、读取链资产或创建链数据库；
history 未选择时不初始化历史服务。SDK 执行的 prepared transaction 保持先持久化 pending 再广播。
既有 ABI 结构与数值保持；统一钱包、通用冷热签名、安全链读取、通用交易准备与执行加入后，当前闭集为 117 个。

### 安全链读取边界

公开同步状态的 best、verified finalized、peer count、`isSyncing`、`isUsable` 来自同一个 smoldot
typed snapshot；只有 `isUsable` 是链读取 readiness 事实。调用方不能用节点数、等待时间或高度变化
替代 Core 的能力判定。按高度/哈希解析 finalized 块必须经过 verified ancestry；调用方提供的
`finality` 位、缓存或普通 RPC header 都不能提升为 finalized 证明。

准确块读取先验证 hash/height/canonical 关系。Header 重新构造完整 SCALE Header 并核对
Blake2-256；Body 保留完整 extrinsic 顺序且不业务解码；Runtime、storage 和 batch 都绑定同一个
准确块。batch 保留输入顺序与重复 key，任一项错误时不返回部分结果。`System.Events` 便利入口
固定协议 key 且只接受 finalized 块，但返回值仍为 opaque SCALE bytes；Square、投票、立法、提案、
治理、旅行、订单等解释由接入 App 完成。

公开输入/输出受固定资源上限约束：storage key 1..4 KiB、batch 1..1024 项且 key 总量不超过
1 MiB、Header digest 1 MiB、Body 16384 项/64 MiB、metadata 与 storage batch 响应聚合 64 MiB、
状态 database 256 KiB。跨 ABI 大值使用先询长后完整复制或逐项复制，短缓冲不产生部分输出。
公开层没有任意 RPC method/URL、未验证 JSON、业务 storage schema 或“调用方声明已验证”旁路。

### 通用交易执行边界

prepared 对象只可原子消费一次；执行前重新构造并逐字节核对 chain identity、runtime、nonce、
signed extensions、完整 SigningPayload 和 extrinsic 模板，漂移时要求重新 prepare。热路径只经
现有 SecretVault/强认证/唯一 sr25519 signer；冷路径只经既有 `QR_V1`，错误账户、session、payload、
expiry、重放或签名会销毁该 execution，绝不回退热签或接受裸签名字节。

签名只填充冻结模板的 64 字节槽。完整 generic authorization 必须先由 typed store CAS 持久化并
写后回读，之后才能创建 provider watch。Ready/Broadcast/InBlock/Finalized 通知都不是执行成功；
只有 canonical finalized body 与同 index `System.ExtrinsicSuccess/Failed` 能写终态，Invalid/Usurped
才是 pool rejection。取消会唤醒 provider wait 并排空已进入的 CAS，不删除真实 Pending/InBlock。
重启扫描先查 finalized 证据；仍未终态时只在当前 chain/runtime 与完整签名字节全部一致后，每个
monitor generation 重发一次原 signed extrinsic，不重新解锁、签名、迁移或兼容旧数据。

`exportState`/`importState` 只运输 CitizenSDK 当前 smoldot 数据库与 finalized 锚。导入只允许在
启动前，Core 回执必须与输入锚完全一致；它不是 CitizenApp/CitizenWallet 数据迁移格式，不解析、
转换、回退或兼容旧数据库。

Apple 绑定为 Core 借用的 HostBridge、callback、store 和 vault context 保留显式 ABI +1。
关闭只能沿 `live -> monitorStopped -> destroyOnly -> closed` 单调前进；callback clear
在首次 destroy 前已持久，部分关闭后不得重新开放请求。destroy 成功时先释放
HostBridge/数据库，再且只释放一次 ABI +1。显式 close、deinit 或 Flutter detach 失败
把整个 facade 交给进程级 supervisor 按有界退避继续收口，不提前释放借用上下文。
C capability/lifecycle 回调只入队，Core 查询由专用队列执行；这防止 Core callback
线程与 close/destroy 形成重入死锁。wallet ownership 在 open/owned/closing/closed 状态上原子
线性化，交给 supervisor 后即使重试在 teardown 前失败也继续 fail-closed。

创建备份以及 import/add 的用户恢复词输入是唯一明确允许跨语言绑定的助记词边界：创建只由
SDK-owned prepared handle 为明确备份 UI 临时输出，并同时校验 owner SDK handle；另一实例
不能读取、释放或消费。import/add 只接收用户显式输入。C ABI 只接收或返回临时字节缓冲区；
public binding 不得把它转换成日志、返回值或持久缓存。SDK-owned 原生 UI 是唯一展示/输入例外，
流程终态必须 best-effort 清空平台控件和可清零缓冲区。
已经持久化或解锁的 child mini-secret、展开私钥不进入宿主公开 Swift/Kotlin API 或 Dart；
公开产品 ABI 不提供秘密 getter。账户私钥查看仅允许 Rust 将 32 字节 child mini-secret
同步借用给 SDK 原生显示组件，组件只复制到自身可清零缓冲区；不经过普通 JNI 返回值、
Flutter、事件、业务回调、剪贴板或可选文本控件。关闭清屏与实际设备认证排空必须同时完成，
公开操作才结束。展开私钥不进入该显示路径。Android 恢复词/password 仅进入非导出、`FLAG_SECURE` 的 SDK-owned
Activity。Apple 使用共享 Darwin native 边界；Security framework 解封 DEK 时返回不可变
`CFData`，只在对应 `autoreleasepool` 内短暂存活。桥接层避免生成 Swift `Data`/COW 副本，
在不能可靠原地清零的边界下立即把精确 32 字节复制到 Rust-owned buffer，并由 pool 排空释放；
Rust-owned 输出在使用后清零。
助记词、password、child mini-secret、private key、DEK 及 native/result/prepared handle 都没有
Flutter tuple 位置。旧 Dart 硬件秘密通道与装配已删除，归档差分源码不是正式平台运行路径。

## 设备机密与受信任宿主

账户私钥查看使用钱包模块和原有设备金库，不启动链或公开签名服务。Core 统一校验账户归属、
钱包代际和解锁后公钥；平台只实现设备认证、原生绘制与窗口保护。原生认证窗口必须与本次
查看的真实宿主认证操作精确关联，不能用请求编号、任意认证窗口或短暂时间窗口代替。
真实后台、锁屏、窗口销毁会永久撤销本次查看，晚到认证不得恢复展示。用户关闭后仍有认证
借用时保留上下文至真实回调结束，不以提前取消通知冒充资源排空。
内部链接声明不安装给消费者；隐藏声明和禁止复制不构成对恶意同进程宿主、系统管理员、
外部拍摄或所有截图机制的绝对隔离。

助记词、母种子、child mini-secret 和私钥不得上传到 TuyuServe、TuyuBooking、Cloudflare、
GitHub、TataConsole 或任何远端服务。标准移动装配只在用户设备硬件金库保存 child 密文，并在
本地认证、解密和签名。

CitizenSDK Core 使用 RustCrypto `aes-gcm` 在 Rust 受控缓冲区内以随机 256 位 DEK 和随机
nonce 认证加密 child mini-secret；AAD 精确绑定 `citizensdk`、wallet index、generation、secret owner、
AccountId 和秘密类型。Android Keystore/StrongBox 或 Apple Secure Enclave 只创建、查询、
退休 KEK，并封装或解封 32 字节随机 DEK，绝不接收 child mini-secret 或执行 sr25519。
解封目标必须是 Rust 拥有的固定 32 字节输出缓冲区，签名结束后立即清零。Android 仍要求
逐次 `BIOMETRIC_STRONG`；Apple 要求 `biometryCurrentSet + privateKeyUsage` 与
`WhenUnlockedThisDeviceOnly`。Android 与 Apple 正式投影均使用上述边界；iOS 模拟器变体因无
Secure Enclave 必须如实报告硬件金库和钱包能力不可用，不能用软件降级冒充真机安全能力。
Android 恢复词与密码在比例分配或 JNI 复制之前必须通过严格 UTF-8 校验和 1024-byte 上限；
Kotlin/JNI 临时敏感缓冲区以单一所有权管理，并在全部成功、错误和异常出口清零。
Apple 通过分离的 typed public/secure SQLite 保存公开状态与加密秘密事实。SDK-owned wallet UI
会在流程终态前由文本控件和短期 Swift `String` 持有恢复词/password；终态 best-effort 清空
控件与 Rust 敏感 buffer，但 Swift `String` 不可可靠擦除。实现不得将其返回 public Swift API、
记录、持久化或发送到 Flutter。iOS
没有 `FLAG_SECURE` 等价能力，只能在录屏/后台切换时提供 best-available 覆盖层；macOS 的
SDK-owned window 禁止系统共享。这些界面防护不是对恶意宿主进程或全部截屏路径的硬隔离。

Linux 第 7.1 步以 TPM 2.0 作为唯一合格硬件金库后端。每个 wallet generation 使用独占、
不可导出的 TPM KEK，以 RSA-OAEP-SHA256 wrap/unwrap 随机 32-byte DEK；TPM2-TSS 调用必须
使用 salted HMAC session 与 parameter encryption，不使用 plaintext password session，也不
把对象绑定到 PCR。设备金库解锁口令只在 SDK-owned GTK UI 和可清零原生缓冲区内短暂存在，
不得与 BIP-39 password 混同，也不得进入 Dart、Flutter tuple、环境变量、命令行、日志或
持久化记录。无 TPM、无强认证 UI、TPM 不可访问或 dictionary-attack lockout 时均失败关闭
钱包/签名能力；禁止以 Secret Service、文件 KEK 或软件密钥自动降级。
设备口令派生在 `secure-state-v1` 固定为 PBKDF2-HMAC-SHA256、600000 次迭代；持久化随机
`auth_salt`，不持久化一份可被篡改为另一参数集的 KDF 配置。
Linux public/secure store 目录均强制 `0700`，主 DB、rollback journal、WAL 与 SHM 均强制
`0600`；最终目录和所有实际 sidecar 必须由进程有效 UID 拥有，文件 link count 必须为 1。
CitizenSDK 自有 openat 型 SQLite VFS 只相对已验证目录 fd 创建、打开、访问和删除节点，并以
`O_NOFOLLOW`、类型、owner、link count 与 inode 复核阻止路径替换；符号链接、hardlink、目录
或其它非普通节点直接失败关闭。实现不得把 `/proc/self/fd` 路径交给默认 SQLite VFS。
`sqlite_master` schema/约束闭集与 journal mode、同步、外键、超时、secure-delete PRAGMA 必须
设置后读回；所有可失败后置检查都在 `COMMIT` 前完成，禁止 durable commit 后向 Core 报错。

TPM object name 校验必须与 child public template 全字段白名单共同成立；type、nameAlg、object
attributes、authPolicy、symmetric、scheme、keyBits 或 exponent 任一漂移都视为密钥失效。
availability 还必须确认 owner authorization 兼容、storage hierarchy 已启用、DA 未锁定且参数
有效，并以 `Esys_TestParms` 分别探测 RSA-2048/AES-128-CFB primary 与
RSA-2048/OAEP-SHA256 wrap 的完整参数组合；不能只凭算法列表宣布钱包可用。generation 准入
和 Vault object 写入在同一 secure-store 事务中条件提交；retire
墓碑与 provision 线性化，unwrap 在长认证提示返回后、交付明文前再次核验未退休并在失败时
清零输出。

Linux Host API 先取得统一 closing fence 的 lease；显式 destroy 有其它在途 API lease 时
返回 `BUSY`，不等待回调线程。provider 另持 service lease，认证期间不持 Host 全局锁，
close 对在途 service 返回 `BUSY`。abandon 把完整图移交 supervisor 后，由其等待 lease
退役；不可逆 teardown 开始后不重开 admission。callback、route、Vault 与 UI 均收口后才
销毁 store/Vault，关闭不能持有回调可能重入的 API 锁等待 Core。TPM 返回码只对 TPM/
RESMGR_TPM 层解释 format-1，软件层不可借相同低位伪装为认证或密钥错误。
建立私有 route 期间同步到达的 completion 必须对 65 个以上和
并发突发保持无损。GTK parent 的 `destroy` 在 owner UI 线程立即清空并退休密码/恢复词控件、
使 parent 引用失效并唤醒等待者，不能让后台认证稍后解引用悬空窗口。

宿主进程仍属于信任边界，但公共 host v1 合同没有“任意键值仓储”或 child-secret callback：
五类存储操作各自具名，金库只接触随机 DEK。恶意同进程宿主仍可篡改公开持久状态、拒绝
completion 或观察本来就需要展示的恢复词，因此 SDK 不能宣称对宿主进程提供硬隔离；所有
host callback、存储原子性和平台绑定都必须审计。

没有合格硬件金库或设备能力时必须失败关闭钱包创建、导入、追加账户、签名和签名交易；
公开轻节点查询与公钥验签仍可用。

## 钱包一致性

以下 CAS/provisioning/cleanup 契约由 Rust `WalletService` 实现，并与归档 legacy Dart 差分
基线对齐；其中 `WalletProfileStore`/`EncryptedSecretBlobStore`/`SecretVault` 是 Rust 名称，
`WalletRepository`/`SecureSeedStore` 是 legacy Dart 名称。Android 与 Apple 正式装配均已切换到
Rust typed stores；这些 Dart 类型仅用于受控差分测试，正式绑定不可达。

- `WalletRepository` 只保存热 profile、仅公钥冷账户、全局账户顺序、revision、provisioning
  plan、active cleanup 和不相交的 exact cleanup queue。
- 冷账户只接受 AccountId32 或严格 prefix `2027` SS58 公钥身份；它不进入 `SecureSeedStore`
  或 `SecretVault`。导入、改名、排序、设默认和删除的 Engine 路径均为公开事实 CAS，测试以
  Vault 不可用状态证明零 `open`、零 wallet-key delete、零密文写入。
- `SecureSeedStore` 每个账户只保存 `//index` child mini-secret。
- 创建首先生成只存在于 Rust 内存的一次性会话；准备阶段对 profile、密文和 KEK 零写入，
  用户确认已经备份助记词后才消费会话进入持久提交。由此消除“钱包已提交、唯一助记词尚未
  返回”之间的不可恢复崩溃窗口。导入因用户本来持有助记词，不需要该展示阶段。
- 确认创建、导入、追加账户先预检强生物识别，再为钱包、账户秘密和操作生成 CSPRNG 128 位身份；
  在任何秘密写入前用 revision CAS 提交并回读目标 profile 与完整 provisioning plan。
- 仓储正常返回或“写入后抛错”都必须由回读的 revision/profile/provisioning/cleanup/
  cleanup queue 决定真实提交结果。
- 追加前必须确认钱包 KEK 与当前 profile 的每个既有账户 child 都存在，避免在不可恢复的
  缺失秘密上继续扩大钱包；还必须实际解密并核对账户0锚点，确保生物集合变化没有使先前
  KEK 失效，随后立即清零锚点明文。
- 每个 child 由 `walletGeneration + secretOwner + AccountId` 精确定位；写后逐项确认账户密文
  与本代钱包 KEK。
- 失败方必须先以 CAS 把自己持有的 provisioning 转成 exact cleanup，取得计划后才可删除。
  若越出默认单 isolate 合同的另一执行者先清除计划而 secret 随后落地，还在运行的失败方
  会把同一 exact cleanup 加入与当前事实不相交的 queue；只能删除自身 generation/
  owner。清理失败时计划保持可重放。
- 删除先持久化 cleanup plan，再把每个 `SecretRef` 从 `Vacant/Sealed` 单向推进到永久
  `Tombstone`；整钱包删除还要求 `SecretVault` 持久退休 generation，之后任何旧 operation 的
  `seal` 都必须失败。墓碑和退休记录先于清理成功返回落盘，未完成计划保留并可重放。
- Rust 钱包变更与 `sign` 由进程内统一操作门串行；legacy Dart 对应路径在同一 isolate 内跨
  `WalletService` 实例串行。签名前再次确认 exact generation/owner 与账户仍存在，成功或失败
  均由秘密缓冲区完成清零。
- `usableProfile` / `isUsable` 不只读取公开 profile，而是验证账户0、KEK 及全部 child 的
  sr25519 公钥；后端异常上抛，不能把认证、金库或仓储故障伪装成“无钱包”。
- 热 `renameAccount` 与冷账户改名都只经 revision CAS 修改公开名称；cleanup 未完成或并发
  删除时失败关闭，绝不代为创建、恢复或删除秘密。
- `getAccountPrivateKey` 只属于归档 legacy Dart API：它返回不可擦除的 Dart `String`，
  宿主必须负责风险确认、防截屏、禁日志/持久化/上传和尽快丢弃引用。Rust Core 与新的产品
  C ABI 明确不提供对应私钥导出路径。
- 进程内操作门只减少同进程竞争，不是安全真源。Rust `EncryptedSecretBlobStore` 必须跨进程
  提供共享、耐久、强原子 CAS 和永久墓碑，`SecretVault` 必须提供 generation retirement；
  两道 fence 共同阻止 cleanup 后的迟到密文/KEK 复活。SharedPreferences 仍不自动满足这些
  Rust 合同，legacy Dart 路径也仍只承诺同 isolate 串行，不能借 Rust 合同夸大现有装配。

## 轻节点与交易

公民链状态由设备内 smoldot P2P 轻节点验证。Bootstrap 只能提供固定 schema 下的链身份与
bootnode 建议；根对象及 `chain/light_client/p2p/security` 都必须精确匹配字段闭集，不能夹带
聊天、广场、TUYU、宿主业务、远程 RPC 或链状态真源。Bootstrap 地址只允许 HTTPS，本机
回环地址也不允许使用明文 HTTP；SDK 不实现服务器签名或通用 RPC 代理。

`author_submitExtrinsic` 返回 txHash、peer 广播、`inBlock` 和 `finalized` 都不能单独证明
runtime 执行成功。SDK 必须按 txHash 定位同一 extrinsic index，并读取该 index 的
`System.ExtrinsicSuccess/Failed`；未找到明确结果时报告未核实。收到 finalized 后由执行核对
独占后台终态，订阅流的迟到数据和错误不能形成与执行结果冲突的第二终态。

runtime version 与 metadata 必须在同一 finalized/目标块上读取并按 `specVersion` 绑定缓存；
前一代 in-flight 请求迟到不能覆盖新缓存。余额批量读取只走轻节点 finalized batch storage，
手续费只信任同一 metadata 的链上常量。状态观察回调和订阅取消 Future 的异常均为
best-effort 隔离，不能泄漏未处理错误或改变交易终态。持久 `RuntimeCacheStore` 是可替换的
性能层，不是交易执行证据；安全关键终态核验必须直接从 provider 取得准确 finalized 块的
runtime context，不能信任宿主可写缓存中的 metadata。

Rust 交易构造只接受准确 CitizenChain 身份、同一 best 块的 runtime context 和同次
`AccountNonceApi_account_nonce` typed snapshot。该 Runtime 值不包含交易池；同账户一旦有
Pending/InBlock，持久历史 single-flight 会禁止构造另一笔交易，防止本地复用 nonce。

通用准备入口只接收 source AccountId 和有界 opaque RuntimeCall。Engine 必须用准确 best block 的
outer-call metadata 类型完整消费到 EOF 并 canonical 回编码；未知 call、截断、trailing、超限或
不支持的 signed extension 全部失败关闭。当前策略固定为 SDK 自动 nonce、immortal era、tip=0，
调用方没有 nonce/era/tip/选项或版本入口。准备对象按实例 generation 和 source single-flight 隔离，
不持久化且只能取消或由后续交易闭环原子消费一次；stop/close 清除注册表和可清零内部 signer
message/extrinsic 模板。公开摘要不包含这些敏感交易材料或原生 handle。

通用准备入口只接收调用方生成的 opaque RuntimeCall，并用准确 metadata 完整消费到 EOF 后
canonical 回编码；SDK 不解释目的账户、金额、备注或 pallet 业务含义。签名前复核 source AccountId
与金库秘密公钥，签后立即验签。执行入口把 source、callData hash、nonce、完整 signed extrinsic、
构造块、RuntimeVersion 和 genesis_hash 原子持久化为 pending，确认 CAS 成功后才广播。恢复先
核验 finalized 证据；仍未决才从当前已验证 best 读取同版本 Runtime，核对账户、nonce、call、
完整编码与 sr25519 签名，再决定是否重发相同字节。
immortal 的额外签名域绑定 genesis 而非原 best 哈希，因此原构造块不可读不阻断同版本恢复。
当前 Runtime 版本已变且尚无执行证据时安全报错，保留原授权，不擅自重签或清除记录。写后异常、
取消或进程退出不丢失这份授权；缺少授权的状态失败关闭，不自动清库或重签。
纯链客户端的 raw pre-signed submit 只用于
无钱包组合；一旦注入任一钱包交易组件，它也必须命中内部 pending，否则失败关闭。底层
`watch_extrinsic` 合同实际会 submit-and-watch，而不是被动观察既有哈希；因此只要组合任一
钱包交易组件，Engine 也会在触达 provider 前禁止 raw submit-and-watch。

通用 `citizensdk_execute_prepared_transaction` 的完整 terminal future 在独立四线程长观察池运行，
不会占用 lifecycle/read/state 所用的短操作池。宿主取消会得到 `CANCELLED`；provider 断线、
dropped、retracted、timeout 或取消只结束本次观察，不删除 durable Pending/InBlock 门。
finalized 返回仍必须经过 canonical body、准确块 metadata 与同 index `System.Events` 核验。

Rust Engine 现在把上述规则固化为准确 `VerifiedBlockRef` 的 runtime context 和交易证据核验：
它对完整 signed extrinsic 计算哈希、在准确块体定位 index，再只接受同块 metadata 解出的
同 index System 终态。宿主传入的 finality 位不是证明；Engine 先调用 provider
`resolve_finalized_block(hash, height)`，smoldot 从准确 verified finalized 锚沿 exact parent
hash 验证到目标高度；best/recent cache 或 peer 高度映射都不能替代这条证明。每批最多 120 块，
独立有界 proof-derived cache 只用于减少重复回溯。这样安全支持重启补扫并关闭重组 TOCTOU。
历史终态只接收核验器产生的私有令牌，令牌不可分离地绑定 txHash 与 Success/Failed，且必须
精确匹配唯一 pending，不能把 A 交易结论写给 B。SDK 历史不扫描 transfer、投票或治理事件，
不推断方向，也不保存目的账户、金额、备注或业务 pallet。导入的轻节点状态执行启动前、
链/协议/genesis/格式/finality、最大 256 KiB 和不倒退门禁。System 执行结果必须属于
`ApplyExtrinsic`，不能用 hook 流水证明某笔 extrinsic 执行成功。
engine 使用官方 `subxt-core = 0.43.0` 做 metadata/events 解码，
不增加第二轻节点。真实 `smoldot/provider` 已实现 `VerifiedChainClient`；它内部仅允许源码
固定的准确块读取、runtime、提交/观察和状态方法，产品 ABI 不接受任意 RPC 方法名。Provider
提交后立即独立核对完整 extrinsic Blake2-256；节点哈希不一致直接失败关闭。

`citizensdk_sign_wallet_payload` 是提供给受信任宿主的产品无关本地账户签名能力，可用于 TUYU
等明确业务协议；它返回签名，因此同进程宿主技术上也能把签名用于 SDK 交易闭环之外。
pending-before-broadcast 保证只覆盖 SDK 自己执行的 prepared transaction，不能被描述为对所有宿主签名
用途的强制约束。语言绑定必须明确这条信任边界，不能把通用载荷签名伪装成只能签业务
challenge 的受限密码学原语。

导入还会合并本 Engine provisional anchor 与 revisioned `ChainDatabaseStore` 的持久化 finalized
锚，拒绝高度回退及同高度异哈希，并以 CAS 保存 exact 导入状态；写后抛错只在回读事实完全
相同时收敛为成功。跨 Engine 或进程防回退仅在 store adapter 提供共享、耐久、强原子 CAS
时成立；旧 `citizensdk_create` 的进程内 chain session store 和 legacy Dart Preferences store
都不因此获得跨进程保证。当前官方绑定的模块化持久 store adapter 负责
满足这些合同；Apple 以分离的 typed public/secure SQLite 落实相同 store 语义。导入数据库导致
启动失败时当前
Provider/Engine 组合进入
不可复用 `StartFailed`；只有销毁该 handle 并创建未导入的新实例才能从随包 #0 回退，禁止在
已经发生副作用的实例上重试或伪报恢复成功。

host 构造的 start 会在 provider start 前自动恢复上述状态；export 与 graceful stop 只在完整
`revision + state` 与预期候选一致时提交，不能把“同 state、不同 revision”的竞争写误判为本次
成功。stop 的 checkpoint 失败必须发生在退订和 provider 停止之前。destroy 为避免主线程等待
任意异步平台回调而不做 checkpoint，宿主必须显式成功 stop；最坏只丢失可重新同步的近期公开
轻节点缓存，不影响钱包秘密或链上事实。host start/stop/import 的独占 admission 还保证从
checkpoint 到 provider/Engine 生命周期提交之间没有另一项链、钱包或控制请求穿插；旧 session
构造继续使用既有共享 admission。

产品 ABI 使用单调非零实例/result handle、Rust-owned 结果和显式一次释放，销毁在请求或结果
未收口时返回 `BUSY`。回调只在每实例独立线程执行；从自身回调销毁或同步退订 capability 会在
任何生命周期/monitor 变更前返回 `BUSY`。事件与请求队列均有界，watch 背压使用稳定
`QUEUE_FULL`，不能无界占用内存。每个已接受请求在 admission 前预留 64 槽队列中的一个
真实完成槽位和一个结果 handle；普通事件不得占用预留容量。序号分配与即时入队共用短锁，
不在锁内等待队列空间，宿主回调始终锁外调用。容量耗尽在接收请求前拒绝。
host completion 被 claim 后仍计为 outstanding，直到 SDK
校验、复制与投递结束；其后的无状态 callback 尾部不访问实例，避免 destroy 在敏感窗口释放
实例状态。所有输出先支持 `NULL + 0` 长度查询，再复制到宿主缓冲区。
每个非空 completion 必须在读取或 claim pending registry 前先核对 callback token 与
`result.host_operation_id` 完全相等。交叉 identity pair 被忽略，不能取消、完成、消费或观察任一
真实 operation；空 result 没有第二身份，仍以 integrity 失败终止 token 所属 operation。只有身份
匹配的非空 completion 才能进入 Pending→Completing。

公民链账户签名、TUYU challenge 签名和 TuyuBooking 员工登录是不同业务权限。它们可以在
明确设计下使用同一用户 sr25519 公钥，但不得合并账户、授权或审计记录。

## 原生产品边界

全节点 `author` 出块代码、identity keystore 和 seed phrase 私钥入口不进入 CitizenSDK。
保留的 `identity::ss58` 只做公开地址编解码。libp2p Noise 密钥按连接随机生成、只用于传输
握手并在内存清理，不是钱包或管理员密钥。

根产品 C ABI/头文件不导出低层 signer、private-key 或 child-secret 原语；高层
`citizensdk_sign_wallet_payload` 只返回签名结果。Android AAR/Flutter 双投影禁止
`libsmoldot`，只带产品 Core 与薄 JNI bridge；Apple XCFramework 只导出根产品头的 97 个
`citizensdk_*` 符号，并拒绝 `smoldot_*`、`citizen_sr25519_*` 与 `account_crypto_*`。legacy
smoldot/signer 符号只允许存在于源码树外的 macOS `arm64` 差分测试宿主库，绝不进入候选。

Linux C/C++ Host 同样只能加载唯一 `libcitizensdk.so`。`libcitizensdk_host.so` 不得
重复导出 Core、内嵌第二份 smoldot/signer/Engine，或让恢复词、设备金库口令、DEK、child
mini-secret 和 private key 穿过公共 C++/Flutter 边界。第 7.1 步只提交这套源码与测试合同，
没有构建 `.so`，也没有取得 LinuxARM/LinuxAMD 或实体 TPM 的运行证据。
第 7.4 步把双平台安装投影、默认公开入口和 Hosted 过滤纳入同版本候选合同，不改变上述秘密
边界。Hosted 只保留 39 项 Linux 运行输入，不携带 Host 私有源码或从系统位置替换 Core/Host；
plugin 固定 `$ORIGIN`，不借助测试 runner 修补路径。同版产物缺失或重叠文件漂移时拒绝
候选。CMake 全部指令采用闭集校验，阻断追加命令覆盖导入路径。当前 ELF 结构/禁止依赖
检查不能证明实际构建提交或静态依赖来源；真实依赖、许可证和运行证据不齐不得正式分发，
这些证据由后续统一 CI/Release 验收，不在本步以伪造元数据填补。

聊天、广场、OpenMLS、TUYU 消息协议与产品数据库均被排除。测试夹具只能使用公开向量和
非生产数据，不得加入真实助记词、设备密钥或用户数据。

## 构建与分发

- SDK 源码树不得接收构建缓存、原生库或 Release 产物。
- 本机 Linux 合同测试必须由 CMake/CTest 以 `CITIZENSDK_TEST_WORK_DIR` 注入
  `/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk` 下有效 UID 所有、`0700`、任务独占的现有
  绝对目录。测试 helper 逐级 no-follow 验证后，以 CSPRNG 随机名称和 `mkdirat` 只在已验证
  目录 fd 下创建子目录，不回退 `/tmp`、当前目录或用户目录，也不递归删除未经 fd 与 inode
  复核的路径。
- 原生构建和 Release 在首次建目录前校验绝对规范路径及每一级既存祖先，拒绝路径穿越、
  符号链接祖先和非目录祖先；工作目录与产物目录必须成对通过预检，任一无效时保持零写入。
- 本机发布器只接受 `/Users/rhett/TATA/tataconsole/target/gmb/citizensdk` 和
  `/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk` 的严格后代；永久根本身、
  旧根、邻产品/仓库/平台、伪前缀和最终链接均拒绝。只核验匹配根存在且为普通目录，
  未使用根缺失不影响本次请求。GitHub 隔离分支不变。该门禁不替代执行方对 UID、权限、
  任务归属和清理范围的检查；永久容器不得删除，不能清理别的任务内容。
- CI/Release 使用锁文件与准确提交；Release 必须绑定同产品、同目标的成功 CI。
- Android 与 Apple 的 generation 准入/退休数据库事实和物理 Keystore/Keychain KEK
  副作用处于同一个进程内锁与 OS 文件锁临界区。退休 tombstone 先提交，迟到 ensure 不能
  在另一进程删除后复活同 generation 的物理 KEK；锁文件只含协调状态，不含密钥。
- Apple SQLite revision 只接受 SQLite INTEGER 且范围为 `1...Int64.max`；负数、零、REAL、
  TEXT 或其他畸形持久值作为存储错误失败关闭，不触发 Swift 数值转换 trap。
- 候选只允许标准 macOS framework 内精确五个相对符号链接：`Versions/Current -> A`，以及
  根 `CitizenSDK`、`Headers`、`Modules`、`Resources` 指向 `Versions/Current/...`；其他任何
  符号链接、路径穿越、未登记文件、常见密钥文件及 PEM 私钥材料均拒绝。
- `SHA256SUMS` 是 tgz 外部资产，精确覆盖 manifest 与 tgz；校验器重建规范归档字节。
- Release 候选合同包含 Android、iOS、macOS、LinuxARM、LinuxAMD 与 Windows；iOS 设备和模拟器只是同一平台的技术变体，
  全部平台使用同一产品 ABI、Core commit 和 SDK version。当前 Android ABI 为 `arm64-v8a`，
  Apple machine slice 架构元数据为 `arm64`。
- GitHub Release 是正式分发终态，但不等于真机硬件金库安全验收；对应结果必须单独留档。
- LinuxARM、LinuxAMD 已在第 7.4 步纳入 manifest 候选合同与公开入口，但尚未真实编译或运行；
  正式分发前必须由后续统一 GitHub CI/Release 分别验证 ELF/GLIBC、公共符号、依赖闭集、
  软件 TPM 与实体 TPM，不能把源码注册或软件 TPM 结果代替硬件证明。

本轮 Apple 本机已编译 iOS 设备与模拟器变体两组测试 bundle，但因无 Simulator
runtime 没有声称 iOS XCTest 已运行。macOS Core 58 项与 Flutter adapter 23 项 XCTest
0 失败，1 项需要真机硬件的用例跳过；normal/supervisor smoke 通过。本机无真实
Apple 移动设备，所以 Secure Enclave、生物认证和 device-only Keychain 仍需真机验收。
TataConsole Flow 已接入 Apple/Hosted 与五平台 Release 闭集；本轮仅执行本机闭集，
没有运行远程 CI、正式 Release、Hosted 上传或 Git。

同轮 Android ARM64 Core/JNI/AAR 构建、原生 Kotlin 单元测试及最新本机 Flutter/AGP
宿主的插件单元测试通过；Rust 根 workspace 295 项和 TataConsole CitizenSDK 合同
61 项通过。Android 硬件金库跨进程用例保留在 androidTest，仍须真机执行；这些本机
结果不替代 GitHub 五宿主 Release 或实体硬件验收。

第 7.1 步没有运行 Linux 编译与 CTest、Dart/Flutter/Cargo 测试、Git、远程 CI、Release 或
Hosted 上传；仅执行获准的 Node Release 来源合同测试与脚本语法检查，不代表 Linux 安全
运行验收通过。完整平台安全合同见 `LINUX_PLATFORM.md`。

第 7.2 步 Linux Flutter adapter 也不承载秘密：助记词和 password 只出现在 SDK-owned GTK
控件，DEK/child secret/sr25519 仍只在 Host/Core 受控路径；tuple 没有对应位置。Core callback
内只同步复制公开结果到拥有值，借用 result、Host/Core/request/flow handle 和 `FlValue` 不跨
线程。请求 route 先于原生接受，终态复制结束才允许退役；钱包变更门禁覆盖不同 session/引擎，
删除类方法的 EMPTY→profile 回读也在同一门禁内。Event sink 用 epoch 阻止迟到队列进入新订阅，
detach 不在 handler 销毁栈内回复；待回复句柄保留到 UI 队列再结束，防止活 engine 通道替换
造成悬空请求。它也不提前释放在途变更门禁，真实完成后才交既有 Host 关闭机制。
长度保持 codec 只修复 GLib 内部 NUL 表示，wire 仍为 Flutter
标准字符串类型，拒绝其它自定义值和超深/超大输入。

iOS 设备与模拟器变体的浅层 framework install ID 为
`@rpath/CitizenSDK.framework/CitizenSDK`；macOS 标准 `Versions/A` framework install ID 为
`@rpath/CitizenSDK.framework/Versions/A/CitizenSDK`。真实 Flutter consumer 已完成 Android
release APK（ABI `arm64-v8a`）、iOS device Release no-codesign、iOS 模拟器变体（Rust target
`aarch64-apple-ios-sim`）编译和 macOS Release 构建，但没有移动真机或 Simulator runtime
声明。Flutter SPM 识别警告与
Android built-in Kotlin 迁移提示延后到第 9 步处理。

同一本机闭集已验证 Android AAR、Hosted 17 文件分析 0 问题、完整 Dart 316/316
（`--timeout=2m`）、根 Rust 285/285 与 compile-fail 文档测试 1/1、Clippy/格式，以及
Android 原生 Kotlin/Java 单元测试 Gradle 17 个 task；这些结果不扩大上述真机安全验收边界。

## Windows 系统金库边界（第 8.1 步）

只使用 PCP + TPM 2.0、当前用户不可导出的 RSA KEK。SDK 设备口令在有界可清零缓冲区
进入官方 PIN 授权，不是业务登录或链口令；DEK 直接解封到 Rust 的 32 字节输出，失败清零。
PCP 冷/暖进程、重开 key、错误/缺失口令和静默解密仍需隔离硬件验收，关闭 handle
不等于清除 OS 缓存。生产代码不试错口令、不清 TPM，不使用软件降级。
持久 KEK 按 generation 定址；跨 Host 创建/提交与退休串行，CAS 失败不能删除胜者 key。
物理删除失败保留重试身份。文件操作绑定已验证父 HANDLE、SID/DACL、文件身份、单链接
和无 reparse。自有输入不经 EDIT/业务通道；缓冲区清零不代表系统渲染副本或截图可控。

第 8.2 步的 Flutter adapter 只传递公开拥有值，不把助记词、设备口令、私钥、DEK 或原生
handle 放进 tuple、错误或事件。钱包入口只调用现有 Windows 原生流程，未引入新秘密存储。
`CITIZENSDK_APPLICATION_ID` 是稳定数据命名空间而非 Windows 身份认证；它不能替代 SID、
DACL、TPM 或路径检查。插件不修改 Shell 身份，不从显示名、可执行文件名或目录推导身份。
事件订阅按 epoch 隔离，工作线程不接触 Flutter 消息对象；原生结果在回调期间完成拥有值
复制，再调度 UI 回复。已接纳请求与钱包变更门必须存活到真实终态，不能以 handler 销毁
或 detach 代替完成。Windows Host 关闭可能先释放 Core、再等待 UI 退休；只有已经进入
合法关闭流程的会话可以内部重试，无 Core 不能被普遍解释成关闭成功。Host 生产实现和
Core 均未在本步修改。Windows/MSVC、真实消息泵与 TPM 验收仍待统一平台检查。

两条 Windows channel 在官方解码前先执行无分配的标准 wire 预检，限制字节数、节点数和
深度，拒绝截断、尾随数据、不支持的类型和畸形 UTF-8。不能只在官方 decoder 已分配后
检查 Value 大小，也不能让截断载荷被零填充后进入签名或交易。预检不替代官方 codec，
合法消息仍由 StandardMethodCodec 解码；保留合法整数宽度、长度表示及内嵌 NUL。

第 8.4 步的公开入口和安装投影不改变上述安全实现。当前候选与 Hosted 仅接受同版 22 项
安装件和 12 项插件输入，额外 DLL、路径、修改过的公开头或链资产均失败关闭。正式消费者
必须经原始包声明与自动注册，不允许内部平台注入或通过临时修改 SDK 副本规避来源检查。

Windows Flutter 生产数据根由 SHGetKnownFolderPath(FOLDERID_LocalAppData) 返回，不能
通过 HOME、LOCALAPPDATA 或 XDG 环境变量替换。真实消费者只在一次性 GitHub 隔离用户
环境中运行，使用运行前不存在的 org.citizensdk.flutterconsumer 命名空间；只允许清理
核实归属后的自身状态，不能删除整个 LocalAppData。Flutter/Pub 工具副本与缓存放本轮
工作目录；官方工具自身用户状态由一次性 runner 隔离，不在本机 Windows 用户中执行。
消费者不创建钱包、显示秘密或发交易，能力不可用必须如实呈现，不能证明实体 TPM 授权。
