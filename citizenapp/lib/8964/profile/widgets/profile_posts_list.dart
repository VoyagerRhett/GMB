import 'package:citizenapp/8964/services/square_post_store.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_local_post_presenter.dart';
import 'package:citizenapp/8964/widgets/square_article_card.dart';
import 'package:citizenapp/8964/widgets/square_post_card.dart';
import 'package:citizenapp/8964/widgets/square_media_grid.dart';
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
    this.onRefresh,
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
  final Future<void> Function()? onRefresh;
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
    SquarePostStore.revision.addListener(_onLocalPostsChanged);
    _requestSession = widget.session;
    unawaited(_loadFirst());
  }

  void _onLocalPostsChanged() {
    if (mounted &&
        widget.isSelf &&
        SquarePostStore.revision.value?.cidNumber == widget.cidNumber) {
      unawaited(_loadFirst());
    }
  }

  @override
  void dispose() {
    SquarePostStore.revision.removeListener(_onLocalPostsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProfilePostsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contractChanged =
        oldWidget.cidNumber != widget.cidNumber ||
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
    // 身份或分类变化不能沿用旧列表；会话变化不影响本人的本地内容。
    if (contractChanged) _posts.clear();
    if (!widget.isSelf || contractChanged) {
      unawaited(_loadFirst(reloadLocal: contractChanged));
    }
  }

  Future<void> _loadFirst({bool reloadLocal = true}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _failedFirst = false;
      _sessionUnavailable = false;
      _cursor = null;
      _done = false;
      if (reloadLocal && !widget.isSelf) {
        _posts.clear();
      }
    });
    var localHasContent = _posts.isNotEmpty;
    if (widget.isSelf && reloadLocal) {
      try {
        final localCopies = await widget.api.fetchLocalPublishedPosts(
          widget.cidNumber,
        );
        final presentations = localCopies
            .where((item) => item.cidNumber == widget.cidNumber)
            .map(_localPresenter.present)
            .where(_matchesLocalFilters)
            .toList(growable: false);
        localHasContent = presentations.isNotEmpty;
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _posts
            ..clear()
            ..addAll(presentations.map((item) => item.post));
        });
      } catch (_) {
        if (mounted && generation == _loadGeneration) {
          setState(() => _failedFirst = true);
          if (_posts.isNotEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('本地读取失败，已保留当前内容')));
          }
        }
      }
    }

    if (widget.isSelf) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _done = true;
        });
      }
      return;
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
    if (widget.isSelf ||
        _loading ||
        _done ||
        _cursor == null ||
        session == null) {
      return;
    }
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
        post.mediaItems.any((item) => item.mediaKind == mediaKind);
  }

  /// 他人主页分页合并；本人列表只读取本地持久副本。
  void _mergeRemotePosts(List<SquarePost> remotePosts) {
    final byPostId = <String, SquarePost>{
      for (final post in _posts) post.postId: post,
    };
    for (final remote in remotePosts) {
      byPostId[remote.postId] = remote;
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
      onRefresh: () async {
        if (widget.onRefresh != null) {
          // 上层提交后通过revision重建内容，避免同一次下拉再读一轮。
          await widget.onRefresh!();
        } else if (mounted) {
          await _loadFirst();
        }
      },
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
    if (_failedFirst && _posts.isEmpty) {
      return [_message('加载失败，下拉重试')];
    }
    if (_sessionUnavailable && _posts.isEmpty) {
      return [_message(widget.sessionUnavailableMessage ?? '公民服务暂时不可用，请稍后重试')];
    }
    if (widget.mediaKind != null) {
      return _mediaSlivers();
    }
    if (_posts.isEmpty) {
      return [_message(widget.isSelf ? '本地尚未保存此类内容，下拉刷新' : widget.emptyLabel)];
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
            final avatarUrl = avatarKey == null
                ? null
                : widget.api.mediaUrl(avatarKey);
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
    if (entries.isEmpty) {
      return [_message(widget.emptyLabel)];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: AppLayout.scaledValue(6),
            mainAxisSpacing: AppLayout.scaledValue(6),
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final entry = entries[index];
            return _MediaTile(
              media: entry.media,
              onTap: () => widget.onOpenPost?.call(entry.post),
            );
          }, childCount: entries.length),
        ),
      ),
      _footer(),
    ];
  }

  Widget _footer() {
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }

  Widget _message(String text) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Text(text, style: const TextStyle(color: AppTheme.textTertiary)),
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
    return GestureDetector(
      onTap: onTap,
      child: SquareMediaTile(
        item: media,
        radius: BorderRadius.circular(AppTheme.radiusSm),
      ),
    );
  }
}
