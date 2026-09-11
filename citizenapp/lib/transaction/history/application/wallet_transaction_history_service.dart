import 'package:citizenapp/transaction/history/data/local_tx_store.dart';
import 'package:citizenapp/transaction/ports/transaction_executor.dart';

/// Projects generic SDK execution facts into CitizenApp's existing business
/// history without teaching the SDK about destination, amount or remarks.
///
/// The Isar entity remains the sole App-owned business record. This service is
/// activated when the SDK adapter is installed in Part 3; it does not introduce
/// a second database or a dual-write path.
final class WalletTransactionHistoryService {
  const WalletTransactionHistoryService(this._executor);

  final TransactionExecutor _executor;

  Future<void> syncExecutionFacts() async {
    await _executor.syncTransactionHistory();
    final facts = await _executor.getTransactionHistory();
    for (final fact in facts) {
      final txHash = '0x${_hex(fact.transactionHash)}';
      final accountId = '0x${_hex(fact.sourceAccountId)}';
      switch (fact.status) {
        case AppTransactionExecutionStatus.pending:
          await LocalTxStore.markLocalSubmitPending(
            accountId: accountId,
            txHash: txHash,
          );
          break;
        case AppTransactionExecutionStatus.inBlock:
          final blockHash = fact.blockHash;
          if (blockHash != null) {
            await LocalTxStore.markLocalSubmitInBlock(
              accountId: accountId,
              txHash: txHash,
              blockHash: blockHash,
            );
          }
          break;
        case AppTransactionExecutionStatus.poolRejected:
        case AppTransactionExecutionStatus.finalizedFailed:
          await LocalTxStore.markLocalSubmitFailed(
            accountId: accountId,
            txHash: txHash,
            failureReason: fact.failureReason ?? fact.status.name,
          );
          break;
        case AppTransactionExecutionStatus.finalizedSuccess:
          await LocalTxStore.markLocalSubmitFinalized(
            accountId: accountId,
            txHash: txHash,
            blockHash: fact.blockHash,
            blockNumber: fact.blockNumber,
            extrinsicIndex: fact.extrinsicIndex,
          );
          break;
      }
    }
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
