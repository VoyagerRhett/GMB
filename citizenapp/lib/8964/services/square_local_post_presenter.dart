import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';

class SquareLocalPostPresenterException implements Exception {
  const SquareLocalPostPresenterException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 本人本地发布副本的展示结果。
///
/// 媒体按CID/帖子/槽位交给数据库读取组件；缺失不能推断为远端删除。
class SquareLocalPostPresentation {
  const SquareLocalPostPresentation({required this.post});

  final SquarePost post;
}

/// 把通过 [SquarePostStore] 完整性闸门的原始 manifest 转成广场只读展示模型。
///
/// 本转换仍会复核 SHA-256 和关键外层字段，防止调用方绕过 Store 直接构造损坏值。
/// 转换只解析声明，实际字节由媒体组件查询；不生成远端地址。
class SquareLocalPostPresenter {
  const SquareLocalPostPresenter();

  SquareLocalPostPresentation present(SquareLocalPost local) {
    final actualHash = sha256.convert(local.manifestBytes).toString();
    if (actualHash != local.contentHash) {
      throw const SquareLocalPostPresenterException(
        '本地 manifest 与 content_hash 不一致',
      );
    }

    final manifest = _decodeManifest(local);
    final postCategory = _parsePostCategory(local.postCategory);
    final postType = _parsePostType(local.postType);
    final text = manifest['text'];
    final mediaItems = manifest['media_items'];
    if (text is! String || mediaItems is! List) {
      throw const SquareLocalPostPresenterException('本地 manifest 正文或媒体声明不完整');
    }

    final media = <SquareMediaItem>[];
    for (final item in mediaItems) {
      if (item is! Map) {
        throw const SquareLocalPostPresenterException('本地 manifest 媒体声明损坏');
      }
      final mediaKind = item['media_kind'];
      if (mediaKind != SquareMediaKind.image.workerValue &&
          mediaKind != SquareMediaKind.video.workerValue) {
        throw const SquareLocalPostPresenterException(
          '本地 manifest media_kind 不合法',
        );
      }
      media.add(
        SquareMediaItem(
          mediaKind: mediaKind == 'image'
              ? SquareMediaKind.image
              : SquareMediaKind.video,
          url: '',
          cidNumber: local.cidNumber,
          postId: local.postId,
          mediaIndex: media.length,
          byteSize: item['byte_size'] as int?,
          width: item['width'] as int?,
          height: item['height'] as int?,
        ),
      );
    }

    final title = manifest['title'];
    if (title != null && title is! String) {
      throw const SquareLocalPostPresenterException('本地 manifest title 不合法');
    }
    if (postType == SquarePostType.article &&
        (title is! String || title.trim().isEmpty)) {
      throw const SquareLocalPostPresenterException('本地文章 title 不能为空');
    }
    // 规范 manifest 必须声明首项图片；否则该文章
    // 不具备首图真源，不能作为正常文章进入本人内容列表。
    if (postType == SquarePostType.article &&
        (mediaItems.isEmpty ||
            mediaItems.first is! Map ||
            (mediaItems.first as Map)['media_kind'] !=
                SquareMediaKind.image.workerValue)) {
      throw const SquareLocalPostPresenterException('本地文章首图声明缺失');
    }

    return SquareLocalPostPresentation(
      post: SquarePost(
        postId: local.postId,
        isLocal: true,
        mediaItems: media,
        author: SquareAuthor(
          accountId: local.accountId,
          cidNumber: local.cidNumber,
        ),
        postCategory: postCategory,
        postType: postType,
        title: title as String?,
        text: text,
        contentSections: parseArticleContentSections(
          manifest['content_sections'],
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(local.createdAt),
        contentHash: local.contentHash,
        storageReceiptId: local.storageReceiptId,
        chainBlock: local.chainBlock,
      ),
    );
  }

  static Map<String, dynamic> _decodeManifest(SquareLocalPost local) {
    try {
      final decoded = jsonDecode(
        utf8.decode(local.manifestBytes, allowMalformed: false),
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['schema'] != SquarePostStore.manifestSchema ||
          decoded['cid_number'] != local.cidNumber ||
          decoded['post_type'] != local.postType) {
        throw const SquareLocalPostPresenterException('本地 manifest 与发布事实不一致');
      }
      return decoded;
    } on SquareLocalPostPresenterException {
      rethrow;
    } on Object {
      throw const SquareLocalPostPresenterException(
        '本地 manifest 不是合法 UTF-8 JSON',
      );
    }
  }

  static SquarePostCategory _parsePostCategory(String value) {
    for (final category in SquarePostCategory.values) {
      if (category.workerValue == value) return category;
    }
    throw const SquareLocalPostPresenterException('本地 post_category 不合法');
  }

  static SquarePostType _parsePostType(String value) {
    for (final postType in SquarePostType.values) {
      if (postType.workerValue == value) return postType;
    }
    throw const SquareLocalPostPresenterException('本地 post_type 不合法');
  }
}
