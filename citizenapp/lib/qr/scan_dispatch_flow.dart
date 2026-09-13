import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';

import 'package:citizenapp/citizen/shared/account_derivation.dart'
    show ss58FromAccountIdText;
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/qr/pages/qr_scan_page.dart';
import 'package:citizenapp/qr/pages/qr_sign_response_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/signer/square_action_sign_service.dart';
import 'package:citizenapp/signer/citizen_identity_sign_service.dart';
import 'package:citizenapp/signer/citizen_occupy_sign_service.dart';
import 'package:citizenapp/signer/app_business_qr_codec.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/myid/myid_service.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/transaction/offchain-transaction/services/offchain_scan_flow.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 聊天 tab「扫一扫」统一入口：扫码 → 按协议分派。
///
/// - 收款 / 链下支付码 → 现有链下支付流程（用 [paymentWallet]）。
/// - signRequest → 用 QR `u` 对应的本机 CitizenWalletStateAccount 签名，与付款钱包无关。
/// - 未来其它类型只需在此加分支。
///
/// 交易页不再走本分发器：那里的扫码收进收款地址输入框（[AddressScanButton]），
/// 只填地址；签名请求（广场账户动作 / 公民身份 / 注册局占号换绑）统一由本入口承接。
Future<void> openScanDispatchFlow({
  required BuildContext context,
  required CitizenWalletStateAccount? paymentWallet,
  CitizenWalletStateAccount? signingAccount,
}) async {
  final scanned = await Navigator.of(context).push<Object?>(
    MaterialPageRoute(
      builder: (_) => const QrScanPage(mode: QrScanMode.dispatch),
    ),
  );
  if (scanned == null || !context.mounted) return;

  if (scanned is QrScanTransferResult) {
    // 支付分支：此处才要求付款钱包（签名分支不需要）。
    if (paymentWallet == null) {
      _snack(context, '请先选择付款钱包');
      return;
    }
    await proceedOffchainPayment(
      context: context,
      wallet: paymentWallet,
      result: scanned,
    );
    return;
  }
  if (scanned is String) {
    await _dispatchSignRequest(context, scanned, signingAccount);
  }
}

/// 我的钱包账户卡“扫码签名”：保留扫码页原 UI，只把业务边界收紧为签名请求。
///
/// 扫码页先由 CitizenSDK 识别通用请求；CitizenApp 专用请求则由
/// [AppBusinessQrCodec.parseRequest] 校验业务字段和有效期。
Future<void> openAccountScanSignFlow({
  required BuildContext context,
  required CitizenWalletStateAccount account,
}) async {
  final scanned = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) =>
          const QrScanPage(mode: QrScanMode.signRequest, customTitle: '扫码签名'),
    ),
  );
  if (scanned == null || !context.mounted) return;
  await _dispatchSignRequest(context, scanned, account);
}

Future<void> _dispatchSignRequest(
  BuildContext context,
  String raw,
  CitizenWalletStateAccount? requiredAccount,
) async {
  final int action;
  try {
    action = AppBusinessQrCodec().parseRequest(raw).body.action;
  } on AppBusinessQrException catch (error) {
    if (context.mounted) _snack(context, '请扫描公民 App 业务签名请求：${error.message}');
    return;
  }
  if (action == QrActions.citizenIdentity) {
    await _handleCitizenIdentitySignRequest(context, raw, requiredAccount);
  } else if (QrActions.isSelfAccountDomainAction(action)) {
    await _handleOccupySignRequest(context, raw, requiredAccount);
  } else {
    await _handleSquareActionSignRequest(context, raw, requiredAccount);
  }
}

Future<void> _handleSquareActionSignRequest(
  BuildContext context,
  String raw,
  CitizenWalletStateAccount? requiredAccount,
) async {
  final service = SquareActionSignService();
  final sdk = context.read<CitizenSdk>();

  final SquareActionSignPrep prep;
  try {
    prep = await service.prepare(
      raw,
      sdk.wallet,
      requiredAccount: requiredAccount,
    );
  } on SquareActionSignException catch (e) {
    if (context.mounted) _snack(context, e.message);
    return;
  }
  if (!context.mounted) return;

  final confirmed = await _showActionConfirm(context, prep);
  if (confirmed != true || !context.mounted) return;

  final String responseJson;
  try {
    // 动钱动权 → 读硬件金库、弹一次生物识别。
    responseJson = await service.sign(prep, sdk.signing, context);
  } on AccountSecurityException catch (e) {
    if (context.mounted) _snack(context, e.message);
    return;
  } on Exception catch (e) {
    // 兜底：任何签名异常都必须有反馈，永不静默。
    if (context.mounted) _snack(context, '签名失败：$e');
    return;
  }
  if (!context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => QrSignResponsePage(
        responseJson: responseJson,
        actionLabel: prep.actionLabel,
        reviewEntries: prep.decoded.reviewFields!
            .map((field) => (field.label, field.value))
            .toList(),
      ),
    ),
  );
}

Future<void> _handleCitizenIdentitySignRequest(
  BuildContext context,
  String raw,
  CitizenWalletStateAccount? signingAccount,
) async {
  final service = CitizenIdentitySignService();
  final sdk = context.read<CitizenSdk>();
  try {
    final prep = await service.prepare(
      raw,
      sdk.wallet,
      requiredAccount: signingAccount,
    );
    if (!context.mounted) return;
    final fields = prep.decoded.reviewEntries;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(prep.actionLabel),
        content: Text(
          fields.map((field) => '${field.$1}：${field.$2}').join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认签名'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final response = await service.sign(prep, sdk.signing, context);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrSignResponsePage(
          responseJson: response,
          actionLabel: prep.actionLabel,
          reviewEntries: fields,
        ),
      ),
    );
  } on CitizenIdentitySignException catch (error) {
    if (context.mounted) _snack(context, error.message);
  } on AccountSecurityException catch (error) {
    if (context.mounted) _snack(context, error.message);
  } on Exception catch (error) {
    if (context.mounted) _snack(context, '签名失败：$error');
  }
}

/// 注册局占号/换绑：请求 b.u 留空，完整授权模板内的账户槽必须为零；用户选择本机
/// 热账户后，服务把账户原位填入并签名。确认页展示全部防重放字段，禁止盲签。
Future<void> _handleOccupySignRequest(
  BuildContext context,
  String raw,
  CitizenWalletStateAccount? requiredAccount,
) async {
  final sdk = context.read<CitizenSdk>();
  final accountSecurity = context.read<AccountSecurityService>();
  final currentUserContext = context.read<CurrentUserContext>();
  final service = CitizenOccupySignService();

  final selected =
      requiredAccount ?? await _pickBindingAccount(context, sdk.wallet);
  if (selected == null || !context.mounted) return;

  try {
    final prep = await service.prepare(raw, selected, sdk.wallet);
    if (!context.mounted) return;
    final reviewEntries = <(String, String)>[
      ('创世哈希', prep.genesisHash),
      ('身份CID', prep.cidNumber),
      if (prep.currentAccountId != null)
        ('当前绑定账户', ss58FromAccountIdText(prep.currentAccountId!)),
      ('预期绑定版本', prep.expectedBindingRevision.toString()),
      ('过期时间（Unix 秒）', prep.expiresAt.toString()),
      (prep.isOccupy ? '绑定账户' : '新绑定账户', prep.account.ss58Address),
    ];
    final reviewText = reviewEntries
        .map((entry) => '${entry.$1}：${entry.$2}')
        .join('\n');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(prep.actionLabel),
        content: SingleChildScrollView(
          child: SelectableText(
            '${prep.isOccupy ? '把此 CID 占号绑定到你的账户' : '把此 CID 换绑到你的新账户'}\n'
            '$reviewText',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认签名'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final response = await service.sign(prep, sdk.signing, context);
    if (!prep.isOccupy && prep.currentAccount != null) {
      if (!context.mounted) return;
      final sessionProvider = context.read<SquareSessionProvider>();
      final chain = context.read<CitizenSdk>().chain;
      final chatRuntime = context.read<ChatSdk>();
      final source = AccountDataBinding(
        genesisHash: prep.genesisHash,
        cidNumber: prep.cidNumber,
        bindingRevision: prep.expectedBindingRevision.toInt(),
        accountId: prep.currentAccount!.accountId,
      );
      final target = AccountDataBinding(
        genesisHash: prep.genesisHash,
        cidNumber: prep.cidNumber,
        bindingRevision: source.bindingRevision + 1,
        accountId: prep.account.accountId,
      );
      final handover = CidAccountDataHandover(
        contactService: UserContactService(
          accountSecurity: accountSecurity,
          currentUserContext: currentUserContext,
          sessionProvider: sessionProvider,
          chainReader: CitizenIdentityChainReader(chain: chain),
          autoSync: false,
        ),
        accountSecurity: accountSecurity,
        chatRuntime: chatRuntime,
      );
      await handover.stage(source: source, target: target);
      // 注册局后续冷签上链无需用户再次扫码；本 App 在后台只等待 finalized 目标绑定，
      // 命中后提交同一次扫码已暂存的新账户密文。退出 App 时公开交接清单仍可在下次
      // 身份门禁就位时续接，不依赖此前设备进程持续存活。
      unawaited(
        _completeRegistryHandover(
          chain: chain,
          accountSecurity: accountSecurity,
          handover: handover,
          target: target,
          expiresAt: prep.expiresAt.toInt(),
        ),
      );
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrSignResponsePage(
          responseJson: response,
          actionLabel: prep.actionLabel,
          reviewEntries: reviewEntries,
        ),
      ),
    );
  } on CitizenOccupySignException catch (error) {
    if (context.mounted) _snack(context, error.message);
  } on AccountSecurityException catch (error) {
    if (context.mounted) _snack(context, error.message);
  } on Exception catch (error) {
    if (context.mounted) _snack(context, '签名失败：$error');
  }
}

Future<void> _completeRegistryHandover({
  required CitizenChain chain,
  required AccountSecurityService accountSecurity,
  required CidAccountDataHandover handover,
  required AccountDataBinding target,
  required int expiresAt,
}) async {
  final reader = CitizenIdentityChainReader(chain: chain);
  while (DateTime.now().millisecondsSinceEpoch ~/ 1000 <= expiresAt + 600) {
    try {
      final current = await reader.readBindingByCidNumber(target.cidNumber);
      if (current?.accountIdText == target.accountId &&
          current?.bindingRevision == target.bindingRevision) {
        final previous = await accountSecurity.readAccountDataBindingForCid(
          target.cidNumber,
        );
        await accountSecurity.activateAccountDataBinding(
          genesisHash: target.genesisHash,
          cidNumber: target.cidNumber,
          bindingRevision: target.bindingRevision,
          accountId: target.accountId,
        );
        await handover.prepareFinalizedBinding(
          current: target,
          previous: previous,
        );
        // finalized 只完成公开绑定与数据交接；设备数据钥按真实数据缺钥生成，P-256
        // 子钥只在 Worker 明确报告未登记时登记，禁止在此额外读取目标账户 child。
        await handover.completeFinalizedBinding(target);
        accountSecurity.notifyIdentityBindingChanged();
        return;
      }
      if (current != null && current.bindingRevision > target.bindingRevision) {
        return;
      }
    } catch (_) {
      // 链暂不可用时继续等待；交接清单仍在本地，绝不回退或清掉此前密文。
    }
    await Future<void>.delayed(const Duration(seconds: 5));
  }
}

/// 通用扫一扫遇到占号/换绑时，从唯一热钱包的全部账户中选一个；账户卡入口则直接
/// 使用卡片账户，不进入本选择器。
Future<CitizenWalletStateAccount?> _pickBindingAccount(
  BuildContext context,
  CitizenSdkWallet wallet,
) async {
  final accounts = (await wallet.getState()).accounts;
  if (!context.mounted) return null;
  if (accounts.isEmpty) {
    _snack(context, '本机没有可绑定的钱包账户');
    return null;
  }
  return showModalBottomSheet<CitizenWalletStateAccount>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.all(AppLayout.scaledValue(16)),
            child: Text(
              '选择要绑定到该 CID 的账户',
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 16),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final account in accounts)
            ListTile(
              title: Text(account.name),
              subtitle: Text(_shortAddress(account.ss58Address)),
              onTap: () => Navigator.of(sheetContext).pop(account),
            ),
          SizedBox(height: AppLayout.scaled(context, 8)),
        ],
      ),
    ),
  );
}

Future<bool?> _showActionConfirm(
  BuildContext context,
  SquareActionSignPrep prep,
) {
  final fieldLines = prep.decoded.reviewFields!
      .map((field) => '${field.label}：${field.value}')
      .join('\n');
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认签名'),
      content: Text(
        '账户：${_shortAddress(prep.account.ss58Address)}\n'
        '动作：${prep.actionLabel}\n'
        '$fieldLines\n\n'
        '确认后将用本机钱包对此操作签名。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('确认签名'),
        ),
      ],
    ),
  );
}

String _shortAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 6)}…${address.substring(address.length - 6)}';
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
