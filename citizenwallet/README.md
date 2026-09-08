# 公民钱包

钱包所有 Dart 功能集中在 `lib/`，平台实现归入 `android/` 和 `ios/`，Rust 密码学只有一个 crate。钱包不依赖 CitizenApp 或 CitizenSDK。

## 目录

```text
citizenwallet/
├── lib/                 Dart 应用代码
│   ├── wallet/          钱包管理、派生、password
│   ├── security/        金库接口、应用锁、用途钥交付
│   ├── qr/scanner/      相机扫码适配
│   ├── qr/              二维码信封、载荷与生成表
│   ├── signer/          交易解码、确认字段与离线签名
│   ├── ui/              页面与组件
│   ├── isar/            数据模型与持久化
│   ├── chain/           离线链参数
│   ├── login/           登录二维码业务
│   └── util/            应用内工具
├── android/             Android 宿主、硬件金库与原生测试
├── ios/                 iOS 宿主、硬件金库与 Rust 链接配置
├── rust/
│   ├── src/lib.rs       八个 FFI 入口
│   ├── src/sr25519.rs   派生、签名和验签
│   └── src/account_crypto.rs  用途钥派生与加密交付
├── test/                Dart 测试和本地固定向量
├── resources/           唯一资源根：icons、android、ios
└── scripts/             控制台构建入口及生成工具
```

根目录只保留 README、Flutter/Cargo 所需配置及上述源码目录；不设本地 `packages/`、多 crate 层或第二份分析配置。包依赖统一由根 `pubspec.yaml` 和锁文件管理。

`CitizenWallet` 是公民体系的离线冷钱包。应用不声明网络权限，使用二维码接收
`QR_V1` 请求并离线签名；SS58 地址仅用于展示和边界输入输出，签名与授权使用
`AccountId`。

## 安全边界

- 助记词和 32 字节 master `MiniSecretKey` 只以可擦除字节数组进出
  `lib/security/hardware_secretvault.dart`；Secure Storage 只保存 Base64 硬件信封密文。
- Android 使用 StrongBox/TEE RSA-2048 OAEP KEK，每次解密由强生物识别
  `CryptoObject` 原子授权；iOS 使用 Secure Enclave P-256 ECIES，访问控制
  固定为 `biometryCurrentSet + privateKeyUsage`，不回退设备密码。
- 每只钱包使用独立硬件 KEK，AAD 同时绑定产品、`masterId`/`AccountId`
  与机密类型；跨产品、跨钱包、跨类型替换和密文篡改全部失败关闭。
- 创建、导入、查看根机密、删除和签名前强制使用指纹或面容认证，不回退设备密码。
- 创建、导入或删除失败时逐项尝试清理 master 密文、助记词密文和硬件
  KEK；全部清理并回读通过后才删除 Isar 事实行。
- 钱包可选 Substrate BIP-39 `password` 由 `lib/wallet/wallet_password.dart` 单源校验和
  派生；非空值为 6–30 位，不持久化。`substrate_bip39` 声明统一为
  `^0.7.0`，实际解析补丁版本由各应用 `pubspec.lock` 锁定。
- 链上签名必须严格匹配正式 `genesis_hash` 和支持的 `transaction_version`；
  `spec_version` 只解析展示，不要求 App 在每次 runtime 升级后同步升级。
- 助记词、私钥和签名响应二维码页面进入后及时启用引用计数式截屏/录屏保护，
  转入后台立即隐藏敏感内容。
- 普通扫码签名与登录扫码签名的请求 id 均在本地持久化原子占位；重复或已过期请求
  在生物识别和私钥调用前拒绝，认证或签名失败会释放占位供用户重试。
- 设置中的应用锁可配置独立 6 位 `duress_mode` 密码，且不得与普通应用锁密码相同。
  启动或重新锁定时单次输入该密码不会累计普通错误次数，第六位命中后先写持久 pending
  门闩，立即封锁、后台擦除并退出前台，全程不显示任何弹窗，也不存在等待或二次输入状态。
  擦除先删除并回读每只钱包的硬件 KEK，再删除
  WalletIsar、Secure Storage 与偏好；中断后下次启动只能继续擦除，完成后回到全新初始化状态。
- 普通应用锁 PIN 与公民统一使用随机盐及 100,000 次 PBKDF2-HMAC-SHA256，`duress_mode`
  PIN 使用独立随机盐及 10,000 次；派生在辅助 isolate 中执行，普通密码命中只执行一次，
  未命中后才识别防共匪密码。数字键盘按下即记录并把触觉反馈移出输入关键路径。

## 密钥关系

`助记词 → 32B 主种子 → //index 硬派生 → 账户私钥 → sr25519 公钥 / AccountId
→ SS58 展示地址`

应用内“设置 → 产品手册”提供对应的图形化说明。

## 构建与验证

本机构建通过 TataConsole 钱包 Android/iOS 入口执行。控制台生成当前平台的 Flutter、Gradle 和 Pods 配置，业务源码按文件只读引用。

- 正式本机工作目录：TataConsole `work/gmb/citizenwallet/<platform>/`。
- Flutter 状态和产物、Cargo target、平台缓存均写入当前中央任务目录；成功包由控制台归档。
- 宿主 FFI 从控制台注入的 `CARGO_TARGET_DIR/release` 加载，不查找源码下的 `rust/target`。
- 源码目录不运行裸 `flutter test`、`dart pub get` 或无目标目录的 `cargo build`；校验使用同一中央配置生成、源码写保护及任务回收机制。
- Android 金库测试位于 `android/app/src/test/`，随宿主 Release 单元测试执行；Flutter 测试位于 `test/`。

`.dart_tool`、`build`、`target`、IDE 状态和自动注册文件属于生成状态，不是业务源码。不得把清理源码缓存作为正常构建步骤。
