import 'dart:async';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/security/account_data_key_provision.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/local_data_key.dart';

const _hotId =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _coldId =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late AccountSecurityService security;

  setUp(() {
    security = AccountSecurityService(
      wallet: _FakeWallet(_account(_hotId, CitizenWalletSignMode.hot)),
      signing: _UnusedSigning(),
      subkeyRegistrar: _registerNothing,
      coldDeviceBindingSigner: _rejectColdBinding,
      coldAccountDataKeyProvider: _rejectColdKeys,
    );
  });
  tearDown(() => security.dispose());

  test('只读取 SDK 顺序第一账户的精确绑定', () async {
    final requested = <String>[];
    final context = CurrentUserContext(
      wallet: _FakeWallet(_account(_hotId, CitizenWalletSignMode.hot)),
      accountSecurity: security,
      bindingReader: (accountId) async {
        requested.add(accountId);
        return null;
      },
    );
    expect((await context.resolve())!.accountId, _hotId);
    expect(requested, [_hotId]);
  });

  test('冷账户可以成为当前默认用户', () async {
    final context = CurrentUserContext(
      wallet: _FakeWallet(_account(_coldId, CitizenWalletSignMode.cold)),
      accountSecurity: security,
      bindingReader: (_) async => _binding(_coldId, 'CID-COLD'),
    );
    final current = await context.resolve();
    expect(current!.account.signMode, CitizenWalletSignMode.cold);
    expect(current.cidNumber, 'CID-COLD');
  });

  test('并发读取合并，显式失效后重新精确读取', () async {
    var calls = 0;
    final completer = Completer<AccountDataBinding?>();
    final context = CurrentUserContext(
      wallet: _FakeWallet(_account(_hotId, CitizenWalletSignMode.hot)),
      accountSecurity: security,
      bindingReader: (_) {
        calls += 1;
        return calls == 1
            ? completer.future
            : Future.value(_binding(_hotId, 'CID-HOT'));
      },
    );
    final reads = [context.resolve(), context.resolve(), context.resolve()];
    completer.complete(_binding(_hotId, 'CID-HOT'));
    await Future.wait(reads);
    await context.resolve();
    expect(calls, 1);
    context.invalidate();
    expect((await context.resolve())!.cidNumber, 'CID-HOT');
    expect(calls, 2);
  });

  test('SDK 账户目录为空时返回 null', () async {
    final context = CurrentUserContext(
      wallet: _FakeWallet(null),
      accountSecurity: security,
      bindingReader: (_) async => throw StateError('不应读取绑定'),
    );
    expect(await context.resolve(), isNull);
  });
}

CitizenWalletStateAccount _account(
  String accountId,
  CitizenWalletSignMode mode,
) =>
    CitizenWalletStateAccount(
      signMode: mode,
      walletIndex: 0,
      accountIndex: mode == CitizenWalletSignMode.hot ? 0 : null,
      accountId: accountId,
      ss58Address: '${mode.name}-ss58',
      name: mode.name,
      createdAtMillis: BigInt.zero,
      isDefault: true,
    );

AccountDataBinding _binding(String accountId, String cid) => AccountDataBinding(
      genesisHash: '0x${'11' * 32}',
      cidNumber: cid,
      bindingRevision: 1,
      accountId: accountId,
    );

final class _FakeWallet implements CitizenSdkWallet {
  _FakeWallet(this.account);
  final CitizenWalletStateAccount? account;

  @override
  Future<CitizenWalletState> getState() async => CitizenWalletState(
        revision: BigInt.one,
        hotProfile: null,
        accounts: account == null ? const [] : [account!],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedSigning implements CitizenSigning {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
