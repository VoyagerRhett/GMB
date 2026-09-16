# CitizenSDK QR image

本目录是 CitizenSDK 五平台唯一二维码图像实现。平台只把相机或图片转换成 8 位亮度
平面；识别和生成统一进入本包装及固定 ZXing-C++ 3.1.1，不允许接入第二识别器或回退。

构建必须显式传入官方完整 Release 解包目录 `CITIZENSDK_ZXING_SOURCE_DIR`。上游源不复制
进GMB、不修改；版本和归档摘要由CitizenSDK依赖锁固定。包装仅接受QR Code Model 2，
拒绝多码、无效 UTF-8、超大图像和超容量文本，并把 C++ 异常收敛为稳定 C 状态码。
