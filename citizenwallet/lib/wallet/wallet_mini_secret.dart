import 'dart:typed_data';

import 'package:substrate_bip39/substrate_bip39.dart';

import 'wallet_password.dart';

/// Substrate BIP-39 助记词派生 master [MiniSecretKey] 的物理唯一真源。
///
/// 两款移动产品只允许通过本类执行 `mnemonic + password → MiniSecretKey`。助记词按
/// BIP-39 English 解析为 entropy，password 先经过 [WalletPassword.parse] 的统一校验
/// 与 NFKD，再交给固定版本的 `substrate_bip39`。返回值是可擦除的 32 字节缓冲，调用方
/// 必须在 `finally` 中调用 [clear]。
final class WalletMiniSecret {
  const WalletMiniSecret._();

  /// 从标准 English BIP-39 助记词派生 master mini-secret。
  static Future<Uint8List> fromMnemonic(
    String mnemonic, {
    String password = '',
  }) async {
    final normalizedPassword = WalletPassword.parse(password);
    final entropy = Uint8List.fromList(
      Mnemonic.fromSentence(
        mnemonic,
        Language.english,
      ).entropy,
    );
    List<int>? derived;
    try {
      derived = await CryptoScheme.miniSecretFromEntropy(
        entropy,
        password: normalizedPassword.value,
      );
      if (derived.length != 32) {
        throw StateError('Substrate MiniSecretKey 必须为 32 字节');
      }
      return Uint8List.fromList(derived);
    } finally {
      if (derived != null) clear(derived);
      clear(entropy);
    }
  }

  /// Substrate 官方数字硬派生 junction 的 32 字节 [ChainCode]。
  ///
  /// 必须复用 `substrate_bip39` 的 [DeriveJunction]，禁止两款 App 各自重写 SCALE
  /// 编码。`//index` 在 SURI 中对应传给 [DeriveJunction.fromStr] 的 `/index`。
  static Uint8List hardJunctionChainCode(int index) {
    if (index < 0) {
      throw RangeError.value(index, 'index', '派生序号不能为负');
    }
    final junction = DeriveJunction.fromStr('/$index');
    if (!junction.isHard || junction.junctionId.length != 32) {
      throw StateError('Substrate 硬派生 ChainCode 必须为 32 字节');
    }
    return Uint8List.fromList(junction.junctionId);
  }

  /// 覆写可变字节缓冲；所有派生调用方统一使用，避免各端重复清理实现。
  static void clear(List<int> bytes) {
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = 0;
    }
  }
}
