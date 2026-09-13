import 'dart:async';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_citizen_sdk.dart';

import 'package:citizenapp/8964/chain/square_chain_service.dart';
import 'package:citizenapp/8964/compose/compose_page.dart';
import 'package:citizenapp/8964/compose/document/document_compose_body.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_store.dart';
import 'package:citizenapp/8964/compose/video/video_compose_body.dart';
import 'package:citizenapp/8964/compose/widgets/compose_media_widgets.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/pages/square_home_page.dart';
import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/widgets/profile_avatar.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_identity_state.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/identity_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile/fake_profile.dart';

/// 身份账户缓存 fake:resolve 返回 null,让 loadCurrent 回退 wallet.accountId
/// 使用测试默认账户快照，避免 instance 访问真实本地钱包/Isar。
class _NullIdentityCache implements CurrentUserContext {
  @override
  Future<CurrentUser?> resolve() async => null;
  @override
  Future<String?> accountId() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWallet implements CitizenSdkWallet {
  _FakeWallet(this.wallet);

  final CitizenWalletStateAccount? wallet;

  @override
  Future<CitizenWalletState> getState() async => CitizenWalletState(
        revision: BigInt.one,
        hotProfile: null,
        accounts: wallet == null ? const [] : [wallet!],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticProfileMediaCache extends CitizenProfileMediaCache {
  @override
  Future<CitizenProfileMediaSnapshot> read(CitizenProfile profile) async =>
      const CitizenProfileMediaSnapshot(avatarPath: '/tmp/synced-avatar.png');
}

final _registeredWallet = CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.hot,
  walletIndex: 1,
  accountIndex: 0,
  name: '测试钱包',
  ss58Address: 'citizen_test_account_id',
  accountId:
      '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  createdAtMillis: BigInt.one,
  isDefault: true,
);

SquareIdentityService _registeredIdentityService({
  _FakeSquareChainService? chainService,
}) => SquareIdentityService(
  wallet: _FakeWallet(_registeredWallet),
  currentUserContext: _NullIdentityCache(),
  chainService:
      chainService ?? _FakeSquareChainService('CN220-CTZN2-100000001-2026'),
);

SquareIdentityService _emptyIdentityService() => SquareIdentityService(
      wallet: _FakeWallet(null),
      currentUserContext: _NullIdentityCache(),
      chainService: _FakeSquareChainService(null),
    );

SquareIdentityService _unregisteredIdentityService() => SquareIdentityService(
      wallet: _FakeWallet(_registeredWallet),
      currentUserContext: _UnregisteredIdentityCache(),
      chainService: _FakeSquareChainService(null),
    );

class _FakeSquareChainService extends SquareChainService {
  _FakeSquareChainService(this.cidNumber)
      : super(
          chain: TestCitizenChain(),
          transactions: TestCitizenTransactions(),
        );

  final String? cidNumber;
  int fetchIdentityCount = 0;

  @override
  Future<String?> fetchNormalCitizenCidNumber(String accountId) async {
    return cidNumber;
  }

  @override
  Future<({String? cidNumber, String identityLevel})> fetchIdentity(
    String accountId,
  ) async {
    fetchIdentityCount += 1;
    return (
      cidNumber: cidNumber,
      identityLevel: cidNumber == null ? 'visitor' : 'voting',
    );
  }
}

class _StaticComposeIdentityService implements SquareIdentityService {
  const _StaticComposeIdentityService();

  @override
  Future<SquareIdentityState> loadCurrent({bool readLiveChain = true}) async {
    return const SquareIdentityState(
      accountId:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      cidNumber: 'CN220-CTZN2-100000001-2026',
      displayName: '不应显示的用户昵称',
      signMode: CitizenWalletSignMode.hot,
      identityLevel: 'voting',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedComposeIdentityService implements SquareIdentityService {
  final Completer<SquareIdentityState> completer =
      Completer<SquareIdentityState>();

  @override
  Future<SquareIdentityState> loadCurrent({bool readLiveChain = true}) =>
      completer.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingDraftRepository implements SquareComposeDraftRepository {
  final List<SquareComposeDraft> saved = <SquareComposeDraft>[];
  final List<String> deleted = <String>[];

  @override
  Future<void> save(SquareComposeDraft draft) async => saved.add(draft);

  @override
  Future<List<SquareComposeDraft>> list(String cidNumber) async =>
      List<SquareComposeDraft>.unmodifiable(saved);

  @override
  Future<void> delete(String cidNumber, String draftId) async {
    deleted.add('$cidNumber:$draftId');
  }

  @override
  Future<void> retryPendingFileCleanup({String? cidNumber}) async {}
}

class _FakeFeedSource implements SquareFeedSource {
  const _FakeFeedSource();

  @override
  Future<List<SquarePost>> fetchFeed({
    required SquareFeedKind feedKind,
    int limit = 20,
    SquareSession? session,
  }) async {
    return const <SquarePost>[];
  }
}

/// 模拟后台通知在创建会话时抛出非 Exception 错误，验证 unawaited 边界完整。
class _ThrowingSessionProvider implements SquareSessionProvider {
  @override
  Future<SquareSession?> ensureSession() async {
    throw StateError('session unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 保持生产路径类型判断成立，但不访问真实 Worker。
class _FakeSquareApiClient extends SquareApiClient {
  @override
  Future<List<SquarePost>> fetchFeed({
    required SquareFeedKind feedKind,
    int limit = 20,
    SquareSession? session,
  }) async {
    return const <SquarePost>[];
  }
}

/// 未注册：当前默认账户的本地绑定为空，不回退其他账户。
class _UnregisteredIdentityCache implements CurrentUserContext {
  @override
  Future<CurrentUser?> resolve() async => CurrentUser(
    account: CitizenWalletStateAccount(
      signMode: CitizenWalletSignMode.hot,
      walletIndex: 1,
      accountIndex: 0,
      accountId:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      ss58Address: 'ss58-demo',
      name: '默认账户',
      createdAtMillis: BigInt.one,
      isDefault: true,
    ),
    binding: null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Worker 真源判定:登录挑战对未绑定账户回 403 cid_not_bound。
class _CidNotBoundSessionProvider implements SquareSessionProvider {
  @override
  Future<SquareSession?> ensureSession() async {
    throw const SquareApiException(
      '该钱包账户未绑定 CID,无法登录',
      statusCode: 403,
      errorCode: 'cid_not_bound',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 记录最近一次请求的分类，用于断言分类切换真的按 feedKind 重新拉流。
class _RecordingFeedSource implements SquareFeedSource {
  SquareFeedKind? lastFeedKind;
  int calls = 0;

  @override
  Future<List<SquarePost>> fetchFeed({
    required SquareFeedKind feedKind,
    int limit = 20,
    SquareSession? session,
  }) async {
    calls++;
    lastFeedKind = feedKind;
    return const <SquarePost>[];
  }
}

/// 控制 feed 完成时机，验证网络未返回时页面结构仍已显示。
class _PendingFeedSource implements SquareFeedSource {
  final Completer<List<SquarePost>> completer = Completer<List<SquarePost>>();
  int calls = 0;

  @override
  Future<List<SquarePost>> fetchFeed({
    required SquareFeedKind feedKind,
    int limit = 20,
    SquareSession? session,
  }) {
    calls += 1;
    return completer.future;
  }
}

/// 按分类返回不同夹具的假数据源；模拟 Worker 对每个 feed 端点各自过滤
/// （关注流走 `/square/feed/following` 的 JOIN 结果）。
class _KindFeedSource implements SquareFeedSource {
  _KindFeedSource({this.following = const <SquarePost>[]});

  final List<SquarePost> following;

  @override
  Future<List<SquarePost>> fetchFeed({
    required SquareFeedKind feedKind,
    int limit = 20,
    SquareSession? session,
  }) async {
    if (feedKind == SquareFeedKind.following) return following;
    return const <SquarePost>[];
  }
}

SquareMediaItem _media(SquareMediaKind kind) =>
    SquareMediaItem(mediaKind: kind, url: '');

SquarePost _seedPost({
  required String id,
  required String text,
  String? title,
  SquarePostType postType = SquarePostType.document,
  List<SquareMediaItem> media = const [],
}) {
  return SquarePost(
    postId: id,
    author: const SquareAuthor(
      accountId:
          '0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      displayName: '作者',
      identityLevel: 'voting',
    ),
    postCategory: SquarePostCategory.normal,
    postType: postType,
    text: text,
    title: title,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    mediaItems: media,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('feed 未返回时直接显示广场页面且不使用整页转圈', (tester) async {
    final feedSource = _PendingFeedSource();

    await tester.pumpWidget(
      _wrap(
        SquareHomePage(
          identityService: _emptyIdentityService(),
          feedSource: feedSource,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(feedSource.calls, 1);
    expect(find.byTooltip('发布'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('square-person-tank-watermark')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('square-feed-progress')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('广场内容加载失败'), findsNothing);

    feedSource.completer.complete(const <SquarePost>[]);
    await tester.pumpAndSettle();

    expect(feedSource.calls, 1);
    expect(find.byKey(const ValueKey('square-feed-progress')), findsNothing);
    expect(find.text('广场内容加载失败'), findsNothing);
  });

  testWidgets('广场只替换人物坦克背景且保留分类、发布与切换行为', (tester) async {
    final identityService = _emptyIdentityService();
    final feedSource = _RecordingFeedSource();

    await tester.pumpWidget(
      _wrap(
        SquareHomePage(
          identityService: identityService,
          feedSource: feedSource,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 顶部大小标题与空态图标/文字彻底删除。
    expect(find.text('广场'), findsNothing);
    expect(find.text('暂无推荐内容'), findsNothing);
    expect(find.text('暂无关注内容'), findsNothing);
    expect(find.text('暂无竞选内容'), findsNothing);

    // 中央背景只使用选定的人物坦克透明资源；旧单坦克水印不再存在。
    final watermarkFinder = find.byKey(
      const ValueKey<String>('square-person-tank-watermark'),
    );
    expect(watermarkFinder, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('square-tank-watermark')),
      findsNothing,
    );
    final watermark = tester.widget<Image>(watermarkFinder);
    expect(
      (watermark.image as AssetImage).assetName,
      'assets/icons/square-person-tank-watermark.png',
    );
    final watermarkContext = tester.element(watermarkFinder);
    expect(
      watermark.width,
      closeTo(AppLayout.scaled(watermarkContext, 280), 0.01),
    );
    expect(
      watermark.height,
      closeTo(AppLayout.scaled(watermarkContext, 141), 0.01),
    );
    final watermarkOpacity = tester.widget<Opacity>(
      find.byKey(
        const ValueKey<String>('square-person-tank-watermark-opacity'),
      ),
    );
    expect(watermarkOpacity.opacity, 0.08);
    // 顶部头像入口已删除；发布改为右下角悬浮 FAB。
    expect(find.byKey(const ValueKey('compose-user-avatar')), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byTooltip('发布'), findsOneWidget);

    // 五分类可切换：照片不再单独占一档，图片公文继续归普通推荐内容。
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('照片'), findsNothing);
    expect(feedSource.lastFeedKind, SquareFeedKind.recommended);

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    expect(feedSource.lastFeedKind, SquareFeedKind.following);

    await tester.tap(find.text('竞选'));
    await tester.pumpAndSettle();
    expect(feedSource.lastFeedKind, SquareFeedKind.campaign);

    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    expect(feedSource.lastFeedKind, SquareFeedKind.article);

    await tester.tap(find.byIcon(Icons.videocam_outlined));
    await tester.pumpAndSettle();
    expect(feedSource.lastFeedKind, SquareFeedKind.videos);
  });

  testWidgets('会员镜像确认后已挂载广场就地刷新', (tester) async {
    final feedSource = _RecordingFeedSource();
    await tester.pumpWidget(
      _wrap(
        SquareHomePage(
          identityService: _emptyIdentityService(),
          feedSource: feedSource,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(feedSource.calls, 1);

    MembershipRevision.instance.notifyChanged('CID-1');
    await tester.pumpAndSettle();
    expect(feedSource.calls, 2);
  });

  testWidgets('广场图片公文留在推荐流，文章和视频继续按内容分类过滤', (tester) async {
    // 带媒体的卡片较高，默认 600 视口会让第二张之后懒加载不构建；用高视口保证三帖都渲染。
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final seed = [
      _seedPost(id: 'a', text: '照片帖', media: [_media(SquareMediaKind.image)]),
      _seedPost(
        id: 'b',
        text: '视频帖',
        postType: SquarePostType.video,
        media: [_media(SquareMediaKind.video)],
      ),
      _seedPost(
        id: 'c',
        text: '文章正文C',
        title: '文章帖',
        postType: SquarePostType.article,
      ),
    ];
    await tester.pumpWidget(
      _wrap(
        SquareHomePage(
          identityService: _emptyIdentityService(),
          feedSource: _RecordingFeedSource(),
          seedPosts: seed,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 推荐：三帖全在。
    expect(find.text('照片帖'), findsOneWidget);
    expect(find.text('视频帖'), findsOneWidget);
    expect(find.text('文章帖'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    expect(find.text('文章帖'), findsOneWidget);
    expect(find.text('照片帖'), findsNothing);
    expect(find.text('视频帖'), findsNothing);

    await tester.tap(find.byIcon(Icons.videocam_outlined));
    await tester.pumpAndSettle();
    expect(find.text('视频帖'), findsOneWidget);
    expect(find.text('照片帖'), findsNothing);
    expect(find.text('文章帖'), findsNothing);
  });

  testWidgets('发布按钮展开公文、文章、视频，打开编辑页不读链', (tester) async {
    final chainService = _FakeSquareChainService('CN220-CTZN2-100000001-2026');
    final identityService = _registeredIdentityService(
      chainService: chainService,
    );

    await tester.pumpWidget(
      _wrap(
        SquareHomePage(
          identityService: identityService,
          feedSource: const _FakeFeedSource(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(chainService.fetchIdentityCount, 0);

    await tester.tap(find.byTooltip('发布'));
    await tester.pumpAndSettle();
    expect(find.text('公文'), findsOneWidget);
    expect(find.text('文章'), findsWidgets);
    expect(find.text('视频'), findsWidgets);
    expect(chainService.fetchIdentityCount, 0);

    final itemFinders = [
      find.byKey(const ValueKey('square-publish-document')),
      find.byKey(const ValueKey('square-publish-article')),
      find.byKey(const ValueKey('square-publish-video')),
    ];
    final centers = <Offset>[];
    for (final finder in itemFinders) {
      final size = tester.getSize(finder);
      expect(size.width, closeTo(size.height, 0.01));
      expect(tester.widget<Material>(finder).shape, isA<CircleBorder>());
      final center = tester.getCenter(finder);
      centers.add(center);
    }
    // 公文标签也是完整入口的一部分，因此圆弧虚拟圆心需上移标签高度。
    final arcCenter = Offset(centers[2].dx, centers[0].dy);
    final radii = [for (final center in centers) (center - arcCenter).distance];
    // 三个入口圆心位于同一短半径圆弧，且明显比旧菜单更靠近主按钮。
    expect(radii.reduce((a, b) => a > b ? a : b), lessThan(120));
    expect(
      radii.reduce((a, b) => a > b ? a : b) -
          radii.reduce((a, b) => a < b ? a : b),
      lessThan(0.5),
    );
    // 标准四分之一圆弧：0° / 45° / 90°，两段相邻弦长严格相等。
    expect(centers[0].dy, closeTo(arcCenter.dy, 0.5));
    expect(centers[2].dx, closeTo(arcCenter.dx, 0.5));
    expect(
      (centers[0] - centers[1]).distance,
      closeTo((centers[1] - centers[2]).distance, 0.5),
    );
    expect(
      arcCenter.dx - centers[1].dx,
      closeTo(arcCenter.dy - centers[1].dy, 0.5),
    );
    // 完整“公文”入口的下边距等于“视频”圆形入口的右边距。
    final pageSize = tester.getSize(find.byType(SquareHomePage));
    final documentBottom = tester.getBottomRight(find.text('公文')).dy;
    final videoRight = tester.getTopRight(itemFinders[2]).dx;
    expect(
      pageSize.height - documentBottom,
      closeTo(pageSize.width - videoRight, 1),
    );

    await tester.tap(find.byKey(const ValueKey('square-publish-document')));
    await tester.pumpAndSettle();
    expect(find.text('发公文'), findsOneWidget);
    expect(chainService.fetchIdentityCount, 0);
  });

  testWidgets('三类发布页标题真正居中、按钮紧凑且只显示同步头像', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const identityService = _StaticComposeIdentityService();

    for (final postType in SquarePostType.values) {
      await tester.pumpWidget(
        _wrap(
          SquareComposePage(
            postType: postType,
            identityService: identityService,
            profileCache: FakeProfileCache(
              sampleProfile(avatarKey: 'profile/avatar'),
            ),
            profileMediaCache: _StaticProfileMediaCache(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pageWidth = tester.getSize(find.byType(SquareComposePage)).width;
      final titleCenter = tester.getCenter(
        find.byKey(const ValueKey('compose-centered-title')),
      );
      expect(titleCenter.dx, closeTo(pageWidth / 2, 0.5));
      expect(titleCenter.dy, lessThan(tester.getCenter(find.text('取消')).dy));
      final title = tester.widget<Text>(
        find.byKey(const ValueKey('compose-centered-title')),
      );
      final cancel = tester.widget<Text>(find.text('取消'));
      expect(title.style!.fontSize!, greaterThan(cancel.style?.fontSize ?? 14));
      expect(find.text('发${postType.label}'), findsOneWidget);

      final publishSize = tester.getSize(
        find.byKey(const ValueKey('compose-publish-button')),
      );
      expect(publishSize.height, lessThanOrEqualTo(34));
      expect(publishSize.height, greaterThanOrEqualTo(30));

      final avatar = tester.widget<ProfileAvatar>(
        find.byKey(const ValueKey('compose-user-avatar')),
      );
      expect(avatar.imagePath, '/tmp/synced-avatar.png');
      expect(avatar.borderRadius, 17);
      expect(avatar.showBadge, isFalse);
      expect(find.byType(IdentityBadge), findsNothing);
      expect(find.text('不应显示的用户昵称'), findsNothing);
      expect(find.text(postType.label), findsNothing);
      expect(find.text('发布额度按会员套餐计'), findsNothing);
      expect(find.byIcon(Icons.workspace_premium_outlined), findsNothing);

      final publishButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('compose-publish-button')),
      );
      expect(publishButton.onPressed, isNull);
    }
  });

  testWidgets('公文内容合法后发布按钮启用，清空后立即恢复灰色禁用', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SquareComposePage(
          postType: SquarePostType.document,
          identityService: _StaticComposeIdentityService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    FilledButton publishButton() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('compose-publish-button')),
    );
    expect(publishButton().onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('document-text-field')),
      '合法公文内容',
    );
    await tester.pump();
    await tester.pump();
    expect(publishButton().onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const ValueKey('document-text-field')),
      '',
    );
    await tester.pump();
    await tester.pump();
    expect(publishButton().onPressed, isNull);
  });

  testWidgets('文章首图位于标题右侧，添加图文框独占顶部靠右位置', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SquareComposePage(
          postType: SquarePostType.article,
          identityService: _StaticComposeIdentityService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final coverFinder = find.byKey(const ValueKey('article-cover-picker'));
    final addSectionFinder = find.byKey(const ValueKey('article-add-section'));
    final inlineFinder = find.byKey(const ValueKey('article-insert-media-0'));
    expect(coverFinder, findsOneWidget);
    expect(addSectionFinder, findsOneWidget);
    expect(
      tester.widget<ComposeMediaAddButton>(coverFinder).icon,
      Icons.add_photo_alternate_outlined,
    );
    expect(
      tester.getCenter(coverFinder).dy,
      lessThan(tester.getCenter(inlineFinder).dy),
    );
    expect(
      tester.getCenter(addSectionFinder).dx,
      greaterThan(tester.getSize(find.byType(SquareComposePage)).width * 0.75),
    );
    expect(
      tester.getCenter(coverFinder).dy,
      greaterThan(tester.getCenter(addSectionFinder).dy),
    );
    expect(
      tester.getTopRight(coverFinder).dx,
      closeTo(tester.getTopRight(addSectionFinder).dx, 0.5),
    );
    expect(
      tester.getTopRight(inlineFinder).dx,
      closeTo(tester.getTopRight(addSectionFinder).dx, 1.1),
    );
    expect(
      tester.widget<ComposeMediaAddButton>(addSectionFinder).iconSize,
      greaterThan(tester.widget<ComposeMediaAddButton>(inlineFinder).iconSize!),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('compose-fixed-identity-bar')))
          .height,
      closeTo(45, 0.5),
    );
    expect(
      tester.getCenter(inlineFinder).dx,
      greaterThan(tester.getSize(find.byType(SquareComposePage)).width * 0.75),
    );
  });

  testWidgets('取消前立即保存最新文字，身份稍后完成也不丢失草稿', (tester) async {
    final identityService = _DelayedComposeIdentityService();
    final drafts = _RecordingDraftRepository();
    await tester.pumpWidget(
      _wrap(
        SquareComposePage(
          postType: SquarePostType.document,
          identityService: identityService,
          draftStore: drafts,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('document-text-field')),
      '尚未到防抖时间也必须保存的文字',
    );
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(drafts.saved, isEmpty);

    identityService.completer.complete(
      const SquareIdentityState(
        accountId:
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        cidNumber: 'CN220-CTZN2-100000001-2026',
        signMode: CitizenWalletSignMode.hot,
      ),
    );
    await tester.pumpAndSettle();
    expect(drafts.saved, hasLength(1));
    expect(drafts.saved.single.text, '尚未到防抖时间也必须保存的文字');
  });

  testWidgets('公文9张后顶部图片入口禁用，视频选中后顶部显示首帧入口', (tester) async {
    const image = SquareLocalMediaDraft(
      mediaKind: SquareMediaKind.image,
      path: '/tmp/missing-document-image.jpg',
      fileName: 'image.jpg',
      contentType: 'image/jpeg',
      byteSize: 1,
    );
    const video = SquareLocalMediaDraft(
      mediaKind: SquareMediaKind.video,
      path: '/tmp/missing-video.mp4',
      fileName: 'video.mp4',
      contentType: 'video/mp4',
      byteSize: 1,
      durationSeconds: 10,
    );

    await tester.pumpWidget(
      _wrap(
        const SquareComposePage(
          postType: SquarePostType.document,
          identityService: _StaticComposeIdentityService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final documentState = tester.state<SquareDocumentComposeBodyState>(
      find.byType(SquareDocumentComposeBody),
    );
    documentState.restore(
      const SquareComposeDraft(
        draftId: 'document-draft',
        cidNumber: 'CN220-CTZN2-100000001-2026',
        postType: SquarePostType.document,
        text: '',
        media: [image, image, image, image, image, image, image, image, image],
        updatedAtMillis: 1,
      ),
    );
    await tester.pump();

    final imageAction = tester.widget<ComposeMediaAddButton>(
      find.byKey(const ValueKey('document-add-images')),
    );
    expect(imageAction.onPressed, isNull);
    expect(find.text('图片  9/9'), findsNothing);

    await tester.pumpWidget(
      _wrap(
        const SquareComposePage(
          postType: SquarePostType.video,
          identityService: _StaticComposeIdentityService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final videoState = tester.state<SquareVideoComposeBodyState>(
      find.byType(SquareVideoComposeBody),
    );
    videoState.restore(
      const SquareComposeDraft(
        draftId: 'video-draft',
        cidNumber: 'CN220-CTZN2-100000001-2026',
        postType: SquarePostType.video,
        text: '',
        media: [video],
        updatedAtMillis: 1,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('video-picker-thumbnail')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('video-picker')), findsNothing);
    expect(find.byKey(const ValueKey('video-local-preview')), findsOneWidget);
  });

  group('关注流', () {
    testWidgets('渲染服务端关注帖(公文+文章)，本地种子不混入', (tester) async {
      final feedSource = _KindFeedSource(
        following: [
          _seedPost(id: 'f1', text: '关注公文AA'),
          _seedPost(
            id: 'f2',
            text: '文章摘要',
            title: '关注文章BB',
            postType: SquarePostType.article,
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          SquareHomePage(
            identityService: _emptyIdentityService(),
            feedSource: feedSource,
            seedPosts: [_seedPost(id: 's1', text: '种子SS')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 推荐流(默认)：种子帖在。
      expect(find.text('种子SS'), findsOneWidget);

      // 关注流：只服务端 following 结果(公文+文章)，种子不混入。
      await tester.tap(find.text('关注'));
      await tester.pumpAndSettle();
      expect(find.text('关注公文AA'), findsOneWidget);
      expect(find.text('关注文章BB'), findsOneWidget);
      expect(find.text('种子SS'), findsNothing);
    });
  });

  testWidgets('信息流与后台通知会话快速失败时不产生未捕获异步异常', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SquareHomePage(
          identityService: _emptyIdentityService(),
          feedSource: _FakeSquareApiClient(),
          sessionProvider: _ThrowingSessionProvider(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);

    // 会话失败属通用故障(非未注册),维持原故障文案,不得误入注册引导。
    expect(find.text('广场内容加载失败'), findsOneWidget);
    expect(find.text('尚未注册'), findsNothing);
  });

  testWidgets('本机无绑定 → 仍由 Worker 判定未注册并显示统一注册引导', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SquareHomePage(
          identityService: _unregisteredIdentityService(),
          feedSource: _FakeSquareApiClient(),
          sessionProvider: _CidNotBoundSessionProvider(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 引导态呈现,假故障文案禁止出现。
    expect(find.text('尚未注册'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.text('广场内容加载失败'), findsNothing);
  });

  testWidgets('未注册(缓存未命中,Worker 判定 cid_not_bound) → 同一注册引导', (tester) async {
    // 默认 _NullIdentityCache = 缓存未命中,本地不武断,由 Worker 真源判定。
    await tester.pumpWidget(
      _wrap(
        SquareHomePage(
          identityService: _emptyIdentityService(),
          feedSource: _FakeSquareApiClient(),
          sessionProvider: _CidNotBoundSessionProvider(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('尚未注册'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.text('广场内容加载失败'), findsNothing);
  });

}
