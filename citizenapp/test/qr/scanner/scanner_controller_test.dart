import 'dart:async';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/qr/scanner/scanner.dart';
import '../../support/fake_citizen_sdk.dart';

/// 原控制器的生命周期回归现在验证SDK资源接线；不再构造App扫码后台或影子识别器。
Widget _view(TestCitizenQr qr, {ValueChanged<String>? value}) => Directionality(
  textDirection: TextDirection.ltr,
  child: ScannerView(qr: qr, purpose: CitizenQrScanPurpose.generalScan, onRawValue: value ?? (_) {}),
);

void main() {
  testWidgets('打开尚未完成便退出，迟到摄像资源必须关闭且不展示', (tester) async {
    final opening = Completer<CitizenQrCapture>();
    final capture = TestCitizenQrCapture();
    final qr = TestCitizenQr()..captureFactory = (_) => opening.future;
    final values = <String>[];
    await tester.pumpWidget(_view(qr, value: values.add));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    opening.complete(capture);
    await tester.pump();
    expect(capture.closeCalls, 1);
    expect(capture.closed, isTrue);
    expect(values, isEmpty);
    expect(find.byType(Texture), findsNothing);
  });

  testWidgets('dispose不伪造SDK排空，close未完成时资源仍是未关闭', (tester) async {
    final barrier = Completer<void>();
    final capture = TestCitizenQrCapture()..closeBarrier = barrier;
    final qr = TestCitizenQr()..captureFactory = (_) async => capture;
    await tester.pumpWidget(_view(qr));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(capture.closeCalls, 1);
    expect(capture.closed, isFalse);
    barrier.complete();
    await tester.pump();
    expect(capture.closed, isTrue);
  });

  testWidgets('更换SDK前先关闭前一个预览，不向新页面交付旧流', (tester) async {
    final first = TestCitizenQrCapture();
    final second = TestCitizenQrCapture();
    final oldQr = TestCitizenQr()..captureFactory = (_) async => first;
    final newQr = TestCitizenQr()..captureFactory = (_) async {
      expect(first.closed, isTrue);
      return second;
    };
    await tester.pumpWidget(_view(oldQr));
    await tester.pump();
    await tester.pumpWidget(_view(newQr));
    await tester.pump();
    expect(first.closeCalls, 1);
    expect(second.closed, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(second.closeCalls, 1);
  });
}
