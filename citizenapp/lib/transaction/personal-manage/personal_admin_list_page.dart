// 个人多签管理员列表页(req 1+2)。
//
// 从详情页"管理员列表"卡片折叠入口跳转进来,展示该多签的所有管理员,并按
// admin 投票状态渲染三态激活按钮:
//
//   - 创建者:无按钮(创建即同意)
//   - 非本钱包成员:无按钮(仅展示)
//   - 本钱包未投 + 多签 Pending:蓝色"激活"(可点)→ 跳 MultisigProposalDetailPage
//   - 本钱包已投赞成:灰色"已激活"(禁用)
//   - 本钱包已投反对:灰色"已拒绝"(禁用)
//   - 多签 Active:无按钮(创建已完成)
//
// "激活"行为本质是 votingengine `internal_vote(proposal_id, approve=true)`,
// 沿用现有 [MultisigProposalDetailPage] 的 AppBusinessQrCodec 签名 + InternalVoteService 投票流程,
// 不引入新的签名逻辑。

import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_context.dart';
import 'package:citizenapp/citizen/shared/institution_manage_detail_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'personal_manage_models.dart';
import 'personal_pending_create_lookup.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 管理员行的激活按钮渲染状态。
enum _ActivateButtonState {
  /// 不显示按钮(创建者 / 非本钱包成员 / 多签已激活)。
  hidden,

  /// 蓝色"激活"可点(本钱包成员且未投票且多签待激活)。
  ready,

  /// 灰色"已激活"禁用(本钱包成员已投赞成)。
  alreadyApproved,

  /// 灰色"已拒绝"禁用(本钱包成员已投反对)。
  alreadyRejected,
}

class PersonalAdminListPage extends StatefulWidget {
  const PersonalAdminListPage({
    super.key,
    required this.institution,
    required this.multisigStatus,
    required this.admins,
    required this.adminWallets,
    this.creatorAccountId,
  });

  /// 多签元信息(名称 / 多签账户 / cidNumber 等)。
  final InstitutionInfo institution;

  /// 多签当前状态(Pending / Active)。
  final MultisigStatus multisigStatus;

  /// 完整管理员人员集合；权限和投票匹配只使用 `account_id`。
  final List<AdminPerson> admins;

  /// 用户本地能签名的 admin 钱包子集(由调用方过滤好)。
  final List<CitizenWalletStateAccount> adminWallets;

  /// 创建人规范 AccountId。req 3 未实现时只有创建者本机已知。
  final String? creatorAccountId;

  @override
  State<PersonalAdminListPage> createState() => _PersonalAdminListPageState();
}

class _PersonalAdminListPageState extends State<PersonalAdminListPage> {
  static final _keyring = Keyring();

  late final ProposalQueryService _proposalService;
  bool _dependenciesReady = false;
  final PersonalPendingCreateLookup _lookup = PersonalPendingCreateLookup();

  bool _loading = true;
  String? _error;
  int? _proposalId;
  Map<String, bool?> _votes = const {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _proposalService = ProposalQueryService(
      chain: context.read<CitizenSdk>().chain,
    );
    _dependenciesReady = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 多签已激活时无需查投票:激活按钮整体不显示。
      if (widget.multisigStatus != MultisigStatus.pending) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _proposalId = null;
          _votes = const {};
        });
        return;
      }

      final pid = await _lookup.findActiveCreate(
        widget.institution.personalAccountId,
      );

      // 仅查本钱包持有的 admin 投票状态(其他人投票状态对 UI 无意义,节省 RPC)。
      final votes = <String, bool?>{};
      if (pid != null) {
        // 本机可能导入多个管理员钱包，用批量 storage 查询避免逐钱包 RPC。
        votes.addAll(await _proposalService.fetchAdminVotesBatch(
          pid,
          widget.adminWallets.map((wallet) => wallet.accountId),
        ));
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _proposalId = pid;
        _votes = votes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  _ActivateButtonState _resolveButtonState(String adminAccountId) {
    // 多签已激活 → 全部隐藏
    if (widget.multisigStatus != MultisigStatus.pending) {
      return _ActivateButtonState.hidden;
    }
    // 创建者 → 隐藏(创建即同意)
    if (widget.creatorAccountId != null &&
        widget.creatorAccountId!.toLowerCase() == adminAccountId) {
      return _ActivateButtonState.hidden;
    }
    // 非本钱包持有的 admin → 隐藏(本机不能代签)
    final isLocalWallet = widget.adminWallets.any((w) {
      return w.accountId == adminAccountId;
    });
    if (!isLocalWallet) return _ActivateButtonState.hidden;
    // 找不到活跃创建提案(异常态)→ 不显示按钮
    if (_proposalId == null) return _ActivateButtonState.hidden;
    final vote = _votes[adminAccountId];
    if (vote == null) return _ActivateButtonState.ready;
    return vote
        ? _ActivateButtonState.alreadyApproved
        : _ActivateButtonState.alreadyRejected;
  }

  Future<void> _onActivatePressed() async {
    final pid = _proposalId;
    if (pid == null) return;
    final pushed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultisigProposalDetailPage(
          institution: widget.institution,
          proposalId: pid,
          proposalContext: ProposalContext(
            institution: widget.institution,
            adminWallets: widget.adminWallets,
            role: ProposalRole.admin,
          ),
        ),
      ),
    );
    if (pushed == true && mounted) {
      // 投票完成 → 重读投票状态(可能本行变成"已激活")
      await _load();
    }
  }

  // ──── UI ────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '管理员列表',
          style: TextStyle(
              fontSize: AppLayout.scaled(context, 17),
              fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: EdgeInsets.all(AppLayout.scaledValue(24)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: AppLayout.scaledValue(36), color: AppTheme.textTertiary),
          SizedBox(height: AppLayout.scaledValue(12)),
          Text(_error!,
              style: const TextStyle(color: AppTheme.textSecondary),
              textAlign: TextAlign.center),
          SizedBox(height: AppLayout.scaledValue(16)),
          OutlinedButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildHeaderCard(),
          SizedBox(height: AppLayout.scaledValue(16)),
          _buildAdminListCard(),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(16)),
        child: Row(
          children: [
            const Icon(Icons.person, color: AppTheme.accent),
            SizedBox(width: AppLayout.scaledValue(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.institution.cidShortName,
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(15),
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaledValue(2)),
                  Text(
                    widget.multisigStatus == MultisigStatus.active
                        ? '已激活 · ${widget.admins.length} 位管理员'
                        : '待激活 · ${widget.admins.length} 位管理员需逐一签名',
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(12),
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminListCard() {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Column(
        children: List.generate(widget.admins.length, (index) {
          final admin = widget.admins[index];
          final accountId = admin.account_id;
          final ss58 = _accountIdToSs58(accountId);
          final isCreator = widget.creatorAccountId != null &&
              widget.creatorAccountId!.toLowerCase() == accountId;
          final state = _resolveButtonState(accountId);
          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  radius: AppLayout.scaledValue(16),
                  backgroundColor: AppTheme.primaryDark.withValues(alpha: 0.08),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(12),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
                title: Text(
                  '${admin.family_name}${admin.given_name}',
                ),
                subtitle: Text(
                  isCreator ? '$ss58\n创建者' : ss58,
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(11),
                    fontFamily: 'monospace',
                    color: isCreator ? AppTheme.accent : null,
                  ),
                ),
                trailing: _buildActivateButton(state),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget? _buildActivateButton(_ActivateButtonState state) {
    switch (state) {
      case _ActivateButtonState.hidden:
        return null;
      case _ActivateButtonState.ready:
        return TextButton(
          onPressed: _onActivatePressed,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryDark,
            backgroundColor: AppTheme.primaryDark.withValues(alpha: 0.08),
            padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaledValue(14),
                vertical: AppLayout.scaledValue(6)),
            minimumSize: Size(0, AppLayout.scaledValue(32)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child:
              Text('激活', style: TextStyle(fontSize: AppLayout.scaledValue(13))),
        );
      case _ActivateButtonState.alreadyApproved:
        return const _DisabledTag(label: '已激活');
      case _ActivateButtonState.alreadyRejected:
        return const _DisabledTag(label: '已拒绝');
    }
  }

  /// 把规范 AccountId 编码为 GMB SS58 地址(prefix 走 kGmbSs58Prefix 单源),并做两端截断
  /// 以适配 monospace 11 字号的 ListTile title 行宽。
  ///
  /// 编码失败(理论上不会发生,数据来自链上 storage)兜底返回原 AccountId。
  String _accountIdToSs58(String accountId) {
    try {
      if (!isAccountIdText(accountId)) {
        throw const FormatException('account_id 格式错误');
      }
      final hex = accountId.substring(2);
      final bytes = Uint8List(hex.length ~/ 2);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
      final ss58 = _keyring.encodeAddress(bytes, kGmbSs58Prefix);
      if (ss58.length <= 24) return ss58;
      return '${ss58.substring(0, 12)}…${ss58.substring(ss58.length - 8)}';
    } catch (_) {
      return accountId;
    }
  }
}

class _DisabledTag extends StatelessWidget {
  const _DisabledTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 10),
          vertical: AppLayout.scaled(context, 4)),
      decoration: BoxDecoration(
        color: AppTheme.textTertiary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppLayout.scaled(context, 12),
          color: AppTheme.textTertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
