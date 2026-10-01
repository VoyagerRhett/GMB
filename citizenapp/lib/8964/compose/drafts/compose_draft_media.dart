import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:citizenapp/8964/services/square_media_store.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:citizenapp/8964/square_models.dart';

enum _ComposeDraftMediaLifecycle { active, closing, closed }

/// 草稿媒体数据库导入与临时处理文件域。
/// 持久内容只在 SocialIsar，临时文件丢失后从数据库重新生成。
///
/// 文件操作使用独立串行队列和终态，数据库事务之外才进行文件操作。AppLock 显式擦除一旦进入
/// closing，新写入会同步拒绝；晚到 copy 也会清除自己产生的目录，不能在擦除后复活。
class ComposeDraftMedia {
  const ComposeDraftMedia();

  static final Object _operationZoneKey = Object();
  static Future<void> _operationTail = Future<void>.value();
  static _ComposeDraftMediaLifecycle _lifecycle =
      _ComposeDraftMediaLifecycle.active;
  static int _generation = 0;
  static Future<void>? _closing;

  static const Duration _drainTimeout = Duration(seconds: 2);

  @visibleForTesting
  static Future<Directory> Function()? debugDocumentsDirectoryProvider;

  static Future<Directory> _documentsDirectory(
    Future<Directory> Function()? override,
  ) =>
      (override ??
      debugDocumentsDirectoryProvider ??
      getApplicationDocumentsDirectory)();

  static Future<Directory> _root({
    required bool create,
    Future<Directory> Function()? documentsDirectoryProvider,
  }) async {
    final docs = await _documentsDirectory(documentsDirectoryProvider);
    final dir = Directory('${docs.path}/square_drafts');
    final type = await FileSystemEntity.type(dir.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.file) {
      throw StateError('广场草稿根路径不是目录，拒绝继续文件操作。');
    }
    if (create && type == FileSystemEntityType.notFound) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> _draftDir(
    String cidNumber,
    String draftId, {
    required bool create,
    bool temporary = false,
  }) async {
    _validatePathSegment(cidNumber, 'cid_number');
    _validatePathSegment(draftId, 'draft_id');
    final root = temporary
        ? await _temporaryRoot(create: create)
        : await _root(create: create);
    final ownerDir = Uri.encodeComponent(cidNumber);
    final encodedDraftId = Uri.encodeComponent(draftId);
    final owner = Directory('${root.path}/$ownerDir');
    final ownerType = await FileSystemEntity.type(
      owner.path,
      followLinks: false,
    );
    if (ownerType == FileSystemEntityType.link ||
        ownerType == FileSystemEntityType.file) {
      throw StateError('广场草稿属主路径不是目录，拒绝继续文件操作。');
    }
    if (create && ownerType == FileSystemEntityType.notFound) {
      await owner.create(recursive: true);
    }
    final dir = Directory('${owner.path}/$encodedDraftId');
    final type = await FileSystemEntity.type(dir.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.file) {
      throw StateError('广场草稿媒体路径不是目录，拒绝继续文件操作。');
    }
    if (create && type == FileSystemEntityType.notFound) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static void _validatePathSegment(String value, String field) {
    if (value.trim().isEmpty ||
        value.trim() != value ||
        value == '.' ||
        value == '..') {
      throw ArgumentError.value(value, field, '不是合法的草稿路径标识');
    }
  }

  static Future<Directory> _temporaryRoot({
    required bool create,
    Future<Directory> Function()? directoryProvider,
  }) async {
    final parent =
        await (directoryProvider ??
            debugDocumentsDirectoryProvider ??
            getTemporaryDirectory)();
    final root = Directory('${parent.path}/square_media_work');
    final type = await FileSystemEntity.type(root.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw StateError('媒体临时路径不是目录');
    }
    if (create && type == FileSystemEntityType.notFound) await root.create();
    return root;
  }

  /// 旧草稿只允许导入本 CID/草稿目录内的普通文件，拒绝越界路径和符号链接。
  static Future<void> validateLegacyPaths(
    String cid,
    String draftId,
    Iterable<String> paths,
  ) async {
    final root = await _draftDir(cid, draftId, create: false);
    final resolvedRoot = await root.resolveSymbolicLinks();
    for (final path in paths) {
      if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file ||
          !(await File(
            path,
          ).resolveSymbolicLinks()).startsWith('$resolvedRoot/')) {
        throw StateError('旧草稿媒体路径不属于当前用户和草稿');
      }
    }
  }

  /// 先校验并提交数据库，再生成可删除的处理文件；外部原文件不在这里删除。
  static Future<SquareLocalMediaDraft> persist(
    String cidNumber,
    String draftId,
    SquareLocalMediaDraft media,
  ) {
    Directory? createdDirectory;
    return _enqueueMutation(
      () async {
        const store = SquareMediaStore();
        final stored = media.mediaId == null
            ? await store.saveFile(
                cidNumber: cidNumber,
                path: media.path,
                mediaKind: media.mediaKind.workerValue,
                contentType: media.contentType,
                byteSize: media.byteSize,
              )
            : await store.get(cidNumber: cidNumber, mediaId: media.mediaId!);
        if (stored == null ||
            !stored.complete ||
            stored.byteSize != media.byteSize ||
            stored.mediaKind != media.mediaKind.workerValue ||
            stored.contentType != media.contentType) {
          throw StateError('草稿媒体归属或完整性不匹配');
        }
        final dir = await _draftDir(
          cidNumber,
          draftId,
          create: true,
          temporary: true,
        );
        createdDirectory = dir;
        final ext = RegExp(r'^[a-zA-Z0-9]{1,10}$').hasMatch(media.fileExt)
            ? media.fileExt
            : 'bin';
        final target = File('${dir.path}/${stored.mediaId}.$ext');
        if (await FileSystemEntity.type(target.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw StateError('媒体临时文件不能是符号链接');
        }
        final output = target.openWrite();
        try {
          for (
            var offset = 0;
            offset < stored.byteSize;
            offset += SquareMediaStore.chunkSize
          ) {
            output.add(
              await store.readRange(
                cidNumber: cidNumber,
                mediaId: stored.mediaId,
                offset: offset,
                length: math.min(
                  SquareMediaStore.chunkSize,
                  stored.byteSize - offset,
                ),
              ),
            );
            await output.flush();
          }
        } finally {
          await output.close();
        }
        return SquareLocalMediaDraft(
          mediaKind: media.mediaKind,
          path: target.path,
          mediaId: stored.mediaId,
          fileName: media.fileName,
          contentType: media.contentType,
          byteSize: media.byteSize,
          durationSeconds: media.durationSeconds,
          width: media.width,
          height: media.height,
          photoManagerAssetId: media.photoManagerAssetId,
        );
      },
      onInvalidated: () async {
        final dir = createdDirectory;
        if (dir != null && await dir.exists()) {
          await dir.delete(recursive: true);
        }
      },
    );
  }

  /// 删除一条草稿的整个媒体目录；路径不存在时不创建任何目录。
  static Future<void> deleteDir(String cidNumber, String draftId) {
    return _enqueueMutation(() async {
      final dir = await _draftDir(cidNumber, draftId, create: false);
      if (await dir.exists()) await dir.delete(recursive: true);
      final work = await _draftDir(
        cidNumber,
        draftId,
        create: false,
        temporary: true,
      );
      if (await work.exists()) await work.delete(recursive: true);
    });
  }

  static Future<T> _enqueueMutation<T>(
    Future<T> Function() action, {
    Future<void> Function()? onInvalidated,
  }) {
    if (identical(Zone.current[_operationZoneKey], true)) {
      throw StateError('禁止在广场草稿文件操作内再次进入同一文件队列。');
    }
    if (_lifecycle != _ComposeDraftMediaLifecycle.active) {
      throw StateError('广场草稿文件域已关闭，禁止继续写入。');
    }

    final generation = _generation;
    final previous = _operationTail;
    final completer = Completer<T>();
    _operationTail = completer.future.then<void>((_) {}, onError: (_) {});
    () async {
      try {
        await previous.catchError((_) {});
        if (_lifecycle != _ComposeDraftMediaLifecycle.active ||
            generation != _generation) {
          throw StateError('广场草稿文件域已关闭，排队操作已取消。');
        }
        final result = await runZoned(
          action,
          zoneValues: <Object?, Object?>{_operationZoneKey: true},
        );
        if (_lifecycle != _ComposeDraftMediaLifecycle.active ||
            generation != _generation) {
          throw StateError('广场草稿文件域已关闭，旧操作结果已取消。');
        }
        completer.complete(result);
      } catch (error, stackTrace) {
        // 擦除后晚到的操作即使在数据库读取阶段失败，也必须清除已创建的处理目录。
        if (_lifecycle != _ComposeDraftMediaLifecycle.active ||
            generation != _generation) {
          try {
            await onInvalidated?.call();
          } catch (cleanupError, cleanupStack) {
            completer.completeError(cleanupError, cleanupStack);
            return;
          }
        }
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  /// AppLock 显式安全擦除调用；只删除旧草稿目录和可再生的媒体工作目录。
  static Future<void> closeAndDeleteAll({
    Future<Directory> Function()? documentsDirectoryProvider,
  }) {
    final inFlight = _closing;
    if (_lifecycle == _ComposeDraftMediaLifecycle.closing && inFlight != null) {
      return inFlight;
    }

    _lifecycle = _ComposeDraftMediaLifecycle.closing;
    _generation += 1;
    late final Future<void> task;
    task = _closeAndDeleteInternal(documentsDirectoryProvider).whenComplete(() {
      _lifecycle = _ComposeDraftMediaLifecycle.closed;
      if (identical(_closing, task)) _closing = null;
    });
    _closing = task;
    return task;
  }

  static Future<void> _closeAndDeleteInternal(
    Future<Directory> Function()? documentsDirectoryProvider,
  ) async {
    try {
      await _operationTail.timeout(_drainTimeout);
    } on TimeoutException {
      // 晚到写入会在完成后检查 generation 并删除自己创建的草稿目录。
    }
    final root = await _root(
      create: false,
      documentsDirectoryProvider: documentsDirectoryProvider,
    );
    if (await root.exists()) await root.delete(recursive: true);
    final work = await _temporaryRoot(
      create: false,
      directoryProvider: documentsDirectoryProvider,
    );
    if (await work.exists()) await work.delete(recursive: true);
  }

  @visibleForTesting
  static Future<void> resetForTest({
    Future<Directory> Function()? documentsDirectoryProvider,
  }) async {
    await closeAndDeleteAll(
      documentsDirectoryProvider: documentsDirectoryProvider,
    );
    _operationTail = Future<void>.value();
    _closing = null;
    _generation += 1;
    _lifecycle = _ComposeDraftMediaLifecycle.active;
  }
}
