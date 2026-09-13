// 链上发行代币（onchain-issuance）pallet_index / call_index / ACTION 常量（ADR-011）。
//
// 业务调用走 propose_X extrinsic(InternalVote 路径):
//   propose_issue / mint / burn / close / transfer  (call_index 0..=4)
// 监管调用走 propose_monitor_X extrinsic(JointVote 路径,NRC admin 发起):
//   propose_monitor_freeze / unfreeze / confiscate / force_transfer / force_close
//   (call_index 10..=14)
//
// 链端权威定义见 citizenchain/runtime/issuance/onchain-issuance/src/lib.rs。
// 冷钱包 citizenwallet/lib/signer/pallet_registry.dart 同步 pallet_index/call_index 常量。
//
// ⚠ 本目录(lib/asset/shared + lib/asset/entity)不是死代码,是跨端契约常量层。
// 当前资产视图尚未消费这些常量，因此暂无页面引用。
// 链端 pallet(index 23)、qr-protocol action(0x1700-0x1704)、citizenwallet decoder 均已实装。
// 框架阶段的 pages/ 与 widgets/ 占位壳已于 2026-07-23 删除,子任务 C 按真实设计重写。

import 'package:citizenapp/citizen/shared/pallet_registry.dart';

class OnchainAssetActions {
  OnchainAssetActions._();

  // ---------- pallet_index / call_index(与链端 + citizenwallet PalletRegistry 同步) ----------

  /// OnchainIssuance pallet_index(单源 PalletRegistry,对齐 construct_runtime)。
  static const int onchainIssuancePalletIndex =
      PalletRegistry.onchainIssuancePallet;

  /// pallet_assets 内核 pallet_index(原生 extrinsic 全部被 RuntimeCallFilter reject)。
  static const int assetsPalletIndex = PalletRegistry.assetsPallet;

  // 业务 propose_X(call_index 0..=4)
  static const int callProposeIssue = PalletRegistry.proposeIssueCall;
  static const int callProposeMint = PalletRegistry.proposeMintCall;
  static const int callProposeBurn = PalletRegistry.proposeBurnCall;
  static const int callProposeClose = PalletRegistry.proposeCloseAssetCall;
  static const int callProposeTransfer =
      PalletRegistry.proposeAssetTransferCall;

  // 监管 propose_monitor_X(call_index 10..=14)
  static const int callProposeMonitorFreeze =
      PalletRegistry.proposeMonitorFreezeCall;
  static const int callProposeMonitorUnfreeze =
      PalletRegistry.proposeMonitorUnfreezeCall;
  static const int callProposeMonitorConfiscate =
      PalletRegistry.proposeMonitorConfiscateCall;
  static const int callProposeMonitorForceTransfer =
      PalletRegistry.proposeMonitorForceTransferCall;
  static const int callProposeMonitorForceClose =
      PalletRegistry.proposeMonitorForceCloseCall;

  // ---------- ACTION 字符串常量(VotingEngine ProposalData 业务标签) ----------

  // 业务 ACTION(InternalVote)
  static const String actionIssue = 'OAIS';
  static const String actionMint = 'OAMT';
  static const String actionBurn = 'OABN';
  static const String actionClose = 'OACL';
  static const String actionTransfer = 'OATR';

  // 监管 ACTION(JointVote)
  static const String actionMonitorFreeze = 'OMFZ';
  static const String actionMonitorUnfreeze = 'OMUF';
  static const String actionMonitorConfiscate = 'OMCF';
  static const String actionMonitorForceTransfer = 'OMFT';
  static const String actionMonitorForceClose = 'OMFC';

  /// VotingEngine ProposalData 业务标签前缀(与链端 MODULE_TAG 一致)。
  static const String moduleTag = 'onc-iss';

  /// decimals 合法区间(链端 onchain_issuance::validation 同步约束)。
  static const int minDecimals = 0;
  static const int maxDecimals = 18;
}
