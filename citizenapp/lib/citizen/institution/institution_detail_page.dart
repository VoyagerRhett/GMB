import 'package:provider/provider.dart';

import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/institution/institution.dart';
import 'package:citizenapp/citizen/institution/institution_accounts.dart';
import 'package:citizenapp/citizen/institution/institution_accounts_page.dart';
import 'package:citizenapp/citizen/institution/institution_chain_state.dart';
import 'package:citizenapp/citizen/institution/institution_classification.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/citizen/institution/institution_repository.dart';
import 'package:citizenapp/citizen/public/public_institution_admin_list_page.dart';
import 'package:citizenapp/citizen/legislation/data/law_models.dart';
import 'package:citizenapp/citizen/legislation/law_list_page.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_activation_service.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/institution_admin_service.dart';
import 'package:citizenapp/citizen/proposal/proposal_entry_page.dart';
import 'package:citizenapp/citizen/shared/institution_manage_detail_page.dart';
import 'package:citizenapp/citizen/institution/institution_admin_list_page.dart';
import 'package:citizenapp/citizen/proposal/runtime-upgrade/runtime_upgrade_detail_page.dart';
import 'package:citizenapp/citizen/institution/institution_role_models.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_context.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_local_store.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_proposal_adapter.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_service.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 统一机构详情页(ADR-028 决策 2/6)——替代公权 `PublicInstitutionDetailPage`
/// 与治理 `InstitutionDetailPage` 两套。
///
/// 公共壳(信息卡/账户/管理员/提案列表/关注)对全部机构统一;按机构类型
/// dispatch 重型流:
/// - 储备治理三档(NRC/PRC/PRB):提案列表可点→`_openProposalDetail`;
/// - 其余注册机构:提案列表仍走只读摘要,但发起提案/管理员激活共用统一入口。
/// 提案能力由 `ProposalCapabilityRegistry` 判断,详情页不再散落机构码 if。
class InstitutionDetailPage extends StatefulWidget {
  const InstitutionDetailPage({
    super.key,
    required this.cidNumber,
    required this.repository,
    this.chainState,
    this.subscriberCidNumberProvider,
  });

  final String cidNumber;
  final InstitutionRepository repository;

  /// 链态读服务(余额/管理员/提案);测试注入,默认 Live。
  final InstitutionChainState? chainState;

  /// 当前已注册公民的永久 CID（只用于本地关注关系归属）。
  ///
  /// 账户换绑后 CID 不变，因此关注列表不会随签名账户切换而分叉。
  final Future<String?> Function()? subscriberCidNumberProvider;

  @override
  State<InstitutionDetailPage> createState() => _InstitutionDetailPageState();
}

class _InstitutionDetailPageState extends State<InstitutionDetailPage> {
  late final InstitutionChainState _chainState;
  InstitutionAdminService? _adminService;
  CitizenSdkWallet? _wallet;
  MultisigTransferProposalFeed? _multisigTransferFeed;
  ActivationService? _activationService;
  ProposalContextResolver? _contextResolver;
  bool _dependenciesReady = false;

  Institution? _inst;

  /// 提案/管理员入口使用的链上主体信息。所有机构都以目录或静态注册表中的
  /// CID 为唯一身份；账户集合只用于具体资金操作。
  InstitutionInfo? _govInfo;
  bool get _isGovernance =>
      InstitutionClassification.isGovernance(_inst?.institutionCode ?? '');

  bool _loading = true;

  String? _subscriberCidNumber;
  bool _subscribed = false;

  List<InstitutionAccountRow> _accounts = const [];
  String _areaPath = '';

  double? _mainBalanceYuan;
  bool _mainBalanceLoading = true;

  List<InstitutionAdminView> _adminViews = const [];

  // 治理路径专用(管理员角色 / 激活 / 富提案列表)。
  List<CitizenWalletStateAccount> _adminWallets = const [];
  bool _isCurrentUserAdmin = false;
  Set<String> _importedColdAccountIds = const {};
  Set<String> _activatedAccountIds = const {};
  List<LocalProposalSummary> _govProposals = const [];
  Map<int, ProposalWithDetail> _govProposalDetailsById = const {};

  // 公权路径专用(只读提案摘要)。
  List<InstitutionProposalSummary> _publicProposals = const [];

  AdminAccountIdentity? get _accountIdentity {
    final info = _govInfo;
    if (info == null) return null;
    try {
      return AdminAccountIdentity.fromInstitution(info);
    } on ArgumentError {
      // 非治理且非注册账户身份暂无法解析 → 优雅降级(提案入口仍开,但需激活后才能发起)。
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final sdk = context.read<CitizenSdk?>();
    if (sdk == null) {
      final injectedChainState = widget.chainState;
      if (injectedChainState == null) {
        throw StateError('机构详情缺少 CitizenSDK');
      }
      // 只读 Widget 夹具可直接注入已经完成链投影的 InstitutionChainState；
      // 正式 App 根始终走下方唯一 CitizenSDK 实例。
      _chainState = injectedChainState;
      _dependenciesReady = true;
      _load();
      return;
    }
    final wallet = sdk.wallet;
    _wallet = wallet;
    final multisigService = MultisigTransferService(
      chain: sdk.chain,
      transactions: sdk.transactions,
    );
    final multisigFeed = MultisigTransferProposalFeed(service: multisigService);
    _multisigTransferFeed = multisigFeed;
    final adminService = InstitutionAdminService(chain: sdk.chain);
    _adminService = adminService;
    final activationService = ActivationService(adminService: adminService);
    _activationService = activationService;
    _chainState =
        widget.chainState ??
        LiveInstitutionChainState(
          chain: sdk.chain,
          transactions: sdk.transactions,
          adminService: adminService,
          feed: multisigFeed,
        );
    _contextResolver = ProposalContextResolver(
      wallet: wallet,
      adminService: adminService,
      activationService: activationService,
    );
    _dependenciesReady = true;
    _load();
  }

  Future<String?> _resolveSubscriberCidNumber() async {
    final provider = widget.subscriberCidNumberProvider;
    if (provider != null) return provider();
    final identity = await context.read<CurrentUserContext>().resolve();
    return identity?.cidNumber;
  }

  Future<void> _load() async {
    final inst = await widget.repository.getByCid(widget.cidNumber);
    final subscriberCidNumber = await _resolveSubscriberCidNumber();
    if (!mounted) return;
    if (inst == null) {
      setState(() => _loading = false);
      return;
    }
    // 全机构统一开提案入口:固定治理档使用静态档(含安全基金等专户),其余机构
    // 由目录 CID 派生主体。是否能发起某类提案交给 ProposalCapabilityRegistry。
    final govInfo =
        widget.repository.governanceInfo(inst.cidNumber) ??
        _infoFromInstitution(inst);
    final subscribed = subscriberCidNumber == null
        ? false
        : await widget.repository.isSubscribed(
            subscriberCidNumber,
            inst.cidNumber,
          );
    final areaPath = await widget.repository.institutionAreaPath(inst);
    if (!mounted) return;
    setState(() {
      _inst = inst;
      _govInfo = govInfo;
      _subscriberCidNumber = subscriberCidNumber;
      _subscribed = subscribed;
      _accounts = institutionAccountIdRows(inst);
      _areaPath = areaPath;
      _loading = false;
    });
    unawaited(_loadDynamics());
  }

  /// 为非治理注册机构从 Institution 派生 InstitutionInfo。
  /// CID 始终是机构主键，主/费账户只进入具体账户操作。
  InstitutionInfo _infoFromInstitution(Institution inst) {
    final rows = institutionAccountIdRows(inst);
    if (rows.length < 2) {
      throw StateError('机构账户集合缺少主账户或费用账户: ${inst.cidNumber}');
    }
    final main = rows.first.accountId;
    final fee = rows[1].accountId;
    return InstitutionInfo(
      cidFullName: inst.cidFullName,
      cidShortName: inst.cidShortNameOrFullName,
      cidFullNameEn: inst.cidFullName, // 普通公权机构暂无英文名,中文兜底
      cidShortNameEn: inst.cidShortNameOrFullName,
      cidNumber: inst.cidNumber,
      orgType: inst.orgType,
      accounts: InstitutionAccounts(mainAccountId: main, feeAccountId: fee),
      adminAccountCode: inst.institutionCode,
    );
  }

  Future<void> _loadDynamics({bool force = false}) async {
    final inst = _inst;
    if (inst == null) return;

    // 主账户余额(批量接口查一条)。
    final mainHex = _accounts.isNotEmpty ? _accounts.first.accountId : '';
    try {
      final balances = await _chainState.balances([mainHex]);
      if (mounted) {
        setState(() {
          _mainBalanceYuan = balances[mainHex];
          _mainBalanceLoading = false;
        });
      }
    } on Exception {
      if (mounted) setState(() => _mainBalanceLoading = false);
    }

    if (_isGovernance) {
      await _loadGovernanceAdminsAndRole(force: force);
      await _loadGovernanceProposals(force: force);
    } else {
      unawaited(_loadGovernanceAdminsAndRole(force: force));
      await _loadPublicDynamics(inst);
    }
  }

  // ──── 管理员角色加载(固定治理与注册机构账户共用)────

  Future<void> _loadGovernanceAdminsAndRole({bool force = false}) async {
    final identity = _accountIdentity;
    final govInfo = _govInfo;
    final adminService = _adminService;
    final contextResolver = _contextResolver;
    final activationService = _activationService;
    if (identity == null ||
        govInfo == null ||
        adminService == null ||
        contextResolver == null ||
        activationService == null) {
      return;
    }
    if (force) {
      adminService.clearCache(identity);
      contextResolver.clearWalletCache();
    }
    try {
      final results = await Future.wait<Object>([
        adminService.fetchAdminViews(identity, _inst!.cidNumber),
        contextResolver.resolve(knownInstitution: govInfo),
        activationService
            .getActivatedAdmins(identity)
            .catchError((_) => <ActivatedAdmin>[]),
      ]);
      final adminViews = results[0] as List<InstitutionAdminView>;
      final adminAccountIds = adminViews
          .map((view) => view.admin.account_id)
          .toList(growable: false);
      final ctx = results[1] as ProposalContext;
      final activated = results[2] as List<ActivatedAdmin>;
      final coldAccountIds = await _loadImportedColdAccountIds(adminAccountIds);
      if (ctx.isAdmin) {
        ProposalContextResolver.markInstitutionAdmin(
          _inst?.cidNumber ?? govInfo.cidNumber,
        );
      }
      if (!mounted) return;
      final shouldUpdateAdmins =
          _isGovernance || adminViews.isNotEmpty || _adminViews.isEmpty;
      setState(() {
        if (shouldUpdateAdmins) {
          _adminViews = adminViews;
        }
        _govInfo = ctx.institution ?? govInfo;
        _adminWallets = ctx.adminWallets;
        _importedColdAccountIds = coldAccountIds;
        _activatedAccountIds = activated.map((a) => a.accountId).toSet();
        _isCurrentUserAdmin = ctx.isAdmin;
      });
    } catch (_) {
      // 联网失败保持空,不崩(治理角色仅影响发起入口可用态)。
    }
  }

  Future<Set<String>> _loadImportedColdAccountIds(
    List<String> adminAccountIds,
  ) async {
    final wallet = _wallet;
    if (wallet == null) return const {};
    final coldAccountIds = <String>{};
    try {
      final allWallets = (await wallet.getState()).accounts;
      for (final w in allWallets) {
        if (w.signMode == CitizenWalletSignMode.cold) {
          if (adminAccountIds.contains(w.accountId)) {
            coldAccountIds.add(w.accountId);
          }
        }
      }
    } on Exception {
      // 本地钱包库异常不影响展示。
    }
    return coldAccountIds;
  }

  Future<void> _loadGovernanceProposals({bool force = false}) async {
    final govInfo = _govInfo;
    final feed = _multisigTransferFeed;
    if (govInfo == null || feed == null) return;
    try {
      final proposals = await feed.fetchInstitutionVisibleProposals(
        govInfo,
        forceRefresh: force,
      );
      final summaries = proposals
          .map(
            (p) => LocalProposalSummary.fromProposal(p, institution: govInfo),
          )
          .toList(growable: false);
      await ProposalLocalStore.instance.upsertSummaries(summaries);
      await ProposalLocalStore.instance.putInstitutionIndex(
        govInfo.cidNumber,
        summaries.map((s) => s.proposalId).toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _govProposals = summaries;
        _govProposalDetailsById = {
          for (final p in proposals) p.meta.proposalId: p,
        };
      });
    } catch (_) {
      // 同上,保持空。
    }
  }

  // ──── 注册机构路径加载 ────

  Future<void> _loadPublicDynamics(Institution inst) async {
    try {
      final adminViews = await _chainState.adminViews(inst);
      if (mounted) {
        setState(() {
          _adminViews = adminViews;
        });
      }
    } on Exception {
      // 保持空。
    }
    try {
      final proposals = await _chainState.proposals(inst);
      if (mounted) setState(() => _publicProposals = proposals);
    } on Exception {
      // 保持空。
    }
  }

  Future<void> _toggleSubscribe() async {
    final inst = _inst;
    final subscriberCidNumber = _subscriberCidNumber;
    if (inst == null || subscriberCidNumber == null) return;
    if (_subscribed) {
      await widget.repository.unsubscribe(subscriberCidNumber, inst.cidNumber);
    } else {
      await widget.repository.subscribe(subscriberCidNumber, inst.cidNumber);
    }
    if (!mounted) return;
    setState(() => _subscribed = !_subscribed);
  }

  @override
  Widget build(BuildContext context) {
    final inst = _inst;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: Text(inst?.cidShortNameOrFullName ?? '机构'),
        backgroundColor: AppTheme.surfaceCard,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          if (inst != null && _subscriberCidNumber != null)
            IconButton(
              tooltip: _subscribed ? '取消关注' : '订阅关注',
              icon: Icon(
                _subscribed ? Icons.bookmark : Icons.bookmark_border,
                color: _subscribed ? AppTheme.primary : AppTheme.textSecondary,
              ),
              onPressed: _toggleSubscribe,
            ),
        ],
      ),
      body: _buildBody(inst),
    );
  }

  Widget _buildBody(Institution? inst) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (inst == null) {
      return const Center(
        child: Text('未找到该机构', style: TextStyle(color: AppTheme.textTertiary)),
      );
    }
    return ListView(
      padding: EdgeInsets.all(AppLayout.scaledValue(16)),
      children: [
        _infoCard(inst),
        SizedBox(height: AppLayout.scaledValue(12)),
        _accountsEntry(inst),
        SizedBox(height: AppLayout.scaledValue(12)),
        _proposalEntry(),
        // 法律原文(仅立法机构):查看该机构全部法律。发起立法=类B,归口提案入口
        // (proposal_entry_page,按 registry 立法机构→发起立法),不在详情页另设入口。
        if (_lawTarget(inst) != null) ...[
          SizedBox(height: AppLayout.scaledValue(12)),
          _lawOriginalEntry(inst),
        ],
        SizedBox(height: AppLayout.scaledValue(12)),
        _adminsEntry(),
        SizedBox(height: AppLayout.scaledValue(12)),
        _proposalList(),
      ],
    );
  }

  // ── ① 机构信息卡(全称/身份CID号/主账户/余额/法代/所属地;非法人 +所属上级法人) ──

  Widget _infoCard(Institution inst) {
    final mainSs58 = _accounts.isNotEmpty ? _accounts.first.ss58Address : '—';
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaledValue(14),
          vertical: AppLayout.scaledValue(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoTile(
              icon: Icons.account_balance_outlined,
              label: '全称',
              value: inst.cidFullName,
            ),
            Divider(height: AppLayout.scaledValue(18)),
            _infoTile(
              icon: Icons.badge_outlined,
              label: '身份CID号',
              value: inst.cidNumber,
            ),
            Divider(height: AppLayout.scaledValue(18)),
            _infoTile(
              icon: Icons.account_balance_wallet_outlined,
              label: '主账户',
              value: mainSs58,
            ),
            Divider(height: AppLayout.scaledValue(18)),
            _infoTile(
              icon: Icons.payments_outlined,
              label: '主账户余额',
              value: _mainBalanceLabel(),
            ),
            Divider(height: AppLayout.scaledValue(18)),
            _infoTile(
              icon: Icons.person_outline,
              label: '法定代表人',
              value: '${inst.familyName ?? ''}${inst.givenName ?? ''}',
            ),
            Divider(height: AppLayout.scaledValue(18)),
            _infoTile(
              icon: Icons.place_outlined,
              label: '所属地',
              value: _areaPath,
            ),
            // 非法人加显「所属上级法人全称」(ADR-028 决策 6)。
            if (inst.isUnincorporated) ...[
              Divider(height: AppLayout.scaledValue(18)),
              _infoTile(
                icon: Icons.account_tree_outlined,
                label: '所属上级法人',
                value: inst.parentCidNumber ?? '',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _mainBalanceLabel() {
    if (_mainBalanceLoading) return '读取中...';
    final yuan = _mainBalanceYuan;
    if (yuan == null) return '未激活';
    return '${AmountFormat.formatThousands(yuan)} 元';
  }

  // ──── ② 机构账户入口 ────

  Widget _accountsEntry(Institution inst) {
    return _entryCard(
      icon: Icons.account_balance_wallet_outlined,
      title: '机构账户',
      subtitle: '共 ${_accounts.length} 个账户',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InstitutionAccountsPage(
            institution: inst,
            chainState: _chainState,
          ),
        ),
      ),
    );
  }

  // ──── ③ 提案入口(按主体能力统一展示)────

  Widget _proposalEntry() {
    return _entryCard(
      icon: Icons.how_to_vote_outlined,
      title: '发起提案',
      subtitle: _isCurrentUserAdmin
          ? '转账 / 管理员更换 / …（链上按岗位授权）'
          : '激活机构签名钱包后按岗位授权发起',
      onTap: _openProposalTypes,
    );
  }

  // ──── 法律原文入口(仅立法机构,ADR-028 P3-1)────

  /// 立法机构 → (tier, scope_code);非立法机构返回 null。国家级 scope=0;省/市级
  /// scope 取行政区数字 code(省码为字母时回退 0,待链端有省/市级法律后核验映射;
  /// 当前仅宪法 law_id=0 经顶部卡直达,本入口对其余立法机构暂为空)。
  ({LawTier tier, int scope})? _lawTarget(Institution inst) {
    const national = {'NLG', 'NRP', 'NSN', 'NED'};
    const provincial = {'PLG', 'PRP', 'PSN'};
    const municipal = {'CLEG'};
    final code = inst.institutionCode;
    if (national.contains(code)) return (tier: LawTier.national, scope: 0);
    if (provincial.contains(code)) {
      return (
        tier: LawTier.provincial,
        scope: int.tryParse(inst.provinceCode) ?? 0,
      );
    }
    if (municipal.contains(code)) {
      return (tier: LawTier.municipal, scope: int.tryParse(inst.cityCode) ?? 0);
    }
    return null;
  }

  Widget _lawOriginalEntry(Institution inst) {
    final target = _lawTarget(inst)!;
    return _entryCard(
      icon: Icons.menu_book_outlined,
      title: '法律原文',
      subtitle: '该机构制定的全部法律',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LawListPage(
            tier: target.tier,
            scopeCode: target.scope,
            title: '${inst.cidShortNameOrFullName} · 法律原文',
          ),
        ),
      ),
    );
  }

  Future<void> _openProposalTypes() async {
    final govInfo = _govInfo;
    if (govInfo == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProposalEntryPage(
          institution: govInfo,
          institutionCode: _inst?.institutionCode ?? '',
          icon: Icons.account_balance,
          badgeColor: AppTheme.primary,
          adminWallets: _adminWallets,
          isActivated: _isCurrentUserAdmin,
        ),
      ),
    );
    if (mounted) unawaited(_loadDynamics(force: true));
  }

  // ──── ④ 管理员入口(治理→AdminListPage 含激活;公权→只读列表)────

  Widget _adminsEntry() {
    return _entryCard(
      icon: Icons.people_outline,
      title: '管理员',
      subtitle: '共 ${_adminViews.length} 位管理员',
      onTap: _accountIdentity != null
          ? _openGovernanceAdminList
          : _openPublicAdminList,
    );
  }

  void _openGovernanceAdminList() {
    final govInfo = _govInfo;
    final identity = _accountIdentity;
    if (govInfo == null || identity == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminListPage(
          institution: govInfo,
          accountIdentity: identity,
          admins: _adminViews,
          importedColdAccountIds: _importedColdAccountIds,
          activatedAccountIds: _activatedAccountIds,
          badgeColor: AppTheme.primary,
          onActivated: () {
            _adminService?.clearCache(identity);
            _contextResolver?.clearWalletCache();
            unawaited(_loadGovernanceAdminsAndRole());
          },
        ),
      ),
    );
  }

  void _openPublicAdminList() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicInstitutionAdminListPage(admins: _adminViews),
      ),
    );
  }

  // ──── ⑤ 提案列表 ────

  Widget _proposalList() {
    final hasGov = _isGovernance && _govProposals.isNotEmpty;
    final hasPublic = !_isGovernance && _publicProposals.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: AppLayout.scaledValue(2),
            bottom: AppLayout.scaledValue(12),
          ),
          child: Text(
            '提案列表',
            style: TextStyle(
              fontSize: AppLayout.scaledValue(16),
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
        if (!hasGov && !hasPublic)
          _emptyProposalState()
        else if (_isGovernance)
          ...List.generate(_govProposals.length, (i) {
            final s = _govProposals[i];
            return Padding(
              padding: EdgeInsets.only(
                bottom: AppLayout.scaledValue(
                  i < _govProposals.length - 1 ? 10 : 0,
                ),
              ),
              child: _govProposalCard(s),
            );
          })
        else
          ...List.generate(_publicProposals.length, (i) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: AppLayout.scaledValue(
                  i < _publicProposals.length - 1 ? 10 : 0,
                ),
              ),
              child: _publicProposalCard(_publicProposals[i]),
            );
          }),
      ],
    );
  }

  Widget _emptyProposalState() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppLayout.scaledValue(24)),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.ballot_outlined,
            size: AppLayout.scaledValue(40),
            color: AppTheme.textTertiary,
          ),
          SizedBox(height: AppLayout.scaledValue(8)),
          Text(
            '暂无提案',
            style: TextStyle(
              fontSize: AppLayout.scaledValue(14),
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // 治理:可点卡片 → _openProposalDetail。
  Widget _govProposalCard(LocalProposalSummary s) {
    final statusColor = AppTheme.proposalStatusColor(s.status);
    return InkWell(
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
      onTap: () => _openProposalDetail(s),
      child: _proposalCardBody(
        title: s.displayId,
        subtitle: s.listSubtitle,
        statusColor: statusColor,
        statusLabel: _statusLabel(s.status),
        trailingChevron: true,
      ),
    );
  }

  // 公权:只读卡片。
  Widget _publicProposalCard(InstitutionProposalSummary p) {
    final statusColor = AppTheme.proposalStatusColor(p.status);
    return _proposalCardBody(
      title: p.idLabel,
      subtitle: null,
      statusColor: statusColor,
      statusLabel: p.statusLabel,
      trailingChevron: false,
    );
  }

  Widget _proposalCardBody({
    required String title,
    required String? subtitle,
    required Color statusColor,
    required String statusLabel,
    required bool trailingChevron,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppLayout.scaledValue(14),
        vertical: AppLayout.scaledValue(12),
      ),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: AppLayout.scaledValue(36),
            height: AppLayout.scaledValue(36),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
            ),
            child: Icon(
              Icons.how_to_vote_outlined,
              size: AppLayout.scaledValue(18),
              color: statusColor,
            ),
          ),
          SizedBox(width: AppLayout.scaledValue(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(15),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryDark,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  SizedBox(height: AppLayout.scaledValue(2)),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(12),
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaledValue(8),
              vertical: AppLayout.scaledValue(2),
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(11),
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          if (trailingChevron) ...[
            SizedBox(width: AppLayout.scaledValue(4)),
            Icon(
              Icons.chevron_right,
              size: AppLayout.scaledValue(20),
              color: AppTheme.textTertiary,
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(int status) => switch (status) {
    1 => '已通过',
    2 => '已拒绝',
    3 => '已执行',
    4 => '执行失败',
    _ => '投票中',
  };

  // ──── 治理提案详情路由(port 自治理详情页)────

  Future<void> _openProposalDetail(LocalProposalSummary summary) async {
    final govInfo = _govInfo;
    if (govInfo == null) return;
    final proposal = await _resolveProposalDetail(summary);
    if (!mounted) return;
    if (proposal == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('提案详情读取失败，请稍后重试')));
      return;
    }
    final proposalId = proposal.meta.proposalId;
    final ctx = ProposalContext(
      institution: govInfo,
      adminWallets: _adminWallets,
      role: _isCurrentUserAdmin ? ProposalRole.admin : ProposalRole.viewer,
    );
    if (proposal.runtimeUpgradeDetail != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RuntimeUpgradeDetailPage(
            proposalId: proposalId,
            proposalContext: ctx,
          ),
        ),
      );
    } else if (MultisigTransferProposalAdapter.matches(proposal)) {
      await MultisigTransferProposalAdapter.openDetail(
        context,
        proposal: proposal,
        institution: govInfo,
        proposalContext: ctx,
      );
    } else if (proposal.createMultisigDetail != null ||
        proposal.closeMultisigDetail != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MultisigProposalDetailPage(
            institution: govInfo,
            proposalId: proposalId,
            proposalContext: ctx,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该联合提案详情页正在开发中')));
      return;
    }
    if (mounted) unawaited(_loadDynamics(force: true));
  }

  Future<ProposalWithDetail?> _resolveProposalDetail(
    LocalProposalSummary summary,
  ) async {
    final cached = _govProposalDetailsById[summary.proposalId];
    if (cached != null) return cached;
    final feed = _multisigTransferFeed;
    if (feed == null) return null;
    try {
      final fresh = await feed.fetchProposalsByIds([summary.proposalId]);
      if (fresh.isEmpty) return null;
      final proposal = fresh.first;
      if (mounted) {
        setState(() {
          _govProposalDetailsById = {
            ..._govProposalDetailsById,
            proposal.meta.proposalId: proposal,
          };
        });
      }
      return proposal;
    } catch (_) {
      return null;
    }
  }

  // ──── 公用零件 ────

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: AppLayout.scaledValue(32),
          height: AppLayout.scaledValue(32),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(AppLayout.scaledValue(9)),
          ),
          child: Icon(
            icon,
            size: AppLayout.scaledValue(16),
            color: AppTheme.primary,
          ),
        ),
        SizedBox(width: AppLayout.scaledValue(10)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(11),
                  color: AppTheme.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: AppLayout.scaledValue(2)),
              Text(
                value,
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(13),
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _entryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(14),
            vertical: AppLayout.scaledValue(12),
          ),
          child: Row(
            children: [
              Container(
                width: AppLayout.scaledValue(36),
                height: AppLayout.scaledValue(36),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(
                    AppLayout.scaledValue(10),
                  ),
                ),
                child: Icon(
                  icon,
                  size: AppLayout.scaledValue(18),
                  color: AppTheme.primaryDark,
                ),
              ),
              SizedBox(width: AppLayout.scaledValue(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppLayout.scaledValue(15),
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    SizedBox(height: AppLayout.scaledValue(2)),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppLayout.scaledValue(12),
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: AppLayout.scaledValue(20),
                color: AppTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
