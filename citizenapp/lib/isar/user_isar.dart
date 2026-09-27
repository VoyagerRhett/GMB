import 'dart:async';

import 'package:isar_community/isar.dart';

import 'isar_core_bootstrap.dart';

part 'user_isar.g.dart';

/// 按永久 CID 保存的公开资料离线缓存。
@collection
class UserPublicProfileCacheEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String cidNumber;

  late String profileJson;
}

/// 身份展示唯一快照；CID 供徽章读取，账户用于恢复完整身份及已验证未注册状态。
///
/// 本行只服务离线展示，不能作为发布、投票或其它授权判断依据。
@collection
class UserIdentityBadgeSnapshotEntity {
  Id id = Isar.autoIncrement;

  @Index()
  late String cidNumber;

  /// 尚未完整验真的既有徽章没有账户归属，不能作为当前账户的完整身份。
  @Index()
  String? accountId;

  /// null 表示仅有徽章；JSON null 表示该账户已经验真为未注册。
  String? identitySnapshotJson;

  late String identityLevel;
  late int updatedAtMillis;
}

/// 通讯录域的加密本地状态。
///
/// [stateKind] 明确区分联系人表、待同步操作、同步状态、换绑清单、换绑暂存密文和不可
/// 访问归档；本集合不能承载其它 User 数据。密文的 AAD 继续绑定完整 [stateKey]。
@collection
class UserContactStateEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String stateKey;

  @Index()
  late String ownerCidNumber;

  @Index()
  late String stateKind;

  late String sealedPayload;
}

/// 通用用户设置和 App 展示状态。
///
/// 钱包排序、活动钱包、设备锁和安全失败计数不属于本行。
@collection
class UserSettingsEntity {
  Id id = 0;

  bool permissionGuideSeen = false;
  bool openChatOnLaunch = false;
  List<String> governanceProvincialCouncilOrder = const [];
  List<String> governanceProvincialBankOrder = const [];
  int updatedAtMillis = 0;
}

/// 按订阅者永久 CID 隔离的公权机构关注关系。
@collection
class UserPublicInstitutionSubscriptionEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String subscriptionKey;

  @Index()
  late String subscriberCidNumber;

  late String institutionCidNumber;
  late int subscribedAtMillis;
}

enum _UserIsarLifecycle { active, closing, closed }

class _UserOpeningCancelled implements Exception {
  const _UserOpeningCancelled([this.cleanupError]);

  final Object? cleanupError;
}

/// 用户域独立数据库。
///
/// UserIsar 拥有自己的文件、schema、队列和关闭终态。回调内只允许访问 UserIsar；
/// 钱包能力、密码学、网络、平台通道、文件和其它业务数据库必须在回调外完成。
class UserIsar {
  UserIsar._();

  static final UserIsar instance = UserIsar._();

  static final Object _operationZoneKey = Object();

  Isar? _isar;
  Future<Isar>? _opening;
  Future<bool>? _deleteInFlight;
  Future<void>? _closing;
  Future<void> _operationTail = Future<void>.value();
  bool _operationActive = false;
  _UserIsarLifecycle _lifecycle = _UserIsarLifecycle.active;
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

  /// User 域唯一 schema 清单。
  static const List<CollectionSchema<dynamic>> _schemas =
      <CollectionSchema<dynamic>>[
        UserPublicProfileCacheEntitySchema,
        UserIdentityBadgeSnapshotEntitySchema,
        UserContactStateEntitySchema,
        UserSettingsEntitySchema,
        UserPublicInstitutionSubscriptionEntitySchema,
      ];

  bool get hasActiveOperation => _operationActive;

  /// 读取用户选择的 App 首页；缺省值固定为广场，不从其它存储推断。
  Future<bool> readOpenChatOnLaunch() {
    return read((isar) async {
      final settings = await isar.userSettingsEntitys.get(0);
      return settings?.openChatOnLaunch ?? false;
    });
  }

  /// 原子保存首页选择；本偏好只属于 UserIsar，不进入平台安全存储。
  Future<void> writeOpenChatOnLaunch(bool value) {
    return writeTxn((isar) async {
      final settings =
          await isar.userSettingsEntitys.get(0) ?? UserSettingsEntity();
      settings
        ..id = 0
        ..openChatOnLaunch = value
        ..updatedAtMillis = DateTime.now().millisecondsSinceEpoch;
      await isar.userSettingsEntitys.put(settings);
    });
  }

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
      if (_lifecycle != _UserIsarLifecycle.active ||
          generation != _generation) {
        throw const _UserOpeningCancelled();
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
      throw StateError('禁止在 UserIsar 操作回调内再次进入 UserIsar；请先返回快照。');
    }
    _ensureActive();

    final generation = _generation;
    final previous = _operationTail;
    final completer = Completer<T>();
    _operationTail = completer.future.then<void>((_) {}, onError: (_) {});

    () async {
      try {
        await previous.catchError((_) {});
        if (_lifecycle != _UserIsarLifecycle.active ||
            generation != _generation) {
          throw StateError('UserIsar 已关闭，禁止继续执行或重新打开数据库。');
        }
        _operationActive = true;
        final result = await runZoned(
          () => _runWithBusyRetry(action),
          zoneValues: <Object?, Object?>{_operationZoneKey: this},
        );
        if (_lifecycle != _UserIsarLifecycle.active ||
            generation != _generation) {
          throw StateError('UserIsar 已关闭，旧操作结果已取消。');
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
    if (_lifecycle != _UserIsarLifecycle.active) {
      throw StateError('UserIsar 已关闭，禁止继续执行或重新打开数据库。');
    }
  }

  Future<Isar> _openForGeneration(int generation) async {
    final opened = await _open();
    if (_lifecycle == _UserIsarLifecycle.active && generation == _generation) {
      return opened;
    }
    try {
      final deleted = await _deleteInstance(opened)
          .timeout(_forcedDeleteTimeout);
      if (!deleted) throw StateError('User 数据库仍被其它实例持有，未实际删除。');
      throw const _UserOpeningCancelled();
    } catch (error) {
      if (error is _UserOpeningCancelled) rethrow;
      throw _UserOpeningCancelled(error);
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

    final existing = Isar.getInstance('citizenapp_user');
    if (existing != null && existing.isOpen) {
      try {
        existing.userPublicProfileCacheEntitys;
        existing.userIdentityBadgeSnapshotEntitys;
        existing.userContactStateEntitys;
        existing.userSettingsEntitys;
        existing.userPublicInstitutionSubscriptionEntitys;
      } catch (error) {
        throw StateError('已打开的 UserIsar 不是当前完整 schema：$error');
      }
      return existing;
    }

    return Isar.open(
      _schemas,
      name: 'citizenapp_user',
      directory: await IsarCoreBootstrap.resolveDirectory(),
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
    _lifecycle = _UserIsarLifecycle.active;
  }

  /// 只供既有 AppLock 显式安全擦除；普通启动和读取绝不调用本方法。
  Future<void> closeAndDeleteFromDisk() {
    final inFlight = _closing;
    if (_lifecycle == _UserIsarLifecycle.closing && inFlight != null) {
      return inFlight;
    }

    _lifecycle = _UserIsarLifecycle.closing;
    _generation += 1;
    late final Future<void> task;
    task = _closeAndDeleteInternal().whenComplete(() {
      _lifecycle = _UserIsarLifecycle.closed;
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
      // 永久等待的 User 操作不能阻止显式安全擦除继续关闭本数据库。
    } catch (error) {
      failures.add('等待 User 操作队列失败：$error');
    }

    final openingAtClose = _opening;
    if (openingAtClose != null) {
      try {
        await openingAtClose.timeout(_openingSettleTimeout);
      } on _UserOpeningCancelled catch (error) {
        if (error.cleanupError != null) {
          failures.add('取消 User 数据库打开后的删除失败：${error.cleanupError}');
        }
      } catch (error) {
        failures.add('等待 User 数据库打开任务失败：$error');
      }
    }

    final candidates = <Isar>[];
    final tracked = _isar;
    final registered = Isar.getInstance('citizenapp_user');
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
        if (!deleted) failures.add('User 数据库仍被其它实例持有，未实际删除。');
      } catch (error) {
        failures.add('强制删除 User 数据库失败：$error');
      }
    }

    final deleting = _deleteInFlight;
    if (deleting != null) {
      deleteWasAttempted = true;
      try {
        final deleted = await deleting.timeout(_forcedDeleteTimeout);
        if (!deleted) failures.add('User 数据库删除没有落盘。');
      } catch (error) {
        failures.add('等待 User 数据库删除落盘失败：$error');
      }
    }

    if (!deleteWasAttempted) {
      try {
        final coldDatabase = await _open().timeout(_openingSettleTimeout);
        final deleted = await coldDatabase
            .close(deleteFromDisk: true)
            .timeout(_forcedDeleteTimeout);
        if (!deleted) failures.add('User 冷数据库删除没有落盘。');
      } catch (error) {
        failures.add('打开并删除 User 冷数据库失败：$error');
      }
    }

    if ((_isar?.isOpen ?? false) == false) _isar = null;
    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
  }
}
