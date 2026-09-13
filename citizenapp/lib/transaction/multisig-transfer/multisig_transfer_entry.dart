import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_page.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_limit_service.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 多签转账入口卡片。
///
/// 转账入口按钮、管理员钱包检查和页面跳转都归 `multisig-transfer`
/// 模块实现，外部页面只负责把当前账户上下文传进来。
class MultisigTransferEntryCard extends StatelessWidget {
  const MultisigTransferEntryCard({
    super.key,
    required this.institution,
    required this.isPersonal,
    required this.enabled,
    required this.loadAdminWallets,
    this.onCreated,
  });

  final InstitutionInfo institution;
  final bool isPersonal;
  final bool enabled;
  final Future<List<CitizenWalletStateAccount>> Function() loadAdminWallets;
  final Future<void> Function()? onCreated;

  @override
  Widget build(BuildContext context) {
    final accentColor = enabled ? AppTheme.primaryDark : AppTheme.textTertiary;
    final subtitle = enabled ? '从当前多签账户发起链上转账' : '账户尚未激活,无法发起转账';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        side: BorderSide(color: accentColor.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        onTap: enabled ? () => _open(context) : null,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaled(context, 14),
                vertical: AppLayout.scaled(context, 12)),
            child: Row(
              children: [
                Container(
                  width: AppLayout.scaled(context, 36),
                  height: AppLayout.scaled(context, 36),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppLayout.scaledValue(10)),
                  ),
                  child: Icon(
                    Icons.send_outlined,
                    size: AppLayout.scaled(context, 18),
                    color: accentColor,
                  ),
                ),
                SizedBox(width: AppLayout.scaled(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '发起转账',
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 15),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryDark,
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
                  size: AppLayout.scaled(context, 20),
                  color: AppTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final wallets = await loadAdminWallets();
    if (!context.mounted || wallets.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到此多签账户的管理员钱包')),
        );
      }
      return;
    }

    final limitService = ProposalLimitService(
      chain: context.read<CitizenSdk>().chain,
    );
    final activeIds = await limitService.fetchActiveProposalIds(institution);
    if (!context.mounted) return;
    if (activeIds.length >= ProposalLimitService.maxActiveProposalsPerSubject) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提案数量已达上限'),
          content: Text(
            '本账户当前有 ${activeIds.length} 个活跃提案，'
            '已达上限 ${ProposalLimitService.maxActiveProposalsPerSubject} 个。'
            '请等待现有提案完成后再发起新提案。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MultisigTransferPage(
          institution: institution,
          icon: isPersonal ? Icons.person : Icons.business,
          badgeColor: isPersonal ? AppTheme.accent : AppTheme.info,
          adminWallets: wallets,
        ),
      ),
    );
    if (created == true && context.mounted) {
      await onCreated?.call();
    }
  }
}
