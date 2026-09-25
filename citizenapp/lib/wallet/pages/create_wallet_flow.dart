import 'dart:async';
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

/// 只负责原备份界面的可见期；系统认证尚未显示秘密时允许临时失焦。
class _WalletBackupLifecycle extends WidgetsBindingObserver {
  _WalletBackupLifecycle(this.revoke, this.isVisible);
  final VoidCallback revoke;
  final bool Function() isVisible;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    if (state == AppLifecycleState.inactive && !isVisible()) return;
    revoke();
  }
}

/// 保留原创建成功后显示备份的顺序；准备、派生和持久提交全部由SDK执行。
/// 备份文本只在原弹窗存续期使用，不持久化、不复制到日志；普通签名不走此通道。
Future<CitizenWalletProfile> runCreateWalletFlow(
  BuildContext context, {
  required int wordCount,
  String password = '',
}) async {
  final sdk = context.read<CitizenSdk>();
  final wallet = sdk.wallet;
  CitizenSdkPreparedWallet? prepared;
  CitizenSdkRecoveryPhrase? phrase;
  var protected = false;
  var mnemonic = '';
  var revoked = false;
  ModalRoute<void>? backupRoute;
  StreamSubscription<CitizenSdkEvent>? walletEvents;
  BigInt? baselineRevision;
  BigInt? observedRevision;
  void revoke() {
    revoked = true;
    mnemonic = '';
    final route = backupRoute;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
    final owned = phrase;
    if (owned != null) unawaited(owned.release().catchError((Object _) {}));
  }
  final lifecycle = _WalletBackupLifecycle(revoke, () => backupRoute != null);
  WidgetsBinding.instance.addObserver(lifecycle);
  try {
    prepared = await wallet.prepareCreation(
      wordCount: CitizenWalletWordCount.values.singleWhere((value) => value.value == wordCount),
      password: password,
    ).result;
    if (!context.mounted || revoked) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.cancelled, message: '创建页面已关闭',
      );
    }
    phrase = await prepared.recoveryPhrase();
    if (!context.mounted || revoked) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.cancelled, message: '创建页面已关闭',
      );
    }
    final created = await prepared.commit().result;
    if (!context.mounted || revoked) return created;
    bool isOwner(CitizenWalletState state) =>
        state.hotProfile?.walletIndex == created.walletIndex &&
        state.hotProfile?.masterAccountId == created.masterAccountId &&
        state.hotProfile?.createdAtMillis == created.createdAtMillis;
    Future<void> checkOwner() async {
      try {
        final state = await wallet.getState().result;
        if (revoked) return;
        if (observedRevision == null || state.revision > observedRevision!) {
          observedRevision = state.revision;
        }
        if (!isOwner(state) ||
            (baselineRevision != null && state.revision > baselineRevision)) {
          revoke();
        }
      } catch (_) {
        // 无法确认归属时关闭显示；不把读取失败当成空钱包或撤销真实提交。
        revoke();
      }
    }
    walletEvents = sdk.events.listen((event) {
      if (event is CitizenSdkWalletChanged) unawaited(checkOwner());
    }, onError: (Object _) => revoke());
    final CitizenWalletState state;
    try {
      state = await wallet.getState().result;
    } catch (_) {
      revoke();
      return created;
    }
    baselineRevision = state.revision;
    if (!isOwner(state) ||
        (observedRevision != null && observedRevision! > state.revision)) {
      revoke();
    }
    if (!context.mounted || revoked) return created;
    mnemonic = utf8.decode(phrase.bytes);
    await ScreenshotGuard.enable();
    protected = true;
    if (!context.mounted || revoked) return created;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        backupRoute = ModalRoute.of<void>(context);
        // showDialog接纳与首次build之间也可能退后台；不得再展示迟到秘密。
        if (revoked) scheduleMicrotask(revoke);
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
    revoked = true;
    mnemonic = '';
    WidgetsBinding.instance.removeObserver(lifecycle);
    await walletEvents?.cancel();
    backupRoute = null;
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
