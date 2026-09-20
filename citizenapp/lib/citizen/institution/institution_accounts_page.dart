import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/institution/institution.dart';
import 'package:citizenapp/citizen/institution/institution_accounts.dart';
import 'package:citizenapp/citizen/institution/institution_chain_state.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 统一机构「全部账户」页(ADR-028 决策 2)——替代公权/治理两套账户页。
///
/// 账户行由 [institutionAccountIdRows] 统一构造(固定治理档用 china 固定
/// 账户、普通机构本地派生);余额经统一链态服务批量补(ADR-018 R2 精确整键批量)。
class InstitutionAccountsPage extends StatefulWidget {
  const InstitutionAccountsPage({
    super.key,
    required this.institution,
    required this.chainState,
  });

  final Institution institution;
  final InstitutionChainState chainState;

  @override
  State<InstitutionAccountsPage> createState() =>
      _InstitutionAccountsPageState();
}

class _InstitutionAccountsPageState extends State<InstitutionAccountsPage> {
  late List<InstitutionAccountRow> _rows =
      institutionAccountIdRows(widget.institution);
  bool _balanceLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBalances();
  }

  Future<void> _loadBalances() async {
    try {
      final balances = await widget.chainState
          .balances(_rows.map((r) => r.accountId).toList());
      if (!mounted) return;
      setState(() {
        _rows = _rows
            .map((r) => r.withBalance(balances[r.accountId]))
            .toList(growable: false);
        _balanceLoading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _balanceLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('全部账户'),
        backgroundColor: AppTheme.surfaceCard,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        itemCount: _rows.length,
        separatorBuilder: (_, _) =>
            SizedBox(height: AppLayout.scaled(context, 10)),
        itemBuilder: (context, i) => _AccountCard(
          row: _rows[i],
          balanceLoading: _balanceLoading,
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.row, required this.balanceLoading});

  final InstitutionAccountRow row;
  final bool balanceLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppLayout.scaled(context, 14)),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(row.label,
                  style: TextStyle(
                      fontSize: AppLayout.scaled(context, 14),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              Text(
                balanceLoading
                    ? '—'
                    : (row.balanceYuan == null
                        ? '未激活'
                        : '${AmountFormat.formatThousands(row.balanceYuan)} 元'),
                style: TextStyle(
                    fontSize: AppLayout.scaled(context, 13.5),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary),
              ),
            ],
          ),
          SizedBox(height: AppLayout.scaled(context, 6)),
          Text(row.ss58Address,
              style: TextStyle(
                  fontSize: AppLayout.scaled(context, 11.5),
                  color: AppTheme.textTertiary)),
        ],
      ),
    );
  }
}
