// 测试隔离:每个测试文件(独立 isolate)用唯一临时目录开各业务 Isar,从物理上根除
// 系统临时目录下同名数据库导致的并发锁竞争(30 秒超时)与磁盘残留污染。
//
// 打开真库的测试文件在 main() 顶部调一次 `useIsolatedIsar();` 即可,不再各自手写
// setUpAll(ensureTestCoreInitialized) / setUp / tearDown(resetForTest) 样板。

import 'dart:io';
import 'dart:typed_data';

import 'package:citizenapp/isar/social_isar.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'package:citizenapp/isar/app_isar.dart';
import 'package:citizenapp/isar/isar_core_bootstrap.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:flutter_test/flutter_test.dart';

/// 聊天本地加密的测试用途子钥（固定 32 字节）。
///
/// 单测没有平台通道，真实路径会走
/// `AccountSecurityService → CitizenSDK/设备金库` 而需要真实平台；
/// 这里注入固定用途子钥，让 `ChatStore` 在测试中走**真实加解密**（不是绕过加密），
/// 只是密钥来源换成确定值。
final Map<LocalKeyPurpose, Uint8List> debugChatKeys =
    <LocalKeyPurpose, Uint8List>{
  LocalKeyPurpose.chat:
      Uint8List.fromList(List<int>.generate(32, (i) => i * 3 % 256)),
  LocalKeyPurpose.chatIndex:
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 5 + 1) % 256)),
};

/// 为当前测试文件挂上隔离的 Isar 生命周期:
/// - setUpAll:建本文件专属临时目录 + 指向它 + 初始化 IsarCore + 注入聊天测试密钥
/// - setUp / tearDown:复位(防入 + 清出)
/// - tearDownAll:复位并删除临时目录
void useIsolatedIsar() {
  late Directory dir;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('citizenapp_test_');
    IsarCoreBootstrap.debugTestDirectoryOverride = dir.path;
    ChatCrypto.debugFixedKeys = <ChatStorageKeyPurpose, Uint8List>{
      ChatStorageKeyPurpose.chat: debugChatKeys[LocalKeyPurpose.chat]!,
      ChatStorageKeyPurpose.chatIndex:
          debugChatKeys[LocalKeyPurpose.chatIndex]!,
    };
    await IsarCoreBootstrap.ensureTestCoreInitialized();
  });
  setUp(() async {
    await _resetAllIsar();
  });
  tearDown(() async {
    await _resetAllIsar();
  });
  tearDownAll(() async {
    await _resetAllIsar();
    IsarCoreBootstrap.debugTestDirectoryOverride = null;
    ChatCrypto.debugFixedKeys = null;
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
}

Future<void> _resetAllIsar() async {
  // libmdbx 的进程级实例注册表不保证多个不同 schema 同时 cold-open/delete；
  // 测试复位按域顺序执行，业务运行时的数据库和操作队列仍完全独立。
  await WalletIsar.instance.resetForTest();
  await ChatIsar.instance.resetForTest();
  await SocialIsar.instance.resetForTest();
  await UserIsar.instance.resetForTest();
  await AppIsar.instance.resetForTest();
}
