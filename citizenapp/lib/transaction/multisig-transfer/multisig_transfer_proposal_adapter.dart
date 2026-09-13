import 'package:flutter/material.dart';

import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_cache.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_detail_page.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_models.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_service.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_context.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/my/util/amount_format.dart';

/// 多签转账给外部列表页使用的只读适配器。
///
/// 外部页面只调用这里的标题、摘要、图标、跳转和缓存清理能力，
/// 不直接判断多签转账模型，也不直接打开多签转账详情页。
class MultisigTransferProposalAdapter {
  MultisigTransferProposalAdapter._();

  static TransferProposalInfo? _transfer(ProposalWithDetail proposal) {
    final detail =
        proposal.businessDetails[MultisigTransferProposalDetailKeys.transfer];
    return detail is TransferProposalInfo ? detail : null;
  }

  static SafetyFundProposalInfo? _safetyFund(ProposalWithDetail proposal) {
    final detail =
        proposal.businessDetails[MultisigTransferProposalDetailKeys.safetyFund];
    return detail is SafetyFundProposalInfo ? detail : null;
  }

  static SweepProposalInfo? _sweep(ProposalWithDetail proposal) {
    final detail =
        proposal.businessDetails[MultisigTransferProposalDetailKeys.sweep];
    return detail is SweepProposalInfo ? detail : null;
  }

  static bool matches(ProposalWithDetail proposal) {
    return _transfer(proposal) != null ||
        _safetyFund(proposal) != null ||
        _sweep(proposal) != null;
  }

  static String? title(ProposalWithDetail proposal, String proposalId) {
    if (_transfer(proposal) != null) {
      return '转账提案 $proposalId';
    }
    if (_safetyFund(proposal) != null) {
      return '安全基金转账 $proposalId';
    }
    if (_sweep(proposal) != null) {
      return '手续费划转 $proposalId';
    }
    return null;
  }

  static String? subtitle(ProposalWithDetail proposal, String status) {
    final transfer = _transfer(proposal);
    if (transfer != null) {
      return '${AmountFormat.format(transfer.amountYuan, symbol: '')} 元 · $status';
    }
    final safetyFund = _safetyFund(proposal);
    if (safetyFund != null) {
      return '安全基金转账 ${AmountFormat.format(safetyFund.amountYuan, symbol: '')} 元 · $status';
    }
    final sweep = _sweep(proposal);
    if (sweep != null) {
      return '手续费划转 ${AmountFormat.format(sweep.amountYuan, symbol: '')} 元 · $status';
    }
    return null;
  }

  static String? listSummary(ProposalWithDetail proposal) {
    final transfer = _transfer(proposal);
    if (transfer != null) {
      return '转账 ${AmountFormat.format(transfer.amountYuan, symbol: '')} 元';
    }
    final safetyFund = _safetyFund(proposal);
    if (safetyFund != null) {
      return '安全基金转账 ${AmountFormat.format(safetyFund.amountYuan, symbol: '')} 元';
    }
    final sweep = _sweep(proposal);
    if (sweep != null) {
      return '手续费划转 ${AmountFormat.format(sweep.amountYuan, symbol: '')} 元';
    }
    return null;
  }

  static IconData? icon(ProposalWithDetail proposal) {
    if (_transfer(proposal) != null) {
      return Icons.send_outlined;
    }
    if (_safetyFund(proposal) != null) {
      return Icons.health_and_safety_outlined;
    }
    if (_sweep(proposal) != null) {
      return Icons.account_balance_wallet_outlined;
    }
    return null;
  }

  static Future<bool> openDetail(
    BuildContext context, {
    required ProposalWithDetail proposal,
    required InstitutionInfo? institution,
    required ProposalContext proposalContext,
  }) async {
    if (institution == null) {
      return false;
    }

    final proposalId = proposal.meta.proposalId;
    final kind = _detailKind(proposal);
    if (kind == null) {
      return false;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultisigTransferDetailPage(
          institution: institution,
          proposalId: proposalId,
          proposalContext: proposalContext,
          kind: kind,
        ),
      ),
    );
    return true;
  }

  static void clearCache() {
    MultisigTransferCache.clear();
    MultisigTransferProposalFeed.clearCache();
  }

  static MultisigTransferKind? _detailKind(ProposalWithDetail proposal) {
    if (_transfer(proposal) != null) {
      return MultisigTransferKind.transfer;
    }
    if (_safetyFund(proposal) != null) {
      return MultisigTransferKind.safetyFund;
    }
    if (_sweep(proposal) != null) {
      return MultisigTransferKind.sweep;
    }
    return null;
  }
}

/// 多签转账模块导出的提案数据源适配器。
class MultisigTransferProposalFeed {
  MultisigTransferProposalFeed({required MultisigTransferService service})
      : _service = service;

  static const Duration _balanceCacheTtl = Duration(seconds: 10);
  static const Duration _proposalCacheTtl = Duration(seconds: 20);

  static final Map<String, _TimedValue<double>> _balanceCache = {};
  static final Map<String, Future<double>> _balanceInFlight = {};
  static final Map<String, int> _balanceFetchTokens = {};
  static int _nextFetchToken = 0;

  // ADR-018 统一提案查询:当前年全部提案的进程内共享缓存。公民-提案 / 机构详情 /
  // 个人多签同一刷新周期共用同一份,把"每页各自查链"降为"全应用取一次"。
  static _TimedValue<List<ProposalWithDetail>>? _yearProposalsCache;
  static Future<List<ProposalWithDetail>>? _yearProposalsInFlight;

  final MultisigTransferService _service;

  Future<double> fetchInstitutionBalance(
    InstitutionInfo institution, {
    bool forceRefresh = false,
  }) {
    final key = _balanceKey(institution);
    final cached = _balanceCache[key];
    if (!forceRefresh && cached != null && cached.isFresh(_balanceCacheTtl)) {
      return Future.value(cached.value);
    }

    final inFlight = _balanceInFlight[key];
    if (!forceRefresh && inFlight != null) return inFlight;

    final token = ++_nextFetchToken;
    _balanceFetchTokens[key] = token;
    final future = _service.fetchInstitutionBalance(institution).then((value) {
      if (_balanceFetchTokens[key] == token) {
        _balanceCache[key] = _TimedValue(value);
      }
      return value;
    });
    _balanceInFlight[key] = future;
    return future.whenComplete(() {
      if (_balanceInFlight[key] == future) {
        _balanceInFlight.remove(key);
      }
      if (_balanceFetchTokens[key] == token) {
        _balanceFetchTokens.remove(key);
      }
    });
  }

  /// ADR-018 统一提案查询入口:当前年全部提案,进程内共享缓存(TTL 20s)。
  /// 公民-提案 / 机构详情 / 个人多签同周期复用同一份,避免各页面重复查链。
  Future<List<ProposalWithDetail>> currentYearProposals({
    bool forceRefresh = false,
  }) {
    final cached = _yearProposalsCache;
    if (!forceRefresh && cached != null && cached.isFresh(_proposalCacheTtl)) {
      return Future.value(cached.value);
    }
    final inFlight = _yearProposalsInFlight;
    if (!forceRefresh && inFlight != null) return inFlight;

    final future = _service.fetchCurrentYearProposals().then((value) {
      final immutableValue = List<ProposalWithDetail>.unmodifiable(value);
      _yearProposalsCache = _TimedValue(immutableValue);
      return immutableValue;
    });
    _yearProposalsInFlight = future;
    return future.whenComplete(() {
      if (identical(_yearProposalsInFlight, future)) {
        _yearProposalsInFlight = null;
      }
    });
  }

  /// 机构页可见提案:从共享年缓存客户端过滤(本机构内部提案 ∪ 联合投票)。
  Future<List<ProposalWithDetail>> fetchInstitutionVisibleProposals(
    InstitutionInfo institution, {
    bool forceRefresh = false,
  }) async {
    final all = await currentYearProposals(forceRefresh: forceRefresh);
    return _service.filterInstitutionVisible(all, institution);
  }

  /// 公民 tab「提案」统一流 id:默认公共机构码 + 当前钱包订阅机构 CID。
  Future<List<int>> fetchCitizenProposalFeedIds({
    required Set<String> defaultCodes,
    required Set<String> subscribedInstitutionCidNumbers,
    bool forceRefresh = false,
  }) async {
    final all = await currentYearProposals(forceRefresh: forceRefresh);
    return _service.filterCitizenProposalFeedIds(
      all,
      defaultCodes: defaultCodes,
      subscribedInstitutionCidNumbers: subscribedInstitutionCidNumbers,
    );
  }

  /// 治理提案 id:从共享年缓存按机构码过滤,替代 3 次 `ProposalsByOrg` 查询。
  Future<List<int>> fetchGovernanceProposalIds(
    Set<String> codes, {
    bool forceRefresh = false,
  }) async {
    final all = await currentYearProposals(forceRefresh: forceRefresh);
    return _service.filterGovernanceIds(all, codes);
  }

  Future<List<ProposalWithDetail>> fetchProposalsByIds(List<int> ids) {
    return _service.fetchProposalsByIds(ids);
  }

  static void clearCache() {
    _balanceCache.clear();
    _balanceInFlight.clear();
    _balanceFetchTokens.clear();
    _yearProposalsCache = null;
    _yearProposalsInFlight = null;
  }

  static String _balanceKey(InstitutionInfo institution) {
    return '${institution.cidNumber}:${institution.mainAccountId}';
  }
}

class _TimedValue<T> {
  _TimedValue(this.value) : createdAt = DateTime.now();

  final T value;
  final DateTime createdAt;

  bool isFresh(Duration ttl) => DateTime.now().difference(createdAt) < ttl;
}
