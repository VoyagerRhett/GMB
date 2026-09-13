import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_models.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_service.dart';
import '../../support/fake_citizen_sdk.dart';

class _RawStorageChain extends TestCitizenChain {
  _RawStorageChain(this.value);

  final Uint8List value;
  final List<String> storageKeys = [];

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
    storageKeys.add(
      '0x${key.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}',
    );
    return value;
  }
}

/// 批量解码路径（_decodeProposalData）布局回归。
///
/// 固化当前 runtime `MODULE_TAG + TransferAction` SCALE 布局，确保机构转账
/// 始终按 actor CID + funding account 解码，短备注和空备注都不会静默消失。
void main() {
  List<int> compactU32(int value) {
    if (value < 64) return [value << 2];
    final v = (value << 2) | 1;
    return [v & 0xff, (v >> 8) & 0xff];
  }

  List<int> u128Le(BigInt value) {
    final bytes = List<int>.filled(16, 0);
    var remaining = value;
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    return bytes;
  }

  List<int> u32Le(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];

  List<int> u64Le(int value) =>
      List<int>.generate(8, (i) => (value >> (i * 8)) & 0xff);

  Uint8List institutionPayload({
    required List<int> institutionAccountId,
    required List<int> beneficiary,
    required BigInt amountFen,
    required String remark,
    required List<int> proposer,
  }) {
    const actorCidNumber = 'LN001-CGOVC-000000001-2026';
    final actorCidBytes = utf8.encode(actorCidNumber);
    final remarkBytes = utf8.encode(remark);
    final body = <int>[
      ...utf8.encode('multisig'),
      0x01, // actor_cid_number: Some
      ...compactU32(actorCidBytes.length),
      ...actorCidBytes,
      ...institutionAccountId,
      ...beneficiary,
      ...u128Le(amountFen),
      ...compactU32(remarkBytes.length),
      ...remarkBytes,
      ...proposer,
    ];
    return Uint8List.fromList([...compactU32(body.length), ...body]);
  }

  List<int> cid(String value) {
    final bytes = utf8.encode(value);
    return [...compactU32(bytes.length), ...bytes];
  }

  final service = MultisigTransferService(
    chain: TestCitizenChain(),
    transactions: TestCitizenTransactions(),
  );

  test('机构 propose_transfer 当前 SCALE payload 的短备注必须可解码', () {
    final institutionAccountId = List<int>.filled(32, 0x11);
    final beneficiary = List<int>.filled(32, 0x22);
    final decoded = service.debugDecodeProposalData(
      0,
      institutionPayload(
        institutionAccountId: institutionAccountId,
        beneficiary: beneficiary,
        amountFen: BigInt.from(10000000),
        remark: '转账测试',
        proposer: List<int>.filled(32, 0x33),
      ),
    );

    expect(decoded, isNotNull, reason: '短备注机构提案必须进入提案列表和详情页');
    expect(decoded!.actorCidNumber, 'LN001-CGOVC-000000001-2026');
    expect(decoded.institutionAccountId, institutionAccountId);
    expect(decoded.amountFen, BigInt.from(10000000)); // 100,000.00 元
    expect(decoded.remark, '转账测试');
    expect(
      decoded.beneficiary,
      Keyring().encodeAddress(Uint8List.fromList(beneficiary), 2027),
    );
  });

  test('机构 propose_transfer 当前 SCALE payload 的空备注必须可解码', () {
    final decoded = service.debugDecodeProposalData(
      1,
      institutionPayload(
        institutionAccountId: List<int>.filled(32, 0x11),
        beneficiary: List<int>.filled(32, 0x22),
        amountFen: BigInt.zero,
        remark: '',
        proposer: List<int>.filled(32, 0x33),
      ),
    );

    expect(decoded, isNotNull);
    expect(decoded!.actorCidNumber, 'LN001-CGOVC-000000001-2026');
    expect(decoded.remark, '');
  });

  test('截断 payload(不足下限)返回 null', () {
    final full = institutionPayload(
      institutionAccountId: List<int>.filled(32, 0x11),
      beneficiary: List<int>.filled(32, 0x22),
      amountFen: BigInt.zero,
      remark: '',
      proposer: List<int>.filled(32, 0x33),
    );
    final raw = Uint8List.fromList(full.sublist(0, full.length - 1));

    expect(service.debugDecodeProposalData(2, raw), isNull);
  });

  test('MODULE_TAG 不符返回 null', () {
    final body = <int>[
      ...'dq-xxxx'.codeUnits,
      ...List<int>.filled(114, 0x11),
    ];
    final raw = Uint8List.fromList([...compactU32(body.length), ...body]);

    expect(service.debugDecodeProposalData(3, raw), isNull);
  });

  test('SafetyFundAction 严格解码 actor CID、机构账户和 proposer', () async {
    const actorCidNumber = 'LN001-NRC0G-944805165-2026';
    final institutionAccountId = List<int>.filled(32, 0x41);
    final proposer = List<int>.filled(32, 0x43);
    final remark = utf8.encode('安全基金');
    final raw = Uint8List.fromList([
      ...cid(actorCidNumber),
      ...institutionAccountId,
      ...List<int>.filled(32, 0x42),
      ...u128Le(BigInt.from(500)),
      ...compactU32(remark.length),
      ...remark,
      ...proposer,
    ]);
    final decoded = await MultisigTransferService(chain: _RawStorageChain(raw), transactions: TestCitizenTransactions()).fetchSafetyFundAction(4);

    expect(decoded, isNotNull);
    expect(decoded!.actorCidNumber, actorCidNumber);
    expect(decoded.institutionAccountId, institutionAccountId);
    expect(decoded.amountFen, BigInt.from(500));
    expect(
      decoded.proposer,
      Keyring().encodeAddress(Uint8List.fromList(proposer), 2027),
    );

    final trailing = Uint8List.fromList([...raw, 0]);
    expect(
      await MultisigTransferService(chain: _RawStorageChain(trailing), transactions: TestCitizenTransactions()).fetchSafetyFundAction(4),
      isNull,
    );
  });

  test('SweepAction 完整消费 proposer，尾随字节必须拒绝', () async {
    const actorCidNumber = 'ZS001-PRB08-233384677-2026';
    final institutionAccountId = List<int>.filled(32, 0x51);
    final proposer = List<int>.filled(32, 0x52);
    final raw = Uint8List.fromList([
      ...cid(actorCidNumber),
      ...institutionAccountId,
      ...u128Le(BigInt.from(800)),
      ...proposer,
    ]);
    final decoded = await MultisigTransferService(chain: _RawStorageChain(raw), transactions: TestCitizenTransactions()).fetchSweepAction(5);

    expect(decoded, isNotNull);
    expect(decoded!.actorCidNumber, actorCidNumber);
    expect(decoded.institutionAccountId, institutionAccountId);
    expect(decoded.amountFen, BigInt.from(800));
    expect(
      decoded.proposer,
      Keyring().encodeAddress(Uint8List.fromList(proposer), 2027),
    );

    final trailing = Uint8List.fromList([...raw, 0]);
    expect(
      await MultisigTransferService(chain: _RawStorageChain(trailing), transactions: TestCitizenTransactions()).fetchSweepAction(5),
      isNull,
    );
  });

  test('VotingEngine Proposal 元数据严格按 CID 主体完整解码', () {
    const actorCidNumber = 'LN001-CGOVC-000000001-2026';
    const subjectCidNumber = 'LN001-CGOVC-000000002-2026';
    final executionAccountId = List<int>.filled(32, 0x61);
    final raw = Uint8List.fromList([
      0, 0, 0, // kind / stage / status
      1, ...utf8.encode('CGOV'), // internal_code Some
      1, ...cid(actorCidNumber), // actor CID Some
      1, ...executionAccountId, // execution account Some
      4, ...cid(subjectCidNumber), // subject CID Vec len=1
      ...u32Le(10),
      ...u32Le(20),
    ]);
    final decoded = service.debugDecodeProposalMeta(6, raw);
    expect(decoded, isNotNull);
    expect(decoded!.actorCidNumber, actorCidNumber);
    expect(decoded.executionAccountId, executionAccountId);
    expect(decoded.subjectCidNumbers, [subjectCidNumber]);

    expect(
      service.debugDecodeProposalMeta(6, Uint8List.fromList([...raw, 0])),
      isNull,
    );
    final invalidOption = Uint8List.fromList(raw)..[3] = 2;
    expect(service.debugDecodeProposalMeta(6, invalidOption), isNull);
  });

  test('ProposalSubject 唯一编码严格区分机构 CID 与个人多签账户', () {
    const institutionCidNumber = 'LN001-CGOVC-000000001-2026';
    final institution = InstitutionInfo(
      cidFullName: '测试机构',
      cidShortName: '测试机构',
      cidFullNameEn: 'Test Institution',
      cidShortNameEn: 'TI',
      cidNumber: institutionCidNumber,
      orgType: OrgType.institution,
      accounts: InstitutionAccounts(
        mainAccountId: '0x${'11' * 32}',
        feeAccountId: '0x${'22' * 32}',
      ),
    );
    final institutionKey = ProposalQueryService.proposalSubjectKey(institution);
    expect(institutionKey.first, 0);
    expect(institutionKey[1], utf8.encode(institutionCidNumber).length << 2);
    expect(utf8.decode(institutionKey.sublist(2)), institutionCidNumber);

    final personalAccount = '0x${'ab' * 32}';
    final personal = InstitutionInfo(
      cidFullName: '个人多签',
      cidShortName: '个人多签',
      cidFullNameEn: 'Personal Multisig',
      cidShortNameEn: 'PMUL',
      cidNumber: 'personal-account:$personalAccount',
      orgType: OrgType.personalMultisig,
      personalAccountId: personalAccount,
    );
    final personalKey = ProposalQueryService.proposalSubjectKey(personal);
    expect(personalKey, Uint8List.fromList([1, ...List.filled(32, 0xab)]));
  });

  test('投票引擎主体索引和管理员快照必须完整消费 SCALE 字节', () {
    final adminsRaw = Uint8List.fromList([
      8, // Compact(2)
      ...List.filled(32, 0x11),
      ...List.filled(32, 0x22),
    ]);
    expect(
      ProposalQueryService.decodeAdminSnapshot(adminsRaw),
      ['0x${'11' * 32}', '0x${'22' * 32}'],
    );
    expect(
      ProposalQueryService.decodeAdminSnapshot(
        Uint8List.fromList([...adminsRaw, 0]),
      ),
      isNull,
    );

    final activeRaw = Uint8List.fromList([
      8, // Compact(2)
      ...u64Le(7),
      ...u64Le(9),
    ]);
    expect(ProposalQueryService.decodeActiveProposalIds(activeRaw), [7, 9]);
    expect(
      ProposalQueryService.decodeActiveProposalIds(
        Uint8List.fromList([...activeRaw, 0]),
      ),
      isNull,
    );
  });

  test('机构按完整岗位主体读取选民快照，个人多签读取管理员快照', () async {
    final raw = Uint8List.fromList([
      4, // Compact(1)
      ...List.filled(32, 0x33),
    ]);
    final rpc = _RawStorageChain(raw);
    final query = ProposalQueryService(chain: rpc);
    final institution = InstitutionInfo(
      cidFullName: '测试机构',
      cidShortName: '测试机构',
      cidFullNameEn: 'Test Institution',
      cidShortNameEn: 'TI',
      cidNumber: 'LN001-CGOVC-000000001-2026',
      orgType: OrgType.institution,
      accounts: InstitutionAccounts(
        mainAccountId: '0x${'11' * 32}',
        feeAccountId: '0x${'22' * 32}',
      ),
    );
    final personalAccount = '0x${'ab' * 32}';
    final personal = InstitutionInfo(
      cidFullName: '个人多签',
      cidShortName: '个人多签',
      cidFullNameEn: 'Personal Multisig',
      cidShortNameEn: 'PMUL',
      cidNumber: 'personal-account:$personalAccount',
      orgType: OrgType.personalMultisig,
      personalAccountId: personalAccount,
    );

    expect(
      await query.fetchRoleVoterSnapshot(
        7,
        institution.cidNumber,
        'COMMITTEE_MEMBER',
      ),
      ['0x${'33' * 32}'],
    );
    expect(
      await query.fetchEligibleVoterSnapshot(7, personal),
      ['0x${'33' * 32}'],
    );
    expect(rpc.storageKeys, hasLength(2));
    expect(rpc.storageKeys[0], isNot(rpc.storageKeys[1]));
  });

  test('公民提案流按默认机构码和订阅机构 CID 合并过滤', () {
    Uint8List accountIdBytes(int seed) => Uint8List.fromList(
          List<int>.filled(32, seed),
        );

    ProposalWithDetail proposal(
      int id, {
      required String code,
      required Uint8List institution,
      List<String> subjectCidNumbers = const [],
    }) {
      return ProposalWithDetail(
        meta: ProposalMeta(
          proposalId: id,
          kind: 0,
          stage: 0,
          status: 0,
          internalCode: code,
          actorCidNumber:
              subjectCidNumbers.isEmpty ? null : subjectCidNumbers.first,
          executionAccountId: institution,
          subjectCidNumbers: subjectCidNumbers,
        ),
      );
    }

    const subscribedCid = 'LN001-CGOVC-000000001-2026';
    const ignoredSameCodeCid = 'LN001-CGOVC-000000002-2026';
    final ids = service.filterCitizenProposalFeedIds(
      [
        proposal(1, code: 'NRC', institution: accountIdBytes(0x11)),
        proposal(2, code: 'PRC', institution: accountIdBytes(0x22)),
        proposal(3, code: 'PRB', institution: accountIdBytes(0x33)),
        proposal(
          4,
          code: 'CGOV',
          institution: accountIdBytes(0x44),
          subjectCidNumbers: const [subscribedCid],
        ),
        proposal(
          5,
          code: 'CGOV',
          institution: accountIdBytes(0x45),
          subjectCidNumbers: const [ignoredSameCodeCid],
        ),
        proposal(6, code: 'PRS', institution: accountIdBytes(0x66)),
      ],
      defaultCodes: const {
        'NRC',
        'NLG',
        'NSN',
        'NRP',
        'NED',
        'NJD',
        'NSP',
        'PRS',
      },
      subscribedInstitutionCidNumbers: const {subscribedCid},
    );

    expect(ids, [6, 4, 1]);
  });
}
