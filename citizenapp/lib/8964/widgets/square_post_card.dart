import 'package:flutter/material.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/widgets/square_media_grid.dart';
import 'package:citizenapp/8964/widgets/square_post_actions.dart';
import 'package:citizenapp/8964/widgets/square_post_header.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 动态流与详情页的显示模式。
enum SquarePostCardDisplayMode { feed, detail }

/// 广场公文/视频卡（含竞选变体）。
///
/// 公文固定“正文 → 照片”，视频固定“封面 → 配文”。Feed 中公文正文最多 3 行、
/// 视频配文最多 2 行，真实溢出才显示展开入口；详情页显示完整文字。
class SquarePostCard extends StatelessWidget {
  const SquarePostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onAuthorTap,
    this.avatarUrl,
    this.avatarHeaders,
    this.displayMode = SquarePostCardDisplayMode.feed,
  });

  final SquarePost post;
  final VoidCallback? onTap;

  /// 点击作者头像/名进入其用户主页。
  final VoidCallback? onAuthorTap;

  /// 作者真头像地址与鉴权头（由页面据 avatarObjectKey + session 生成）。
  final String? avatarUrl;
  final Map<String, String>? avatarHeaders;
  final SquarePostCardDisplayMode displayMode;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(AppLayout.scaled(context, 14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SquarePostHeader(
                post: post,
                onAuthorTap: onAuthorTap,
                avatarUrl: avatarUrl,
                avatarHeaders: avatarHeaders,
              ),
              _buildBody(context),
              SizedBox(height: AppLayout.scaled(context, 12)),
              const SquarePostActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final media = post.mediaItems;
    final caption = post.text.trim();
    final isVideo = post.postType == SquarePostType.video;

    if (media.isEmpty) {
      if (caption.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(top: AppLayout.scaledValue(12)),
        child: _caption(context, caption, isVideo: isVideo),
      );
    }

    final mediaWidget = SquareMediaGrid(
      mediaItems: media,
      enableVideoPlayback: displayMode == SquarePostCardDisplayMode.detail,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isVideo) ...[
          SizedBox(height: AppLayout.scaledValue(12)),
          mediaWidget,
          if (caption.isNotEmpty) ...[
            SizedBox(height: AppLayout.scaledValue(12)),
            _caption(context, caption, isVideo: true),
          ],
        ] else ...[
          if (caption.isNotEmpty) ...[
            SizedBox(height: AppLayout.scaledValue(12)),
            _caption(context, caption, isVideo: false),
          ],
          SizedBox(height: AppLayout.scaledValue(12)),
          mediaWidget,
        ],
      ],
    );
  }

  Widget _caption(BuildContext context, String text, {required bool isVideo}) {
    final style = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: AppLayout.scaledValue(15),
      height: 1.45,
    );
    if (displayMode == SquarePostCardDisplayMode.detail) {
      return Text(text, style: style);
    }
    return _ExpandableFeedText(
      key: ValueKey('${post.postType.workerValue}-feed-text'),
      text: text,
      style: style,
      maxLines: isVideo ? 2 : 3,
      expandLabel: isVideo ? '展开' : '展开全文',
      onExpand: onTap,
    );
  }
}

/// 按当前真实宽度、系统字体倍率和字体样式判断文字是否溢出，禁止用字符数猜测。
class _ExpandableFeedText extends StatelessWidget {
  const _ExpandableFeedText({
    super.key,
    required this.text,
    required this.style,
    required this.maxLines,
    required this.expandLabel,
    this.onExpand,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final String expandLabel;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflowed = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              key: ValueKey('$expandLabel-text'),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            if (overflowed)
              Semantics(
                button: true,
                label: expandLabel,
                child: InkWell(
                  key: ValueKey('$expandLabel-action'),
                  onTap: onExpand,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: AppLayout.scaledValue(4),
                      right: AppLayout.scaledValue(8),
                      bottom: AppLayout.scaledValue(4),
                    ),
                    child: Text(
                      expandLabel,
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: AppLayout.scaledValue(14),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
