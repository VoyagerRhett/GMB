import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/8964/services/square_api_client.dart'
    show SquareMembershipState, SquareSession;
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/my/creator/creator_api.dart';
import 'package:citizenapp/my/creator/creator_service.dart';
import 'package:citizenapp/my/creator/models/creator_overview.dart';
import 'package:citizenapp/my/creator/models/creator_plan.dart';
import 'package:citizenapp/my/membership/subscription_service.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/membership/subscription_chain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/isar_test_env.dart';
import '../../support/fake_citizen_sdk.dart';

void main() {
  useIsolatedIsar();
  const session = SquareSession(
    sessionToken: 't',
    cidNumber: "CN220-CTZN2-198805200-2026",
    bindingRevision: 1,
    accountId:
        '0x7777777777777777777777777777777777777777777777777777777777777777',
    expiresAt: 9999999999999,
  );

  const tier = CreatorTier(
    tierId: 't1',
    tierName: '铁杆粉丝',
    pricesFen: {BillingPeriod.monthly: 990},
  );

  test('FakeCreatorApi 只接收已 finalized 交易哈希，不再触发第二次业务签名', () async {
    final api = FakeCreatorApi();

    final plan = await api.saveMyPlan(
      session: session,
      txHash: '0x${List.filled(64, 'a').join()}',
      blockHashHex: '0x${List.filled(64, 'b').join()}',
    );

    expect(api.lastSaveTxHash, '0x${List.filled(64, 'a').join()}');
    expect(plan.creatorCidNumber, session.cidNumber);
    expect(plan.tiers, isEmpty);
    expect(await api.fetchMyPlan(session), isNotNull);
  });

  test('CreatorApiHttp 保存只调用一次 plan 接口且携带链上交易哈希', () async {
    final paths = <String>[];
    var deviceSignCount = 0;
    final txHash = '0x${List.filled(64, 'b').join()}';
    final blockHash = '0x${List.filled(64, 'c').join()}';
    final api = CreatorApiHttp(
      baseUrl: 'https://creator.test',
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['tx_hash'], txHash);
        expect(body['block_hash'], blockHash);
        expect(body, isNot(contains('signed_extrinsic_hex')));
        expect(body, isNot(contains('tiers')));
        expect(body, isNot(contains('challenge_id')));
        expect(body, isNot(contains('signature')));
        expect(request.headers['authorization'], 'Bearer t');
        expect(request.headers, isNot(contains('x-device-signature')));
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'plan': {
                'creator_cid_number': 'CN220-CTZN2-198805200-2026',
                'tiers': [tier.toJson()],
                'updated_at': 1,
              },
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final signedSession = SquareSession(
      sessionToken: 't',
      cidNumber: "CN220-CTZN2-198805200-2026",
      bindingRevision: 1,
      accountId:
          '0x7777777777777777777777777777777777777777777777777777777777777777',
      expiresAt: 9999999999999,
      signRequest: (_) async {
        deviceSignCount++;
        return 'device-signature';
      },
    );

    await api.saveMyPlan(
      session: signedSession,
      txHash: txHash,
      blockHashHex: blockHash,
    );

    expect(paths, ['/square/creator/plan']);
    expect(deviceSignCount, 0, reason: 'finalized 后的 Cloudflare 投影不得产生第二次签名');
  });

  test('创作者订阅投影确认只传 finalized 交易定位', () async {
    final api = CreatorApiHttp(
      baseUrl: 'https://creator.test',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, unorderedEquals(['tx_hash', 'block_hash']));
        expect(body, isNot(contains('creator_cid_number')));
        expect(body, isNot(contains('action')));
        expect(body, isNot(contains('tier_id')));
        return http.Response(
          jsonEncode({'ok': true}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await api.confirmCreatorSubscription(
      session: session,
      txHash: '0x${List.filled(64, 'a').join()}',
      blockHashHex: '0x${List.filled(64, 'b').join()}',
    );
  });

  test('FakeCreatorApi 概览默认按档位数', () async {
    final api = FakeCreatorApi(
      initialPlan: const CreatorPlan(
        creatorCidNumber: 'CN220-CTZN2-198805200-2026',
        tiers: [tier],
        updatedAt: 0,
      ),
    );
    final overview = await api.fetchOverview(session);
    expect(overview.tierCount, 1);
    expect(overview.subscriberCount, 0);
  });

  test('创作者展示快照按 CID 持久化并完整往返', () async {
    final service = CreatorService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      api: FakeCreatorApi(),
      subscriptionChain: _FakeSubscriptionChain(),
      wallet: _FakeWallet(),
      identityResolver: _FakeIdentityCache(),
      sessionProvider: _FakeSessionProvider(),
      subscriptionService: _ActiveMembershipService(),
    );
    final display = CreatorPageData.active(
      plan: const CreatorPlan(
        creatorCidNumber: _creatorCidNumber,
        tiers: [tier],
        updatedAt: 123,
      ),
      overview: const CreatorOverview(
        subscriberCount: 7,
        monthIncomeFen: 8800,
        tierCount: 1,
      ),
    );
    await service.rememberDisplayData(
      cidNumber: _creatorCidNumber,
      data: display,
      membershipFetchedAtMs: 1000,
      creatorFetchedAtMs: 2000,
    );

    final snapshot = await service.readDisplaySnapshot(_creatorCidNumber);
    expect(snapshot, isNotNull);
    expect(snapshot!.cidNumber, _creatorCidNumber);
    expect(snapshot.data.gated, isFalse);
    expect(snapshot.data.plan!.tiers.single.tierName, '铁杆粉丝');
    expect(snapshot.data.overview!.subscriberCount, 7);
    expect(snapshot.membershipFetchedAtMs, 1000);
    expect(snapshot.creatorFetchedAtMs, 2000);
  });

  test('链上 finalized 后 Cloudflare 失败只重试投影确认，不产生第二次链上签名', () async {
    final api = _FlakyCreatorApi()..failSave = true;
    final rpc = _FakeSubscriptionChain();
    final sessionProvider = _FakeSessionProvider();
    final service = CreatorService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      api: api,
      subscriptionChain: rpc,
      wallet: _FakeWallet(),
      identityResolver: _FakeIdentityCache(),
      sessionProvider: sessionProvider,
      subscriptionService: _ActiveMembershipService(),
    );

    final saved = await service.saveTiers(const [tier]);
    expect(saved.tiers.single.tierName, '铁杆粉丝');
    expect(rpc.setPlansCount, 1);
    expect(rpc.signCount, 1);
    expect(api.saveCount, 1);

    // 同一 CID 已换绑到新钱包账户；待提交证明仍必须由新会话接续处理。
    sessionProvider.accountId = _reboundAccountId;
    api.failSave = false;
    await service.load();
    expect(api.saveCount, 2, reason: '再次进入页面只重试 Cloudflare 查询投影');
    expect(rpc.setPlansCount, 1, reason: '同一业务不得再次提交链上交易');
    expect(rpc.signCount, 1, reason: '同一业务不得再次账户签名');
  });

  test('创作者刷新只使用 CitizenServe 会员与档位投影', () async {
    final rpc = _FakeSubscriptionChain();
    final service = CreatorService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      api: FakeCreatorApi(),
      subscriptionChain: rpc,
      wallet: _FakeWallet(),
      identityResolver: _FakeIdentityCache(),
      sessionProvider: _FakeSessionProvider(),
      subscriptionService: _ActiveMembershipService(),
    );

    final data = await service.load(expectedCidNumber: _creatorCidNumber);

    expect(data.gated, isFalse);
    expect(rpc.lastPlansBlockHash, isNull, reason: '页面展示不得再直接读取链上创作者档位');
  });

  test('仅改档位名只提交 call_index 6，不重写价格计划', () async {
    final rpc = _FakeSubscriptionChain();
    final api = FakeCreatorApi(
      initialPlan: CreatorPlan(
        creatorCidNumber: _creatorCidNumber,
        tiers: [tier.copyWith(tierName: '核心支持者')],
        updatedAt: 1,
      ),
    );
    final service = CreatorService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      api: api,
      subscriptionChain: rpc,
      wallet: _FakeWallet(),
      identityResolver: _FakeIdentityCache(),
      sessionProvider: _FakeSessionProvider(),
      subscriptionService: _ActiveMembershipService(),
    );

    final plan = await service.updateTierName(
      currentTiers: const [tier],
      tierId: 't1',
      tierName: '核心支持者',
    );

    expect(rpc.renameCount, 1);
    expect(rpc.setPlansCount, 0);
    expect(rpc.signCount, 1);
    expect(api.lastSaveTxHash, '0x${List.filled(64, 'e').join()}');
    expect(plan.tiers.single.tierName, '核心支持者');
    expect(plan.tiers.single.priceFenOf(BillingPeriod.monthly), 990);
  });
}

const _signerSs58Address = '5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY';
const _accountId =
    '0x0000000000000000000000000000000000000000000000000000000000000000';
const _reboundAccountId =
    '0x1111111111111111111111111111111111111111111111111111111111111111';
const _creatorCidNumber = 'CN220-CTZN2-198805200-2026';

class _FakeSessionProvider implements SquareSessionProvider {
  String accountId = _accountId;

  @override
  Future<SquareSession?> ensureSession() async => SquareSession(
    sessionToken: 'creator-session',
    cidNumber: _creatorCidNumber,
    bindingRevision: 1,
    accountId: accountId,
    expiresAt: 9999999999999,
  );

  @override
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) async {
    final session = await ensureSession();
    return SquareSessionResolution(SquareSessionStatus.ready, session: session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 身份账户单源 fake：身份=账户0（与钱包/会话同账户），offline、不链读。
class _FakeIdentityCache implements FinalizedIdentityResolver {
  @override
  Future<FinalizedIdentity?> resolve() async => FinalizedIdentity(
    accountId: _accountId,
    ss58Address: _signerSs58Address,
    snapshot: CitizenIdentityChainSnapshot(
      cidNumber: _creatorCidNumber,
      accountId: Uint8List(32),
      bindingRevision: 1,
      votingIdentity: null,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWallet implements CitizenSdkWallet {
  @override
  Future<CitizenWalletState> getState() async => CitizenWalletState(
    revision: BigInt.one,
    hotProfile: null,
    accounts: [
      CitizenWalletStateAccount(
        signMode: CitizenWalletSignMode.hot,
        walletIndex: 1,
        accountIndex: 0,
        name: 'creator',
        ss58Address: _signerSs58Address,
        accountId: _accountId,
        createdAtMillis: BigInt.zero,
        isDefault: true,
      ),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ActiveMembershipService implements SubscriptionService {
  @override
  Future<SquareMembershipState> authorizeMembership(
    SquareSession session, {
    bool forceRefresh = false,
  }) async => const SquareMembershipState(
    active: true,
    paidUntil: 9999999999999,
    membershipLevel: 'freedom',
    subscriptionStatus: 'active',
    subscriptionActive: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSubscriptionChain extends SubscriptionChain {
  _FakeSubscriptionChain()
    : super(chain: TestCitizenChain(), transactions: TestCitizenTransactions());

  int setPlansCount = 0;
  int renameCount = 0;
  int signCount = 0;
  String currentTierName = '铁杆粉丝';
  String? lastPlansBlockHash;

  @override
  Future<FinalizedSubscriptionSnapshot> fetchSubscriptionSnapshot({
    required String subscriberCidNumber,
    String? creatorCidNumber,
  }) async => FinalizedSubscriptionSnapshot(
    state: ChainSubscriptionState(
      plan: const ChainSubscriptionPlan.platform('freedom'),
      startedAt: 1000,
      lastChargedAt: 1000,
      lastChargedPriceFen: BigInt.one,
      paidUntil: 3000,
      status: 'active',
      authorizedPriceFen: BigInt.one,
      suspendReason: null,
    ),
    chainNowMs: 2000,
    block: CitizenBlockRef(
      hash: '0x${List.filled(64, '0').join()}',
      number: BigInt.one,
      finality: CitizenBlockFinality.finalized,
    ),
  );

  @override
  Future<FinalizedSubscriptionTransaction> setCreatorPlans({
    required Uint8List signerPublicKey,
    required List<CreatorTierInput> tiers,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    setPlansCount++;
    signCount++;
    return (
      txHash: '0x${List.filled(64, 'c').join()}',
      usedNonce: 1,
      blockHashHex: '0x${List.filled(64, 'd').join()}',
    );
  }

  @override
  Future<FinalizedSubscriptionTransaction> updateCreatorTierName({
    required Uint8List signerPublicKey,
    required String tierId,
    required String tierName,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    renameCount++;
    signCount++;
    currentTierName = tierName;
    return (
      txHash: '0x${List.filled(64, 'e').join()}',
      usedNonce: 2,
      blockHashHex: '0x${List.filled(64, 'f').join()}',
    );
  }

  @override
  Future<List<ChainCreatorTier>> fetchCreatorPlans(
    String creatorCidNumber,
  ) async => [
    ChainCreatorTier(
      tierId: 't1',
      tierName: currentTierName,
      pricesFen: {'monthly': BigInt.from(990)},
    ),
  ];

  @override
  Future<List<ChainCreatorTier>> fetchCreatorPlansAtBlock(
    String creatorCidNumber,
    CitizenBlockRef block,
  ) {
    lastPlansBlockHash = block.hash;
    return fetchCreatorPlans(creatorCidNumber);
  }
}

class _FlakyCreatorApi extends FakeCreatorApi {
  bool failSave = false;
  int saveCount = 0;

  @override
  Future<CreatorPlan> saveMyPlan({
    required SquareSession session,
    required String txHash,
    required String blockHashHex,
  }) async {
    saveCount++;
    if (failSave) throw const CreatorApiException('temporary');
    return super.saveMyPlan(
      session: session,
      txHash: txHash,
      blockHashHex: blockHashHex,
    );
  }
}
