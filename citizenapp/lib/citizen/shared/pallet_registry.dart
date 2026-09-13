/// CitizenApp 链上 pallet / call 索引唯一真源。
///
/// 索引由 citizenchain 的 `construct_runtime!`(runtime/src/lib.rs)声明顺序决定。
/// 链升级调整 pallet 顺序后，**只改本文件**，全端各 service 引用这里、不再各自写死字面量。
/// 冷钱包 `citizenwallet/lib/signer/pallet_registry.dart` 是同一契约的另一份镜像，
/// 两者必须逐项一致；本文件仅收录 CitizenApp 实际构造 extrinsic 用到的 pallet/call。
///
/// 约定：pallet 常量以 `Pallet` 结尾；call 常量以 `Call` 结尾。
class PalletRegistry {
  const PalletRegistry._();

  // ---- Balances (2) · 只读余额账本(外部转账入口在 OnchainTransaction) ----
  static const int balancesPallet = 2;

  // ---- OnchainTransaction (4) ----
  static const int onchainTransactionPallet = 4;
  static const int transferWithRemarkCall = 0;

  // ---- PersonalManage (7) · 个人多签生命周期 ----
  static const int personalManagePallet = 7;

  // ---- CitizenIdentity (10) · 公民链上身份(匿名自助占号 / 换绑) ----
  static const int citizenIdentityPallet = 10;
  static const int selfOccupyCidCall = 5;
  static const int selfRebindCidAccountCall = 9;

  // ---- MultisigTransfer (17) ----
  static const int multisigTransferPallet = 17;

  // ---- OffchainTransaction (19) · 清算行 L2 体系 ----
  static const int offchainTransactionPallet = 19;
  static const int bindClearingBankCall = 30;
  static const int depositCall = 31;
  static const int withdrawCall = 32;
  static const int switchBankCall = 33;

  // ---- InternalVote (20) · 内部投票管理员一人一票 ----
  static const int internalVotePallet = 20;
  static const int internalVoteCastCall = 0;

  // ---- JointVote (21) · 联合投票(内部投票阶段 + 联合公投) ----
  static const int jointVotePallet = 21;
  static const int jointVoteCastAdminCall = 0;

  // ---- OnchainIssuance (23) · 链上发行代币(Plain FT, ADR-011) ----
  // call_index 5..=9 / 15+ 留洞不复用(永久 ABI)。
  static const int onchainIssuancePallet = 23;
  static const int proposeIssueCall = 0;
  static const int proposeMintCall = 1;
  static const int proposeBurnCall = 2;
  static const int proposeCloseAssetCall = 3;
  static const int proposeAssetTransferCall = 4;
  static const int proposeMonitorFreezeCall = 10;
  static const int proposeMonitorUnfreezeCall = 11;
  static const int proposeMonitorConfiscateCall = 12;
  static const int proposeMonitorForceTransferCall = 13;
  static const int proposeMonitorForceCloseCall = 14;

  // ---- Assets (24) · pallet_assets 内核(原生 extrinsic 全被 RuntimeCallFilter reject) ----
  static const int assetsPallet = 24;

  // ---- LegislationVote (26) · 立法专属投票引擎 ----
  // call_index 0 留洞(特别案快照内联生成)。
  static const int legislationVotePallet = 26;
  static const int castRepresentativeVoteCall = 1;
  static const int castLegislationReferendumCall = 2;
  static const int executiveSignCall = 3;
  static const int overrideSignCall = 4;
  static const int guardVoteCall = 5;

  // ---- PersonalAdmins (29) · 个人多签管理员集合变更 ----
  static const int personalAdminsPallet = 29;
  static const int proposePersonalAdminSetChangeCall = 0;

  // ---- SquarePost (34) · 广场发帖 + 会员订阅价格治理 ----
  static const int squarePostPallet = 34;
  static const int publishPostCall = 0;
  static const int subscribeCall = 1;
  static const int cancelSubscriptionCall = 2;
  static const int setCreatorPlansCall = 3;
  static const int changeSubscriptionPlanCall = 4;
  static const int updateCreatorTierNameCall = 6;
}
