import 'package:flutter/material.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 协议升级介绍页。
///
/// citizenapp 端只负责展示协议升级流程和后续投票入口说明，
/// 不在移动端发起协议升级提案。
class RuntimeUpgradePage extends StatelessWidget {
  const RuntimeUpgradePage({super.key, required this.adminWallets});

  final List<CitizenWalletStateAccount> adminWallets;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '协议升级',
          style: TextStyle(
            fontSize: AppLayout.scaled(context, 17),
            fontWeight: FontWeight.w700,
          ),
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
            icon: Icons.info_outline,
            title: '协议升级是什么',
            body: '协议升级用于更新链上运行协议。升级提案会携带新的 WASM 代码哈希和升级理由，经过联合投票通过后再由链上流程执行。',
          ),
          SizedBox(height: AppLayout.scaled(context, 12)),
          _buildInfoCard(
            icon: Icons.desktop_windows_outlined,
            title: '发起位置',
            body: '协议升级提案只在 node 管理端发起。citizenapp 端只负责说明、查看详情和参与投票。',
          ),
          SizedBox(height: AppLayout.scaled(context, 12)),
          _buildInfoCard(
            icon: Icons.how_to_vote_outlined,
            title: '投票流程',
            body:
                '提案创建后会出现在治理提案列表和机构详情页。机构管理员可进入协议升级详情页查看升级理由、代码哈希和投票状态，并按页面提示完成投票。',
          ),
          SizedBox(height: AppLayout.scaled(context, 12)),
          _buildInfoCard(
            icon: Icons.verified_outlined,
            title: '执行结果',
            body:
                '联合投票通过后由链上协议升级模块执行升级。详情页展示的真实状态以投票引擎记录为准，包括投票中、已否决、已执行和执行失败。',
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
              Icons.arrow_upward,
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
                  '协议升级',
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(18),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDark,
                  ),
                ),
                SizedBox(height: AppLayout.scaledValue(4)),
                Text(
                  '查看流程说明，后续在提案详情页参与投票。',
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
          Icon(
            icon,
            size: AppLayout.scaledValue(20),
            color: AppTheme.primaryDark,
          ),
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
