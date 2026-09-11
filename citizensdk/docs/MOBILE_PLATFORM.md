# CitizenSDK Android 与 Apple 平台实现

当前模块化实现共用同一 Rust 规则：wallet 管理、signing、chain、transactions、history、qr 可组合，
默认 full；模块依赖与编译支持在任何平台业务资源创建前校验。现有正式 full 包仍包含完整链资产，
运行期只在选中 chain 时加载；未选历史不初始化 history，wallet/signing 才创建安全存储与金库。
signing-only 仅访问同一宿主已有的 SDK 安全账户归属资料，首次 provision 仍走 wallet 安全流程。
模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

## 当前支持边界

| 平台 | 当前状态 | 正式候选运行件 |
|---|---|---|
| Android | 产品 ABI；ABI 值 `arm64-v8a` | `citizensdk.aar`、`libcitizensdk.so`、`libcitizensdk_jni.so` |
| iOS | 设备与模拟器变体；模拟器无 Secure Enclave 钱包能力 | `CitizenSDK.xcframework` |
| macOS | 产品 ABI、Swift/Flutter；机器架构值 `arm64` | `CitizenSDK.xcframework` |

LinuxARM、LinuxAMD 已有 Host、Flutter adapter/测试及安装消费者源码；第 7.4 步把两者纳入
同版本候选合同、官方 `linux` plugin 注册及默认 `CitizenSdk.open()`，不增加第二套移动通道。
Linux 尚未经过真实编译、运行和硬件金库验证，不能把源码登记写成已发布的 Release 资产。
Windows 已有 Host 和 Flutter 适配；第 8.4 步同时接入默认注册、同版候选和公开 Flutter
消费者。Windows 实际编译/运行和正式发布仍须统一平台验收，不能用 macOS 结果替代。
legacy `libsmoldot.dylib` 仅为外部 macOS `arm64` 差分测试宿主库，
不进入任何 Release 候选。

## Dart 与 Flutter 公共边界

根 Dart 入口公开 `CitizenSdk` 及独立 chain、wallet、signing、transactions、history 门面。
Android 与 Apple Flutter adapter 均使用固定：

```text
MethodChannel  citizen/sdk/core/v1
EventChannel   citizen/sdk/events/v1
```

Linux adapter 源码也只使用这两个 channel 和相同 62 方法 tuple；无会话验签是五端共享方法，
不增加 Map 旁路或 Linux 专用 Dart API。第 7.4 步公开入口使用同版已安装 Host/Core；跨平台实测仍
由后续统一 GitHub CI 增量缓存、Release 全量构建承担，保持同一产品版本与 ABI。

Windows adapter 源码也复用这两个 channel 和全部 62 方法；五份绑定各自的权威常量/方法表
独立对拍同一金标。Windows 不带入 GLib 实现，也不增加移动端参数或业务功能；其本地身份、
路径和 HWND 只在原生环境层取得。第 8.4 步注册官方 Windows 插件，不增加新的协议或
产品业务；注册源码不代表已在 Hosted 发布。

协议共 62 个方法。第 1.6 步新增准备执行、QR_V1 响应消费和 execution 取消三个方法；第 1.5 步新增
通用交易准备和显式取消两个方法；第 1.4 步新增 12 个通用安全链读取方法；此前新增的 5 个通用签名/默认账户
授权方法、6 个统一钱包方法与既有 10 个 QR
方法在五端名称、字段位置、上限和错误映射完全相同。平台层只投影 Core，不解释 opaque payload/action。
请求、响应、事件、错误和嵌套公开值都是固定长度、固定位置的 `List`
tuple；没有 `Map` 兼容旁路。request sequence 在接纳时严格连续，但并发响应可乱序并精确回显
自己的序号；event sequence 独立递增。cancel/relisten 使用订阅代际和 sink identity，旧队列事件
不能进入新 sink。Android 同笔交易的 bind 前后进度统一进入单派发者 FIFO，较晚事件不能
越过尚在 drain 的早期事件；Apple Flutter 字节参数只接受 `FlutterStandardTypedData.uint8`，
Int32/Int64/浮点 typed data 即使底层长度合适也会失败关闭。

错误固定为 `[1, sessionId?, requestSequence?, errorCode, failureStage, method,
errorMessage?]` 七项 tuple。同步拒绝不伪造 requestSequence；异步完成精确回显原序号。
Android/Apple 只投影 C 真源的八阶段，未知阶段或非 62 项 method 失败关闭。

通用链读取方法为 `getSyncStatus`、`getBestHead`、`getFinalizedBlockAt`、
`resolveFinalizedBlock`、`getBlockHeader`、`getBlockBody`、`getRuntimeContext`、`getStorage`、
`getStorageBatch`、`getSystemEvents`、`exportState`、`importState`。五端只投影 Core 的准确块、
opaque bytes 和不可变模型；不自行联网、不缓存第二份链状态，也不解释任何 App 业务 SCALE。
`getSystemEvents` 只接受 finalized block；`importState` 验证 Core 返回的 finalized 回执与输入锚
完全一致后才向 Flutter 返回空完成 tuple。

统一钱包快照响应固定为
`[revisionDecimal, hotProfileOrNull, accounts]`；每个账户固定为
`[signMode, walletIndex, accountIndexOrNull, accountId, ss58, name, createdAtMillis, isDefault]`。
五端都复核规范 SS58、热/冷 index 形状、账户与冷 wallet index 唯一性、热 profile 闭集以及
`isDefault == (index == 0)`。新增请求分别为 `getWalletState`、`importColdAccountId`、
`importColdAccountSs58`、`reorderWalletAccountsWithoutDefaultChange`、`renameAccount` 和
`deleteAccount`；没有 `setDefaultAccount` 方法。冷账户请求不进入平台钱包 UI 或设备 Vault。

## 统一扫码与签名路径

五端 SDK 相机采集与公开图像输入统一为 8 位亮度帧；扫码识别和二维码生成全部进入同一
ZXing-C++ 3.1.1 窄包装，限定 QR Code Model 2、单码、UTF-8 和固定资源上限。没有 ML Kit、Vision、
Windows 平台识别器或任何回退引擎。解出的文本继续由 Rust 严格解析 `QR_V1`，平台不解释协议。

QR 模块和 signing 模块独立。扫描由 SDK 自有窗口提供：Apple 共用 AVFoundation，Android 使用
CameraX；设备层只采集像素，不使用平台二维码识别。解析、图片解码和扫描返回 Core 的同一公开文档。
链调用的 `signQrRequest` 显式组合 qr、signing、chain，内部完成可信审阅、原生确认和设备授权，
调用方不再取得待签字节或拼装签名响应。QR-only 不访问金库，普通 signing-only 不要求链。
相机权限按调用申请，窗口关闭、设备中断及迟到权限结果必须收口；不得后台继续采集。

Apple 宿主须在自己的 Info.plist 声明 `NSCameraUsageDescription`；macOS 沙盒应用还须开启
camera entitlement。SDK 不能代替宿主声明系统隐私用途，缺少声明时在打开设备之前明确拒绝。
Android 相机权限及非导出扫描 Activity 由 AAR manifest 合并，运行时授权由 SDK 扫描窗口申请。
这些是操作系统集成配置，不是要求产品自行实现相机或二维码识别。

Flutter 插件和原生 Gradle 模块都声明相同 AndroidX 运行依赖。单独通过 `files(...)` 消费
AAR 不会自动解析 Maven 传递依赖，须同时声明其既有 biometric、core-ktx、fragment-ktx 和
CameraX core/camera2/lifecycle；准确坐标见 `android/native/build.gradle`。不把原始 AAR
描述成自带 Maven 依赖元数据，也不为此增加另一套发布流程。

## 无实例验签与会话路由

open 只接受 `[1, modules]`。普通 session 方法仍使用原 session/sequence 外壳。
`CitizenSigning.verify` 是无需 open 的静态入口：`verifySignature` 唯一请求为
`[1, accountId, signature, payload]`，唯一响应为 `[1, bool]`；错误复用原
PlatformException 形态，session/sequence 为 null。拒绝会话形状，不建立会话或事件订阅，
不创建钱包、金库、链数据库或轻节点。

需要 session 的入口中，每个 Flutter engine 只建立一个 EventChannel router，并在 native open 前订阅。早到事件按
session 隔离进入有界缓冲；open 返回该 session 的 event baseline 后才按序交付，不能为每个
session 在 open 后另建订阅，也不能让一个 session 的事件填满或越过另一个 session 的队列。

Dart 永远看不到 C request/result/prepared handle、signed extrinsic、助记词、password、DEK、
mini-secret 或私钥。u64/u128、时间戳和区块高度使用规范十进制字符串；平台 adapter 无损
投影 u32 后再由 Dart 验证范围。
finalized history 的 `accountIds` 必须为 1..1990 个且不得重复；Dart 在 session 请求前、Kotlin
与 Swift 在产品 ABI 前分别失败关闭空列表、超限和重复项。

## Android 单一实现

`android/native` 是原生 Android facade、宿主服务、安全 Activity 与 JNI bridge 的唯一生产
实现。根 Flutter 插件通过 Gradle source set 直接编译其 `src/main/kotlin`，只增加 channel
投影，不复制 facade，也不嵌套 AAR。原生宿主使用同一源码生成 `android/citizensdk.aar`。

外部 staging 的 `arm64-v8a` 目录必须且只能包含：

```text
libcitizensdk.so
libcitizensdk_jni.so
```

两种投影使用逐字节相同的双库；候选拒绝额外 ABI、`libsmoldot.so`、`libc++_shared.so`、嵌套
AAR，以及原生 AAR 中的 Flutter class/reference。AAR 还必须携带与候选逐字节一致的完整
CitizenChain 信任资产和必需 facade/JNI/金库/安全界面 class。
Core 与 JNI 的 `DT_SONAME` 分别固定为 `libcitizensdk.so`、`libcitizensdk_jni.so`；JNI 必须只按
Core SONAME 依赖一次，任何包含 `/` 的 `DT_NEEDED` 都失败关闭，避免构建机路径进入设备。

Android 构建变量固定为：

```text
CITIZENSDK_ANDROID_BUILD_DIR
CITIZENSDK_ANDROID_CORE_DIR
```

本机路径必须位于 `/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk`，GitHub Actions 路径必须位于 checkout
之外。源码树不得产生 Gradle、CMake、SO、AAR 或测试报告。
独立 AAR 的 `settings.gradle` 通过 `CITIZENSDK_WORK_DIR/gradle-project` 显式绑定 `:native`；即使入口脚本
从源码目录 `apply from`，Gradle 也只把当前任务中的 `gradle-project/native` 当作可写项目目录。

## Android 钱包安全界面

创建、导入和追加账户只启动 SDK-owned `CitizenSdkWalletFlowActivity`。Activity
`exported=false`、`FLAG_SECURE`，恢复词和 password 只在该界面与 Rust-owned secret buffer
间流动。Flutter 只传 word count 或公开 derivation indices，并只接收公开 wallet profile。

平台金库使用 Android Keystore/StrongBox 或 TEE 保护 KEK，每次解封要求
`BIOMETRIC_STRONG`。KEK 只 wrap/unwrap 随机 DEK；child mini-secret 的 AES-256-GCM 加解密
和 sr25519 签名在 Rust 受控缓冲区完成，结束后清零。产品与密钥命名空间固定为 `citizensdk`。
恢复词与密码输入在比例分配或 JNI 复制前执行严格 UTF-8 与 1024-byte 上限校验；Kotlin/JNI
临时敏感缓冲区采用单一所有权并在成功、错误和异常路径上清零。

钱包流程先原子登记 owner，再启动 Activity；同步早回调、并发完成、取消先于 coordinator
返回都不能遗留或复活流程。配置变化只替换 UI host，不关闭 Core session。

## Android 生命周期

普通请求可以并发；start/stop 是独占生命周期操作。close 或 Flutter engine detach 会封闭新
接纳、取消 SDK-owned UI 和可取消的 transfer watch，并在每次尝试中最多等待 30 秒：

- `Running` 必须先成功 `stop` 并持久化 checkpoint，之后才允许 close/destroy；
- `Created`、`Stopped`、`StartFailed` 直接 close，`StartFailed` 没有可持久化稳定快照；
- `Starting`、`ImportingState` 若在已接纳工作收口后仍出现，失败关闭；
- stop/close/settlement 失败由进程级强引用 orphan registry 以 250ms 到 30s 的有界退避重试，
  绝不转成直接 destroy。

EventChannel `onCancel` 只解除 Dart sink，不停止 session。只有 engine detach 或显式 close 进入
上述监管流程。

## Apple 单一实现

`darwin/` 是 iOS 与 macOS 唯一共享生产源码。它提供 `CitizenSdk` Swift 公开门面、
`CitizenSDKFlutter` 薄 adapter、typed host services 与平台安全设施，并通过单一
`CitizenSDK.xcframework` 调用同一 Rust 产品 Core。`pubspec.yaml` 对 iOS 和 macOS 均使用
`sharedDarwinSource: true`；iOS 最低版本为 16.0，macOS 最低版本为 13.0。产品名称始终只写
macOS，`arm64` 只作为 Apple 工具链机器架构值。

Apple host 把可重建链数据库、runtime cache 与交易公开事实放入 typed public SQLite，把钱包
profile、加密秘密信封和 Vault 引用放入 typed secure SQLite；两者都使用具名 record contract、
持久 revision CAS 与写后回读，不提供任意键值逃生口。iOS 文件保护等级按数据域区分；macOS
使用相同 schema 与原子语义。

Android 与 Apple 的 `runtime_cache_store` 在原有 SQLite 事务内同时写入并按 rowid FIFO 裁剪，
提交后最多保留最新 64 个准确 block hash；REPLACE 会把该 hash 提升为最新项。完整记录上限仍为
8 MiB，超过其 metadata 容量但符合 64 MiB Core 合同的 runtime context 只留内存，不调用宿主
store。history 使用全新且唯一的 public schema v2：一行通用 meta、按 executionId 分行的 opaque
record，以及 newest/retention/reconcile 三个索引。`THQ1` 查询受 100 条硬上限，`THM1` 在同一
事务内提交删除、upsert 和汇总；不含目的账户、金额、备注、方向或业务 pallet。旧 schema 不迁移、
不兼容。终态删除后的增量回收每次最多 128 页，不建立后台线程，也不运行 full `VACUUM`。

Apple 默认根为 `Application Support/<application_id>/citizensdk/v1/{public,secure}`，
application_id 来自宿主 `Bundle.main.bundleIdentifier`，不是 SDK framework 标识。
缺失或非法身份在创建文件前拒绝；Keychain KEK 标签同时绑定该身份、wallet index 和 generation。
不自动搬动或删除既有数据库与 Keychain。命名空间隔离不等于抵御已控制同一宿主进程的代码。

`CitizenSDKNative` 为 Core 借用的 HostBridge/callback/store/vault 上下文保留一个显式
ABI +1。关闭只能沿 `live -> monitorStopped -> destroyOnly -> closed` 前进；callback clear
在首次 destroy 前已经成为持久阶段，所以之后不再重新安装 callback 或调用其它
lifecycle 操作。destroy 成功时先释放 HostBridge 及 SQLite 连接，再且只释放一次
ABI +1。显式 close、deinit 或 Flutter detach 中断时，进程级 supervisor 持有整个
facade 并按有界退避继续重试，避免孤立 Core 或提前释放借用上下文。

capability/lifecycle C 回调只快速入队，真正的 Core 查询和交付在专用串行队列执行。
Flutter detach 先撤销 method/event handler，再永久废弃当前 event epoch 并清空 sink，
然后对所有 session 先取消未完工作、后逐一等待关闭。iOS 使用 Flutter 对 published
plugin 的正式 detach callback；当前 FlutterMacOS registrar 没有对应 callback，macOS 宿主调用
同一幂等入口，`deinit` 仅作最终 fallback。

Secure Enclave 只保存 generation-scoped EC KEK，用于 wrap/unwrap Rust 随机生成的 DEK，绝不
执行 sr25519。Security framework 解封结果是不可变 `CFData`，只在对应 `autoreleasepool` 内
短暂存活；桥接层避免生成 Swift `Data`/COW 副本，在不能可靠原地清零的边界下立即把精确
32 字节复制到 Rust-owned buffer，并由 pool 排空释放。Apple SDK-owned wallet UI 会在流程终态前由文本
控件和短期 Swift `String` 持有恢复词/password；终态会 best-effort 清空控件与 Rust 敏感
buffer，但 Swift `String` 不可可靠擦除。它们不得返回 public Swift API、记录、持久化或进入
Flutter。child mini-secret 与 sr25519 private key 仍只在 Rust；任何秘密或 native handle 都不跨 Flutter。iOS 模拟器变体没有 Secure Enclave，
必须如实报告硬件金库/钱包能力不可用；其 Apple `arm64` machine slice 用于产品 ABI 与 Flutter/Swift 集成测试，
不能冒充真机硬件钱包。
macOS 也必须在 Secure Enclave 与生物认证实际可用时才开放对应钱包能力；能力缺失不影响公开
链读取，但禁止软件 KEK 降级。

Android 生物识别 Prompt 的创建、启动和取消均在主线程，执行前重查宿主 resumed 状态。
Activity 销毁或 detach 只完成一次操作；终态取得 buffer 所有权后才复制/清零，迟到回调
不能再触及已归还的 Rust buffer。Keystore/Cipher 准备仍在工作线程。
Android close 先标记 closing，再在不持有 facade/native 调用锁的情况下等待 Core 销毁；
已有调用持短 lease，关闭期间新调用立即拒绝。失败保留唯一关闭所有权供重试，不能先释放
HostServices 或重复销毁。公开调用的同步监听器重入不会与关闭屏障互锁。

iOS 没有与 Android `FLAG_SECURE` 完全等价的系统能力：SDK-owned 界面在录屏与进入后台时使用
保护覆盖层；macOS 的 SDK-owned window 禁止系统共享。文档不能把这些 best-available 防护写成
对恶意宿主进程或所有截屏路径的硬隔离。

legacy `libsmoldot.dylib` 只允许构建 macOS `arm64` 外部差分测试宿主库；其 `LC_ID_DYLIB` 是 build-local
路径，不是可分发 install name，不能进入 XCFramework、Hosted 或 GitHub 候选。

## 验证原则

Release 源码门禁反向枚举并固定 Dart、Android 与 Darwin 生产源码、各平台测试、文档、链资产、
AAR 与 XCFramework 投影。本轮本机 Android AAR 构建通过，Apple 单一 XCFramework 的 iOS 设备与
模拟器变体及 macOS 三个 Apple `arm64` machine slice 构建通过，并已编译 iOS 的两组测试 bundle；
由于没有 Simulator runtime，没有把 iOS XCTest 记为已运行。macOS 已运行 Core 50 项与
Flutter adapter 22 项 XCTest，0 失败，1 项真机硬件用例跳过；最终 normal/supervisor
smoke 均通过。本机无真实 Apple 移动设备，不声称 Secure Enclave、生物认证或
device-only Keychain 已完成真机验收。TataConsole Flow 已接入本闭集，但本机记录
不冒充远程 CI、正式 Release、Hosted 上传或 Git 已运行。

iOS 设备与模拟器变体使用浅层 framework 和
`@rpath/CitizenSDK.framework/CitizenSDK` install ID；macOS 使用标准 `Versions/A`
framework 和 `@rpath/CitizenSDK.framework/Versions/A/CitizenSDK` install ID。候选只允许
macOS framework 的精确五个标准内部相对符号链接，其他符号链接全部拒绝。真实 Flutter
consumer 已完成 Android release APK（ABI `arm64-v8a`）、iOS device Release no-codesign、
iOS 模拟器变体（Rust target `aarch64-apple-ios-sim`）编译和 macOS Release 构建，但没有移动真机或 Simulator
runtime 声明。Flutter SPM 与 Android built-in Kotlin 的未来迁移提示延后到第 9 步。
