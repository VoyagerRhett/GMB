# Generic QR_V1 external signer

本目录仅通过 `CitizenSigning.signQrRequest` 和 `CitizenQr.parse` 实现独立签名端。它不导入、不调用也不复制
CitizenWallet 产品代码；测试密钥行为由测试替身提供。
