import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/shared/multisig_create_amount_rules.dart';
import 'package:citizenapp/citizen/shared/proposal/proposal_query_service.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/widgets/address_scan_button.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/widgets/chain_progress_banner.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/transaction/shared/account_balance_snapshot_store.dart';

import 'personal_manage_service.dart';
import 'personal_proposal_history_service.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 关闭个人多签账户提案页面。
///
/// 指定受益人地址后发起个人多签账户关闭提案。
class PersonalAccountClosePage extends StatefulWidget {
  const PersonalAccountClosePage({
    super.key,
    required this.institution,
    required this.adminWallets,
  });

  final InstitutionInfo institution;
  final List<CitizenWalletStateAccount> adminWallets;

  @override
  State<PersonalAccountClosePage> createState() =>
      _PersonalAccountClosePageState();
}

class _PersonalAccountClosePageState extends State<PersonalAccountClosePage> {
  final _beneficiaryController = TextEditingController();
  late final PersonalManageService _manageService;
  late final ProposalQueryService _proposalQuery;
  bool _dependenciesReady = false;

  bool _submitting = false;
  bool _loadingBalance = true;
  double? _availableBalance;
  String? _addressError;
  CitizenChainSyncStatus? _chainProgress;
  String? _chainProgressError;

  late CitizenWalletStateAccount _selectedWallet;
  late String _accountSs58;

  @override
  void initState() {
    super.initState();
    _selectedWallet = widget.adminWallets.first;
    _accountSs58 = _hexToSs58(widget.institution.personalAccountId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final sdk = context.read<CitizenSdk>();
    _manageService = PersonalManageService(
      chain: sdk.chain,
      transactions: sdk.transactions,
    );
    _proposalQuery = ProposalQueryService(chain: sdk.chain);
    _dependenciesReady = true;
    _fetchBalance();
  }

  @override
  void dispose() {
    _beneficiaryController.dispose();
    super.dispose();
  }

  Future<void> _fetchBalance() async {
    final chain = context.read<CitizenSdk>().chain;
    final store = AccountBalanceSnapshotStore.instance;
    final local = await store.read(widget.institution.personalAccountId);
    if (local != null && mounted) {
      setState(() {
        _availableBalance = local.balanceYuan;
        _loadingBalance = false;
      });
      if (local.isFresh(AccountBalanceSnapshotStore.displayTtl)) return;
    }
    try {
      final snapshot = await chain.getAccountBalance(
        widget.institution.personalAccountId,
      );
      final balance = snapshot.freeFen.toDouble() / 100;
      try {
        await store.put(
          accountId: widget.institution.personalAccountId,
          balanceYuan: balance,
        );
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
      if (local == null) setState(() => _loadingBalance = false);
    }
  }

  // ──── 校验 ────

  bool _validateAddress(String address) {
    if (address.isEmpty) {
      setState(() => _addressError = '请输入受益人地址');
      return false;
    }
    try {
      Keyring().decodeAddress(address);
    } catch (_) {
      setState(() => _addressError = '地址格式无效');
      return false;
    }

    // 受益人不能是多签账户本身
    if (address == _accountSs58) {
      setState(() => _addressError = '受益人不能与个人多签账户相同');
      return false;
    }

    setState(() => _addressError = null);
    return true;
  }

  // ──── 提交 ────

  Future<void> _submit() async {
    final chain = context.read<CitizenSdk>().chain;
    final blockedReason = _submitBlockedReason;
    if (blockedReason != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(blockedReason)));
      return;
    }

    final beneficiary = _beneficiaryController.text.trim();
    if (!_validateAddress(beneficiary)) return;

    if (_availableBalance != null) {
      final balanceFen = MultisigCreateAmountRules.yuanToFen(
        _availableBalance!,
      );
      final executionFeeFen = MultisigCreateAmountRules.calculateOnchainFeeFen(
        balanceFen,
      );
      final requiredFen =
          executionFeeFen + MultisigCreateAmountRules.existentialDepositFen;
      if (balanceFen < requiredFen) {
        final requiredYuan = MultisigCreateAmountRules.fenToYuan(requiredFen);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '账户余额不足（需要覆盖链上执行费，且扣费后转出金额不低于 ED；当前至少需要 ${AmountFormat.format(requiredYuan, symbol: '')} 元）',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _submitting = true);

    try {
      final wallet = _selectedWallet;
      final publicKeyBytes = _hexDecode(wallet.accountId);

      // 提前查链上 NextProposalId 作为本次关闭提案的预测 ID(req 5 历史保留)。
      final predictedProposalId = await _proposalQuery.fetchNextProposalId();

      final result = await _manageService.submitProposeClosePersonal(
        accountId: widget.institution.personalAccountId,
        beneficiaryAddress: beneficiary,
        signerPublicKey: Uint8List.fromList(publicKeyBytes),
        externalSigning: (pending) => showCitizenSdkQrResponse(
          context,
          request: pending.qrRequest,
          expiresAt: BigInt.from(
            pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
      );

      // 写入 Isar `PersonalAccountProposalEntity`,详情页提案列表才能显示。
      await PersonalProposalHistoryService(chain: chain).recordOrUpdate(
        personalAccountId: widget.institution.personalAccountId,
        proposalId: predictedProposalId,
        action: PersonalProposalAction.close,
        status: PersonalProposalStatus.voting,
        // 发起关闭提案签名成功后，投票引擎已自动记录发起人的赞成票。
        yesVotes: 1,
        noVotes: 0,
        snapshot: {'beneficiary': beneficiary},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('提案已提交：${_truncateAddress(result.txHash)}'),
          backgroundColor: AppTheme.primaryDark,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败：$e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
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

  /// 关闭个人多签会直接动到账户资金，链不同步时不允许继续发起。
  String? get _submitBlockedReason {
    final progress = _chainProgress;
    if (progress == null) {
      return _chainProgressError ?? '正在读取区块链状态，请稍后再试';
    }
    if (progress.peerCount == BigInt.zero) {
      return '轻节点尚未连接到区块链网络，暂不能发起关闭个人多签提案';
    }
    if (progress.isSyncing) {
      return '轻节点仍在验证或同步链状态，完成后才能发起关闭个人多签提案';
    }
    if (!progress.isUsable) {
      return _chainProgressError ?? '区块链状态尚未就绪，暂不能发起关闭个人多签提案';
    }
    return null;
  }

  // ──── UI ────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '关闭个人多签',
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
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 个人多签账户（只读）
              _buildSectionTitle('个人多签账户'),
              SizedBox(height: AppLayout.scaled(context, 8)),
              Container(
                padding: EdgeInsets.all(AppLayout.scaled(context, 12)),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(
                    AppLayout.scaledValue(10),
                  ),
                ),
                child: Text(
                  _accountSs58,
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 13),
                    fontFamily: 'monospace',
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 16)),
              // 当前余额
              _buildSectionTitle('个人多签余额'),
              SizedBox(height: AppLayout.scaled(context, 8)),
              Container(
                padding: EdgeInsets.all(AppLayout.scaled(context, 12)),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(
                    AppLayout.scaledValue(10),
                  ),
                ),
                child: _loadingBalance
                    ? SizedBox(
                        height: AppLayout.scaled(context, 16),
                        width: AppLayout.scaled(context, 16),
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _availableBalance != null
                            ? '${AmountFormat.format(_availableBalance!, symbol: '')} 元'
                            : '查询失败',
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 15),
                          fontWeight: FontWeight.w600,
                          color: _availableBalance != null
                              ? AppTheme.primaryDark
                              : AppTheme.danger,
                        ),
                      ),
              ),
              SizedBox(height: AppLayout.scaled(context, 20)),
              _buildSectionTitle('阈值规则', note: '注销须全员同意'),
              SizedBox(height: AppLayout.scaled(context, 20)),
              // 受益人地址
              _buildSectionTitle('受益人地址'),
              SizedBox(height: AppLayout.scaled(context, 8)),
              TextField(
                controller: _beneficiaryController,
                decoration: InputDecoration(
                  hintText: '输入或扫码',
                  errorText: _addressError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(10),
                    ),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppLayout.scaled(context, 12),
                    vertical: AppLayout.scaled(context, 10),
                  ),
                  suffixIcon: AddressScanButton(
                    onAddressScanned: (ss58Address) => setState(
                      () => _beneficiaryController.text = ss58Address,
                    ),
                  ),
                ),
              ),
              if (widget.adminWallets.length > 1) ...[
                SizedBox(height: AppLayout.scaled(context, 20)),
                _buildSectionTitle('签名钱包'),
                SizedBox(height: AppLayout.scaled(context, 8)),
                DropdownButtonFormField<CitizenWalletStateAccount>(
                  initialValue: _selectedWallet,
                  items: widget.adminWallets.map((w) {
                    return DropdownMenuItem(
                      value: w,
                      child: Text(
                        '${w.name} (${_truncateAddress(w.ss58Address)})',
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 13),
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (w) {
                    if (w != null) setState(() => _selectedWallet = w);
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppLayout.scaledValue(10),
                      ),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppLayout.scaled(context, 12),
                      vertical: AppLayout.scaled(context, 10),
                    ),
                  ),
                ),
              ],
              SizedBox(height: AppLayout.scaled(context, 28)),
              // 提交按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: AppLayout.scaled(context, 14),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppLayout.scaledValue(12),
                      ),
                    ),
                  ),
                  child: _submitting
                      ? SizedBox(
                          width: AppLayout.scaled(context, 18),
                          height: AppLayout.scaled(context, 18),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          '发起关闭个人多签提案',
                          style: TextStyle(
                            fontSize: AppLayout.scaled(context, 16),
                            fontWeight: FontWeight.w600,
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
          ChainProgressBanner(
            busy: _submitting || _loadingBalance,
            onProgressChanged: _handleChainProgressChanged,
            onErrorChanged: _handleChainProgressErrorChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {String? note}) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: AppLayout.scaledValue(14),
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryDark,
          ),
        ),
        if (note != null) ...[
          SizedBox(width: AppLayout.scaledValue(8)),
          Text(
            note,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(12),
              color: AppTheme.textTertiary,
            ),
          ),
        ],
      ],
    );
  }

  // ──── 工具 ────

  String _truncateAddress(String address) {
    if (address.length <= 14) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
  }

  String _hexToSs58(String hex) {
    final bytes = _hexDecode(hex);
    return Keyring().encodeAddress(Uint8List.fromList(bytes), kGmbSs58Prefix);
  }

  Uint8List _hexDecode(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = Uint8List(h.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
