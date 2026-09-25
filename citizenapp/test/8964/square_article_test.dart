import '../support/fake_citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';

import 'package:citizenapp/8964/compose/article/article_blocks.dart';
import 'package:citizenapp/8964/compose/article/article_compose_body.dart';
import 'package:citizenapp/8964/compose/compose_media_picker.dart';
import 'package:citizenapp/8964/compose/widgets/compose_media_widgets.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_upload_service.dart';
import 'package:citizenapp/8964/widgets/square_media_carousel.dart';

class _ArticleMediaPickerFake extends ImagePicker
    implements ComposeMediaPicker {
  _ArticleMediaPickerFake({
    this.cover,
    this.media = const <XFile>[],
    this.replacementImages = const <XFile>[],
  });

  final XFile? cover;
  final List<XFile> media;
  final List<XFile> replacementImages;
  int callCount = 0;
  int imageCallCount = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      cover;

  @override
  Future<List<XFile>> pickImages(BuildContext context, int maxImages) async {
    imageCallCount += 1;
    return replacementImages.take(maxImages).toList(growable: false);
  }

  @override
  Future<ComposeImageSelection?> pickImagesWithSelection(
    BuildContext context,
    int maxImages, {
    List<String> selectedPhotoManagerAssetIds = const <String>[],
  }) async {
    imageCallCount += 1;
    final selectedIds = selectedPhotoManagerAssetIds.toSet();
    final files = <XFile>[
      ...media.where(
        (file) =>
            file.mimeType?.startsWith('image/') == true &&
            selectedIds.contains(file.path),
      ),
      ...replacementImages,
    ].take(maxImages).toList(growable: false);
    return ComposeImageSelection(
      selected: [
        for (final file in files)
          ComposePickedMedia(
            file: file,
            mediaKind: SquareMediaKind.image,
            photoManagerAssetId: file.path,
          ),
      ],
    );
  }

  @override
  Future<List<ComposePickedMedia>> pickArticleMedia(
    BuildContext context,
  ) async {
    callCount += 1;
    return media
        .map(
          (file) => ComposePickedMedia(
            file: file,
            mediaKind: file.mimeType?.startsWith('video/') == true
                ? SquareMediaKind.video
                : SquareMediaKind.image,
            photoManagerAssetId: file.path,
          ),
        )
        .toList(growable: false);
  }
}

Future<SquareLocalMediaDraft> _buildDraft(
  XFile file,
  SquareMediaKind mediaKind,
) async =>
    SquareLocalMediaDraft(
      mediaKind: mediaKind,
      path: file.path,
      fileName: file.name,
      contentType:
          mediaKind == SquareMediaKind.image ? 'image/jpeg' : 'video/mp4',
      byteSize: 1,
      durationSeconds: mediaKind == SquareMediaKind.video ? 30 : null,
    );

Widget _articleEditor({
  required GlobalKey<SquareArticleComposeBodyState> key,
  required _ArticleMediaPickerFake picker,
  String initialText = '这是满足十个字的正文内容',
}) =>
    MaterialApp(
      home: Scaffold(
        body: SquareArticleComposeBody(
          key: key,
          initialTitle: '这是满足十个字的标题',
          initialText: initialText,
          imagePicker: picker,
          mediaPicker: picker,
          mediaDraftBuilder: _buildDraft,
        ),
      ),
    );

String? _validate({
  String title = '标题标题标题标题标题',
  bool cover = true,
  String body = '正文内容',
}) {
  return articleValidationError(title: title, hasCover: cover, body: body);
}

void main() {
  TestCitizenSdkHarness();
  group('articleValidationError', () {
    test('passes with valid title, cover and body', () {
      expect(_validate(), isNull);
    });

    test('rejects a title shorter than 10 chars', () {
      expect(_validate(title: '短标题'), '标题需 10–50 字');
    });

    test('rejects a title longer than 50 chars', () {
      expect(_validate(title: 'x' * 51), '标题需 10–50 字');
    });

    test('requires a cover image', () {
      expect(_validate(cover: false), '请选择 1 张首图');
    });

    test('requires non-empty body', () {
      expect(_validate(body: '   '), '正文不能为空');
    });

    test('rejects a body over 30000 chars', () {
      expect(_validate(body: 'x' * 30001), '正文不能超过 30000 字');
    });

    test('counts non-BMP body characters as one Unicode scalar', () {
      expect(_validate(body: '🌱' * 30000), isNull);
      expect(_validate(body: '🌱' * 30001), '正文不能超过 30000 字');
    });
  });

  group('CitizenApp 文章会员用量强校验', () {
    test('手机端解析服务端的档位与当前用量快照', () async {
      final api = SquareApiClient(
        baseUrl: 'https://square.test',
        httpClient: MockClient(
          (_) async => http.Response(
            '''{"active":true,"subscription_active":true,"membership":{"membership_level":"democracy","paid_until":200,"last_charged_at":100},"plans":[{"membership_level":"democracy","display_name":"民主会员","chat_file_max_bytes":1,"chat":{"text_enabled":true,"emoji_enabled":true,"sticker_enabled":true,"image_enabled":true,"voice_message_max_seconds":180,"video_message_max_seconds":180,"voice_call_enabled":true,"video_call_enabled":true},"document":{"text_max_chars":300,"image_quality":"hd","max_images":9},"video":{"text_max_chars":300,"video_quality":"hd","max_video_seconds":1800,"max_video_bytes":300000000},"article":{"title_min_chars":10,"title_max_chars":50,"body_max_chars":30000,"cover_quality":"hd","image_quality":"hd","max_images":100,"max_videos":3},"usage":{"monthly_images":1500,"monthly_video_seconds":60000,"active_uploads":2,"storage_bytes":1000000000000}}],"usage_state":{"period_start":100,"period_end":200,"image_count":12,"video_seconds":345,"active_uploads":1}}''',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final state = await api.fetchMembership(
        SquareSession(
          sessionToken: 'token',
          cidNumber: 'CN220-CTZN2-198805200-2026',
          bindingRevision: 1,
          accountId:
              '0x1111111111111111111111111111111111111111111111111111111111111111',
          expiresAt: 9999999999999,
          // MockClient 只验证响应解析，不校验设备请求签名头。
          signRequest: (_) async => 'test-device-signature',
        ),
      );
      expect(state.activePlan!.article.maxVideos, 3);
      expect(state.activePlan!.video.maxVideoSeconds, 1800);
      expect(state.activePlan!.video.maxVideoBytes, 300000000);
      expect(state.activePlan!.usage.monthlyVideoSeconds, 60000);
      expect(state.activePlan!.usage.storageBytes, 1000000000000);
      expect(state.usageState!.imageCount, 12);
      expect(state.usageState!.videoSeconds, 345);
      expect(state.usageState!.activeUploads, 1);
    });

    test('民主会员单篇允许3个视频但拒绝4个', () {
      expect(_validateUpload(videoCount: 3), isNull);
      expect(_validateUpload(videoCount: 4), '当前会员每篇文章最多插入 3 个视频');
    });

    test('首图计入单篇图片总数且图集每组最多9张', () {
      expect(_validateUpload(imageCount: 100), isNull);
      expect(_validateUpload(imageCount: 101), '文章图片总数不能超过 100 张');
      expect(
        _validateUpload(gallerySize: 10, imageCount: 11),
        '文章每个图集必须包含 1-9 张图片',
      );
    });

    test('每个段落不少于10字，并在手机端预检月度用量', () {
      expect(_validateUpload(textBlock: '不足十字'), '文章每个段落不少于 10 个字');
      expect(_validateUpload(usedImages: 1499, imageCount: 2), '当前会员本月图片可用量不足');
      expect(
        _validateUpload(videoCount: 1, usedVideoSeconds: 59980),
        '当前会员本月视频时长可用量不足',
      );
      expect(_validateUpload(activeUploads: 2), '当前会员活动上传数已达上限');
    });
  });

  group('文章发布编辑器', () {
    testWidgets('标题透明两行且硬限50字，媒体入口固定在段落右下角', (tester) async {
      final key = GlobalKey<SquareArticleComposeBodyState>();
      final picker = _ArticleMediaPickerFake(
        cover: XFile('/tmp/cover.jpg', mimeType: 'image/jpeg'),
      );
      await tester.pumpWidget(_articleEditor(key: key, picker: picker));

      await tester.enterText(
        find.byKey(const ValueKey('article-title-field')),
        '标' * 55,
      );
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('article-title-field')),
      );
      expect(field.controller!.text.characters.length, articleTitleMax);
      expect(find.text('50/50'), findsOneWidget);
      expect(find.byKey(const ValueKey('article-insert-image')), findsNothing);
      expect(find.byKey(const ValueKey('article-insert-video')), findsNothing);
      expect(
        find.byKey(const ValueKey('article-insert-media-0')),
        findsOneWidget,
      );
      final addMedia = find.byKey(const ValueKey('article-insert-media-0'));
      expect(find.byKey(const ValueKey('article-add-section')), findsNothing);
      final cover = find.byKey(const ValueKey('article-cover-picker'));
      final section = find.byKey(const ValueKey('article-section-0'));
      expect(cover, findsOneWidget);
      expect(
        tester.getCenter(addMedia).dx,
        greaterThan(tester.getSize(find.byType(Scaffold)).width * 0.75),
      );
      final mediaRightGap =
          tester.getTopRight(section).dx - tester.getTopRight(addMedia).dx;
      final mediaBottomGap = tester.getBottomRight(section).dy -
          tester.getBottomRight(addMedia).dy;
      // 段落 1px 边框属于框本身；按钮与右、下边框的视觉间距必须一致。
      expect(mediaRightGap, inInclusiveRange(0, 1));
      expect(mediaBottomGap, closeTo(mediaRightGap, 0.5));
      final titleField = tester.widget<TextField>(
        find.byKey(const ValueKey('article-title-field')),
      );
      expect(titleField.minLines, 1);
      expect(titleField.maxLines, 2);
      expect(titleField.decoration?.hintText, '请输入文章标题');
      expect(titleField.decoration?.filled, isFalse);
      expect(titleField.decoration?.fillColor, Colors.transparent);
      expect(titleField.decoration?.border, InputBorder.none);
      expect(
        tester.getCenter(cover).dx,
        greaterThan(tester
            .getCenter(find.byKey(
              const ValueKey('article-title-field'),
            ))
            .dx),
      );
      expect(
        tester.widget<ComposeMediaAddButton>(addMedia).iconSize,
        24,
      );
      expect(
          find.byKey(const ValueKey('article-title-divider')), findsOneWidget);
      final divider = find.byKey(const ValueKey('article-title-divider'));
      final bodyCounter = find.byKey(const ValueKey('article-body-counter'));
      final titleCounter = find.byKey(const ValueKey('article-title-counter'));
      expect(
        tester.getTopLeft(divider).dx,
        lessThan(tester.getTopLeft(bodyCounter).dx),
      );
      expect(
        tester.getTopRight(divider).dx,
        greaterThan(tester.getTopRight(titleCounter).dx),
      );
      expect(
        tester.getCenter(bodyCounter).dy,
        closeTo(
          tester.getCenter(titleCounter).dy,
          0.5,
        ),
      );
      final toolbar = find.byKey(const ValueKey('article-bottom-toolbar'));
      final connector =
          find.byKey(const ValueKey('article-section-connector-0'));
      expect(toolbar, findsOneWidget);
      expect(tester.getTopLeft(toolbar).dy,
          greaterThan(tester.getBottomLeft(connector).dy));
    });

    testWidgets('正文上滑只收起标题首图分隔线，下滑恢复且计数始终显示', (tester) async {
      final key = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(key: key, picker: _ArticleMediaPickerFake()),
      );
      for (var index = 0; index < 7; index++) {
        key.currentState!.addTextSection();
      }
      await tester.pump();

      final list = find.byKey(const ValueKey('article-sections-list'));
      final titleRegion = find.byKey(const ValueKey('article-title-region'));
      final bodyCounter = find.byKey(const ValueKey('article-body-counter'));
      final titleCounter = find.byKey(const ValueKey('article-title-counter'));
      expect(tester.getSize(titleRegion).height, greaterThan(0));

      await tester.drag(list, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.getSize(titleRegion).height, closeTo(0, 0.5));
      expect(tester.getSize(bodyCounter).height, greaterThan(0));
      expect(tester.getSize(titleCounter).height, greaterThan(0));

      await tester.drag(list, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(tester.getSize(titleRegion).height, greaterThan(0));
    });

    testWidgets('320宽度与放大字体下标题两行和首图入口不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final key = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(key: key, picker: _ArticleMediaPickerFake()),
      );
      await tester.enterText(
        find.byKey(const ValueKey('article-title-field')),
        '标题' * 25,
      );
      await tester.pump();

      final field = find.byKey(const ValueKey('article-title-field'));
      final cover = find.byKey(const ValueKey('article-cover-picker'));
      expect(tester.getSize(field).height, greaterThan(52));
      expect(tester.getTopRight(cover).dx, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });

    testWidgets('段落竖虚线随同组媒体高度自动伸长', (tester) async {
      final key = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(
          key: key,
          picker: _ArticleMediaPickerFake(
            media: [XFile('/tmp/connector.jpg', mimeType: 'image/jpeg')],
          ),
        ),
      );
      final connector =
          find.byKey(const ValueKey('article-section-connector-0'));
      final textOnlyHeight = tester.getSize(connector).height;

      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();

      expect(tester.getSize(connector).height, greaterThan(textOnlyHeight));
    });

    testWidgets('一次选择多图生成一个可滑动图集并可逐张删除', (tester) async {
      final key = GlobalKey<SquareArticleComposeBodyState>();
      final picker = _ArticleMediaPickerFake(
        cover: XFile('/tmp/cover.jpg', mimeType: 'image/jpeg'),
        media: [
          XFile('/tmp/1.jpg', mimeType: 'image/jpeg'),
          XFile('/tmp/2.jpg', mimeType: 'image/jpeg'),
          XFile('/tmp/3.jpg', mimeType: 'image/jpeg'),
        ],
      );
      await tester.pumpWidget(_articleEditor(key: key, picker: picker));

      await key.currentState!.pickCover();
      await tester.pumpAndSettle();
      expect(key.currentState!.isContentValid, isTrue);
      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();

      expect(picker.callCount, 1);
      expect(find.byType(SquareMediaCarousel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('square-media-carousel-dot-2')),
        findsOneWidget,
      );
      final firstGallery = key.currentState!.snapshot().contentSections!.first;
      expect(
        firstGallery['gallery_media_indices'],
        orderedEquals([1, 2, 3]),
      );

      final removeButton = find.byWidgetPredicate(
        (widget) =>
            widget is ComposeMediaRemoveButton && widget.tooltip == '删除图片',
      );
      expect(removeButton, findsOneWidget);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('square-media-carousel-dot-2')),
        findsNothing,
      );
      final reducedGallery =
          key.currentState!.snapshot().contentSections!.first;
      expect(reducedGallery['gallery_media_indices'], orderedEquals([1, 2]));
      expect(picker.imageCallCount, 0);
    });

    testWidgets('轻点已有图集原位替换，横滑不打开相册且保留段落文本', (tester) async {
      final key = GlobalKey<SquareArticleComposeBodyState>();
      final picker = _ArticleMediaPickerFake(
        media: [
          XFile('/tmp/old-1.jpg', mimeType: 'image/jpeg'),
          XFile('/tmp/old-2.jpg', mimeType: 'image/jpeg'),
        ],
        replacementImages: [
          XFile('/tmp/new-1.jpg', mimeType: 'image/jpeg'),
          XFile('/tmp/new-2.jpg', mimeType: 'image/jpeg'),
          XFile('/tmp/new-3.jpg', mimeType: 'image/jpeg'),
        ],
      );
      await tester.pumpWidget(_articleEditor(key: key, picker: picker));
      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();

      final gallery = find.byKey(const ValueKey('article-replace-gallery-0'));
      final before = key.currentState!.snapshot();
      final beforeDelta = before.contentSections!.single['text_delta'];
      expect(before.media.map((item) => item.path), [
        '/tmp/old-1.jpg',
        '/tmp/old-2.jpg',
      ]);

      await tester.drag(gallery, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(picker.imageCallCount, 0);

      await tester.tap(gallery);
      await tester.pumpAndSettle();
      final replaced = key.currentState!.snapshot();
      expect(picker.imageCallCount, 1);
      expect(replaced.contentSections, hasLength(1));
      expect(replaced.contentSections!.single['text_delta'], beforeDelta);
      // 重新打开相册时原图保持选中，用户可在此基础上继续添加。
      expect(replaced.media.map((item) => item.path), [
        '/tmp/old-1.jpg',
        '/tmp/old-2.jpg',
        '/tmp/new-1.jpg',
        '/tmp/new-2.jpg',
        '/tmp/new-3.jpg',
      ]);
      expect(
        replaced.contentSections!.single['gallery_media_indices'],
        orderedEquals([0, 1, 2, 3, 4]),
      );
    });

    testWidgets('重新选择图集时取消保持原图集', (tester) async {
      final key = GlobalKey<SquareArticleComposeBodyState>();
      final picker = _ArticleMediaPickerFake(
        media: [XFile('/tmp/keep.jpg', mimeType: 'image/jpeg')],
      );
      await tester.pumpWidget(_articleEditor(key: key, picker: picker));
      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();

      final before = key.currentState!.snapshot();
      await tester.tap(
        find.byKey(const ValueKey('article-replace-gallery-0')),
      );
      await tester.pumpAndSettle();

      expect(picker.imageCallCount, 1);
      expect(key.currentState!.snapshot().media.single.path,
          before.media.single.path);
      expect(
          key.currentState!.snapshot().contentSections, before.contentSections);
    });

    testWidgets('图片视频混选直接拒绝，多次选择单视频保留多个视频块', (tester) async {
      final mixedKey = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(
          key: mixedKey,
          picker: _ArticleMediaPickerFake(
            media: [
              XFile('/tmp/image.jpg', mimeType: 'image/jpeg'),
              XFile('/tmp/video.mp4', mimeType: 'video/mp4'),
            ],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();
      expect(find.text('一次只能选择 1 个视频，或 1–9 张图片'), findsOneWidget);
      expect(mixedKey.currentState!.snapshot().media, isEmpty);

      final videoKey = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(
          key: videoKey,
          picker: _ArticleMediaPickerFake(
            media: [XFile('/tmp/video.mp4', mimeType: 'video/mp4')],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();
      videoKey.currentState!.addTextSection();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -220));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('article-insert-media-1')));
      await tester.pumpAndSettle();
      expect(
        videoKey.currentState!.snapshot().contentSections!.where(
              (section) => section['video_media_index'] != null,
            ),
        hasLength(2),
      );
    });

    testWidgets('段落不足10字时标记并聚焦', (tester) async {
      final key = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(
          key: key,
          picker: _ArticleMediaPickerFake(),
          initialText: '不足十字',
        ),
      );

      expect(key.currentState!.collect().error, '文章每个段落不少于 10 个字');
      expect(key.currentState!.isContentValid, isFalse);
      await tester.pump();
      expect(find.text('输入内容后至少需要 10 个字'), findsOneWidget);
      expect(tester.testTextInput.hasAnyClients, isTrue);
    });

    testWidgets('删除媒体时有文字保留段落，空文字删除所属段落', (tester) async {
      final textKey = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(
          key: textKey,
          picker: _ArticleMediaPickerFake(
            media: [XFile('/tmp/one.jpg', mimeType: 'image/jpeg')],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ComposeMediaRemoveButton));
      await tester.pumpAndSettle();
      final kept = textKey.currentState!.snapshot();
      expect(kept.contentSections, hasLength(1));
      expect(kept.contentSections!.single['gallery_media_indices'], isNull);

      final emptyKey = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(
          key: emptyKey,
          initialText: '',
          picker: _ArticleMediaPickerFake(
            media: [XFile('/tmp/empty.jpg', mimeType: 'image/jpeg')],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ComposeMediaRemoveButton));
      await tester.pumpAndSettle();
      expect(emptyKey.currentState!.snapshot().contentSections, isEmpty);
    });

    testWidgets('左滑有文字段落二次确认，确认后连同媒体删除', (tester) async {
      final key = GlobalKey<SquareArticleComposeBodyState>();
      await tester.pumpWidget(
        _articleEditor(
          key: key,
          picker: _ArticleMediaPickerFake(
            media: [XFile('/tmp/swipe.jpg', mimeType: 'image/jpeg')],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('article-insert-media-0')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Dismissible).first, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('删除这一段？'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      final snapshot = key.currentState!.snapshot();
      expect(snapshot.contentSections, isEmpty);
      expect(snapshot.media, isEmpty);
    });
  });
}

String? _validateUpload({
  int imageCount = 1,
  int videoCount = 0,
  int gallerySize = 0,
  int usedImages = 0,
  int usedVideoSeconds = 0,
  int activeUploads = 0,
  String textBlock = '这是满足十个字的正文内容',
}) {
  final media = <SquareLocalMediaDraft>[
    for (var index = 0; index < imageCount; index++) _image(index),
    for (var index = 0; index < videoCount; index++) _video(index),
  ];
  final bodyIndices = [for (var index = 1; index < imageCount; index++) index];
  final galleries = gallerySize > 0
      ? [bodyIndices.take(gallerySize).toList()]
      : [
          for (var start = 0; start < bodyIndices.length; start += 9)
            bodyIndices.skip(start).take(9).toList(),
        ];
  return validateSquarePostContent(
    postType: SquarePostType.article,
    title: '这是满足十个字的文章标题',
    text: textBlock,
    mediaDrafts: media,
    contentSections: [
      {
        'text_delta': [
          {'insert': textBlock},
          {'insert': '\n'},
        ],
        if (galleries.isNotEmpty && galleries.first.isNotEmpty)
          'gallery_media_indices': galleries.first,
      },
      for (final indices in galleries.skip(1))
        {
          'text_delta': [
            {'insert': textBlock},
            {'insert': '\n'},
          ],
          'gallery_media_indices': indices,
        },
      for (var index = 0; index < videoCount; index++)
        {
          'text_delta': [
            {'insert': textBlock},
            {'insert': '\n'},
          ],
          'video_media_index': imageCount + index,
        },
    ],
    plan: _democracyPlan,
    usageState: SquareMembershipUsageState(
      periodStart: 1,
      periodEnd: 2,
      imageCount: usedImages,
      videoSeconds: usedVideoSeconds,
      activeUploads: activeUploads,
    ),
  );
}

SquareLocalMediaDraft _image(int index) => SquareLocalMediaDraft(
      mediaKind: SquareMediaKind.image,
      path: '/tmp/$index.jpg',
      fileName: '$index.jpg',
      contentType: 'image/jpeg',
      byteSize: 100,
    );

SquareLocalMediaDraft _video(int index) => SquareLocalMediaDraft(
      mediaKind: SquareMediaKind.video,
      path: '/tmp/$index.mp4',
      fileName: '$index.mp4',
      contentType: 'video/mp4',
      byteSize: 100,
      durationSeconds: 30,
    );

const _democracyPlan = SquareMembershipPlan(
  membershipLevel: 'democracy',
  displayName: '民主会员',
  chatFileMaxBytes: 1,
  chat: SquareChatQuota(
    textEnabled: true,
    emojiEnabled: true,
    stickerEnabled: true,
    imageEnabled: true,
    voiceMessageMaxSeconds: 180,
    videoMessageMaxSeconds: 180,
    voiceCallEnabled: true,
    videoCallEnabled: true,
  ),
  document: SquareDocumentQuota(
    textMaxChars: 300,
    imageQuality: 'hd',
    maxImages: 9,
  ),
  video: SquareVideoQuota(
    textMaxChars: 300,
    videoQuality: 'hd',
    maxVideoSeconds: 1800,
    maxVideoBytes: 1024,
  ),
  article: SquareArticleQuota(
    titleMinChars: 10,
    titleMaxChars: 50,
    bodyMaxChars: 30000,
    coverQuality: 'hd',
    imageQuality: 'hd',
    maxImages: 100,
    maxVideos: 3,
  ),
  usage: SquareMembershipUsageQuota(
    monthlyImages: 1500,
    monthlyVideoSeconds: 60000,
    activeUploads: 2,
    storageBytes: 1000000000000,
  ),
);
