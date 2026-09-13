import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter/services.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/institution_admin_service.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/votingengine/internal-vote/internal_vote_service.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_context.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_detail_local_store.dart';
import 'package:citizenapp/votingengine/internal-vote/proposal_vote_widgets.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/transaction/personal-manage/personal_manage_models.dart'
    as personal_models;
import 'package:citizenapp/transaction/personal-manage/personal_manage_service.dart';
import 'package:citizenapp/citizen/institution/institution_models.dart'
    as institution_models;
import 'package:citizenapp/citizen/institution/institution_chain_service.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 多签管理提案详情页：展示创建/关闭提案信息、投票进度及投票操作。
class MultisigProposalDetailPage extends StatefulWidget {
  const MultisigProposalDetailPage({
    super.key,
    required this.institution,
    required this.proposalId,
    required this.proposalContext,
  });

  final InstitutionInfo institution;
  final int proposalId;
  final ProposalContext proposalContext;

  List<CitizenWalletStateAccount> get adminWallets =>
      proposalContext.adminWallets;

  @override
  State<MultisigProposalDetailPage> createState() =>
      _MultisigProposalDetailPageState();
}

class _MultisigProposalDetailPageState
    extends State<MultisigProposalDetailPage> {
  static const int _statusVoting = 0;

  late final ProposalQueryService _proposalService;
  final ProposalDetailLocalStore _detailStore =
      ProposalDetailLocalStore.instance;
  final InstitutionChainService _manageService = InstitutionChainService();
  late final PersonalManageService _personalManageService;
  late final InstitutionAdminService _adminService;
  bool _dependenciesReady = false;
  AdminAccountIdentity get _accountIdentity =>
      AdminAccountIdentity.fromInstitution(widget.institution);
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  int? _status;

  // 提案详情（二选一）
  personal_models.CreateProposalInfo? _createInfo;
  personal_models.CloseProposalInfo? _closeInfo;
  institution_models.CloseProposalInfo? _institutionCloseInfo;

  bool get _isCreateProposal => _createInfo != null;

  // 投票计数
  int _yesCount = 0;
  int _noCount = 0;
  int _threshold = 0;

  // 提案创建时冻结的合格选民与投票记录；机构路径来自岗位快照。
  List<String> _admins = const [];
  Map<String, bool?> _adminVotes = {};
  List<EligibleVoterTicket> _voterTickets = const [];

  List<CitizenWalletStateAccount> _votableWallets = const [];
  CitizenWalletStateAccount? _selectedVoteWallet;
  String? _voteNotice;
  bool _voteNoticeIsError = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final sdk = context.read<CitizenSdk>();
    _proposalService = ProposalQueryService(chain: sdk.chain);
    _personalManageService = PersonalManageService(
      chain: sdk.chain,
      transactions: sdk.transactions,
    );
    _adminService = InstitutionAdminService(chain: sdk.chain);
    _dependenciesReady = true;
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    AppLog.d('[VoteDetail._load] 开始 proposalId=${widget.proposalId}');
    ProposalDetailSnapshot? localSnapshot;
    if (showSpinner) {
      localSnapshot = await _applyLocalSnapshot();
    }
    // 岗位票据包含 CID + 岗位码，旧的账户级本地详情快照不能作为投票资格真源；
    // 即使缓存新鲜也继续读取链上 VotePlan/VoterSnapshot。

    if (showSpinner && localSnapshot == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }

    try {
      // step1:并行加载合格选民快照、提案状态、投票计数、阈值快照。
      // 机构资格只来自岗位有效选民快照，个人资格来自管理员快照；缺失或损坏
      // 必须失败，禁止回落到当前 admins。
      AppLog.d(
        '[VoteDetail._load] step1: 并行 fetchSnapshot/Status/Tally/Threshold...',
      );
      final thresholdFuture = _proposalService
          .fetchInternalThresholdSnapshot(widget.proposalId)
          .catchError((_) => null);
      final results = await Future.wait([
        _proposalService.fetchEligibleVoterTickets(
          widget.proposalId,
          widget.institution,
        ),
        _proposalService.fetchProposalStatus(widget.proposalId),
        _proposalService.fetchVoteTally(widget.proposalId),
        thresholdFuture,
      ]);

      final voterTickets = results[0] as List<EligibleVoterTicket>;
      final admins = voterTickets
          .map((ticket) => ticket.voterAccountId)
          .toSet()
          .toList();
      final status = results[1] as int?;
      final tally = results[2] as ({int yes, int no});
      final thresholdSnapshot = results[3] as int?;
      final threshold = _resolveVoteThreshold(
        thresholdSnapshot,
        voterTickets.length,
      );
      AppLog.d(
        '[VoteDetail._load] step1 完成 admins.len=${admins.length} status=$status yes=${tally.yes} no=${tally.no} threshold=$threshold',
      );

      // step2:加载提案业务数据（从 ProposalData 解码）
      AppLog.d('[VoteDetail._load] step2: fetchProposalData');
      final raw = await _proposalService.fetchProposalData(widget.proposalId);
      AppLog.d('[VoteDetail._load] step2 完成 raw.len=${raw?.length ?? 0}');
      personal_models.CreateProposalInfo? createInfo;
      personal_models.CloseProposalInfo? closeInfo;
      institution_models.CloseProposalInfo? institutionCloseInfo;
      if (raw != null && raw.isNotEmpty) {
        final personalDetail = _personalManageService
            .decodePersonalProposalData(widget.proposalId, raw);
        if (personalDetail is personal_models.CreateProposalInfo) {
          createInfo = personalDetail;
        } else if (personalDetail is personal_models.CloseProposalInfo) {
          closeInfo = personalDetail;
        } else {
          final orgDetail = _manageService.decodeManageProposalData(
            widget.proposalId,
            raw,
          );
          if (orgDetail is institution_models.CloseProposalInfo) {
            if (orgDetail.actorCidNumber != widget.institution.cidNumber) {
              throw StateError('机构关闭提案 actor CID 与当前机构不一致');
            }
            institutionCloseInfo = orgDetail;
          }
        }
      }

      // step3:批量查询每张快照票据的投票记录，避免逐条 RPC。
      AppLog.d('[VoteDetail._load] step3: 批量查岗位票据 (${voterTickets.length} 张)');
      final votes = await _proposalService.fetchTicketVotesBatch(
        widget.proposalId,
        voterTickets,
      );
      AppLog.d('[VoteDetail._load] step3 完成');

      // 筛选可投票钱包
      final votable = <CitizenWalletStateAccount>[];
      for (final w in widget.adminWallets) {
        final accountId = _requireAccountId(w.accountId);
        final walletTickets = voterTickets.where(
          (ticket) => _requireAccountId(ticket.voterAccountId) == accountId,
        );
        if (walletTickets.any((ticket) => votes[ticket.ticketKey] == null)) {
          votable.add(w);
        }
      }

      if (!mounted) {
        AppLog.d('[VoteDetail._load] !mounted 提前返回');
        return;
      }
      try {
        await _detailStore.put(
          _snapshotFromChain(
            status: status,
            tally: tally,
            threshold: threshold,
            admins: admins,
            votes: votes,
            createInfo: createInfo,
            closeInfo: closeInfo,
            institutionCloseInfo: institutionCloseInfo,
          ),
        );
      } catch (_) {
        // 详情快照只是首屏加速，写入失败不能影响链上结果展示。
      }
      if (!mounted) return;
      AppLog.d('[VoteDetail._load] step5: setState');
      setState(() {
        _admins = admins;
        _status = status;
        _yesCount = tally.yes;
        _noCount = tally.no;
        _threshold = threshold;
        _adminVotes = votes;
        _voterTickets = voterTickets;
        _votableWallets = votable;
        _selectedVoteWallet = votable.isNotEmpty ? votable.first : null;
        _createInfo = createInfo;
        _closeInfo = closeInfo;
        _institutionCloseInfo = institutionCloseInfo;
        _loading = false;
      });
      AppLog.d('[VoteDetail._load] 结束');
    } catch (e, st) {
      AppLog.d('[VoteDetail._load] catch 异常: $e\n$st');
      if (!mounted) return;
      if (localSnapshot != null) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = '提案链状态暂时不可用';
        _loading = false;
      });
    }
  }

  Future<ProposalDetailSnapshot?> _applyLocalSnapshot() async {
    try {
      final snapshot = await _detailStore.read(
        'institution_multisig',
        widget.proposalId,
      );
      if (snapshot == null || !mounted) return snapshot;
      final admins = snapshot.admins;
      final votable = <CitizenWalletStateAccount>[];
      for (final w in widget.adminWallets) {
        final accountId = _requireAccountId(w.accountId);
        if (admins.contains(accountId) &&
            snapshot.adminVotes[accountId] == null) {
          votable.add(w);
        }
      }
      final createInfo = _createInfoFromSnapshot(snapshot);
      final closeInfo = _closeInfoFromSnapshot(snapshot);
      final institutionCloseInfo = _institutionCloseInfoFromSnapshot(snapshot);
      if (createInfo == null &&
          closeInfo == null &&
          institutionCloseInfo == null) {
        return null;
      }
      setState(() {
        _admins = admins;
        _status = snapshot.status;
        _yesCount = snapshot.yesCount;
        _noCount = snapshot.noCount;
        _threshold = snapshot.threshold ?? 0;
        _adminVotes = snapshot.adminVotes;
        _votableWallets = votable;
        _selectedVoteWallet = votable.isNotEmpty ? votable.first : null;
        _createInfo = createInfo;
        _closeInfo = closeInfo;
        _institutionCloseInfo = institutionCloseInfo;
        _loading = false;
        _error = null;
      });
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  ProposalDetailSnapshot _snapshotFromChain({
    required int? status,
    required ({int yes, int no}) tally,
    required int threshold,
    required List<String> admins,
    required Map<String, bool?> votes,
    required personal_models.CreateProposalInfo? createInfo,
    required personal_models.CloseProposalInfo? closeInfo,
    required institution_models.CloseProposalInfo? institutionCloseInfo,
  }) {
    return ProposalDetailSnapshot(
      proposalId: widget.proposalId,
      typeKey: 'institution_multisig',
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      status: status,
      yesCount: tally.yes,
      noCount: tally.no,
      threshold: threshold,
      admins: admins.map(_requireAccountId).toList(growable: false),
      adminVotes: votes.map(
        (key, value) => MapEntry(_requireAccountId(key), value),
      ),
      pendingPublicKeys: const [],
      detail: createInfo != null
          ? _createInfoToJson(createInfo)
          : closeInfo != null
          ? _closeInfoToJson(closeInfo)
          : institutionCloseInfo != null
          ? _institutionCloseInfoToJson(institutionCloseInfo)
          : const {},
    );
  }

  Map<String, Object?> _createInfoToJson(
    personal_models.CreateProposalInfo info,
  ) {
    return {
      'kind': 'create',
      'account_id': info.accountId,
      'proposer_ss58_address': info.proposerSs58Address,
      'amount_fen': info.amountFen.toString(),
      'fee_fen': info.feeFen.toString(),
      'status': info.status,
    };
  }

  Map<String, Object?> _closeInfoToJson(
    personal_models.CloseProposalInfo info,
  ) {
    return {
      'kind': 'close',
      'account_id': info.accountId,
      'beneficiary_ss58_address': info.beneficiarySs58Address,
      'proposer_ss58_address': info.proposerSs58Address,
      'status': info.status,
    };
  }

  Map<String, Object?> _institutionCloseInfoToJson(
    institution_models.CloseProposalInfo info,
  ) {
    return {
      'kind': 'institution_close',
      'actor_cid_number': info.actorCidNumber,
      'institution_account_id': info.institutionAccountId,
      'beneficiary': info.beneficiary,
      'proposer': info.proposer,
      'status': info.status,
    };
  }

  personal_models.CreateProposalInfo? _createInfoFromSnapshot(
    ProposalDetailSnapshot snapshot,
  ) {
    if (!isPersonalAccountIdentity(widget.institution.cidNumber)) return null;
    final detail = snapshot.detail;
    if (detail['kind'] != 'create') return null;
    final amountFen = BigInt.tryParse(detail['amount_fen']?.toString() ?? '');
    final feeFen = BigInt.tryParse(detail['fee_fen']?.toString() ?? '');
    final accountId = detail['account_id']?.toString();
    if (amountFen == null || feeFen == null || accountId == null) {
      return null;
    }
    return personal_models.CreateProposalInfo(
      proposalId: snapshot.proposalId,
      accountId: accountId,
      proposerSs58Address: detail['proposer_ss58_address']?.toString() ?? '',
      amountFen: amountFen,
      feeFen: feeFen,
      status: snapshot.status,
    );
  }

  personal_models.CloseProposalInfo? _closeInfoFromSnapshot(
    ProposalDetailSnapshot snapshot,
  ) {
    if (!isPersonalAccountIdentity(widget.institution.cidNumber)) return null;
    final detail = snapshot.detail;
    if (detail['kind'] != 'close') return null;
    final accountId = detail['account_id']?.toString();
    if (accountId == null) return null;
    return personal_models.CloseProposalInfo(
      proposalId: snapshot.proposalId,
      accountId: accountId,
      beneficiarySs58Address:
          detail['beneficiary_ss58_address']?.toString() ?? '',
      proposerSs58Address: detail['proposer_ss58_address']?.toString() ?? '',
      status: snapshot.status,
    );
  }

  institution_models.CloseProposalInfo? _institutionCloseInfoFromSnapshot(
    ProposalDetailSnapshot snapshot,
  ) {
    if (isPersonalAccountIdentity(widget.institution.cidNumber)) return null;
    final detail = snapshot.detail;
    if (detail['kind'] != 'institution_close') return null;
    final actorCidNumber = detail['actor_cid_number']?.toString();
    final institutionAccountId = detail['institution_account_id']?.toString();
    final beneficiary = detail['beneficiary']?.toString();
    final proposer = detail['proposer']?.toString();
    if (actorCidNumber != widget.institution.cidNumber ||
        institutionAccountId == null ||
        institutionAccountId.length != 64 ||
        beneficiary == null ||
        beneficiary.isEmpty ||
        proposer == null ||
        proposer.isEmpty) {
      return null;
    }
    return institution_models.CloseProposalInfo(
      proposalId: snapshot.proposalId,
      actorCidNumber: actorCidNumber!,
      institutionAccountId: institutionAccountId,
      beneficiary: beneficiary,
      proposer: proposer,
      status: snapshot.status,
    );
  }

  // ──── 工具方法 ────

  String _truncateAddress(String address) {
    if (address.length <= 14) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
  }

  int _resolveVoteThreshold(int? snapshotThreshold, int adminsLen) {
    if (snapshotThreshold != null && snapshotThreshold > 0) {
      return snapshotThreshold;
    }
    final institutionThreshold = widget.institution.internalThreshold;
    if (institutionThreshold > 0) return institutionThreshold;
    return adminsLen;
  }

  // ──── 投票提交 ────

  bool get _isCurrentUserAdmin => widget.proposalContext.isAdmin;

  bool get _canVote {
    if (_selectedVoteWallet == null) return false;
    if (_status != _statusVoting) return false;
    return _votableWallets.isNotEmpty;
  }

  bool get _allVoted {
    if (widget.adminWallets.isEmpty) return false;
    for (final w in widget.adminWallets) {
      final accountId = _requireAccountId(w.accountId);
      final tickets = _voterTickets.where(
        (ticket) => _requireAccountId(ticket.voterAccountId) == accountId,
      );
      if (tickets.any((ticket) => _adminVotes[ticket.ticketKey] == null)) {
        return false;
      }
    }
    return true;
  }

  Future<EligibleVoterTicket?> _selectTicket(
    List<EligibleVoterTicket> tickets,
  ) async {
    if (tickets.length == 1) return tickets.single;
    return showDialog<EligibleVoterTicket>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('选择本次投票岗位'),
        children: tickets
            .map(
              (ticket) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, ticket),
                child: Text(ticket.voterRoleCode ?? '个人多签管理员'),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _submitVote(bool approve) async {
    AppLog.d(
      '[VoteDetail] _submitVote 开始 approve=$approve proposalId=${widget.proposalId}',
    );
    final wallet = _selectedVoteWallet;
    if (wallet == null) {
      AppLog.d('[VoteDetail] _submitVote 无可投钱包,直接 return');
      return;
    }
    AppLog.d(
      '[VoteDetail] 选中钱包 ${wallet.ss58Address} accountId=${wallet.accountId} isHot=${wallet.signMode == CitizenWalletSignMode.hot}',
    );

    setState(() => _submitting = true);

    try {
      final signerPublicKeyBytes = _hexDecode(wallet.accountId);
      final accountId = _requireAccountId(wallet.accountId);
      final availableTickets = _voterTickets
          .where(
            (ticket) =>
                _requireAccountId(ticket.voterAccountId) == accountId &&
                _adminVotes[ticket.ticketKey] == null,
          )
          .toList(growable: false);
      if (availableTickets.isEmpty) {
        throw StateError('当前钱包不在该提案的合格选民快照中，不能投票');
      }
      final ticket = await _selectTicket(availableTickets);
      if (ticket == null) throw StateError('已取消选择投票岗位');
      if (!mounted) return;
      final sdk = context.read<CitizenSdk>();
      final balance = await sdk.chain.getAccountBalance(accountId);
      if (balance.freeFen <= BigInt.zero) {
        throw StateError('当前投票钱包余额不足，无法支付链上投票手续费');
      }

      // 创建/关闭多签的投票都走 InternalVote::cast(20.0),
      // 由 runtime 的 InternalVoteExecutor 按 MODULE_TAG+ACTION 分派。
      AppLog.d('[VoteDetail] 调 InternalVoteService.submit');
      final result =
          await InternalVoteService(
            chain: sdk.chain,
            transactions: sdk.transactions,
          ).submit(
            proposalId: widget.proposalId,
            approve: approve,
            actorCidNumber: ticket.cidNumber,
            voterRoleCode: ticket.voterRoleCode,
            signerPublicKey: Uint8List.fromList(signerPublicKeyBytes),
            externalSigning: (pending) => showCitizenSdkQrResponse(
              context,
              request: pending.qrRequest,
              expiresAt: BigInt.from(
                pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
              ),
            ),
          );
      AppLog.d(
        '[VoteDetail] submit 已入块 txHash=${result.txHash} nonce=${result.usedNonce} block=${result.blockHashHex}',
      );

      if (!mounted) return;
      setState(() {
        _adminVotes[ticket.ticketKey] = approve;
        _votableWallets = _votableWallets
            .where((w) {
              final accountId = _requireAccountId(w.accountId);
              return _voterTickets.any(
                (candidate) =>
                    _requireAccountId(candidate.voterAccountId) == accountId &&
                    _adminVotes[candidate.ticketKey] == null,
              );
            })
            .toList(growable: false);
        _selectedVoteWallet = _votableWallets.isNotEmpty
            ? _votableWallets.first
            : null;
        _voteNotice = '链上已确认该合格选民投票。';
        _voteNoticeIsError = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('投票已由 runtime 确认：${_truncateAddress(result.txHash)}'),
          backgroundColor: AppTheme.primaryDark,
        ),
      );

      _adminService.clearCache(_accountIdentity);
      // 服务层已经等待入块并回读 InternalVote storage；这里
      // 只后台刷新展示状态，不能再把 txHash 当作投票成功依据。
      AppLog.d('[VoteDetail] fire-and-forget 调 _load 后台刷新');
      unawaited(_load());
    } catch (e, st) {
      AppLog.d('[VoteDetail] _submitVote catch 异常: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('投票失败：$e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      AppLog.d('[VoteDetail] finally setState(_submitting=false)');
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  void _confirmVote(bool approve) {
    final label = approve ? '赞成' : '反对';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认$label'),
        content: Text('确定要对此提案投"$label"票吗？投票后不可更改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitVote(approve);
            },
            child: Text(label),
          ),
        ],
      ),
    );
  }

  // ──── 构建 UI ────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '提案详情',
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildError()
          : _buildContent(),
      bottomNavigationBar:
          (!_loading &&
              _error == null &&
              _status == _statusVoting &&
              _isCurrentUserAdmin)
          ? ProposalVoteActions(
              votableWallets: _votableWallets,
              selectedWallet: _selectedVoteWallet,
              submitting: _submitting,
              canVote: _canVote,
              allVoted: _allVoted,
              onWalletChanged: (w) => setState(() => _selectedVoteWallet = w),
              onVote: _confirmVote,
            )
          : null,
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: AppLayout.scaledValue(48),
              color: AppTheme.danger,
            ),
            SizedBox(height: AppLayout.scaledValue(12)),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(16),
                color: AppTheme.textSecondary,
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(6)),
            Text(
              _error!,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(12),
                color: AppTheme.textTertiary,
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: AppLayout.scaledValue(16)),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: () async {
        _adminService.clearCache(_accountIdentity);
        await _load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ProposalStatusBadge(status: _status, proposalId: widget.proposalId),
          if (_voteNotice != null) ...[
            SizedBox(height: AppLayout.scaledValue(12)),
            _buildVoteNotice(),
          ],
          SizedBox(height: AppLayout.scaledValue(16)),
          _buildProposalInfoCard(),
          SizedBox(height: AppLayout.scaledValue(16)),
          ProposalVoteProgress(
            yesCount: _yesCount,
            noCount: _noCount,
            threshold: _threshold,
          ),
          SizedBox(height: AppLayout.scaledValue(16)),
          ProposalAdminVoteList(
            admins: _admins,
            voterTickets: _voterTickets,
            adminVotes: _adminVotes,
            pendingPublicKeys: const {},
          ),
        ],
      ),
    );
  }

  Widget _buildVoteNotice() {
    final color = _voteNoticeIsError ? AppTheme.danger : AppTheme.info;
    return Container(
      padding: EdgeInsets.all(AppLayout.scaledValue(12)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _voteNoticeIsError ? Icons.error_outline : Icons.info_outline,
            size: AppLayout.scaledValue(18),
            color: color,
          ),
          SizedBox(width: AppLayout.scaledValue(8)),
          Expanded(
            child: Text(
              _voteNotice!,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(13),
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProposalInfoCard() {
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
            Text(
              _isCreateProposal ? '创建多签提案信息' : '关闭多签提案信息',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(16),
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryDark,
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(12)),
            if (_createInfo != null) ..._buildCreateInfoRows(),
            if (_closeInfo != null) ..._buildCloseInfoRows(),
            if (_institutionCloseInfo != null)
              ..._buildInstitutionCloseInfoRows(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCreateInfoRows() {
    final info = _createInfo!;
    final accountSs58 = Keyring().encodeAddress(
      _hexDecode(info.accountId),
      kGmbSs58Prefix,
    );
    return [
      _buildInfoRow(
        '多签账户',
        _truncateAddress(accountSs58),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: accountSs58));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('地址已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        },
      ),
      Divider(height: AppLayout.scaledValue(20)),
      _buildInfoRow('发起人', _truncateAddress(info.proposerSs58Address)),
      Divider(height: AppLayout.scaledValue(20)),
      _buildInfoRow(
        '初始资金',
        '${AmountFormat.format(info.amountYuan, symbol: '')} 元',
      ),
      Divider(height: AppLayout.scaledValue(20)),
      _buildInfoRow(
        '创建手续费',
        '${AmountFormat.format(info.feeYuan, symbol: '')} 元',
      ),
    ];
  }

  List<Widget> _buildCloseInfoRows() {
    final info = _closeInfo!;
    final accountSs58 = Keyring().encodeAddress(
      _hexDecode(info.accountId),
      kGmbSs58Prefix,
    );
    return [
      _buildInfoRow(
        '多签账户',
        _truncateAddress(accountSs58),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: accountSs58));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('地址已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        },
      ),
      Divider(height: AppLayout.scaledValue(20)),
      _buildInfoRow(
        '受益人',
        _truncateAddress(info.beneficiarySs58Address),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: info.beneficiarySs58Address));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('地址已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        },
      ),
      Divider(height: AppLayout.scaledValue(20)),
      _buildInfoRow('发起人', _truncateAddress(info.proposerSs58Address)),
    ];
  }

  List<Widget> _buildInstitutionCloseInfoRows() {
    final info = _institutionCloseInfo!;
    final accountSs58 = Keyring().encodeAddress(
      _hexDecode(info.institutionAccountId),
      kGmbSs58Prefix,
    );
    return [
      _buildInfoRow('机构 CID', info.actorCidNumber),
      Divider(height: AppLayout.scaledValue(20)),
      _buildInfoRow(
        '机构账户',
        _truncateAddress(accountSs58),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: accountSs58));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('地址已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        },
      ),
      Divider(height: AppLayout.scaledValue(20)),
      _buildInfoRow(
        '受益人',
        _truncateAddress(info.beneficiary),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: info.beneficiary));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('地址已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        },
      ),
      Divider(height: AppLayout.scaledValue(20)),
      _buildInfoRow('发起管理员', _truncateAddress(info.proposer)),
    ];
  }

  Widget _buildInfoRow(String label, String value, {VoidCallback? onCopy}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: AppLayout.scaledValue(80),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(13),
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(13),
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (onCopy != null)
          GestureDetector(
            onTap: onCopy,
            child: Icon(
              Icons.copy,
              size: AppLayout.scaledValue(16),
              color: AppTheme.textTertiary,
            ),
          ),
      ],
    );
  }

  // ──── 工具 ────

  Uint8List _hexDecode(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = Uint8List(h.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
