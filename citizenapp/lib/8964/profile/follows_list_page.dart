import 'dart:async';

import 'package:flutter/material.dart';

import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/profile/user_profile_page.dart';
import 'package:citizenapp/8964/profile/widgets/profile_avatar.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

enum FollowsType {
  following('关注', 'following'),
  followers('关注者', 'followers'),
  mutualFollowing('互关', 'mutual_following');

  const FollowsType(this.label, this.workerValue);

  final String label;
  final String workerValue;
}

/// 关注、关注者和互关列表页。列表项为身份主键 cid_number；缺少公开资料时仍使用与主页
/// 一致的稳定默认昵称和头像，身份号显示在副标题，点击进入唯一用户主页。
class FollowsListPage extends StatefulWidget {
  const FollowsListPage({
    super.key,
    required this.cidNumber,
    required this.type,
    required this.session,
    this.api,
  });

  /// 被查看列表的所有者身份主键 cid_number（三类关系均按 cid 拉取）。
  final String cidNumber;
  final FollowsType type;
  final SquareSession session;
  final CitizenProfileApi? api;

  @override
  State<FollowsListPage> createState() => _FollowsListPageState();
}

class _FollowsListPageState extends State<FollowsListPage> {
  late final CitizenProfileApi _api;
  final List<SquareFollowEntry> _entries = [];
  final Map<String, CitizenProfile> _profiles = <String, CitizenProfile>{};
  int? _cursor;
  bool _loading = false;
  bool _done = false;
  bool _failedFirst = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? CitizenProfileApi();
    MembershipRevision.instance.listenable.addListener(_onMembershipChanged);
    _loadFirst();
  }

  @override
  void dispose() {
    MembershipRevision.instance.listenable.removeListener(_onMembershipChanged);
    super.dispose();
  }

  /// 当前列表可见 CID 的会员镜像变化时只重取该行公开资料。
  void _onMembershipChanged() {
    final event = MembershipRevision.instance.listenable.value;
    if (!mounted || event == null) return;
    final matching = _entries
        .where((entry) => entry.cidNumber == event.cidNumber)
        .toList(growable: false);
    if (matching.isEmpty) return;
    _profiles.remove(event.cidNumber);
    unawaited(_loadProfiles(matching));
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _failedFirst = false;
    });
    try {
      final page = await _api.fetchFollows(
        widget.cidNumber,
        type: widget.type.workerValue,
        limit: 20,
        session: widget.session,
      );
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(page.entries);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
        _loading = false;
      });
      unawaited(_loadProfiles(page.entries));
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failedFirst = _entries.isEmpty;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _done || _cursor == null) return;
    setState(() => _loading = true);
    try {
      final page = await _api.fetchFollows(
        widget.cidNumber,
        type: widget.type.workerValue,
        limit: 20,
        cursor: _cursor,
        session: widget.session,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        _cursor = page.nextCursor;
        _done = page.nextCursor == null;
        _loading = false;
      });
      unawaited(_loadProfiles(page.entries));
    } on Exception {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 300) {
      _loadMore();
    }
    return false;
  }

  /// 关注关系接口只返回身份主键 cid_number；公开资料按当前分页并行补齐（按 cid 拉、
  /// 按 cid 去重）。单个资料失败时保留稳定本地默认展示，不阻塞列表及其他用户。
  Future<void> _loadProfiles(List<SquareFollowEntry> entries) async {
    await Future.wait(
      entries.map((entry) async {
        if (_profiles.containsKey(entry.cidNumber)) return;
        try {
          final profile = await _api.fetchProfile(
            entry.cidNumber,
            session: widget.session,
          );
          _profiles[entry.cidNumber] = profile;
        } on Exception {
          // 公开资料不可用时由 ProfilePresentation 稳定兜底。
        }
      }),
    );
    if (mounted) setState(() {});
  }

  void _openProfile(String cidNumber) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(
          cidNumber: cidNumber,
          isSelf: false,
          initialProfile: _profiles[cidNumber],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.type.label), centerTitle: true),
      body: Stack(
        children: [
          Positioned.fill(child: _body()),
          if (_loading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                key: const ValueKey('follows-load-progress'),
                minHeight: AppLayout.scaled(context, 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _entries.isEmpty) {
      return const Center(
        child: Text('正在读取关注关系', style: TextStyle(color: AppTheme.textTertiary)),
      );
    }
    if (_failedFirst) {
      return const Center(
        child: Text(
          '加载失败，请返回重试',
          style: TextStyle(color: AppTheme.textTertiary),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text(
            switch (widget.type) {
              FollowsType.following => '还没有关注任何人',
              FollowsType.followers => '还没有关注者',
              FollowsType.mutualFollowing => '还没有互关用户',
            },
            style: const TextStyle(color: AppTheme.textTertiary)),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.separated(
        itemCount: _entries.length + (_loading ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index >= _entries.length) {
            return Padding(
              padding: EdgeInsets.symmetric(
                vertical: AppLayout.scaled(context, 12),
              ),
              child: LinearProgressIndicator(
                key: const ValueKey('follows-more-progress'),
                minHeight: AppLayout.scaled(context, 2),
              ),
            );
          }
          final entry = _entries[index];
          final profile = _profiles[entry.cidNumber];
          final presentation = ProfilePresentation.forIdentityKey(
            entry.cidNumber,
          );
          final avatarKey = profile?.avatarObjectKey;
          return ListTile(
            leading: ProfileAvatar(
              seed: entry.cidNumber,
              size: AppLayout.scaled(context, 42),
              imageUrl: avatarKey == null ? null : _api.mediaUrl(avatarKey),
              imageHeaders: <String, String>{
                'authorization': 'Bearer ${widget.session.sessionToken}',
              },
              identityLevel: profile?.identityLevel,
              membershipLevel: profile?.membershipLevel,
              membershipActive: profile?.membershipActive ?? false,
            ),
            title: Text(
              presentation.resolveDisplayName(publicName: profile?.displayName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              entry.cidNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: AppLayout.scaled(context, 20),
            ),
            onTap: () => _openProfile(entry.cidNumber),
          );
        },
      ),
    );
  }
}
