import 'package:citizen_sdk/citizen_sdk.dart';

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
  });

  /// 当前默认账户；没有 CID 时仍返回该账户对应的访客状态。
  final String accountId;
  final String ss58Address;

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
  })  : _wallet = wallet,
        _chainReader =
            chainReader ?? CitizenIdentityChainReader(chain: chain);

  final CitizenSdkWallet _wallet;
  final CitizenIdentityChainReader _chainReader;

  /// 解析当前默认账户对应的用户。热、冷账户走同一条公开链读取路径。
  ///
  /// 链读异常**不吞**(上抛给调用方 fail-closed,绝不静默降级成访客/未注册)。
  Future<FinalizedIdentity?> resolve() async {
    final account = (await _wallet.getState()).defaultAccount;
    if (account == null) return null;
    final snapshot = await _chainReader.readByAccountId(account.accountId);
    return FinalizedIdentity(
      accountId: account.accountId,
      ss58Address: account.ss58Address,
      snapshot: snapshot,
    );
  }
}
