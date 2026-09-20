import 'dart:async';

import 'package:flutter/material.dart';

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_local_post_presenter.dart';
import 'package:citizenapp/8964/widgets/square_article_card.dart';
import 'package:citizenapp/8964/widgets/square_post_card.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 单个分类 Tab 的内容：按作者分页拉帖，游标触底加载。
///
/// [mediaKind] 为空 → 帖子卡列表；视频页按 [postType] 在 Worker
/// 分页前过滤，避免客户端分页后筛选造成漏项和错误空态。
class ProfilePostsTab extends StatefulWidget {
  const ProfilePostsTab({
    super.key,
    required this.cidNumber,
    required this.api,
    required this.emptyLabel,
    required this.session,
    required this.sessionReady,
    this.sessionUnavailableMessage,
    required this.isSelf,
    this.onSessionExpired,
    this.category,
    this.postType,
    this.mediaKind,
    this.onOpenPost,
  });

  /// 作者身份主键 cid_number（按 cid 分页拉该身份的帖子）。
  final String cidNumber;
  final CitizenProfileApi api;
  final String emptyLabel;

  /// 可选浏览会话：只用于远端请求和受保护媒体，不是本人本地副本的读取凭证。
  ///
  /// 本人身份已经由上层以永久 `cid_number` 判定；断网或 Worker 不可用时会话可能为空，
  /// 此时仍必须允许本人读取本机已校验的发布副本。
  final SquareSession? session;

  /// 上层是否已经完成首次会话解析。false 表示仍在握手，禁止拿 null 抢跑远端请求；
  /// true + null 表示本次确实没有可用钱包会话。
  final bool sessionReady;

  /// 上层解析出的真实失败原因；为空只用于极短的未决窗口，不推断本地钱包事实。
  final String? sessionUnavailableMessage;

  /// Worker 明确返回 401 时由上层清理缓存并重新握手；每个请求最多调用一次。
  final Future<SquareSession?> Function()? onSessionExpired;
  final bool isSelf;
  final SquarePostCategory? category;
  final SquarePostType? postType;
  final SquareMediaKind? mediaKind;
  final void Function(SquarePost post)? onOpenPost;

  @override
  State<ProfilePostsTab> createState() => _ProfilePostsTabState();
}

class _ProfilePostsTabState extends State<ProfilePostsTab> {
  static const int _pageSize = 20;
  static const SquareLocalPostPresenter _localPresenter =
      SquareLocalPostPresenter();

  final List<SquarePost> _posts = [];
  final Map<String, Set<SquareMediaKind>> _unavailableMediaKindsByPostId = {};
  int? _cursor;
  bool _loading = false;
  bool _done = false;
  bool _failedFirst = false;
  bool _sessionUnavailable = false;
  int _loadGeneration = 0;
  SquareSession? _requestSession;

  @override
  void initState() {
    super.initState();
    _requestSession = widget.session;
    unawaited(_loadFirst());
  }

  @override
  void didUpdateWidget(covariant ProfilePostsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contractChanged = oldWidget.cidNumber != widget.cidNumber ||
        oldWidget.api != widget.api ||
        oldWidget.category != widget.category ||
        oldWidget.postType != widget.postType ||
        oldWidget.mediaKind != widget.mediaKind ||
        oldWidget.isSelf != widget.isSelf;
    final incomingSessionChanged =
        _sessionKey(widget.session) != _sessionKey(_requestSession) ||
            oldWidget.sessionReady != widget.sessionReady;
    if (!contractChanged && !incomingSessionChanged) return;
    _requestSession = widget.session;
    // 只有作者/过滤契约变化才重读本地副本；单纯 Session 就绪或刷新只补远端，避免
    // 首次进入时重复读取并闪空已经展示的本人本地内容。
    unawaited(_loadFirst(reloadLocal: contractChanged));
  }

  Future<void> _loadFirst({bool reloadLocal = true}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _failedFirst = false;
      _sessionUnavailable = false;
      _cursor = null;
      _done = false;
      if (reloadLocal) {
        _posts.clear();
        _unavailableMediaKindsByPostId.clear();
      }
    });
    var localHasContent = _posts.isNotEmpty;
    if (widget.isSelf && reloadLocal) {
      try {
        final localCopies =
            await widget.api.fetchLocalPublishedPosts(widget.cidNumber);
        final presentations = localCopies
            .map(_localPresenter.present)
            .where(_matchesLocalFilters)
            .toList(growable: false);
        localHasContent = presentations.isNotEmpty;
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _posts
            ..clear()
            ..addAll(presentations.map((item) => item.post));
          _unavailableMediaKindsByPostId
            ..clear()
            ..addEntries(
              presentations
                  .where((item) => item.unavailableMediaKinds.isNotEmpty)
                  .map(
                    (item) => MapEntry(
                      item.post.postId,
                      item.unavailableMediaKinds,
                    ),
                  ),
            );
        });
      } on Exception {
        // 本地副本损坏时 fail-closed，但仍继续读取 Worker，不让单机磁盘故障遮住远端内容。
      }
    }

    final session = _requestSession;
    if (!widget.sessionReady || session == null) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        // 本人已有本地副本时直接展示；其余情况在握手完成前保持加载态。
        _loading = !widget.sessionReady && _posts.isEmpty;
        _sessionUnavailable = widget.sessionReady && session == null;
      });
      return;
    }

    try {
      final page = await _fetchRemotePage(
        generation: generation,
        session: session,
      );
      if (page == null || !mounted || generation != _loadGeneration) return;
      setState(() {
        _mergeRemotePosts(page.posts);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
        _loading = false;
      });
    } on Exception {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _failedFirst = _posts.isEmpty && !localHasContent;
      });
    }
  }

  Future<void> _loadMore() async {
    final session = _requestSession;
    if (_loading || _done || _cursor == null || session == null) return;
    final generation = _loadGeneration;
    setState(() => _loading = true);
    try {
      final page = await _fetchRemotePage(
        generation: generation,
        session: session,
        cursor: _cursor,
      );
      if (page == null || !mounted || generation != _loadGeneration) return;
      setState(() {
        _mergeRemotePosts(page.posts);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
        _loading = false;
      });
    } on Exception {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loading = false);
    }
  }

  /// 按当前 Tab 契约拉一页；401 只委托上层刷新一次 Session，第二次失败直接上抛。
  Future<({List<SquarePost> posts, int? nextCursor})?> _fetchRemotePage({
    required int generation,
    required SquareSession session,
    int? cursor,
  }) async {
    Future<({List<SquarePost> posts, int? nextCursor})> request(
      SquareSession activeSession,
    ) {
      return widget.api.fetchAuthorPosts(
        widget.cidNumber,
        category: widget.category,
        postType: widget.postType,
        limit: _pageSize,
        cursor: cursor,
        session: activeSession,
      );
    }

    try {
      return await request(session);
    } on SquareApiException catch (error) {
      if (!mounted || generation != _loadGeneration) return null;
      final refresh = widget.onSessionExpired;
      if (error.statusCode != 401 || refresh == null) rethrow;
      final refreshed = await refresh();
      if (!mounted || generation != _loadGeneration) return null;
      if (refreshed == null) rethrow;
      _requestSession = refreshed;
      return request(refreshed);
    }
  }

  String? _sessionKey(SquareSession? session) => session == null
      ? null
      : '${session.accountId}:${session.cidNumber}:${session.bindingRevision}:${session.sessionToken}';

  bool _matchesLocalFilters(SquareLocalPostPresentation presentation) {
    final post = presentation.post;
    if (widget.category != null && post.postCategory != widget.category) {
      return false;
    }
    if (widget.postType != null && post.postType != widget.postType) {
      return false;
    }
    final mediaKind = widget.mediaKind;
    return mediaKind == null ||
        presentation.unavailableMediaKinds.contains(mediaKind);
  }

  /// 远端资料与媒体元数据优先；远端未返回的本地正文继续保留。
  ///
  /// 同一 post_id 的本地媒体声明只在远端缺少对应媒体时保留“云端已清理”标记，
  /// 不会构造第二套媒体对象或覆盖 Worker 返回的作者资料。
  void _mergeRemotePosts(List<SquarePost> remotePosts) {
    final byPostId = <String, SquarePost>{
      for (final post in _posts) post.postId: post,
    };
    for (final remote in remotePosts) {
      byPostId[remote.postId] = remote;
      final unavailable = _unavailableMediaKindsByPostId[remote.postId];
      if (unavailable != null) {
        final remaining = unavailable.difference(
          remote.mediaItems.map((media) => media.mediaKind).toSet(),
        );
        if (remaining.isEmpty) {
          _unavailableMediaKindsByPostId.remove(remote.postId);
        } else {
          _unavailableMediaKindsByPostId[remote.postId] =
              Set<SquareMediaKind>.unmodifiable(remaining);
        }
      }
    }
    final merged = byPostId.values.toList()
      ..sort((left, right) {
        final byCreatedAt = right.createdAt.compareTo(left.createdAt);
        if (byCreatedAt != 0) return byCreatedAt;
        return right.postId.compareTo(left.postId);
      });
    _posts
      ..clear()
      ..addAll(merged);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 400) {
      _loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          key: PageStorageKey<String>(
            '${widget.category?.name ?? 'all'}:'
            '${widget.postType?.name ?? 'all'}:'
            '${widget.mediaKind?.name ?? 'posts'}',
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (_loading)
              SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  key: const ValueKey('profile-posts-load-progress'),
                  minHeight: AppLayout.scaled(context, 2),
                ),
              ),
            ..._contentSlivers(),
          ],
        ),
      ),
    );
  }

  List<Widget> _contentSlivers() {
    if (_loading && _posts.isEmpty) {
      return [_message('正在读取内容')];
    }
    if (_failedFirst) {
      return [_message('加载失败，下拉重试')];
    }
    if (_sessionUnavailable && _posts.isEmpty) {
      return [
        _message(widget.sessionUnavailableMessage ?? '公民服务暂时不可用，请稍后重试'),
      ];
    }
    if (widget.mediaKind != null) {
      return _mediaSlivers();
    }
    if (_posts.isEmpty) {
      return [_message(widget.emptyLabel)];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        sliver: SliverList.separated(
          itemCount: _posts.length,
          separatorBuilder: (_, _) =>
              SizedBox(height: AppLayout.scaledValue(10)),
          itemBuilder: (context, index) {
            final post = _posts[index];
            final avatarKey = post.author.avatarObjectKey;
            final avatarUrl =
                avatarKey == null ? null : widget.api.mediaUrl(avatarKey);
            final session = widget.session;
            final avatarHeaders = session == null
                ? null
                : <String, String>{
                    'authorization': 'Bearer ${session.sessionToken}',
                  };
            if (widget.postType == SquarePostType.article) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SquareArticleCard(
                    post: post,
                    onTap: () => widget.onOpenPost?.call(post),
                    onAuthorTap: () => widget.onOpenPost?.call(post),
                    avatarUrl: avatarUrl,
                    avatarHeaders: avatarHeaders,
                  ),
                  if (_hasUnavailableMedia(post.postId))
                    const _UnavailableMediaNotice(),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SquarePostCard(
                  post: post,
                  onTap: () => widget.onOpenPost?.call(post),
                  onAuthorTap: () => widget.onOpenPost?.call(post),
                  avatarUrl: avatarUrl,
                  avatarHeaders: avatarHeaders,
                ),
                if (_hasUnavailableMedia(post.postId))
                  const _UnavailableMediaNotice(),
              ],
            );
          },
        ),
      ),
      _footer(),
    ];
  }

  List<Widget> _mediaSlivers() {
    final entries = <({SquarePost post, SquareMediaItem media})>[];
    for (final post in _posts) {
      for (final media in post.mediaItems) {
        if (media.mediaKind == widget.mediaKind) {
          entries.add((post: post, media: media));
        }
      }
    }
    final unavailable = _posts.any(
      (post) =>
          _unavailableMediaKindsByPostId[post.postId]
              ?.contains(widget.mediaKind) ??
          false,
    );
    if (entries.isEmpty && unavailable) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: _UnavailableMediaNotice()),
        ),
      ];
    }
    if (entries.isEmpty) {
      return [_message(widget.emptyLabel)];
    }
    return [
      if (unavailable)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _UnavailableMediaNotice(),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: AppLayout.scaledValue(6),
            mainAxisSpacing: AppLayout.scaledValue(6),
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final entry = entries[index];
              return _MediaTile(
                media: entry.media,
                onTap: () => widget.onOpenPost?.call(entry.post),
              );
            },
            childCount: entries.length,
          ),
        ),
      ),
      _footer(),
    ];
  }

  bool _hasUnavailableMedia(String postId) =>
      _unavailableMediaKindsByPostId[postId]?.isNotEmpty ?? false;

  Widget _footer() {
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  Widget _message(String text) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: AppTheme.textTertiary),
        ),
      ),
    );
  }
}

class _UnavailableMediaNotice extends StatelessWidget {
  const _UnavailableMediaNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 12),
          vertical: AppLayout.scaled(context, 10)),
      child: Text(
        '媒体已从云端清理，本机仅保留正文',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.textTertiary,
          fontSize: AppLayout.scaled(context, 12),
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media, this.onTap});

  final SquareMediaItem media;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isVideo = media.mediaKind == SquareMediaKind.video;
    final imageUrl = isVideo ? (media.coverUrl ?? '') : media.url;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppTheme.surfaceElevated),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fallbackIcon(isVideo),
                )
              else
                _fallbackIcon(isVideo),
              if (isVideo)
                Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      size: AppLayout.scaled(context, 34),
                      color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon(bool isVideo) {
    return Center(
      child: Icon(
        isVideo ? Icons.play_circle_fill_rounded : Icons.image_rounded,
        size: AppLayout.scaledValue(34),
        color: AppTheme.textTertiary,
      ),
    );
  }
}
