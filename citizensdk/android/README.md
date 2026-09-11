# CitizenSDK Android Flutter host

当前按 wallet、signing、chain、transactions、history、qr 六模块装配同一 Rust Core，
默认 full。先调用统一模块校验，再仅创建所选服务的资源；chain 未选不加载链资产或创建链数据库，
history 未选不初始化历史，wallet/signing 才使用配套 secure store/Vault。SigningService
仅使用同宿主已有 SDK 安全账户归属资料，首次 provision 仍须钱包安全流程，秘密不导出。
纯验签无需实例、钱包、金库或链；Flutter 五端共用 63 方法，open 仅 `[1, modules]`，
`verifySignature` 请求仅 `[1, accountId, signature, payload]`、响应仅 `[1, bool]`，
不建立 session 或事件订阅。运行期模块选择不裁剪现有正式 full 包及链资产。
Android 相机层只向 JNI 交付 8 位亮度帧；识别与生成唯一进入 SDK 内 ZXing-C++ 3.1.1，
协议解析和扫码签名会话唯一进入 Rust QR 模块。QR-only 不初始化钱包、Vault 或轻节点。
本次第 2 步仅更新源码、注释、合同和测试，尚未执行新的真实构建、平台测试或硬件验收；下文旧分步运行记录保留为历史证据，不代表本次变更已验证。

第 1.2 步新增 `getWalletState`、两种冷公钥导入、保持默认项不变的 revision 重排，以及统一
改名/删除。Kotlin/JNI 和 Flutter 只严格投影 Core 的热/冷账户事实；冷账户路径不启动
Activity、认证或 Vault，产品没有无授权 default setter，也没有旧 App 钱包迁移/兼容分支。

第 1.3 步新增通用 opaque 签名、external QR_V1 会话和默认账户签名授权。JNI/Kotlin 不重算
transform、不维护业务 action 表；冷账户不访问 Android Keystore/Vault，热账户仍使用现有
认证路径。默认账户仅在 Core 验原默认账户签名并完成 revision CAS 后改变。

第 1.4 步新增 12 个通用安全链读取方法。Kotlin/JNI/Flutter 只复制准确块、同步状态、
Header/Body/Runtime、opaque storage/System.Events 和显式 smoldot 状态，不自行联网、重算
finality 或解释 App 业务 SCALE。所有 byte array 在跨异步边界前复制，返回模型防御性复制；
输入数量、累计字节、输出类型和 import finalized 回执均失败关闭。

第 1.5/1.6 步把 opaque callData 准备及冷热执行投影为五个固定方法。Kotlin/JNI 不构造
RuntimeCall、payload 或 extrinsic；同步 admission 失败会恢复唯一 prepared token。冷签 response
固定 1..2331 UTF-8 bytes 且只进入 Core 的 `QR_V1` 会话，长观察使用 Core executionId 取消，
平台不保存签名或链上授权字节。

第 3 步补充会话内 `getGenesisHash` 与 `getAccountBalances`，分别投影无需启动的固定链身份
及同一 finalized 块的批量余额；后者保留顺序、重复项与空列表，不在 Android 重写查询逻辑。
`viewAccountPrivateKey` 只传公开 accountId，成功为空；它复用 SDK 原生安全 Activity 与会话取消注册。
私钥不进入 Flutter tuple、普通 JNI result 或 Dart；只有 UI 清除和 Core 请求真实排空后才完成。
真实后台或 Activity 销毁永久撤销，系统认证短暂失焦只隐藏。新的平台运行态验收尚未完成。

`gradle.properties` enables AndroidX for both the standalone native AAR and the
Flutter plugin projection. It is source configuration, not generated Gradle
state; the Kotlin compiler runs in-process so all caches and outputs remain
under TataConsole `target` rather than a user-level compiler-daemon directory.

This directory is the Android side of the `citizen_sdk` Flutter package. The
plugin does not contain a second wallet, vault, JNI adapter, or light client.
Its `main` source set compiles the public Kotlin facade directly from
`android/native/src/main/kotlin`, while the Flutter-specific channel projection
stays under `android/src/main/kotlin/org/citizen/sdk`.

The build consumes one externally staged `arm64-v8a` directory selected by
`CITIZENSDK_ANDROID_CORE_DIR`. That directory must contain exactly
`libcitizensdk.so` and `libcitizensdk_jni.so`. The same staged bytes are used by
the native Android distribution; the Flutter plugin never embeds an AAR and
never packages legacy `libsmoldot.so`.

`CITIZENSDK_ANDROID_BUILD_DIR` selects the shared external build root. Local
flows accept only descendants of `/Users/rhett/TATA/tataconsole/cache/gmb/citizensdk`; GitHub
Actions may use any absolute path outside the SDK source tree. The Flutter and
native modules use separate children below that root.

The native build entry applies the NDK's deterministic `--strip-unneeded` to
the Core staging file before either projection. AGP therefore packages the
same release bytes that are delivered as the standalone Core library instead
of silently creating a second stripped variant inside the AAR.
The same entry fixes the Core ELF SONAME as `libcitizensdk.so`; post-assembly
validation requires both library SONAMEs, exactly one JNI dependency on that
Core name, and rejects every `DT_NEEDED` value containing a build-host path.

Hosted-package assembly may inject the same two files into
`android/src/main/jniLibs/arm64-v8a` in its disposable candidate. Build outputs,
native C++ sources, AARs, and tests remain outside the published runtime package.

The plugin exposes fixed v1 method and event channels. Every request, response,
event, error and nested public value uses a fixed-length positional list;
`Map` payloads are rejected because StandardMessageCodec cannot preserve
duplicate keys for validation. Recovery phrases,
passwords, native handles, prepared-wallet handles, result handles, and signed
extrinsics cannot cross those channels. Wallet creation, import, and account
expansion launch the non-exported SDK-owned secure activity instead.

Detach and explicit close share one supervised lifecycle: all accepted work is
first settled; a `running` provider is checkpointed through `stop` before
destruction; `created`, `stopped`, and `startFailed` instances close directly.
`startFailed` has no persistable stable running snapshot. A still `starting` or
`importingState` instance fails closed, and no stop failure is converted into a
direct destroy. Engine detach transfers the whole session registry into a
process-owned strong orphan supervisor. A failed stop or close is retried with
bounded exponential delay; an operation that has not settled keeps ownership
alive instead of permitting premature native destruction. Supervised close
asks cancellable transfer watches to terminate and waits at most 30 seconds per
attempt; timeout re-enters orphan supervision and never authorizes destruction.
