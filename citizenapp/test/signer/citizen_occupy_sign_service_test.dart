import '../support/fake_citizen_sdk.dart';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/signer/citizen_occupy_sign_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _cid = 'CN220-CTZN2-198805200-2026';
const _expiresAt = 1900000000;

CitizenWalletStateAccount _account({int index = 0, int accountByte = 0xab}) =>
    CitizenWalletStateAccount(
      signMode: CitizenWalletSignMode.hot,
      walletIndex: 0,
      accountIndex: index,
      accountId: '0x${_hexByte(accountByte) * 32}',
      ss58Address: 'w5FhTestAddress',
      name: '账户$index',
      createdAtMillis: BigInt.zero,
      isDefault: index == 0,
    );

class _FakeWallet implements CitizenSdkWallet {
  _FakeWallet({this.currentAccount});

  final CitizenWalletStateAccount? currentAccount;

  @override
  CitizenSdkOperation<CitizenWalletState> getState() => testCitizenOperation(() async => CitizenWalletState(
        initializationState: currentAccount == null ? CitizenWalletInitializationState.empty : CitizenWalletInitializationState.ready,
        cleanupPending: false,
        revision: BigInt.one,
        hotProfile: null,
        accounts: currentAccount == null ? const [] : [currentAccount!],
      ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSigning implements CitizenSigning {
  String? signedAccountId;
  Uint8List? signedPayload;
  final List<String> signedAccountIds = <String>[];
  final List<Uint8List> signedPayloads = <Uint8List>[];

  @override
  CitizenSdkOperation<CitizenSigningOutcome> begin(CitizenSigningIntent intent) => testCitizenOperation(() async {
    signedAccountId = intent.accountId;
    signedPayload = Uint8List.fromList(intent.payload);
    signedAccountIds.add(intent.accountId);
    signedPayloads.add(Uint8List.fromList(intent.payload));
    return CitizenSigningCompleted(
      accountId: intent.accountId,
      payloadHash: '0x${'00' * 32}',
      signature: Uint8List(64),
    );
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _hexByte(int value) => value.toRadixString(16).padLeft(2, '0');

List<int> _u64Le(int value) =>
    List<int>.generate(8, (index) => (value >> (index * 8)) & 0xff);

List<int> _occupyTemplate({int revision = 0, int expiresAt = _expiresAt}) => [
      ...List<int>.filled(32, 0x44),
      _cid.length << 2,
      ..._cid.codeUnits,
      ...List<int>.filled(32, 0),
      ..._u64Le(revision),
      ..._u64Le(expiresAt),
    ];

List<int> _rebindTemplate({int revision = 7, int expiresAt = _expiresAt}) => [
      ...List<int>.filled(32, 0x44),
      _cid.length << 2,
      ..._cid.codeUnits,
      ...List<int>.filled(32, 0x55),
      ...List<int>.filled(32, 0),
      ..._u64Le(revision),
      ..._u64Le(expiresAt),
    ];

/// 合成授权模板交由真实SDK编码；测试不持有App协议实现。
Future<String> _domainRaw(CitizenQr qr, {
  int? action,
  List<int>? payload,
  int outerExpiresAt = _expiresAt,
}) async {
  final actualAction = action ?? CitizenQrActions.citizenOccupy;
  final authorization = payload ?? (actualAction == CitizenQrActions.citizenOccupy
      ? _occupyTemplate() : _rebindTemplate());
  return (await qr.encodeDocument(CitizenQrContent.signRequest(
    requestId: 'citizen-occupy-req-000001', expiresAt: BigInt.from(outerExpiresAt),
    action: actualAction, reviewPayload: Uint8List.fromList(authorization),
  ))).canonicalText;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestCitizenSdkTransport encodingTransport;
  late CitizenSdk encodingSdk;
  setUp(() async {
    encodingTransport = TestCitizenSdkTransport({}, useCore: true);
    encodingSdk = await encodingTransport.open();
  });
  tearDown(() async {
    await encodingSdk.close();
    await encodingTransport.dispose();
  });

  late CitizenOccupySignService service;
  setUp(() { service = CitizenOccupySignService(qr: encodingSdk.qr); });

  test('SDK占号与换绑公开动作保留原QR_V1数值', () {
    expect(CitizenQrActions.citizenOccupy, 10);
    expect(CitizenQrActions.citizenRebind, 11);
  });

  test('prepare 严格解出占号完整授权模板并展示全部防重放字段', () async {
    final prep = await service.prepare(await _domainRaw(encodingSdk.qr), _account());
    expect(prep.cidNumber, _cid);
    expect(prep.isOccupy, isTrue);
    expect(prep.genesisHash, '0x${'44' * 32}');
    expect(prep.currentAccountId, isNull);
    expect(prep.expectedBindingRevision, BigInt.zero);
    expect(prep.expiresAt, BigInt.from(_expiresAt));
    expect(prep.account.accountId, '0x${'ab' * 32}');
  });

  test('prepare 严格解出换绑当前账户、非零 revision 与 expires', () async {
    final prep = await service.prepare(
        await _domainRaw(encodingSdk.qr, action: CitizenQrActions.citizenRebind), _account());
    expect(prep.isOccupy, isFalse);
    expect(prep.cidNumber, _cid);
    expect(prep.genesisHash, '0x${'44' * 32}');
    expect(prep.currentAccountId, '0x${'55' * 32}');
    expect(prep.expectedBindingRevision, BigInt.from(7));
    expect(prep.expiresAt, BigInt.from(_expiresAt));
  });

  test('非占号/换绑动作即拒', () async {
    final raw = (await encodingSdk.qr.encodeDocument(CitizenQrContent.signRequest(
      requestId: 'citizen-identity-req-0001', signerAccountId: '0x${'11' * 32}',
      reviewPayload: Uint8List.fromList([1, 2, 3, 4]),
      action: CitizenQrActions.citizenIdentity, expiresAt: BigInt.from(_expiresAt),
    ))).canonicalText;
    await expectLater(
      service.prepare(raw, _account()),
      throwsA(isA<CitizenOccupySignException>()),
    );
  });

  test('旧 CID-only 载荷即拒，不恢复末尾追加账户协议', () async {
    await expectLater(
      service.prepare(
        await _domainRaw(encodingSdk.qr, payload: [_cid.length << 2, ..._cid.codeUnits]),
        _account(),
      ),
      throwsA(isA<CitizenOccupySignException>()),
    );
  });

  test('外层 e 与内层 expires_at 不一致即拒', () async {
    await expectLater(
      service.prepare(
        await _domainRaw(encodingSdk.qr, outerExpiresAt: _expiresAt + 1),
        _account(),
      ),
      throwsA(
        isA<CitizenOccupySignException>().having(
          (error) => error.message,
          'message',
          contains('过期时间'),
        ),
      ),
    );
  });

  test('零槽污染、尾字节与错误 revision 全部 fail-closed', () async {
    final nonZeroSlot = _occupyTemplate();
    nonZeroSlot[32 + 1 + _cid.length] = 1;
    final malformed = <List<int>>[
      nonZeroSlot,
      [..._occupyTemplate(), 0xff],
      _occupyTemplate(revision: 1),
      _rebindTemplate(revision: 0),
    ];
    for (var index = 0; index < malformed.length; index++) {
      await expectLater(
        service.prepare(
          await _domainRaw(encodingSdk.qr,
            action: index == malformed.length - 1
                ? CitizenQrActions.citizenRebind
                : CitizenQrActions.citizenOccupy,
            payload: malformed[index],
          ),
          _account(),
        ),
        throwsA(isA<CitizenOccupySignException>()),
        reason: 'malformed template #$index must reject',
      );
    }
  });

  test('换绑选择账户与 current_account_id 相同即拒', () async {
    await expectLater(
      service.prepare(
        await _domainRaw(encodingSdk.qr, action: CitizenQrActions.citizenRebind),
        _account(accountByte: 0x55),
      ),
      throwsA(
        isA<CitizenOccupySignException>().having(
          (error) => error.message,
          'message',
          contains('不得与当前绑定账户相同'),
        ),
      ),
    );
  });

  test('账户卡锁定的子账户原位填入占号零槽后签名', () async {
    final account = _account(index: 5);
    final signing = _FakeSigning();
    final prep = await service.prepare(await _domainRaw(encodingSdk.qr), account);
    await service.sign(prep, signing, null);
    expect(prep.account.accountIndex, 5);
    expect(signing.signedAccountId, account.accountId);
    final exactAuthorization = _occupyTemplate()
      ..setRange(
        32 + 1 + _cid.length,
        32 + 1 + _cid.length + 32,
        List<int>.filled(32, 0xab),
      );
    expect(
      signing.signedPayload,
      (await CitizenSigning.encodePayload(CitizenSigningPayload.message(
        opTag: kOpSignCidOccupy,
        scalePayload: Uint8List.fromList(exactAuthorization),
      ))),
    );
  });

  test('注册局换绑在同一次扫码中收集当前与新账户对同一授权的双签名', () async {
    final newAccount = _account(accountByte: 0xab);
    final currentAccount = _account(accountByte: 0x55);
    final wallet = _FakeWallet(currentAccount: currentAccount);
    final signing = _FakeSigning();
    final prep = await service.prepare(
      await _domainRaw(encodingSdk.qr, action: CitizenQrActions.citizenRebind),
      newAccount,
      wallet,
    );

    expect(prep.currentAccount?.accountId, currentAccount.accountId);
    final raw = await service.sign(prep, signing, null);
    expect(signing.signedAccountIds, <String>[
      newAccount.accountId,
      currentAccount.accountId,
    ]);

    final exactAuthorization = _rebindTemplate()
      ..setRange(
        32 + 1 + _cid.length + 32,
        32 + 1 + _cid.length + 64,
        List<int>.filled(32, 0xab),
      );
    expect(
      signing.signedPayloads[0],
      (await CitizenSigning.encodePayload(CitizenSigningPayload.message(
        opTag: kOpSignCidAdminRebind,
        scalePayload: Uint8List.fromList(exactAuthorization),
      ))),
    );
    expect(
      signing.signedPayloads[1],
      (await CitizenSigning.encodePayload(CitizenSigningPayload.message(
        opTag: kOpSignCidRebind,
        scalePayload: Uint8List.fromList(exactAuthorization),
      ))),
    );

    final response = await encodingSdk.qr.parse(raw);
    expect(response.signerAccountId, newAccount.accountId);
    expect(response.currentAccountId, currentAccount.accountId);
    expect(response.currentAccountSignature, Uint8List(64));
  });

  test('当前钱包不在本机时注册局仍可强制换绑，但响应不伪造当前账户签名', () async {
    final wallet = _FakeWallet();
    final signing = _FakeSigning();
    final prep = await service.prepare(
      await _domainRaw(encodingSdk.qr, action: CitizenQrActions.citizenRebind),
      _account(accountByte: 0xab),
      wallet,
    );
    expect(prep.currentAccount, isNull);

    final response = await encodingSdk.qr.parse(await service.sign(prep, signing, null));
    expect(signing.signedAccountIds, <String>['0x${'ab' * 32}']);
    expect(response.currentAccountId, isNull);
    expect(response.currentAccountSignature, isNull);
  });
}
