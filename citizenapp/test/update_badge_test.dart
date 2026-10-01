import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/update/app_update_controller.dart';
import 'package:citizenapp/update/app_update_manifest.dart';
import 'package:citizenapp/update/app_update_service.dart';
import 'package:citizenapp/update/update_badge.dart';

class _FakeAppUpdateService extends AppUpdateService {
  _FakeAppUpdateService({this.failAndroidCheck = false});

  final bool failAndroidCheck;
  int androidCheckCount = 0;

  @override
  Future<AppVersionInfo> readCurrentVersion() async => const AppVersionInfo(
        packageName: 'com.crcfrcn.citizenapp',
        versionName: '1.0.0',
        versionCode: 7,
      );

  @override
  Future<AppUpdateInfo?> checkAndroidUpdate(
    AppVersionInfo currentVersion,
  ) async {
    androidCheckCount += 1;
    if (failAndroidCheck) throw StateError('offline');
    return null;
  }
}

void main() {
  testWidgets('有更新时显示红点', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UpdateDotBadge(
            show: true,
            dotKey: Key('update-dot'),
            child: Icon(Icons.settings),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('update-dot')), findsOneWidget);
  });

  testWidgets('没有更新时不显示红点', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UpdateDotBadge(
            show: false,
            dotKey: Key('update-dot'),
            child: Icon(Icons.settings),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('update-dot')), findsNothing);
  });

  test('iOS 读取本机版本后不请求 Android APK 更新', () async {
    final service = _FakeAppUpdateService();
    final controller = AppUpdateController.forTesting(
      service: service,
      isAndroid: false,
    );

    await controller.check();

    expect(controller.state.status, AppUpdateStatus.idle);
    expect(controller.state.versionLabel, 'v1.0.0');
    expect(controller.state.hasUpdate, isFalse);
    expect(service.androidCheckCount, 0);
  });

  test('Android 联网检查失败仍保留已读取的本机版本', () async {
    final service = _FakeAppUpdateService(failAndroidCheck: true);
    final controller = AppUpdateController.forTesting(
      service: service,
      isAndroid: true,
    );

    await controller.check();

    expect(controller.state.status, AppUpdateStatus.error);
    expect(controller.state.versionLabel, 'v1.0.0');
    expect(service.androidCheckCount, 1);
  });
}
