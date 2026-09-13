import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 构造固定账户码（`QR_V1 k=5 account_id_code`）。
///
/// 本机账户名称和 SS58 地址只用于弹窗展示，绝不进入二维码载荷；账户授权与关系主键
/// 始终是规范 `account_id`。
@visibleForTesting
Future<String> buildWalletAccountQrData(CitizenQr qr, String accountId) =>
    qr.encodeAccountId(accountId);

/// 打开冷热钱包共用的账户二维码弹窗。
///
/// [showDialog] 默认允许点击遮罩关闭；显式保留该行为，避免恢复成必须进入独立页面或只能
/// 点击按钮退出的旧交互。非法 `account_id` 从严拒绝，不生成可误导扫码端的二维码。
Future<void> showWalletQrDialog(
  BuildContext context, {
  required String accountId,
  required String accountName,
}) async {
  final normalizedAccountId = accountId.trim();
  if (!isAccountIdText(normalizedAccountId)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('账户标识无效，无法生成二维码')));
    return;
  }

  final ss58Address = ss58FromAccountIdText(normalizedAccountId);
  final qrData = await buildWalletAccountQrData(
    context.read<CitizenSdk>().qr,
    normalizedAccountId,
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          AppLayout.scaled(dialogContext, 16),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaled(dialogContext, 24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              accountName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppLayout.scaled(dialogContext, 16),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: AppLayout.scaled(dialogContext, 16)),
            Container(
              padding: EdgeInsets.all(AppLayout.scaled(dialogContext, 12)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(
                  AppLayout.scaled(dialogContext, 12),
                ),
                border: Border.all(color: AppTheme.border),
              ),
              child: QrImageView(
                key: const ValueKey('wallet-account-qr'),
                data: qrData,
                version: QrVersions.auto,
                size: AppLayout.scaled(dialogContext, 240),
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppTheme.primaryDark,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppTheme.primaryDark,
                ),
              ),
            ),
            SizedBox(height: AppLayout.scaled(dialogContext, 12)),
            SelectableText(
              ss58Address,
              key: const ValueKey('wallet-account-address'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontFamily: 'monospace',
                fontSize: AppLayout.scaled(dialogContext, 11),
              ),
            ),
            SizedBox(height: AppLayout.scaled(dialogContext, 12)),
            // 与公民钱包保持同一结构：关闭、复制均为等宽文字按钮。
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('关闭'),
                  ),
                ),
                SizedBox(width: AppLayout.scaled(dialogContext, 8)),
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: ss58Address));
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('账户地址已复制'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: const Text('复制'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
