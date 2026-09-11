import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';

/// CitizenApp-owned transfer draft. This type must never move into SDK code.
final class CitizenAppTransferDraft {
  CitizenAppTransferDraft({
    required Uint8List destination,
    required this.amountFen,
    required this.remark,
  }) : destination = Uint8List.fromList(destination).asUnmodifiableView() {
    if (this.destination.length != 32) {
      throw ArgumentError.value(
        this.destination.length,
        'destination',
        'must contain 32 bytes',
      );
    }
    if (amountFen <= BigInt.zero || amountFen >= (BigInt.one << 128)) {
      throw ArgumentError.value(
        amountFen,
        'amountFen',
        'must fit positive u128',
      );
    }
    final remarkBytes = utf8.encode(remark);
    if (remarkBytes.length > 63) {
      throw ArgumentError.value(
        remarkBytes.length,
        'remark',
        'must contain at most 63 UTF-8 bytes in this fixture',
      );
    }
  }

  final Uint8List destination;
  final BigInt amountFen;
  final String remark;
}

/// CitizenApp-owned event projection used only after the App decodes chain bytes.
final class CitizenAppTransferEvent {
  CitizenAppTransferEvent({
    required Uint8List destination,
    required this.amountFen,
    required this.remark,
  }) : destination = Uint8List.fromList(destination).asUnmodifiableView();

  final Uint8List destination;
  final BigInt amountFen;
  final String remark;
}

/// App-side adapter: business encoding stays here and SDK sees only opaque bytes.
final class CitizenAppFixture {
  const CitizenAppFixture({
    required this.chain,
    required this.transactions,
    required this.history,
  });

  final CitizenChain chain;
  final CitizenTransactions transactions;
  final CitizenHistory history;

  Future<CitizenPreparedTransaction> prepareTransfer({
    required Uint8List sourceAccountId,
    required CitizenAppTransferDraft draft,
  }) => transactions.prepareTransaction(
    Uint8List.fromList(sourceAccountId),
    encodeTransferRuntimeCall(draft),
  );

  Future<Uint8List?> readTransferIndex({
    required CitizenBlockRef finalizedBlock,
    required Uint8List accountId,
  }) => chain.getStorage(finalizedBlock, transferStorageKey(accountId));

  Future<CitizenTransactionHistoryPage> readSdkExecutionFacts() =>
      history.getTransactionHistory();

  /// App-owned RuntimeCall encoding: pallet/call and all business fields remain
  /// outside CitizenSDK.
  static Uint8List encodeTransferRuntimeCall(CitizenAppTransferDraft draft) {
    final remark = utf8.encode(draft.remark);
    return Uint8List.fromList(<int>[
      41,
      0,
      ...draft.destination,
      ..._encodeUnsigned128(draft.amountFen),
      remark.length << 2,
      ...remark,
    ]);
  }

  /// App-owned storage key; SDK only verifies the supplied bytes against a block.
  static Uint8List transferStorageKey(Uint8List accountId) {
    if (accountId.length != 32) {
      throw ArgumentError.value(
        accountId.length,
        'accountId',
        'must be 32 bytes',
      );
    }
    return Uint8List.fromList(<int>[
      ...utf8.encode('CitizenApp/transfer-index/'),
      ...accountId,
    ]);
  }

  /// Minimal App-side event decoder used to prove that SDK history remains a
  /// product-independent execution log.
  static CitizenAppTransferEvent decodeTransferEvent(Uint8List bytes) {
    const fixedLength = 32 + 16 + 1;
    if (bytes.length < fixedLength) {
      throw const FormatException('transfer event is truncated');
    }
    final destination = Uint8List.sublistView(bytes, 0, 32);
    final amount = _decodeUnsigned128(bytes, 32);
    final compactLength = bytes[48];
    if ((compactLength & 3) != 0) {
      throw const FormatException(
        'fixture accepts only single-byte SCALE length',
      );
    }
    final remarkLength = compactLength >> 2;
    if (bytes.length != fixedLength + remarkLength) {
      throw const FormatException('transfer event length is inconsistent');
    }
    return CitizenAppTransferEvent(
      destination: destination,
      amountFen: amount,
      remark: utf8.decode(bytes.sublist(49)),
    );
  }
}

List<int> _encodeUnsigned128(BigInt value) {
  var remaining = value;
  return List<int>.generate(16, (_) {
    final byte = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
    return byte;
  }, growable: false);
}

BigInt _decodeUnsigned128(Uint8List bytes, int offset) {
  var value = BigInt.zero;
  for (var index = 15; index >= 0; index -= 1) {
    value = (value << 8) | BigInt.from(bytes[offset + index]);
  }
  return value;
}
