import 'package:flutter/material.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 公权选举 tab 未开放视图。
///
/// `election-vote` 已具备通用投票、快照、计票和结果能力，但具体候选条件、目标岗位、
/// 席位、任期和结果写回必须由对应公权选举业务模块提供。具体模块落地前不开放假入口。
class ElectionTab extends StatelessWidget {
  const ElectionTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: AppLayout.scaled(context, 32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.how_to_vote_outlined,
                size: AppLayout.scaled(context, 48),
                color: AppTheme.textTertiary),
            SizedBox(height: AppLayout.scaled(context, 14)),
            Text('选举',
                style: TextStyle(
                    fontSize: AppLayout.scaled(context, 17),
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary)),
            SizedBox(height: AppLayout.scaled(context, 8)),
            Text('具体公权选举业务模块尚未接入，当前不开放选举入口',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppLayout.scaled(context, 13),
                    color: AppTheme.textTertiary)),
          ],
        ),
      ),
    );
  }
}
