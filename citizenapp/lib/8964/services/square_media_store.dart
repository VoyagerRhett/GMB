import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:isar_community/isar.dart';

import 'package:citizenapp/isar/social_isar.dart';

/// 媒体描述不含字节；列表读取不会把视频载入内存。
class SquareStoredMedia {
  const SquareStoredMedia({
    required this.cidNumber,
    required this.mediaId,
    required this.mediaKind,
    required this.contentType,
    required this.byteSize,
    required this.sha256,
    this.complete = false,
  });

  final String cidNumber;
  final String mediaId;
  final String mediaKind;
  final String contentType;
  final int byteSize;
  final String sha256;
  final bool complete;

  factory SquareStoredMedia._fromEntity(SquareMediaEntity entity) {
    return SquareStoredMedia(
      cidNumber: entity.cidNumber,
      mediaId: entity.mediaId,
      mediaKind: entity.mediaKind,
      contentType: entity.contentType,
      byteSize: entity.byteSize,
      sha256: entity.sha256,
      complete: entity.complete,
    );
  }
}

/// 一条内容的媒体槽位，CID 是关联归属，不从当前全局用户隐式推断。
class SquareMediaReference {
  const SquareMediaReference({
    required this.cidNumber,
    required this.mediaId,
    required this.contentKind,
    required this.contentId,
    required this.mediaIndex,
    required this.mediaRole,
  });

  final String cidNumber;
  final String mediaId;
  final String contentKind;
  final String contentId;
  final int mediaIndex;
  final String mediaRole;

  String get _key =>
      jsonEncode([contentKind, contentId, mediaIndex, mediaRole]);

  factory SquareMediaReference._fromEntity(SquareMediaReferenceEntity entity) {
    return SquareMediaReference(
      cidNumber: entity.cidNumber,
      mediaId: entity.mediaId,
      contentKind: entity.contentKind,
      contentId: entity.contentId,
      mediaIndex: entity.mediaIndex,
      mediaRole: entity.mediaRole,
    );
  }
}

class SquareMediaStoreException implements Exception {
  const SquareMediaStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 广场媒体字节的唯一数据库入口，不访问网络或平台播放器。
/// 文件来源以流导入，文件读取和哈希计算均在数据库事务之外。
///
/// 描述、分块、关联均属于 SocialIsar。每块单独提交，完整校验逐块读取；
/// 中断后仍保持未完成，只有 finish 成功后才允许读取和建立关联。
/// 同一 CID 的操作跨实例串行，避免校验期间删除重建、写入或关联造成竞态；
/// 哈希计算在数据库队列之外，不长期占用其它 Social 业务的事务。
class SquareMediaStore {
  const SquareMediaStore();

  static const int chunkSize = 1024 * 1024;
  static final Map<String, Future<void>> _tails = {};

  Future<SquareStoredMedia> saveFile({
    required String cidNumber,
    required String path,
    required String mediaKind,
    required String contentType,
    required int byteSize,
  }) async {
    final file = File(path);
    if (await file.length() != byteSize) _fail('媒体来源长度不匹配');
    final digest = (await sha256.bind(file.openRead()).first).toString();
    final media = SquareStoredMedia(
      cidNumber: cidNumber,
      mediaId: digest,
      mediaKind: mediaKind,
      contentType: contentType,
      byteSize: byteSize,
      sha256: digest,
    );
    await saveStream(media, file.openRead());
    return (await get(cidNumber: cidNumber, mediaId: digest))!;
  }

  /// 将任意输入流归整为固定数据库块；不把整个视频载入内存。
  /// 来源必须可提供已核实的长度与哈希，短流、长流和变更中的来源都无法完成。
  Future<void> saveStream(
    SquareStoredMedia media,
    Stream<List<int>> stream,
  ) async {
    await begin(media);
    var block = Uint8List(chunkSize);
    var used = 0;
    var index = 0;
    var total = 0;
    await for (final bytes in stream) {
      total += bytes.length;
      if (total > media.byteSize) _fail('媒体来源长度发生变化');
      var offset = 0;
      while (offset < bytes.length) {
        final take = math.min(chunkSize - used, bytes.length - offset);
        block.setRange(used, used + take, bytes, offset);
        used += take;
        offset += take;
        if (used == chunkSize) {
          await writeChunk(
            cidNumber: media.cidNumber,
            mediaId: media.mediaId,
            chunkIndex: index++,
            bytes: block,
          );
          block = Uint8List(chunkSize);
          used = 0;
        }
      }
    }
    if (total != media.byteSize) _fail('媒体来源长度发生变化');
    if (used > 0) {
      await writeChunk(
        cidNumber: media.cidNumber,
        mediaId: media.mediaId,
        chunkIndex: index,
        bytes: Uint8List.sublistView(block, 0, used),
      );
    }
    await finish(cidNumber: media.cidNumber, mediaId: media.mediaId);
  }

  /// 帖子/草稿事务的同域组成操作：调用方必须已处于 SocialIsar 写事务。
  /// 先验证全部新引用再替换，失败由外层事务整体回滚，不允许先删草稿再补引用。
  static Future<void> replaceReferencesInTransaction(
    Isar db, {
    required String cidNumber,
    required String contentKind,
    required String contentId,
    required List<SquareMediaReference> references,
  }) async {
    _validateContent(contentKind, contentId);
    final keys = <String>{};
    for (final ref in references) {
      _validateReference(ref);
      if (ref.cidNumber != cidNumber ||
          ref.contentKind != contentKind ||
          ref.contentId != contentId ||
          !keys.add(ref._key)) {
        _fail('媒体关联归属或槽位重复');
      }
      final media = await _requireMedia(db, cidNumber, ref.mediaId);
      if (!media.complete) _fail('未完成媒体不能关联内容');
    }
    final previous = await db.squareMediaReferenceEntitys
        .where()
        .contentIdCidNumberContentKindEqualTo(contentId, cidNumber, contentKind)
        .findAll();
    await db.squareMediaReferenceEntitys
        .where()
        .contentIdCidNumberContentKindEqualTo(contentId, cidNumber, contentKind)
        .deleteAll();
    for (final ref in references) {
      await db.squareMediaReferenceEntitys.put(
        SquareMediaReferenceEntity()
          ..cidNumber = cidNumber
          ..referenceKey = ref._key
          ..mediaId = ref.mediaId
          ..contentKind = contentKind
          ..contentId = contentId
          ..mediaIndex = ref.mediaIndex
          ..mediaRole = ref.mediaRole,
      );
    }
    final retained = references.map((r) => r.mediaId).toSet();
    for (final id
        in previous.map((r) => r.mediaId).toSet().difference(retained)) {
      await _deleteIfUnreferenced(db, cidNumber, id);
    }
  }

  /// 同一内容删除/成功发布收尾使用；引用已转给帖子时其字节不会被误删。
  static Future<void> removeContentInTransaction(
    Isar db, {
    required String cidNumber,
    required String contentKind,
    required String contentId,
  }) async {
    _validateContent(contentKind, contentId);
    final refs = await db.squareMediaReferenceEntitys
        .where()
        .contentIdCidNumberContentKindEqualTo(contentId, cidNumber, contentKind)
        .findAll();
    await db.squareMediaReferenceEntitys.deleteAll(
      refs.map((r) => r.id).toList(),
    );
    for (final id in refs.map((r) => r.mediaId).toSet()) {
      await _deleteIfUnreferenced(db, cidNumber, id);
    }
  }

  static Future<void> _deleteIfUnreferenced(
    Isar db,
    String cidNumber,
    String id,
  ) async {
    final count = await db.squareMediaReferenceEntitys
        .where()
        .mediaIdCidNumberEqualTo(id, cidNumber)
        .count();
    if (count != 0) return;
    await db.squareMediaChunkEntitys
        .where()
        .cidNumberMediaIdEqualToAnyChunkIndex(cidNumber, id)
        .deleteAll();
    await db.squareMediaEntitys.deleteByCidNumberMediaId(cidNumber, id);
  }

  /// 建立不可变描述；重试只接受完全相同的描述，不能由调用方标记完成。
  Future<void> begin(SquareStoredMedia media) async {
    _validateMedia(media);
    if (media.complete) _fail('不能跳过媒体完整性校验');
    return _serial(
      media.cidNumber,
      () => SocialIsar.instance.writeTxn((db) async {
        final existing = await db.squareMediaEntitys.getByCidNumberMediaId(
          media.cidNumber,
          media.mediaId,
        );
        if (existing != null) {
          if (existing.mediaKind != media.mediaKind ||
              existing.contentType != media.contentType ||
              existing.byteSize != media.byteSize ||
              existing.sha256 != media.sha256) {
            _fail('媒体标识已对应不同内容');
          }
          return;
        }
        await db.squareMediaEntitys.put(
          SquareMediaEntity()
            ..cidNumber = media.cidNumber
            ..mediaId = media.mediaId
            ..mediaKind = media.mediaKind
            ..contentType = media.contentType
            ..byteSize = media.byteSize
            ..sha256 = media.sha256,
        );
      }),
    );
  }

  /// 写入一块；输入先复制，调用方之后修改缓冲区不能改变待保存内容。
  /// 完全相同的块可安全重试，已存在但不同的字节必须拒绝。
  Future<void> writeChunk({
    required String cidNumber,
    required String mediaId,
    required int chunkIndex,
    required Uint8List bytes,
  }) async {
    _validateId(mediaId);
    if (chunkIndex < 0 || bytes.isEmpty || bytes.length > chunkSize) {
      _fail('媒体分块范围不合法');
    }
    final owned = Uint8List.fromList(bytes);
    final digest = sha256.convert(owned).toString();
    return _serial(
      cidNumber,
      () => SocialIsar.instance.writeTxn((db) async {
        final media = await _requireMedia(db, cidNumber, mediaId);
        if (owned.length != _chunkLength(media.byteSize, chunkIndex)) {
          _fail('媒体分块长度不匹配');
        }
        final existing = await db.squareMediaChunkEntitys
            .getByCidNumberMediaIdChunkIndex(cidNumber, mediaId, chunkIndex);
        if (existing != null) {
          if (existing.chunkSha256 != digest ||
              !_sameBytes(existing.chunkBytes, owned)) {
            _fail('媒体分块重试内容不一致');
          }
          return;
        }
        if (media.complete) _fail('已完成媒体禁止补写分块');
        await db.squareMediaChunkEntitys.put(
          SquareMediaChunkEntity()
            ..cidNumber = cidNumber
            ..mediaId = mediaId
            ..chunkIndex = chunkIndex
            ..chunkBytes = owned
            ..chunkSha256 = digest,
        );
      }),
    );
  }

  /// 不拼接整个视频；逐块核验连续序号、每块长度、块哈希和整体 SHA-256。
  /// 任一步失败都不推进完成状态。重复完成仍重新校验，不信任旧标记。
  Future<void> finish({required String cidNumber, required String mediaId}) {
    return _serial(cidNumber, () async {
      final media = await SocialIsar.instance.read(
        (db) => _requireMedia(db, cidNumber, mediaId),
      );
      final count = _chunkCount(media.byteSize);
      final storedCount = await SocialIsar.instance.read(
        (db) => db.squareMediaChunkEntitys
            .where()
            .cidNumberMediaIdEqualToAnyChunkIndex(cidNumber, mediaId)
            .count(),
      );
      if (storedCount != count) _fail('媒体分块不完整');
      final result = _DigestSink();
      final sink = sha256.startChunkedConversion(result);
      try {
        for (var index = 0; index < count; index++) {
          sink.add(await _readChunk(media, index));
        }
      } finally {
        sink.close();
      }
      if (result.digest?.toString() != media.sha256) {
        _fail('媒体整体哈希不匹配');
      }
      await SocialIsar.instance.writeTxn((db) async {
        final current = await _requireMedia(db, cidNumber, mediaId);
        if (current.id != media.id || current.sha256 != media.sha256) {
          _fail('媒体在校验期间发生变化');
        }
        current.complete = true;
        await db.squareMediaEntitys.put(current);
      });
    });
  }

  Future<SquareStoredMedia?> get({
    required String cidNumber,
    required String mediaId,
  }) {
    _validateId(mediaId);
    return _serial(
      cidNumber,
      () => SocialIsar.instance.read((db) async {
        final media = await db.squareMediaEntitys.getByCidNumberMediaId(
          cidNumber,
          mediaId,
        );
        return media == null ? null : SquareStoredMedia._fromEntity(media);
      }),
    );
  }

  /// 仅列出指定用户的描述，包含未完成状态供显式恢复；不读取分块集合。
  Future<List<SquareStoredMedia>> listByCid(String cidNumber) {
    return _serial(
      cidNumber,
      () => SocialIsar.instance.read((db) async {
        final rows = await db.squareMediaEntitys
            .where()
            .cidNumberEqualToAnyMediaId(cidNumber)
            .findAll();
        return rows.map(SquareStoredMedia._fromEntity).toList(growable: false);
      }),
    );
  }

  /// 精确范围读取，单次最多 1 MiB，可跨块；播放器按需继续请求下一段。
  /// 不截短越界请求；EOF 仅允许零长度读取。缺块或块损坏必须报错。
  Future<Uint8List> readRange({
    required String cidNumber,
    required String mediaId,
    required int offset,
    required int length,
  }) {
    return _serial(cidNumber, () async {
      if (offset < 0 || length < 0 || length > chunkSize) {
        _fail('媒体读取范围不合法');
      }
      final media = await SocialIsar.instance.read(
        (db) => _requireMedia(db, cidNumber, mediaId),
      );
      if (!media.complete) _fail('媒体尚未完整保存');
      if (offset > media.byteSize || length > media.byteSize - offset) {
        _fail('媒体读取范围超出长度');
      }
      final bytes = Uint8List(length);
      var copied = 0;
      while (copied < length) {
        final position = offset + copied;
        final chunk = await _readChunk(media, position ~/ chunkSize);
        final start = position % chunkSize;
        final take = math.min(length - copied, chunk.length - start);
        bytes.setRange(copied, copied + take, chunk, start);
        copied += take;
      }
      return bytes;
    });
  }

  /// 一个槽位只能关联一份已完成媒体；更换媒体需先显式移除旧关联。
  Future<void> attach(SquareMediaReference reference) async {
    _validateReference(reference);
    return _serial(
      reference.cidNumber,
      () => SocialIsar.instance.writeTxn((db) async {
        final media = await _requireMedia(
          db,
          reference.cidNumber,
          reference.mediaId,
        );
        if (!media.complete) _fail('未完成媒体不能关联内容');
        final existing = await db.squareMediaReferenceEntitys
            .getByCidNumberReferenceKey(reference.cidNumber, reference._key);
        if (existing != null) {
          if (existing.mediaId != reference.mediaId) {
            _fail('媒体槽位已有不同关联');
          }
          return;
        }
        await db.squareMediaReferenceEntitys.put(
          SquareMediaReferenceEntity()
            ..cidNumber = reference.cidNumber
            ..referenceKey = reference._key
            ..mediaId = reference.mediaId
            ..contentKind = reference.contentKind
            ..contentId = reference.contentId
            ..mediaIndex = reference.mediaIndex
            ..mediaRole = reference.mediaRole,
        );
      }),
    );
  }

  Future<List<SquareMediaReference>> referencesForContent({
    required String cidNumber,
    required String contentKind,
    required String contentId,
  }) {
    _validateContent(contentKind, contentId);
    return _serial(
      cidNumber,
      () => SocialIsar.instance.read((db) async {
        final rows = await db.squareMediaReferenceEntitys
            .where()
            .contentIdCidNumberContentKindEqualTo(
              contentId,
              cidNumber,
              contentKind,
            )
            .sortByMediaIndex()
            .thenByMediaRole()
            .findAll();
        return rows
            .map(SquareMediaReference._fromEntity)
            .toList(growable: false);
      }),
    );
  }

  /// 删除前匹配媒体标识，避免迟到的删除请求移除另一个媒体的新关联。
  Future<bool> detach(SquareMediaReference reference) async {
    _validateReference(reference);
    return _serial(
      reference.cidNumber,
      () => SocialIsar.instance.writeTxn((db) async {
        final existing = await db.squareMediaReferenceEntitys
            .getByCidNumberReferenceKey(reference.cidNumber, reference._key);
        if (existing == null || existing.mediaId != reference.mediaId) {
          return false;
        }
        return db.squareMediaReferenceEntitys.delete(existing.id);
      }),
    );
  }

  /// 显式删除无引用媒体（包含未完成媒体）。引用检查与删除在同一事务；
  /// 删引用本身不会触发此操作，不因打开页面、数量上限或时间自动淘汰。
  Future<bool> deleteUnused({
    required String cidNumber,
    required String mediaId,
  }) {
    _validateId(mediaId);
    return _serial(
      cidNumber,
      () => SocialIsar.instance.writeTxn((db) async {
        final media = await db.squareMediaEntitys.getByCidNumberMediaId(
          cidNumber,
          mediaId,
        );
        if (media == null) return false;
        final references = await db.squareMediaReferenceEntitys
            .where()
            .mediaIdCidNumberEqualTo(mediaId, cidNumber)
            .count();
        if (references != 0) _fail('媒体仍被内容引用');
        await db.squareMediaChunkEntitys
            .where()
            .cidNumberMediaIdEqualToAnyChunkIndex(cidNumber, mediaId)
            .deleteAll();
        return db.squareMediaEntitys.delete(media.id);
      }),
    );
  }

  static Future<SquareMediaEntity> _requireMedia(
    Isar db,
    String cidNumber,
    String mediaId,
  ) async {
    _validateId(mediaId);
    final media = await db.squareMediaEntitys.getByCidNumberMediaId(
      cidNumber,
      mediaId,
    );
    if (media == null) _fail('当前用户没有此媒体');
    return media;
  }

  static Future<List<int>> _readChunk(
    SquareMediaEntity media,
    int index,
  ) async {
    final chunk = await SocialIsar.instance.read(
      (db) => db.squareMediaChunkEntitys.getByCidNumberMediaIdChunkIndex(
        media.cidNumber,
        media.mediaId,
        index,
      ),
    );
    if (chunk == null ||
        chunk.chunkBytes.length != _chunkLength(media.byteSize, index) ||
        sha256.convert(chunk.chunkBytes).toString() != chunk.chunkSha256) {
      _fail('媒体分块缺失或损坏');
    }
    return chunk.chunkBytes;
  }

  static int _chunkCount(int size) => (size - 1) ~/ chunkSize + 1;

  static int _chunkLength(int size, int index) {
    if (index < 0 || index >= _chunkCount(size)) _fail('媒体分块序号越界');
    return math.min(chunkSize, size - index * chunkSize);
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static void _validateMedia(SquareStoredMedia media) {
    _validateId(media.mediaId);
    if (!{'image', 'video'}.contains(media.mediaKind) ||
        !media.contentType.startsWith('${media.mediaKind}/') ||
        media.contentType.trim() != media.contentType ||
        media.contentType.length > 255 ||
        media.contentType.length <= media.mediaKind.length + 1 ||
        media.byteSize <= 0 ||
        media.byteSize > 0x1fffffffffffff ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(media.sha256)) {
      _fail('媒体描述不合法');
    }
  }

  static void _validateContent(String kind, String id) {
    _validateId(id);
    if (!{'draft', 'post', 'publication'}.contains(kind)) _fail('媒体关联内容类型不合法');
  }

  static void _validateReference(SquareMediaReference reference) {
    _validateId(reference.mediaId);
    _validateContent(reference.contentKind, reference.contentId);
    if (reference.mediaIndex < 0 ||
        reference.mediaIndex > 0x1fffffffffffff ||
        !{'main', 'thumbnail', 'cover'}.contains(reference.mediaRole)) {
      _fail('媒体槽位不合法');
    }
  }

  static void _validateId(String value) {
    if (value.trim().isEmpty ||
        value.trim() != value ||
        utf8.encode(value).length > 512) {
      _fail('媒体或内容标识不合法');
    }
  }

  static Future<T> _serial<T>(String cid, Future<T> Function() action) async {
    // 复用现有 CID 载荷的字节边界，不在 App 另建号码格式或链上授权规则。
    if (cid.trim() != cid || cid.isEmpty || utf8.encode(cid).length > 32) {
      _fail('cid_number 格式不合法');
    }
    final previous = _tails[cid] ?? Future<void>.value();
    final result = previous.then((_) => action());
    // 失败只返回给本次调用者，不阻塞同一用户后续的显式恢复。
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[cid] = tail;
    try {
      return await result;
    } finally {
      if (identical(_tails[cid], tail)) _tails.remove(cid);
    }
  }

  static Never _fail(String message) =>
      throw SquareMediaStoreException(message);
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}
