import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/proposal/proposal_placeholder.dart';

/// 决议销毁提案(占位,链端 resolution-destroy 客户端待接)。
class ResolutionDestroyPage extends StatelessWidget {
  const ResolutionDestroyPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const ProposalPlaceholderPage(title: '决议销毁', kind: '决议销毁');
}
