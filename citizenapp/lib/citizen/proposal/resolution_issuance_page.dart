import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/proposal/proposal_placeholder.dart';

/// 决议发行提案(占位,链端 onchain-issuance 客户端待接)。
class ResolutionIssuancePage extends StatelessWidget {
  const ResolutionIssuancePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const ProposalPlaceholderPage(title: '决议发行', kind: '决议发行');
}
