import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/8964/chain/square_chain_service.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/identity_badge_snapshot_store.dart';

/// 广场身份状态。
///
/// `account_id` 固定使用 CID 当前绑定账户；`cid_number` 只能从链上
/// 通过 `CidByAccountId`、`AccountIdByCid`、Active `CidRegistry` 和
/// `VotingIdentityByCid` 闭环读取，App 不允许自行传入链上身份。
class SquareIdentityState {
  const SquareIdentityState({
    required this.accountId,
    this.displayName,
    this.cidNumber,
    this.walletIndex,
    this.ss58Address,
    this.signMode,
    this.identityLevel,
  });

  final String accountId;
  final String? displayName;
  final String? cidNumber;
  final int? walletIndex;
  final String? ss58Address;

  /// 当前身份账户的钱包签名模式；有账户却缺失模式时，所有钱包签名入口必须拒绝。
  final CitizenWalletSignMode? signMode;

  /// 链上身份档（徽章分色）：visitor/voting/candidate。
  final String? identityLevel;

  bool get hasWallet => accountId.isNotEmpty;
  bool get isCertified => cidNumber != null && cidNumber!.isNotEmpty;

  /// 竞选身份（candidate）：发布竞选内容的资格（用户 2026-07-16：发帖分类按身份档）。
  bool get isCandidate => identityLevel == 'candidate';

  /// 发帖页展示公开昵称；资料尚未缓存时按 CID（无 CID 才按账户）稳定兜底。
  String get resolvedDisplayName => ProfilePresentation.forIdentityKey(
        cidNumber ?? accountId,
      ).resolveDisplayName(publicName: displayName);

  String get accountLabel {
    if (!hasWallet) return '未选择钱包';
    if (accountId.length <= 14) return accountId;
    return '${accountId.substring(0, 7)}...${accountId.substring(accountId.length - 7)}';
  }
}

class SquareIdentityService {
  const SquareIdentityService({
    required CitizenSdkWallet wallet,
    required CurrentUserContext currentUserContext,
    required this.chainService,
    this.badgeSnapshotStore,
    this.profileCache,
  })  : _wallet = wallet,
        _currentUserContext = currentUserContext;

  final CitizenSdkWallet _wallet;
  final SquareChainService chainService;
  final IdentityBadgeSnapshotStore? badgeSnapshotStore;
  final CurrentUserContext _currentUserContext;
  final CitizenProfileCache? profileCache;

  /// 加载当前广场身份。
  ///
  /// 身份主键 = CID 号:`accountId`/`ss58`/`cid` 跟随**身份账户**(CID 绑定账户,
  /// 即账户顺序第一项),`walletIndex` 只用于钱包主钥/设备数据钥硬件金库，P-256 设备
  /// 子钥按 CID 保存；公开昵称
  /// 只从 CID 资料缓存读取。[readLiveChain] 仅允许发布等主动链流程传 true;广场浏览必须传 false,
  /// 只读 CID 级徽章快照，不能因此发起 CitizenSDK 链读。
  Future<SquareIdentityState> loadCurrent({bool readLiveChain = true}) async {
    final defaultAccount = (await _wallet.getState()).defaultAccount;
    if (defaultAccount == null) {
      return const SquareIdentityState(accountId: '');
    }
    // 普通浏览只读默认账户的本机逐 CID 绑定；主动发布才进入下方 finalized 链读。
    // 两条路径显式分离，普通浏览不得因缓存未命中暗中发起链读。
    final current = readLiveChain
        ? null
        : await _currentUserContext.resolve();
    final identityAccountId = current?.accountId ?? defaultAccount.accountId;
    final identitySs58 = current?.ss58Address ?? defaultAccount.ss58Address;

    String? cidNumber = current?.cidNumber;
    if (cidNumber != null && cidNumber.isEmpty) cidNumber = null;
    String identityLevel = 'visitor';
    final snapshotStore = badgeSnapshotStore ?? IdentityBadgeSnapshotStore();
    if (readLiveChain) {
      try {
        final chainIdentity = await chainService.fetchIdentity(identityAccountId);
        final liveCidNumber = chainIdentity.cidNumber?.trim();
        cidNumber = liveCidNumber == null || liveCidNumber.isEmpty
            ? null
            : liveCidNumber;
        identityLevel = chainIdentity.identityLevel;
        if (cidNumber != null) {
          try {
            await snapshotStore.write(
              cidNumber: cidNumber,
              identityLevel: identityLevel,
            );
          } catch (_) {
            // 快照写失败不影响本次发布流程使用真实链上身份。
          }
        }
      } catch (_) {
        cidNumber = null;
        identityLevel = 'visitor';
      }
    } else {
      final snapshot =
          cidNumber == null ? null : await snapshotStore.read(cidNumber);
      identityLevel = snapshot?.identityLevel ?? 'visitor';
    }

    String? displayName;
    final profileCid = cidNumber?.trim() ?? '';
    if (profileCid.isNotEmpty) {
      final profile = await (profileCache ?? const CitizenProfileCache()).read(
        profileCid,
      );
      final cachedName = profile?.displayName.trim() ?? '';
      if (cachedName.isNotEmpty) {
        displayName = cachedName;
      }
    }

    return SquareIdentityState(
      accountId: identityAccountId,
      displayName: displayName,
      cidNumber: cidNumber,
      walletIndex: defaultAccount.walletIndex,
      ss58Address: identitySs58,
      signMode: defaultAccount.signMode,
      identityLevel: identityLevel,
    );
  }
}
