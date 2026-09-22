import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/my/util/screenshot_guard.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 只映射SDK事实到原提示；App不再根据数据库错误字符串猜测底层状态。
bool isWalletLocalStoreError(Object? error) =>
    error is CitizenSdkException && error.code == CitizenSdkErrorCode.storage;

String walletLocalStoreErrorMessage(Object? error) {
  if (isWalletLocalStoreError(error)) return '本地钱包数据库繁忙，请稍后重试';
  return '本地钱包读取失败：$error';
}

String walletOperationErrorMessage(Object error) {
  if (isWalletLocalStoreError(error)) return walletLocalStoreErrorMessage(error);
  if (error is CitizenSdkException) return error.message;
  return '$error';
}

/// 保留原创建成功后显示备份的顺序；准备、派生和持久提交全部由SDK执行。
/// 备份文本只在原弹窗存续期使用，不持久化、不复制到日志；普通签名不走此通道。
Future<CitizenWalletProfile> runCreateWalletFlow(
  BuildContext context, {
  required int wordCount,
  String password = '',
}) async {
  final wallet = context.read<CitizenSdk>().wallet;
  CitizenSdkPreparedWallet? prepared;
  CitizenSdkRecoveryPhrase? phrase;
  var protected = false;
  var mnemonic = '';
  try {
    prepared = await wallet.prepareCreation(
      wordCount: CitizenWalletWordCount.values.singleWhere((value) => value.value == wordCount),
      password: password,
    ).result;
    if (!context.mounted) throw const CitizenSdkException(
      code: CitizenSdkErrorCode.cancelled, message: '创建页面已关闭',
    );
    phrase = await prepared.recoveryPhrase();
    if (!context.mounted) throw const CitizenSdkException(
      code: CitizenSdkErrorCode.cancelled, message: '创建页面已关闭',
    );
    final created = await prepared.commit().result;
    if (!context.mounted) return created;
    mnemonic = utf8.decode(phrase.bytes);
    await ScreenshotGuard.enable();
    protected = true;
    if (!context.mounted) return created;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('请备份助记词'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '公民不保存助记词，关闭本弹窗后将无法再次显示。\n'
                '请立即手抄备份，或在「公民钱包」中妥善保管——这是恢复钱包'
                '与追加其他账户的唯一凭证。设置过钱包密码时，还必须单独备份密码。\n'
                '不支持复制，不支持截屏。',
              ),
              SizedBox(height: AppLayout.scaled(context, 12)),
              Text(
                mnemonic,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我已备份'),
            ),
          ],
        );
      },
    );
    return created;
  } finally {
    mnemonic = '';
    try {
      await phrase?.release();
    } finally {
      try {
        await prepared?.release();
      } finally {
        if (protected) await ScreenshotGuard.disable();
      }
    }
  }
}
