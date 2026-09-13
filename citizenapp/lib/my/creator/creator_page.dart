import 'package:provider/provider.dart';
import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:citizenapp/my/creator/creator_plan_edit_sheet.dart';
import 'package:citizenapp/my/creator/creator_service.dart';
import 'package:citizenapp/my/creator/models/creator_overview.dart';
import 'package:citizenapp/my/creator/models/creator_plan.dart';
import 'package:citizenapp/my/creator/widgets/creator_gate_view.dart';
import 'package:citizenapp/my/creator/widgets/creator_overview_card.dart';
import 'package:citizenapp/my/creator/widgets/creator_tier_card.dart';
import 'package:citizenapp/my/membership/membership_page.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/identity_register_guide.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 「我的 → 创作者」：管理自己的创作者会员（档位 / 收入概览）。
///
/// 首帧直接使用「我的」页传入的 CitizenServe 会员缓存；创作者档位只在后台
/// 刷新读模型。档位名称和价格都由链上保存；整次保存只产生一次
/// `set_creator_plans` 账户签名，展示快照不参与授权。
class CreatorPage extends StatefulWidget {
  const CreatorPage({
    super.key,
    CreatorService? service,
    this.initialCidNumber = '',
    this.initialMembershipDecision =
        MembershipDisplayDecision.inactiveConfirmed,
  }) : _service = service;

  final CreatorService? _service;

  /// 「我的」页已经持有的永久 CID，用于跳过页面入口的重复身份读取。
  final String initialCidNumber;

  /// 仅作为首帧展示提示；只允许有效或无效二元态。
  /// 创建、编辑等动作仍由 CitizenServe D1 重新鉴权。
  final MembershipDisplayDecision initialMembershipDecision;

  @override
  State<CreatorPage> createState() => _CreatorPageState();
}

class _CreatorPageState extends State<CreatorPage> {
  late final CreatorService _service;
  AccountSecurityService? _accountSecurity;
  bool _dependenciesReady = false;
  CreatorPageData? _data;
  bool _unregistered = false;
  String? _error;
  String _cidNumber = '';
  int _membershipFetchedAtMs = 0;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initialCidNumber = widget.initialCidNumber.trim();
    _cidNumber = initialCidNumber;
    _data = switch (widget.initialMembershipDecision) {
      MembershipDisplayDecision.inactiveConfirmed => CreatorPageData.gated(),
      MembershipDisplayDecision.activeConfirmed => CreatorPageData.active(
        plan: CreatorPlan.empty(initialCidNumber),
        overview: CreatorOverview.zero,
      ),
    };
    MembershipRevision.instance.listenable.addListener(_onMembershipChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final injected = widget._service;
    if (injected != null) {
      _service = injected;
      _dependenciesReady = true;
      unawaited(_bootstrap(useInitialCid: true));
      return;
    }
    final sdk = context.read<CitizenSdk>();
    final accountSecurity = context.read<AccountSecurityService>();
    _service = CreatorService(
      wallet: sdk.wallet,
      chain: sdk.chain,
      transactions: sdk.transactions,
      identityResolver: context.read<FinalizedIdentityResolver>(),
      sessionProvider: context.read<SquareSessionProvider>(),
    );
    _accountSecurity = accountSecurity;
    accountSecurity.revision.addListener(_onIdentityChanged);
    _dependenciesReady = true;
    unawaited(_bootstrap(useInitialCid: true));
  }

  @override
  void dispose() {
    _accountSecurity?.revision.removeListener(_onIdentityChanged);
    MembershipRevision.instance.listenable.removeListener(_onMembershipChanged);
    super.dispose();
  }

  /// 注册可能发生在任意常驻页；finalized 身份广播后，本页必须原地退出注册引导。
  void _onIdentityChanged() {
    if (mounted) unawaited(_bootstrap(useInitialCid: false, force: true));
  }

  /// 会员动作确认后只刷新同一永久 CID；广播本身不直接授予页面能力。
  void _onMembershipChanged() {
    final event = MembershipRevision.instance.listenable.value;
    if (!mounted || event == null || event.cidNumber != _cidNumber) return;
    unawaited(_refresh(forceVisibleError: false));
  }

  /// 先提交本地展示态，再决定是否后台刷新；任何远端 Future 都不在首帧关键路径。
  Future<void> _bootstrap({
    required bool useInitialCid,
    bool force = false,
  }) async {
    final generation = ++_loadGeneration;
    try {
      var cidNumber = useInitialCid ? widget.initialCidNumber.trim() : '';
      if (cidNumber.isEmpty) {
        final currentUser = await context.read<CurrentUserContext>().resolve();
        cidNumber = currentUser?.cidNumber.trim() ?? '';
      }
      if (!mounted || generation != _loadGeneration) return;
      if (cidNumber.isEmpty) {
        setState(() {
          _unregistered = true;
          _data = null;
          _cidNumber = '';
          _error = null;
        });
        return;
      }

      final cidChanged = cidNumber != _cidNumber;
      if (cidChanged || _unregistered) {
        setState(() {
          _cidNumber = cidNumber;
          _unregistered = false;
          _error = null;
          if (cidChanged) _data = null;
        });
      }

      final snapshot = await _service.readDisplaySnapshot(cidNumber);
      if (!mounted || generation != _loadGeneration) return;
      // Creator 展示快照只由 CitizenServe 会员缓存与创作者读取写入，可信度高于入口提示；
      // 已确认有效的本地快照可以覆盖旧的无会员入口状态。
      if (snapshot != null) {
        setState(() {
          _data = snapshot.data;
          _membershipFetchedAtMs = snapshot.membershipFetchedAtMs;
          _error = null;
        });
      }

      final fresh =
          snapshot?.isFresh(DateTime.now().millisecondsSinceEpoch) == true;
      if (force || !fresh) {
        unawaited(_refresh(generation: generation, forceVisibleError: false));
      }
    } on Exception catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = _data == null ? '读取本地创作者状态失败：$e' : null;
      });
    }
  }

  Future<void> _refresh({
    int? generation,
    required bool forceVisibleError,
  }) async {
    final owner = generation ?? ++_loadGeneration;
    final cidNumber = _cidNumber;
    if (cidNumber.isEmpty) return;
    try {
      final data = await _service.load(expectedCidNumber: cidNumber);
      if (!mounted || owner != _loadGeneration || cidNumber != _cidNumber) {
        return;
      }
      setState(() {
        _data = data;
        _membershipFetchedAtMs = DateTime.now().millisecondsSinceEpoch;
        _error = null;
      });
    } on CreatorException catch (e) {
      if (!mounted || owner != _loadGeneration || cidNumber != _cidNumber) {
        return;
      }
      if (forceVisibleError || _data == null) {
        setState(() => _error = e.message);
      }
    } on Exception catch (e) {
      if (!mounted || owner != _loadGeneration || cidNumber != _cidNumber) {
        return;
      }
      if (forceVisibleError || _data == null) {
        setState(() => _error = '刷新失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('创作者')),
      body: _body(),
    );
  }

  Widget _body() {
    final data = _data;
    final Widget content;
    if (_unregistered) {
      content = IdentityRegisterGuide(
        description: '注册后即可开通创作者会员。',
        onRegistered: () => _bootstrap(useInitialCid: false, force: true),
      );
    } else if (data == null && _error != null) {
      content = _loadFailed(_error!);
    } else if (data == null) {
      // 极短的本地快照读取窗口只显示稳定结构，不出现等待文案或进度条。
      content = _activeView(
        CreatorPlan.empty(_cidNumber),
        CreatorOverview.zero,
        resolved: false,
      );
    } else if (data.gated) {
      content = CreatorGateView(onOpenMembership: _openMembership);
    } else {
      content = _activeView(data.plan!, data.overview!);
    }
    return content;
  }

  Widget _activeView(
    CreatorPlan plan,
    CreatorOverview overview, {
    bool resolved = true,
  }) {
    final atMax = plan.tiers.length >= CreatorPlan.maxTiers;
    return RefreshIndicator(
      onRefresh: () => _refresh(forceVisibleError: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          CreatorOverviewCard(overview: overview, resolved: resolved),
          if (_error != null) ...[
            SizedBox(height: AppLayout.scaledValue(12)),
            _inlineError(_error!),
          ],
          SizedBox(height: AppLayout.scaledValue(16)),
          if (plan.tiers.isEmpty)
            _emptyTiers(resolved: resolved)
          else ...[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaledValue(2),
              ),
              child: Row(
                children: [
                  Text(
                    '我的会员档',
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(14),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${plan.tiers.length} / ${CreatorPlan.maxTiers}',
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(12),
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(12)),
            for (final tier in plan.tiers) ...[
              CreatorTierCard(
                tier: tier,
                onEdit: () {
                  if (resolved) _openEdit(tier);
                },
              ),
              SizedBox(height: AppLayout.scaledValue(12)),
            ],
            _addTierButton(atMax, resolved: resolved),
          ],
          SizedBox(height: AppLayout.scaledValue(16)),
          _subscribersEntry(overview.subscriberCount, resolved: resolved),
          SizedBox(height: AppLayout.scaledValue(14)),
          Center(
            child: Text(
              '价格以公民币结算 · 订阅款全额进你的钱包 · 保存只签名一次',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(11),
                color: AppTheme.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyTiers({required bool resolved}) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: EdgeInsets.symmetric(
        horizontal: AppLayout.scaledValue(16),
        vertical: AppLayout.scaledValue(24),
      ),
      child: Column(
        children: [
          Container(
            width: AppLayout.scaledValue(52),
            height: AppLayout.scaledValue(52),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(24),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(
              Icons.storefront_outlined,
              size: AppLayout.scaledValue(26),
              color: AppTheme.primary,
            ),
          ),
          SizedBox(height: AppLayout.scaledValue(12)),
          Text(
            resolved ? '还没有会员档' : '会员档',
            style: TextStyle(
              fontSize: AppLayout.scaledValue(15),
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: AppLayout.scaledValue(6)),
          Text(
            resolved ? '创建第一个会员档，粉丝就能用公民币订阅你。' : '创建和管理你的会员档。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(13),
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: AppLayout.scaledValue(16)),
          FilledButton.icon(
            onPressed: resolved ? () => _openEdit(null) : null,
            icon: Icon(Icons.add, size: AppLayout.scaledValue(19)),
            label: const Text('创建会员档'),
          ),
        ],
      ),
    );
  }

  Widget _addTierButton(bool atMax, {required bool resolved}) {
    return InkWell(
      onTap: !resolved || atMax ? null : () => _openEdit(null),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(12)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: atMax ? AppTheme.border : AppTheme.primaryLight,
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add,
              size: AppLayout.scaledValue(18),
              color: atMax ? AppTheme.textTertiary : AppTheme.primary,
            ),
            SizedBox(width: AppLayout.scaledValue(6)),
            Text(
              atMax ? '已达 ${CreatorPlan.maxTiers} 档上限' : '新增会员档',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(14),
                fontWeight: FontWeight.w600,
                color: atMax ? AppTheme.textTertiary : AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subscribersEntry(int count, {required bool resolved}) {
    return InkWell(
      onTap: resolved
          ? () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('订阅者明细即将上线')))
          : null,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaledValue(14),
          vertical: AppLayout.scaledValue(13),
        ),
        child: Row(
          children: [
            Container(
              width: AppLayout.scaledValue(30),
              height: AppLayout.scaledValue(30),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.info.withAlpha(24),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(
                Icons.group_outlined,
                size: AppLayout.scaledValue(17),
                color: AppTheme.info,
              ),
            ),
            SizedBox(width: AppLayout.scaledValue(10)),
            Expanded(
              child: Text(
                '谁订阅了我',
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              resolved ? '$count 位' : '--',
              style: TextStyle(
                fontSize: AppLayout.scaledValue(13),
                color: AppTheme.textSecondary,
              ),
            ),
            SizedBox(width: AppLayout.scaledValue(4)),
            Icon(
              Icons.chevron_right,
              size: AppLayout.scaledValue(20),
              color: AppTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  /// 本地展示态读取失败时复用 [_inlineError] 居中呈现，不另造页面结构。
  Widget _loadFailed(String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppLayout.scaledValue(16)),
        child: _inlineError(message),
      ),
    );
  }

  Widget _inlineError(String message) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: EdgeInsets.all(AppLayout.scaledValue(14)),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.textTertiary),
          SizedBox(width: AppLayout.scaledValue(10)),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(13),
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: () => _refresh(forceVisibleError: true),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEdit(CreatorTier? tier) async {
    final plan = await showModalBottomSheet<CreatorPlan>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CreatorPlanEditSheet(
        service: _service,
        currentTiers: _data?.plan?.tiers ?? const [],
        editing: tier,
      ),
    );
    if (plan != null && mounted) {
      final current = _data;
      final overview = current?.overview ?? CreatorOverview.zero;
      final data = CreatorPageData.active(plan: plan, overview: overview);
      setState(() {
        _data = data;
        _error = null;
      });
      unawaited(
        _service.rememberDisplayData(
          cidNumber: _cidNumber,
          data: data,
          membershipFetchedAtMs: _membershipFetchedAtMs,
          creatorFetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  }

  Future<void> _openMembership() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MembershipPage()));
    if (mounted) await _refresh(forceVisibleError: false);
  }
}
