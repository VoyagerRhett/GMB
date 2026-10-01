import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/square_models.dart';

SquareLocalMediaDraft _media(SquareMediaKind kind, String name) =>
    SquareLocalMediaDraft(
      mediaKind: kind,
      path: '/temporary/$name',
      mediaId: 'stored-$name',
      fileName: name,
      contentType: kind == SquareMediaKind.video ? 'video/mp4' : 'image/jpeg',
      byteSize: 100,
    );

void main() {
  group('SquareComposeDraft JSON 往返', () {
    test('文章草稿含段落和媒体完整往返', () {
      final draft = SquareComposeDraft(
        draftId: 'd1',
        cidNumber: 'CN001-CTZN-100000001-2026',
        postType: SquarePostType.article,
        title: '论社区自治',
        text: '正文',
        media: [
          _media(SquareMediaKind.image, 'cover.jpg'),
          _media(
            SquareMediaKind.image,
            'inline.jpg',
          ).copyWith(photoManagerAssetId: 'ios-or-android-photo-asset-id'),
        ],
        contentSections: const [
          {
            'text_delta': [
              {'insert': '第一段正文满足十字'},
              {'insert': '\n'},
            ],
            'gallery_media_indices': [1],
          },
        ],
        updatedAtMillis: 1800000000000,
      );
      final restored = SquareComposeDraft.fromJsonString(draft.toJsonString())!;
      expect(restored.draftId, 'd1');
      expect(restored.isArticle, isTrue);
      expect(restored.title, '论社区自治');
      expect(restored.media.length, 2);
      expect(restored.media[1].fileName, 'inline.jpg');
      expect(restored.media[1].mediaId, 'stored-inline.jpg');
      expect(restored.media[1].path, isEmpty);
      expect(draft.toJsonString(), isNot(contains('/temporary/')));
      expect(
        restored.media[1].photoManagerAssetId,
        'ios-or-android-photo-asset-id',
      );
      expect(restored.contentSections!.length, 1);
      expect(restored.contentSections!.first['gallery_media_indices'], [1]);
      expect(restored.updatedAtMillis, 1800000000000);
    });

    test('损坏字符串返回 null', () {
      expect(SquareComposeDraft.fromJsonString('不是json'), isNull);
      expect(SquareComposeDraft.fromJsonString(null), isNull);
    });
  });

  group('卡片派生', () {
    test('类型标签由固定 post_type 决定', () {
      SquareComposeDraft draft({
        required SquarePostType postType,
        List<SquareLocalMediaDraft> media = const [],
      }) => SquareComposeDraft(
        draftId: 'd',
        cidNumber: 'CN001-CTZN-100000001-2026',
        postType: postType,
        text: 't',
        media: media,
        updatedAtMillis: 1,
      );

      expect(
        draft(
          postType: SquarePostType.document,
          media: [_media(SquareMediaKind.image, 'a.jpg')],
        ).typeLabel,
        '公文',
      );
      expect(
        draft(
          postType: SquarePostType.video,
          media: [_media(SquareMediaKind.video, 'v.mp4')],
        ).typeLabel,
        '视频',
      );
      expect(draft(postType: SquarePostType.article).typeLabel, '文章');
    });

    test('文章摘要优先标题；空内容 isEmpty', () {
      const article = SquareComposeDraft(
        draftId: 'd',
        cidNumber: 'CN001-CTZN-100000001-2026',
        postType: SquarePostType.article,
        title: '标题',
        text: '正文',
        media: [],
        updatedAtMillis: 1,
      );
      expect(article.summary, '标题');

      const empty = SquareComposeDraft(
        draftId: 'd',
        cidNumber: 'CN001-CTZN-100000001-2026',
        postType: SquarePostType.document,
        text: '  ',
        media: [],
        updatedAtMillis: 1,
      );
      expect(empty.isEmpty, isTrue);
    });
  });
}
