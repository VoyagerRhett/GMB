import 'package:citizenwallet/qr/generated/qr_action_registry.g.dart';
export 'package:citizenwallet/qr/generated/qr_bodies.g.dart' show QrKind;

/// QR_V1 统一二维码协议常量。
///
/// 唯一事实源：`citizenchain/crates/qr-protocol/registry.json`。
/// Golden fixtures:`citizenchain/crates/qr-protocol/tests/fixtures/*.json`
///
/// 与 citizenapp/lib/qr/qr_protocols.dart 逐字节一致(两个独立 Flutter app,
/// 无代码依赖,靠 fixture 对齐)。
class QrProtocols {
  QrProtocols._();

  /// 唯一协议版本字符串。压缩为 5 字符以降低二维码密度。
  static const String qrV1 = 'QR_V1';
}

/// 统一扫码流向枚举。线上只序列化为数字 `k`。
///
/// ## body 单字母键全局注册表(一字母 = 一含义,跨所有码型唯一)
///
/// 信封层:`p` 协议 / `k` 码型 / `i` 临时码 id / `e` 过期毫秒 / `b` body。
///
/// | 键 | 含义 | 编码 | 出现于 |
/// |---|---|---|---|
/// | `a` | 业务动作码 | int | k=1 |
/// | `g` | 签名算法(1=sr25519) | int | k=1 |
/// | `u` | 签名者公钥 | base64url | k=1, k=2 |
/// | `d` | 审阅载荷 | base64url | k=1 |
/// | `s` | 签名 | base64url | k=2 |
/// | `o` | 换绑时当前账户 | base64url | k=2 |
/// | `r` | 换绑时当前账户签名 | base64url | k=2 |
/// | `c` | cid_number 身份主键 | 文本 | k=3 |
/// | `n` | account_id 账户标识 | `0x` 小写 64 hex | k=3, k=4, k=5 |
/// | `v` | 金额 | 文本 | k=4 |
/// | `t` | 币种 | 文本 | k=4 |
/// | `m` | 备注 | 文本 | k=4 |
/// | `l` | 收款方清算行 CID | 文本 | k=4 |
///
/// `u` 与 `n` 都是 32 字节公钥却用两个字母:编码不同(`u` base64url 压体积、
/// `n` `0x` 小写 hex 走 `isAccountIdText` 单源校验)。同一字母两种编码会让解析器
/// 按码型猜格式,是明确埋雷,故分开。
///
/// 新增字段必须先在本表登记,禁止就地取一个没登记过的字母。
/// QR_V1 业务动作码。`k` 只表达扫码流向,业务场景必须放在 `a`。
class QrActions {
  QrActions._();

  static int _code(String key) =>
      GeneratedQrActionRegistry.actionCodeForKey(key)!;

  static int get login => _code('login');
  static int get citizenIdentity => _code('citizen_identity');
  static int get citizenOccupy => _code('citizen_occupy');
  static int get citizenRebind => _code('citizen_rebind');
  static int get switchDefaultAccount => _code('switch_default_account');
  static int get squareDeviceBind => _code('square_device_bind');
  static int get accountDataKeyProvision => _code('account_data_key_provision');
  static int get publish => _code('publish');
  static int get onchinaAdmin => _code('onchina_admin_action');
  static int get activateAdmin => _code('activate_admin_account');
  static int get decryptAdmin => _code('decrypt_admin');
  static int get runtimeUpgradeHash => _code('runtime_upgrade_hash');

  /// 广场账户链下动作：Hot 由 CitizenApp 本机签名，Cold 由 CitizenWallet
  /// 严格解码后签名；两端使用同一个 0x1D 签名域。
  static int get squareAccountAction => _code('square_account_action');

  static int get transferWithRemark => _code('transfer');
  static int get personalCreate => _code('propose_create_personal');
  static int get personalClose => _code('propose_close_personal');
  static int get personalAdminSetChange =>
      _code('propose_personal_admin_set_change');
  static int get resolutionIssuance => _code('propose_issuance');
  static int get finalizeProposal => _code('finalize_proposal');
  static int get retryPassedProposal => _code('retry_passed_proposal');
  static int get cancelPassedProposal => _code('cancel_passed_proposal');
  static int get registerVotingIdentity => _code('register_voting_identity');
  static int get upgradeToCandidateIdentity =>
      _code('upgrade_to_candidate_identity');
  static int get updateVotingIdentity => _code('update_voting_identity');
  static int get updateCandidateIdentity => _code('update_candidate_identity');
  static int get revokeIdentity => _code('revoke_identity');
  static int get occupyCid => _code('occupy_cid');
  static int get adminRebindCidAccountId =>
      _code('admin_rebind_cid_account_id');
  static int get revokeCid => _code('revoke_cid');
  static int get proposeRuntimeUpgrade => _code('propose_runtime_upgrade');
  static int get developerDirectUpgrade => _code('developer_direct_upgrade');
  static int get resolutionDestroy => _code('propose_destroy');
  static int get grandpaKeyChange =>
      _code('propose_emergency_grandpa_key_recovery');
  static int get publicInstitutionClose =>
      _code('propose_close_public_institution');
  static int get publicInstitutionUpdateInfo =>
      _code('update_public_institution_info');
  static int get publicInstitutionAddAccount =>
      _code('add_public_institution_account');
  static int get publicInstitutionGovernance =>
      _code('propose_public_institution_governance');
  static int get publicInstitutionRegisterAdmins =>
      _code('register_public_institution_admins');
  static int get privateInstitutionClose =>
      _code('propose_close_private_institution');
  static int get privateInstitutionUpdateInfo =>
      _code('update_private_institution_info');
  static int get privateInstitutionAddAccount =>
      _code('add_private_institution_account');
  static int get privateInstitutionGovernance =>
      _code('propose_private_institution_governance');
  static int get privateInstitutionRegisterAdmins =>
      _code('register_private_institution_admins');
  static int get multisigTransfer => _code('propose_transfer');
  static int get safetyFundTransfer => _code('propose_safety_fund_transfer');
  static int get sweepToMain => _code('propose_sweep_to_main');
  static int get bindClearingBank => _code('bind_clearing_bank');
  static int get depositClearingBank => _code('deposit_clearing_bank');
  static int get withdrawClearingBank => _code('withdraw_clearing_bank');
  static int get switchClearingBank => _code('switch_clearing_bank');
  static int get proposeL2FeeRate => _code('propose_l2_fee_rate');
  static int get registerClearingBank => _code('register_clearing_bank');
  static int get updateClearingBankEndpoint =>
      _code('update_clearing_bank_endpoint');
  static int get unregisterClearingBank => _code('unregister_clearing_bank');
  static int get internalVote => _code('internal_vote');
  static int get jointVote => _code('joint_vote');
  static int get castReferendum => _code('cast_referendum');
  static int get castPopularVote => _code('cast_popular_vote');
  static int get castMutualVote => _code('cast_mutual_vote');

  // 链上资产 OnchainIssuance(23 = 0x17)。动作码与 runtime call_index 一一对应。
  static int get proposeAssetIssue => _code('propose_asset_issue');
  static int get proposeAssetMint => _code('propose_asset_mint');
  static int get proposeAssetBurn => _code('propose_asset_burn');
  static int get proposeAssetClose => _code('propose_asset_close');
  static int get proposeAssetTransfer => _code('propose_asset_transfer');
  static int get proposeMonitorFreeze => _code('propose_monitor_freeze');
  static int get proposeMonitorUnfreeze => _code('propose_monitor_unfreeze');
  static int get proposeMonitorConfiscate =>
      _code('propose_monitor_confiscate');
  static int get proposeMonitorForceTransfer =>
      _code('propose_monitor_force_transfer');
  static int get proposeMonitorForceClose =>
      _code('propose_monitor_force_close');

  // 注册局地址目录 AddressRegistry(33 = 0x21)
  static int get setAddressCatalogVersion =>
      _code('set_address_catalog_version');
  static int get setAddressName => _code('set_address_name');
  static int get removeAddressName => _code('remove_address_name');
  static int get setAddress => _code('set_address');
  static int get removeAddress => _code('remove_address');

  // 广场发布、会员订阅与平台调价 SquarePost(34 = 0x22)
  static int get publishPost => _code('publish_post');
  static int get subscribe => _code('subscribe');
  static int get cancel => _code('cancel');
  static int get setCreatorPlans => _code('set_creator_plans');
  static int get changeSubscriptionPlan => _code('change_subscription_plan');
  static int get proposeSetPlatformPrice => _code('propose_set_platform_price');
  static int get updateCreatorTierName => _code('update_creator_tier_name');

  // 立法院 LegislationYuan(25 = 0x19)
  static int get proposeEnactLaw => _code('propose_enact_law');
  static int get proposeAmendLaw => _code('propose_amend_law');
  static int get proposeRepealLaw => _code('propose_repeal_law');

  // 立法投票 LegislationVote(26 = 0x1a)
  static int get castRepresentativeVote => _code('cast_representative_vote');
  static int get castLegislationReferendum => _code('cast_referendum_vote');
  static int get executiveSign => _code('executive_sign');
  static int get overrideSign => _code('override_sign');
  static int get guardVote => _code('guard_vote');

  /// 链交易动作统一按 `(pallet_index << 8) | call_index` 生成。
  static int chain(int palletIndex, int callIndex) =>
      ((palletIndex & 0xff) << 8) | (callIndex & 0xff);

  static bool isChainAction(int action) => action >= 0x0100;

  /// 注册局首次绑定/换绑的域签名：b.u 留空，d 是带零账户槽的完整授权模板；
  /// 钱包严格解析后原位填入本账户，再按对应 op_tag 签名。
  static bool isSelfAccountDomainAction(int action) =>
      action == citizenOccupy || action == citizenRebind;

  static bool isBinaryRaw(int action) =>
      action == activateAdmin || action == decryptAdmin;

  static bool isRuntimeHashOnly(int action) =>
      GeneratedQrActionRegistry.isHashOnlyAction(action);

  /// QR 数字动作码对应的 registry 唯一动作名；解码器据此限定无 pallet 前缀的域。
  static String? actionKeyForCode(int action) =>
      GeneratedQrActionRegistry.actionKeyForCode(action);

  static int fromDecodedAction(String action) {
    // 公民参选身份确认复用 a=2 的公民身份签名域，具体身份等级由 payload 字段展示。
    if (action == 'citizen_candidate_identity') return citizenIdentity;
    return GeneratedQrActionRegistry.actionCodeForKey(action) ?? 0;
  }
}
