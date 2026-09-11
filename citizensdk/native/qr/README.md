# CitizenSDK QR

本 crate 是 CitizenSDK 内唯一的 `QR_V1` 协议与扫码签名会话实现。它只处理有界公开载荷、
请求关联、过期、一次性消费和公开验签材料，不读取相机、不持有私钥，也不实现产品业务。

`test/consumers/external_signer/` 只通过根公开 `CitizenSigning` 与 `CitizenQr` 组合通用签名端，
证明本 crate 不依赖任何外部钱包产品。历史 kind 数值空洞保持拒绝，不存在其它 QR 协议版本。

二维码像素由相邻的 `native/qr-image` 统一交给 ZXing-C++；平台绑定只能提供像素、权限、
窗口和用户确认。账户秘密仍由现有 signing 与设备金库路径掌管。
