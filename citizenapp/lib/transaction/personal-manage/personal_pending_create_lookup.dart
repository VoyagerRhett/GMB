// 个人多签待激活创建提案反查(req 2 依赖)。
//
// 数据源选择:Isar 而非链上 state_getKeys。
//
// 详情页 mount 时已经通过 `PersonalProposalHistoryService.fetchAll` 把链上活跃提案
// 同步到 Isar。因此从详情页跳转进入管理员子页时,Isar 必然已包含该多签
// 当前活跃创建提案的 entity(若存在),无需再次调链上 prefix iteration。
//
// 这避免了无边界整表扫描，并且查询成本是
// O(1) 级 Isar 索引读取。

import 'package:isar_community/isar.dart';

import 'package:citizenapp/isar/wallet_isar.dart';

import 'personal_proposal_history_service.dart';

class PersonalPendingCreateLookup {
  /// 查找该地址当前在投票中的创建提案 ID。
  ///
  /// 返回 null 表示无活跃创建提案 — 可能因为:
  /// 1. 多签已激活(创建提案已 EXECUTED,Account 已转 Active);
  /// 2. 创建提案被否决(Account 已删除);
  /// 3. 详情页未触发过历史服务同步,Isar 尚未填充(异常态,管理员子页应回退提示)。
  Future<int?> findActiveCreate(String personalAccountId) async {
    final entity = await WalletIsar.instance.read((isar) {
      return isar.personalAccountProposalEntitys
          .filter()
          .personalAccountIdEqualTo(personalAccountId)
          .actionEqualTo(PersonalProposalAction.create)
          .statusEqualTo(PersonalProposalStatus.voting)
          .findFirst();
    });
    return entity?.proposalId;
  }
}
