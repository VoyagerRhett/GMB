import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/citizen/cid/cid_generator.dart';
import 'package:citizenapp/citizen/public/data/admin_division_store.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/my/myid/identity_badge_snapshot_store.dart';
import 'package:citizenapp/my/myid/myid_service.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:citizenapp/my/myid/citizen_identity_transaction.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import '../../support/fake_citizen_sdk.dart';

/// Alice 通用 SS58(校验和有效),仅用于让 `decodeAddress` 解出 32 字节账户;
/// 护照 App 真号是 prefix=2027,这里只需一个可解码地址驱动 storage key。
const _validAddress = '5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY';
const _validAccountId =
    '0xd43593c715fdd31c61141abd04a99fd6822c8558854ccde39a5684e7a56da27d';

CitizenWalletStateAccount _testAccount({
  required String accountId,
  required String ss58Address,
  required int accountIndex,
  required String name,
}) => CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.hot,
  walletIndex: 1,
  accountIndex: accountIndex,
  accountId: accountId,
  ss58Address: ss58Address,
  name: name,
  createdAtMillis: BigInt.zero,
  isDefault: accountIndex == 0,
);

final _aliceWallet = _testAccount(
  accountId: _validAccountId,
  ss58Address: _validAddress,
  accountIndex: 0,
  name: '账户0',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MyIdService buildService({
    CitizenWalletStateAccount? wallet,
    bool noWallet = false,
    Uint8List? voting,
    Uint8List? candidate,
    bool chainThrows = false,
    bool mismatchWallet = false,
    int cidStatus = 0,
    bool hasCid = false,
    DateTime? now,
  }) {
    final walletManager = _FakeWalletManager(
      noWallet ? null : wallet ?? _aliceWallet,
    );
    final chainRpc = _FakeChain(
      voting: voting,
      candidate: candidate,
      throws: chainThrows,
      mismatchWallet: mismatchWallet,
      cidStatus: cidStatus,
      hasCid: hasCid,
    );
    return MyIdService(
      wallet: walletManager,
      signing: walletManager,
      accountSecurity: walletManager,
      currentUserContext: _InvalidationCountingIdentityCache(),
      sessionProvider: _UnusedSessionProvider(),
      chatRuntime: () => throw StateError('测试未请求 Chat runtime'),
      chain: chainRpc,
      transactions: TestCitizenTransactions(),
      identityResolver: FinalizedIdentityResolver(
        wallet: walletManager,
        chain: chainRpc,
      ),
      divisionStore: _FakeDivisionStore(),
      badgeSnapshotStore: _FakeBadgeStore(),
      nowProvider: () => now ?? DateTime.utc(2026, 6, 1),
    );
  }

  MyIdService testService({
    _FakeWalletManager? wallet,
    CitizenChain? chain,
    FinalizedIdentityResolver? identityResolver,
    CitizenIdentityTransaction? identityTransaction,
    CidAccountDataHandover? dataHandover,
    CurrentUserContext? currentUserContext,
    int Function()? cidYearProvider,
  }) {
    final actualWallet = wallet ?? _FakeWalletManager(_aliceWallet);
    final actualChain = chain ?? _FakeChain();
    return MyIdService(
      wallet: actualWallet,
      signing: actualWallet,
      accountSecurity: actualWallet,
      currentUserContext:
          currentUserContext ?? _InvalidationCountingIdentityCache(),
      identityResolver: identityResolver ?? _FakeIdentityResolver(null),
      sessionProvider: _UnusedSessionProvider(),
      chatRuntime: () => throw StateError('测试未请求 Chat runtime'),
      chain: actualChain,
      transactions: TestCitizenTransactions(),
      divisionStore: _FakeDivisionStore(),
      badgeSnapshotStore: _FakeBadgeStore(),
      identityTransaction: identityTransaction,
      dataHandover: dataHandover,
      cidYearProvider: cidYearProvider,
    );
  }

  group('注册前余额闸 fetchRegistrationAffordability', () {
    test('门槛取自链上常量,余额旁路缓存读取', () async {
      final rpc = _FakeChain()
        ..minSelfPayFen = BigInt.from(121)
        ..balanceYuan = 1.21;
      final service = testService(chain: rpc);
      final result = await service.fetchRegistrationAffordability(
        _validAccountId,
      );
      expect(result.requiredFen, BigInt.from(121));
      expect(result.balanceFen, BigInt.from(121));
    });

    test('链读失败必须上抛,绝不静默当成余额充足或不足', () async {
      final rpc = _FakeChain()..balanceThrows = true;
      final service = testService(chain: rpc);
      await expectLater(
        service.fetchRegistrationAffordability(_validAccountId),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('无默认账户时为访客并提示创建钱包', () async {
    final state = await buildService(noWallet: true).getState();
    expect(state.tier, MyIdTier.visitor);
    expect(state.votingAccountId, isNull);
    expect(state.errorMessage, '请先创建钱包');
  });

  test('MyId 身份只读不构造 ChatSdk', () async {
    final liveChatRuntimeCount = ChatRuntimeCore.debugLiveInstanceCount;
    final service = buildService(noWallet: true);
    await service.getState();
    expect(
      ChatRuntimeCore.debugLiveInstanceCount,
      lessThanOrEqualTo(liveChatRuntimeCount),
      reason: 'Wallet/MyId 普通读取不得惰性之外构造 ChatSdk',
    );
  });

  test('默认账户链上无投票身份时为访客轻节点', () async {
    final state = await buildService(voting: null).getState();
    expect(state.tier, MyIdTier.visitor);
    expect(state.votingAccountId, isNull);
    expect(state.status, isNull);
    expect(state.isAnonymousRegistered, isFalse);
    expect(state.cidNumber, isNull);
  });

  test('有 CID、绑定闭环但无投票身份时为匿名已注册(访客卡显 CID)', () async {
    final state = await buildService(voting: null, hasCid: true).getState();
    // 仍是访客档(不新增卡/色),但已占匿名 CID → isAnonymousRegistered。
    expect(state.tier, MyIdTier.visitor);
    expect(state.isAnonymousRegistered, isTrue);
    expect(state.cidNumber, 'GD-CTZN1-8F3A2B');
    expect(state.votingAccountId, _validAccountId);
    expect(state.status, isNull);
  });

  test('有投票身份、无候选身份时为投票公民并解出全部字段', () async {
    final state = await buildService(
      voting: _encodeVoting(
        from: 20260101,
        until: 20310101,
        status: 0,
        province: 'GD',
        city: '0755',
        town: '001',
      ),
    ).getState();

    expect(state.tier, MyIdTier.voting);
    expect(state.status, MyIdStatus.normal);
    expect(state.votingAccountId, _validAccountId);
    expect(state.cidNumber, 'GD-CTZN1-8F3A2B');
    expect(state.passportValidFrom, '2026-01-01');
    expect(state.passportValidUntil, '2031-01-01');
    // 居住选区经字典 join:省名 + 市名 + 镇名(fake 字典把 code 映射成 N(code))。
    expect(state.residenceDistrict, contains('N(0755)'));
    expect(state.residenceDistrict, contains('N(001)'));
    // 投票公民无候选专属字段。
    expect(state.familyName, isNull);
    expect(state.givenName, isNull);
    expect(state.birthDistrict, isNull);
  });

  test('同时有候选身份时为竞选公民并解出姓名/性别/出生地', () async {
    final state = await buildService(
      voting: _encodeVoting(
        from: 20260101,
        until: 20310101,
        status: 0,
        province: 'GD',
        city: '0755',
        town: '001',
      ),
      candidate: _encodeCandidate(
        province: 'GD',
        city: '0020',
        town: '005',
        familyName: '陈',
        givenName: '明',
        sex: 0,
      ),
    ).getState();

    expect(state.tier, MyIdTier.candidate);
    expect(state.familyName, '陈');
    expect(state.givenName, '明');
    expect(state.citizenSexLabel, '男');
    expect(state.birthDistrict, contains('N(0020)'));
    expect(state.citizenBirthDate, '2000-01-31');
  });

  test('护照未生效/已过期/已吊销状态派生正确', () async {
    Uint8List voting({required int status}) => _encodeVoting(
      from: 20260101,
      until: 20310101,
      status: status,
      province: 'GD',
      city: '0755',
      town: '001',
    );

    final notYet = await buildService(
      voting: voting(status: 0),
      now: DateTime.utc(2025),
    ).getState();
    expect(notYet.status, MyIdStatus.notYetValid);

    final expired = await buildService(
      voting: voting(status: 0),
      now: DateTime.utc(2032),
    ).getState();
    expect(expired.status, MyIdStatus.expired);

    final revoked = await buildService(voting: voting(status: 1)).getState();
    expect(revoked.status, MyIdStatus.revoked);
  });

  test('链上读取失败时不静默降级访客,而是标记读取失败', () async {
    final state = await buildService(chainThrows: true).getState();
    expect(state.status, MyIdStatus.queryFailed);
    expect(state.errorMessage, '链上身份读取失败');
  });

  test('反向钱包错配或 CID 已吊销时不承认公民身份', () async {
    final voting = _encodeVoting(
      from: 20260101,
      until: 20310101,
      status: 0,
      province: 'GD',
      city: '0755',
      town: '001',
    );

    final mismatch = await buildService(
      voting: voting,
      mismatchWallet: true,
    ).getState();
    final revoked = await buildService(voting: voting, cidStatus: 1).getState();

    expect(mismatch.tier, MyIdTier.visitor);
    expect(revoked.tier, MyIdTier.visitor);
  });

  test('空居住镇码不会把公民误判为访客', () async {
    final state = await buildService(
      voting: _encodeVoting(
        from: 20260101,
        until: 20310101,
        status: 0,
        province: 'GD',
        city: '0755',
        town: '', // 空镇码
      ),
    ).getState();
    expect(state.tier, MyIdTier.voting);
    expect(state.cidNumber, 'GD-CTZN1-8F3A2B');
  });

  test('注册匿名 CID:用账户0 accountId + UTC 年生成金标 CID 并提交自签占号', () async {
    final identityCache = _InvalidationCountingIdentityCache();
    final fakeWallet = _FakeWalletManager(_aliceWallet);
    final fakeRpc = _FakeIdentityTransaction();
    final expected = generateCitizenCid(
      accountId: _validAccountId,
      institution: kCidInstitutionCitizen,
      year: 2026,
    );
    final service = testService(
      wallet: fakeWallet,
      chain: _FakeChain(),
      identityTransaction: fakeRpc,
      identityResolver: _FakeIdentityResolver(
        _registeredIdentity(_validAccountId, cidNumber: expected),
      ),
      currentUserContext: identityCache,
      cidYearProvider: () => 2026,
    );

    final cid = await service.registerAnonymousCid(
      context: null,
      institution: kCidInstitutionCitizen,
    );

    // 与 cid_generator 金标同源:accountId=_validAccountId, CTZN, 2026。
    expect(cid, expected);
    expect(fakeRpc.occupiedCid, expected);
    expect(fakeRpc.occupiedAccountId, _validAccountId);
    expect(identityCache.invalidateCalls, 1);
    expect(fakeWallet.identityNotifications, 1);
  });

  test('自主换绑保留当前账户授权；finalized 后仅由新账户接管', () async {
    final newAccount = _testAccount(
      accountIndex: 5,
      accountId: '0x${'11' * 32}',
      ss58Address: 'new-ss58',
      name: '账户5',
    );
    final fakeRpc = _FakeIdentityTransaction();
    final fakeWallet = _FakeWalletManager(_aliceWallet, accounts: [newAccount]);
    final resolver = _SequenceResolver(<FinalizedIdentity>[
      _registeredIdentity(_validAccountId),
      _registeredIdentity(newAccount.accountId, bindingRevision: 2),
    ]);
    final service = testService(
      wallet: fakeWallet,
      chain: _FakeChain(),
      identityTransaction: fakeRpc,
      identityResolver: resolver,
      dataHandover: _FakeDataHandover(),
    );

    await service.rebindCidTo(
      buildContext: null,
      cidNumber: 'GD-CTZN1-8F3A2B',
      newAccountId: newAccount.accountId,
    );

    // 链上换绑参数传对。
    expect(fakeRpc.reboundCid, 'GD-CTZN1-8F3A2B');
    expect(fakeRpc.reboundOld, _validAccountId);
    expect(fakeRpc.reboundNew, newAccount.accountId);
    // runtime 调用参数仍包含当前绑定账户，证明自主换绑授权没有被接管阶段替代。
    expect(fakeRpc.reboundOld, _validAccountId);
    // finalized 只激活公开绑定，不生成数据钥，也不登记 P-256 设备子钥。
    expect(fakeWallet.dataBindings.single.accountId, newAccount.accountId);
    expect(fakeWallet.dataBindings.single.bindingRevision, 2);
    expect(fakeWallet.deviceSubkeyRegistrationCalls, 0);
  });

  test('换绑 finalized 不登记 P-256 子钥，后续仅由 Worker 缺钥响应触发', () async {
    final newAccount = _testAccount(
      accountIndex: 5,
      accountId: '0x${'11' * 32}',
      ss58Address: 'new-ss58',
      name: '账户5',
    );
    final fakeWallet = _FakeWalletManager(_aliceWallet, accounts: [newAccount]);
    final resolver = _MutableResolver(_validAccountId);
    final service = testService(
      wallet: fakeWallet,
      chain: _FakeChain(),
      identityTransaction: _FakeIdentityTransaction(
        onRebound: () =>
            resolver.setAccountId(newAccount.accountId, bindingRevision: 2),
      ),
      identityResolver: resolver,
      dataHandover: _FakeDataHandover(),
    );

    await service.rebindCidTo(
      buildContext: null,
      cidNumber: 'GD-CTZN1-8F3A2B',
      newAccountId: newAccount.accountId,
    );
    expect(fakeWallet.dataBindings.single.accountId, newAccount.accountId);
    expect(fakeWallet.deviceSubkeyRegistrationCalls, 0);
  });

  test('换绑 extrinsic finalized 但目标状态未确认时绝不迁移本地数据', () async {
    final newAccount = _testAccount(
      accountIndex: 5,
      accountId: '0x${'11' * 32}',
      ss58Address: 'new-ss58',
      name: '账户5',
    );
    final fakeWallet = _FakeWalletManager(_aliceWallet, accounts: [newAccount]);
    final handover = _FakeDataHandover();
    final service = testService(
      wallet: fakeWallet,
      chain: _FakeChain(),
      identityTransaction: _FakeIdentityTransaction(
        rebindError: StateError('finalized 目标绑定未生效'),
      ),
      identityResolver: _FakeIdentityResolver(
        _registeredIdentity(_validAccountId),
      ),
      dataHandover: handover,
    );

    await expectLater(
      service.rebindCidTo(
        buildContext: null,
        cidNumber: 'GD-CTZN1-8F3A2B',
        newAccountId: newAccount.accountId,
      ),
      throwsA(isA<StateError>()),
    );

    expect(fakeWallet.deviceSubkeyRegistrationCalls, 0);
    expect(fakeWallet.dataBindings, isEmpty);
    expect(handover.stageCalls, 1);
    expect(handover.discardCalls, 1);
  });

  test('换绑目标 == 当前身份账户时拒', () async {
    final self = _testAccount(
      accountIndex: 0,
      accountId: _validAccountId,
      ss58Address: _validAddress,
      name: '账户0',
    );
    final wallet = _FakeWalletManager(_aliceWallet, accounts: [self]);
    final identityRpc = _FakeIdentityTransaction();
    final handover = _FakeDataHandover();
    final service = testService(
      wallet: wallet,
      chain: _FakeChain(),
      identityTransaction: identityRpc,
      identityResolver: _FakeIdentityResolver(
        _registeredIdentity(_validAccountId),
      ),
      dataHandover: handover,
    );

    await expectLater(
      service.rebindCidTo(
        buildContext: null,
        cidNumber: 'GD-CTZN1-8F3A2B',
        newAccountId: _validAccountId,
      ),
      throwsA(isA<AccountSecurityException>()),
    );
    expect(wallet.signCalls, 0, reason: '相同 account_id 必须在读取私钥前拒绝');
    expect(identityRpc.fetchRebindContextCalls, 0);
    expect(handover.stageCalls, 0);
  });

  test('listRebindTargets 排除当前身份账户', () async {
    final self = _testAccount(
      accountIndex: 0,
      accountId: _validAccountId,
      ss58Address: _validAddress,
      name: '账户0',
    );
    final other = _testAccount(
      accountIndex: 1,
      accountId: '0x${'22' * 32}',
      ss58Address: 'other-ss58',
      name: '账户1',
    );
    final service = testService(
      wallet: _FakeWalletManager(_aliceWallet, accounts: [self, other]),
      chain: _FakeChain(),
      identityResolver: _FakeIdentityResolver(
        _registeredIdentity(_validAccountId),
      ),
    );

    final targets = await service.listRebindTargets();
    expect(targets.map((account) => account.accountId).toList(), [
      other.accountId,
    ]);
  });

  test('listBindableAccounts 返回全部本地账户(含账户0)', () async {
    final acc0 = _testAccount(
      accountIndex: 0,
      accountId: _validAccountId,
      ss58Address: _validAddress,
      name: '账户0',
    );
    final acc5 = _testAccount(
      accountIndex: 5,
      accountId: '0x${'55' * 32}',
      ss58Address: 'ss5-addr',
      name: '账户5',
    );
    final service = testService(
      wallet: _FakeWalletManager(_aliceWallet, accounts: [acc0, acc5]),
      chain: _FakeChain(),
    );

    final accounts = await service.listBindableAccounts();
    expect(accounts.map((a) => a.accountIndex).toList(), [0, 5]);
  });

  test('注册匿名 CID 可绑到所选子账户 //5(非账户0)', () async {
    final acc5 = _testAccount(
      accountIndex: 5,
      accountId: '0x${'55' * 32}',
      ss58Address: 'ss5-addr',
      name: '账户5',
    );
    final fakeRpc = _FakeIdentityTransaction();
    final expected = generateCitizenCid(
      accountId: acc5.accountId,
      institution: kCidInstitutionCitizen,
      year: 2026,
    );
    final service = testService(
      wallet: _FakeWalletManager(_aliceWallet, accounts: [acc5]),
      chain: _FakeChain(),
      identityTransaction: fakeRpc,
      identityResolver: _FakeIdentityResolver(
        _registeredIdentity(acc5.accountId, cidNumber: expected),
      ),
      cidYearProvider: () => 2026,
    );

    final cid = await service.registerAnonymousCid(
      context: null,
      institution: kCidInstitutionCitizen,
      bindAccountId: acc5.accountId,
    );

    expect(cid, expected);
    expect(fakeRpc.occupiedCid, expected);
    // 绑到子账户 //5,而非默认账户0。
    expect(fakeRpc.occupiedAccountId, acc5.accountId);
  });

  group('CID 私有数据交接 intent', () {
    const source = AccountDataBinding(
      genesisHash:
          '0x4242424242424242424242424242424242424242424242424242424242424242',
      cidNumber: 'GD-CTZN1-8F3A2B',
      bindingRevision: 1,
      accountId:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    const target = AccountDataBinding(
      genesisHash:
          '0x4242424242424242424242424242424242424242424242424242424242424242',
      cidNumber: 'GD-CTZN1-8F3A2B',
      bindingRevision: 2,
      accountId:
          '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );

    test('stage 普通失败自动丢弃两子域并清除 preparing', () async {
      final wallet = _FakeWalletManager(null);
      final chat = _HandoverChatRuntime();
      final contacts = _HandoverContactService()
        ..stageError = StateError('通讯录 stage 失败');
      final handover = CidAccountDataHandover(
        accountSecurity: wallet,
        chatRuntime: chat,
        contactService: contacts,
      );

      await expectLater(
        handover.stage(source: source, target: target),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            '通讯录 stage 失败',
          ),
        ),
      );
      expect(chat.discardCalls, 1);
      expect(contacts.discardCalls, 1);
      expect(wallet.pendingHandover, isNull);
    });

    test('stage 补偿部分失败保留 preparing 并同时报告两个错误', () async {
      final wallet = _FakeWalletManager(null);
      final chat = _HandoverChatRuntime();
      final contacts = _HandoverContactService()
        ..stageError = StateError('通讯录 stage 失败')
        ..discardError = StateError('通讯录 discard 失败');
      final handover = CidAccountDataHandover(
        accountSecurity: wallet,
        chatRuntime: chat,
        contactService: contacts,
      );

      await expectLater(
        handover.stage(source: source, target: target),
        throwsA(
          isA<StateError>()
              .having(
                (error) => error.message,
                'stage error',
                contains('通讯录 stage 失败'),
              )
              .having(
                (error) => error.message,
                'discard error',
                contains('通讯录 discard 失败'),
              ),
        ),
      );
      expect(chat.discardCalls, 1);
      expect(contacts.discardCalls, 1);
      expect(wallet.pendingHandover?.state, AccountDataHandoverState.preparing);
    });
  });
}

// ── SCALE 编码夹具(镜像 citizen-identity pallet 的 VotingIdentity/CandidateIdentity 布局) ──

List<int> _compact(int n) {
  if (n < 64) return [n << 2];
  if (n < 16384) {
    final x = (n << 2) | 1;
    return [x & 0xff, (x >> 8) & 0xff];
  }
  throw ArgumentError('测试夹具只覆盖短向量');
}

List<int> _vec(String s) {
  final bytes = utf8.encode(s);
  return [..._compact(bytes.length), ...bytes];
}

List<int> _u32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

Uint8List _encodeVoting({
  required int from,
  required int until,
  required int status,
  required String province,
  required String city,
  required String town,
  int updatedAt = 1,
}) {
  return Uint8List.fromList([
    ..._u32(from),
    ..._u32(until),
    status,
    ..._vec(province),
    ..._vec(city),
    ..._vec(town),
    ..._u32(updatedAt),
  ]);
}

Uint8List _encodeCandidate({
  required String province,
  required String city,
  required String town,
  required String familyName,
  required String givenName,
  required int sex,
  int birthDate = 20000131,
  int updatedAt = 1,
}) {
  return Uint8List.fromList([
    ..._vec(province),
    ..._vec(city),
    ..._vec(town),
    ..._vec(familyName),
    ..._vec(givenName),
    sex,
    ..._u32(birthDate),
    ..._u32(updatedAt),
  ]);
}

// ── Fakes ──

class _FakeWalletManager
    implements CitizenSdkWallet, CitizenSigning, AccountSecurityService {
  _FakeWalletManager(
    this._wallet, {
    this.accounts = const <CitizenWalletStateAccount>[],
  });
  final CitizenWalletStateAccount? _wallet;
  final List<CitizenWalletStateAccount> accounts;

  int deviceSubkeyRegistrationCalls = 0;

  /// 当前钱包派生上下文激活记录。
  final List<({String cidNumber, int bindingRevision, String accountId})>
  dataBindings = [];
  final List<String> events = <String>[];
  int signCalls = 0;
  int identityNotifications = 0;
  AccountDataBinding? activeDataBinding;
  ({
    AccountDataBinding source,
    AccountDataBinding target,
    AccountDataHandoverState state,
  })?
  pendingHandover;

  @override
  Future<CitizenWalletState> getState() async => CitizenWalletState(
    revision: BigInt.one,
    hotProfile: null,
    accounts: <CitizenWalletStateAccount>[
      if (_wallet != null) _wallet,
      ...accounts.where((account) => account.accountId != _wallet?.accountId),
    ],
  );

  @override
  Future<CitizenSigningOutcome> begin(CitizenSigningIntent intent) async {
    signCalls++;
    return CitizenSigningCompleted(
      accountId: intent.accountId,
      payloadHash: '0x${'00' * 32}',
      signature: Uint8List(64),
    );
  }

  @override
  Future<void> activateAccountDataBinding({
    required String genesisHash,
    required String cidNumber,
    required int bindingRevision,
    required String accountId,
  }) async {
    expect(genesisHash, '0x${'42' * 32}');
    events.add('activate');
    dataBindings.add((
      cidNumber: cidNumber,
      bindingRevision: bindingRevision,
      accountId: accountId,
    ));
    activeDataBinding = AccountDataBinding(
      genesisHash: genesisHash,
      cidNumber: cidNumber,
      bindingRevision: bindingRevision,
      accountId: accountId,
    );
  }

  @override
  Future<AccountDataBinding?> readAccountDataBindingForCid(
    String cidNumber,
  ) async =>
      activeDataBinding?.cidNumber == cidNumber ? activeDataBinding : null;

  @override
  Future<AccountDataBinding?> readAccountDataBindingForAccountId(
    String accountId,
  ) async =>
      activeDataBinding?.accountId == accountId ? activeDataBinding : null;

  @override
  Future<
    ({
      AccountDataBinding source,
      AccountDataBinding target,
      AccountDataHandoverState state,
    })?
  >
  readPendingAccountDataHandover() async => pendingHandover;

  @override
  Future<void> recordPendingAccountDataHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    pendingHandover ??= (
      source: source,
      target: target,
      state: AccountDataHandoverState.preparing,
    );
  }

  @override
  Future<void> markPendingAccountDataHandoverReady({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    pendingHandover = (
      source: source,
      target: target,
      state: AccountDataHandoverState.ready,
    );
  }

  @override
  Future<void> clearPendingAccountDataHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    pendingHandover = null;
  }

  @override
  Future<void> registerDeviceSubkeyForBinding(
    AccountDataBinding binding,
  ) async {
    deviceSubkeyRegistrationCalls++;
  }

  @override
  void notifyIdentityBindingChanged() {
    identityNotifications++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HandoverChatRuntime extends ChatSdk {
  _HandoverChatRuntime() : super(host: _UnusedChatHost());

  int discardCalls = 0;

  @override
  Future<void> stageAccountHandover({
    required ChatDataBinding source,
    required ChatDataBinding target,
  }) async {}

  @override
  Future<void> discardAccountHandover({
    required ChatDataBinding source,
    required ChatDataBinding target,
  }) async {
    discardCalls++;
  }
}

class _UnusedChatHost implements ChatRuntimeHost {
  @override
  final ChatStorageKeyProvider keyProvider = _UnusedChatStorageKeyProvider();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedChatStorageKeyProvider implements ChatStorageKeyProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedSessionProvider implements SquareSessionProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HandoverContactService implements UserContactService {
  Object? stageError;
  Object? discardError;
  int discardCalls = 0;

  @override
  Future<void> stageAccountHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    final error = stageError;
    if (error != null) throw error;
  }

  @override
  Future<void> discardAccountHandover({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    discardCalls++;
    final error = discardError;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 预设身份账户解析结果的假 resolver(换绑/列举目标测试用,绕开真链读序列)。
class _FakeIdentityResolver implements FinalizedIdentityResolver {
  _FakeIdentityResolver(this._resolved);
  final FinalizedIdentity? _resolved;
  @override
  Future<FinalizedIdentity?> resolve() async => _resolved;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InvalidationCountingIdentityCache implements CurrentUserContext {
  int invalidateCalls = 0;

  @override
  void invalidate() {
    invalidateCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SequenceResolver implements FinalizedIdentityResolver {
  _SequenceResolver(this._values);
  final List<FinalizedIdentity> _values;
  int _index = 0;

  @override
  Future<FinalizedIdentity?> resolve() async {
    final index = _index < _values.length ? _index++ : _values.length - 1;
    return _values[index];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 可变身份账户的假 resolver(对账测试:换绑前后链上身份账户切换)。
class _MutableResolver implements FinalizedIdentityResolver {
  _MutableResolver(this._accountId, {int bindingRevision = 1})
    : _bindingRevision = bindingRevision;
  String _accountId;
  int _bindingRevision;
  void setAccountId(String accountId, {required int bindingRevision}) {
    _accountId = accountId;
    _bindingRevision = bindingRevision;
  }

  @override
  Future<FinalizedIdentity?> resolve() async =>
      _registeredIdentity(_accountId, bindingRevision: _bindingRevision);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 造一个「已注册(匿名)身份账户」解析结果:accountId 绑了 CID(snapshot 非空)。
FinalizedIdentity _registeredIdentity(
  String accountId, {
  String cidNumber = 'GD-CTZN1-8F3A2B',
  int bindingRevision = 1,
}) => FinalizedIdentity(
  accountId: accountId,
  ss58Address: _validAddress,
  snapshot: CitizenIdentityChainSnapshot(
    cidNumber: cidNumber,
    accountId: Uint8List(32),
    bindingRevision: bindingRevision,
    votingIdentity: null,
    candidateIdentity: null,
  ),
);

/// 记录占号 / 换绑调用参数的假 RPC(不上链),验证 service 编排把账户与 CID 传对。
class _FakeIdentityTransaction extends CitizenIdentityTransaction {
  _FakeIdentityTransaction({this.rebindError, this.onRebound})
    : super(chain: TestCitizenChain(), transactions: TestCitizenTransactions());

  final Object? rebindError;
  final void Function()? onRebound;
  String? occupiedCid;
  String? occupiedAccountId;
  String? reboundCid;
  String? reboundOld;
  String? reboundNew;
  int fetchRebindContextCalls = 0;

  @override
  Future<({String txHash, int usedNonce, String blockHashHex})> selfOccupyCid({
    required String cidNumber,
    required String accountId,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    occupiedCid = cidNumber;
    occupiedAccountId = accountId;
    return (txHash: '0xtx', usedNonce: 0, blockHashHex: '0xblk');
  }

  @override
  Future<({String txHash, int usedNonce, String blockHashHex})>
  selfRebindCidAccount({
    required String cidNumber,
    required String newAccountId,
    required String currentAccountId,
    required SelfRebindAuthorizationContext context,
    required Uint8List currentAccountSignature,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    final error = rebindError;
    if (error != null) throw error;
    reboundCid = cidNumber;
    reboundNew = newAccountId;
    reboundOld = currentAccountId;
    onRebound?.call();
    return (txHash: '0xtx', usedNonce: 0, blockHashHex: '0xblk');
  }

  @override
  Future<SelfRebindAuthorizationContext> fetchSelfRebindAuthorizationContext(
    String cidNumber,
  ) async {
    fetchRebindContextCalls++;
    return SelfRebindAuthorizationContext(
      genesisHash: Uint8List.fromList(List<int>.filled(32, 0x42)),
      currentAccountId: _validAccountId,
      expectedBindingRevision: BigInt.one,
      expiresAt: BigInt.from(1900000000),
    );
  }
}

class _FakeDataHandover implements CidAccountDataHandover {
  int stageCalls = 0;
  int discardCalls = 0;

  @override
  Future<void> stage({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    stageCalls++;
  }

  @override
  Future<void> commit({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {}

  @override
  Future<void> discard({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    discardCalls++;
  }

  @override
  Future<void> resumeForFinalizedBinding(AccountDataBinding current) async {}

  @override
  Future<void> prepareFinalizedBinding({
    required AccountDataBinding current,
    AccountDataBinding? previous,
  }) async {}

  @override
  Future<void> completeFinalizedBinding(AccountDataBinding current) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChain extends TestCitizenChain {
  _FakeChain({
    this.voting,
    this.candidate,
    this.throws = false,
    this.mismatchWallet = false,
    this.cidStatus = 0,
    this.hasCid = false,
  });
  final Uint8List? voting;
  final Uint8List? candidate;
  final bool throws;
  static const String cidNumber = 'GD-CTZN1-8F3A2B';
  final bool mismatchWallet;
  final int cidStatus;

  /// 是否存在 `CidByAccountId`。有 voting 必有 cid;匿名态显式置 true 表示
  /// 「有 CID 且绑定闭环、但无 voting」,用来驱动 reader 的匿名已注册分支。
  final bool hasCid;
  int _readIndex = 0;

  /// 链上下发的自付门槛(分)与账户余额(元),供注册前余额闸用例驱动三分支。
  BigInt minSelfPayFen = BigInt.from(121);
  double balanceYuan = 0.0;
  bool balanceThrows = false;

  @override
  Future<String> getGenesisHash() async => '0x${'42' * 32}';

  @override
  Future<CitizenFeeSnapshot> getFeeSnapshot() async {
    if (balanceThrows) throw StateError('metadata 未就绪');
    return CitizenFeeSnapshot(
      bestBlock: _bestBlock,
      feeRateParts: 1000000,
      minimumFeeFen: BigInt.from(10),
      existentialDepositFen: minSelfPayFen - BigInt.from(10),
    );
  }

  @override
  Future<CitizenAccountBalance> getAccountBalance(String accountId) async {
    if (balanceThrows) throw StateError('CitizenSDK 链状态未就绪');
    final fen = BigInt.from((balanceYuan * 100).round());
    return CitizenAccountBalance(
      accountId: accountId,
      block: _finalizedBlock,
      freeFen: fen,
      reservedFen: BigInt.zero,
      totalFen: fen,
    );
  }

  @override
  Future<CitizenBlockRef> getFinalizedHead() async => _finalizedBlock;

  @override
  Future<Uint8List?> getStorage(CitizenBlockRef block, Uint8List key) async {
    if (throws) throw StateError('CitizenSDK 链状态未就绪');
    final current = _readIndex++;
    if (current == 0) {
      // 有投票身份必有 CID;匿名态(hasCid=true)也有 CID 但后续 voting 读为 null。
      final present = voting != null || hasCid;
      return present ? Uint8List.fromList(_vec(cidNumber)) : null;
    }
    if (current == 1) {
      final accountId = Uint8List.fromList(
        Keyring().decodeAddress(_validAddress),
      );
      if (mismatchWallet) accountId[0] ^= 0xff;
      return accountId;
    }
    if (current == 2) {
      return Uint8List.fromList([
        ..._vec('FEDERAL_REGISTRY-CID'),
        ...List<int>.filled(32, 7),
        ..._vec('GD'),
        ..._vec('0755'),
        cidStatus,
        ..._u32(1),
        0,
      ]);
    }
    if (current == 3) return voting;
    if (current == 4) return candidate;
    if (current == 5) return Uint8List.fromList(<int>[1, 0, 0, 0, 0, 0, 0, 0]);
    throw StateError('读取次数超出身份闭环');
  }

  @override
  Future<List<Uint8List?>> getStorageBatch(
    CitizenBlockRef block,
    List<Uint8List> keys,
  ) async => Future.wait(keys.map((key) => getStorage(block, key)));

  static final CitizenBlockRef _finalizedBlock = CitizenBlockRef(
    hash: '0x${'00' * 32}',
    number: BigInt.one,
    finality: CitizenBlockFinality.finalized,
  );

  static final CitizenBlockRef _bestBlock = CitizenBlockRef(
    hash: '0x${'11' * 32}',
    number: BigInt.one,
    finality: CitizenBlockFinality.best,
  );
}

class _FakeDivisionStore implements AdminDivisionStore {
  @override
  Future<String> divisionName(
    String level,
    String scopeKey,
    String code,
  ) async => 'N($code)';
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeBadgeStore extends IdentityBadgeSnapshotStore {
  @override
  Future<void> write({
    required String cidNumber,
    required String identityLevel,
  }) async {}
  @override
  Future<IdentityBadgeSnapshot?> read(String cidNumber) async => null;
}
