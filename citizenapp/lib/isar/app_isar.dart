import 'dart:async';

import 'package:isar_community/isar.dart';

import 'isar_core_bootstrap.dart';

part 'app_isar.g.dart';

/// 行政区字典实体。
///
/// 行政区属于全 App 通用目录，不是用户、广场、聊天或区块链事实。
@collection
class AdminDivisionEntity {
  Id id = Isar.autoIncrement;

  /// `"<level>|<province_code>|<city_code>|<town_code>"`。
  @Index(unique: true, replace: true)
  late String divisionKey;

  @Index()
  late String level;

  late String code;

  @Index()
  late String scopeKey;

  late String divisionName;
  String? dictVersion;
}

/// 公权机构公开目录的本机缓存。
///
/// 本集合只保存公开目录事实；用户关注关系保存在 UserIsar，机构多签账户保存在
/// WalletIsar，三者不得共用事务或队列。
@collection
class PublicInstitutionEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String cidNumber;

  late String cidFullName;
  String? cidShortName;
  late String status;

  @Index()
  late String provinceCode;

  @Index()
  late String cityCode;

  String townCode = '';

  @Index()
  late String institutionCode;

  String? parentCidNumber;
  bool? hasLegalPersonality;
  String? familyName;
  String? givenName;
  String? legalRepresentativeCidNumber;
  String? legalRepresentativeAccountId;
  late int accountCount;
  List<String> customAccountNames = const [];
  String? catalogVersion;
  late int updatedAtMillis;
}

/// 通用静态数据版本状态。
@collection
class AppDataVersionEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String namespace;

  String? globalVersion;
  String? provinceVersionsJson;
  int updatedAtMillis = 0;
}

/// 公权机构目录的省级顺序。
@collection
class AppPublicInstitutionCatalogEntity {
  Id id = 0;

  List<String> provinceCodes = const [];
  int updatedAtMillis = 0;
}

/// 单省公权机构目录同步版本。
@collection
class AppPublicInstitutionProvinceVersionEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String provinceCode;

  late String version;
  late int updatedAtMillis;
}

enum _AppIsarLifecycle { active, closing, closed }

class _AppOpeningCancelled implements Exception {
  const _AppOpeningCancelled([this.cleanupError]);

  final Object? cleanupError;
}

/// 通用 App 数据库。
///
/// AppIsar 只承载不属于 Social、Chat、User、Wallet 的全局目录与系统状态，拥有独立
/// 文件、schema、队列与关闭终态。回调内禁止进入其它业务数据库或执行网络、密码学、
/// 平台通道和文件操作；调用方必须先返回不可变快照，再跨域处理。
class AppIsar {
  AppIsar._();

  static final AppIsar instance = AppIsar._();

  static final Object _operationZoneKey = Object();

  Isar? _isar;
  Future<Isar>? _opening;
  Future<bool>? _deleteInFlight;
  Future<void>? _closing;
  Future<void> _operationTail = Future<void>.value();
  bool _operationActive = false;
  _AppIsarLifecycle _lifecycle = _AppIsarLifecycle.active;
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

  /// App 域唯一 schema 清单。
  static const List<CollectionSchema<dynamic>> _schemas =
      <CollectionSchema<dynamic>>[
    AdminDivisionEntitySchema,
    PublicInstitutionEntitySchema,
    AppDataVersionEntitySchema,
    AppPublicInstitutionCatalogEntitySchema,
    AppPublicInstitutionProvinceVersionEntitySchema,
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
      if (_lifecycle != _AppIsarLifecycle.active || generation != _generation) {
        throw const _AppOpeningCancelled();
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
      throw StateError('禁止在 AppIsar 操作回调内再次进入 AppIsar；请先返回快照。');
    }
    _ensureActive();

    final generation = _generation;
    final previous = _operationTail;
    final completer = Completer<T>();
    _operationTail = completer.future.then<void>((_) {}, onError: (_) {});

    () async {
      try {
        await previous.catchError((_) {});
        if (_lifecycle != _AppIsarLifecycle.active ||
            generation != _generation) {
          throw StateError('AppIsar 已关闭，禁止继续执行或重新打开数据库。');
        }
        _operationActive = true;
        final result = await runZoned(
          () => _runWithBusyRetry(action),
          zoneValues: <Object?, Object?>{_operationZoneKey: this},
        );
        if (_lifecycle != _AppIsarLifecycle.active ||
            generation != _generation) {
          throw StateError('AppIsar 已关闭，旧操作结果已取消。');
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
    if (_lifecycle != _AppIsarLifecycle.active) {
      throw StateError('AppIsar 已关闭，禁止继续执行或重新打开数据库。');
    }
  }

  Future<Isar> _openForGeneration(int generation) async {
    final opened = await _open();
    if (_lifecycle == _AppIsarLifecycle.active && generation == _generation) {
      return opened;
    }
    try {
      final deleted =
          await _deleteInstance(opened).timeout(_forcedDeleteTimeout);
      if (!deleted) throw StateError('App 数据库仍被其它实例持有，未实际删除。');
      throw const _AppOpeningCancelled();
    } catch (error) {
      if (error is _AppOpeningCancelled) rethrow;
      throw _AppOpeningCancelled(error);
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

    final existing = Isar.getInstance('citizenapp_app');
    if (existing != null && existing.isOpen) {
      try {
        existing.adminDivisionEntitys;
        existing.publicInstitutionEntitys;
        existing.appDataVersionEntitys;
        existing.appPublicInstitutionCatalogEntitys;
        existing.appPublicInstitutionProvinceVersionEntitys;
      } catch (error) {
        throw StateError('已打开的 AppIsar 不是当前完整 schema：$error');
      }
      return existing;
    }

    return Isar.open(
      _schemas,
      name: 'citizenapp_app',
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
    _lifecycle = _AppIsarLifecycle.active;
  }

  /// 只供既有 AppLock 显式安全擦除；普通启动和读取绝不调用本方法。
  Future<void> closeAndDeleteFromDisk() {
    final inFlight = _closing;
    if (_lifecycle == _AppIsarLifecycle.closing && inFlight != null) {
      return inFlight;
    }

    _lifecycle = _AppIsarLifecycle.closing;
    _generation += 1;
    late final Future<void> task;
    task = _closeAndDeleteInternal().whenComplete(() {
      _lifecycle = _AppIsarLifecycle.closed;
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
      // 永久等待的 App 操作不能阻止显式安全擦除继续关闭本数据库。
    } catch (error) {
      failures.add('等待 App 操作队列失败：$error');
    }

    final openingAtClose = _opening;
    if (openingAtClose != null) {
      try {
        await openingAtClose.timeout(_openingSettleTimeout);
      } on _AppOpeningCancelled catch (error) {
        if (error.cleanupError != null) {
          failures.add('取消 App 数据库打开后的删除失败：${error.cleanupError}');
        }
      } catch (error) {
        failures.add('等待 App 数据库打开任务失败：$error');
      }
    }

    final candidates = <Isar>[];
    final tracked = _isar;
    final registered = Isar.getInstance('citizenapp_app');
    if (tracked != null) candidates.add(tracked);
    if (registered != null && !identical(registered, tracked)) {
      candidates.add(registered);
    }
    for (final candidate in candidates) {
      if (!candidate.isOpen) continue;
      deleteWasAttempted = true;
      try {
        final deleted =
            await _deleteInstance(candidate).timeout(_forcedDeleteTimeout);
        if (!deleted) failures.add('App 数据库仍被其它实例持有，未实际删除。');
      } catch (error) {
        failures.add('强制删除 App 数据库失败：$error');
      }
    }

    final deleting = _deleteInFlight;
    if (deleting != null) {
      deleteWasAttempted = true;
      try {
        final deleted = await deleting.timeout(_forcedDeleteTimeout);
        if (!deleted) failures.add('App 数据库删除没有落盘。');
      } catch (error) {
        failures.add('等待 App 数据库删除落盘失败：$error');
      }
    }

    if (!deleteWasAttempted) {
      try {
        final coldDatabase = await _open().timeout(_openingSettleTimeout);
        final deleted = await coldDatabase
            .close(deleteFromDisk: true)
            .timeout(_forcedDeleteTimeout);
        if (!deleted) failures.add('App 冷数据库删除没有落盘。');
      } catch (error) {
        failures.add('打开并删除 App 冷数据库失败：$error');
      }
    }

    if ((_isar?.isOpen ?? false) == false) _isar = null;
    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
  }
}
