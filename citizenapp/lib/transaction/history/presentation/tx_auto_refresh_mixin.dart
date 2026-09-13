import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:citizenapp/log/app_log.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';

/// 交易记录展示页共用:订阅某账户在 Isar 里的交易记录变更,后台
/// SDK history 或 finalized 业务投影更新记录后，列表自动重刷——
/// 取代"提交后延时 N 秒盲刷"。子类给出重载动作,mixin 负责订阅/去抖/取消。
///
/// 用法:
/// ```dart
/// class _FooState extends State<Foo> with TxAutoRefreshMixin<Foo> {
///   @override
///   void initState() {
///     super.initState();
///     startTxAutoRefresh(accountId);
///   }
///   @override
///   Future<void> onTxRecordsChanged() => _loadRecords();
///   @override
///   void dispose() {
///     unawaited(stopTxAutoRefresh().catchError((Object _, StackTrace __) {}));
///     super.dispose();
///   }
/// }
/// ```
mixin TxAutoRefreshMixin<T extends StatefulWidget> on State<T> {
  static const Duration _debounce = Duration(milliseconds: 200);

  LocalTxAccountChangeSubscription? _txAutoSub;
  Timer? _txAutoDebounce;
  String? _txAutoAccountId;

  /// 库变更时执行的重载(通常是页面现成的 `_loadXxx`)。
  Future<void> onTxRecordsChanged();

  /// 开始/切换监听指定账户的交易记录变更;账户为空则停止监听。
  /// 重复传同一账户是幂等空操作(不重复订阅)。
  void startTxAutoRefresh(String? accountId) {
    String? normalized;
    try {
      normalized = (accountId == null || accountId.isEmpty)
          ? null
          : LocalTxStore.requireAccountId(accountId);
    } on Object {
      normalized = null;
    }
    if (normalized == _txAutoAccountId && _txAutoSub != null) return;
    _txAutoAccountId = normalized;
    final previous = _txAutoSub;
    _txAutoSub = null;
    if (previous != null) {
      _observeTxAutoFuture(previous.cancel(), '切换账户取消 watcher');
    }
    if (normalized == null) return;
    _txAutoSub = LocalTxStore.listenAccountChanges(normalized, () {
      _txAutoDebounce?.cancel();
      _txAutoDebounce = Timer(_debounce, () {
        if (!mounted) return;
        _observeTxAutoFuture(onTxRecordsChanged(), '交易记录自动刷新');
      });
    });
  }

  /// 停止监听并释放定时器；返回值在原生 watcher 真正释放后完成。
  ///
  /// Flutter 的 `dispose` 无法 `await`，可直接发起本方法；WalletIsar 全量擦除会通过
  /// 已登记的 lease 再次取得同一个取消 Future 并确定性等待。
  Future<void> stopTxAutoRefresh() {
    _txAutoDebounce?.cancel();
    _txAutoDebounce = null;
    final subscription = _txAutoSub;
    _txAutoSub = null;
    _txAutoAccountId = null;
    return subscription?.cancel() ?? Future<void>.value();
  }

  void _observeTxAutoFuture(Future<void> future, String action) {
    unawaited(
      future.catchError((Object error, StackTrace stackTrace) {
        AppLog.d('[TxAutoRefresh] $action 失败: $error\n$stackTrace');
      }),
    );
  }
}
