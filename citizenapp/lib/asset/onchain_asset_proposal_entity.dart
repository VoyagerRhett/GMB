// Isar 永久保留:链上发行代币业务/监管 10 类提案历史(框架阶段占位)。
//
// 设计参考 project_personal_account_ui_2026_05_03 的"双轨制"思路:
// 链上 90 天清理终态后,本地 Isar 永久持有提案痕迹(发起方 / 时间 / 资产 ID / 状态 / 解码后参数)。
//
// 后续任务卡 C 实装时启用 Isar 标注 + collection schema。框架阶段先定义裸 dart class,
// 不引入 Isar package 依赖,以免让 citizenapp 编译条件 prematurely 复杂。

class OnchainAssetProposalEntity {
  OnchainAssetProposalEntity({
    required this.proposalId,
    required this.action,
    required this.assetId,
    required this.proposerSs58,
    required this.createdAtBlock,
    required this.createdAtMs,
    this.amount,
    this.counterpartySs58,
    this.reasonHashHex,
    this.status = 'Voting',
  });

  /// VotingEngine 提案 ID(双层:high32 = year, low32 = seq,实际数值由链端分配)。
  final int proposalId;

  /// 4 字符 ACTION 常量(OAIS / OAMT / OABN / ... / OMFC)。
  final String action;

  /// pallet_assets AssetId;create 提案此字段在终结后回填。
  int? assetId;

  final String proposerSs58;
  final int createdAtBlock;
  final int createdAtMs;

  /// mint / burn / transfer / confiscate / forceTransfer 时的金额(raw,含 decimals)。
  BigInt? amount;

  /// transfer / forceTransfer 的对方 SS58。
  String? counterpartySs58;

  /// 监管 5 动作的 reason_hash(链下文书 sha256)hex 字符串。
  String? reasonHashHex;

  /// 'Voting' / 'Passed' / 'Rejected' / 'Cleaned'。
  String status;
}
