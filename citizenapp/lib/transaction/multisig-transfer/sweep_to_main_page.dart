import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_transfer_call.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_balance_guard.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_service.dart';
import 'package:citizenapp/transaction/shared/account_balance_snapshot_store.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/chain_progress_banner.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 治理机构手续费划转提案创建页面。
///
/// source 锁定为机构 `feeAccountId`,destination 固定为机构 `mainAccountId`,
/// 链端调用 `propose_sweep_to_main (call_index=2)`,无 beneficiary/remark 入参。
class SweepToMainPage extends StatefulWidget {
  const SweepToMainPage({
    super.key,
    required this.institution,
    required this.icon,
    required this.badgeColor,
    required this.adminWallets,
  });

  final InstitutionInfo institution;
  final IconData icon;
  final Color badgeColor;

  final List<CitizenWalletStateAccount> adminWallets;

  @override
  State<SweepToMainPage> createState() => _SweepToMainPageState();
}

class _SweepToMainPageState extends State<SweepToMainPage> {
  final _amountController = TextEditingController();
  late final TextEditingController _proposerRoleCodeController;

  bool _loadingBalance = true;
  bool _submitting = false;
  double? _availableBalance;
  double _estimatedFee = 0.0;
  String? _amountError;
  CitizenChainSyncStatus? _chainProgress;
  String? _chainProgressError;

  late final String _feeAccountId;
  late final String _mainAccountId;
  late final String _fromSs58;
  late final String _toSs58;
  late CitizenWalletStateAccount _selectedWallet;

  @override
  void initState() {
    super.initState();
    _selectedWallet = widget.adminWallets.first;
    _proposerRoleCodeController = TextEditingController(
      text: defaultInstitutionProposerRoleCode(widget.institution),
    );
    final feeHex = widget.institution.accounts?.feeAccountId;
    if (feeHex == null) {
      throw StateError('治理机构 InstitutionAccounts.feeAccountId 为空,无法发起手续费划转');
    }
    _feeAccountId = feeHex;
    _mainAccountId = widget.institution.mainAccountId;
    _fromSs58 = _accountIdToSs58(_feeAccountId);
    _toSs58 = _accountIdToSs58(_mainAccountId);
    _fetchBalance();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _proposerRoleCodeController.dispose();
    super.dispose();
  }

  String _accountIdToSs58(String hex) {
    final bytes = _hexToBytes(hex);
    return Keyring().encodeAddress(Uint8List.fromList(bytes), kGmbSs58Prefix);
  }

  Future<void> _fetchBalance() async {
    final chain = context.read<CitizenSdk>().chain;
    final store = AccountBalanceSnapshotStore.instance;
    final local = await store.read(_feeAccountId);
    if (local != null && mounted) {
      setState(() {
        _availableBalance = local.balanceYuan;
        _loadingBalance = false;
      });
      if (local.isFresh(AccountBalanceSnapshotStore.displayTtl)) return;
    }
    try {
      final balanceSnapshot = await chain.getAccountBalance(_feeAccountId);
      final balance = balanceSnapshot.freeFen.toDouble() / 100;
      try {
        await store.put(accountId: _feeAccountId, balanceYuan: balance);
      } catch (_) {
        // 余额快照写入失败不影响当前链上余额展示。
      }
      if (!mounted) return;
      setState(() {
        _availableBalance = balance;
        _loadingBalance = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (local == null) {
        setState(() {
          _availableBalance = null;
          _loadingBalance = false;
        });
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

  bool _validateAmount() {
    final amount = AmountFormat.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _amountError = '划转金额必须大于 0');
      return false;
    }
    if (_availableBalance != null) {
      final fee = OnchainTransferCall.estimateTransferFeeYuan(amount);
      final operationFee = MultisigTransferBalanceGuard.onchainOperationFeeYuan;
      const ed = 1.11;
      if (amount + fee + operationFee + ed > _availableBalance!) {
        setState(
          () => _amountError =
              '费用账户余额不足（需支付 ${AmountFormat.format(amount, symbol: '')} 元划转本金 + ${AmountFormat.format(fee, symbol: '')} 元执行手续费 + ${AmountFormat.format(operationFee, symbol: '')} 元操作费，并保留 ${AmountFormat.format(ed, symbol: '')} 元 ED）',
        );
        return false;
      }
    }
    setState(() => _amountError = null);
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

    if (!_validateAmount()) return;
    final proposerRoleCode = _proposerRoleCodeController.text.trim();
    if (proposerRoleCode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入提案发起岗位码')));
      return;
    }

    final wallet = _selectedWallet;
    final amountYuan = AmountFormat.tryParse(_amountController.text) ?? 0;
    final sdk = context.read<CitizenSdk>();
    final balanceBlockedReason =
        await MultisigTransferBalanceGuard.checkInstitutionFeeAccountBalance(
          feeAccountId: _feeAccountId,
          actionLabel: '发起手续费划转提案',
          additionalDebitYuan:
              amountYuan +
              OnchainTransferCall.estimateTransferFeeYuan(amountYuan),
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
      // 提案类交易等真正入块并核对事件后才返回，proposalId 来自
      // 链上 SweepToMainProposed 事件，是业务成功的唯一凭据。
      final result = await service.submitProposeSweep(
        institution: widget.institution,
        proposerRoleCode: proposerRoleCode,
        amountYuan: amountYuan,
        signerPublicKey: signerPublicKey,
        externalSigning: (pending) => showCitizenSdkQrResponse(
          context,
          request: pending.qrRequest,
          expiresAt: BigInt.from(
            pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提案已创建（#${result.proposalId}），等待岗位选民投票')),
      );
      Navigator.of(context).pop(true);
    } on AccountSecurityException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
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

  String? get _submitBlockedReason {
    final progress = _chainProgress;
    if (progress == null) {
      return _chainProgressError ?? '正在读取区块链状态，请稍后再试';
    }
    if (progress.peerCount == BigInt.zero) {
      return '轻节点尚未连接到区块链网络，暂不能提交手续费划转提案';
    }
    if (progress.isSyncing) {
      return '轻节点仍在验证或同步链状态，完成后才能提交手续费划转提案';
    }
    if (!progress.isUsable) {
      return _chainProgressError ?? '区块链状态尚未就绪，暂不能提交手续费划转提案';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '发起手续费划转提案',
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
              _buildInstitutionHeader(),
              SizedBox(height: AppLayout.scaled(context, 16)),
              _buildLabel('发起管理员'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              _buildAdminSelector(),
              SizedBox(height: AppLayout.scaled(context, 16)),
              _buildLabel('提案发起岗位码'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              TextField(
                controller: _proposerRoleCodeController,
                maxLength: 64,
                decoration: const InputDecoration(
                  hintText: 'NRC/PRC 委员，PRB 董事；动态机构填写链上岗位码',
                  filled: true,
                  fillColor: AppTheme.surfaceMuted,
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 16)),
              _buildLabel('转出账户（费用账户）'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              _buildReadOnlyField(_fromSs58),
              SizedBox(height: AppLayout.scaled(context, 16)),
              _buildLabel('划入账户（本机构主账户）'),
              SizedBox(height: AppLayout.scaled(context, 6)),
              _buildReadOnlyField(_toSs58),
              SizedBox(height: AppLayout.scaled(context, 16)),
              _buildLabel('划转金额（元）'),
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
              _buildInfoRow(
                '预估手续费',
                _estimatedFee > 0
                    ? '${AmountFormat.format(_estimatedFee, symbol: '')} 元'
                    : '--',
              ),
              SizedBox(height: AppLayout.scaled(context, 8)),
              _buildInfoRow(
                '费用账户可用余额',
                _loadingBalance
                    ? '查询中...'
                    : _availableBalance != null
                    ? '${AmountFormat.format(_availableBalance!, symbol: '')} 元'
                    : '查询失败',
              ),
              SizedBox(height: AppLayout.scaled(context, 24)),
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
                          '提交手续费划转提案',
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

  String _truncateAddress(String address) {
    if (address.length <= 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 8)}';
  }

  Widget _buildAdminSelector() {
    final wallets = widget.adminWallets;
    if (wallets.length == 1) {
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
            '${widget.institution.cidShortName}（手续费划转）',
            style: TextStyle(
              fontSize: AppLayout.scaledValue(15),
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
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

List<int> _hexToBytes(String input) {
  final text = input.startsWith('0x') ? input.substring(2) : input;
  if (text.isEmpty || text.length.isOdd) return const <int>[];
  final out = <int>[];
  for (var i = 0; i < text.length; i += 2) {
    out.add(int.parse(text.substring(i, i + 2), radix: 16));
  }
  return out;
}
