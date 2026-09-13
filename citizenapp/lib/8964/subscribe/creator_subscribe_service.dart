import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/services/square_api_client.dart'
    show SquareSession;
import 'package:citizenapp/my/creator/creator_api.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/my/membership/subscription_chain.dart';
import 'package:citizenapp/security/device_subkey.dart' show hexToBytes;
import 'package:shared_preferences/shared_preferences.dart';

class CreatorSubscribeException implements Exception {
  const CreatorSubscribeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 订阅者侧编排：在他人主页订阅 / 取消订阅创作者会员。
///
/// 用户只为订阅、取消和换档签名；首次扣款、真实公历到期时间与后续自动扣款由
/// runtime 根据共识时间戳完成，CitizenApp 不提交续费或周期确认。
class CreatorSubscribeService {
  CreatorSubscribeService({
    required CitizenSdkWallet wallet,
    required CitizenChain chain,
    required CitizenTransactions transactions,
    required FinalizedIdentityResolver identityResolver,
    required SquareSessionProvider sessionProvider,
    SubscriptionChain? subscriptionChain,
    CreatorApi? api,
    SharedPreferences? preferences,
  }) : _subscriptionChain = subscriptionChain ??
           SubscriptionChain(chain: chain, transactions: transactions),
       _wallet = wallet,
       _identityResolver = identityResolver,
       _session = sessionProvider,
       _api = api ?? CreatorApiHttp(),
       _preferences = preferences {
    unawaited(_retryPendingMirrors());
  }

  final SubscriptionChain _subscriptionChain;
  final CitizenSdkWallet _wallet;
  final FinalizedIdentityResolver _identityResolver;
  final SquareSessionProvider _session;
  final CreatorApi _api;
  final SharedPreferences? _preferences;

  Future<CreatorView> fetchView(
    SquareSession session,
    String creatorCidNumber,
  ) async {
    await _retryPendingMirrors();
    return _api.fetchViewOf(session, creatorCidNumber);
  }

  /// 订阅创作者某档某周期（priceFen=该档该周期价，分）。
  Future<void> subscribe({
    BuildContext? context,
    required String creatorCidNumber,
    required String tierId,
    required String period,
    required int priceFen,
  }) async {
    final identity = await _requireIdentity();
    await _requireSigningAccount(identity.accountId);
    final session = await _requireCurrentSession(identity.accountId);
    if (session.cidNumber == creatorCidNumber) {
      throw const CreatorSubscribeException('不能订阅自己');
    }
    try {
      final result = await _subscriptionChain.subscribeCreator(
        signerPublicKey: Uint8List.fromList(hexToBytes(identity.accountId)),
        creatorCidNumber: creatorCidNumber,
        tierId: tierId,
        billingPeriod: period,
        expectedPriceFen: BigInt.from(priceFen),
        externalSigning: (pending) => _showExternalSigning(context, pending),
      );
      await _confirm(
        subscriberCidNumber: session.cidNumber,
        txHash: result.txHash,
        blockHashHex: result.blockHashHex,
      );
    } on Exception catch (e) {
      throw CreatorSubscribeException('订阅失败：$e');
    }
  }

  /// 取消对某创作者的订阅（撤销按月扣款授权）。
  Future<void> cancel({
    BuildContext? context,
    required String creatorCidNumber,
  }) async {
    final identity = await _requireIdentity();
    await _requireSigningAccount(identity.accountId);
    final session = await _requireCurrentSession(identity.accountId);
    try {
      final result = await _subscriptionChain.cancelCreator(
        signerPublicKey: Uint8List.fromList(hexToBytes(identity.accountId)),
        creatorCidNumber: creatorCidNumber,
        externalSigning: (pending) => _showExternalSigning(context, pending),
      );
      await _confirm(
        subscriberCidNumber: session.cidNumber,
        txHash: result.txHash,
        blockHashHex: result.blockHashHex,
      );
    } on Exception catch (e) {
      throw CreatorSubscribeException('取消失败：$e');
    }
  }

  /// 更换创作者档位或周期；同一换档业务只提交这一笔账户签名交易。
  Future<void> changePlan({
    BuildContext? context,
    required String creatorCidNumber,
    required String tierId,
    required String period,
    required int priceFen,
  }) async {
    final identity = await _requireIdentity();
    await _requireSigningAccount(identity.accountId);
    final session = await _requireCurrentSession(identity.accountId);
    if (session.cidNumber == creatorCidNumber) {
      throw const CreatorSubscribeException('不能订阅自己');
    }
    try {
      final result = await _subscriptionChain.changeCreatorPlan(
        signerPublicKey: Uint8List.fromList(hexToBytes(identity.accountId)),
        creatorCidNumber: creatorCidNumber,
        tierId: tierId,
        billingPeriod: period,
        expectedPriceFen: BigInt.from(priceFen),
        externalSigning: (pending) => _showExternalSigning(context, pending),
      );
      await _confirm(
        subscriberCidNumber: session.cidNumber,
        txHash: result.txHash,
        blockHashHex: result.blockHashHex,
      );
    } on Exception catch (e) {
      throw CreatorSubscribeException('更换订阅失败：$e');
    }
  }

  Future<CitizenWalletStateAccount> _requireSigningAccount(
    String accountId,
  ) async {
    final account = (await _wallet.getState()).defaultAccount;
    if (account == null || account.accountId != accountId) {
      throw const CreatorSubscribeException('当前身份与默认钱包账户不一致，已拒绝签名');
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
      expiresAt: BigInt.from(
        pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }

  /// 当前默认账户经 finalized 闭环验证后，才可成为创作者订阅交易签名者。
  /// 待提交证明归属永久 CID，账户只记录当时的签名与付款事实；自订阅拦截也按
  /// 不可换绑的 CID 比对。
  Future<FinalizedIdentity> _requireIdentity() async {
    final identity = await _identityResolver.resolve();
    if (identity == null || !identity.isRegistered) {
      throw const CreatorSubscribeException('请先注册并绑定公民 CID');
    }
    return identity;
  }

  Future<SquareSession> _requireCurrentSession(String accountId) async {
    final session = await _session.ensureSession();
    if (session == null || session.accountId != accountId) {
      throw const CreatorSubscribeException('当前会话与默认钱包账户不一致，请重新登录');
    }
    return session;
  }

  Future<SharedPreferences> get _prefs async {
    final preferences = _preferences;
    if (preferences != null) return preferences;
    return SharedPreferences.getInstance();
  }

  String _pendingKey(String subscriberCidNumber) =>
      'creator_subscription_mirror_pending_by_cid:$subscriberCidNumber';

  /// finalized 回执按订阅者永久 CID 持久化；签名账户只作为交易事实保留。
  /// HTTP 失败只重放同一交易证明，不要求第二次签名。
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
      // 链上已 finalized；本地缓存异常不得转化为重新签名。
    }
    try {
      final session = await _session.ensureSession();
      if (session == null || session.cidNumber != subscriberCidNumber) return;
      await _api.confirmCreatorSubscription(
        session: session,
        txHash: txHash,
        blockHashHex: blockHashHex,
      );
      await _removePendingProof(subscriberCidNumber, txHash);
    } on Exception {
      // 保留证明，下次进入创作者订阅页仅重试 HTTP。
    }
  }

  Future<void> _retryPendingMirrors() async {
    try {
      final session = await _session.ensureSession();
      if (session == null) return;
      final subscriberCidNumber = session.cidNumber;
      final pending = await _readList(_pendingKey(subscriberCidNumber));
      for (final proof in List<Map<String, dynamic>>.from(pending)) {
        final txHash = proof['tx_hash'];
        final blockHashHex = proof['block_hash'];
        if (txHash is! String || blockHashHex is! String) {
          continue;
        }
        await _api.confirmCreatorSubscription(
          session: session,
          txHash: txHash,
          blockHashHex: blockHashHex,
        );
        await _removePendingProof(subscriberCidNumber, txHash);
      }
    } on Exception {
      // Cloudflare 不可用不影响链上自动续费，证明继续保留。
    }
  }

  Future<void> _storeLocalProof(
    String subscriberCidNumber,
    Map<String, dynamic> proof,
  ) async {
    final pending = await _readList(_pendingKey(subscriberCidNumber));
    pending.removeWhere((item) => item['tx_hash'] == proof['tx_hash']);
    pending.add(proof);
    await (await _prefs).setString(
      _pendingKey(subscriberCidNumber),
      jsonEncode(pending),
    );

    final historyKey = 'subscription_tx_history_by_cid:$subscriberCidNumber';
    final history = await _readList(historyKey);
    history.removeWhere((item) => item['tx_hash'] == proof['tx_hash']);
    history.add(proof);
    if (history.length > 50) history.removeRange(0, history.length - 50);
    await (await _prefs).setString(historyKey, jsonEncode(history));
  }

  Future<void> _removePendingProof(
    String subscriberCidNumber,
    String txHash,
  ) async {
    final pending = await _readList(_pendingKey(subscriberCidNumber));
    pending.removeWhere((item) => item['tx_hash'] == txHash);
    final prefs = await _prefs;
    if (pending.isEmpty) {
      await prefs.remove(_pendingKey(subscriberCidNumber));
    } else {
      await prefs.setString(
        _pendingKey(subscriberCidNumber),
        jsonEncode(pending),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final raw = (await _prefs).getString(key);
    if (raw == null) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(raw);
    return decoded is List
        ? decoded.whereType<Map<String, dynamic>>().toList(growable: true)
        : <Map<String, dynamic>>[];
  }
}
