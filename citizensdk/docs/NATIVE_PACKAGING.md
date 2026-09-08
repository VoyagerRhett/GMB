# CitizenSDK 原生产物与候选打包

当前闭集为 89 个 Core C 函数、Linux/Windows 各 17 个 Host C 函数、3 个
ZXing-C++ 图像 C 函数和五端统一 36 个 Flutter 方法。新增符号不改变 ABI v1
既有结构和数值。模块选择只影响运行时服务与
资源装配，不是发布包裁剪：现有正式包装仍编译 full，并完整携带链资产。未选 chain 的实例
不加载这些资产、不创建链数据库或启动 smoldot。模块化、链查询与安全查看的完整五端硬件验收尚未完成；准确构建、测试与运行证据以当前任务卡为准，旧分步结果不替代本轮验收。

## SDK CI/Release 依赖接线

固定 Flutter 提交先引导对应 Dart，Pub 预加载显式使用其实际 dart/dart.exe。中央预加载
仍限定登记 task 的缓存目录；SDK 仅把原锁中的官方包和已核验摘要投影到本作业缓存，
不复制凭据、任意缓存条目或符号链接。CI 沿用统一增量缓存，Release 使用本次全新
CARGO_HOME 和 target，CARGO_INCREMENTAL=0；Linux fetch 与断网容器使用同一个已挂载根。
Release 来源参数是 `--pipeline gmb.citizensdk.sdk.ci`，不是 workflow 文件名；独立核对
准确 `.github/workflows/repository.yml`、成功状态、显示标题、冻结 SHA 与源码版本。

## 同源汇总与同包消费

中央产品流程采用五宿主构建 → macOS 汇总 → 五宿主同包消费，Release 再接正式发布阶段。
CI 使用统一增量缓存：原生阶段复用 Cargo，中间消费者复用 Pub、Gradle、CMake 对象与 Apple
module cache；最终库、消费者程序、证据和钱包测试状态先清除且不入缓存。Release 只复用已
验证官方工具原件，原生件和消费者均在本轮全新根中全量重建，不取 CI 编译件。
Apple 作业同时覆盖 iOS 与 macOS，LinuxARM、LinuxAMD 始终是两个独立原生作业。

阶段 0 的 USTAR 包携带 `phase0.json`，绑定 `source_sha`、`software_version`、`run_id`、
`run_attempt`、`job`、`platforms` 和逐文件摘要；五份证明必须来自本次冻结运行。
汇总使用标准归档解析器，先检查闭集再写普通文件，最后按本 SDK 发布器导出的唯一
Apple 链接合同重建五条 framework 内部链接。任何缺项、混版、覆盖、硬链接或路径越界失败。
完整候选和 Hosted 字节只由 `scripts/release.mjs` 生成/验真，不存在第二份打包算法。

最终消费者参数统一为：

    scripts/build-native.sh <Android|iOS|macOS|LinuxARM|LinuxAMD|Windows> \
      <candidate> <audit.tgz> <hosted.tar.gz> <flutter> <pub-cache> <tool-path>

输入位于调用方准备的互斥工作路径。消费者从 Hosted 包加载正式运行件，测试源码只读对应
审计候选，不往 Hosted 补测试，也不重新构建 Core。桌面运行公开消费者；Android 核对最终
ARM64 Release APK 的两份 SDK 库与 Hosted 字节相同；iOS 构建 device Release 宿主和
Simulator ARM64 Swift 链接。后两项不声称真机运行，也不要求上传应用商店签名凭据。

## 静态依赖准备与证据（第 10.5 步）

中央唯一来源为 TataConsole 的 flows/gmb/shared/dependencies.json 内
native_dependencies 子合同；同目录 dependencies.mjs 的 prepare-native 子命令执行准备。
SDK 不依赖另一个仓库路径：release.mjs 只固定子合同规范 JSON 的 SHA256，并验证输入收据
内的合同副本。不自动升级，不使用 latest；SQLite 的官方 SHA3-256 与独立计算的 SHA256
分别保存、分别验证，绝不混写算法。

| 平台 | 固定静态输入 | 构建要求 |
| --- | --- | --- |
| LinuxARM / LinuxAMD | SQLite 3.53.4、OpenSSL libcrypto 3.5.8、TPM2-TSS 4.2.0 | 原生 GNU 对应架构、PIC、最终 GLIBC 不高于 2.31 |
| Windows | SQLite 3.53.4 | 原生 x64 MSVC，Release /MD，拒绝 import library 冒充静态实现 |

SQLite 仅固定 SQLITE_THREADSAFE=1，不裁剪默认 OS VFS、WAL、外键和 PRAGMA。
OpenSSL 使用官方 no-shared/no-module/no-dso/no-tests 与 -fPIC，依次构建 build_generated、
libcrypto.a；不执行会额外构建 libssl 的 install_dev，不使用会禁用 PIC/线程的 -static。
TPM2-TSS 保留 ESYS/SYS/MU/RC/device，禁用 FAPI/Policy/其它 TCTI，启用 nodl。
只构建五个官方 .la 目标并复制静态 .a，不执行 make all/install 或 autotools bootstrap。
OpenSSL 头固定为 142 个；TPM2-TSS 头固定为八个；SQLite 只带 sqlite3.h。

准确调用接口（路径由既有中央作业提供，不是第二套 CI）：

    node <中央 flows>/gmb/shared/dependencies.mjs prepare-native --scope citizensdk \
      --platform <LinuxARM|LinuxAMD|Windows> --work <全新中央工作子目录> \
      --sources <既存归档缓存目录> --sdk <同源SDK目录> --mode <ci|release> \
      --source-sha <冻结GMB提交> --software-version <源码版本>

第 10.6 步已将准备接口接到 CI 阶段 0。CI/Release 均可复用中央摘要对象库的固定官方原件，
仍须验证长度与所有摘要；Release 不复用任何 CI 编译件，在全新目录全量重建。
原件复用不等于增量编译；本入口不另实现缓存保存/恢复。CI 指纹包含中央合同、准备器及
SDK 锁和构建器。调用方必须先准备工具，prepare-native 自身不安装任何系统组件。

    <本轮中央工作目录>/
    ├── <平台准备目录>/          # 全新目录，不写 SDK 源树
    │   ├── sources/             # 官方归档验证后解包，保留上游 mtime
    │   ├── tmp/                 # 本轮工具临时文件
    │   └── prefix/
    │       ├── include/         # 对应平台完整公共头闭集
    │       ├── lib/             # 仅本平台准确静态归档
    │       └── native-dependencies.json # 来源、选项、入口工具身份及输入摘要
    └── <原生输出目录>/
        ├── linux/               # 既有 LinuxARM/LinuxAMD 安装闭集不改
        ├── Windows/             # 既有 Windows 安装闭集不改
        └── dependencies/        # 三份生成证据，不是仓库源码目录

构建器要求 CITIZENSDK_DEPENDENCY_RECEIPT 和冻结 GMB_SOURCE_SHA。先验证收据及所有
实际头/库，由同一前缀填充现有 CITIZENSDK_HOST_* 或 CITIZENSDK_WINDOWS_SQLITE_* 入口；
若调用方同时指定不同路径即拒绝，不能拼凑多个前缀。静态库按 ar 成员逐项验证目标 ELF/COFF
结构和架构，拒绝 thin ar、动态库、import object、截断和越界。原有最终 ELF/PE、导出、
GLIBC、消费者运行门禁全部保留；通过后才写三份 dependencies/<平台>.json，绑定输入和
最终 Core/Host SHA256、SDK 版本/提交以及 LICENSE/THIRD_PARTY_NOTICES 字节。

唯一发布器在创建候选前验证三份证据，将它们合并成生成的根 native-dependencies.json，
由既有 manifest.files 和 tgz 校验和覆盖；manifest 顶层仍是原六字段，外层仍是既有三件套。
同一证据也进入 Hosted 包，不新增发布渠道。不得把缺证据的旧三端候选当作完整新候选。

build_tools 记录直接入口工具的实际 SHA256（Linux 的 C 编译器还记录 GNU target），
不是完整系统头/sysroot/编译器内部程序 SBOM，也不是远程签名证明；准确中央流程指纹与
实际平台运行证据仍由后续统一 CI/Release 提供。本步本机只执行受控 Node/Bash 及来源
检查，不声称 Linux/Windows 静态编译、硬件金库、消费者或整个分发许可闭包已验收。


## 源码树规则

`/Users/rhett/GMB/citizensdk` 只保存源码、`assets/README.md` 资产边界、
`assets/citizenchain` 固定链资产、manifest、锁文件、文档和测试源码，
不得保存 `.so`、`.a`、`target`、`build`、CMake cache、`.dart_tool`、Gradle/CocoaPods 状态或
Release 包。

根 `Cargo.toml` workspace 现包含 `native/contracts`、`native/engine`、`native/ffi`、
`native/signer` 和 `native/smoldot/provider`。前三项是 CitizenSDK 自有 Core/产品 ABI 闭集；
Provider 是 `SOURCE_SHA256.json` 中单独分类的 SDK-only smoldot 适配。`engine` 精确依赖官方
`subxt-core = 0.43.0`。收编的 PoW/light-base 保留嵌套 workspace 与已验证锁语义；Release
另外核对 Provider 递归 smoldot registry 闭包与 PoW 锁的 name/version/checksum 完全一致。

统一原生入口 `scripts/build-native.sh` 要求调用方提供源码树外的：

```text
CITIZENSDK_WORK_DIR=<Cargo 工作目录>
CITIZENSDK_NATIVE_OUTPUT_DIR=<原生产物目录>
```

脚本在首次 `mkdir` 前要求两个目录都是绝对规范路径，拒绝 `.`、`..`、重复或末尾分隔符，
并逐级拒绝既存符号链接及非目录祖先。发布器对 candidate、archive 和 verify 路径执行同一
预检，不能借中间符号链接或路径穿越把生成状态写进 SDK 源码树或 TataConsole 中央目录之外。

脚本使用 `cargo build --locked`。Android 产品目标构建唯一
`libcitizensdk.so` 与薄 `libcitizensdk_jni.so`，拒绝 `libsmoldot`、共享 C++ 运行库、额外 ABI
或第二份 Core。Apple 产品从 `native/ffi` 构建同一 `citizensdk_*` Core，再将
`darwin/Sources/CitizenSDK` Swift 源码、根产品头、Privacy Manifest 与完整 CitizenChain 资产组合为一个
`CitizenSDK.xcframework`。其闭集只有 iOS 设备变体、iOS 模拟器变体与 macOS；三个
Apple machine slice 的架构元数据均为 `arm64`；
每个 slice 精确导出产品头声明的 89 个符号及 3 个 QR 图像符号，并拒绝 `smoldot_*`、`citizen_sr25519_*`、
`account_crypto_*` 和其它架构。

legacy `libsmoldot.dylib` 只允许作为源码树外的 macOS `arm64` 差分测试宿主库生成；它绝不进入
XCFramework、Hosted 或 GitHub 候选。其 `LC_ID_DYLIB` 是编译工作区的 build-local 路径，只适合
按准确文件路径直接加载测试，不是可分发 install name，并须随 `.work` 清理。

显式 `abi-host` 目标从 `native/ffi` 构建当前宿主测试用 `libcitizensdk`，把真实导出符号与根
`include/citizensdk.h` 逐项比较，同时用 C11/C++17 编译合同核对全部公开布局；任何
`smoldot_*`、`citizen_sr25519_*` 或 `account_crypto_*` 泄露都会失败。它只写入调用者指定的
外部 `abi-host/` 目录，不加入 `all`，也不进入 Android/Apple 正式候选。
产品 ABI v1 保持既有 73 个符号，再追加模块验证、模块构造和无实例验签三个符号，以及四个链查询/结果符号，
QR 统一为 9 个协议、审阅、签名和结果符号，总计 89 个；构建产物与头文件
任一缺失、额外或重复都必须失败关闭。

Android Core 在进入 Gradle 前由固定 NDK 的 `llvm-strip --strip-unneeded` 显式处理一次；该同一
staging 字节随后复制为独立 `libcitizensdk.so` 并进入 AAR。构建结束再逐字节对拍 AAR 与独立
双库，避免 AGP 在 AAR 内隐式产生第二个 stripped Core 版本。
Android Core 同时固定 `DT_SONAME=libcitizensdk.so`；JNI 固定
`DT_SONAME=libcitizensdk_jni.so`，并且必须只按该 SONAME 依赖一次 Core。最终 ELF 门禁拒绝
任何包含 `/` 的 `DT_NEEDED`，防止中央构建机绝对路径进入设备运行时依赖。

Android 原生 AAR 与 Flutter 插件消费同一产品双库字节。Apple Swift 原生 API 与 Flutter
adapter 消费同一个 `CitizenSDK.xcframework`；`native/smoldot/ffi` 只属于归档差分测试，不能
被描述为任何正式平台的产品 ABI。

第 4.1 步已经加入 Rust Core 账户、钱包、sr25519、准确 V4 交易构造和历史源码；钱包
创建使用 prepare/备份确认/commit，删除使用永久密文墓碑和 generation retirement，钱包交易在
pending CAS 成功后才广播。第 4.2 步完成 Rust 内部 provider/runtime/store/vault 组合；第 5.1
步在未发布 ABI v1 内保留旧 `citizensdk_create` 的 chain-only 语义，并追加
`citizensdk_create_with_host`、五类 typed stores/KEK-DEK Vault 合同以及账户、钱包、签名、
高层转账和历史投影。第 5.2 步进一步完成 Dart 公共入口、Android Kotlin/JNI/安全界面、
Flutter tuple channel 与 Android 候选投影；第 6 步共享 Darwin 源码把同一产品 ABI 投影为
Swift/Flutter、typed SQLite 与 Apple Vault。TataConsole Flow 同步仍由后续步骤验收。

同一未发布 ABI v1 还把平台链数据库接点固定在既有 start/export/stop：host start 自动恢复，
host export 与 graceful stop 自动 exact-CAS 持久化；legacy constructor 跳过这些自动动作。
host start/stop/import 独占异步 admission，平台包装必须先收口较早请求，并在完成前阻止后续控制；
Android/Apple 包装不得自行解析私有 store 信封或另造缓存协议，且直接 destroy 不作为 checkpoint。

第 7.1 步新增 LinuxARM、LinuxAMD 共用的 Host/C/C++ 源码、typed stores、TPM Vault 与合同
测试；第 7.2 步增加只消费同版已安装 Host/Core 的 Flutter plugin 源码及测试。两步都不修改
Rust Core、根 C ABI、Cargo workspace 或 Dart 平台注册，没有生成 `.so`、运行 Linux
编译/CTest，或把 Linux 加入正式候选 manifest。

Android NDK 版本在 SDK 原生入口中固定为 `28.2.13676358`，与 GMB 官方依赖合同一致。
调用方提供 `ANDROID_NDK_HOME` 时必须精确指向该版本；同时提供 `ANDROID_HOME` 与
`ANDROID_SDK_ROOT` 时两者必须一致。若三个 Android 环境变量均缺失，本机入口只从宿主标准
SDK 目录（macOS 为 `$HOME/Library/Android/sdk`，LinuxARM 或 LinuxAMD 为 `$HOME/Android/Sdk`）解析该固定
版本，不扫描或选择“最新”NDK。这样 SDK 本机构建不依赖塔塔控制台版本，同时仍拒绝版本漂移。

Apple 产品构建固定 `ios_deployment_target=16.0` 与 `macos_deployment_target=13.0`。iOS 设备变体、
iOS 模拟器变体与 macOS 三次 `cargo build` 分别使用 `aarch64-apple-ios`、
`aarch64-apple-ios-sim` 与 `aarch64-apple-darwin`，并显式设置对应最低系统版本，避免 Rust/C
对象继承构建机当前系统。`darwin/citizen_sdk.podspec` 与 `darwin/Package.swift` 使用相同最低
版本合同；所有 Swift module、framework binary 与 XCFramework 的机器架构元数据都必须精确为 `arm64`。

## LinuxARM 与 LinuxAMD 原生安装边界

Flutter 官方平台源码目录固定为小写 `linux/`；公开平台目录和 manifest 值只允许
`LinuxARM`、`LinuxAMD`。两者对应的工具链值分别是 `aarch64-unknown-linux-gnu` 与
`x86_64-unknown-linux-gnu`，首版动态兼容基线固定为 glibc 2.31。这些 target triple、ELF
machine 和 `CMAKE_SYSTEM_PROCESSOR` 只属于机器字段，不能演变为额外产品名。

第 7.4 步统一候选合同纳入以下双库路径；第 7.3 步已有的安装投影和消费者装配继续复用同一构建器。
当前开发以本机 macOS 编译通过为验收标准；2026-09-03 已通过既有 `abi-host` 与 `apple`。跨平台构建
与功能验证后续统一进入 GitHub CI 增量缓存、Release 全量构建，不再等待用户提供 Linux/TPM
环境，仍只交付同一 Core commit、SDK 版本、ABI 版本的一个 CitizenSDK Release：

```text
linux/lib/LinuxARM/libcitizensdk.so
linux/lib/LinuxARM/libcitizensdk_host.so
linux/lib/LinuxAMD/libcitizensdk.so
linux/lib/LinuxAMD/libcitizensdk_host.so
```

独立 Core 动态库必须精确导出89个公开函数及4个内部查看链接函数；Host只装配typed stores、TPM/认证、SDK-owned
钱包流程和生命周期，不复制 smoldot、signer 或 Engine。Host 只能按 SONAME 依赖 Core 一次，
两库不得出现绝对 `DT_NEEDED` 或构建机 RPATH/RUNPATH。CMake 公开目标固定为
`CitizenSDK::Core` 与 `CitizenSDK::Host`，C++ convenience API 保持 header-only，不引入跨
编译器 C++ ABI。Host 使用自有 openat 型 SQLite VFS，把主库、journal、WAL 与 SHM 的实际
文件操作绑定到已验证目录 fd；不得依赖 `/proc/self/fd` 或重新解析可替换路径。第 7.3 步
安装后 C/C++ 消费者仅通过安装头和运行库验证生命周期、能力与错误所有权；目录替换、sidecar、
精确 schema/PRAGMA 与 durable commit 线性化仍由同轮的既有 Host 合同目标覆盖，不为消费者
开放 Host 私有实现或复刻存储测试。

Flutter generated plugin target 固定为 `citizen_sdk_plugin`，文件名为
`libcitizen_sdk_plugin.so`；它从选定安装前缀的
`lib/<LinuxARM|LinuxAMD>/cmake/CitizenSDK` 精确发现同版 `CitizenSDK::Host/Core`，并把双库
列入同一个 Flutter bundle。它不从系统路径、网络或另一仓库补依赖，也不重编 Host/Core。
原生 C/C++ 安装排除 Flutter registration header，不使非 Flutter consumer 依赖 Flutter。

第 7.3 步安装/消费者装配继续属于唯一 `scripts/build-native.sh`。后续统一 GitHub CI/Release
执行 Linux 分支时，只消费显式预装的 Flutter/Pub 缓存，副本及 XDG/TMP 状态都位于中央工作目录；
既有工具 `HOME` 也必须已位于本轮 work_dir、当前用户所有且为 `0700`，构建器不重设它。
Flutter 工具子进程禁网，缺缓存/隔离能力即失败；
不引入下载、系统安装、挂载或虚拟机编排。这是后续 Linux 执行合同，不是当前开发等待用户
提供环境的条件；目前没有 Linux 实际构建结果，macOS 编译也不能代替该结果。

CMake 安装投影包含根 C ABI
头、7 个 Host/C++ 头、同平台双库、平台隔离 CMake package 和三项 CitizenChain 资产；Flutter
注册头不进入原生安装。`linux/test/CitizenSDKConsumer.cmake` 只消费该安装投影，C、C++ 两个
消费者不编译 Host/Core。真实 Flutter 消费者在一次性中央测试工程装配 generated registrant，
复用同版安装双库；第 7.4 步根包已正式登记 Linux plugin，消费者直接调用 `CitizenSdk.open()`，
不再注入内部 platform 或临时改写 pubspec。plugin 自己固定 `$ORIGIN`，删除测试 runner 的
运行库查找代偿。

两种平台各 20 项安装件在候选 `linux/` 下合并为 27 项；共享头和资产必须逐字节一致，平台
库与 5 项 CMake 包配置按 `LinuxARM`、`LinuxAMD` 隔离。源码校验拒绝生成状态，候选校验只
准入此准确投影，不覆盖漂移文件。Hosted 只保留这 27 项及插件所需的 12 项输入：Linux
`CMakeLists.txt`、`cmake/CitizenSDKFlutter.cmake`、5 个 `.cc`、4 个 `.hpp` 和 Flutter 注册头；
共 39 项，不包含 Host 私有源码、测试或原生构建模板，也不重建 Core/Host。发布器检查
完整安装件、同版声明与 ELF 结构；真实构建来源、依赖和许可证证据仍须在后续统一
CI/Release 补齐，证据缺失不得正式分发，不能把结构检查冒充来源证明。

CMake 的 Config 前缀、完整导入目标与 Release 属性按官方生成指令闭合，只允许已知的
生成器版本保护差异。校验不执行候选 CMake，也不只查一行路径或使用目录名黑名单；追加
`set_property`、额外 `include`、重复赋值或其它覆盖指令均被拒绝。ELF 的动态表必须与
映射段和相应符号/版本节一致；DT_NEEDED 检查禁止项和唯一 Core，不冒称外部系统库
已经得到完整依赖溯源。合成 ELF 测试仅证明这些检查有效，不证明平台执行或 TPM 功能。

本机 Linux 构建与测试状态必须写入
`/Users/rhett/TATA/tataconsole/work/gmb/citizensdk` 下的任务独占工作目录；GitHub runner 使用统一
工作流的 checkout 外独占目录，不照搬本机绝对路径。第 7.1 步只固定源码
和 Release 源文件反向闭集；上述 Linux 安装、ELF、GLIBC、TPM 和两种机器运行门禁尚未执行，
第 7.4 步候选 manifest 合同已同步为 Android、iOS、macOS、LinuxARM、LinuxAMD；这是源码
投影合同，不是已生成全部运行件或已发布正式 Release 的声明。
Linux CMake/CTest 调用方必须以
`-DCITIZENSDK_TEST_WORK_DIR=<该任务目录>` 注入一个已存在、有效 UID 所有、权限为 `0700` 的
绝对目录；测试不创建或猜测中央根，只在已验证目录 fd 下以 CSPRNG 名称和 `mkdirat` 创建
本用例子目录，也没有 `/tmp` fallback。

## Android 与 Apple 注入

Android 根 Gradle 与 native AAR 子项目统一读取：

```text
CITIZENSDK_ANDROID_BUILD_DIR=<源码树外的 Android 构建根>
CITIZENSDK_ANDROID_CORE_DIR=<直接包含双 SO 的 arm64-v8a 目录>
```

后一目录必须且只能包含 `libcitizensdk.so` 与 `libcitizensdk_jni.so`。本机两个目录必须使用获准
中央工作目录，并同时满足既有 Gradle 与原生构建器的门禁；GitHub Actions 必须位于 checkout 外。
第 8.2.1 步仅修改发布器本机门禁，没有修改或重新验证 Android 构建器的路径接纳范围。根 Flutter 模块
通过 source set 编译 `android/native/src/main/kotlin` 的同一生产 facade，不依赖或嵌套 AAR。
正式候选另外放置 `android/citizensdk.aar` 供原生宿主使用。
Gradle/Kotlin 的 persistent project state 必须由构建器显式定向到 TataConsole 中央 work
directory；源码树不得生成或保存 `android/.kotlin`，候选构造与反向验证也必须将其视为错误。

Apple 构建不读取 legacy iOS 静态库目录。统一原生入口在外部工作目录生成
`apple/CitizenSDK.xcframework`，随后由候选构造器原子注入到 `darwin/CitizenSDK.xcframework`。
podspec、Swift Package 与 `Sources/CitizenSDKFlutter` 均引用这一名字固定的 XCFramework，不重新链接一份
Core。反向验证精确核对 iOS 设备与模拟器变体、macOS 三个 slice、单一 Apple `arm64` machine 架构、
每个平台的准确 install ID、产品 70 符号、Swift interface、根头文件、
Privacy Manifest 与完整链资产；缺失或额外项均失败关闭。

iOS 设备和模拟器变体的 framework 是浅层布局，二进制位于
`CitizenSDK.framework/CitizenSDK`，install ID 均为
`@rpath/CitizenSDK.framework/CitizenSDK`。macOS framework 使用标准版本化布局，真实二进制
位于 `CitizenSDK.framework/Versions/A/CitizenSDK`，install ID 为
`@rpath/CitizenSDK.framework/Versions/A/CitizenSDK`。macOS 产品和 slice 公开名称始终是
`macOS`，不会附加架构后缀。

macOS framework 内只允许并必须保留以下精确五个相对符号链接：

```text
Versions/Current -> A
CitizenSDK -> Versions/Current/CitizenSDK
Headers -> Versions/Current/Headers
Modules -> Versions/Current/Modules
Resources -> Versions/Current/Resources
```

iOS 两种变体、XCFramework 其他位置和候选其他目录不允许任何符号链接。上述五个链接
若目标、相对路径、节点类型或数量漂移，或出现绝对路径、`..`、dangling、环路、逃逸，同样
失败关闭。

## 本机 TataConsole

CitizenSDK 的永久最终容器为 `/Users/rhett/TATA/tataconsole/target/gmb/citizensdk`，
永久工作容器为 `/Users/rhett/TATA/tataconsole/work/gmb/citizensdk`。
唯一 `release.mjs` 对 native 输入、候选输出和归档路径只接受上述两根的严格后代；拒绝
永久根自身、旧根、相邻仓库/产品/平台、伪前缀、非规范路径及既存链接。只核验本次命中的
根存在且为普通目录，不要求未使用的另一个根存在。GitHub 的隔离路径分支保持不变。
该函数不负责 UID/权限、清理或事务提交；执行方仍须验证任务归属，只清理自己的内容，
保留永久容器。第 8.2.1 步未修改原生构建器、控制台实现或 GitHub 流程。

下述为既有本机构建快照和三件套事务职责，不是本步重新验收控制台的声明。本机构建先读取
GMB 当前提交 SHA，再通过 `git archive <sha> citizensdk` 建立无生成状态的打包快照；构建
快照从该提交快照派生。这样工作区未提交修改不会被错误标注为已提交 HEAD。

成功后中央目录只保留：

- `citizensdk.tgz`
- `citizensdk-release.json`
- `SHA256SUMS`

替换使用带恢复槽的三件套事务；`.work` 和恢复记录在完成或恢复后清理。目录中已经存在的
三件套只证明其生成时的提交，不能证明当前未提交源码已构建或通过。
当前中央目录中唯一已知的两行外层合同之前的历史三件套，以 tgz、manifest、sums 三个固定
SHA-256 同时识别。它只允许作为准确历史前驱被完整备份、原子替换或失败恢复；任何其他
324 行先前清单、部分集合或损坏字节均不在接受范围内并失败关闭。

TataConsole 本机构建以 `work/gmb/citizensdk/candidate-transaction.lock` 覆盖初始化、构建、提交和恢复的完整
跨进程事务。锁 owner 先以 noclobber 完整写入 PID 与随机 token，再由同文件系统硬链接原子
声明固定普通文件锁，不存在空 owner 固定态。活动、非法或无法确认死亡的 owner 均失败关闭，
失效锁只有在两种本机进程检查均证明 PID 已死亡后才可原子接管。退出清理只能移除逐字节属于
本进程的锁；恢复槽建立前和最终提交前还会重新检查中央目录闭集。

## CI 与 Release

CitizenSDK 复用 GMB 唯一顶层 Workflow 和现有产品流程。第 10.6 步现态：

- CI 阶段 0 对冻结 GMB SHA 分为五宿主作业，分别调用原有 Android、Apple、LinuxARM、
  LinuxAMD、Windows 构建入口。Apple 一次生成唯一 XCFramework；iOS device/simulator
  编译测试 harness，macOS 执行 XCTest。Android 执行两类绑定单元测试，Linux/Windows
  保留原有原生和 Flutter 消费者；本机未运行这些远程命令，不能宣称其已通过。
- 每个阶段 0 传输件只含本作业原生输出与 phase0.json，绑定 run/attempt、job、SHA、版本
  和逐文件摘要；Apple 链接另保存相对目标。传输件不是正式三件套或 Hosted 包。
- 阶段 1 的唯一候选、唯一审计与 Hosted 归档，阶段 2 从同一个包进行公开消费，仍待接线。
  本步不改旧 Release 块；它不能被当作已完成新五宿主发布合同。

最终 Release 目标仍为：复核指定 CI 的 workflow、显示标题、产品 `citizensdk`、目标 `sdk`、成功状态和
  准确 `source_sha`，不读取、下载或比较 CI 资产；随后在隔离快照中重新执行依赖检查、测试、
  原生构建、候选生成、反向验证与 Hosted dry-run，并创建正式 GitHub Release。孤立 Tag
  清理、主发布路径和响应中断恢复三处都必须核验版本 Tag 精确锚定该成功 CI 的 `source_sha`。

CI 与 Release 都使用确定性候选算法，但 Release 的成立条件是来源绑定、独立重建与完整
验证，不宣称不同 Runner、不同 run 的压缩包在所有环境下必然逐字节相同。

工具来源和准备属于既有中央 dependencies.json / dependencies.mjs；SDK 源码不依赖 TATA。
Flutter 固定 3.44.4 官方提交，Android 明确选 NDK 28.2.13676358、Gradle 8.14、CMake 3.22.1；
后者由 sdkmanager 维护安装元数据，并将安装文件与已验 SHA256 的官方归档逐字节比较。
Windows 初始化 runner 已装 MSVC，保留 /MD。Linux 使用固定官方 Debian rootfs、签名 APT
快照及 CMake 3.31.6；系统包版本留在本作业记录中，不把 Ubuntu 24.04 的 GLIBC 2.39 链入 SDK。
Debian 11 已结束常规 LTS，此处仅作隔离构建基线，不是新增受支持生产系统或取消后续漏洞审计。

Linux 构建容器断网、非 root、只读根、移除全部 capabilities、no-new-privileges；不挂载
Docker socket、用户钱包或宿主 HOME，不注入令牌。固定 Moby 模板保留原拒绝项，仅增加
AppArmor userns 和 seccomp 准确 unshare(CLONE_NEWUSER|CLONE_NEWNET) 规则。
按 run/attempt/平台具名加载并核对标签后清理，不关闭宿主全局策略、不用 privileged/unconfined。
策略的实际加载尚待用户确认；当前仅验证生成合同，未进行 Docker/AppArmor 或平台运行验收。

五宿主各用独立统一 CI 缓存身份；仅 cargo-home、work/cargo、dart-pub 三项进入成功缓存，
保存前删除最终运行库。原件由中央对象库管理；安装树、测试金库、消费者、证据和候选不缓存。

两条流程的测试命令合同相同：根包一次发现并执行全部根测试和已经迁入的 smoldot 测试，
不把历史的 230 项与 51 项固定成两套数量门禁，并以 `flutter test --timeout=2m` 统一执行；
第 2 步隔离副本实际执行结果为 288/288。外层两分钟超时必须长于来源测试内部的 30 秒活链
订阅窗口。Android 在临时 Flutter 宿主中执行 Gradle
`:citizen_sdk:testDebugUnitTest`；Apple 必须启动 iOS 模拟器变体 runtime 执行 XCTest，并验证
iOS 设备变体、iOS 模拟器变体与 macOS 的 XCFramework/Swift/Flutter 闭集；三个 slice 的
机器架构元数据均须为 `arm64`。
平台测试必须实际启动测试运行器并取得成功终态，不能用 APK 构建、framework 链接、test
discovery 或报告文件存在来代替。本轮本机 Android AAR 构建通过，Apple 单一 XCFramework
只含 iOS 设备与模拟器变体及 macOS 三个 Apple `arm64` machine slice 并构建通过；iOS 的
两组测试 bundle 已编译，但本机没有 Simulator runtime，所以 iOS XCTest
仅记录编译门禁。macOS 已运行
Core 50 项和 Flutter adapter 22 项 XCTest，0 失败、1 项真机硬件用例跳过；最终
normal/supervisor smoke 通过。正式 CI 仍必须在安装了 Simulator runtime 的 runner 上实际
执行 iOS XCTest。

同一真实 Flutter consumer 已完成 Android release APK（ABI `arm64-v8a`）、iOS device Release
no-codesign、iOS 模拟器变体（Rust target `aarch64-apple-ios-sim`）编译和 macOS Release 构建。它们证明当前
Flutter/Dart、插件与原生投影能够链接成正式配置产物，不代表移动真机或 Simulator runtime
已执行。Flutter 对插件 Swift Package Manager 目录的未来识别警告，以及 Android built-in
Kotlin 迁移提示，留到第 9 步 Hosted/Flutter 集成统一处理，不扩展第 6 步。

同一本机闭集还验证 Hosted 17 个 Dart 文件分析 0 问题、完整 Dart 316/316
（`--timeout=2m`）、根 Rust 285/285 加 compile-fail 文档测试 1/1、Clippy/格式，以及
Android 原生 Kotlin/Java 单元测试 Gradle 17 个 task 全部成功。

## 正式候选格式

`scripts/release.mjs` 从只读源码快照和外部原生产物构造唯一规范候选与 gzip/tar。GitHub
归档内包含完整 SDK 源码、测试、文档、锁文件、Android 原生投影、Apple XCFramework 与 Linux
双平台合并安装投影、Windows 安装投影，并包含
`citizensdk-release.json`；外层 `SHA256SUMS` 不进入 tgz，避免对 tgz 自身形成循环哈希。

GitHub Release 三项资产固定为：

```text
citizensdk.tgz
citizensdk-release.json
SHA256SUMS
```

`citizensdk-release.json` 固定产品、包名、版本、40 位提交 SHA；当前候选合同登记 Android、
iOS、macOS、LinuxARM、LinuxAMD 与 Windows。iOS 设备与模拟器只是同一平台内的技术变体。manifest 同时登记
归档载荷逐文件 SHA-256。`SHA256SUMS` 精确覆盖外层 manifest 与 tgz。反向验证会重建规范
tar/gzip 字节并逐字节比较归档，拒绝符号链接、路径穿越、未登记文件和常见私钥材料。
其中“拒绝符号链接”唯一例外是上文标准 macOS framework 的精确五个内部相对链接；归档必须
保留其链接身份与目标，不能把它们展开为重复文件。除此之外的任何符号链接仍一律拒绝。

## Hosted Package 与分发边界

GitHub Release 三件套继续作为来源审计、校验和离线留档。Hosted Package 不重新装配 SDK：
官方 Dart 发布工具读取已经注入 Android `arm64-v8a` 产品双库/AAR、Apple `arm64` machine
XCFramework、Linux 双平台安装投影与 Windows 安装投影，并通过反向校验的同一
候选的逐字节临时副本；副本只隔离 Dart 生成的 `.dart_tool`，不是第二份发布候选。根
`.pubignore` 排除完整 Rust 源码、测试、脚本、审计文档、Cargo/Dart
锁文件以及 GitHub 外层 manifest/checksums，只保留根 pubspec、运行时 Dart/Flutter、平台插件、
`assets/README.md` 与 `assets/citizenchain` 四文件链资产闭集、Android/Apple/Linux/Windows 原生投影、README、
CHANGELOG、第三方声明与全部适用许可证。GitHub 候选中的 `android/citizensdk.aar` 不进入
Hosted 包；Hosted Android 只保留根插件、共享 Kotlin 生产 facade 和同一双 SO，不保留 native
测试、C++、Gradle/AAR 构建输入。即使 dry-run 副本已经执行过 Dart、Flutter 或平台
工具，`.dart_tool`、`build`、`target` 与 `.gradle` 生成树也必须全部过滤。统一 CI 和 Release 的目标合同均执行
`dart pub publish --dry-run`，任何缺失文件、不允许的依赖源或官方校验问题都会失败关闭。

Hosted 的 Dart 运行时闭包精确为 18 个文件：`lib/citizen_sdk.dart`、`lib/src/api`
七个 Dart 文件、`lib/src/crypto/account_codec.dart`、`lib/src/models` 五个 Dart 文件，以及
`lib/src/platform` 下 codec、sessions、platform contract 和 Flutter platform 四个文件。运行依赖只有
Flutter SDK 与 `polkadart_keyring`；legacy/差分依赖是 dev-only，不进入 Hosted 运行时。

源码中的 `pubspec.yaml`、`android/build.gradle`、`darwin/citizen_sdk.podspec`、
`linux/CMakeLists.txt` 与 `windows/CMakeLists.txt` 已统一冻结为 `1.0.0`。发布器要求五者、请求软件版本及候选 manifest
完全一致；版本升级必须先形成新的
源码提交，不能只向 Release 输入另一个版本。本步骤不执行 Hosted 上传，在首次发布完成前
不得宣称已经可由 `citizen_sdk: ^1.0.0` 获取。正式发布由 TataConsole 的 SDK 发布按钮触发；
不接任何产品下载指针。Android、iOS、macOS、Linux 与 Windows 源码投影均使用同一
产品 ABI。此前已完成 Android AAR、Apple 单一 XCFramework、本机 Apple 编译、macOS XCTest
和最终 smoke；本机无
Simulator runtime 和真实 Apple 移动设备，因此不声称 iOS XCTest 已运行或真机硬件金库
已验收。当前 TataConsole Flow 已接阶段 0 原生入口、完整候选闭集汇总、同包消费与正式发布阶段，
但尚未运行的远程 CI、正式 Release、Hosted 上传或 Git 不能记为通过。

Linux 第 7.1 步源码已进入 GitHub 审计候选的受控源闭集，第 7.2 步已完成 Flutter adapter 源码，
第 7.4 步已把 `.pubignore`、pubspec、默认公开入口、manifest 与候选投影原子同步。正式分发
须经同产品同版本的统一 GitHub CI/Release 完成 LinuxARM/LinuxAMD
真实构建、测试和 ELF/ABI 反向校验，不能先发布声明 Linux、实际缺少运行库的 Dart 包。当前 macOS
开发验收与此后的 Linux 平台正式分发门禁分别记录，不将本机通过写成 Linux 已运行或正式发布。

## Hosted 本地归档与解包验真（第 9.1 步）

仍使用唯一 `scripts/release.mjs`，不更改上述审计三件套的确定性算法。以下参数必须是
已经准备好的绝对路径；输出必须不存在并位于中央产品容器的严格子路径，不能指向永久根。

```text
node scripts/release.mjs --hosted <已验真候选> --archive <citizensdk.tgz> \
  --output <全新工作子目录> --dart <Dart SDK/bin/dart> \
  --flutter <Flutter SDK> --pub-cache <中央隔离缓存> --expected-git-sha <40位SHA>

node scripts/release.mjs --verify-hosted <已验真候选> --archive <citizensdk.tgz> \
  --hosted-archive <citizen_sdk-1.0.0.tar.gz> --output <全新解包子目录> \
  --expected-git-sha <40位SHA>
```

本地工具固定 Dart **3.12.2**；同时检查版本文件和实际 `--version`，直接调用 Dart 二进制，
不调用 Flutter 包装脚本。先单独 `pub publish --dry-run`，必须明确零 warnings；再单独
`pub publish --to-archive=...`。后者是该固定版本的本地分支，参数不开放给调用者，不能
替换为上传、force 或 skip-validation。成功工作目录包含逐字节来源副本 `input/`、
本轮 `tmp/`、`pub.log`、单个 `citizen_sdk-1.0.0.tar.gz` 和验真解包 `package/`。

子进程仅获得 Dart bin PATH、指定 Flutter/隔离 Pub cache、中央临时目录和关闭遥测配置；
不继承用户 HOME、XDG、APPDATA 或令牌环境。缓存必须与输入/工具/输出双向不重叠且预先
存在，不能复用用户发布凭据目录。官方验证可能只读访问 pub.dev，故不宣称完全离线。
第 10.4 步把归档工具监督固定为 POSIX 进程组；正式 Hosted 归档仍由既定 macOS 作业
统一生成。Windows 不运行该归档生产命令，调用会在创建输出或启动工具前明确失败；
Windows SDK、原生/Flutter 绑定、同步 `--verify-hosted` 和安装消费验收不受此限制。

两个既有中央 SDK 动作入口以 `citizensdk-release` 子命令原样传递上面的 Hosted 参数，
只调用同一 checkout 中的 SDK 发布器。拒绝重复/未知/混用参数；全部 Hosted 路径须为
无链接、无穿越的准确绝对路径，与 SDK 源树双向分离。GitHub 的 expected SHA 必须
与冻结 `GMB_SOURCE_SHA` 一致；参数层不创建输出，也不新增上传入口。

程序调用 `buildCitizenSdkHosted({ ..., signal })` 使用标准 `AbortSignal`；CLI 的
SIGINT/SIGTERM 也转交该信号。每条 Dart 命令有 120 秒期限和 4 MiB 输出上限；
取消/超时/输出或管道失败先向准确工具组发送 TERM，5 秒后仍存活才升级 KILL，
10 秒内无法确认退出则返回带 `preserveHostedOutput` 的失败并保留准确工作目录。
监督同时检查 `exit` 和 `close`，不能把父进程退出当成管道后代退出；退出后 200 ms
仍未完成关闭的工具被记作失败并收尾。只有管道关闭且已知工具组消失后才允许清理
本次新建且身份未变的目录；预取消不启动命令，阶段间取消不进入下一条命令。

外层动作的十分钟总期限和 SIGINT/SIGTERM 只向准确发布器 PID 发 TERM，最多再等
30 秒，不能先强杀发布器而越过内部 Dart 组监督。无法确认发布器退出时保留现场、
报错并断开管道引用，不删目录、不宣称所有进程已退出。取消后即使子进程返回 0
仍记失败；CLI 保留 130/143，总期限保留 124。不可捕获的 SIGKILL 或主动逃逸进程组
不属于可保证优雅收尾的范围，不能据此自动清理现场。

取消合同使用 [Node AbortController](https://nodejs.org/api/globals.html#class-abortcontroller)
与 [子进程独立进程组](https://nodejs.org/api/child_process.html#optionsdetached)；不维护第二套工具调度器。
本步只用有期限的 Node 伪工具和受控时钟验证这些失败边界，不把夹具结果计作官方 Pub、
实际平台安装或远程 CI 已通过。

完整预期由已验真候选和现有 `.pubignore` 推导，包括显式目录、法律材料及全部平台运行
输入。枚举实现按官方 `**/` 可匹配零层、目录末尾 `/*` 不匹配空子项的语义校正，过滤规则
本身没有更改。原候选只准入既有五个 Apple 相对链接；Hosted 将其目标展开为普通文件，
逐项验证而不要求归档编码或 mtime 相同。其余链接仍拒绝。

解包前限定普通文件压缩输入不超过 **100 MiB**，展开 tar 不超过 **256 MiB**，条目与含隐式
父项的节点均不超过 **16384**，UTF-8 路径不超过 **4096 bytes**。解析完整单 gzip member、
CRC/ISIZE、tar checksum/padding/终止块和官方 GNU 长名；拒绝穿越、重复/大小写/NFC 冲突、
软硬链接、设备/PAX 等不支持类型、追加成员和垃圾尾部。全部内容符合预期后才创建全新输出，
写后再次校验完整闭集及原审计候选；失败仅清理自己新建且身份未变的目录。这些是本地安全
上限，不保证 Hosted 服务端接受同样大小的包。

本步实际官方 Pub 往返只使用明确的跨平台格式夹具，没有原生重编、真实安装消费或发布。
最终全平台产物体积、macOS 实际消费以及其余平台运行证据仍待后续步骤；不能删平台、拆包
或降低安全门禁以规避届时发现的限制。官方实现依据见
[固定 Pub 归档分支](https://raw.githubusercontent.com/dart-lang/pub/74408212b5348003381bc63f3b59274aaa23cfa3/lib/src/command/lish.dart)
与 [Dart 发布说明](https://dart.dev/tools/pub/publishing)。

## macOS Hosted 安装消费（第 9.2 步实现；实际运行转第 10 步验收）

此验收继续使用唯一 `build-native.sh` 和 `release.mjs`。macOS Flutter Release 测试
必须消费由审计候选及官方 Hosted 归档共同验真的解包包，不能用来源目录、内部平台注入
或源码 `@testable` 测试替代。测试的真实 Apple 件必须来自本轮同版编译；其余平台若仍
使用格式件，整个候选必须明确标为本地测试输入，不可发布。

新增 `darwin/Tests/citizen_sdk_flutter_consumer.dart` 只调用公开 CitizenSdk，覆盖
空钱包、能力、未就绪错误、启停事件和关闭/重开。临时宿主在注册插件前核对 Foundation
真实 Application Support 路径，系统 sandbox 禁止工作区外写入和访问用户 SDK 状态；
隔离不成立就拒绝运行，不改 SDK 私有存储入口，不改 HOME 或用户系统配置。
macOS 不支持重复安装 sandbox；工具监督器分别为每个离线构建命令安装单层策略，只允许
写入本轮临时宿主、Flutter 与 Pub 副本，Git 元数据只读；最终消费者单独使用运行策略。
真实工具失败时保留准确独占目录和诊断日志，复查原因及占用后才清理，禁止外层提前删掉证据。

保持官方 Flutter backend 和默认插件注册，禁止为验收修改 SDK pubspec、podspec 或
Package.swift。Flutter 的 Xcode backend 会再次调用 bin/dart、bin/flutter，其官方启动器
使用 Git 查询工具版本；任何新增执行权限必须经用户明确确认，不能悄悄修改官方脚本绕过。
当前准确执行记录和待验证项目统一见中央任务卡第 35 节，不提前宣称安装成功。
本机已到达标准工程创建、离线依赖安装及插件发现/注册检查；Xcode 解析 Swift Package
依赖时仍报告权限错误。独立 Foundation 路径诊断表明，仅设置本轮 TMPDIR 并不保证其
临时目录离开系统 `/var`；没有据此放行中央目录外写入、关闭 SwiftPM 或修改 SDK 声明。
尚未得到最终 Flutter Release app，也未执行其公开消费者，不能记为安装运行通过。
用户已确认本机保留已通过的 Apple 原生编译验收，并将这项 Flutter macOS 实际安装运行
移交第 10 步 GitHub 统一 CI。该调整只划分验收执行位置，不取消实际消费者测试，不降低
来源、状态隔离或失败门禁；第 9.2 步本机开发范围可收尾，但不代表远程验收或发布完成。

第 10.3 步的目录预检由同一构建器按执行环境选择：本机固定
`/Users/rhett/TATA/tataconsole/work/gmb/citizensdk`；当
`GITHUB_ACTIONS=true` 时固定 `RUNNER_TEMP/citizensdk`，必须提供 GitHub 官方
`RUNNER_TEMP`、`GITHUB_WORKSPACE`，且 SDK 来源是该 checkout 的严格子目录。
受控根与 checkout/SDK 源树在任一方向都不得交叠。根、输入目录和工作/输出容器须预先存在，
采用绝对规范路径，不含链接、穿越或路径别名；输入和工作/输出不能等于受控根，不能等值
或祖先交叠。APFS 的大小写别名另以 Node 原生真实路径检查，不能只比较 Bash 路径文本；
固定受控根采用系统磁盘身份，其下的输入必须无别名。候选/归档保持只读，Flutter/Pub
副本及消费者的可写范围仍由原沙箱限定。
预检不创建目录，失败不尝试另一个根。真实消费测试也执行这个根预检，并向根预检、
Hosted 归档监督器及原生构建器原样传递上述 Runner 环境，不新增消费者或发布器。
归档监督器缺少该环境也会误用本机路径门禁，不能只接最后的 Flutter 消费调用。
该项只验证目录合同；远程 Xcode/SwiftPM 和最终公开消费者仍须在统一 CI 实际运行，
不能由本机路径测试推导通过。

## Windows 原生安装与候选投影

唯一 `build-native.sh Windows` 组合原有 `native/ffi` 与 Win32 Host；最低 Windows 11，
MSVC 官方目标 `x86_64-pc-windows-msvc`，公开名称只有 Windows。安装的 bin/Windows
保存 Core/Host DLL，lib/Windows 保存 import libraries 与 CMake，头和资产用公共布局。
第 8.4 步在同一 `release.mjs` 接纳 21 项 Windows 安装件；第4步加入 QR 图像头后当前为 22 项，继续纳入唯一候选平台集合。
七个 Host 头与源码重叠，必须逐字节一致，只注入其余十四项；不覆盖不同内容或接受多余
文件。版本、PE/COFF、完整导出、导入依赖、CMake 引用和链资产一起验证。二进制结构
校验不是来源 commit、静态依赖许可证或真实运行证明，证据仍须统一 CI/Release 闭合。

第 8.2 步新增的 Windows Flutter adapter 在第 8.4 步纳入正式运行投影。Flutter
构建分支只接受同版安装包的 `CitizenSDK::Core`、`CitizenSDK::Host`，校验 package config、
所有已声明配置的 DLL/import library、公开 include 与传递依赖；不回退搜索另一版本，
不重新编译 Host/Core。插件只捆绑这两个已安装 DLL，使用官方 Flutter wrapper。
源树公开头为八个，其中 `citizen_sdk_plugin.h` 仅用于 Flutter 注册；纯原生安装仍为七个头。
宿主在 generated_plugins.cmake 之前显式设置 `CITIZENSDK_APPLICATION_ID`；其合同见
WINDOWS_PLATFORM.md。`.pubignore` 精确保留 34 项 Windows 运行输入（22 安装件 + 12
插件输入），排除 Host 私有源码和测试；未注入源码的可见集合是 19 项（七头 + 十二插件
输入），源码门禁仍禁止原生产物。MSVC 运行时由宿主部署环境提供，不额外引入未登记 DLL。
默认 `CitizenSdk` 与 pubspec 的官方 Windows 注册一起开放；这不是已执行 Hosted 上传。

第 8.3 步在同一原生构建器补齐 Windows 安装消费顺序：先运行原有 14 项原生测试，安装到
本次 work_dir/Windows/install，反向核对精确 21 文件与 install_manifest、来源字节、版本、
PE 及完整符号，再构建和运行仅消费公开安装件的 C11/C++17 程序。独立消费者不重编
Host/Core，不通过系统 PATH 接受另一份 DLL，且不触发钱包 UI/TPM 或链上交易。
第 8.4 步在此基础上使用同版 SDK 安装投影生成官方 Flutter 宿主，由原始 SDK pubspec
自动注册插件；构建并运行六项 adapter CTest 与真实 Release Flutter 消费者，不改写 SDK
副本的注册或注入私有通道。全部成功才同卷导出到全新 output_dir/Windows；已有目标或
跨卷拒绝，不先覆盖成功输出。实际 Windows 执行仍留统一 GitHub，当前只完成源码合同。
