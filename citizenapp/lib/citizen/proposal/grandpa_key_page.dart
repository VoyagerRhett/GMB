import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/proposal/proposal_placeholder.dart';

/// 验证密钥入口占位；真实密钥保管与换钥只在对应权威节点桌面端执行。
class GrandpaKeyPage extends StatelessWidget {
  const GrandpaKeyPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const ProposalPlaceholderPage(title: '验证密钥', kind: '验证密钥');
}
