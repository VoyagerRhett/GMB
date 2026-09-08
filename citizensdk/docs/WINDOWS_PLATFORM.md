# CitizenSDK Windows 平台合同

扫码窗口由 SDK Host 提供，Media Foundation 仅用于设备采集和像素转换，二维码统一由
同一 ZXing-C++ 识别。系统相机隐私权限关闭、无设备或设备断开都明确失败，不启用其它识别器。
链调用的签名窗口只展示 Rust 已验证审阅，确认后消费同一 Core 结果并复用现有设备授权。

当前为 89 个 Core 函数、17 个 Host 函数、3 个 QR 图像函数和五端统一 36 个 Flutter 方法。
Config.modules 是唯一模块真源，旧 C Host 配置 enable_wallet 的布局/布尔含义保持。
先由 Rust 验证模块，再按需创建 public/secure store 与 Vault；未选 chain 不加载链资产或创建
链数据库，未选 history 不初始化历史。signing-only 不开放钱包管理/UI，只使用同宿主既有
SDK 安全账户；首次 provision 仍须 wallet 流程。运行期选择不裁剪现有 full 包及链资产。
模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

Flutter 创建钱包只传 12／18／24 的 word_count；导入与追加账户显式传 0，不继承创建默认值。
两种入口均经同一个原生 Host 参数校验器，不能静默忽略无关字段。

## 当前阶段

第 8.1 步增加原生 C/C++ Host、Win32 自有 UI、系统存储、PCP/TPM 金库与构建/测试源码；
第 8.2 步新增只连接这些既有能力的 Flutter adapter；第 8.3 步增加独立 C/C++ 安装消费合同。
第 8.4 步同步接入默认 Flutter 注册、同版候选/Hosted 文件与真实公开 Flutter 消费者。
该阶段不修改 CitizenApp 或复制 Rust Core；当前第 2 步按五端统一模块合同扩展根 ABI 与验签方法。Windows 尚未实际编译、运行或发布，源码注册不是平台验收通过。

| 边界 | 固定实现 |
| --- | --- |
| 产品、网络 | CitizenSDK / `citizensdk`；链 ID 和 protocol ID 都是 `citizenchain` |
| 平台、机器 | Windows 11；公开名称 Windows；官方 Rust target `x86_64-pc-windows-msvc` |
| 核心 | 现有 `native/ffi` 动态库；Host 不实现链、metadata、交易或 sr25519 算法 |
| 原生入口 | 17 项 `citizensdk_host_*`；C++ `citizen_sdk::Host` header-only 包装 |
| UI | SDK-owned Win32；父窗口所有权与消息分派均限创建线程 |
| 金库 | Microsoft Platform Crypto Provider、TPM 2.0、用户级不可导出 RSA-2048 KEK |
| 认证 | SDK 独立设备口令，PBKDF2-HMAC-SHA256 派生后通过 PCP 官方 PIN 属性授权 |
| 存储 | Win32 HANDLE 绑定的私有 SQLite VFS；公共状态与钱包密文分库 |

## 秘密与认证

TPM 仅保护 KEK/DEK，不能执行 sr25519。CNG OAEP-SHA256 解封输出直接写调用 Core 所有的
32 字节 Rust buffer；账户秘密解密、签名、清零仍在 Rust。原生 SDK 自有输入控件有界保存
口令/助记词，不使用普通 EDIT、剪贴板、业务字符串或 Flutter 通道转发。SDK 自有缓冲区
显式 `SecureZeroMemory` 后释放；不能由此声称操作系统渲染缓存、屏幕截图或恶意同进程代码
也已被清除或隔离。

PCP 只按当前用户范围创建持久 KEK，明确验证 TPM 2.0、硬件实现、用户 ACL、RSA 类型、
用途、授权要求、不可导出属性及公开对象身份。generation 的随机 16 字节组成唯一 key name
`citizensdk.<generation hex>`，同时是公开派生盐；秘密不写 key name。SDK 不持久化解锁口令
或派生 PIN，不复用已授权 key handle，不开启 Software KSP、DPAPI 或 Windows Hello。

PCP 的通用 PIN 属性存在操作系统缓存语义；关闭句柄并不等于证明缓存已清除。
本实现使用每次显式授权的候选路径，**尚未证明**真实 PCP 在冷/暖进程、重开 key、错误/缺失
口令及静默调用下完全满足强认证合同。隔离 Windows/TPM 验证是正式分发的必过门禁。
生产代码不自动注入错误口令，不清 TPM、不变更 owner、不用未经文档确认的清缓存属性。

官方依据：[Microsoft CNG providers](https://learn.microsoft.com/en-us/windows/win32/seccertenroll/cng-key-storage-providers)、
[CNG key properties](https://learn.microsoft.com/en-us/windows/win32/seccng/key-storage-property-identifiers)、
[Microsoft PCPTool sample](https://github.com/microsoft/TSS.MSR/blob/main/PCPTool.v11/exe/SDKSample.cpp)。

## 持久化、并发与取消

每个应用使用 `storage_root/application_id/citizensdk/v1/{public,secure}`。当前用户 SID、
受保护 DACL、真实目录、文件身份和单链接约束在句柄上检查；现有宽权限目录被拒绝，
不擅自收紧用户现存数据。安装资产只读，允许安装者拥有，但不接受 reparse 或硬链接替换。
SQLite 主库、journal、WAL、SHM 通过已验证父 HANDLE 相对打开，IO/同步/删除使用同一 HANDLE；
不借 `SQLITE_FCNTL_WIN32_SET_HANDLE` 测试接口替换默认 VFS 的句柄。

Core 的 typed record、CAS、写前所有权、generation 和永久墓碑语义保留。
PCP 持久对象创建不能被当成临时内存：崩溃恢复按 generation 精确定址，CAS 失败方不能销毁
胜者 key；退休顺序是持久墓碑、删除 PCP key、删除对象记录，删除失败留可重放身份。
平台实现必须串行化同一 generation 的跨实例副作用，避免墓碑清理后又出现晚到的持久 key。

Win32 dispatcher 只传内部操作身份，不传秘密指针给公开回调。父 HWND 通过同进程/同 UI
线程与销毁通知绑定，不能仅依靠可能复用的 `IsWindow`。关闭要等待 Core 停止及请求、结果、
服务和窗口租约退出；窗口必须在 UI 线程销毁，BUSY 时整个 Host/store/vault 图保持可重试。

## 唯一构建路径与后续证据

`scripts/build-native.sh Windows` 使用预装 MSVC、Rust target、CMake、Node 与固定 SQLite
归档/头。`CITIZENSDK_WORK_DIR`、`CITIZENSDK_NATIVE_OUTPUT_DIR` 使用 Git Bash 绝对路径；
`CITIZENSDK_WINDOWS_SQLITE_INCLUDE_DIR` 与 `CITIZENSDK_WINDOWS_SQLITE_ARCHIVE` 指向预置只读依赖。
脚本在首次写入前拒绝源码内路径、非法 Windows 名称、设备/UNC 路径、别名或 reparse 祖先，
再显式转换给 MSVC 工具；Rust `--locked --offline`，没有第二套 PowerShell/CI/Release。

原生安装布局：

```text
<中央安装前缀>/
├── bin/Windows/                 # citizensdk.dll、citizensdk_host.dll
├── lib/Windows/                 # 对应 import libraries 与 cmake/CitizenSDK
├── include/                     # 两个 Core 头与七个 Host 头
└── share/citizensdk/citizenchain/ # 三份精确链资产
```

源包审计固定 Windows 的 62 个生产文件、28 个测试输入和平台文档，拒绝额外目录和任何
生成状态。当前候选按精确白名单注入安装件，Hosted 保留 34 项运行输入，不纳入
Host 私有源码。MSVC 运行时由宿主部署环境提供，SDK 不额外捆绑未登记运行库。
MSVC/CTest、全量 PE 导出、UI、跨进程存储与真实 TPM 结果必须在后续统一 GitHub CI（增量）
和 Release（全量）取得。当前源码检查、合成数据或 macOS 编译均不是这些运行证据。

### 安装与 C/C++ 消费合同（第 8.3 步）

唯一构建器保留 14 项原生 CTest，先安装到 work_dir/Windows/install。安装清单与磁盘
反向枚举必须精确为 22 文件：10 个公开头、2 个 DLL、2 个 import library、5 个 CMake
文件和 3 个链资产；不含 Flutter 注册头。安装文件与源码/本轮 Core、Host、CMake 输出
逐字节一致，SDK 版本、PE 机器格式与完整导出同时核验。

独立 CMake 只查准确版本及安装前缀，两个消费者不访问 Host 私有源码或测试支撑，不
重编核心。导入目标路径、公开 include、同版资产及运行时实际加载的 DLL 均核对来源。
异步上下文在请求接纳前建立；C 拥有结果并唯一释放，C++ 回调借用结果且由包装层释放。
关闭 BUSY 有界重试，不能丢弃仍然存活的句柄，也不依赖 Release 可删除的断言。

消费者关闭钱包、HWND 为空，只验链 Host 的能力、启停、checkpoint、结果所有权及关闭，
不证明 PCP/TPM、UI 或钱包实测。第 8.4 步在安装和两个消费者之后追加正式 Flutter 验证，
全部通过后才向全新输出位置同卷导出；目标已存在、链接或跨卷即失败，已有成功输出不被
覆盖。同一安装输入供根 Release 候选和默认 Flutter 运行投影共同使用。

## Flutter 绑定与应用身份（第 8.2 步）

依赖为 `CitizenSdk → 标准双通道 → Windows adapter → 已安装 Host/Core`。官方
StandardMethodCodec 的字符串保留精确长度，不引入 Linux GLib 的专用内部表示。36 个
方法与其它四份绑定按独立金标对齐，不增加 Windows 专用 Dart 参数或业务方法。

open 只接受 `[1, modules]`；无会话 verifySignature 只接受
`[1, accountId, signature, payload]`，返回 `[1, bool]`，错误 session/sequence 均 null。
该方法在 session 查找与环境/Host 工厂前调用纯 C，无需 open、事件订阅、数据库或金库。

宿主顶层 Windows CMake 在 generated_plugins.cmake 之前显式设置
`CITIZENSDK_APPLICATION_ID`。它原样成为现有 Config.application_id，必须满足
3..253 字节小写反向域规则、跨升级稳定；没有共享默认值、静默小写转换或路径/展示名推导。
这是持久数据命名空间声明，不是 Windows 身份验证；SID/DACL 和 TPM 安全边界仍由 Host
执行。Windows 除包依赖外需要这一项原生配置，不能称为完全零配置。

原生环境使用系统 LocalAppData 和标准 executable-relative
`data/flutter_assets/packages/citizen_sdk/assets/citizenchain`。身份、路径和 HWND 不进入
Flutter tuple，窗口销毁不得变成新无父窗口输入。适配层只调度公开拥有值，Core/Host/result
句柄及钱包秘密始终留在原生内部。

Windows Host 可能在 Core 已释放后仍因窗口退休返回 BUSY。适配层仅在真实发起关闭且
Host 明确报告 Core 已退休时保留内部重试状态，其它操作拒绝；只有 Host.close 成功后才向
Dart 返回 disposed，不能把一次 BUSY 当作完成或再次访问已释放的 Core。

CMake 只消费包内精确同版 DLL、import libraries、公开头与 Host→Core 依赖；插件和测试
使用自身异常设置，不修改宿主全局编译选项。六项 adapter 测试与原生 14 项分支隔离，
不重编第二份 Host/Core。当前 Hosted 精确保留 22 项安装件与 12 项插件输入；七个
Host 头与审计源码重叠，字节必须一致。纯源码默认检查仍拒绝 DLL/LIB 等生成内容。

## 正式 Flutter 消费者（第 8.4 步）

唯一构建器用同版安装件和未改写的 SDK pubspec 生成官方 Flutter 宿主，通过自动 registrant
与 `CitizenSdk.open()` 验证真实插件；保留 14 项原生、2 项 C/C++ 和 6 项 adapter 检查。
程序必须在 Release 下执行，检查初始错误、能力、空 profile、启停/事件、关闭与重开，
超时或非零退出均失败，成功标记必须恰好一次；最终 DLL/链资产必须来自本轮安装。

实际 Windows 运行仅接受一次性 GitHub 隔离用户环境。应用数据仍来自系统 Known Folder，
只使用预检不存在的 org.citizensdk.flutterconsumer，结束核验归属再清理，不能删除用户
数据根或引入 SDK 私有路径参数。不创建钱包、执行签名、交易或 TPM 强认证；实体硬件
能力与行为仍须另行真实验收。本机 macOS 的 Node/Dart 检查不替代此 Windows 程序运行。
