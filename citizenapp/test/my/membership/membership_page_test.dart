import 'dart:async';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/chain/square_chain_service.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/my/membership/membership_page.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/identity_badge.dart';

import '../../support/isar_test_env.dart';
import '../../support/fake_citizen_sdk.dart';

const String _owner = '5GrwvaEF5zXb26Fz9rcQpDWS7u4m6DXb6T6TQvF9j5uQ8g6U';
const _identityAccountId =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
final _identityAccount = CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.hot,
  walletIndex: 1,
  accountIndex: 0,
  accountId: _identityAccountId,
  ss58Address: 'ss58-demo',
  name: '默认账户',
  createdAtMillis: BigInt.one,
  isDefault: true,
);

class _FakeSessionProvider implements SquareSessionProvider {
  SquareSession _session() => SquareSession(
    sessionToken: 'tok',
    cidNumber: "CN220-CTZN2-198805200-2026",
    bindingRevision: 1,
    accountId: _owner,
    expiresAt: DateTime.now().millisecondsSinceEpoch + 600000,
  );

  @override
  Future<SquareSession?> ensureSession() async => _session();

  @override
  Future<SquareSessionResolution> resolveSession({
    bool refresh = false,
  }) async =>
      SquareSessionResolution(SquareSessionStatus.ready, session: _session());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CidNotBoundSessionProvider implements SquareSessionProvider {
  _CidNotBoundSessionProvider({
    this.status = SquareSessionStatus.identityUnbound,
  });

  final SquareSessionStatus status;
  int calls = 0;

  @override
  Future<SquareSession?> ensureSession() async {
    calls++;
    throw const SquareApiException(
      '该钱包账户未绑定 CID,无法登录',
      statusCode: 403,
      errorCode: 'cid_not_bound',
    );
  }

  @override
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) async {
    calls++;
    return SquareSessionResolution(status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 会话建立即失败(如设备子钥校验失败/网络故障):页面须给可见解释,不得留残缺骨架。
class _ThrowingSessionProvider implements SquareSessionProvider {
  @override
  Future<SquareSession?> ensureSession() async {
    throw const SquareApiException(
      '设备子钥签名校验失败',
      statusCode: 401,
      errorCode: 'invalid_signature',
    );
  }

  @override
  Future<SquareSessionResolution> resolveSession({
    bool refresh = false,
  }) async =>
      const SquareSessionResolution(SquareSessionStatus.deviceUnavailable);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingSessionProvider implements SquareSessionProvider {
  _PendingSessionProvider(this.pending);

  final Future<SquareSession?> pending;

  @override
  Future<SquareSession?> ensureSession() => pending;

  @override
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) async {
    final session = await pending;
    return session == null
        ? const SquareSessionResolution(SquareSessionStatus.noWallet)
        : SquareSessionResolution(SquareSessionStatus.ready, session: session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 平台档价格链上单源（`PlatformPrice[level]`，分）；测试直接注入 mock 价表。
class _FakeChainService extends SquareChainService {
  _FakeChainService(this._prices)
    : super(chain: TestCitizenChain(), transactions: TestCitizenTransactions());

  final Map<String, int> _prices;
  int fetchCount = 0;
  final List<bool> forceFreshCalls = [];

  @override
  Future<Map<String, int>> fetchAllPlatformPrices({
    bool forceFresh = false,
  }) async {
    fetchCount++;
    forceFreshCalls.add(forceFresh);
    return _prices;
  }
}

class _FailingChainService extends SquareChainService {
  _FailingChainService()
    : super(chain: TestCitizenChain(), transactions: TestCitizenTransactions());

  int fetchCount = 0;

  @override
  Future<Map<String, int>> fetchAllPlatformPrices({
    bool forceFresh = false,
  }) async {
    fetchCount++;
    throw StateError('chain unavailable');
  }
}

/// 记录订阅 / 取消动作的假编排：不触发真钱包与真上链。
class _RecordingSubscriptionService implements SubscriptionService {
  final List<String> subscribed = [];
  final List<String> changed = [];
  int cancelCount = 0;
  int authorizationCount = 0;
  final List<bool> forceAuthorizationCalls = <bool>[];
  int cacheReadCount = 0;
  int cacheWriteCount = 0;
  SquareMembershipState? mirror;
  MembershipDisplaySnapshot? cachedSnapshot;
  bool mirrorPending = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  bool get mirrorSyncPending => mirrorPending;

  @override
  Future<SquareMembershipState> authorizeMembership(
    SquareSession session, {
    bool forceRefresh = false,
  }) async {
    authorizationCount++;
    forceAuthorizationCalls.add(forceRefresh);
    final state = mirror!;
    final previous = cachedSnapshot;
    cachedSnapshot = MembershipDisplaySnapshot(
      state: state,
      prices: previous?.prices ?? const <String, int>{},
      subscriptionFetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      pricesFetchedAtMs: previous?.pricesFetchedAtMs ?? 0,
    );
    return state;
  }

  @override
  Future<MembershipDisplaySnapshot?> readDisplaySnapshot(
    String accountId,
  ) async {
    cacheReadCount++;
    return cachedSnapshot;
  }

  @override
  Future<void> writeDisplaySnapshot(
    String accountId,
    MembershipDisplaySnapshot snapshot,
  ) async {
    cacheWriteCount++;
    cachedSnapshot = snapshot;
  }

  @override
  Future<void> subscribe(
    String level,
    int expectedPriceFen, {
    BuildContext? context,
  }) async {
    subscribed.add('$level:$expectedPriceFen');
  }

  @override
  Future<void> cancel({BuildContext? context}) async {
    cancelCount++;
  }

  @override
  Future<void> changePlan(
    String level,
    int expectedPriceFen, {
    BuildContext? context,
  }) async {
    changed.add('$level:$expectedPriceFen');
  }
}

/// 会员与身份彻底解耦（ADR-037）：会员卡只描述订阅，不含任何身份字段。
/// plans 留空 → 页面用三档兜底套餐（自由 / 民主 / 薪火）渲染。
SquareMembershipState _state({
  bool active = false,
  bool subscriptionActive = false,
  String? membershipLevel,
  String? subscriptionStatus,
  int lastChargedAt = 0,
}) {
  return SquareMembershipState(
    active: active,
    paidUntil: active ? DateTime.now().millisecondsSinceEpoch + 600000 : 0,
    membershipLevel: membershipLevel,
    subscriptionStatus:
        subscriptionStatus ?? (subscriptionActive ? 'active' : null),
    subscriptionActive: subscriptionActive,
    lastChargedAt: lastChargedAt,
    plans: const [],
  );
}

Future<void> _pump(
  WidgetTester tester,
  SquareMembershipState state, {
  Map<String, int> prices = const {},
  SubscriptionService? service,
  SquareSessionProvider? sessionProvider,
  SquareChainService? chainService,
}) async {
  final effectiveService = service ?? _RecordingSubscriptionService();
  if (effectiveService is _RecordingSubscriptionService) {
    effectiveService.mirror ??= effectiveService.cachedSnapshot?.state ?? state;
  }
  await tester.pumpWidget(
    MaterialApp(
      home: MembershipPage(
        chainService: chainService ?? _FakeChainService(prices),
        sessionProvider: sessionProvider ?? _FakeSessionProvider(),
        subscriptionService: effectiveService,
        identityResolver: _RegisteredFinalizedIdentity(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _frontCard(String text) => find.descendant(
  of: find.byKey(const ValueKey('membership-front-card')),
  matching: find.text(text),
);

Finder _frontButton(String label) => find.descendant(
  of: find.byKey(const ValueKey('membership-front-card')),
  matching: find.widgetWithText(FilledButton, label),
);

class _RegisteredFinalizedIdentity implements FinalizedIdentityResolver {
  @override
  Future<FinalizedIdentity?> resolve() async => FinalizedIdentity(
    accountId: _identityAccountId,
    ss58Address: 'ss58-demo',
    snapshot: CitizenIdentityChainSnapshot(
      cidNumber: 'CN220-CTZN2-100000001-2026',
      accountId: Uint8List(32),
      bindingRevision: 1,
      votingIdentity: null,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWallet implements CitizenSdkWallet {
  @override
  Future<CitizenWalletState> getState() async => CitizenWalletState(
    revision: BigInt.one,
    hotProfile: null,
    accounts: [_identityAccount],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SubscriptionService _subscriptionService({SquareApiClient? api}) =>
    SubscriptionService(
      wallet: _FakeWallet(),
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      identityResolver: _RegisteredFinalizedIdentity(),
      sessionProvider: _FakeSessionProvider(),
      api: api,
    );

void main() {
  useIsolatedIsar();

  test('平台 finalized 镜像回执不再产生设备签名', () async {
    var deviceSignCount = 0;
    final api = SquareApiClient(
      baseUrl: 'https://membership.test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/square/membership/confirm');
        expect(request.headers['authorization'], 'Bearer tok');
        expect(request.headers, isNot(contains('x-device-signature')));
        expect(request.body, contains('"tx_hash"'));
        expect(request.body, contains('"block_hash"'));
        expect(request.body, isNot(contains('signed_extrinsic_hex')));
        expect(request.body, isNot(contains('membership_level')));
        expect(request.body, isNot(contains('"action"')));
        return http.Response(
          '''{"active":true,"subscription_active":true,"membership":{"membership_level":"democracy","paid_until":9999999999999,"subscription_status":"active","last_charged_at":1000},"plans":[],"usage_state":null}''',
          200,
        );
      }),
    );
    final session = SquareSession(
      sessionToken: 'tok',
      cidNumber: "CN220-CTZN2-198805200-2026",
      bindingRevision: 1,
      accountId: _owner,
      expiresAt: 9999999999999,
      signRequest: (_) async {
        deviceSignCount++;
        return 'device-signature';
      },
    );

    final confirmed = await api.confirmPlatformSubscription(
      session: session,
      txHash: '0x${List.filled(64, 'a').join()}',
      blockHashHex: '0x${List.filled(64, 'b').join()}',
    );

    expect(deviceSignCount, 0);
    expect(confirmed.active, isTrue);
    expect(confirmed.membershipLevel, 'democracy');
  });

  test('同一 CitizenServe 身份会话跨页面服务实例只读取一次会员', () async {
    var membershipCalls = 0;
    final api = SquareApiClient(
      baseUrl: 'https://membership.test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/square/membership');
        membershipCalls += 1;
        return http.Response(
          '''{"active":true,"subscription_active":true,"membership":{"membership_level":"freedom","paid_until":9999999999999,"subscription_status":"active","last_charged_at":1000},"plans":[],"usage_state":null}''',
          200,
        );
      }),
    );
    final session = SquareSession(
      sessionToken: 'membership-session-once',
      cidNumber: 'CN220-CTZN2-198805299-2026',
      bindingRevision: 9,
      accountId:
          '0x9999999999999999999999999999999999999999999999999999999999999999',
      expiresAt: 9999999999999,
      signRequest: (_) async => 'test-device-signature',
    );
    final first = _subscriptionService(api: api);
    final second = _subscriptionService(api: api);

    final states = await Future.wait([
      first.authorizeMembership(session),
      second.authorizeMembership(session),
    ]);

    expect(membershipCalls, 1);
    expect(states.every((state) => state.active), isTrue);
    expect(
      SubscriptionService.chatAuthorizationResolvedFor(session.cidNumber),
      isTrue,
    );
    expect(
      SubscriptionService.membershipResolvedFor(session.cidNumber),
      isTrue,
    );
  });

  testWidgets('renders the three subscription tier cards', (tester) async {
    await _pump(tester, _state());

    expect(find.text('自由会员'), findsOneWidget);
    expect(find.text('民主会员'), findsOneWidget);
    expect(find.text('薪火会员'), findsOneWidget);
    const mottos = <String, String>{
      'freedom': '生命诚可贵.爱情价更高.若为自由故.两者皆可抛',
      'democracy': '民主不是万能的.没有民主是万万不能的',
      'spark': '自由民主.薪火相传',
    };
    for (final entry in mottos.entries) {
      final level = entry.key;
      final expectedBadgeColor = switch (level) {
        'freedom' => AppTheme.identityVisitor,
        'democracy' => AppTheme.identityVoting,
        _ => AppTheme.identityCandidate,
      };
      final displayName = switch (level) {
        'freedom' => '自由会员',
        'democracy' => '民主会员',
        _ => '薪火会员',
      };
      final titleFinder = find.text(displayName);
      final badgeFinder = find.byKey(ValueKey('membership-tier-badge-$level'));
      final badge = tester.widget<IdentityBadge>(badgeFinder);
      final title = tester.widget<Text>(titleFinder);
      expect(badge.size, title.style?.fontSize);
      expect(badge.style.color, expectedBadgeColor);
      expect(badge.style.checked, isTrue);
      expect(
        tester.getCenter(badgeFinder).dx,
        lessThan(tester.getCenter(titleFinder).dx),
      );
      final motto = find.byKey(ValueKey('membership-motto-$level'));
      final content = find.byKey(ValueKey('membership-motto-content-$level'));
      expect(motto, findsOneWidget);
      expect(content, findsOneWidget);
      expect(
        tester.getCenter(content).dx,
        closeTo(tester.getCenter(motto).dx, 0.01),
      );

      final dotCount = '.'.allMatches(entry.value).length;
      for (var index = 0; index < dotCount; index++) {
        final slot = find.byKey(ValueKey('membership-motto-dot-$level-$index'));
        final dot = find.byKey(
          ValueKey('membership-motto-dot-shape-$level-$index'),
        );
        expect(slot, findsOneWidget);
        expect(dot, findsOneWidget);
        // 点在自己的固定盒中上下、左右精确居中；最长宣传语缩放后仍至少 4px，
        // 明显大于原字体基线句点。
        expect(
          tester.getCenter(dot).dx,
          closeTo(tester.getCenter(slot).dx, 0.01),
        );
        expect(
          tester.getCenter(dot).dy,
          closeTo(tester.getCenter(slot).dy, 0.01),
        );
        expect(tester.getSize(dot).width, greaterThanOrEqualTo(4));
        expect(tester.getSize(dot).height, greaterThanOrEqualTo(4));
      }

      final coloredHeader = tester.widget<Container>(
        find.byKey(ValueKey('membership-colored-header-$level')),
      );
      expect(coloredHeader.padding, const EdgeInsets.fromLTRB(16, 16, 16, 8));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 宽视口下三档徽章、名称和价格不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      _state(),
      prices: const {'freedom': 29900, 'democracy': 99900, 'spark': 199900},
    );

    for (final level in const ['freedom', 'democracy', 'spark']) {
      expect(
        find.byKey(ValueKey('membership-tier-badge-$level')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('会话请求未完成时首帧已经显示三张静态会员卡', (tester) async {
    final pendingSession = Completer<SquareSession?>();
    await tester.pumpWidget(
      MaterialApp(
        home: MembershipPage(
          chainService: _FakeChainService(const {}),
          sessionProvider: _PendingSessionProvider(pendingSession.future),
          subscriptionService: _RecordingSubscriptionService(),
          identityResolver: _RegisteredFinalizedIdentity(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('自由会员'), findsOneWidget);
    expect(find.text('民主会员'), findsOneWidget);
    expect(find.text('薪火会员'), findsOneWidget);
    expect(find.text('会员状态同步中'), findsNWidgets(3));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    pendingSession.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('请先添加钱包账户'), findsNWidgets(4));
  });

  testWidgets('有效缓存直接展示且身份会话只鉴权一次并且不重复读取价格', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = _RecordingSubscriptionService()
      ..cachedSnapshot = MembershipDisplaySnapshot(
        state: _state(
          active: true,
          subscriptionActive: true,
          membershipLevel: 'democracy',
        ),
        prices: const {'freedom': 29900, 'democracy': 99900, 'spark': 199900},
        subscriptionFetchedAtMs: now,
        pricesFetchedAtMs: now,
      );
    final chain = _FakeChainService(const {
      'freedom': 1,
      'democracy': 2,
      'spark': 3,
    });

    await _pump(tester, _state(), service: service, chainService: chain);

    expect(find.text('999.00 元'), findsOneWidget);
    expect(find.text('当前会员'), findsOneWidget);
    expect(service.authorizationCount, 1);
    expect(service.forceAuthorizationCalls, [isFalse]);
    expect(chain.fetchCount, 0);
  });

  testWidgets('手动刷新绕过会话结果强制读取 CitizenServe 和链上价格', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = _RecordingSubscriptionService()
      ..cachedSnapshot = MembershipDisplaySnapshot(
        state: _state(),
        prices: const {'freedom': 29900},
        subscriptionFetchedAtMs: now,
        pricesFetchedAtMs: now,
      );
    final chain = _FakeChainService(const {'freedom': 39900});

    await _pump(tester, _state(), service: service, chainService: chain);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();

    expect(service.authorizationCount, 2);
    expect(service.forceAuthorizationCalls, [isFalse, isTrue]);
    expect(chain.fetchCount, 1);
    expect(chain.forceFreshCalls, [isTrue]);
    expect(find.text('399.00 元'), findsOneWidget);
  });

  testWidgets('后台价格刷新失败时保留上一次缓存价格和三张卡', (tester) async {
    final stale = DateTime.now()
        .subtract(const Duration(hours: 1))
        .millisecondsSinceEpoch;
    final service = _RecordingSubscriptionService()
      ..cachedSnapshot = MembershipDisplaySnapshot(
        state: _state(),
        prices: const {'freedom': 29900},
        subscriptionFetchedAtMs: stale,
        pricesFetchedAtMs: stale,
      );
    final chain = _FailingChainService();

    await _pump(tester, _state(), service: service, chainService: chain);

    expect(chain.fetchCount, 1);
    expect(find.text('自由会员'), findsOneWidget);
    expect(find.text('民主会员'), findsOneWidget);
    expect(find.text('薪火会员'), findsOneWidget);
    expect(find.text('299.00 元'), findsOneWidget);
  });

  testWidgets('会员页不依赖 Cloudflare 套餐接口也能展示静态名称', (tester) async {
    await _pump(tester, _state(), prices: const {'freedom': 29900});

    expect(find.text('自由会员'), findsOneWidget);
    expect(find.text('299.00 元'), findsOneWidget);
    expect(find.text('会员状态加载失败'), findsNothing);
  });

  testWidgets('defaults to the freedom card for a fresh account', (
    tester,
  ) async {
    await _pump(tester, _state());
    expect(_frontCard('自由会员'), findsOneWidget);
  });

  testWidgets('fronts the current membership tier card + 当前会员 marker', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(active: true, subscriptionActive: true, membershipLevel: 'spark'),
    );

    expect(_frontCard('薪火会员'), findsOneWidget);
    expect(find.text('当前会员'), findsOneWidget);
    final currentCard = tester.widget<Container>(
      find.byKey(const ValueKey('membership-tier-card-spark')),
    );
    final border = (currentCard.decoration as BoxDecoration).border! as Border;
    expect(border.top.color, AppTheme.identityCandidate);
    expect(border.top.width, 2);
  });

  testWidgets('any identity can subscribe any tier — all cards show 订阅', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(),
      prices: const {'freedom': 1, 'democracy': 2, 'spark': 3},
    );
    // 三档解耦、无身份门槛：三张卡都可订阅。
    expect(find.text('订阅'), findsNWidgets(3));
    expect(find.text('当前会员'), findsNothing);
  });

  testWidgets('shows 取消订阅 on the active tier + 更换为此档 on the others', (
    tester,
  ) async {
    await _pump(
      tester,
      _state(
        active: true,
        subscriptionActive: true,
        membershipLevel: 'freedom',
      ),
      prices: const {'freedom': 1, 'democracy': 2, 'spark': 3},
    );

    expect(find.text('取消订阅'), findsOneWidget);
    expect(find.text('更换为此档'), findsNWidgets(2));
  });

  testWidgets('公民币月价来自链读，逐档展示', (tester) async {
    await _pump(
      tester,
      _state(),
      prices: const {'freedom': 29900, 'democracy': 99900, 'spark': 199900},
    );

    expect(find.text('299.00 元'), findsOneWidget);
    expect(find.text('999.00 元'), findsOneWidget);
    expect(find.text('1,999.00 元'), findsOneWidget);
    for (final level in const ['freedom', 'democracy', 'spark']) {
      final image = tester.widget<Image>(
        find.byKey(ValueKey('membership-price-gmb-mark-$level')),
      );
      expect(
        (image.image as AssetImage).assetName,
        'assets/icons/gmb-mark.png',
      );
      expect(image.width, 18);
      expect(image.height, 18);
      expect(image.colorBlendMode, BlendMode.srcIn);
    }
  });

  testWidgets('会员详情价格左侧显示公民币标志', (tester) async {
    await _pump(tester, _state(), prices: const {'freedom': 199900});

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('membership-front-card')),
        matching: find.text('查看详细权益'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('会员详情'), findsOneWidget);
    expect(find.text('1,999.00 元'), findsOneWidget);
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('membership-detail-price-gmb-mark-freedom')),
    );
    expect((image.image as AssetImage).assetName, 'assets/icons/gmb-mark.png');
    expect(image.width, 18);
    expect(image.height, 18);
    expect(image.color, AppTheme.textPrimary);
    expect(image.colorBlendMode, BlendMode.srcIn);
  });

  testWidgets('会员卡片和详情展示最新自由会员用量标准', (tester) async {
    await _pump(tester, _state());

    expect(find.text('聊天 文字/表情/贴纸/图片'), findsNWidgets(3));
    expect(find.text('语音/视频消息 3 分钟 · 语音/视频通话'), findsNWidgets(3));
    expect(find.text('聊天附件 每个 10MB'), findsOneWidget);
    expect(find.text('视频 3 分钟 · 标清 · 16MB'), findsOneWidget);
    expect(find.text('文章 3 万字 · 50 图 · 1 视频'), findsOneWidget);
    expect(find.text('每月 图 300 · 视频 300 分钟'), findsOneWidget);
    expect(find.text('并发上传 1 个 · 存储 100GB'), findsOneWidget);
    expect(find.text('视频 30 分钟 · 高清 · 300MB'), findsOneWidget);
    expect(find.text('文章 3 万字 · 100 图 · 3 视频'), findsOneWidget);
    expect(find.text('每月 图 1,500 · 视频 1,000 分钟'), findsOneWidget);
    expect(find.text('并发上传 2 个 · 存储 1TB'), findsOneWidget);
    expect(find.text('视频 3 小时 · 高清 · 3GB'), findsOneWidget);
    expect(find.text('文章 3 万字 · 100 图 · 10 视频'), findsOneWidget);
    expect(find.text('每月 图 5,000 · 视频 10,000 分钟'), findsOneWidget);
    expect(find.text('并发上传 3 个 · 存储 10TB'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('membership-front-card')),
        matching: find.text('查看详细权益'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('文字、表情、贴纸、图片'), findsOneWidget);
    expect(find.text('最长 3 分钟'), findsNWidgets(2));
    expect(find.text('支持'), findsNWidgets(2));
    expect(find.text('最大 10MB'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('最多 1 个'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('最多 1 个'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('用量额度'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('300 分钟'), findsOneWidget);
    expect(find.text('100GB'), findsOneWidget);
  });

  testWidgets('链上未设价 → 显示占位且禁止发起订阅', (tester) async {
    await _pump(tester, _state());
    expect(find.text('—'), findsNWidgets(3));
    final button = tester.widget<FilledButton>(_frontButton('链上价格未就绪'));
    expect(button.onPressed, isNull);
  });

  testWidgets('点击订阅按钮走 App 内订阅并传对应档', (tester) async {
    final service = _RecordingSubscriptionService();
    await _pump(
      tester,
      _state(),
      prices: const {'freedom': 29900},
      service: service,
    );

    final button = _frontButton('订阅');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();

    // 默认前置档=自由 → 订阅传 'freedom'。
    expect(service.subscribed, ['freedom:29900']);
    expect(service.cancelCount, 0);
    expect(service.changed, isEmpty);
  });

  testWidgets('finalized 后镜像未确认时明确提示权益仍在同步', (tester) async {
    final service = _RecordingSubscriptionService()..mirrorPending = true;
    await _pump(
      tester,
      _state(),
      prices: const {'freedom': 29900},
      service: service,
    );

    await tester.tap(_frontButton('订阅'));
    await tester.pumpAndSettle();

    expect(find.text('链上订阅已生效，会员权益正在同步'), findsOneWidget);
  });

  test('会员修订只为非空公民号发出失效通知', () {
    final events = <MembershipRevisionEvent>[];
    void listener() {
      final event = MembershipRevision.instance.listenable.value;
      if (event != null) events.add(event);
    }

    MembershipRevision.instance.listenable.addListener(listener);
    addTearDown(
      () => MembershipRevision.instance.listenable.removeListener(listener),
    );

    MembershipRevision.instance.notifyChanged('   ');
    MembershipRevision.instance.notifyChanged('CID-1');

    expect(events, hasLength(1));
    expect(events.single.cidNumber, 'CID-1');
    expect(events.single.revision, greaterThan(0));
  });

  testWidgets('点击另一档按钮走一次链上换档', (tester) async {
    final service = _RecordingSubscriptionService();
    await _pump(
      tester,
      _state(
        active: true,
        subscriptionActive: true,
        membershipLevel: 'freedom',
        subscriptionStatus: 'active',
      ),
      prices: const {'freedom': 1, 'democracy': 2, 'spark': 3},
      service: service,
    );

    // 在会员卡层叠手势区左滑，把民主档移到前层，再执行换档。
    await tester.drag(
      find.byKey(const ValueKey('membership-tier-stack-gesture')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(_frontButton('更换为此档'));
    await tester.pumpAndSettle();

    expect(service.changed, ['democracy:2']);
    expect(service.subscribed, isEmpty);
  });

  testWidgets('点击取消订阅按钮走 App 内取消', (tester) async {
    final service = _RecordingSubscriptionService();
    await _pump(
      tester,
      _state(
        active: true,
        subscriptionActive: true,
        membershipLevel: 'freedom',
      ),
      service: service,
    );

    final button = _frontButton('取消订阅');
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(service.cancelCount, 1);
    expect(service.subscribed, isEmpty);
    expect(service.changed, isEmpty);
  });

  testWidgets('订阅生效横幅显示订阅起止 + 链上自动续费口径', (tester) async {
    await _pump(
      tester,
      _state(
        active: true,
        subscriptionActive: true,
        membershipLevel: 'freedom',
        subscriptionStatus: 'active',
        lastChargedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(find.textContaining('链上到期自动续费'), findsOneWidget);
    expect(find.textContaining('订阅 '), findsOneWidget);
  });

  testWidgets('会话建立失败且无可展示数据 → 顶部失败横幅 + 三卡保留', (tester) async {
    await _pump(
      tester,
      _state(active: false),
      sessionProvider: _ThrowingSessionProvider(),
    );

    // 失败必须有可见解释与重试入口;三张静态卡按本页设计不得被整页错误替换。
    expect(
      find.byKey(const ValueKey('membership-load-failure-banner')),
      findsOneWidget,
    );
    expect(find.text('钱包设备认证暂时不可用，请稍后重试'), findsNWidgets(4));
    expect(find.text('请先添加钱包账户'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('membership-front-card')), findsOneWidget);
  });

  testWidgets('已取消订阅 → 横幅标签「到期终止」且不再续费', (tester) async {
    await _pump(
      tester,
      _state(
        active: true,
        subscriptionActive: true,
        membershipLevel: 'freedom',
        subscriptionStatus: 'cancelled',
        lastChargedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    expect(find.textContaining('已取消 · 到期终止'), findsOneWidget);
    expect(find.textContaining('链上到期自动续费'), findsNothing);
  });

  test('SquareMembershipState 订阅窗口 getter', () {
    const withWindow = SquareMembershipState(
      active: true,
      paidUntil: 2000,
      subscriptionActive: true,
      lastChargedAt: 1000,
    );
    expect(withWindow.hasSubscriptionWindow, isTrue);

    const noWindow = SquareMembershipState(
      active: true,
      paidUntil: 2000,
      subscriptionActive: true,
    );
    // 缺 last_charged_at（=0）→ 无可展示窗口。
    expect(noWindow.hasSubscriptionWindow, isFalse);
  });

  test('会员动态展示快照按 CID 持久化且不包含静态套餐', () async {
    final service = _subscriptionService();
    const cidNumber = 'CN220-CTZN2-100000001-2026';
    const snapshot = MembershipDisplaySnapshot(
      state: SquareMembershipState(
        active: true,
        paidUntil: 9999999999999,
        membershipLevel: 'democracy',
        subscriptionStatus: 'active',
        subscriptionActive: true,
        lastChargedAt: 1000,
      ),
      prices: {'freedom': 29900, 'democracy': 99900, 'spark': 199900},
      subscriptionFetchedAtMs: 3000,
      pricesFetchedAtMs: 4000,
    );

    await service.writeDisplaySnapshot(cidNumber, snapshot);
    final restored = await service.readDisplaySnapshot(cidNumber);

    expect(restored, isNotNull);
    expect(restored!.state.membershipLevel, 'democracy');
    expect(restored.state.plans, isEmpty);
    expect(restored.decision, MembershipDisplayDecision.activeConfirmed);
    expect(restored.prices['spark'], 199900);
    expect(restored.subscriptionFetchedAtMs, 3000);
    expect(restored.pricesFetchedAtMs, 4000);
  });

  // 中文注释：同一状态在会员卡和详情页都必须保真，且按钮不得再与价格拼接。
  testWidgets('本机已有绑定但 Worker 未投影 → 显示身份同步故障而不是无钱包', (tester) async {
    final sessionProvider = _CidNotBoundSessionProvider(
      status: SquareSessionStatus.identityUnavailable,
    );
    await _pump(
      tester,
      _state(active: false),
      prices: const {'freedom': 299, 'democracy': 999, 'spark': 9999},
      sessionProvider: sessionProvider,
    );

    expect(find.text('当前钱包身份尚未同步或绑定，请稍后重试'), findsWidgets);
    expect(find.text('请先添加钱包账户'), findsNothing);
    expect(find.text('注册用户'), findsNothing);
    expect(sessionProvider.calls, 1);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('membership-front-card')),
        matching: find.text('查看详细权益'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('会员详情'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('当前钱包身份尚未同步或绑定，请稍后重试'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('当前钱包身份尚未同步或绑定，请稍后重试'), findsWidgets);
    expect(find.text('请先添加钱包账户'), findsNothing);
  });

  testWidgets('本机无绑定 → Worker 判未注册后显示注册引导', (tester) async {
    final sessionProvider = _CidNotBoundSessionProvider();
    await _pump(
      tester,
      _state(active: false),
      prices: const {'freedom': 299, 'democracy': 999, 'spark': 9999},
      sessionProvider: sessionProvider,
    );

    // 没注册不是加载失败,重试也不会变——横幅必须完全消失。
    expect(
      find.byKey(const ValueKey('membership-load-failure-banner')),
      findsNothing,
    );
    expect(find.textContaining('会员数据加载失败'), findsNothing);
    expect(find.text('重试'), findsNothing);
    // 三张卡照常在,按钮引导注册,且不再显示「会员状态同步中」这类假故障文案。
    expect(find.byKey(const ValueKey('membership-front-card')), findsOneWidget);
    expect(find.text('注册用户'), findsWidgets);
    expect(find.text('会员状态同步中'), findsNothing);
    expect(sessionProvider.calls, 1);
  });

  testWidgets('未注册 → 价格仍显示(价格是链上公开读,不依赖会话)', (tester) async {
    await _pump(
      tester,
      _state(active: false),
      prices: const {'freedom': 299, 'democracy': 999, 'spark': 9999},
      sessionProvider: _CidNotBoundSessionProvider(),
    );

    // 价格排在会话之后时未注册用户看不到价;前置后必须能看到真实价格。
    expect(find.textContaining('2.99'), findsWidgets);
  });
}
