import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/log/app_log.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 钱包详情页主视觉中的链上余额区。
///
/// - RPC 查最新块,字段 = `free + reserved`,与 polkadot.js apps 的 total 口径一致。
/// - 不再展示卡内刷新按钮,刷新由外层 [WalletDetailPage] 的 RefreshIndicator
///   下拉触发,通过 [GlobalKey<WalletOnchainBalanceCardState>] 调 [refresh()]。
/// - 与 [WalletIdentityCard] 共用外层纯色面板，单位只在金额行展示一次。
/// - 加载态:金额位显示「— 元」占位。
/// - 错误态:金额位显示「查询失败,点击刷新」,点击触发 [refresh()]。
class WalletOnchainBalanceCard extends StatefulWidget {
  const WalletOnchainBalanceCard({
    super.key,
    required this.wallet,
    this.balanceLoader,
  });

  final CitizenWalletStateAccount wallet;

  /// Widget 测试可注入；正式页面始终从 CitizenSDK finalized 余额接口读取。
  final Future<CitizenAccountBalance> Function(String accountId)? balanceLoader;

  @override
  State<WalletOnchainBalanceCard> createState() =>
      WalletOnchainBalanceCardState();
}

/// State 类公开(去掉下划线)是为了支持外层 [GlobalKey] 引用,
/// 下拉刷新时由 [WalletDetailPage] 通过 key 调 [refresh()]。
class WalletOnchainBalanceCardState extends State<WalletOnchainBalanceCard> {
  /// 查询结果(yuan),null 表示尚未查询或加载中。
  double? _balance;

  /// 最近一次查询是否失败。失败后 `_balance` 可能保留上一次成功的值,但
  /// UI 优先展示错误态并提供刷新入口。
  bool _hasError = false;

  /// 是否正在刷新。用于防止重复触发刷新。
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  /// 拉取链上 finalized total 余额。
  ///
  /// 公开方法,供外层 [WalletDetailPage] 通过 [GlobalKey] 触发下拉刷新。
  Future<void> refresh() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final loader =
          widget.balanceLoader ??
          context.read<CitizenSdk>().chain.getAccountBalance;
      final snapshot = await loader(widget.wallet.accountId);
      final total = snapshot.totalFen.toDouble() / 100;
      if (!mounted) return;
      setState(() {
        _balance = total;
        _isLoading = false;
      });
    } catch (e) {
      AppLog.d(
        '[WalletOnchainBalanceCard] fetchFinalizedTotalBalance failed: $e',
      );
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('wallet-onchain-balance-section'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '链上余额',
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 14),
              fontWeight: FontWeight.w500,
              color: Colors.white.withAlpha(190),
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 8)),
          _buildAmountSection(),
        ],
      ),
    );
  }

  /// 金额区:根据状态切换占位 / 错误提示 / 正常金额。
  Widget _buildAmountSection() {
    // 错误态:点击再次触发刷新。
    if (_hasError && _balance == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          onTap: refresh,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppLayout.scaledValue(44)),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '查询失败，点击刷新',
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(15),
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }
    // 加载态 / 初始态：金额与单位分开排版，确保单位仅出现一次。
    if (_balance == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '—',
            style: TextStyle(
              fontSize: AppLayout.scaledValue(44),
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          SizedBox(width: AppLayout.scaledValue(6)),
          Text(
            '元',
            style: TextStyle(
              fontSize: AppLayout.scaledValue(22),
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ],
      );
    }
    // 正常态：保留系统设置后的实际字号；大额或大字体超出卡片时横向查看，
    // 不使用 FittedBox 把用户主动放大的文字重新缩小。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            AmountFormat.format(_balance!, symbol: ''),
            style: TextStyle(
              fontSize: AppLayout.scaledValue(44),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          SizedBox(width: AppLayout.scaledValue(6)),
          Text(
            '元',
            style: TextStyle(
              fontSize: AppLayout.scaledValue(22),
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
