import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/transaction/offchain-transaction/rpc/offchain_clearing_rpc.dart';

/// 钱包各入口共享同一加载和展示状态；失败保留成功值，未知值始终为 null。
/// 测试可注入读取器，生产状态只由下方余额所有者按账户和来源创建。
class WalletBalanceState<T> extends ChangeNotifier {
  WalletBalanceState(this._loader);

  final Future<T> Function(bool forceRefresh) _loader;
  T? _value;
  Object? _error;
  Future<void>? _loading;
  T? get value => _value;
  bool get hasError => _error != null;
  bool get isLoading => _loading != null;

  /// 普通显示已有快照即返回；并发刷新共享同一次读取，不清空可显示金额。
  Future<void> load({bool forceRefresh = false}) {
    if (!forceRefresh && _value != null) return Future.value();
    final running = _loading;
    if (running != null) return running;
    final completed = Completer<void>();
    _loading = completed.future;
    _error = null;
    // 读取可能在首帧绑定时开始；通知延后，避免组件构建期间反向 setState。
    unawaited(
      Future<void>.microtask(() async {
        notifyListeners();
        try {
          _accept(await _loader(forceRefresh));
        } catch (error) {
          _error = error;
        } finally {
          _loading = null;
          notifyListeners();
          completed.complete();
        }
      }),
    );
    return completed.future;
  }

  void _accept(T value) {
    _value = value;
    _error = null;
    notifyListeners();
  }

  void _fail(Object error) {
    _error = error;
    notifyListeners();
  }

  void _clear() {
    _value = null;
    _error = null;
    notifyListeners();
  }
}

/// wallet 域唯一余额所有者。页面进入只读持久快照，不按时间自动失效；
/// 首次缺失、用户刷新、交易前校验才查询。SDK 仍负责链上证明，缓存不授予交易权限。
class AccountBalanceSnapshotStore {
  AccountBalanceSnapshotStore._(this._chain);

  static final Expando<AccountBalanceSnapshotStore> _stores = Expando();

  /// 每个 SDK 链实例只有一个余额所有者，避免不同实例和测试互相持有在途查询。
  static AccountBalanceSnapshotStore forChain(CitizenChain chain) =>
      _stores[chain] ??= AccountBalanceSnapshotStore._(chain);

  final CitizenChain _chain;
  final _inflight = <String, Future<CitizenAccountBalance>>{};
  final _clearingInflight = <(String, String), Future<BigInt>>{};
  final _changes = StreamController<String>.broadcast();
  final _accountStates = <String, WalletBalanceState<CitizenAccountBalance>>{};
  final _clearingStates = <(String, String), WalletBalanceState<BigInt>>{};
  final _localReads = <String, Future<CitizenAccountBalance?>>{};

  /// 同一账户的所有钱包组件直接观察此状态，不在页面复制金额或加载标志。
  WalletBalanceState<CitizenAccountBalance> accountState(String accountId) {
    _requireAccountId(accountId);
    return _accountStates.putIfAbsent(
      accountId,
      () => WalletBalanceState(
        (force) => getAccountBalance(accountId, forceRefresh: force),
      ),
    );
  }

  WalletBalanceState<BigInt> clearingState({
    required String accountId,
    required String ss58Address,
    required String wssUrl,
  }) {
    _requireAccountId(accountId);
    return _clearingStates.putIfAbsent(
      (accountId, wssUrl),
      () => WalletBalanceState(
        (force) => getClearingBalance(
          accountId: accountId,
          ss58Address: ss58Address,
          wssUrl: wssUrl,
          forceRefresh: force,
        ),
      ),
    );
  }

  /// 钱包目录首次显示前仅恢复磁盘快照，不等待网络、身份或其他缺失账户。
  Future<void> restore(Iterable<String> accountIds) async {
    await Future.wait(accountIds.toSet().map(read));
  }

  /// 已确认钱包删除后先排空该账户读取，再丢弃内存；持久清理由原删除服务执行。
  Future<void> forget(Iterable<String> accountIds) async {
    for (final id in accountIds.toSet()) {
      final states = [
        ?_accountStates[id],
        ..._clearingStates.entries
            .where((entry) => entry.key.$1 == id)
            .map((entry) => entry.value),
      ];
      final pending = <Future<Object?>>[
        ?_inflight[id],
        ?_localReads[id],
        ..._clearingInflight.entries
            .where((entry) => entry.key.$1 == id)
            .map((entry) => entry.value),
        ...states.map((state) => state._loading).whereType<Future<void>>(),
      ];
      await Future.wait(
        pending.map((future) async {
          try {
            await future;
          } catch (_) {
            /* 删除清理继续按原持久事实裁决。 */
          }
        }),
      );
      for (final state in states) {
        state._clear();
      }
    }
  }

  /// 整数分唯一显示转换；不经 double，避免大额最后几位被四舍五入。
  static String formatFen(BigInt fen) {
    final yuan = (fen ~/ BigInt.from(100)).toString();
    final grouped = yuan.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$grouped.${(fen % BigInt.from(100)).abs().toString().padLeft(2, '0')}';
  }

  /// 只通知账户主键；组件重新读取唯一快照，不保存另一份余额业务状态。
  Stream<String> get changes => _changes.stream;

  /// 交易最终确认后只补充落后于证明块的快照；重放旧历史不能触发重复查链。
  Future<void> afterFinalized(
    CitizenBlockRef block,
    Iterable<String> accountIds,
  ) async {
    if (block.finality != CitizenBlockFinality.finalized) {
      throw StateError('余额更新需要 finalized 证明');
    }
    final missing = <String>[];
    for (final accountId in accountIds.toSet()) {
      final snapshot = await read(accountId);
      if (snapshot == null || snapshot.block.number < block.number) {
        missing.add(accountId);
      }
    }
    if (missing.isNotEmpty) {
      await getAccountBalances(missing, forceRefresh: true);
    }
  }

  Future<CitizenAccountBalance> getAccountBalance(
    String accountId, {
    bool forceRefresh = false,
  }) async => (await _load(
    [accountId],
    forceRefresh: forceRefresh,
    single: true,
  )).single;

  /// 保持输入顺序和重复项；并发页面共享同账户正在执行的读取。
  Future<List<CitizenAccountBalance>> getAccountBalances(
    List<String> accountIds, {
    bool forceRefresh = false,
  }) => _load(accountIds, forceRefresh: forceRefresh);

  Future<List<CitizenAccountBalance>> _load(
    List<String> accountIds, {
    bool forceRefresh = false,
    bool single = false,
  }) async {
    for (final accountId in accountIds) {
      _requireAccountId(accountId);
    }
    final ids = accountIds.toSet().toList();
    // 先完成本地读取，再同步登记全部缺失项；避免批量读库途中悬挂未监听的错误 Future。
    // 已有快照的展示不等待其它页面发起的网络刷新。
    final localValues = forceRefresh ? null : await Future.wait(ids.map(read));
    final results = <String, Future<CitizenAccountBalance>>{};
    final missing = <String, Completer<CitizenAccountBalance>>{};
    for (var index = 0; index < ids.length; index++) {
      final accountId = ids[index];
      final local = localValues?[index];
      if (local != null) {
        results[accountId] = Future.value(local);
        continue;
      }
      final running = _inflight[accountId];
      if (running != null) {
        results[accountId] = running;
        continue;
      }
      final completer = Completer<CitizenAccountBalance>();
      missing[accountId] = completer;
      results[accountId] = _inflight[accountId] = completer.future;
    }
    if (missing.isNotEmpty) unawaited(_refresh(missing, single: single));
    return Future.wait(accountIds.map((id) => results[id]!));
  }

  Future<void> _refresh(
    Map<String, Completer<CitizenAccountBalance>> pending, {
    required bool single,
  }) async {
    final ids = pending.keys.toList();
    try {
      final values = single
          ? [await _chain.getAccountBalance(ids.single)]
          : await _chain.getAccountBalances(ids);
      if (values.length != ids.length) throw StateError('余额响应数量不一致');
      for (var i = 0; i < ids.length; i++) {
        _validate(values[i], ids[i]);
      }
      for (var i = 0; i < ids.length; i++) {
        final value = await _put(values[i]);
        accountState(ids[i])._accept(value);
        pending[ids[i]]!.complete(value);
        _changes.add(ids[i]);
      }
    } catch (error, stack) {
      // 失败只返回本次失败；持久快照不清空、不写零，已有页面继续显示最近成功值。
      for (final entry in pending.entries) {
        accountState(entry.key)._fail(error);
        final completer = entry.value;
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    } finally {
      for (final id in ids) {
        _inflight.remove(id);
      }
    }
  }

  Future<CitizenAccountBalance?> read(String accountId) async {
    _requireAccountId(accountId);
    final current = accountState(accountId).value;
    if (current != null) return current;
    final running = _localReads[accountId];
    if (running != null) return running;
    final reading = WalletIsar.instance.read((isar) async {
      final row = await isar.walletAccountBalanceSnapshotEntitys.getByAccountId(
        accountId,
      );
      return _decodeChain(_decodeRecord(row?.payloadJson)['chain'], accountId);
    });
    _localReads[accountId] = reading;
    try {
      final value = await reading;
      // 在途数据库旧读不能覆盖已经刷新完成的内存值。
      final state = accountState(accountId);
      if (state.value == null && value != null) state._accept(value);
      return state.value;
    } finally {
      _localReads.remove(accountId);
    }
  }

  Future<CitizenAccountBalance> _put(CitizenAccountBalance value) async {
    return WalletIsar.instance.writeTxn((isar) async {
      final existing = await isar.walletAccountBalanceSnapshotEntitys
          .getByAccountId(value.accountId);
      final row =
          existing ??
          (WalletAccountBalanceSnapshotEntity()..accountId = value.accountId);
      final record = _decodeRecord(existing?.payloadJson);
      final previous = _decodeChain(record['chain'], value.accountId);
      if (previous != null) {
        if (previous.block.number > value.block.number) return previous;
        if (previous.block.number == value.block.number &&
            previous.block.hash != value.block.hash) {
          throw StateError('同高度 finalized 余额证明冲突');
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      record['chain'] = {
        'account_id': value.accountId,
        'block_hash': value.block.hash,
        'block_number': value.block.number.toString(),
        'free_fen': value.freeFen.toString(),
        'reserved_fen': value.reservedFen.toString(),
        'total_fen': value.totalFen.toString(),
        'updated_at_millis': now,
      };
      row
        ..payloadJson = jsonEncode(record)
        ..updatedAtMillis = now;
      await isar.walletAccountBalanceSnapshotEntitys.putByAccountId(row);
      return value;
    });
  }

  /// 清算行可用余额也由 wallet 拥有；WSS 端点参与键控，切换绑定不能复用另一行余额。
  Future<BigInt> getClearingBalance({
    required String accountId,
    required String ss58Address,
    required String wssUrl,
    bool forceRefresh = false,
  }) async {
    _requireAccountId(accountId);
    final uri = Uri.parse(wssUrl);
    if (uri.scheme != 'wss' || uri.host.isEmpty) {
      throw const FormatException('清算行必须使用 WSS');
    }
    final key = (accountId, wssUrl);
    final state = clearingState(
      accountId: accountId,
      ss58Address: ss58Address,
      wssUrl: wssUrl,
    );
    if (!forceRefresh) {
      if (state.value != null) return state.value!;
      final local = await WalletIsar.instance.read((isar) async {
        final row = await isar.walletAccountBalanceSnapshotEntitys
            .getByAccountId(accountId);
        final values = _decodeRecord(row?.payloadJson)['clearing_balances'];
        final raw = values is Map ? values[wssUrl] : null;
        return raw is String ? BigInt.tryParse(raw) : null;
      });
      if (local != null && local >= BigInt.zero) {
        if (state.value == null) state._accept(local);
        return state.value!;
      }
    }
    final concurrent = _clearingInflight[key];
    if (concurrent != null) return concurrent;
    final result = _refreshClearing(accountId, ss58Address, wssUrl);
    _clearingInflight[key] = result;
    try {
      final value = await result;
      state._accept(value);
      return value;
    } catch (error) {
      state._fail(error);
      rethrow;
    } finally {
      _clearingInflight.remove(key);
    }
  }

  Future<BigInt> _refreshClearing(
    String accountId,
    String ss58Address,
    String wssUrl,
  ) async {
    final raw = await OffchainClearingBankRpc(wssUrl)
        .call('offchain_queryBalance', [ss58Address]);
    final value = (raw is int || raw is String)
        ? BigInt.tryParse(raw.toString())
        : null;
    if (value == null || value < BigInt.zero) {
      throw const FormatException('清算行余额必须为非负整数分');
    }
    await WalletIsar.instance.writeTxn((isar) async {
      final existing = await isar.walletAccountBalanceSnapshotEntitys
          .getByAccountId(accountId);
      final record = _decodeRecord(existing?.payloadJson);
      final values = Map<String, dynamic>.from(
        record['clearing_balances'] as Map? ?? const {},
      );
      values[wssUrl] = value.toString();
      record['clearing_balances'] = values;
      final row =
          existing ??
          (WalletAccountBalanceSnapshotEntity()..accountId = accountId);
      row
        ..payloadJson = jsonEncode(record)
        ..updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
      await isar.walletAccountBalanceSnapshotEntitys.putByAccountId(row);
    });
    _changes.add(accountId);
    return value;
  }

  static Map<String, dynamic> _decodeRecord(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      // 仅保留当前合同；不解释旧的单值 balance_yuan 为 free 或 total。
      return {
        if (decoded['chain'] is Map) 'chain': decoded['chain'],
        if (decoded['clearing_balances'] is Map)
          'clearing_balances': decoded['clearing_balances'],
      };
    } on FormatException {
      return {};
    }
  }

  static CitizenAccountBalance? _decodeChain(Object? raw, String accountId) {
    if (raw is! Map) return null;
    try {
      final value = CitizenAccountBalance(
        accountId: raw['account_id'] as String,
        block: CitizenBlockRef(
          hash: raw['block_hash'] as String,
          number: BigInt.parse(raw['block_number'] as String),
          finality: CitizenBlockFinality.finalized,
        ),
        freeFen: BigInt.parse(raw['free_fen'] as String),
        reservedFen: BigInt.parse(raw['reserved_fen'] as String),
        totalFen: BigInt.parse(raw['total_fen'] as String),
      );
      _validate(value, accountId);
      return value;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on StateError {
      return null;
    }
  }

  static void _validate(CitizenAccountBalance value, String accountId) {
    if (value.accountId != accountId ||
        value.block.finality != CitizenBlockFinality.finalized ||
        !isAccountIdText(value.block.hash) ||
        value.block.number < BigInt.zero ||
        value.freeFen < BigInt.zero ||
        value.reservedFen < BigInt.zero ||
        value.totalFen != value.freeFen + value.reservedFen) {
      throw StateError('账户余额证明或整数分数据不一致');
    }
  }

  static void _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写十六进制账户');
    }
  }
}
