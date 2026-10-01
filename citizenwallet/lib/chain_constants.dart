/// CitizenChain 链级常量。
///
/// 所有与链相关的固定参数统一在此维护，
/// 避免散落在多个文件中导致升级遗漏。
class ChainConstants {
  const ChainConstants._();

  /// SS58 地址前缀（CitizenChain 注册编号）。
  static const int ss58Prefix = 2027;

  /// 2026-08-07 冻结并已部署的唯一正式创世哈希；Runtime 升级不会改变该值。
  static const String genesisHash =
      '0x18847a5dfd263272f2e7727836fe6582f8c4463ff48609df7b96d5e4d9dd24dd';

  /// 当前钱包支持的 Substrate `transaction_version`。
  ///
  /// `spec_version` 会随 Runtime 业务升级而变化，钱包只解析展示；只有交易编码格式
  /// 变化时才提高 `transaction_version`，届时旧钱包必须拒签并升级。
  static const int transactionVersion = 0;
}
