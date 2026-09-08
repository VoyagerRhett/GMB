# CitizenSDK Linux Host

当前 C++ Config 只有 `modules` 作为模块选择真源，默认 full；薄 Host 通过新增
`citizensdk_host_create_with_modules` 进入同一装配逻辑。既有 C Host ABI v1 的
`enable_wallet` 布局与含义保持，不能把其内存重解释为模块位；显式入口检查它与安全资源选择一致。
Rust 先验证模块，chain/history 才创建 public store，wallet/signing 才创建配套 secure store/Vault；
签名-only 不开放钱包 UI，只使用同宿主既有 SDK 安全账户，首次建立仍须钱包流程。
现有正式包装仍为 full 并含链资产，运行期未选链不加载资产或创建链数据库。
第4步新增独立 qr=32，full=63。Linux 只将亮度帧交给 SDK 内唯一 ZXing-C++ 3.1.1 图像层，
`QR_V1` 协议与扫码签名会话由同一 Rust QR 模块实现，不设兼容或回退识别器。
本次第 2 步仅更新源码、注释、合同和测试，尚未执行新的真实构建、平台测试或硬件验收；下文旧分步运行记录保留为历史证据，不代表本次变更已验证。

This directory is the official Linux projection of the platform-independent
CitizenSDK Core. It adds typed host storage, TPM 2.0 KEK protection, an
SDK-owned GTK wallet flow, and C/C++ packaging. It never implements chain,
runtime, sr25519, wallet-envelope, or transaction logic a second time.

The public product identities are exactly `LinuxARM` and `LinuxAMD`. Machine
triples may appear only in build-tool inputs. The Flutter-required source
directory remains lowercase `linux` and is not a third product identity.

## Runtime boundary

- `libcitizensdk.so` is the single Rust Core and owns the current 88-function
  C ABI, smoldot, wallet envelopes, sr25519 signing, and transactions.
- `libcitizensdk_host.so` owns the Linux host-services vtables, typed stores,
  TPM objects, user authentication, and native wallet flow.
- Native applications include `citizensdk.h` and `citizen_sdk/citizen_sdk.hpp`.
  The C++ API is header-only so the stable binary contract remains C.
- `libcitizen_sdk_plugin.so` is the Step 7.2 Flutter adapter source target. It
  links the exact same-version installed Host/Core pair and maps only the fixed
  36-method tuple protocol; it neither rebuilds Core/Host nor accepts an
  arbitrary RPC method.
- Secrets never cross a Flutter method or event channel. SDK-owned create,
  import and add-account screens remain in the existing native GTK flow; only
  their public wallet profile is returned.

Native owners must stop Core and await its persisted checkpoint before normal
destroy. The C++ RAII wrapper transfers an unexpectedly busy destructor to the
process supervisor, which performs a checkpointed stop and monotonic teardown
with bounded backoff; it never frees Host vtables while Core borrows them. The
destructor performs finite clear/destroy attempts and terminates if even that
ownership transfer cannot be established. A C++ `EventObserver` only borrows
its event/result synchronously and must not retain or release the result; the
wrapper releases it exactly once after normal or exceptional observer return.

Explicit destroy returns `BUSY` when another public call still holds a lease;
it does not wait on a callback thread. Provider service leases protect resource
lifetime without holding the Host call mutex across GTK authentication, and
close returns `BUSY` while a service is active. Abandon transfers the complete
graph to the supervisor, which waits for existing leases outside the caller.
Host and test targets use standard C++17 with GNU C++ extensions disabled so
the compiler's legacy `linux` macro cannot replace an internal namespace.

The source tree must not contain generated libraries, build directories,
CMake caches, downloaded dependencies, or test reports. Every local generated
item belongs under `/Users/rhett/TATA/tataconsole/work/gmb/citizensdk` in a
task-exclusive directory selected by TataConsole or the caller. Linux CTest
configuration requires that existing mode-`0700` directory through
`-DCITIZENSDK_TEST_WORK_DIR=<absolute-path>`; the test helper rejects a missing,
relative, root, symlinked, wrongly owned, or wrongly permissioned directory and
has no `/tmp` fallback.

## Flutter adapter and candidate contract

The Flutter-facing CMake branch is selected only when Flutter's official
`flutter` target exists. It accepts the official machine target value and maps
that value internally to exactly one public platform, `LinuxARM` or
`LinuxAMD`. The Host prefix is fixed to this package's
`linux/` directory and must contain a complete ordinary
same-version installed projection containing `libcitizensdk.so`,
`libcitizensdk_host.so`, and its isolated CMake package. System search paths,
network downloads, another repository and source rebuilds are not fallbacks.

The adapter registers only `citizen/sdk/core/v1` and
`citizen/sdk/events/v1`. Request routes are allocated before native admission,
public result data is synchronously copied while the Host-owned result is
borrowed, and only an owned value tree is queued back to GTK. Event cancellation
changes the sink epoch without closing sessions. Engine detach first revokes
Flutter replies/events, then cancels eligible wallet/transfer work and retires
the complete Host graph through its existing supervisor boundary.

Runtime environment values are native-only: the executable determines the
standard `data/flutter_assets/packages/citizen_sdk/assets/citizenchain` bundle
path, `g_get_user_data_dir()` supplies the XDG data root, the real default
`GApplication` supplies its application ID, and the registrar view supplies a
weak GTK parent. Dart cannot provide a path, identity or window pointer. A
headless view may use chain reads but cannot silently borrow another active
window for wallet UI.

Step 7.2 added this source and its contract tests without registering Linux or
building its runtime. Step 7.4 registers the official `linux` plugin as
`CitizenSdkPlugin`, enables the default `CitizenSdk.open()` path, and includes
both Linux platforms in the same-version candidate contract. Actual Linux
runtime validation belongs to the later unified GitHub CI/Release, not to a
requirement for user-provided local Linux hosts.

第 7.3 步已在唯一构建器中增加安装闭集和真实消费者装配源码。当前开发以本机 macOS 编译通过
为验收标准；2026-09-03 已通过既有 `abi-host` 与 `apple`，不再等待用户提供 Linux/TPM 环境。
跨平台构建与功能验证后续统一进入 GitHub CI/Release：CI 使用增量缓存，Release 使用全量构建，
保持同一 Core commit、SDK 版本、ABI 版本和一个 CitizenSDK Release。
第 7.4 步源码包已使用正式 Linux plugin 注册，由标准 Flutter 工具生成 runner/registrant；
真实消费者直接调用 `CitizenSdk.open()`，不注入内部 platform 或临时改写 pubspec。
plugin 自己固定 `$ORIGIN` 运行库路径，不依赖测试 runner 补配置；同版安装件缺失即失败关闭。

Each application supplies a validated reverse-DNS `application_id`. Host data
is always placed below `<base>/<application_id>/citizensdk/v1/{public,secure}`;
the application cannot point CitizenSDK at another product's final wallet
directory. Both typed roots are mode `0700`; their database, rollback journal,
WAL, and SHM files are mode `0600`, owned by the process effective UID, limited
to one hard link, and opened relative to a no-follow directory descriptor.
CitizenSDK's openat-backed SQLite VFS binds every database and sidecar action
to that descriptor and never routes the validated path back through
`/proc/self/fd` or the default pathname VFS. Existing schema and all required
PRAGMAs are read back exactly; no fallible postcondition may run after a
successful `COMMIT` and turn a durable write into a reported failure.
Fresh v1 tables and `user_version` are created in one explicit transaction;
an unknown version or any partial/extra schema is rejected without repair.

SQLite, OpenSSL crypto, and TPM2-TSS enter the Host link as explicit pinned
static archives supplied from the authorized central build root. CMake rejects
missing, relative, shared, or implicit replacements; there is no dynamic
dependency fallback. `libstdc++` and `libgcc` are selected statically by the
Release-pinned compiler through `-static-libstdc++ -static-libgcc`. CI/Release
must record that toolchain, verify every archive identity, and reject dynamic
C++ runtime dependencies before the two ordinary runtime files are admitted
to the same-version release through that unified platform validation.

## CMake consumer shape

The installed package is designed for the following minimal CMake boundary:

Select exactly one platform package directory, for example
`<prefix>/lib/LinuxARM/cmake/CitizenSDK` or
`<prefix>/lib/LinuxAMD/cmake/CitizenSDK`, as `CitizenSDK_DIR`. The two package
configs and target exports are deliberately isolated and cannot overwrite one
another when both release projections are unpacked under one prefix.

```cmake
find_package(CitizenSDK 1 CONFIG REQUIRED)

add_executable(example main.cc)
target_link_libraries(example PRIVATE CitizenSDK::Host)
target_compile_definitions(example PRIVATE
  CITIZENSDK_ASSET_DIR="${CITIZENSDK_ASSET_DIR}")
```

The package config exposes `CITIZENSDK_ASSET_DIR`; the example forwards that
installed path into its own source and uses it when constructing the Host:

```cpp
#include <citizen_sdk/citizen_sdk.hpp>

citizen_sdk::Config config;
config.storage_root = "/absolute/application/state";
config.asset_root = CITIZENSDK_ASSET_DIR;
config.application_id = "org.example.application";
citizen_sdk::Host host(config);
host.open();
host.close();
```

No `COMPONENTS` are declared. This snippet records the intended source contract
only: the Step 7.3 installed C/C++ consumer fixtures have not yet been compiled
or run on either Linux machine target; local macOS acceptance does not imply
that they have. `CitizenSDK::Host` carries `CitizenSDK::Core` in its
public link interface; consumers do not rediscover SQLite, TPM2-TSS, OpenSSL,
GTK, or a second Core.

安装技术闭集为 19 个普通文件：9 个公开头、同平台 Core/Host 双库、5 个隔离 CMake 包文件和
3 个链资产。构建器逐字节核对公开头、资产、Core 和依赖合同，并检查安装后 Host 的 `$ORIGIN`
RUNPATH、双库 ELF/ABI 和 GLIBC 2.31 基线。私有头、plugin 注册头、测试及源码不进入此安装前缀。
两种平台合并为同一候选 `linux/` 下的 27 项安装投影，10 个公开头与 3 个链资产只留一份且
重叠字节必须一致。Hosted 在这 27 项之外仅保留 `CMakeLists.txt`、`cmake/CitizenSDKFlutter.cmake`、
5 个 plugin `.cc`、4 个对应 `.hpp` 和 Flutter 注册头，精确为 39 项；Host 私有源码不进入
Hosted，也不在 Flutter 应用编译时重建。
这不是已经验收的正式分发包：真实依赖身份、许可证与两种 Linux 平台运行证据由后续统一
GitHub CI/Release 验证，不作为等待用户提供环境的当前开发阻塞。

`test/CitizenSDKConsumer.cmake` 只链接该安装前缀；真实 C/C++ 消费者不回指 Host 私有源码。
后续 Linux 验证须将 12 个 Host 合同目标、6 个 adapter 合同目标和 2 个原生消费者分别精确
枚举再运行，Flutter Release bundle 还必须限时以 0 退出并输出成功标记。源码/Node 合同不能替代 GTK/实体 TPM
和实际消费者验证，macOS 编译也不提供这些证据；当前没有通过任何 Linux 实机验收。

第 3 步安全查看通过无秘密 Host 控制复用原 GTK 流程；私钥仅进入可清零自绘缓冲，
不进入 GtkTextBuffer、剪贴板、Flutter 或通用 result。锁屏监督只使用现有 GLib/GIO 读取
当前进程真实 logind session，要求可确认 Active/LockedHint 及休眠/关机状态；监督不可用
则拒绝显示。私有 40 字节回调表的 `authorizing` 只同步登记本视图真实的 Host 解包操作号；
失焦仅允许同 Host、同操作号的 SDK 认证窗口，该认证窗口再次失焦也会取消。
Linux 不宣称能够阻止系统截屏。完整安全流程与实际 GTK/TPM 验收尚未完成。
`CITIZENSDK_INTERNAL_INCLUDE_DIR` 只给 Host/内部测试 PRIVATE include，不进入安装件。

## Hardware-vault contract

Wallet capability is available only when TPM 2.0 and the SDK-owned strong user
authentication flow are both usable. Missing or inaccessible TPM hardware is
reported truthfully and never falls back to a file KEK, Secret Service, or a
software-only key. Chain read and verification remain usable without a vault.
When executed in that later validation phase, deterministic software-TPM
validation must therefore run inside a controlled Linux guest that exposes
its vTPM as `/dev/tpmrm0` or `/dev/tpm0`; production
code has no socket TCTI injection or public downgrade switch.

The separate device-vault unlock password is used as the TPM object's authValue
and is not the optional BIP-39 derivation password. It is held only in a
zeroizing native buffer. Mnemonics, child mini-secrets, private keys, plaintext
DEKs, and passwords must never be logged or returned by this layer.
