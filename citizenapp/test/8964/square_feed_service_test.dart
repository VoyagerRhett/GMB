import '../support/fake_citizen_sdk.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';

// 发布会员体系后，`SquareApiClient._headers` 对带 session 的请求强制要求设备请求签名器，
// 缺失即抛「设备请求签名器缺失」。测试用固定假签名占位；MockClient 不校验签名头。
SquareSession _session() => SquareSession(
      sessionToken: 'sqs_test',
      cidNumber: "CN220-CTZN2-198805200-2026",
      bindingRevision: 1,
      accountId:
          '0x8888888888888888888888888888888888888888888888888888888888888888',
      expiresAt: 1800000000000,
      signRequest: (_) async => 'test-device-signature',
    );

void main() {
  TestCitizenSdkHarness();
  test('SquareApiClient 解析 Worker feed 内容和媒体元数据', () async {
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/square/feed/recommended');
        return http.Response(
          '''
          {
            "ok": true,
            "feed_kind": "recommended",
            "posts": [
              {
                "post_id": "sqp_001",
                "account_id": "0x0101010101010101010101010101010101010101010101010101010101010101",
                "cid_number": "CN001-CTZN-000000001-2026",
                "display_name": "林正华",
                "avatar_object_key": "profile/1111111111111111111111111111111111111111111111111111111111111111/avatar",
                "post_category": "campaign",
                "post_type": "document",
                "excerpt": "竞选公文摘要",
                "content_hash": "0x1111",
                "storage_receipt_id": "sqr_001",
                "chain_block": 88,
                "created_at": 1800000000000,
                "post_state": "published",
                "media_items": [
                  {
                    "media_kind": "image",
                    "object_key": "square/cid/posts/sqp_001/media/0/source.webp",
                    "derivative_kind": "thumbnail",
                    "derivative_object_key": "square/cid/posts/sqp_001/media/0/thumbnail.webp",
                    "asset_state": "ready",
                    "url": "https://media.crcfrcn.com/square/cid/posts/sqp_001/media/0/source.webp",
                    "thumbnail_url": "https://media.crcfrcn.com/square/cid/posts/sqp_001/media/0/thumbnail.webp",
                    "byte_size": 1024,
                    "width": 1080,
                    "height": 1920
                  }
                ]
              }
            ]
          }
          ''',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final posts = await client.fetchFeed(feedKind: SquareFeedKind.recommended);

    expect(posts, hasLength(1));
    expect(posts.first.postCategory, SquarePostCategory.campaign);
    expect(posts.first.text, '竞选公文摘要');
    expect(posts.first.author.cidNumber, 'CN001-CTZN-000000001-2026');
    // 真数据：作者展示名与头像键随 feed 回传并解析。
    expect(posts.first.author.displayName, '林正华');
    expect(posts.first.author.avatarObjectKey,
        'profile/1111111111111111111111111111111111111111111111111111111111111111/avatar');
    expect(posts.first.chainBlock, 88);
    expect(posts.first.mediaItems.single.mediaKind, SquareMediaKind.image);
    expect(posts.first.mediaItems.single.url,
        'https://media.crcfrcn.com/square/cid/posts/sqp_001/media/0/source.webp');
    expect(posts.first.mediaItems.single.coverUrl,
        'https://media.crcfrcn.com/square/cid/posts/sqp_001/media/0/thumbnail.webp');
    expect(posts.first.mediaItems.single.byteSize, 1024);
    // 横竖屏所需宽高解析：高>宽 → 竖屏。
    expect(posts.first.mediaItems.single.isPortrait, isTrue);
  });

  test('SquareApiClient 详情接口读取全文并保留 Feed 作者资料', () async {
    final summary = SquarePost(
      postId: 'sqp_detail',
      author: const SquareAuthor(
        accountId:
            '0x0101010101010101010101010101010101010101010101010101010101010101',
        cidNumber: 'CN001-CTZN-000000001-2026',
        displayName: '林正华',
      ),
      postCategory: SquarePostCategory.normal,
      postType: SquarePostType.article,
      title: '文章标题标题标题',
      text: '列表摘要',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1800000000000),
    );
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/square/posts/sqp_detail');
        return http.Response(
          jsonEncode({
            'ok': true,
            'post': {
              'post_id': 'sqp_detail',
              'account_id': summary.author.accountId,
              'cid_number': summary.author.cidNumber,
              'post_category': 'normal',
              'post_type': 'article',
              'title': '文章标题标题标题',
              'text': 'R2 规范全文',
              'content_sections': [
                {
                  'text_delta': [
                    {'insert': 'R2 规范全文满足十个字'},
                    {'insert': '\n'}
                  ]
                }
              ],
              'content_hash': List<String>.filled(64, '1').join(),
              'storage_receipt_id': 'sqr_detail',
              'chain_block': 88,
              'created_at': 1800000000000,
              'post_state': 'published',
              'media_items': [
                {
                  'media_kind': 'image',
                  'url': 'https://media.test/cover.jpg',
                  'width': 1920,
                  'height': 1080,
                }
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final detail = await client.fetchPostDetail(
      session: _session(),
      summary: summary,
    );

    expect(detail.text, 'R2 规范全文');
    expect(detail.contentSections, hasLength(1));
    expect(detail.author.displayName, '林正华');
  });

  test('SquareApiClient 拒绝缺少必填首图的文章 Feed', () async {
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'ok': true,
              'feed_kind': 'recommended',
              'posts': [
                {
                  'post_id': 'article_without_cover',
                  'account_id':
                      '0x0101010101010101010101010101010101010101010101010101010101010101',
                  'post_category': 'normal',
                  'post_type': 'article',
                  'title': '缺少首图的非法文章',
                  'excerpt': '这条数据不得作为正常文章进入动态流',
                  'created_at': 1800000000000,
                  'media_items': <Object>[],
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );

    await expectLater(
      client.fetchFeed(feedKind: SquareFeedKind.recommended),
      throwsA(
        isA<SquareApiException>().having(
          (error) => error.message,
          'message',
          '文章首图缺失',
        ),
      ),
    );
  });

  test('SquareApiConfig 只允许 HTTPS 或本地调试 HTTP', () {
    expect(
      SquareApiConfig.normalizeBaseUrl('https://square.example/'),
      'https://square.example',
    );
    expect(
      SquareApiConfig.normalizeBaseUrl('http://127.0.0.1:8787/'),
      'http://127.0.0.1:8787',
    );
    expect(
      () => SquareApiConfig.normalizeBaseUrl('http://square.example'),
      throwsUnsupportedError,
    );
  });

  test('SquareApiClient prepareUpload 发送内容形态和额度声明', () async {
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/square/uploads/prepare');
        expect(request.headers['authorization'], 'Bearer sqs_test');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('post_category'), isFalse);
        expect(body['post_type'], 'article');
        expect(body['title_length'], 12);
        expect(body['text_length'], 30000);
        return http.Response(
          jsonEncode({
            'ok': true,
            'upload_id': 'squ_test',
            'post_id': 'sqp_test',
            'storage_receipt_id': 'sqr_test',
            'expires_at': 1800000000000,
            'estimated_bytes': 1024,
            'manifest_object_key': 'square/accountId/posts/sqp/manifest.json',
            'manifest_upload_url': 'https://r2.test/manifest',
            'media_items': [
              {
                'media_kind': 'image',
                'content_type': 'image/webp',
                'byte_size': 1024,
                'object_key': 'square/cid/posts/sqp_test/media/0/source.webp',
                'upload_method': 'r2_put',
                'upload_url': 'https://upload.test/image',
                'upload_headers': {
                  'content-type': 'image/webp',
                  'content-length': '1024',
                },
                'derivative_kind': 'thumbnail',
                'derivative_object_key':
                    'square/cid/posts/sqp_test/media/0/thumbnail.webp',
                'derivative_byte_size': 256,
                'derivative_upload_url': 'https://upload.test/thumbnail',
                'derivative_upload_headers': {
                  'content-type': 'image/webp',
                  'content-length': '256',
                },
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final prepared = await client.prepareUpload(
      session: _session(),
      postType: SquarePostType.article,
      titleLength: 12,
      textLength: 30000,
      manifestHash: '11' * 32,
      manifestByteSize: 512,
      mediaItems: const [
        SquareUploadMediaRequest(
          mediaKind: SquareMediaKind.image,
          contentType: 'image/webp',
          byteSize: 1024,
          sha256:
              '1111111111111111111111111111111111111111111111111111111111111111',
          width: 320,
          height: 240,
          derivativeKind: 'thumbnail',
          derivativeContentType: 'image/webp',
          derivativeByteSize: 256,
          derivativeSha256:
              '2222222222222222222222222222222222222222222222222222222222222222',
        ),
      ],
    );

    expect(prepared.postId, 'sqp_test');
  });

  test('SquareApiClient 对 R2 临时 5xx 只重试当前文件上传', () async {
    final root = await Directory.systemTemp.createTemp('square_r2_retry_');
    final file = File('${root.path}/source.webp');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    var attempts = 0;
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        attempts += 1;
        expect(request.method, 'PUT');
        expect(request.bodyBytes, const [1, 2, 3, 4]);
        return http.Response('', attempts == 1 ? 503 : 200);
      }),
    );
    try {
      await client.uploadMediaAsset(
        upload: const SquarePreparedMediaUpload(
          mediaKind: SquareMediaKind.image,
          contentType: 'image/webp',
          byteSize: 4,
          objectKey: 'square/cid/posts/sqp_test/media/0/source.webp',
          uploadMethod: 'r2_put',
          uploadUrl: 'https://upload.test/source.webp',
          uploadHeaders: <String, String>{
            'content-type': 'image/webp',
            'content-length': '4',
          },
          derivativeKind: 'thumbnail',
          derivativeByteSize: 1,
          derivativeObjectKey:
              'square/cid/posts/sqp_test/media/0/thumbnail.webp',
          derivativeUploadUrl: 'https://upload.test/thumbnail.webp',
          derivativeUploadHeaders: <String, String>{},
        ),
        filePath: file.path,
      );
      expect(attempts, 2);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('SquareApiClient deletePost 使用登录态删除指定内容', () async {
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/square/posts/sqp_old');
        expect(request.headers['authorization'], 'Bearer sqs_test');
        return http.Response(
          jsonEncode({'ok': true, 'post_id': 'sqp_old'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await client.deletePost(
      session: _session(),
      postId: 'sqp_old',
    );
  });

  test('SquareApiClient 严格解析本人副本原始字节并携带设备请求证明', () async {
    final manifestBytes = utf8.encode(jsonEncode({
      'schema': 'citizenapp.square.post',
      'cid_number': _session().cidNumber,
      'post_type': 'document',
      'text': '本人原始正文',
      'media_items': const <Object>[],
    }));
    final contentHash = sha256.convert(manifestBytes).toString();
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/square/posts/self');
        expect(request.url.queryParameters['limit'], '5');
        expect(request.headers['authorization'], 'Bearer sqs_test');
        expect(request.headers['x-device-signature'], isNotEmpty);
        return http.Response(
          jsonEncode({
            'ok': true,
            'items': [
              {
                'post_id': 'sqp_self',
                'cid_number': _session().cidNumber,
                'account_id': _session().accountId,
                'post_category': 'normal',
                'post_type': 'document',
                'manifest_bytes_base64': base64Encode(manifestBytes),
                'content_hash': contentHash,
                'storage_receipt_id': 'sqr_self',
                'chain_block': 88,
                'created_at': 1800000000000,
                'post_state': 'published',
              }
            ],
            'next_cursor': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final page = await client.fetchSelfPublishedPostCopies(
      session: _session(),
    );

    expect(page.items.single.manifestBytes, orderedEquals(manifestBytes));
    expect(page.items.single.contentHash, contentHash);
    expect(page.items.single.createdAt, 1800000000000);
    expect(page.nextCursor, isNull);
  });

  test('SquareApiClient 本人副本任一条字段漂移时拒绝整页', () async {
    final client = SquareApiClient(
      baseUrl: 'https://square.test',
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'ok': true,
              'items': [
                {
                  'post_id': 'sqp_wrong',
                  'cid_number': 'OTHER-CID',
                  'account_id': _session().accountId,
                  'post_category': 'normal',
                  'post_type': 'document',
                  'manifest_bytes_base64': 'e30=',
                  'content_hash': '11' * 32,
                  'storage_receipt_id': 'sqr_wrong',
                  'chain_block': 88,
                  'created_at': 1800000000000,
                  'post_state': 'published',
                }
              ],
              'next_cursor': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );

    await expectLater(
      client.fetchSelfPublishedPostCopies(session: _session()),
      throwsA(isA<SquareApiException>()),
    );
  });
}
