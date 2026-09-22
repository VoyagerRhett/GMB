import '../support/fake_citizen_sdk.dart';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/qr/pages/qr_scan_page.dart';

/// 扫码填地址时扫到签名请求:必须给明确去向,不得用「无法识别」含糊过去。
///
/// 签名请求(广场动作 / 公民身份 / 注册局占号换绑)统一在「聊天 → 扫一扫」处理;
/// 交易页与多签各页的地址框扫码都走 [QrScanMode.transfer],共用这一条提示。
void main() {
  const signRequestCode = 'synthetic-sign-request';
  const accountCode = 'synthetic-account-code';

  testWidgets('transfer 模式扫到签名请求:指路聊天扫一扫,不回传结果', (tester) async {
    QrScanTransferResult? popped;
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
    );

    unawaitedPush(navigatorKey, signRequestCode).then((value) {
      popped = value;
    });
    await tester.pumpAndSettle();

    expect(find.text('这是签名请求'), findsOneWidget);
    expect(find.text('此处只扫收款地址。请到「聊天 → 扫一扫」。'), findsOneWidget);
    // 未识别文案不得同时出现:两条提示并存等于没给去向。
    expect(find.text('无法识别二维码'), findsNothing);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 扫码页停留在原地继续扫,不带结果返回调用方。
    expect(find.byType(QrScanPage), findsOneWidget);
    expect(popped, isNull);
  });

  testWidgets('账户目标入口拒绝签名请求码', (tester) async {
    final navigatorKey = await pumpScannerHost(tester);
    unawaitedPushMode(navigatorKey, signRequestCode, QrScanMode.accountTarget);
    await tester.pumpAndSettle();
    expect(find.text('二维码类型不符'), findsOneWidget);
    expect(find.text('请扫描用户码或账户码'), findsOneWidget);
  });

  testWidgets('签名入口拒绝账户码', (tester) async {
    final navigatorKey = await pumpScannerHost(tester);
    unawaitedPushMode(navigatorKey, accountCode, QrScanMode.signRequest);
    await tester.pumpAndSettle();
    expect(find.text('二维码类型不符'), findsOneWidget);
    expect(find.text('请扫描签名请求二维码'), findsOneWidget);
  });

  testWidgets('用户资料入口拒绝账户码并提示扫描用户码', (tester) async {
    final navigatorKey = await pumpScannerHost(tester);
    unawaitedPushMode(navigatorKey, accountCode, QrScanMode.userContactValue);
    await tester.pumpAndSettle();
    expect(find.text('这不是用户码'), findsOneWidget);
    expect(find.textContaining('只有「用户主页」出示的用户码'), findsOneWidget);
  });
}

Future<GlobalKey<NavigatorState>> pumpScannerHost(WidgetTester tester) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(navigatorKey: navigatorKey, home: const SizedBox.shrink()),
  );
  return navigatorKey;
}

Future<Object?> unawaitedPushMode(
  GlobalKey<NavigatorState> navigatorKey,
  String initialCode,
  QrScanMode mode,
) {
  return navigatorKey.currentState!.push<Object?>(
    MaterialPageRoute(
      builder: (_) => QrScanPage(
        mode: mode,
        initialCode: initialCode,
        qr: _qrFor(initialCode),
      ),
    ),
  );
}

Future<QrScanTransferResult?> unawaitedPush(
  GlobalKey<NavigatorState> navigatorKey,
  String initialCode,
) {
  return navigatorKey.currentState!.push<QrScanTransferResult>(
    MaterialPageRoute(
      builder: (_) => QrScanPage(
        mode: QrScanMode.transfer,
        initialCode: initialCode,
        qr: _qrFor(initialCode),
      ),
    ),
  );
}

/// 页面只根据SDK事实选择原提示；协议有效性由SDK Core金标测试覆盖。
TestCitizenQr _qrFor(String code) => TestCitizenQr()
  ..captureFactory = (_) async => TestCitizenQrCapture()
  ..parseDocument = (text) async {
    expect(text, code);
    return CitizenQrDocument(
      kind: code == 'synthetic-account-code' ? CitizenQrKind.accountId : CitizenQrKind.signRequest,
      canonicalText: code,
      scanPurposeMask: code == 'synthetic-account-code' ? 195 : 80,
      accountId: code == 'synthetic-account-code' ? testCitizenAccountId : null,
      signerAccountId: code == 'synthetic-sign-request' ? testCitizenAccountId : null,
      action: code == 'synthetic-sign-request' ? CitizenQrActions.squareAccountAction : null,
    );
  };
