import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';

import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/my/myid/myid_service.dart';
import 'package:citizenapp/my/myid/register_identity_flow.dart';
import 'package:citizenapp/my/myid/widgets/rebind_account_sheet.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/identity_badge.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 身份页(原电子护照)。
///
/// 页面始终展示访客、投票身份、竞选身份三张卡。只有当前身份对应的卡片排在
/// 首位、标记"当前身份"并展示真实链上值;非当前公民卡只展示该身份涉及的字段名称,
/// 不能重复泄露当前用户数据。链读取失败时不静默降级成访客。
///
/// 右上角按钮随状态切换:纯访客→「注册」(自助占一个匿名 CID);匿名已注册→「更换」
/// (把 CID 换绑到另一个本地账户);投票/竞选→「更换」但只提示须去注册局。访客卡在
/// 已占匿名 CID 时于卡内补显「公民号」,徽章色不变(仍访客,决策:不新增卡/色)。
/// 顶部支持下拉刷新。
class MyIdPage extends StatefulWidget {
  const MyIdPage({super.key, this.myIdService});

  final MyIdService? myIdService;

  @override
  State<MyIdPage> createState() => _MyIdPageState();
}

class _MyIdPageState extends State<MyIdPage> {
  static const List<MyIdTier> _baseTierOrder = <MyIdTier>[
    MyIdTier.visitor,
    MyIdTier.voting,
    MyIdTier.candidate,
  ];

  MyIdService? _myIdService;
  AccountSecurityService? _accountSecurity;
  MyIdState _state = const MyIdState(tier: MyIdTier.visitor);
  bool _loading = true;
  bool _submitting = false;

  bool get _isQueryFailed => _state.status == MyIdStatus.queryFailed;

  /// 右上主操作按钮文案:状态未知(链读失败)不给操作;纯访客「注册」;其余(匿名已
  /// 注册 / 投票 / 竞选)「更换」。civic 的「更换」点击后只提示走注册局。
  String? get _actionLabel {
    if (_isQueryFailed) return null;
    if (_state.tier == MyIdTier.visitor && !_state.isAnonymousRegistered) {
      return '注册';
    }
    return '更换';
  }

  @override
  void initState() {
    super.initState();
    if (widget.myIdService != null) {
      _myIdService = widget.myIdService;
      _loadState();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_myIdService != null) return;
    final sdk = context.read<CitizenSdk>();
    final accountSecurity = context.read<AccountSecurityService>();
    _accountSecurity = accountSecurity;
    _myIdService = MyIdService(
      wallet: sdk.wallet,
      signing: sdk.signing,
      chain: sdk.chain,
      transactions: sdk.transactions,
      accountSecurity: accountSecurity,
      currentUserContext: context.read<CurrentUserContext>(),
      identityResolver: context.read<FinalizedIdentityResolver>(),
      sessionProvider: context.read<SquareSessionProvider>(),
      chatRuntime: () => context.read<ChatSdk>(),
    );
    // 身份账户切换必须让身份页立即重排，和广场、聊天共用同一身份版本号。
    accountSecurity.revision.addListener(_loadState);
    _loadState();
  }

  @override
  void dispose() {
    _accountSecurity?.revision.removeListener(_loadState);
    super.dispose();
  }

  Future<void> _loadState() async {
    if (mounted) setState(() => _loading = true);
    MyIdState nextState;
    try {
      nextState = await _myIdService!.getState();
    } on Exception catch (error) {
      // Service 正常会把链错误收口为 queryFailed；这里兜住依赖异常，仍不能把
      // 未知错误误认成访客。
      nextState = MyIdState(
        tier: MyIdTier.visitor,
        status: MyIdStatus.queryFailed,
        errorMessage: '身份读取失败:$error',
      );
    }
    if (!mounted) return;
    setState(() {
      _state = nextState;
      _loading = false;
    });
  }

  /// 右上按钮总入口:civic 提示走注册局;匿名已注册→换绑;纯访客→注册。
  Future<void> _onPrimaryAction() async {
    if (_submitting || _loading) return;
    if (_state.isCitizen) {
      _showSnack('投票 / 竞选身份只能在对应注册局线下更换。');
      return;
    }
    if (_state.isAnonymousRegistered) {
      await _onRebind();
    } else {
      await _onRegister();
    }
  }

  /// 注册走全 App 唯一共享流程(弹窗、余额闸、占号提交、缓存失效、成败提示全在
  /// [startCidRegistrationFlow] 单源);本页只驱动提交阶段转圈与成功后回刷。
  ///
  /// [_submitting] 只跟随提交阶段(onSubmitting 回调),与旧实现一致:面板打开
  /// 期间不转圈;选择阶段的重入由模态面板天然阻挡。
  Future<void> _onRegister() async {
    final registered = await startCidRegistrationFlow(
      context,
      myIdService: _myIdService,
      onSubmitting: (submitting) {
        if (mounted) setState(() => _submitting = submitting);
      },
    );
    if (registered && mounted) await _loadState();
  }

  Future<void> _onRebind() async {
    final cid = _state.cidNumber;
    if (cid == null || cid.trim().isEmpty) return;
    final targets = await _myIdService!.listRebindTargets();
    if (!mounted) return;
    final newAccountId =
        await showRebindAccountSheet(context, targets: targets);
    if (newAccountId == null || !mounted) return;
    await _runSubmit(() async {
      await _myIdService!.rebindCidTo(
        buildContext: context,
        cidNumber: cid,
        newAccountId: newAccountId,
      );
      return '身份 CID 已换绑到所选账户';
    });
  }

  /// 统一提交外壳:置 loading → 跑动作 → 成功提示并回刷身份 → 失败提示;不吞异常。
  Future<void> _runSubmit(Future<String> Function() action) async {
    setState(() => _submitting = true);
    try {
      final message = await action();
      if (!mounted) return;
      _showSnack(message);
      await _loadState();
    } on Object catch (error) {
      if (!mounted) return;
      _showSnack(_describeError(error), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : null,
      ),
    );
  }

  String _describeError(Object error) {
    if (error is AccountSecurityException) return error.message;
    final text = error.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }

  List<MyIdTier> _orderedTiers() {
    if (_isQueryFailed) return _baseTierOrder;
    return <MyIdTier>[
      _state.tier,
      ..._baseTierOrder.where((tier) => tier != _state.tier),
    ];
  }

  bool _isCurrent(MyIdTier tier) => !_isQueryFailed && tier == _state.tier;

  bool _showActualValues(MyIdTier tier) =>
      _isCurrent(tier) && tier != MyIdTier.visitor;

  @override
  Widget build(BuildContext context) {
    final tiers = _orderedTiers();
    return Scaffold(
      appBar: AppBar(
        title: const Text('身份'),
        centerTitle: true,
        actions: [
          if (_actionLabel != null)
            _submitting
                ? Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppLayout.scaled(context, 18)),
                    child: Center(
                      child: SizedBox(
                        width: AppLayout.scaled(context, 18),
                        height: AppLayout.scaled(context, 18),
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : Padding(
                    padding:
                        EdgeInsets.only(right: AppLayout.scaled(context, 4)),
                    child: TextButton(
                      onPressed: _loading ? null : _onPrimaryAction,
                      child: Text(_actionLabel!),
                    ),
                  ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadState,
        child: ListView(
          padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaled(context, 12),
              vertical: AppLayout.scaled(context, 14)),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_loading)
              LinearProgressIndicator(minHeight: AppLayout.scaled(context, 2))
            else
              SizedBox(height: AppLayout.scaled(context, 2)),
            if (_isQueryFailed) ...[
              SizedBox(height: AppLayout.scaled(context, 12)),
              _PassportMessageBanner(
                message: _state.errorMessage ?? '链上身份读取失败',
                isError: true,
                onRetry: _loading ? null : _loadState,
              ),
            ] else if ((_state.errorMessage ?? '').trim().isNotEmpty) ...[
              SizedBox(height: AppLayout.scaled(context, 12)),
              _PassportMessageBanner(message: _state.errorMessage!),
            ],
            SizedBox(height: AppLayout.scaled(context, 14)),
            Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: AppLayout.scaled(context, 560)),
                child: Column(
                  children: [
                    for (var index = 0; index < tiers.length; index++) ...[
                      _PassportIdentityCard(
                        key: ValueKey<String>(
                            'passport-card-${tiers[index].name}'),
                        tier: tiers[index],
                        current: _isCurrent(tiers[index]),
                        showActualValues: _showActualValues(tiers[index]),
                        fields: _fieldsFor(tiers[index]),
                        registeredCid: tiers[index] == MyIdTier.visitor &&
                                _state.isAnonymousRegistered
                            ? _state.cidNumber
                            : null,
                      ),
                      if (index != tiers.length - 1)
                        SizedBox(height: AppLayout.scaled(context, 14)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_PassportField> _fieldsFor(MyIdTier tier) {
    if (tier == MyIdTier.visitor) return const <_PassportField>[];
    final showValues = _showActualValues(tier);
    final fields = <_PassportField>[
      _PassportField(
        label: '投票账户',
        value: showValues ? _shortAddress(_state.votingAccountId) : null,
        mono: true,
      ),
      _PassportField(
        label: '公民号',
        value: showValues ? _displayValue(_state.cidNumber) : null,
        mono: true,
        singleLine: true,
      ),
      _PassportField(
        label: '居住选区',
        value: showValues ? _displayValue(_state.residenceDistrict) : null,
      ),
      _PassportField(
        label: '身份状态',
        value: showValues ? _statusText(_state.status) : null,
      ),
      _PassportField(
        label: '身份有效期',
        value: showValues ? _validityText() : null,
      ),
    ];
    if (tier == MyIdTier.candidate) {
      fields.addAll(<_PassportField>[
        _PassportField(
          label: '公民姓名',
          value: showValues
              ? _displayValue(
                  '${_state.familyName ?? ''}${_state.givenName ?? ''}')
              : null,
        ),
        _PassportField(
          label: '性别',
          value: showValues ? _displayValue(_state.citizenSexLabel) : null,
        ),
        _PassportField(
          label: '出生日期',
          value:
              showValues ? (_formatDate(_state.citizenBirthDate) ?? '—') : null,
        ),
        _PassportField(
          label: '出生地',
          value: showValues ? _displayValue(_state.birthDistrict) : null,
        ),
      ]);
    }
    return fields;
  }

  String _validityText() {
    final from = _formatDate(_state.passportValidFrom);
    final until = _formatDate(_state.passportValidUntil);
    if (from == null || until == null) return '—';
    return '$from 至 $until';
  }

  static String _displayValue(String? input) {
    final value = input?.trim() ?? '';
    return value.isEmpty ? '—' : value;
  }

  static String _shortAddress(String? input) {
    final value = input?.trim() ?? '';
    if (value.isEmpty) return '—';
    if (value.length <= 18) return value;
    return '${value.substring(0, 8)}…${value.substring(value.length - 8)}';
  }

  static String _statusText(MyIdStatus? status) => switch (status) {
        MyIdStatus.normal => '正常',
        MyIdStatus.notYetValid => '未生效',
        MyIdStatus.expired => '已过期',
        MyIdStatus.revoked => '已吊销',
        _ => '—',
      };

  static String? _formatDate(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return '${year.toString().padLeft(4, '0')}年'
        '${month.toString().padLeft(2, '0')}月'
        '${day.toString().padLeft(2, '0')}日';
  }
}

class _PassportIdentityCard extends StatelessWidget {
  const _PassportIdentityCard({
    super.key,
    required this.tier,
    required this.current,
    required this.showActualValues,
    required this.fields,
    this.registeredCid,
  });

  final MyIdTier tier;
  final bool current;
  final bool showActualValues;
  final List<_PassportField> fields;

  /// 访客卡专用:已占匿名 CID 时的 CID 号(非空则在卡内补显「公民号」)。
  final String? registeredCid;

  String get _title => switch (tier) {
        MyIdTier.visitor => '身份·访客',
        MyIdTier.voting => '公民身份 · 投票',
        MyIdTier.candidate => '公民身份 · 竞选',
      };

  Color get _color => switch (tier) {
        MyIdTier.visitor => AppTheme.identityVisitor,
        MyIdTier.voting => AppTheme.identityVoting,
        MyIdTier.candidate => AppTheme.identityCandidate,
      };

  String get _identityLevel => switch (tier) {
        MyIdTier.visitor => 'visitor',
        MyIdTier.voting => 'voting',
        MyIdTier.candidate => 'candidate',
      };

  /// 是否在右上角挂「当前身份」徽章。
  ///
  /// 当前卡才挂，且**纯访客（无 CID）不挂**：投票/竞选必有 CID，匿名已注册有 CID
  /// （`registeredCid` 非空），只有从未占号的纯访客不挂。链读失败时 `current` 恒 false，
  /// 天然不挂——「不挂徽章」绝不能把「没读到链」冒充成「没注册」。
  bool get _showsCurrentBadge {
    if (!current) return false;
    if (tier != MyIdTier.visitor) return true;
    return registeredCid != null && registeredCid!.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final badgeStyle = identityBadgeStyle(
      identityLevel: _identityLevel,
      membershipLevel: null,
      membershipActive: false,
    )!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
      decoration: BoxDecoration(
        color: Color.alphaBlend(_color.withAlpha(8), AppTheme.surfaceCard),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: _color, width: current ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: _color.withAlpha(current ? 38 : 13),
            blurRadius: AppLayout.scaledValue(current ? 18 : 8),
            offset: Offset(
              0,
              AppLayout.scaledValue(current ? 8 : 3),
            ),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                // 徽章不挂时不预留其 88px 位置，避免纯访客卡标题行右侧留空。
                padding: EdgeInsets.only(
                  right: AppLayout.scaledValue(_showsCurrentBadge ? 88 : 0),
                ),
                child: Row(
                  children: [
                    IdentityBadge(
                      style: badgeStyle,
                      size: AppLayout.scaled(context, 44),
                      tooltip: _title,
                    ),
                    SizedBox(width: AppLayout.scaled(context, 12)),
                    // Flexible（非 Expanded）让标题只占内容宽度，匿名标签紧贴访客卡标题右侧，
                    // 而不是被撑到卡片最右端；标题过长时仍走省略号避免溢出。
                    Flexible(
                      child: Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 18),
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          color: _color,
                        ),
                      ),
                    ),
                    // 访客卡默认匿名，用一枚小标签直接点明，替代原“没有公民身份信息”整段空态。
                    if (tier == MyIdTier.visitor) ...[
                      SizedBox(width: AppLayout.scaled(context, 8)),
                      _AnonymousTag(color: _color),
                    ],
                  ],
                ),
              ),
              // 访客卡:已占匿名 CID 时补一行「公民号」;纯访客只留标题行,高度自然收缩。
              if (tier == MyIdTier.visitor) ...[
                if (registeredCid != null &&
                    registeredCid!.trim().isNotEmpty) ...[
                  SizedBox(height: AppLayout.scaled(context, 14)),
                  _PassportFieldRow(
                    field: _PassportField(
                      label: '公民号',
                      value: registeredCid,
                      mono: true,
                      singleLine: true,
                    ),
                    color: _color,
                    showValue: true,
                  ),
                ],
              ] else ...[
                SizedBox(height: AppLayout.scaled(context, 14)),
                for (var index = 0; index < fields.length; index++) ...[
                  _PassportFieldRow(
                    field: fields[index],
                    color: _color,
                    showValue: showActualValues,
                  ),
                  if (index != fields.length - 1)
                    SizedBox(height: AppLayout.scaled(context, 6)),
                ],
              ],
            ],
          ),
          if (_showsCurrentBadge)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                key: ValueKey<String>('current-identity-${tier.name}'),
                padding: EdgeInsets.symmetric(
                    horizontal: AppLayout.scaled(context, 9),
                    vertical: AppLayout.scaled(context, 5)),
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(AppLayout.scaledValue(7)),
                ),
                child: Text(
                  '当前身份',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppLayout.scaled(context, 11),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 访客卡的“匿名”提示标签：小圆角药丸 + 隐私图标，沿用所在卡片的身份色。
class _AnonymousTag extends StatelessWidget {
  const _AnonymousTag({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('passport-anonymous-tag'),
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 8),
          vertical: AppLayout.scaled(context, 3)),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(999)),
        border: Border.all(color: color.withAlpha(64)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_outlined,
              size: AppLayout.scaled(context, 12), color: color),
          SizedBox(width: AppLayout.scaled(context, 3)),
          Text(
            '匿名',
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 11),
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PassportField {
  const _PassportField({
    required this.label,
    this.value,
    this.mono = false,
    this.singleLine = false,
  });

  final String label;
  final String? value;
  final bool mono;
  final bool singleLine;
}

class _PassportFieldRow extends StatelessWidget {
  const _PassportFieldRow({
    required this.field,
    required this.color,
    required this.showValue,
  });

  final _PassportField field;
  final Color color;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 10),
          vertical: AppLayout.scaled(context, 7)),
      decoration: BoxDecoration(
        color: color.withAlpha(showValue ? 10 : 7),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
        border: Border.all(color: color.withAlpha(24)),
      ),
      child: showValue
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 名称按自身宽度占位，值紧随其后；不再为短名称保留固定列空白。
                Text(
                  field.label,
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    height: 1.4,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: AppLayout.scaled(context, 6)),
                Expanded(
                  child: _PassportFieldValue(field: field),
                ),
              ],
            )
          : Text(
              field.label,
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 12),
                height: 1.35,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

class _PassportFieldValue extends StatelessWidget {
  const _PassportFieldValue({required this.field});

  final _PassportField field;

  @override
  Widget build(BuildContext context) {
    final value = Text(
      field.value ?? '—',
      maxLines: field.singleLine ? 1 : null,
      softWrap: !field.singleLine,
      textAlign: TextAlign.left,
      style: TextStyle(
        fontSize: AppLayout.scaledValue(field.mono ? 12 : 13),
        height: 1.4,
        fontFamily: field.mono ? 'monospace' : null,
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    if (!field.singleLine) return value;
    // 公民号必须完整保持一行；窄屏只在必要时等比缩小，不用换行或省略破坏号码。
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: value,
    );
  }
}

class _PassportMessageBanner extends StatelessWidget {
  const _PassportMessageBanner({
    required this.message,
    this.isError = false,
    this.onRetry,
  });

  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTheme.danger : AppTheme.warning;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppLayout.scaled(context, 560)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: AppTheme.bannerDecoration(color),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.info_outline,
                size: AppLayout.scaled(context, 18),
                color: color,
              ),
              SizedBox(width: AppLayout.scaled(context, 8)),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    height: 1.4,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}
