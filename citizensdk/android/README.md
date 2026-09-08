# CitizenSDK Android Flutter host

当前按 wallet、signing、chain、transactions、history、qr 六模块装配同一 Rust Core，
默认 full。先调用统一模块校验，再仅创建所选服务的资源；chain 未选不加载链资产或创建链数据库，
history 未选不初始化历史，wallet/signing 才使用配套 secure store/Vault。SigningService
仅使用同宿主已有 SDK 安全账户归属资料，首次 provision 仍须钱包安全流程，秘密不导出。
纯验签无需实例、钱包、金库或链；Flutter 五端共用 36 方法，open 仅 `[1, modules]`，
`verifySignature` 请求仅 `[1, accountId, signature, payload]`、响应仅 `[1, bool]`，
不建立 session 或事件订阅。运行期模块选择不裁剪现有正式 full 包及链资产。
Android 相机层只向 JNI 交付 8 位亮度帧；识别与生成唯一进入 SDK 内 ZXing-C++ 3.1.1，
协议解析和扫码签名会话唯一进入 Rust QR 模块。QR-only 不初始化钱包、Vault 或轻节点。
本次第 2 步仅更新源码、注释、合同和测试，尚未执行新的真实构建、平台测试或硬件验收；下文旧分步运行记录保留为历史证据，不代表本次变更已验证。

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
flows accept only descendants of `/Users/rhett/TATA/tataconsole/work/gmb/citizensdk`; GitHub
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
