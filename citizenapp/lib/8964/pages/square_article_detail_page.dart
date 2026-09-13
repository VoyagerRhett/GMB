import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/compose/compose_page.dart';
import 'package:citizenapp/8964/pages/square_post_detail_page.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_post_deletion_coordinator.dart';
import 'package:citizenapp/8964/widgets/square_media_carousel.dart';
import 'package:citizenapp/8964/widgets/square_media_grid.dart';
import 'package:citizenapp/8964/widgets/article_rich_text_view.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 文章详情：首图、标题、作者及保持图集/视频块关系的完整正文。
class SquareArticleDetailPage extends StatefulWidget {
  const SquareArticleDetailPage({
    super.key,
    required this.post,
    this.api,
    this.sessionProvider,
    this.deletionCoordinator,
  });

  final SquarePost post;
  final SquareApiClient? api;
  final SquareSessionProvider? sessionProvider;
  final SquarePostDeleteCoordinator? deletionCoordinator;

  @override
  State<SquareArticleDetailPage> createState() =>
      _SquareArticleDetailPageState();
}

enum _ArticleDetailAction { edit, delete }

class _SquareArticleDetailPageState extends State<SquareArticleDetailPage> {
  late final SquareApiClient _api;
  late final SquareSessionProvider _sessionProvider;
  late final SquarePostDeleteCoordinator _deletionCoordinator;
  late SquarePost _post;
  bool _loading = true;
  Object? _loadError;
  bool _deleting = false;
  bool _dependenciesReady = false;

  SquarePost get post => _post;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _api = widget.api ?? SquareApiClient();
    _deletionCoordinator = widget.deletionCoordinator ??
        SquarePostDeletionCoordinator(remoteDeletion: _api);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _sessionProvider =
        widget.sessionProvider ?? context.read<SquareSessionProvider>();
    _dependenciesReady = true;
    unawaited(_loadDetail());
  }

  Future<void> _loadDetail() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final session = await _sessionProvider.ensureSession();
      if (session == null) throw const SquareApiException('请先选择默认钱包账户');
      final detail = await _api.fetchPostDetail(
        session: session,
        summary: _post,
      );
      if (!mounted) return;
      setState(() {
        _post = detail;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = post.mediaItems;
    final cover = media.isNotEmpty ? media.first : null;
    final title = post.title?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('文章'),
        centerTitle: true,
        actions: [
          PopupMenuButton<_ArticleDetailAction>(
            enabled: !_deleting,
            onSelected: _handleAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ArticleDetailAction.edit,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('修改'),
                ),
              ),
              PopupMenuItem(
                value: _ArticleDetailAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('删除'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _DetailLoadError(error: _loadError!, onRetry: _loadDetail)
              : ListView(
                  children: [
                    if (cover != null && cover.url.isNotEmpty)
                      Image.network(
                        cover.url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    Padding(
                      padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null && title.isNotEmpty)
                            Text(
                              title,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: AppLayout.scaled(context, 22),
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          SizedBox(height: AppLayout.scaled(context, 8)),
                          Text(
                            post.author.title,
                            style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: AppLayout.scaled(context, 13),
                            ),
                          ),
                          SizedBox(height: AppLayout.scaled(context, 16)),
                          ..._buildBody(media),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// 每个规范段落先渲染富文本，再渲染该段落的可选媒体。
  List<Widget> _buildBody(List<SquareMediaItem> media) {
    final sections = post.contentSections;
    if (sections.isEmpty) return const <Widget>[];
    final widgets = <Widget>[];
    for (final section in sections) {
      widgets.add(ArticleRichTextView(delta: section.textDelta));
      final mediaIndices = section.galleryMediaIndices;
      if (mediaIndices != null) {
        final gallery = <SquareMediaItem>[];
        for (final mediaIndex in mediaIndices) {
          if (mediaIndex >= 0 && mediaIndex < media.length) {
            final item = media[mediaIndex];
            if (item.mediaKind == SquareMediaKind.image &&
                item.url.isNotEmpty) {
              gallery.add(item);
            }
          }
        }
        if (gallery.isNotEmpty) widgets.add(_bodyGallery(gallery));
      } else if (section.videoMediaIndex case final mediaIndex?) {
        if (mediaIndex >= 0 && mediaIndex < media.length) {
          widgets.add(_bodyVideo(media[mediaIndex]));
        }
      }
    }
    return widgets;
  }

  Widget _bodyGallery(List<SquareMediaItem> items) => Padding(
        padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(8)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: SquareMediaCarousel(
            children: [
              for (final item in items)
                Image.network(
                  item.url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: AppTheme.surfaceElevated,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _bodyVideo(SquareMediaItem item) => Padding(
        padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(8)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: SquareNetworkVideo(
              url: item.url,
              thumbnailUrl: item.coverUrl,
            ),
          ),
        ),
      );

  Future<void> _handleAction(_ArticleDetailAction action) async {
    switch (action) {
      case _ArticleDetailAction.edit:
        await _editArticle();
        break;
      case _ArticleDetailAction.delete:
        await _deleteArticle();
        break;
    }
  }

  Future<void> _editArticle() async {
    final replacement = await Navigator.of(context).push<SquarePost>(
      MaterialPageRoute<SquarePost>(
        builder: (_) => SquareComposePage(
          postType: SquarePostType.article,
          initialTitle: post.title,
          initialText: post.text,
          replacePostId: post.postId,
        ),
      ),
    );
    if (replacement == null || !mounted) return;
    Navigator.of(context).pop(SquarePostDetailResult(replacement: replacement));
  }

  Future<void> _deleteArticle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除文章'),
        content: const Text('删除后将清理 Cloudflare 中的正文和媒体。链上发布记录保持不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      final session = await _sessionProvider.ensureSession();
      if (session == null) {
        throw const SquareApiException('请先选择默认热钱包');
      }
      final authorCidNumber = post.author.cidNumber;
      if (authorCidNumber == null || authorCidNumber.isEmpty) {
        throw const SquareApiException('只能删除本人文章');
      }
      await _deletionCoordinator.delete(
        session: session,
        cidNumber: authorCidNumber,
        postId: post.postId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已删除'),
          backgroundColor: AppTheme.primaryDark,
        ),
      );
      Navigator.of(context).pop(const SquarePostDetailResult(deleted: true));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败：$error'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }
}

class _DetailLoadError extends StatelessWidget {
  const _DetailLoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('文章加载失败：$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
}
