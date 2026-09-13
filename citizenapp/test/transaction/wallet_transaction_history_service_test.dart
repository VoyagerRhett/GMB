import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/transaction/history/wallet_transaction_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_citizen_sdk.dart';
import '../support/isar_test_env.dart';

const _accountId =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  useIsolatedIsar();

  test('完整遍历 SDK history 分页并只投影 SDK execution 终态', () async {
    await _insert(txHash: '0x01', executionId: 'execution-newer');
    await _insert(txHash: '0x02', executionId: 'execution-older');
    final events = StreamController<CitizenSdkEvent>();
    final service = WalletTransactionHistoryService(
      history: _PagedHistory(),
      chain: TestCitizenChain(),
      wallet: TestCitizenSdkWallet(),
      events: events.stream,
    );

    await service.start();

    final records = await LocalTxStore.queryByAccountId(_accountId);
    final byHash = {for (final record in records) record.txHash: record};
    expect(byHash['0x01']?.status, LocalTxStore.statusInBlock);
    expect(byHash['0x01']?.blockHash, '0x${'11' * 32}');
    expect(byHash['0x02']?.status, LocalTxStore.statusFinalized);
    expect(byHash['0x02']?.blockNumber, 8);
    expect(byHash['0x02']?.extrinsicIndex, 3);

    await service.stop();
    await events.close();
  });
}

Future<void> _insert({
  required String txHash,
  required String executionId,
}) {
  return LocalTxStore.upsertLocalSubmitTransfer(
    ss58Address: 'sender',
    accountId: _accountId,
    txHash: txHash,
    executionId: executionId,
    callDataHash: '0x${'22' * 32}',
    amountDeltaFen: '-101',
    transferAmountFen: '100',
    feeFen: '1',
    counterpartySs58Address: 'recipient',
    fromSs58Address: 'sender',
    toSs58Address: 'recipient',
    usedNonce: 1,
    createdAtMillis: 1,
  );
}

final class _PagedHistory extends TestCitizenHistory {
  @override
  Future<CitizenTransactionHistoryPage> syncTransactionHistory() async {
    return CitizenTransactionHistoryPage(
      revision: BigInt.one,
      records: [_record('execution-newer', '0x01', inBlock: true)],
      nextBeforeExecutionId: 'execution-newer',
    );
  }

  @override
  Future<CitizenTransactionHistoryPage> getTransactionHistory({
    String? beforeExecutionId,
    int limit = 100,
  }) async {
    expect(beforeExecutionId, 'execution-newer');
    expect(limit, 100);
    return CitizenTransactionHistoryPage(
      revision: BigInt.one,
      records: [_record('execution-older', '0x02', inBlock: false)],
      nextBeforeExecutionId: null,
    );
  }

  CitizenTransactionHistoryRecord _record(
    String executionId,
    String txHash, {
    required bool inBlock,
  }) {
    final block = CitizenBlockRef(
      hash: inBlock ? '0x${'11' * 32}' : '0x${'33' * 32}',
      number: BigInt.from(inBlock ? 7 : 8),
      finality: inBlock
          ? CitizenBlockFinality.best
          : CitizenBlockFinality.finalized,
    );
    return CitizenTransactionHistoryRecord(
      executionId: executionId,
      sourceAccountId: _accountId,
      callDataHash: '0x${'22' * 32}',
      transactionHash: txHash,
      status: inBlock
          ? CitizenTransactionHistoryStatus.inBlock
          : CitizenTransactionHistoryStatus.finalizedSuccess,
      block: block,
      execution: inBlock
          ? null
          : CitizenExecution(
              status: CitizenExecutionStatus.success,
              block: block,
              extrinsicIndex: 3,
              dispatchVariant: null,
              palletIndex: null,
              errorIndex: null,
            ),
      replacementHash: null,
      createdAtMillis: BigInt.one,
      updatedAtMillis: BigInt.from(2),
      poolRejectionReason: null,
    );
  }
}
