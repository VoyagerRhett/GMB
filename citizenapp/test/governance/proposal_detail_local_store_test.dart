import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_detail_local_store.dart';

import '../support/isar_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();

  test('提案详情快照可持久化管理员投票和业务详情', () async {
    final snapshot = ProposalDetailSnapshot(
      proposalId: 77,
      typeKey: 'transfer',
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      status: 0,
      yesCount: 2,
      noCount: 1,
      threshold: 6,
      admins: const ['aa', 'bb'],
      adminVotes: const {'aa': true, 'bb': null},
      pendingPublicKeys: const ['bb'],
      detail: const {'kind': 'transfer', 'amount_fen': '12300'},
    );

    await ProposalDetailLocalStore.instance.put(snapshot);

    final loaded = await ProposalDetailLocalStore.instance.read('transfer', 77);

    expect(loaded, isNotNull);
    expect(loaded!.proposalId, 77);
    expect(loaded.adminVotes['aa'], isTrue);
    expect(loaded.adminVotes['bb'], isNull);
    expect(loaded.detail['amount_fen'], '12300');
    expect(loaded.isFresh(ProposalDetailLocalStore.activeTtl), isTrue);
  });
}
