import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/isar/app_isar.dart';
import 'package:citizenapp/wallet/pages/account_detail_page.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/identity_badge_snapshot_store.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/qr/pages/qr_scan_page.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import '../../support/isar_test_env.dart';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_flutter_codec.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/shimmer_loading.dart';
import 'package:citizenapp/wallet/pages/wallet_page.dart';
import 'package:citizenapp/wallet/account_balance_snapshot_store.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_service.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/fake_citizen_sdk.dart';

/// 历史UI断言直接取自be75a90b；仅以公开SDK事实替换旧钱包/三段仓储测试接缝。
/// 详情/徽标测试只使用本文件隔离数据库和合成事实，不访问真实钱包或金库。
/// QR图像为显式UI替身；协议解析仍可调用本轮Core，不把页面替身当设备验收。
class _Security implements AccountSecurityService {
  @override final ValueNotifier<int> revision = ValueNotifier<int>(0);
  List<String>? preparedIds;
  Set<int>? preparedWallets;
  bool? preparedWide;
  int cleanupCalls = 0;
  Object? cleanupError;
  AccountDataBinding? binding;
  bool _pending = false;
  @override Future<bool> get hasPendingAccountCleanup async => _pending || cleanupError != null;
  @override
  Future<void> prepareAccountCleanup({required List<String> accountIds, required Set<int> walletIndexes, required bool deleteWalletWideKey}) async {
    preparedIds = List.of(accountIds); preparedWallets = Set.of(walletIndexes); preparedWide = deleteWalletWideKey; _pending = true;
  }
  @override
  Future<void> reconcileAccountCleanup() async {
    cleanupCalls++;
    if (cleanupError != null) throw cleanupError!;
    _pending = false;
  }
  @override
  Future<void> cancelAccountCleanup() async { preparedIds = null; _pending = false; }
  @override
  void notifyDefaultAccountChanged() {}
  @override dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('UI测试未配置安全业务调用');
  @override
  Future<AccountDataBinding?> readAccountDataBindingForAccountId(String accountId) async => binding;
}

// 只替身现有服务公开结果，不复制身份规则或建立聊天/广场运行态。
class _CurrentUser extends Fake implements CurrentUserContext {
  @override Future<CurrentUser?> resolve() async => null;
}
class _Sessions extends Fake implements SquareSessionProvider {}
class _Resolver extends Fake implements FinalizedIdentityResolver {
  @override Future<FinalizedIdentity?> resolve() async =>
      _identityGate == null ? _identity : await _identityGate!.future;
}
FinalizedIdentity? _identity;
Completer<FinalizedIdentity?>? _identityGate;

late CitizenSdk _sdk;
late TestCitizenSdkTransport _transport;
late _Security _security;
late Future<CitizenWalletState> Function() _snapshotLoader;

CitizenWalletStateAccount _makeAccount({
  int index = 1,
  String name = '账户1',
  String ss58 = 'w5Bc7ma8qUcECfQDJmRyQM2wGmga5XSYtz7DvEengQ86xBWrT',
}) => CitizenWalletStateAccount(
  signMode: CitizenWalletSignMode.hot, walletIndex: 0, accountIndex: index,
  accountId: '0x${index.toRadixString(16).padLeft(64, '0')}',
  ss58Address: ss58, name: name, createdAtMillis: BigInt.zero, isDefault: false,
);

CitizenWalletStateAccount _makeColdWallet({int walletIndex = 2, String name = '冷钱包', bool isDefault = true}) {
  final id = '0x${walletIndex.toRadixString(16).padLeft(64, '0')}';
  return CitizenWalletStateAccount(
    signMode: CitizenWalletSignMode.cold, walletIndex: walletIndex,
    accountIndex: null, accountId: id, ss58Address: ss58FromAccountIdText(id),
    name: name, createdAtMillis: BigInt.zero, isDefault: isDefault,
  );
}

CitizenWalletState _hotWalletSnapshot() =>
    const CitizenSdkFlutterCodec().decodeWalletState(testCitizenWalletState());

CitizenWalletState _coldWalletSnapshot({String name = '测试冷钱包'}) =>
    CitizenWalletState(revision: BigInt.one, hotProfile: null, activeWalletIndex: 2,
      accounts: [_makeColdWallet(name: name)],
      initializationState: CitizenWalletInitializationState.ready, cleanupPending: false);

List<Object?> _stateTuple(CitizenWalletState state) => [
  state.revision.toString(),
  state.hotProfile == null ? null : [
    state.hotProfile!.walletIndex, state.hotProfile!.origin.name,
    state.hotProfile!.createdAtMillis.toString(), state.hotProfile!.masterAccountId, state.hotProfile!.activeAccountId,
    [for (final account in state.hotProfile!.accounts) [account.index, account.accountId, account.ss58Address,
      account.name, account.createdAtMillis.toString(), account.isActive]],
    state.hotProfile!.walletName,
  ],
  [
    for (final account in state.accounts) [
      account.signMode.name, account.walletIndex, account.accountIndex,
      account.accountId, account.ss58Address, account.name,
      account.createdAtMillis.toString(), account.isDefault,
    ],
  ],
  state.initializationState.index, state.cleanupPending, state.activeWalletIndex,
  [for (final value in state.diagnostics) [value.walletIndex, value.walletName, value.accountId, value.ss58Address,
    value.diagnosticReason.index + 1, value.signMode?.name,
    if (value.cleanupTargets == null) null else [value.cleanupTargets!.accountIds, value.cleanupTargets!.deleteWalletWideKey]]],
];

Widget _walletTabHost(Future<CitizenWalletState> Function() loader, {bool selectForTrade = false}) {
  _snapshotLoader = loader;
  return MultiProvider(providers: [
    Provider<CitizenSdk>.value(value: _sdk),
    Provider<AccountSecurityService>.value(value: _security),
    Provider<CurrentUserContext>(create: (_) => _CurrentUser()),
    Provider<FinalizedIdentityResolver>(create: (_) => _Resolver()),
    Provider<SquareSessionProvider>(create: (_) => _Sessions()),
  ], child: MaterialApp(home: WalletTab(selectForTrade: selectForTrade)));
}

void _disposeWidgetBeforeStores(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _drainStoreOperations(tester);
  });
}

Future<void> _drainStoreOperations(WidgetTester tester) async {
  // 钱包余额与身份徽标分别读取 Wallet/User；页面销毁不能取消已进入原生库的查询。
  // 同时推进原生 I/O 和 Widget 虚拟时钟，排空两域操作后才允许隔离夹具关闭数据库。
  for (var i = 0; i < 50 &&
      (WalletIsar.instance.hasActiveOperation || UserIsar.instance.hasActiveOperation); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(WalletIsar.instance.hasActiveOperation, isFalse,
    reason: '页面销毁后的钱包查询和 watch lease 必须先排空再清隔离库');
  expect(UserIsar.instance.hasActiveOperation, isFalse,
    reason: '页面销毁后的本地身份查询必须先排空再清隔离库');
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue, reason: '等待实际隔离库/SDK回调完成，不能用帧稳定代替I/O完成');
}

// 钱包首帧恢复读取真实隔离 Isar；虚拟帧稳定不能替代异步文件 I/O 完成。
Future<void> _settleWallet(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame && !WalletIsar.instance.hasActiveOperation) return;
  }
  fail('钱包页面或本地 I/O 未在有界等待内完成');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useIsolatedIsar();
  setUp(() async {
    _identity = null;
    _identityGate = null;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('citizenapp/security'), (_) async => null);
    _security = _Security();
    // 原生库在Widget虚拟时钟之外打开，避免首次open挂在FakeAsync中。
    await UserIsar.instance.db();
    await WalletIsar.instance.db();
    await AppIsar.instance.db();
    _snapshotLoader = () async => _coldWalletSnapshot();
    var inspectionSequence = 0;
    CitizenWalletState? inspectedSnapshot;
    _transport = TestCitizenSdkTransport({
      'inspectWallets': (_) async {
        final snapshot = await _snapshotLoader();
        inspectedSnapshot = snapshot;
        return ['inspection-${++inspectionSequence}', _stateTuple(snapshot)];
      },
      'releaseWalletInspection': (_) => [],
      'qrEncode': (_) => [29, 29, Uint8List(29 * 29)..fillRange(0, 29 * 29, 255)],
      'getAccountBalance': (fields) => [[fields[0], ['0x${'00' * 32}', '1', 'finalized'], '100', '0', '100']],
      // SDK普通状态读取复用已取得的目录事实，不能消费UI检查的下一次请求或并发闸门。
      'getWalletState': (_) => [_stateTuple(inspectedSnapshot ?? _coldWalletSnapshot())],
      'getAccountBalances': (fields) => [
        [
          for (final id in fields[0] as List) [
            id, ['0x${'00' * 32}', '1', 'finalized'], '0', '0', '0',
          ],
        ],
      ],
    }, useCore: true);
    _sdk = await _transport.open();
  });
  tearDown(() async {
    await _sdk.close();
    await _transport.dispose();
    _security.revision.dispose();
  });

  testWidgets('页面退出排空仍在运行的本地身份查询，即使钱包库已空闲', (tester) async {
    _disposeWidgetBeforeStores(tester);
    final release = Completer<void>();
    final pending = UserIsar.instance.read<void>((_) => release.future);
    Timer? timer;
    try {
      // 队列可能先等待真实setUp区域的Future；不能把一次pump当作已经进入操作。
      await _pumpUntil(tester, () => UserIsar.instance.hasActiveOperation);
      expect(WalletIsar.instance.hasActiveOperation, isFalse);
      timer = Timer(const Duration(milliseconds: 40), () => release.complete());
      await _drainStoreOperations(tester);
      await pending;
    } finally {
      timer?.cancel();
      if (!release.isCompleted) release.complete();
      await tester.pump();
    }
  });

  for (final selectForTrade in [false, true]) {
    testWidgets('冷钱包已有余额在卡片首次出现时显示，身份未返回不阻塞：$selectForTrade', (tester) async {
      _disposeWidgetBeforeStores(tester);
      final snapshot = _coldWalletSnapshot();
      final store = AccountBalanceSnapshotStore.forChain(_sdk.chain);
      await tester.runAsync(() => store.getAccountBalance(snapshot.accounts.single.accountId));
      // 清空内存且保留隔离库，验证首次卡片真正恢复磁盘余额，不能靠预热内存通过。
      await tester.runAsync(() => store.forget([snapshot.accounts.single.accountId]));
      expect(store.accountState(snapshot.accounts.single.accountId).value, isNull);
      var queries = 0;
      _transport.handlers['getAccountBalance'] = (_) { queries++; throw StateError('禁止重复余额查询'); };
      _transport.handlers['getAccountBalances'] = (_) { queries++; throw StateError('禁止重复余额查询'); };
      final identity = _identityGate = Completer<FinalizedIdentity?>();
      await tester.pumpWidget(_walletTabHost(() async => snapshot, selectForTrade: selectForTrade));
      // 只等待钱包目录使卡片可见；不等待身份或余额从网络回来。
      await _pumpUntil(tester, () => find.byType(WalletListTile).evaluate().isNotEmpty);
      expect(identity.isCompleted, isFalse);
      expect(find.text('1.00'), findsOneWidget);
      expect(queries, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_walletTabHost(() async => snapshot, selectForTrade: selectForTrade));
      await _pumpUntil(tester, () => find.byType(WalletListTile).evaluate().isNotEmpty);
      expect(find.text('1.00'), findsOneWidget);
      expect(queries, 0);
      identity.complete(null);
      await tester.pump();
    });
  }




  CitizenWalletState orderedState({int revision = 1, String name = '原冷钱包'}) {
    final hot = _hotWalletSnapshot();
    final cold = _makeColdWallet(name: name);
    final master = hot.accounts.single;
    return CitizenWalletState(revision: BigInt.from(revision), hotProfile: hot.hotProfile,
      activeWalletIndex: 0, initializationState: CitizenWalletInitializationState.ready, cleanupPending: false,
      accounts: [cold, CitizenWalletStateAccount(signMode: master.signMode, walletIndex: master.walletIndex,
        accountIndex: master.accountIndex, accountId: master.accountId, ss58Address: master.ss58Address,
        name: master.name, createdAtMillis: master.createdAtMillis, isDefault: false)]);
  }


  testWidgets('默认账户热签完成后读取SDK新顺序，不改付款钱包', (tester) async {
      _disposeWidgetBeforeStores(tester);
    final hot = _hotWalletSnapshot();
    final cold = _makeColdWallet(name: '新默认冷钱包', isDefault: false);
    var state = CitizenWalletState(revision: BigInt.one, hotProfile: hot.hotProfile,
      accounts: [...hot.accounts, cold], activeWalletIndex: 0,
      initializationState: CitizenWalletInitializationState.ready, cleanupPending: false);
    _transport.handlers['beginDefaultAccountChange'] = (fields) {
      expect(fields[0], '1');
      expect(fields[1], [cold.accountId, hot.accounts.single.accountId]);
      state = orderedState(revision: 2, name: '新默认冷钱包');
      return [['completed', hot.accounts.single.accountId, '0x${'22' * 32}', '2', null, null, null]];
    };
    await tester.pumpWidget(_walletTabHost(() async => state)); await _settleWallet(tester);
    tester.widget<SliverReorderableList>(find.byType(SliverReorderableList)).onReorderItem!(0, 1);
    await _settleWallet(tester);
    expect(tester.widget<WalletListTile>(find.byType(WalletListTile)).isDefault, isTrue);
    expect(state.activeWalletIndex, 0);
    expect(_transport.calls, isNot(contains('setActiveWallet')));
    expect(find.byType(QrSignSessionPage), findsNothing);
  });

  testWidgets('非0热账户沿原菜单直接删除，不增加确认或整钱包签名', (tester) async {
      _disposeWidgetBeforeStores(tester);
    final raw = testCitizenWalletState();
    final childId = '0x${'02' * 32}';
    final address = ss58FromAccountIdText(childId);
    ((raw[1] as List)[5] as List).add([1, childId, address, '账户1', '1', false]);
    (raw[2] as List).add(['hot', 0, 1, childId, address, '账户1', '1', false]);
    var state = const CitizenSdkFlutterCodec().decodeWalletState(raw);
    _transport.handlers['deleteAccount'] = (fields) {
      expect(fields, [childId]);
      final next = testCitizenWalletState()..[0] = '2';
      state = const CitizenSdkFlutterCodec().decodeWalletState(next);
      return [next];
    };
    await tester.pumpWidget(_walletTabHost(() async => state)); await _settleWallet(tester);
    final row = find.ancestor(of: find.text('账户1'), matching: find.byType(WalletAccountTile));
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('账户操作')));
    await _settleWallet(tester);
    await tester.tap(find.text('删除账户')); await _settleWallet(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('账户1'), findsNothing);
    expect(_security.preparedIds, [childId]);
    expect(_security.preparedWide, isFalse);
    expect(_transport.calls, isNot(contains('signAndDeleteWallet')));
  });

  testWidgets('默认账户冷签取消归还会话，恢复原排序和原取消提示', (tester) async {
      _disposeWidgetBeforeStores(tester);
    final state = orderedState();
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90;
    const request = 'synthetic-default-request';
    _transport.handlers['beginDefaultAccountChange'] = (_) => [[
      'externalPending', state.accounts.first.accountId, '0x${'22' * 32}', null,
      '$expiry', 'synthetic-default-session', request,
    ]];
    _transport.handlers['qrParse'] = (_) => [jsonEncode({
      'kind': 1, 'canonical_text': request, 'scan_purpose_mask': 80,
      'request_id': 'synthetic-request-id-1', 'expires_at': expiry, 'action': CitizenQrActions.switchDefaultAccount,
      'signer_account_id': state.accounts.first.accountId, 'review_payload': '0x0c0001',
    })];
    _transport.handlers['cancelSigning'] = (_) => [true];
    await tester.pumpWidget(_walletTabHost(() async => state)); await _settleWallet(tester);
    final reorder = tester.widget<SliverReorderableList>(find.byType(SliverReorderableList)).onReorderItem;
    reorder!(0, 1); await _settleWallet(tester);
    expect(find.byType(QrSignSessionPage), findsOneWidget);
    await tester.tap(find.text('取消')); await _settleWallet(tester);
    expect(find.text('已取消默认账户切换'), findsOneWidget);
    expect(_transport.calls.where((m) => m == 'cancelSigning'), hasLength(1));
    expect(_transport.calls, isNot(contains('consumeDefaultAccountChange')));
    expect(tester.widget<WalletListTile>(find.byType(WalletListTile)).isDefault, isTrue);
  });

  testWidgets('默认账户旧失败不能覆盖等待期间读取到的新目录修订', (tester) async {
      _disposeWidgetBeforeStores(tester);
    var state = orderedState();
    final pending = Completer<List<Object?>>();
    _transport.handlers['beginDefaultAccountChange'] = (_) => pending.future;
    await tester.pumpWidget(_walletTabHost(() async => state)); await _settleWallet(tester);
    tester.widget<SliverReorderableList>(find.byType(SliverReorderableList)).onReorderItem!(0, 1);
    await tester.pump();
    state = orderedState(revision: 2, name: '新修订冷钱包');
    // SDK 回调使用测试时钟，Isar 使用真实 I/O；按既有有界等待同时驱动两者。
    var refreshed = false;
    final refreshing = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
    unawaited(refreshing.whenComplete(() => refreshed = true));
    await _pumpUntil(tester, () => refreshed);
    await refreshing;
    await _settleWallet(tester);
    pending.completeError(const CitizenSdkException(code: CitizenSdkErrorCode.conflict, message: '旧修订已失效'));
    await _settleWallet(tester);
    expect(find.text('新修订冷钱包'), findsOneWidget);
    expect(find.text('原冷钱包'), findsNothing);
    expect(find.text('旧修订已失效'), findsOneWidget);
  });

  for (final cancel in [false, true]) {
    testWidgets('账户0保留签名并删除确认：${cancel ? '取消不调用SDK' : '成功调用唯一受控删除'}', (tester) async {
      _disposeWidgetBeforeStores(tester);
      var state = _hotWalletSnapshot();
      _transport.handlers['signAndDeleteWallet'] = (_) {
        state = CitizenWalletState(revision: BigInt.two, hotProfile: null, accounts: const [],
          initializationState: CitizenWalletInitializationState.empty, cleanupPending: false);
        return [];
      };
      await tester.pumpWidget(_walletTabHost(() async => state)); await _settleWallet(tester);
      await tester.tap(find.byTooltip('账户操作')); await _settleWallet(tester);
      await tester.tap(find.text('删除钱包')); await _settleWallet(tester);
      expect(find.text('签名并删除'), findsOneWidget);
      await tester.tap(find.text(cancel ? '取消' : '签名并删除')); await _settleWallet(tester);
      expect(_transport.calls.where((m) => m == 'signAndDeleteWallet'), hasLength(cancel ? 0 : 1));
      expect(_transport.calls, isNot(contains('deleteWallet')));
      if (!cancel) {
        expect(_security.preparedIds, [testCitizenAccountId]);
        expect(find.textContaining('已删除钱包'), findsOneWidget);
      }
    });
  }

  testWidgets('签名删除已提交但SDK安全清理未完，保留原事实已移除提示', (tester) async {
      _disposeWidgetBeforeStores(tester);
    var state = _hotWalletSnapshot();
    // 删除失败后的SDK回读必须看到已提交事实；与页面inspect的生命周期分开配置。
    _transport.handlers['getWalletState'] = (_) => [_stateTuple(state)];
    _transport.handlers['signAndDeleteWallet'] = (_) {
      state = CitizenWalletState(revision: BigInt.two, hotProfile: null, accounts: const [],
        initializationState: CitizenWalletInitializationState.recovering, cleanupPending: true);
      throw const CitizenSdkException(code: CitizenSdkErrorCode.storage, message: '合成安全清理未完成');
    };
    _security.cleanupError = const AccountSecurityException('等待SDK安全清理');
    await tester.pumpWidget(_walletTabHost(() async => state)); await _settleWallet(tester);
    await tester.tap(find.byTooltip('账户操作')); await _settleWallet(tester);
    await tester.tap(find.text('删除钱包')); await _settleWallet(tester);
    await tester.tap(find.text('签名并删除')); await _settleWallet(tester);
    expect(find.textContaining('事实已移除，但本机安全清理未完成'), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-pending-cleanup-banner')), findsOneWidget);
    expect(find.textContaining('删除未完成：'), findsNothing);
  });

  testWidgets('钱包徽标复用公民状态，不把匿名本地绑定显示为身份钱包', (tester) async {
      _disposeWidgetBeforeStores(tester);
    final state = _hotWalletSnapshot();
    final account = state.defaultAccount!;
    _security.binding = AccountDataBinding(genesisHash: '0x${'11' * 32}',
      cidNumber: 'GD-CTZN1-8F3A2B', bindingRevision: 1, accountId: account.accountId);
    Uint8List voting() {
      final dates = ByteData(8)
        ..setUint32(0, 20260101, Endian.little)
        ..setUint32(4, 20310101, Endian.little);
      // 合成公开身份记录夹具；身份解码和公民判断仍由原MyIdService执行。
      return Uint8List.fromList([...dates.buffer.asUint8List(), 0,
        8, 71, 68, 16, 48, 55, 53, 53, 12, 48, 48, 49, 1, 0, 0, 0]);
    }
    FinalizedIdentity identity(Uint8List? bytes) => FinalizedIdentity(
      accountId: account.accountId, ss58Address: account.ss58Address,
      snapshot: CitizenIdentityChainSnapshot(cidNumber: 'GD-CTZN1-8F3A2B',
        accountId: Uint8List.fromList(List.filled(32, 1)), bindingRevision: 1,
        votingIdentity: bytes));
    final badges = IdentityBadgeSnapshotStore();
    Future<void> saveIdentity(CitizenIdentityChainSnapshot? snapshot) => badges.writeVerified(
      accountId: account.accountId, identity: snapshot, isCurrent: () => true);
    // 徽标读取User域已验真快照，不能再靠远端Resolver替身驱动普通页面展示。
    await tester.runAsync(() => saveIdentity(identity(null).snapshot));
    await tester.pumpWidget(_walletTabHost(() async => state)); await _settleWallet(tester);
    await _pumpUntil(tester, () => _transport.calls.contains('getAccountBalances'));
    expect(find.text('身份钱包'), findsNothing);
    await tester.runAsync(() => saveIdentity(identity(voting()).snapshot));
    _security.revision.value++;
    await _pumpUntil(tester, () => find.text('身份钱包').evaluate().length == 1);
    expect(find.text('身份钱包'), findsOneWidget);
    await tester.runAsync(() => saveIdentity(null));
    _security.revision.value++;
    await _pumpUntil(tester, () => find.text('身份钱包').evaluate().isEmpty);
    expect(find.text('身份钱包'), findsNothing);
  });

  for (final code in [CitizenSdkErrorCode.network, CitizenSdkErrorCode.timeout,
    CitizenSdkErrorCode.unavailable, CitizenSdkErrorCode.integrity, CitizenSdkErrorCode.notReady]) {
    testWidgets('余额读取$code只按SDK明确事实显示原提示', (tester) async {
      _disposeWidgetBeforeStores(tester);
      _transport.handlers['getAccountBalances'] = (_) => throw CitizenSdkException(
        code: code, message: 'synthetic detail does not define a UI category');
      _transport.handlers['getSyncStatus'] = (_) => [[
        '0', true, false, ['0x${'00' * 32}', '1', 'best'],
        ['0x${'00' * 32}', '1', 'finalized'],
      ]];
      await tester.pumpWidget(_walletTabHost(() async => _coldWalletSnapshot()));
      await _settleWallet(tester);
      final expected = switch (code) {
        CitizenSdkErrorCode.unavailable || CitizenSdkErrorCode.integrity => '区块链暂不可用，请检查网络连接后重试',
        CitizenSdkErrorCode.notReady => '轻节点正在同步链状态，请稍后再试',
        _ => '区块链读取失败，请稍后再试',
      };
      await _pumpUntil(tester, () => find.text(expected).evaluate().isNotEmpty);
      expect(find.text(expected), findsOneWidget);
      expect(find.text('公民链余额暂时不可用'), findsNothing);
      expect(find.text('设备网络不可用，请检查网络后重试'), findsNothing);
      expect(find.text('轻节点同步超时，请检查网络后重试'), findsNothing);
    });
  }


  testWidgets('SDK明确启动失败使用原初始化提示，不能伪称设备离线', (tester) async {
      _disposeWidgetBeforeStores(tester);
    _transport.handlers['start'] = (_) => ['startFailed'];
    await expectLater(_sdk.start(), throwsA(isA<CitizenSdkException>()));
    expect(_sdk.lifecycle, CitizenSdkLifecycle.startFailed);
    _transport.handlers['getAccountBalances'] = (_) => throw const CitizenSdkException(
      code: CitizenSdkErrorCode.network, message: '合成启动后错误');
    await tester.pumpWidget(_walletTabHost(() async => _coldWalletSnapshot()));
    await _settleWallet(tester);
    await _pumpUntil(tester, () => find.text('轻节点初始化失败，请检查网络后重试').evaluate().isNotEmpty);
    expect(find.text('轻节点初始化失败，请检查网络后重试'), findsOneWidget);
  });

  testWidgets('notReady且同步事实也不可读取时使用原通用提示', (tester) async {
      _disposeWidgetBeforeStores(tester);
    _transport.handlers['getAccountBalances'] = (_) => throw const CitizenSdkException(
      code: CitizenSdkErrorCode.notReady, message: '合成未就绪');
    _transport.handlers['getSyncStatus'] = (_) => throw const CitizenSdkException(
      code: CitizenSdkErrorCode.unavailable, message: '合成状态不可读');
    await tester.pumpWidget(_walletTabHost(() async => _coldWalletSnapshot()));
    await _settleWallet(tester);
    await _pumpUntil(tester, () => find.text('区块链读取失败，请稍后再试').evaluate().isNotEmpty);
    expect(find.text('区块链读取失败，请稍后再试'), findsOneWidget);
    expect(find.text('轻节点正在同步链状态，请稍后再试'), findsNothing);
  });

  for (final cancel in [false, true]) {
    testWidgets('账户重命名${cancel ? '取消' : '保存'}等待原退场，不提前释放控制器', (tester) async {
      _disposeWidgetBeforeStores(tester);
      var state = _hotWalletSnapshot();
      List<Object?>? submitted;
      _transport.handlers['renameAccount'] = (fields) {
        submitted = fields;
        final raw = _stateTuple(state);
        (((raw[1] as List)[5] as List).single as List)[3] = fields[1];
        ((raw[2] as List).single as List)[5] = fields[1];
        raw[0] = '2';
        state = const CitizenSdkFlutterCodec().decodeWalletState(raw);
        return [raw];
      };
      await tester.pumpWidget(_walletTabHost(() async => state)); await _settleWallet(tester);
      await tester.tap(find.byTooltip('账户操作')); await _settleWallet(tester);
      await tester.tap(find.text('重命名')); await _settleWallet(tester);
      expect(find.text('重命名账户'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '原账户新名称');
      await tester.tap(find.text(cancel ? '取消' : '保存'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await _settleWallet(tester);
      expect(tester.takeException(), isNull);
      if (cancel) { expect(submitted, isNull); }
      else { expect(submitted, [testCitizenAccountId, '原账户新名称']); expect(find.text('原账户新名称'), findsOneWidget); }
    });
  }

  for (final failImport in [false, true]) {
    testWidgets('冷导入手填地址${failImport ? '失败留页' : '成功返回'}只调用同一SDK入口', (tester) async {
      _disposeWidgetBeforeStores(tester);
      List<Object?>? submitted;
      _transport.handlers['importColdAccountSs58'] = (fields) {
        submitted = fields;
        if (failImport) {
          throw const CitizenSdkException(
            code: CitizenSdkErrorCode.invalidArgument, message: '合成冷导入失败');
        }
        return [_stateTuple(_coldWalletSnapshot())];
      };
      bool? result;
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk,
        child: MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: TextButton(onPressed: () async {
            result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const ImportColdWalletPage()));
          }, child: const Text('打开冷导入')),
        )))));
      await tester.tap(find.text('打开冷导入')); await _settleWallet(tester);
      final address = _makeColdWallet().ss58Address;
      await tester.enterText(find.byType(TextField), address);
      await tester.tap(find.text('确认导入')); await _settleWallet(tester);
      expect(submitted, [address, '']);
      if (failImport) {
        expect(find.byType(ImportColdWalletPage), findsOneWidget);
        expect(find.text('合成冷导入失败'), findsOneWidget);
        expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, address);
      } else { expect(result, isTrue); expect(find.text('打开冷导入'), findsOneWidget); }
      expect(_transport.calls, isNot(contains('importWallet')));
      await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester);
    });
  }

  testWidgets('冷导入扫码拒绝非账户码，账户码只填入地址不自动导入', (tester) async {
      _disposeWidgetBeforeStores(tester);
    _transport.handlers['openQrCapture'] = (_) => throw const CitizenSdkException(
      code: CitizenSdkErrorCode.permissionDenied, message: '显式扫码页面替身，不使用设备');
    await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk,
      child: const MaterialApp(home: ImportColdWalletPage())));
    final address = _makeColdWallet().ss58Address;
    final accountCode = await _sdk.qr.encodeAccountId(_makeColdWallet().accountId);
    final userCode = (await _sdk.qr.encodeDocument(CitizenQrContent.userContact(
      accountId: _makeColdWallet().accountId,
      cidNumber: 'GD-CTZN1-8F3A2B'))).canonicalText;
    for (final raw in ['not-an-account-code', userCode, accountCode]) {
      await tester.tap(find.byTooltip('扫码填入地址')); await _settleWallet(tester);
      // 只替身路由返回值，调用方仍经实际SDK解析，不声称摄像验收。
      Navigator.of(tester.element(find.byType(QrScanPage))).pop(raw);
      await _settleWallet(tester);
      if (raw != accountCode) {
        expect(find.text('未识别到可导入的钱包账户地址'), findsOneWidget);
        expect(_transport.calls, isNot(contains('importColdAccountSs58')));
      }
    }
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, address);
    expect(find.text('未识别到可导入的钱包账户地址'), findsNothing);
    expect(_transport.calls, isNot(contains('importColdAccountSs58')));
    await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester);
  });

  for (final accountPage in [false, true]) {
    testWidgets('原${accountPage ? '账户' : '钱包'}私钥弹窗保留独立警告，后台清屏并只关闭一次', (tester) async {
      _disposeWidgetBeforeStores(tester);
      final account = _hotWalletSnapshot().accounts.single;
      _transport.handlers['openPrivateKey'] = (_) => ['synthetic-key'];
      _transport.handlers['revealPrivateKey'] = (_) => [Uint8List.fromList(List.filled(32, 90))];
      _transport.handlers['closePrivateKey'] = (_) => [];
      addTearDown(() {
        if (tester.binding.lifecycleState == AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        }
        if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        }
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk,
        child: MaterialApp(home: accountPage ? AccountDetailPage(account: account)
          : WalletDetailPage(wallet: account, walletName: '原钱包', expectedRevision: BigInt.one))));
      await _settleWallet(tester);
      await tester.tap(find.byIcon(Icons.more_vert)); await _settleWallet(tester);
      await tester.tap(find.text('查看私钥')); await _settleWallet(tester);
      expect(find.text(accountPage
        ? '私钥泄露将导致该账户资产被盗（仅该账户，不影响本钱包其他账户）。\n\n确认要查看吗？'
        : '私钥是核心机密信息，泄露将导致资产被盗。\n\n确认要查看吗？'), findsOneWidget);
      await tester.tap(find.text('查看')); await _settleWallet(tester);
      expect(find.text('私钥'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _settleWallet(tester);
      expect(find.text('私钥'), findsNothing);
      expect(_transport.calls.where((m) => m == 'closePrivateKey'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('钱包原Builder只在刷新失败时包横幅，轻提示限频且重试恢复', (tester) async {
      _disposeWidgetBeforeStores(tester);
    var fail = false;
    await tester.pumpWidget(_walletTabHost(() async {
      if (fail) throw StateError('合成钱包刷新失败');
      return _coldWalletSnapshot();
    }));
    await _settleWallet(tester);
    Widget bodyContent() {
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.body, isA<Builder>());
      return (scaffold.body! as Builder).builder(
        tester.element(find.byType(WalletTab)),
      );
    }

    // 历史正常态直接返回列表，不额外增加Column/Expanded层。
    expect(bodyContent(), isA<RefreshIndicator>());
    fail = true;
    _security.revision.value++;
    await _settleWallet(tester);
    final failedBody = bodyContent() as Column;
    expect(failedBody.children, hasLength(2));
    expect(failedBody.children.first, isA<Material>());
    expect(failedBody.children.last, isA<Expanded>());
    expect(find.text('测试冷钱包'), findsOneWidget);
    expect(find.text('钱包刷新失败，已保留上次成功加载的数据'), findsOneWidget);

    // 连续失败不能把同一轻提示排队重复显示；横幅仍保留重试入口。
    _security.revision.value++;
    await _settleWallet(tester);
    await tester.pump(const Duration(seconds: 5));
    await _settleWallet(tester);
    expect(find.text('钱包刷新失败，已保留上次成功加载的数据'), findsNothing);
    expect(find.byKey(const ValueKey('wallet-refresh-retry')), findsOneWidget);

    fail = false;
    await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
    await _settleWallet(tester);
    expect(bodyContent(), isA<RefreshIndicator>());
    expect(find.byKey(const ValueKey('wallet-refresh-retry')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 以下七项详情布局/菜单/返回断言从历史原件恢复，仅替换SDK模型与注入。
    testWidgets('顶部完整地址和卡片右上角二维码，删除/私钥/清算行不残留在正文', (tester) async {
      _disposeWidgetBeforeStores(tester);
      addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester); });
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final account = _makeAccount(name: '账户1');
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk, child:
        MaterialApp(home: AccountDetailPage(account: account)),
      ));
      await tester.pump();
      expect(find.text('账户详情'), findsOneWidget);
      expect(find.text(account.ss58Address), findsOneWidget);
      expect(find.byTooltip('账户二维码'), findsOneWidget);
      expect(find.byTooltip('复制 SS58 地址'), findsOneWidget);
      final headerFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).gradient != null,
        description: '账户详情渐变资料卡',
      );
      final headerRect = tester.getRect(headerFinder);
      final nameRect = tester.getRect(find.text(account.name));
      final qrRect = tester.getRect(find.byTooltip('账户二维码'));
      final copyRect = tester.getRect(find.byTooltip('复制 SS58 地址'));
      expect(
        qrRect.left,
        greaterThanOrEqualTo(nameRect.right),
        reason: '二维码必须位于账户名布局区之外，不能紧挨名称排版',
      );
      expect(
        qrRect.top - headerRect.top,
        lessThanOrEqualTo(12),
        reason: '二维码触控区必须贴在账户卡顶部',
      );
      expect(
        headerRect.right - qrRect.right,
        lessThanOrEqualTo(12),
        reason: '二维码触控区必须贴在账户卡右侧',
      );
      expect(
        copyRect.top,
        greaterThanOrEqualTo(qrRect.bottom),
        reason: '复制按钮必须下移到独立地址行，不能继续占用二维码旁的地址宽度',
      );
      expect(
        headerRect.right - copyRect.right,
        lessThanOrEqualTo(24),
        reason: '复制按钮必须靠齐账户卡内容右侧',
      );
      expect(find.text('点击查看私钥'), findsNothing);
      expect(find.text('删除账户'), findsNothing);
      expect(find.text('删除钱包'), findsNothing);
      expect(find.text('绑定 / 切换清算行'), findsNothing);
    });

    testWidgets('AppBar 右侧竖三点只有「清算行 / 查看私钥」', (tester) async {
      _disposeWidgetBeforeStores(tester);
      addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester); });
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk, child:
        MaterialApp(
          home: AccountDetailPage(account: _makeAccount(index: 0, name: '账户0')),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await _settleWallet(tester);
      expect(find.text('清算行'), findsOneWidget);
      expect(find.text('查看私钥'), findsOneWidget);
      expect(find.text('删除钱包'), findsNothing);
      expect(find.text('重命名'), findsNothing);
    });

    testWidgets('账户右上角二维码打开固定账户码弹窗', (tester) async {
      _disposeWidgetBeforeStores(tester);
      addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester); });
      final account = _makeAccount(index: 5, name: '日常账户');
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk, child:
        MaterialApp(home: AccountDetailPage(account: account)),
      ));
      await tester.pump();
      await tester.tap(find.byTooltip('账户二维码'));
      await _settleWallet(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('日常账户')),
        findsOneWidget,
      );
      expect(find.text('账户地址'), findsNothing);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-account-qr')), findsOneWidget);
    });

    testWidgets('账户清算行入口只提示暂未上线', (tester) async {
      _disposeWidgetBeforeStores(tester);
      addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester); });
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk, child:
        MaterialApp(home: AccountDetailPage(account: _makeAccount(index: 0))),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await _settleWallet(tester);
      await tester.tap(find.text('清算行'));
      await tester.pump();

      expect(find.text('暂未上线，敬请期待'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '账户详情'), findsOneWidget);
    });

    testWidgets('iOS 左边缘手势可从账户详情返回上一级', (tester) async {
      _disposeWidgetBeforeStores(tester);
      addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester); });
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk, child:
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AccountDetailPage(account: _makeAccount(index: 1)),
                  ),
                ),
                child: const Text('打开账户详情'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开账户详情'));
      await _settleWallet(tester);
      expect(find.widgetWithText(AppBar, '账户详情'), findsOneWidget);

      await tester.dragFrom(const Offset(1, 300), const Offset(500, 0));
      await _settleWallet(tester);

      expect(find.text('打开账户详情'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '账户详情'), findsNothing);
    });

    testWidgets('iOS 左边缘手势可从钱包详情返回上一级', (tester) async {
      _disposeWidgetBeforeStores(tester);
      addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester); });
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk, child:
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => WalletDetailPage(wallet: _makeColdWallet(), walletName: '冷钱包', expectedRevision: BigInt.one),
                  ),
                ),
                child: const Text('打开钱包详情'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开钱包详情'));
      await _settleWallet(tester);
      expect(find.widgetWithText(AppBar, '钱包详情'), findsOneWidget);

      await tester.dragFrom(const Offset(1, 300), const Offset(500, 0));
      await _settleWallet(tester);

      expect(find.text('打开钱包详情'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '钱包详情'), findsNothing);
    });

    testWidgets('冷钱包清算行入口只提示暂未上线', (tester) async {
      _disposeWidgetBeforeStores(tester);
      addTearDown(() async { await tester.pumpWidget(const SizedBox.shrink()); await _settleWallet(tester); });
      await tester.pumpWidget(Provider<CitizenSdk>.value(value: _sdk, child:
        MaterialApp(home: WalletDetailPage(wallet: _makeColdWallet(), walletName: '冷钱包', expectedRevision: BigInt.one)),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.more_vert));
      await _settleWallet(tester);
      await tester.tap(find.text('清算行'));
      await tester.pump();

      expect(find.text('暂未上线，敬请期待'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '钱包详情'), findsOneWidget);
    });

  testWidgets('原异常行验证确认与取消不新增UI，验证交SDK后释放旧快照', (tester) async {
      _disposeWidgetBeforeStores(tester);
    final id = testCitizenAccountId;
    final broken = CitizenWalletDiagnostic(walletIndex: 0, walletName: '原异常钱包', accountId: id,
      ss58Address: ss58FromAccountIdText(id), diagnosticReason: CitizenWalletDiagnosticReason.invalidSignMode,
      signMode: null, cleanupTargets: CitizenWalletCleanupTargets(accountIds: [id], deleteWalletWideKey: true));
    var current = CitizenWalletState(revision: BigInt.one, hotProfile: null, accounts: const [],
      activeWalletIndex: 0, initializationState: CitizenWalletInitializationState.ready, cleanupPending: false, diagnostics: [broken]);
    List<Object?>? fields;
    _transport.handlers['repairHotWallet'] = (value) { fields = value; current = _hotWalletSnapshot(); return [_stateTuple(current)]; };
    await tester.pumpWidget(_walletTabHost(() async => current));
    await _settleWallet(tester);
    expect(find.text('钱包数据异常，请验证热钱包或重新导入冷钱包'), findsOneWidget);
    await tester.tap(find.text('原异常钱包')); await _settleWallet(tester);
    expect(find.text('验证热钱包'), findsOneWidget);
    expect(find.text('仅当该账户私钥保存在本机时才能验证为热钱包。如果这是冷钱包，请取消并从“导入冷钱包”重新扫描同一账户。'), findsOneWidget);
    await tester.tap(find.text('取消')); await _settleWallet(tester);
    expect(fields, isNull);
    await tester.tap(find.text('原异常钱包')); await _settleWallet(tester);
    await tester.tap(find.text('验证')); await _settleWallet(tester);
    expect(fields, ['inspection-1', 0]);
    await _pumpUntil(tester, () => find.text('已验证为热钱包').evaluate().isNotEmpty);
    expect(find.text('已验证为热钱包'), findsOneWidget);
    expect(_transport.calls, contains('releaseWalletInspection'));
    expect(_transport.calls, isNot(contains('signWalletPayload')));
  });

  testWidgets('异常钱包删除使用完整SDK目标，不假造正常账户或漏掉子账户', (tester) async {
      _disposeWidgetBeforeStores(tester);
    final id = testCitizenAccountId, second = '0x${'02' * 32}';
    var current = CitizenWalletState(revision: BigInt.one, hotProfile: null, accounts: const [],
      initializationState: CitizenWalletInitializationState.ready, cleanupPending: false,
      diagnostics: [CitizenWalletDiagnostic(walletIndex: 0, walletName: '异常热钱包', accountId: id, ss58Address: null,
        diagnosticReason: CitizenWalletDiagnosticReason.invalidStructure, signMode: CitizenWalletSignMode.hot,
        cleanupTargets: CitizenWalletCleanupTargets(accountIds: [id, second], deleteWalletWideKey: true))]);
    List<Object?>? submitted;
    _transport.handlers['deleteDiagnosticWallet'] = (fields) {
      submitted = fields;
      current = CitizenWalletState(revision: BigInt.two, hotProfile: null, accounts: const [],
        initializationState: CitizenWalletInitializationState.empty, cleanupPending: false);
      return [_stateTuple(current)];
    };
    await tester.pumpWidget(_walletTabHost(() async => current)); await _settleWallet(tester);
    await tester.tap(find.byIcon(Icons.more_vert)); await _settleWallet(tester);
    await tester.tap(find.text('删除钱包')); await _settleWallet(tester);
    expect(find.text('确认删除「异常热钱包」？此操作无法撤销。'), findsOneWidget);
    await tester.tap(find.text('删除')); await _settleWallet(tester);
    expect(submitted, ['inspection-1', 0]);
    expect(_security.preparedIds, [id, second]); expect(_security.preparedWallets, {0}); expect(_security.preparedWide, isTrue);
    expect(find.text('已删除「异常热钱包」'), findsOneWidget);
    expect(_transport.calls, isNot(contains('deleteAccount')));
  });

  testWidgets('原待清理提示和重试保留，失败不报已全部处理', (tester) async {
      _disposeWidgetBeforeStores(tester);
    _security.cleanupError = const AccountSecurityException('合成清理失败');
    _transport.handlers['reconcileWalletCleanup'] = (_) => [null];
    await tester.pumpWidget(_walletTabHost(() async => _coldWalletSnapshot())); await _settleWallet(tester);
    expect(find.text('钱包事实已移除，但部分后续缓存清理尚未完成'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wallet-pending-cleanup-retry'))); await _settleWallet(tester);
    expect(find.textContaining('部分后续清理仍未完成'), findsOneWidget);
    _security.cleanupError = null;
    // 等原失败SnackBar按自身时长退场，成功提示不会被前一条队列遮住。
    await tester.pump(const Duration(seconds: 5)); await _settleWallet(tester);
    await tester.tap(find.byKey(const ValueKey('wallet-pending-cleanup-retry'))); await _settleWallet(tester);
    await _pumpUntil(tester, () => find.text('待清理缓存已全部处理').evaluate().isNotEmpty);
    expect(find.byKey(const ValueKey('wallet-pending-cleanup-banner')), findsNothing);
    expect(find.text('待清理缓存已全部处理'), findsOneWidget);
  });

  testWidgets('付款选择只提交独立SDK选择，不签名不改默认账户，返回原页面', (tester) async {
      _disposeWidgetBeforeStores(tester);
    final hot = _hotWalletSnapshot();
    final cold = _makeColdWallet(name: '选择此冷钱包', isDefault: false);
    var current = CitizenWalletState(revision: BigInt.one, hotProfile: hot.hotProfile,
      accounts: [...hot.accounts, cold], activeWalletIndex: 0,
      initializationState: CitizenWalletInitializationState.ready, cleanupPending: false);
    _snapshotLoader = () async => current;
    // setActiveWallet返回后，普通读取仍须反映同一SDK状态；不能返回上次检查前的选择。
    _transport.handlers['getWalletState'] = (_) => [_stateTuple(current)];
    List<Object?>? submitted;
    _transport.handlers['setActiveWallet'] = (fields) {
      submitted = fields;
      current = CitizenWalletState(revision: BigInt.from(2), hotProfile: hot.hotProfile,
        accounts: current.accounts, activeWalletIndex: 2,
        initializationState: CitizenWalletInitializationState.ready, cleanupPending: false);
      return [_stateTuple(current)];
    };
    bool? returned;
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<CitizenSdk>.value(value: _sdk),
      Provider<AccountSecurityService>.value(value: _security),
    Provider<CurrentUserContext>(create: (_) => _CurrentUser()),
    Provider<FinalizedIdentityResolver>(create: (_) => _Resolver()),
    Provider<SquareSessionProvider>(create: (_) => _Sessions()),
    ], child: MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { returned = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const WalletTab(selectForTrade: true))); },
      child: const Text('打开选择'),
    ))))));
    await tester.tap(find.text('打开选择'));
    await _settleWallet(tester);
    await tester.tap(find.text('选择此冷钱包'));
    await _settleWallet(tester);
    expect(submitted, ['1', 2]);
    expect(returned, isTrue);
    expect(current.defaultAccount!.accountId, hot.defaultAccount!.accountId);
    expect(current.hotProfile!.activeAccountId, hot.hotProfile!.activeAccountId);
    expect(_transport.calls, isNot(contains('beginDefaultAccountChange')));
    expect(_transport.calls, isNot(contains('reorderWalletAccountsWithoutDefaultChange')));
    final payments = OnchainPaymentService(wallet: _sdk.wallet, transactions: TestCitizenTransactions());
    expect((await payments.getCurrentWallet())!.accountId, cold.accountId);
  });

  test('交易准备失败保留SDK原始分类与阶段，不冒充广播失败', () async {
    final original = const CitizenSdkException(
      code: CitizenSdkErrorCode.decode,
      stage: CitizenSdkFailureStage.provider,
      method: 'prepareTransaction',
      message: '合成链数据解析失败',
    );
    _transport.handlers['prepareTransaction'] = (_) => throw original;
    final payments = OnchainPaymentService(
      wallet: _sdk.wallet, transactions: _sdk.transactions,
    );
    await expectLater(
      payments.prepareTransfer(OnchainPaymentDraft(
        toSs58Address: _makeColdWallet(walletIndex: 3).ss58Address,
        amount: 1,
        symbol: 'GMB',
        remark: '',
      )),
      // SDK 传输层重建异常实例；只要求 App 不改写错误分类、阶段和方法。
      throwsA(isA<CitizenSdkException>()
          .having((error) => error.code, 'code', original.code)
          .having((error) => error.stage, 'stage', original.stage)
          .having((error) => error.method, 'method', original.method)),
    );
  });

  test('非有限金额在调用SDK前作为草稿错误拒绝', () async {
    var invoked = false;
    _transport.handlers['prepareTransaction'] = (_) {
      invoked = true;
      return const <Object?>[];
    };
    final payments = OnchainPaymentService(
      wallet: _sdk.wallet, transactions: _sdk.transactions,
    );
    await expectLater(
      payments.prepareTransfer(OnchainPaymentDraft(
        toSs58Address: _makeColdWallet(walletIndex: 3).ss58Address,
        amount: double.infinity,
        symbol: 'GMB',
        remark: '',
      )),
      throwsA(isA<OnchainPaymentException>().having(
        (error) => error.code, 'code', OnchainPaymentErrorCode.invalidDraft,
      )),
    );
    expect(invoked, isFalse);
    await expectLater(
      payments.prepareTransfer(OnchainPaymentDraft(
        toSs58Address: _makeColdWallet(walletIndex: 3).ss58Address,
        amount: double.maxFinite,
        symbol: 'GMB',
        remark: '',
      )),
      throwsA(isA<OnchainPaymentException>()),
    );
    expect(invoked, isFalse);
  });


  testWidgets('付款选择修订冲突仍留原选择页，不回退默认账户变更', (tester) async {
      _disposeWidgetBeforeStores(tester);
    _transport.handlers['setActiveWallet'] = (_) => throw const CitizenSdkException(
      code: CitizenSdkErrorCode.conflict, message: '目录已变化');
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<CitizenSdk>.value(value: _sdk), Provider<AccountSecurityService>.value(value: _security),
    Provider<CurrentUserContext>(create: (_) => _CurrentUser()),
    Provider<FinalizedIdentityResolver>(create: (_) => _Resolver()),
    Provider<SquareSessionProvider>(create: (_) => _Sessions()),
    ], child: const MaterialApp(home: WalletTab(selectForTrade: true))));
    await _settleWallet(tester);
    await tester.tap(find.text('测试冷钱包'));
    await _settleWallet(tester);
    expect(find.byType(WalletTab), findsOneWidget);
    expect(find.textContaining('目录已变化'), findsOneWidget);
    expect(_transport.calls.where((method) => method == 'setActiveWallet'), hasLength(1));
    expect(_transport.calls, isNot(contains('beginDefaultAccountChange')));
  });

  testWidgets('选择列表显示独立热钱包名，不显示账户名替代', (tester) async {
      _disposeWidgetBeforeStores(tester);
    final raw = testCitizenWalletState();
    (raw[1]! as List<Object?>)[6] = '原独立钱包名';
    final state = const CitizenSdkFlutterCodec().decodeWalletState(raw);
    _snapshotLoader = () async => state;
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<CitizenSdk>.value(value: _sdk), Provider<AccountSecurityService>.value(value: _security),
    Provider<CurrentUserContext>(create: (_) => _CurrentUser()),
    Provider<FinalizedIdentityResolver>(create: (_) => _Resolver()),
    Provider<SquareSessionProvider>(create: (_) => _Sessions()),
    ], child: const MaterialApp(home: WalletTab(selectForTrade: true))));
    await _settleWallet(tester);
    expect(find.text('原独立钱包名'), findsOneWidget);
    expect(find.text(state.accounts.single.name), findsNothing);
  });

  testWidgets('原钱包改名弹窗只调用SDK钱包改名并携带显示修订', (tester) async {
      _disposeWidgetBeforeStores(tester);
    List<Object?>? submitted;
    _transport.handlers['renameWallet'] = (fields) {
      submitted = fields;
      final changed = CitizenWalletState(revision: BigInt.from(2), hotProfile: null,
        accounts: [_makeColdWallet(name: fields[2]! as String)], activeWalletIndex: 2,
        initializationState: CitizenWalletInitializationState.ready, cleanupPending: false);
      _snapshotLoader = () async => changed;
      return [_stateTuple(changed)];
    };
    await tester.pumpWidget(_walletTabHost(() async => _coldWalletSnapshot()));
    await _settleWallet(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await _settleWallet(tester);
    await tester.tap(find.text('重命名'));
    await _settleWallet(tester);
    await tester.enterText(find.byType(TextField), '新钱包名称');
    await tester.tap(find.text('保存'));
    await _settleWallet(tester);
    expect(submitted, ['1', 2, '新钱包名称']);
    expect(_transport.calls, isNot(contains('renameAccount')));
    expect(find.text('新钱包名称'), findsOneWidget);
  });

  group('「＋」入口三项菜单（添加下一个账户 / 添加指定账户 / 导入冷钱包）', () {
    testWidgets('有热钱包时三项齐全,导入冷钱包在最下', (tester) async {
      _disposeWidgetBeforeStores(tester);
      var next = false;
      var specify = false;
      var cold = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletEntryChooserSheet(
              canAddAccount: true,
              onAddNextAccount: () => next = true,
              onAddSpecifyAccount: () => specify = true,
              onImportCold: () => cold = true,
            ),
          ),
        ),
      );
      expect(find.text('添加下一个账户'), findsOneWidget);
      expect(find.text('添加指定账户'), findsOneWidget);
      expect(find.text('导入冷钱包'), findsOneWidget);
      // 不得出现热钱包创建 / 导入入口。
      expect(find.text('创建钱包'), findsNothing);
      expect(find.text('导入热钱包'), findsNothing);

      for (final subtitle in <String>[
        '在本钱包下派生下一个序号账户',
        '指定序号恢复本钱包下的特定账户',
        '仅导入公钥，私钥保留在签名设备',
      ]) {
        final text = tester.widget<Text>(find.text(subtitle));
        expect(text.style?.color, AppTheme.textTertiary);
      }

      await tester.tap(find.text('添加下一个账户'));
      await tester.tap(find.text('添加指定账户'));
      await tester.tap(find.text('导入冷钱包'));
      await tester.pump();
      expect(next && specify && cold, isTrue);
    });

    testWidgets('无热钱包时只有「导入冷钱包」', (tester) async {
      _disposeWidgetBeforeStores(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletEntryChooserSheet(
              canAddAccount: false,
              onAddNextAccount: () {},
              onAddSpecifyAccount: () {},
              onImportCold: () {},
            ),
          ),
        ),
      );
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('添加下一个账户'), findsNothing);
      expect(find.text('添加指定账户'), findsNothing);
    });

    testWidgets('WalletEmptyChoices 空态也只有「导入冷钱包」', (tester) async {
      _disposeWidgetBeforeStores(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WalletEmptyChoices(onImportCold: () {})),
        ),
      );
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('创建钱包'), findsNothing);
      expect(find.text('导入热钱包'), findsNothing);
    });
  });

  group('WalletTab 本地快照加载状态', () {
    testWidgets('首次加载中保持骨架且右上角＋禁用，不打开冷钱包伪菜单', (tester) async {
      _disposeWidgetBeforeStores(tester);
      final pending = Completer<CitizenWalletState>();
      await tester.pumpWidget(_walletTabHost(() => pending.future));
      await tester.pump();

      expect(find.byType(WalletCardSkeleton), findsNWidgets(3));
      final addButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('wallet-add-entry')),
      );
      expect(addButton.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('导入冷钱包'), findsNothing);

      pending.complete(_coldWalletSnapshot());
      await _settleWallet(tester);
    });

    testWidgets('首次失败显示重试，失败和重试加载期间＋都禁用', (tester) async {
      _disposeWidgetBeforeStores(tester);
      final retryPending = Completer<CitizenWalletState>();
      var calls = 0;
      await tester.pumpWidget(
        _walletTabHost(() {
          calls += 1;
          if (calls == 1) {
            return Future<CitizenWalletState>.error(
              StateError('首次读取失败'),
            );
          }
          return retryPending.future;
        }),
      );
      await _settleWallet(tester);

      expect(find.text('钱包加载失败'), findsOneWidget);
      expect(find.textContaining('首次读取失败'), findsOneWidget);
      expect(find.byKey(const ValueKey('wallet-initial-load-retry')),
          findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('wallet-add-entry')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byKey(const ValueKey('wallet-initial-load-retry')));
      await tester.pump();
      expect(find.byType(WalletCardSkeleton), findsNWidgets(3));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('wallet-add-entry')),
            )
            .onPressed,
        isNull,
      );

      retryPending.complete(_coldWalletSnapshot());
      await _settleWallet(tester);
      expect(find.text('钱包加载失败'), findsNothing);
      expect(find.text('测试冷钱包'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('首次成功且存在热钱包时右上角＋显示完整三项', (tester) async {
      _disposeWidgetBeforeStores(tester);
      await tester.pumpWidget(
        _walletTabHost(() async => _hotWalletSnapshot()),
      );
      await _settleWallet(tester);

      final addButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('wallet-add-entry')),
      );
      expect(addButton.onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await _settleWallet(tester);

      expect(find.text('添加下一个账户'), findsOneWidget);
      expect(find.text('添加指定账户'), findsOneWidget);
      expect(find.text('导入冷钱包'), findsOneWidget);
    });

    testWidgets('首次成功且明确无热钱包时右上角＋只显示导入冷钱包', (tester) async {
      _disposeWidgetBeforeStores(tester);
      await tester.pumpWidget(
        _walletTabHost(() async => _coldWalletSnapshot()),
      );
      await _settleWallet(tester);

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await _settleWallet(tester);
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('添加下一个账户'), findsNothing);
      expect(find.text('添加指定账户'), findsNothing);
    });

    testWidgets('已有成功数据刷新失败时保留列表和＋能力并显示重试提示', (tester) async {
      _disposeWidgetBeforeStores(tester);
      var calls = 0;
      await tester.pumpWidget(
        _walletTabHost(() {
          calls += 1;
          if (calls == 1) {
            return Future<CitizenWalletState>.value(_coldWalletSnapshot());
          }
          return Future<CitizenWalletState>.error(
            StateError('刷新读取失败'),
          );
        }),
      );
      await _settleWallet(tester);
      expect(find.text('测试冷钱包'), findsOneWidget);

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await tester.pump();
      await _settleWallet(tester);

      expect(calls, 2);
      expect(find.text('测试冷钱包'), findsOneWidget);
      expect(
        find.text('钱包刷新失败，正在显示上次成功加载的数据'),
        findsOneWidget,
      );
      expect(
          find.byKey(const ValueKey('wallet-refresh-retry')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('wallet-add-entry')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const ValueKey('wallet-add-entry')));
      await _settleWallet(tester);
      expect(find.text('导入冷钱包'), findsOneWidget);
      expect(find.text('添加下一个账户'), findsNothing);
      expect(find.text('添加指定账户'), findsNothing);
    });

    testWidgets('较新的刷新成功先完成时，较旧成功不得逆序覆盖最新快照', (tester) async {
      _disposeWidgetBeforeStores(tester);
      final olderRequest = Completer<CitizenWalletState>();
      final newerRequest = Completer<CitizenWalletState>();
      var calls = 0;
      await tester.pumpWidget(
        _walletTabHost(() {
          calls += 1;
          switch (calls) {
            case 1:
              return Future<CitizenWalletState>.value(
                _coldWalletSnapshot(name: '基线钱包'),
              );
            case 2:
              return Future<CitizenWalletState>.error(
                StateError('建立刷新失败态'),
              );
            case 3:
              return olderRequest.future;
            case 4:
              return newerRequest.future;
            default:
              return Future<CitizenWalletState>.error(
                StateError('出现非预期的第$calls次读取'),
              );
          }
        }),
      );
      await _settleWallet(tester);

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await _settleWallet(tester);
      expect(
        find.byKey(const ValueKey('wallet-refresh-retry')),
        findsOneWidget,
      );

      // 失败横幅在请求完成前保留，因此可以制造两次并发重试并按相反顺序完成。
      await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
      await tester.pump();
      expect(calls, 4);

      newerRequest.complete(_coldWalletSnapshot(name: '最新钱包'));
      await _settleWallet(tester);
      expect(find.text('最新钱包'), findsOneWidget);

      olderRequest.complete(_coldWalletSnapshot(name: '过期钱包'));
      await _settleWallet(tester);
      expect(find.text('最新钱包'), findsOneWidget);
      expect(find.text('过期钱包'), findsNothing);
      expect(
        find.byKey(const ValueKey('wallet-refresh-retry')),
        findsNothing,
      );
    });

    testWidgets('较新的刷新成功先完成时，较旧失败不得把最新快照降级', (tester) async {
      _disposeWidgetBeforeStores(tester);
      final olderRequest = Completer<CitizenWalletState>();
      final newerRequest = Completer<CitizenWalletState>();
      var calls = 0;
      await tester.pumpWidget(
        _walletTabHost(() {
          calls += 1;
          switch (calls) {
            case 1:
              return Future<CitizenWalletState>.value(
                _coldWalletSnapshot(name: '基线钱包'),
              );
            case 2:
              return Future<CitizenWalletState>.error(
                StateError('建立刷新失败态'),
              );
            case 3:
              return olderRequest.future;
            case 4:
              return newerRequest.future;
            default:
              return Future<CitizenWalletState>.error(
                StateError('出现非预期的第$calls次读取'),
              );
          }
        }),
      );
      await _settleWallet(tester);

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await _settleWallet(tester);
      await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wallet-refresh-retry')));
      await tester.pump();
      expect(calls, 4);

      newerRequest.complete(_coldWalletSnapshot(name: '最新钱包'));
      await _settleWallet(tester);
      olderRequest.completeError(StateError('过期请求失败'));
      await _settleWallet(tester);

      expect(find.text('最新钱包'), findsOneWidget);
      expect(find.text('钱包加载失败'), findsNothing);
      expect(
        find.byKey(const ValueKey('wallet-refresh-retry')),
        findsNothing,
      );
    });


  });
  group('WalletAccountTile（账户行渲染 + 冷钱包共存）', () {
    testWidgets('渲染账户名与短地址', (tester) async {
      _disposeWidgetBeforeStores(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(),
              onTap: () {},
              onScan: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('账户1'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      // 长 SS58 固定展示首 10 位与末 8 位，中间严格为 6 个 ASCII 句点。
      expect(find.text('w5Bc7ma8qU......Q86xBWrT'), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
    });

    testWidgets('点击账户行触发 onTap', (tester) async {
      _disposeWidgetBeforeStores(tester);
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(),
              onTap: () => tapped = true,
              onScan: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('账户1'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('默认紧邻账户名称右上侧且不改变卡片高度', (tester) async {
      _disposeWidgetBeforeStores(tester);
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const longName = '这是一个需要在窄屏省略的很长账户名称';
      Future<double> pumpDefaultTile(bool isDefault) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WalletAccountTile(
                account: _makeAccount(name: longName),
                isIdentity: true,
                isDefault: isDefault,
                onTap: () {},
                onScan: () {},
                onRename: () {},
                onDelete: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.getSize(find.byType(WalletAccountTile)).height;
      }

      final normalHeight = await pumpDefaultTile(false);
      final defaultHeight = await pumpDefaultTile(true);

      expect(defaultHeight, normalHeight);
      expect(find.text('默认'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);

      final labelRect = tester.getRect(find.text('默认'));
      final nameRect = tester.getRect(find.text(longName));
      expect(labelRect.left, greaterThan(nameRect.right));
      expect(labelRect.center.dy, lessThan(nameRect.center.dy));
      expect(tester.takeException(), isNull);

      final address = tester.widget<Text>(find.textContaining('......'));
      expect(address.maxLines, 1);
      expect(address.overflow, TextOverflow.ellipsis);
    });

    testWidgets('扫一扫是三点菜单第一项且只触发当前账户扫码', (tester) async {
      _disposeWidgetBeforeStores(tester);
      var scanned = false;
      var cardTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(),
              onTap: () => cardTapped = true,
              onScan: () => scanned = true,
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      final menu = find.byTooltip('账户操作');
      expect(menu, findsOneWidget);
      // 卡片行内不再保留独立扫码按钮。
      expect(find.byTooltip('扫码签名'), findsNothing);
      expect(find.text('扫一扫'), findsNothing);

      await tester.tap(menu);
      await _settleWallet(tester);
      final scan = find.text('扫一扫');
      final rename = find.text('重命名');
      expect(scan, findsOneWidget);
      expect(tester.getCenter(scan).dy, lessThan(tester.getCenter(rename).dy));

      await tester.tap(scan);
      await _settleWallet(tester);
      expect(scanned, isTrue);
      expect(cardTapped, isFalse);
    });

    testWidgets('账户0菜单为扫一扫/重命名/删除钱包且不再显示账户详情', (tester) async {
      _disposeWidgetBeforeStores(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(index: 0, name: '账户0'),
              onTap: () {},
              onScan: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('账户操作'));
      await _settleWallet(tester);
      expect(find.text('扫一扫'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('账户详情'), findsNothing);
      expect(find.text('删除钱包'), findsOneWidget);
      expect(find.text('删除账户'), findsNothing);
    });

    testWidgets('非0账户菜单显示删除账户而不是删除钱包', (tester) async {
      _disposeWidgetBeforeStores(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WalletAccountTile(
              account: _makeAccount(index: 5, name: '账户5'),
              onTap: () {},
              onScan: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('账户操作'));
      await _settleWallet(tester);
      expect(find.text('删除账户'), findsOneWidget);
      expect(find.text('删除钱包'), findsNothing);
    });

    testWidgets('账户行与冷钱包行可在同一列表共存', (tester) async {
      _disposeWidgetBeforeStores(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                WalletAccountTile(
                  account: _makeAccount(index: 0, name: '账户0'),
                  onTap: () {},
                  onScan: () {},
                  onRename: () {},
                  onDelete: () {},
                ),
                WalletListTile(
                  wallet: _makeColdWallet(name: '我的冷钱包'),
                  walletName: '我的冷钱包',
                  balance: 0,
                  showActions: true,
                  onTap: () {},
                  onRename: () {},
                  onDelete: () {},
                ),
              ],
            ),
          ),
        ),
      );
      // 热钱包账户行与冷钱包行同列出现。
      expect(find.text('账户0'), findsOneWidget);
      expect(find.text('我的冷钱包'), findsOneWidget);
    });
  });


  testWidgets('冷钱包重命名保留原钱包标题与提示，取消不提交SDK', (tester) async {
      _disposeWidgetBeforeStores(tester);
    await tester.pumpWidget(_walletTabHost(() async => _coldWalletSnapshot()));
    await _settleWallet(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await _settleWallet(tester);
    await tester.tap(find.text('重命名'));
    await _settleWallet(tester);
    expect(find.text('重命名钱包'), findsOneWidget);
    expect(find.text('重命名账户'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).decoration?.hintText, '输入新的钱包名称');
    await tester.tap(find.text('取消'));
    await _settleWallet(tester);
    expect(_transport.calls, isNot(contains('renameAccount')));
  });

  testWidgets('SDK目录失败保持原重试页，不能伪装空钱包或开放菜单', (tester) async {
      _disposeWidgetBeforeStores(tester);
    await tester.pumpWidget(_walletTabHost(() => Future.error(
      const CitizenSdkException(code: CitizenSdkErrorCode.integrity, message: '合成目录不一致'),
    )));
    await _settleWallet(tester);
    expect(find.text('钱包加载失败'), findsOneWidget);
    expect(find.byType(WalletEmptyChoices), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('wallet-add-entry'))).onPressed, isNull);
  });

  testWidgets('操作禁用保留原卡片，菜单不能触发第二条交互', (tester) async {
      _disposeWidgetBeforeStores(tester);
    var actions = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WalletAccountTile(
      account: _makeAccount(), actionsEnabled: false, onTap: () {},
      onScan: () { actions++; }, onRename: () { actions++; }, onDelete: () { actions++; },
    ))));
    await tester.tap(find.byTooltip('账户操作'));
    await _settleWallet(tester);
    expect(find.text('扫一扫'), findsNothing);
    expect(find.text('重命名'), findsNothing);
    expect(actions, 0);
  });
}
