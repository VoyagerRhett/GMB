import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _account = '0x1111111111111111111111111111111111111111111111111111111111111111';
const _requestId = 'synthetic-request-1';

/// 页面用例只控制SDK验签事实；实际密码学校验由Core及公共ABI测试覆盖。
class _Qr extends Fake implements CitizenQr {
  @override Future<CitizenQrImage> encode(String text, {int scale = 4}) async =>
      CitizenQrImage(width: 29, height: 29, luminance: Uint8List(29 * 29)..fillRange(0, 29 * 29, 255));
  final List<String> responses = [];
  bool reject = true;
  @override
  Future<void> validateSignResponse({required String sessionId, required String response}) async {
    expect(sessionId, _requestId);
    responses.add(response);
    if (reject) {
      throw const CitizenSdkException(code: CitizenSdkErrorCode.integrity, message: '合成签名无效');
    }
  }
}

CitizenQrDocument _request({int? expiresAt}) => CitizenQrDocument(
  kind: CitizenQrKind.signRequest,
  canonicalText: 'synthetic-request',
  scanPurposeMask: 80,
  requestId: _requestId,
  expiresAt: expiresAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000 + 120,
  action: 0x0400,
  signerAccountId: _account,
  reviewPayload: Uint8List.fromList([4, 0, 1]),
);

void main() {
  Future<void> open(WidgetTester tester, _Qr qr, {
    int? expiresAt, required ValueChanged<String?> completed,
    Future<String?> Function(BuildContext, CitizenQrKind)? scan,
  }) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            final request = _request(expiresAt: expiresAt);
            completed(await Navigator.of(context).push<String>(MaterialPageRoute(
              builder: (_) => QrSignSessionPage(
                request: request, requestJson: request.canonicalText,
                expectedSignerPublicKey: _account, qr: qr,
                scanResponse: scan ?? (_, kind) async {
                  expect(kind, CitizenQrKind.signResponse);
                  return 'synthetic-response';
                },
              ),
            )));
          },
          child: const Text('打开原冷签页'),
        ),
      )),
    ));
    await tester.tap(find.text('打开原冷签页'));
    await tester.pumpAndSettle();
  }

  testWidgets('原标题、倒计时图标、提示文字和双按钮保留，错签名留页重扫', (tester) async {
    final qr = _Qr();
    var completed = false;
    await open(tester, qr, completed: (_) => completed = true);
    expect(find.text('公民钱包签名'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.text('请用离线设备扫描此二维码完成签名，\n然后点击下方按钮扫描签名响应二维码。'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('扫描响应'));
    await tester.pumpAndSettle();
    expect(find.text('签名响应解析失败'), findsOneWidget);
    expect(find.text('合成签名无效'), findsOneWidget);
    expect(completed, isFalse);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byType(QrSignSessionPage), findsOneWidget);
    qr.reject = false;
    await tester.tap(find.text('扫描响应'));
    await tester.pumpAndSettle();
    expect(qr.responses, ['synthetic-response', 'synthetic-response']);
    expect(completed, isTrue);
    expect(find.byType(QrSignSessionPage), findsNothing);
  });

  testWidgets('预检成功后按原流程返回原文，不在页面提前消费或提交交易', (tester) async {
    final qr = _Qr()..reject = false;
    String? result;
    await open(tester, qr, completed: (value) => result = value);
    await tester.tap(find.text('扫描响应'));
    await tester.pumpAndSettle();
    expect(result, 'synthetic-response');
    expect(qr.responses, ['synthetic-response']);
  });

  testWidgets('原取消返回null，不调用预检', (tester) async {
    final qr = _Qr();
    Object? result = Object();
    await open(tester, qr, completed: (value) => result = value);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(qr.responses, isEmpty);
  });

  testWidgets('扫码路由取消后留在原请求页', (tester) async {
    final qr = _Qr();
    var completed = false;
    await open(tester, qr, completed: (_) => completed = true, scan: (_, _) async => null);
    await tester.tap(find.text('扫描响应'));
    await tester.pumpAndSettle();
    expect(completed, isFalse);
    expect(qr.responses, isEmpty);
    expect(find.byType(QrSignSessionPage), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('过期显示原提示和禁用按钮，不发起预检', (tester) async {
    final qr = _Qr();
    await open(tester, qr, expiresAt: 1, completed: (_) {});
    expect(find.byIcon(Icons.timer_off), findsOneWidget);
    expect(find.text('签名请求已过期，请返回重新提交'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '扫描响应'));
    expect(button.onPressed, isNull);
    expect(qr.responses, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}
