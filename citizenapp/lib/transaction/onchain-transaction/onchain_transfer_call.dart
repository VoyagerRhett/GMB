import 'dart:convert';
import 'dart:typed_data';

import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'citizenchain_transfer_call_encoder.dart';

/// CitizenApp 普通转账的业务 RuntimeCall 编码与表单金额计算。
///
/// 本类只知道 `transfer_with_remark` 的业务字段，不读取链、不选 nonce、
/// 不签名也不构造 extrinsic；生成的 opaque bytes 直接交给 CitizenSDK。
abstract final class OnchainTransferCall {
  static const int maxTransferRemarkBytes =
      CitizenChainTransferCallEncoder.maxRemarkBytes;

  static Uint8List encode({
    required String destinationSs58Address,
    required double amountYuan,
    required String remark,
  }) {
    final remarkBytes = Uint8List.fromList(utf8.encode(remark));
    if (remarkBytes.length > maxTransferRemarkBytes) {
      throw const FormatException('转账备注超过链上长度上限');
    }
    final destinationAccountId = Keyring().decodeAddress(
      destinationSs58Address,
    );
    if (destinationAccountId.length != 32) {
      throw const FormatException('收款账户不是 32 字节 AccountId');
    }
    return const CitizenChainTransferCallEncoder().encode(
      destinationAccountId: destinationAccountId,
      amountFen: BigInt.from((amountYuan * 100).round()),
      remarkBytes: remarkBytes,
    );
  }

  /// 只用于交易确认页展示。真实费率、最低费用和 ED 由 SDK
  /// [CitizenFeeSnapshot] 读链，不使用本值作授权或可用余额真源。
  static double estimateTransferFeeYuan(double amountYuan) {
    const perbillParts = 1000000;
    const perbillDenominator = 1000000000;
    const minimumFeeFen = 10;
    final amountFen = BigInt.from((amountYuan * 100).round());
    final byRate = (amountFen * BigInt.from(perbillParts) +
            BigInt.from(perbillDenominator ~/ 2)) ~/
        BigInt.from(perbillDenominator);
    final feeFen = byRate < BigInt.from(minimumFeeFen)
        ? BigInt.from(minimumFeeFen)
        : byRate;
    return feeFen.toDouble() / 100;
  }
}
