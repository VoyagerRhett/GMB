import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/subscribe/creator_subscribe_service.dart';
import 'package:citizenapp/my/creator/creator_api.dart';
import 'package:citizenapp/my/creator/creator_money.dart';
import 'package:citizenapp/my/creator/models/creator_plan.dart';
import 'package:citizenapp/my/myid/register_identity_flow.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 广场他人主页的创作者订阅入口（订阅者侧）。
///
/// 有档才显示；订阅、取消、更换分别只提交一笔账户签名交易。档位、价格和当前订阅展示
/// 统一采用 CitizenServe finalized 投影，手机页面不再直接读取链上会员状态。
class CreatorSubscribeButton extends StatefulWidget {
  const CreatorSubscribeButton({
    super.key,
    required this.creatorCidNumber,
    this.enabled = true,
    CreatorSubscribeService? service,
    SquareSessionProvider? sessionProvider,
  }) : _service = service,
       _sessionProvider = sessionProvider;

  final String creatorCidNumber;

  /// false=置灰不可点（以他人视角看自己时，订阅自己无意义）。
  final bool enabled;
  final CreatorSubscribeService? _service;
  final SquareSessionProvider? _sessionProvider;

  @override
  State<CreatorSubscribeButton> createState() => _CreatorSubscribeButtonState();
}

class _CreatorSubscribeButtonState extends State<CreatorSubscribeButton> {
  CreatorSubscribeService? _service;
  SquareSessionProvider? _session;
  bool _dependenciesReady = false;

  bool _loading = true;
  bool _busy = false;
  CreatorPlan? _plan;
  CreatorSubscriptionState? _subscription;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final injectedService = widget._service;
    final injectedSession = widget._sessionProvider;
    if (injectedService != null && injectedSession != null) {
      _service = injectedService;
      _session = injectedSession;
      _dependenciesReady = true;
      _load();
      return;
    }
    final session =
        widget._sessionProvider ?? context.read<SquareSessionProvider?>();
    final sdk = context.read<CitizenSdk?>();
    final identityResolver = context.read<FinalizedIdentityResolver?>();
    _session = session;
    if (session == null ||
        (injectedService == null &&
            (sdk == null || identityResolver == null))) {
      // 独立 Widget/预览没有完整产品依赖时只隐藏远端订阅入口；正式 App 根始终
      // 提供三项依赖，钱包、链和交易仍只来自同一个 CitizenSDK 实例。
      _loading = false;
      _dependenciesReady = true;
      return;
    }
    final resolvedSdk = sdk!;
    final resolvedIdentity = identityResolver!;
    _service =
        injectedService ??
        CreatorSubscribeService(
          wallet: resolvedSdk.wallet,
          chain: resolvedSdk.chain,
          transactions: resolvedSdk.transactions,
          identityResolver: resolvedIdentity,
          sessionProvider: session,
        );
    _dependenciesReady = true;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sessionProvider = _session;
    final service = _service;
    if (sessionProvider == null || service == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final session = await sessionProvider.ensureSession();
      if (session == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final view = await service.fetchView(session, widget.creatorCidNumber);
      if (!mounted) return;
      setState(() {
        _plan = view.plan;
        _subscription = view.subscription;
        _loading = false;
      });
    } on Exception {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 服务端只有在创作者平台会员有效时才返回档位；无档或读取失败一律隐藏。
    if (_loading || _plan == null || _plan!.tiers.isEmpty) {
      return const SizedBox.shrink();
    }
    final actionable = widget.enabled && !_busy;
    final subscribed = _subscription?.subscriptionStatus == 'active';
    // 顶部操作栏只保留一个紧凑入口，并固定在通知图标左侧。是否已订阅只决定
    // 点击后的操作面板，不能在主页头部展开成两个按钮或增加纵向高度。
    return SizedBox(
      height: AppLayout.scaled(context, 34),
      child: OutlinedButton(
        onPressed: actionable
            ? (subscribed ? _openSubscribedActions : _openPicker)
            : null,
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, AppLayout.scaled(context, 34)),
          padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaled(context, 12),
          ),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('订阅', maxLines: 1),
      ),
    );
  }

  /// 已订阅时把“更换会员档 / 取消订阅”收进二级操作面板，主页只显示单一订阅入口。
  Future<void> _openSubscribedActions() async {
    final action = await showModalBottomSheet<_SubscribedAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('更换会员档'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_SubscribedAction.changePlan),
            ),
            ListTile(
              leading: const Icon(
                Icons.cancel_outlined,
                color: AppTheme.danger,
              ),
              title: const Text(
                '取消订阅',
                style: TextStyle(color: AppTheme.danger),
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_SubscribedAction.cancel),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _SubscribedAction.changePlan:
        await _openPicker();
      case _SubscribedAction.cancel:
        await _cancel();
    }
  }

  Future<void> _openPicker() async {
    // 未注册 CID:先于选档就地弹全 App 统一注册面板,不让用户选完档才被拦;
    // 占号成功后订阅由用户重新发起。取消订阅无需此门(未注册者不可能有订阅)。
    if (!await ensureCidRegisteredOrPrompt(context)) return;
    if (!mounted) return;
    final selection = await showModalBottomSheet<_TierPeriodSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TierPeriodPicker(plan: _plan!),
    );
    if (selection == null || !mounted) return;
    final current = _subscription;
    final samePlan =
        current?.tierId == selection.tierId &&
        current?.billingPeriod == selection.period.key;
    final shouldChange =
        (current?.subscriptionStatus == 'active' ||
            current?.subscriptionStatus == 'cancelled') &&
        !samePlan;
    final service = _service;
    if (service == null) return;
    await _run(
      () => shouldChange
          ? service.changePlan(
              context: context,
              creatorCidNumber: widget.creatorCidNumber,
              tierId: selection.tierId,
              period: selection.period.key,
              priceFen: selection.priceFen,
            )
          : service.subscribe(
              context: context,
              creatorCidNumber: widget.creatorCidNumber,
              tierId: selection.tierId,
              period: selection.period.key,
              priceFen: selection.priceFen,
            ),
    );
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消订阅'),
        content: const Text('取消后区块链不再按月从你的钱包扣款，确定取消？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('取消订阅'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final service = _service;
    if (service == null) return;
    await _run(
      () => service.cancel(
        context: context,
        creatorCidNumber: widget.creatorCidNumber,
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      await _load();
    } on CreatorSubscribeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _TierPeriodSelection {
  const _TierPeriodSelection(this.tierId, this.period, this.priceFen);
  final String tierId;
  final BillingPeriod period;
  final int priceFen;
}

enum _SubscribedAction { changePlan, cancel }

/// 选档 + 周期底部弹窗：列出每档可用的月/季/年选项，点选即返回。
class _TierPeriodPicker extends StatelessWidget {
  const _TierPeriodPicker({required this.plan});

  final CreatorPlan plan;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: AppLayout.scaled(context, 38),
                height: AppLayout.scaled(context, 4),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(AppLayout.scaledValue(4)),
                ),
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 14)),
            Text(
              '选择会员档与周期',
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 16),
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 4)),
            Text(
              '订阅后区块链按所选周期自动扣公民币；款项全额进创作者钱包。',
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 12),
                color: AppTheme.textSecondary,
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 14)),
            for (final tier in plan.tiers) _tierBlock(context, tier),
          ],
        ),
      ),
    );
  }

  Widget _tierBlock(BuildContext context, CreatorTier tier) {
    final periods = BillingPeriod.values
        .where((period) => tier.hasPeriod(period))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: AppLayout.scaled(context, 14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tier.tierName.isEmpty ? '未命名档位' : tier.tierName,
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 15),
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 8)),
          Wrap(
            spacing: AppLayout.scaled(context, 8),
            runSpacing: AppLayout.scaled(context, 8),
            children: periods.map((period) {
              final fen = tier.priceFenOf(period)!;
              return OutlinedButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(_TierPeriodSelection(tier.tierId, period, fen)),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, AppLayout.scaled(context, 40)),
                  padding: EdgeInsets.symmetric(
                    horizontal: AppLayout.scaled(context, 14),
                  ),
                ),
                child: Text('${period.label} ${fenToYuanLabel(fen)} 元'),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
