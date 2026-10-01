import 'package:citizenapp/8964/compose/article/article_section_editor.dart';
import 'package:citizenapp/8964/square_models.dart';

const int articleTitleMin = 10;
const int articleTitleMax = 50;
const int articleBodyMax = 30000;
const int articleSectionTextMin = 10;

/// 文章发布校验（纯函数，便于双端边界测试）。
String? articleValidationError({
  required String title,
  required bool hasCover,
  required String body,
}) {
  final titleLength = title.trim().runes.length;
  if (titleLength < articleTitleMin || titleLength > articleTitleMax) {
    return '标题需 $articleTitleMin–$articleTitleMax 字';
  }
  if (!hasCover) return '请选择 1 张首图';
  final trimmedBody = body.trim();
  if (trimmedBody.isEmpty) return '正文不能为空';
  if (trimmedBody.runes.length > articleBodyMax) {
    return '正文不能超过 $articleBodyMax 字';
  }
  return null;
}

sealed class ArticleDraftSectionMedia {
  const ArticleDraftSectionMedia();
}

final class ArticleDraftGallery extends ArticleDraftSectionMedia {
  ArticleDraftGallery(List<SquareLocalMediaDraft> drafts)
      : drafts = List<SquareLocalMediaDraft>.unmodifiable(drafts);

  final List<SquareLocalMediaDraft> drafts;
}

final class ArticleDraftVideo extends ArticleDraftSectionMedia {
  const ArticleDraftVideo(this.draft);
  final SquareLocalMediaDraft draft;
}

/// 一个文章段落始终包含富文本；媒体是该段落的可选附属内容。
final class ArticleDraftSection {
  ArticleDraftSection({required Object delta, this.media})
      : delta = List<Map<String, Object?>>.unmodifiable(
          normalizeArticleDelta(delta),
        );

  final List<Map<String, Object?>> delta;
  final ArticleDraftSectionMedia? media;

  String get plainText => articleDeltaPlainText(delta);
}

class ArticleManifestParts {
  const ArticleManifestParts({
    required this.mediaDrafts,
    required this.contentSections,
    required this.text,
  });

  final List<SquareLocalMediaDraft> mediaDrafts;
  final List<Map<String, Object?>> contentSections;
  final String text;
}

/// 拍平首图和段落单元；每个段落先写 text_delta，再写可选媒体引用。
ArticleManifestParts buildArticleManifest({
  required SquareLocalMediaDraft cover,
  required List<ArticleDraftSection> sections,
}) {
  final mediaDrafts = <SquareLocalMediaDraft>[cover];
  final contentSections = <Map<String, Object?>>[];
  final textParts = <String>[];
  for (final section in sections) {
    final plainText = section.plainText;
    if (plainText.isEmpty) continue;
    final encoded = <String, Object?>{'text_delta': section.delta};
    switch (section.media) {
      case ArticleDraftGallery(:final drafts):
        final indices = <int>[];
        for (final draft in drafts) {
          mediaDrafts.add(draft);
          indices.add(mediaDrafts.length - 1);
        }
        encoded['gallery_media_indices'] = indices;
      case ArticleDraftVideo(:final draft):
        mediaDrafts.add(draft);
        encoded['video_media_index'] = mediaDrafts.length - 1;
      case null:
        break;
    }
    contentSections.add(encoded);
    textParts.add(plainText);
  }
  return ArticleManifestParts(
    mediaDrafts: mediaDrafts,
    contentSections: contentSections,
    text: textParts.join('\n\n'),
  );
}
