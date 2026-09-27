// 离线签名页 widget 测试(既有基线修复:runtime 升级哈希签的绿 banner 与明细
// 不再自相矛盾)。normal + decoded==null 是 runtime 升级哈希签唯一产生的组合,
// 旧代码在明细里错误地走了“拒绝签名”分支。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenwallet/qr/qr_protocols.dart';
import 'package:citizenwallet/qr/envelope.dart';
import 'package:citizenwallet/qr/bodies/sign_request_body.dart';
import 'package:citizenwallet/signer/qr_signer.dart';
import 'package:citizenwallet/ui/offline_sign_page.dart';
import 'package:citizenwallet/util/screenshot_guard.dart';
import 'package:citizenwallet/wallet/wallet_manager.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  const securityChannel = MethodChannel('citizenwallet/security');
  const securityEvents = MethodChannel('citizenwallet/security_events');

  Future<void> releasePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await ScreenshotGuard.waitForIdleForTest();
  }

  setUp(() {
    // ScreenshotGuard 走平台通道:mock 成 no-op,避免 MissingPluginException。
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityChannel,
      (call) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityEvents,
      (call) async => null,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityChannel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      securityEvents,
      null,
    );
  });

  const signerPk =
      '0xb606fc73f57f03cdb4c932d475ab426043e429cecc2ffff0d2672b0df8398c48';
  const account = Account(
    masterId:
        '0x2afba9278e30ccf6a6ceb3a8b6e336b70068f045c666f2e7f4f9cc5f47db8972',
    accountIndex: 1,
    accountId: signerPk,
    ss58Address: 'w5FhUDLW4BxsE1QXK4sNjPZ8rqSnK2QeVpUfXzqczpWdxChxV',
    accountName: '账户1',
    createdAtMillis: 0,
  );

  testWidgets('runtime 升级哈希签:绿 banner 且无“拒绝签名”矛盾行', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 32 字节升级摘要。
    final hashHex =
        '0x'
        '${List<int>.generate(32, (i) => i).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    final request = QrEnvelope<SignRequestBody>(
      kind: QrKind.signRequest,
      id: 'offline-req-hashonly-0001',
      expiresAt: now + 90,
      body: SignRequestBody.fromHex(
        action: QrActions.runtimeUpgradeHash,
        signerPublicKeyHex: signerPk,
        payloadHex: hashHex,
      ),
    );
    final raw = QrSigner().encodeRequest(request);

    await tester.pumpWidget(
      MaterialApp(
        home: OfflineSignPage(account: account, walletName: '钱包1', raw: raw),
      ),
    );
    // 原生保护确认后才解析请求；直接等保护队列，避免墙钟轮询与假时钟交错。
    await ScreenshotGuard.waitForIdleForTest();
    await tester.pump();

    // 绿 banner(hash-only 变体)在场。
    expect(find.textContaining('可以签名'), findsWidgets);
    // 矛盾修复核心:hash-only 合法签绝不出现“拒绝签名”明细行。
    expect(find.text('拒绝签名'), findsNothing);
    // hash-only 说明行在场。
    expect(find.text('32 字节升级摘要（哈希）'), findsOneWidget);

    // 强制释放页面,取消倒计时 Timer,避免 pending timer 报错。
    await releasePage(tester);
  });

  testWidgets('占号请求(空 b.u)渲染签名页不崩溃,展示自选绑定账户', (tester) async {
    // 回归:占号/换绑请求 b.u 留空,曾因展示行无条件求值 signerPublicKeyHex
    // (对空 u 抛 FormatException)导致整页崩溃。
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const cid = 'CN220-CTZN2-198805200-2026';
    final expiresAt = now + 90;
    final u64Expiry = List<int>.generate(
      8,
      (index) => (expiresAt >> (index * 8)) & 0xff,
    );
    final authorizationTemplate = <int>[
      ...List<int>.filled(32, 0x44),
      cid.length << 2,
      ...cid.codeUnits,
      ...List<int>.filled(32, 0),
      ...List<int>.filled(8, 0), // expected_binding_revision=0
      ...u64Expiry,
    ];
    final payloadB64 = base64Url
        .encode(authorizationTemplate)
        .replaceAll('=', '');
    final request = QrEnvelope<SignRequestBody>(
      kind: QrKind.signRequest,
      id: 'offline-req-occupy-0001',
      expiresAt: expiresAt,
      body: SignRequestBody(
        action: QrActions.citizenOccupy,
        signerPublicKey: '', // 占号:b.u 留空,钱包自填本账户
        payload: payloadB64,
      ),
    );
    final raw = QrSigner().encodeRequest(request);

    await tester.pumpWidget(
      MaterialApp(
        home: OfflineSignPage(account: account, walletName: '钱包1', raw: raw),
      ),
    );
    await ScreenshotGuard.waitForIdleForTest();
    await tester.pump();

    // 核心断言:渲染过程不抛异常(修复前此处 FormatException 使整页红屏)。
    expect(tester.takeException(), isNull);
    // 展示「签名账户」行 + 自选绑定账户(account.accountId 截断),不是空 u。
    expect(
      find.text('签名账户'),
      findsOneWidget,
      reason:
          '保护失败=${find.textContaining('屏幕保护不可用').evaluate().isNotEmpty}，'
          '解析错误=${find.byIcon(Icons.error_outline).evaluate().isNotEmpty}',
    );

    await releasePage(tester);
  });
}
