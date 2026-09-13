import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/isar_test_env.dart';

void main() {
  useIsolatedIsar();

  const fromAccountId =
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fromSs58Address = 'from-wallet';
  const toSs58Address = 'to-wallet';

  Future<void> insert({String txHash = '0xabc'}) =>
      LocalTxStore.upsertLocalSubmitTransfer(
        ss58Address: fromSs58Address,
        accountId: fromAccountId,
        txHash: txHash,
        executionId: 'execution-1',
        callDataHash: '0x${'11' * 32}',
        amountDeltaFen: '-101',
        transferAmountFen: '100',
        feeFen: '1',
        counterpartySs58Address: toSs58Address,
        fromSs58Address: fromSs58Address,
        toSs58Address: toSs58Address,
        usedNonce: 7,
        createdAtMillis: 1,
        remark: '备注',
      );

  test('App 业务字段与 SDK execution/hash 关联后只保留一条记录', () async {
    await insert();

    final records = await LocalTxStore.queryByAccountId(fromAccountId);
    expect(records, hasLength(1));
    final record = records.single;
    expect(record.executionId, 'execution-1');
    expect(record.callDataHash, '0x${'11' * 32}');
    expect(record.txHash, '0xabc');
    expect(record.transferAmountFen, '100');
    expect(record.feeFen, '1');
    expect(record.remark, '备注');
    expect(record.status, LocalTxStore.statusPending);
  });

  test('inBlock 和 finalized 只投影 SDK 事实，recordKey 不变', () async {
    await insert();
    final before =
        (await LocalTxStore.queryByAccountId(fromAccountId)).single.recordKey;

    await LocalTxStore.markLocalSubmitInBlock(
      accountId: fromAccountId,
      txHash: '0xabc',
      executionId: 'execution-1',
      callDataHash: '0x${'11' * 32}',
      blockHash: '0x${'22' * 32}',
    );
    expect(
      (await LocalTxStore.queryByAccountId(fromAccountId)).single.status,
      LocalTxStore.statusInBlock,
    );

    await LocalTxStore.markLocalSubmitFinalized(
      accountId: fromAccountId,
      txHash: '0xabc',
      executionId: 'execution-1',
      callDataHash: '0x${'11' * 32}',
      blockHash: '0x${'22' * 32}',
      blockNumber: 9,
      extrinsicIndex: 2,
    );
    final after =
        (await LocalTxStore.queryByAccountId(fromAccountId)).single;
    expect(after.recordKey, before);
    expect(after.status, LocalTxStore.statusFinalized);
    expect(after.blockNumber, 9);
    expect(after.extrinsicIndex, 2);
  });

  test('SDK 交易池拒绝只更新失败展示，不丢失业务字段', () async {
    await insert(txHash: '0xdef');
    await LocalTxStore.markLocalSubmitFailed(
      accountId: fromAccountId,
      txHash: '0xdef',
      executionId: 'execution-1',
      callDataHash: '0x${'11' * 32}',
      failureReason: 'pool rejected',
    );

    final record =
        (await LocalTxStore.queryByAccountId(fromAccountId)).single;
    expect(record.status, LocalTxStore.statusFailed);
    expect(record.failureReason, 'pool rejected');
    expect(record.executionId, 'execution-1');
    expect(record.transferAmountFen, '100');
  });

  test('拒绝 executionId 或 callDataHash 不匹配的 SDK 状态投影', () async {
    await insert();

    await LocalTxStore.markLocalSubmitFinalized(
      accountId: fromAccountId,
      txHash: '0xabc',
      executionId: 'other-execution',
      callDataHash: '0x${'11' * 32}',
    );
    await LocalTxStore.markLocalSubmitFailed(
      accountId: fromAccountId,
      txHash: '0xabc',
      executionId: 'execution-1',
      callDataHash: '0x${'22' * 32}',
      failureReason: 'must-not-apply',
    );

    final record =
        (await LocalTxStore.queryByAccountId(fromAccountId)).single;
    expect(record.status, LocalTxStore.statusPending);
    expect(record.failureReason, isNull);
  });

  test('finalized 业务事件合并后保留 submit key 且不覆盖 SDK 状态', () async {
    await insert();
    final submitKey = LocalTxStore.submitRecordKey(fromAccountId, '0xabc');

    await LocalTxStore.upsertBlockTransferEvent(
      ss58Address: fromSs58Address,
      accountId: fromAccountId,
      recordKey: LocalTxStore.blockEventRecordKey(
        fromAccountId,
        '0x${'33' * 32}',
        4,
      ),
      status: LocalTxStore.statusFinalized,
      amountDeltaFen: '-100',
      transferAmountFen: '100',
      fromSs58Address: fromSs58Address,
      toSs58Address: toSs58Address,
      counterpartySs58Address: toSs58Address,
      blockNumber: 10,
      blockHash: '0x${'33' * 32}',
      eventIndex: 4,
      extrinsicIndex: 2,
    );

    final records = await LocalTxStore.queryByAccountId(fromAccountId);
    expect(records, hasLength(1));
    expect(records.single.recordKey, submitKey);
    expect(records.single.executionId, 'execution-1');
    expect(records.single.status, LocalTxStore.statusPending);

    await LocalTxStore.markLocalSubmitFinalized(
      accountId: fromAccountId,
      txHash: '0xabc',
      executionId: 'execution-1',
      callDataHash: '0x${'11' * 32}',
      blockHash: '0x${'33' * 32}',
      blockNumber: 10,
      extrinsicIndex: 2,
    );
    expect(
      (await LocalTxStore.queryByAccountId(fromAccountId)).single.status,
      LocalTxStore.statusFinalized,
    );
  });
}
