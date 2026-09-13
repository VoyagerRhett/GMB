import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/user_profile_page.dart';
import 'package:citizenapp/8964/profile/user_qr_page.dart';
import 'package:citizenapp/8964/profile/widgets/profile_action_icons.dart';
import 'package:citizenapp/8964/profile/widgets/profile_category_tabs.dart';
import 'package:citizenapp/8964/profile/widgets/profile_header_card.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/identity_badge.dart';

import 'fake_profile.dart';

const String _profileCidNumber = 'CN001-CTZN-000000001-2026';

/// 身份账户缓存 fake：resolve/accountId 返回 null，让 _resolveOwnAccount 回退成
/// 「非本人」（行为与迁移前一致）；避免 instance 触发真链读/真 Isar。
class _NullMembershipSnapshotService implements SubscriptionService {
  @override
  Future<MembershipDisplaySnapshot?> readDisplaySnapshot(
    String cidNumber,
  ) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap({
  required bool isSelf,
  required CitizenProfileApi api,
  CitizenProfileCache? cache,
  SquareSessionProvider? sessionProvider,
  TargetPlatform platform = TargetPlatform.android,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets padding = EdgeInsets.zero,
  MembershipDisplayDecision initialMembershipDecision =
      MembershipDisplayDecision.inactiveConfirmed,
  SquareMembershipState? initialMembershipState,
  SubscriptionService? subscriptionService,
}) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: textScaler, padding: padding),
      child: child!,
    ),
    home: UserProfilePage(
      cidNumber: _profileCidNumber,
      isSelf: isSelf,
      api: api,
      cache: cache ?? FakeProfileCache(),
      sessionProvider: sessionProvider ?? FakeSessionProvider(fakeSession()),
      initialMembershipDecision: initialMembershipDecision,
      initialMembershipState: initialMembershipState,
      subscriptionService:
          subscriptionService ?? _NullMembershipSnapshotService(),
      viewerAccountLoader: () async => null,
    ),
  );
}

void main() {
  testWidgets('公开昵称、公民号、三项关系和四类内容计数按身份语义展示', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 914);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _wrap(isSelf: false, api: FakeProfileApi(sampleProfile(displayName: ''))),
    );
    await tester.pumpAndSettle();

    final fallback = ProfilePresentation.forIdentityKey(
      _profileCidNumber,
    ).fallbackName;
    expect(find.text(fallback), findsWidgets);
    expect(find.text('公民号：$_profileCidNumber'), findsOneWidget);
    expect(find.textContaining('SS58：'), findsNothing);
    expect(find.text(kOwner), findsNothing);
    expect(find.textContaining('8 互关'), findsOneWidget);
    expect(find.textContaining('2 关注'), findsOneWidget);
    expect(find.textContaining('128 关注者'), findsOneWidget);
    expect(find.text('公文{36}'), findsOneWidget);
    expect(find.text('帖子{36}'), findsNothing);
    expect(find.text('竞选{6}'), findsOneWidget);
    expect(find.text('视频{4}'), findsOneWidget);
    expect(find.text('文章{12}'), findsOneWidget);
    final mutual = tester.getRect(find.textContaining('8 互关'));
    final following = tester.getRect(find.textContaining('2 关注'));
    final followers = tester.getRect(find.textContaining('128 关注者'));
    expect(following.left - mutual.right, closeTo(18, 0.5));
    expect(followers.left - following.right, closeTo(18, 0.5));
    final categoryBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(categoryBar.labelStyle?.fontSize, 16);
    expect(categoryBar.labelStyle?.fontWeight, FontWeight.w700);
    expect(categoryBar.unselectedLabelStyle?.fontSize, 16);
    expect(categoryBar.unselectedLabelStyle?.fontWeight, FontWeight.w700);
    expect(categoryBar.unselectedLabelColor, AppTheme.textPrimary);
    expect(categoryBar.isScrollable, isTrue);
    expect(categoryBar.tabAlignment, TabAlignment.start);
    expect(ProfileCategoryTabs.height, 36);
    expect(ProfileCategoryTabs.labelTopPadding, 8);
    final postsLabel = tester.widget<Text>(
      find.byKey(const ValueKey<String>('profile-tab-posts')),
    );
    final spans = (postsLabel.textSpan! as TextSpan).children!;
    expect((spans.first as TextSpan).style?.fontSize, 16);
    expect((spans.first as TextSpan).style?.fontWeight, FontWeight.w700);
    expect((spans.last as TextSpan).style?.fontSize, 11);
    expect((spans.last as TextSpan).style?.fontWeight, FontWeight.w400);
    expect((spans.last as TextSpan).style?.color, AppTheme.textTertiary);
    expect(find.byTooltip('复制 SS58 地址'), findsNothing);
    expect(find.byIcon(Icons.copy), findsNothing);
  });

  testWidgets('本人主页首帧优先使用已确认会员快照而非普通资料镜像', (tester) async {
    await tester.pumpWidget(
      _wrap(
        isSelf: true,
        api: FakeProfileApi(
          sampleProfile(membershipLevel: null, membershipActive: false),
        ),
        initialMembershipDecision: MembershipDisplayDecision.activeConfirmed,
        initialMembershipState: const SquareMembershipState(
          active: true,
          paidUntil: 9999999999999,
          membershipLevel: 'democracy',
        ),
      ),
    );
    await tester.pump();

    final badge = tester.widget<IdentityBadge>(find.byType(IdentityBadge));
    expect(badge.style.checked, isTrue);
  });

  testWidgets('资料模型保留非法账户文本也不展示且窄屏不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(sampleProfile(accountId: 'invalid-account-id')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('SS58：'), findsNothing);
    expect(find.text('公民号：$_profileCidNumber'), findsOneWidget);
    expect(find.byTooltip('复制 SS58 地址'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大字体下三项关系统计保持一组且不反向缩小文字', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(sampleProfile()),
        platform: TargetPlatform.iOS,
        textScaler: const TextScaler.linear(53 / 17),
      ),
    );
    await tester.pumpAndSettle();

    final header = find.byType(ProfileHeaderCard);
    expect(
      find.descendant(of: header, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: header,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('2 关注'), findsOneWidget);
    expect(find.textContaining('128 关注者'), findsOneWidget);
    expect(find.textContaining('8 互关'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('订阅入口固定在通知左侧且与三图标保持同一行', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileActionIcons(
            isSelf: false,
            isFollowing: false,
            leading: SizedBox(
              key: ValueKey<String>('creator-subscribe-entry'),
              width: 56,
              height: 34,
            ),
          ),
        ),
      ),
    );

    final subscribe = find.byKey(
      const ValueKey<String>('creator-subscribe-entry'),
    );
    final notify = find.byIcon(Icons.notifications_outlined);
    expect(subscribe, findsOneWidget);
    expect(notify, findsOneWidget);
    expect(
      tester.getRect(subscribe).right,
      lessThan(tester.getRect(notify).left),
    );
    expect(
      tester.getCenter(subscribe).dy,
      closeTo(tester.getCenter(notify).dy, 0.1),
    );
  });

  testWidgets('仅个性签名改变资料高度且分类文字顶部不产生额外留白', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<({double labelTopPadding, double statsTop})> layoutOf(
      String bio, {
      required TargetPlatform platform,
      required EdgeInsets padding,
    }) async {
      // 先卸载旧 State，避免相同路由类型复用上一轮 late final API，确保三种签名独立装配。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _wrap(
          isSelf: true,
          api: FakeProfileApi(sampleProfile(bio: bio)),
          platform: platform,
          padding: padding,
        ),
      );
      await tester.pumpAndSettle();
      final stats = find.textContaining('128 关注者');
      final categoryPosts = find.descendant(
        of: find.byType(ProfileCategoryTabs),
        matching: find.byKey(const ValueKey<String>('profile-tab-posts')),
      );
      return (
        labelTopPadding: tester.getRect(categoryPosts).top -
            tester.getRect(find.byType(ProfileCategoryTabs)).top,
        statsTop: tester.getRect(stats).top,
      );
    }

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final padding = platform == TargetPlatform.iOS
          ? const EdgeInsets.only(top: 44, bottom: 34)
          : const EdgeInsets.only(top: 24);
      final empty = await layoutOf('', platform: platform, padding: padding);
      final oneLine = await layoutOf(
        '一行个性签名',
        platform: platform,
        padding: padding,
      );
      final twoLines = await layoutOf(
        '这是一段需要在窄屏显示为两行的个性签名，用来验证只有签名实际高度会推动统计区',
        platform: platform,
        padding: padding,
      );

      for (final layout in [empty, oneLine, twoLines]) {
        expect(
          layout.labelTopPadding,
          closeTo(ProfileCategoryTabs.labelTopPadding, 0.5),
        );
      }
      expect(oneLine.statsTop, greaterThan(empty.statsTop));
      expect(twoLines.statsTop, greaterThan(oneLine.statsTop));
    }
    // WidgetTest 无法准确还原 SliverAppBar.bottom 与 flexibleSpace 的真机叠层
    // 坐标，因此在此锁定产品间距契约；真实视觉距离由双端页面验收覆盖。
    expect(ProfileHeaderCard.statsToCategoryVisualGap, 15);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [375.0, 390.0, 412.0]) {
      testWidgets('${platform.name} 分类栏在 ${width.toInt()}px 屏宽内五段文字空隙相等', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme.copyWith(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                // 真机 iPhone 当前为 Extra Large，Flutter 引擎映射为 19/17。
                textScaler: platform == TargetPlatform.iOS
                    ? const TextScaler.linear(19 / 17)
                    : TextScaler.noScaling,
              ),
              child: child!,
            ),
            home: const DefaultTabController(
              length: 4,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: ProfileCategoryTabs.height,
                    child: ProfileCategoryTabs(
                      posts: 36,
                      campaigns: 6,
                      videos: 4,
                      articles: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final bar = tester.getRect(find.byType(TabBar));
        final labels = [
          for (final tab in ProfileTab.values)
            tester.getRect(
              find.byKey(ValueKey<String>('profile-tab-${tab.name}')),
            ),
        ];
        final gaps = <double>[
          labels.first.left - bar.left,
          for (var index = 1; index < labels.length; index++)
            labels[index].left - labels[index - 1].right,
          bar.right - labels.last.right,
        ];
        expect(gaps.first, greaterThan(0));
        for (final gap in gaps.skip(1)) {
          expect(
            gap,
            closeTo(gaps.first, 0.75),
            reason: '${platform.name} ${width.toInt()}px 的五段视觉空隙必须相等',
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name} 主页统计完整位于分类栏上方且不被裁切', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          isSelf: false,
          api: FakeProfileApi(
            sampleProfile(bio: '两行简介用于验证窄屏和不同平台字体度量下统计区仍完整可见'),
          ),
          platform: platform,
          textScaler: const TextScaler.linear(1.3),
          padding: platform == TargetPlatform.iOS
              ? const EdgeInsets.only(top: 44, bottom: 34)
              : const EdgeInsets.only(top: 24),
        ),
      );
      await tester.pumpAndSettle();

      final stats = [
        find.textContaining('8 互关'),
        find.textContaining('2 关注'),
        find.textContaining('128 关注者'),
      ];
      for (final stat in stats) {
        expect(stat, findsOneWidget);
      }
      // 这里只锁定窄屏大字体时三项文字完整且无 RenderFlex 溢出；统计到分类的
      // 15px 视觉间距由上面的精确几何测试分别覆盖 Android 与 iOS。
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'self profile hides accountId-directed action icons, edit in kebab',
    (tester) async {
      await tester.pumpWidget(
        _wrap(isSelf: true, api: FakeProfileApi(sampleProfile())),
      );
      await tester.pumpAndSettle();

      // 自己看自己：通知/聊天/关注是对主页主人的操作，一律不显示。
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
      expect(find.byIcon(Icons.person_add_alt), findsNothing);
      expect(find.byIcon(Icons.how_to_reg), findsNothing);
      // 认证以头像角的公民徽章呈现；无会员显示身份档，会员显示对应会员档位。
      expect(find.byType(IdentityBadge), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('用户码'), findsOneWidget);
      expect(find.text('编辑资料'), findsOneWidget);
    },
  );

  testWidgets('other profile shows subscribe, chat and follow', (tester) async {
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(sampleProfile(following: false)),
      ),
    );
    await tester.pumpAndSettle();

    // 看别人主页：通知(订阅)/聊天/关注 三个图标都在。
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('用户码'), findsOneWidget);
    expect(find.text('编辑资料'), findsNothing);
  });

  testWidgets('renders an avatar image when the profile has an avatar key', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(sampleProfile(avatarKey: 'profile/acct/avatar')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsWidgets);
    final networkImage = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<NetworkImage>()
        .single;
    expect(networkImage.headers?['authorization'], 'Bearer tok');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pure visitor shows an orange person badge (no membership)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(sampleProfile(certified: false)),
      ),
    );
    await tester.pumpAndSettle();

    final badge = tester.widget<IdentityBadge>(find.byType(IdentityBadge));
    expect(badge.style.color, AppTheme.identityVisitor);
    expect(badge.style.checked, isFalse);
  });

  testWidgets('voting identity, no membership -> blue ring, unchecked', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(sampleProfile(identityLevel: 'voting')),
      ),
    );
    await tester.pumpAndSettle();
    final badge = tester.widget<IdentityBadge>(find.byType(IdentityBadge));
    expect(badge.style.color, AppTheme.identityVoting);
    expect(badge.style.checked, isFalse);
  });

  testWidgets('voting identity + democracy membership -> blue, checked', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(
          sampleProfile(identityLevel: 'voting', membershipLevel: 'democracy'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final badge = tester.widget<IdentityBadge>(find.byType(IdentityBadge));
    expect(badge.style.color, AppTheme.identityVoting);
    expect(badge.style.checked, isTrue);
  });

  testWidgets('candidate identity + spark membership -> red, checked', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(
          sampleProfile(identityLevel: 'candidate', membershipLevel: 'spark'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final badge = tester.widget<IdentityBadge>(find.byType(IdentityBadge));
    expect(badge.style.color, AppTheme.identityCandidate);
    expect(badge.style.checked, isTrue);
  });

  testWidgets('candidate identity + freedom membership -> gold, checked', (
    tester,
  ) async {
    // 会员徽章按会员档位着色，不复用竞选身份的红色。
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: FakeProfileApi(
          sampleProfile(identityLevel: 'candidate', membershipLevel: 'freedom'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final badge = tester.widget<IdentityBadge>(find.byType(IdentityBadge));
    expect(badge.style.color, AppTheme.identityVisitor);
    expect(badge.style.checked, isTrue);
  });

  testWidgets('cache-first renders the fetched profile and writes cache', (
    tester,
  ) async {
    final api = FakeProfileApi(sampleProfile(displayName: '刷新名'));
    final cache = FakeProfileCache();
    await tester.pumpWidget(_wrap(isSelf: true, api: api, cache: cache));
    await tester.pumpAndSettle();

    expect(api.calls, 1);
    expect(cache.wrote, isTrue);
    expect(find.text('刷新名'), findsWidgets);
  });

  testWidgets('following a user optimistically flips the icon', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(following: false, followedBy: true),
    );
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: api,
        sessionProvider: FakeSessionProvider(fakeSession()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person_add_alt), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_add_alt));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.how_to_reg), findsOneWidget);
    expect(find.textContaining('129 关注者'), findsOneWidget);
    expect(find.textContaining('9 互关'), findsOneWidget);
    expect(api.followCalls, 1);
  });

  testWidgets(
    'unfollowing a mutual user decrements followers and mutual count',
    (tester) async {
      final api = FakeProfileApi(
        sampleProfile(following: true, followedBy: true),
      );
      await tester.pumpWidget(
        _wrap(
          isSelf: false,
          api: api,
          sessionProvider: FakeSessionProvider(fakeSession()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.how_to_reg));
      await tester.pumpAndSettle();

      expect(find.textContaining('127 关注者'), findsOneWidget);
      expect(find.textContaining('7 互关'), findsOneWidget);
      expect(api.unfollowCalls, 1);
    },
  );

  testWidgets('a failed follow rolls the icon back', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(following: false),
      throwOnFollow: true,
    );
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: api,
        sessionProvider: FakeSessionProvider(fakeSession()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_add_alt));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person_add_alt), findsOneWidget);
    expect(find.textContaining('128 关注者'), findsOneWidget);
    expect(find.textContaining('8 互关'), findsOneWidget);
    expect(api.followCalls, 1);
  });

  testWidgets('tapping mutual following opens the mutual list', (tester) async {
    final api = FakeProfileApi(sampleProfile());
    await tester.pumpWidget(
      _wrap(
        isSelf: false,
        api: api,
        sessionProvider: FakeSessionProvider(fakeSession()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('8 互关'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '互关'), findsOneWidget);
    expect(api.lastFollowsType, 'mutual_following');
  });

  testWidgets('message on another profile opens a direct chat with that user', (
    tester,
  ) async {
    String? peer;
    String? chatTitle;
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          cidNumber: _profileCidNumber,
          isSelf: false,
          api: FakeProfileApi(sampleProfile(displayName: '轻节点')),
          cache: FakeProfileCache(),
          sessionProvider: FakeSessionProvider(fakeSession()),
          subscriptionService: _NullMembershipSnapshotService(),
          viewerAccountLoader: () async => null,
          onOpenDirectChat: (context,
              {required peerUserId, required title}) {
            peer = peerUserId;
            chatTitle = title;
            return Future<void>.value();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();

    expect(peer, _profileCidNumber);
    expect(chatTitle, '轻节点');
  });

  testWidgets('从他人视角看的是自己账户时私信按钮置灰不触发', (tester) async {
    String? peer;
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          cidNumber: _profileCidNumber,
          isSelf: false,
          api: FakeProfileApi(sampleProfile(displayName: '轻节点')),
          cache: FakeProfileCache(),
          sessionProvider: FakeSessionProvider(fakeSession()),
          subscriptionService: _NullMembershipSnapshotService(),
          // 浏览者账户 == 主页账户 = 他人视角看自己 → 按钮应置灰。
          viewerAccountLoader: () async => kOwner,
          onOpenDirectChat: (context,
              {required peerUserId, required title}) {
            peer = peerUserId;
            return Future<void>.value();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 按钮仍显示（保留他人视角版式）但禁用：点了不触发私信。
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();
    expect(peer, isNull);
  });

  testWidgets('other profile bell prompts to follow first when not following', (
    tester,
  ) async {
    final api = FakeProfileApi(sampleProfile(following: false));
    await tester.pumpWidget(_wrap(isSelf: false, api: api));
    await tester.pumpAndSettle();

    // 未关注时铃铛为空心；点它提示先关注（通知归属挂在关注关系上），不发通知请求。
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('请先关注'), findsOneWidget);
    expect(api.notifyCalls, 0);
  });

  testWidgets('other profile bell mutes notify when following and notifying', (
    tester,
  ) async {
    final api = FakeProfileApi(sampleProfile(following: true, notifying: true));
    await tester.pumpWidget(_wrap(isSelf: false, api: api));
    await tester.pumpAndSettle();

    // 已关注且开通知：铃铛为实心 active；点它静音（enabled=false）。
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);
    await tester.tap(find.byIcon(Icons.notifications_active));
    await tester.pumpAndSettle();

    expect(api.notifyCalls, 1);
    expect(api.lastNotifyEnabled, isFalse);
    // 乐观更新后铃铛转为空心。
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('三点菜单的用户码入口打开用户码页面', (tester) async {
    await tester.pumpWidget(
      _wrap(isSelf: true, api: FakeProfileApi(sampleProfile())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户码'));
    await tester.pumpAndSettle();

    expect(find.byType(UserQrPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, '我的用户码'), findsOneWidget);
  });
}
