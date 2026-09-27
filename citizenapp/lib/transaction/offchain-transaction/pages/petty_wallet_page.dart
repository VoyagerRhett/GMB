import 'dart:async';

import 'package:provider/provider.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/wallet/account_balance_snapshot_store.dart';
import 'package:flutter/material.dart';

import 'package:citizenapp/transaction/offchain-transaction/pages/deposit_page.dart';
import 'package:citizenapp/transaction/offchain-transaction/pages/withdraw_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 零钱包详情页(链下清算行零钱包)。
///
/// 从账户详情「零钱包」按钮进入。承接原动作卡上的「充值到清算行」入口,并提供:
/// - 零钱包余额(节点端 `offchain_queryBalance`);
/// - 充值到清算行(链上账户 → 清算行零钱包,原 `DepositPage`);
/// - 提现到链上(清算行 → 链上账户,`WithdrawPage`)。
/// 一律按 `account_id` 键控,单钱包多账户下每账户独立零钱包。
class PettyWalletPage extends StatefulWidget {
  const PettyWalletPage({
    super.key,
    required this.accountId,
    required this.ss58Address,
    required this.wssUrl,
    required this.displayTitle,
  });

  /// 该账户链账户主键(0x+64hex)。
  final String accountId;

  /// 该账户 SS58 地址,用于查询零钱包余额。
  final String ss58Address;
  final String wssUrl;
  final String displayTitle;

  @override
  State<PettyWalletPage> createState() => _PettyWalletPageState();
}

class _PettyWalletPageState extends State<PettyWalletPage> {
  late WalletBalanceState<BigInt> _balance;

  String get _balanceText {
    final value = _balance.value;
    if (value != null) {
      return '¥${AccountBalanceSnapshotStore.formatFen(value)}';
    }
    return _balance.hasError ? '节点不可达' : '查询中';
  }

  @override
  void initState() {
    super.initState();
    _balance =
        AccountBalanceSnapshotStore.forChain(context.read<CitizenSdk>().chain)
            .clearingState(
              accountId: widget.accountId,
              ss58Address: widget.ss58Address,
              wssUrl: widget.wssUrl,
            )
          ..addListener(_changed);
    unawaited(_loadBalance());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _balance.removeListener(_changed);
    super.dispose();
  }

  // 返回和下拉只通知 wallet 唯一状态，不另存零钱包金额。
  Future<void> _loadBalance({bool forceRefresh = false}) =>
      _balance.load(forceRefresh: forceRefresh);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('零钱包'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () => _loadBalance(forceRefresh: true),
        child: ListView(
          padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Container(
              padding: EdgeInsets.all(AppLayout.scaled(context, 20)),
              decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.displayTitle,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 13),
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 10)),
                  Text(
                    _balanceText,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 28),
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 4)),
                  Text(
                    '零钱包余额（链下清算行）',
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 12),
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 16)),
            _ActionTile(
              icon: Icons.arrow_circle_down_outlined,
              title: '充值到清算行',
              subtitle: '从链上账户转入清算行零钱包',
              onTap: _openDeposit,
            ),
            SizedBox(height: AppLayout.scaled(context, 12)),
            _ActionTile(
              icon: Icons.arrow_circle_up_outlined,
              title: '提现到链上',
              subtitle: '从零钱包提现回链上账户',
              onTap: _openWithdraw,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDeposit() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DepositPage(
          accountId: widget.accountId,
          ss58Address: widget.ss58Address,
        ),
      ),
    );
    await _loadBalance(forceRefresh: submitted == true);
  }

  Future<void> _openWithdraw() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WithdrawPage(
          accountId: widget.accountId,
          ss58Address: widget.ss58Address,
          wssUrl: widget.wssUrl,
        ),
      ),
    );
    await _loadBalance(forceRefresh: submitted == true);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
          decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
          child: Row(
            children: [
              Container(
                width: AppLayout.scaled(context, 44),
                height: AppLayout.scaled(context, 44),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: AppLayout.scaled(context, 22),
                  color: AppTheme.primaryDark,
                ),
              ),
              SizedBox(width: AppLayout.scaled(context, 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppLayout.scaled(context, 16),
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: AppLayout.scaled(context, 2)),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppLayout.scaled(context, 12),
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: AppLayout.scaled(context, 18),
                color: AppTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
