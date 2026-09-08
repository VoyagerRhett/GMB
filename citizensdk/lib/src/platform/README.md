# Flutter 平台投影

Android、iOS、macOS、LinuxARM/LinuxAMD 与 Windows 共用 `citizen/sdk/core/v1` MethodChannel 和
`citizen/sdk/events/v1` EventChannel。macOS 产品只称为 macOS；当前 Apple 工具链机器架构值为
`arm64`，不得拼入平台名。
iOS 与 macOS 在 `pubspec.yaml` 中都声明官方 `sharedDarwinSource: true`，由同一份 Apple
binding 实现协议；LinuxARM/LinuxAMD 共用官方 `linux` 注册，Windows 使用官方 `windows`
注册，两者的插件类型均为 `CitizenSdkPlugin`。
Dart 不为平台复制第二套 transport。

全部平台的 Flutter 边界完全相同：36 个方法只允许固定长度、固定位置的 List tuple，并逐层
校验长度、类型、session、request sequence、event sequence 和枚举闭集。协议不接受 Map、
任意 RPC、独立 signed extrinsic、原生 handle、助记词、密码、DEK、child secret 或私钥。
创建、导入和追加账户只触发 SDK-owned 原生安全流程；秘密始终留在 Rust、平台金库与 SDK 自有安全界面内。
`viewAccountPrivateKey` 紧接 `getWalletProfile`，采用原 session 外壳，字段仅 `[accountId]`，
成功字段只能为 `[]`；取消、认证失败与关联错误沿用同一错误合同，不增加秘密返回槽。
原生显示通知不是请求终态，必须清屏并等实际认证/回调排空，才能完成 Dart 调用。

`CitizenSdk.open(modules: ...)` 默认完整启用，唯一 open tuple 为 `[1, modules]`，不接受
省略模块的位置。模块闭集、依赖关系和编译支持由 Rust 在平台资源创建前统一校验。
钱包、签名、链、交易和历史分别通过 `sdk.wallet`、`sdk.signing`、`sdk.chain`、
`sdk.transactions`、`sdk.history`、`sdk.qr` 使用；完整 SDK 组合相同实现，不设第二套业务逻辑。
十个 QR 方法只将规范文本、公开字节和 8 位亮度图在边界上传输；协议逻辑在 Rust，
图像逻辑在同一 ZXing-C++ 3.1.1 窄包装，不进入平台专用扫码引擎。
`CitizenSigning.verify` 是无需 open 的静态入口，直接使用 transport，不读取事件流。
`verifySignature` 唯一请求为 `[1, accountId, signature, payload]`，唯一响应为 `[1, bool]`；
错误复用原 PlatformException 形态，session/sequence 均为 null。拒绝会话请求外壳，
不建立 session、事件订阅、钱包、金库或链，也不要求实例启用签名位。本地签名则必须启用签名模块，并经设备金库
使用已有账户秘密。未启用钱包时，不得因签名模块拥有金库而开放钱包管理界面。

两项 session 链查询直接投影同一 Core：`getGenesisHash` 无字段，响应字段为规范 hex32；
`getAccountBalances` 字段为账户列表，响应字段为既有余额 tuple 列表，允许空列表和重复，
数量上限为 1990。绑定验证响应数量、顺序、重复项与共同 finalized 块，不返回部分事实。

`CitizenSdkFlutterSession` 只协调 session、序列、事件和关闭，不实现链、钱包、签名或交易逻辑。
`FlutterCitizenSdkPlatform` 只是原生 facade 的公共 transport。`close` 必须等待原生
checkpoint、stop、结果释放与 destroy 完成；EventChannel cancel 不能替代关闭。平台实现不得
扩展方法闭集、改变 tuple 位置或以 Map 增加兼容旁路。

第 7.2 步 LinuxARM/LinuxAMD adapter 复用 Linux Host 和唯一 Core；第 7.4 步已原子纳入
`pubspec.yaml`、默认 `CitizenSdk.open()` 与同版本 Release 候选合同。尚未执行 Linux 编译或
CTest，真实平台验证留到后续统一 GitHub CI/Release，不把源码注册写成运行或正式发布成功。
它不增加 Linux 专用 Dart transport。Linux 字符串通过官方 StandardMessageCodec 扩展点
保留内嵌 NUL 的完整 UTF-8 字节，线上仍是标准字符串编码，不截断备注或新增 wire 类型。

Windows 原生 adapter 源码也遵守同一双通道和 36 方法，使用官方
StandardMethodCodec；身份、路径、HWND 由 Windows 原生层装配。第 8.4 步已同步接入
pubspec 官方注册、默认 `CitizenSdk.open()` 和同版候选/Hosted 运行投影；缺插件仍失败
关闭，WASM、Fuchsia 不开放。Windows 宿主须一次声明 `CITIZENSDK_APPLICATION_ID`，
公开 Dart API 不接收路径或秘密。Windows 实际编译、运行和正式分发仍待统一 GitHub
验收，不把默认入口已接入写成平台实测或 Hosted 已发布。

旧 `citizen/sdk/hardware_secretvault` byte-only channel、Dart
`HardwareBoundSeedStore`、`MobileCitizenSdkComponents` 与通用 secure-blob 装配已经删除。
Android、iOS、macOS、LinuxARM/LinuxAMD 与 Windows 的公开 Flutter 路径都只经产品 C ABI、平台 typed stores 和平台
`SecretVault`。Preferences 仓储、旧 Dart 链、钱包和交易实现已删除；原子性由正式
平台持久仓储与 Rust CAS 合同保证，不依赖 Dart isolate 内的互斥锁。
