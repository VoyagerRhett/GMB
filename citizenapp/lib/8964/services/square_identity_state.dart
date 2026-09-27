import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/identity_badge_snapshot_store.dart';

/// 广场身份状态。
///
/// 普通展示读取本地绑定及完整验真后保存的快照；该状态不能证明当前发布权限。
/// 实际发布必须由统一解析器完成链上双向绑定及身份有效性验真。
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
  String get resolvedDisplayName =>
      ProfilePresentation.forIdentityKey(cidNumber ?? accountId)
          .resolveDisplayName(publicName: displayName);

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
    this.badgeSnapshotStore,
    this.profileCache,
  }) : _wallet = wallet,
       _currentUserContext = currentUserContext;

  final CitizenSdkWallet _wallet;
  final IdentityBadgeSnapshotStore? badgeSnapshotStore;
  final CurrentUserContext _currentUserContext;
  final CitizenProfileCache? profileCache;

  /// 广场与编辑页只读取本地身份；实际发布在动作服务调用统一验真入口。
  Future<SquareIdentityState> loadCurrent() async {
    final defaultAccount = (await _wallet.getState().result).defaultAccount;
    if (defaultAccount == null) return const SquareIdentityState(accountId: '');
    final current = await _currentUserContext.resolve();
    final identityAccountId = defaultAccount.accountId;
    final identitySs58 = defaultAccount.ss58Address;
    final snapshotStore = badgeSnapshotStore ?? IdentityBadgeSnapshotStore();
    final saved = await snapshotStore.readForAccountId(identityAccountId);
    String? cidNumber = saved?.verified == true
        ? saved!.identity?.cidNumber
        : current?.accountId == identityAccountId
        ? current?.cidNumber
        : null;
    if (cidNumber != null && cidNumber.isEmpty) cidNumber = null;
    final badge = saved?.verified == true
        ? saved
        : cidNumber == null
        ? null
        : await snapshotStore.read(cidNumber);
    final identityLevel = badge?.identityLevel ?? 'visitor';

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
