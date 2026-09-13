import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/votingengine/internal-vote/proposal_vote_widgets.dart';
import 'package:citizenapp/votingengine/legislation-vote/legislation_vote_query_service.dart';
import 'package:citizenapp/votingengine/legislation-vote/legislation_vote_service.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 立法提案表决页(LegislationVote sub-pallet)。
///
/// 按提案当前阶段渲染对应动作——代表机构表决 / 行政签署 / 三人会签 /
/// 护宪终审,均为纯 extrinsic(signer=origin),走标准交易签名 + 冷钱包 QR。
/// 特别案公投(referendum 阶段)走公民 CID 凭证流程(citizen 投票入口),本页只提示。
/// 发起立法不在手机端(见 legislation_intro_page,类B)。
class LegislationVotePage extends StatefulWidget {
  const LegislationVotePage({
    super.key,
    required this.proposalId,
    required this.adminWallets,
    this.voteService,
    this.queryService,
  });

  final int proposalId;

  /// 当前公民登录态下可用于签名的管理员钱包(由上层注入)。
  final List<CitizenWalletStateAccount> adminWallets;

  final LegislationVoteService? voteService;
  final LegislationVoteQueryService? queryService;

  @override
  State<LegislationVotePage> createState() => _LegislationVotePageState();
}

class _LegislationVotePageState extends State<LegislationVotePage> {
  late final LegislationVoteService _vote;
  late final LegislationVoteQueryService _query;
  bool _dependenciesReady = false;

  LegProposalState? _state;
  LegRepresentativeMeta? _representativeMeta;
  LegislationMeta? _legislationMeta;
  ({int yes, int no}) _representativeTally = (yes: 0, no: 0);
  ({int yes, int no}) _referendumTally = (yes: 0, no: 0);

  List<CitizenWalletStateAccount> _votableWallets = const [];
  CitizenWalletStateAccount? _selectedWallet;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.voteService != null && widget.queryService != null) {
      _vote = widget.voteService!;
      _query = widget.queryService!;
      _dependenciesReady = true;
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final sdk = context.read<CitizenSdk>();
    _vote =
        widget.voteService ??
        LegislationVoteService(
          chain: sdk.chain,
          transactions: sdk.transactions,
        );
    _query =
        widget.queryService ?? LegislationVoteQueryService(chain: sdk.chain);
    _dependenciesReady = true;
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final state = await _query.fetchProposalState(widget.proposalId);
      final representativeMeta = await _query.fetchRepresentativeMeta(
        widget.proposalId,
      );
      final legislationMeta = await _query.fetchLegislationMeta(
        widget.proposalId,
      );
      final representativeTally = representativeMeta == null
          ? (yes: 0, no: 0)
          : await _query.fetchRepresentativeTally(
              widget.proposalId,
              representativeMeta.currentBody,
            );
      final refTally = representativeMeta?.rule == 2
          ? await _query.fetchReferendumTally(widget.proposalId)
          : (yes: 0, no: 0);

      // 代表机构阶段按 body_index 检查席位票据，其余阶段交由链端校验身份。
      final votable = <CitizenWalletStateAccount>[];
      if (state?.stage == LegStage.representative &&
          representativeMeta != null) {
        final body = representativeMeta.bodies[representativeMeta.currentBody];
        for (final w in widget.adminWallets) {
          final voted = await _query.fetchRepresentativeVote(
            widget.proposalId,
            representativeMeta.currentBody,
            body.cidNumber,
            body.roleCode,
            _requireAccountId(w.accountId),
          );
          if (voted == null) votable.add(w);
        }
      } else {
        votable.addAll(widget.adminWallets);
      }

      if (!mounted) return;
      setState(() {
        _state = state;
        _representativeMeta = representativeMeta;
        _legislationMeta = legislationMeta;
        _representativeTally = representativeTally;
        _referendumTally = refTally;
        _votableWallets = votable;
        _selectedWallet = votable.isNotEmpty ? votable.first : null;
        _loading = false;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '提案读取失败：$e';
        });
      }
    }
  }

  bool get _isVotingStage =>
      _state?.status == LegProposalStatus.voting &&
      _state?.stage != LegStage.referendum;

  bool get _canAct => _isVotingStage && !_submitting && _selectedWallet != null;

  Future<void> _act(bool approve) async {
    final wallet = _selectedWallet;
    final stage = _state?.stage;
    if (wallet == null || stage == null) return;
    setState(() => _submitting = true);
    try {
      final publicKeyBytes = _hexDecode(wallet.accountId);
      final balance = await context.read<CitizenSdk>().chain.getAccountBalance(
        wallet.accountId,
      );
      if (balance.freeFen <= BigInt.zero) {
        throw StateError('当前钱包余额不足，无法支付链上手续费');
      }

      await _dispatch(
        stage: stage,
        approve: approve,
        publicKeyBytes: publicKeyBytes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('提交成功')));
      await _load(showSpinner: false);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('提交失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _dispatch({
    required int stage,
    required bool approve,
    required Uint8List publicKeyBytes,
  }) {
    final common = (
      proposalId: widget.proposalId,
      approve: approve,
      signerPublicKey: Uint8List.fromList(publicKeyBytes),
    );
    Future<String?> externalSigning(
      CitizenTransactionExternalSigningPending pending,
    ) => showCitizenSdkQrResponse(
      context,
      request: pending.qrRequest,
      expiresAt: BigInt.from(pending.expiresAt.millisecondsSinceEpoch ~/ 1000),
    );
    switch (stage) {
      case LegStage.representative:
        final meta = _representativeMeta;
        if (meta == null) {
          return Future<void>.error(StateError('代表机构表决元数据不存在'));
        }
        return _vote.castRepresentativeVote(
          proposalId: common.proposalId,
          voterRoleCode: meta.bodies[meta.currentBody].roleCode,
          approve: common.approve,
          signerPublicKey: common.signerPublicKey,
          externalSigning: externalSigning,
        );
      case LegStage.sign:
        return _vote.executiveSign(
          proposalId: common.proposalId,
          approve: common.approve,
          signerPublicKey: common.signerPublicKey,
          externalSigning: externalSigning,
        );
      case LegStage.override_:
        return _vote.overrideSign(
          proposalId: common.proposalId,
          approve: common.approve,
          signerPublicKey: common.signerPublicKey,
          externalSigning: externalSigning,
        );
      case LegStage.guard:
        return _vote.guardVote(
          proposalId: common.proposalId,
          approve: common.approve,
          signerPublicKey: common.signerPublicKey,
          externalSigning: externalSigning,
        );
      default:
        return Future<void>.error(StateError('当前阶段不支持本端操作'));
    }
  }

  int _qrAction(int stage) => switch (stage) {
    LegStage.representative => QrActions.legislationRepresentativeVote,
    LegStage.sign => QrActions.legislationExecutiveSign,
    LegStage.override_ => QrActions.legislationOverrideSign,
    LegStage.guard => QrActions.legislationGuardVote,
    _ => 0,
  };

  String _stageLabel(int stage) => switch (stage) {
    LegStage.representative => '代表机构表决',
    LegStage.referendum => '特别案公投',
    LegStage.sign => '行政首长签署',
    LegStage.override_ => '三人会签',
    LegStage.guard => '护宪大法官终审',
    _ => '未知阶段',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: Text('立法提案 #${widget.proposalId}'),
        backgroundColor: AppTheme.surfaceCard,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: _buildBody(),
      bottomNavigationBar: _isVotingStage && _qrAction(_state!.stage) != 0
          ? ProposalVoteActions(
              votableWallets: _votableWallets,
              selectedWallet: _selectedWallet,
              submitting: _submitting,
              canVote: _canAct,
              allVoted: _votableWallets.isEmpty,
              onWalletChanged: (w) => setState(() => _selectedWallet = w),
              onVote: _act,
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final state = _state;
    if (_error != null || state == null) {
      return Center(
        child: Text(
          _error ?? '提案不存在',
          style: const TextStyle(color: AppTheme.textTertiary),
        ),
      );
    }
    final representativeMeta = _representativeMeta;
    final legislationMeta = _legislationMeta;
    final isReferendum = state.stage == LegStage.referendum;
    return ListView(
      padding: EdgeInsets.all(AppLayout.scaledValue(16)),
      children: [
        ProposalStatusBadge(
          status: state.status,
          proposalId: widget.proposalId,
        ),
        SizedBox(height: AppLayout.scaledValue(16)),
        _infoCard(state, representativeMeta, legislationMeta),
        SizedBox(height: AppLayout.scaledValue(12)),
        _tallyCard(isReferendum),
        if (isReferendum) ...[
          SizedBox(height: AppLayout.scaledValue(12)),
          _referendumNote(),
        ],
      ],
    );
  }

  Widget _infoCard(
    LegProposalState state,
    LegRepresentativeMeta? representativeMeta,
    LegislationMeta? legislationMeta,
  ) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv('当前阶段', _stageLabel(state.stage)),
            if (representativeMeta != null) ...[
              SizedBox(height: AppLayout.scaledValue(6)),
              _kv('表决规则', _representativeRuleLabel(representativeMeta.rule)),
              SizedBox(height: AppLayout.scaledValue(6)),
              _kv('代表机构', representativeMeta.bodies.join(' → ')),
              if (legislationMeta?.needsGuard == true) ...[
                SizedBox(height: AppLayout.scaledValue(6)),
                _kv('修宪', '通过后需护宪大法官终审'),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _tallyCard(bool isReferendum) {
    final t = isReferendum ? _referendumTally : _representativeTally;
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '当前计票',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(15),
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryDark,
              ),
            ),
            Text(
              '赞成 ${t.yes}　反对 ${t.no}',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(14),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _referendumNote() {
    return Container(
      padding: EdgeInsets.all(AppLayout.scaledValue(14)),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.18)),
      ),
      child: Text(
        '特别案需立法公投表决。请在「立法投票」入口凭 CID 资格参与，本页仅展示进度。',
        style: TextStyle(
          fontSize: AppLayout.scaledValue(13),
          height: 1.5,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: AppLayout.scaledValue(72),
          child: Text(
            k,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(13),
              color: AppTheme.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(13),
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  static String _representativeRuleLabel(int rule) => switch (rule) {
    0 => '常规规则',
    1 => '重要规则',
    2 => '特别规则',
    _ => '未知',
  };

  // ──── 工具 ────

  String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  Uint8List _hexDecode(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    final out = Uint8List(h.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
