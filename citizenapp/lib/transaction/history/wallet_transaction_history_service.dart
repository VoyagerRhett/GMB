import 'dart:async';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:polkadart/polkadart.dart' show Hasher;
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:citizenapp/transaction/history/citizenchain_transaction_event_decoder.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/wallet/account_balance_snapshot_store.dart';

/// 钱包业务流水的唯一同步入口；所有读取复用 SDK 已验证链。
/// SDK history 决定本机提交状态，App 原子保存业务事件与逐账户进度。
final class WalletTransactionHistoryService {
  WalletTransactionHistoryService({
    required CitizenHistory history,
    required CitizenChain chain,
    required CitizenSdkWallet wallet,
    required Stream<CitizenSdkEvent> events,
  }) : _history = history,
       _chain = chain,
       _wallet = wallet,
       _sdkEvents = events;

  final CitizenHistory _history;
  final CitizenChain _chain;
  final CitizenSdkWallet _wallet;
  final Stream<CitizenSdkEvent> _sdkEvents;
  StreamSubscription<CitizenSdkEvent>? _events;
  WalletIsarConsumerLease? _lease;
  Future<void>? _flight;
  Timer? _retry;
  bool _active = false;
  bool _foreground = true;
  int _epoch = 0;
  int _retrySeconds = 2;
  bool _requested = false;

  /// 启动不等待网络补齐，离线不能阻塞钱包原页面。
  Future<void> start() async {
    if (_active) return;
    _lease = WalletIsar.instance.registerExternalConsumer(stop);
    _active = true;
    _events = _sdkEvents.listen((event) {
      if (event is CitizenSdkWalletChanged) _epoch++;
      if (event is CitizenSdkWalletChanged ||
          event is CitizenSdkHistoryChanged ||
          event is CitizenSdkFinalizedBlockChanged) {
        requestSync();
      }
    });
    requestSync();
  }

  /// 后台停止调度，迟到结果失效；前台从持久进度继续。
  void setForeground(bool foreground) {
    _foreground = foreground;
    if (!foreground) {
      _epoch++;
      _retry?.cancel();
      _retry = null;
    } else {
      requestSync();
    }
  }

  void requestSync() {
    if (!_active || !_foreground) return;
    unawaited(
      sync().catchError((Object _) {
        AppLog.d('[TransactionHistory] sync_failed');
      }),
    );
  }

  /// 手动刷新和 SDK 事件合并在途任务，最多每轮处理 32 块。
  Future<void> sync() {
    if (!_active || !_foreground) return Future<void>.value();
    if (_flight != null) {
      _requested = true;
      return _flight!;
    }
    _retry?.cancel();
    _retry = null;
    _requested = false;
    final epoch = _epoch;
    final future = _syncPass(epoch)
        .then((more) {
          _retrySeconds = 2;
          if (more || _requested || epoch != _epoch) {
            _schedule(const Duration(seconds: 1));
          }
        })
        .catchError((Object error, StackTrace stack) {
          _schedule(Duration(seconds: _retrySeconds));
          _retrySeconds = (_retrySeconds * 2).clamp(2, 30);
          Error.throwWithStackTrace(error, stack);
        })
        .whenComplete(() => _flight = null);
    _flight = future;
    return future;
  }

  void _schedule(Duration delay) {
    if (!_active || !_foreground || _retry != null) return;
    _retry = Timer(delay, () {
      _retry = null;
      requestSync();
    });
  }

  bool _current(int epoch) => _active && _foreground && epoch == _epoch;

  /// 停止后等待在途读取退出，禁止迟到写入重新打开已擦除的库。
  Future<void> stop() async {
    _active = false;
    _epoch++;
    _retry?.cancel();
    _retry = null;
    final events = _events;
    _events = null;
    await events?.cancel();
    try {
      await _flight;
    } catch (_) {
      // 读取失败不阻断关闭；业务进度留在上次已提交块。
    } finally {
      _lease?.release();
      _lease = null;
    }
  }

  Future<void> _syncExecutionFacts(int epoch) async {
    var page = await _history.syncTransactionHistory();
    final consumed = <String>{};
    while (true) {
      for (final record in page.records) {
        if (!_current(epoch)) return;
        await _applyExecution(record);
      }
      final cursor = page.nextBeforeExecutionId;
      if (cursor == null) return;
      if (!consumed.add(cursor)) throw StateError('SDK history 分页游标重复');
      page = await _history.getTransactionHistory(beforeExecutionId: cursor);
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
          failureReason:
              record.poolRejectionReason ??
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
    final block = record.block;
    if (_active &&
        _foreground &&
        block != null &&
        (record.status == CitizenTransactionHistoryStatus.finalizedSuccess ||
            record.status == CitizenTransactionHistoryStatus.finalizedFailed)) {
      try {
        await AccountBalanceSnapshotStore.forChain(
          _chain,
        ).afterFinalized(block, [accountId]);
      } catch (_) {
        // 交易的链上结果已确认；余额刷新失败不得把结果降为失败或清空原快照。
      }
    }
  }

  Future<bool> _syncPass(int epoch) async {
    await _syncExecutionFacts(epoch);
    if (!_current(epoch)) return false;
    final wallet = await _wallet.getState().result;
    if (!_current(epoch) || wallet.accounts.isEmpty) return false;
    final genesis = await _chain.getGenesisHash();
    final head = await _chain.getFinalizedHead();
    if (head.number < BigInt.zero ||
        head.number >= BigInt.from(0x7fffffffffffffff)) {
      throw StateError('finalized 高度超出本机进度范围');
    }
    _requireBlock(head, head.number.toInt());
    final cursors = <String, WalletTransactionHistoryCursorEntity>{};
    final accounts = {for (final a in wallet.accounts) a.accountId: a};
    // 同次导入的多个账户共享边界定位结果，避免重复二分查询。
    final starts = <BigInt, int>{};
    for (final account in accounts.values) {
      if (!_current(epoch)) return false;
      var cursor = await LocalTxStore.historyCursor(account.accountId);
      if (cursor == null) {
        final start =
            starts[account.createdAtMillis] ??
            await _findStartBlock(head, account.createdAtMillis, epoch);
        starts[account.createdAtMillis] = start;
        if (!_current(epoch)) return false;
        cursor = WalletTransactionHistoryCursorEntity()
          ..accountId = account.accountId
          ..createdAtMillis = account.createdAtMillis.toInt()
          ..genesisHash = genesis
          ..startBlockNumber = start
          ..cursorBlockNumber = start - 1;
        await LocalTxStore.insertHistoryCursor(cursor);
      }
      if (cursor.genesisHash != genesis ||
          BigInt.from(cursor.createdAtMillis) != account.createdAtMillis ||
          cursor.startBlockNumber < 1 ||
          cursor.cursorBlockNumber < cursor.startBlockNumber - 1 ||
          cursor.cursorBlockNumber > head.number.toInt()) {
        throw StateError('钱包进度的链身份或账户代次不一致');
      }
      cursors[account.accountId] = cursor;
    }
    final first = cursors.values
        .map((c) => c.cursorBlockNumber + 1)
        .reduce((a, b) => a < b ? a : b);
    final target = head.number.toInt();
    final end = first + 31 < target ? first + 31 : target;
    for (var number = first; number <= end; number++) {
      if (!_current(epoch)) return false;
      final block = await _chain.getFinalizedBlockAt(BigInt.from(number));
      _requireBlock(block, number);
      final time = await _timestamp(block);
      final participants = cursors.values
          .where((c) => c.cursorBlockNumber == number - 1)
          .toList();
      final addresses = <String, String>{
        for (final c in participants)
          if (time >= c.createdAtMillis)
            c.accountId: accounts[c.accountId]!.ss58Address,
      };
      final records = await _readRecords(block, time, addresses);
      if (!_current(epoch)) return false;
      await LocalTxStore.commitHistoryBlock(
        blockNumber: number,
        cursors: participants,
        records: records,
      );
      for (final cursor in participants) {
        cursor.cursorBlockNumber = number;
      }
      // 历史补齐不逐块刷新余额，只有最新块影响钱包时通知余额唯一入口。
      if (number == target && records.isNotEmpty && _current(epoch)) {
        try {
          await AccountBalanceSnapshotStore.forChain(
            _chain,
          ).afterFinalized(block, records.map((r) => r.accountId).toSet());
        } catch (_) {
          // 余额失败不撤销交易记录，也不清空原快照。
        }
      }
    }
    return cursors.values.any((c) => c.cursorBlockNumber < target);
  }

  /// 本链 Timestamp.Now 为严格递增 u64 毫秒；按高度二分定位导入时间。
  /// 只读取早期块的边界证明，不投影其交易。失败不得把起点换成当前块。
  Future<int> _findStartBlock(
    CitizenBlockRef head,
    BigInt createdAt,
    int epoch,
  ) async {
    if (createdAt <= BigInt.zero ||
        createdAt > BigInt.from(0x7fffffffffffffff)) {
      throw StateError('账户导入时间无效');
    }
    var low = 1;
    var high = head.number.toInt() + 1;
    while (low < high) {
      if (!_current(epoch)) throw StateError('业务同步已取消');
      final middle = low + ((high - low) ~/ 2);
      final block = await _chain.getFinalizedBlockAt(BigInt.from(middle));
      _requireBlock(block, middle);
      if (BigInt.from(await _timestamp(block)) < createdAt) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  Future<int> _timestamp(CitizenBlockRef block) async {
    final bytes = await _chain.getStorage(
      block,
      Uint8List.fromList([
        ...Hasher.twoxx128.hashString('Timestamp'),
        ...Hasher.twoxx128.hashString('Now'),
      ]),
    );
    if (bytes == null || bytes.length != 8) {
      throw const FormatException('已验证区块缺少准确 Timestamp.Now');
    }
    final value = ByteData.sublistView(bytes).getUint64(0, Endian.little);
    if (value <= 0) throw const FormatException('链上区块时间无效');
    return value;
  }

  void _requireBlock(CitizenBlockRef block, int number) {
    if (number < 0 ||
        block.finality != CitizenBlockFinality.finalized ||
        block.number != BigInt.from(number)) {
      throw StateError('SDK 区块与 finalized 请求高度不一致');
    }
  }

  Future<List<LocalTxEntity>> _readRecords(
    CitizenBlockRef block,
    int time,
    Map<String, String> addresses,
  ) async {
    if (addresses.isEmpty) return [];
    final bytes = await _chain.getSystemEvents(block);
    if (bytes == null) return [];
    if (bytes.isEmpty) throw const FormatException('System.Events SCALE 内容为空');
    final runtime = await _chain.getRuntimeContext(block);
    if (runtime.block.hash != block.hash ||
        runtime.block.number != block.number) {
      throw StateError('Runtime metadata 与事件锚点不一致');
    }
    final decoded = const CitizenChainTransactionEventDecoder().decode(
      eventsBytes: bytes,
      metadataBytes: runtime.metadata,
    );
    final relevant = decoded.transfers
        .where(
          (e) =>
              addresses.containsKey(e.fromAccountId) ||
              addresses.containsKey(e.toAccountId),
        )
        .toList();
    if (relevant.isEmpty) return [];
    final body = await _chain.getBlockBody(block);
    if (body.block.hash != block.hash || body.block.number != block.number) {
      throw StateError('区块正文与事件锚点不一致');
    }
    final records = <LocalTxEntity>[];
    for (final transfer in relevant) {
      final index = transfer.extrinsicIndex;
      if (index != null) {
        final outcome = decoded.outcomes[index];
        if (outcome == null) throw const FormatException('转账缺少 System 执行结果');
        if (!outcome.succeeded) continue;
        if (index < 0 || index >= body.extrinsics.length) {
          throw const FormatException('转账事件索引超出区块正文');
        }
      }
      // 与 SDK 同合同：完整 SCALE extrinsic 字节的 Blake2-256。
      final hash = index == null
          ? null
          : '0x${_hex(Hasher.blake2b256.hash(body.extrinsics[index]))}';
      for (final accountId in {transfer.fromAccountId, transfer.toAccountId}) {
        final address = addresses[accountId];
        if (address == null) continue;
        final incoming = accountId == transfer.toAccountId;
        final self = transfer.fromAccountId == transfer.toAccountId;
        records.add(
          LocalTxEntity()
            ..recordKey = LocalTxStore.blockEventRecordKey(
              accountId,
              block.hash,
              transfer.eventRecordIndex,
            )
            ..accountId = accountId
            ..ss58Address = address
            ..type = 'transfer'
            ..amountDeltaFen = self
                ? '0'
                : incoming
                ? transfer.amountFen
                : LocalTxStore.negateFen(transfer.amountFen)
            ..transferAmountFen = transfer.amountFen
            ..fromSs58Address = _ss58(transfer.fromAccountId)
            ..toSs58Address = _ss58(transfer.toAccountId)
            ..counterpartySs58Address = _ss58(
              incoming ? transfer.fromAccountId : transfer.toAccountId,
            )
            ..remark = transfer.remark
            ..status = LocalTxStore.statusFinalized
            ..source = 'sdk_finalized_event'
            ..txHash = hash
            ..blockNumber = block.number.toInt()
            ..blockHash = block.hash
            ..eventIndex = transfer.eventRecordIndex
            ..extrinsicIndex = index
            ..createdAtMillis = time
            ..confirmedAtMillis = time,
        );
      }
    }
    return records;
  }

  String _ss58(String accountId) =>
      Keyring().encodeAddress(_accountIdBytes(accountId), kGmbSs58Prefix);

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
}
