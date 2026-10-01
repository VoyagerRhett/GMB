import 'dart:async';

import 'package:isar_community/isar.dart';

import 'isar_core_bootstrap.dart';

part 'social_isar.g.dart';

/// 用户明确删除的持久事实；确认后保留以阻止迟到同步复活帖子。
@collection
class SquarePostDeletionEntity {
  Id id = Isar.autoIncrement;
  @Index(composite: [CompositeIndex('postId')], unique: true)
  late String cidNumber;
  late String postId;
  late String operationState;
}

/// 本人已发布广场内容的设备本地副本。
///
/// [cidNumber] 是内容归属真源，[accountId] 只记录发布时的链上签名账户事实。
/// 正文与媒体声明只保存已经由内容哈希确认的原始 manifest 字节。
@collection
class SquareLocalPostEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String postId;

  @Index()
  late String cidNumber;

  late String accountId;
  late String postCategory;
  late String postType;
  late List<byte> manifestBytes;
  late String contentHash;
  late String storageReceiptId;
  int? chainBlock;

  @Index()
  late int createdAt;

  late String postState;
}

/// 广场发帖草稿。
///
/// 草稿属于 Social 域，不得借用 WalletIsar 或通用数据库。媒体与文章块使用规范 JSON 保存
/// 是因为它们本身是有序嵌套结构；主键、类型、正文和时间均为显式字段，禁止再把整条
/// 草稿塞进通用 KV。
@collection
class SquareComposeDraftEntity {
  Id id = Isar.autoIncrement;

  /// `cidNumber|draftId` 的唯一键，只用于本地集合唯一性。
  @Index(unique: true, replace: true)
  late String draftKey;

  @Index()
  late String cidNumber;

  late String draftId;
  late String postType;
  String? title;
  late String text;
  late String mediaJson;
  String? contentSectionsJson;

  @Index()
  late int updatedAtMillis;
}

/// 本人广场副本的远端同步检查点。
///
/// 它只记录一次完整回灌结束时的远端事实，不保存设备当前时间。
@collection
class SquarePostSyncCheckpointEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String cidNumber;

  String? newestPostId;
  late int newestCreatedAt;
}

/// 用户明确删除草稿或发布成功后留下的文件清理事实。
///
/// 数据库事务先删除草稿并写入本行，事务外再删除媒体目录；文件系统失败时保留本行，
/// 后续显式重试仍能精确定位。禁止持久化应用容器绝对路径。
@collection
class SquareFileCleanupEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String cleanupKey;

  @Index()
  late String cidNumber;

  late String draftId;
  late String cleanupKind;
  late int createdAtMillis;
  late int attemptCount;
  String? lastError;
}

/// 广场媒体描述；实际内容位于分块集合，不在列表查询中加载。
///
/// 同一媒体标识可以属于不同 CID。complete 只由完整长度和 SHA-256 校验推进，
/// 不代表上传状态；未完成记录允许显式续写，不允许展示或绑定内容。
@collection
class SquareMediaEntity {
  Id id = Isar.autoIncrement;

  @Index(composite: [CompositeIndex('mediaId')], unique: true)
  late String cidNumber;

  late String mediaId;
  late String mediaKind;
  late String contentType;
  late int byteSize;
  late String sha256;
  bool complete = false;
}

/// 一个媒体字节块，最多 1 MiB；chunkIndex 从零开始。
///
/// 唯一索引禁止不同用户或不同块互相覆盖。末块长度由媒体描述确定；分块哈希
/// 用于范围读取校验，不能替代媒体完成前的整体哈希校验。
@collection
class SquareMediaChunkEntity {
  Id id = Isar.autoIncrement;

  @Index(
    composite: [CompositeIndex('mediaId'), CompositeIndex('chunkIndex')],
    unique: true,
  )
  late String cidNumber;

  late String mediaId;
  late int chunkIndex;
  late List<byte> chunkBytes;
  late String chunkSha256;
}

/// 草稿或帖子内的媒体槽位；主图、缩略图、视频封面分别关联。
///
/// referenceKey 是内容类型、内容标识、媒体序号、用途的有序 JSON 数组。
/// 删除槽位不删除媒体；仅无引用的媒体才允许显式删除。
@collection
class SquareMediaReferenceEntity {
  Id id = Isar.autoIncrement;

  @Index(composite: [CompositeIndex('referenceKey')], unique: true)
  late String cidNumber;

  late String referenceKey;

  @Index(composite: [CompositeIndex('cidNumber')])
  late String mediaId;

  @Index(
    composite: [CompositeIndex('cidNumber'), CompositeIndex('contentKind')],
  )
  late String contentId;

  late String contentKind;
  late int mediaIndex;
  late String mediaRole;
}

/// 一次发布的持久恢复事实，不保存会话凭据；交易提交后禁止重新发起同一草稿。
/// 远端确认后与帖子、媒体关联及草稿删除在同一事务中收尾。
@collection
class SquarePublicationEntity {
  Id id = Isar.autoIncrement;

  @Index(composite: [CompositeIndex('draftId')], unique: true)
  late String cidNumber;
  late String draftId;
  late String accountId;
  late String postId;
  late String postType;
  late String contentHash;
  late String storageReceiptId;
  late String uploadId;
  late List<byte> manifestBytes;
  late String publicationState;
  String? replacePostId;
  String? blockHash;
  String? transactionHash;
  String? postCategory;
  int? chainBlock;
  int? createdAt;
}

enum _SocialIsarLifecycle { active, closing, closed }

class _SocialOpeningCancelled implements Exception {
  const _SocialOpeningCancelled([this.cleanupError]);

  final Object? cleanupError;
}

/// 广场域独立数据库。
///
/// SocialIsar 拥有自己的数据库文件、schema、串行队列和关闭终态。广场操作挂起时不得
/// 占用 App、钱包、聊天或用户数据库的队列。回调内只允许访问 SocialIsar；网络、平台、
/// 文件和跨域读取必须在回调外完成。
class SocialIsar {
  SocialIsar._();

  static final SocialIsar instance = SocialIsar._();

  static final Object _operationZoneKey = Object();

  Isar? _isar;
  Future<Isar>? _opening;
  Future<bool>? _deleteInFlight;
  Future<void>? _closing;
  Future<void> _operationTail = Future<void>.value();
  bool _operationActive = false;
  _SocialIsarLifecycle _lifecycle = _SocialIsarLifecycle.active;
  int _generation = 0;

  static const Duration _gracefulDrainTimeout = Duration(milliseconds: 250);
  static const Duration _openingSettleTimeout = Duration(seconds: 2);
  static const Duration _forcedDeleteTimeout = Duration(seconds: 2);

  static const List<Duration> _busyRetryDelays = <Duration>[
    Duration(milliseconds: 80),
    Duration(milliseconds: 160),
    Duration(milliseconds: 320),
    Duration(milliseconds: 640),
    Duration(milliseconds: 1200),
    Duration(milliseconds: 2400),
    Duration(milliseconds: 3600),
    Duration(milliseconds: 5000),
  ];

  /// Social 域的唯一 schema 清单。
  static const List<CollectionSchema<dynamic>> _schemas =
      <CollectionSchema<dynamic>>[
        SquareLocalPostEntitySchema,
        SquarePostDeletionEntitySchema,
        SquareComposeDraftEntitySchema,
        SquarePostSyncCheckpointEntitySchema,
        SquareFileCleanupEntitySchema,
        SquareMediaEntitySchema,
        SquareMediaChunkEntitySchema,
        SquareMediaReferenceEntitySchema,
        SquarePublicationEntitySchema,
      ];

  bool get hasActiveOperation => _operationActive;

  Future<Isar> db() async {
    _ensureActive();

    final current = _isar;
    if (current != null && current.isOpen) return current;

    final opening = _opening;
    if (opening != null) return opening;

    final generation = _generation;
    final task = _openForGeneration(generation);
    _opening = task;
    try {
      final opened = await task;
      if (_lifecycle != _SocialIsarLifecycle.active ||
          generation != _generation) {
        throw const _SocialOpeningCancelled();
      }
      _isar = opened;
      return opened;
    } finally {
      if (identical(_opening, task)) _opening = null;
    }
  }

  Future<T> read<T>(Future<T> Function(Isar isar) action) {
    return _enqueue(() async {
      final isar = await db();
      return action(isar);
    });
  }

  Future<T> writeTxn<T>(Future<T> Function(Isar isar) action) {
    return _enqueue(() async {
      final isar = await db();
      return isar.writeTxn<T>(() => action(isar));
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (identical(Zone.current[_operationZoneKey], this)) {
      throw StateError('禁止在 SocialIsar 操作回调内再次进入 SocialIsar；请先返回快照。');
    }
    _ensureActive();

    final generation = _generation;
    final previous = _operationTail;
    final completer = Completer<T>();
    _operationTail = completer.future.then<void>((_) {}, onError: (_) {});

    () async {
      try {
        await previous.catchError((_) {});
        if (_lifecycle != _SocialIsarLifecycle.active ||
            generation != _generation) {
          throw StateError('SocialIsar 已关闭，禁止继续执行或重新打开数据库。');
        }
        _operationActive = true;
        final result = await runZoned(
          () => _runWithBusyRetry(action),
          zoneValues: <Object?, Object?>{_operationZoneKey: this},
        );
        if (_lifecycle != _SocialIsarLifecycle.active ||
            generation != _generation) {
          throw StateError('SocialIsar 已关闭，旧操作结果已取消。');
        }
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (generation == _generation) _operationActive = false;
      }
    }();

    return completer.future;
  }

  Future<T> _runWithBusyRetry<T>(Future<T> Function() action) async {
    for (var attempt = 0; attempt <= _busyRetryDelays.length; attempt++) {
      try {
        return await action();
      } catch (error) {
        if (!_isBusyError(error) || attempt == _busyRetryDelays.length) {
          rethrow;
        }
        await Future<void>.delayed(_busyRetryDelays[attempt]);
      }
    }
    throw StateError('unreachable');
  }

  bool _isBusyError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('mdbxerror (11)') ||
        raw.contains('try again') ||
        raw.contains('active transaction');
  }

  void _ensureActive() {
    if (_lifecycle != _SocialIsarLifecycle.active) {
      throw StateError('SocialIsar 已关闭，禁止继续执行或重新打开数据库。');
    }
  }

  Future<Isar> _openForGeneration(int generation) async {
    final opened = await _open();
    if (_lifecycle == _SocialIsarLifecycle.active &&
        generation == _generation) {
      return opened;
    }
    try {
      final deleted = await _deleteInstance(opened)
          .timeout(_forcedDeleteTimeout);
      if (!deleted) throw StateError('Social 数据库仍被其它实例持有，未实际删除。');
      throw const _SocialOpeningCancelled();
    } catch (error) {
      if (error is _SocialOpeningCancelled) rethrow;
      throw _SocialOpeningCancelled(error);
    }
  }

  Future<bool> _deleteInstance(Isar isar) {
    final deleting = _deleteInFlight;
    if (deleting != null) return deleting;
    if (!isar.isOpen) return Future<bool>.value(true);

    final task = isar.close(deleteFromDisk: true);
    _deleteInFlight = task;
    task.then<void>(
      (_) {
        if (identical(_deleteInFlight, task)) _deleteInFlight = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_deleteInFlight, task)) _deleteInFlight = null;
      },
    );
    return task;
  }

  Future<Isar> _open() async {
    await IsarCoreBootstrap.ensureTestCoreInitialized();

    final existing = Isar.getInstance('citizenapp_social');
    if (existing != null && existing.isOpen) {
      try {
        existing.squareLocalPostEntitys;
        existing.squarePostDeletionEntitys;
        existing.squareComposeDraftEntitys;
        existing.squarePostSyncCheckpointEntitys;
        existing.squareFileCleanupEntitys;
        existing.squareMediaEntitys;
        existing.squareMediaChunkEntitys;
        existing.squareMediaReferenceEntitys;
        existing.squarePublicationEntitys;
      } catch (error) {
        throw StateError('已打开的 SocialIsar 不是当前完整 schema：$error');
      }
      return existing;
    }

    return Isar.open(
      _schemas,
      name: 'citizenapp_social',
      directory: await IsarCoreBootstrap.resolveDirectory(),
      // 媒体完整标记只能在持久提交后返回；不能用异步落盘承诺允许清理原内容。
      relaxedDurability: false,
      // 媒体分块仍共享一个广场库；容量达到上限时明确失败，禁止淘汰用户内容。
      maxSizeMiB: 64 * 1024,
    );
  }

  Future<void> resetForTest() async {
    if (!IsarCoreBootstrap.isFlutterTest) return;
    await closeAndDeleteFromDisk();
    _isar = null;
    _opening = null;
    _deleteInFlight = null;
    _closing = null;
    _operationTail = Future<void>.value();
    _operationActive = false;
    _generation += 1;
    _lifecycle = _SocialIsarLifecycle.active;
  }

  /// 既有 AppLock 显式擦除入口调用；普通启动和读取绝不调用本方法。
  Future<void> closeAndDeleteFromDisk() {
    final inFlight = _closing;
    if (_lifecycle == _SocialIsarLifecycle.closing && inFlight != null) {
      return inFlight;
    }

    _lifecycle = _SocialIsarLifecycle.closing;
    _generation += 1;
    late final Future<void> task;
    task = _closeAndDeleteInternal().whenComplete(() {
      _lifecycle = _SocialIsarLifecycle.closed;
      if (identical(_closing, task)) _closing = null;
    });
    _closing = task;
    return task;
  }

  Future<void> _closeAndDeleteInternal() async {
    final failures = <String>[];
    final tailAtClose = _operationTail;
    var deleteWasAttempted = false;

    try {
      await tailAtClose.timeout(_gracefulDrainTimeout);
    } on TimeoutException {
      // 永久等待的 Social 操作不能阻止显式安全擦除继续关闭本数据库。
    } catch (error) {
      failures.add('等待 Social 操作队列失败：$error');
    }

    final openingAtClose = _opening;
    if (openingAtClose != null) {
      try {
        await openingAtClose.timeout(_openingSettleTimeout);
      } on _SocialOpeningCancelled catch (error) {
        if (error.cleanupError != null) {
          failures.add('取消 Social 数据库打开后的删除失败：${error.cleanupError}');
        }
      } catch (error) {
        failures.add('等待 Social 数据库打开任务失败：$error');
      }
    }

    final candidates = <Isar>[];
    final tracked = _isar;
    final registered = Isar.getInstance('citizenapp_social');
    if (tracked != null) candidates.add(tracked);
    if (registered != null && !identical(registered, tracked)) {
      candidates.add(registered);
    }
    for (final candidate in candidates) {
      if (!candidate.isOpen) continue;
      deleteWasAttempted = true;
      try {
        final deleted = await _deleteInstance(candidate)
            .timeout(_forcedDeleteTimeout);
        if (!deleted) failures.add('Social 数据库仍被其它实例持有，未实际删除。');
      } catch (error) {
        failures.add('强制删除 Social 数据库失败：$error');
      }
    }

    final deleting = _deleteInFlight;
    if (deleting != null) {
      deleteWasAttempted = true;
      try {
        final deleted = await deleting.timeout(_forcedDeleteTimeout);
        if (!deleted) failures.add('Social 数据库删除没有落盘。');
      } catch (error) {
        failures.add('等待 Social 数据库删除落盘失败：$error');
      }
    }

    if (!deleteWasAttempted) {
      try {
        final coldDatabase = await _open().timeout(_openingSettleTimeout);
        final deleted = await coldDatabase
            .close(deleteFromDisk: true)
            .timeout(_forcedDeleteTimeout);
        if (!deleted) failures.add('Social 冷数据库删除没有落盘。');
      } catch (error) {
        failures.add('打开并删除 Social 冷数据库失败：$error');
      }
    }

    if ((_isar?.isOpen ?? false) == false) _isar = null;
    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
  }
}
