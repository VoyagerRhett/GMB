# 多消费者通用性验收

本目录只通过 `package:citizen_sdk/citizen_sdk.dart` 使用正式 Dart 公开面，不允许导入
`lib/src`、调用测试符号或读取 CitizenApp/CitizenWallet 源码。

- `reference/`：没有产品业务语义的最小消费者，贯穿钱包、签名、QR_V1、链读取、交易与历史。
- `citizenapp_fixture/`：CitizenApp 形状的业务字节构造示例；业务字段和编码只能留在该目录。
- `third_party_fixture/`：与 CitizenApp 无关的第三方业务示例，证明 SDK 不按产品登记业务模型。
- `external_signer/`：只消费通用 QR_V1 签名公开面的测试签名器，不依赖 CitizenWallet。

这些文件是发布合同夹具，不是可复制进 SDK 生产目录的业务实现。测试生成物仍只能写入仓库外
TataConsole 缓存。
