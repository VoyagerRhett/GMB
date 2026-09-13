import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/chain_progress_banner.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_models.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_service.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_transfer_call.dart';
import 'package:citizenapp/transaction/history/local_tx_store.dart';
import 'package:citizenapp/transaction/history/presentation/tx_auto_refresh_mixin.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/widgets/address_scan_button.dart';
import 'package:citizenapp/my/user/contact_book_page.dart';
import 'package:citizenapp/my/user/contact_service.dart' show UserContact;
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/wallet/pages/wallet_page.dart';
import 'package:citizenapp/transaction/history/presentation/transaction_history_page.dart';
import 'package:citizenapp/ui/app_layout.dart';

typedef OnchainPaymentExtraEntriesBuilder =
    List<Widget> Function(BuildContext context);

/// 交易表单四个输入框(收款地址 / 金额 / 币种 / 备注)共用的装饰。
///
/// [suffixIcon] 必须逐字段传入,不能写死进本函数 —— 只有收款地址需要扫码按钮,
/// 写死会让金额、币种、备注也长出图标。
///
/// 提到类外是因为它不依赖任何实例状态,且「带 suffixIcon 的收款地址框必须与不带的
/// 金额框等高」这条布局约束要由测试钉住:`isDense` 把内容高压到与 suffix 图标同高,
/// 二者相等时输入框才不会被图标撑高。
@visibleForTesting
InputDecoration transactionFieldDecoration({
  required String hintText,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AppTheme.surfaceCard,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: AppLayout.scaledValue(14),
      vertical: AppLayout.scaledValue(14),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      borderSide: const BorderSide(color: AppTheme.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      borderSide: const BorderSide(color: AppTheme.danger),
    ),
  );
}

typedef OnchainWalletPicker = Future<bool?> Function();
typedef OnchainCurrentWalletLoader =
    Future<CitizenWalletStateAccount?> Function();
typedef OnchainLocalRecordsLoader =
    Future<List<LocalTxEntity>> Function(String accountId, {int limit});
typedef OnchainContactPageBuilder = Widget Function(ContactPickMode mode);

class OnchainPaymentPage extends StatelessWidget {
  const OnchainPaymentPage({super.key, this.initialToAddress});

  /// 预填收款地址（从通讯录等入口跳转时使用）。
  final String? initialToAddress;

  @override
  Widget build(BuildContext context) {
    return OnchainPaymentPanel(
      title: '链上支付',
      initialToAddress: initialToAddress,
    );
  }
}

class OnchainPaymentPanel extends StatefulWidget {
  const OnchainPaymentPanel({
    super.key,
    this.title,
    this.chainStatusInHeader = false,
    this.initialToAddress,
    this.extraEntriesBuilder,
    this.walletPicker,
    this.currentWalletLoader,
    this.localRecordsLoader,
    this.paymentService,
    this.balanceLoader,
    this.contactPageBuilder,
  }) : assert(chainStatusInHeader || title != null, '非交易 Tab 的链上支付面板必须提供标题');

  final String? title;

  /// 交易 Tab 将真实链状态放入原页面标题位置。
  ///
  /// 默认关闭；通讯录进入的独立“链上支付”页只保留标题，链状态在后台读取。
  final bool chainStatusInHeader;

  /// 预填收款地址（从通讯录等入口跳转时使用）。
  final String? initialToAddress;

  /// 交易 Tab 可在顶栏链状态下方、链上支付表单上方插入入口。
  /// onchain 模块不直接 import offchain / multisig，跨功能编排留在 ui 层。
  final OnchainPaymentExtraEntriesBuilder? extraEntriesBuilder;

  /// 默认打开我的钱包选择页；测试或宿主页面可替换选择流程。
  final OnchainWalletPicker? walletPicker;

  /// 默认读取当前激活钱包；测试可替换为内存钱包。
  final OnchainCurrentWalletLoader? currentWalletLoader;

  /// 默认读取本地流水；测试可替换为内存流水。
  final OnchainLocalRecordsLoader? localRecordsLoader;

  /// 测试可注入；生产直接使用 CitizenSDK 钱包构造同一服务。
  final OnchainPaymentService? paymentService;
  final Future<double> Function(String accountId)? balanceLoader;

  /// 测试只记录页面意图；正式运行固定打开现有通讯录页面。
  final OnchainContactPageBuilder? contactPageBuilder;

  @override
  State<OnchainPaymentPanel> createState() => _OnchainPaymentPanelState();
}

class _OnchainPaymentPanelState extends State<OnchainPaymentPanel>
    with TxAutoRefreshMixin<OnchainPaymentPanel> {
  /// 链的 SS58 地址前缀。

  /// 链上存在性保证金（Existential Deposit）= 111 分 = 1.11 元。
  /// 来源：primitives::core_const::ACCOUNT_EXISTENTIAL_DEPOSIT = 111
  static const double _edYuan = 1.11;
  OnchainPaymentService? _paymentService;
  AccountSecurityService? _accountSecurity;
  bool _dependenciesReady = false;
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  // CitizenChain 原生币在交易页统一展示为 GMB。
  final String _selectedSymbol = 'GMB';

  CitizenWalletStateAccount? _currentWallet;
  double _currentBalance = 0;
  bool _loadingWallet = true;
  bool _submitting = false;
  CitizenChainSyncStatus? _chainProgress;
  String? _chainProgressError;

  /// 下拉刷新进行中：驱动连接状态栏 busy（触发轻节点连接即时重探）。
  bool _refreshing = false;

  /// 本地链上转账记录（用于状态行显示）。
  List<LocalTxEntity> _localTxRecords = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialToAddress != null) {
      _toController.text = widget.initialToAddress!;
    }
    _remarkController.addListener(_onRemarkChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    if (widget.currentWalletLoader != null) {
      _paymentService = widget.paymentService;
      _dependenciesReady = true;
      _bootstrap();
      return;
    }
    final sdk = context.read<CitizenSdk>();
    final accountSecurity = context.read<AccountSecurityService>();
    _paymentService =
        widget.paymentService ??
        OnchainPaymentService(
          wallet: sdk.wallet,
          transactions: sdk.transactions,
        );
    _accountSecurity = accountSecurity;
    accountSecurity.revision.addListener(_onWalletsChanged);
    _dependenciesReady = true;
    _bootstrap();
  }

  @override
  void dispose() {
    unawaited(
      stopTxAutoRefresh().catchError((Object error, StackTrace stackTrace) {
        AppLog.d('[Transaction] 链上支付 watcher 停止失败: $error\n$stackTrace');
      }),
    );
    _accountSecurity?.revision.removeListener(_onWalletsChanged);
    _remarkController.removeListener(_onRemarkChanged);
    _toController.dispose();
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  void _onWalletsChanged() {
    if (!mounted) return;
    _reloadWalletAndLocalRecords();
  }

  void _onRemarkChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _bootstrap() async {
    await _reloadWalletAndLocalRecords();
    // 交易终态由 CitizenSDK history 写入业务投影，列表经
    // TxAutoRefreshMixin 响应式重刷，不定时盲刷也不轮询 nonce。
  }

  /// 从本地 Isar 加载链上转账记录。
  Future<void> _loadLocalRecords({CitizenWalletStateAccount? wallet}) async {
    final targetWallet = wallet ?? _currentWallet;
    if (targetWallet == null) {
      if (mounted && _localTxRecords.isNotEmpty) {
        setState(() {
          _localTxRecords = [];
        });
      }
      return;
    }
    final targetAccountId = LocalTxStore.requireAccountId(
      targetWallet.accountId,
    );
    try {
      final records = await _queryLocalRecords(targetAccountId, limit: 100);
      // 钱包流水不再保存 direction，支出由 amountDeltaFen 的负号判断。
      final filtered = records
          .where(
            (r) =>
                r.type == 'transfer' &&
                BigInt.parse(r.amountDeltaFen).isNegative,
          )
          .toList();
      if (mounted) {
        final currentAccountId = _accountIdOf(_currentWallet);
        if (currentAccountId != targetAccountId) {
          return;
        }
        setState(() {
          _localTxRecords = filtered;
        });
      }
    } catch (e) {
      if (WalletIsar.instance.isBusyError(e)) {
        return;
      }
      AppLog.d('[链上交易] 加载本地记录失败: $e');
    }
  }

  @override
  Future<void> onTxRecordsChanged() => _loadLocalRecords();

  String? _accountIdOf(CitizenWalletStateAccount? wallet) {
    if (wallet == null) return null;
    return LocalTxStore.requireAccountId(wallet.accountId);
  }

  Future<List<LocalTxEntity>> _queryLocalRecords(
    String accountId, {
    int limit = 100,
  }) {
    final loader = widget.localRecordsLoader;
    if (loader != null) {
      return loader(accountId, limit: limit);
    }
    return LocalTxStore.queryByAccountId(accountId, limit: limit);
  }

  int _countByStatus(String status) {
    return _localTxRecords.where((r) => r.status == status).length;
  }

  /// `inBlock` 只是未最终化的内部进度，界面与 `pending` 统一归为“待确认”。
  int get _waitingCount => _localTxRecords
      .where(
        (record) =>
            record.status == LocalTxStore.statusPending ||
            record.status == LocalTxStore.statusInBlock,
      )
      .length;

  Future<void> _reloadWallet() async {
    CitizenWalletStateAccount? wallet;
    var balance = 0.0;
    try {
      final loader = widget.currentWalletLoader;
      wallet = loader != null
          ? await loader()
          : await _paymentService!.getCurrentWallet();
      if (wallet != null) {
        balance =
            await (widget.balanceLoader?.call(wallet.accountId) ??
                _loadFinalizedBalance(wallet.accountId));
      }
    } catch (e, st) {
      if (!WalletIsar.instance.isBusyError(e)) {
        AppLog.d('[链上交易] 当前钱包加载失败: $e\n$st');
      }
    }
    if (!mounted) {
      return;
    }
    final nextAccountId = _accountIdOf(wallet);
    final currentAccountId = _accountIdOf(_currentWallet);
    setState(() {
      _currentWallet = wallet;
      _currentBalance = balance;
      _loadingWallet = false;
      if (nextAccountId != currentAccountId) {
        _localTxRecords = [];
      }
    });
    startTxAutoRefresh(nextAccountId);
  }

  Future<double> _loadFinalizedBalance(String accountId) async {
    final balance = await context.read<CitizenSdk>().chain.getAccountBalance(
      accountId,
    );
    return balance.freeFen.toDouble() / 100;
  }

  Future<void> _reloadWalletAndLocalRecords() async {
    await _reloadWallet();
    await _loadLocalRecords();
  }

  /// 下拉刷新：余额 + 本地交易记录重载；`_refreshing` 驱动链状态读取 busy →
  /// 触发轻节点连接即时重探（ChainProgressBanner 内部 `_loadProgress`）。
  Future<void> _onPullRefresh() async {
    if (mounted) setState(() => _refreshing = true);
    try {
      await _reloadWalletAndLocalRecords();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openWalletTab() async {
    final picker = widget.walletPicker;
    final navigator = Navigator.of(context);
    final changed = picker != null
        ? await picker()
        : await navigator.push<bool>(
            MaterialPageRoute(
              builder: (_) => const WalletTab(selectForTrade: true),
            ),
          );
    if (!mounted) {
      return;
    }
    if (changed == true) {
      await _reloadWalletAndLocalRecords();
    }
  }

  Future<void> _openContactsPage() async {
    const mode = ContactPickMode.pickForTransfer;
    final contact = await Navigator.of(context).push<UserContact>(
      MaterialPageRoute(
        builder: (_) =>
            widget.contactPageBuilder?.call(mode) ??
            const ContactBookPage(mode: mode),
      ),
    );
    if (!mounted || contact == null) return;
    setState(() {
      // 通讯录始终属于身份账户；这里只接收联系人 SS58 地址，付款钱包保持不变。
      _toController.text = contact.ss58Address;
    });
  }

  Future<void> _submit() async {
    final blockedReason = _submitBlockedReason;
    if (blockedReason != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(blockedReason)));
      }
      return;
    }
    if (_loadingWallet) {
      return;
    }
    if (_currentWallet == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先创建或导入钱包')));
      await _openWalletTab();
      return;
    }

    final toSs58Address = _toController.text.trim();
    final amountRaw = _amountController.text.trim();
    if (toSs58Address.isEmpty || amountRaw.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填写完整的收款地址和金额')));
      return;
    }
    final amountText = AmountFormat.stripCommas(amountRaw);

    // SS58 地址校验（prefix 走 kGmbSs58Prefix 单源）
    try {
      final decoded = Keyring().decodeAddress(toSs58Address);
      // 验证 prefix：重新编码后比对
      final reEncoded = Keyring().encodeAddress(decoded, kGmbSs58Prefix);
      if (reEncoded != toSs58Address) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('收款地址不是本链地址（SS58 前缀不匹配）')));
        return;
      }
    } catch (e) {
      AppLog.d('[OnchainPay] 收款地址 SS58 校验失败: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('收款地址格式错误，请输入有效的 SS58 地址')));
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('金额格式不正确')));
      return;
    }
    final remark = _remarkController.text;
    final remarkBytes = utf8.encode(remark).length;
    if (remarkBytes > OnchainTransferCall.maxTransferRemarkBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '转账备注不能超过 ${OnchainTransferCall.maxTransferRemarkBytes} 字节，当前 $remarkBytes 字节',
          ),
        ),
      );
      return;
    }

    // 预估手续费，展示确认对话框
    final estimatedFee = OnchainTransferCall.estimateTransferFeeYuan(amount);

    // 余额校验：转账金额 + 手续费 ≤ 可用余额（余额 - ED）
    final availableBalance = _currentBalance - _edYuan;
    if (amount + estimatedFee > availableBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '余额不足，可用余额：${AmountFormat.format(availableBalance, symbol: '')} GMB'
            '（已扣除 ED ${AmountFormat.format(_edYuan, symbol: '')} GMB）',
          ),
        ),
      );
      return;
    }
    // 收起焦点与软键盘:确认弹窗关闭时 Flutter 会把焦点还给之前的输入框、
    // 误弹一次键盘(紧接着就是生物识别,键盘纯属多余)。进入确认流程即失焦,
    // 弹窗关闭后无焦点可恢复,键盘不再弹。
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认交易'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '转账金额：${AmountFormat.format(amount, symbol: _selectedSymbol)}',
            ),
            if (remark.isNotEmpty) ...[
              SizedBox(height: AppLayout.scaledValue(4)),
              Text('转账备注：$remark'),
            ],
            SizedBox(height: AppLayout.scaledValue(4)),
            Text(
              '预估手续费：${AmountFormat.format(estimatedFee, symbol: _selectedSymbol)}',
            ),
            Divider(height: AppLayout.scaledValue(16)),
            Text(
              '合计：${AmountFormat.format(amount + estimatedFee, symbol: _selectedSymbol)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _submitting = true;
    });
    try {
      final wallet = _currentWallet!;
      final sdk = context.read<CitizenSdk>();
      final prepared = await _paymentService!.prepareTransfer(
        OnchainPaymentDraft(
          toSs58Address: toSs58Address,
          amount: amount,
          symbol: _selectedSymbol,
          remark: remark,
        ),
      );
      final started = await sdk.transactions.executePreparedTransaction(
        prepared.preparationId,
      );
      CitizenTransactionExecutionCompleted completed;
      if (started is CitizenTransactionExternalSigningPending) {
        if (!mounted) return;
        final response = await showCitizenSdkQrResponse(
          context,
          request: started.qrRequest,
          expiresAt: BigInt.from(
            started.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        );
        if (response == null) {
          await sdk.transactions.cancelPreparedTransactionExecution(
            started.executionId,
          );
          throw const AccountSecurityException('交易签名已取消');
        }
        completed = await sdk.transactions.consumePreparedTransactionQrResponse(
          started.executionId,
          response,
        );
      } else {
        completed = started as CitizenTransactionExecutionCompleted;
      }
      if (!mounted) {
        return;
      }

      final txHash = '0x${_toHex(completed.transactionHash)}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_executionMessage(completed, txHash))),
      );
      _toController.clear();
      _amountController.clear();
      _remarkController.clear();

      // 写入本地交易记录（失败不影响交易）
      try {
        final transferAmountFen = LocalTxStore.fenFromYuan(amount);
        final feeFen = LocalTxStore.fenFromYuan(estimatedFee);
        final amountDeltaFen =
            (-(BigInt.parse(transferAmountFen) + BigInt.parse(feeFen)))
                .toString();
        await LocalTxStore.upsertLocalSubmitTransfer(
          ss58Address: wallet.ss58Address,
          accountId: wallet.accountId,
          txHash: txHash,
          amountDeltaFen: amountDeltaFen,
          transferAmountFen: transferAmountFen,
          feeFen: feeFen,
          counterpartySs58Address: toSs58Address,
          fromSs58Address: wallet.ss58Address,
          toSs58Address: toSs58Address,
          remark: remark,
          executionId: completed.executionId,
          callDataHash: '0x${_toHex(completed.callDataHash)}',
          usedNonce: prepared.nonce.toInt(),
          createdAtMillis: DateTime.now().millisecondsSinceEpoch,
          blockHash: completed.execution?.block.hash,
        );
        await _applyExecutionToLocalRecord(wallet, completed);
        if (mounted) await _loadLocalRecords();
      } catch (e) {
        AppLog.d('[交易记录] 写入本地失败: $e');
      }
    } on AccountSecurityException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } on OnchainPaymentException catch (e) {
      if (!mounted) {
        return;
      }
      final message = e.code == OnchainPaymentErrorCode.broadcastFailed
          ? '交易发送失败：${e.message}'
          : '签名失败：${e.message}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) {
        return;
      }
      AppLog.d('[链上交易] 未知异常: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('交易异常：$e')));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String _executionMessage(
    CitizenTransactionExecutionCompleted completed,
    String txHash,
  ) {
    return switch (completed.resolution) {
      CitizenTransactionResolution.finalizedSuccess => '交易已完成，tx=$txHash',
      CitizenTransactionResolution.finalizedFailed => '交易已最终失败，tx=$txHash',
      CitizenTransactionResolution.poolRejected => '交易池已拒绝，tx=$txHash',
    };
  }

  /// 只把 CitizenSDK 已核验的终态投影到 App 交易展示记录。
  /// CitizenApp 不根据 txHash、超时或页面生命周期猜测交易结果。
  Future<void> _applyExecutionToLocalRecord(
    CitizenWalletStateAccount wallet,
    CitizenTransactionExecutionCompleted completed,
  ) async {
    final txHash = '0x${_toHex(completed.transactionHash)}';
    switch (completed.resolution) {
      case CitizenTransactionResolution.finalizedSuccess:
        final execution = completed.execution;
        await LocalTxStore.markLocalSubmitFinalized(
          accountId: wallet.accountId,
          txHash: txHash,
          executionId: completed.executionId,
          callDataHash: '0x${_toHex(completed.callDataHash)}',
          blockHash: execution?.block.hash,
          blockNumber: execution?.block.number.toInt(),
          extrinsicIndex: execution?.extrinsicIndex,
        );
        break;
      case CitizenTransactionResolution.finalizedFailed:
        final execution = completed.execution;
        await LocalTxStore.markLocalSubmitFailed(
          accountId: wallet.accountId,
          txHash: txHash,
          executionId: completed.executionId,
          callDataHash: '0x${_toHex(completed.callDataHash)}',
          failureReason: execution == null
              ? '链上执行失败'
              : '链上执行失败 '
                    '${execution.palletIndex ?? '-'}:'
                    '${execution.errorIndex ?? '-'}',
        );
        break;
      case CitizenTransactionResolution.poolRejected:
        await LocalTxStore.markLocalSubmitFailed(
          accountId: wallet.accountId,
          txHash: txHash,
          executionId: completed.executionId,
          callDataHash: '0x${_toHex(completed.callDataHash)}',
          failureReason: completed.poolRejectionReason ?? '交易池拒绝',
        );
        break;
    }
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppLayout.scaledValue(8)),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: AppLayout.scaledValue(14),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStatusMetric({required String label, required int count}) {
    return Expanded(
      child: Text(
        '$label $count',
        maxLines: 1,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontSize: AppLayout.scaledValue(13),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSubmitCard() {
    return Container(
      decoration: AppTheme.cardDecoration(radius: AppTheme.radiusLg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentWallet != null)
              Padding(
                padding: EdgeInsets.only(bottom: AppLayout.scaledValue(18)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Transform.rotate(
                      angle: 0.785398,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppLayout.scaledValue(6),
                        ),
                        child: Image.asset(
                          'assets/icons/icons8-96.png',
                          width: AppLayout.scaledValue(22),
                          height: AppLayout.scaledValue(22),
                        ),
                      ),
                    ),
                    SizedBox(width: AppLayout.scaledValue(6)),
                    Text(
                      '钱包可用余额：${AmountFormat.format(_currentBalance, symbol: '')} GMB',
                      style: TextStyle(
                        fontSize: AppLayout.scaledValue(14),
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            _buildFieldLabel('收款地址'),
            TextField(
              controller: _toController,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: AppLayout.scaledValue(14),
              ),
              decoration: transactionFieldDecoration(
                hintText: '请输入账户',
                suffixIcon: AddressScanButton(
                  onAddressScanned: (ss58Address) =>
                      setState(() => _toController.text = ss58Address),
                ),
              ),
            ),
            SizedBox(height: AppLayout.scaledValue(16)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('金额'),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [ThousandSeparatorFormatter()],
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: AppLayout.scaledValue(14),
                        ),
                        decoration: transactionFieldDecoration(
                          hintText: '请输入金额',
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: AppLayout.scaledValue(12)),
                SizedBox(
                  width: AppLayout.scaledValue(112),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('币种'),
                      InputDecorator(
                        decoration: transactionFieldDecoration(hintText: ''),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 公民币标志只辅助识别；GMB 文本继续承担币种语义与无障碍朗读。
                            ExcludeSemantics(
                              child: Image.asset(
                                'assets/icons/gmb-mark.png',
                                width: 18,
                                height: 18,
                                color: AppTheme.primary,
                                colorBlendMode: BlendMode.srcIn,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            SizedBox(width: AppLayout.scaledValue(6)),
                            Text(
                              'GMB',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: AppLayout.scaledValue(14),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: AppLayout.scaledValue(16)),
            _buildFieldLabel('转账备注（选填）'),
            Stack(
              children: [
                TextField(
                  controller: _remarkController,
                  minLines: 3,
                  maxLines: 3,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: AppLayout.scaledValue(14),
                  ),
                  decoration:
                      transactionFieldDecoration(
                        hintText: '请输入转账备注（选填）',
                      ).copyWith(
                        contentPadding: const EdgeInsets.fromLTRB(
                          14,
                          14,
                          14,
                          32,
                        ),
                        errorText:
                            _transferRemarkBytes >
                                OnchainTransferCall.maxTransferRemarkBytes
                            ? '备注不能超过 ${OnchainTransferCall.maxTransferRemarkBytes} 字节'
                            : null,
                      ),
                ),
                Positioned(
                  right: AppLayout.scaledValue(12),
                  bottom: AppLayout.scaledValue(10),
                  child: Text(
                    '$_transferRemarkBytes/${OnchainTransferCall.maxTransferRemarkBytes} 字节',
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(12),
                      color:
                          _transferRemarkBytes >
                              OnchainTransferCall.maxTransferRemarkBytes
                          ? AppTheme.danger
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppLayout.scaledValue(14)),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                child: Text(_submitting ? '签名中' : '签名交易'),
              ),
            ),
            if (_submitBlockedReason != null &&
                !_loadingWallet &&
                _currentWallet != null)
              Padding(
                padding: EdgeInsets.only(top: AppLayout.scaledValue(8)),
                child: Text(
                  _submitBlockedReason!,
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(12),
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(
                top: AppLayout.scaledValue(18),
                bottom: AppLayout.scaledValue(12),
              ),
              child: const Divider(color: AppTheme.divider),
            ),
            // 展示口径只有三态；inBlock 未获最终性确认，归入“待确认”。
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildStatusMetric(label: '待确认', count: _waitingCount),
                SizedBox(
                  height: AppLayout.scaledValue(18),
                  child: const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppTheme.divider,
                  ),
                ),
                _buildStatusMetric(
                  label: '已确认',
                  count: _countByStatus(LocalTxStore.statusFinalized),
                ),
                SizedBox(
                  height: AppLayout.scaledValue(18),
                  child: const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppTheme.divider,
                  ),
                ),
                _buildStatusMetric(
                  label: '失败',
                  count: _countByStatus(LocalTxStore.statusFailed),
                ),
                InkWell(
                  onTap: _currentWallet != null
                      ? () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TransactionHistoryPage(
                                ss58Address: _currentWallet!.ss58Address,
                                accountId: _currentWallet!.accountId,
                              ),
                            ),
                          );
                        }
                      : null,
                  borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
                  child: Padding(
                    padding: EdgeInsets.all(AppLayout.scaledValue(6)),
                    child: Icon(
                      Icons.chevron_right,
                      size: AppLayout.scaledValue(22),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '我的通讯录',
                    onPressed: _openContactsPage,
                    icon: SvgPicture.asset(
                      'assets/icons/contact-round.svg',
                      width: AppLayout.scaled(context, 22),
                      height: AppLayout.scaled(context, 22),
                      colorFilter: const ColorFilter.mode(
                        AppTheme.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: widget.chainStatusInHeader
                          ? ChainProgressBanner(
                              margin: EdgeInsets.zero,
                              busy: _refreshing,
                              showInlineStatus: true,
                              onProgressChanged: _handleChainProgressChanged,
                              onErrorChanged: _handleChainProgressErrorChanged,
                            )
                          : Text(
                              widget.title!,
                              style: TextStyle(
                                fontSize: AppLayout.scaled(context, 20),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  IconButton(
                    tooltip: '选择交易钱包',
                    onPressed: _openWalletTab,
                    icon: SvgPicture.asset(
                      'assets/icons/wallet.svg',
                      width: AppLayout.scaled(context, 22),
                      height: AppLayout.scaled(context, 22),
                      colorFilter: const ColorFilter.mode(
                        AppTheme.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.chainStatusInHeader)
              ChainProgressBanner(
                busy: _refreshing,
                onProgressChanged: _handleChainProgressChanged,
                onErrorChanged: _handleChainProgressErrorChanged,
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onPullRefresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
                  children: [
                    if (widget.extraEntriesBuilder != null)
                      ...widget.extraEntriesBuilder!(context),
                    if (_currentWallet == null && !_loadingWallet)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: AppLayout.scaled(context, 12),
                        ),
                        child: Container(
                          decoration: AppTheme.cardDecoration(),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('未检测到钱包，无法执行链上签名与交易广播'),
                                SizedBox(height: AppLayout.scaled(context, 8)),
                                FilledButton(
                                  onPressed: _openWalletTab,
                                  child: const Text('去创建/导入钱包'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    _buildSubmitCard(),
                    SizedBox(height: AppLayout.scaled(context, 24)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleChainProgressChanged(CitizenChainSyncStatus? progress) {
    if (!mounted) return;
    setState(() {
      _chainProgress = progress;
    });
  }

  void _handleChainProgressErrorChanged(String? error) {
    if (!mounted) return;
    setState(() {
      _chainProgressError = error;
    });
  }

  int get _transferRemarkBytes => utf8.encode(_remarkController.text).length;

  bool get _canSubmit =>
      !_submitting &&
      !_loadingWallet &&
      _currentWallet != null &&
      _submitBlockedReason == null;

  String? get _submitBlockedReason {
    if (_submitting || _loadingWallet || _currentWallet == null) {
      return null;
    }
    if (_transferRemarkBytes > OnchainTransferCall.maxTransferRemarkBytes) {
      return '转账备注不能超过 ${OnchainTransferCall.maxTransferRemarkBytes} 字节';
    }

    final progress = _chainProgress;
    if (progress == null) {
      return _chainProgressError ?? '正在读取区块链状态，请稍后再试';
    }
    if (progress.peerCount == BigInt.zero) {
      return '轻节点尚未连接到区块链网络，请等待至少 1 个 peer';
    }
    if (progress.isSyncing) {
      return '轻节点仍在验证或同步链状态，完成后才能签名交易';
    }
    if (!progress.isUsable) {
      return _chainProgressError ?? '区块链状态尚未就绪，请稍后再试';
    }
    return null;
  }
}

String _toHex(List<int> bytes) {
  const chars = '0123456789abcdef';
  final buf = StringBuffer();
  for (final b in bytes) {
    buf
      ..write(chars[(b >> 4) & 0x0f])
      ..write(chars[b & 0x0f]);
  }
  return buf.toString();
}
