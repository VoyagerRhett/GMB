import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import '../support/fake_citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/qr/pages/qr_scan_page.dart';
import 'package:citizenapp/qr/widgets/address_scan_button.dart';

/// 全仓「扫码填地址」唯一组件的契约测试。
///
/// 三处调用方(链上支付、多签转账、安全基金转账)都只经此组件扫码,所以这里钉住的
/// 是全仓行为:只进 [QrScanMode.transfer](绝不进签名分支)、只回传 SS58、空结果不回调。
void main() {
  late TestCitizenSdkTransport transport;
  late CitizenSdk sdk;
  setUp(() async {
    transport = TestCitizenSdkTransport({
      'openQrCapture': (_) => ['capture-1', 42, 640, 480, 90],
      'pauseQrCapture': (_) => [],
      'resumeQrCapture': (_) => [],
      'closeQrCapture': (_) => [],
    });
    sdk = await transport.open();
  });
  tearDown(() async { await sdk.close(); await transport.dispose(); });
  Widget host({required ValueChanged<String> onAddressScanned}) {
    return Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(
      home: Scaffold(
        body: TextField(
          decoration: InputDecoration(
            suffixIcon: AddressScanButton(onAddressScanned: onAddressScanned),
          ),
        ),
      ),
    ));
  }

  testWidgets('渲染为带扫码提示的按钮', (tester) async {
    await tester.pumpWidget(host(onAddressScanned: (_) {}));

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.tooltip, '扫码填入收款地址');
  });

  testWidgets('点击进入 transfer 扫码页,标题为扫码填入收款地址', (tester) async {
    await tester.pumpWidget(host(onAddressScanned: (_) {}));

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    final page = tester.widget<QrScanPage>(find.byType(QrScanPage));
    // 只认地址类码:签名请求在此模式下会被扫码页挡回,不会走到调用方。
    expect(page.mode, QrScanMode.transfer);
    expect(page.customTitle, '扫码填入收款地址');
  });

  testWidgets('扫码页回传收款码结果时只把 SS58 交给调用方', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final scanned = <String>[];
    await tester.pumpWidget(
      Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: TextField(
            decoration: InputDecoration(
              suffixIcon: AddressScanButton(
                onAddressScanned: scanned.add,
              ),
            ),
          ),
        ),
      )),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop(
      const QrScanTransferResult(
        toSs58Address: '5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY',
        amount: '100.50',
        symbol: 'GMB',
        memo: '房租',
        bank: 'CN001-SFGF-000000001-2026',
      ),
    );
    await tester.pumpAndSettle();

    // 金额、备注、清算行一律丢弃:本组件只负责填地址,不承接支付。
    expect(scanned, ['5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY']);
  });

  testWidgets('用户取消扫码时不回调', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var callCount = 0;
    await tester.pumpWidget(
      Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: TextField(
            decoration: InputDecoration(
              suffixIcon: AddressScanButton(
                onAddressScanned: (_) => callCount += 1,
              ),
            ),
          ),
        ),
      )),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(callCount, 0);
  });
}
