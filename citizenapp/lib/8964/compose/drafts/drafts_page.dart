import 'dart:io';

import 'package:flutter/material.dart';

import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_store.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 草稿箱：全类型缩略卡，新→旧；右滑删除；点击返回该草稿供发布页恢复。
class DraftsPage extends StatefulWidget {
  const DraftsPage({
    super.key,
    required this.cidNumber,
    required this.postType,
    this.store,
  });

  final String cidNumber;
  final SquarePostType postType;
  final SquareComposeDraftRepository? store;

  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  late final SquareComposeDraftRepository _store;
  late Future<List<SquareComposeDraft>> _future;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? SquareComposeDraftStore.instance;
    _future = _loadDrafts();
  }

  Future<List<SquareComposeDraft>> _loadDrafts() =>
      _store.list(widget.cidNumber).then(
            (drafts) => drafts
                .where((draft) => draft.postType == widget.postType)
                .toList(growable: false),
          );

  void _reloadAfterDelete() {
    if (!mounted) return;
    setState(() {
      _future = _loadDrafts();
    });
  }

  Future<bool?> _confirmDelete(SquareComposeDraft draft) async {
    try {
      await _store.delete(widget.cidNumber, draft.draftId);
      _reloadAfterDelete();
      return true;
    } on SquareComposeDraftStoreException {
      _reloadAfterDelete();
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('草稿已删除，但本地媒体仍待清理'),
          action: SnackBarAction(
            label: '重试清理',
            onPressed: _retryFileCleanup,
          ),
        ),
      );
      // 数据库草稿事实已经删除；只保留可重试文件清理事实，列表应同步移除该卡片。
      return true;
    } on Object {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('草稿删除失败，请重试')),
      );
      return false;
    }
  }

  void _retryFileCleanup() {
    _store.retryPendingFileCleanup(cidNumber: widget.cidNumber).then<void>((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地媒体清理完成')),
      );
    }, onError: (Object _) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地媒体仍未清理，请稍后重试')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('草稿箱'), centerTitle: true),
      body: FutureBuilder<List<SquareComposeDraft>>(
        future: _future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState != ConnectionState.done;
          final drafts = snapshot.data ?? const <SquareComposeDraft>[];
          final Widget content;
          if (loading && drafts.isEmpty) {
            content = const Center(
              child: Text(
                '正在读取本地草稿',
                style: TextStyle(color: AppTheme.textTertiary),
              ),
            );
          } else if (snapshot.hasError) {
            content = const Center(
              child: Text(
                '草稿读取失败，请返回重试',
                style: TextStyle(color: AppTheme.textTertiary),
              ),
            );
          } else if (drafts.isEmpty) {
            content = const Center(
              child: Text(
                '还没有草稿',
                style: TextStyle(color: AppTheme.textTertiary),
              ),
            );
          } else {
            content = ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: drafts.length,
              separatorBuilder: (_, _) =>
                  SizedBox(height: AppLayout.scaled(context, 10)),
              itemBuilder: (context, index) {
                final draft = drafts[index];
                return Dismissible(
                  key: ValueKey(draft.draftId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding:
                        EdgeInsets.only(right: AppLayout.scaled(context, 20)),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius:
                          BorderRadius.circular(AppLayout.scaledValue(12)),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  confirmDismiss: (_) => _confirmDelete(draft),
                  child: _DraftCard(
                    draft: draft,
                    onTap: () => Navigator.of(context).pop(draft),
                  ),
                );
              },
            );
          }
          // 草稿是本地内容，页面结构立即显示；磁盘读取只占顶部细进度，不替换整页。
          return Stack(
            children: [
              Positioned.fill(child: content),
              if (loading)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    key: const ValueKey('drafts-load-progress'),
                    minHeight: AppLayout.scaled(context, 2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.draft, required this.onTap});

  final SquareComposeDraft draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
      child: Container(
        padding: EdgeInsets.all(AppLayout.scaled(context, 10)),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        ),
        child: Row(
          children: [
            _Thumb(draft: draft),
            SizedBox(width: AppLayout.scaled(context, 10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _TypeChip(label: draft.typeLabel),
                      const Spacer(),
                      Text(_relativeTime(draft.updatedAtMillis),
                          style: TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: AppLayout.scaled(context, 11))),
                    ],
                  ),
                  SizedBox(height: AppLayout.scaled(context, 4)),
                  Text(
                    draft.summary.isEmpty ? '（无正文）' : draft.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: AppLayout.scaled(context, 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _relativeTime(int millis) {
    final diff =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.draft});

  final SquareComposeDraft draft;

  @override
  Widget build(BuildContext context) {
    final media = draft.media.isNotEmpty ? draft.media.first : null;
    final isVideo = media?.mediaKind == SquareMediaKind.video;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
      child: SizedBox(
        width: AppLayout.scaled(context, 48),
        height: AppLayout.scaled(context, 48),
        child: (media != null && !isVideo && File(media.path).existsSync())
            ? Image.file(File(media.path), fit: BoxFit.cover)
            : ColoredBox(
                color: AppTheme.surfaceElevated,
                child: Icon(
                  isVideo
                      ? Icons.play_circle_fill_rounded
                      : draft.isArticle
                          ? Icons.article_outlined
                          : Icons.image_outlined,
                  color: AppTheme.textTertiary,
                ),
              ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const color = AppTheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 7), vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(0x1F),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(20)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: AppLayout.scaled(context, 10),
              fontWeight: FontWeight.w600)),
    );
  }
}
