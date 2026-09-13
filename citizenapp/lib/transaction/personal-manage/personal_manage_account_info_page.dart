import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:isar_community/isar.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_entry.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/votingengine/internal-vote/internal_vote_service.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/my/util/amount_format.dart';

import 'personal_admin_list_page.dart';
import 'personal_account_close_page.dart';
import 'personal_pending_create_lookup.dart';
import 'personal_proposal_list_section.dart';
import 'personal_manage_models.dart';
import 'personal_manage_service.dart';

import 'package:citizenapp/ui/app_layout.dart';

/// 个人多签账户详情页。
///
/// 展示个人多签名称、地址、余额、状态、管理员列表和个人提案历史。
class PersonalManageAccountInfoPage extends StatefulWidget {
  const PersonalManageAccountInfoPage({
    super.key,
    required this.institution,
    this.initialLocalStatus,
    this.initialAdminAccountIds = const [],
  });

  final InstitutionInfo institution;
  final String? initialLocalStatus;
  final List<String> initialAdminAccountIds;

  @override
  State<PersonalManageAccountInfoPage> createState() =>
      _PersonalManageAccountInfoPageState();
}

class _PersonalManageAccountInfoPageState
    extends State<PersonalManageAccountInfoPage> {
  late final CitizenChain _chain;
  late final PersonalManageService _personalManageService;
  bool _dependenciesReady = false;

  AccountInfo? _accountInfo;
  List<AdminPerson> _admins = const [];
  String _localStatus = PersonalMultisigLocalState.statusPending;
  int? _lastDetailRefreshAtMillis;
  int? _lastBalanceRefreshAtMillis;
  bool _isClosed = false;

  /// 账户余额(元):Active 来自链上 free_balance,Pending 来自本机 Isar
  /// PersonalAccountProposalEntity.snapshotJson.amount_fen(发起人承诺入金)。
  double? _balanceYuan;

  @override
  void initState() {
    super.initState();
    _localStatus =
        widget.initialLocalStatus ?? PersonalMultisigLocalState.statusPending;
    _admins = _adminsFromAccounts(widget.initialAdminAccountIds);
    _isClosed = _localStatus == PersonalMultisigLocalState.statusClosed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final sdk = context.read<CitizenSdk>();
    _chain = sdk.chain;
    _personalManageService = PersonalManageService(
      chain: _chain,
      transactions: sdk.transactions,
    );
    _dependenciesReady = true;
    _load();
  }

  Future<void> _load() async {
    await _loadFromLocal();
    if (_shouldRefreshDetail()) {
      unawaited(_refreshChainDetail());
    } else {
      unawaited(_refreshBalanceIfNeeded());
    }
  }

  Future<void> _loadFromLocal() async {
    try {
      final local = await WalletIsar.instance.read((isar) async {
        final entity = await isar.personalAccountEntitys
            .filter()
            .accountIdEqualTo(widget.institution.personalAccountId)
            .findFirst();
        final statuses = await PersonalMultisigLocalState.readStatusSnapshots(
          isar,
          [widget.institution.personalAccountId],
        );
        final detail = await PersonalMultisigLocalState.readDetail(
          isar,
          widget.institution.personalAccountId,
        );
        final pendingBalance = await _readPendingBalanceFromIsar(isar);
        return (
          entity: entity,
          status: statuses[widget.institution.personalAccountId],
          detail: detail,
          pendingBalance: pendingBalance,
        );
      });

      final status =
          local.status?.status ??
          local.detail?.status ??
          widget.initialLocalStatus ??
          PersonalMultisigLocalState.statusPending;
      final isClosed = status == PersonalMultisigLocalState.statusClosed;
      final normalizedAdmins = local.detail?.admins.isNotEmpty == true
          ? _normalizeAdmins(local.detail!.admins)
          : _adminsFromAccounts(
              local.entity?.matchedAdminAccountIds.isNotEmpty == true
                  ? local.entity!.matchedAdminAccountIds
                  : widget.initialAdminAccountIds,
            );
      final statusEnum = _statusEnumFromLocal(status);
      final accountInfo = isClosed
          ? null
          : AccountInfo(
              adminsLen: normalizedAdmins.length,
              threshold: local.detail?.threshold,
              admins: normalizedAdmins,
              status: statusEnum,
            );
      final balance = isClosed
          ? null
          : statusEnum == MultisigStatus.active
          ? local.detail?.balanceYuan
          : local.pendingBalance ?? local.detail?.balanceYuan;

      if (!mounted) return;
      setState(() {
        _localStatus = status;
        _accountInfo = accountInfo;
        _admins = normalizedAdmins;
        _isClosed = isClosed;
        _balanceYuan = balance;
        _lastDetailRefreshAtMillis =
            local.detail?.lastChainRefreshAtMillis ??
            local.status?.lastSyncAtMillis;
        _lastBalanceRefreshAtMillis = local.detail?.lastBalanceRefreshAtMillis;
      });
    } catch (_) {
      // 本地读取失败也不能让详情页进入全屏错误；保留入口传入的
      // 名称、地址和状态，用户仍可下拉触发链上强制刷新。
    }
  }

  bool _shouldRefreshDetail() {
    if (_lastDetailRefreshAtMillis == null) return true;
    final lastSyncAt = DateTime.fromMillisecondsSinceEpoch(
      _lastDetailRefreshAtMillis!,
    );
    final ttl = _localStatus == PersonalMultisigLocalState.statusActive
        ? const Duration(minutes: 60)
        : const Duration(minutes: 10);
    return DateTime.now().difference(lastSyncAt) >= ttl;
  }

  bool _shouldRefreshBalance() {
    if (_localStatus != PersonalMultisigLocalState.statusActive) return false;
    if (_balanceYuan == null) return true;
    if (_lastBalanceRefreshAtMillis == null) return true;
    final lastSyncAt = DateTime.fromMillisecondsSinceEpoch(
      _lastBalanceRefreshAtMillis!,
    );
    return DateTime.now().difference(lastSyncAt) >= const Duration(minutes: 10);
  }

  Future<void> _refreshBalanceIfNeeded({bool force = false}) async {
    if (!force && !_shouldRefreshBalance()) return;
    try {
      final snapshot = await _chain.getAccountBalance(
        widget.institution.personalAccountId,
      );
      final balance = snapshot.freeFen.toDouble() / 100;
      final now = DateTime.now().millisecondsSinceEpoch;
      await WalletIsar.instance.writeTxn((isar) async {
        final previous = await PersonalMultisigLocalState.readDetail(
          isar,
          widget.institution.personalAccountId,
        );
        await PersonalMultisigLocalState.putDetailInTxn(
          isar,
          widget.institution.personalAccountId,
          MultisigLocalDetailSnapshot(
            status: previous?.status ?? _localStatus,
            admins: previous?.admins ?? _admins,
            threshold: previous?.threshold ?? _accountInfo?.threshold,
            balanceYuan: balance,
            lastChainRefreshAtMillis:
                previous?.lastChainRefreshAtMillis ??
                _lastDetailRefreshAtMillis,
            lastBalanceRefreshAtMillis: now,
            updatedAtMillis: now,
          ),
        );
      });
      if (!mounted) return;
      setState(() {
        _balanceYuan = balance;
        _lastBalanceRefreshAtMillis = now;
      });
    } catch (_) {
      // 余额失败只保留本地旧余额；不要影响详情页其他信息。
    }
  }

  Future<void> _refreshChainDetail({bool force = false}) async {
    if (!force && !_shouldRefreshDetail()) return;
    try {
      final infos = await _personalManageService.fetchPersonalAccountsBatch([
        widget.institution.personalAccountId,
      ]);
      final info = infos[widget.institution.personalAccountId];
      final status = info == null
          ? PersonalMultisigLocalState.statusClosed
          : _localStatusFromInfo(info.status);
      final balance = info == null ? null : await _resolveBalance(info.status);
      final now = DateTime.now().millisecondsSinceEpoch;

      await WalletIsar.instance.writeTxn((isar) async {
        await PersonalMultisigLocalState.putStatusInTxn(
          isar,
          widget.institution.personalAccountId,
          status,
        );
        if (info == null) {
          await PersonalMultisigLocalState.deleteDetailInTxn(
            isar,
            widget.institution.personalAccountId,
          );
        } else {
          final previous = await PersonalMultisigLocalState.readDetail(
            isar,
            widget.institution.personalAccountId,
          );
          await PersonalMultisigLocalState.putDetailInTxn(
            isar,
            widget.institution.personalAccountId,
            MultisigLocalDetailSnapshot(
              status: status,
              admins: info.admins,
              threshold: info.threshold,
              balanceYuan: balance ?? previous?.balanceYuan,
              lastChainRefreshAtMillis: now,
              lastBalanceRefreshAtMillis:
                  info.status == MultisigStatus.active && balance != null
                  ? now
                  : previous?.lastBalanceRefreshAtMillis,
              updatedAtMillis: now,
            ),
          );
        }
      });

      if (!mounted) return;
      setState(() {
        _localStatus = status;
        _isClosed = status == PersonalMultisigLocalState.statusClosed;
        _accountInfo = info;
        _admins = _normalizeAdmins(info?.admins);
        _balanceYuan = _isClosed ? null : balance ?? _balanceYuan;
        _lastDetailRefreshAtMillis = now;
        if (_isClosed) {
          _lastBalanceRefreshAtMillis = null;
        } else if (balance != null) {
          _lastBalanceRefreshAtMillis = now;
        }
      });
    } catch (_) {
      // 链上刷新失败只保留本地详情，不弹进度提示或全屏失败。
    }
  }

  Future<double?> _resolveBalance(MultisigStatus? status) async {
    if (status == MultisigStatus.active) {
      try {
        final snapshot = await _chain.getAccountBalance(
          widget.institution.personalAccountId,
        );
        return snapshot.freeFen.toDouble() / 100;
      } catch (_) {
        return null;
      }
    }
    return WalletIsar.instance.read(_readPendingBalanceFromIsar);
  }

  Future<double?> _readPendingBalanceFromIsar(Isar isar) async {
    // Pending 态:从本机 Isar PersonalAccountProposalEntity 取
    // (该 multisig 的 create 提案 snapshot 含 amount_fen)。
    try {
      final entity = await isar.personalAccountProposalEntitys
          .filter()
          .personalAccountIdEqualTo(widget.institution.personalAccountId)
          .actionEqualTo('create')
          .findFirst();
      if (entity?.snapshotJson == null || entity!.snapshotJson!.isEmpty) {
        return null;
      }
      final snapshot = jsonDecode(entity.snapshotJson!) as Map<String, dynamic>;
      final amountFenStr = snapshot['amount_fen']?.toString();
      if (amountFenStr == null) return null;
      final fen = BigInt.tryParse(amountFenStr);
      if (fen == null) return null;
      return fen.toDouble() / 100.0;
    } catch (_) {
      return null;
    }
  }

  String _localStatusFromInfo(MultisigStatus status) {
    return status == MultisigStatus.active
        ? PersonalMultisigLocalState.statusActive
        : PersonalMultisigLocalState.statusPending;
  }

  MultisigStatus _statusEnumFromLocal(String status) {
    return status == PersonalMultisigLocalState.statusActive
        ? MultisigStatus.active
        : MultisigStatus.pending;
  }

  List<AdminPerson> _normalizeAdmins(List<AdminPerson>? admins) {
    if (admins == null) return const [];
    return admins
        .map(
          (admin) =>
              admin.copyWith(account_id: _requireAccountId(admin.account_id)),
        )
        .where((admin) => admin.account_id.isNotEmpty)
        .toList(growable: false);
  }

  List<AdminPerson> _adminsFromAccounts(List<String> accountIds) => accountIds
      .map(_requireAccountId)
      .where((accountId) => accountId.isNotEmpty)
      .map(
        (accountId) => AdminPerson(
          account_id: accountId,
          family_name: '管理',
          given_name: '员',
        ),
      )
      .toList(growable: false);

  String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  // ──── 关闭 ────

  void _confirmClose() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关闭个人多签'),
        content: const Text('关闭个人多签将发起链上关闭提案，需要其他管理员投票通过后才会真正关闭。\n\n确定要发起关闭吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openClosePage();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('发起关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _openClosePage() async {
    var wallets = await _getAdminWallets();
    if (wallets.isEmpty) {
      await _refreshChainDetail(force: true);
      wallets = await _getAdminWallets();
    }
    if (!mounted || wallets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请先导入此账户的管理员钱包')));
      }
      return;
    }

    final closed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalAccountClosePage(
          institution: widget.institution,
          adminWallets: wallets,
        ),
      ),
    );
    if (closed == true && mounted) {
      // 关闭提案已提交,但**链上 close 还没真正执行**(要等其他管理员投票通过)。
      // 此时 admins-change AdminAccounts 仍存,反向索引下次扫还会拉回 → **不能立即删本地**。
      // 等链上 close execute 自动清掉 AdminAccounts 后,反向索引下次扫不到再清孤立 entity。
      Navigator.pop(context);
    }
  }

  /// 是否展示右上角三点菜单；Active 显关闭，Pending 显撤销创建，Closed 显删除。
  bool _shouldShowMenu() {
    if (_isClosed) return true;
    return _localStatus == PersonalMultisigLocalState.statusActive ||
        _localStatus == PersonalMultisigLocalState.statusPending;
  }

  Future<List<CitizenWalletStateAccount>> _getAdminWallets() async {
    final wallets =
        (await context.read<CitizenSdk>().wallet.getState()).accounts;
    final adminSet = _admins.map((admin) => admin.account_id).toSet();
    return wallets.where((w) {
      return adminSet.contains(w.accountId);
    }).toList();
  }

  Future<void> _removeFromLocal() async {
    await WalletIsar.instance.writeTxn((isar) async {
      await isar.personalAccountEntitys
          .where()
          .accountIdEqualTo(widget.institution.personalAccountId)
          .deleteAll();
      // 个人多签 create/transfer/close 提案 snapshot 一并清掉,否则
      // [PersonalProposalHistoryService] 下次会把它们再拉回详情页。
      await isar.personalAccountProposalEntitys
          .filter()
          .personalAccountIdEqualTo(widget.institution.personalAccountId)
          .deleteAll();
      await PersonalMultisigLocalState.deleteStatusInTxn(
        isar,
        widget.institution.personalAccountId,
      );
      await PersonalMultisigLocalState.deleteDetailInTxn(
        isar,
        widget.institution.personalAccountId,
      );
    });
  }

  Future<void> _confirmDeleteLocal() async {
    if (!_isClosed) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: const Text('确认删除该已注销个人多签账户在本机的所有数据？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _removeFromLocal();
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// 撤销 Pending 阶段的个人多签创建提案(向链上发起反对投票)。
  ///
  /// 链上侧:个人多签 propose_create 的 threshold = 全员通过,任意一票反对都让
  /// `tally.yes + remaining < threshold` 立即满足,提案直接进入 STATUS_REJECTED。
  /// `cleanup_pending_personal_create` 自动执行:unreserve 创建者锁仓 + 删
  /// `PersonalAdmins::PersonalAccounts` /
  /// `PendingPersonalCreate` / `PersonalAdmins::AdminAccounts`。其他管理员设备的反向索引下次扫不到该
  /// AccountId,自动清理孤立 Isar entity。
  ///
  /// 仅个人 Pending 路径调用；Active 走 propose_close。
  /// 当前仅支持热钱包:冷钱包用户走"管理员列表" → 投反对票完成同样语义。
  Future<void> _confirmRevokeCreate() async {
    if (_localStatus == PersonalMultisigLocalState.statusActive) return;

    var adminWallets = await _getAdminWallets();
    if (adminWallets.isEmpty) {
      await _refreshChainDetail(force: true);
      adminWallets = await _getAdminWallets();
    }
    if (!mounted) return;
    if (adminWallets.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先导入此多签的管理员钱包')));
      return;
    }
    final hot = adminWallets.firstWhere(
      (w) => w.signMode == CitizenWalletSignMode.hot,
      orElse: () => adminWallets.first,
    );
    if (hot.signMode != CitizenWalletSignMode.hot) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前管理员钱包均为冷钱包,请到"管理员列表"扫码投反对票')),
      );
      return;
    }

    final pid = await PersonalPendingCreateLookup().findActiveCreate(
      widget.institution.personalAccountId,
    );
    if (!mounted) return;
    if (pid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未找到活跃的创建提案,可能已被处理')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销创建'),
        content: const Text(
          '将向链上发起反对投票。提案被否决后,链上自动清理该多签,'
          '所有管理员设备上的本地记录会随之消失。\n\n'
          '创建者锁定的资金将原路返还。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final publicKeyBytes = _hexDecode(hot.accountId);
      final sdk = context.read<CitizenSdk>();
      await InternalVoteService(
        chain: sdk.chain,
        transactions: sdk.transactions,
      ).submit(
        proposalId: pid,
        approve: false,
        signerPublicKey: Uint8List.fromList(publicKeyBytes),
        externalSigning: (pending) => showCitizenSdkQrResponse(
          context,
          request: pending.qrRequest,
          expiresAt: BigInt.from(
            pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
      );
      // 链上 reject 触发 cleanup 是异步的(下个出块周期),但 admins-change
      // 一旦清空,反向索引就扫不到 → 兜底机制完整。本地立即清,避免用户再看到。
      await _removeFromLocal();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('撤销失败:$e')));
    }
  }

  // ──── UI ────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '个人多签账户',
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
        // 个人多签菜单:
        // - Active  → 关闭个人多签，走 PersonalAdmins::propose_close，不显示删除图标。
        // - Pending → 撤销创建，走 InternalVote approve=false 早期否决。
        actions: [
          if (_shouldShowMenu())
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'delete') _confirmDeleteLocal();
                if (value == 'close') _confirmClose();
                if (value == 'revoke_create') _confirmRevokeCreate();
              },
              itemBuilder: (_) {
                final isActive =
                    _localStatus == PersonalMultisigLocalState.statusActive;
                return [
                  if (_isClosed)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: AppLayout.scaled(context, 20),
                            color: AppTheme.danger,
                          ),
                          SizedBox(width: AppLayout.scaled(context, 8)),
                          const Text(
                            '删除',
                            style: TextStyle(color: AppTheme.danger),
                          ),
                        ],
                      ),
                    )
                  else if (isActive)
                    const PopupMenuItem(
                      value: 'close',
                      child: Text(
                        '关闭个人多签',
                        style: TextStyle(color: AppTheme.danger),
                      ),
                    )
                  else
                    PopupMenuItem(
                      value: 'revoke_create',
                      child: Row(
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            size: AppLayout.scaled(context, 20),
                            color: AppTheme.danger,
                          ),
                          SizedBox(width: AppLayout.scaled(context, 8)),
                          const Text(
                            '撤销创建',
                            style: TextStyle(color: AppTheme.danger),
                          ),
                        ],
                      ),
                    ),
                ];
              },
            ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    final accountSs58 = _hexToSs58(widget.institution.personalAccountId);
    final info = _accountInfo;
    final statusLabel = _isClosed
        ? '已注销'
        : _localStatus == PersonalMultisigLocalState.statusActive
        ? '已激活'
        : '待激活';
    final statusColor = _isClosed
        ? AppTheme.textTertiary
        : _localStatus == PersonalMultisigLocalState.statusActive
        ? AppTheme.success
        : AppTheme.warning;

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshChainDetail(force: true);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 基本信息卡片
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
              side: const BorderSide(color: AppTheme.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(AppLayout.scaledValue(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '账户信息',
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(16),
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaledValue(12)),
                  _buildInfoRow('账户简称', widget.institution.cidShortName),
                  Divider(height: AppLayout.scaledValue(20)),
                  _buildInfoRow(
                    '多签账户',
                    accountSs58,
                    onCopy: () {
                      Clipboard.setData(ClipboardData(text: accountSs58));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('地址已复制'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  if (!_isClosed) ...[
                    // 账户余额：Active 显示链上 free_balance，Pending 显示
                    // 发起人承诺金额；注销账户不再显示旧金额。
                    Divider(height: AppLayout.scaledValue(20)),
                    _buildBalanceRow(_statusEnumFromLocal(_localStatus)),
                  ],
                  Divider(height: AppLayout.scaledValue(20)),
                  _buildInfoRow('状态', statusLabel, valueColor: statusColor),
                  // 管理员数量 / 通过阈值不单列:管理员列表卡片
                  // subtitle 已显示这两项信息,避免重复。
                ],
              ),
            ),
          ),

          if (!_isClosed) ...[
            SizedBox(height: AppLayout.scaledValue(16)),
            MultisigTransferEntryCard(
              institution: widget.institution,
              isPersonal: true,
              enabled: _localStatus == PersonalMultisigLocalState.statusActive,
              loadAdminWallets: _getAdminWallets,
              onCreated: () => _refreshChainDetail(force: true),
            ),
            SizedBox(height: AppLayout.scaledValue(16)),
          ] else
            SizedBox(height: AppLayout.scaledValue(16)),

          // 管理员列表(折叠成单行,点击进入子页)
          _buildAdminEntryCard(info),

          // 个人多签提案列表(req 5):活跃 + 历史(本机 Isar 永久保留终态记录)
          SizedBox(height: AppLayout.scaledValue(16)),
          FutureBuilder<List<CitizenWalletStateAccount>>(
            future: _getAdminWallets(),
            builder: (context, snapshot) {
              final wallets =
                  snapshot.data ?? const <CitizenWalletStateAccount>[];
              return PersonalProposalListSection(
                institution: widget.institution,
                adminWallets: wallets,
              );
            },
          ),
        ],
      ),
    );
  }

  /// 管理员列表入口卡片(req 1):点击进入完整管理员列表页。
  Widget _buildAdminEntryCard(AccountInfo? info) {
    final adminsLen = _admins.length;
    final threshold = info?.threshold;
    final subtitle = _isClosed
        ? '已注销'
        : threshold == null
        ? '$adminsLen 人'
        : '$adminsLen 人 · 阈值 $threshold/$adminsLen';

    // 卡片高度对齐 institution_detail_page._buildAdminEntry,
    // 用 InkWell + Padding(14,12) + Row(36×36 icon)而非 ListTile 减少视觉高度。
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: InkWell(
        onTap: () => _openAdminListPage(info),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(14),
            vertical: AppLayout.scaledValue(12),
          ),
          child: Row(
            children: [
              Container(
                width: AppLayout.scaledValue(36),
                height: AppLayout.scaledValue(36),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(
                    AppLayout.scaledValue(10),
                  ),
                ),
                child: Icon(
                  Icons.group_outlined,
                  size: AppLayout.scaledValue(18),
                  color: AppTheme.primaryDark,
                ),
              ),
              SizedBox(width: AppLayout.scaledValue(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '管理员列表',
                      style: TextStyle(
                        fontSize: AppLayout.scaledValue(15),
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    SizedBox(height: AppLayout.scaledValue(2)),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppLayout.scaledValue(12),
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: AppLayout.scaledValue(20),
                color: AppTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAdminListPage(AccountInfo? info) async {
    if (_admins.isEmpty) {
      await _refreshChainDetail(force: true);
    }
    final wallets = await _getAdminWallets();
    if (!mounted) return;
    final creator = await _resolvePersonalCreatorAccountId();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalAdminListPage(
          institution: widget.institution,
          multisigStatus: _statusEnumFromLocal(_localStatus),
          admins: _admins,
          adminWallets: wallets,
          creatorAccountId: creator,
        ),
      ),
    );
    // 子页可能完成投票 → 精准刷新当前多签状态(可能已激活)。
    if (mounted) await _refreshChainDetail(force: true);
  }

  /// 从本机 Isar 读取个人多签创建者账户 ID。
  /// req 3 未实现时,只有创建者本机有此记录;非创建者打开子页 creatorAccountId 为 null
  /// (届时所有 admin 都按"非创建者"渲染,语义略损但不阻塞主流程)。
  Future<String?> _resolvePersonalCreatorAccountId() async {
    try {
      final entity = await WalletIsar.instance.read((isar) {
        return isar.personalAccountEntitys
            .filter()
            .accountIdEqualTo(widget.institution.personalAccountId)
            .findFirst();
      });
      if (entity == null) return null;
      return entity.creatorAccountId;
    } catch (_) {
      return null;
    }
  }

  /// 账户余额行(bug 4):
  /// - Active:链上 free_balance 实时(无标签)
  /// - Pending:发起人承诺金额(snapshot.amount_fen)+ "不可用" 灰色标签
  Widget _buildBalanceRow(MultisigStatus? status) {
    final balanceStr = _balanceYuan == null
        ? '—'
        : AmountFormat.format(_balanceYuan!);
    final isPending = status != MultisigStatus.active;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: AppLayout.scaledValue(80),
          child: Text(
            '账户余额',
            style: TextStyle(
              fontSize: AppLayout.scaledValue(13),
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: AppLayout.scaledValue(8),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                balanceStr,
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(13),
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isPending && _balanceYuan != null)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppLayout.scaledValue(6),
                    vertical: AppLayout.scaledValue(2),
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(4),
                    ),
                  ),
                  child: Text(
                    '不可用',
                    style: TextStyle(
                      fontSize: AppLayout.scaledValue(11),
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    VoidCallback? onCopy,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: AppLayout.scaledValue(80),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(13),
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: AppLayout.scaledValue(13),
              color: valueColor ?? AppTheme.textPrimary,
              fontWeight: valueColor != null ? FontWeight.w600 : null,
            ),
          ),
        ),
        if (onCopy != null)
          GestureDetector(
            onTap: onCopy,
            child: Icon(
              Icons.copy,
              size: AppLayout.scaledValue(16),
              color: AppTheme.textTertiary,
            ),
          ),
      ],
    );
  }

  // ──── 工具 ────

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
