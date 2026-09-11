import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';

/// A product-neutral consumer proving that all six SDK capabilities compose
/// without importing an SDK implementation library.
final class ReferenceConsumer {
  const ReferenceConsumer({
    required this.chain,
    required this.wallet,
    required this.signing,
    required this.qr,
    required this.transactions,
    required this.history,
  });

  factory ReferenceConsumer.fromSdk(CitizenSdk sdk) => ReferenceConsumer(
    chain: sdk.chain,
    wallet: sdk.wallet,
    signing: sdk.signing,
    qr: sdk.qr,
    transactions: sdk.transactions,
    history: sdk.history,
  );

  final CitizenChain chain;
  final CitizenWallet wallet;
  final CitizenSigning signing;
  final CitizenQr qr;
  final CitizenTransactions transactions;
  final CitizenHistory history;

  /// Exercises only public, product-independent facts. The caller remains the
  /// owner of storage keys, payload bytes and RuntimeCall bytes.
  Future<ReferenceConsumerSnapshot> inspect({
    required String signerAccountId,
    required Uint8List sourceAccountId,
    required Uint8List storageKey,
    required Uint8List payload,
    required Uint8List callData,
  }) async {
    final finalized = await chain.getFinalizedHead();
    final storage = await chain.getStorage(
      finalized,
      Uint8List.fromList(storageKey),
    );
    final walletState = await wallet.getState();
    final signingOutcome = await signing.begin(
      CitizenSigningIntent(
        accountId: signerAccountId,
        payload: Uint8List.fromList(payload),
        transform: CitizenSigningTransform.raw(),
      ),
    );
    final qrRequest = await qr.createSignRequest(
      action: 0,
      signerAccountId: signerAccountId,
      reviewPayload: Uint8List.fromList(payload),
    );
    final prepared = await transactions.prepareTransaction(
      Uint8List.fromList(sourceAccountId),
      Uint8List.fromList(callData),
    );
    final executionHistory = await history.getTransactionHistory(limit: 1);

    return ReferenceConsumerSnapshot(
      finalized: finalized,
      walletRevision: walletState.revision,
      signingOutcome: signingOutcome,
      qrRequest: qrRequest,
      prepared: prepared,
      historyRevision: executionHistory.revision,
      storage: storage,
    );
  }
}

/// Product-neutral output containing only SDK facts.
final class ReferenceConsumerSnapshot {
  ReferenceConsumerSnapshot({
    required this.finalized,
    required this.walletRevision,
    required this.signingOutcome,
    required this.qrRequest,
    required this.prepared,
    required this.historyRevision,
    required Uint8List? storage,
  }) : storage = storage == null
           ? null
           : Uint8List.fromList(storage).asUnmodifiableView();

  final CitizenBlockRef finalized;
  final BigInt walletRevision;
  final CitizenSigningOutcome signingOutcome;
  final String qrRequest;
  final CitizenPreparedTransaction prepared;
  final BigInt historyRevision;
  final Uint8List? storage;
}
