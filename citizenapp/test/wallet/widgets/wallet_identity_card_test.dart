import 'dart:typed_data';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/qr/widgets/qr_display_scaffold.dart' show AppQrImage;
import 'package:citizenapp/wallet/widgets/wallet_identity_card.dart';
import 'package:citizenapp/wallet/widgets/wallet_qr_dialog.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';
import '../../support/fake_citizen_sdk.dart';

/// 几何和交互断言取自be75a90b原件；仅账户模型与QR底层改用现有SDK。
void main() {
  late CitizenSdk sdk;
  late TestCitizenSdkTransport transport;
  setUp(() async {
    // 图像明确是UI替身；账户码编码/解析走本轮真实Core，不把白图当二维码验真。
    transport = TestCitizenSdkTransport({
      'qrEncode': (_) => [29, 29, Uint8List(29 * 29)..fillRange(0, 29 * 29, 255)],
    }, useCore: true);
    sdk = await transport.open();
  });
  tearDown(() async { await sdk.close(); await transport.dispose(); });
  final wallet = CitizenWalletStateAccount(
    signMode: CitizenWalletSignMode.hot, walletIndex: 0, accountIndex: 0,
    name: '账户名称与钱包名不同',
    ss58Address: '5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty',
    accountId: '0x0000000000000000000000000000000000000000000000000000000000000000',
    createdAtMillis: BigInt.zero, isDefault: true,
  );

  Future<void> pumpCard(
    WidgetTester tester,
    Future<void> Function(String) onNameChanged, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = platform == TargetPlatform.iOS
        ? const Size(402, 874)
        : const Size(411, 914);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Provider<CitizenSdk>.value(value: sdk, child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => Theme(
          data: AppTheme.lightThemeFor(context).copyWith(platform: platform),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 411,
              child: WalletIdentityCard(
                wallet: wallet,
                walletName: '我的钱包',
                onNameChanged: onNameChanged,
              ),
            ),
          ),
        ),
      )),
    );
  }

  testWidgets('renders wallet name and full address', (tester) async {
    await pumpCard(tester, (_) async {});
    expect(find.text('我的钱包'), findsOneWidget);
    expect(find.textContaining('...'), findsNothing);
    final firstLine = tester.widget<Text>(
      find.byKey(const ValueKey('wallet-identity-address-line-1')),
    );
    final secondLine = tester.widget<Text>(
      find.byKey(const ValueKey('wallet-identity-address-line-2')),
    );
    expect('${firstLine.data}${secondLine.data}', wallet.ss58Address);
    expect(secondLine.data, isNotEmpty);
    // 测试字体下第一行可容纳 20 个字符；锁定“排满第一行后再换行”，
    // 防止恢复为优先塞满第二行而导致第一行过短的旧拆分逻辑。
    expect(firstLine.data, wallet.ss58Address.substring(0, 20));
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_rounded), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_rounded), findsNothing);
  });

  testWidgets('方案 2 身份区高度和二维码竖分隔线固定', (tester) async {
    final platformHeights = <TargetPlatform, double>{};
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await pumpCard(tester, (_) async {}, platform: platform);
      platformHeights[platform] = tester
          .getSize(find.byKey(const ValueKey('wallet-identity-section')))
          .height;
    }

    expect(platformHeights[TargetPlatform.android], 112);
    expect(
      platformHeights[TargetPlatform.iOS],
      closeTo(112 * AppLayout.visualScaleForSize(const Size(402, 874)), 0.001),
    );

    // 后续精确几何断言都在 411×914 设计基准视口下量取。
    await pumpCard(tester, (_) async {});
    expect(
      tester.getSize(find.byKey(const ValueKey('wallet-identity-qr-divider'))),
      const Size(1, 48),
    );
    final copyButtonRect = tester.getRect(
      find.byKey(const ValueKey('wallet-identity-copy-button')),
    );
    final dividerRect = tester.getRect(
      find.byKey(const ValueKey('wallet-identity-qr-divider')),
    );
    final qrButtonRect = tester.getRect(
      find.byKey(const ValueKey('wallet-identity-qr-button')),
    );
    expect(dividerRect.left - copyButtonRect.right, 21.25);
    expect(qrButtonRect.left - dividerRect.right, 16);
    // 复制图标保持原 copy_outlined 原子与 12 尺寸；21.25 的按钮外间距是
    // Pixel 8a 真机可见图形边缘校准值，不用按钮盒理论留白代替视觉量取。

    final copyIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('wallet-identity-copy-icon')),
    );
    expect(copyIcon.icon, Icons.copy_outlined);
    expect(copyIcon.size, 12);
    final copyIconRect = tester.getRect(
      find.byKey(const ValueKey('wallet-identity-copy-icon')),
    );
    expect(copyIconRect.center.dy - copyButtonRect.center.dy, 4);
    final qrMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('wallet-identity-qr-button')),
    );
    expect(qrMaterial.color, Colors.transparent);

    final nameRect = tester.getRect(find.text('我的钱包'));
    final firstLineRect = tester.getRect(
      find.byKey(const ValueKey('wallet-identity-address-line-1')),
    );
    expect(copyIconRect.center.dy, greaterThan(firstLineRect.center.dy));
    expect(copyButtonRect.center.dy, isNot(closeTo(nameRect.center.dy, 1)));
  });

  testWidgets('冷热钱包账户码弹窗严格使用居中地址和左右对称文字按钮', (tester) async {
    await pumpCard(tester, (_) async {});

    await tester.tap(find.byKey(const ValueKey('wallet-identity-qr-button')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('我的钱包'), findsWidgets);
    expect(find.text('账户地址'), findsNothing);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-account-qr')), findsOneWidget);
    expect(find.byType(AppQrImage), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);

    final address = tester.widget<SelectableText>(
      find.byKey(const ValueKey('wallet-account-address')),
    );
    expect(address.textAlign, TextAlign.center);

    final dialogRect = tester.getRect(find.byType(Dialog));
    final closeRect = tester.getRect(find.widgetWithText(TextButton, '关闭'));
    final copyRect = tester.getRect(find.widgetWithText(TextButton, '复制'));
    expect(closeRect.size, copyRect.size);
    expect(
      dialogRect.center.dx - closeRect.center.dx,
      closeTo(copyRect.center.dx - dialogRect.center.dx, 0.01),
    );

    await tester.tap(find.widgetWithText(TextButton, '复制'));
    await tester.pump();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  test('二维码载荷固定为k5且不携带本机名称和SS58', () async {
    final raw = await buildWalletAccountQrData(sdk.qr, wallet.accountId);
    final parsed = await sdk.qr.parseForPurpose(raw, CitizenQrScanPurpose.coldAccountImport);
    expect(parsed.document.kind, CitizenQrKind.accountId);
    expect(parsed.document.requestId, isNull);
    expect(parsed.document.expiresAt, isNull);
    expect(parsed.accountId, wallet.accountId);
    expect(raw, isNot(contains('我的钱包')));
    expect(raw, isNot(contains('ss58_address')));
  });

  testWidgets('tap wallet name enters edit mode and submits new name', (
    tester,
  ) async {
    String? received;
    await pumpCard(tester, (name) async {
      received = name;
    });

    // 点击钱包名进入编辑态。
    await tester.tap(find.text('我的钱包'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    // 输入新名称并提交(通过 TextField onSubmitted)。
    await tester.enterText(find.byType(TextField), '新钱包名');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(received, '新钱包名');
  });

  testWidgets('empty name rollback without calling callback', (tester) async {
    var callCount = 0;
    await pumpCard(tester, (_) async {
      callCount += 1;
    });

    await tester.tap(find.text('我的钱包'));
    await tester.pump();
    // 清空后提交 → 回滚,不触发回调。
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(callCount, 0);
    // 回滚后应该回到展示态显示原钱包名。
    expect(find.text('我的钱包'), findsOneWidget);
  });
}
