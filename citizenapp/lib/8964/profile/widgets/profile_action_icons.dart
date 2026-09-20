import 'package:flutter/material.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 头像行右上角的动作图标——**对主页主人的操作**，只在看**别人**主页时出现。
///
/// 通知 = 关注后收其发帖通知（红点+声音）、聊天 = 给该用户发消息、关注 = 关注/取关该用户。
/// 通知归属挂在关注关系上：关注即默认开通知，铃铛按用户静音/取消静音；未关注时点铃铛提示先关注。
/// 看自己主页时不显示任何图标（给自己发消息/关注自己无意义；编辑资料在右上 ⋮ 菜单）。
class ProfileActionIcons extends StatelessWidget {
  const ProfileActionIcons({
    super.key,
    required this.isSelf,
    required this.isFollowing,
    this.isNotifying = false,
    this.enabled = true,
    this.leading,
    this.onNotify,
    this.onChat,
    this.onToggleFollow,
  });

  final bool isSelf;
  final bool isFollowing;

  /// 是否已开启该用户的发帖通知（= 已关注且未静音）；铃铛据此高亮/实心。
  final bool isNotifying;

  /// false=置灰不可点（从广场头像以他人视角看自己时，给自己关注/私信/通知无意义）。
  final bool enabled;

  /// 可选的创作者订阅入口；有有效创作者计划才构建，固定在通知图标左侧。
  /// 入口只占本操作行的横向空间，不得改变主页资料区高度。
  final Widget? leading;

  /// 通知：开/关该用户发帖通知（须已关注）。
  final VoidCallback? onNotify;

  /// 聊天：给该用户发消息。
  final VoidCallback? onChat;

  /// 关注：关注/取关该用户。
  final VoidCallback? onToggleFollow;

  @override
  Widget build(BuildContext context) {
    // 自己的主页不显示这些操作。
    if (isSelf) return const SizedBox.shrink();

    final buttons = <Widget>[
      _CircleIcon(
        icon: isNotifying
            ? Icons.notifications_active
            : Icons.notifications_outlined,
        tooltip: isNotifying ? '已开启通知' : '通知',
        active: enabled && isNotifying,
        onTap: enabled ? onNotify : null,
      ),
      _CircleIcon(
        icon: Icons.chat_bubble_outline,
        tooltip: '发消息',
        onTap: enabled ? onChat : null,
      ),
      _CircleIcon(
        icon: isFollowing ? Icons.how_to_reg : Icons.person_add_alt,
        tooltip: isFollowing ? '已关注' : '关注',
        active: enabled && isFollowing,
        onTap: enabled ? onToggleFollow : null,
      ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?leading,
        for (final button in buttons)
          Padding(
            padding: EdgeInsets.only(left: AppLayout.scaled(context, 8)),
            child: button,
          ),
      ],
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    required this.icon,
    required this.tooltip,
    this.active = false,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;

  /// 激活态（如已关注）用品牌色描边与图标高亮。
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // onTap==null 视为禁用：图标与描边转灰，不可点。
    final disabled = onTap == null;
    final color = disabled
        ? AppTheme.textTertiary
        : (active ? AppTheme.primary : AppTheme.textSecondary);
    return Material(
      color: AppTheme.surfaceCard,
      shape: CircleBorder(
        side: BorderSide(
          color: disabled
              ? AppTheme.border
              : (active ? AppTheme.primary : AppTheme.border),
          width: active ? 1 : 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(AppLayout.scaled(context, 7)),
          child: Icon(
            icon,
            color: color,
            size: AppLayout.scaled(context, 20),
            semanticLabel: tooltip,
          ),
        ),
      ),
    );
  }
}
