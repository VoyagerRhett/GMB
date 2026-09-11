import 'dart:typed_data';

/// App-facing projection of one generic SDK transaction execution fact.
///
/// CitizenApp business services retain their own destination, amount, remark
/// and pallet semantics and correlate them with this value by execution/hash.
final class AppTransactionExecutionFact {
  AppTransactionExecutionFact({
    required this.executionId,
    required Uint8List sourceAccountId,
    required Uint8List callDataHash,
    required Uint8List transactionHash,
    required this.status,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.blockHash,
    this.blockNumber,
    this.extrinsicIndex,
    this.failureReason,
  })  : sourceAccountId = Uint8List.fromList(sourceAccountId),
        callDataHash = Uint8List.fromList(callDataHash),
        transactionHash = Uint8List.fromList(transactionHash);

  final String executionId;
  final Uint8List sourceAccountId;
  final Uint8List callDataHash;
  final Uint8List transactionHash;
  final AppTransactionExecutionStatus status;
  final int createdAtMillis;
  final int updatedAtMillis;
  final String? blockHash;
  final int? blockNumber;
  final int? extrinsicIndex;
  final String? failureReason;
}

enum AppTransactionExecutionStatus {
  pending,
  inBlock,
  poolRejected,
  finalizedSuccess,
  finalizedFailed,
}

/// Product-neutral transaction operations required by CitizenApp business code.
///
/// Part 3 binds this port to CitizenSDK. No CitizenApp business DTO crosses it.
abstract interface class TransactionExecutor {
  Future<String> prepareTransaction({
    required Uint8List sourceAccountId,
    required Uint8List opaqueCallData,
  });

  Future<AppTransactionExecutionFact> executePreparedTransaction(
    String preparationId,
  );

  Future<List<AppTransactionExecutionFact>> getTransactionHistory({
    String? beforeExecutionId,
    int limit = 100,
  });

  Future<void> syncTransactionHistory();
}
