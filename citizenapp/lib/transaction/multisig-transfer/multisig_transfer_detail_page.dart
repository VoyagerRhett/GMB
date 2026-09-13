import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter/services.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/institution_admin_service.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_context.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_detail_local_store.dart';
import 'package:citizenapp/votingengine/internal-vote/internal_vote_service.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_balance_guard.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_models.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_service.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/votingengine/internal-vote/proposal_vote_widgets.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 详情页展示/投票的三种提案类型。
///
/// 决定：读哪个 storage map 与 QR 签名如何展示。
/// 投票动作统一走 `InternalVote::cast`(20.0);`kind` 仅影响"创建提案"
/// 路径与详情展示逻辑。
enum MultisigTransferKind {
  /// 机构转账提案（propose_transfer, pallet=17 call=0）。
  transfer,

  /// 安全基金转账提案（propose_safety_fund_transfer, pallet=17 call=1）。
  safetyFund,

  /// 手续费划转提案（propose_sweep_to_main, pallet=17 call=2）。
  sweep,
}

/// 转账提案详情页：展示提案信息、投票进度、合格选民投票明细及投票操作。
///
/// 通过 [kind] 区分三种转账类提案；不同 kind 读不同 storage、提交不同 extrinsic、
/// QR 签名显示不同文案。
class MultisigTransferDetailPage extends StatefulWidget {
  const MultisigTransferDetailPage({
    super.key,
    required this.institution,
    required this.proposalId,
    required this.proposalContext,
    this.kind = MultisigTransferKind.transfer,
  });

  final InstitutionInfo institution;
  final int proposalId;
  final MultisigTransferKind kind;

  /// 统一的提案上下文。
  final ProposalContext proposalContext;

  /// 便捷访问。
  List<CitizenWalletStateAccount> get adminWallets =>
      proposalContext.adminWallets;

  @override
  State<MultisigTransferDetailPage> createState() =>
      _MultisigTransferDetailPageState();
}

class _MultisigTransferDetailPageState
    extends State<MultisigTransferDetailPage> {
  static const int _statusVoting = 0;

  late final MultisigTransferService _proposalService;
  final ProposalDetailLocalStore _detailStore =
      ProposalDetailLocalStore.instance;
  late final InstitutionAdminService _adminService;
  bool _dependenciesReady = false;
  AdminAccountIdentity get _accountIdentity =>
      AdminAccountIdentity.fromInstitution(widget.institution);
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  // 提案状态
  int? _status;

  // 提案详情（从链上读取）— 按 kind 使用对应字段，其余字段为 null。
  TransferProposalInfo? _transferInfo;
  SafetyFundProposalInfo? _safetyFundInfo;
  SweepProposalInfo? _sweepInfo;
  bool _remarkExpanded = false;

  // ──── kind 相关常量 ────

  /// 本详情页绑定的提案类型标签（供本地详情快照区分 key）。
  String get _proposalTypeKey {
    switch (widget.kind) {
      case MultisigTransferKind.transfer:
        return 'transfer';
      case MultisigTransferKind.safetyFund:
        return 'safety_fund';
      case MultisigTransferKind.sweep:
        return 'sweep';
    }
  }

  /// 签名显示用的人类可读类型名。
  String get _kindLabel {
    switch (widget.kind) {
      case MultisigTransferKind.transfer:
        return '转账提案';
      case MultisigTransferKind.safetyFund:
        return '安全基金转账提案';
      case MultisigTransferKind.sweep:
        return '手续费划转提案';
    }
  }

  // 投票计数
  int _yesCount = 0;
  int _noCount = 0;
  int? _thresholdSnapshot;

  // 提案创建时冻结的合格选民与投票记录。
  List<String> _admins = const [];
  // publicKey → true(赞成) / false(反对) / null(未投票)
  Map<String, bool?> _adminVotes = {};
  List<EligibleVoterTicket> _voterTickets = const [];

  // 当前用户已导入且属于合格选民快照的投票钱包。
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
    _proposalService = MultisigTransferService(
      chain: sdk.chain,
      transactions: sdk.transactions,
    );
    _adminService = InstitutionAdminService(chain: sdk.chain);
    _dependenciesReady = true;
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    ProposalDetailSnapshot? localSnapshot;
    if (showSpinner) {
      localSnapshot = await _applyLocalSnapshot();
    }
    // 岗位票据不可由旧的账户级本地缓存恢复，始终继续读取链上快照。

    if (showSpinner && localSnapshot == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }

    try {
      // 根据 kind 选择对应的详情查询方法。
      // 不同 kind 写在不同的 storage map：
      //   transfer   → VotingEngine.ProposalData（带 multisig tag）
      //   safetyFund → MultisigTransfer.SafetyFundProposalActions
      //   sweep      → MultisigTransfer.SweepProposalActions
      final Future<dynamic> detailFuture;
      switch (widget.kind) {
        case MultisigTransferKind.transfer:
          detailFuture = _proposalService.fetchProposalAction(
            widget.proposalId,
          );
          break;
        case MultisigTransferKind.safetyFund:
          detailFuture = _proposalService.fetchSafetyFundAction(
            widget.proposalId,
          );
          break;
        case MultisigTransferKind.sweep:
          detailFuture = _proposalService.fetchSweepAction(widget.proposalId);
          break;
      }

      // 并行加载提案快照、提案状态、投票计数、提案详情。
      // 多签转账投票资格和进度必须以提案创建时的快照为准，
      // 机构路径不能使用当前 admins 或当前岗位任职，个人路径不能使用当前
      // 管理员集合；否则任职或人员变化后旧提案会显示错误。
      final results = await Future.wait([
        _proposalService.fetchEligibleVoterTickets(
          widget.proposalId,
          widget.institution,
        ),
        _proposalService.fetchInternalThresholdSnapshot(widget.proposalId),
        _proposalService.fetchProposalStatus(widget.proposalId),
        _proposalService.fetchVoteTally(widget.proposalId),
        detailFuture,
      ]);

      final voterTickets = results[0] as List<EligibleVoterTicket>;
      final admins = voterTickets
          .map((ticket) => ticket.voterAccountId)
          .toSet()
          .toList();
      final thresholdSnapshot = results[1] as int?;
      final status = results[2] as int?;
      final tally = results[3] as ({int yes, int no});
      final detail = results[4];
      // 选民投票记录批量读取，避免逐个产生 RPC。
      final votes = await _proposalService.fetchTicketVotesBatch(
        widget.proposalId,
        voterTickets,
      );

      // 筛选出至少仍有一张未投岗位票据的钱包。
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

      if (!mounted) return;
      try {
        await _detailStore.put(
          _snapshotFromChain(
            status: status,
            tally: tally,
            thresholdSnapshot: thresholdSnapshot,
            admins: admins,
            votes: votes,
            detail: detail,
          ),
        );
      } catch (e) {
        // 详情快照写入失败不能影响链上最新结果展示；仅留痕便于排查。
        AppLog.d('[MultisigDetail] 详情快照写入失败: $e');
      }
      if (!mounted) return;
      setState(() {
        _admins = admins;
        _status = status;
        _yesCount = tally.yes;
        _noCount = tally.no;
        _thresholdSnapshot = thresholdSnapshot;
        _adminVotes = votes;
        _voterTickets = voterTickets;
        _votableWallets = votable;
        _selectedVoteWallet = votable.isNotEmpty ? votable.first : null;
        _transferInfo = null;
        _safetyFundInfo = null;
        _sweepInfo = null;
        switch (widget.kind) {
          case MultisigTransferKind.transfer:
            _transferInfo = detail as TransferProposalInfo?;
            break;
          case MultisigTransferKind.safetyFund:
            _safetyFundInfo = detail as SafetyFundProposalInfo?;
            break;
          case MultisigTransferKind.sweep:
            _sweepInfo = detail as SweepProposalInfo?;
            break;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (localSnapshot != null) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = '多签提案链状态暂时不可用';
        _loading = false;
      });
    }
  }

  Future<ProposalDetailSnapshot?> _applyLocalSnapshot() async {
    try {
      final snapshot = await _detailStore.read(
        _proposalTypeKey,
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
      final detail = _detailFromSnapshot(snapshot);
      setState(() {
        _admins = admins;
        _status = snapshot.status;
        _yesCount = snapshot.yesCount;
        _noCount = snapshot.noCount;
        _thresholdSnapshot = snapshot.threshold;
        _adminVotes = snapshot.adminVotes;
        _votableWallets = votable;
        _selectedVoteWallet = votable.isNotEmpty ? votable.first : null;
        _transferInfo = null;
        _safetyFundInfo = null;
        _sweepInfo = null;
        switch (widget.kind) {
          case MultisigTransferKind.transfer:
            _transferInfo = detail as TransferProposalInfo?;
            break;
          case MultisigTransferKind.safetyFund:
            _safetyFundInfo = detail as SafetyFundProposalInfo?;
            break;
          case MultisigTransferKind.sweep:
            _sweepInfo = detail as SweepProposalInfo?;
            break;
        }
        _loading = false;
        _error = null;
      });
      return snapshot;
    } catch (e) {
      AppLog.d('[MultisigDetail] 加载多签详情快照失败: $e');
      return null;
    }
  }

  ProposalDetailSnapshot _snapshotFromChain({
    required int? status,
    required ({int yes, int no}) tally,
    required int? thresholdSnapshot,
    required List<String> admins,
    required Map<String, bool?> votes,
    required Object? detail,
  }) {
    return ProposalDetailSnapshot(
      proposalId: widget.proposalId,
      typeKey: _proposalTypeKey,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      status: status,
      yesCount: tally.yes,
      noCount: tally.no,
      threshold: thresholdSnapshot,
      admins: admins.map(_requireAccountId).toList(growable: false),
      adminVotes: votes.map(
        (key, value) => MapEntry(_requireAccountId(key), value),
      ),
      pendingPublicKeys: const [],
      detail: _detailToJson(detail),
    );
  }

  Map<String, Object?> _detailToJson(Object? detail) {
    if (detail is TransferProposalInfo) {
      return {
        'kind': 'transfer',
        'actor_cid_number': detail.actorCidNumber,
        'institution_account_id': _accountIdText(detail.institutionAccountId),
        'beneficiary': detail.beneficiary,
        'amount_fen': detail.amountFen.toString(),
        'remark': detail.remark,
        'proposer': detail.proposer,
        'status': detail.status,
      };
    }
    if (detail is SafetyFundProposalInfo) {
      return {
        'kind': 'safety_fund',
        'actor_cid_number': detail.actorCidNumber,
        'institution_account_id': _accountIdText(detail.institutionAccountId),
        'beneficiary': detail.beneficiary,
        'amount_fen': detail.amountFen.toString(),
        'remark': detail.remark,
        'proposer': detail.proposer,
        'status': detail.status,
      };
    }
    if (detail is SweepProposalInfo) {
      return {
        'kind': 'sweep',
        'actor_cid_number': detail.actorCidNumber,
        'institution_account_id': _accountIdText(detail.institutionAccountId),
        'amount_fen': detail.amountFen.toString(),
        'proposer': detail.proposer,
        'status': detail.status,
      };
    }
    return const {};
  }

  Object? _detailFromSnapshot(ProposalDetailSnapshot snapshot) {
    final detail = snapshot.detail;
    final kind = detail['kind']?.toString();
    if (kind == 'transfer') {
      final amountFen = BigInt.tryParse(detail['amount_fen']?.toString() ?? '');
      final actorCidNumber = detail['actor_cid_number']?.toString();
      final institutionAccountId = detail['institution_account_id']?.toString();
      if (amountFen == null || institutionAccountId == null) return null;
      return TransferProposalInfo(
        proposalId: snapshot.proposalId,
        actorCidNumber: actorCidNumber,
        institutionAccountId: _accountIdBytes(institutionAccountId),
        beneficiary: detail['beneficiary']?.toString() ?? '',
        amountFen: amountFen,
        remark: detail['remark']?.toString() ?? '',
        proposer: detail['proposer']?.toString() ?? '',
        status: snapshot.status,
      );
    }
    if (kind == 'safety_fund') {
      final amountFen = BigInt.tryParse(detail['amount_fen']?.toString() ?? '');
      final actorCidNumber = detail['actor_cid_number']?.toString();
      final institutionAccountId = detail['institution_account_id']?.toString();
      if (amountFen == null ||
          actorCidNumber == null ||
          institutionAccountId == null) {
        return null;
      }
      return SafetyFundProposalInfo(
        proposalId: snapshot.proposalId,
        actorCidNumber: actorCidNumber,
        institutionAccountId: _accountIdBytes(institutionAccountId),
        beneficiary: detail['beneficiary']?.toString() ?? '',
        amountFen: amountFen,
        remark: detail['remark']?.toString() ?? '',
        proposer: detail['proposer']?.toString() ?? '',
        status: snapshot.status,
      );
    }
    if (kind == 'sweep') {
      final amountFen = BigInt.tryParse(detail['amount_fen']?.toString() ?? '');
      final actorCidNumber = detail['actor_cid_number']?.toString();
      final institutionAccountId = detail['institution_account_id']?.toString();
      final proposer = detail['proposer']?.toString();
      if (amountFen == null ||
          actorCidNumber == null ||
          institutionAccountId == null ||
          proposer == null ||
          proposer.isEmpty) {
        return null;
      }
      return SweepProposalInfo(
        proposalId: snapshot.proposalId,
        actorCidNumber: actorCidNumber,
        institutionAccountId: _accountIdBytes(institutionAccountId),
        amountFen: amountFen,
        proposer: proposer,
        status: snapshot.status,
      );
    }
    return null;
  }

  // ──── SS58 编码工具 ────

  String _toHex(List<int> bytes) {
    const chars = '0123456789abcdef';
    final buf = StringBuffer();
    for (final b in bytes) {
      buf
        ..write(chars[(b >> 4) & 0x0f])
        ..write(chars[b & 0x0f]);
    }
    return buf.toString();
  }

  String _accountIdText(List<int> bytes) {
    if (bytes.length != 32) {
      throw const FormatException('institution_account_id 必须为 32 字节');
    }
    return '0x${_toHex(bytes)}';
  }

  Uint8List _accountIdBytes(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('institution_account_id 必须为小写 0x + 64 位十六进制');
    }
    return _hexDecode(accountId);
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

  String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  // ──── 投票提交 ────

  /// 当前用户是否是此机构的管理员（可能导入了多个管理员钱包）。
  bool get _isCurrentUserAdmin => widget.proposalContext.isAdmin;

  /// 是否还有可投票的钱包（未投票的管理员钱包）。
  bool get _canVote {
    if (_selectedVoteWallet == null) return false;
    if (_status != _statusVoting) return false;
    return _votableWallets.isNotEmpty;
  }

  /// 所有管理员钱包都已投过票或正在投票中。
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
    final wallet = _selectedVoteWallet;
    if (wallet == null) return;

    final balanceBlockedReason =
        await MultisigTransferBalanceGuard.checkAdminWalletBalance(
          wallet: wallet,
          requiredFeeYuan: MultisigTransferBalanceGuard.voteFeeYuan,
          actionLabel: '提交多签转账投票',
          chain: context.read<CitizenSdk>().chain,
        );
    if (balanceBlockedReason != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(balanceBlockedReason),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

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
        throw StateError('当前钱包没有未使用的投票票据');
      }
      final ticket = await _selectTicket(availableTickets);
      if (ticket == null) throw StateError('已取消选择投票岗位');
      if (!mounted) return;

      // 机构岗位快照选民和个人多签管理员都统一走 InternalVote::cast(20.0)。
      // 业务 kind 仅用于 QR 展示的文案与 storage 读取。
      final sdk = context.read<CitizenSdk>();
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
        '[MultisigTransferVote] submit 已入块 txHash=${result.txHash} nonce=${result.usedNonce} block=${result.blockHashHex}',
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

      // 刷新数据
      _adminService.clearCache(_accountIdentity);
      // 服务层已经等待入块并回读 InternalVote storage；这里
      // 只后台刷新展示状态，不能再把 txHash 当作投票成功依据。
      unawaited(_load(showSpinner: false));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('投票失败：$e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: Text(
          '$_kindLabel详情',
          style: TextStyle(
            fontSize: AppLayout.scaled(context, 17),
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        foregroundColor: AppTheme.textPrimary,
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
            threshold:
                _thresholdSnapshot ?? widget.institution.internalThreshold,
          ),
          SizedBox(height: AppLayout.scaledValue(16)),
          ProposalAdminVoteList(
            admins: _admins,
            voterTickets: _voterTickets,
            adminVotes: _adminVotes,
            pendingPublicKeys: const {},
            proposerSs58: _proposerSs58,
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

  // ──── 提案信息卡片 ────

  /// 提案创建者公钥。
  String? get _proposerSs58 {
    switch (widget.kind) {
      case MultisigTransferKind.transfer:
        return _transferInfo?.proposer;
      case MultisigTransferKind.safetyFund:
        return _safetyFundInfo?.proposer;
      case MultisigTransferKind.sweep:
        return _sweepInfo?.proposer;
    }
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
              '提案信息',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(16),
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryDark,
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(12)),
            ..._buildInfoRowsByKind(),
          ],
        ),
      ),
    );
  }

  /// 按 kind 生成提案信息卡的内容行（含 Divider）。
  List<Widget> _buildInfoRowsByKind() {
    switch (widget.kind) {
      case MultisigTransferKind.transfer:
        return _buildTransferRows();
      case MultisigTransferKind.safetyFund:
        return _buildSafetyFundRows();
      case MultisigTransferKind.sweep:
        return _buildSweepRows();
    }
  }

  /// 普通机构转账：机构简称 + 金额 + 收款地址 + 备注。
  List<Widget> _buildTransferRows() {
    final info = _transferInfo;
    final rows = <Widget>[
      _buildInfoRow('机构简称', widget.institution.cidShortName),
    ];
    if (info != null) {
      rows
        ..add(Divider(height: AppLayout.scaledValue(20)))
        ..add(
          _buildInfoRow(
            '转账金额',
            '${AmountFormat.format(info.amountYuan, symbol: '')} 元',
          ),
        )
        ..add(Divider(height: AppLayout.scaledValue(20)))
        ..add(
          _buildInfoRow(
            '收款地址',
            _truncateAddress(info.beneficiary),
            onCopy: () => _copyToClipboard(info.beneficiary),
          ),
        );
    }
    rows
      ..add(Divider(height: AppLayout.scaledValue(20)))
      ..add(_buildRemarkRow(info?.remark ?? ''));
    return rows;
  }

  /// 安全基金转账：金额 + 收款地址 + 备注（无机构维度，安全基金是全链级账户）。
  List<Widget> _buildSafetyFundRows() {
    final info = _safetyFundInfo;
    final rows = <Widget>[_buildInfoRow('付款账户', '安全基金账户')];
    if (info != null) {
      rows
        ..add(Divider(height: AppLayout.scaledValue(20)))
        ..add(
          _buildInfoRow(
            '转账金额',
            '${AmountFormat.format(info.amountYuan, symbol: '')} 元',
          ),
        )
        ..add(Divider(height: AppLayout.scaledValue(20)))
        ..add(
          _buildInfoRow(
            '收款地址',
            _truncateAddress(info.beneficiary),
            onCopy: () => _copyToClipboard(info.beneficiary),
          ),
        );
    }
    rows
      ..add(Divider(height: AppLayout.scaledValue(20)))
      ..add(_buildRemarkRow(info?.remark ?? ''));
    return rows;
  }

  /// 手续费划转：机构简称 + 划转金额 + 目标（机构主账户），无备注、无收款地址。
  List<Widget> _buildSweepRows() {
    final info = _sweepInfo;
    final rows = <Widget>[
      _buildInfoRow('机构简称', widget.institution.cidShortName),
    ];
    if (info != null) {
      rows
        ..add(Divider(height: AppLayout.scaledValue(20)))
        ..add(
          _buildInfoRow(
            '划转金额',
            '${AmountFormat.format(info.amountYuan, symbol: '')} 元',
          ),
        )
        ..add(Divider(height: AppLayout.scaledValue(20)))
        ..add(_buildInfoRow('划转路径', '手续费账户 → 机构主账户'));
    }
    return rows;
  }

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('地址已复制'), duration: Duration(seconds: 1)),
    );
  }

  Widget _buildRemarkRow(String remark) {
    if (remark.isEmpty) {
      return _buildInfoRow('备注', '无');
    }
    final isLong = remark.length > 30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: AppLayout.scaledValue(80),
              child: Text(
                '备注',
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(13),
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                remark,
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(13),
                  color: AppTheme.textPrimary,
                ),
                maxLines: _remarkExpanded ? null : 1,
                overflow: _remarkExpanded ? null : TextOverflow.ellipsis,
              ),
            ),
            if (isLong)
              GestureDetector(
                onTap: () => setState(() => _remarkExpanded = !_remarkExpanded),
                child: Icon(
                  _remarkExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: AppLayout.scaledValue(20),
                  color: AppTheme.textTertiary,
                ),
              ),
          ],
        ),
      ],
    );
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
}
