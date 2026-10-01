import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'square_media_store.dart';
import 'square_post_deletion_coordinator.dart';

import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';

typedef SquareSelfPostPageLoader = Future<SquareLocalPostPage> Function({
  required SquareSession session,
  String? cursor,
  required int limit,
});

/// 本人已发布广场内容的增量回灌协调器。
///
/// 同步只会补写 Worker 仍保留的发布事实，绝不会因为会员到期或远端删除而反向删除
/// 本地副本。每页原子落盘，全部目标页成功后才推进检查点；中途失败时下次从远端
/// 最新位置重新扫描，已落盘页依靠 post_id 不可变事实幂等重放。
class SquarePostSyncService {
  SquarePostSyncService({
    SquareSelfPostPageLoader? pageLoader,
    SquarePostStore? store,
    SquareApiClient? api,
  }) : _pageLoader =
           pageLoader ??
           (api ?? SquareApiClient()).fetchSelfPublishedPostCopies,
       _store = store ?? const SquarePostStore(),
       _api = api ?? SquareApiClient();

  static const int pageSize = 5;

  List<Map<String, dynamic>> _declarations(SquareLocalPost post) {
    if (sha256.convert(post.manifestBytes).toString() != post.contentHash) {
      throw StateError('正文哈希不一致');
    }
    final raw = jsonDecode(utf8.decode(post.manifestBytes));
    if (raw is! Map ||
        raw['cid_number'] != post.cidNumber ||
        raw['schema'] != SquarePostStore.manifestSchema ||
        raw['media_items'] is! List) {
      throw StateError('正文归属或媒体声明损坏');
    }
    return (raw['media_items'] as List).map((value) {
      if (value is! Map<String, dynamic> ||
          !{'image', 'video'}.contains(value['media_kind']) ||
          value['byte_size'] is! int ||
          (value['byte_size'] as int) <= 0 ||
          value['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['sha256']) ||
          value['content_type'] is! String) {
        throw StateError('媒体声明损坏');
      }
      return value;
    }).toList();
  }

  Future<List<SquareMediaReference>?> _existingMedia(
    SquareLocalPost post,
  ) async {
    final declarations = _declarations(post);
    final refs = await _media.referencesForContent(
      cidNumber: post.cidNumber,
      contentKind: 'post',
      contentId: post.postId,
    );
    if (refs.length != declarations.length * 2) return null;
    for (var i = 0; i < declarations.length; i++) {
      final item = declarations[i];
      for (final role in [
        'main',
        item['media_kind'] == 'video' ? 'cover' : 'thumbnail',
      ]) {
        final matching = refs
            .where((r) => r.mediaIndex == i && r.mediaRole == role)
            .toList();
        if (matching.length != 1) return null;
        final stored = await _media.get(
          cidNumber: post.cidNumber,
          mediaId: matching.single.mediaId,
        );
        if (stored == null || !stored.complete) return null;
        if (role != 'main' && stored.mediaKind != 'image') return null;
        if (role == 'main' &&
            (stored.sha256 != item['sha256'] ||
                stored.byteSize != item['byte_size'] ||
                stored.contentType != item['content_type'] ||
                stored.mediaKind != item['media_kind'])) {
          return null;
        }
      }
    }
    return refs;
  }

  /// 主媒体对照已确认manifest；衍生图由HTTPS详情指定，计算本地完整性摘要后入库。
  /// 详情当前没有衍生图哈希，不能把本地摘要宣称成链上或manifest对衍生图的承诺。
  Future<List<SquareMediaReference>> _restoreMedia(
    SquareSession session,
    SquareLocalPost post,
    void Function() check,
  ) async {
    final existing = await _existingMedia(post);
    if (existing != null) return existing;
    final declarations = _declarations(post);
    final remote = await _api.fetchPostMedia(session: session, post: post);
    if (remote.length != declarations.length) throw StateError('远端媒体数量不一致');
    final refs = <SquareMediaReference>[];
    for (var i = 0; i < declarations.length; i++) {
      check();
      final item = declarations[i];
      final source = remote[i];
      for (final field in [
        'media_kind',
        'byte_size',
        'sha256',
        'content_type',
      ]) {
        if (source[field] != item[field]) throw StateError('远端媒体与正文声明不一致');
      }
      if (source['asset_state'] != 'ready') throw StateError('远端媒体尚未就绪');
      final descriptor = SquareStoredMedia(
        cidNumber: post.cidNumber,
        mediaId: item['sha256'] as String,
        mediaKind: item['media_kind'] as String,
        contentType: item['content_type'] as String,
        byteSize: item['byte_size'] as int,
        sha256: item['sha256'] as String,
      );
      final stored = await _media.get(
        cidNumber: post.cidNumber,
        mediaId: descriptor.mediaId,
      );
      if (stored?.complete != true) {
        // 上轮下载可能留下错误字节；本次显式重试只重建未完成、无引用的媒体。
        // 完成的本地原件永远不因此删除，引用检查由仓库原子执行。
        if (stored != null) {
          await _media.deleteUnused(
            cidNumber: post.cidNumber,
            mediaId: descriptor.mediaId,
          );
        }
        final response = await _api.openPostMedia(source['url'] as String);
        if (response.contentLength != null &&
            response.contentLength != descriptor.byteSize) {
          await response.stream.listen(null).cancel();
          throw StateError('媒体响应长度不一致');
        }
        await _media.saveStream(
          descriptor,
          response.stream.timeout(const Duration(seconds: 30)).map((chunk) {
            check();
            return chunk;
          }),
        );
      }
      final role = descriptor.mediaKind == 'video' ? 'cover' : 'thumbnail';
      if (source['derivative_kind'] != role ||
          source['thumbnail_url'] is! String) {
        throw StateError('衍生图声明不一致');
      }
      final preview = await _api.openPostMedia(
        source['thumbnail_url'] as String,
      );
      const limit = 4 * 1024 * 1024;
      if ((preview.contentLength ?? 0) > limit) {
        await preview.stream.listen(null).cancel();
        throw StateError('衍生图超出大小限制');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in preview.stream.timeout(
        const Duration(seconds: 30),
      )) {
        check();
        if (bytes.length + chunk.length > limit) throw StateError('衍生图超出大小限制');
        bytes.add(chunk);
      }
      final data = bytes.takeBytes();
      final type = preview.headers['content-type']?.split(';').first.trim();
      if (data.isEmpty ||
          !{'image/jpeg', 'image/png', 'image/webp'}.contains(type)) {
        throw StateError('衍生图格式无效');
      }
      final validHeader = switch (type) {
        'image/png' =>
          data.length >= 8 &&
              data.take(8).join(',') == '137,80,78,71,13,10,26,10',
        'image/jpeg' =>
          data.length >= 3 &&
              data[0] == 255 &&
              data[1] == 216 &&
              data[2] == 255,
        'image/webp' =>
          data.length >= 12 &&
              ascii.decode(data.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
              ascii.decode(data.sublist(8, 12), allowInvalid: true) == 'WEBP',
        _ => false,
      };
      if (!validHeader ||
          (preview.contentLength != null &&
              preview.contentLength != data.length)) {
        throw StateError('衍生图字节与响应声明不一致');
      }
      final digest = sha256.convert(data).toString();
      await _media.saveStream(
        SquareStoredMedia(
          cidNumber: post.cidNumber,
          mediaId: digest,
          mediaKind: 'image',
          contentType: type!,
          byteSize: data.length,
          sha256: digest,
        ),
        Stream.value(data),
      );
      refs.addAll([
        SquareMediaReference(
          cidNumber: post.cidNumber,
          mediaId: descriptor.mediaId,
          contentKind: 'post',
          contentId: post.postId,
          mediaIndex: i,
          mediaRole: 'main',
        ),
        SquareMediaReference(
          cidNumber: post.cidNumber,
          mediaId: digest,
          contentKind: 'post',
          contentId: post.postId,
          mediaIndex: i,
          mediaRole: role,
        ),
      ]);
    }
    return refs;
  }

  final SquareSelfPostPageLoader _pageLoader;
  final SquarePostStore _store;
  final SquareApiClient _api;
  static const _media = SquareMediaStore();
  static final Map<String, Future<void>> _inflightByCid =
      <String, Future<void>>{};

  static final Map<String, String> _bindings = {};

  /// 只接受明确的用户操作；同CID和绑定的在途刷新跨服务实例合并。
  Future<void> sync(
    SquareSession session, {
    required bool userInitiated,
    bool Function()? isCurrent,
  }) {
    if (!userInitiated) throw StateError('普通加载不得启动本人内容同步');
    final binding = '${session.accountId}:${session.bindingRevision}';
    void check() {
      if (!session.isUsable || !(isCurrent?.call() ?? true)) {
        throw StateError('同步身份已变化');
      }
    }

    check();
    final running = _inflightByCid[session.cidNumber];
    if (running != null) {
      if (_bindings[session.cidNumber] != binding) {
        throw StateError('不能共用旧身份的同步任务');
      }
      return running;
    }
    _bindings[session.cidNumber] = binding;

    late final Future<void> task;
    task = () async {
      try {
        await _sync(session, check);
      } finally {
        if (identical(_inflightByCid[session.cidNumber], task)) {
          _inflightByCid.remove(session.cidNumber);
          _bindings.remove(session.cidNumber);
        }
      }
    }();
    _inflightByCid[session.cidNumber] = task;
    return task;
  }

  Future<void> _sync(SquareSession session, void Function() check) async {
    // 删除恢复先于拉取，避免同轮把用户已删除内容重新导入。
    await SquarePostDeletionCoordinator(remoteDeletion: _api).recover(session);
    check();
    final checkpoint = await _store.readSyncCheckpoint(session.cidNumber);
    var repairMedia = false;
    for (final post in await _store.listByCid(session.cidNumber)) {
      if (await _existingMedia(post) == null) {
        repairMedia = true;
        break;
      }
    }
    final seenCursors = <String>{};
    String? cursor;
    SquareLocalPost? remoteNewest;
    SquareLocalPost? previousItem;

    while (true) {
      check();
      final page = await _pageLoader(
        session: session,
        cursor: cursor,
        limit: pageSize,
      );
      if (page.items.length > pageSize) {
        throw const SquarePostStoreException('本人副本回灌页超过客户端上限');
      }
      if (page.items.isEmpty && page.nextCursor != null) {
        throw const SquarePostStoreException('空回灌页不得携带下一页游标');
      }

      for (final item in page.items) {
        if (item.cidNumber != session.cidNumber) {
          throw const SquarePostStoreException('回灌内容不属于当前会话 CID');
        }
        final previous = previousItem;
        if (previous != null &&
            (item.createdAt > previous.createdAt ||
                (item.createdAt == previous.createdAt &&
                    item.postId.compareTo(previous.postId) >= 0))) {
          throw const SquarePostStoreException('本人副本回灌顺序不稳定');
        }
        previousItem = item;
        remoteNewest ??= item;
      }

      final references = <String, List<SquareMediaReference>>{};
      for (final post in page.items) {
        check();
        if (await _store.readDeletion(post.cidNumber, post.postId) != null) {
          references[post.postId] = [];
          continue;
        }
        references[post.postId] = await _restoreMedia(session, post, check);
      }
      check();
      await _store.saveSyncedPage(page.items, references);

      final reachedCheckpoint =
          checkpoint?.newestPostId != null &&
          page.items.any(
            (item) =>
                item.postId == checkpoint!.newestPostId &&
                item.createdAt == checkpoint.newestCreatedAt,
          );
      if ((!repairMedia && reachedCheckpoint) || page.nextCursor == null) {
        break;
      }
      final nextCursor = page.nextCursor!;
      if (!seenCursors.add(nextCursor)) {
        throw const SquarePostStoreException('本人副本回灌游标发生循环');
      }
      cursor = nextCursor;
    }

    // 检查点只记录 Worker 最新发布事实，不记录本次设备同步时间。
    check();
    await _store.writeSyncCheckpoint(
      cidNumber: session.cidNumber,
      checkpoint: SquarePostSyncCheckpoint(
        newestPostId: remoteNewest?.postId,
        newestCreatedAt: remoteNewest?.createdAt ?? 0,
      ),
    );
  }
}
