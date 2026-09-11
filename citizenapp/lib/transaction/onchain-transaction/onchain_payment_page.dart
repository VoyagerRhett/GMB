import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter/services.dart';
import 'package:smoldot/smoldot.dart' show LightClientStatusSnapshot;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/chain_progress_banner.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_models.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_service.dart';
import 'package:citizenapp/rpc/chain_rpc.dart';
import 'package:citizenapp/transaction/history/chain/wallet_transaction_history_sync.dart';
import 'package:citizenapp/rpc/transfer_rpc.dart';
import 'package:citizenapp/transaction/history/data/local_tx_store.dart';
import 'package:citizenapp/transaction/history/presentation/tx_auto_refresh_mixin.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/qr/widgets/address_scan_button.dart';
import 'package:citizenapp/signer/qr_signer.dart';
import 'package:citizenapp/my/user/contact_book_page.dart';
import 'package:citizenapp/my/user/contact_service.dart' show UserContact;
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/wallet/core/wallet_manager.dart';
import 'package:citizenapp/wallet/pages/wallet_page.dart';
import 'package:citizenapp/transaction/history/presentation/transaction_history_page.dart';
import 'package:citizenapp/ui/app_layout.dart';

typedef OnchainPaymentExtraEntriesBuilder = List<Widget> Function(
  BuildContext context,
);

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
        vertical: AppLayout.scaledValue(14)),
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
typedef OnchainCurrentWalletLoader = Future<WalletProfile?> Function();
typedef OnchainLocalRecordsLoader = Future<List<LocalTxEntity>> Function(
  String accountId, {
  int limit,
});

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
  }) : assert(
          chainStatusInHeader || title != null,
          '非交易 Tab 的链上支付面板必须提供标题',
        );

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

  @override
  State<OnchainPaymentPanel> createState() => _OnchainPaymentPanelState();
}

class _OnchainPaymentPanelState extends State<OnchainPaymentPanel>
    with TxAutoRefreshMixin<OnchainPaymentPanel> {
  /// 链的 SS58 地址前缀。

  /// 链上存在性保证金（Existential Deposit）= 111 分 = 1.11 元。
  /// 来源：primitives::core_const::ACCOUNT_EXISTENTIAL_DEPOSIT = 111
  static const double _edYuan = 1.11;
  final OnchainPaymentService _paymentService = OnchainPaymentService();
  final ChainRpc _chainRpc = ChainRpc();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  // CitizenChain 原生币在交易页统一展示为 GMB。
  final String _selectedSymbol = 'GMB';

  WalletProfile? _currentWallet;
  bool _loadingWallet = true;
  bool _submitting = false;
  LightClientStatusSnapshot? _chainProgress;
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
    // 本页常驻 IndexedStack;在「我的→钱包」增删/清空钱包后经
    // walletsRevision 广播重读当前交易钱包(纯本地 Isar),
    // 避免付款方停留在已删除的钱包上导致签名报错。
    WalletManager.walletsRevision.addListener(_onWalletsChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    unawaited(
      stopTxAutoRefresh().catchError((Object error, StackTrace stackTrace) {
        AppLog.d('[Transaction] 链上支付 watcher 停止失败: $error\n$stackTrace');
      }),
    );
    WalletManager.walletsRevision.removeListener(_onWalletsChanged);
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
    // 交易确认由 ChainTxMonitor 写库、列表经 TxAutoRefreshMixin 响应式重刷,
    // 不再定时盲刷、也不发 nonce 轮询确认 RPC。
  }

  /// 从本地 Isar 加载链上转账记录。
  Future<void> _loadLocalRecords({WalletProfile? wallet}) async {
    final targetWallet = wallet ?? _currentWallet;
    if (targetWallet == null) {
      if (mounted && _localTxRecords.isNotEmpty) {
        setState(() {
          _localTxRecords = [];
        });
      }
      return;
    }
    final targetAccountId =
        LocalTxStore.requireAccountId(targetWallet.accountId);
    try {
      final records = await _queryLocalRecords(
        targetAccountId,
        limit: 100,
      );
      // 钱包流水不再保存 direction，支出由 amountDeltaFen 的负号判断。
      final filtered = records
          .where((r) =>
              r.type == 'transfer' && BigInt.parse(r.amountDeltaFen).isNegative)
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

  String? _accountIdOf(WalletProfile? wallet) {
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
      .where((record) =>
          record.status == LocalTxStore.statusPending ||
          record.status == LocalTxStore.statusInBlock)
      .length;

  /// 只有交易池「确定性拒绝」才算失败。
  ///
  /// `dropped`（被交易池剔除：mempool 已满或优先级过低）对 smoldot 只是「停止
  /// 跟踪」，交易可能仍在其它节点的池中并最终进块，因此**不算失败**：改由 dropped
  /// 分支保持「待确认」，再由 ChainTxMonitor 按 txHash 在最终块里认到后就地翻已确认。
  bool _isDefinitivePoolFailure(TxPoolWatchKind kind) {
    return kind == TxPoolWatchKind.invalid || kind == TxPoolWatchKind.usurped;
  }

  Future<void> _applyWatchEventToLocalRecord({
    required TxPoolWatchEvent event,
    required WalletProfile wallet,
    required String txHash,
  }) async {
    if (_isDefinitivePoolFailure(event.kind)) {
      await LocalTxStore.markLocalSubmitFailed(
        accountId: wallet.accountId,
        txHash: txHash,
        failureReason: event.description,
      );
    } else if (event.kind == TxPoolWatchKind.retracted ||
        event.kind == TxPoolWatchKind.dropped) {
      // retracted：非最终区块被回滚。dropped：被交易池剔除（mempool 已满或优先级
      // 过低），对 smoldot 只是停止跟踪，交易可能仍在其它节点池中并最终进块。
      // 两者都只保持「待确认」；最终性由 ChainTxMonitor 按 txHash 精确认（唯一那条
      // 记录就地翻已确认），绝不误判失败、绝不另建第二条。
      await LocalTxStore.markLocalSubmitPending(
        accountId: wallet.accountId,
        txHash: txHash,
      );
    } else if (event.kind == TxPoolWatchKind.finalized) {
      // finalized 先证明“不会回滚”，再按 txHash 定位该笔 extrinsic，
      // 只读取同一 extrinsic index 的失败事件，避免误用同块其它交易的错误。
      await LocalTxStore.markLocalSubmitInBlock(
        accountId: wallet.accountId,
        txHash: txHash,
        blockHash: event.blockHashHex,
      );
      final blockHash = event.blockHashHex;
      if (blockHash != null && blockHash.isNotEmpty) {
        try {
          final extrinsicIndex =
              await _chainRpc.findSubmittedExtrinsicIndexAtFinalizedBlock(
            blockHashHex: blockHash,
            txHashHex: txHash,
          );
          if (extrinsicIndex != null) {
            final events = await _chainRpc.fetchSystemEventsAtBlock(blockHash);
            final failure = events == null
                ? null
                : _chainRpc.findExtrinsicFailureInEvents(
                    events,
                    extrinsicIndex: extrinsicIndex,
                  );
            if (failure != null) {
              await LocalTxStore.markLocalSubmitFailed(
                accountId: wallet.accountId,
                txHash: txHash,
                failureReason: failure.description,
              );
            }
          }
        } catch (error) {
          // 最终结果核对暂时不可用时保留“待确认”，绝不猜成失败或已确认。
          AppLog.d('[链上交易] finalized 失败事件核对失败: $error');
        }
      }
    } else if (event.kind == TxPoolWatchKind.inBlock) {
      await LocalTxStore.markLocalSubmitInBlock(
        accountId: wallet.accountId,
        txHash: txHash,
        blockHash: event.blockHashHex,
      );
    } else {
      return;
    }
    if (mounted) await _loadLocalRecords(wallet: wallet);
  }

  Future<void> _reloadWallet() async {
    WalletProfile? wallet;
    try {
      final loader = widget.currentWalletLoader;
      wallet = loader != null
          ? await loader()
          : await _paymentService.getCurrentWallet();
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
      _loadingWallet = false;
      if (nextAccountId != currentAccountId) {
        _localTxRecords = [];
      }
    });
    startTxAutoRefresh(nextAccountId);
    // 交易 Tab 也必须使用完整钱包事实原子 replace，不得只 add 当前钱包。
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final monitoredAccounts =
            await WalletManager().getTransactionMonitorAccounts();
        await ChainTxMonitor.instance.replaceWatchedAccounts(
          monitoredAccounts,
        );
        if (monitoredAccounts.isNotEmpty) {
          await ChainTxMonitor.instance.start();
        }
      } on Object catch (error, stackTrace) {
        AppLog.d('[链上交易] 交易监控启动失败: $error\n$stackTrace');
      }
    }
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
    final contact = await Navigator.of(context).push<UserContact>(
      MaterialPageRoute(
        builder: (_) => const ContactBookPage(
          mode: ContactPickMode.pickForTransfer,
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写完整的收款地址和金额')),
      );
      return;
    }
    final amountText = AmountFormat.stripCommas(amountRaw);

    // SS58 地址校验（prefix 走 kGmbSs58Prefix 单源）
    try {
      final decoded = Keyring().decodeAddress(toSs58Address);
      // 验证 prefix：重新编码后比对
      final reEncoded = Keyring().encodeAddress(decoded, kGmbSs58Prefix);
      if (reEncoded != toSs58Address) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('收款地址不是本链地址（SS58 前缀不匹配）')),
        );
        return;
      }
    } catch (e) {
      AppLog.d('[OnchainPay] 收款地址 SS58 校验失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收款地址格式错误，请输入有效的 SS58 地址')),
      );
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
    if (remarkBytes > TransferRpc.maxTransferRemarkBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '转账备注不能超过 ${TransferRpc.maxTransferRemarkBytes} 字节，当前 $remarkBytes 字节',
          ),
        ),
      );
      return;
    }

    // 预估手续费，展示确认对话框
    final estimatedFee = TransferRpc.estimateTransferFeeYuan(amount);

    // 余额校验：转账金额 + 手续费 ≤ 可用余额（余额 - ED）
    final availableBalance = _currentWallet!.balance - _edYuan;
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
                '转账金额：${AmountFormat.format(amount, symbol: _selectedSymbol)}'),
            if (remark.isNotEmpty) ...[
              SizedBox(height: AppLayout.scaledValue(4)),
              Text('转账备注：$remark'),
            ],
            SizedBox(height: AppLayout.scaledValue(4)),
            Text(
                '预估手续费：${AmountFormat.format(estimatedFee, symbol: _selectedSymbol)}'),
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

    setState(() {
      _submitting = true;
    });
    try {
      final wallet = _currentWallet!;
      final Future<Uint8List> Function(Uint8List payload) signCallback;

      if (wallet.requiresHotSign) {
        // 热钱包：签名回调在构造交易后调用，届时弹一次生物/密码验证。
        final walletManager = WalletManager();
        signCallback = (payload) =>
            walletManager.signWithWallet(wallet.walletIndex, payload);
      } else {
        // 冷钱包：扫码签名。
        signCallback = (Uint8List payload) async {
          final qrSigner = QrSigner();
          final requestId = QrSigner.generateRequestId(prefix: 'tx-');
          final request = qrSigner.buildRequest(
            requestId: requestId,
            signerPublicKey: wallet.accountId,
            payloadHex: '0x${_toHex(payload)}',
            action: QrActions.transferWithRemark,
          );
          final requestJson = qrSigner.encodeRequest(request);

          if (!mounted) {
            throw Exception('页面已关闭，无法继续扫码签名');
          }
          final response = await Navigator.push<SignResponseEnvelope>(
            context,
            MaterialPageRoute(
              builder: (_) => QrSignSessionPage(
                request: request,
                requestJson: requestJson,
                expectedSignerPublicKey: wallet.accountId,
              ),
            ),
          );

          if (response == null) {
            throw Exception('签名已取消');
          }

          return Uint8List.fromList(_hexToBytes(response.body.signatureHex));
        };
      }

      String? submittedTxHash;
      String? includedBlockHash;
      TxPoolWatchEvent? latestWatchEvent;
      var localRecordReady = false;
      void handleWatchEvent(TxPoolWatchEvent event) {
        latestWatchEvent = event;
        if (event.isIncluded) {
          includedBlockHash = event.blockHashHex ?? includedBlockHash;
        }
        final txHash = submittedTxHash;
        if (!localRecordReady || txHash == null) return;
        unawaited(_applyWatchEventToLocalRecord(
          event: event,
          wallet: wallet,
          txHash: txHash,
        ));
      }

      final result = await _paymentService.submitTransfer(
        OnchainPaymentDraft(
          toSs58Address: toSs58Address,
          amount: amount,
          symbol: _selectedSymbol,
          remark: remark,
        ),
        sign: signCallback,
        onWatchEvent: handleWatchEvent,
      );
      if (!mounted) {
        return;
      }

      // 交易已成功提交，后续写入本地记录失败不影响交易结果
      final txHash = result.txHash.toLowerCase();
      submittedTxHash = txHash;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('签名成功，交易已发送，tx=$txHash')));
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
          usedNonce: result.usedNonce,
          createdAtMillis: DateTime.now().millisecondsSinceEpoch,
          blockHash: includedBlockHash,
        );
        localRecordReady = true;
        final watchEvent = latestWatchEvent;
        if (watchEvent != null) {
          await _applyWatchEventToLocalRecord(
            event: watchEvent,
            wallet: wallet,
            txHash: txHash,
          );
        }
        if (mounted) await _loadLocalRecords();
      } catch (e) {
        AppLog.d('[交易记录] 写入本地失败: $e');
      }
    } on WalletAuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on OnchainPaymentException catch (e) {
      if (!mounted) {
        return;
      }
      final message = e.code == OnchainPaymentErrorCode.broadcastFailed
          ? '交易发送失败：${e.message}'
          : '签名失败：${e.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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

  Widget _buildStatusMetric({
    required String label,
    required int count,
  }) {
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
                        borderRadius:
                            BorderRadius.circular(AppLayout.scaledValue(6)),
                        child: Image.asset(
                          'assets/icons/icons8-96.png',
                          width: AppLayout.scaledValue(22),
                          height: AppLayout.scaledValue(22),
                        ),
                      ),
                    ),
                    SizedBox(width: AppLayout.scaledValue(6)),
                    Text(
                      '钱包可用余额：${AmountFormat.format(_currentWallet!.balance, symbol: '')} GMB',
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
                  onAddressScanned: (ss58Address) => setState(
                    () => _toController.text = ss58Address,
                  ),
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
                        decoration: transactionFieldDecoration(
                          hintText: '',
                        ),
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
                  decoration: transactionFieldDecoration(
                    hintText: '请输入转账备注（选填）',
                  ).copyWith(
                    contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                    errorText: _transferRemarkBytes >
                            TransferRpc.maxTransferRemarkBytes
                        ? '备注不能超过 ${TransferRpc.maxTransferRemarkBytes} 字节'
                        : null,
                  ),
                ),
                Positioned(
                  right: AppLayout.scaledValue(12),
                  bottom: AppLayout.scaledValue(10),
                  child: Text(
                    '$_transferRemarkBytes/${TransferRpc.maxTransferRemarkBytes} 字节',
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(12),
                      color: _transferRemarkBytes >
                              TransferRpc.maxTransferRemarkBytes
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
                _buildStatusMetric(
                  label: '待确认',
                  count: _waitingCount,
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
                    child: Icon(Icons.chevron_right,
                        size: AppLayout.scaledValue(22)),
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
                            bottom: AppLayout.scaled(context, 12)),
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

  void _handleChainProgressChanged(LightClientStatusSnapshot? progress) {
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
    if (_transferRemarkBytes > TransferRpc.maxTransferRemarkBytes) {
      return '转账备注不能超过 ${TransferRpc.maxTransferRemarkBytes} 字节';
    }

    final progress = _chainProgress;
    if (progress == null) {
      return _chainProgressError ?? '正在读取区块链状态，请稍后再试';
    }
    if (!progress.hasPeers) {
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

List<int> _hexToBytes(String input) {
  final text = input.startsWith('0x') ? input.substring(2) : input;
  if (text.isEmpty || text.length.isOdd) return const <int>[];
  final out = <int>[];
  for (var i = 0; i < text.length; i += 2) {
    out.add(int.parse(text.substring(i, i + 2), radix: 16));
  }
  return out;
}
