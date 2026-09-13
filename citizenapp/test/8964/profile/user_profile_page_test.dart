import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/profile/user_profile_page.dart';
import 'package:citizenapp/8964/profile/widgets/collapsible_header.dart';
import 'package:citizenapp/8964/profile/widgets/profile_category_tabs.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/ui/app_theme.dart';

import 'fake_profile.dart';

/// 身份账户缓存 fake：resolve/accountId 返回 null，让 _resolveOwnAccount 回退成
/// 「非本人」（行为与迁移前一致）；避免 instance 触发真链读/真 Isar。
class _NullMembershipSnapshotService implements SubscriptionService {
  @override
  Future<MembershipDisplaySnapshot?> readDisplaySnapshot(String cidNumber) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap({required bool isSelf}) => MaterialApp(
  home: UserProfilePage(
    cidNumber: kOwner,
    isSelf: isSelf,
    api: FakeProfileApi(sampleProfile()),
    cache: FakeProfileCache(),
    sessionProvider: FakeSessionProvider(fakeSession()),
    subscriptionService: _NullMembershipSnapshotService(),
    viewerAccountLoader: () async => null,
  ),
);

void main() {
  testWidgets('renders 4 counted category tabs without a photo tab', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(isSelf: true));
    await tester.pumpAndSettle();

    for (final tab in ['posts', 'campaign', 'videos', 'articles']) {
      expect(find.byKey(ValueKey<String>('profile-tab-$tab')), findsOneWidget);
    }
    expect(find.textContaining('照片'), findsNothing);
    expect(find.text('公文{36}'), findsOneWidget);
    expect(find.text('帖子{36}'), findsNothing);
    expect(find.text('竞选{6}'), findsOneWidget);
    expect(find.text('视频{4}'), findsOneWidget);
    expect(find.text('文章{12}'), findsOneWidget);
    // 当前资料页统一使用细体左箭头返回，测试与已确认的正式 UI 保持一致。
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.text('还没有公文'), findsOneWidget);
    expect(find.text('还没有帖子'), findsNothing);
    expect(ProfileCategoryTabs.height, 36);
    expect(ProfileCategoryTabs.labelTopPadding, 8);

    final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(appBar.backgroundColor, AppTheme.primaryDark);
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(appBar.scrolledUnderElevation, 0);
    expect(appBar.forceMaterialTransparency, isFalse);
    // 背景必须由折叠头部明确绘制，不能再把透明 Material 当作真实背景。
    expect(find.byType(FlexibleSpaceBar), findsNothing);
    final header = tester.widget<CollapsibleHeader>(
      find.byType(CollapsibleHeader),
    );
    expect(header.banner, isNotNull);
    expect(header.collapsedBanner, isNotNull);
    expect(header.bottomHeight, ProfileCategoryTabs.height);

    final collapsedBackground = find.byKey(
      const ValueKey('profile-collapsed-background-opacity'),
    );
    expect(
      tester.widget<Opacity>(collapsedBackground).opacity,
      closeTo(0, 0.001),
    );
    expect(
      find.descendant(of: collapsedBackground, matching: find.byType(Image)),
      findsOneWidget,
    );

    await tester.drag(find.byType(NestedScrollView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Opacity>(collapsedBackground).opacity,
      closeTo(1, 0.001),
    );
  });

  testWidgets('switching category shows the matching tab body', (tester) async {
    await tester.pumpWidget(_wrap(isSelf: true));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('profile-tab-campaign')),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有竞选内容'), findsOneWidget);
  });

  testWidgets('builds another user profile without exceptions', (tester) async {
    await tester.pumpWidget(_wrap(isSelf: false));
    await tester.pumpAndSettle();

    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('会员镜像确认后只刷新同一公民号的已挂载主页', (tester) async {
    final api = FakeProfileApi(sampleProfile());
    await tester.pumpWidget(
      MaterialApp(
        home: UserProfilePage(
          cidNumber: kOwner,
          isSelf: true,
          api: api,
          cache: FakeProfileCache(),
          sessionProvider: FakeSessionProvider(fakeSession()),
          subscriptionService: _NullMembershipSnapshotService(),
          viewerAccountLoader: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls, 1);

    MembershipRevision.instance.notifyChanged('OTHER-CID');
    await tester.pumpAndSettle();
    expect(api.calls, 1);

    MembershipRevision.instance.notifyChanged(kOwner);
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });
}
