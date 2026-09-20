import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'institution_role_models.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 机构管理员人员卡；姓名与账户来自 admins，岗位任职来自 entity。
class InstitutionAssignmentCard extends StatelessWidget {
  const InstitutionAssignmentCard({
    super.key,
    required this.adminView,
    this.index,
    this.balanceYuan,
    this.trailing,
  });

  final InstitutionAdminView adminView;
  final int? index;
  final double? balanceYuan;
  final Widget? trailing;
  static const double actionHeight = 30;

  @override
  Widget build(BuildContext context) {
    final admin = adminView.admin;
    final personName = '${admin.family_name}${admin.given_name}';
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaled(context, 12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (index != null) Text('$index　'),
              Expanded(
                  child: Text(personName,
                      style: Theme.of(context).textTheme.titleMedium)),
              ?trailing,
            ]),
            if (adminView.assignments.isEmpty)
              const Text('岗位：暂无岗位')
            else
              for (final assignment in adminView.assignments) ...[
                Text('岗位：${assignment.roleName}'),
                Text('任期：${assignment.termLabel}'),
                Text('任职来源：${assignment.source.label}'),
                if (assignment.sourceRef.isNotEmpty)
                  Text('来源引用：${assignment.sourceRef}'),
              ],
            Text('管理员账户：${ss58FromAccountIdText(admin.account_id)}'),
            if (balanceYuan != null)
              Text('余额：${AmountFormat.formatThousands(balanceYuan)} 元'),
          ],
        ),
      ),
    );
  }
}
