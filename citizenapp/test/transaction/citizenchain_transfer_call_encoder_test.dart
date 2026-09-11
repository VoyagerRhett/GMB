import 'dart:typed_data';

import 'package:citizenapp/transaction/onchain-transaction/citizenchain_transfer_call_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const encoder = CitizenChainTransferCallEncoder();

  test('CitizenApp encodes destination amount and remark into opaque callData',
      () {
    final encoded = encoder.encode(
      destinationAccountId: Uint8List.fromList(List<int>.filled(32, 0x11)),
      amountFen: BigInt.from(0x1234),
      remarkBytes: Uint8List.fromList([0x61, 0x62]),
    );

    expect(encoded.take(2), [4, 0]);
    expect(encoded.sublist(2, 34), List<int>.filled(32, 0x11));
    expect(encoded[34], 0x34);
    expect(encoded[35], 0x12);
    expect(encoded.sublist(50), [0x08, 0x61, 0x62]);
  });

  test('encoder rejects invalid business fields before calling the SDK', () {
    expect(
      () => encoder.encode(
        destinationAccountId: Uint8List(31),
        amountFen: BigInt.one,
        remarkBytes: Uint8List(0),
      ),
      throwsArgumentError,
    );
    expect(
      () => encoder.encode(
        destinationAccountId: Uint8List(32),
        amountFen: BigInt.zero,
        remarkBytes: Uint8List(0),
      ),
      throwsArgumentError,
    );
    expect(
      () => encoder.encode(
        destinationAccountId: Uint8List(32),
        amountFen: BigInt.one,
        remarkBytes: Uint8List(100),
      ),
      throwsArgumentError,
    );
  });
}
