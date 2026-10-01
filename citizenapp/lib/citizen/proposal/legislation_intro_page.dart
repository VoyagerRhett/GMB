import 'package:flutter/material.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 立法发起介绍页(类B 提案:只投票 / 查看,不在手机端发起)。
///
/// 立法 / 修法 / 废法提案只在电脑节点端(citizenchain 桌面端)发起,
/// 因为条 / 款结构化编辑不便在手机操作。citizenapp 端只负责说明、查看法律和
/// 参与代表机构表决 / 签署 / 会签 / 护宪终审 / 特别案公投。
class LegislationIntroPage extends StatelessWidget {
  const LegislationIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '发起立法',
          style: TextStyle(
              fontSize: AppLayout.scaled(context, 17),
              fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildHeader(),
          SizedBox(height: AppLayout.scaled(context, 18)),
          _buildInfoCard(
            icon: Icons.gavel_outlined,
            title: '立法是什么',
            body: '法律以「章 > 节 > 条 > 款」结构化上链。立法、修法、废法都通过提案 + 投票通过后生效，'
                '不再修改链上代码。公民可在本端查看全部法律与历史版本。',
          ),
          SizedBox(height: AppLayout.scaled(context, 12)),
          _buildInfoCard(
            icon: Icons.desktop_windows_outlined,
            title: '发起位置',
            body: '立法 / 修法 / 废法提案只在电脑节点端发起——条款结构化编辑在手机上不便操作。'
                'citizenapp 端只负责说明、查看法律和参与表决。',
          ),
          SizedBox(height: AppLayout.scaled(context, 12)),
          _buildInfoCard(
            icon: Icons.how_to_vote_outlined,
            title: '表决流程',
            body: '提案创建后出现在立法机构详情页。管理员按代表机构席位表决；通过后由行政首长签署，'
                '否决或超时进入三人会签；修宪还需护宪大法官终审；特别案叠加公民公投。',
          ),
          SizedBox(height: AppLayout.scaled(context, 12)),
          _buildInfoCard(
            icon: Icons.verified_outlined,
            title: '生效结果',
            body: '表决通过并完成签署后写入链上法律，到生效区块自动转为生效版本。'
                '真实状态以投票引擎记录为准（投票中、已否决、已生效）。',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppLayout.scaledValue(16)),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: AppLayout.scaledValue(40),
            height: AppLayout.scaledValue(40),
            decoration: BoxDecoration(
              color: AppTheme.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
            ),
            child: Icon(
              Icons.account_balance_outlined,
              size: AppLayout.scaledValue(20),
              color: AppTheme.info,
            ),
          ),
          SizedBox(width: AppLayout.scaledValue(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发起立法',
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(18),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDark,
                  ),
                ),
                SizedBox(height: AppLayout.scaledValue(4)),
                Text(
                  '请在电脑节点端发起，本端查看法律并参与表决。',
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(13),
                    height: 1.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppLayout.scaledValue(16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: AppLayout.scaledValue(20), color: AppTheme.primaryDark),
          SizedBox(width: AppLayout.scaledValue(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(15),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDark,
                  ),
                ),
                SizedBox(height: AppLayout.scaledValue(6)),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(13),
                    height: 1.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
