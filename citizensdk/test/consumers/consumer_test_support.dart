import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';

const String testAccountId =
    '0x0000000000000000000000000000000000000000000000000000000000000000';

final CitizenBlockRef testFinalizedBlock = CitizenBlockRef(
  hash: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  number: BigInt.one,
  finality: CitizenBlockFinality.finalized,
);

/// Keeps unexercised interface members fail-closed while allowing each test
/// double to implement only the public calls relevant to the consumer matrix.
abstract class StrictPublicPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'unexpected public SDK call: ${invocation.memberName}',
  );
}

final class RecordingChain extends StrictPublicPort implements CitizenChain {
  final List<Uint8List> storageKeys = <Uint8List>[];

  @override
  Future<CitizenBlockRef> getFinalizedHead() async => testFinalizedBlock;

  @override
  Future<Uint8List?> getStorage(CitizenBlockRef block, Uint8List key) async {
    if (block.hash != testFinalizedBlock.hash) {
      throw StateError('consumer used an unverified block');
    }
    storageKeys.add(Uint8List.fromList(key));
    return Uint8List.fromList(<int>[9, 8, 7]);
  }
}

final class RecordingWallet extends StrictPublicPort implements CitizenSdkWallet {
  @override
  Future<CitizenWalletState> getState() async => CitizenWalletState(
    revision: BigInt.from(3),
    hotProfile: null,
    accounts: const <CitizenWalletStateAccount>[],
  );
}

final class RecordingSigning extends StrictPublicPort
    implements CitizenSigning {
  RecordingSigning({this.mismatchedBinding = false});

  final bool mismatchedBinding;
  final List<CitizenSigningIntent> intents = <CitizenSigningIntent>[];

  @override
  Future<CitizenSigningOutcome> begin(CitizenSigningIntent intent) async {
    intents.add(intent);
    return CitizenSigningCompleted(
      accountId: intent.accountId,
      payloadHash: '0x${'11' * 32}',
      signature: Uint8List(64),
    );
  }

  @override
  Future<CitizenQrSigned> signQrRequest(String signRequest) async =>
      CitizenQrSigned(
        canonicalText: 'QR_V1 response',
        qrImage: CitizenQrImage(
          width: 2,
          height: 2,
          luminance: Uint8List.fromList(<int>[0, 255, 255, 0]),
        ),
        requestId: mismatchedBinding ? 'other-request' : 'request-1',
        signerAccountId: testAccountId,
        signature: Uint8List(64),
        signRequest: signRequest,
      );
}

final class RecordingQr extends StrictPublicPort implements CitizenQr {
  RecordingQr({this.mismatchedResponseSignature = false});

  final bool mismatchedResponseSignature;
  final List<Uint8List> reviewPayloads = <Uint8List>[];

  @override
  Future<String> createSignRequest({
    required int action,
    required String signerAccountId,
    required Uint8List reviewPayload,
    int ttlSeconds = 120,
  }) async {
    reviewPayloads.add(Uint8List.fromList(reviewPayload));
    return 'QR_V1 request';
  }

  @override
  Future<CitizenQrDocument> parse(String text) async {
    if (text == 'QR_V1 request') {
      return CitizenQrDocument(
        kind: CitizenQrKind.signRequest,
        canonicalText: text,
        requestId: 'request-1',
        expiresAt: 4102444800,
        action: 0,
        signerAccountId: testAccountId,
        reviewPayload: Uint8List.fromList(<int>[1, 2, 3]),
      );
    }
    if (text == 'QR_V1 response') {
      final signature = Uint8List(64);
      if (mismatchedResponseSignature) signature[0] = 1;
      return CitizenQrDocument(
        kind: CitizenQrKind.signResponse,
        canonicalText: text,
        requestId: 'request-1',
        expiresAt: 4102444800,
        signerAccountId: testAccountId,
        signature: signature,
      );
    }
    throw const FormatException('unsupported QR_V1 fixture');
  }
}

final class RecordedTransactionCall {
  RecordedTransactionCall(Uint8List sourceAccountId, Uint8List callData)
    : sourceAccountId = Uint8List.fromList(
        sourceAccountId,
      ).asUnmodifiableView(),
      callData = Uint8List.fromList(callData).asUnmodifiableView();

  final Uint8List sourceAccountId;
  final Uint8List callData;
}

final class RecordingTransactions extends StrictPublicPort
    implements CitizenTransactions {
  final List<RecordedTransactionCall> calls = <RecordedTransactionCall>[];

  @override
  Future<CitizenPreparedTransaction> prepareTransaction(
    Uint8List sourceAccountId,
    Uint8List callData,
  ) async {
    calls.add(RecordedTransactionCall(sourceAccountId, callData));
    final ordinal = calls.length;
    return CitizenPreparedTransaction(
      preparationId: 'preparation-$ordinal',
      sourceAccountId: sourceAccountId,
      callDataHash: Uint8List.fromList(
        List<int>.generate(
          32,
          (index) => (callData[index % callData.length] + index) & 0xff,
        ),
      ),
      bestBlock: testFinalizedBlock,
      runtimeSpecNumber: 1,
      transactionFormatNumber: 1,
      nonce: BigInt.from(ordinal),
    );
  }
}

final class RecordingHistory extends StrictPublicPort
    implements CitizenHistory {
  var readCount = 0;
  var syncCount = 0;

  @override
  Future<CitizenTransactionHistoryPage> getTransactionHistory({
    String? beforeExecutionId,
    int limit = 100,
  }) async {
    readCount += 1;
    return _page();
  }

  @override
  Future<CitizenTransactionHistoryPage> syncTransactionHistory() async {
    syncCount += 1;
    return _page();
  }

  CitizenTransactionHistoryPage _page() => CitizenTransactionHistoryPage(
    revision: BigInt.from(readCount + syncCount),
    records: const <CitizenTransactionHistoryRecord>[],
    nextBeforeExecutionId: null,
  );
}
