import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_post_deletion_coordinator.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';
import 'package:citizenapp/isar/social_isar.dart';

import '../support/isar_test_env.dart';

const _cidNumber = 'CN001-CTZN-000000001-2026';
const _otherCidNumber = 'CN002-CTZN-000000002-2026';
const _accountId =
    '0xd43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d';

SquareSession _session() => const SquareSession(
  sessionToken: 'session',
  cidNumber: _cidNumber,
  bindingRevision: 1,
  accountId: _accountId,
  expiresAt: 4102444800000,
);

class _FakeRemoteDeletion implements SquarePostDeletionService {
  _FakeRemoteDeletion({this.error});

  final SquareApiException? error;
  int calls = 0;

  @override
  Future<void> deletePost({
    required SquareSession session,
    required String postId,
  }) async {
    calls += 1;
    if (error != null) throw error!;
  }
}

class _FakeLocalStore implements SquareLocalPostDeletionStore {
  bool fail = false;
  int deleteCalls = 0;
  String? deletedCidNumber;
  String? deletedPostId;

  @override
  Future<bool> delete({
    required String cidNumber,
    required String postId,
  }) async {
    deleteCalls += 1;
    if (fail) throw StateError('本地事务失败');
    deletedCidNumber = cidNumber;
    deletedPostId = postId;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();
  test('远端成功本地失败，重启后只重试本地删除', () async {
    final remote = _FakeRemoteDeletion();
    final local = _FakeLocalStore()..fail = true;
    await expectLater(
      SquarePostDeletionCoordinator(
        remoteDeletion: remote,
        localStore: local,
      ).delete(
        session: _session(),
        cidNumber: _cidNumber,
        postId: 'pending-delete',
      ),
      throwsStateError,
    );
    expect(
      (await const SquarePostStore().readDeletion(
        _cidNumber,
        'pending-delete',
      ))!.operationState,
      'confirmed',
    );
    await (await SocialIsar.instance.db()).close();
    local.fail = false;
    await SquarePostDeletionCoordinator(
      remoteDeletion: remote,
      localStore: local,
    ).delete(
      session: _session(),
      cidNumber: _cidNumber,
      postId: 'pending-delete',
    );
    expect(remote.calls, 1);
    expect(local.deleteCalls, 2);
  });
  test('Worker 删除成功后删除同 CID 本地副本', () async {
    final remote = _FakeRemoteDeletion();
    final local = _FakeLocalStore();
    final coordinator = SquarePostDeletionCoordinator(
      remoteDeletion: remote,
      localStore: local,
    );

    await coordinator.delete(
      session: _session(),
      cidNumber: _cidNumber,
      postId: 'post-1',
    );

    expect(remote.calls, 1);
    expect(local.deleteCalls, 1);
    expect(local.deletedCidNumber, _cidNumber);
    expect(local.deletedPostId, 'post-1');
  });

  test('Worker 精确返回 404/post_not_found 时允许清理本人本地残留', () async {
    final remote = _FakeRemoteDeletion(
      error: const SquareApiException(
        '帖子不存在',
        statusCode: 404,
        errorCode: 'post_not_found',
      ),
    );
    final local = _FakeLocalStore();
    final coordinator = SquarePostDeletionCoordinator(
      remoteDeletion: remote,
      localStore: local,
    );

    await coordinator.delete(
      session: _session(),
      cidNumber: _cidNumber,
      postId: 'post-2',
    );

    expect(local.deleteCalls, 1);
  });

  test('权限、会话或网络错误必须保留本地副本', () async {
    final remote = _FakeRemoteDeletion(
      error: const SquareApiException(
        '无权删除',
        statusCode: 403,
        errorCode: 'post_owner_mismatch',
      ),
    );
    final local = _FakeLocalStore();
    final coordinator = SquarePostDeletionCoordinator(
      remoteDeletion: remote,
      localStore: local,
    );

    await expectLater(
      coordinator.delete(
        session: _session(),
        cidNumber: _cidNumber,
        postId: 'post-3',
      ),
      throwsA(isA<SquareApiException>()),
    );

    expect(local.deleteCalls, 0);
  });

  test('请求 CID 与会话 CID 不同则在访问 Worker 前拒绝', () async {
    final remote = _FakeRemoteDeletion();
    final local = _FakeLocalStore();
    final coordinator = SquarePostDeletionCoordinator(
      remoteDeletion: remote,
      localStore: local,
    );

    await expectLater(
      coordinator.delete(
        session: _session(),
        cidNumber: _otherCidNumber,
        postId: 'post-4',
      ),
      throwsA(
        isA<SquareApiException>().having(
          (error) => error.errorCode,
          'errorCode',
          'post_owner_mismatch',
        ),
      ),
    );

    expect(remote.calls, 0);
    expect(local.deleteCalls, 0);
  });
}
