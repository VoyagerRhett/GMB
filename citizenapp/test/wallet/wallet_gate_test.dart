import 'dart:async';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/security/account_data_key_provision.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/wallet/wallet_gate.dart';

void main() {
  late AccountSecurityService security;

  setUp(() {
    security = AccountSecurityService(
      wallet: _UnusedWallet(),
      signing: _UnusedSigning(),
      subkeyRegistrar: _registerNothing,
      coldDeviceBindingSigner: _rejectColdBinding,
      coldAccountDataKeyProvider: _rejectColdKeys,
    );
  });

  tearDown(() => security.dispose());

  Widget gate(Future<CitizenWalletState> Function() loader) =>
      Provider<AccountSecurityService>.value(
        value: security,
        child: MaterialApp(
          home: WalletGate(
            walletStateLoader: loader,
            onInitialized: (_) {},
            child: const Scaffold(body: Text('main-shell')),
          ),
        ),
      );

  testWidgets('空目录保留创建和助记词导入入口', (tester) async {
    await tester.pumpWidget(gate(() async => _state(const [])));
    await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsNothing);
    expect(find.widgetWithText(FilledButton, '创建钱包'), findsOneWidget);
    expect(find.text('已有钱包？导入助记词'), findsOneWidget);
  });

  testWidgets('热账户或冷账户任一存在都放行', (tester) async {
    for (final mode in CitizenWalletSignMode.values) {
      await tester.pumpWidget(gate(() async => _state([_account(mode)])));
      await tester.pumpAndSettle();
      expect(find.text('main-shell'), findsOneWidget);
    }
  });

  testWidgets('SDK 目录读取失败不误判为空，重试后放行', (tester) async {
    var calls = 0;
    await tester.pumpWidget(gate(() async {
      calls += 1;
      if (calls == 1) throw Exception('sdk unavailable');
      return _state([_account(CitizenWalletSignMode.hot)]);
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('本地钱包读取失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsOneWidget);
  });

  testWidgets('运行期 SDK 账户删空后回到门禁', (tester) async {
    var accounts = <CitizenWalletStateAccount>[
      _account(CitizenWalletSignMode.hot),
    ];
    await tester.pumpWidget(gate(() async => _state(accounts)));
    await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsOneWidget);
    accounts = const [];
    security.notifyDefaultAccountChanged();
    await tester.pumpAndSettle();
    expect(find.text('main-shell'), findsNothing);
    expect(find.widgetWithText(FilledButton, '创建钱包'), findsOneWidget);
  });

  testWidgets('永久 pending 会按门禁超时显示错误', (tester) async {
    final pending = Completer<CitizenWalletState>();
    await tester.pumpWidget(
      Provider<AccountSecurityService>.value(
        value: security,
        child: MaterialApp(
          home: WalletGate(
            walletStateLoader: () => pending.future,
            loadTimeout: const Duration(milliseconds: 20),
            child: const Scaffold(body: Text('main-shell')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 25));
    expect(find.textContaining('本地钱包读取失败'), findsOneWidget);
  });
}

CitizenWalletState _state(List<CitizenWalletStateAccount> accounts) =>
    CitizenWalletState(
      revision: BigInt.one,
      hotProfile: null,
      accounts: accounts,
    );

CitizenWalletStateAccount _account(CitizenWalletSignMode mode) =>
    CitizenWalletStateAccount(
      signMode: mode,
      walletIndex: 0,
      accountIndex: mode == CitizenWalletSignMode.hot ? 0 : null,
      accountId:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      ss58Address: 'test-address',
      name: mode.name,
      createdAtMillis: BigInt.zero,
      isDefault: true,
    );

Future<void> _registerNothing({
  required String cidNumber,
  required int bindingRevision,
  required String accountId,
  required Future<String> Function({
    required Uint8List payload,
    required Uint8List signingMessage,
    required String devicePublicKey,
    required int issuedAtMillis,
  }) signBinding,
}) async {}

Future<String> _rejectColdBinding({
  required AccountDataBinding binding,
  required Uint8List payload,
  required Uint8List signingMessage,
  required String devicePublicKey,
  required int issuedAtMillis,
}) =>
    throw UnimplementedError();

Future<List<Uint8List>> _rejectColdKeys({
  required AccountDataBinding binding,
  required List<DataKeyRequest> requests,
}) =>
    throw UnimplementedError();

final class _UnusedWallet implements CitizenSdkWallet {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedSigning implements CitizenSigning {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
