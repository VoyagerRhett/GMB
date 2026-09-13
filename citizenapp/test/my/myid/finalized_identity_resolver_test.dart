import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import '../../support/fake_citizen_sdk.dart';

const _account0 =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _account5 =
    '0x5555555555555555555555555555555555555555555555555555555555555555';

/// 金标：链上创世 `CidRegistry[CN220-CTZN2-198805200-2026]` 逐字节实测值
/// （2026-07-31 于 127.0.0.1:9944 finalized 读出，共 67 字节）。
///
/// registrar "ZS001-FRG07-249474503-2026" | commitment 32B | 省码空 | 市码空
/// | status=Active | registered_at=0 | revoked_at=None。
const _genesisCidRecordHex =
    '685a533030312d46524730372d3234393437343530332d323032'
    '3693c7cc569ee4c38bead016a83ffd5e76d1c6a628555b55805cf18d3f06779a66'
    '0000000000000000';

const _genesisCid = 'CN220-CTZN2-198805200-2026';
const _genesisAccountId =
    '0x0cb1d05c0c9c7f05679b60d6f24c7e5719a3985264e41c5e899d4822dca4b06b';

final _genesisDefaultAccount = CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.hot,
  walletIndex: 1,
  accountIndex: 0,
  name: '钱包1',
  ss58Address: 'ss58-genesis',
  accountId: _genesisAccountId,
  createdAtMillis: BigInt.zero,
  isDefault: true,
);

final _default0 = CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.hot,
  walletIndex: 1,
  accountIndex: 0,
  name: '账户0',
  ss58Address: 'ss58-0',
  accountId: _account0,
  createdAtMillis: BigInt.zero,
  isDefault: true,
);

final _default5 = CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.cold,
  walletIndex: 2,
  accountIndex: null,
  name: '冷账户5',
  ss58Address: 'ss58-5',
  accountId: _account5,
  createdAtMillis: BigInt.zero,
  isDefault: true,
);

CitizenIdentityChainSnapshot _anonSnapshot() => CitizenIdentityChainSnapshot(
      cidNumber: 'CID-TEST-0001',
      accountId: Uint8List(32),
      bindingRevision: 1,
      votingIdentity: null,
      candidateIdentity: null,
    );

void main() {
  ({FinalizedIdentityResolver resolver, _FakeReader reader}) resolver({
    CitizenWalletStateAccount? account,
    bool noAccount = false,
    Map<String, CitizenIdentityChainSnapshot> chain = const {},
    String? throwFor,
  }) {
    final reader = _FakeReader(chain, throwFor: throwFor);
    return (
      resolver: FinalizedIdentityResolver(
        wallet: _FakeWallet(noAccount ? null : account ?? _default0),
        chain: TestCitizenChain(),
        chainReader: reader,
      ),
      reader: reader,
    );
  }

  test('默认账户绑 CID → 当前用户命中且只读取该账户一次', () async {
    final fixture = resolver(
      chain: {_account0: _anonSnapshot()},
    );
    final r = await fixture.resolver.resolve();
    expect(r, isNotNull);
    expect(r!.accountId, _account0);
    expect(r.isRegistered, isTrue);
    expect(fixture.reader.calls, [_account0]);
  });

  test('默认账户无 CID 时保持访客，禁止扫描另一个有 CID 的账户', () async {
    final fixture = resolver(
      chain: {_account5: _anonSnapshot()},
    );
    final r = await fixture.resolver.resolve();
    expect(r!.accountId, _account0);
    expect(r.isRegistered, isFalse);
    expect(r.snapshot, isNull);
    expect(fixture.reader.calls, [_account0]);
  });

  test('冷钱包也可成为默认账户并解析其 CID', () async {
    final fixture = resolver(
      account: _default5,
      chain: {_account5: _anonSnapshot()},
    );
    final r = await fixture.resolver.resolve();
    expect(r!.accountId, _account5);
    expect(r.isRegistered, isTrue);
    expect(fixture.reader.calls, [_account5]);
  });

  test('没有任何默认账户 → null', () async {
    final r = await resolver(noAccount: true).resolver.resolve();
    expect(r, isNull);
  });

  test('链读异常上抛,绝不吞成访客/未注册', () async {
    await expectLater(
      resolver(throwFor: _account0).resolver.resolve(),
      throwsA(isA<StateError>()),
    );
  });

  test('按 CID 读取绑定锚定同一 finalized 区块并校验双向闭环', () async {
    const cidNumber = 'CN220-CTZN2-100000001-2026';
    final accountId = Uint8List.fromList(List<int>.filled(32, 0xaa));
    final cidScale = CitizenIdentityChainReader.encodeBoundedBytes(
      cidNumber.codeUnits,
    );
    String key(String storageName, Uint8List data) =>
        CitizenIdentityChainReader.hexEncode(
          CitizenIdentityChainReader.storageMapKey(
            'CitizenIdentity',
            storageName,
            data,
          ),
        );
    final chainRpc = _BindingChain(<String, Uint8List>{
      key('AccountIdByCid', cidScale): accountId,
      key('CidRegistry', cidScale): _activeCidRecord(),
      key('BindingRevisionByCid', cidScale):
          Uint8List.fromList([2, 0, 0, 0, 0, 0, 0, 0]),
      key('CidByAccountId', accountId):
          CitizenIdentityChainReader.encodeBoundedBytes(cidNumber.codeUnits),
    });

    final result = await CitizenIdentityChainReader(chain: chainRpc)
        .readBindingByCidNumber(cidNumber);

    expect(result, isNotNull);
    expect(result!.accountIdText, _accountIdText(accountId));
    expect(result.bindingRevision, 2);
    expect(
      chainRpc.blockHashes.toSet(),
      {'0x${List<String>.filled(32, '00').join()}'},
    );
  });

  test('按 CID 读取时反向账户映射不一致必须失败关闭', () async {
    const cidNumber = 'CN220-CTZN2-100000001-2026';
    final accountId = Uint8List.fromList(List<int>.filled(32, 0xbb));
    final cidScale = CitizenIdentityChainReader.encodeBoundedBytes(
      cidNumber.codeUnits,
    );
    String key(String storageName, Uint8List data) =>
        CitizenIdentityChainReader.hexEncode(
          CitizenIdentityChainReader.storageMapKey(
            'CitizenIdentity',
            storageName,
            data,
          ),
        );
    final chainRpc = _BindingChain(<String, Uint8List>{
      key('AccountIdByCid', cidScale): accountId,
      key('CidRegistry', cidScale): _activeCidRecord(),
      key('BindingRevisionByCid', cidScale):
          Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0]),
      key('CidByAccountId', accountId):
          CitizenIdentityChainReader.encodeBoundedBytes('OTHER-CID'.codeUnits),
    });

    final result = await CitizenIdentityChainReader(chain: chainRpc)
        .readBindingByCidNumber(cidNumber);

    expect(result, isNull);
  });

  group('CidRecord 解析', () {
    test('创世金标:居住省/市码为空的 Active 记录判 Active', () {
      final record = _bytes(_genesisCidRecordHex);
      expect(record.length, 67);
      expect(CitizenIdentityChainReader.cidRecordIsActive(record), isTrue);
    });

    test('居住省/市码非空同样判 Active', () {
      final record = Uint8List.fromList([
        ..._bounded('FEDERAL_REGISTRY-CID'),
        ...List<int>.filled(32, 7),
        ..._bounded('GD'),
        ..._bounded('0755'),
        0,
        1,
        0,
        0,
        0,
        0,
      ]);
      expect(CitizenIdentityChainReader.cidRecordIsActive(record), isTrue);
    });

    test('记录不存在判非 Active,不抛异常', () {
      expect(CitizenIdentityChainReader.cidRecordIsActive(null), isFalse);
    });

    test('status=Revoked 判非 Active', () {
      final record = _bytes(_genesisCidRecordHex);
      record[61] = 1; // CidRecordStatus::Revoked
      expect(CitizenIdentityChainReader.cidRecordIsActive(record), isFalse);
    });

    test('Active 却带撤销块号 → 自相矛盾判非 Active', () {
      final record = Uint8List.fromList([
        ..._bytes(_genesisCidRecordHex).sublist(0, 66),
        1, 9, 0, 0, 0, // revoked_at = Some(9)
      ]);
      expect(CitizenIdentityChainReader.cidRecordIsActive(record), isFalse);
    });

    test('布局截断上抛,绝不吞成非 Active', () {
      expect(
        () => CitizenIdentityChainReader.cidRecordIsActive(
          _bytes(_genesisCidRecordHex).sublist(0, 62),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('尾随字节非法上抛', () {
      expect(
        () => CitizenIdentityChainReader.cidRecordIsActive(
          Uint8List.fromList([..._bytes(_genesisCidRecordHex), 0]),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('创世匿名身份端到端', () {
    Map<String, Uint8List> genesisStorage() {
      final accountId = _bytes(_genesisAccountId.substring(2));
      final cidScale = CitizenIdentityChainReader.encodeBoundedBytes(
        _genesisCid.codeUnits,
      );
      String key(String storageName, Uint8List data) =>
          CitizenIdentityChainReader.hexEncode(
            CitizenIdentityChainReader.storageMapKey(
              'CitizenIdentity',
              storageName,
              data,
            ),
          );
      // VotingIdentityByCid / CandidateIdentityByCid 故意缺席 = 匿名已注册。
      return <String, Uint8List>{
        key('CidByAccountId', accountId):
            CitizenIdentityChainReader.encodeBoundedBytes(
                _genesisCid.codeUnits),
        key('AccountIdByCid', cidScale): accountId,
        key('CidRegistry', cidScale): _bytes(_genesisCidRecordHex),
        key('BindingRevisionByCid', cidScale):
            Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0]),
      };
    }

    test('readByAccountId 命中匿名快照', () async {
      final snapshot = await CitizenIdentityChainReader(
              chain: _BindingChain(genesisStorage()))
          .readByAccountId(_genesisAccountId);

      expect(snapshot, isNotNull);
      expect(snapshot!.cidNumber, _genesisCid);
      expect(snapshot.bindingRevision, 1);
      expect(snapshot.isAnonymous, isTrue);
    });

    test('门禁判据 isRegistered = true(不再误判未注册)', () async {
      final r = await FinalizedIdentityResolver(
        wallet: _FakeWallet(_genesisDefaultAccount),
        chain: TestCitizenChain(),
        chainReader: CitizenIdentityChainReader(
          chain: _BindingChain(genesisStorage()),
        ),
      ).resolve();

      expect(r, isNotNull);
      expect(r!.accountId, _genesisAccountId);
      expect(r.isRegistered, isTrue);
    });
  });
}

List<int> _bounded(String value) =>
    CitizenIdentityChainReader.encodeBoundedBytes(value.codeUnits);

/// 链上真实形态的 Active `CidRecord`。
///
/// 居住省码/市码**恒为空**：创世 `initial_cid_bindings`、`self_occupy_cid` 与
/// 注册局占号都写 `AreaCodeBound::default()`。夹具必须照此，写非空省市码会让
/// 「空 BoundedVec 解析」这条真实路径永远测不到。
Uint8List _activeCidRecord() => Uint8List.fromList([
      ..._bounded('FEDERAL_REGISTRY-CID'),
      ...List<int>.filled(32, 7), // commitment
      0, // residence_province_code 空
      0, // residence_city_code 空
      0, // status = Active
      1, 0, 0, 0, // registered_at
      0, // revoked_at = None
    ]);

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

String _accountIdText(Uint8List bytes) =>
    CitizenIdentityChainReader.hexEncode(bytes);

class _FakeWallet implements CitizenSdkWallet {
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

class _FakeReader extends CitizenIdentityChainReader {
  _FakeReader(this._chain, {this.throwFor})
      : super(chain: TestCitizenChain());
  final Map<String, CitizenIdentityChainSnapshot> _chain;
  final String? throwFor;
  final List<String> calls = <String>[];

  @override
  Future<CitizenIdentityChainSnapshot?> readByAccountId(
      String accountId) async {
    calls.add(accountId);
    if (accountId == throwFor) throw StateError('chain down');
    return _chain[accountId];
  }
}

class _BindingChain extends TestCitizenChain {
  _BindingChain(this.storage);

  final Map<String, Uint8List> storage;
  final List<String> blockHashes = <String>[];

  @override
  Future<CitizenBlockRef> getFinalizedHead() async => CitizenBlockRef(
        hash: '0x${'00' * 32}',
        number: BigInt.from(7),
        finality: CitizenBlockFinality.finalized,
      );

  @override
  Future<Uint8List?> getStorage(
    CitizenBlockRef block,
    Uint8List key,
  ) async {
    blockHashes.add(block.hash);
    return storage[_hex(key)];
  }

  @override
  Future<List<Uint8List?>> getStorageBatch(
    CitizenBlockRef block,
    List<Uint8List> keys,
  ) async {
    blockHashes.addAll(List<String>.filled(keys.length, block.hash));
    return keys.map((key) => storage[_hex(key)]).toList(growable: false);
  }

  String _hex(List<int> bytes) =>
      '0x${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
}
