import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_activation_service.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/institution_admin_service.dart';
import 'package:citizenapp/citizen/institution/institution_assignment_card.dart';
import 'package:citizenapp/citizen/institution/institution_role_models.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 管理员列表页面。
///
/// 展示机构所有管理员的完整 SS58 地址，支持 QR 扫码激活。
class AdminListPage extends StatefulWidget {
  const AdminListPage({
    super.key,
    required this.institution,
    required this.accountIdentity,
    required this.admins,
    required this.importedColdAccountIds,
    required this.activatedAccountIds,
    required this.badgeColor,
    this.onActivated,
  });

  final InstitutionInfo institution;
  final AdminAccountIdentity accountIdentity;

  /// 机构管理员人员视图；同一管理员的多个岗位归在同一人员行。
  final List<InstitutionAdminView> admins;

  /// 用户已导入冷钱包的规范 AccountId 集合。
  final Set<String> importedColdAccountIds;

  /// 已激活管理员的规范 AccountId 集合。
  final Set<String> activatedAccountIds;
  final Color badgeColor;

  /// 激活成功后的回调（通知父页面刷新）。
  final VoidCallback? onActivated;

  @override
  State<AdminListPage> createState() => _AdminListPageState();
}

class _AdminListPageState extends State<AdminListPage> {
  late Set<String> _activatedAccountIds;
  Map<String, double> _balanceByAccountId = const {};

  @override
  void initState() {
    super.initState();
    _activatedAccountIds = Set.of(widget.activatedAccountIds);
    unawaited(_loadBalances());
  }

  @override
  void didUpdateWidget(covariant AdminListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.admins != widget.admins) {
      unawaited(_loadBalances());
    }
  }

  static String _balanceKey(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  Future<void> _loadBalances() async {
    final accountIds = {
      for (final view in widget.admins) _balanceKey(view.admin.account_id),
    }.where((accountId) => accountId.isNotEmpty).toList(growable: false);
    if (accountIds.isEmpty) {
      if (mounted) setState(() => _balanceByAccountId = const {});
      return;
    }
    try {
      final snapshots = await context
          .read<CitizenSdk>()
          .chain
          .getAccountBalances(accountIds);
      final balances = <String, double>{
        for (final snapshot in snapshots)
          snapshot.accountId: snapshot.freeFen.toDouble() / 100,
      };
      if (!mounted) return;
      setState(() => _balanceByAccountId = balances);
    } catch (_) {
      // 余额展示失败不影响管理员激活流程,卡片保留“余额”标签且值为空。
      if (mounted) setState(() => _balanceByAccountId = const {});
    }
  }

  void _onAdminActivated(String accountId) {
    setState(() {
      _activatedAccountIds.add(accountId);
    });
    widget.onActivated?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '管理员列表',
          style: TextStyle(
            fontSize: AppLayout.scaled(context, 17),
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 机构信息
          _buildInstitutionHeader(),
          SizedBox(height: AppLayout.scaled(context, 16)),
          // 管理员总数
          Text(
            '共 ${widget.admins.length} 位管理员　通过阈值 ${widget.institution.internalThreshold}',
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 13),
              color: AppTheme.textTertiary,
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 12)),
          // 管理员列表
          if (widget.admins.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: AppLayout.scaled(context, 24),
              ),
              child: Center(
                child: Text(
                  '暂无管理员信息',
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 14),
                    color: AppTheme.textTertiary,
                  ),
                ),
              ),
            )
          else
            ...List.generate(widget.admins.length, (index) {
              final adminView = widget.admins[index];
              final accountId = adminView.admin.account_id;
              final isImported = widget.importedColdAccountIds.contains(
                accountId,
              );
              final isActivated = _activatedAccountIds.contains(accountId);
              return _AdminTile(
                index: index + 1,
                adminView: adminView,
                isImported: isImported,
                isActivated: isActivated,
                institution: widget.institution,
                accountIdentity: widget.accountIdentity,
                onActivated: () => _onAdminActivated(accountId),
                balanceYuan: _balanceByAccountId[_balanceKey(accountId)],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildInstitutionHeader() {
    return Row(
      children: [
        Container(
          width: AppLayout.scaledValue(36),
          height: AppLayout.scaledValue(36),
          decoration: BoxDecoration(
            color: widget.badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
          ),
          child: Icon(
            Icons.people_outline,
            size: AppLayout.scaledValue(18),
            color: widget.badgeColor,
          ),
        ),
        SizedBox(width: AppLayout.scaledValue(10)),
        Expanded(
          child: Text(
            widget.institution.cidShortName,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(15),
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(8),
            vertical: AppLayout.scaledValue(2),
          ),
          decoration: BoxDecoration(
            color: widget.badgeColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
          ),
          child: Text(
            OrgType.label(widget.institution.orgType),
            style: TextStyle(
              fontSize: AppLayout.scaledValue(11),
              color: widget.badgeColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({
    required this.index,
    required this.adminView,
    required this.isImported,
    required this.isActivated,
    required this.institution,
    required this.accountIdentity,
    required this.onActivated,
    required this.balanceYuan,
  });

  final int index;

  final InstitutionAdminView adminView;

  /// 管理员规范 AccountId；激活和匹配只按账户 ID。
  String get accountId => adminView.admin.account_id;

  /// 用户是否已导入此账户 ID 的冷钱包。
  final bool isImported;

  /// 此管理员是否已激活。
  final bool isActivated;
  final InstitutionInfo institution;
  final AdminAccountIdentity accountIdentity;
  final VoidCallback onActivated;
  final double? balanceYuan;

  Future<void> _startActivation(BuildContext context) async {
    // 检查是否为冷钱包（热钱包不允许激活）
    final wallets =
        (await context.read<CitizenSdk>().wallet.getState()).accounts;
    final wallet = wallets.where((w) {
      return w.accountId == accountId;
    }).firstOrNull;

    if (wallet == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未找到对应钱包')));
      return;
    }

    if (wallet.signMode != CitizenWalletSignMode.cold) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('管理员仅支持冷钱包激活')));
      return;
    }
    if (!context.mounted) return;
    final sdk = context.read<CitizenSdk>();

    // App 构造业务 payload；SDK 负责冷热账户签名与 QR_V1 会话。
    final activationService = ActivationService(
      adminService: InstitutionAdminService(chain: sdk.chain),
    );
    final payload = activationService.buildActivationPayload(
      accountId: accountId,
      identity: accountIdentity,
    );

    if (!context.mounted) return;
    await signCitizenPayload(
      signing: sdk.signing,
      context: context,
      accountId: accountId,
      payload: payload,
      action: QrActions.activateAdmin,
    );
    if (!context.mounted) return;

    // 验证并存储激活记录
    try {
      await activationService.activate(
        accountId: accountId,
        identity: accountIdentity,
      );
      onActivated();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('管理员激活成功')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('激活失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppLayout.scaled(context, 6)),
      child: InstitutionAssignmentCard(
        adminView: adminView,
        index: index,
        balanceYuan: balanceYuan,
        trailing: _buildActivationControl(context),
      ),
    );
  }

  Widget? _buildActivationControl(BuildContext context) {
    // 激活按钮：仅对已导入冷钱包的管理员显示。
    if (!isImported) return null;
    if (isActivated) {
      return Container(
        height: InstitutionAssignmentCard.actionHeight,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 8),
          vertical: AppLayout.scaled(context, 4),
        ),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
        ),
        child: Text(
          '已激活',
          style: TextStyle(
            fontSize: AppLayout.scaled(context, 11),
            color: AppTheme.success,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _startActivation(context),
      child: Container(
        height: InstitutionAssignmentCard.actionHeight,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 8),
          vertical: AppLayout.scaled(context, 4),
        ),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
        ),
        child: Text(
          '激活',
          style: TextStyle(
            fontSize: AppLayout.scaled(context, 11),
            color: AppTheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
