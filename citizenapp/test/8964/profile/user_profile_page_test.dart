import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
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
  Future<MembershipDisplaySnapshot?> readDisplaySnapshot(
    String cidNumber,
  ) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _wrap({required bool isSelf}) => MaterialApp(
  home: UserProfilePage(
    cidNumber: sampleProfile().cidNumber!,
    isSelf: isSelf,
    api: FakeProfileApi(sampleProfile()),
    cache: FakeProfileCache(sampleProfile()),
    sessionProvider: FakeSessionProvider(fakeSession()),
    subscriptionService: _NullMembershipSnapshotService(),
    viewerAccountLoader: () async => null,
  ),
);

class _PendingRefreshSession extends FakeSessionProvider {
  _PendingRefreshSession() : super(fakeSession());
  final completion = Completer<SquareSessionResolution>();
  int calls = 0;
  @override
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) {
    if (!refresh) return super.resolveSession();
    calls++;
    return completion.future;
  }
}

class _UnavailableSession extends FakeSessionProvider {
  _UnavailableSession(this.status) : super(null);
  final SquareSessionStatus status;
  @override
  Future<SquareSessionResolution> resolveSession({
    bool refresh = false,
  }) async => SquareSessionResolution(status);
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('${platform.name}空内容下拉显示完整进度，服务失败仍重读本地', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakeProfileApi(sampleProfile());
      final provider = _PendingRefreshSession();
      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            cidNumber: sampleProfile().cidNumber!,
            isSelf: true,
            api: api,
            cache: FakeProfileCache(sampleProfile()),
            sessionProvider: provider,
            subscriptionService: _NullMembershipSnapshotService(),
            viewerAccountLoader: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = api.localPostCalls;
      await tester.drag(find.text('暂无公文内容，请在广场发布'), const Offset(0, 380));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(provider.calls, 1);
      expect(
        find.byKey(const ValueKey('profile-refresh-progress')),
        findsOneWidget,
      );
      expect(api.localPostCalls, greaterThan(before));
      provider.completion.complete(
        const SquareSessionResolution(SquareSessionStatus.networkUnavailable),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-refresh-progress')),
        findsNothing,
      );
      expect(find.text('内容加载失败，请下拉刷新'), findsAtLeastNWidgets(1));
      expect(find.text('需要钱包账户才能浏览关注列表'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final status in [
    SquareSessionStatus.noWallet,
    SquareSessionStatus.networkUnavailable,
    SquareSessionStatus.identityUnavailable,
    SquareSessionStatus.deviceUnavailable,
  ]) {
    testWidgets('关注列表保留真实会话状态：${status.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UserProfilePage(
            cidNumber: fakeSession().cidNumber,
            isSelf: true,
            api: FakeProfileApi(sampleProfile()),
            cache: FakeProfileCache(sampleProfile()),
            sessionProvider: _UnavailableSession(status),
            subscriptionService: _NullMembershipSnapshotService(),
            viewerAccountLoader: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(' 关注').first);
      await tester.pumpAndSettle();
      if (status == SquareSessionStatus.noWallet) {
        expect(find.text('需要钱包账户才能浏览关注列表'), findsOneWidget);
      } else {
        expect(find.text(status.message), findsWidgets);
        expect(find.text('需要钱包账户才能浏览关注列表'), findsNothing);
      }
    });
  }

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
    expect(find.text('暂无公文内容，请在广场发布'), findsOneWidget);
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

    expect(find.text('暂无竞选内容，请在广场发布'), findsOneWidget);
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
          cidNumber: sampleProfile().cidNumber!,
          isSelf: true,
          api: api,
          cache: FakeProfileCache(sampleProfile()),
          sessionProvider: FakeSessionProvider(fakeSession()),
          subscriptionService: _NullMembershipSnapshotService(),
          viewerAccountLoader: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.calls, 0);

    MembershipRevision.instance.notifyChanged('OTHER-CID');
    await tester.pumpAndSettle();
    expect(api.calls, 0);

    MembershipRevision.instance.notifyChanged(sampleProfile().cidNumber!);
    await tester.pumpAndSettle();
    expect(api.calls, 0);
  });
}
