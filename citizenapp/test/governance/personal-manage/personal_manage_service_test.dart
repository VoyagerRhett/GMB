import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/transaction/personal-manage/personal_manage_models.dart';
import 'package:citizenapp/transaction/personal-manage/personal_manage_service.dart';
import 'package:citizenapp/transaction/personal-manage/personal_manage_storage_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';

import '../../support/fake_citizen_sdk.dart';

class FakeChain extends TestCitizenChain {
  final Map<String, Uint8List?> responses = {};
  final List<String> requestedKeys = [];

  @override
  Future<CitizenBlockRef> getFinalizedHead() async => CitizenBlockRef(
        hash: '0x${'11' * 32}',
        number: BigInt.one,
        finality: CitizenBlockFinality.finalized,
      );

  @override
  Future<Uint8List?> getStorage(
    CitizenBlockRef block,
    Uint8List key,
  ) async {
    final storageKeyHex = _hex(key);
    requestedKeys.add(storageKeyHex);
    return responses[storageKeyHex];
  }

  @override
  Future<List<Uint8List?>> getStorageBatch(
    CitizenBlockRef block,
    List<Uint8List> keys,
  ) async {
    final result = <Uint8List?>[];
    for (final key in keys) {
      final keyHex = _hex(key);
      requestedKeys.add(keyHex);
      result.add(responses[keyHex]);
    }
    return result;
  }

  String _hex(List<int> bytes) =>
      '0x${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
}

void main() {
  String hexOf(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  List<int> codeBytes(String code) {
    final out = List<int>.filled(4, 0);
    final raw = code.codeUnits;
    for (var i = 0; i < out.length && i < raw.length; i++) {
      out[i] = raw[i];
    }
    return out;
  }

  List<int> compactVec(String text) {
    final bytes = utf8.encode(text);
    return [(bytes.length << 2) & 0xff, ...bytes];
  }

  List<int> compactU32(int value) {
    if (value < 64) return [(value << 2) & 0xff];
    final encoded = (value << 2) | 0x01;
    return [encoded & 0xff, (encoded >> 8) & 0xff];
  }

  List<int> adminBytes(
    List<int> account, {
    String familyName = '管理',
    String givenName = '员',
  }) =>
      [
        ...account,
        0, // 空公民 CID（统一 Admin 恒带 cid，Compact(0)）
        ...compactVec(familyName),
        ...compactVec(givenName),
      ];

  AdminPerson adminPerson(
    List<int> account, {
    String familyName = '管理',
    String givenName = '员',
  }) =>
      AdminPerson(
        account_id: '0x${hexOf(account)}',
        family_name: familyName,
        given_name: givenName,
      );

  List<int> u32Le(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];

  List<int> u128Le(BigInt value) {
    final out = List<int>.filled(16, 0);
    var tmp = value;
    for (var i = 0; i < 16; i++) {
      out[i] = (tmp & BigInt.from(0xff)).toInt();
      tmp = tmp >> 8;
    }
    return out;
  }

  Uint8List personalAccountBytes() {
    return Uint8List.fromList([
      ...List<int>.filled(32, 0xc2),
      ...compactVec('家庭基金'),
      ...u32Le(100),
      1,
    ]);
  }

  Uint8List adminAccountBytes({
    required List<int> admin1,
    required List<int> admin2,
  }) {
    return Uint8List.fromList([
      0x00, // cid_number(AdminAccount 前导字段;个人多签为空)
      ...codeBytes('PMUL'),
      2, // AdminAccountKind::PersonalMultisig
      (2 << 2) & 0xff,
      ...adminBytes(admin1, familyName: '张', givenName: '三'),
      ...adminBytes(admin2, familyName: '李', givenName: '四'),
      ...List<int>.filled(32, 0x44), // creator
      ...u32Le(100), // created_at
      ...u32Le(101), // updated_at
      1, // Active
    ]);
  }

  group('PersonalManageService', () {
    test('builds propose_create_personal call_data with regular_threshold', () {
      final admin1 = Uint8List.fromList(List<int>.filled(32, 0x11));
      final admin2 = Uint8List.fromList(List<int>.filled(32, 0x22));
      final accountName = Uint8List.fromList(utf8.encode('家庭基金'));

      final callData = PersonalManageService.buildProposeCreatePersonalCallData(
        accountName: accountName,
        admins: [
          adminPerson(admin1, familyName: '张', givenName: '三'),
          adminPerson(admin2, familyName: '李', givenName: '四'),
        ],
        regularThreshold: 2,
        amountFen: BigInt.from(111),
      );

      final expected = <int>[
        0x07,
        0x00,
        ...compactVec('家庭基金'),
        (2 << 2) & 0xff,
        ...adminBytes(admin1, familyName: '张', givenName: '三'),
        ...adminBytes(admin2, familyName: '李', givenName: '四'),
        ...u32Le(2),
        ...u128Le(BigInt.from(111)),
      ];

      expect(hexOf(callData), hexOf(expected));
    });

    test('rejects regular_threshold below strict majority', () {
      final admins = List.generate(
        4,
        (i) => adminPerson(List<int>.filled(32, 0x10 + i)),
      );

      expect(
        () => PersonalManageService.buildProposeCreatePersonalCallData(
          accountName: Uint8List.fromList(utf8.encode('家庭基金')),
          admins: admins,
          regularThreshold: 2,
          amountFen: BigInt.from(111),
        ),
        throwsArgumentError,
      );
    });

    test('decodes current PersonalManage create ProposalData', () {
      final service = PersonalManageService(
        chain: TestCitizenChain(),
        transactions: TestCitizenTransactions(),
      );
      final inner = <int>[
        ...utf8.encode('per-mgmt'),
        0x00,
        ...List<int>.filled(32, 0x33),
        ...List<int>.filled(32, 0x44),
        ...u128Le(BigInt.from(111)),
        ...u128Le(BigInt.from(10)),
      ];
      final raw = Uint8List.fromList([
        ...compactU32(inner.length),
        ...inner,
      ]);

      final decoded = service.decodePersonalProposalData(7, raw);

      expect(decoded, isA<CreateProposalInfo>());
      final info = decoded as CreateProposalInfo;
      expect(info.proposalId, 7);
      expect(info.accountId, '0x${'33' * 32}');
      expect(info.amountFen, BigInt.from(111));
      expect(info.feeFen, BigInt.from(10));
    });

    test('fetchPersonalAccount reads PersonalManage current storage', () async {
      final rpc = FakeChain();
      final service = PersonalManageService(chain: rpc, transactions: TestCitizenTransactions());
      final accountId = '0x${'22' * 32}';
      final personalKey =
          '0x${hexOf(PersonalManageStorageCodec.personalAccountsKey(accountId))}';
      final adminKey = '0x${hexOf(PersonalManageStorageCodec.adminAccountKey(
        PersonalManageStorageCodec.accountIdBytes(accountId),
      ))}';
      final thresholdKey =
          '0x${hexOf(PersonalManageStorageCodec.activePersonalThresholdKey(
        PersonalManageStorageCodec.accountIdBytes(accountId),
      ))}';
      rpc.responses[personalKey] = personalAccountBytes();
      rpc.responses[adminKey] = adminAccountBytes(
        admin1: List<int>.filled(32, 0xcc),
        admin2: List<int>.filled(32, 0xdd),
      );
      rpc.responses[thresholdKey] = Uint8List.fromList(u32Le(2));

      final info = await service.fetchPersonalAccount(accountId);

      expect(info, isNotNull);
      expect(
        info!.admins.map((admin) => admin.account_id),
        ['0x${'cc' * 32}', '0x${'dd' * 32}'],
      );
      expect(info.threshold, 2);
      expect(info.status, MultisigStatus.active);
      expect(rpc.requestedKeys, [personalKey, adminKey, thresholdKey]);
    });

    test('fetchPersonalAccountsBatch reads accounts in staged storage batches',
        () async {
      final rpc = FakeChain();
      final service = PersonalManageService(chain: rpc, transactions: TestCitizenTransactions());
      final firstAccountId = '0x${'22' * 32}';
      final secondAccountId = '0x${'33' * 32}';
      String personalKey(String accountId) =>
          '0x${hexOf(PersonalManageStorageCodec.personalAccountsKey(accountId))}';
      String adminKey(String accountId) =>
          '0x${hexOf(PersonalManageStorageCodec.adminAccountKey(
            PersonalManageStorageCodec.accountIdBytes(accountId),
          ))}';
      String thresholdKey(String accountId) =>
          '0x${hexOf(PersonalManageStorageCodec.activePersonalThresholdKey(
            PersonalManageStorageCodec.accountIdBytes(accountId),
          ))}';

      rpc.responses[personalKey(firstAccountId)] = personalAccountBytes();
      rpc.responses[personalKey(secondAccountId)] = personalAccountBytes();
      rpc.responses[adminKey(firstAccountId)] = adminAccountBytes(
        admin1: List<int>.filled(32, 0xaa),
        admin2: List<int>.filled(32, 0xbb),
      );
      rpc.responses[adminKey(secondAccountId)] = adminAccountBytes(
        admin1: List<int>.filled(32, 0xcc),
        admin2: List<int>.filled(32, 0xdd),
      );
      rpc.responses[thresholdKey(firstAccountId)] =
          Uint8List.fromList(u32Le(2));

      final infos = await service.fetchPersonalAccountsBatch([
        firstAccountId,
        secondAccountId,
      ]);

      expect(
        infos[firstAccountId]!.admins.map((admin) => admin.account_id),
        ['0x${'aa' * 32}', '0x${'bb' * 32}'],
      );
      expect(
        infos[secondAccountId]!.admins.map((admin) => admin.account_id),
        ['0x${'cc' * 32}', '0x${'dd' * 32}'],
      );
      expect(infos[firstAccountId]!.threshold, 2);
      expect(infos[secondAccountId]!.threshold, isNull);
      expect(rpc.requestedKeys, [
        personalKey(firstAccountId),
        adminKey(firstAccountId),
        personalKey(secondAccountId),
        adminKey(secondAccountId),
        thresholdKey(firstAccountId),
        thresholdKey(secondAccountId),
      ]);
    });

  });
}
