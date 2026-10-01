import 'package:flutter/material.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 广场分类分段控件（推荐 / 关注 / 竞选）。
///
/// 青色主题圆角分段 pill：选中段=白底青字带图标，未选=灰字。图标语义与各分类原空态
/// 一致（推荐=罗盘、关注=人群、竞选=喇叭）。对外 API 与 [SquareFeedKind] 与旧版保持一致，
/// 仅替换视觉。
class SquareFeedTabs extends StatelessWidget {
  const SquareFeedTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    this.followingUnread = 0,
  });

  final SquareFeedKind selected;
  final ValueChanged<SquareFeedKind> onChanged;

  /// 关注子 tab 红点数（我未静音关注在关注游标之后的新帖数）；0=不显示。
  final int followingUnread;

  static IconData iconFor(SquareFeedKind kind) => switch (kind) {
        SquareFeedKind.recommended => Icons.explore_outlined,
        SquareFeedKind.following => Icons.people_alt_outlined,
        SquareFeedKind.campaign => Icons.campaign_outlined,
        SquareFeedKind.article => Icons.article_outlined,
        SquareFeedKind.videos => Icons.videocam_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppLayout.scaled(context, 4)),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(13)),
      ),
      child: Row(
        children: SquareFeedKind.values
            .map(
              (kind) => Expanded(
                child: _SquareFeedTab(
                  kind: kind,
                  selected: kind == selected,
                  unread:
                      kind == SquareFeedKind.following ? followingUnread : 0,
                  onTap: () => onChanged(kind),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _SquareFeedTab extends StatelessWidget {
  const _SquareFeedTab({
    required this.kind,
    required this.selected,
    required this.onTap,
    this.unread = 0,
  });

  final SquareFeedKind kind;
  final bool selected;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(vertical: AppLayout.scaled(context, 6)),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
          // 选中/未选都保留 1px 边框（未选透明），避免切换时因边框有无产生宽高抖动。
          border: Border.all(
            color:
                selected ? AppTheme.primary.withAlpha(40) : Colors.transparent,
          ),
        ),
        // 五段等宽：图标在上、文字在下的竖排，横排图标+文字在 320px 窄屏会溢出。
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: unread > 0,
              label: Text(
                unread > 99 ? '99+' : '$unread',
                style: TextStyle(fontSize: AppLayout.scaled(context, 9)),
              ),
              child: Icon(SquareFeedTabs.iconFor(kind),
                  size: AppLayout.scaled(context, 17), color: color),
            ),
            SizedBox(height: AppLayout.scaled(context, 3)),
            Text(
              kind.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 12),
                height: 1.0,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
