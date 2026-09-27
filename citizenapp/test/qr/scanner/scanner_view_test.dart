import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/qr/scanner/scanner.dart';
import '../../support/fake_citizen_sdk.dart';

Widget _view(TestCitizenQr qr, {ValueChanged<String>? result, ValueChanged<ScannerFailure>? failure}) =>
    Directionality(textDirection: TextDirection.ltr, child: ScannerView(
      qr: qr, purpose: CitizenQrScanPurpose.generalScan,
      onRawValue: result ?? (_) {}, onFailure: failure,
    ));

void main() {
  testWidgets('预览只应用SDK剩余角度并保留纹理比例，方向事件更新同一资源', (tester) async {
    final capture = TestCitizenQrCapture()
      ..preview = const CitizenQrPreview(width: 480, height: 640, rotationDegrees: 0);
    var opens = 0;
    final qr = TestCitizenQr()..captureFactory = (_) async { opens++; return capture; };
    await tester.pumpWidget(_view(qr));
    await tester.pump();
    // Android SurfaceTexture已转正时直接显示；不可根据平台再次猜传感器角度。
    for (final rotation in [0, 270, 180, 90, 0]) {
      capture.preview = CitizenQrPreview(width: 480, height: 640, rotationDegrees: rotation);
      capture.previewEvents.add(capture.preview);
      await tester.pump();
      final rotated = tester.widget<RotatedBox>(find.byType(RotatedBox));
      expect(rotated.quarterTurns, rotation ~/ 90);
      final size = rotated.child! as SizedBox;
      expect(size.width, 480);
      expect(size.height, 640);
      expect((size.child! as Texture).textureId, capture.textureId);
    }
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(capture.closeCalls, 1);
  });

  testWidgets('SDK纹理原样交给预览，结果只转发SDK规范文本', (tester) async {
    final capture = TestCitizenQrCapture();
    final qr = TestCitizenQr()..captureFactory = (purpose) async {
      expect(purpose, CitizenQrScanPurpose.generalScan);
      return capture;
    };
    final values = <String>[];
    await tester.pumpWidget(_view(qr, result: values.add));
    await tester.pump();
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, capture.textureId);
    capture.resultEvents.add(CitizenQrScanResult(
      purpose: CitizenQrScanPurpose.generalScan,
      document: CitizenQrDocument(kind: CitizenQrKind.accountId,
        canonicalText: 'sdk-canonical-code', scanPurposeMask: 195,
        accountId: testCitizenAccountId),
    ));
    await tester.pump();
    expect(values, ['sdk-canonical-code']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(capture.closed, isTrue);
  });

  testWidgets('SDK权限/设备错误按稳定类别投影，不读取异常字符串猜测', (tester) async {
    final failures = <ScannerFailure>[];
    final qr = TestCitizenQr()..captureFactory = (_) async =>
        throw const CitizenSdkException(code: CitizenSdkErrorCode.permissionDenied, message: '合成拒绝');
    await tester.pumpWidget(_view(qr, failure: failures.add));
    await tester.pump();
    expect(failures.single.kind, ScannerFailureKind.permissionDenied);
    expect(find.byType(Texture), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('前后台只转发SDK暂停恢复，退出等待真实资源close', (tester) async {
    final capture = TestCitizenQrCapture();
    final qr = TestCitizenQr()..captureFactory = (_) async => capture;
    await tester.pumpWidget(_view(qr));
    await tester.pump();
    final before = capture.pauseCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(capture.pauseCalls, greaterThan(before));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(capture.resumeCalls, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(capture.closeCalls, 1);
  });
}
