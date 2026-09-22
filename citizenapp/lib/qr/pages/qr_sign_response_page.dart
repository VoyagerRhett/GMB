import 'package:citizenapp/qr/widgets/qr_display_scaffold.dart' show AppQrImage;
import 'package:flutter/material.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 广场账户动作签名响应页：展示 QR_V1 signResponse 二维码，供发起方（官网）扫回完成。
class QrSignResponsePage extends StatelessWidget {
  const QrSignResponsePage({
    super.key,
    required this.responseJson,
    required this.actionLabel,
    required this.reviewEntries,
  });

  /// signResponse envelope 的 JSON。
  final String responseJson;

  final String actionLabel;
  final List<(String, String)> reviewEntries;

  @override
  Widget build(BuildContext context) {
    final fieldLines =
        reviewEntries.map((field) => '${field.$1}：${field.$2}').join('\n');
    return Scaffold(
      appBar: AppBar(title: const Text('签名结果')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppLayout.scaled(context, 24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$actionLabel\n$fieldLines',
                style: TextStyle(
                    fontSize: AppLayout.scaled(context, 18),
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppLayout.scaled(context, 24)),
              Center(
                child: AppQrImage(
                  data: responseJson,
                  size: AppLayout.scaled(context, 240),
                  errorStateBuilder: (context, error) {
                    return Container(
                      width: AppLayout.scaled(context, 240),
                      height: AppLayout.scaled(context, 240),
                      padding: EdgeInsets.all(AppLayout.scaled(context, 10)),
                      decoration: AppTheme.bannerDecoration(AppTheme.danger),
                      child: const Center(
                        child: Text(
                          '二维码渲染失败',
                          style: TextStyle(color: AppTheme.danger),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 24)),
              const Text(
                '已完成签名。请在发起页面（官网）扫描此二维码以继续。',
                style: TextStyle(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: AppLayout.scaled(context, 24)),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
