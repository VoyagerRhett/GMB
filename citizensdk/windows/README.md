# CitizenSDK Windows 原生 Host

当前 C++ Config 只有 `modules` 作为模块选择真源，默认 full；薄 Host 通过新增
`citizensdk_host_create_with_modules` 进入同一装配逻辑。既有 C Host ABI v1 的
`enable_wallet` 布局与含义保持，不能把其内存重解释为模块位；显式入口检查它与安全资源选择一致。
Rust 先验证模块，chain/history 才创建 public store，wallet/signing 才创建配套 secure store/Vault；
签名-only 不开放钱包 UI，只使用同宿主既有 SDK 安全账户，首次建立仍须钱包流程。
现有正式包装仍为 full 并含链资产，运行期未选链不加载资产或创建链数据库。
第4步新增独立 qr=32，full=63。Windows 只将亮度帧交给 SDK 内唯一 ZXing-C++ 3.1.1 图像层，
`QR_V1` 协议与扫码签名会话由同一 Rust QR 模块实现，不设兼容或回退识别器。
本次第 2 步仅更新源码、注释、合同和测试，尚未执行新的真实构建、平台测试或硬件验收；下文旧分步运行记录保留为历史证据，不代表本次变更已验证。

第 1.2 步在 C++/Flutter session 中新增统一钱包状态、冷公钥导入、revision 重排和统一改名/删除。
它们只投影 Core 的公开账户事实；冷账户路径不弹出 Win32 认证、不调用 PCP Vault，且不提供
无授权 default setter、旧 App 钱包迁移或兼容读取。

第 1.5/1.6 步加入 opaque callData 准备及冷热执行。Windows session 只保管 owner-bound
preparation token，并在同步 admission 失败时恢复；冷签 response 固定进入 Core 既有 `QR_V1`，
executionId 可取消同一 Core 长观察。Win32/Flutter 不构造业务 call、签名、payload 或 extrinsic。

本目录是同一个 CitizenSDK 的 Windows 系统适配，不是另一个钱包或轻节点实现。
最低 Windows 11，机器目标 `x86_64-pc-windows-msvc`；公开平台名只有 **Windows**。
本步新增源码与原生构建合同，尚未在 Windows 实际编译、运行或分发。macOS 验收不能
替代 Windows CTest、Win32 交互和实体 TPM 验收。

## 依赖与入口

`CitizenSDK::Host → CitizenSDK::Core → native/ffi → Engine/Contracts/Providers`。
原生安装包含 `citizensdk_host.dll`、`citizensdk.dll`、对应 MSVC import libraries、七个
Host 公开头、两个 Core 公开头、可重定位 CMake 配置与同一 CitizenChain 资产。
原生入口不依赖 Flutter，不复制 signer、交易或 smoldot。第 8.4 步接入默认 Dart 注册和
同版候选运行投影，Flutter 运行包仅保留 22 项安装件与 12 项插件输入，不携带 Host 私有
源码或测试。源码注册不是已经在 Hosted 发布；Windows 实际平台运行仍待统一验收。

```cmake
find_package(CitizenSDK 1.0 CONFIG REQUIRED)
target_link_libraries(application PRIVATE CitizenSDK::Host)
```

```cpp
#include <citizen_sdk/citizen_sdk.hpp>

citizen_sdk::Config config;
config.storage_root = state_directory;  // 绝对路径，当前用户私有目录。
config.asset_root = asset_directory;    // 安装包 share/citizensdk/citizenchain。
config.application_id = "org.example.application";
config.hwnd = nullptr;                  // 关闭钱包时必须为空，不创建钱包窗口。
config.modules = CITIZENSDK_MODULE_CHAIN; // 只读链不创建钱包 UI 或金库。
citizen_sdk::Host host(config);
host.open();                            // 返回的 native_handle 由 Host 唯一持有。
// Core 尚未 start；运行后必须先异步 stop 完成 checkpoint，再关闭。
host.close();
```

钱包模式要求构造所在 UI 线程持续处理 Win32 消息。窗口不能由其它进程或线程冒充；
父窗口销毁会取消正在进行的原生操作，不转成另一个 rootless 窗口继续输入。
关闭返回 BUSY 时保留整个资源图；C++ 析构可转交 supervisor，不能直接销毁借用的 Core。

## 安全与构建

仅 Microsoft Platform Crypto Provider + TPM 2.0，SDK 独立设备金库口令授权 KEK 使用；
没有 Software KSP、DPAPI、Windows Hello 或纯软件降级。TPM RSA 只封装/解封随机 DEK，
sr25519 仍由同一 Rust signer 实现。设备解锁口令不是业务账户密码，不改变链签名 context。

唯一入口是根 `scripts/build-native.sh Windows`。预先提供 MSVC、Rust 目标、CMake、Node、
已固定 SQLite MSVC 静态归档与头；不由脚本安装工具或联网补依赖。工作区和安装前缀只在
TataConsole/runner checkout 外中央目录，源码目录禁止任何编译缓存、DLL、LIB 或日志。
具体环境、未实测门禁和秘密边界见 [Windows 技术说明](../docs/WINDOWS_PLATFORM.md)。

原生构建先保留原有 14 项合同测试，再安装到本次工作目录，核对精确 21 文件、安装清单、
同轮构建字节、版本和完整 PE 导出。独立 C11/C++17 消费者只查准确安装前缀，不包含 Host
私有头或重新编译核心；检查实际加载 DLL，执行启停、异步完成、结果释放和关闭重试。
两个消费者均关闭钱包且不提供 HWND，不触发 TPM 或钱包 UI。随后完成六项 adapter CTest
和真实 Flutter Release 消费者，全部成功后才同卷导出安装目录；
输出已存在或跨卷则失败，不覆盖既有成功结果。Windows 实际执行仍须统一平台验收。

第 3 步安全查看复用既有自绘敏感控件、WDA_EXCLUDEFROMCAPTURE 和原生主线程，
用系统 wtsapi32 监督当前会话锁屏、断开与注销；注册失败或状态无法确认时不显示秘密。
私有 40 字节回调表的 `authorizing` 贯通真实 Host 解包操作号，只有同 Host、同操作号的
SDK 认证窗口可临时获得焦点；认证窗口再次失焦会取消，晚到结果不能恢复显示。
私钥不进入窗口文本消息、剪贴板、Flutter 或通用 result。完整安全流程和真实 Win32/TPM
验收尚未完成。生成私有头仅通过 `CITIZENSDK_INTERNAL_INCLUDE_DIR` 给内部目标使用，不安装。

第 1.4 步新增 12 个通用安全链读取方法。Windows codec/session 仅把固定 tuple 投影到同一
121 项 Core ABI，并校验准确块、optional bytes、body 顺序、累计资源上限和 import finalized
回执；不通过 WinHTTP/Win32 建立旁路网络，不解码任何宿主业务 SCALE。

## Flutter 适配源码

`citizen_sdk_plugin` 通过官方 `flutter`、`flutter_wrapper_plugin` 连接包内同版
`CitizenSDK::Host/Core`，不重新编译核心。使用官方 StandardMethodCodec 和已有双 channel、
63 方法；钱包交互只接本目录现有 Win32 安全流程。无会话 verifySignature 在环境/Host 创建前
直接调用公共 Core；Dart 使用静态 CitizenSigning.verify，无需 open 或事件订阅。

Windows 宿主须在顶层 CMake 引入 generated_plugins.cmake 之前声明一次：

```cmake
set(CITIZENSDK_APPLICATION_ID "org.example.application")
```

这是 3..253 字节小写反向域形式的数据命名空间，不是 Windows 身份认证或业务账户。
必须由宿主固定且升级后不变，缺失/非法立即拒绝，不从展示名、可执行文件、目录或
AppUserModelID 推导。它不进入 Dart tuple；系统 LocalAppData、标准 Flutter 资产与 HWND
由原生环境读取，Host 继续执行已有安全检查。

第 8.4 步同时开启 pubspec 与 `CitizenSdk.open()` 的 Windows 默认入口；缺少同版插件
仍失败关闭。这项原生身份声明意味着 Windows 不是完全零配置，MSVC 运行时也由宿主
部署环境提供。真实消费者只在一次性 GitHub 用户环境运行，不注入私有平台或路径；
应用只使用预检为空的测试命名空间，不创建钱包或触发 TPM 授权。
