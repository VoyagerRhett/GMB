import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:citizenapp/ui/widgets/wallet_password.dart';
import 'package:citizenapp/my/util/screenshot_guard.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/bip39_input.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 「添加账户」两模式：下一个序号 / 指定序号。
enum AddAccountMode { next, specify }

/// 弹出「添加账户」底部面板；成功追加返回 `true`，否则返回 `null`。
///
/// [mode] 固定本次添加口径：`next`=添加下一个账户；`specify`=添加指定账户。
/// 由「我的钱包」列表右上角「＋」的两个入口分别指定，面板内不再切换。
Future<bool?> showAddAccountSheet(
  BuildContext context, {
  required String masterId,
  required AddAccountMode mode,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AddAccountSheet(masterId: masterId, mode: mode),
  );
}

/// 无根多账户追加面板：录入本钱包助记词与可选 password →（按固定 [mode]）添加账户。
///
/// 无根设备不保存助记词或 password，追加账户须重新录入；[CitizenSdkWallet.addAccounts]
/// SDK在真实操作门内核对输入归属当前唯一热钱包；[masterId]只标识原面板的展示上下文。
class AddAccountSheet extends StatefulWidget {
  const AddAccountSheet({
    super.key,
    required this.masterId,
    required this.mode,
  });

  final String masterId;

  /// 固定的添加模式(由钱包列表「＋」的两个入口分别指定,面板内不再切换)。
  final AddAccountMode mode;

  @override
  State<AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<AddAccountSheet> {
  CitizenSdkWallet get _wallet => context.read<CitizenSdk>().wallet;
  final TextEditingController _mnemonicController = TextEditingController();
  final TextEditingController _indexController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  int? _nextIndex;
  bool _submitting = false;
  String? _error;
  CitizenSdkOperation<CitizenWalletProfile>? _operation;

  @override
  void initState() {
    super.initState();
    // 面板承载助记词与可选钱包密码，整个显示周期都禁止截屏和录屏。
    unawaited(ScreenshotGuard.enable());
    _loadNextIndex();
  }

  @override
  void dispose() {
    final operation = _operation;
    if (operation != null) unawaited(operation.cancel().then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    unawaited(ScreenshotGuard.disable());
    _mnemonicController.clear();
    _indexController.clear();
    _passwordController.clear();
    _mnemonicController.dispose();
    _indexController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadNextIndex() async {
    try {
      final state = await _wallet.getState().result;
      if (!mounted) return;
      setState(() => _nextIndex = state.hotProfile?.nextAccountIndex);
    } catch (_) {
      // 拿不到下一个序号只影响副标题展示，不阻塞添加（addNextAccount 内部会自算）。
    }
  }

  String _describeError(Object error) {
    // 展示稳定中文类别，不把原生金库描述或调用细节直接交给用户。
    if (error is CitizenSdkException) {
      return switch (error.code) {
        CitizenSdkErrorCode.keyInvalidated => '钱包安全密钥不可用，无法添加账户',
        CitizenSdkErrorCode.authenticationCancelled || CitizenSdkErrorCode.cancelled => '已取消添加账户',
        CitizenSdkErrorCode.authenticationRequired => '请完成设备认证，并确认助记词和钱包密码属于当前钱包',
        CitizenSdkErrorCode.invalidArgument => '请检查助记词、钱包密码和账户序号',
        CitizenSdkErrorCode.conflict => '钱包状态已变化，请重新打开添加账户',
        CitizenSdkErrorCode.busy => '钱包正在处理其他操作，请稍后重试',
        CitizenSdkErrorCode.storage => '账户保存失败，请重试',
        _ => '添加账户失败，请重试',
      };
    }
    return '添加账户失败，请重试';
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final mnemonic = _mnemonicController.text;
      final password = _passwordController.text;
      await validateWalletPasswordInput(context, password);
      if (!mounted) return;
      if (widget.mode == AddAccountMode.next) {
        final operation = _wallet.addNextAccount(
          mnemonic: mnemonic,
          password: password,
        );
        _operation = operation;
        await operation.result;
      } else {
        final parsed = CitizenWalletAccountIndices.parse(_indexController.text);
        if (parsed.indices == null || parsed.indices!.isEmpty) {
          setState(() => _error = parsed.invalidToken == null
              ? '请输入至少一个账户序号' : '序号必须是数字：${parsed.invalidToken}');
          return;
        }
        final operation = _wallet.addAccounts(
          mnemonic: mnemonic,
          indices: parsed.indices!,
          password: password,
        );
        _operation = operation;
        await operation.result;
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _describeError(e));
    } finally {
      _operation = null;
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: AppLayout.scaled(context, 36),
                  height: AppLayout.scaled(context, 4),
                  margin:
                      EdgeInsets.only(bottom: AppLayout.scaled(context, 16)),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius:
                        BorderRadius.circular(AppLayout.scaledValue(2)),
                  ),
                ),
              ),
              Text(
                widget.mode == AddAccountMode.next ? '添加下一个账户' : '添加指定账户',
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 17),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 6)),
              Text(
                '无根设备不保存助记词或密码，追加账户需重新录入两者校验归属。',
                style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    color: AppTheme.textSecondary),
              ),
              SizedBox(height: AppLayout.scaled(context, 12)),
              Bip39InputField(controller: _mnemonicController, wordCount: 0),
              SizedBox(height: AppLayout.scaled(context, 12)),
              WalletPasswordField(controller: _passwordController),
              SizedBox(height: AppLayout.scaled(context, 16)),
              if (widget.mode == AddAccountMode.next)
                Text(
                  _nextIndex == null ? '将派生下一个账户' : '将派生 //$_nextIndex',
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    color: AppTheme.textSecondary,
                  ),
                )
              else
                TextField(
                  controller: _indexController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: '账户序号',
                    hintText: '空格分隔，如 1 5 9',
                    helperText: '连续或断续均可，范围 1–1989',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (_error != null) ...[
                SizedBox(height: AppLayout.scaled(context, 12)),
                Text(
                  _error!,
                  style: TextStyle(
                      color: AppTheme.danger,
                      fontSize: AppLayout.scaled(context, 13)),
                ),
              ],
              SizedBox(height: AppLayout.scaled(context, 16)),
              SizedBox(
                width: double.infinity,
                height: AppLayout.scaled(context, 46),
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(_submitting ? '添加中…' : '确认添加'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
