import 'package:provider/provider.dart';
import 'package:citizenapp/8964/chain/square_chain_service.dart';
import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:citizenapp/log/app_log.dart';

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/pages/square_article_detail_page.dart';
import 'package:citizenapp/8964/compose/compose_page.dart';
import 'package:citizenapp/8964/pages/square_post_detail_page.dart';
import 'package:citizenapp/8964/profile/user_profile_page.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_identity_state.dart';
import 'package:citizenapp/8964/services/square_post_sync_service.dart';
import 'package:citizenapp/8964/widgets/square_feed_tabs.dart';
import 'package:citizenapp/8964/widgets/square_article_card.dart';
import 'package:citizenapp/8964/widgets/square_post_card.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/identity_register_guide.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/ui/app_layout.dart';

class SquareHomePage extends StatefulWidget {
  const SquareHomePage({
    super.key,
    this.identityService,
    this.feedSource,
    this.initialFeed = SquareFeedKind.recommended,
    this.seedPosts = const <SquarePost>[],
    this.sessionProvider,
    this.onSquareUnreadChanged,
    this.selectedTab,
    this.tabIndex = 0,
  });

  final SquareIdentityService? identityService;
  final SquareFeedSource? feedSource;
  final SquareFeedKind initialFeed;
  final List<SquarePost> seedPosts;
  final SquareSessionProvider? sessionProvider;

  /// 广场底部 tab 红点计数回调（上抛给 AppShell 挂 Badge）。
  final ValueChanged<int>? onSquareUnreadChanged;

  /// 底部导航当前活动 tab 广播；值 == [tabIndex] 时视为「进广场」，清广场红点。
  final ValueNotifier<int>? selectedTab;
  final int tabIndex;

  @override
  State<SquareHomePage> createState() => _SquareHomePageState();
}

class _SquareHomePageState extends State<SquareHomePage> {
  late SquareFeedKind _selectedFeed = widget.initialFeed;
  late Future<SquareIdentityState> _identityFuture;
  late final SquareIdentityService _identityService;
  late final SquareFeedSource _feedSource;
  late Future<List<SquarePost>> _feedFuture;
  int _feedLoadGeneration = 0;
  final List<SquarePost> _localPosts = [];

  /// 最近一次身份加载结果的身份账户与永久 CID，供身份 revision 广播后成对比对。
  String? _identityAddress;
  String? _identityCidNumber;

  final SquareApiClient _squareApi = SquareApiClient();
  final SquarePostSyncService _postSyncService = SquarePostSyncService();

  /// 最近一次 feed 加载的 session token，供卡片头像鉴权头复用。
  String? _feedSessionToken;
  SquareSessionProvider? _sessionProvider;
  AccountSecurityService? _accountSecurity;
  bool _dependenciesReady = false;

  /// 关注子 tab 红点数（服务端 following_unread）。广场底部 tab 数经回调上抛。
  int _followingUnread = 0;

  /// 发帖通知红点轮询；仅生产真实数据源下开启，测试注入 fake feedSource 时跳过不触网。
  static const Duration _notifyPollInterval = Duration(seconds: 45);
  Timer? _notifyTimer;
  bool _publishMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _feedSource = widget.feedSource ?? SquareApiClient();
    MembershipRevision.instance.listenable.addListener(_onMembershipChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _sessionProvider = widget.sessionProvider;
    final injectedIdentity = widget.identityService;
    if (injectedIdentity != null) {
      _identityService = injectedIdentity;
    } else {
      final sdk = context.read<CitizenSdk>();
      final accountSecurity = context.read<AccountSecurityService>();
      _sessionProvider ??= context.read<SquareSessionProvider>();
      _identityService = SquareIdentityService(
        wallet: sdk.wallet,
        currentUserContext: context.read<CurrentUserContext>(),
        chainService: SquareChainService(
          chain: sdk.chain,
          transactions: sdk.transactions,
        ),
      );
      _accountSecurity = accountSecurity;
      accountSecurity.revision.addListener(_onWalletsChanged);
    }
    _identityFuture = _loadIdentity(readLiveChain: false);
    // 浏览态首帧直接挂载页面并并行加载 feed；身份与会员只在发布等写操作前严格校验，
    // 避免链读取或会话握手把整个广场长期挡在转圈页后面。
    _feedFuture = _beginFeedLoad();
    // 本页常驻 IndexedStack；切换身份账户（CID 换绑 / 切钱包）后经
    // 账户／身份 revision 广播重载身份，保证身份图标与作者点击的 isSelf
    // 判定始终基于当前身份账户。
    // 发帖通知红点：仅生产真实数据源下开启（fake feedSource 的测试不触网）。
    if (_feedSource is SquareApiClient) {
      widget.selectedTab?.addListener(_onSelectedTabChanged);
      unawaited(_onSquareActivated());
      _notifyTimer = Timer.periodic(
        _notifyPollInterval,
        (_) => unawaited(_refreshNotify()),
      );
    }
    _dependenciesReady = true;
  }

  @override
  void dispose() {
    _accountSecurity?.revision.removeListener(_onWalletsChanged);
    MembershipRevision.instance.listenable.removeListener(_onMembershipChanged);
    _notifyTimer?.cancel();
    widget.selectedTab?.removeListener(_onSelectedTabChanged);
    super.dispose();
  }

  /// 会员确认事件只负责让当前 feed 重新读取 Worker 作者信号；事件本身不携带权益。
  void _onMembershipChanged() {
    if (!mounted || MembershipRevision.instance.listenable.value == null) {
      return;
    }
    unawaited(_refreshFeedAfterMembershipChanged());
  }

  Future<void> _refreshFeedAfterMembershipChanged() async {
    try {
      await _refreshFeed();
    } on Object catch (error) {
      AppLog.d('square feed membership refresh failed: $error');
    }
  }

  /// 底部导航切到广场（值 == tabIndex）→ 清广场红点。
  void _onSelectedTabChanged() {
    if (widget.selectedTab?.value == widget.tabIndex) {
      unawaited(_onSquareActivated());
    }
  }

  Future<SquareSession?> _notifySession() async {
    try {
      return await (_sessionProvider ?? context.read<SquareSessionProvider>())
          .ensureSession();
    } on Object {
      // 后台通知由 unawaited 启动，任何会话失败都只能降级为不刷新红点，
      // 不得逸出为未捕获异步异常并影响广场浏览。
      return null;
    }
  }

  /// 拉双游标红点：广场数经回调上抛底部 tab，关注数留本地驱动关注子 tab 徽章。
  Future<void> _refreshNotify() async {
    if (_feedSource is! SquareApiClient) return;
    final session = await _notifySession();
    if (session == null) return;
    try {
      final counts = await _squareApi.fetchNotifyUnread(session: session);
      if (!mounted) return;
      widget.onSquareUnreadChanged?.call(counts.squareUnread);
      if (counts.followingUnread != _followingUnread) {
        setState(() => _followingUnread = counts.followingUnread);
      }
    } on Object {
      // 红点拉取失败静默：不影响广场浏览。
    }
  }

  /// 进广场：清广场游标 → 底部红点归零，随后回拉（关注游标不动，关注红点保留）。
  Future<void> _onSquareActivated() async {
    if (_feedSource is! SquareApiClient) return;
    final session = await _notifySession();
    if (session == null) return;
    try {
      await _squareApi.markNotifyRead(session: session, scope: 'square');
      if (mounted) widget.onSquareUnreadChanged?.call(0);
    } on Object {
      // 清读失败静默；下次轮询以服务端为准。
    }
    await _refreshNotify();
  }

  /// 进关注子 tab：清关注游标 → 关注红点归零。
  Future<void> _onFollowingActivated() async {
    if (_feedSource is! SquareApiClient) return;
    if (mounted && _followingUnread != 0) {
      setState(() => _followingUnread = 0);
    }
    final session = await _notifySession();
    if (session == null) return;
    try {
      await _squareApi.markNotifyRead(session: session, scope: 'following');
    } on Object {
      // 清读失败静默；本地已归零，下次轮询以服务端为准。
    }
  }

  Future<SquareIdentityState> _loadIdentity({
    required bool readLiveChain,
  }) async {
    final identity = await _identityService.loadCurrent(
      readLiveChain: readLiveChain,
    );
    _identityAddress = identity.accountId;
    _identityCidNumber = identity.cidNumber;
    return identity;
  }

  Future<void> _onWalletsChanged() async {
    // CID 占号可在 account_id 不变时把 cid_number 从空推进为有效值；收到显式身份
    // revision 后必须读取完整身份，不能沿用只比较账户的旧优化。
    final identity = await context.read<CurrentUserContext>().resolve();
    final identityAccountId = identity?.accountId ?? '';
    final identityCidNumber = identity?.cidNumber ?? '';
    if (!mounted) return;
    if (identityAccountId == (_identityAddress ?? '') &&
        identityCidNumber == (_identityCidNumber ?? '')) {
      return;
    }
    setState(() {
      _identityFuture = _loadIdentity(readLiveChain: false);
      _feedFuture = _beginFeedLoad();
    });
  }

  Future<void> _openCompose(SquarePostType postType) async {
    // 菜单和编辑页只使用本地当前用户；finalized 身份、会员和余额统一留到最终签名阶段。
    if (_publishMenuOpen) setState(() => _publishMenuOpen = false);
    final post = await Navigator.of(context).push<SquarePost>(
      MaterialPageRoute<SquarePost>(
        builder: (_) => SquareComposePage(
          postType: postType,
          identityService: _identityService,
        ),
      ),
    );
    if (post == null || !mounted) return;
    setState(() => _localPosts.insert(0, post));
    await _refreshFeed();
  }

  Future<void> _openAuthor(String cidNumber) async {
    if (cidNumber.isEmpty) return;
    final identity = await _identityFuture;
    if (!mounted) return;
    // 身份主键 = cid_number：作者主键与本人身份都按 cid 比对判定 isSelf。
    final selfCid = identity.cidNumber?.trim() ?? '';
    final isSelf = selfCid.isNotEmpty && selfCid == cidNumber;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UserProfilePage(cidNumber: cidNumber, isSelf: isSelf),
      ),
    );
  }

  Future<void> _openDetail(SquarePost post) async {
    final result = await Navigator.of(context).push<SquarePostDetailResult>(
      MaterialPageRoute<SquarePostDetailResult>(
        builder: (_) => post.postType == SquarePostType.article
            ? SquareArticleDetailPage(post: post)
            : SquarePostDetailPage(post: post),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _localPosts.removeWhere((item) => item.postId == post.postId);
      final replacement = result.replacement;
      if (replacement != null) {
        _localPosts.removeWhere((item) => item.postId == replacement.postId);
        _localPosts.insert(0, replacement);
      }
    });
    await _refreshFeed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _SquarePublishMenu(
        expanded: _publishMenuOpen,
        onToggle: () => setState(() => _publishMenuOpen = !_publishMenuOpen),
        onSelected: _openCompose,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // 头像入口已删（进自己主页只走「我的-背景图」），分类栏上移到顶部省空间。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: SquareFeedTabs(
                      selected: _selectedFeed,
                      followingUnread: _followingUnread,
                      onChanged: (feed) {
                        setState(() {
                          _selectedFeed = feed;
                          _feedFuture = _beginFeedLoad();
                        });
                        if (feed == SquareFeedKind.following) {
                          unawaited(_onFollowingActivated());
                        }
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Opacity(
                              key: const ValueKey<String>(
                                'square-person-tank-watermark-opacity',
                              ),
                              // 8% 只增强背景可见度；原图 alpha 保持完整，避免资产被二次淡化。
                              opacity: 0.08,
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: 2.2,
                                  sigmaY: 2.2,
                                ),
                                // 只替换 feed 底层水印；顶栏、内容、FAB 和底部导航
                                // 不读取该图片，也不得随水印设计一起改动。
                                child: Image.asset(
                                  'assets/icons/square-person-tank-watermark.png',
                                  key: const ValueKey<String>(
                                    'square-person-tank-watermark',
                                  ),
                                  width: AppLayout.scaled(context, 280),
                                  height: AppLayout.scaled(context, 141),
                                  fit: BoxFit.contain,
                                  color: AppTheme.primary,
                                  colorBlendMode: BlendMode.srcIn,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      FutureBuilder<List<SquarePost>>(
                        future: _feedFuture,
                        builder: (context, snapshot) {
                          final error = snapshot.error;
                          if (error is SquareApiException &&
                              error.errorCode == 'cid_not_bound') {
                            return IdentityRegisterGuide(
                              description: '注册后即可浏览广场、发布内容。',
                              onRegistered: _onRegisteredFromGuide,
                            );
                          }
                          final posts = _composeFeed(
                            snapshot.data ?? const <SquarePost>[],
                          );
                          final errorMessage = snapshot.hasError
                              ? '广场内容加载失败'
                              : null;
                          return Stack(
                            children: [
                              RefreshIndicator(
                                onRefresh: _refreshFeed,
                                child: _FeedBody(
                                  posts: posts,
                                  errorMessage: errorMessage,
                                  onOpenPost: _openDetail,
                                  onOpenAuthor: _openAuthor,
                                  mediaUrlOf: _squareApi.mediaUrl,
                                  avatarHeaders: _feedSessionToken == null
                                      ? null
                                      : {
                                          'authorization':
                                              'Bearer $_feedSessionToken',
                                        },
                                ),
                              ),
                              if (snapshot.connectionState !=
                                  ConnectionState.done)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: LinearProgressIndicator(
                                    key: const ValueKey('square-feed-progress'),
                                    minHeight: AppLayout.scaled(context, 2),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_publishMenuOpen)
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('square-publish-menu-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _publishMenuOpen = false),
                child: const ColoredBox(color: Color(0x14000000)),
              ),
            ),
        ],
      ),
    );
  }

  Future<List<SquarePost>> _loadFeed(
    SquareFeedKind feedKind,
    int generation,
  ) async {
    SquareSession? session;
    SquareSessionProvider? sessionProvider;
    if (_feedSource is SquareApiClient) {
      sessionProvider =
          _sessionProvider ?? context.read<SquareSessionProvider>();
      session = await sessionProvider.ensureSession();
      if (session == null) {
        throw const SquareApiException('需要钱包账户才能浏览广场');
      }
      // 会话和链上当前绑定均已通过后再后台回灌本人副本；不阻塞公共 feed 首屏。
      // 同步失败只保留本地既有内容，下次启动/刷新继续从未推进的检查点重试。
      unawaited(
        _postSyncService.sync(session).catchError((Object error) {
          AppLog.d('[SquareHomePage] local post sync failed: $error');
        }),
      );
    }
    List<SquarePost> posts;
    try {
      posts = await _feedSource.fetchFeed(feedKind: feedKind, session: session);
    } on SquareApiException catch (error) {
      // 只在 Worker 明确拒绝旧 Session 时重新握手一次；第二次失败原样交给前台，禁止
      // 无限重试。测试/离线数据源不参与生产会话刷新。
      if (error.statusCode != 401 ||
          _feedSource is! SquareApiClient ||
          generation != _feedLoadGeneration) {
        rethrow;
      }
      final refreshed = await sessionProvider!.refreshSession();
      if (refreshed == null) rethrow;
      session = refreshed;
      posts = await _feedSource.fetchFeed(
        feedKind: feedKind,
        session: refreshed,
      );
    }
    // 存 session token 供 feed 卡片头像 Image.network 带鉴权头（读任意作者头像同域可读）。
    // 迟到的旧分类请求不得覆盖当前分类的媒体鉴权头。
    if (generation == _feedLoadGeneration) {
      _feedSessionToken = session?.sessionToken;
    }
    return posts;
  }

  Future<List<SquarePost>> _beginFeedLoad() {
    final generation = ++_feedLoadGeneration;
    final feedKind = _selectedFeed;
    final future = _loadFeed(feedKind, generation);
    // initState 和分类切换会先创建 Future、随后才由下一帧 FutureBuilder 挂监听。
    // Worker 快速失败时必须立刻观察错误，消除这段未处理时间窗；原 Future
    // 不做转换，页面仍能通过 snapshot.hasError 展示真实前台失败态。
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          AppLog.d('[SquareHomePage] feed load failed: $error');
        },
      ),
    );
    return future;
  }

  Future<void> _refreshFeed() async {
    final next = _beginFeedLoad();
    // Future 赋值表达式本身会返回 Future，必须使用语句块确保 setState 回调
    // 同步返回 void；会员确认后的就地刷新也复用这条安全路径。
    setState(() {
      _feedFuture = next;
    });
    await next;
  }

  /// 引导内占号成功后的就地回刷。服务层已经先失效身份缓存再广播全局 revision；
  /// 当前回调只保证本页在注册流程返回的同一帧重载身份与 feed。
  void _onRegisteredFromGuide() {
    if (!mounted) return;
    setState(() {
      _identityFuture = _loadIdentity(readLiveChain: false);
      _feedFuture = _beginFeedLoad();
    });
  }

  /// 按当前 feed 组装最终列表。[serverPosts] 是 `_loadFeed` 已按所选 feed 从
  /// Worker 拉回的结果。关注流由服务端 `square_posts JOIN square_follows` 过滤，
  /// 直接渲染服务端结果——本地草稿与种子帖不属于关注流，只在其余分类混入。
  List<SquarePost> _composeFeed(List<SquarePost> serverPosts) {
    final merged = [..._localPosts, ...serverPosts, ...widget.seedPosts];
    switch (_selectedFeed) {
      case SquareFeedKind.recommended:
        return merged;
      case SquareFeedKind.following:
        return serverPosts;
      case SquareFeedKind.campaign:
        return merged
            .where((post) => post.postCategory == SquarePostCategory.campaign)
            .toList(growable: false);
      case SquareFeedKind.article:
        return merged
            .where((post) => post.postType == SquarePostType.article)
            .toList(growable: false);
      case SquareFeedKind.videos:
        return merged
            .where((post) => post.postType == SquarePostType.video)
            .toList(growable: false);
    }
  }
}

class _FeedBody extends StatelessWidget {
  const _FeedBody({
    required this.posts,
    required this.errorMessage,
    required this.onOpenPost,
    required this.onOpenAuthor,
    required this.mediaUrlOf,
    required this.avatarHeaders,
  });

  final List<SquarePost> posts;
  final String? errorMessage;
  final ValueChanged<SquarePost> onOpenPost;
  final ValueChanged<String> onOpenAuthor;

  /// 把 object_key 解析成可读媒体地址（作者头像等）。
  final String Function(String objectKey) mediaUrlOf;

  /// 头像 `Image.network` 鉴权头（钱包 session Bearer）；未登录为空。
  final Map<String, String>? avatarHeaders;

  String? _avatarUrl(SquareAuthor author) {
    final key = author.avatarObjectKey;
    return key == null ? null : mediaUrlOf(key);
  }

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      // 空态不再展示图标+文字，仅保留可下拉刷新的空滚动区，让底层人物坦克水印透出；
      // 有错误时顶部仍显示错误横幅。
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [if (errorMessage != null) _errorBanner(errorMessage!)],
      );
    }

    return ListView.separated(
      // 底部留白给右下角发布 FAB，避免盖住末条内容的互动区。
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      itemBuilder: (context, index) {
        if (index == 0 && errorMessage != null) {
          return _errorBanner(errorMessage!);
        }
        final postIndex = errorMessage == null ? index : index - 1;
        final post = posts[postIndex];
        final avatarUrl = _avatarUrl(post.author);
        // 文章走标题/正文在上、强制横屏首图在下的文章卡；其余走图文卡。
        if (post.postType == SquarePostType.article) {
          return SquareArticleCard(
            post: post,
            onTap: () => onOpenPost(post),
            onAuthorTap: () => onOpenAuthor(post.author.cidNumber ?? ''),
            avatarUrl: avatarUrl,
            avatarHeaders: avatarHeaders,
          );
        }
        return SquarePostCard(
          post: post,
          onTap: () => onOpenPost(post),
          onAuthorTap: () => onOpenAuthor(post.author.cidNumber ?? ''),
          avatarUrl: avatarUrl,
          avatarHeaders: avatarHeaders,
        );
      },
      separatorBuilder: (_, __) =>
          SizedBox(height: AppLayout.scaled(context, 10)),
      itemCount: posts.length + (errorMessage == null ? 0 : 1),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: EdgeInsets.all(AppLayout.scaledValue(12)),
      decoration: AppTheme.bannerDecoration(AppTheme.warning),
      child: Text(
        message,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: AppLayout.scaledValue(13),
          height: 1.35,
        ),
      ),
    );
  }
}

/// 右下角发布按钮的三项等半径圆弧菜单；只管理本地动画和类型导航，
/// 不触发任何网络或链读取。
class _SquarePublishMenu extends StatefulWidget {
  const _SquarePublishMenu({
    required this.expanded,
    required this.onToggle,
    required this.onSelected,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<SquarePostType> onSelected;

  static const _duration = Duration(milliseconds: 220);

  @override
  State<_SquarePublishMenu> createState() => _SquarePublishMenuState();
}

class _SquarePublishMenuState extends State<_SquarePublishMenu> {
  bool _itemsVisible = false;

  @override
  void initState() {
    super.initState();
    _itemsVisible = widget.expanded;
  }

  @override
  void didUpdateWidget(covariant _SquarePublishMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded) {
      // 本轮 build 会立即把入口挂回主按钮位置，再沿圆弧展开。
      _itemsVisible = true;
      return;
    }
    if (oldWidget.expanded) {
      // 先播放归位/淡出动画，结束后再移出命中测试与语义树。
      Future<void>.delayed(_SquarePublishMenu._duration, () {
        if (!mounted || widget.expanded) return;
        setState(() => _itemsVisible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = AppLayout.scaled(context, 190);
    final mainSize = AppLayout.scaled(context, 56);
    final itemSize = AppLayout.scaled(context, 46);
    final radius = AppLayout.scaled(context, 100);
    final origin = size - mainSize / 2;
    final labelGap = AppLayout.scaled(context, 2);
    final labelSize = AppLayout.scaled(context, 12);
    // 公文入口的完整下缘包含文字；圆弧整体上移同等高度后，其完整下边距才与
    // 视频圆形入口的右边距一致。三个圆心仍使用同一虚拟圆心和标准等分角度。
    final arcOriginY = origin - labelGap - labelSize;
    const entries = <({SquarePostType postType, IconData icon})>[
      (postType: SquarePostType.document, icon: Icons.description_outlined),
      (postType: SquarePostType.article, icon: Icons.article_outlined),
      (postType: SquarePostType.video, icon: Icons.videocam_outlined),
    ];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        // 水平端点的标签允许使用主按钮下方既有安全空白，圆心无需为避让文字偏离圆弧。
        clipBehavior: Clip.none,
        children: [
          for (var index = 0; index < entries.length; index++)
            _item(
              context,
              postType: entries[index].postType,
              icon: entries[index].icon,
              // 标准四分之一圆弧按 0° / 45° / 90° 等分，两个相邻弦长必然相同。
              angleDegrees: 90 * index / (entries.length - 1),
              originX: origin,
              originY: arcOriginY,
              collapsedOrigin: origin,
              radius: radius,
              size: itemSize,
              labelGap: labelGap,
              labelSize: labelSize,
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: SizedBox(
              width: mainSize,
              height: mainSize,
              child: FloatingActionButton(
                key: const ValueKey('square-publish-main-button'),
                heroTag: 'square-publish-main',
                shape: const CircleBorder(),
                onPressed: widget.onToggle,
                tooltip: widget.expanded ? '收起发布菜单' : '发布',
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                child: AnimatedRotation(
                  turns: widget.expanded ? 0.125 : 0,
                  duration: _SquarePublishMenu._duration,
                  child: Icon(
                    widget.expanded ? Icons.close : Icons.edit_rounded,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required SquarePostType postType,
    required IconData icon,
    required double angleDegrees,
    required double originX,
    required double originY,
    required double collapsedOrigin,
    required double radius,
    required double size,
    required double labelGap,
    required double labelSize,
  }) {
    // 角度从主按钮正左方向向上递增；三个圆心到主按钮圆心的距离完全相同。
    final radians = angleDegrees * math.pi / 180;
    final left = originX - radius * math.cos(radians) - size / 2;
    final top = originY - radius * math.sin(radians) - size / 2;
    final collapsed = collapsedOrigin - size / 2;
    return AnimatedPositioned(
      duration: _SquarePublishMenu._duration,
      curve: Curves.easeOutCubic,
      left: widget.expanded ? left : collapsed,
      top: widget.expanded ? top : collapsed,
      child: Offstage(
        offstage: !_itemsVisible,
        child: ExcludeSemantics(
          excluding: !widget.expanded,
          child: IgnorePointer(
            ignoring: !widget.expanded,
            child: AnimatedScale(
              duration: _SquarePublishMenu._duration,
              scale: widget.expanded ? 1 : 0.72,
              child: AnimatedOpacity(
                duration: _SquarePublishMenu._duration,
                opacity: widget.expanded ? 1 : 0,
                child: Semantics(
                  button: true,
                  label: '发布${postType.label}',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        key: ValueKey('square-publish-${postType.workerValue}'),
                        color: AppTheme.surfaceCard,
                        elevation: 3,
                        shadowColor: Colors.black26,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => widget.onSelected(postType),
                          child: SizedBox(
                            width: size,
                            height: size,
                            child: Icon(
                              icon,
                              size: AppLayout.scaled(context, 22),
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: labelGap),
                      Text(
                        postType.label,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: labelSize,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
