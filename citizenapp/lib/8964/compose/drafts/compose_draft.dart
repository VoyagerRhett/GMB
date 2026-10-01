import 'dart:convert';

import 'package:citizenapp/8964/square_models.dart';

/// 广场草稿箱的一条草稿；发布类型在创建时固定为公文、文章或视频。
///
/// 与发布 manifest 同构，便于恢复到发布页并直接发布：
/// media 顺序 = [首图, ...正文媒体]（文章）/ 图集（公文）/ 单视频（视频）；
/// contentSections 仅文章使用：每段保存 text_delta 与一个可选媒体引用。
class SquareComposeDraft {
  const SquareComposeDraft({
    required this.draftId,
    required this.cidNumber,
    required this.postType,
    this.title,
    required this.text,
    required this.media,
    this.contentSections,
    required this.updatedAtMillis,
  });

  final String draftId;

  /// 草稿永久属于 CID；发布时再读取该 CID 当前绑定账户完成签名与付款。
  final String cidNumber;
  final SquarePostType postType;
  final String? title;
  final String text;
  final List<SquareLocalMediaDraft> media;
  final List<Map<String, Object?>>? contentSections;
  final int updatedAtMillis;

  bool get isArticle => postType == SquarePostType.article;

  bool get isEmpty =>
      text.trim().isEmpty && media.isEmpty && (title?.trim().isEmpty ?? true);

  String get typeLabel => postType.label;

  /// 卡片摘要：文章优先标题，否则正文。
  String get summary {
    final trimmedTitle = title?.trim();
    if (isArticle && trimmedTitle != null && trimmedTitle.isNotEmpty) {
      return trimmedTitle;
    }
    return text.trim();
  }

  SquareComposeDraft copyWith({
    List<SquareLocalMediaDraft>? media,
    List<Map<String, Object?>>? contentSections,
    int? updatedAtMillis,
  }) {
    return SquareComposeDraft(
      draftId: draftId,
      cidNumber: cidNumber,
      postType: postType,
      title: title,
      text: text,
      media: media ?? this.media,
      contentSections: contentSections ?? this.contentSections,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
    );
  }

  Map<String, Object?> toJson() => {
    'draft_id': draftId,
    'cid_number': cidNumber,
    'post_type': postType.workerValue,
    if (title != null) 'title': title,
    'text': text,
    'media': media.map(_mediaToJson).toList(),
    if (contentSections != null) 'content_sections': contentSections,
    'updated_at': updatedAtMillis,
  };

  String toJsonString() => jsonEncode(toJson());

  static SquareComposeDraft? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SquareComposeDraft.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  factory SquareComposeDraft.fromJson(Map<String, dynamic> json) {
    final rawMedia = json['media'];
    final rawSections = json['content_sections'];
    final draftId = json['draft_id']?.toString() ?? '';
    final cidNumber = json['cid_number']?.toString() ?? '';
    final updatedAt = json['updated_at'] is int
        ? json['updated_at'] as int
        : int.tryParse(json['updated_at']?.toString() ?? '') ?? 0;
    if (draftId.isEmpty ||
        cidNumber.isEmpty ||
        updatedAt <= 0 ||
        rawMedia is! List ||
        (rawSections != null && rawSections is! List)) {
      throw const FormatException('草稿主键或时间不合法');
    }
    return SquareComposeDraft(
      draftId: draftId,
      cidNumber: cidNumber,
      postType: _postTypeFromJson(json['post_type']),
      title: json['title']?.toString(),
      text: json['text']?.toString() ?? '',
      media: rawMedia.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('草稿媒体条目损坏');
        }
        return _mediaFromJson(item);
      }).toList(),
      contentSections: rawSections is List
          ? rawSections.map((e) {
              if (e is! Map) throw const FormatException('草稿文章条目损坏');
              return e.map((k, v) => MapEntry(k.toString(), v));
            }).toList()
          : null,
      updatedAtMillis: updatedAt,
    );
  }

  static SquarePostType _postTypeFromJson(Object? value) {
    for (final postType in SquarePostType.values) {
      if (postType.workerValue == value) return postType;
    }
    throw const FormatException('草稿 post_type 不合法');
  }

  static Map<String, Object?> _mediaToJson(SquareLocalMediaDraft draft) => {
    'media_kind': draft.mediaKind.workerValue,
    'media_id': draft.mediaId ?? (throw const FormatException('草稿媒体尚未入库')),
    'file_name': draft.fileName,
    'content_type': draft.contentType,
    'byte_size': draft.byteSize,
    if (draft.width != null) 'width': draft.width,
    if (draft.height != null) 'height': draft.height,
    if (draft.photoManagerAssetId != null)
      'photo_manager_asset_id': draft.photoManagerAssetId,
    if (draft.durationSeconds != null)
      'duration_seconds': draft.durationSeconds,
  };

  static SquareLocalMediaDraft _mediaFromJson(Map<String, dynamic> json) {
    final mediaKind = switch (json['media_kind']) {
      'image' => SquareMediaKind.image,
      'video' => SquareMediaKind.video,
      _ => throw const FormatException('草稿 media_kind 不合法'),
    };
    return SquareLocalMediaDraft(
      mediaKind: mediaKind,
      // 旧文件草稿仅供用户恢复时核验入库；新写入永不保存 path。
      path: json['media_id'] == null ? json['path']?.toString() ?? '' : '',
      mediaId: json['media_id'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      fileName: json['file_name']?.toString() ?? '',
      contentType: json['content_type']?.toString() ?? '',
      byteSize: json['byte_size'] is int
          ? json['byte_size'] as int
          : int.tryParse(json['byte_size']?.toString() ?? '') ?? 0,
      durationSeconds: json['duration_seconds'] is int
          ? json['duration_seconds'] as int
          : int.tryParse(json['duration_seconds']?.toString() ?? ''),
      photoManagerAssetId:
          json['photo_manager_asset_id']?.toString().trim().isEmpty == false
          ? json['photo_manager_asset_id']?.toString()
          : null,
    );
  }
}
