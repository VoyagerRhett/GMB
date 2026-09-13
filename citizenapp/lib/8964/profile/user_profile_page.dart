import 'dart:async';
import 'dart:io';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/pages/square_article_detail_page.dart';
import 'package:citizenapp/8964/pages/square_post_detail_page.dart';
import 'package:citizenapp/8964/profile/follows_list_page.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/profile_edit_page.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/user_qr_page.dart';
import 'package:citizenapp/8964/profile/widgets/collapsible_header.dart';
import 'package:citizenapp/8964/profile/widgets/creator_subscribe_button.dart';
import 'package:citizenapp/8964/profile/widgets/profile_action_icons.dart';
import 'package:citizenapp/8964/profile/widgets/profile_category_tabs.dart';
import 'package:citizenapp/8964/profile/widgets/profile_header_card.dart';
import 'package:citizenapp/8964/profile/widgets/profile_kebab_menu.dart';
import 'package:citizenapp/8964/profile/widgets/profile_posts_list.dart';
import 'package:citizenapp/8964/services/square_account_deletion_service.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/chat/chat_entry.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/security/device_subkey.dart' show bytesToHex;

/// 推特式用户主页。
///
/// 折叠虚化头部 + 圆角方形头像/背景（R2）+ 认证勾 + 展示名/地址/签名/计数 +
/// 三图标（本人 通知/聊天/关注 · 他人 关注/消息）+ ⋮（用户码/编辑资料）+
/// 公文/竞选/视频/文章四个互斥 Tab（“公文”底层仍为 posts）。身份主键 = CID 号
/// （cid_number）；cache-first
/// 加载，关注复用登录 session 静默签名，公开资料只进 R2、不上链。链上订阅/私信/
/// 用户码需要的钱包账户 account_id 从已拉取的 profile.account_id（当前绑定账户）取。
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.cidNumber,
    required this.isSelf,
    this.initialProfile,
    this.initialProfileMedia,
    this.api,
    this.cache,
    this.mediaCache,
    this.sessionProvider,
    this.subscriptionService,
    this.initialMembershipDecision =
        MembershipDisplayDecision.inactiveConfirmed,
    this.initialMembershipState,
    this.onOpenDirectChat,
    this.viewerAccountLoader,
  });

  /// 主页身份主键 = CID 号（cid_number）。资料/关注/帖子全按此 cid 寻址。
  final String cidNumber;

  /// 本人主页（可编辑资料）还是他人主页。
  final bool isSelf;

  /// 当前浏览者账户加载器（测试可注入）；默认取本机默认热钱包地址。
  /// 用于判定「他人视角看的其实是自己账户」时把动作按钮置灰。
  final Future<String?> Function()? viewerAccountLoader;

  /// 首屏可选注入的资料（缓存或上层已拉到的）。
  final CitizenProfile? initialProfile;
  final CitizenProfileMediaSnapshot? initialProfileMedia;

  /// 数据入口，测试可注入替身。
  final CitizenProfileApi? api;
  final CitizenProfileCache? cache;
  final CitizenProfileMediaCache? mediaCache;
  final SquareSessionProvider? sessionProvider;
  final SubscriptionService? subscriptionService;

  /// “我的”页已经持有的会员二元首帧；他人主页不使用该覆盖值。
  final MembershipDisplayDecision initialMembershipDecision;
  final SquareMembershipState? initialMembershipState;

  /// 私聊入口，测试可注入 spy；默认走正式 TataChatSDK。
  final DirectChatOpener? onOpenDirectChat;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  /// 顶部头图高度（不含状态栏）。
  static const double _bannerHeight = 128;

  late final CitizenProfileApi _api;
  late final CitizenProfileCache _cache;
  late final CitizenProfileMediaCache _mediaCache;
  late final SquareSessionProvider _sessionProvider;
  SubscriptionService? _subscriptionService;
  late final DirectChatOpener _directChat;
  CitizenProfile? _profile;
  CitizenProfileMediaSnapshot _profileMedia =
      const CitizenProfileMediaSnapshot();
  SquareSession? _session;
  SquareSessionStatus? _sessionStatus;
  Future<SquareSession?>? _sessionFuture;
  bool _sessionResolved = false;
  int _postsRevision = 0;
  late MembershipDisplayDecision _membershipDecision;
  SquareMembershipState? _membershipState;

  /// 「他人视角」下看的是不是自己账户；true → 关注/私信/通知/订阅按钮置灰不可点。
  bool _isOwnAccount = false;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? CitizenProfileApi();
    _cache = widget.cache ?? const CitizenProfileCache();
    _mediaCache = widget.mediaCache ?? CitizenProfileMediaCache();
    _membershipDecision = widget.initialMembershipDecision;
    _membershipState = widget.initialMembershipState;
    _directChat = widget.onOpenDirectChat ?? openDirectChat;
    _profile = widget.initialProfile;
    _profileMedia =
        widget.initialProfileMedia ?? const CitizenProfileMediaSnapshot();
    // 「他人视角看的其实是自己」判定需要目标当前绑定账户（profile.account_id），
    // 故在资料加载后（_load）再算；注入了初始资料时先算一次。
    MembershipRevision.instance.listenable.addListener(_onMembershipChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _sessionProvider =
        widget.sessionProvider ?? context.read<SquareSessionProvider>();
    final injectedSubscription = widget.subscriptionService;
    if (injectedSubscription != null) {
      _subscriptionService = injectedSubscription;
    } else {
      final sdk = context.read<CitizenSdk?>();
      final identityResolver = context.read<FinalizedIdentityResolver?>();
      if (sdk != null && identityResolver != null) {
        _subscriptionService = SubscriptionService(
          wallet: sdk.wallet,
          chain: sdk.chain,
          transactions: sdk.transactions,
          identityResolver: identityResolver,
          sessionProvider: _sessionProvider,
        );
      }
    }
    _dependenciesReady = true;
    if (_profile != null) {
      _resolveOwnAccount(_profile!.accountId);
      unawaited(_loadProfileMedia(_profile!));
    }
    if (widget.isSelf) unawaited(_loadConfirmedMembership());
    _load();
  }

  @override
  void dispose() {
    MembershipRevision.instance.listenable.removeListener(_onMembershipChanged);
    super.dispose();
  }

  /// 当前主页 CID 的会员镜像变化时重读资料，并重建当前内容 Tab 的作者徽章。
  void _onMembershipChanged() {
    final event = MembershipRevision.instance.listenable.value;
    if (!mounted || event == null || event.cidNumber != widget.cidNumber) {
      return;
    }
    setState(() => _postsRevision += 1);
    if (widget.isSelf) unawaited(_loadConfirmedMembership());
    unawaited(_load());
  }

  /// 本人徽章读取本地 CitizenServe 展示快照；没有快照时保持无会员展示。
  /// 他人主页使用 CitizenServe 当前 D1 公开资料，不存在第三种未知展示态。
  Future<void> _loadConfirmedMembership() async {
    final subscriptionService = _subscriptionService;
    if (subscriptionService == null) return;
    try {
      final snapshot = await subscriptionService.readDisplaySnapshot(
        widget.cidNumber,
      );
      if (!mounted || snapshot == null) return;
      setState(() {
        _membershipDecision = snapshot.decision;
        _membershipState = snapshot.state;
      });
    } on Exception {
      // 本地快照失败保留路由首帧或公开镜像，不伪造无会员状态。
    }
  }

  bool? get _confirmedMembershipActive {
    // null 只表示“不覆盖公开资料”，不是会员第三态；他人展示严格采用 CitizenServe D1。
    if (!widget.isSelf) return null;
    return switch (_membershipDecision) {
      MembershipDisplayDecision.activeConfirmed => true,
      MembershipDisplayDecision.inactiveConfirmed => false,
    };
  }

  /// 判定「他人视角看的其实是自己账户」：浏览者身份账户 == 目标当前绑定钱包账户
  /// （[targetAccountId] = profile.account_id）。身份主键是 cid，但浏览者手上只有
  /// 自己的当前用户上下文，故用「账户是否一致」判定同一身份。
  /// 本人视角（isSelf）按钮本就隐藏，无需判定；判定失败按非本人处理，不阻塞主页。
  Future<void> _resolveOwnAccount(String? targetAccountId) async {
    if (widget.isSelf || _isOwnAccount) return;
    final target = targetAccountId?.trim() ?? '';
    if (target.isEmpty) return;
    // 浏览者身份账户来自本机当前默认账户上下文，不为普通主页读取链。
    final loadViewer =
        widget.viewerAccountLoader ??
        () async => context.read<CurrentUserContext>().accountId();
    try {
      final viewer = (await loadViewer())?.trim() ?? '';
      if (!mounted) return;
      if (viewer.isNotEmpty && viewer == target) {
        setState(() => _isOwnAccount = true);
      }
    } on Exception {
      // 判定失败按非本人处理。
    }
  }

  Future<void> _load() async {
    // 先渲染缓存（若无注入资料），再后台刷新回刷 + 写回缓存。
    if (_profile == null) {
      final cached = await _cache.read(widget.cidNumber);
      if (cached != null && mounted) {
        setState(() => _profile = cached);
        unawaited(_resolveOwnAccount(cached.accountId));
        unawaited(_loadProfileMedia(cached));
      }
    }
    final session = await _ensureSession();
    try {
      // 带 session 拉取 → is_following 反映当前登录者视角。
      final fresh = await _api.fetchProfile(widget.cidNumber, session: session);
      if (!mounted) return;
      setState(() => _profile = fresh);
      unawaited(_resolveOwnAccount(fresh.accountId));
      await _cache.write(fresh);
      unawaited(_loadProfileMedia(fresh, session: session, refresh: true));
    } on Exception {
      // 网络/服务异常保留缓存或占位，不覆盖已展示内容。
    }
  }

  Future<void> _loadProfileMedia(
    CitizenProfile profile, {
    SquareSession? session,
    bool refresh = false,
  }) async {
    try {
      final cidNumber = profile.cidNumber?.trim() ?? '';
      if (cidNumber.isEmpty) return;
      final local = await _mediaCache.read(profile);
      if (mounted && _profile?.updatedAt == profile.updatedAt) {
        setState(() => _profileMedia = local);
      }
      if (!refresh || session == null) return;
      final headers = <String, String>{
        'authorization': 'Bearer ${session.sessionToken}',
      };
      final updated = await _mediaCache.refresh(
        profile: profile,
        avatarUrl: _mediaUrl(profile.avatarObjectKey, profile: profile),
        bannerUrl: _mediaUrl(profile.bannerObjectKey, profile: profile),
        headers: headers,
      );
      if (mounted && _profile?.updatedAt == profile.updatedAt) {
        setState(() => _profileMedia = updated);
      }
    } on Exception {
      // 公开资料仍可展示；媒体缓存失败只保留当前用户图或中性占位。
    }
  }

  /// 默认热钱包静默登录换 Session；同一时刻只允许一个握手。首次结果落地前
  /// [_sessionResolved] 保持 false，让帖子 Tab 等待而不是用 null 抢跑请求 Worker。
  Future<SquareSession?> _ensureSession({bool refresh = false}) {
    final pending = _sessionFuture;
    if (pending != null) return pending;
    if (refresh && mounted) {
      setState(() => _sessionResolved = false);
    }
    late final Future<SquareSession?> future;
    future = _resolveSession(refresh).whenComplete(() {
      if (identical(_sessionFuture, future)) _sessionFuture = null;
    });
    _sessionFuture = future;
    return future;
  }

  /// 首次握手仍由本页统一持有，但失败原因必须保留给内容区，禁止把远端故障伪装成无钱包。
  Future<SquareSession?> _resolveSession(bool refresh) async {
    final resolution = await _sessionProvider.resolveSession(refresh: refresh);
    if (mounted) {
      setState(() {
        _session = resolution.session;
        _sessionStatus = resolution.status;
        _sessionResolved = true;
      });
    }
    return resolution.session;
  }

  /// 帖子请求收到 401 时清缓存并只重新握手一次；新 Session 仍由本页统一持有。
  Future<SquareSession?> _refreshSessionAfterUnauthorized() =>
      _ensureSession(refresh: true);

  Future<void> _toggleFollow() async {
    final current = _profile;
    if (current == null) return;
    final session = _session ?? await _ensureSession();
    if (session == null) {
      _snack('请先在「我的 → 我的钱包」创建热钱包');
      return;
    }
    final wasFollowing = current.isFollowing;
    final nextFollowers = wasFollowing
        ? (current.followers > 0 ? current.followers - 1 : 0)
        : current.followers + 1;
    final nextMutualFollowing = current.isFollowedBy
        ? (wasFollowing
              ? (current.mutualFollowing > 0 ? current.mutualFollowing - 1 : 0)
              : current.mutualFollowing + 1)
        : current.mutualFollowing;
    // 乐观更新。
    setState(() {
      _profile = current.copyWith(
        isFollowing: !wasFollowing,
        // 关注即默认开通知，取关即无通知；与 Worker（关注写入默认 notify_enabled=1、
        // 取关删记录）保持一致，铃铛态随关注态即时联动。
        isNotifying: !wasFollowing,
        followers: nextFollowers,
        mutualFollowing: nextMutualFollowing,
      );
    });
    try {
      if (wasFollowing) {
        await _api.unfollowUser(
          session: session,
          followedCidNumber: widget.cidNumber,
        );
      } else {
        await _api.followUser(
          session: session,
          followedCidNumber: widget.cidNumber,
        );
      }
    } on Exception {
      if (!mounted) return;
      setState(() => _profile = current); // 失败回滚。
      _snack('操作失败，请重试');
    }
  }

  /// 开/关该用户的发帖通知（红点+声音）。通知归属挂在关注关系上：未关注先提示去关注；
  /// 关注后铃铛按用户静音/取消静音，静音不影响其内容在关注流展示。
  Future<void> _toggleNotify() async {
    final current = _profile;
    if (current == null) return;
    if (!current.isFollowing) {
      _snack('请先关注 TA 再开启通知');
      return;
    }
    final session = _session ?? await _ensureSession();
    if (session == null) {
      _snack('请先在「我的 → 我的钱包」创建热钱包');
      return;
    }
    final wasNotifying = current.isNotifying;
    // 乐观更新。
    setState(() {
      _profile = current.copyWith(isNotifying: !wasNotifying);
    });
    try {
      await _api.setNotify(
        session: session,
        followedCidNumber: widget.cidNumber,
        enabled: !wasNotifying,
      );
    } on Exception {
      if (!mounted) return;
      setState(() => _profile = current); // 失败回滚。
      _snack('操作失败，请重试');
    }
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.of(context).push<CitizenProfile>(
      MaterialPageRoute<CitizenProfile>(
        builder: (_) => CitizenProfileEditPage(
          cidNumber: widget.cidNumber,
          initialProfile: _profile,
          api: _api,
          cache: _cache,
          mediaCache: _mediaCache,
          sessionProvider: _sessionProvider,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _profile = updated);
    await _cache.write(updated);
    await _loadProfileMedia(updated, session: _session, refresh: true);
  }

  /// 注销用户（仅本人）：二次确认 → 主钥签名(生物识别) → 服务端硬删 → 清本地 → 回落空态。
  /// 无冷静期、硬删不可逆；链上数据与本地钱包不受影响。
  Future<void> _openDeleteAccount() async {
    // 注销目标始终是页面永久 CID；profile.account_id 只作为该 CID 当前绑定账户完成
    // 会话与主钥签名授权，Worker 会再用 finalized 链双向绑定复核，不能决定删除范围。
    final selfAccountId = _profile?.accountId.trim() ?? '';
    if (selfAccountId.isEmpty) {
      _snack('资料尚未加载，请稍后再试');
      return;
    }
    final sdk = context.read<CitizenSdk>();
    final walletState = await sdk.wallet.getState();
    if (!mounted) return;
    if (!walletState.accounts.any(
      (account) => account.accountId == selfAccountId,
    )) {
      _snack('未找到当前身份钱包账户，无法注销');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('注销用户'),
        content: const Text('注销将立即硬删除你在公民广场/私信的全部数据，无冷静期、不可恢复，链上数据不受注销影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认注销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await SquareAccountDeletionService(
        chatRuntime: context.read<ChatSdk>(),
      ).deleteAccount(
        cidNumber: widget.cidNumber,
        accountId: selfAccountId,
        // 账户注销签名统一交给 CitizenSDK，冷热模式不在页面分支。
        // 设备子钥仍按 cid_number 精确删除，不进入钱包签名模式。
        signAction: (message) async =>
            '0x${bytesToHex(await signCitizenPayload(signing: sdk.signing, context: context, accountId: selfAccountId, payload: message, action: QrActions.squareAccountAction))}',
      );
    } on SquareAccountLocalCleanupException catch (e) {
      // Worker 已经完成不可逆注销；此时不能误报“注销失败”诱导用户重复提交。
      if (mounted) _snack(e.toString());
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    } on SquareApiException catch (e) {
      if (mounted) _snack('注销失败：${e.message}');
      return;
    } on CitizenSdkException catch (e) {
      if (mounted) _snack('注销已取消：${e.message}');
      return;
    } on Exception catch (e) {
      // 兜底：注销签名的任何异常都必须有反馈，永不静默。
      if (mounted) _snack('注销失败：$e');
      return;
    }

    if (!mounted) return;
    _snack('账户已注销');
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openUserCode() {
    // 用户码载荷取该永久公民号当前绑定的 account_id，供加联系人和转账使用。
    final accountId = _profile?.accountId.trim() ?? '';
    if (accountId.isEmpty) {
      _snack('资料尚未加载，请稍后再试');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserQrPage(
          cidNumber: widget.cidNumber,
          displayName: _displayName,
          accountId: accountId,
          isSelf: widget.isSelf,
        ),
      ),
    );
  }

  void _openChatWithUser() {
    final peerCidNumber = widget.cidNumber.trim();
    if (peerCidNumber.isEmpty) {
      _snack('资料尚未加载，请稍后再试');
      return;
    }
    _directChat(context, peerUserId: peerCidNumber, title: _displayName);
  }

  void _openFollows(FollowsType type) {
    final session = _session;
    if (session == null) {
      _snack('需要钱包账户才能浏览关注列表');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowsListPage(
          cidNumber: widget.cidNumber,
          type: type,
          session: session,
          api: _api,
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 公开昵称只取后端 `display_name`；缺失时按 CID 稳定生成本地占位昵称。
  String get _displayName {
    return ProfilePresentation.forIdentityKey(
      widget.cidNumber,
    ).resolveDisplayName(publicName: _profile?.displayName);
  }

  String get _title => _displayName;

  String? _mediaUrl(String? objectKey, {CitizenProfile? profile}) =>
      objectKey == null
      ? null
      : _api.mediaUrl(objectKey, updatedAt: (profile ?? _profile)?.updatedAt);

  Map<String, String>? get _mediaHeaders => _session == null
      ? null
      : <String, String>{'authorization': 'Bearer ${_session!.sessionToken}'};

  Widget _bannerWidget() {
    final fallback = Image.asset(
      ProfilePresentation.forIdentityKey(widget.cidNumber).bannerAsset,
      fit: BoxFit.cover,
    );
    final objectKey = _profile?.bannerObjectKey?.trim();
    if (objectKey == null || objectKey.isEmpty) return fallback;
    final path = _profileMedia.bannerPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    final url = _mediaUrl(objectKey);
    if (url == null) return const ColoredBox(color: AppTheme.surfaceMuted);
    return Image.network(
      url,
      headers: _mediaHeaders,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, syncLoaded) =>
          syncLoaded || frame != null
          ? child
          : const ColoredBox(color: AppTheme.surfaceMuted),
      errorBuilder: (_, __, ___) =>
          const ColoredBox(color: AppTheme.surfaceMuted),
    );
  }

  /// 他人主页的创作者订阅入口：SquarePost 以公民 CID 为创作者唯一主键。
  /// 本人主页不显示；CID 不因换绑改变，因此换绑不会重建或丢失订阅态。
  Widget? _creatorSubscribeButton() {
    if (widget.isSelf) return null;
    final creatorCidNumber = widget.cidNumber.trim();
    if (creatorCidNumber.isEmpty) return null;
    return CreatorSubscribeButton(
      key: ValueKey<String>('creator-subscribe:$creatorCidNumber'),
      creatorCidNumber: creatorCidNumber,
      enabled: !_isOwnAccount,
      sessionProvider: _sessionProvider,
    );
  }

  Future<void> _openPost(SquarePost post) async {
    final result = await Navigator.of(context).push<SquarePostDetailResult>(
      MaterialPageRoute<SquarePostDetailResult>(
        builder: (_) => SquarePostDetailPage(post: post),
      ),
    );
    if (result != null && mounted) {
      setState(() => _postsRevision += 1);
    }
  }

  Future<void> _openArticle(SquarePost post) async {
    final result = await Navigator.of(context).push<SquarePostDetailResult>(
      MaterialPageRoute<SquarePostDetailResult>(
        builder: (_) => SquareArticleDetailPage(post: post),
      ),
    );
    if (result != null && mounted) {
      setState(() => _postsRevision += 1);
    }
  }

  Widget _tabBody(ProfileTab tab) {
    final session = _session;
    switch (tab) {
      case ProfileTab.posts:
        return ProfilePostsTab(
          key: ValueKey('posts:$_postsRevision'),
          cidNumber: widget.cidNumber,
          api: _api,
          category: SquarePostCategory.normal,
          postType: SquarePostType.document,
          emptyLabel: '还没有公文',
          session: session,
          sessionReady: _sessionResolved,
          sessionUnavailableMessage: _sessionStatus?.message,
          onSessionExpired: _refreshSessionAfterUnauthorized,
          isSelf: widget.isSelf,
          onOpenPost: _openPost,
        );
      case ProfileTab.campaign:
        return ProfilePostsTab(
          key: ValueKey('campaign:$_postsRevision'),
          cidNumber: widget.cidNumber,
          api: _api,
          category: SquarePostCategory.campaign,
          emptyLabel: '还没有竞选内容',
          session: session,
          sessionReady: _sessionResolved,
          sessionUnavailableMessage: _sessionStatus?.message,
          onSessionExpired: _refreshSessionAfterUnauthorized,
          isSelf: widget.isSelf,
          onOpenPost: _openPost,
        );
      case ProfileTab.videos:
        return ProfilePostsTab(
          key: ValueKey('videos:$_postsRevision'),
          cidNumber: widget.cidNumber,
          api: _api,
          category: SquarePostCategory.normal,
          postType: SquarePostType.video,
          mediaKind: SquareMediaKind.video,
          emptyLabel: '还没有视频',
          session: session,
          sessionReady: _sessionResolved,
          sessionUnavailableMessage: _sessionStatus?.message,
          onSessionExpired: _refreshSessionAfterUnauthorized,
          isSelf: widget.isSelf,
          onOpenPost: _openPost,
        );
      case ProfileTab.articles:
        return ProfilePostsTab(
          key: ValueKey('articles:$_postsRevision'),
          cidNumber: widget.cidNumber,
          api: _api,
          category: SquarePostCategory.normal,
          postType: SquarePostType.article,
          emptyLabel: '还没有文章',
          session: session,
          sessionReady: _sessionResolved,
          sessionUnavailableMessage: _sessionStatus?.message,
          onSessionExpired: _refreshSessionAfterUnauthorized,
          isSelf: widget.isSelf,
          onOpenPost: _openArticle,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expandedHeight =
        _bannerHeight +
        ProfileCategoryTabs.height +
        ProfileHeaderCard.requiredHeight(context, bio: _profile?.bio ?? '');
    return DefaultTabController(
      length: ProfileTab.values.length,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                pinned: true,
                expandedHeight: expandedHeight,
                // 品牌色只作为所有图片均失败时的最底层兜底；完全折叠态由
                // CollapsibleHeader 明确绘制真实背景，不再依赖透明 Material 透出页面。
                backgroundColor: AppTheme.primaryDark,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                foregroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.chevron_left),
                  // 背景图明暗不定：加半透明深色圆形底衬保证白色返回箭头始终可读。
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.32),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                actions: [
                  ProfileKebabMenu(
                    isSelf: widget.isSelf,
                    onUserCode: _openUserCode,
                    onEditProfile: _openEditProfile,
                    onDeleteAccount: _openDeleteAccount,
                  ),
                ],
                // 展开头图和固定折叠头图各自明确渲染；不能再以透明背景替代真实图片。
                flexibleSpace: CollapsibleHeader(
                  expandedHeight: expandedHeight,
                  bannerHeight: _bannerHeight,
                  bottomHeight: ProfileCategoryTabs.height,
                  collapsedTitle: _title,
                  banner: _bannerWidget(),
                  collapsedBanner: _bannerWidget(),
                  foreground: ProfileHeaderCard(
                    cidNumber: widget.cidNumber,
                    profile: _profile,
                    avatarPath: _profileMedia.avatarPath,
                    avatarUrl: _mediaUrl(_profile?.avatarObjectKey),
                    avatarHeaders: _mediaHeaders,
                    confirmedMembershipLevel: _membershipState?.membershipLevel,
                    confirmedMembershipActive: _confirmedMembershipActive,
                    onFollowing: () => _openFollows(FollowsType.following),
                    onFollowers: () => _openFollows(FollowsType.followers),
                    onMutualFollowing: () =>
                        _openFollows(FollowsType.mutualFollowing),
                    actions: ProfileActionIcons(
                      isSelf: widget.isSelf,
                      isFollowing: _profile?.isFollowing ?? false,
                      isNotifying: _profile?.isNotifying ?? false,
                      // 他人视角看的是自己账户时置灰（不能关注/私信/通知自己）。
                      enabled: !_isOwnAccount,
                      // 有有效创作者计划时在通知左侧就地出现；不存在时完全不占位。
                      leading: _creatorSubscribeButton(),
                      onNotify: _toggleNotify,
                      onChat: _openChatWithUser,
                      onToggleFollow: _toggleFollow,
                    ),
                  ),
                ),
                bottom: ProfileCategoryTabs(
                  posts: _profile?.posts ?? 0,
                  campaigns: _profile?.campaigns ?? 0,
                  videos: _profile?.videos ?? 0,
                  articles: _profile?.articles ?? 0,
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [for (final tab in ProfileTab.values) _tabBody(tab)],
          ),
        ),
      ),
    );
  }
}
