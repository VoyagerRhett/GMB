import 'dart:typed_data';

import 'package:isar_community/isar.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/identity_badge_snapshot_store.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/isar_test_env.dart';

void main() {
  const cidA = 'GD-CTZN1-000000001-2026';
  const cidB = 'GD-CTZN1-000000002-2026';

  useIsolatedIsar();

  test('完整身份持久化、未注册和换绑结果按账户隔离', () async {
    final a =
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        b = '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    CitizenIdentityChainSnapshot snapshot(int byte, int version) =>
        CitizenIdentityChainSnapshot(
          cidNumber: cidA,
          accountId: Uint8List.fromList(List.filled(32, byte)),
          bindingRevision: version,
          votingIdentity: null,
        );
    final store = IdentityBadgeSnapshotStore();
    await store.writeVerified(
      accountId: a,
      identity: snapshot(0xaa, 1),
      isCurrent: () => true,
    );
    // 真正关闭后重开数据库，不能只用新服务实例证明持久保存。
    await (await UserIsar.instance.db()).close();
    final reopened = IdentityBadgeSnapshotStore();
    expect((await reopened.readForAccountId(a))?.identity?.cidNumber, cidA);
    await store.writeVerified(
      accountId: b,
      identity: null,
      isCurrent: () => true,
    );
    expect((await reopened.readForAccountId(b))?.verified, isTrue);
    expect((await reopened.readForAccountId(b))?.identity, isNull);
    await store.writeVerified(
      accountId: b,
      identity: snapshot(0xbb, 2),
      isCurrent: () => true,
    );
    expect((await reopened.readForAccountId(a))?.identity, isNull);
    expect((await reopened.readForAccountId(b))?.identity?.bindingRevision, 2);
    expect((await reopened.read(cidA))?.accountId, b);
    await store.writeVerified(
      accountId: b,
      identity: null,
      isCurrent: () => true,
    );
    expect(await reopened.read(cidA), isNull);
    expect((await reopened.readForAccountId(b))?.verified, isTrue);
  });

  test('过期上下文和损坏完整快照不能覆盖成功数据或伪装未注册', () async {
    final account =
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final store = IdentityBadgeSnapshotStore();
    await store.writeVerified(
      accountId: account,
      identity: CitizenIdentityChainSnapshot(
        cidNumber: cidA,
        accountId: Uint8List.fromList(List.filled(32, 0xaa)),
        bindingRevision: 1,
        votingIdentity: null,
      ),
      isCurrent: () => true,
    );
    await expectLater(
      store.writeVerified(
        accountId: account,
        identity: null,
        isCurrent: () => false,
      ),
      throwsStateError,
    );
    expect((await store.readForAccountId(account))?.cidNumber, cidA);
    await UserIsar.instance.writeTxn((isar) async {
      final row = await isar.userIdentityBadgeSnapshotEntitys
          .filter()
          .accountIdEqualTo(account)
          .findFirst();
      row!.identitySnapshotJson = '{broken';
      await isar.userIdentityBadgeSnapshotEntitys.put(row);
    });
    expect(await store.readForAccountId(account), isNull);
  });

  test('身份徽章快照按永久 CID 隔离', () async {
    final store = IdentityBadgeSnapshotStore(
      nowProvider: () => DateTime.fromMillisecondsSinceEpoch(1234),
    );

    await store.write(cidNumber: cidA, identityLevel: 'voting');
    await store.write(cidNumber: cidB, identityLevel: 'candidate');

    final citizenA = await store.read(cidA);
    final citizenB = await store.read(cidB);
    expect(citizenA?.identityLevel, 'voting');
    expect(citizenA?.updatedAtMillis, 1234);
    expect(citizenB?.identityLevel, 'candidate');
  });

  test('损坏快照按无展示处理且读取路径不删除事实', () async {
    final store = IdentityBadgeSnapshotStore();
    await UserIsar.instance.writeTxn((isar) async {
      await isar.userIdentityBadgeSnapshotEntitys.put(
        UserIdentityBadgeSnapshotEntity()
          ..cidNumber = cidA
          ..identityLevel = 'broken'
          ..updatedAtMillis = -1,
      );
    });
    expect(await store.read(cidA), isNull);
    final retained = await UserIsar.instance.read(
      (isar) async => isar.userIdentityBadgeSnapshotEntitys
          .filter()
          .cidNumberEqualTo(cidA)
          .findFirst(),
    );
    expect(retained, isNotNull);
    expect(retained?.identityLevel, 'broken');
  });

  test('不接受非正式身份档', () async {
    final store = IdentityBadgeSnapshotStore();

    await expectLater(
      store.write(cidNumber: cidA, identityLevel: 'admin'),
      throwsArgumentError,
    );
    expect(await store.read(cidA), isNull);
  });
}
