import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:citizenapp/log/app_log.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_activation_service.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/institution_admin_service.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/institution/governance_registry.dart';
import 'package:citizenapp/votingengine/internal-vote/internal_vote_query_service.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';
import 'package:citizenapp/citizen/proposal/runtime-upgrade/runtime_upgrade_service.dart';

/// 用户与某个提案的关系上下文。
///
/// 所有提案详情页统一使用该类判断：
/// - 用户是否为该提案对应机构的管理员
/// - 用户可用于投票的冷钱包列表
/// - 用户的角色（admin / citizen / viewer）
class ProposalContext {
  const ProposalContext({
    this.institution,
    this.adminWallets = const [],
    this.role = ProposalRole.viewer,
  });

  /// 匹配到的机构（可能为 null，表示无法关联机构）。
  final InstitutionInfo? institution;

  /// 用户在该机构的管理员冷钱包列表。
  final List<CitizenWalletStateAccount> adminWallets;

  /// 用户角色。
  final ProposalRole role;

  /// 是否有机构上下文（能进行管理员操作）。
  bool get hasInstitutionContext => institution != null;

  /// 是否为管理员。
  bool get isAdmin => role == ProposalRole.admin;

  /// 是否为公民（有链上公民身份）。
  bool get isCitizen =>
      role == ProposalRole.citizen || role == ProposalRole.admin;

  /// 是否有导入的管理员钱包。
  bool get hasAdminWallets => adminWallets.isNotEmpty;
}

/// 用户角色。
enum ProposalRole {
  /// 管理员：有冷钱包匹配到链上管理员列表。
  admin,

  /// 公民：有链上公民身份的钱包（暂未实现，预留）。
  citizen,

  /// 查看者：无关联钱包。
  viewer,
}

/// 提案上下文解析器。
///
/// 统一处理"用户与某提案的关系"解析逻辑，所有入口（治理列表、机构页面）
/// 共用同一套代码，避免重复且保证一致性。
class ProposalContextResolver {
  ProposalContextResolver({
    required CitizenSdkWallet wallet,
    required InstitutionAdminService adminService,
    required ActivationService activationService,
  })  : _adminService = adminService,
        _wallet = wallet,
        _activationService = activationService;

  final InstitutionAdminService _adminService;
  final CitizenSdkWallet _wallet;
  final ActivationService _activationService;

  /// 已缓存的钱包列表（同一次会话内复用）。
  List<CitizenWalletStateAccount>? _wallets;

  /// 静态缓存：用户已确认为管理员的机构 cidNumber 集合。
  ///
  /// 当用户浏览某个机构详情页后，如果匹配到管理员身份，
  /// 该机构 cidNumber 会被加入此集合。机构列表页据此渲染绿色卡片和排序。
  static final Set<String> _institutionAdminIds = {};

  /// 记录某机构的管理员状态。
  static void markInstitutionAdmin(String cidNumber) {
    _institutionAdminIds.add(cidNumber);
  }

  /// 查询某机构是否已确认为管理员。
  static bool isInstitutionAdmin(String cidNumber) {
    return _institutionAdminIds.contains(cidNumber);
  }

  /// 获取所有已确认的管理员机构 cidNumber 集合。
  static Set<String> get institutionAdminIds =>
      Set.unmodifiable(_institutionAdminIds);

  /// 清除管理员机构缓存（如钱包被删除时）。
  static void clearInstitutionAdminCache() {
    _institutionAdminIds.clear();
  }

  /// 解析用户与指定提案的关系。
  ///
  /// [actorCidNumber] 是机构身份唯一真源；[executionAccountId] 只用于个人多签
  /// 或具体账户展示，不能反向覆盖已有 actor CID。
  /// [knownInstitution] 如果调用方已知机构信息（如从机构页面进入），直接传入跳过反查。
  Future<ProposalContext> resolve({
    String? actorCidNumber,
    List<int>? executionAccountId,
    String? internalCode,
    InstitutionInfo? knownInstitution,
  }) async {
    final wallets = await _getWallets();
    final actorCid = actorCidNumber?.trim();
    final code = internalCode?.toUpperCase();
    InstitutionInfo? institution;

    // 机构提案只认 actor CID。调用方传入的已知机构也必须 CID 完全一致，
    // 禁止 execution account 或管理员钱包反向覆盖链上主体。
    if (actorCid != null && actorCid.isNotEmpty) {
      institution = knownInstitution?.cidNumber == actorCid
          ? knownInstitution
          : findInstitutionByCidNumber(actorCid);
    } else if (code == 'PMUL' && executionAccountId != null) {
      // 个人多签没有 CID，且只有 PMUL 才允许 execution account 成为主体。
      final executionAccountIdText = _hexFromBytes(executionAccountId);
      final knownPersonalAccount = knownInstitution == null
          ? null
          : personalAccountIdFromIdentity(knownInstitution.cidNumber);
      institution = knownPersonalAccount == executionAccountIdText
          ? knownInstitution
          : personalMultisigFromAccountId(executionAccountId);
    }

    // 匹配管理员钱包（通过激活状态判断）。
    if (institution == null) {
      return const ProposalContext();
    }

    late final AdminAccountIdentity identity;
    try {
      identity = AdminAccountIdentity.fromInstitution(institution);
      if (institution.isRegisteredInstitution) {
        final threshold = await _adminService.fetchThreshold(
          identity,
        );
        if (threshold != null) {
          institution = institution.copyWith(
            internalThresholdOverride: threshold,
          );
        }
      }
    } catch (_) {
      return ProposalContext(institution: institution);
    }

    // 仅通过激活记录匹配管理员钱包
    final activatedAdmins = await _activationService
        .getActivatedAdmins(identity)
        .catchError((_) => <ActivatedAdmin>[]);

    final matchedWallets = <CitizenWalletStateAccount>[];

    // 已激活的管理员 → 在钱包列表中找到对应钱包
    for (final activated in activatedAdmins) {
      CitizenWalletStateAccount? wallet;
      for (final w in wallets) {
        if (_requireAccountId(w.accountId) == activated.accountId) {
          wallet = w;
          break;
        }
      }
      if (wallet != null &&
          !matchedWallets.any(
            (w) => _requireAccountId(w.accountId) == activated.accountId,
          )) {
        matchedWallets.add(wallet);
      }
    }

    return ProposalContext(
      institution: institution,
      adminWallets: matchedWallets,
      role:
          matchedWallets.isNotEmpty ? ProposalRole.admin : ProposalRole.viewer,
    );
  }

  /// 批量解析多个提案的上下文（用于列表页）。
  ///
  /// 返回 Map<提案索引, ProposalContext>，与传入列表一一对应。
  Future<List<ProposalContext>> resolveBatch(List<String?> actorCidNumbers,
      {List<List<int>?>? executionAccountIds,
      List<String?>? internalCodeList,
      Map<String, InstitutionInfo> knownInstitutionsByCidNumber =
          const {}}) async {
    final wallets = await _getWallets();
    final results = <ProposalContext>[];
    final knownInstitutions = {
      for (final entry in knownInstitutionsByCidNumber.entries)
        entry.key.trim(): entry.value,
    };

    for (var i = 0; i < actorCidNumbers.length; i++) {
      final actorCidNumber = actorCidNumbers[i];
      final executionAccountId =
          executionAccountIds != null && i < executionAccountIds.length
              ? executionAccountIds[i]
              : null;
      final internalCode =
          internalCodeList != null && i < internalCodeList.length
              ? internalCodeList[i]
              : null;
      InstitutionInfo? institution;
      final actorCid = actorCidNumber?.trim();
      final code = internalCode?.toUpperCase();

      if (actorCid != null && actorCid.isNotEmpty) {
        institution =
            knownInstitutions[actorCid] ?? findInstitutionByCidNumber(actorCid);
      } else if (code == 'PMUL' && executionAccountId != null) {
        institution = personalMultisigFromAccountId(executionAccountId);
      }

      if (institution == null) {
        results.add(const ProposalContext());
        continue;
      }

      late final AdminAccountIdentity identity;
      try {
        identity = AdminAccountIdentity.fromInstitution(institution);
        if (institution.isRegisteredInstitution) {
          final threshold = await _adminService.fetchThreshold(
            identity,
          );
          if (threshold != null) {
            institution = institution.copyWith(
              internalThresholdOverride: threshold,
            );
          }
        }
      } catch (_) {
        results.add(ProposalContext(institution: institution));
        continue;
      }

      // 仅通过激活记录匹配管理员钱包
      final activatedAdmins = await _activationService
          .getActivatedAdmins(identity)
          .catchError((_) => <ActivatedAdmin>[]);

      final matchedWallets = <CitizenWalletStateAccount>[];
      for (final activated in activatedAdmins) {
        for (final w in wallets) {
          if (_requireAccountId(w.accountId) == activated.accountId &&
              !matchedWallets.any(
                (m) => _requireAccountId(m.accountId) == activated.accountId,
              )) {
            matchedWallets.add(w);
          }
        }
      }

      results.add(ProposalContext(
        institution: institution,
        adminWallets: matchedWallets,
        role: matchedWallets.isNotEmpty
            ? ProposalRole.admin
            : ProposalRole.viewer,
      ));
    }

    return results;
  }

  /// 清除钱包缓存（钱包列表变化时调用）。
  void clearWalletCache() => _wallets = null;
  // 内部方法
  Future<List<CitizenWalletStateAccount>> _getWallets() async {
    try {
      _wallets ??= (await _wallet.getState()).accounts;
    } catch (e, st) {
      // 治理页的链上内容不能因为钱包公开目录短暂不可用而整体加载失败。
      AppLog.d('[ProposalContext] SDK wallet load failed: $e\n$st');
      _wallets = const [];
    }
    return _wallets!;
  }

  static String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  static String _hexFromBytes(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return '0x$buffer';
  }
}

/// 统一投票状态检查器。
///
/// 根据提案类型（kind）和阶段（stage）自动选择正确的链上存储查询，
/// 避免不同入口查错存储导致的状态不一致。
class VoteChecker {
  VoteChecker({
    required InternalVoteQueryService internalVoteService,
    required RuntimeUpgradeService runtimeService,
    required ProposalQueryService proposalQueryService,
  })  : _internalVoteService = internalVoteService,
        _runtimeService = runtimeService,
        _proposalQueryService = proposalQueryService;

  final InternalVoteQueryService _internalVoteService;
  final RuntimeUpgradeService _runtimeService;
  final ProposalQueryService _proposalQueryService;

  /// 跨提案批量计算"哪些提案存在本机未投票的管理员钱包"。
  ///
  /// (ADR-018 R2):列表页原来按提案逐个查投票(P 个提案 = P 次往返);
  /// 这里把同类提案(内部/联合)的投票 key 各自一次性拼齐批量读取,P 次往返
  /// 降为最多 2 次。只统计 status==0(投票中)且本机有管理员钱包的提案。
  Future<Set<int>> proposalsNeedingVote(List<VoteCheckTarget> targets) async {
    final active =
        targets.where((t) => t.status == 0 && t.adminWallets.isNotEmpty);

    final internalByPid = <int, List<EligibleVoterTicket>>{};
    final jointByPid = <int,
        ({
      String actorCidNumber,
      String voterRoleCode,
      List<String> accountIds
    })>{};
    for (final t in active) {
      final accountIds = t.adminWallets.map((w) => w.accountId).toList();
      if (t.kind == 0 && t.institution != null) {
        final localAccountIds = accountIds.map(_requireAccountId).toSet();
        final tickets = await _proposalQueryService.fetchEligibleVoterTickets(
          t.proposalId,
          t.institution!,
        );
        internalByPid[t.proposalId] = tickets
            .where((ticket) => localAccountIds.contains(ticket.voterAccountId))
            .toList(growable: false);
      } else if (t.kind == 1 && t.institution != null) {
        jointByPid[t.proposalId] = (
          actorCidNumber: t.institution!.cidNumber,
          voterRoleCode: t.institution!.orgType == OrgType.prb
              ? 'DIRECTOR'
              : 'COMMITTEE_MEMBER',
          accountIds: accountIds,
        );
      }
    }

    final needs = <int>{};
    if (internalByPid.isNotEmpty) {
      final votes = await _internalVoteService
          .fetchTicketVotesForProposals(internalByPid);
      internalByPid.forEach((pid, tickets) {
        final m = votes[pid] ?? const <String, bool?>{};
        if (tickets.any((ticket) => m[ticket.ticketKey] == null)) {
          needs.add(pid);
        }
      });
    }
    if (jointByPid.isNotEmpty) {
      final votes =
          await _runtimeService.fetchJointTicketVotesForProposals(jointByPid);
      jointByPid.forEach((pid, v) {
        final m = votes[pid] ?? const <String, bool?>{};
        if (v.accountIds.any(
          (accountId) => m[_requireAccountId(accountId)] == null,
        )) {
          needs.add(pid);
        }
      });
    }
    return needs;
  }

  static String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }
}

/// [VoteChecker.proposalsNeedingVote] 的输入项:一个提案的投票判定所需上下文。
class VoteCheckTarget {
  const VoteCheckTarget({
    required this.proposalId,
    required this.kind,
    required this.status,
    required this.adminWallets,
    this.institution,
  });

  final int proposalId;
  final int kind;
  final int status;
  final List<CitizenWalletStateAccount> adminWallets;
  final InstitutionInfo? institution;
}
