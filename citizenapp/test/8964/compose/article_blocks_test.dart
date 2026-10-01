import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/compose/article/article_blocks.dart';
import 'package:citizenapp/8964/square_models.dart';

SquareLocalMediaDraft _img(String name) => SquareLocalMediaDraft(
      mediaKind: SquareMediaKind.image,
      path: '/tmp/$name',
      fileName: name,
      contentType: 'image/jpeg',
      byteSize: 100,
    );

SquareLocalMediaDraft _video(String name) => SquareLocalMediaDraft(
      mediaKind: SquareMediaKind.video,
      path: '/tmp/$name',
      fileName: name,
      contentType: 'video/mp4',
      byteSize: 200,
      durationSeconds: 30,
    );

List<Map<String, Object?>> _delta(String text) => [
      {'insert': text},
      const {'insert': '\n'},
    ];

void main() {
  group('buildArticleManifest 段落拍平', () {
    test('富文本后关联图集并保留媒体索引', () {
      final cover = _img('cover.jpg');
      final a = _img('a.jpg');
      final b = _img('b.jpg');
      final parts = buildArticleManifest(
        cover: cover,
        sections: [
          ArticleDraftSection(
            delta: _delta('第一段正文内容满足十字'),
            media: ArticleDraftGallery([a, b]),
          ),
          ArticleDraftSection(delta: _delta('第二段正文内容满足十字')),
        ],
      );
      expect(parts.mediaDrafts, [cover, a, b]);
      expect(parts.contentSections.first['gallery_media_indices'], [1, 2]);
      expect(parts.contentSections.first['text_delta'], _delta('第一段正文内容满足十字'));
      expect(parts.text, '第一段正文内容满足十字\n\n第二段正文内容满足十字');
    });

    test('视频属于同一段落而不是独立块', () {
      final cover = _img('cover.jpg');
      final video = _video('body.mp4');
      final parts = buildArticleManifest(
        cover: cover,
        sections: [
          ArticleDraftSection(
            delta: _delta('视频前面的正文满足十字'),
            media: ArticleDraftVideo(video),
          ),
        ],
      );
      expect(parts.mediaDrafts, [cover, video]);
      expect(parts.contentSections.single['video_media_index'], 1);
    });
  });

  group('parseArticleContentSections', () {
    test('解析富文本与图集关系', () {
      final sections = parseArticleContentSections([
        {
          'text_delta': _delta('这是满足十个字的正文内容'),
          'gallery_media_indices': [2, 3],
        },
      ]);
      expect(sections.single.galleryMediaIndices, [2, 3]);
      expect(sections.single.textDelta, _delta('这是满足十个字的正文内容'));
    });

    test('拒绝同段图集和视频及旧平铺块', () {
      expect(
        parseArticleContentSections([
          {
            'text_delta': _delta('这是满足十个字的正文内容'),
            'gallery_media_indices': [1],
            'video_media_index': 2,
          },
        ]),
        isEmpty,
      );
      expect(
          parseArticleContentSections([
            {'t': 'text', 'text': '旧块'}
          ]),
          isEmpty);
    });
  });
}
