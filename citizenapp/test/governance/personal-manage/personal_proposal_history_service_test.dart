// 个人多签提案历史服务单元测试。
//
// 仅覆盖 Isar 持久层路径(`recordOrUpdate` 写 / `fetchAll` 读 / 状态字段映射 /
// snapshot JSON 序列化反序列化)。链上拉取依赖 CitizenChain，测试走不可用分支，
// 等价于"链上失败 → 仅返回 Isar"路径。

import 'dart:typed_data';
import 'dart:convert';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';
import 'package:citizenapp/transaction/personal-manage/personal_proposal_history_service.dart';
import '../../support/isar_test_env.dart';
import '../../support/fake_citizen_sdk.dart';

/// 离线 CitizenChain：本单测只验证 Isar 持久层，注入它切断真链依赖。
/// 可达探针为 false(等价「链不可达 → 仅返回本机 Isar」)。避免本机是否连着真链
/// 造成 flaky;配合服务端「链不可达不删幽灵」的容错回退,写入的历史必被完整读回。
class _OfflineChain extends TestCitizenChain {
  @override
  Future<CitizenChainSyncStatus> getSyncStatus() async {
    final finalized = CitizenBlockRef(
      hash: '0x${'00' * 32}',
      number: BigInt.zero,
      finality: CitizenBlockFinality.finalized,
    );
    return CitizenChainSyncStatus(
      peerCount: BigInt.zero,
      isSyncing: false,
      isUsable: false,
      best: finalized,
      finalized: finalized,
    );
  }
}

PersonalProposalHistoryService _service() {
  final chain = _OfflineChain();
  return PersonalProposalHistoryService(
    chain: chain,
    proposalService: ProposalQueryService(chain: chain),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();

  const personalAccount = 'aabbccddeeff00112233445566778899'
      '00112233445566778899aabbccddeeff';

  List<int> compactU32(int value) {
    if (value < 64) return [value << 2];
    final encoded = (value << 2) | 1;
    return [encoded & 0xff, encoded >> 8];
  }

  test('ProposalData 只识别当前 per-mgmt / multisig 标签并拒绝尾随字节', () {
    final service = _service();
    Uint8List wrap(List<int> body) =>
        Uint8List.fromList([...compactU32(body.length), ...body]);

    expect(
      service.debugDecodeActionFromProposalData(
        wrap([...utf8.encode('per-mgmt'), 0, ...List.filled(32, 1)]),
      ),
      PersonalProposalAction.create,
    );
    expect(
      service.debugDecodeActionFromProposalData(
        wrap([...utf8.encode('per-mgmt'), 1, ...List.filled(32, 1)]),
      ),
      PersonalProposalAction.close,
    );
    expect(
      service.debugDecodeActionFromProposalData(
        wrap([
          ...utf8.encode('multisig'),
          0, // actor_cid_number: None（个人多签）
          ...List.filled(32, 1), // funding_account_id
          ...List.filled(32, 2), // beneficiary
          ...List.filled(16, 0), // amount
          0, // empty remark
          ...List.filled(32, 3), // proposer
        ]),
      ),
      PersonalProposalAction.transfer,
    );
    expect(
      service.debugDecodeActionFromProposalData(
        wrap([...utf8.encode('multisig-transfer'), 0]),
      ),
      isNull,
    );

    final current = wrap([...utf8.encode('multisig'), 0]);
    expect(
      service.debugDecodeActionFromProposalData(
        Uint8List.fromList([...current, 0]),
      ),
      isNull,
    );
  });

  test('recordOrUpdate inserts new entity then readAllFromIsar 返回单条', () async {
    final service = _service();
    await service.recordOrUpdate(
      personalAccountId: personalAccount,
      proposalId: 42,
      action: PersonalProposalAction.create,
      status: PersonalProposalStatus.voting,
      yesVotes: 1,
      noVotes: 0,
      snapshot: {'name': 'TestPersonal', 'amount_fen': '1000'},
    );

    final list = await service.fetchAll(personalAccount);
    expect(list.length, 1);
    expect(list[0].proposalId, 42);
    expect(list[0].action, PersonalProposalAction.create);
    expect(list[0].status, PersonalProposalStatus.voting);
    expect(list[0].yesVotes, 1);
    expect(list[0].noVotes, 0);
    expect(list[0].isActive, isTrue);
    expect(list[0].finalStatusAtMillis, isNull);
    expect(list[0].snapshot?['name'], 'TestPersonal');
    expect(list[0].snapshot?['amount_fen'], '1000');
  });

  test(
      'recordOrUpdate 同 proposalId upsert,createdAt 保留首次值,'
      'snapshot 沿用旧值若新调用未传', () async {
    final service = _service();
    await service.recordOrUpdate(
      personalAccountId: personalAccount,
      proposalId: 7,
      action: PersonalProposalAction.create,
      status: PersonalProposalStatus.voting,
      yesVotes: 0,
      noVotes: 0,
      snapshot: {'name': 'X'},
    );
    final firstList = await service.fetchAll(personalAccount);
    final firstCreatedAt = firstList[0].createdAtMillis;

    await Future<void>.delayed(const Duration(milliseconds: 5));

    // 二次写入只更新投票计数和状态,不传 snapshot
    await service.recordOrUpdate(
      personalAccountId: personalAccount,
      proposalId: 7,
      action: PersonalProposalAction.create,
      status: PersonalProposalStatus.executed,
      yesVotes: 3,
      noVotes: 0,
    );
    final list = await service.fetchAll(personalAccount);
    expect(list.length, 1);
    expect(list[0].status, PersonalProposalStatus.executed);
    expect(list[0].yesVotes, 3);
    expect(list[0].finalStatusAtMillis, isNotNull);
    expect(list[0].createdAtMillis, firstCreatedAt,
        reason: '二次 upsert 必须保留首次 createdAt');
    expect(list[0].snapshot?['name'], 'X', reason: 'snapshot 旧值应保留');
  });

  test('voting → executed 转换会写入 finalStatusAtMillis', () async {
    final service = _service();
    await service.recordOrUpdate(
      personalAccountId: personalAccount,
      proposalId: 1,
      action: PersonalProposalAction.create,
      status: PersonalProposalStatus.voting,
      yesVotes: 0,
      noVotes: 0,
    );
    var list = await service.fetchAll(personalAccount);
    expect(list[0].finalStatusAtMillis, isNull);
    expect(list[0].isFinal, isFalse);

    await service.recordOrUpdate(
      personalAccountId: personalAccount,
      proposalId: 1,
      action: PersonalProposalAction.create,
      status: PersonalProposalStatus.rejected,
      yesVotes: 0,
      noVotes: 3,
    );
    list = await service.fetchAll(personalAccount);
    expect(list[0].finalStatusAtMillis, isNotNull);
    expect(list[0].isFinal, isTrue);
  });

  test('多个 proposal 按 createdAt desc 排序', () async {
    final service = _service();
    await service.recordOrUpdate(
      personalAccountId: personalAccount,
      proposalId: 100,
      action: PersonalProposalAction.create,
      status: PersonalProposalStatus.voting,
      yesVotes: 0,
      noVotes: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.recordOrUpdate(
      personalAccountId: personalAccount,
      proposalId: 101,
      action: PersonalProposalAction.transfer,
      status: PersonalProposalStatus.voting,
      yesVotes: 1,
      noVotes: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.recordOrUpdate(
      personalAccountId: personalAccount,
      proposalId: 102,
      action: PersonalProposalAction.close,
      status: PersonalProposalStatus.executed,
      yesVotes: 3,
      noVotes: 0,
    );

    final list = await service.fetchAll(personalAccount);
    expect(list.map((v) => v.proposalId).toList(), [102, 101, 100]);
  });

  test('mapChainStatus 链上 u8 → 字符串映射穷尽', () {
    expect(mapChainStatus(0), PersonalProposalStatus.voting);
    expect(mapChainStatus(1), PersonalProposalStatus.passed);
    expect(mapChainStatus(2), PersonalProposalStatus.rejected);
    expect(mapChainStatus(3), PersonalProposalStatus.executed);
    expect(mapChainStatus(4), PersonalProposalStatus.executionFailed);
    expect(mapChainStatus(null), PersonalProposalStatus.voting);
    expect(mapChainStatus(99), PersonalProposalStatus.voting);
  });
}
