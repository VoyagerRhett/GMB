import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/clearing_bank_prefs.dart';

const _accountA =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _accountB =
    '0x2222222222222222222222222222222222222222222222222222222222222222';
const _mainAccountId =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _feeAccountId =
    '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ClearingBankBindingSnapshot _snapshot({
  required String cidNumber,
  String mainAccountId = _mainAccountId,
  String feeAccountId = _feeAccountId,
}) {
  return ClearingBankBindingSnapshot(
    cidNumber: cidNumber,
    cidFullName: '测试清算行',
    cidShortName: '测试清算行',
    mainAccountId: mainAccountId,
    feeAccountId: feeAccountId,
    peerId: '12D3KooWTest',
    rpcDomain: '127.0.0.1',
    rpcPort: 9944,
    boundAtMs: 1,
    lastVerifiedAtMs: 2,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClearingBankPrefs.debugRemoveForTest = null;
  });

  tearDown(() {
    ClearingBankPrefs.debugRemoveForTest = null;
  });

  group('ClearingBankPrefs', () {
    test('loadSnapshot returns null when key absent', () async {
      expect(await ClearingBankPrefs.loadSnapshot(_accountA), isNull);
    });

    test('完整快照按 account_id 隔离', () async {
      await ClearingBankPrefs.saveSnapshot(
        _accountA,
        _snapshot(cidNumber: 'GD001-SCB05-000000001-2026'),
      );
      await ClearingBankPrefs.saveSnapshot(
        _accountB,
        _snapshot(cidNumber: 'BJ001-SCB0U-000000002-2026'),
      );
      expect(
        (await ClearingBankPrefs.loadSnapshot(_accountA))?.cidNumber,
        'GD001-SCB05-000000001-2026',
      );
      expect(
        (await ClearingBankPrefs.loadSnapshot(_accountB))?.cidNumber,
        'BJ001-SCB0U-000000002-2026',
      );
    });

    test('clear removes only the specified account_id', () async {
      await ClearingBankPrefs.saveSnapshot(
          _accountA, _snapshot(cidNumber: 'AAA'));
      await ClearingBankPrefs.saveSnapshot(
          _accountB, _snapshot(cidNumber: 'BBB'));
      await ClearingBankPrefs.clear(_accountA);
      expect(await ClearingBankPrefs.loadSnapshot(_accountA), isNull);
      expect(
          (await ClearingBankPrefs.loadSnapshot(_accountB))?.cidNumber, 'BBB');
    });

    test('clear 在 remove=false 时抛错，不得伪装已删除', () async {
      await ClearingBankPrefs.saveSnapshot(
        _accountA,
        _snapshot(cidNumber: 'REMOVE-FALSE'),
      );
      ClearingBankPrefs.debugRemoveForTest = (_, _) async => false;

      await expectLater(
        ClearingBankPrefs.clear(_accountA),
        throwsA(isA<StateError>()),
      );
      expect(await ClearingBankPrefs.loadSnapshot(_accountA), isNotNull);
    });

    test('clear 回读前并发重建键时抛错，上层不得 ack', () async {
      await ClearingBankPrefs.saveSnapshot(
        _accountA,
        _snapshot(cidNumber: 'BEFORE-REAPPEAR'),
      );
      ClearingBankPrefs.debugRemoveForTest = (prefs, key) async {
        final removed = await prefs.remove(key);
        await prefs.setString(
          key,
          '{"cid_number":"REAPPEARED"}',
        );
        return removed;
      };

      await expectLater(
        ClearingBankPrefs.clear(_accountA),
        throwsA(isA<StateError>()),
      );
      expect(
        (await SharedPreferences.getInstance())
            .containsKey('clearing_bank_binding_$_accountA'),
        isTrue,
      );
    });

    test('saveSnapshot overwrites previous value (切换清算行)', () async {
      await ClearingBankPrefs.saveSnapshot(
          _accountA, _snapshot(cidNumber: 'OLD'));
      await ClearingBankPrefs.saveSnapshot(
          _accountA, _snapshot(cidNumber: 'NEW'));
      expect(
          (await ClearingBankPrefs.loadSnapshot(_accountA))?.cidNumber, 'NEW');
    });

    test('saveSnapshot stores endpoint data', () async {
      await ClearingBankPrefs.saveSnapshot(
        _accountA,
        _snapshot(
          cidNumber: 'GD001-SCB05-000000001-2026',
        ),
      );

      final snapshot = await ClearingBankPrefs.loadSnapshot(_accountA);
      expect(snapshot, isNotNull);
      expect(snapshot!.cidNumber, 'GD001-SCB05-000000001-2026');
      expect(snapshot.wssUrl, 'ws://127.0.0.1:9944');
      expect(snapshot.mainAccountId, _mainAccountId);
      expect(snapshot.feeAccountId, _feeAccountId);
    });

    test('缺少费用账户的旧快照必须拒绝', () async {
      SharedPreferences.setMockInitialValues({
        'clearing_bank_binding_$_accountA':
            '{"cid_number":"GD001-SCB05-000000001-2026",'
                '"main_account_id":"$_mainAccountId",'
                '"rpc_domain":"127.0.0.1","rpc_port":9944}',
      });
      expect(await ClearingBankPrefs.loadSnapshot(_accountA), isNull);
    });
  });
}
