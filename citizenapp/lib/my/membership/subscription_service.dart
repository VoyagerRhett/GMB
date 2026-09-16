import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/my/membership/membership_revision.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/my/membership/subscription_chain.dart';
import 'package:citizenapp/security/device_subkey.dart' show hexToBytes;
import 'package:citizenapp/isar/wallet_isar.dart';

class SubscriptionException implements Exception {
  const SubscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 会员页持久化展示快照：只缓存 CitizenServe 已确认的订阅态与三档链上价格。
///
/// 套餐名称和权益不进入缓存，始终使用 App 内置静态定义；订阅或支付动作仍在提交前
/// 使用 CitizenServe D1 鉴权并由链上交易最终执行，展示缓存不构成服务端授权真源。
class MembershipDisplaySnapshot {
  const MembershipDisplaySnapshot({
    required this.state,
    required this.prices,
    required this.subscriptionFetchedAtMs,
    required this.pricesFetchedAtMs,
  });

  final SquareMembershipState state;
  final Map<String, int> prices;
  final int subscriptionFetchedAtMs;
  final int pricesFetchedAtMs;

  MembershipDisplayDecision get decision {
    return state.active
        ? MembershipDisplayDecision.activeConfirmed
        : MembershipDisplayDecision.inactiveConfirmed;
  }

  bool pricesAreFresh(int nowMs, Duration ttl) =>
      pricesFetchedAtMs > 0 &&
      nowMs >= pricesFetchedAtMs &&
      nowMs - pricesFetchedAtMs <= ttl.inMilliseconds;
}

/// 平台会员订阅编排：在「我的 → 会员」页订阅 / 取消平台会员（自由/民主/薪火）。
///
/// 用户签名订阅、取消和换档；首次扣款、真实公历到期时间与后续自动扣款由 runtime
/// 根据共识时间戳完成。CitizenApp 不提交续费或周期确认。
class SubscriptionService {
  SubscriptionService({
    required CitizenSdkWallet wallet,
    required CitizenChain chain,
    required CitizenTransactions transactions,
    required FinalizedIdentityResolver identityResolver,
    required SquareSessionProvider sessionProvider,
    SubscriptionChain? subscriptionChain,
    SquareApiClient? api,
  }) : _subscriptionChain =
           subscriptionChain ??
           SubscriptionChain(chain: chain, transactions: transactions),
       _wallet = wallet,
       _identityResolver = identityResolver,
       _session = sessionProvider,
       _api = api ?? SquareApiClient() {
    // App/会员服务重新建立时主动恢复 finalized 待同步交易；失败仍留在原 tx_hash 队列，
    // 后续状态刷新再次重试，不把恢复职责塞进广场发布流程。
    unawaited(
      _retryPendingMirrorsForCurrentSession().catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        // 构造期恢复是后台收敛，不得把暂时关闭的本地库等错误泄漏成未处理异常；
        // 原 tx_hash 队列保持不变，下一次状态刷新仍会重试。
        debugPrint(
          '[Membership] pending mirror recovery deferred: $error\n$stackTrace',
        );
      }),
    );
  }

  final SubscriptionChain _subscriptionChain;
  final CitizenSdkWallet _wallet;
  final FinalizedIdentityResolver _identityResolver;
  final SquareSessionProvider _session;
  final SquareApiClient _api;

  bool _mirrorSyncPending = false;

  /// 全 App 按 CID 共享一份内存会员快照；WalletIsar 只是跨进程重启的持久化副本。
  static final Map<String, MembershipDisplaySnapshot> _memorySnapshots =
      <String, MembershipDisplaySnapshot>{};

  /// 同一 CitizenServe 登录会话只执行一次会员鉴权读取；页面之间复用同一个 Future。
  static final Map<String, _MembershipAuthorization> _authorizations =
      <String, _MembershipAuthorization>{};

  /// 聊天等会员消费者只读本次 CitizenServe 会话已经确认的会员事实。
  /// 该状态属于会员模块；聊天模块不得保存 CID、会员档或附件权益副本。
  static final Map<String, int> _authorizedChatFileMaxBytes = <String, int>{};
  static String? _currentAuthorizedCidNumber;

  static bool membershipResolvedFor(String cidNumber) =>
      _memorySnapshots.containsKey(cidNumber.trim());

  static bool chatAuthorizationResolvedFor(String cidNumber) =>
      _authorizedChatFileMaxBytes.containsKey(cidNumber.trim());

  static bool chatAuthorizedFor(String cidNumber) =>
      chatFileMaxBytesFor(cidNumber) > 0;

  static int chatFileMaxBytesFor(String cidNumber) =>
      _authorizedChatFileMaxBytes[cidNumber.trim()] ?? 0;

  static int get currentChatFileMaxBytes {
    final cidNumber = _currentAuthorizedCidNumber;
    return cidNumber == null ? 0 : chatFileMaxBytesFor(cidNumber);
  }

  static String get currentChatFileSizeLabel {
    final cidNumber = _currentAuthorizedCidNumber;
    return cidNumber == null ? '0MB' : chatFileSizeLabelFor(cidNumber);
  }

  static String chatFileSizeLabelFor(String cidNumber) =>
      _chatFileSizeLabel(chatFileMaxBytesFor(cidNumber));

  static void markChatAuthorizationUnavailable(String cidNumber) {
    final normalized = cidNumber.trim();
    _currentAuthorizedCidNumber = normalized;
    _authorizedChatFileMaxBytes.remove(normalized);
  }

  static void _rememberChatAuthorization(
    String cidNumber,
    SquareMembershipState state,
  ) {
    final normalized = cidNumber.trim();
    _currentAuthorizedCidNumber = normalized;
    _authorizedChatFileMaxBytes[normalized] =
        state.activePlan?.chatFileMaxBytes ?? 0;
  }

  @visibleForTesting
  static void setChatAuthorizationForTesting(
    String cidNumber,
    int? chatFileMaxBytes,
  ) {
    final normalized = cidNumber.trim();
    _memorySnapshots.remove(normalized);
    _authorizedChatFileMaxBytes.remove(normalized);
    _currentAuthorizedCidNumber = normalized;
    if (chatFileMaxBytes == null) return;
    final state = SquareMembershipState(
      active: chatFileMaxBytes > 0,
      paidUntil: 1,
      membershipLevel: chatFileMaxBytes > 0 ? 'test' : null,
    );
    _memorySnapshots[normalized] = MembershipDisplaySnapshot(
      state: state,
      prices: const <String, int>{},
      subscriptionFetchedAtMs: 1,
      pricesFetchedAtMs: 1,
    );
    _authorizedChatFileMaxBytes[normalized] = chatFileMaxBytes;
  }

  static String _chatFileSizeLabel(int bytes) {
    const mib = 1024 * 1024;
    if (bytes >= 1024 * mib) {
      final gib = bytes / (1024 * mib);
      return gib == gib.roundToDouble()
          ? '${gib.round()}GB'
          : '${gib.toStringAsFixed(1)}GB';
    }
    return '${(bytes / mib).round()}MB';
  }

  /// 最近一次平台订阅动作已经 finalized，但 Worker 镜像仍等待确认。
  ///
  /// 该状态只供会员页显示同步提示；会员资格以 CitizenServe D1 与本机统一缓存为准。
  bool get mirrorSyncPending => _mirrorSyncPending;

  /// 身份鉴权后的唯一会员读取入口。同一会话内会员页、我的、聊天、创作者和发布共用结果，
  /// 只有显式鉴权动作或用户手动刷新才允许 [forceRefresh] 再读 CitizenServe。
  Future<SquareMembershipState> authorizeMembership(
    SquareSession session, {
    bool forceRefresh = false,
  }) async {
    final cidNumber = session.cidNumber.trim();
    if (cidNumber.isEmpty) {
      throw const SubscriptionException('当前会话缺少公民 CID');
    }
    final key = _authorizationKey(session);
    final existing = _authorizations[cidNumber];
    if (!forceRefresh && existing?.key == key) return existing!.state;

    final state = _fetchAndRememberMembership(session);
    final authorization = _MembershipAuthorization(key, state);
    _authorizations[cidNumber] = authorization;
    try {
      return await state;
    } on Object {
      if (identical(_authorizations[cidNumber], authorization)) {
        _authorizations.remove(cidNumber);
      }
      rethrow;
    }
  }

  Future<SquareMembershipState> _fetchAndRememberMembership(
    SquareSession session,
  ) async {
    final state = await _api.fetchMembership(session);
    await _rememberServerState(session, state);
    _rememberChatAuthorization(session.cidNumber, state);
    return state;
  }

  String _authorizationKey(SquareSession session) =>
      '${session.accountId}:${session.bindingRevision}:${session.expiresAt}';

  String _displaySnapshotKey(String cidNumber) =>
      'platform_membership_display_snapshot:$cidNumber';

  /// 读取当前账户上一次成功同步的展示快照；损坏缓存只忽略展示，读取路径不删除事实。
  Future<MembershipDisplaySnapshot?> readDisplaySnapshot(
    String cidNumber,
  ) async {
    final normalized = cidNumber.trim();
    if (normalized.isEmpty) return null;
    final memory = _memorySnapshots[normalized];
    if (memory != null) return _rememberInMemory(normalized, memory);
    final key = _displaySnapshotKey(normalized);
    final raw = await _readState(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final pricesRaw = decoded['prices'];
      final prices = <String, int>{};
      if (pricesRaw is Map<String, dynamic>) {
        for (final level in const ['freedom', 'democracy', 'spark']) {
          final value = pricesRaw[level];
          if (value is int && value >= 0) prices[level] = value;
        }
      }
      final membershipLevel = decoded['membership_level'];
      final subscriptionStatus = decoded['subscription_status'];
      final snapshot = MembershipDisplaySnapshot(
        state: SquareMembershipState(
          active: decoded['active'] == true,
          paidUntil: decoded['paid_until'] is int
              ? decoded['paid_until'] as int
              : 0,
          membershipLevel: membershipLevel is String ? membershipLevel : null,
          subscriptionStatus: subscriptionStatus is String
              ? subscriptionStatus
              : null,
          subscriptionActive: decoded['subscription_active'] == true,
          lastChargedAt: decoded['last_charged_at'] is int
              ? decoded['last_charged_at'] as int
              : 0,
        ),
        prices: prices,
        subscriptionFetchedAtMs: decoded['subscription_fetched_at_ms'] is int
            ? decoded['subscription_fetched_at_ms'] as int
            : 0,
        pricesFetchedAtMs: decoded['prices_fetched_at_ms'] is int
            ? decoded['prices_fetched_at_ms'] as int
            : 0,
      );
      return _rememberInMemory(normalized, snapshot, notify: false);
    } on FormatException {
      // 损坏展示快照不参与授权；读取路径保留事实供显式诊断。
      return null;
    }
  }

  /// 原子覆盖当前账户展示快照；调用方只在对应链读成功后推进该部分时间戳。
  Future<void> writeDisplaySnapshot(
    String cidNumber,
    MembershipDisplaySnapshot snapshot,
  ) async {
    final normalized = cidNumber.trim();
    if (normalized.isEmpty) return;
    final effective = _rememberInMemory(normalized, snapshot);
    await _writeState(
      _displaySnapshotKey(normalized),
      jsonEncode({
        'active': effective.state.active,
        'paid_until': effective.state.paidUntil,
        'membership_level': effective.state.membershipLevel,
        'subscription_status': effective.state.subscriptionStatus,
        'subscription_active': effective.state.subscriptionActive,
        'last_charged_at': effective.state.lastChargedAt,
        'prices': effective.prices,
        'subscription_fetched_at_ms': effective.subscriptionFetchedAtMs,
        'prices_fetched_at_ms': effective.pricesFetchedAtMs,
      }),
    );
  }

  MembershipDisplaySnapshot _rememberInMemory(
    String cidNumber,
    MembershipDisplaySnapshot snapshot, {
    bool notify = true,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = snapshot.state;
    final effectiveState =
        state.active && (state.paidUntil <= 0 || now >= state.paidUntil)
        ? SquareMembershipState(
            active: false,
            paidUntil: state.paidUntil,
            membershipLevel: state.membershipLevel,
            subscriptionStatus: state.subscriptionStatus,
            subscriptionActive: false,
            lastChargedAt: state.lastChargedAt,
            plans: state.plans,
            usageState: state.usageState,
          )
        : state;
    final effective = identical(effectiveState, state)
        ? snapshot
        : MembershipDisplaySnapshot(
            state: effectiveState,
            prices: snapshot.prices,
            subscriptionFetchedAtMs: snapshot.subscriptionFetchedAtMs,
            pricesFetchedAtMs: snapshot.pricesFetchedAtMs,
          );
    final previous = _memorySnapshots[cidNumber];
    _memorySnapshots[cidNumber] = effective;
    if (notify && !_sameMembership(previous?.state, effective.state)) {
      MembershipRevision.instance.notifyChanged(cidNumber);
    }
    return effective;
  }

  bool _sameMembership(
    SquareMembershipState? left,
    SquareMembershipState right,
  ) =>
      left?.active == right.active &&
      left?.paidUntil == right.paidUntil &&
      left?.membershipLevel == right.membershipLevel &&
      left?.subscriptionStatus == right.subscriptionStatus &&
      left?.subscriptionActive == right.subscriptionActive &&
      left?.lastChargedAt == right.lastChargedAt;

  Future<void> _rememberServerState(
    SquareSession session,
    SquareMembershipState state,
  ) async {
    final previous = await readDisplaySnapshot(session.cidNumber);
    final snapshot = MembershipDisplaySnapshot(
      state: state,
      prices: previous?.prices ?? const <String, int>{},
      subscriptionFetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      pricesFetchedAtMs: previous?.pricesFetchedAtMs ?? 0,
    );
    try {
      await writeDisplaySnapshot(session.cidNumber, snapshot);
    } on Object {
      // 内存快照已经原子推进；磁盘失败不允许撤销服务端鉴权成功事实。
    }
  }

  /// 订阅平台会员某档（level=freedom/democracy/spark）。
  Future<void> subscribe(
    String level,
    int expectedPriceFen, {
    BuildContext? context,
  }) async {
    final identity = await _requireIdentity();
    await _requireSigningAccount(identity.accountId);
    final cidNumber = identity.snapshot!.cidNumber;
    try {
      final result = await _subscriptionChain.subscribePlatform(
        signerPublicKey: Uint8List.fromList(hexToBytes(identity.accountId)),
        level: level,
        expectedPriceFen: BigInt.from(expectedPriceFen),
        externalSigning: (pending) => _showExternalSigning(context, pending),
      );
      await _confirm(
        subscriberCidNumber: cidNumber,
        txHash: result.txHash,
        blockHashHex: result.blockHashHex,
      );
    } on Exception catch (e) {
      throw SubscriptionException('订阅失败：$e');
    }
  }

  /// 取消平台会员（撤销按月扣款授权）。
  Future<void> cancel({BuildContext? context}) async {
    final identity = await _requireIdentity();
    await _requireSigningAccount(identity.accountId);
    final cidNumber = identity.snapshot!.cidNumber;
    try {
      final result = await _subscriptionChain.cancelPlatform(
        signerPublicKey: Uint8List.fromList(hexToBytes(identity.accountId)),
        externalSigning: (pending) => _showExternalSigning(context, pending),
      );
      await _confirm(
        subscriberCidNumber: cidNumber,
        txHash: result.txHash,
        blockHashHex: result.blockHashHex,
      );
    } on Exception catch (e) {
      throw SubscriptionException('取消失败：$e');
    }
  }

  /// 更换平台会员档。当前已付周期内仅登记待切换档位，具体生效时间由 runtime 决定。
  Future<void> changePlan(
    String level,
    int expectedPriceFen, {
    BuildContext? context,
  }) async {
    final identity = await _requireIdentity();
    await _requireSigningAccount(identity.accountId);
    final cidNumber = identity.snapshot!.cidNumber;
    try {
      final result = await _subscriptionChain.changePlatformPlan(
        signerPublicKey: Uint8List.fromList(hexToBytes(identity.accountId)),
        level: level,
        expectedPriceFen: BigInt.from(expectedPriceFen),
        externalSigning: (pending) => _showExternalSigning(context, pending),
      );
      await _confirm(
        subscriberCidNumber: cidNumber,
        txHash: result.txHash,
        blockHashHex: result.blockHashHex,
      );
    } on Exception catch (e) {
      throw SubscriptionException('更换订阅失败：$e');
    }
  }

  Future<CitizenWalletStateAccount> _requireSigningAccount(
    String accountId,
  ) async {
    final account = (await _wallet.getState()).defaultAccount;
    if (account == null || account.accountId != accountId) {
      throw const SubscriptionException('当前身份与默认钱包账户不一致，已拒绝签名');
    }
    return account;
  }

  Future<String?> _showExternalSigning(
    BuildContext? context,
    CitizenTransactionExternalSigningPending pending,
  ) {
    if (context == null || !context.mounted) return Future<String?>.value();
    return showCitizenSdkQrResponse(
      context,
      request: pending.qrRequest,
      expiresAt: BigInt.from(pending.expiresAt.millisecondsSinceEpoch ~/ 1000),
    );
  }

  /// 当前默认账户经 finalized 闭环验证后，才可成为链上订阅交易签名者。
  Future<FinalizedIdentity> _requireIdentity() async {
    final identity = await _identityResolver.resolve();
    if (identity == null || !identity.isRegistered) {
      throw const SubscriptionException('请先注册并绑定公民 CID');
    }
    return identity;
  }

  String _pendingKey(String subscriberCidNumber) =>
      'platform_subscription_mirror_pending_by_cid:$subscriberCidNumber';

  /// finalized 定位按永久 CID 落本地，只保存 tx_hash 与 block_hash。HTTP 失败只重试
  /// 同一链上交易确认，不再签名，也不根据旧 D1 状态猜测同步成功。
  Future<void> _confirm({
    required String subscriberCidNumber,
    required String txHash,
    required String blockHashHex,
  }) async {
    final proof = <String, dynamic>{
      'tx_hash': txHash,
      'block_hash': blockHashHex,
    };
    try {
      await _storeLocalProof(subscriberCidNumber, proof);
    } on Exception {
      // 链上已 finalized；本地缓存异常不能让用户重新签名。
    }
    _mirrorSyncPending = !await _syncProof(
      subscriberCidNumber: subscriberCidNumber,
      proof: proof,
    );
  }

  Future<void> _retryPendingMirrorsForCurrentSession() async {
    try {
      final session = await _session.ensureSession();
      if (session == null) return;
      final subscriberCidNumber = session.cidNumber;
      final pending = await _readList(_pendingKey(subscriberCidNumber));
      for (final proof in List<Map<String, dynamic>>.from(pending)) {
        await _syncProof(
          subscriberCidNumber: subscriberCidNumber,
          proof: proof,
        );
      }
      _mirrorSyncPending = (await _readList(_pendingKey(subscriberCidNumber)))
          .isNotEmpty;
    } on Exception {
      // 保留未完成证明；链上订阅与自动续费不依赖 Cloudflare。
    }
  }

  /// 用已 finalized 的交易证明推进 Worker 会员记录；失败只保留本地证明并重试，
  /// 发布与资料读取不承担链上重建职责，也不产生第二次签名。
  Future<bool> _syncProof({
    required String subscriberCidNumber,
    required Map<String, dynamic> proof,
  }) async {
    final txHash = proof['tx_hash'];
    final blockHashHex = proof['block_hash'];
    if (txHash is! String || blockHashHex is! String) {
      return false;
    }

    final SquareSession? session;
    try {
      session = await _session.ensureSession();
    } on Exception {
      return false;
    }
    if (session == null ||
        session.cidNumber.trim() != subscriberCidNumber.trim()) {
      return false;
    }

    try {
      final confirmed = await _api.confirmPlatformSubscription(
        session: session,
        txHash: txHash,
        blockHashHex: blockHashHex,
      );
      await _rememberServerState(session, confirmed);
      _rememberChatAuthorization(session.cidNumber, confirmed);
      _authorizations[subscriberCidNumber] = _MembershipAuthorization(
        _authorizationKey(session),
        Future<SquareMembershipState>.value(confirmed),
      );
    } on Exception {
      return false;
    }

    try {
      await _removePendingProof(subscriberCidNumber, txHash);
    } on Exception {
      // Worker 镜像已经确认；本地删除失败只会导致后续幂等重试，不能撤销成功事实。
    }
    return true;
  }

  Future<void> _storeLocalProof(
    String subscriberCidNumber,
    Map<String, dynamic> proof,
  ) async {
    final pending = await _readList(_pendingKey(subscriberCidNumber));
    pending.removeWhere((item) => item['tx_hash'] == proof['tx_hash']);
    pending.add(proof);
    await _writeState(_pendingKey(subscriberCidNumber), jsonEncode(pending));

    final historyKey = 'subscription_tx_history_by_cid:$subscriberCidNumber';
    final history = await _readList(historyKey);
    history.removeWhere((item) => item['tx_hash'] == proof['tx_hash']);
    history.add(proof);
    if (history.length > 50) history.removeRange(0, history.length - 50);
    await _writeState(historyKey, jsonEncode(history));
  }

  Future<void> _removePendingProof(
    String subscriberCidNumber,
    String txHash,
  ) async {
    final pending = await _readList(_pendingKey(subscriberCidNumber));
    pending.removeWhere((item) => item['tx_hash'] == txHash);
    if (pending.isEmpty) {
      await _deleteState(_pendingKey(subscriberCidNumber));
    } else {
      await _writeState(_pendingKey(subscriberCidNumber), jsonEncode(pending));
    }
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final raw = await _readState(key);
    if (raw == null) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded.whereType<Map<String, dynamic>>().toList(growable: true)
        : <Map<String, dynamic>>[];
  }

  Future<String?> _readState(String key) => WalletIsar.instance.read(
    (isar) async =>
        (await isar.walletMembershipStateEntitys.getByStateKey(key))
            ?.payloadJson,
  );

  Future<void> _writeState(String key, String payloadJson) =>
      WalletIsar.instance.writeTxn((isar) async {
        final row =
            await isar.walletMembershipStateEntitys.getByStateKey(key) ??
            WalletMembershipStateEntity();
        row
          ..stateKey = key
          ..payloadJson = payloadJson;
        await isar.walletMembershipStateEntitys.put(row);
      });

  Future<void> _deleteState(String key) =>
      WalletIsar.instance.writeTxn((isar) async {
        await isar.walletMembershipStateEntitys.deleteByStateKey(key);
      });
}

enum MembershipDisplayDecision { activeConfirmed, inactiveConfirmed }

class _MembershipAuthorization {
  const _MembershipAuthorization(this.key, this.state);

  final String key;
  final Future<SquareMembershipState> state;
}
