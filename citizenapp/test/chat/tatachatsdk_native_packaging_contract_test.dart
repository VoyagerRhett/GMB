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
      contains(
        r'TATACHATSDK_PACKAGE_IOS_DIR="$TATA_CONSOLE_FLUTTER_ROOT/../../TATA/tatachatsdk/ios"',
      ),
    );
    expect(runner, contains(r'verify-ios-package "$IOS_APP"'));
    expect(
      pubspec,
      contains('tatachat_sdk:\n    path: ../../TATA/tatachatsdk'),
    );
    // path 依赖由控制台只读工程视图直接投影，不再创建第二份 override 配置。
    expect(runner, isNot(contains('pubspec_overrides.yaml')));
    expect(runner, isNot(contains('cleanup_direct_source_state')));
    expect(runner, isNot(contains(r'rm -f "$TATACHATSDK_ROOT/ios/')));
    expect(runner, contains('flutter pub get --offline --enforce-lockfile'));
    expect(runner, contains('flutter build ios --no-pub --release'));
    expect(runner, contains(r'android/gradlew" --offline'));
    expect(runner, isNot(contains('\nflutter pub get\n')));
    expect(testRunner, isNot(contains('pubspec_overrides.yaml')));
    expect(testRunner, isNot(contains('stage_gmb_mobile_source')));
    expect(
      testRunner,
      contains(r'pub get --offline --enforce-lockfile'),
    );
    expect(podfile, contains('TataChatSDK 通过自身 Flutter FFI plugin'));
    expect(lockfile, contains('- tatachat_sdk (1.0.0)'));
  });
}
