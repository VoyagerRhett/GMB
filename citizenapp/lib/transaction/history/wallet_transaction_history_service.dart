import 'dart:async';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show RuntimeMetadata;
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:citizenapp/transaction/history/citizenchain_transaction_event_decoder.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';

/// CitizenApp 交易业务记录的唯一投影器。
///
/// CitizenSDK history 是本机提交交易状态真源；CitizenApp 只在 Isar 中保留
/// 目的账户、金额、备注、收发方向等业务展示字段。本类不启动节点、
/// 不管理链 database、不订阅 JSON-RPC、不扫描接入 SDK 之前的历史块。
final class WalletTransactionHistoryService {
  WalletTransactionHistoryService({
    required CitizenHistory history,
    required CitizenChain chain,
    required CitizenSdkWallet wallet,
    required Stream<CitizenSdkEvent> events,
  })  : _history = history,
        _chain = chain,
        _wallet = wallet,
        _sdkEvents = events;

  final CitizenHistory _history;
  final CitizenChain _chain;
  final CitizenSdkWallet _wallet;
  final Stream<CitizenSdkEvent> _sdkEvents;
  StreamSubscription<CitizenSdkEvent>? _events;
  Future<void> _tail = Future<void>.value();

  /// 开始消费同一 SDK session 的类型化事件。重复调用不会建立第二订阅。
  Future<void> start() async {
    if (_events != null) return;
    _events = _sdkEvents.listen((event) {
      if (event is CitizenSdkHistoryChanged) {
        _enqueue(syncExecutionFacts);
      } else if (event is CitizenSdkFinalizedBlockChanged) {
        _enqueue(() => _projectFinalizedBlock(event.finalized));
      }
    });
    await syncExecutionFacts();
  }

  /// 取消 App 业务投影订阅并等待已进入队列的写入完成。
  Future<void> stop() async {
    final events = _events;
    _events = null;
    await events?.cancel();
    await _tail;
  }

  void _enqueue(Future<void> Function() operation) {
    _tail = _tail.then((_) => operation()).catchError(
      (Object error, StackTrace stackTrace) {
        AppLog.d('[TransactionHistory] 业务投影失败: $error\n$stackTrace');
      },
    );
  }

  /// 把 SDK 公开 execution history 终态投影到已存在的 App 业务记录。
  Future<void> syncExecutionFacts() async {
    var page = await _history.syncTransactionHistory();
    final consumedCursors = <String>{};
    while (true) {
      for (final record in page.records) {
        await _applyExecution(record);
      }
      final cursor = page.nextBeforeExecutionId;
      if (cursor == null) return;
      if (!consumedCursors.add(cursor)) {
        throw StateError('CitizenSDK history 返回了重复分页游标');
      }
      page = await _history.getTransactionHistory(
        beforeExecutionId: cursor,
      );
    }
  }

  Future<void> _applyExecution(CitizenTransactionHistoryRecord record) async {
    final txHash = record.transactionHash;
    final accountId = record.sourceAccountId;
    final executionId = record.executionId;
    final callDataHash = record.callDataHash;
    switch (record.status) {
      case CitizenTransactionHistoryStatus.pending:
        await LocalTxStore.markLocalSubmitPending(
          accountId: accountId,
          txHash: txHash,
          executionId: executionId,
          callDataHash: callDataHash,
        );
        break;
      case CitizenTransactionHistoryStatus.inBlock:
        final block = record.block;
        if (block != null) {
          await LocalTxStore.markLocalSubmitInBlock(
            accountId: accountId,
            txHash: txHash,
            executionId: executionId,
            callDataHash: callDataHash,
            blockHash: block.hash,
          );
        }
        break;
      case CitizenTransactionHistoryStatus.poolRejected:
      case CitizenTransactionHistoryStatus.finalizedFailed:
        await LocalTxStore.markLocalSubmitFailed(
          accountId: accountId,
          txHash: txHash,
          executionId: executionId,
          callDataHash: callDataHash,
          failureReason: record.poolRejectionReason ??
              (record.status == CitizenTransactionHistoryStatus.poolRejected
                  ? '交易池拒绝'
                  : '链上执行失败'),
        );
        break;
      case CitizenTransactionHistoryStatus.finalizedSuccess:
        final block = record.block;
        await LocalTxStore.markLocalSubmitFinalized(
          accountId: accountId,
          txHash: txHash,
          executionId: executionId,
          callDataHash: callDataHash,
          blockHash: block?.hash,
          blockNumber: block?.number.toInt(),
          extrinsicIndex: record.execution?.extrinsicIndex,
          confirmedAtMillis: record.updatedAtMillis.toInt(),
        );
        break;
    }
  }

  /// 只解码 SDK 已验证 finalized 块中的 CitizenApp 转账业务事件。
  Future<void> _projectFinalizedBlock(CitizenBlockRef finalized) async {
    final eventsBytes = await _chain.getSystemEvents(finalized);
    if (eventsBytes == null || eventsBytes.isEmpty) return;
    final runtime = await _chain.getRuntimeContext(finalized);
    final metadata = RuntimeMetadata.fromHex('0x${_hex(runtime.metadata)}');
    final decoded = const CitizenChainTransactionEventDecoder().decode(
      eventsBytes: eventsBytes,
      metadata: metadata,
      eventsStorageKeyHex: '0x${_hex(_systemEventsStorageKey)}',
    );
    final wallet = await _wallet.getState();
    final ss58ByAccountId = <String, String>{
      for (final account in wallet.accounts)
        account.accountId: account.ss58Address,
    };
    for (final transfer in decoded.transfers) {
      final outcome = transfer.extrinsicIndex == null
          ? null
          : decoded.outcomes[transfer.extrinsicIndex];
      // 有 extrinsic phase 的业务事件必须同时具有同索引 System.Success；
      // 缺失或失败都不能投影为 App 交易流水。
      if (transfer.extrinsicIndex != null && outcome?.succeeded != true) {
        continue;
      }
      await _writeTransferSide(
        accountId: transfer.toAccountId,
        ss58ByAccountId: ss58ByAccountId,
        finalized: finalized,
        transfer: transfer,
        amountDeltaFen: transfer.amountFen,
        counterpartyAccountId: transfer.fromAccountId,
      );
      if (transfer.fromAccountId != transfer.toAccountId) {
        await _writeTransferSide(
          accountId: transfer.fromAccountId,
          ss58ByAccountId: ss58ByAccountId,
          finalized: finalized,
          transfer: transfer,
          amountDeltaFen: LocalTxStore.negateFen(transfer.amountFen),
          counterpartyAccountId: transfer.toAccountId,
        );
      }
    }
  }

  Future<void> _writeTransferSide({
    required String accountId,
    required Map<String, String> ss58ByAccountId,
    required CitizenBlockRef finalized,
    required CitizenChainTransferEvent transfer,
    required String amountDeltaFen,
    required String counterpartyAccountId,
  }) async {
    final ss58Address = ss58ByAccountId[accountId];
    if (ss58Address == null) return;
    final fromSs58 = _ss58(transfer.fromAccountId);
    final toSs58 = _ss58(transfer.toAccountId);
    await LocalTxStore.upsertBlockTransferEvent(
      ss58Address: ss58Address,
      accountId: accountId,
      recordKey: LocalTxStore.blockEventRecordKey(
        accountId,
        finalized.hash,
        transfer.eventRecordIndex,
      ),
      status: LocalTxStore.statusFinalized,
      amountDeltaFen: amountDeltaFen,
      transferAmountFen: transfer.amountFen,
      fromSs58Address: fromSs58,
      toSs58Address: toSs58,
      counterpartySs58Address: _ss58(counterpartyAccountId),
      blockNumber: finalized.number.toInt(),
      blockHash: finalized.hash,
      eventIndex: transfer.eventRecordIndex,
      extrinsicIndex: transfer.extrinsicIndex,
      remark: transfer.remark,
    );
  }

  String _ss58(String accountId) => Keyring().encodeAddress(
        _accountIdBytes(accountId),
        kGmbSs58Prefix,
      );

  static Uint8List _accountIdBytes(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return Uint8List.fromList(<int>[
      for (var offset = 2; offset < accountId.length; offset += 2)
        int.parse(accountId.substring(offset, offset + 2), radix: 16),
    ]);
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static final Uint8List _systemEventsStorageKey = Uint8List.fromList(<int>[
    0x26, 0xaa, 0x39, 0x4e, 0xea, 0x56, 0x30, 0xe0,
    0x7c, 0x48, 0xae, 0x0c, 0x95, 0x58, 0xce, 0xf7,
    0x80, 0xd4, 0x1e, 0x5e, 0x16, 0x05, 0x67, 0x65,
    0xbc, 0x84, 0x6f, 0x2b, 0xb2, 0x0c, 0x7a, 0xa9,
  ]);
}
