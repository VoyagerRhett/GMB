import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/proposal/proposal_placeholder.dart';

/// 发起选举提案未开放页。
///
/// 未来必须由具体公权选举业务模块提供提案入口，不允许直接调用投票引擎创建选举。
class ElectionProposalPage extends StatelessWidget {
  const ElectionProposalPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const ProposalPlaceholderPage(title: '发起选举', kind: '发起选举');
}
