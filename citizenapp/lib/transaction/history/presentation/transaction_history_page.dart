import 'dart:async';

import 'package:flutter/material.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter/services.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/transaction/history/data/local_tx_store.dart';
import 'package:citizenapp/transaction/history/presentation/tx_auto_refresh_mixin.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({
    super.key,
    required this.ss58Address,
    required this.accountId,
  });

  final String ss58Address;
  final String accountId;

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage>
    with TxAutoRefreshMixin<TransactionHistoryPage> {
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

  List<LocalTxEntity> _records = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
    startTxAutoRefresh(widget.accountId);
  }

  @override
  void dispose() {
    unawaited(
      stopTxAutoRefresh().catchError((Object error, StackTrace stackTrace) {
        AppLog.d('[Wallet] 交易历史 watcher 停止失败: $error\n$stackTrace');
      }),
    );
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await LocalTxStore.queryByAccountId(
        widget.accountId,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _hasMore = records.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore || _records.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final records = await LocalTxStore.queryByAccountId(
        widget.accountId,
        limit: _pageSize,
        offset: _records.length,
      );
      if (!mounted) return;
      setState(() {
        _records = [..._records, ...records];
        _hasMore = records.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      AppLog.d('[TxHistory] 分页加载失败: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// 后台监视器写库后:只重查当前已加载窗口、刷新其状态(如翻已确认),
  /// 不重置分页;空列表时退化为首页加载,拾起新到的第一条。
  @override
  Future<void> onTxRecordsChanged() async {
    if (_records.isEmpty) {
      await _loadFirstPage();
      return;
    }
    try {
      final refreshed = await LocalTxStore.queryByAccountId(
        widget.accountId,
        limit: _records.length,
        offset: 0,
      );
      if (!mounted) return;
      setState(() => _records = refreshed);
    } catch (e) {
      AppLog.d('[TxHistory] 响应式刷新失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('交易记录'),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '加载失败: $_error',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: AppLayout.scaledValue(12),
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(8)),
            TextButton(onPressed: _loadFirstPage, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_records.isEmpty) {
      return const Center(
        child: Text('暂无交易记录', style: TextStyle(color: AppTheme.textTertiary)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: _scrollController,
        itemCount: _records.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _records.length) {
            return Padding(
              padding:
                  EdgeInsets.symmetric(vertical: AppLayout.scaled(context, 16)),
              child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final record = _records[index];
          return LocalTxRecordTile(
            record: record,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LocalTxRecordDetailPage(record: record),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _businessTypeLabel(String type) {
  switch (type) {
    case 'transfer':
      return '转账';
    case 'fee':
      return '手续费';
    case 'reward':
      return '奖励';
    case 'interest':
      return '利息';
    case 'issuance':
      return '增发';
    case 'burn':
      return '资金销毁';
    case 'multisig_transfer':
      return '多签转账';
    default:
      return type;
  }
}

String _sourceLabel(String source) {
  switch (source) {
    case 'local_submit':
      return '本机发起';
    case 'chain_event':
      return '链上事件';
    case 'resync':
      return '后台补同步';
    default:
      return source;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case LocalTxStore.statusPending:
    case LocalTxStore.statusInBlock:
      return '待确认';
    case LocalTxStore.statusFinalized:
      return '已确认';
    case LocalTxStore.statusFailed:
      return '失败';
    default:
      return status;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case LocalTxStore.statusPending:
    case LocalTxStore.statusInBlock:
      return AppTheme.warning;
    case LocalTxStore.statusFinalized:
      return AppTheme.success;
    case LocalTxStore.statusFailed:
      return AppTheme.danger;
    default:
      return AppTheme.textTertiary;
  }
}

String _pad(int n) => n.toString().padLeft(2, '0');

String _formatMillis(int millis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
}

String _formatMillisFull(int millis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
}

String _shortAddress(String? address) {
  if (address == null || address.length <= 12) return address ?? '-';
  return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
}

String _formatFen(String fen, {String symbol = '元'}) {
  return AmountFormat.format(LocalTxStore.fenToYuan(fen).abs(), symbol: symbol);
}

// ─── 交易记录列表项 ──────────────────────────────────────────

class LocalTxRecordTile extends StatelessWidget {
  const LocalTxRecordTile({
    super.key,
    required this.record,
    this.onTap,
    this.showChevron = false,
  });

  final LocalTxEntity record;
  final VoidCallback? onTap;

  /// 钱包详情页最近记录需要显式展示进入详情的箭头；完整列表保持原布局。
  final bool showChevron;

  double get _amountDeltaYuan => LocalTxStore.fenToYuan(record.amountDeltaFen);
  bool get _isExpense => _amountDeltaYuan < 0;
  bool get _isIncome => _amountDeltaYuan > 0;

  Color get _iconColor {
    if (_isExpense) return AppTheme.danger;
    if (_isIncome) return AppTheme.primaryDark;
    return AppTheme.textTertiary;
  }

  Color get _iconBgColor {
    if (_isExpense) return AppTheme.danger.withAlpha(20);
    if (_isIncome) return AppTheme.success.withAlpha(20);
    return AppTheme.surfaceElevated;
  }

  IconData get _icon {
    switch (record.type) {
      case 'reward':
        return Icons.token;
      case 'interest':
        return Icons.account_balance;
      case 'issuance':
        return Icons.gavel;
      case 'fee':
        return Icons.receipt_long;
      case 'burn':
        return Icons.delete_forever;
      case 'multisig_transfer':
        return Icons.groups_2_outlined;
      default:
        return _isExpense ? Icons.arrow_upward : Icons.arrow_downward;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _businessTypeLabel(record.type);
    final counterpartyPrefix = _isExpense ? '去向' : '来自';
    final counterparty = _shortAddress(record.counterpartySs58Address);
    final timeStr =
        _formatMillis(record.confirmedAtMillis ?? record.createdAtMillis);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: AppLayout.scaled(context, 18),
        backgroundColor: _iconBgColor,
        child:
            Icon(_icon, size: AppLayout.scaled(context, 18), color: _iconColor),
      ),
      title: Row(
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: AppLayout.scaled(context, 15),
                fontWeight: FontWeight.w600),
          ),
          SizedBox(width: AppLayout.scaled(context, 6)),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaled(context, 4), vertical: 1),
            decoration: BoxDecoration(
              color: _statusColor(record.status).withAlpha(30),
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(4)),
            ),
            child: Text(
              _statusLabel(record.status),
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 10),
                color: _statusColor(record.status),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '$counterpartyPrefix：$counterparty\n$timeStr',
        style: TextStyle(fontSize: AppLayout.scaled(context, 12), height: 1.5),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_isExpense ? "-" : "+"}${AmountFormat.format(_amountDeltaYuan.abs(), symbol: '')}',
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 15),
              fontWeight: FontWeight.w700,
              color: _iconColor,
            ),
          ),
          if (showChevron) ...[
            SizedBox(width: AppLayout.scaled(context, 4)),
            Icon(
              Icons.chevron_right,
              size: AppLayout.scaled(context, 20),
              color: AppTheme.textTertiary,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 交易详情页 ──────────────────────────────────────────────

class LocalTxRecordDetailPage extends StatelessWidget {
  const LocalTxRecordDetailPage({
    super.key,
    required this.record,
  });

  final LocalTxEntity record;

  double get _amountDeltaYuan => LocalTxStore.fenToYuan(record.amountDeltaFen);
  bool get _isExpense => _amountDeltaYuan < 0;
  bool get _isIncome => _amountDeltaYuan > 0;

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  Widget _buildRow(
    BuildContext context, {
    required String label,
    required String value,
    bool copyable = false,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppLayout.scaled(context, 10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppLayout.scaled(context, 88),
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 14),
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: AppLayout.scaled(context, 14))),
          ),
          if (copyable)
            GestureDetector(
              onTap: () => _copy(context, value),
              child: Padding(
                padding: EdgeInsets.only(left: AppLayout.scaled(context, 8)),
                child: Icon(Icons.copy,
                    size: AppLayout.scaled(context, 16),
                    color: AppTheme.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amountColor = _isExpense
        ? AppTheme.danger
        : _isIncome
            ? AppTheme.primaryDark
            : AppTheme.textSecondary;
    final label = _businessTypeLabel(record.type);

    return Scaffold(
      appBar: AppBar(
        title: const Text('交易详情'),
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        children: [
          Center(
            child: Text(
              '${_isExpense ? "-" : "+"}${AmountFormat.format(_amountDeltaYuan.abs(), symbol: '元')}',
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 28),
                fontWeight: FontWeight.w700,
                color: amountColor,
              ),
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 8)),
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: AppLayout.scaled(context, 8),
                  vertical: AppLayout.scaled(context, 2)),
              decoration: BoxDecoration(
                color: _statusColor(record.status).withAlpha(20),
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(4)),
              ),
              child: Text(
                _statusLabel(record.status),
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 12),
                  color: _statusColor(record.status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 24)),
          const Divider(height: 1),
          _buildRow(context, label: '类型', value: label),
          _buildRow(
            context,
            label: '余额变化',
            value:
                '${_isExpense ? "-" : "+"}${AmountFormat.format(_amountDeltaYuan.abs(), symbol: '元')}',
          ),
          if (record.transferAmountFen != null)
            _buildRow(
              context,
              label: '转账金额',
              value: _formatFen(record.transferAmountFen!),
            ),
          if (record.feeFen != null)
            _buildRow(
              context,
              label: '手续费',
              value: _formatFen(record.feeFen!),
            ),
          if (record.fromSs58Address != null)
            _buildRow(
              context,
              label: '来源地址',
              value: record.fromSs58Address!,
              copyable: true,
            ),
          if (record.toSs58Address != null)
            _buildRow(
              context,
              label: '去向地址',
              value: record.toSs58Address!,
              copyable: true,
            ),
          if (record.counterpartySs58Address != null)
            _buildRow(
              context,
              label: '对方地址',
              value: record.counterpartySs58Address!,
              copyable: true,
            ),
          if (record.remark != null && record.remark!.isNotEmpty)
            _buildRow(
              context,
              label: '转账备注',
              value: record.remark!,
              copyable: true,
            ),
          if (record.txHash != null)
            _buildRow(
              context,
              label: '交易哈希',
              value: record.txHash!,
              copyable: true,
            ),
          if (record.blockNumber != null)
            _buildRow(context, label: '区块号', value: '${record.blockNumber}'),
          if (record.blockHash != null)
            _buildRow(
              context,
              label: '区块哈希',
              value: record.blockHash!,
              copyable: true,
            ),
          if (record.eventIndex != null)
            _buildRow(context, label: '事件序号', value: '${record.eventIndex}'),
          if (record.extrinsicIndex != null)
            _buildRow(
              context,
              label: '交易序号',
              value: '${record.extrinsicIndex}',
            ),
          _buildRow(context, label: '记录来源', value: _sourceLabel(record.source)),
          _buildRow(
            context,
            label: '记录时间',
            value: _formatMillisFull(record.createdAtMillis),
          ),
          if (record.confirmedAtMillis != null)
            _buildRow(
              context,
              label: '最终确认时间',
              value: _formatMillisFull(record.confirmedAtMillis!),
            ),
          if (record.failureReason != null)
            _buildRow(context, label: '失败原因', value: record.failureReason!),
        ],
      ),
    );
  }
}
