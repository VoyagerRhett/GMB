import 'package:provider/provider.dart';

import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/user_qr_page.dart';
import 'package:citizenapp/8964/profile/user_profile_page.dart';
import 'package:citizenapp/8964/profile/widgets/profile_avatar.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/my/myid/identity_badge_snapshot_store.dart';
import 'package:citizenapp/my/creator/creator_page.dart';
import 'package:citizenapp/my/creator/creator_service.dart';
import 'package:citizenapp/my/membership/membership_page.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/my/myid/myid_page.dart';
import 'package:citizenapp/my/myid/register_identity_flow.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/security/app_lock_service.dart';
import 'package:citizenapp/security/pin_input_page.dart';
import 'package:citizenapp/security/secure_storage.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/my/user/contact_book_page.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/biometric_auth_text.dart';
import 'package:citizenapp/update/app_update.dart';
import 'package:citizenapp/update/update_badge.dart';
import 'package:citizenapp/wallet/pages/wallet_page.dart';

class MyTab extends StatefulWidget {
  const MyTab({
    super.key,
    this.showSettingsUpdateDot = false,
    this.wallet,
    this.badgeSnapshotStore,
    this.profileApi,
    this.profileCache,
    this.profileMediaCache,
    this.sessionProvider,
    this.squareApi,
    this.subscriptionService,
    this.creatorService,
    this.currentUserContext,
  });

  final bool showSettingsUpdateDot;
  final CitizenSdkWallet? wallet;
  final IdentityBadgeSnapshotStore? badgeSnapshotStore;
  final CitizenProfileApi? profileApi;
  final CitizenProfileCache? profileCache;
  final CitizenProfileMediaCache? profileMediaCache;
  final SquareSessionProvider? sessionProvider;
  final SquareApiClient? squareApi;
  final SubscriptionService? subscriptionService;
  final CreatorService? creatorService;
  final CurrentUserContext? currentUserContext;

  @override
  State<MyTab> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<MyTab> {
  late final CitizenSdkWallet _wallet;
  late final IdentityBadgeSnapshotStore _badgeSnapshotStore;
  late final CitizenProfileApi _profileApi;
  late final CitizenProfileCache _profileCache;
  late final CitizenProfileMediaCache _profileMediaCache;
  late final SquareSessionProvider _sessionProvider;

  CitizenWalletStateAccount? _defaultWallet;
  String? _defaultWalletIdentityLevel;
  CitizenProfile? _publicProfile;
  CitizenProfileMediaSnapshot _publicProfileMedia =
      const CitizenProfileMediaSnapshot();
  SquareSession? _profileSession;

  /// 每个 MyTab 生命周期同一 CID 最多后台刷新一次；反复进入页面只读缓存。
  String? _profileRefreshCid;

  /// 默认钱包的会员购买态（档位色 + 对勾）；best-effort，读失败为 null。
  late final SubscriptionService _subscriptionService;
  late final CurrentUserContext _currentUserContext;
  AccountSecurityService? _accountSecurity;
  bool _dependenciesReady = false;
  SquareMembershipState? _membership;
  MembershipDisplayDecision _membershipDecision =
      MembershipDisplayDecision.inactiveConfirmed;

  /// _loadState 世代号：本地钱包、资料和徽章快照并发重载时，旧结果
  /// 不得覆盖新默认钱包。
  int _loadGeneration = 0;

  /// 身份账户 ID 来自当前默认账户的本机绑定；普通“我的”页面不读取链。
  String _identityAccountId = '';

  /// 当前身份永久 CID；徽章、公开资料和业务数据都以它作为归属主键。
  String _identityCidNumber = '';

  /// 用户身份账户 ID（展示口径）= 当前身份账户（CID 绑定账户，非恒账户0）。
  String get _communicationAccountId => _identityAccountId;

  /// 公开昵称唯一真源是 CID 资料的 display_name；资料尚未缓存时稳定兜底。
  /// 本机 walletName 只用于钱包列表，绝不进入此展示链路。
  String get _nickname => ProfilePresentation.forIdentityKey(
    _publicProfile?.cidNumber ?? _communicationAccountId,
  ).resolveDisplayName(publicName: _publicProfile?.displayName);

  /// 默认钱包徽章信号：颜色只来自 CID 级链上身份快照，勾来自会员匹配。
  String? get _defaultWalletMembershipLevel => _membership?.membershipLevel;
  bool get _defaultWalletMembershipActive =>
      _membershipDecision == MembershipDisplayDecision.activeConfirmed &&
      (_membership?.active ?? false);

  // 个人页副标题只组合既有身份与会员快照，不新增第二套身份或订阅真源。
  String get _identityLabel => switch (_defaultWalletIdentityLevel) {
    'candidate' => '竞选身份',
    'voting' => '投票身份',
    _ => '匿名访客',
  };

  String? get _membershipLabel {
    if (!_defaultWalletMembershipActive) return null;
    return switch (_defaultWalletMembershipLevel) {
      'freedom' => '自由会员',
      'democracy' => '民主会员',
      'spark' => '薪火会员',
      _ => null,
    };
  }

  String get _profileSubtitle {
    final membership = _membershipLabel;
    return membership == null
        ? _identityLabel
        : '$_identityLabel · $membership';
  }

  @override
  void initState() {
    super.initState();
    _badgeSnapshotStore =
        widget.badgeSnapshotStore ?? IdentityBadgeSnapshotStore();
    _profileApi = widget.profileApi ?? CitizenProfileApi();
    _profileCache = widget.profileCache ?? const CitizenProfileCache();
    _profileMediaCache = widget.profileMediaCache ?? CitizenProfileMediaCache();
    MembershipRevision.instance.listenable.addListener(_onMembershipChanged);
    CitizenProfileCache.revision.addListener(_onPublicProfileChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final injectedWallet = widget.wallet;
    final injectedSession = widget.sessionProvider;
    final injectedSubscription = widget.subscriptionService;
    final injectedCurrentUser = widget.currentUserContext;
    if (injectedWallet != null &&
        injectedSession != null &&
        injectedSubscription != null &&
        injectedCurrentUser != null) {
      _wallet = injectedWallet;
      _sessionProvider = injectedSession;
      _subscriptionService = injectedSubscription;
      _currentUserContext = injectedCurrentUser;
      _dependenciesReady = true;
      _loadState();
      return;
    }
    final sdk = context.read<CitizenSdk>();
    final accountSecurity = context.read<AccountSecurityService>();
    _wallet = widget.wallet ?? sdk.wallet;
    _currentUserContext =
        widget.currentUserContext ?? context.read<CurrentUserContext>();
    _sessionProvider =
        widget.sessionProvider ?? context.read<SquareSessionProvider>();
    _subscriptionService = widget.subscriptionService ??
        SubscriptionService(
          wallet: _wallet,
          chain: sdk.chain,
          transactions: sdk.transactions,
          identityResolver: context.read<FinalizedIdentityResolver>(),
          sessionProvider: _sessionProvider,
          api: widget.squareApi ?? SquareApiClient(),
        );
    // 本页常驻 IndexedStack；SDK 账户目录或 finalized CID 绑定变化后重读身份。
    _accountSecurity = accountSecurity;
    accountSecurity.revision.addListener(_onWalletsChanged);
    _dependenciesReady = true;
    _loadState();
  }

  @override
  void dispose() {
    _accountSecurity?.revision.removeListener(_onWalletsChanged);
    MembershipRevision.instance.listenable.removeListener(_onMembershipChanged);
    CitizenProfileCache.revision.removeListener(_onPublicProfileChanged);
    super.dispose();
  }

  /// 编辑资料成功后缓存会先于路由返回提交。MyTab 常驻 IndexedStack，按 CID 定向
  /// 重读即可原地更新头像、背景和昵称，不等待页面重建或再次请求 Worker。
  void _onPublicProfileChanged() {
    final event = CitizenProfileCache.revision.value;
    if (!mounted || event == null || event.cidNumber != _identityCidNumber) {
      return;
    }
    unawaited(_reloadCachedPublicProfile(event.cidNumber, _loadGeneration));
  }

  /// 统一会员缓存推进后，只重读当前永久 CID 的本机快照；不重复访问 CitizenServe，
  /// 也不从广播事件本身推导或授予徽章。
  void _onMembershipChanged() {
    final event = MembershipRevision.instance.listenable.value;
    if (!mounted || event == null || event.cidNumber != _identityCidNumber) {
      return;
    }
    unawaited(_loadMembershipSnapshot(event.cidNumber, _loadGeneration));
  }

  Future<void> _onWalletsChanged() async {
    // revision 同时覆盖钱包列表与 finalized CID 绑定。注册前后默认账户可能完全相同，
    // 不能只比钱包 account_id；必须重读并比较 cid_number + 身份账户。
    final wallet = (await _wallet.getState()).defaultAccount;
    final identity = await _currentUserContext.resolve();
    if (!mounted) return;
    final identityAccountId = identity?.accountId ?? wallet?.accountId ?? '';
    final identityCidNumber = identity?.cidNumber ?? '';
    if (wallet?.accountId == _defaultWallet?.accountId &&
        identityAccountId == _identityAccountId &&
        identityCidNumber == _identityCidNumber) {
      return;
    }
    await _loadState();
  }

  Future<void> _loadState() async {
    final generation = ++_loadGeneration;
    final defaultWallet = (await _wallet.getState()).defaultAccount;
    // CID 是快照归属主键；当前绑定账户只负责链读和签名。
    final identity = await _currentUserContext.resolve();
    final identityAccountId =
        identity?.accountId ?? defaultWallet?.accountId ?? '';
    final identityCidNumber = identity?.cidNumber ?? '';
    String? identityLevel;
    try {
      final snapshot = identityCidNumber.isEmpty
          ? null
          : await _badgeSnapshotStore.read(identityCidNumber);
      identityLevel = switch (snapshot?.identityLevel) {
        'voting' || 'candidate' => snapshot!.identityLevel,
        _ => null,
      };
    } catch (e) {
      AppLog.d('profile badge snapshot load failed: $e');
    }
    if (!mounted || generation != _loadGeneration) {
      return;
    }
    final identityChanged =
        identityAccountId != _identityAccountId ||
        identityCidNumber != _identityCidNumber;
    setState(() {
      _defaultWallet = defaultWallet;
      _identityAccountId = identityAccountId;
      _identityCidNumber = identityCidNumber;
      _defaultWalletIdentityLevel = identityLevel;
      if (identityChanged) {
        _publicProfile = null;
        _publicProfileMedia = const CitizenProfileMediaSnapshot();
        _profileSession = null;
        _membership = null;
        _membershipDecision = MembershipDisplayDecision.inactiveConfirmed;
        _profileRefreshCid = null;
      }
    });
    // 会员展示快照与本地资料一样先回刷；它只决定徽章和创作者入口首帧，任何
    // 订阅、创作者编辑动作仍在提交前读取 finalized 链状态。
    if (identityCidNumber.isNotEmpty) {
      unawaited(_loadMembershipSnapshot(identityCidNumber, generation));
    }
    // 公开资料与会员态均非阻塞加载：昵称/头像先用缓存或稳定占位渲染。
    unawaited(_refreshRemoteState(generation));
  }

  Future<void> _loadMembershipSnapshot(String cidNumber, int generation) async {
    try {
      final snapshot = await _subscriptionService.readDisplaySnapshot(
        cidNumber,
      );
      if (snapshot == null ||
          !mounted ||
          generation != _loadGeneration ||
          cidNumber != _identityCidNumber) {
        return;
      }
      setState(() {
        _membership = snapshot.state;
        _membershipDecision = snapshot.decision;
      });
    } on Exception catch (e) {
      AppLog.d('profile membership snapshot load failed: $e');
    }
  }

  Future<void> _refreshRemoteState(int generation) async {
    final SquareSession? session;
    try {
      session = await _sessionProvider.ensureSession();
    } on Exception catch (e) {
      AppLog.d('profile session load failed: $e');
      return;
    }
    if (session == null ||
        session.cidNumber.trim() != _identityCidNumber ||
        generation != _loadGeneration) {
      return;
    }

    _profileSession = session;

    await _loadPublicProfile(session, generation);

    try {
      // 身份会话只通过统一会员服务读取一次 CitizenServe；其它页面复用同一缓存。
      final membership = await _subscriptionService.authorizeMembership(
        session,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _membership = membership;
        _membershipDecision = membership.active
            ? MembershipDisplayDecision.activeConfirmed
            : MembershipDisplayDecision.inactiveConfirmed;
      });
    } on Exception catch (e) {
      AppLog.d('profile membership load failed: $e');
    }
  }

  /// 缓存立即回刷；同一页面生命周期、同一 CID 只后台请求一次。
  Future<void> _loadPublicProfile(SquareSession session, int generation) async {
    final cidNumber = session.cidNumber.trim();
    if (cidNumber.isEmpty) return;
    try {
      final cached = await _profileCache.read(cidNumber);
      if (cached != null && mounted && generation == _loadGeneration) {
        setState(() => _publicProfile = cached);
        unawaited(
          _loadPublicProfileMedia(
            cached,
            session: session,
            generation: generation,
          ),
        );
      }
    } on Exception catch (e) {
      AppLog.d('public profile cache load failed: $e');
    }

    if (_profileRefreshCid == cidNumber) return;
    _profileRefreshCid = cidNumber;
    try {
      final fresh = await _profileApi.fetchProfile(cidNumber, session: session);
      await _profileCache.write(fresh);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _publicProfile = fresh);
      unawaited(
        _loadPublicProfileMedia(
          fresh,
          session: session,
          generation: generation,
          refresh: true,
        ),
      );
    } on Exception catch (e) {
      AppLog.d('public profile refresh failed: $e');
    }
  }

  Future<void> _reloadCachedPublicProfile(
    String cidNumber,
    int generation,
  ) async {
    final profile = await _profileCache.read(cidNumber);
    if (profile == null ||
        !mounted ||
        generation != _loadGeneration ||
        cidNumber != _identityCidNumber) {
      return;
    }
    setState(() => _publicProfile = profile);
    await _loadPublicProfileMedia(
      profile,
      session: _profileSession,
      generation: generation,
    );
  }

  Future<void> _loadPublicProfileMedia(
    CitizenProfile profile, {
    required SquareSession? session,
    required int generation,
    bool refresh = false,
  }) async {
    try {
      final local = await _profileMediaCache.read(profile);
      if (!mounted ||
          generation != _loadGeneration ||
          _publicProfile?.updatedAt != profile.updatedAt) {
        return;
      }
      setState(() => _publicProfileMedia = local);
      if (!refresh || session == null) return;
      final headers = <String, String>{
        'authorization': 'Bearer ${session.sessionToken}',
      };
      final updated = await _profileMediaCache.refresh(
        profile: profile,
        avatarUrl: _publicMediaUrl(profile.avatarObjectKey, profile),
        bannerUrl: _publicMediaUrl(profile.bannerObjectKey, profile),
        headers: headers,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          _publicProfile?.updatedAt != profile.updatedAt) {
        return;
      }
      setState(() => _publicProfileMedia = updated);
    } on Exception {
      // 资料真源已存在；文件缓存异常时保留现有用户图或中性占位。
    }
  }

  String? _publicMediaUrl(String? objectKey, CitizenProfile profile) {
    final normalized = objectKey?.trim() ?? '';
    return normalized.isEmpty
        ? null
        : _profileApi.mediaUrl(normalized, updatedAt: profile.updatedAt);
  }

  Map<String, String>? get _publicMediaHeaders {
    final session = _profileSession;
    return session == null
        ? null
        : <String, String>{'authorization': 'Bearer ${session.sessionToken}'};
  }

  Future<void> _openContacts() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const ContactBookPage()));
    await _loadState();
  }

  /// 本人主页与本人用户码共用当前默认账户的本机/Cloudflare 用户上下文。
  Future<CurrentUser?> _resolveOwnedIdentity() async {
    final address = _communicationAccountId;
    if (address.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在「我的 → 我的钱包」添加钱包账户')));
      return null;
    }
    CurrentUser? identity;
    try {
      identity = await _currentUserContext.resolve();
      if (identity != null && !identity.isRegistered) {
        await _sessionProvider.ensureSession();
        identity = await _currentUserContext.resolve();
      }
    } on Exception {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法验证身份，请稍后重试')));
      return null;
    }
    if (!mounted) return null;
    final cidNumber = identity?.cidNumber.trim() ?? '';
    if (cidNumber.isEmpty) {
      // 未注册：就地弹全 App 统一注册面板；占号成功后回刷本页。
      final registered = await startCidRegistrationFlow(context);
      if (registered && mounted) await _loadState();
      return null;
    }
    return identity;
  }

  Future<void> _openMyProfile() async {
    // 资料页身份主键 = CID 号（cid_number）：按 CID 寻址（换绑不变）。
    final identity = await _resolveOwnedIdentity();
    if (!mounted || identity == null) return;
    final cidNumber = identity.cidNumber.trim();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(
          cidNumber: cidNumber,
          isSelf: true,
          initialProfile: _publicProfile,
          cache: _profileCache,
          mediaCache: _profileMediaCache,
          subscriptionService: _subscriptionService,
          initialMembershipDecision: _membershipDecision,
          initialMembershipState: _membership,
        ),
      ),
    );
    if (!mounted) return;
    await _loadState();
  }

  Future<void> _openMyUserCode() async {
    final identity = await _resolveOwnedIdentity();
    if (!mounted || identity == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UserQrPage(
          cidNumber: identity.cidNumber.trim(),
          displayName: _nickname,
          accountId: identity.accountId,
          isSelf: true,
        ),
      ),
    );
  }

  Future<void> _openMembership() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const MembershipPage()));
    await _loadState();
  }

  void _openCreator() {
    // MyTab 已持有 CID 与会员展示态，直接作为下一路由首帧；创作者页后台复核真态。
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CreatorPage(
          service: widget.creatorService,
          initialCidNumber: _identityCidNumber,
          initialMembershipDecision: _membershipDecision,
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            imagePath: _publicProfileMedia.avatarPath,
            imageUrl: _publicProfile == null
                ? null
                : _publicMediaUrl(
                    _publicProfile!.avatarObjectKey,
                    _publicProfile!,
                  ),
            imageHeaders: _publicMediaHeaders,
            userImageSet:
                _publicProfile?.avatarObjectKey?.trim().isNotEmpty == true,
            // 与用户主页统一为 80 逻辑像素；主页的 4px 边框会让默认徽章视觉上多
            // 外露约 4px，“我的”无边框，因此在这里补偿同等右下外溢距离。
            size: 80,
            badgeOverflow: 6,
            seed: _identityCidNumber.isEmpty
                ? _communicationAccountId
                : _identityCidNumber,
            identityLevel: _defaultWalletIdentityLevel,
            membershipLevel: _defaultWalletMembershipLevel,
            membershipActive: _defaultWalletMembershipActive,
          ),
          SizedBox(width: AppLayout.scaledValue(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppLayout.scaledValue(20),
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(
                        color: const Color(0x80000000),
                        blurRadius: AppLayout.scaledValue(10),
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppLayout.scaledValue(6)),
                Text(
                  _profileSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppLayout.scaledValue(14),
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(
                        color: const Color(0x99000000),
                        blurRadius: AppLayout.scaledValue(8),
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 80,
            child: Center(
              child: InkWell(
                key: const ValueKey('my-profile-chevron'),
                onTap: _openMyProfile,
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
                child: Padding(
                  padding: EdgeInsets.all(AppLayout.scaledValue(4)),
                  child: Icon(
                    Icons.chevron_right,
                    size: AppLayout.scaledValue(24),
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: const Color(0x80000000),
                        blurRadius: AppLayout.scaledValue(10),
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryEntry({
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      key: ValueKey<String>('my-primary-entry-$title'),
      height: AppLayout.primaryEntryCardHeight(context),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaledValue(12),
                vertical: AppLayout.scaledValue(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: AppLayout.primaryEntryIconBox,
                    height: AppLayout.primaryEntryIconBox,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(14),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Center(child: leading),
                  ),
                  SizedBox(width: AppLayout.scaledValue(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: AppLayout.scaledValue(15),
                            color: AppTheme.textPrimary,
                            height: AppLayout.compactLineHeight,
                          ),
                        ),
                        SizedBox(height: AppLayout.scaledValue(3)),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppLayout.scaledValue(12),
                            color: AppTheme.textSecondary,
                            height: AppLayout.subtitleLineHeight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: AppLayout.iconSmall,
                    color: AppTheme.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServiceEntry({
    required Widget leading,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return SizedBox(
      key: ValueKey<String>('my-service-entry-$title'),
      height: AppLayout.serviceEntryHeight(context),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaledValue(14),
              vertical: AppLayout.scaledValue(14),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: AppLayout.scaledValue(36),
                  height: AppLayout.scaledValue(36),
                  child: Center(child: leading),
                ),
                SizedBox(width: AppLayout.scaledValue(12)),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: AppLayout.scaledValue(15),
                      color: AppTheme.textPrimary,
                      height: AppLayout.compactLineHeight,
                    ),
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.chevron_right,
                      size: AppLayout.scaledValue(20),
                      color: AppTheme.textTertiary,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = topPadding + 260.0;
    final myTitleStyle = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        color: Colors.white,
        fontSize: AppLayout.scaled(context, 20),
        fontWeight: FontWeight.w700,
        // 显式锁定页面原有 1.4 行高，使定位测量和 Scaffold 内真实 Text 完全一致。
        height: AppLayout.bodyLineHeight,
        shadows: [
          Shadow(
            color: const Color(0x66000000),
            blurRadius: AppLayout.scaled(context, 12),
            offset: Offset(0, AppLayout.scaledValue(2)),
          ),
        ],
      ),
    );
    final myTitlePainter = TextPainter(
      text: TextSpan(text: '我的', style: myTitleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final userCodeButtonSize = AppLayout.scaled(context, 44);
    final userCodeIconSize = AppLayout.scaled(context, 22);
    // 可见图标位于点击区正中；按标题实际行高计算按钮顶部，使二维码顶部
    // 始终落在“我的”文字底部之后，系统文字倍率变化时也不重新重叠。
    final userCodeButtonTop =
        topPadding +
        AppLayout.scaled(context, 10) +
        myTitlePainter.height -
        (userCodeButtonSize - userCodeIconSize) / 2 +
        AppLayout.scaled(context, 1);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: headerHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: _openMyProfile,
                    child: _HeaderBackground(
                      path: _publicProfileMedia.bannerPath,
                      imageUrl: _publicProfile == null
                          ? null
                          : _publicMediaUrl(
                              _publicProfile!.bannerObjectKey,
                              _publicProfile!,
                            ),
                      imageHeaders: _publicMediaHeaders,
                      userImageSet:
                          _publicProfile?.bannerObjectKey?.trim().isNotEmpty ==
                          true,
                      height: headerHeight,
                      seed: _identityCidNumber.isEmpty
                          ? _communicationAccountId
                          : _identityCidNumber,
                    ),
                  ),
                  // 用户可选任意明暗的背景图；状态栏区域固定叠加暗色渐隐，保证白色
                  // 时间、信号和电池图标不会落在浅色天空或高光区域后失去对比度。
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: topPadding + 72,
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        key: ValueKey('my-header-status-bar-scrim'),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x66000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: topPadding + 10,
                    left: 0,
                    right: 0,
                    child: Center(child: Text('我的', style: myTitleStyle)),
                  ),
                  Positioned(
                    // 整个点击区随可见二维码下移；不能只挪图标造成点击位置错位。
                    // 右边距使其中心与下方资料卡右箭头严格垂直对齐。
                    top: userCodeButtonTop,
                    right: AppLayout.scaled(context, 24),
                    child: SizedBox(
                      width: userCodeButtonSize,
                      height: userCodeButtonSize,
                      child: IconButton(
                        key: const ValueKey('my-header-user-code-button'),
                        tooltip: '我的用户码',
                        padding: EdgeInsets.zero,
                        onPressed: _openMyUserCode,
                        icon: Icon(
                          Icons.qr_code_2_rounded,
                          size: userCodeIconSize,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: const Color(0x80000000),
                              blurRadius: AppLayout.scaled(context, 10),
                              offset: Offset(0, AppLayout.scaledValue(2)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: AppLayout.scaled(context, 16),
                    right: AppLayout.scaled(context, 16),
                    bottom: AppLayout.scaled(context, 22),
                    child: _buildProfileCard(),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 12)),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaled(context, 16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildPrimaryEntry(
                      leading: SvgPicture.asset(
                        'assets/icons/wallet.svg',
                        width: AppLayout.scaled(context, 24),
                        height: AppLayout.scaled(context, 24),
                        colorFilter: const ColorFilter.mode(
                          AppTheme.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                      title: '钱包',
                      subtitle: '管理账户',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const WalletTab()),
                        );
                      },
                    ),
                  ),
                  SizedBox(width: AppLayout.scaled(context, 10)),
                  Expanded(
                    child: _buildPrimaryEntry(
                      leading: Icon(
                        Icons.badge_outlined,
                        color: AppTheme.primary,
                        size: AppLayout.scaled(context, 24),
                      ),
                      title: '身份',
                      subtitle: '注册与查看',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MyIdPage()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
              child: Text(
                '个人服务',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: AppLayout.scaled(context, 17),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaled(context, 16),
              ),
              child: Container(
                decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
                child: Column(
                  children: [
                    _buildServiceEntry(
                      leading: Icon(
                        Icons.edit_outlined,
                        color: AppTheme.primary,
                        size: AppLayout.scaled(context, 22),
                      ),
                      title: '创作者',
                      onTap: _openCreator,
                    ),
                    Divider(
                      height: 1,
                      indent: AppLayout.scaled(context, 62),
                      endIndent: AppLayout.scaled(context, 14),
                    ),
                    _buildServiceEntry(
                      leading: SvgPicture.asset(
                        'assets/icons/contact-round.svg',
                        width: AppLayout.scaled(context, 22),
                        height: AppLayout.scaled(context, 22),
                        colorFilter: const ColorFilter.mode(
                          AppTheme.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                      title: '通讯录',
                      onTap: _openContacts,
                    ),
                    Divider(
                      height: 1,
                      indent: AppLayout.scaled(context, 62),
                      endIndent: AppLayout.scaled(context, 14),
                    ),
                    _buildServiceEntry(
                      leading: Icon(
                        Icons.workspace_premium_outlined,
                        color: AppTheme.primary,
                        size: AppLayout.scaled(context, 22),
                      ),
                      title: '会员｜订阅',
                      onTap: _openMembership,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 16)),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaled(context, 16),
              ),
              child: Container(
                decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
                child: _buildServiceEntry(
                  leading: UpdateDotBadge(
                    show: widget.showSettingsUpdateDot,
                    dotKey: const Key('settings-entry-update-dot'),
                    child: Icon(
                      Icons.settings_outlined,
                      color: AppTheme.textSecondary,
                      size: AppLayout.scaled(context, 22),
                    ),
                  ),
                  title: '设置',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 32)),
          ],
        ),
      ),
    );
  }
}

class _HeaderBackground extends StatelessWidget {
  const _HeaderBackground({
    required this.path,
    required this.imageUrl,
    required this.imageHeaders,
    required this.userImageSet,
    required this.height,
    required this.seed,
  });

  final String? path;
  final String? imageUrl;
  final Map<String, String>? imageHeaders;
  final bool userImageSet;
  final double height;
  final String seed;

  @override
  Widget build(BuildContext context) {
    final hasImage = path != null && path!.trim().isNotEmpty;
    final file = hasImage ? File(path!) : null;
    final validImage = file != null && file.existsSync();

    final Widget background;
    if (validImage) {
      background = Image.file(file, fit: BoxFit.cover);
    } else if (userImageSet && imageUrl?.trim().isNotEmpty == true) {
      background = Image.network(
        imageUrl!,
        headers: imageHeaders,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, syncLoaded) =>
            syncLoaded || frame != null
            ? child
            : const ColoredBox(color: AppTheme.surfaceMuted),
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: AppTheme.surfaceMuted),
      );
    } else if (userImageSet) {
      background = const ColoredBox(color: AppTheme.surfaceMuted);
    } else {
      background = Image.asset(
        ProfilePresentation.forIdentityKey(seed).bannerAsset,
        fit: BoxFit.cover,
      );
    }
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.18),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.homeTabPreferenceReader,
    this.homeTabPreferenceWriter,
  });

  /// 测试只替换 UserIsar 读写；产品运行始终使用 UserIsar 唯一真源。
  @visibleForTesting
  final Future<bool> Function()? homeTabPreferenceReader;

  @visibleForTesting
  final Future<void> Function(bool value)? homeTabPreferenceWriter;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _deviceLockKey = 'device_lock_enabled';
  final LocalAuthentication _localAuth = LocalAuthentication();
  final AppUpdateController _updateController = AppUpdateController.instance;
  bool _deviceLockEnabled = false;
  bool _pinLockEnabled = false;
  bool _duressModeEnabled = false;
  bool _openChatOnLaunch = false;
  bool _savingHomeTab = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _updateController.addListener(_handleUpdateStateChanged);
    _loadSettings();
    _updateController.check();
  }

  @override
  void dispose() {
    _updateController.removeListener(_handleUpdateStateChanged);
    super.dispose();
  }

  void _handleUpdateStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadSettings() async {
    // 四项读取先同时启动，新增首页偏好不能延长原有三项安全设置的串行等待。
    final values = await Future.wait<Object?>([
      appSecureStorage.read(key: _deviceLockKey),
      AppLockService.isPinSet(),
      AppLockService.isDuressModeEnabled(),
      (widget.homeTabPreferenceReader ??
          UserIsar.instance.readOpenChatOnLaunch)(),
    ]);
    if (!mounted) return;
    setState(() {
      _deviceLockEnabled = values[0] == 'true';
      _pinLockEnabled = values[1]! as bool;
      _duressModeEnabled = values[2]! as bool;
      _openChatOnLaunch = values[3]! as bool;
      _loading = false;
    });
  }

  Future<void> _toggleHomeTab(bool value) async {
    if (_savingHomeTab) return;
    setState(() => _savingHomeTab = true);
    try {
      await (widget.homeTabPreferenceWriter ??
          UserIsar.instance.writeOpenChatOnLaunch)(value);
      if (!mounted) return;
      setState(() => _openChatOnLaunch = value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('首页设置保存失败，请重试')));
    } finally {
      if (mounted) setState(() => _savingHomeTab = false);
    }
  }

  Future<void> _toggleDeviceLock(bool value) async {
    if (value) {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!canCheck && !isDeviceSupported) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('您的设备不支持生物识别或设备密码，无法开启设备锁')),
        );
        return;
      }

      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: BiometricAuthText.pick(
            zh: '验证身份以开启设备锁',
            en: 'Verify your identity to enable the device lock',
          ),
          authMessages: BiometricAuthText.messages(),
          biometricOnly: false,
          persistAcrossBackgrounding: true,
          sensitiveTransaction: true,
        );
        if (!authenticated) return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('身份验证失败：$e')));
        return;
      }
    }

    await appSecureStorage.write(key: _deviceLockKey, value: value.toString());
    if (!mounted) return;
    setState(() => _deviceLockEnabled = value);
  }

  Future<void> _togglePinLock(bool value) async {
    if (value) {
      // 开启：进入设置 PIN 页面
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const PinInputPage(mode: PinInputMode.setup),
        ),
      );
      if (result == true && mounted) {
        setState(() {
          _pinLockEnabled = true;
          _duressModeEnabled = false;
        });
      }
    } else {
      // 关闭：进入验证 PIN 页面（验证通过后删除）
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const PinInputPage(mode: PinInputMode.remove),
        ),
      );
      if (result == true && mounted) {
        setState(() {
          _pinLockEnabled = false;
          _duressModeEnabled = false;
        });
      }
    }
  }

  Future<void> _handlePinLockAreaTap() async {
    if (_deviceLockEnabled || _duressModeEnabled) return;
    if (!_pinLockEnabled) {
      await _togglePinLock(true);
      return;
    }
    final saved = await showDuressModeSetupDialog(context);
    if (saved && mounted) setState(() => _duressModeEnabled = true);
  }

  Future<void> _installUpdate() async {
    final started = await _updateController.downloadAndInstall();
    if (!mounted) return;

    final error = _updateController.state.errorMessage;
    if (!started && error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已打开系统安装器，请按系统提示完成更新')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : ListView(
              padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
              children: [
                // 安全区标题
                Padding(
                  padding: EdgeInsets.only(
                    left: AppLayout.scaled(context, 4),
                    bottom: AppLayout.scaled(context, 10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.security_rounded,
                        size: AppLayout.scaled(context, 16),
                        color: AppTheme.primary,
                      ),
                      SizedBox(width: AppLayout.scaled(context, 8)),
                      Text(
                        '安全',
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 13),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: AppTheme.cardDecoration(
                    radius: AppTheme.radiusLg,
                  ),
                  child: Column(
                    children: [
                      _buildSettingTile(
                        icon: Icons.fingerprint_rounded,
                        title: '设备锁',
                        subtitle: _pinLockEnabled
                            ? '请先关闭应用锁'
                            : '启动应用时需要生物识别或设备密码',
                        value: _deviceLockEnabled,
                        onChanged: _pinLockEnabled ? null : _toggleDeviceLock,
                      ),
                      Divider(
                        height: 1,
                        indent: AppLayout.scaled(context, 56),
                        endIndent: AppLayout.scaled(context, 16),
                      ),
                      _buildSettingTile(
                        icon: Icons.pin_outlined,
                        title: _pinLockEnabled && _duressModeEnabled
                            ? '应用锁（防共匪模式）'
                            : '应用锁（防共匪锁）',
                        subtitle: _deviceLockEnabled
                            ? '请先关闭设备锁'
                            : !_pinLockEnabled
                            ? '启动应用时需要输入 6 位数字密码'
                            : _duressModeEnabled
                            ? '防共匪模式已开启'
                            : '点击设置防共匪密码',
                        value: _pinLockEnabled,
                        onChanged: _deviceLockEnabled ? null : _togglePinLock,
                        onTap: _deviceLockEnabled
                            ? null
                            : _handlePinLockAreaTap,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppLayout.scaled(context, 28)),
                _buildHomeTabTile(),
                SizedBox(height: AppLayout.scaled(context, 28)),
                // 关于区标题
                Padding(
                  padding: EdgeInsets.only(
                    left: AppLayout.scaled(context, 4),
                    bottom: AppLayout.scaled(context, 10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: AppLayout.scaled(context, 16),
                        color: AppTheme.primary,
                      ),
                      SizedBox(width: AppLayout.scaled(context, 8)),
                      Text(
                        '关于',
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 13),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
                  decoration: AppTheme.cardDecoration(
                    radius: AppTheme.radiusLg,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: AppLayout.scaled(context, 36),
                            height: AppLayout.scaled(context, 36),
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(
                                AppLayout.scaledValue(8),
                              ),
                            ),
                            child: Icon(
                              Icons.how_to_vote_rounded,
                              color: Colors.white,
                              size: AppLayout.scaled(context, 18),
                            ),
                          ),
                          SizedBox(width: AppLayout.scaled(context, 12)),
                          Text(
                            '公民',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: AppLayout.scaled(context, 16),
                            ),
                          ),
                          const Spacer(),
                          _buildUpdateButton(),
                          SizedBox(width: AppLayout.scaled(context, 8)),
                          Text(
                            _updateController.state.versionLabel,
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: AppLayout.scaled(context, 13),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppLayout.scaled(context, 10)),
                      Row(
                        children: [
                          SizedBox(width: AppLayout.scaled(context, 48)),
                          Text(
                            '公民治理，链上投票',
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: AppLayout.scaled(context, 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    VoidCallback? onTap,
  }) {
    final disabled = onChanged == null && onTap == null;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppLayout.scaledValue(16),
        vertical: AppLayout.scaledValue(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
              child: Row(
                children: [
                  Container(
                    width: AppLayout.scaledValue(36),
                    height: AppLayout.scaledValue(36),
                    decoration: BoxDecoration(
                      color: disabled
                          ? AppTheme.surfaceElevated
                          : AppTheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(
                        AppLayout.scaledValue(8),
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: AppLayout.scaledValue(20),
                      color: disabled
                          ? AppTheme.textTertiary
                          : AppTheme.primary,
                    ),
                  ),
                  SizedBox(width: AppLayout.scaledValue(14)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: AppLayout.scaledValue(15),
                            fontWeight: FontWeight.w500,
                            color: disabled
                                ? AppTheme.textTertiary
                                : AppTheme.textPrimary,
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
                ],
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// 首页偏好是一行展示设置：标题、当前首页和与安全设置同款的 Switch 同行显示。
  Widget _buildHomeTabTile() {
    return Container(
      key: const ValueKey('home-tab-setting-tile'),
      // 与“我的”主页的“设置”入口复用同一高度令牌，禁止两处随屏幕缩放后分叉。
      height: AppLayout.serviceEntryHeight(context),
      decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaledValue(16),
          // Switch 保持与安全设置同款视觉和触控区；少量上下留白只负责内部居中，
          // 卡片最终行高统一由 serviceEntryHeight 控制。
          vertical: AppLayout.scaledValue(4),
        ),
        child: Row(
          children: [
            Container(
              width: AppLayout.scaledValue(36),
              height: AppLayout.scaledValue(36),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
              ),
              child: Icon(
                Icons.home_outlined,
                size: AppLayout.scaledValue(20),
                color: AppTheme.primary,
              ),
            ),
            SizedBox(width: AppLayout.scaledValue(14)),
            Expanded(
              child: Text(
                '首页设置',
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(15),
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              _openChatOnLaunch ? '聊天' : '广场',
              key: const ValueKey('home-tab-setting-value'),
              style: TextStyle(
                fontSize: AppLayout.scaledValue(13),
                color: AppTheme.textSecondary,
              ),
            ),
            SizedBox(width: AppLayout.scaledValue(8)),
            Switch(
              key: const ValueKey('home-tab-setting-switch'),
              value: _openChatOnLaunch,
              onChanged: _savingHomeTab ? null : _toggleHomeTab,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateButton() {
    final state = _updateController.state;
    if (!state.hasUpdate) {
      return const SizedBox.shrink();
    }

    final downloading = state.status == AppUpdateStatus.downloading;
    final installing = state.status == AppUpdateStatus.installing;
    final disabled = downloading || installing;
    final progress = (state.progress * 100).clamp(0, 99).round();
    final label = downloading
        ? '$progress%'
        : installing
        ? '安装'
        : '更新';

    return SizedBox(
      height: AppLayout.scaledValue(30),
      child: FilledButton.icon(
        onPressed: disabled ? null : _installUpdate,
        icon: downloading
            ? SizedBox(
                width: AppLayout.scaledValue(12),
                height: AppLayout.scaledValue(12),
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                Icons.system_update_alt_rounded,
                size: AppLayout.scaledValue(14),
              ),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: AppLayout.scaledValue(10)),
          textStyle: TextStyle(
            fontSize: AppLayout.scaledValue(12),
            fontWeight: FontWeight.w600,
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
