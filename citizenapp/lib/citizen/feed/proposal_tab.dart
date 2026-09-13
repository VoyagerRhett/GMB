import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/citizen/institution/institution.dart';
import 'package:citizenapp/citizen/institution/institution_accounts.dart';
import 'package:citizenapp/citizen/institution/institution_repository.dart';
import 'package:citizenapp/citizen/shared/institution_manage_detail_page.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/pressable_card.dart';
import 'package:citizenapp/ui/widgets/shimmer_loading.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/institution_admin_service.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_activation_service.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_cache.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_context.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_local_store.dart';
import 'package:citizenapp/citizen/proposal/runtime-upgrade/runtime_upgrade_detail_page.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_proposal_adapter.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_service.dart';
import 'package:citizenapp/citizen/proposal/runtime-upgrade/runtime_upgrade_service.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';
import 'package:citizenapp/votingengine/internal-vote/internal_vote_query_service.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 公民 tab「提案」统一列表:默认公共机构 + 当前钱包订阅公权机构,按 ID 倒序。
///
/// **数据源(v1 双层 ID + 当前年缓存)**:
/// - 默认机构码: NRC/NLG/NSN/NRP/NED/NJD/NSP/PRS。
/// - 订阅机构:按当前热钱包订阅的公权机构 CID 精确命中。
/// - 不把全部公权机构提案塞进列表,订阅范围也不得按机构码放大。
///
/// **分页**:cursor 模式按 `_allIds` 切分,翻页天然不会卡空页。
/// **新区块订阅**:周期性重 fetch 可见提案 id 列表,补差异。
class ProposalTab extends StatefulWidget {
  const ProposalTab({
    super.key,
    this.onPendingVoteCountChanged,
  });

  /// 待投票数变化时的回调（用于底部 tab 红点数字）。
  final ValueChanged<int>? onPendingVoteCountChanged;

  @override
  State<ProposalTab> createState() => _ProposalViewState();
}

class _ProposalViewState extends State<ProposalTab> {
  static const int _pageSize = 10;
  static const Duration _newBlockIndexCheckMinInterval = Duration(seconds: 60);

  // 提案页默认公共机构集合独立于“治理”子 tab。
  // 省储委会/省储行不默认进入提案流,只有用户订阅对应机构后才展示。
  static const Set<String> _defaultProposalCodes = {
    'NRC',
    'NLG',
    'NSN',
    'NRP',
    'NED',
    'NJD',
    'NSP',
    'PRS',
  };

  late final MultisigTransferProposalFeed _multisigTransferFeed;
  late final InstitutionAdminService _adminService;
  late final ProposalContextResolver _contextResolver;
  late final VoteChecker _voteChecker;
  final ScrollController _scrollController = ScrollController();
  final InstitutionRepository _institutionRepo = InstitutionRepository();
  late final CitizenSdkWallet _wallet;
  bool _dependenciesReady = false;

  StreamSubscription<CitizenSdkEvent>? _eventSub;

  // 分页状态
  bool _loading = true;
  bool _loadingMore = false;
  // 机构/行政区数据包是否已后台同步（首次进「公民」才触发，不阻塞首屏）。
  bool _directorySynced = false;
  String? _error;
  List<_ProposalDisplayItem> _items = [];

  /// 当前钱包可见提案 ID(降序排列)。
  /// 列表页基于此切分翻页 — cursor `_items.length` 标记已加载到第几条,
  /// `_hasMore = _items.length < _allIds.length`。
  List<int> _allIds = const [];

  /// cidNumber -> InstitutionInfo。列表和详情只按机构唯一 CID 复用上下文。
  Map<String, InstitutionInfo> _knownInstitutionsByCidNumber = const {};

  /// 待投票计数。
  int _pendingVoteCount = 0;

  DateTime? _lastProposalIndexCheckAt;

  bool get _hasMore => _items.length < _allIds.length;
  bool get _isFlutterTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final sdk = context.read<CitizenSdk>();
    _wallet = sdk.wallet;
    final multisigService = MultisigTransferService(
      chain: sdk.chain,
      transactions: sdk.transactions,
    );
    _multisigTransferFeed = MultisigTransferProposalFeed(
      service: multisigService,
    );
    _adminService = InstitutionAdminService(chain: sdk.chain);
    final activationService = ActivationService(adminService: _adminService);
    _contextResolver = ProposalContextResolver(
      wallet: _wallet,
      adminService: _adminService,
      activationService: activationService,
    );
    final proposalQuery = ProposalQueryService(chain: sdk.chain);
    _voteChecker = VoteChecker(
      internalVoteService: InternalVoteQueryService(chain: sdk.chain),
      runtimeService: RuntimeUpgradeService(
        chain: sdk.chain,
        transactions: sdk.transactions,
      ),
      proposalQueryService: proposalQuery,
    );
    _dependenciesReady = true;
    if (_isFlutterTest) {
      // App 启动 widget test 只验证首屏结构，不验证隐藏提案页的轻节点订阅。
      // 组件测试不启动真实 CitizenSDK 链 session，隐藏页不发起链读。
      _loading = false;
      return;
    }
    _loadFirstPage();
    _eventSub = sdk.events.listen((event) {
      if (event is CitizenSdkFinalizedBlockChanged) {
        _checkForNewProposals();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _checkForNewProposals() async {
    final now = DateTime.now();
    final lastCheck = _lastProposalIndexCheckAt;
    if (lastCheck != null &&
        now.difference(lastCheck) < _newBlockIndexCheckMinInterval) {
      return;
    }
    _lastProposalIndexCheckAt = now;

    try {
      final scope = await _fetchVisibleProposalScope();
      final fresh = scope.ids;
      final knownSet = _allIds.toSet();
      final newIds = fresh.where((id) => !knownSet.contains(id)).toList();
      if (newIds.isEmpty) return;

      // 新增提案插到列表顶部。按 proposalId 去重(fresh 在前优先保留),避免
      // 本地缓存 _items 与 _allIds 口径不同步时同一提案出现两张卡片。
      final newItems = await _loadItemsForIds(
        newIds,
        knownInstitutionsByCidNumber: scope.knownInstitutionsByCidNumber,
      );
      if (mounted) {
        setState(() {
          _items = _dedupById([...newItems, ..._items]);
          _allIds = fresh;
          _knownInstitutionsByCidNumber = scope.knownInstitutionsByCidNumber;
        });
        _updatePendingVoteCount();
      }
    } catch (_) {
      // 静默忽略,不阻塞 UI
    }
  }

  // ──── 分页加载 ────

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<
      ({
        Set<String> subscribedInstitutionCidNumbers,
        Map<String, InstitutionInfo> knownInstitutionsByCidNumber,
      })> _loadInstitutionScope() async {
    // 机构/行政区数据包（首装 4.2 万条行政区，秒级~十几秒）**不阻塞**提案流
    // 首屏：后台同步，首次未就绪先按链上机构码兜底显示（代码本就容忍缺数据），
    // 就绪后回刷一次填充机构名。避免首次进「公民」卡十几秒。
    unawaited(_ensureDirectorySyncedThenRefresh());

    final defaultInstitutions = await _institutionRepo
        .listByCodes(_defaultProposalCodes)
        .catchError((_) => <Institution>[]);
    CitizenWalletStateAccount? activeWallet;
    try {
      activeWallet = (await _wallet.getState()).defaultAccount;
    } on Object {
      activeWallet = null;
    }
    final subscribedInstitutions = activeWallet == null
        ? <Institution>[]
        : await _institutionRepo
            .listSubscribed(activeWallet.accountId)
            .catchError((_) => <Institution>[]);

    final known = <String, InstitutionInfo>{};
    for (final inst in [...defaultInstitutions, ...subscribedInstitutions]) {
      final info = _institutionInfoFromInstitution(inst);
      known[info.cidNumber] = info;
    }

    final subscribedCidNumbers = <String>{
      for (final inst in subscribedInstitutions) inst.cidNumber,
    };
    return (
      subscribedInstitutionCidNumbers: subscribedCidNumbers,
      knownInstitutionsByCidNumber: known,
    );
  }

  /// 后台同步机构/行政区数据包；首次就绪且有变更时回刷一次提案流以填机构名。
  /// 幂等：同步过一次后直接返回，回刷再进本方法不会二次同步或二次回刷。
  Future<void> _ensureDirectorySyncedThenRefresh() async {
    if (_directorySynced) return;
    try {
      final changed = await _institutionRepo.directory.ensureSynced();
      _directorySynced = true;
      if (changed && mounted) {
        // 名称就绪后静默回刷（_items 非空则不显示 loading，不闪屏）。
        unawaited(_loadFirstPage(force: true));
      }
    } catch (_) {
      // 同步失败：保持按机构码兜底显示，不阻塞。
    }
  }

  /// 为普通公权机构派生 ProposalContext 使用的 InstitutionInfo。
  InstitutionInfo _institutionInfoFromInstitution(Institution inst) {
    final govInfo = _institutionRepo.governanceInfo(inst.cidNumber);
    if (govInfo != null) return govInfo;
    final rows = institutionAccountIdRows(inst);
    if (rows.length < 2) {
      throw StateError('机构账户集合缺少主账户或费用账户: ${inst.cidNumber}');
    }
    final main = rows.first.accountId;
    final fee = rows[1].accountId;
    return InstitutionInfo(
      cidFullName: inst.cidFullName,
      cidShortName: inst.cidShortNameOrFullName,
      cidFullNameEn: inst.cidFullName,
      cidShortNameEn: inst.cidShortNameOrFullName,
      cidNumber: inst.cidNumber,
      orgType: inst.orgType,
      accounts: InstitutionAccounts(mainAccountId: main, feeAccountId: fee),
      adminAccountCode: inst.institutionCode,
    );
  }

  Future<
      ({
        List<int> ids,
        Map<String, InstitutionInfo> knownInstitutionsByCidNumber,
      })> _fetchVisibleProposalScope({bool forceRefresh = false}) async {
    final institutionScope = await _loadInstitutionScope();
    final ids = await _multisigTransferFeed.fetchCitizenProposalFeedIds(
      defaultCodes: _defaultProposalCodes,
      subscribedInstitutionCidNumbers:
          institutionScope.subscribedInstitutionCidNumbers,
      forceRefresh: forceRefresh,
    );
    return (
      ids: ids,
      knownInstitutionsByCidNumber:
          institutionScope.knownInstitutionsByCidNumber,
    );
  }

  Future<void> _loadFirstPage({bool force = false}) async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
      _loadingMore = false;
    });

    try {
      final scope = await _fetchVisibleProposalScope(forceRefresh: force);
      final ids = scope.ids;

      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _allIds = const [];
          _items = const [];
          _knownInstitutionsByCidNumber = scope.knownInstitutionsByCidNumber;
          _loading = false;
        });
        widget.onPendingVoteCountChanged?.call(0);
        return;
      }

      // 切前 _pageSize 条
      final firstPageIds =
          ids.sublist(0, ids.length < _pageSize ? ids.length : _pageSize);
      final items = await _loadItemsForIds(
        firstPageIds,
        knownInstitutionsByCidNumber: scope.knownInstitutionsByCidNumber,
      );

      if (!mounted) return;
      setState(() {
        _allIds = ids;
        _items = items;
        _knownInstitutionsByCidNumber = scope.knownInstitutionsByCidNumber;
        _loading = false;
      });

      _updatePendingVoteCount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '提案链状态暂时不可用';
        _loading = false;
      });
      widget.onPendingVoteCountChanged?.call(0);
    }
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final from = _items.length;
      final to = (from + _pageSize) > _allIds.length
          ? _allIds.length
          : (from + _pageSize);
      final pageIds = _allIds.sublist(from, to);
      final newItems = await _loadItemsForIds(
        pageIds,
        knownInstitutionsByCidNumber: _knownInstitutionsByCidNumber,
      );

      if (!mounted) return;
      setState(() {
        _items = _dedupById([..._items, ...newItems]);
        _loadingMore = false;
      });

      _updatePendingVoteCount();
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// 给定一组 proposal_id,batch fetch 详情 + 上下文 + 待投票判定,
  /// 返回 `_ProposalDisplayItem` 列表(顺序与入参一致)。
  Future<List<_ProposalDisplayItem>> _loadItemsForIds(
    List<int> ids, {
    Map<String, InstitutionInfo> knownInstitutionsByCidNumber = const {},
  }) async {
    if (ids.isEmpty) return const [];

    // 批量取提案详情(meta + 业务详情)
    final proposals = await _multisigTransferFeed.fetchProposalsByIds(ids);

    // 批量解析提案上下文
    final contexts = await _contextResolver.resolveBatch(
      proposals.map((p) => p.meta.actorCidNumber).toList(),
      executionAccountIds:
          proposals.map((p) => p.meta.executionAccountId?.toList()).toList(),
      internalCodeList: proposals.map((p) => p.meta.internalCode).toList(),
      knownInstitutionsByCidNumber: knownInstitutionsByCidNumber,
    );

    // ADR-018 R2:一次性批量算出"哪些提案需要投票",替代过去每提案各发一次
    // 投票查询 RPC(P 个提案 = P 次往返)。
    final needVote = await _voteChecker.proposalsNeedingVote([
      for (var i = 0; i < proposals.length; i++)
        VoteCheckTarget(
          proposalId: proposals[i].meta.proposalId,
          kind: proposals[i].meta.kind,
          status: proposals[i].meta.status,
          adminWallets: contexts[i].adminWallets,
          institution: contexts[i].institution,
        ),
    ]);

    final items = <_ProposalDisplayItem>[];
    for (var i = 0; i < proposals.length; i++) {
      items.add(_ProposalDisplayItem.fromProposal(
        proposal: proposals[i],
        context: contexts[i],
        needsVote: needVote.contains(proposals[i].meta.proposalId),
      ));
    }

    await ProposalLocalStore.instance.upsertSummaries(
      items.map((item) => item.summary).toList(growable: false),
    );
    return items;
  }

  /// 按 proposalId 去重,保留首次出现(prepend 的 fresh 项优先)。
  /// 防止本地缓存项与新查项口径不同步时同一提案重复成卡片。
  static List<_ProposalDisplayItem> _dedupById(
      List<_ProposalDisplayItem> items) {
    final seen = <int>{};
    final result = <_ProposalDisplayItem>[];
    for (final item in items) {
      if (seen.add(item.proposalId)) result.add(item);
    }
    return result;
  }

  void _updatePendingVoteCount() {
    _pendingVoteCount = _items.where((i) => i.needsVote).length;
    widget.onPendingVoteCountChanged?.call(_pendingVoteCount);
  }

  // ──── UI ────

  @override
  Widget build(BuildContext context) {
    return _buildForeground();
  }

  Widget _buildForeground() {
    if (_loading) {
      return ListSkeleton(
        itemCount: 5,
        itemBuilder: (_, __) => const ProposalCardSkeleton(),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(AppLayout.scaledValue(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: AppLayout.scaledValue(48), color: AppTheme.danger),
              SizedBox(height: AppLayout.scaledValue(12)),
              Text('加载失败',
                  style: TextStyle(
                      fontSize: AppLayout.scaledValue(16),
                      color: AppTheme.textSecondary)),
              SizedBox(height: AppLayout.scaledValue(6)),
              Text(_error!,
                  style: TextStyle(
                      fontSize: AppLayout.scaledValue(12),
                      color: AppTheme.textTertiary),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis),
              SizedBox(height: AppLayout.scaledValue(16)),
              OutlinedButton(
                  onPressed: _loadFirstPage, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty && !_hasMore) {
      // 空态:留给水印,前景透明占位以承接下拉刷新。
      return RefreshIndicator(
        onRefresh: () async {
          _adminService.clearCache();
          _contextResolver.clearWalletCache();
          ProposalCache.clear();
          MultisigTransferProposalAdapter.clearCache();
          await _loadFirstPage(force: true);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: AppLayout.scaledValue(400))],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _adminService.clearCache();
        _contextResolver.clearWalletCache();
        ProposalCache.clear();
        MultisigTransferProposalAdapter.clearCache();
        await _loadFirstPage(force: true);
      },
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: AppLayout.scaledValue(8)),
        itemBuilder: (context, index) {
          if (index < _items.length) {
            return _buildProposalCard(_items[index]);
          }
          // 底部加载指示器
          return Padding(
            padding:
                EdgeInsets.symmetric(vertical: AppLayout.scaled(context, 16)),
            child: Center(
              child: SizedBox(
                width: AppLayout.scaled(context, 24),
                height: AppLayout.scaled(context, 24),
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProposalCard(_ProposalDisplayItem item) {
    final statusColor = _statusColor(item.status);
    final statusLabel = _statusLabel(item.status);

    return PressableCard(
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
          side: BorderSide(color: statusColor.withValues(alpha: 0.2)),
        ),
        child: InkWell(
          onTap: () => _openProposalDetail(item),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaledValue(14),
                vertical: AppLayout.scaledValue(12)),
            child: Row(
              children: [
                // 左侧图标
                Container(
                  width: AppLayout.scaledValue(36),
                  height: AppLayout.scaledValue(36),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius:
                        BorderRadius.circular(AppLayout.scaledValue(10)),
                  ),
                  child: Icon(_proposalIcon(item),
                      size: AppLayout.scaledValue(18), color: statusColor),
                ),
                SizedBox(width: AppLayout.scaledValue(12)),
                // 中间信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            item.displayId,
                            style: TextStyle(
                              fontSize: AppLayout.scaledValue(15),
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                          SizedBox(width: AppLayout.scaledValue(8)),
                          if (item.cidFullName != null)
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: AppLayout.scaledValue(6),
                                  vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryDark
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(
                                    AppLayout.scaledValue(8)),
                              ),
                              child: Text(
                                item.cidFullName!,
                                style: TextStyle(
                                    fontSize: AppLayout.scaledValue(10),
                                    color: AppTheme.primaryDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: AppLayout.scaledValue(2)),
                      Text(
                        item.summary.listSubtitle,
                        style: TextStyle(
                            fontSize: AppLayout.scaledValue(12),
                            color: AppTheme.textTertiary),
                      ),
                    ],
                  ),
                ),
                // 右侧状态 + 红点
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: AppLayout.scaledValue(8),
                          vertical: AppLayout.scaledValue(2)),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppLayout.scaledValue(10)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                            fontSize: AppLayout.scaledValue(11),
                            fontWeight: FontWeight.w600,
                            color: statusColor),
                      ),
                    ),
                    if (item.needsVote) ...[
                      SizedBox(height: AppLayout.scaledValue(4)),
                      Container(
                        width: AppLayout.scaledValue(8),
                        height: AppLayout.scaledValue(8),
                        decoration: const BoxDecoration(
                          color: AppTheme.danger,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(width: AppLayout.scaledValue(4)),
                Icon(Icons.chevron_right,
                    size: AppLayout.scaledValue(20),
                    color: AppTheme.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(int status) {
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

  Color _statusColor(int status) => AppTheme.proposalStatusColor(status);

  /// 根据提案类型返回图标。
  IconData _proposalIcon(
    _ProposalDisplayItem item,
  ) {
    return switch (item.summary.iconKind) {
      'transfer' => Icons.send_outlined,
      'safety_fund' => Icons.health_and_safety_outlined,
      'sweep' => Icons.account_balance_wallet_outlined,
      'create_multisig' => Icons.group_add,
      'close_multisig' => Icons.group_remove,
      'runtime_upgrade' => Icons.arrow_upward,
      'resolution_issuance' => Icons.add_circle_outline,
      'resolution_destroy' => Icons.remove_circle_outline,
      'joint' => Icons.groups_outlined,
      _ => Icons.description_outlined,
    };
  }

  Future<void> _openProposalDetail(_ProposalDisplayItem item) async {
    final resolved = await _resolveProposalDetail(item);
    if (!mounted) return;
    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提案详情读取失败，请稍后重试')),
      );
      return;
    }
    final (:proposal, :proposalContext) = resolved;
    final inst = proposalContext.institution;
    final proposalId = proposal.meta.proposalId;

    // 协议升级提案（联合投票，kind=1）
    if (proposal.runtimeUpgradeDetail != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RuntimeUpgradeDetailPage(
            proposalId: proposalId,
            proposalContext: proposalContext,
          ),
        ),
      );
    } else if (MultisigTransferProposalAdapter.matches(proposal)) {
      await MultisigTransferProposalAdapter.openDetail(
        context,
        proposal: proposal,
        institution: inst,
        proposalContext: proposalContext,
      );
    } else if ((proposal.createMultisigDetail != null ||
            proposal.closeMultisigDetail != null) &&
        inst != null) {
      // 多签管理提案
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MultisigProposalDetailPage(
            institution: inst,
            proposalId: proposalId,
            proposalContext: proposalContext,
          ),
        ),
      );
    } else {
      // 其他未知类型
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该提案类型的详情页面正在开发中')),
      );
      return;
    }

    // 返回后刷新
    if (mounted) {
      _adminService.clearCache();
      ProposalCache.clear();
      MultisigTransferProposalAdapter.clearCache();
      _loadFirstPage(force: true);
    }
  }

  Future<({ProposalWithDetail proposal, ProposalContext proposalContext})?>
      _resolveProposalDetail(_ProposalDisplayItem item) async {
    final existingProposal = item.proposal;
    final existingContext = item.context;
    if (existingProposal != null && existingContext != null) {
      return (proposal: existingProposal, proposalContext: existingContext);
    }

    try {
      final proposals =
          await _multisigTransferFeed.fetchProposalsByIds([item.proposalId]);
      if (proposals.isEmpty) return null;
      final proposal = proposals.first;
      final contexts = await _contextResolver.resolveBatch(
        [proposal.meta.actorCidNumber],
        executionAccountIds: [proposal.meta.executionAccountId?.toList()],
        internalCodeList: [proposal.meta.internalCode],
        knownInstitutionsByCidNumber: _knownInstitutionsByCidNumber,
      );
      final proposalContext =
          contexts.isEmpty ? const ProposalContext() : contexts.first;
      final resolvedItem = _ProposalDisplayItem.fromProposal(
        proposal: proposal,
        context: proposalContext,
        needsVote: item.needsVote,
      );
      await ProposalLocalStore.instance.upsertSummaries([
        resolvedItem.summary,
      ]);
      if (mounted) {
        setState(() {
          _items = [
            for (final current in _items)
              if (current.proposalId == item.proposalId)
                resolvedItem
              else
                current,
          ];
        });
      }
      return (proposal: proposal, proposalContext: proposalContext);
    } catch (_) {
      return null;
    }
  }
}

class _ProposalDisplayItem {
  const _ProposalDisplayItem({
    required this.summary,
    this.proposal,
    this.context,
    this.needsVote = false,
  });

  factory _ProposalDisplayItem.fromProposal({
    required ProposalWithDetail proposal,
    required ProposalContext context,
    bool needsVote = false,
  }) {
    return _ProposalDisplayItem(
      proposal: proposal,
      context: context,
      summary: LocalProposalSummary.fromProposal(
        proposal,
        institution: context.institution,
      ),
      needsVote: needsVote,
    );
  }

  final LocalProposalSummary summary;
  final ProposalWithDetail? proposal;
  final ProposalContext? context;
  final bool needsVote;

  int get proposalId => summary.proposalId;
  int get status => summary.status;
  String get displayId => summary.displayId;
  String? get cidFullName =>
      context?.institution?.cidFullName ?? summary.cidFullName;
}
