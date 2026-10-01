import 'package:flutter/material.dart';

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:citizenapp/8964/services/square_media_store.dart';
import 'package:citizenapp/isar/social_isar.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';

import '../profile/fake_profile.dart' as profile_fixtures;
import '../../support/isar_test_env.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/widgets/square_article_card.dart';
import 'package:citizenapp/8964/widgets/square_media_grid.dart';
import 'package:citizenapp/8964/widgets/square_post_card.dart';

/// 仅范围适配测试使用真实本机连接，避免Flutter测试绑定的网络占位响应。
class _LoopbackHttp extends HttpOverrides {}

SquareMediaItem _img({int? w, int? h}) => SquareMediaItem(
  mediaKind: SquareMediaKind.image,
  // 空 url → tile 走占位图标，测试不触网。
  url: '',
  width: w,
  height: h,
);

SquareMediaItem _video({int? w, int? h}) => SquareMediaItem(
  mediaKind: SquareMediaKind.video,
  url: '',
  coverUrl: '',
  width: w,
  height: h,
);

SquarePost _post({
  SquarePostCategory category = SquarePostCategory.normal,
  SquarePostType postType = SquarePostType.document,
  String? title,
  String text = '正文',
  List<SquareMediaItem> media = const [],
  String? campaignPosition,
  String? identityLevel = 'voting',
  bool isLocal = false,
}) {
  return SquarePost(
    postId: 'p1',
    isLocal: isLocal,
    author: SquareAuthor(
      accountId:
          '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      displayName: '林正华',
      cidNumber: isLocal ? profile_fixtures.sampleProfile().cidNumber : null,
      identityLevel: identityLevel,
    ),
    postCategory: category,
    postType: postType,
    title: title,
    text: text,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    mediaItems: media,
    campaignPosition: campaignPosition,
  );
}

Future<void> _pump(WidgetTester tester, Widget child, {double textScale = 1}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SizedBox(width: 360, child: child),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();

  Future<SquareMediaItem> saveMedia(
    Uint8List bytes, {
    bool video = true,
  }) async {
    const cid = 'CN001-CTZN-000000001-2026';
    final hash = sha256.convert(bytes).toString();
    const store = SquareMediaStore();
    await store.saveStream(
      SquareStoredMedia(
        cidNumber: cid,
        mediaId: hash,
        mediaKind: video ? 'video' : 'image',
        contentType: video ? 'video/mp4' : 'image/png',
        byteSize: bytes.length,
        sha256: hash,
      ),
      Stream.value(bytes),
    );
    await store.attach(
      SquareMediaReference(
        cidNumber: cid,
        mediaId: hash,
        contentKind: 'post',
        contentId: 'post',
        mediaIndex: 0,
        mediaRole: 'main',
      ),
    );
    return SquareMediaItem(
      mediaKind: video ? SquareMediaKind.video : SquareMediaKind.image,
      url: '',
      cidNumber: cid,
      postId: 'post',
      mediaIndex: 0,
    );
  }

  test('本机视频Range跨块读取、HEAD、后缀、非法范围与路径隔离', () async {
    final bytes = Uint8List.fromList(
      List.generate(SquareMediaStore.chunkSize + 17, (i) => i % 251),
    );
    final item = await saveMedia(bytes);
    await (await SocialIsar.instance.db()).close();
    await HttpOverrides.runWithHttpOverrides(() async {
      final source = await SquareLocalVideoSource.open(item);
      final client = HttpClient();
      try {
        final request = await client.getUrl(source.uri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=1048570-1048580');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(
          await response.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          ),
          bytes.sublist(1048570, 1048581),
        );
        final head = await (await client.openUrl('HEAD', source.uri)).close();
        expect(head.contentLength, bytes.length);
        await head.drain<void>();
        final suffixRequest = await client.getUrl(source.uri);
        suffixRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=-3');
        final suffix = await suffixRequest.close();
        expect(
          await suffix.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
          bytes.sublist(bytes.length - 3),
        );
        for (final range in [
          'bytes=99999999-',
          'bytes=4-2',
          'bytes=0-1,3-4',
          'bytes=-0',
        ]) {
          final invalid = await client.getUrl(source.uri);
          invalid.headers.set(HttpHeaders.rangeHeader, range);
          final result = await invalid.close();
          expect(result.statusCode, 416);
          await result.drain<void>();
        }
        final other = await (await client.getUrl(
          source.uri.replace(path: '/unknown'),
        )).close();
        expect(other.statusCode, 404);
        await other.drain<void>();
        final origin = await client.getUrl(source.uri);
        origin.headers.set('origin', 'https://example.com');
        final denied = await origin.close();
        expect(denied.statusCode, 404);
        await denied.drain<void>();
        final uri = source.uri;
        await source.close();
        await expectLater(
          () async => (await client.getUrl(uri)).close(),
          throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
        );
      } finally {
        client.close(force: true);
        await source.close();
      }
    }, _LoopbackHttp());
  });

  test('本机播放拒绝其他CID及未保存视频，不降级到远端URL', () async {
    await saveMedia(Uint8List.fromList([1, 2, 3]));
    const other = SquareMediaItem(
      mediaKind: SquareMediaKind.video,
      url: 'https://example.com/video',
      cidNumber: 'CN002-CTZN-000000002-2026',
      postId: 'post',
      mediaIndex: 0,
    );
    await expectLater(SquareLocalVideoSource.open(other), throwsStateError);
  });

  test('本机视频读取损坏首块中止连接，不返回成功的完整媒体', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final item = await saveMedia(bytes);
    await SocialIsar.instance.writeTxn((db) async {
      final row = await db.squareMediaChunkEntitys
          .getByCidNumberMediaIdChunkIndex(
            item.cidNumber!,
            sha256.convert(bytes).toString(),
            0,
          );
      row!.chunkBytes = [9, 2, 3];
      await db.squareMediaChunkEntitys.put(row);
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      final source = await SquareLocalVideoSource.open(item);
      final client = HttpClient();
      try {
        await expectLater(
          () async => (await client.getUrl(source.uri)).close(),
          throwsA(anyOf(isA<HttpException>(), isA<SocketException>())),
        );
      } finally {
        client.close(force: true);
        await source.close();
      }
    }, _LoopbackHttp());
  });

  testWidgets('本人帖子头部从UserIsar读取公开昵称，不使用远端头像', (tester) async {
    await tester.runAsync(
      () => const CitizenProfileCache().write(
        profile_fixtures.sampleProfile(displayName: '数据库作者昵称'),
      ),
    );
    await _pump(
      tester,
      SquarePostCard(
        post: _post(isLocal: true),
        avatarUrl: 'https://example.com/forbidden',
      ),
    );
    for (var i = 0; i < 30 && find.text('数据库作者昵称').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.text('数据库作者昵称'), findsOneWidget);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is NetworkImage),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('数据库图片使用MemoryImage，缺失媒体没有NetworkImage', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQAAAABJRU5ErkJggg==',
    );
    final item = await tester.runAsync(() => saveMedia(png, video: false));
    await _pump(tester, SquareMediaImage(item: item!));
    for (var i = 0; i < 20 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    await _pump(
      tester,
      const SquareMediaImage(
        item: SquareMediaItem(
          mediaKind: SquareMediaKind.image,
          url: 'https://example.com/no-fallback',
          cidNumber: 'CN002-CTZN-000000002-2026',
          postId: 'missing',
          mediaIndex: 0,
        ),
      ),
    );
    for (var i = 0; i < 20 && find.text('本地尚未保存媒体').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.text('本地尚未保存媒体'), findsOneWidget);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is NetworkImage),
      isEmpty,
    );
  });
  group('SquareMediaItem.isPortrait', () {
    test('高大于宽为竖屏', () {
      expect(_img(w: 1080, h: 1920).isPortrait, isTrue);
    });
    test('宽不小于高为横屏', () {
      expect(_img(w: 1920, h: 1080).isPortrait, isFalse);
      expect(_img(w: 1000, h: 1000).isPortrait, isFalse);
    });
    test('宽高缺失按横屏兜底', () {
      expect(_img().isPortrait, isFalse);
    });
  });

  group('SquareMediaGrid 公文照片唯一布局', () {
    testWidgets('单张横图为 16:9', (tester) async {
      await _pump(
        tester,
        SquareMediaGrid(mediaItems: [_img(w: 1920, h: 1080)]),
      );
      expect(find.byType(SquareMediaTile), findsOneWidget);
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
      expect(ar.aspectRatio, closeTo(16 / 9, 0.001));
    });

    testWidgets('单张竖图仍固定为 16:9', (tester) async {
      await _pump(
        tester,
        SquareMediaGrid(mediaItems: [_img(w: 1080, h: 1920)]),
      );
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
      expect(ar.aspectRatio, closeTo(16 / 9, 0.001));
    });

    testWidgets('两张照片为两个 16:9 横向长方形且外圆内直', (tester) async {
      await _pump(
        tester,
        SquareMediaGrid(
          mediaItems: [_img(w: 1600, h: 1200), _img(w: 1600, h: 1200)],
        ),
      );
      expect(find.byType(SquareMediaTile), findsNWidgets(2));
      expect(find.textContaining('+'), findsNothing);
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
      expect(ar.aspectRatio, closeTo(32 / 9, 0.001));
      final tiles = tester
          .widgetList<SquareMediaTile>(find.byType(SquareMediaTile))
          .toList(growable: false);
      expect(tiles[0].radius.topLeft, const Radius.circular(12));
      expect(tiles[0].radius.bottomLeft, const Radius.circular(12));
      expect(tiles[0].radius.topRight, Radius.zero);
      expect(tiles[0].radius.bottomRight, Radius.zero);
      expect(tiles[1].radius.topLeft, Radius.zero);
      expect(tiles[1].radius.bottomLeft, Radius.zero);
      expect(tiles[1].radius.topRight, const Radius.circular(12));
      expect(tiles[1].radius.bottomRight, const Radius.circular(12));
      final mediaRow = tester.widget<Row>(
        find.descendant(
          of: find.byType(AspectRatio),
          matching: find.byType(Row),
        ),
      );
      expect((mediaRow.children[1] as SizedBox).width, 2);
    });

    testWidgets('四张照片只出前两张、第二张右下显示 +2', (tester) async {
      await _pump(
        tester,
        SquareMediaGrid(
          mediaItems: List.generate(4, (_) => _img(w: 1600, h: 1200)),
        ),
      );
      expect(find.byType(SquareMediaTile), findsNWidgets(2));
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('九张照片只出前两张、第二张右下显示 +7', (tester) async {
      await _pump(
        tester,
        SquareMediaGrid(
          mediaItems: List.generate(9, (_) => _img(w: 1080, h: 1920)),
        ),
      );
      expect(find.byType(SquareMediaTile), findsNWidgets(2));
      expect(find.text('+7'), findsOneWidget);
    });

    testWidgets('竖屏视频继续使用 3:4 封面', (tester) async {
      await _pump(
        tester,
        SquareMediaGrid(mediaItems: [_video(w: 1080, h: 1920)]),
      );
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
      expect(ar.aspectRatio, closeTo(3 / 4, 0.001));
    });
  });

  group('SquarePostCard 身份与动态流文字', () {
    testWidgets('竞选帖显示竞选药丸和岗位', (tester) async {
      await _pump(
        tester,
        SquarePostCard(
          post: _post(
            category: SquarePostCategory.campaign,
            identityLevel: 'candidate',
            campaignPosition: '市长候选人',
          ),
        ),
      );
      expect(find.text('竞选'), findsOneWidget);
      expect(find.textContaining('市长候选人'), findsOneWidget);
    });

    testWidgets('非竞选帖不显示竞选药丸', (tester) async {
      await _pump(tester, SquarePostCard(post: _post(identityLevel: 'voting')));
      expect(find.text('竞选'), findsNothing);
    });

    testWidgets('公文竖图不再走左图右文并固定为 16:9', (tester) async {
      await _pump(
        tester,
        SquarePostCard(
          post: _post(text: '竖图说明', media: [_img(w: 1080, h: 1920)]),
        ),
      );
      expect(find.byType(SquareMediaTile), findsOneWidget);
      expect(find.text('竖图说明'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(SquareMediaTile),
          matching: find.byType(Row),
        ),
        findsNothing,
      );
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio).first);
      expect(ar.aspectRatio, closeTo(16 / 9, 0.001));
    });

    testWidgets('公文超过三行才显示展开全文且点击进入详情', (tester) async {
      var opened = false;
      await _pump(
        tester,
        SquarePostCard(
          post: _post(
            text: List<String>.filled(12, '这是用于验证公文正文真实排版溢出的内容。').join(),
          ),
          onTap: () => opened = true,
        ),
      );
      expect(find.text('展开全文'), findsOneWidget);
      final body = tester.widget<Text>(find.byKey(const ValueKey('展开全文-text')));
      expect(body.maxLines, 3);
      await tester.tap(find.byKey(const ValueKey('展开全文-action')));
      expect(opened, isTrue);
    });

    testWidgets('公文未超过三行不显示展开全文', (tester) async {
      await _pump(tester, SquarePostCard(post: _post(text: '短公文正文')));
      expect(find.text('展开全文'), findsNothing);
    });

    testWidgets('系统字体放大后仍按真实三行判断公文溢出', (tester) async {
      await _pump(
        tester,
        SquarePostCard(
          post: _post(text: List<String>.filled(5, '字体放大后按真实排版判断。').join()),
        ),
        textScale: 2,
      );
      expect(find.text('展开全文'), findsOneWidget);
    });

    testWidgets('视频封面在配文上方，超过两行显示展开', (tester) async {
      await _pump(
        tester,
        SquarePostCard(
          post: _post(
            postType: SquarePostType.video,
            text: List<String>.filled(10, '这是用于验证视频配文真实排版溢出的内容。').join(),
            media: [_video(w: 1920, h: 1080)],
          ),
        ),
      );
      expect(find.text('展开'), findsOneWidget);
      final body = tester.widget<Text>(find.byKey(const ValueKey('展开-text')));
      expect(body.maxLines, 2);
      expect(
        tester.getTopLeft(find.byType(SquareMediaGrid)).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('展开-text'))).dy),
      );
    });

    testWidgets('视频短配文不显示展开', (tester) async {
      await _pump(
        tester,
        SquarePostCard(
          post: _post(
            postType: SquarePostType.video,
            text: '短视频配文',
            media: [_video(w: 1920, h: 1080)],
          ),
        ),
      );
      expect(find.text('展开'), findsNothing);
      expect(find.byType(SquareVideo), findsNothing);
    });

    testWidgets('视频详情只在点击后初始化单版本 R2 播放器', (tester) async {
      await _pump(
        tester,
        SquarePostCard(
          post: _post(
            postType: SquarePostType.video,
            text: '详情配文',
            media: [_video(w: 1920, h: 1080)],
          ),
          displayMode: SquarePostCardDisplayMode.detail,
        ),
      );
      expect(find.byType(SquareVideo), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
    });

    testWidgets('详情模式显示完整正文且不显示展开入口', (tester) async {
      final text = List<String>.filled(12, '这是详情页必须完整显示的公文正文。').join();
      await _pump(
        tester,
        SquarePostCard(
          post: _post(text: text),
          displayMode: SquarePostCardDisplayMode.detail,
        ),
      );
      expect(find.text(text), findsOneWidget);
      expect(find.text('展开全文'), findsNothing);
    });
  });

  group('SquareArticleCard', () {
    testWidgets('标题、正文与强制 16:9 首图并存', (tester) async {
      await _pump(
        tester,
        SquareArticleCard(
          post: _post(
            postType: SquarePostType.article,
            title: '论社区自治的三个层次',
            text: '正文摘要',
            // 竖首图也强制横屏 16:9；非空 url 使封面块渲染（加载失败走占位）。
            media: const [
              SquareMediaItem(
                mediaKind: SquareMediaKind.image,
                url: 'https://example.com/cover.jpg',
                width: 1080,
                height: 1920,
              ),
            ],
          ),
        ),
      );
      expect(find.text('论社区自治的三个层次'), findsOneWidget);
      expect(find.text('正文摘要'), findsOneWidget);
      final ar = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(ar.aspectRatio, closeTo(16 / 9, 0.001));
    });

    testWidgets('异常本地副本缺少可用首图时不伪造占位首图', (tester) async {
      await _pump(
        tester,
        SquareArticleCard(
          post: _post(
            postType: SquarePostType.article,
            title: '纯文字文章',
            text: '正文',
          ),
        ),
      );
      expect(find.text('纯文字文章'), findsOneWidget);
    });
  });
}
