import 'dart:async';
import 'dart:io';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/my/creator/creator_service.dart';
import 'package:citizenapp/my/creator/models/creator_overview.dart';
import 'package:citizenapp/my/creator/models/creator_plan.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/identity_badge_snapshot_store.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/my/user/user.dart';
import 'package:citizenapp/8964/profile/user_qr_page.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/widgets/profile_avatar.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/identity_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../8964/profile/fake_profile.dart';

const _cidNumber = 'CN220-CTZN2-198805200-2026';

final _testWallet = CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.hot,
  walletIndex: 1,
  accountIndex: 0,
  ss58Address: 'wallet_profile_test',
  accountId:
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  name: '测试钱包',
  createdAtMillis: BigInt.one,
  isDefault: true,
);

/// 身份账户缓存 fake：直接返回已缓存 CID 快照，验证离线读取不会启动轻节点。
class _CachedIdentityCache implements CurrentUserContext {
  @override
  Future<CurrentUser?> resolve() async => CurrentUser(
    account: CitizenWalletStateAccount(
      signMode: CitizenWalletSignMode.hot,
      walletIndex: 1,
      accountIndex: 0,
      accountId:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ss58Address: 'wallet_profile_test',
      name: '默认账户',
      createdAtMillis: BigInt.one,
      isDefault: true,
    ),
    binding: AccountDataBinding(
      genesisHash: '0x${'11' * 32}',
      cidNumber: _cidNumber,
      accountId:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      bindingRevision: 1,
    ),
  );
  @override
  Future<String?> accountId() async =>
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWallet implements CitizenSdkWallet {
  _FakeWallet(this.wallet);

  final CitizenWalletStateAccount wallet;

  @override
  Future<CitizenWalletState> getState() async => CitizenWalletState(
    revision: BigInt.one,
    hotProfile: null,
    accounts: [wallet],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIdentityBadgeSnapshotStore extends IdentityBadgeSnapshotStore {
  int readCalls = 0;

  @override
  Future<IdentityBadgeSnapshot?> read(String cidNumber) async {
    readCalls += 1;
    return IdentityBadgeSnapshot(
      cidNumber: cidNumber,
      identityLevel: 'candidate',
      updatedAtMillis: 1,
    );
  }
}

class _FakeSquareApi extends SquareApiClient {
  int membershipCalls = 0;

  @override
  Future<SquareMembershipState> fetchMembership(SquareSession session) async {
    membershipCalls += 1;
    return const SquareMembershipState(active: false, paidUntil: 0);
  }
}

class _PendingMembershipSquareApi extends SquareApiClient {
  final Completer<SquareMembershipState> result =
      Completer<SquareMembershipState>();

  @override
  Future<SquareMembershipState> fetchMembership(SquareSession session) =>
      result.future;
}

class _ActiveMembershipSquareApi extends SquareApiClient {
  @override
  Future<SquareMembershipState> fetchMembership(SquareSession session) async {
    return const SquareMembershipState(
      active: true,
      paidUntil: 9999999999999,
      membershipLevel: 'democracy',
    );
  }
}

class _StaticProfileMediaCache extends CitizenProfileMediaCache {
  _StaticProfileMediaCache({
    required this.avatarPath,
    required this.bannerPath,
  });

  final String avatarPath;
  final String bannerPath;

  @override
  Future<CitizenProfileMediaSnapshot> read(CitizenProfile profile) async =>
      CitizenProfileMediaSnapshot(
        avatarPath: avatarPath,
        bannerPath: bannerPath,
      );

  @override
  Future<CitizenProfileMediaSnapshot> refresh({
    required CitizenProfile profile,
    required String? avatarUrl,
    required String? bannerUrl,
    required Map<String, String>? headers,
  }) => read(profile);
}

class _ConfirmedMembershipSnapshotService implements SubscriptionService {
  static const _state = SquareMembershipState(
    active: true,
    paidUntil: 9999999999999,
    membershipLevel: 'democracy',
  );
  int authorizeCalls = 0;

  @override
  Future<MembershipDisplaySnapshot?> readDisplaySnapshot(
    String cidNumber,
  ) async {
    return const MembershipDisplaySnapshot(
      state: _state,
      prices: <String, int>{},
      subscriptionFetchedAtMs: 1,
      pricesFetchedAtMs: 0,
    );
  }

  @override
  Future<void> writeDisplaySnapshot(
    String cidNumber,
    MembershipDisplaySnapshot snapshot,
  ) async {}

  @override
  Future<SquareMembershipState> authorizeMembership(
    SquareSession session, {
    bool forceRefresh = false,
  }) async {
    authorizeCalls += 1;
    return _state;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedMembershipSnapshotService implements SubscriptionService {
  final Completer<MembershipDisplaySnapshot?> snapshot =
      Completer<MembershipDisplaySnapshot?>();

  @override
  Future<MembershipDisplaySnapshot?> readDisplaySnapshot(String cidNumber) =>
      snapshot.future;

  @override
  Future<void> writeDisplaySnapshot(
    String cidNumber,
    MembershipDisplaySnapshot snapshot,
  ) async {}

  @override
  Future<SquareMembershipState> authorizeMembership(
    SquareSession session, {
    bool forceRefresh = false,
  }) async =>
      (await snapshot.future)?.state ??
      const SquareMembershipState(active: false, paidUntil: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingCreatorService implements CreatorService {
  final Completer<CreatorPageData> refresh = Completer<CreatorPageData>();

  @override
  Future<CreatorDisplaySnapshot?> readDisplaySnapshot(String cidNumber) async =>
      null;

  @override
  Future<CreatorPageData> load({String? expectedCidNumber}) => refresh.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('我的页面只读徽章快照且不启动轻节点', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 914);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final snapshotStore = _FakeIdentityBadgeSnapshotStore();
    final wallet = _testWallet;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MyTab(
          wallet: _FakeWallet(wallet),
          currentUserContext: _CachedIdentityCache(),
          badgeSnapshotStore: snapshotStore,
          sessionProvider: FakeSessionProvider(fakeSession()),
          subscriptionService: _ConfirmedMembershipSnapshotService(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(IdentityBadge), findsOneWidget);
    expect(snapshotStore.readCalls, 1);
    expect(find.text('钱包'), findsOneWidget);
    expect(find.text('管理账户'), findsOneWidget);
    expect(find.text('身份'), findsOneWidget);
    expect(find.text('注册与查看'), findsOneWidget);
    expect(find.text('个人服务'), findsOneWidget);
    expect(find.text('会员｜订阅'), findsOneWidget);
    expect(find.text('创作者'), findsOneWidget);
    expect(find.text('通讯录'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('my-header-status-bar-scrim')),
      findsOneWidget,
    );
    final creatorTop = tester.getTopLeft(find.text('创作者')).dy;
    final contactsTop = tester.getTopLeft(find.text('通讯录')).dy;
    final membershipTop = tester.getTopLeft(find.text('会员｜订阅')).dy;
    expect(creatorTop, lessThan(contactsTop));
    expect(contactsTop, lessThan(membershipTop));
    expect(
      tester.getSize(find.byKey(const ValueKey('my-primary-entry-钱包'))).height,
      AppLayout.primaryEntryHeight,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('my-primary-entry-身份'))).height,
      AppLayout.primaryEntryHeight,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('my-service-entry-创作者'))).height,
      AppLayout.serviceRowHeight,
    );

    final userCodeButton = find.byKey(
      const ValueKey('my-header-user-code-button'),
    );
    final profileChevron = find.byKey(const ValueKey('my-profile-chevron'));
    expect(userCodeButton, findsOneWidget);
    expect(profileChevron, findsOneWidget);
    expect(
      (tester.getCenter(userCodeButton).dx -
              tester.getCenter(profileChevron).dx)
          .abs(),
      lessThan(0.01),
    );
    final userCodeIconRect = tester.getRect(
      find.byIcon(Icons.qr_code_2_rounded),
    );
    final myTitleRect = tester.getRect(find.text('我的'));
    // 验收比较可见图标顶部与文字底部，而不是再次用两个顶部位置糊弄。
    expect(userCodeIconRect.top, greaterThanOrEqualTo(myTitleRect.bottom));
    expect(
      userCodeIconRect.top - myTitleRect.bottom,
      closeTo(AppLayout.scaledValue(1), 0.5),
    );

    await tester.tap(userCodeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(UserQrPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, '我的用户码'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('我的页面展示公开昵称且钱包改名广播不重复刷新资料', (tester) async {
    final wallet = _testWallet;
    final profileApi = FakeProfileApi(sampleProfile(displayName: '公开昵称'));
    final profileCache = FakeProfileCache(sampleProfile(displayName: '缓存昵称'));
    final squareApi = _FakeSquareApi();
    final membershipService = _ConfirmedMembershipSnapshotService();
    final snapshotStore = _FakeIdentityBadgeSnapshotStore();
    await tester.pumpWidget(
      MaterialApp(
        home: MyTab(
          wallet: _FakeWallet(wallet),
          currentUserContext: _CachedIdentityCache(),
          badgeSnapshotStore: snapshotStore,
          profileApi: profileApi,
          profileCache: profileCache,
          sessionProvider: FakeSessionProvider(fakeSession()),
          squareApi: squareApi,
          subscriptionService: membershipService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('公开昵称'), findsOneWidget);
    expect(find.text('不得公开的钱包名'), findsNothing);
    expect(profileApi.calls, 1);
    expect(membershipService.authorizeCalls, 1);
    expect(squareApi.membershipCalls, 0);

    MembershipRevision.instance.notifyChanged(_cidNumber);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(membershipService.authorizeCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('我的首页统一显示 CID 公开头像背景和已确认会员徽章', (tester) async {
    late Directory root;
    late File avatar;
    late File banner;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('my-profile-media-');
      final sourceImage = File('assets/icons/gmb-mark.png');
      avatar = sourceImage.copySync('${root.path}/avatar.png');
      banner = sourceImage.copySync('${root.path}/banner.png');
    });
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final wallet = _testWallet;
    final profile = sampleProfile(
      displayName: '统一公开资料',
      avatarKey: 'profile/avatar',
      bannerKey: 'profile/banner',
    );
    final remoteMembership = _ActiveMembershipSquareApi();
    await tester.pumpWidget(
      MaterialApp(
        home: MyTab(
          wallet: _FakeWallet(wallet),
          currentUserContext: _CachedIdentityCache(),
          badgeSnapshotStore: _FakeIdentityBadgeSnapshotStore(),
          profileApi: FakeProfileApi(profile),
          profileCache: FakeProfileCache(profile),
          profileMediaCache: _StaticProfileMediaCache(
            avatarPath: avatar.path,
            bannerPath: banner.path,
          ),
          sessionProvider: FakeSessionProvider(fakeSession()),
          squareApi: remoteMembership,
          subscriptionService: _ConfirmedMembershipSnapshotService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final profileAvatar = tester.widget<ProfileAvatar>(
      find.byType(ProfileAvatar),
    );
    expect(profileAvatar.imagePath, avatar.path);
    expect(profileAvatar.userImageSet, isTrue);
    expect(profileAvatar.size, 80);
    expect(profileAvatar.badgeOverflow, 6);
    final fileImages = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<FileImage>()
        .map((provider) => provider.file.path)
        .toSet();
    expect(fileImages, containsAll(<String>{avatar.path, banner.path}));
    final badge = tester.widget<IdentityBadge>(find.byType(IdentityBadge));
    expect(badge.style.checked, isTrue);
    final avatarRect = tester.getRect(find.byType(ProfileAvatar));
    final badgeRect = tester.getRect(find.byType(IdentityBadge));
    expect(badgeRect.right, greaterThan(avatarRect.right));
    expect(badgeRect.bottom, greaterThan(avatarRect.bottom));
    expect(find.text('竞选身份 · 民主会员'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MyTab 已确认有效快照在普通D1读取等待时保持会员徽章和创作者首帧', (tester) async {
    final wallet = _testWallet;
    final membershipSnapshots = _DelayedMembershipSnapshotService();
    final squareApi = _PendingMembershipSquareApi();
    final creatorService = _PendingCreatorService();
    await tester.pumpWidget(
      MaterialApp(
        home: MyTab(
          wallet: _FakeWallet(wallet),
          currentUserContext: _CachedIdentityCache(),
          badgeSnapshotStore: _FakeIdentityBadgeSnapshotStore(),
          profileApi: FakeProfileApi(sampleProfile(displayName: '公开昵称')),
          profileCache: FakeProfileCache(sampleProfile(displayName: '缓存昵称')),
          sessionProvider: FakeSessionProvider(fakeSession()),
          squareApi: squareApi,
          subscriptionService: membershipSnapshots,
          creatorService: creatorService,
        ),
      ),
    );
    await tester.pump();

    // finalized 有效展示快照先落地；后台读取失败也不能把已同步会员降级。
    membershipSnapshots.snapshot.complete(
      const MembershipDisplaySnapshot(
        state: SquareMembershipState(
          active: true,
          paidUntil: 9999999999999,
          membershipLevel: 'democracy',
        ),
        prices: <String, int>{},
        subscriptionFetchedAtMs: 1,
        pricesFetchedAtMs: 0,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final badge = tester.widget<IdentityBadge>(find.byType(IdentityBadge));
    expect(badge.style.checked, isTrue);
    await tester.tap(find.text('创作者'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('去订阅平台会员'), findsNothing);
    expect(find.text('还没有会员档'), findsOneWidget);
    expect(find.textContaining('同步'), findsNothing);

    creatorService.refresh.complete(
      CreatorPageData.active(
        plan: CreatorPlan.empty(_cidNumber),
        overview: CreatorOverview.zero,
      ),
    );
    squareApi.result.complete(
      const SquareMembershipState(
        active: true,
        paidUntil: 9999999999999,
        membershipLevel: 'democracy',
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
