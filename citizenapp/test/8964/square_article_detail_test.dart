import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/isar/social_isar.dart';

import '../support/fake_citizen_sdk.dart';
import '../support/isar_test_env.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';
import 'package:citizenapp/8964/services/square_local_post_presenter.dart';
import 'package:citizenapp/8964/pages/square_post_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/pages/square_article_detail_page.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/widgets/square_media_carousel.dart';
import 'package:citizenapp/8964/widgets/article_rich_text_view.dart';

import 'profile/fake_profile.dart';

// 标题/正文实际出现才算加载完成；同时推进HTTP/SDK回包，不能用无限动画的settle判成功。
Future<void> _pumpArticle(WidgetTester tester) async {
  for (
    var attempt = 0;
    find.byType(ArticleRichTextView).evaluate().isEmpty && attempt < 50;
    attempt++
  ) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.byType(ArticleRichTextView), findsWidgets);
}

void main() {
  TestCitizenSdkHarness();
  useIsolatedIsar();
  // Isar使用真实异步IO；在Widget虚拟时钟启动前打开数据库，避免把未完成的打开任务带入tearDown。
  setUp(() async {
    await UserIsar.instance.db();
    await SocialIsar.instance.db();
  });
  for (final type in ['document', 'article']) {
    testWidgets('本人$type详情离线读取数据库，刷新失败保留正文', (tester) async {
      var requests = 0;
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schema': SquarePostStore.manifestSchema,
            'cid_number': fakeSession().cidNumber,
            'post_type': type,
            'text': '本地已保存的详情正文',
            if (type == 'article') 'title': '本地文章标题',
            if (type == 'article')
              'content_sections': [
                {
                  'text_delta': [
                    {'insert': '本地已保存的详情正文\n'},
                  ],
                },
              ],
            'media_items': type == 'article'
                ? [
                    {
                      'media_kind': 'image',
                      'file_name': 'cover.png',
                      'content_type': 'image/png',
                      'byte_size': 1,
                      'sha256': 'a' * 64,
                    },
                  ]
                : [],
          }),
        ),
      );
      final local = SquareLocalPost(
        postId: 'local-detail',
        cidNumber: fakeSession().cidNumber,
        accountId: kOwner,
        postCategory: 'normal',
        postType: type,
        manifestBytes: bytes,
        contentHash: sha256.convert(bytes).toString(),
        storageReceiptId: 'receipt-local',
        chainBlock: 1,
        createdAt: 1000,
        postState: SquarePostStore.publishedState,
      );
      await tester.runAsync(() => const SquarePostStore().save(local));
      final post = const SquareLocalPostPresenter().present(local).post;
      final api = SquareApiClient(
        baseUrl: 'https://square.test',
        httpClient: MockClient((_) async {
          requests++;
          throw StateError('不应请求远端');
        }),
      );
      // 无会话：普通阅读仍能完成；主动刷新失败应保留原正文。
      final session = FakeSessionProvider(null);
      await tester.pumpWidget(
        MaterialApp(
          home: type == 'article'
              ? SquareArticleDetailPage(
                  post: post,
                  api: api,
                  sessionProvider: session,
                )
              : SquarePostDetailPage(
                  post: post,
                  api: api,
                  sessionProvider: session,
                ),
        ),
      );
      for (
        var i = 0;
        i < 50 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('本地已保存的详情正文', findRichText: true),
        findsWidgets,
      );
      expect(requests, 0);
      if (type == 'article') {
        // 正文先到达，封面读库仍可能在进行；等到缺图终态再刷新和销毁页面。
        for (
          var attempt = 0;
          attempt < 100 && find.text('本地尚未保存媒体').evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text('本地尚未保存媒体'), findsOneWidget);
      }
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('刷新失败，已保留本地内容'), findsOneWidget);
      expect(
        find.textContaining('本地已保存的详情正文', findRichText: true),
        findsWidgets,
      );
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('renders the article title and body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SquareArticleDetailPage(
          post: samplePost(
            postType: SquarePostType.article,
            title: '标题X',
            text: '正文内容正文内容正文',
          ),
          api: SquareApiClient(
            baseUrl: 'https://square.test',
            httpClient: MockClient(
              (request) async => http.Response(
                '''{"ok":true,"post":{"post_id":"p1","account_id":"$kOwner","cid_number":"CN001-CTZN-000000001-2026","post_category":"normal","post_type":"article","title":"标题X","text":"正文内容正文内容正文","content_sections":[{"text_delta":[{"insert":"正文内容正文内容正文"},{"insert":"\\n"}]}],"content_hash":"${List<String>.filled(64, '1').join()}","storage_receipt_id":"sqr_1","chain_block":1,"created_at":1000,"post_state":"published","media_items":[{"media_kind":"image","url":"https://media.test/cover.jpg"}]}}''',
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          ),
          sessionProvider: FakeSessionProvider(fakeSession()),
        ),
      ),
    );
    await _pumpArticle(tester);

    expect(find.text('标题X'), findsOneWidget);
    expect(find.byType(ArticleRichTextView), findsOneWidget);
  });

  testWidgets('公开文章按块保留多图轮播关系和多个视频', (tester) async {
    final hash = List<String>.filled(64, '2').join();
    await tester.pumpWidget(
      MaterialApp(
        home: SquareArticleDetailPage(
          post: samplePost(
            postType: SquarePostType.article,
            title: '图集文章',
            text: '这是满足十个字的正文内容',
          ),
          api: SquareApiClient(
            baseUrl: 'https://square.test',
            httpClient: MockClient(
              (request) async => http.Response(
                '''{"ok":true,"post":{"post_id":"p2","account_id":"$kOwner","cid_number":"CN001-CTZN-000000001-2026","post_category":"normal","post_type":"article","title":"图集文章","text":"这是满足十个字的正文内容","content_sections":[{"text_delta":[{"insert":"图集前面的正文内容满足十字"},{"insert":"\\n"}],"gallery_media_indices":[1,2,3]},{"text_delta":[{"insert":"第一个视频正文内容满足十字"},{"insert":"\\n"}],"video_media_index":4},{"text_delta":[{"insert":"第二个视频正文内容满足十字"},{"insert":"\\n"}],"video_media_index":5}],"content_hash":"$hash","storage_receipt_id":"sqr_2","chain_block":2,"created_at":1000,"post_state":"published","media_items":[{"media_kind":"image","url":"https://media.test/cover.jpg"},{"media_kind":"image","url":"https://media.test/1.jpg"},{"media_kind":"image","url":"https://media.test/2.jpg"},{"media_kind":"image","url":"https://media.test/3.jpg"},{"media_kind":"video","url":"https://media.test/1.m3u8","thumbnail_url":"https://media.test/1.jpg"},{"media_kind":"video","url":"https://media.test/2.m3u8","thumbnail_url":"https://media.test/2.jpg"}]}}''',
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          ),
          sessionProvider: FakeSessionProvider(fakeSession()),
        ),
      ),
    );
    await _pumpArticle(tester);

    expect(find.byType(SquareMediaCarousel), findsOneWidget);
    expect(
      find.byKey(const ValueKey('square-media-carousel-dot-2')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_circle_fill_rounded), findsNWidgets(2));
  });
}
