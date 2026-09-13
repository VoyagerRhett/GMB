import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/citizen/proposal/admins-change/codec/account_id_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/proposal/admins-change/pages/admin_set_change_confirm_page.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_set_change_service.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_set_validation.dart';
import 'package:citizenapp/citizen/proposal/admins-change/services/admin_account_service.dart';
import 'package:citizenapp/citizen/proposal/admins-change/widgets/admin_set_change_action_bar.dart';
import 'package:citizenapp/citizen/proposal/admins-change/widgets/admin_set_diff_card.dart';
import 'package:citizenapp/citizen/proposal/admins-change/widgets/admin_set_editor.dart';
import 'package:citizenapp/citizen/proposal/admins-change/widgets/admin_account_card.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/ui/app_layout.dart';

class AdminsChangePage extends StatefulWidget {
  const AdminsChangePage({
    super.key,
    required this.institution,
    required this.accountIdentity,
    required this.adminWallets,
  });

  final InstitutionInfo institution;
  final AdminAccountIdentity accountIdentity;
  final List<CitizenWalletStateAccount> adminWallets;

  @override
  State<AdminsChangePage> createState() => _AdminsChangePageState();
}

class _AdminsChangePageState extends State<AdminsChangePage> {
  late final AdminAccountService _accountService;
  late final AdminsChangeService _changeService;
  bool _dependenciesReady = false;
  final _thresholdController = TextEditingController();
  AdminAccountState? _subject;
  List<AdminPerson> _admins = const [];
  Map<String, double> _balanceByAccountId = const {};
  CitizenWalletStateAccount? _selectedWallet;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedWallet =
        widget.adminWallets.isNotEmpty ? widget.adminWallets.first : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final sdk = context.read<CitizenSdk>();
    _accountService = AdminAccountService(chain: sdk.chain);
    _changeService = AdminsChangeService(transactions: sdk.transactions);
    _dependenciesReady = true;
    _load();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = await _accountService.fetchByIdentity(
        widget.accountIdentity,
      );
      if (!mounted) return;
      setState(() {
        _subject = account;
        _admins = account?.admins ?? const <AdminPerson>[];
        if (account != null) _syncThresholdInput(account, _admins.length);
        _loading = false;
      });
      unawaited(
        _loadBalances(account?.admins ?? const <AdminPerson>[]),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _subject;
    return Scaffold(
      appBar: AppBar(title: const Text('更换管理员')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : account == null
              ? Center(child: Text(_error ?? '未查询到管理员账户'))
              : ListView(
                  padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
                  children: [
                    AdminAccountCard(account: account),
                    SizedBox(height: AppLayout.scaled(context, 12)),
                    _buildWalletSelector(),
                    SizedBox(height: AppLayout.scaled(context, 12)),
                    AdminSetEditor(
                      admins: _admins,
                      balances: _balanceByAccountId,
                      onChanged: (value) => _setNewAdmins(account, value),
                    ),
                    SizedBox(height: AppLayout.scaled(context, 12)),
                    _buildThresholdCard(account),
                    SizedBox(height: AppLayout.scaled(context, 12)),
                    AdminSetDiffCard(
                      currentAdmins: account.admins,
                      admins: _admins,
                      balances: _balanceByAccountId,
                    ),
                    if (_error != null) ...[
                      SizedBox(height: AppLayout.scaled(context, 12)),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
      bottomNavigationBar: account == null
          ? null
          : AdminsChangeActionBar(
              busy: _submitting,
              enabled: _selectedWallet != null,
              onSubmit: _submit,
            ),
    );
  }

  Widget _buildWalletSelector() {
    return DropdownButtonFormField<CitizenWalletStateAccount>(
      initialValue: _selectedWallet,
      decoration: const InputDecoration(labelText: '发起管理员钱包'),
      items: widget.adminWallets
          .map((wallet) =>
              DropdownMenuItem(value: wallet, child: Text(wallet.name)))
          .toList(),
      onChanged: _submitting
          ? null
          : (wallet) => setState(() => _selectedWallet = wallet),
    );
  }

  void _setNewAdmins(AdminAccountState account, List<AdminPerson> value) {
    setState(() {
      _admins = value;
      _syncThresholdInput(account, value.length);
    });
    unawaited(_loadBalances(value));
  }

  static String _balanceKey(String accountId) {
    final trimmed = accountId.trim();
    return (trimmed.startsWith('0x') || trimmed.startsWith('0X')
            ? trimmed.substring(2)
            : trimmed)
        .toLowerCase();
  }

  Future<void> _loadBalances(List<AdminPerson> admins) async {
    final accountIds = {
      for (final admin in admins) _balanceKey(admin.account_id),
    }.where((accountId) => accountId.isNotEmpty).toList(growable: false);
    if (accountIds.isEmpty) {
      if (mounted) setState(() => _balanceByAccountId = const {});
      return;
    }
    try {
      final snapshots =
          await context.read<CitizenSdk>().chain.getAccountBalances(accountIds);
      final balances = <String, double>{
        for (final snapshot in snapshots)
          snapshot.accountId: snapshot.freeFen.toDouble() / 100,
      };
      if (mounted) setState(() => _balanceByAccountId = balances);
    } catch (_) {
      // 管理员更换编辑态余额读取失败不影响集合修改,余额值留空。
      if (mounted) setState(() => _balanceByAccountId = const {});
    }
  }

  Widget _buildThresholdCard(AdminAccountState account) {
    final min = _admins.isEmpty
        ? 0
        : AdminSetValidation.minimumDynamicThreshold(_admins.length);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(14)),
        child: TextField(
          controller: _thresholdController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '通过阈值',
            helperText:
                _admins.isEmpty ? '请先添加管理员' : '范围：$min ~ ${_admins.length}',
          ),
        ),
      ),
    );
  }

  void _syncThresholdInput(AdminAccountState account, int adminsLen) {
    if (adminsLen <= 0) {
      _thresholdController.clear();
      return;
    }
    final min = AdminSetValidation.minimumDynamicThreshold(adminsLen);
    final current = int.tryParse(_thresholdController.text.trim());
    if (current == null || current < min || current > adminsLen) {
      _thresholdController.text = min.toString();
    }
  }

  int _readNewThreshold(AdminAccountState account) {
    final value = int.tryParse(_thresholdController.text.trim());
    if (value == null) throw StateError('请输入有效阈值');
    return value;
  }

  Future<void> _submit() async {
    final account = _subject;
    final wallet = _selectedWallet;
    if (account == null || wallet == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final newThreshold = _readNewThreshold(account);
      final validated = AdminSetValidation.validate(
        account: account,
        proposerAccountId: wallet.accountId,
        admins: _admins,
        newThreshold: newThreshold,
      );
      final result = await _changeService.submit(
        account: account,
        admins: validated.admins,
        newThreshold: validated.threshold,
        signerPublicKey:
            AdminAccountIdCodec.fromAccountIdText(wallet.accountId),
        externalSigning: (pending) => showCitizenSdkQrResponse(
          context,
          request: pending.qrRequest,
          expiresAt: BigInt.from(
            pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
      );
      _accountService.clearPersonalAccountCache(account.personalAccountId!);
      _accountService.clearCache(widget.accountIdentity);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => AdminsChangeConfirmPage(txHash: result.txHash)),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
