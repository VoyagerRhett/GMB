import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/material.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizen_sdk/citizen_sdk.dart' show CitizenWalletStateAccount;
import 'package:citizenapp/ui/app_layout.dart';

/// 弹出“更换公民号绑定的账户”底部面板：从本地其他账户中挑选新的签名账户。
///
/// 返回选定账户的 `accountId`;取消 / 无可选账户返回 `null`。授权与提交由调用方
/// ([MyIdService.rebindCidTo])承接;目标账户已由调用方过滤掉当前身份账户。
Future<String?> showRebindAccountSheet(
  BuildContext context, {
  required List<CitizenWalletStateAccount> targets,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => RebindAccountSheet(targets: targets),
  );
}

class RebindAccountSheet extends StatelessWidget {
  const RebindAccountSheet({super.key, required this.targets});

  final List<CitizenWalletStateAccount> targets;

  static String _shortAddress(String value) {
    if (value.length <= 18) return value;
    return '${value.substring(0, 8)}…${value.substring(value.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: AppLayout.scaled(context, 36),
                height: AppLayout.scaled(context, 4),
                margin: EdgeInsets.only(bottom: AppLayout.scaled(context, 16)),
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(AppLayout.scaledValue(2)),
                ),
              ),
            ),
            Text(
              '更换公民号绑定的账户',
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 17),
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 6)),
            Text(
              '更换公民号绑定的签名账户为以下选中的账户，更换绑定需当前钱包账户与目标钱包账户'
              '各签名一次（共两次生物识别授权）。',
              style: TextStyle(
                  fontSize: AppLayout.scaled(context, 12),
                  color: AppTheme.textSecondary),
            ),
            SizedBox(height: AppLayout.scaled(context, 16)),
            if (targets.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: AppTheme.bannerDecoration(AppTheme.warning),
                child: Text(
                  '暂无可换绑的其他账户。请先在钱包里添加账户,再来更换。',
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    height: 1.5,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              ...targets.map(
                (account) => Padding(
                  padding:
                      EdgeInsets.only(bottom: AppLayout.scaled(context, 10)),
                  child: _AccountOption(
                    account: account,
                    shortAddress: _shortAddress(account.ss58Address),
                    onTap: () => Navigator.of(context).pop(account.accountId),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单个可换绑账户行:账户名 + 序号 + 短地址,点击即选中并回传。
class _AccountOption extends StatelessWidget {
  const _AccountOption({
    required this.account,
    required this.shortAddress,
    required this.onTap,
  });

  final CitizenWalletStateAccount account;
  final String shortAddress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppLayout.scaled(context, 14)),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppLayout.scaled(context, 15),
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(width: AppLayout.scaled(context, 8)),
                      Text(
                        '#${account.accountIndex}',
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 12),
                          color: AppTheme.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: AppLayout.scaled(context, 3)),
                  Text(
                    shortAddress,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 12),
                      fontFamily: 'monospace',
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppTheme.textTertiary,
              size: AppLayout.scaled(context, 20),
            ),
          ],
        ),
      ),
    );
  }
}
