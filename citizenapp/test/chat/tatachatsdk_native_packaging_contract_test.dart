import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CitizenApp keeps iOS TataChatSDK staging inside the owning task', () {
    final runner = File('scripts/citizenapp-run.sh').readAsStringSync();
    final testRunner = File('scripts/citizenapp-test.sh').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final podfile = File('ios/Podfile').readAsStringSync();
    final lockfile = File('ios/Podfile.lock').readAsStringSync();

    expect(runner, contains('TATACHATSDK_PACKAGE_IOS_DIR='));
    expect(
      runner,
      contains(r'TATACHATSDK_PACKAGE_IOS_DIR="$TATA_CONSOLE_CACHE_DIR/dependencies/tatachatsdk/ios"'),
    );
    expect(runner, contains(r'verify-ios-package "$IOS_APP"'));
    expect(pubspec, contains('tatachat_sdk:\n    path: ../../TATA/tatachatsdk'));
    // 依赖配置由控制台在本端生成，产品脚本不得创建或清理共享源码状态。
    expect(runner, contains(r'$TATA_CONSOLE_FLUTTER_ROOT/pubspec_overrides.yaml'));
    expect(runner, isNot(contains('cleanup_direct_source_state')));
    expect(runner, isNot(contains(r'rm -f "$TATACHATSDK_ROOT/ios/')));
    expect(testRunner, contains(r'$TATA_CONSOLE_FLUTTER_ROOT/pubspec_overrides.yaml'));
    expect(testRunner, isNot(contains('stage_gmb_mobile_source')));
    expect(podfile, contains('TataChatSDK 通过自身 Flutter FFI plugin'));
    expect(lockfile, contains('- tatachat_sdk (1.0.0)'));
  });
}
