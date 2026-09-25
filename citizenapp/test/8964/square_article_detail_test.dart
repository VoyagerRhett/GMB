import '../support/fake_citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/pages/square_article_detail_page.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/widgets/square_media_carousel.dart';
import 'package:citizenapp/8964/widgets/article_rich_text_view.dart';

import 'profile/fake_profile.dart';

// 标题/正文实际出现才算加载完成；同时推进HTTP/SDK回包，不能用无限动画的settle判成功。
Future<void> _pumpArticle(WidgetTester tester) async {
  for (var attempt = 0; find.byType(ArticleRichTextView).evaluate().isEmpty && attempt < 50; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.byType(ArticleRichTextView), findsWidgets);
}

void main() {
  TestCitizenSdkHarness();
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
