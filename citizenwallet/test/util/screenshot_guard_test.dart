// ScreenshotGuard 引用计数单测:修 HIGH「全局单例子页 dispose 误关父页保护」。
// 多页 enable 时平台开关只在计数 0↔1 边界触发;子页 disable 不关闭父页仍需的保护。
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenwallet/util/screenshot_guard.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('citizenwallet/security');
  const events = MethodChannel('citizenwallet/security_events');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      events,
      (call) async => null,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, null);
  });

  test('两页 enable/disable:平台保护仅在计数 0↔1 切换,子页退出不误关', () async {
    void cbA(String e) {}
    void cbB(String e) {}

    await ScreenshotGuard.enable(cbA); // 父页(如钱包详情揭示助记词)
    await ScreenshotGuard.enable(cbB); // 子页(如账户详情揭示私钥)
    expect(
      calls.where((m) => m == 'enableScreenshotProtection').length,
      1,
      reason: '平台保护只应在首次开启一次',
    );
    expect(calls.contains('disableScreenshotProtection'), isFalse);

    await ScreenshotGuard.disable(cbB); // 子页退出:计数 2→1,不应关闭
    expect(
      calls.contains('disableScreenshotProtection'),
      isFalse,
      reason: '父页仍在用,子页 disable 不得关闭全局保护',
    );

    await ScreenshotGuard.disable(cbA); // 父页退出:计数 1→0,真正关闭
    expect(calls.where((m) => m == 'disableScreenshotProtection').length, 1);
  });

  test('原生启用失败不交付保护租约，重试成功后才允许关闭', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'enableScreenshotProtection' &&
          calls.where((method) => method == call.method).length == 1) {
        throw PlatformException(code: 'protectionUnavailable');
      }
      return null;
    });

    await expectLater(
      ScreenshotGuard.enable(),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, ['enableScreenshotProtection']);
    await ScreenshotGuard.enable();
    await ScreenshotGuard.disable();
    expect(calls.last, 'disableScreenshotProtection');
  });

  test('异步启用和关闭严格按调用顺序到达原生', () async {
    final enabled = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'enableScreenshotProtection') await enabled.future;
      return null;
    });

    final enabling = ScreenshotGuard.enable();
    final disabling = ScreenshotGuard.disable();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['enableScreenshotProtection']);
    enabled.complete();
    await Future.wait([enabling, disabling]);
    expect(calls, [
      'enableScreenshotProtection',
      'disableScreenshotProtection',
    ]);
  });

  test('连续敏感页只建立一次进程级安全事件订阅', () async {
    final eventCalls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, (
      call,
    ) async {
      eventCalls.add(call.method);
      return null;
    });
    await ScreenshotGuard.enable();
    await ScreenshotGuard.disable();
    await ScreenshotGuard.enable();
    await ScreenshotGuard.disable();
    await Future<void>.delayed(Duration.zero);
    expect(
      calls.where((method) => method == 'enableScreenshotProtection').length,
      2,
    );
    expect(
      eventCalls.where((method) => method == 'listen').length,
      lessThanOrEqualTo(1),
    );
    expect(eventCalls.contains('cancel'), isFalse);
  });

  test('iOS 已录屏时拒绝启用且不遗留引用计数', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'enableScreenshotProtection') return true;
      return null;
    });
    await expectLater(ScreenshotGuard.enable(), throwsA(isA<StateError>()));
    expect(calls.last, 'disableScreenshotProtection');
  });

  test('永久应用标识、原生通道和 Isar 静态库输出保持统一', () {
    // 中央校验根只生成当前平台配置；原生源码断言读取链接的真实钱包源码。
    final sourceRoot = File('test/util/screenshot_guard_test.dart')
        .resolveSymbolicLinksSync();
    final root = File(sourceRoot).parent.parent.parent.path;
    File sourceFile(String path) => File('$root/$path');
    final androidBuild = sourceFile('android/app/build.gradle.kts')
        .readAsStringSync();
    final androidEntry = sourceFile(
      'android/app/src/MainActivity.kt',
    ).readAsStringSync();
    final iosProject = sourceFile('ios/Runner.xcodeproj/project.pbxproj')
        .readAsStringSync();
    final iosEntry = sourceFile('ios/Runner/AppDelegate.swift')
        .readAsStringSync();
    final infoPlist = sourceFile('ios/Runner/Info.plist').readAsStringSync();
    final podfile = sourceFile('ios/Podfile').readAsStringSync();

    expect(
      androidBuild,
      contains('applicationId = "com.crcfrcn.citizenwallet"'),
    );
    expect(androidBuild, contains('namespace = "com.crcfrcn.citizenwallet"'));
    expect(androidEntry, contains('package com.crcfrcn.citizenwallet'));
    expect(androidEntry, contains('"citizenwallet/security"'));
    expect(
      iosProject,
      contains('PRODUCT_BUNDLE_IDENTIFIER = ios.citizenwallet;'),
    );
    expect(iosProject, contains('DEVELOPMENT_TEAM = MHYMVRN6FC;'));
    expect(iosEntry, contains('name: "citizenwallet/security"'));
    expect(iosEntry, contains('name: "citizenwallet/security_events"'));
    // 当前销售范围排除法国，App Store Connect 已判定标准加密无须上传文稿。
    expect(
      infoPlist,
      contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
    );
    expect(infoPlist, isNot(contains('ITSEncryptionExportComplianceCode')));
    expect(
      podfile,
      contains(
        r'${PODS_XCFRAMEWORKS_BUILD_DIR}/isar_community_flutter_libs/libisar.a',
      ),
    );
    // 首次 pod install 的 post_install 阶段可能尚无 Isar 支持目录。
    expect(podfile, contains('FileUtils.mkdir_p(isar_support_dir)'));
    expect(podfile, contains('flutter_install_all_ios_pods File.dirname(__FILE__)'));
    expect(podfile, isNot(contains('File.dirname(File.realpath(__FILE__))')));
    expect(
      podfile.indexOf('FileUtils.mkdir_p(isar_support_dir)'),
      lessThan(podfile.indexOf('File.write(\n    isar_output_list')),
    );
    expect(podfile, isNot(contains('isar.framework')));
  });
}
