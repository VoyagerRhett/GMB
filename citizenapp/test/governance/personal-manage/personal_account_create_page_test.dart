import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/qr/pages/qr_scan_page.dart';
import 'package:citizenapp/transaction/personal-manage/personal_account_create_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/isar_test_env.dart';

void main() {
  useIsolatedIsar();

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalAccountCreatePage(
          walletStateLoader: () async => CitizenWalletState(
            revision: BigInt.zero,
            hotProfile: null,
            accounts: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('扫码入口位于管理员列表标题行右侧且独立文字按钮已删除', (tester) async {
    await pumpPage(tester);

    final title = find.text('管理员列表（0/64）');
    final scanButton = find.byKey(const ValueKey('personal-admin-scan-button'));
    expect(title, findsOneWidget);
    expect(scanButton, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '扫码添加管理员'), findsNothing);

    final titleRect = tester.getRect(title);
    final buttonRect = tester.getRect(scanButton);
    expect(buttonRect.left, greaterThanOrEqualTo(titleRect.right));
    expect(buttonRect.center.dy, closeTo(titleRect.center.dy, 1));

    final icon = tester.widget<SvgPicture>(
      find.descendant(of: scanButton, matching: find.byType(SvgPicture)),
    );
    expect(icon.bytesLoader, isA<SvgAssetLoader>());
    expect(
      (icon.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/scan-line.svg',
    );
  });

  testWidgets('点击标题行扫码图标仍进入用户码管理员扫码页', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const ValueKey('personal-admin-scan-button')));
    await tester.pumpAndSettle();

    final page = tester.widget<QrScanPage>(find.byType(QrScanPage));
    expect(page.mode, QrScanMode.userContactValue);
    expect(page.customTitle, '扫码添加管理员');
  });
}
