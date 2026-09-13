import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/ui/app_layout.dart';

// ──── 投票进度组件 ────

/// 提案投票进度条（赞成/反对计数 + 阈值 + 进度条）。
class ProposalVoteProgress extends StatelessWidget {
  const ProposalVoteProgress({
    super.key,
    required this.yesCount,
    required this.noCount,
    required this.threshold,
  });

  final int yesCount;
  final int noCount;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final progress =
        threshold > 0 ? (yesCount / threshold).clamp(0.0, 1.0) : 0.0;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '投票进度',
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 16),
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryDark,
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 12)),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(6)),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: AppLayout.scaled(context, 10),
                backgroundColor: AppTheme.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primaryDark),
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 8)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '赞成 $yesCount / 阈值 $threshold',
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 14),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryDark,
                  ),
                ),
                Text(
                  '反对 $noCount',
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 13),
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──── 合格选民投票明细组件 ────

/// 提案创建时合格选民的投票明细列表（编号地址 + 投票状态标签）。
class ProposalAdminVoteList extends StatelessWidget {
  const ProposalAdminVoteList({
    super.key,
    required this.admins,
    required this.adminVotes,
    required this.pendingPublicKeys,
    this.voterTickets = const [],
    this.proposerSs58,
  });

  /// 合格选民公钥列表（小写 hex，不含 0x）。
  final List<String> admins;

  /// 机构岗位票据；非空时逐票据展示，同一钱包多个岗位各占一行。
  final List<EligibleVoterTicket> voterTickets;

  /// 投票记录：publicKey → true(赞成) / false(反对) / null(未投票)。
  final Map<String, bool?> adminVotes;

  /// 已提交但尚未上链确认的选民公钥集合。
  final Set<String> pendingPublicKeys;

  /// 发起人的 SS58 地址（可选，用于显示"发起人"徽章）。
  final String? proposerSs58;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppLayout.scaled(context, 8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '合格投票票据明细（共 ${voterTickets.isEmpty ? admins.length : voterTickets.length} 票）',
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 16),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryDark,
                ),
              ),
            ),
            const Divider(),
            ...List.generate(
                voterTickets.isEmpty ? admins.length : voterTickets.length,
                (index) {
              final ticket = voterTickets.isEmpty ? null : voterTickets[index];
              final accountId = ticket?.voterAccountId ?? admins[index];
              final vote = adminVotes[ticket?.ticketKey ?? accountId];
              final ss58 = _publicKeyToSS58(accountId);
              final isProposer = proposerSs58 != null && proposerSs58 == ss58;

              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: AppLayout.scaled(context, 16),
                  backgroundColor: AppTheme.primaryDark.withValues(alpha: 0.08),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 12),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _truncateAddress(ss58),
                        style:
                            TextStyle(fontSize: AppLayout.scaled(context, 13)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ticket?.voterRoleCode != null) ...[
                      SizedBox(width: AppLayout.scaled(context, 6)),
                      Text(
                        ticket!.voterRoleCode!,
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 10),
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                    if (isProposer) ...[
                      SizedBox(width: AppLayout.scaled(context, 6)),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: AppLayout.scaled(context, 6),
                            vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(AppLayout.scaledValue(8)),
                        ),
                        child: Text(
                          '发起人',
                          style: TextStyle(
                            fontSize: AppLayout.scaled(context, 10),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: _buildVoteStatusChip(
                  vote,
                  ticket?.ticketKey ?? accountId,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildVoteStatusChip(bool? vote, String publicKey) {
    if (vote == true) {
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(8),
            vertical: AppLayout.scaledValue(2)),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
        ),
        child: Text(
          '赞成 \u2713',
          style: TextStyle(
            fontSize: AppLayout.scaledValue(12),
            fontWeight: FontWeight.w600,
            color: AppTheme.success,
          ),
        ),
      );
    } else if (vote == false) {
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(8),
            vertical: AppLayout.scaledValue(2)),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
        ),
        child: Text(
          '反对 \u2717',
          style: TextStyle(
            fontSize: AppLayout.scaledValue(12),
            fontWeight: FontWeight.w600,
            color: AppTheme.danger,
          ),
        ),
      );
    } else if (pendingPublicKeys.contains(publicKey)) {
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(8),
            vertical: AppLayout.scaledValue(2)),
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: AppLayout.scaledValue(10),
              height: AppLayout.scaledValue(10),
              child: const CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppTheme.warning,
              ),
            ),
            SizedBox(width: AppLayout.scaledValue(4)),
            Text(
              '投票中',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(12),
                fontWeight: FontWeight.w600,
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(8),
            vertical: AppLayout.scaledValue(2)),
        decoration: BoxDecoration(
          color: AppTheme.textTertiary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
        ),
        child: Text(
          '未投票 -',
          style: TextStyle(
            fontSize: AppLayout.scaledValue(12),
            fontWeight: FontWeight.w500,
            color: AppTheme.textTertiary,
          ),
        ),
      );
    }
  }
}

// ──── 底部投票操作组件 ────

/// 底部投票操作栏（钱包选择 + 赞成/反对按钮）。
///
/// 通过 [onVote] 回调通知父页面投票意向，父页面自行处理确认对话框和提交逻辑。
class ProposalVoteActions extends StatelessWidget {
  const ProposalVoteActions({
    super.key,
    required this.votableWallets,
    required this.selectedWallet,
    required this.submitting,
    required this.canVote,
    required this.allVoted,
    required this.onWalletChanged,
    required this.onVote,
  });

  final List<CitizenWalletStateAccount> votableWallets;
  final CitizenWalletStateAccount? selectedWallet;
  final bool submitting;
  final bool canVote;
  final bool allVoted;
  final ValueChanged<CitizenWalletStateAccount?> onWalletChanged;

  /// 投票回调：true=赞成，false=反对。
  final ValueChanged<bool> onVote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.textPrimary.withValues(alpha: 0.06),
            blurRadius: AppLayout.scaled(context, 8),
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 多管理员时显示钱包选择器
          if (votableWallets.length > 1)
            Padding(
              padding: EdgeInsets.only(bottom: AppLayout.scaled(context, 10)),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: AppLayout.scaled(context, 12)),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
                  border: Border.all(
                      color: AppTheme.success.withValues(alpha: 0.2)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: selectedWallet?.walletIndex,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down,
                        color: AppTheme.primaryDark),
                    items: votableWallets.map((w) {
                      return DropdownMenuItem<int>(
                        value: w.walletIndex,
                        child: Row(
                          children: [
                            Icon(Icons.verified_user,
                                size: AppLayout.scaled(context, 14),
                                color: AppTheme.success),
                            SizedBox(width: AppLayout.scaled(context, 6)),
                            Expanded(
                              child: Text(
                                _truncateWalletAddress(w.ss58Address),
                                style: TextStyle(
                                  fontSize: AppLayout.scaled(context, 13),
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (index) {
                      if (index == null) return;
                      final wallet = votableWallets
                          .firstWhere((w) => w.walletIndex == index);
                      onWalletChanged(wallet);
                    },
                  ),
                ),
              ),
            ),
          if (allVoted)
            Padding(
              padding: EdgeInsets.only(bottom: AppLayout.scaled(context, 10)),
              child: Text(
                '你已导入的合格投票钱包均已投票',
                style: TextStyle(
                    fontSize: AppLayout.scaled(context, 13),
                    color: AppTheme.textTertiary),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      (submitting || !canVote) ? null : () => onVote(false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        canVote ? AppTheme.danger : AppTheme.border,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        vertical: AppLayout.scaled(context, 14)),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppLayout.scaledValue(10)),
                    ),
                    elevation: 0,
                  ),
                  child: submitting
                      ? SizedBox(
                          width: AppLayout.scaled(context, 20),
                          height: AppLayout.scaled(context, 20),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '反对',
                          style: TextStyle(
                              fontSize: AppLayout.scaled(context, 16),
                              fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              SizedBox(width: AppLayout.scaled(context, 16)),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      (submitting || !canVote) ? null : () => onVote(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppTheme.success.withValues(alpha: 0.25),
                    padding: EdgeInsets.symmetric(
                        vertical: AppLayout.scaled(context, 14)),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppLayout.scaledValue(10)),
                    ),
                    elevation: 0,
                  ),
                  child: submitting
                      ? SizedBox(
                          width: AppLayout.scaled(context, 20),
                          height: AppLayout.scaled(context, 20),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '赞成',
                          style: TextStyle(
                              fontSize: AppLayout.scaled(context, 16),
                              fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _truncateWalletAddress(String address) {
    if (address.length <= 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 8)}';
  }
}

// ──── 状态徽章组件 ────

/// 提案状态徽章（投票中/已通过/已拒绝/已执行）。
class ProposalStatusBadge extends StatelessWidget {
  const ProposalStatusBadge({
    super.key,
    required this.status,
    required this.proposalId,
  });

  final int? status;
  final int proposalId;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.proposalStatusColor(status ?? -1);
    final label = _statusLabel(status);

    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaled(context, 12),
              vertical: AppLayout.scaled(context, 6)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppLayout.scaledValue(20)),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                status == 0
                    ? Icons.how_to_vote
                    : status == 1
                        ? Icons.check_circle
                        : status == 2
                            ? Icons.cancel
                            : status == 3
                                ? Icons.check_circle
                                : status == 4
                                    ? Icons.error_outline
                                    : Icons.error,
                size: AppLayout.scaled(context, 16),
                color: color,
              ),
              SizedBox(width: AppLayout.scaled(context, 4)),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 14),
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text(
          '提案 #$proposalId',
          style: TextStyle(
              fontSize: AppLayout.scaled(context, 13),
              color: AppTheme.textTertiary),
        ),
      ],
    );
  }

  static String _statusLabel(int? status) {
    switch (status) {
      case 0:
        return '投票中';
      case 1:
        return '已通过';
      case 2:
        return '已拒绝';
      case 3:
        return '已执行';
      case 4:
        return '执行失败';
      default:
        return '未知';
    }
  }
}

// ──── 共享工具 ────

String _publicKeyToSS58(String publicKey) {
  final hex = publicKey.startsWith('0x') ? publicKey.substring(2) : publicKey;
  final bytes = _hexDecode(hex);
  return Keyring().encodeAddress(bytes, kGmbSs58Prefix);
}

Uint8List _hexDecode(String hex) {
  final h = hex.startsWith('0x') ? hex.substring(2) : hex;
  final result = Uint8List(h.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

String _truncateAddress(String address) {
  if (address.length <= 14) return address;
  return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
}
