import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/isar_test_env.dart';

void main() {
  useIsolatedIsar();

  const fromAccountId =
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fromSs58Address = 'from-wallet';
  const toSs58Address = 'to-wallet';

  // 只使用合成账户和金额，覆盖接入前后的同表数据及账户隔离。
  LocalTxEntity historicalRow(
    String source,
    int timestamp, {
    String? accountId,
  }) {
    final owner = accountId ?? fromAccountId;
    return LocalTxEntity()
      ..accountId = owner
      ..ss58Address = fromSs58Address
      ..recordKey = '$owner:$source:$timestamp'
      ..type = 'transfer'
      ..amountDeltaFen = '100'
      ..source = source
      ..status = LocalTxStore.statusFinalized
      ..createdAtMillis = timestamp;
  }

  test('既有收款按账户可见，分页、单条查询与总数使用同一范围', () async {
    final rows = [
      historicalRow('chain_event', 1),
      historicalRow('resync', 2),
      historicalRow('sdk_finalized_event', 3),
      historicalRow('local_submit', 4),
    ];
    for (final row in rows) {
      await LocalTxStore.upsert(row);
    }
    const other =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    await LocalTxStore.upsert(
      historicalRow('chain_event', 5, accountId: other),
    );
    expect(await LocalTxStore.countByAccountId(fromAccountId), 4);
    expect(await LocalTxStore.countByAccountId(other), 1);
    expect(
      (await LocalTxStore.queryByAccountId(
        fromAccountId,
        offset: 1,
        limit: 2,
      )).map((row) => row.source),
      ['sdk_finalized_event', 'resync'],
    );
    expect(
      await LocalTxStore.queryByAccountId(fromAccountId, offset: 4),
      isEmpty,
    );
    for (final row in rows) {
      expect(
        (await LocalTxStore.queryByRecordKey(row.recordKey))?.recordKey,
        row.recordKey,
      );
    }
    expect(await LocalTxStore.queryByRecordKey('missing'), isNull);
  });

  test('恢复旧记录可见性不会授予其 SDK 状态更新权限', () async {
    for (final source in [
      'chain_event',
      'sdk_finalized_event',
      'local_submit',
    ]) {
      final row = historicalRow(source, 1)
        ..recordKey = LocalTxStore.submitRecordKey(fromAccountId, '0xabc')
        ..status = LocalTxStore.statusPending
        ..executionId = source == 'local_submit' ? '' : 'execution-1'
        ..callDataHash = source == 'local_submit' ? '' : '0x${'11' * 32}';
      await LocalTxStore.upsert(row);
      await LocalTxStore.markLocalSubmitFinalized(
        accountId: fromAccountId,
        txHash: '0xabc',
        executionId: row.executionId!,
        callDataHash: row.callDataHash!,
      );
      expect(
        (await LocalTxStore.queryByRecordKey(row.recordKey))?.status,
        LocalTxStore.statusPending,
      );
    }
  });

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
    final before = (await LocalTxStore.queryByAccountId(fromAccountId))
        .single
        .recordKey;

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
    final after = (await LocalTxStore.queryByAccountId(fromAccountId)).single;
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

    final record = (await LocalTxStore.queryByAccountId(fromAccountId)).single;
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

    final record = (await LocalTxStore.queryByAccountId(fromAccountId)).single;
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
      txHash: '0xabc',
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

  Future<void> event({String hash = '0xabc', int index = 4}) =>
      LocalTxStore.upsertBlockTransferEvent(
        ss58Address: fromSs58Address,
        accountId: fromAccountId,
        recordKey: LocalTxStore.blockEventRecordKey(
          fromAccountId,
          '0x33',
          index,
        ),
        status: LocalTxStore.statusFinalized,
        txHash: hash,
        amountDeltaFen: '-100',
        transferAmountFen: '100',
        fromSs58Address: fromSs58Address,
        toSs58Address: toSs58Address,
        counterpartySs58Address: toSs58Address,
        blockNumber: 10,
        blockHash: '0x33',
        eventIndex: index,
        extrinsicIndex: 2,
      );

  test('不同哈希的同金额转账保留两条，重放同一事件不重复', () async {
    await insert();
    await event(hash: '0xdef');
    await event(hash: '0xdef');
    final rows = await LocalTxStore.queryByAccountId(fromAccountId);
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.txHash).toSet(), {'0xabc', '0xdef'});
  });

  test('事件先到再本机提交仍只保留一条并保留手续费', () async {
    await event();
    await insert();
    await event();
    final rows = await LocalTxStore.queryByAccountId(fromAccountId);
    expect(rows, hasLength(1));
    expect(
      rows.single.recordKey,
      LocalTxStore.submitRecordKey(fromAccountId, '0xabc'),
    );
    expect(rows.single.amountDeltaFen, '-101');
    expect(rows.single.feeFen, '1');
    expect(rows.single.status, LocalTxStore.statusPending);
  });

  test('同一 extrinsic 的第二个独立事件不能覆盖已关联事件', () async {
    await insert();
    await event(index: 4);
    await event(index: 5);
    await event(index: 5);
    final rows = await LocalTxStore.queryByAccountId(fromAccountId);
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.eventIndex).toSet(), {4, 5});
  });

  WalletTransactionHistoryCursorEntity cursor() =>
      WalletTransactionHistoryCursorEntity()
        ..accountId = fromAccountId
        ..createdAtMillis = 1000
        ..genesisHash = '0x00'
        ..startBlockNumber = 10
        ..cursorBlockNumber = 9;

  test('记录和进度原子提交，重新提交过期进度被拒绝', () async {
    final progress = cursor();
    await LocalTxStore.insertHistoryCursor(progress);
    final row = historicalRow('sdk_finalized_event', 10000)..blockNumber = 10;
    await LocalTxStore.commitHistoryBlock(
      blockNumber: 10,
      cursors: [progress],
      records: [row],
    );
    expect(
      (await LocalTxStore.historyCursor(fromAccountId))!.cursorBlockNumber,
      10,
    );
    expect(await LocalTxStore.countByAccountId(fromAccountId), 1);
    await expectLater(
      LocalTxStore.commitHistoryBlock(
        blockNumber: 10,
        cursors: [progress],
        records: [row],
      ),
      throwsStateError,
    );
  });

  test('块内第二条越界记录使第一条和进度一起回滚', () async {
    final progress = cursor();
    await LocalTxStore.insertHistoryCursor(progress);
    final valid = historicalRow('sdk_finalized_event', 10000)..blockNumber = 10;
    final invalid = historicalRow('sdk_finalized_event', 10001)
      ..blockNumber = 11;
    await expectLater(
      LocalTxStore.commitHistoryBlock(
        blockNumber: 10,
        cursors: [progress],
        records: [valid, invalid],
      ),
      throwsStateError,
    );
    expect(await LocalTxStore.countByAccountId(fromAccountId), 0);
    expect(
      (await LocalTxStore.historyCursor(fromAccountId))!.cursorBlockNumber,
      9,
    );
    expect(progress.cursorBlockNumber, 9);
  });

  test('导入代次不符或进度跳块时不得写入', () async {
    final progress = cursor();
    await LocalTxStore.insertHistoryCursor(progress);
    await expectLater(
      LocalTxStore.commitHistoryBlock(
        blockNumber: 11,
        cursors: [progress],
        records: [],
      ),
      throwsStateError,
    );
    progress.createdAtMillis++;
    await expectLater(
      LocalTxStore.commitHistoryBlock(
        blockNumber: 10,
        cursors: [progress],
        records: [],
      ),
      throwsStateError,
    );
    expect(
      (await LocalTxStore.historyCursor(fromAccountId))!.cursorBlockNumber,
      9,
    );
  });
}
