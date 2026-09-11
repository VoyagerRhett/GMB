import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../8964/compose/drafts/compose_draft_media.dart';
import '../8964/profile/services/citizen_profile_cache.dart';
import '../isar/social_isar.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';
import '../isar/app_isar.dart';
import '../isar/user_isar.dart';
import '../isar/wallet_isar.dart';
import '../wallet/core/wallet_manager.dart';
import 'secure_storage.dart';

/// 全量本机数据擦除没有完整成功。
///
/// [failures] 会保留每个失败数据域，调用方不得把部分擦除当成成功退出。
class AppDataWipeException implements Exception {
  AppDataWipeException(List<String> failures)
      : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  @override
  String toString() => 'AppDataWipeException(${failures.join('; ')})';
}

/// PIN 验证的显式终态，避免把“已擦除”误当成普通密码错误继续操作。
enum AppPinVerificationResult {
  verified,
  duressMode,
  rejected,
  locked,
  dataWiped,
}

/// `main()` 在任何业务运行时初始化前的持久擦除预检结果。
enum AppDataWipeStartupResult {
  ready,
  dataWiped,
  retryRequired,
  preflightBlocked,
}

/// 应用锁（6 位 PIN）服务。
///
/// 普通 PIN 以 10 万次、`duress_mode` PIN 以 1 万次
/// PBKDF2-HMAC-SHA256(pin + salt) 形式存储在 SecureStorage 中。
/// 连续 5 次验证错误锁定 24 小时，累计 3 次锁定则清空全部应用数据。
class AppLockService {
  /// 普通应用锁与公民钱包统一使用 10 万次派生。
  static const int appLockPinHashIterations = 100000;

  /// 防共匪密码与公民钱包统一使用 1 万次派生。
  static const int duressModePinHashIterations = 10000;
  static const String _keyPinHash = 'pin_hash';
  static const String _keyPinSalt = 'pin_salt';
  static const String _keyFailCount = 'pin_fail_count';
  static const String _keyLockUntil = 'pin_lock_until';
  static const String _keyLockCount = 'pin_lock_count';
  static const String _keyDuressModePinHash = 'duress_mode_pin_hash';
  static const String _keyDuressModePinSalt = 'duress_mode_pin_salt';
  static const String _keyDuressModeEnabled = 'duress_mode_enabled';

  static const int maxFailAttempts = 5;
  static const int maxLockCount = 3;
  static const Duration lockDuration = Duration(hours: 24);
  static const Duration _wipeStepTimeout = Duration(seconds: 6);
  static Future<AppPinVerificationResult> Function(String)?
      _debugVerifyPinForTest;
  static Future<bool> Function()? _debugIsLockedForTest;
  static Future<void> Function()? _debugRemovePinForTest;
  static Future<void> Function()? _debugWipeAllDataForTest;
  static Future<void> Function()? _debugLatchPersistentWipeForTest;
  static bool _walletHardwareSecretsDeletedInProcess = false;

  /// Widget 测试只注入 PIN 终态，非 `flutter test` 进程一律拒绝。
  @visibleForTesting
  static void debugConfigureForTest({
    Future<AppPinVerificationResult> Function(String)? verifyPin,
    Future<bool> Function()? isLocked,
    Future<void> Function()? removePin,
    Future<void> Function()? wipeAllData,
    Future<void> Function()? latchPersistentWipe,
  }) {
    _requireFlutterTest();
    _debugVerifyPinForTest = verifyPin;
    _debugIsLockedForTest = isLocked;
    _debugRemovePinForTest = removePin;
    _debugWipeAllDataForTest = wipeAllData;
    _debugLatchPersistentWipeForTest = latchPersistentWipe;
  }

  @visibleForTesting
  static void debugResetForTest() {
    _requireFlutterTest();
    _debugVerifyPinForTest = null;
    _debugIsLockedForTest = null;
    _debugRemovePinForTest = null;
    _debugWipeAllDataForTest = null;
    _debugLatchPersistentWipeForTest = null;
    _walletHardwareSecretsDeletedInProcess = false;
  }

  // PIN 管理
  /// 设置 6 位 PIN。
  static Future<void> setPin(String pin) async {
    _requireSixDigitPin(pin);
    final salt = _generateSalt();
    final hash = await _hash(pin, salt, iterations: appLockPinHashIterations);
    await appSecureStorage.write(key: _keyPinSalt, value: salt);
    await appSecureStorage.write(key: _keyPinHash, value: hash);
    // 重置错误计数
    await appSecureStorage.write(key: _keyFailCount, value: '0');
    await appSecureStorage.delete(key: _keyLockUntil);
    await appSecureStorage.write(key: _keyLockCount, value: '0');
  }

  /// 验证 PIN。
  ///
  /// 返回可区分验证通过、密码错误、24h 锁定和数据已擦除的终态。
  /// 错误达到 [maxFailAttempts] 次时自动触发 24h 锁定。
  /// 锁定达到 [maxLockCount] 次时调用 [wipeAllData] 清空数据。
  static Future<AppPinVerificationResult> verifyPin(String pin) async {
    final debugVerify = _debugVerifyPinForTest;
    if (debugVerify != null) {
      _requireFlutterTest();
      return debugVerify(pin);
    }
    // 锁定中不允许验证
    if (await isLocked()) return AppPinVerificationResult.locked;

    final normalHash = await appSecureStorage.read(key: _keyPinHash);
    final normalSalt = await appSecureStorage.read(key: _keyPinSalt);
    if (normalHash == null || normalSalt == null) {
      return AppPinVerificationResult.rejected;
    }

    // 普通密码是高频路径，一次派生即可进入；未命中时才继续识别防共匪密码。
    final inputNormalHash = await _hash(
      pin,
      normalSalt,
      iterations: appLockPinHashIterations,
    );
    if (inputNormalHash == normalHash) {
      await appSecureStorage.write(key: _keyFailCount, value: '0');
      return AppPinVerificationResult.verified;
    }

    // 防共匪密码命中时不改动普通密码错误计数。
    if (await _matchesDuressModePin(pin)) {
      return AppPinVerificationResult.duressMode;
    }
    return _recordRejectedPin();
  }

  /// 只验证普通应用锁密码，供关闭应用锁使用；该入口永不触发防共匪模式。
  static Future<AppPinVerificationResult> verifyNormalPin(String pin) async {
    final debugVerify = _debugVerifyPinForTest;
    if (debugVerify != null) {
      _requireFlutterTest();
      return debugVerify(pin);
    }
    if (await isLocked()) return AppPinVerificationResult.locked;
    return _verifyNormalPin(pin);
  }

  static Future<AppPinVerificationResult> _verifyNormalPin(String pin) async {
    final storedHash = await appSecureStorage.read(key: _keyPinHash);
    final storedSalt = await appSecureStorage.read(key: _keyPinSalt);
    if (storedHash == null || storedSalt == null) {
      return AppPinVerificationResult.rejected;
    }

    final inputHash = await _hash(
      pin,
      storedSalt,
      iterations: appLockPinHashIterations,
    );
    if (inputHash == storedHash) {
      // 验证成功，重置错误计数
      await appSecureStorage.write(key: _keyFailCount, value: '0');
      return AppPinVerificationResult.verified;
    }

    return _recordRejectedPin();
  }

  static Future<AppPinVerificationResult> _recordRejectedPin() async {
    // 两类密码均未命中后，才累计一次普通应用锁错误。
    final failCount = await _readInt(_keyFailCount) + 1;
    await appSecureStorage.write(
      key: _keyFailCount,
      value: failCount.toString(),
    );

    if (failCount >= maxFailAttempts) {
      final lockCount = await _readInt(_keyLockCount) + 1;
      await appSecureStorage.write(
        key: _keyLockCount,
        value: lockCount.toString(),
      );
      await appSecureStorage.write(key: _keyFailCount, value: '0');

      if (lockCount >= maxLockCount) {
        await wipeAllData();
        return AppPinVerificationResult.dataWiped;
      }

      // 锁定 24 小时
      final lockUntil = DateTime.now().add(lockDuration).millisecondsSinceEpoch;
      await appSecureStorage.write(
        key: _keyLockUntil,
        value: lockUntil.toString(),
      );
      return AppPinVerificationResult.locked;
    }

    return AppPinVerificationResult.rejected;
  }

  /// 关闭应用锁（验证后调用）。
  static Future<void> removePin() async {
    final debugRemove = _debugRemovePinForTest;
    if (debugRemove != null) {
      _requireFlutterTest();
      return debugRemove();
    }
    await appSecureStorage.delete(key: _keyPinHash);
    await appSecureStorage.delete(key: _keyPinSalt);
    await appSecureStorage.delete(key: _keyFailCount);
    await appSecureStorage.delete(key: _keyLockUntil);
    await appSecureStorage.delete(key: _keyLockCount);
    await removeDuressMode();
  }

  /// 设置独立的 6 位防共匪密码。与普通应用锁密码相同则拒绝保存。
  static Future<bool> setDuressModePin(String pin) async {
    _requireSixDigitPin(pin);
    final normalHash = await appSecureStorage.read(key: _keyPinHash);
    final normalSalt = await appSecureStorage.read(key: _keyPinSalt);
    if (normalHash == null || normalSalt == null) return false;
    if (await _hash(pin, normalSalt, iterations: appLockPinHashIterations) ==
        normalHash) {
      return false;
    }

    final salt = _generateSalt();
    await appSecureStorage.write(key: _keyDuressModePinSalt, value: salt);
    await appSecureStorage.write(
      key: _keyDuressModePinHash,
      value: await _hash(pin, salt, iterations: duressModePinHashIterations),
    );
    await appSecureStorage.write(key: _keyDuressModeEnabled, value: 'true');
    return isDuressModeEnabled();
  }

  /// 防共匪模式只有在普通应用锁存在且三项状态完整时才视为开启。
  static Future<bool> isDuressModeEnabled() async {
    if (!await isPinSet()) return false;
    final enabled = await appSecureStorage.read(key: _keyDuressModeEnabled);
    final hash = await appSecureStorage.read(key: _keyDuressModePinHash);
    final salt = await appSecureStorage.read(key: _keyDuressModePinSalt);
    return enabled == 'true' &&
        hash != null &&
        hash.isNotEmpty &&
        salt != null &&
        salt.isNotEmpty;
  }

  static Future<void> removeDuressMode() async {
    await appSecureStorage.delete(key: _keyDuressModePinHash);
    await appSecureStorage.delete(key: _keyDuressModePinSalt);
    await appSecureStorage.delete(key: _keyDuressModeEnabled);
  }

  static Future<bool> _matchesDuressModePin(String pin) async {
    final enabled = await appSecureStorage.read(key: _keyDuressModeEnabled);
    if (enabled != 'true') return false;
    final hash = await appSecureStorage.read(key: _keyDuressModePinHash);
    final salt = await appSecureStorage.read(key: _keyDuressModePinSalt);
    return hash != null &&
        salt != null &&
        await _hash(pin, salt, iterations: duressModePinHashIterations) == hash;
  }

  /// 是否已设置 PIN。
  static Future<bool> isPinSet() async {
    final hash = await appSecureStorage.read(key: _keyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  // 锁定状态
  /// 当前是否处于 24h 锁定期。
  static Future<bool> isLocked() async {
    final debugLocked = _debugIsLockedForTest;
    if (debugLocked != null) {
      _requireFlutterTest();
      return debugLocked();
    }
    final lockUntilStr = await appSecureStorage.read(key: _keyLockUntil);
    if (lockUntilStr == null) return false;
    final lockUntil = int.tryParse(lockUntilStr);
    if (lockUntil == null) return false;
    return DateTime.now().millisecondsSinceEpoch < lockUntil;
  }

  /// 剩余锁定秒数（未锁定返回 0）。
  static Future<int> getRemainingLockSeconds() async {
    final lockUntilStr = await appSecureStorage.read(key: _keyLockUntil);
    if (lockUntilStr == null) return 0;
    final lockUntil = int.tryParse(lockUntilStr);
    if (lockUntil == null) return 0;
    final remaining = lockUntil - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? remaining ~/ 1000 : 0;
  }

  /// 当前连续错误次数。
  static Future<int> getFailCount() async => _readInt(_keyFailCount);

  /// 当前累计锁定次数。
  static Future<int> getLockCount() async => _readInt(_keyLockCount);

  /// 新进程只有在无 marker，或上一进程已完整擦除后才允许启动。
  ///
  /// pending 会无 PIN 重试全量擦除；无论重试成功还是失败，当前
  /// 进程都只能显示擦除终态并退出，不得继续构造 ChatSdk。
  static Future<AppDataWipeStartupResult> recoverPersistentWipeAtStartup({
    Future<void> Function()? debugDeleteSecureStorage,
    Future<void> Function()? debugClearSharedPreferences,
    Future<Directory> Function()? debugChatDocumentsDirectoryProvider,
  }) async {
    if (debugDeleteSecureStorage != null ||
        debugClearSharedPreferences != null ||
        debugChatDocumentsDirectoryProvider != null) {
      _requireFlutterTest();
    }
    try {
      // 普通启动只验证擦除门闩；没有 marker 时不得等待正常 Chat 后台收件，
      // 否则 FCM/APNs 唤醒与用户冷启动重叠会被误判成数据安全故障。
      final initialState = await ChatRuntimeCore.readPersistentAppDataWipeState(
        documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
      );
      if (initialState == ChatPersistentWipeState.none) {
        return AppDataWipeStartupResult.ready;
      }
      return await ChatRuntimeCore.runStartupPreflight(
        // barrier 覆盖 CID artifact 清理、wipe marker 判定与完整恢复，不能在
        // 中间释放后让后台 isolate 插入新 lease。
        operation: () async {
          final state = await ChatRuntimeCore.readPersistentAppDataWipeState(
            documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
          );
          switch (state) {
            case ChatPersistentWipeState.none:
              return AppDataWipeStartupResult.ready;
            case ChatPersistentWipeState.complete:
              try {
                await ChatRuntimeCore.clearCompletedPersistentAppDataWipe(
                  documentsDirectoryProvider:
                      debugChatDocumentsDirectoryProvider,
                );
                return AppDataWipeStartupResult.ready;
              } catch (_) {
                debugPrint('wipe_preflight:complete_cleanup_failed');
                return AppDataWipeStartupResult.preflightBlocked;
              }
            case ChatPersistentWipeState.pending:
              try {
                await wipeAllData(
                  debugDeleteSecureStorage: debugDeleteSecureStorage,
                  debugClearSharedPreferences: debugClearSharedPreferences,
                  debugChatDocumentsDirectoryProvider:
                      debugChatDocumentsDirectoryProvider,
                );
                return AppDataWipeStartupResult.dataWiped;
              } catch (_) {
                return AppDataWipeStartupResult.retryRequired;
              }
          }
        },
        documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
      );
    } catch (error) {
      // 无法读取 marker 不等于已经开始过 wipe：普通启动绝不得
      // 因路径/文件系统故障擅自删数据，只能 fail-closed 并退出重试。
      debugPrint('wipe_preflight:blocked:${error.runtimeType}');
      return AppDataWipeStartupResult.preflightBlocked;
    }
  }

  /// 在退出前先把跨重启擦除意图落盘；未成功落盘时调用方不得退出。
  static Future<void> latchPersistentWipe({
    Future<Directory> Function()? debugChatDocumentsDirectoryProvider,
  }) {
    final debugLatch = _debugLatchPersistentWipeForTest;
    if (debugLatch != null) {
      _requireFlutterTest();
      if (debugChatDocumentsDirectoryProvider != null) {
        throw StateError('禁止同时使用两组 AppLock 测试注入');
      }
      return debugLatch();
    }
    if (debugChatDocumentsDirectoryProvider != null) _requireFlutterTest();
    return ChatRuntimeCore.beginPersistentAppDataWipe(
      documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
    ).timeout(_wipeStepTimeout);
  }

  // 数据清空
  /// 清空全部应用数据：各业务 Isar DB、Chat 文件树、SecureStorage 与偏好设置。
  ///
  /// 第一阶段先同步终止 ChatSdk 与各业务 Isar 生产者，并有界等待其收口；
  /// 第二阶段才最终清理 SecureStorage 与 SharedPreferences。任一域失败
  /// 也不会阻止后续域尝试，但绝不返回成功。Chat 文件域只允许删除
  /// Documents 下的 `chat/` 子树，跨 isolate marker 保留到进程退出。
  /// 全部尝试结束后通过 [AppDataWipeException] 聚合暴露失败。
  static Future<void> wipeAllData({
    Future<void> Function()? debugDeleteSecureStorage,
    Future<void> Function()? debugClearSharedPreferences,
    Future<Directory> Function()? debugChatDocumentsDirectoryProvider,
  }) async {
    final debugWipe = _debugWipeAllDataForTest;
    if (debugWipe != null) {
      _requireFlutterTest();
      if (debugDeleteSecureStorage != null ||
          debugClearSharedPreferences != null ||
          debugChatDocumentsDirectoryProvider != null) {
        throw StateError('禁止同时使用两组 AppLock 测试注入');
      }
      return debugWipe();
    }
    if (debugDeleteSecureStorage != null ||
        debugClearSharedPreferences != null ||
        debugChatDocumentsDirectoryProvider != null) {
      _requireFlutterTest();
    }
    final failures = <String>[];
    final deleteSecureStorage =
        debugDeleteSecureStorage ?? _deleteAndVerifySecureStorage;
    final clearSharedPreferences =
        debugClearSharedPreferences ?? _clearAndVerifySharedPreferences;

    var persistentGateReady = false;
    Object? persistentGateError;
    try {
      await ChatRuntimeCore.beginPersistentAppDataWipe(
        documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
      ).timeout(_wipeStepTimeout);
      persistentGateReady = true;
    } catch (error) {
      persistentGateError = error;
    }

    // 先关闭可能继续写入秘密的 Chat 生产者，再按“硬件密钥 -> 通用安全存储 ->
    // 数据库和文件”执行。libmdbx 的进程级实例注册表不保证多个不同 schema 同时
    // cold-open/delete，因此各业务域仍逐项处理并准确归因失败。
    await _attemptWipe(
      'ChatFiles',
      () => ChatRuntimeCore.closeAndDeleteLocalFiles(
        documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
      ),
      failures,
    );
    var walletSecretsDeleted = _walletHardwareSecretsDeletedInProcess;
    if (!walletSecretsDeleted) {
      final walletFailureCountBefore = failures.length;
      await _attemptWipe(
        'WalletHardwareSecrets',
        () => WalletManager().wipeAllLocalSecretsBeforeDatabaseDeletion(),
        failures,
      );
      walletSecretsDeleted = failures.length == walletFailureCountBefore;
      if (walletSecretsDeleted) {
        _walletHardwareSecretsDeletedInProcess = true;
      }
    }
    // begin 调用超时不代表原子 marker 没有完成落盘；读取持久态后再决定是否允许
    // 删除平台安全存储，避免把一次迟到的成功错误降级成跳过密钥清理。
    if (!persistentGateReady) {
      try {
        final state = await ChatRuntimeCore.readPersistentAppDataWipeState(
          documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
        ).timeout(_wipeStepTimeout);
        persistentGateReady = state != ChatPersistentWipeState.none;
      } catch (error) {
        persistentGateError ??= error;
      }
    }
    if (persistentGateReady && walletSecretsDeleted) {
      await _attemptWipe('SecureStorage', deleteSecureStorage, failures);
    } else if (!persistentGateReady) {
      failures.add('持久擦除门闩：${persistentGateError ?? '未能落盘'}');
      failures.add('SecureStorage：持久擦除门闩未就绪，已安全跳过');
    } else {
      failures.add('SecureStorage：硬件密钥未全部确认删除，已安全保留重试索引');
    }
    if (walletSecretsDeleted) {
      await _attemptWipe(
        'WalletIsar',
        WalletIsar.instance.closeAndDeleteFromDisk,
        failures,
      );
    } else {
      failures.add('WalletIsar：硬件密钥未全部确认删除，已安全保留重试索引');
    }
    await _attemptWipe(
      'ChatIsar',
      ChatIsar.instance.closeAndDeleteFromDisk,
      failures,
    );
    await _attemptWipe(
      'SocialIsar',
      SocialIsar.instance.closeAndDeleteFromDisk,
      failures,
    );
    await _attemptWipe(
      'UserIsar',
      UserIsar.instance.closeAndDeleteFromDisk,
      failures,
    );
    await _attemptWipe(
      'UserProfileFiles',
      CitizenProfileMediaCache(
        // 测试复用同一临时根目录，避免调用未注册的平台 path_provider；生产为 null
        // 时仍严格使用 Application Support/user/profile_media。
        supportDirectoryProvider: debugChatDocumentsDirectoryProvider,
      ).closeAndDeleteAll,
      failures,
    );
    await _attemptWipe(
      'AppIsar',
      AppIsar.instance.closeAndDeleteFromDisk,
      failures,
    );
    await _attemptWipe(
      'SocialFiles',
      () => ComposeDraftMedia.closeAndDeleteAll(
        documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
      ),
      failures,
    );

    if (persistentGateReady && walletSecretsDeleted) {
      await _attemptWipe('SharedPreferences', clearSharedPreferences, failures);
    } else {
      failures.add('SharedPreferences：关键擦除前置条件未完成，已安全跳过');
    }

    if (failures.isEmpty) {
      await _attemptWipe(
        '持久擦除完成态',
        () => ChatRuntimeCore.markPersistentAppDataWipeComplete(
          documentsDirectoryProvider: debugChatDocumentsDirectoryProvider,
        ),
        failures,
      );
    }

    if (failures.isNotEmpty) {
      throw AppDataWipeException(failures);
    }
  }

  static Future<void> _deleteAndVerifySecureStorage() async {
    await appSecureStorage.deleteAll();
    if ((await appSecureStorage.readAll()).isNotEmpty) {
      throw StateError('安全存储仍有残留');
    }
  }

  static Future<void> _clearAndVerifySharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.clear() || prefs.getKeys().isNotEmpty) {
      throw StateError('偏好设置仍有残留');
    }
  }

  static Future<void> _attemptWipe(
    String dataDomain,
    Future<void> Function() operation,
    List<String> failures,
  ) async {
    try {
      await Future<void>.sync(operation).timeout(_wipeStepTimeout);
    } catch (error) {
      failures.add('$dataDomain：$error');
    }
  }

  static void _requireFlutterTest() {
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      throw UnsupportedError('AppLock 测试注入仅允许 flutter test 进程');
    }
  }

  // 内部工具
  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 按密码用途执行固定次数的 PBKDF2-HMAC-SHA256，并在辅助 isolate 中派生。
  ///
  /// 密集计算不得占用 Flutter 主 isolate，否则第六位输入后会阻塞触控和绘制。
  static Future<String> _hash(
    String pin,
    String salt, {
    required int iterations,
  }) {
    return Isolate.run(() {
      final pinBytes = Uint8List.fromList(utf8.encode(pin));
      final saltBytes = Uint8List.fromList(utf8.encode(salt));
      final output = Uint8List(32);
      try {
        final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
          ..init(Pbkdf2Parameters(saltBytes, iterations, output.length));
        derivator.deriveKey(pinBytes, 0, output, 0);
        return output
            .map((value) => value.toRadixString(16).padLeft(2, '0'))
            .join();
      } finally {
        pinBytes.fillRange(0, pinBytes.length, 0);
        saltBytes.fillRange(0, saltBytes.length, 0);
        output.fillRange(0, output.length, 0);
      }
    });
  }

  static Future<int> _readInt(String key) async {
    final str = await appSecureStorage.read(key: key);
    if (str == null) return 0;
    return int.tryParse(str) ?? 0;
  }

  static void _requireSixDigitPin(String pin) {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', '必须是 6 位数字密码');
    }
  }
}
