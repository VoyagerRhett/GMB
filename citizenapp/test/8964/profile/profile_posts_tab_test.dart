import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/profile/user_profile_page.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';

import 'fake_profile.dart';

Widget _page(
  FakeProfileApi api, {
  bool withSession = true,
  bool isSelf = true,
  SquareSessionProvider? sessionProvider,
}) => MaterialApp(
  home: UserProfilePage(
    cidNumber: fakeSession().cidNumber,
    isSelf: isSelf,
    api: api,
    cache: FakeProfileCache(),
    sessionProvider:
        sessionProvider ??
        FakeSessionProvider(withSession ? fakeSession() : null),
    subscriptionService: _NullSubscriptionService(),
    viewerAccountLoader: () async => null,
  ),
);

class _NullSubscriptionService implements SubscriptionService {
  @override
  Future<MembershipDisplaySnapshot?> readDisplaySnapshot(
    String cidNumber,
  ) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedSessionProvider implements SquareSessionProvider {
  final Completer<SquareSession?> completer = Completer<SquareSession?>();
  int calls = 0;

  @override
  Future<SquareSession?> ensureSession() {
    calls++;
    return completer.future;
  }

  @override
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) async {
    final session = await ensureSession();
    return session == null
        ? const SquareSessionResolution(SquareSessionStatus.noWallet)
        : SquareSessionResolution(SquareSessionStatus.ready, session: session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RefreshingSessionProvider implements SquareSessionProvider {
  int refreshCalls = 0;

  SquareSession _session(String token) => SquareSession(
    sessionToken: token,
    cidNumber: fakeSession().cidNumber,
    bindingRevision: 1,
    accountId: kOwner,
    expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
  );

  @override
  Future<SquareSession?> ensureSession() async => _session('stale-token');

  @override
  Future<SquareSession?> refreshSession() async {
    refreshCalls++;
    return _session('fresh-token');
  }

  @override
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) async {
    final session = await (refresh ? refreshSession() : ensureSession());
    return SquareSessionResolution(SquareSessionStatus.ready, session: session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdentityUnavailableSessionProvider implements SquareSessionProvider {
  @override
  Future<SquareSessionResolution> resolveSession({
    bool refresh = false,
  }) async =>
      const SquareSessionResolution(SquareSessionStatus.identityUnavailable);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingAuthorPostsApi extends FakeProfileApi {
  _PendingAuthorPostsApi() : super(sampleProfile());

  final Completer<({List<SquarePost> posts, int? nextCursor})> completer =
      Completer();

  @override
  Future<({List<SquarePost> posts, int? nextCursor})> fetchAuthorPosts(
    String cidNumber, {
    SquarePostCategory? category,
    SquarePostType? postType,
    int limit = 20,
    int? cursor,
    SquareSession? session,
  }) => completer.future;
}

SquareLocalPost _localPost({
  String postId = 'local-1',
  String text = '本机保留的正文',
}) {
  final bytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schema': SquarePostStore.manifestSchema,
        'cid_number': fakeSession().cidNumber,
        'post_type': 'document',
        'text': text,
        'media_items': [
          {
            'media_kind': 'image',
            'file_name': 'photo.jpg',
            'content_type': 'image/jpeg',
            'byte_size': 123,
            'sha256': 'a' * 64,
          },
        ],
      }),
    ),
  );
  return SquareLocalPost(
    postId: postId,
    cidNumber: fakeSession().cidNumber,
    accountId: kOwner,
    postCategory: 'normal',
    postType: 'document',
    manifestBytes: bytes,
    contentHash: sha256.convert(bytes).toString(),
    storageReceiptId: 'receipt-1',
    chainBlock: 88,
    createdAt: 1700000000000,
    postState: SquarePostStore.publishedState,
  );
}

void main() {
  testWidgets('主页帖子未返回时直接显示内容区域且不使用整页转圈', (tester) async {
    final api = _PendingAuthorPostsApi();
    await tester.pumpWidget(_page(api, isSelf: false));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('profile-tab-posts')),
      findsOneWidget,
    );
    expect(find.text('正在读取内容'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-posts-load-progress')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    api.completer.complete((posts: const <SquarePost>[], nextCursor: null));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('profile-posts-load-progress')),
      findsNothing,
    );
  });
  testWidgets('posts tab renders normal author posts', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(),
      authorPosts: [samplePost(id: 'n1', text: '普通帖子内容')],
    );
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();

    expect(find.text('普通帖子内容'), findsOneWidget);
  });

  testWidgets('campaign tab filters to campaign posts', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(),
      authorPosts: [
        samplePost(id: 'n1', text: '普通内容'),
        samplePost(
          id: 'c1',
          text: '竞选宣言内容',
          category: SquarePostCategory.campaign,
        ),
      ],
    );
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('profile-tab-campaign')),
    );
    await tester.pumpAndSettle();

    expect(find.text('竞选宣言内容'), findsOneWidget);
    expect(find.text('普通内容'), findsNothing);
  });

  testWidgets(
    'videos tab requests video posts before pagination and renders tiles',
    (tester) async {
      final api = FakeProfileApi(
        sampleProfile(),
        authorPosts: [
          samplePost(
            id: 'v1',
            postType: SquarePostType.video,
            media: const [
              SquareMediaItem(mediaKind: SquareMediaKind.video, url: ''),
            ],
          ),
        ],
      );
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('profile-tab-videos')),
      );
      await tester.pumpAndSettle();

      expect(api.authorPostTypes.last, SquarePostType.video);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsWidgets);
    },
  );

  testWidgets('articles tab renders article cards with title', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(),
      authorPosts: [
        samplePost(
          id: 'a1',
          postType: SquarePostType.article,
          title: '我的第一篇文章',
          text: '正文内容',
        ),
      ],
    );
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('profile-tab-articles')),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的第一篇文章'), findsOneWidget);
  });

  testWidgets(
    'posts tab includes text and images but excludes articles and videos',
    (tester) async {
      final api = FakeProfileApi(
        sampleProfile(),
        authorPosts: [
          samplePost(id: 'n1', text: '普通帖子正文'),
          samplePost(
            id: 'v1',
            text: '视频配文',
            postType: SquarePostType.video,
            media: const [
              SquareMediaItem(mediaKind: SquareMediaKind.video, url: ''),
            ],
          ),
          samplePost(
            id: 'a1',
            postType: SquarePostType.article,
            title: '文章标题',
            text: '文章正文',
          ),
        ],
      );
      await tester.pumpWidget(_page(api));
      await tester.pumpAndSettle();

      expect(find.text('普通帖子正文'), findsOneWidget);
      expect(find.text('视频配文'), findsNothing);
      expect(find.text('文章正文'), findsNothing);
      expect(api.authorPostTypes.first, SquarePostType.document);
    },
  );

  testWidgets('empty posts tab shows the empty label', (tester) async {
    await tester.pumpWidget(_page(FakeProfileApi(sampleProfile())));
    await tester.pumpAndSettle();

    expect(find.text('还没有公文'), findsOneWidget);
  });

  testWidgets('本人主页远端失败时仍展示本地正文并明确提示媒体已清理', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(),
      localPosts: [_localPost()],
      throwOnAuthorPosts: true,
    );

    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();

    expect(find.text('本机保留的正文'), findsOneWidget);
    expect(find.text('媒体已从云端清理，本机仅保留正文'), findsOneWidget);
    expect(find.text('加载失败，下拉重试'), findsNothing);
  });

  testWidgets('本人主页无法建立会话时仍从 CID 本地副本展示正文', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(),
      localPosts: [_localPost()],
      throwOnAuthorPosts: true,
    );

    await tester.pumpWidget(_page(api, withSession: false));
    await tester.pumpAndSettle();

    expect(api.localPostCalls, 1);
    expect(find.text('本机保留的正文'), findsOneWidget);
    expect(find.text('媒体已从云端清理，本机仅保留正文'), findsOneWidget);
    expect(find.text('加载失败，下拉重试'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('无会话的他人主页禁止读取本机本人副本', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(),
      localPosts: [_localPost()],
      throwOnAuthorPosts: true,
    );

    await tester.pumpWidget(_page(api, withSession: false, isSelf: false));
    await tester.pumpAndSettle();

    expect(api.localPostCalls, 0);
    expect(api.authorPostCalls, 0);
    expect(find.text('本机保留的正文'), findsNothing);
    expect(find.text('加载失败，下拉重试'), findsNothing);
    expect(find.text('请先添加钱包账户'), findsOneWidget);
    expect(find.text('需要钱包账户才能浏览主页'), findsNothing);
  });

  // 中文注释：本地钱包仍存在时，后端投影故障不能降级成“需要钱包账户”。
  testWidgets('身份投影不可用时主页不得误报需要钱包账户', (tester) async {
    final api = FakeProfileApi(sampleProfile(), throwOnAuthorPosts: true);

    await tester.pumpWidget(
      _page(
        api,
        isSelf: false,
        sessionProvider: _IdentityUnavailableSessionProvider(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前钱包身份尚未同步或绑定，请稍后重试'), findsOneWidget);
    expect(find.text('请先添加钱包账户'), findsNothing);
    expect(find.text('需要钱包账户才能浏览主页'), findsNothing);
  });

  testWidgets('首次会话仍在建立时不抢跑，Session 到达后当前帖子 Tab 自动加载', (tester) async {
    final provider = _DelayedSessionProvider();
    final api = FakeProfileApi(
      sampleProfile(),
      authorPosts: [samplePost(id: 'ready', text: '会话就绪后自动出现')],
    );

    await tester.pumpWidget(_page(api, sessionProvider: provider));
    await tester.pump();
    await tester.pump();

    expect(provider.calls, 1);
    expect(api.authorPostCalls, 0);
    expect(find.text('加载失败，下拉重试'), findsNothing);

    provider.completer.complete(fakeSession());
    await tester.pumpAndSettle();

    expect(api.authorPostCalls, 1);
    expect(find.text('会话就绪后自动出现'), findsOneWidget);
  });

  testWidgets('帖子请求 401 时只刷新一次 Session 并自动恢复', (tester) async {
    final provider = _RefreshingSessionProvider();
    final api = FakeProfileApi(
      sampleProfile(),
      authorPosts: [samplePost(id: 'retried', text: '刷新会话后出现')],
      unauthorizedAuthorPosts: 1,
    );

    await tester.pumpWidget(_page(api, sessionProvider: provider));
    await tester.pumpAndSettle();

    expect(provider.refreshCalls, 1);
    expect(api.authorPostCalls, 2);
    expect(api.authorPostSessions.last?.sessionToken, 'fresh-token');
    expect(find.text('刷新会话后出现'), findsOneWidget);
    expect(find.text('加载失败，下拉重试'), findsNothing);
  });

  testWidgets('同一 post_id 的 Worker 内容覆盖本地展示内容', (tester) async {
    final api = FakeProfileApi(
      sampleProfile(),
      localPosts: [_localPost(text: '本地旧展示')],
      authorPosts: [samplePost(id: 'local-1', text: 'Worker 最新展示')],
    );

    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();

    expect(find.text('Worker 最新展示'), findsOneWidget);
    expect(find.text('本地旧展示'), findsNothing);
  });
}
