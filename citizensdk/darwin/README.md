# CitizenSDK Apple projection

当前按 wallet、signing、chain、transactions、history、qr 六模块装配同一 Rust Core，
默认 full。先调用统一模块校验，再仅创建所选服务的资源；chain 未选不加载链资产或创建链数据库，
history 未选不初始化历史，wallet/signing 才使用配套 secure store/Vault。SigningService
仅使用同宿主已有 SDK 安全账户归属资料，首次 provision 仍须钱包安全流程，秘密不导出。
纯验签无需实例、钱包、金库或链；Flutter 五端共用 63 方法，open 仅 `[1, modules]`，
`verifySignature` 请求仅 `[1, accountId, signature, payload]`、响应仅 `[1, bool]`，
不建立 session 或事件订阅。运行期模块选择不裁剪现有正式 full 包及链资产。
iOS/macOS 只将 8 位亮度帧交给同一 framework 中的 ZXing-C++ 3.1.1；不使用 Vision 或其他回退识别器。
QR-only 只构造 Rust 协议/会话状态，不初始化钱包、Keychain/Secure Enclave 金库或轻节点。
本次第 2 步仅更新源码、注释、合同和测试，尚未执行新的真实构建、平台测试或硬件验收；下文旧分步运行记录保留为历史证据，不代表本次变更已验证。

第 1.2 步新增统一 `walletState`、两种冷公钥导入、保持默认项不变的 revision 重排，以及统一
改名/删除。Swift 与 Flutter 只严格投影 Core 的热/冷账户事实；冷账户路径不打开安全界面、
不认证、不访问 Keychain/Secure Enclave Vault，且没有无授权 default setter 或旧 App 兼容分支。

第 1.3 步新增通用 opaque 签名、external QR_V1 会话和默认账户签名授权。Swift 不重算
transform、不维护业务 action 表；冷账户不访问 Keychain/Secure Enclave Vault，热账户沿用
现有认证。默认账户只有 Core 验原默认账户签名并成功 CAS 后才改变。

第 1.4 步新增 12 个通用安全链读取方法。Swift/Flutter 只投影准确块、同步状态、
Header/Body/Runtime、opaque storage/System.Events 和显式 smoldot 状态，不自行联网、缓存
第二份链状态或解释 App 业务 SCALE。Data/数组与 C 两段复制遵守固定上限；import 只有在
Core 返回完全相同的 finalized 锚后才完成。

第 1.5/1.6 步新增 opaque callData 准备与冷热交易执行。Swift 只保管 owner-bound preparation
映射并投影 sealed execution；同步 admission 失败恢复原映射。冷签仍是 Core 的既有 `QR_V1`，
response 固定 1..2331 UTF-8 bytes；平台不构造业务 call、签名、payload 或 extrinsic。

第 3 步补充 `genesisHash()` 与 `accountBalances(accountIDs:)`：前者不要求轻节点启动，
后者保留输入顺序和重复项，复用同一 Rust finalized 批量查询与现有余额结构。
仅选择 chain 即可使用；空列表仍经 Core 状态校验。
`viewAccountPrivateKey(from:accountID:)` 仅属于 wallet，返回 `CitizenSDKOperation<Void>`。
四项私有控制连接 SDK 自有显示缓冲，普通结果没有私钥。确认、认证、后台撤销、清屏和 Core
真实终态共用同一所有权边界；系统认证临时失焦只遮盖，真实后台或窗口销毁不恢复显示。
私有声明仅由构建工作目录导入，不进入交付接口。新的平台运行态及硬件安全验收仍未完成。

This directory is the single Apple source projection for CitizenSDK. The
`CitizenSDK` Swift module is compiled together with the Rust product Core into
one `CitizenSDK.xcframework`; `CitizenSDKFlutter` is only the Flutter adapter
that links that framework. There is no Apple-specific Core, signer, chain
implementation, or asset source of truth here.

The canonical builder exposes the C header and Swift declarations as one mixed
Apple framework module. Stable Swift interfaces are emitted with
`-import-underlying-module` against that same `CitizenSDK` framework module;
the checked-in bridging header remains the traditional/source-build contract
and is deliberately not passed to library-evolution compilation. This avoids
both a second C module/product and Swift's unsupported combination of bridging
headers with `.swiftinterface` generation.

Core copies the Apple host vtables but borrows their contexts through successful
instance destruction. Native therefore holds an explicit ABI +1 retain covering
itself, `CitizenSDKHostBridge`, callback context and every store/vault context.
Close advances monotonically through monitor stop, callback clear and
destroy-only phases; callback clear is persisted before the first destroy call,
so every BUSY or non-BUSY destroy failure retries destroy directly. The +1 is
released exactly once only after destroy succeeds. At that same success point
HostBridge is cleared first, closing its SQLite stores even if the already
closed public facade remains retained; the Native ABI +1 is then released once.
Forgotten Swift close and a failed Flutter detach are transferred to a
supervised, backoff reaper rather than releasing borrowed contexts or leaking
an owner with no recovery path.
Recovery never trusts a possibly delayed Swift lifecycle event: it queries the
authoritative C lifecycle, checkpoints a truly running Core, and then resumes
the monotonic ABI teardown phase.

Supported SDK projection variants are deliberately narrow:

- iOS device variant, Rust target `aarch64-apple-ios`;
- iOS simulator variant, Rust target `aarch64-apple-ios-sim`;
- macOS, Rust target `aarch64-apple-darwin`.

The public platform set is exactly `iOS` and `macOS`; the device and simulator
entries are technical variants of iOS, not separate platform names. Rust target
triples, generated XCFramework identifiers and Swift module identities may
contain architecture or simulator markers, but they are compiler contracts and
never become public product or platform names.

The iOS device and simulator variants use a shallow `CitizenSDK.framework` with
install ID `@rpath/CitizenSDK.framework/CitizenSDK`. The macOS slice uses the
standard `Versions/A` framework layout with install ID
`@rpath/CitizenSDK.framework/Versions/A/CitizenSDK`. Its only permitted
symlinks are `Versions/Current -> A` and the root `CitizenSDK`, `Headers`,
`Modules`, and `Resources` links into `Versions/Current`. All five targets are
relative; every other symlink in the XCFramework or release candidate is
invalid.

The checked-in package manifest and podspec consume the XCFramework injected
into this directory by the canonical candidate builder. Build intermediates,
archives, DerivedData, Pods, SwiftPM state and the XCFramework itself must stay
under TataConsole's central CitizenSDK work directory and never be committed.
本机当前工作根固定为
`/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk`，只使用本任务独占子目录。
成功产物根为 `/Users/rhett/TATA/tataconsole/target/gmb/citizensdk`，已有产物不能被
失败验收覆盖。第 6 步路径仅是任务卡内已结束的历史记录，不是当前生成目录。

The Step 6 Flutter consumer built an Android release APK for ABI `arm64-v8a`, an unsigned iOS
device Release app, a generic iOS simulator variant target using `aarch64-apple-ios-sim`, and a macOS Release
app. These are compile/link results only; no mobile-device or Simulator runtime
success is claimed. Flutter's future Swift Package Manager recognition warning
and Android's built-in Kotlin migration notice are deferred to Step 9.

The hardware vault uses a generation-scoped Secure Enclave EC key only as a
KEK. Rust owns sr25519, secret-envelope encryption and signing. Plaintext DEKs
are borrowed directly from or written directly to Rust-owned 32-byte buffers;
mnemonics and passwords never enter the Flutter adapter.

During create, Apple text controls necessarily retain a Swift recovery-phrase
String inside the non-selectable SDK-owned wallet UI until commit/cancel. Every
terminal path clears the control and zeroes the underlying SDK buffer, although
Swift/platform text storage cannot guarantee in-place String erasure. The
phrase is never returned by public API, logged, persisted, or sent to Flutter.
