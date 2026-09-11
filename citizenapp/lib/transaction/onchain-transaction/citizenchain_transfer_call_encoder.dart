import 'dart:typed_data';

import 'package:citizenapp/rpc/pallet_registry.dart';
import 'package:polkadart/scale_codec.dart' show ByteOutput, CompactBigIntCodec;

/// CitizenApp-owned encoder for `OnchainTransaction.transfer_with_remark`.
///
/// Destination, amount and remark are application business fields. The generic
/// blockchain SDK receives only the returned opaque RuntimeCall bytes and must
/// never duplicate or interpret this schema.
final class CitizenChainTransferCallEncoder {
  const CitizenChainTransferCallEncoder();

  /// Runtime `MaxTransferRemarkLen`, measured in raw UTF-8 bytes.
  static const int maxRemarkBytes = 99;

  Uint8List encode({
    required Uint8List destinationAccountId,
    required BigInt amountFen,
    required Uint8List remarkBytes,
  }) {
    if (destinationAccountId.length != 32) {
      throw ArgumentError.value(
        destinationAccountId.length,
        'destinationAccountId',
        'CitizenChain AccountId 必须正好是 32 字节',
      );
    }
    if (amountFen <= BigInt.zero) {
      throw ArgumentError.value(amountFen, 'amountFen', '转账金额必须大于 0 分');
    }
    if (remarkBytes.length > maxRemarkBytes) {
      throw ArgumentError.value(
        remarkBytes.length,
        'remarkBytes',
        '转账备注不能超过 $maxRemarkBytes 个 UTF-8 字节',
      );
    }

    final output = ByteOutput()
      ..pushByte(PalletRegistry.onchainTransactionPallet)
      ..pushByte(PalletRegistry.transferWithRemarkCall)
      ..write(destinationAccountId)
      ..write(_u128LittleEndian(amountFen))
      ..write(CompactBigIntCodec.codec.encode(BigInt.from(remarkBytes.length)))
      ..write(remarkBytes);
    return output.toBytes();
  }

  Uint8List _u128LittleEndian(BigInt value) {
    final output = Uint8List(16);
    var remaining = value;
    for (var index = 0; index < output.length; index++) {
      output[index] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    if (remaining != BigInt.zero) {
      throw ArgumentError.value(value, 'amountFen', '金额超出 u128 范围');
    }
    return output;
  }
}
