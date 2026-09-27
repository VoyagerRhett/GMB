// 钱包详情与创建备份 widget 测试：保护确认前不展示秘密，备份阶段禁止误退出。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:citizenwallet/isar/wallet_isar.dart';
import 'package:citizenwallet/ui/create_wallet_page.dart';
import 'package:citizenwallet/ui/wallet_detail_page.dart';
import 'package:citizenwallet/util/screenshot_guard.dart';
import 'package:citizenwallet/wallet/wallet_manager.dart';

const String kDevPhrase =
    'bottom drive obey lake curtain smoke basket hold race lonely fit walk';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const securityChannel = MethodChannel('citizenwallet/security');
  const securityEvents = MethodChannel('citizenwallet/security_events');
  const hardwareVaultChannel = MethodChannel('gmb/hardware_secretvault');
  final hardwareRecords = <String, Uint8List>{};
  final hardwareScopes = <String>{};
  var nextCiphertext = 1;
  var decryptCalls = 0;

  Future<void> releasePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await ScreenshotGuard.waitForIdleForTest();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    hardwareRecords.clear();
    hardwareScopes.clear();
    nextCiphertext = 1;
    decryptCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hardwareVaultChannel,
      (call) async {
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        switch (call.method) {
          case 'securityStatus':
            return <String, Object?>{
              'supported': true,
              'strongBiometricEnrolled': true,
            };
          case 'encrypt':
            final scope = args['scope']! as String;
            final ciphertext = Uint8List(8);
            ByteData.sublistView(ciphertext).setUint64(0, nextCiphertext++);
            hardwareRecords[ciphertext.join(',')] = Uint8List.fromList(
              args['plaintext']! as Uint8List,
            );
            hardwareScopes.add(scope);
            return ciphertext;
          case 'decrypt':
            decryptCalls++;
            final scope = args['scope']! as String;
            if (!hardwareScopes.contains(scope)) {
              throw PlatformException(code: 'keyMissing');
            }
            final ciphertext = args['ciphertext']! as Uint8List;
            final plaintext = hardwareRecords[ciphertext.join(',')];
            if (plaintext == null) {
              throw PlatformException(code: 'authenticationFailed');
            }
            // 模拟真机平台通道的只读 TypedData，防止 widget 测试再次漏掉所有权错误。
            return Uint8List.fromList(plaintext).asUnmodifiableView();
          case 'deleteKey':
            hardwareScopes.remove(args['scope']! as String);
            return null;
          case 'containsKey':
            return hardwareScopes.contains(args['scope']! as String);
        }
        throw PlatformException(code: 'notImplemented');
      },
    );
    await WalletIsar.instance.resetForTest();
    // 揭示助记词会启用 ScreenshotGuard(平台通道):mock 成 no-op。
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityChannel,
      (call) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityEvents,
      (call) async => null,
    );
  });

  tearDown(() async {
    for (final plaintext in hardwareRecords.values) {
      plaintext.fillRange(0, plaintext.length, 0);
    }
    hardwareRecords.clear();
    hardwareScopes.clear();
    await WalletIsar.instance.resetForTest();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityChannel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityEvents,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hardwareVaultChannel,
      null,
    );
  });

  const walletFixture = Wallet(
    walletIndex: 1,
    walletName: '钱包1',
    masterId:
        '0x2afba9278e30ccf6a6ceb3a8b6e336b70068f045c666f2e7f4f9cc5f47db8972',
    createdAtMillis: 0,
    source: 'created',
  );

  testWidgets('身份卡助记词区默认隐藏 + 查看确认取消', (tester) async {
    // _load 走真实 Isar I/O + 加载 spinner 会让 pumpAndSettle 在 fake-async 下卡死;
    // 用 runAsync 让真实事件循环完成 getAccounts,再 pump 退出 loading。
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(home: WalletDetailPage(wallet: walletFixture)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text('点击查看助记词'), findsOneWidget);
    expect(find.textContaining('助记词（请绝对保密）'), findsOneWidget);
    expect(find.byTooltip('扫码签名'), findsOneWidget);

    await tester.tap(find.text('点击查看助记词'));
    await tester.pumpAndSettle();
    expect(find.text('查看助记词'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('查看助记词'), findsNothing);
    expect(find.text('点击查看助记词'), findsOneWidget);
    await releasePage(tester);
  });

  testWidgets('查看助记词→确认→验证通过→显示助记词明文', (tester) async {
    // 造一个真实钱包(种子+助记词已加密落库),供 getMasterMnemonic 解密取回。
    late Wallet wallet;
    await tester.runAsync(() async {
      final created = await WalletManager().importWallet(kDevPhrase);
      wallet = created.wallet;
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: WalletDetailPage(wallet: wallet)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    await tester.tap(find.text('点击查看助记词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看'));
    // 查看 → getMasterMnemonic(真实 Isar+SecureStorage+解密)+ 启用防截屏。
    await tester.pump();
    await ScreenshotGuard.waitForIdleForTest();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(
      find.text(kDevPhrase),
      findsOneWidget,
      reason:
          '保护错误=${find.textContaining('验证失败：').evaluate().isNotEmpty}，'
          '解密调用=$decryptCalls',
    );
    await releasePage(tester);
  });

  testWidgets('屏幕保护启用失败时不解封也不展示助记词', (tester) async {
    late Wallet wallet;
    await tester.runAsync(() async {
      wallet = (await WalletManager().importWallet(kDevPhrase)).wallet;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(securityChannel, (
      call,
    ) async {
      if (call.method == 'enableScreenshotProtection') {
        throw PlatformException(code: 'protectionUnavailable');
      }
      return null;
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: WalletDetailPage(wallet: wallet)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.tap(find.text('点击查看助记词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看'));
    await tester.pump();
    await ScreenshotGuard.waitForIdleForTest();
    await tester.pumpAndSettle();
    expect(find.text(kDevPhrase), findsNothing);
    expect(decryptCalls, 0);
    await releasePage(tester);
  });

  testWidgets('原生启用未完成时不读取助记词，完成后才显示', (tester) async {
    late Wallet wallet;
    await tester.runAsync(() async {
      wallet = (await WalletManager().importWallet(kDevPhrase)).wallet;
    });
    final enabled = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(securityChannel, (
      call,
    ) async {
      if (call.method == 'enableScreenshotProtection') await enabled.future;
      return null;
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: WalletDetailPage(wallet: wallet)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.tap(find.text('点击查看助记词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看'));
    await tester.pump();
    expect(decryptCalls, 0);
    expect(find.text(kDevPhrase), findsNothing);
    enabled.complete();
    await tester.pump();
    await ScreenshotGuard.waitForIdleForTest();
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      if (find.text(kDevPhrase).evaluate().isNotEmpty) break;
    }
    expect(
      find.text(kDevPhrase),
      findsOneWidget,
      reason:
          '保护错误=${find.textContaining('验证失败：').evaluate().isNotEmpty}，'
          '解密调用=$decryptCalls',
    );
    await releasePage(tester);
  });

  testWidgets('创建前可返回，助记词展示后仅底部完成按钮可退出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateWalletPage()),
              ),
              child: const Text('打开创建'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开创建'));
    await tester.pumpAndSettle();
    // 选择阶段根本不注册返回拦截，保持原有导航手势。
    expect(find.byType(PopScope<bool>), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    // 创建前保留 iOS 左缘返回手势。
    await tester.dragFrom(const Offset(1, 300), const Offset(700, 300));
    await tester.pumpAndSettle();
    expect(find.text('打开创建'), findsOneWidget);
    await ScreenshotGuard.waitForIdleForTest();

    await tester.tap(find.text('打开创建'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('打开创建'), findsOneWidget);
    await ScreenshotGuard.waitForIdleForTest();

    await tester.tap(find.text('打开创建'));
    await tester.pumpAndSettle();
    // 创建会进行真实 Isar 与硬件金库异步 I/O，点击回调须从真实异步区启动。
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, '创建钱包'));
    });
    for (var attempt = 0; attempt < 40; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      if (find.text('已备份，完成').evaluate().isNotEmpty ||
          find.textContaining('创建失败：').evaluate().isNotEmpty)
        break;
    }
    expect(find.textContaining('创建失败：'), findsNothing);
    expect(
      find.text('已备份，完成'),
      findsOneWidget,
      reason:
          '仍在选择=${find.text('选择助记词数量').evaluate().isNotEmpty}，'
          '创建中=${find.byType(CircularProgressIndicator).evaluate().isNotEmpty}，'
          '保护失败=${find.textContaining('屏幕保护不可用').evaluate().isNotEmpty}',
    );
    expect(
      tester.widget<PopScope<bool>>(find.byType(PopScope<bool>)).canPop,
      isFalse,
    );
    expect(find.byType(BackButton), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('已备份，完成'), findsOneWidget);
    // 助记词展示阶段的同一左缘手势也不能退出。
    await tester.dragFrom(const Offset(1, 300), const Offset(700, 300));
    await tester.pumpAndSettle();
    expect(find.text('已备份，完成'), findsOneWidget);
    await tester.tap(find.text('已备份，完成'));
    await tester.pumpAndSettle();
    expect(find.text('打开创建'), findsOneWidget);
    await releasePage(tester);
  });

  testWidgets('账户列表每行有账户码入口，点它出账户码且不进账户详情', (tester) async {
    // 真实导入一个钱包，账户0 落库后账户列表才有行可点。
    late Wallet wallet;
    await tester.runAsync(() async {
      final created = await WalletManager().importWallet(kDevPhrase);
      wallet = created.wallet;
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: WalletDetailPage(wallet: wallet)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    // 列表标题为「账户列表」;二维码入口在每个账户行上，与右箭头并存。
    expect(find.text('账户列表'), findsOneWidget);
    final addAccountButton = find.widgetWithText(TextButton, '添加账户');
    expect(addAccountButton, findsOneWidget);
    expect(
      find.descendant(of: addAccountButton, matching: find.byType(Icon)),
      findsNothing,
    );
    final qrEntry = find.byTooltip('显示账户码');
    expect(qrEntry, findsWidgets);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);

    await tester.tap(qrEntry.first);
    await tester.pumpAndSettle();

    // 弹出的是账户码（与账户详情共用同一份弹窗），且没有跳进账户详情。
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('账户详情'), findsNothing);
    expect(find.textContaining('扫码登录'), findsNothing);
    expect(find.textContaining('分钟内有效'), findsNothing);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    await releasePage(tester);
  });

  testWidgets('账户序号三位数起 # 挪到左上角、数字另起一行', (tester) async {
    // 真实导入钱包(账户0)+ 指定序号添加 //100,列表同时出现两种徽章形态。
    late Wallet wallet;
    await tester.runAsync(() async {
      final created = await WalletManager().importWallet(kDevPhrase);
      wallet = created.wallet;
      await WalletManager().addAccount(wallet.masterId, index: 100);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: WalletDetailPage(wallet: wallet)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    // 账户0:两位数以内保持 `#xx` 单行整串。
    expect(find.text('#0'), findsOneWidget);
    // 账户100:整串 `#100` 不复存在,# 与数字拆分各自成行。
    expect(find.text('#100'), findsNothing);
    expect(find.text('#'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    await releasePage(tester);
  });
}
