import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CitizenApp consumes TataChatSDK product output without source staging', () {
    final runner = File('scripts/citizenapp-run.sh').readAsStringSync();
    final testRunner = File('scripts/citizenapp-test.sh').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final podfile = File('ios/Podfile').readAsStringSync();
    final lockfile = File('ios/Podfile.lock').readAsStringSync();

    expect(runner, contains('TATACHATSDK_NATIVE_IOS_DIR='));
    expect(runner, contains('ios/TataChatSDK.xcframework'));
    expect(runner, contains('project-framework'));
    expect(runner, isNot(contains('TATACHATSDK_APPLE_FRAMEWORK_DIR')));
    expect(runner, contains(r'verify-ios-package "$IOS_APP"'));
    expect(
      pubspec,
      contains('tatachat_sdk:\n    path: ../../TATA/tatachatsdk'),
    );
    // 本机开发直接读取同工作区SDK源码，不创建第二份override配置。
    expect(runner, isNot(contains('pubspec_overrides.yaml')));
    expect(runner, isNot(contains('cleanup_direct_source_state')));
    expect(runner, isNot(contains(r'rm -f "$TATACHATSDK_ROOT/ios/')));
    expect(runner, contains(r'flutter pub get "${PUB_GET_ARGS[@]}"'));
    expect(runner, contains('flutter build ios --no-pub --release'));
    expect(
      runner,
      contains(r'android/gradlew" ${gradle_network_arg:+"$gradle_network_arg"}'),
    );
    expect(runner, isNot(contains('GRADLE_NETWORK_ARGS')));
    expect(runner, contains('gradle.beforeSettings { settings ->'));
    expect(runner, contains('settings.pluginManagement.repositories'));
    expect(runner, isNot(contains('resolutionStrategy.force')));
    expect(runner, isNot(contains('\nflutter pub get\n')));
    expect(testRunner, isNot(contains('pubspec_overrides.yaml')));
    expect(testRunner, isNot(contains('stage_gmb_mobile_source')));
    expect(
      testRunner,
      contains(r'pub get "${PUB_GET_ARGS[@]}"'),
    );
    expect(podfile, contains('TataChatSDK 通过自身 Flutter FFI plugin'));
    expect(lockfile, contains('- tatachat_sdk (1.0.0)'));
  });
}
