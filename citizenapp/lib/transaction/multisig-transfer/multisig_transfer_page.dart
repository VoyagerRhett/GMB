import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/chain_progress_banner.dart';
import 'package:flutter/services.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:isar_community/isar.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/transaction/personal-manage/personal_proposal_history_service.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_balance_guard.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_service.dart';
import 'package:citizenapp/transaction/shared/account_balance_snapshot_store.dart';
import 'package:citizenapp/qr/widgets/address_scan_button.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_transfer_call.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 机构转账提案创建页面。
class MultisigTransferPage extends StatefulWidget {
  const MultisigTransferPage({
    super.key,
    required this.institution,
    required this.icon,
    required this.badgeColor,
    required this.adminWallets,
  });

  final InstitutionInfo institution;
  final IconData icon;
  final Color badgeColor;

  /// 当前用户导入的、属于此机构的管理员钱包列表。
  final List<CitizenWalletStateAccount> adminWallets;

  @override
  State<MultisigTransferPage> createState() => _MultisigTransferPageState();
}

class _MultisigTransferPageState extends State<MultisigTransferPage> {
  final _beneficiaryController = TextEditingController();
  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();
  late final TextEditingController _proposerRoleCodeController;

  bool _loadingBalance = true;
  bool _submitting = false;
  double? _availableBalance;

  /// 链上余额刷新失败、当前展示的是本地缓存旧值时置位，
  /// UI 必须明示"可能已过期"，防止用户拿过期余额提交转账。
  bool _balanceStale = false;
  double _estimatedFee = 0.0;
  String? _addressError;
  String? _amountError;
  CitizenChainSyncStatus? _chainProgress;
  String? _chainProgressError;

  late final String _fromSs58;
  late CitizenWalletStateAccount _selectedWallet;

  @override
  void initState() {
    super.initState();
    _selectedWallet = widget.adminWallets.first;
    _proposerRoleCodeController = TextEditingController(
      text: defaultInstitutionProposerRoleCode(widget.institution),
    );
    _fromSs58 = _accountIdToSs58(widget.institution.mainAccountId);
    _fetchBalance();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _beneficiaryController.dispose();
    _amountController.dispose();
    _remarkController.dispose();
    _proposerRoleCodeController.dispose();
    super.dispose();
  }

  String _accountIdToSs58(String hex) {
    final bytes = _hexToBytes(hex);
    return Keyring().encodeAddress(Uint8List.fromList(bytes), kGmbSs58Prefix);
  }

  Future<void> _fetchBalance() async {
    final sdk = context.read<CitizenSdk>();
    final store = AccountBalanceSnapshotStore.instance;
    final local = await store.read(widget.institution.mainAccountId);
    if (local != null && mounted) {
      setState(() {
        _availableBalance = local.balanceYuan;
        _loadingBalance = false;
      });
      if (local.isFresh(AccountBalanceSnapshotStore.displayTtl)) return;
    }
    try {
      final service = MultisigTransferService(
        chain: sdk.chain,
        transactions: sdk.transactions,
      );
      final balance = await service.fetchInstitutionBalance(widget.institution);
      try {
        await store.put(
          accountId: widget.institution.mainAccountId,
          balanceYuan: balance,
        );
      } catch (e) {
        // 余额快照写入失败不影响当前链上余额展示，但要留痕便于排查缓存问题。
        AppLog.d('[MultisigTransfer] 余额快照写入失败: $e');
      }
      if (!mounted) return;
      setState(() {
        _availableBalance = balance;
        _loadingBalance = false;
        _balanceStale = false;
      });
    } catch (e) {
      // 链上余额查询失败必须留痕；有缓存时继续展示旧值但要标记过期。
      AppLog.d('[MultisigTransfer] 链上余额查询失败: $e');
      if (!mounted) return;
      if (local == null) {
        setState(() {
          _availableBalance = null;
          _loadingBalance = false;
        });
      } else {
        setState(() => _balanceStale = true);
      }
    }
  }

  void _onAmountChanged() {
    final amount = AmountFormat.tryParse(_amountController.text);
    setState(() {
      if (amount != null && amount > 0) {
        _estimatedFee = OnchainTransferCall.estimateTransferFeeYuan(amount);
      } else {
        _estimatedFee = 0.0;
      }
    });
  }

  bool _validateAddress() {
    final address = _beneficiaryController.text.trim();
    if (address.isEmpty) {
      setState(() => _addressError = '请输入收款地址');
      return false;
    }
    try {
      Keyring().decodeAddress(address);
    } catch (_) {
      setState(() => _addressError = '地址格式无效');
      return false;
    }
    // 检查是否与机构地址相同
    final beneficiaryBytes = Keyring().decodeAddress(address);
    final institutionBytes = Uint8List.fromList(
      _hexToBytes(widget.institution.mainAccountId),
    );
    if (_bytesEqual(beneficiaryBytes, institutionBytes)) {
      setState(() => _addressError = '收款地址不能与机构地址相同');
      return false;
    }
    setState(() => _addressError = null);
    return true;
  }

  bool _validateAmount() {
    final amount = AmountFormat.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _amountError = '转账金额必须大于 0');
      return false;
    }
    if (_availableBalance != null) {
      final fee = OnchainTransferCall.estimateTransferFeeYuan(amount);
      const ed = 1.11;
      // 机构账户只承担本金；执行手续费由同 CID 费用账户承担。
      // 个人多签没有机构费用账户，仍由个人多签资金账户承担本金与执行费。
      final isInstitution = widget.institution.accounts != null;
      final required = amount + ed + (isInstitution ? 0 : fee);
      if (required > _availableBalance!) {
        setState(
          () => _amountError = isInstitution
              ? '机构主账户余额不足（转账后须保留 ${AmountFormat.format(ed, symbol: '')} 元 ED，手续费由机构费用账户另付）'
              : '余额不足（需保留 ${AmountFormat.format(ed, symbol: '')} 元 ED + ${AmountFormat.format(fee, symbol: '')} 元手续费）',
        );
        return false;
      }
    }
    setState(() => _amountError = null);
    return true;
  }

  bool _validateRemark() {
    final remark = _remarkController.text;
    final bytes = utf8.encode(remark);
    if (bytes.length > 256) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备注超过 256 字节限制（当前 ${bytes.length} 字节）')),
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final blockedReason = _submitBlockedReason;
    if (blockedReason != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(blockedReason)));
      return;
    }

    if (!_validateAddress() || !_validateAmount() || !_validateRemark()) {
      return;
    }
    final isPersonal = isPersonalAccountIdentity(widget.institution.cidNumber);
    final proposerRoleCode = _proposerRoleCodeController.text.trim();
    if (!isPersonal && proposerRoleCode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入当前任职且拥有转账提案权限的岗位码')));
      return;
    }

    final wallet = _selectedWallet;
    final amountYuan = AmountFormat.tryParse(_amountController.text) ?? 0;
    final accounts = widget.institution.accounts;
    final sdk = context.read<CitizenSdk>();
    final balanceBlockedReason = accounts == null
        ? await MultisigTransferBalanceGuard.checkAdminWalletBalance(
            wallet: wallet,
            requiredFeeYuan:
                MultisigTransferBalanceGuard.onchainOperationFeeYuan,
            actionLabel: '发起个人多签转账提案',
            chain: sdk.chain,
          )
        : await MultisigTransferBalanceGuard.checkInstitutionFeeAccountBalance(
            feeAccountId: accounts.feeAccountId,
            actionLabel: '发起机构多签转账提案',
            additionalDebitYuan: OnchainTransferCall.estimateTransferFeeYuan(
              amountYuan,
            ),
            chain: sdk.chain,
          );
    if (balanceBlockedReason != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(balanceBlockedReason)));
      return;
    }

    setState(() => _submitting = true);

    try {
      final signerPublicKey = Uint8List.fromList(_hexToBytes(wallet.accountId));

      final service = MultisigTransferService(
        chain: sdk.chain,
        transactions: sdk.transactions,
      );
      final submitResult = await service.submitProposeTransfer(
        institution: widget.institution,
        proposerRoleCode: isPersonal ? null : proposerRoleCode,
        beneficiaryAddress: _beneficiaryController.text.trim(),
        amountYuan: amountYuan,
        remark: _remarkController.text,
        signerPublicKey: signerPublicKey,
        externalSigning: (pending) => showCitizenSdkQrResponse(
          context,
          request: pending.qrRequest,
          expiresAt: BigInt.from(
            pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
      );

      // 仅个人多签写入本地个人提案历史；机构按 CID 路由。
      await _maybeRecordPersonalProposal(
        proposalId: submitResult.proposalId,
        beneficiary: _beneficiaryController.text.trim(),
        amountYuan: amountYuan,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('提案创建成功')));
      Navigator.of(context).pop(true);
    } on AccountSecurityException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('提交失败：${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('提交失败：$e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// 仅当 [widget.institution] 是个人多签时,把转账提案写入 Isar 历史
  /// (`PersonalAccountProposalEntity`),让详情页"提案列表"区域立即看到。
  /// 机构多签的提案历史由其他模块负责,这里 silent skip。
  Future<void> _maybeRecordPersonalProposal({
    required int proposalId,
    required String beneficiary,
    required double amountYuan,
  }) async {
    try {
      final chain = context.read<CitizenSdk>().chain;
      if (!isPersonalAccountIdentity(widget.institution.cidNumber)) {
        return;
      }
      final personalAccountId = widget.institution.personalAccountId;
      final personal = await WalletIsar.instance.read((isar) {
        return isar.personalAccountEntitys
            .filter()
            .accountIdEqualTo(
              '0x${personalAccountId.toLowerCase().replaceFirst('0x', '')}',
            )
            .findFirst();
      });
      if (personal == null) return;

      await PersonalProposalHistoryService(chain: chain).recordOrUpdate(
        personalAccountId: personalAccountId,
        proposalId: proposalId,
        action: PersonalProposalAction.transfer,
        status: PersonalProposalStatus.voting,
        yesVotes: 0,
        noVotes: 0,
        snapshot: {'beneficiary': beneficiary, 'amount_yuan': amountYuan},
      );
    } catch (e) {
      // 写入失败不阻断主流程(链端已成功)，但本地提案历史会缺该记录，
      // 必须留痕，否则用户会误以为提案没创建而重复提交。
      AppLog.d('[MultisigTransfer] 本地提案历史写入失败: $e');
    }
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

  bool get _canSubmit => !_submitting && _submitBlockedReason == null;

  /// 提案页允许用户先填写表单，但链未连上或仍在同步时禁止真正提交。
  String? get _submitBlockedReason {
    final progress = _chainProgress;
    if (progress == null) {
      return _chainProgressError ?? '正在读取区块链状态，请稍后再试';
    }
    if (progress.peerCount == BigInt.zero) {
      return '轻节点尚未连接到区块链网络，暂不能提交转账提案';
    }
    if (progress.isSyncing) {
      return '轻节点仍在验证或同步链状态，完成后才能提交转账提案';
    }
    if (!progress.isUsable) {
      return _chainProgressError ?? '区块链状态尚未就绪，暂不能提交转账提案';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '发起转账提案',
          style: TextStyle(
            fontSize: AppLayout.scaled(context, 17),
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: Stack(
        children: [
          ChainProgressBanner(
            busy: _submitting || _loadingBalance,
            onProgressChanged: _handleChainProgressChanged,
            onErrorChanged: _handleChainProgressErrorChanged,
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ──── 机构信息 ────
              _buildInstitutionHeader(),
              SizedBox(height: AppLayout.scaled(context, 16)),

              // ──── 发起管理员 ────
              _buildLabel('发起管理员'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              _buildAdminSelector(),
              SizedBox(height: AppLayout.scaled(context, 16)),

              if (!isPersonalAccountIdentity(widget.institution.cidNumber)) ...[
                _buildLabel('提案发起岗位码'),
                SizedBox(height: AppLayout.scaled(context, 6)),
                TextField(
                  controller: _proposerRoleCodeController,
                  maxLength: 64,
                  decoration: const InputDecoration(
                    hintText: '填写当前任职且拥有本业务提案权限的岗位码',
                    filled: true,
                    fillColor: AppTheme.surfaceMuted,
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: AppLayout.scaled(context, 16)),
              ],

              // ──── 转出地址（只读） ────
              _buildLabel('转出地址'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              _buildReadOnlyField(_fromSs58),
              SizedBox(height: AppLayout.scaled(context, 16)),

              // ──── 收款地址 ────
              _buildLabel('收款地址'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              TextField(
                controller: _beneficiaryController,
                decoration: InputDecoration(
                  hintText: '输入 SS58 格式地址',
                  hintStyle: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: AppLayout.scaled(context, 14),
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceMuted,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.primaryDark),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.danger),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.danger),
                  ),
                  errorText: _addressError,
                  suffixIcon: AddressScanButton(
                    onAddressScanned: (ss58Address) => setState(
                      () => _beneficiaryController.text = ss58Address,
                    ),
                  ),
                ),
                style: TextStyle(fontSize: AppLayout.scaled(context, 14)),
              ),
              SizedBox(height: AppLayout.scaled(context, 16)),

              // ──── 转账金额 ────
              _buildLabel('转账金额（元）'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [ThousandSeparatorFormatter()],
                decoration: InputDecoration(
                  hintText: '最低 1.11 元',
                  hintStyle: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: AppLayout.scaled(context, 14),
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceMuted,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.primaryDark),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.danger),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.danger),
                  ),
                  errorText: _amountError,
                  suffixText: '元',
                ),
                style: TextStyle(fontSize: AppLayout.scaled(context, 14)),
              ),
              SizedBox(height: AppLayout.scaled(context, 12)),

              // ──── 预估手续费 ────
              _buildInfoRow(
                '预估手续费',
                _estimatedFee > 0
                    ? '${AmountFormat.format(_estimatedFee, symbol: '')} 元'
                    : '--',
              ),
              SizedBox(height: AppLayout.scaled(context, 8)),

              // ──── 可用余额 ────
              _buildInfoRow(
                '可用余额',
                _loadingBalance
                    ? '查询中...'
                    : _availableBalance != null
                    ? '${AmountFormat.format(_availableBalance!, symbol: '')} 元'
                          '${_balanceStale ? '（链上刷新失败，金额可能已过期）' : ''}'
                    : '查询失败',
              ),
              SizedBox(height: AppLayout.scaled(context, 16)),

              // ──── 备注 ────
              _buildLabel('备注（可选）'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              TextField(
                controller: _remarkController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: '最多 256 字节',
                  hintStyle: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: AppLayout.scaled(context, 14),
                  ),
                  filled: true,
                  fillColor: AppTheme.surfaceMuted,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(8),
                    ),
                    borderSide: const BorderSide(color: AppTheme.primaryDark),
                  ),
                ),
                style: TextStyle(fontSize: AppLayout.scaled(context, 14)),
              ),
              SizedBox(height: AppLayout.scaled(context, 24)),

              // ──── 提交按钮 ────
              SizedBox(
                width: double.infinity,
                height: AppLayout.scaled(context, 48),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppLayout.scaledValue(10),
                      ),
                    ),
                  ),
                  onPressed: _canSubmit ? _submit : null,
                  child: _submitting
                      ? SizedBox(
                          width: AppLayout.scaled(context, 20),
                          height: AppLayout.scaled(context, 20),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '提交转账提案',
                          style: TextStyle(
                            fontSize: AppLayout.scaled(context, 16),
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              if (_submitBlockedReason != null) ...[
                SizedBox(height: AppLayout.scaled(context, 10)),
                Text(
                  _submitBlockedReason!,
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    height: 1.4,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ──── 子组件 ────

  String _truncateAddress(String address) {
    if (address.length <= 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 8)}';
  }

  Widget _buildAdminSelector() {
    final wallets = widget.adminWallets;
    if (wallets.length == 1) {
      // 只有一个管理员钱包，直接展示
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaledValue(12),
          vertical: AppLayout.scaledValue(12),
        ),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
          border: Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.verified_user,
              size: AppLayout.scaledValue(16),
              color: AppTheme.success,
            ),
            SizedBox(width: AppLayout.scaledValue(8)),
            Expanded(
              child: Text(
                _truncateAddress(wallets.first.ss58Address),
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(13),
                  fontFamily: 'monospace',
                  color: AppTheme.success,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    // 多个管理员钱包，下拉选择
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppLayout.scaledValue(12)),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedWallet.walletIndex,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primaryDark),
          items: wallets.map((w) {
            return DropdownMenuItem<int>(
              value: w.walletIndex,
              child: Row(
                children: [
                  Icon(
                    Icons.verified_user,
                    size: AppLayout.scaledValue(14),
                    color: AppTheme.success,
                  ),
                  SizedBox(width: AppLayout.scaledValue(6)),
                  Expanded(
                    child: Text(
                      _truncateAddress(w.ss58Address),
                      style: TextStyle(
                        fontSize: AppLayout.scaledValue(13),
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (index) {
            if (index == null) return;
            setState(() {
              _selectedWallet = wallets.firstWhere(
                (w) => w.walletIndex == index,
              );
            });
          },
        ),
      ),
    );
  }

  Widget _buildInstitutionHeader() {
    return Row(
      children: [
        Container(
          width: AppLayout.scaledValue(36),
          height: AppLayout.scaledValue(36),
          decoration: BoxDecoration(
            color: widget.badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
          ),
          child: Icon(
            widget.icon,
            size: AppLayout.scaledValue(18),
            color: widget.badgeColor,
          ),
        ),
        SizedBox(width: AppLayout.scaledValue(10)),
        Expanded(
          child: Text(
            widget.institution.cidShortName,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(15),
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
        // 页头已显示机构名或个人多签名，不再叠加类型标签。
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppLayout.scaledValue(13),
        fontWeight: FontWeight.w600,
        color: AppTheme.primaryDark,
      ),
    );
  }

  Widget _buildReadOnlyField(String value) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: AppLayout.scaledValue(12),
        vertical: AppLayout.scaledValue(14),
      ),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
        border: Border.all(color: AppTheme.border),
      ),
      child: SelectableText(
        value,
        style: TextStyle(
          fontSize: AppLayout.scaledValue(13),
          color: AppTheme.textSecondary,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppLayout.scaledValue(13),
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: AppLayout.scaledValue(13),
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryDark,
          ),
        ),
      ],
    );
  }
}

// ──── 工具函数 ────

List<int> _hexToBytes(String input) {
  final text = input.startsWith('0x') ? input.substring(2) : input;
  if (text.isEmpty || text.length.isOdd) return const <int>[];
  final out = <int>[];
  for (var i = 0; i < text.length; i += 2) {
    out.add(int.parse(text.substring(i, i + 2), radix: 16));
  }
  return out;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
