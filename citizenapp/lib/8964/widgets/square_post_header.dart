import 'package:flutter/material.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/profile/widgets/profile_avatar.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 广场卡片统一作者头部：方形圆角头像 + 右下角扇贝身份勋章、昵称、
/// 竞选药丸（仅竞选公民）、竞选岗位/时间、右上角更多按钮。
///
/// 图片/视频/文章及其竞选变体共用同一头部，保证身份表达一致。
class SquarePostHeader extends StatefulWidget {
  const SquarePostHeader({
    super.key,
    required this.post,
    this.onAuthorTap,
    this.onMore,
    this.avatarUrl,
    this.avatarHeaders,
  });

  final SquarePost post;

  /// 点击头像/昵称区进入作者主页。
  final VoidCallback? onAuthorTap;

  /// 右上角更多菜单；为 null 时按钮仍展示但不响应。
  final VoidCallback? onMore;

  /// 作者头像已解析的可读地址（由页面据 avatarObjectKey + session 生成）；
  /// 用户已设置但缺失时保留占位，只有从未设置才显示稳定默认照片。
  final String? avatarUrl;

  /// 头像 `Image.network` 的鉴权头（钱包 session Bearer）。
  final Map<String, String>? avatarHeaders;

  @override
  State<SquarePostHeader> createState() => _SquarePostHeaderState();
}

class _SquarePostHeaderState extends State<SquarePostHeader> {
  CitizenProfile? _profile;
  CitizenProfileMediaSnapshot _media = const CitizenProfileMediaSnapshot();
  int _generation = 0;
  SquarePost get post => widget.post;
  bool get _isCampaign => post.postCategory == SquarePostCategory.campaign;

  @override
  void initState() {
    super.initState();
    CitizenProfileCache.revision.addListener(_changed);
    _readLocal();
  }

  void _changed() {
    if (CitizenProfileCache.revision.value?.cidNumber == post.author.cidNumber) {
      _readLocal();
    }
  }

  @override
  void didUpdateWidget(covariant SquarePostHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.isLocal != post.isLocal ||
        oldWidget.post.author.cidNumber != post.author.cidNumber) {
      _profile = null;
      _media = const CitizenProfileMediaSnapshot();
      _readLocal();
    }
  }

  /// 本人帖子作者资料复用UserIsar入口；头部更新不获取会话或远端图片。
  Future<void> _readLocal() async {
    final generation = ++_generation;
    final cid = post.author.cidNumber;
    if (!post.isLocal || cid == null) return;
    try {
      final profile = await const CitizenProfileCache().read(cid);
      if (profile?.cidNumber != cid) return;
      final media = await CitizenProfileMediaCache().read(profile!);
      if (mounted && generation == _generation) {
        setState(() {
          _profile = profile;
          _media = media;
        });
      }
    } catch (_) {
      /* 保留既有显示，不下载或写入第二套资料。 */
    }
  }

  @override
  void dispose() {
    _generation++;
    CitizenProfileCache.revision.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final author = post.author;
    return Row(
      // start 对齐让更多按钮贴近卡片上边缘。
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: widget.onAuthorTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                ProfileAvatar(
                  // 头像稳定种子按身份主键 cid_number（与资料页一致，换绑不变）；
                  // cid 缺失（本地草稿等）回落当前账户。
                  seed: author.cidNumber ?? author.accountId,
                  size: AppLayout.scaled(context, 40),
                  imagePath: _media.avatarPath,
                  imageUrl: post.isLocal ? null : widget.avatarUrl,
                  imageHeaders: widget.avatarHeaders,
                  userImageSet:
                      (_profile?.avatarObjectKey ?? author.avatarObjectKey)
                          ?.isNotEmpty ==
                      true,
                  identityLevel:
                      _profile?.identityLevel ?? author.identityLevel,
                  membershipLevel:
                      _profile?.membershipLevel ?? author.membershipLevel,
                  membershipActive:
                      _profile?.membershipActive ?? author.membershipActive,
                  borderRadius: 12,
                ),
                SizedBox(width: AppLayout.scaled(context, 11)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _profile?.displayName.trim().isNotEmpty == true
                                  ? _profile!.displayName
                                  : author.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: AppLayout.scaled(context, 14),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // 药丸只有竞选公民显示；投票/访客靠头像勋章表达。
                          if (_isCampaign) ...[
                            SizedBox(width: AppLayout.scaled(context, 6)),
                            const _CampaignPill(),
                          ],
                        ],
                      ),
                      SizedBox(height: AppLayout.scaled(context, 2)),
                      Text(
                        _subtitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: AppLayout.scaled(context, 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: widget.onMore,
          icon: Icon(
            Icons.more_horiz,
            size: AppLayout.scaled(context, 20),
            color: AppTheme.textTertiary,
          ),
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: AppLayout.scaled(context, 28),
            minHeight: AppLayout.scaled(context, 20),
          ),
          visualDensity: VisualDensity.compact,
          tooltip: '更多',
        ),
      ],
    );
  }

  /// 竞选岗位只有竞选公民且有值时展示，否则只显示时间。
  String _subtitle() {
    final time = _formatCreatedAt(post.createdAt);
    final position = post.campaignPosition?.trim();
    if (_isCampaign && position != null && position.isNotEmpty) {
      return '$position · $time';
    }
    return time;
  }

  String _formatCreatedAt(DateTime createdAt) {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
  }
}

class _CampaignPill extends StatelessWidget {
  const _CampaignPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppLayout.scaled(context, 7),
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: AppTheme.danger.withAlpha(0x1F),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(20)),
      ),
      child: Text(
        '竞选',
        style: TextStyle(
          color: AppTheme.danger,
          fontSize: AppLayout.scaled(context, 11),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
