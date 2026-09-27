import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/foundation.dart';

import 'identity_badge_snapshot_store.dart';

import 'citizen_identity_chain_reader.dart';

/// 动权/动钱路径的 finalized 身份解析结果。
///
/// 普通聊天、通讯录、主页和动态不得使用本类型；它们统一使用
/// `CurrentUserContext` 的本机绑定与 Cloudflare finalized 投影会话。
class FinalizedIdentity {
  const FinalizedIdentity({
    required this.accountId,
    required this.ss58Address,
    required this.snapshot,
    this.walletRevision,
    this.identityRevision,
  });

  /// 当前默认账户；没有 CID 时仍返回该账户对应的访客状态。
  final String accountId;
  final String ss58Address;

  /// 本次操作的账户版本；不进入持久展示授权。
  final BigInt? walletRevision;
  final int? identityRevision;

  /// 链上身份闭环快照；`null` = 当前默认账户未注册（纯访客）。
  final CitizenIdentityChainSnapshot? snapshot;

  /// 是否已占到一个 CID(匿名 / 投票 / 竞选任一皆为 true)。
  bool get isRegistered => snapshot != null;
}

/// 当前用户单源：设备账户级顺序第一项就是唯一默认账户，默认账户绑定的 CID 就是
/// 当前用户。默认账户没有 CID 时直接返回访客，禁止遍历其它账户偷换用户。
///
/// 非链功能唯一身份主键 = CID 号；当前绑定 `account_id` 只承担控制与签名授权，
/// 钱包账户只是与该 CID 绑定的鉴权凭证;鉴权授权取决于 CID 当前绑定了哪个账户。
/// 私钥泄漏可换绑到新账户而 CID(及其通讯录/公文/文章/视频/粉丝)永不丢失。
class FinalizedIdentityResolver {
  FinalizedIdentityResolver({
    required CitizenSdkWallet wallet,
    required CitizenChain chain,
    CitizenIdentityChainReader? chainReader,
    IdentityBadgeSnapshotStore? snapshotStore,
    ValueListenable<int>? identityRevision,
  }) : _wallet = wallet,
       _snapshotStore = snapshotStore,
       _identityRevision = identityRevision,
       _chainReader = chainReader ?? CitizenIdentityChainReader(chain: chain);

  final CitizenSdkWallet _wallet;
  final CitizenIdentityChainReader _chainReader;
  final IdentityBadgeSnapshotStore? _snapshotStore;
  final ValueListenable<int>? _identityRevision;
  final _inflight = <(String, BigInt, int), Future<FinalizedIdentity?>>{};
  int _generation = 0;
  (String, BigInt, int)? _context;

  /// 解析当前默认账户对应的用户。热、冷账户走同一条公开链读取路径。
  ///
  /// 链读异常**不吞**(上抛给调用方 fail-closed,绝不静默降级成访客/未注册)。
  Future<FinalizedIdentity?> resolve() async {
    final state = await _wallet.getState().result;
    final account = state.defaultAccount;
    if (account == null) {
      _context = null;
      _generation++;
      return null;
    }
    final key = (
      account.accountId,
      state.revision,
      _identityRevision?.value ?? 0,
    );
    if (_context != key) {
      _context = key;
      _generation++;
    }
    final existing = _inflight[key];
    if (existing != null) return existing;
    final future = _resolveFresh(account, key, _generation);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_inflight[key], future)) _inflight.remove(key);
    }
  }

  Future<FinalizedIdentity> _resolveFresh(
    CitizenWalletStateAccount account,
    (String, BigInt, int) key,
    int generation,
  ) async {
    final snapshot = await _chainReader.readByAccountId(account.accountId);
    final result = FinalizedIdentity(
      accountId: account.accountId,
      ss58Address: account.ss58Address,
      snapshot: snapshot,
      walletRevision: key.$2,
      identityRevision: key.$3,
    );
    await assertCurrent(result);
    bool isCurrent() =>
        generation == _generation && (_identityRevision?.value ?? 0) == key.$3;
    if (!isCurrent()) throw StateError('身份上下文已变化，请重新操作');
    await _snapshotStore?.writeVerified(
      accountId: account.accountId,
      identity: snapshot,
      isCurrent: isCurrent,
    );
    await assertCurrent(result);
    return result;
  }

  /// 仅比较本机版本；后续步骤复用本次验真结果，不再查询链。
  Future<void> assertCurrent(FinalizedIdentity identity) async {
    final state = await _wallet.getState().result;
    if (state.defaultAccount?.accountId != identity.accountId ||
        (identity.walletRevision != null &&
            state.revision != identity.walletRevision) ||
        (identity.identityRevision != null &&
            (_identityRevision?.value ?? 0) != identity.identityRevision)) {
      throw StateError('身份上下文已变化，请重新操作');
    }
  }
}
