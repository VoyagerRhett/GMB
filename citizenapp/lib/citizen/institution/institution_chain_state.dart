// 统一机构链态读服务(ADR-028 决策 2)——合并公权 `LivePublicInstitutionChainData`
// 与治理侧 admins 读取为一套:按机构 CID 过滤提案,按具体机构账户读余额。
//
//
// - 管理员身份统一按机构 CID 路由，机构码只用于选择对应 admins pallet。
// - 读取遵守 ADR-018:余额走精确整键批量,提案走当年共享缓存客户端过滤,不长前缀扫描。

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/citizen/institution/institution.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/institution_admin_service.dart';
import 'package:citizenapp/citizen/institution/institution_role_models.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_proposal_adapter.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_service.dart';

/// 机构提案摘要(详情页提案列表用)。
class InstitutionProposalSummary {
  const InstitutionProposalSummary({
    required this.proposalId,
    required this.idLabel,
    required this.status,
  });

  final int proposalId;
  final String idLabel;

  /// 0=表决中 1=通过 2=否决 3=已执行 4=执行失败。
  final int status;

  String get statusLabel => switch (status) {
        1 => '已通过',
        2 => '已否决',
        3 => '已执行',
        4 => '执行失败',
        _ => '表决中',
      };
}

/// 统一机构链态读服务接口(可注入 fake 单测)。
abstract interface class InstitutionChainState {
  /// 批量余额(hex→元);精确整键 + ChainReadCache。
  Future<Map<String, double>> balances(List<String> accountIds);

  /// 完整管理员人员集合左连接岗位任职；无岗位管理员仍保留。
  Future<List<InstitutionAdminView>> adminViews(Institution institution);

  /// 该机构当年提案(按 subject_cid_numbers 包含机构 CID 过滤当年缓存)。
  Future<List<InstitutionProposalSummary>> proposals(Institution institution);
}

/// 生产实现:复用既有链读基础设施。链读需联网,真机验证。
class LiveInstitutionChainState implements InstitutionChainState {
  LiveInstitutionChainState({
    required CitizenChain chain,
    required CitizenTransactions transactions,
    InstitutionAdminService? adminService,
    MultisigTransferProposalFeed? feed,
  })  : _chain = chain,
        _adminService = adminService ?? InstitutionAdminService(chain: chain),
        _feed = feed ??
            MultisigTransferProposalFeed(
              service: MultisigTransferService(
                chain: chain,
                transactions: transactions,
              ),
            );

  final CitizenChain _chain;
  final InstitutionAdminService _adminService;
  final MultisigTransferProposalFeed _feed;

  @override
  Future<Map<String, double>> balances(List<String> accountIds) async {
    if (accountIds.isEmpty) return Future.value(const {});
    final snapshots = await _chain.getAccountBalances(accountIds);
    return <String, double>{
      for (final snapshot in snapshots)
        snapshot.accountId: snapshot.freeFen.toDouble() / 100,
    };
  }

  @override
  Future<List<InstitutionAdminView>> adminViews(Institution institution) {
    return _adminService.fetchAdminViews(
      adminIdentityOf(institution),
      institution.cidNumber,
    );
  }

  @override
  Future<List<InstitutionProposalSummary>> proposals(
      Institution institution) async {
    final all = await _feed.currentYearProposals();
    final out = <InstitutionProposalSummary>[];
    for (final p in all) {
      if (p.meta.subjectCidNumbers.contains(institution.cidNumber)) {
        out.add(InstitutionProposalSummary(
          proposalId: p.meta.proposalId,
          idLabel: '提案 #${p.meta.proposalId}',
          status: p.meta.status,
        ));
      }
    }
    return out;
  }
}

/// 机构 → 管理员账户身份(单一路由,机构码决定):
/// 所有机构统一以 CID 构造管理员主体，具体账户不进入授权身份。
AdminAccountIdentity adminIdentityOf(Institution institution) {
  return AdminAccountIdentity.institution(
    cidNumber: institution.cidNumber,
    institutionCode: institution.institutionCode,
    accountLabel: institution.cidFullName,
  );
}
