import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenwallet/isar/wallet_isar.dart';
import 'package:citizenwallet/main.dart';
import 'package:citizenwallet/ui/app_theme.dart';
import 'package:citizenwallet/ui/create_wallet_page.dart';
import 'package:citizenwallet/ui/home_page.dart';
import 'package:citizenwallet/ui/import_wallet_page.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const securityChannel = MethodChannel('citizenwallet/security');

  setUp(() async {
    await WalletIsar.instance.resetForTest();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityChannel,
      (call) async => false,
    );
  });

  tearDown(() async {
    await WalletIsar.instance.resetForTest();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityChannel,
      null,
    );
  });

  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const CitizenWalletApp());
    await tester.pump();
    // App 入口包含 _AppLockGate，测试环境下显示加载指示器即可视为正常构建
    expect(find.byType(CitizenWalletApp), findsOneWidget);
  });

  testWidgets('无钱包首屏上移、使用新文案与缩小后的公民 Logo', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const HomePage()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text('创建或导入钱包后开始使用'), findsOneWidget);
    expect(find.text('创建或导入一个钱包来开始使用'), findsNothing);

    final logo = find.byKey(const Key('citizenLogo'));
    expect(logo, findsOneWidget);
    expect(tester.getSize(logo), const Size(22, 22));

    final emptyIcon = find.byIcon(Icons.account_balance_wallet_outlined);
    final emptyTitle = find.text('还没有钱包');
    final createButton = find.widgetWithText(FilledButton, '创建钱包');
    final importButton = find.widgetWithText(OutlinedButton, '导入钱包');
    for (final finder in [emptyIcon, emptyTitle, createButton, importButton]) {
      expect(tester.getCenter(finder).dx, closeTo(195, 0.5));
    }
    final bodyTop = tester.getBottomLeft(find.byType(AppBar)).dy;
    final topBlank = tester.getTopLeft(emptyIcon).dy - bodyTop;
    final bottomBlank = 844 - tester.getBottomRight(importButton).dy;
    expect(topBlank, lessThan(bottomBlank));
  });

  testWidgets('创建页上移并只显示助记词数量标题', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const CreateWalletPage()),
    );

    expect(find.text('选择助记词数量'), findsOneWidget);
    expect(find.text('创建新钱包'), findsNothing);
    expect(find.text('将生成一组助记词，请务必安全保存'), findsNothing);
    expect(tester.getTopLeft(find.byIcon(Icons.add_rounded)).dy, lessThan(130));
  });

  testWidgets('创建页原选择控件提供12、18、24词并显示对应熵说明', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const CreateWalletPage()),
    );

    final selector = find.byType(SegmentedButton<int>);
    expect(tester.widget<SegmentedButton<int>>(selector).selected, {12});
    expect(find.text('128 位熵，标准安全强度'), findsOneWidget);
    for (final count in [12, 18, 24]) {
      expect(find.text('$count 个单词'), findsOneWidget);
    }

    await tester.tap(find.text('18 个单词'));
    await tester.pump();
    expect(tester.widget<SegmentedButton<int>>(selector).selected, {18});
    expect(find.text('192 位熵'), findsOneWidget);

    await tester.tap(find.text('24 个单词'));
    await tester.pump();
    expect(find.text('256 位熵，安全性更高'), findsOneWidget);

    await tester.tap(find.text('12 个单词'));
    await tester.pump();
    expect(find.text('128 位熵，标准安全强度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导入页顶部统一为输入助记词且没有重复标题', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const ImportWalletPage()),
    );

    expect(find.text('输入助记词'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('输入助记词'),
      ),
      findsOneWidget,
    );
    final mnemonicInput = find.byType(TextField).first;
    expect(
      tester.widget<TextField>(mnemonicInput).decoration!.counterText,
      '0 / 12、18 或 24 个单词',
    );
    await tester.enterText(mnemonicInput, List.filled(18, 'sample').join(' '));
    await tester.pump();
    expect(
      tester.widget<TextField>(mnemonicInput).decoration!.counterText,
      '18 / 12、18 或 24 个单词',
    );
  });
}
