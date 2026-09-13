import 'package:citizenapp/security/app_lock_service.dart';
import 'package:citizenapp/security/pin_input_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    AppLockService.debugResetForTest();
  });

  tearDown(AppLockService.debugResetForTest);

  test('普通应用锁与防共匪密码使用各自固定迭代次数', () {
    expect(AppLockService.appLockPinHashIterations, 100000);
    expect(AppLockService.duressModePinHashIterations, 10000);
  });

  test('防共匪密码独立保存且不影响普通密码错误计数', () async {
    await AppLockService.setPin('123456');

    expect(await AppLockService.setDuressModePin('123456'), isFalse);
    expect(await AppLockService.isDuressModeEnabled(), isFalse);

    expect(await AppLockService.setDuressModePin('654321'), isTrue);
    expect(await AppLockService.isDuressModeEnabled(), isTrue);
    expect(
      await AppLockService.verifyPin(
        '123456',
        wallet: null,
        accountSecurity: null,
      ),
      AppPinVerificationResult.verified,
    );
    expect(
      await AppLockService.verifyPin(
        '654321',
        wallet: null,
        accountSecurity: null,
      ),
      AppPinVerificationResult.duressMode,
    );
    expect(await AppLockService.getFailCount(), 0);
  });

  test('关闭普通应用锁会同步清除防共匪模式', () async {
    await AppLockService.setPin('123456');
    await AppLockService.setDuressModePin('654321');

    await AppLockService.removePin();

    expect(await AppLockService.isPinSet(), isFalse);
    expect(await AppLockService.isDuressModeEnabled(), isFalse);
  });

  testWidgets('防共匪密码两个输入框保持独立间距', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDuressModeSetupDialog(context),
            child: const Text('打开设置'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    final gap = tester.getTopLeft(fields.at(1)).dy -
        tester.getBottomLeft(fields.at(0)).dy;
    expect(gap, greaterThanOrEqualTo(16));
  });

  testWidgets('数字键盘连续按下六位时完整保留输入顺序', (tester) async {
    String? verifiedPin;
    AppLockService.debugConfigureForTest(
      isLocked: () async => false,
      verifyPin: (pin) async {
        verifiedPin = pin;
        return AppPinVerificationResult.verified;
      },
    );
    await tester.pumpWidget(
      const MaterialApp(home: PinInputPage(mode: PinInputMode.verify)),
    );
    await tester.pump();

    for (final digit in <int>[1, 2, 3, 4, 5, 6]) {
      await tester.tap(find.text('$digit'), warnIfMissed: false);
    }
    await tester.pumpAndSettle();

    expect(verifiedPin, '123456');
  });

  testWidgets('单次命中防共匪密码立即落门闩、擦除并退出', (tester) async {
    var latchCalls = 0;
    var wipeCalls = 0;
    var exitCalls = 0;
    final events = <String>[];
    AppLockService.debugConfigureForTest(
      isLocked: () async => false,
      verifyPin: (pin) async => pin == '654321'
          ? AppPinVerificationResult.duressMode
          : AppPinVerificationResult.rejected,
      latchPersistentWipe: () async {
        latchCalls += 1;
        events.add('latch');
      },
      wipeAllData: () async {
        wipeCalls += 1;
        events.add('wipe');
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') {
          exitCalls += 1;
          events.add('exit');
        }
        return null;
      },
    );
    const securityChannel = MethodChannel('citizenapp/security');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityChannel,
      (call) async {
        events.add(call.method);
        return null;
      },
    );
    addTearDown(
      () async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          securityChannel,
          null,
        );
      },
    );

    await tester.pumpWidget(
      const MaterialApp(home: PinInputPage(mode: PinInputMode.verify)),
    );
    await tester.pump();
    await _enterSixDigitPin(tester, <int>[6, 5, 4, 3, 2, 1]);
    // 第一个新帧先提交不可返回的中性遮蔽页，随后才开始后台擦除。
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('密码错误'), findsNothing);
    expect(latchCalls, 1);
    expect(wipeCalls, 1);
    expect(exitCalls, 1);
    expect(events, <String>[
      'latch',
      'beginEmergencyWipe',
      'wipe',
      'finishEmergencyWipe',
      'exit',
    ]);
  });

  testWidgets('单次命中但擦除门闩失败时不得退出或启动擦除', (tester) async {
    var wipeCalls = 0;
    var exitCalls = 0;
    AppLockService.debugConfigureForTest(
      isLocked: () async => false,
      verifyPin: (_) async => AppPinVerificationResult.duressMode,
      latchPersistentWipe: () async => throw StateError('latch failed'),
      wipeAllData: () async => wipeCalls += 1,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls += 1;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: PinInputPage(mode: PinInputMode.verify)),
    );
    await tester.pump();
    await _enterSixDigitPin(tester, <int>[6, 5, 4, 3, 2, 1]);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('操作未完成，请稍后重试'), findsOneWidget);
    expect(wipeCalls, 0);
    expect(exitCalls, 0);
  });
}

Future<void> _enterSixDigitPin(
  WidgetTester tester,
  List<int> digits,
) async {
  for (final digit in digits) {
    await tester.tap(find.text('$digit'));
    await tester.pump();
  }
}
