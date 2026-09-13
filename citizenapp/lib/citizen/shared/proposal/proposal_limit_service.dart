import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';

/// 提案活跃数量限制查询。
///
/// 主体编码、存储键和 SCALE 解码统一委托给 [ProposalQueryService]，
/// 本类型只保留入口页面使用的限制语义。
class ProposalLimitService {
  ProposalLimitService({required CitizenChain chain})
      : _queryService = ProposalQueryService(chain: chain);

  final ProposalQueryService _queryService;

  /// 每个提案主体最多同时 10 个活跃提案（全局，不区分提案类型）。
  static const maxActiveProposalsPerSubject =
      ProposalQueryService.maxActiveProposalsPerSubject;

  /// 机构按 CID、个人多签按 AccountId 查询同一份 runtime 主体索引。
  Future<List<int>> fetchActiveProposalIds(InstitutionInfo institution) {
    return _queryService.fetchActiveProposalIds(institution);
  }
}
