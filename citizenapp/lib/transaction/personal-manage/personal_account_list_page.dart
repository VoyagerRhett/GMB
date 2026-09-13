// 个人多签账户列表页。
//
// 设计边界：
// - 本页只读取、发现、刷新和展示个人多签账户。
// - 机构账户由 OnChina 注册局登记，CitizenApp 这里不再发现或展示机构多签。
// - 入口放在交易 tab，避免把个人自助多签与机构登记流程混在一起。

import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:isar_community/isar.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;

import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/shared/admin_accounts_scan_service.dart';
import 'package:citizenapp/citizen/shared/institution_info.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/ui/app_theme.dart';

import 'personal_account_create_page.dart';
import 'personal_manage_account_info_page.dart';
import 'personal_manage_discovery_service.dart';
import 'personal_manage_models.dart';
import 'personal_manage_service.dart';
import 'personal_proposal_history_service.dart';
import 'package:citizenapp/ui/app_layout.dart';

class PersonalAccountListPage extends StatefulWidget {
  const PersonalAccountListPage({super.key});

  @override
  State<PersonalAccountListPage> createState() =>
      _PersonalAccountListPageState();
}

class _PersonalAccountListPageState extends State<PersonalAccountListPage> {
  late final PersonalManageService _personalManageService;
  late final PersonalProposalHistoryService _personalProposalHistoryService;
  late final AdminAccountsScanService _scanService;
  late final PersonalManageDiscoveryService _discoveryService;
  bool _dependenciesReady = false;

  List<PersonalAccountEntity> _items = [];
  Map<String, String?> _statuses = const {};
  bool _loading = true;
  bool _scanning = false;
  String? _scanProgress;

  static const _activeStatusTtl = Duration(minutes: 60);
  static const _inactiveStatusTtl = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final sdk = context.read<CitizenSdk>();
    _personalManageService = PersonalManageService(
      chain: sdk.chain,
      transactions: sdk.transactions,
    );
    _personalProposalHistoryService = PersonalProposalHistoryService(
      chain: sdk.chain,
    );
    _scanService = AdminAccountsScanService(chain: sdk.chain);
    _discoveryService = PersonalManageDiscoveryService(
      personalManageService: _personalManageService,
    );
    _dependenciesReady = true;
    _load();
  }

  Future<void> _load({bool runDiscovery = true}) async {
    setState(() => _loading = true);
    try {
      await _readFromIsar();
    } catch (_) {
      // 本地库异常不阻塞页面进入，用户仍可通过下拉刷新重试。
    }
    if (!mounted) return;
    setState(() => _loading = false);

    if (runDiscovery) {
      unawaited(_runBackgroundRefresh());
    }
  }

  Future<void> _readFromIsar() async {
    final snapshot = await WalletIsar.instance.read((isar) async {
      final personals = await isar.personalAccountEntitys.where().findAll();
      final statuses = await PersonalMultisigLocalState.readStatuses(
        isar,
        personals.map((p) => p.accountId),
      );
      return (personals: personals, statuses: statuses);
    });

    final sorted = [...snapshot.personals]
      ..sort((a, b) => b.addedAtMillis.compareTo(a.addedAtMillis));
    if (!mounted) return;
    setState(() {
      _items = sorted;
      _statuses = snapshot.statuses;
    });
  }

  Future<void> _runBackgroundRefresh() async {
    await _refreshKnownStatuses();
    await _runDiscoveryIfWalletsChanged();
  }

  Future<void> _refreshKnownStatuses({
    bool force = false,
    Set<String>? personalAccounts,
  }) async {
    final snapshot = await WalletIsar.instance.read((isar) async {
      final personals = await isar.personalAccountEntitys.where().findAll();
      final statuses = await PersonalMultisigLocalState.readStatusSnapshots(
        isar,
        personals.map((p) => p.accountId),
      );
      return (personals: personals, statuses: statuses);
    });

    final filter = personalAccounts?.map(_requireAccountId).toSet();
    final targets = snapshot.personals.where((item) {
      final address = _requireAccountId(item.accountId);
      if (filter != null && !filter.contains(address)) return false;
      return force || _shouldRefreshStatus(snapshot.statuses[address]);
    }).toList(growable: false);

    if (targets.isEmpty) return;
    await _syncPersonalStatuses(targets);
    await _readFromIsar();
  }

  bool _shouldRefreshStatus(MultisigLocalStatusSnapshot? snapshot) {
    if (snapshot?.lastSyncAtMillis == null) return true;
    final lastSyncAt = DateTime.fromMillisecondsSinceEpoch(
      snapshot!.lastSyncAtMillis!,
    );
    final ttl = snapshot.status == PersonalMultisigLocalState.statusActive
        ? _activeStatusTtl
        : _inactiveStatusTtl;
    return DateTime.now().difference(lastSyncAt) >= ttl;
  }

  Future<void> _syncPersonalStatuses(
      List<PersonalAccountEntity> personals) async {
    if (personals.isEmpty) return;
    Map<String, AccountInfo?> infos;
    try {
      infos = await _personalManageService.fetchPersonalAccountsBatch(
        personals.map((p) => p.accountId),
      );
    } catch (_) {
      // 批量查链失败时保留本地旧状态，不能把网络失败写成已注销。
      return;
    }

    for (final personal in personals) {
      try {
        final info = infos[_requireAccountId(personal.accountId)];
        if (info == null &&
            await _personalProposalHistoryService
                .hasUnchainedVotingCreateProposal(personal.accountId)) {
          await _deletePersonalGhost(personal.accountId);
          continue;
        }
        final status = info == null
            ? PersonalMultisigLocalState.statusClosed
            : info.status == MultisigStatus.active
                ? PersonalMultisigLocalState.statusActive
                : PersonalMultisigLocalState.statusPending;
        await WalletIsar.instance.writeTxn((isar) async {
          await PersonalMultisigLocalState.putStatusInTxn(
            isar,
            personal.accountId,
            status,
          );
          if (info == null) {
            await PersonalMultisigLocalState.deleteDetailInTxn(
              isar,
              personal.accountId,
            );
          } else {
            final previousDetail = await PersonalMultisigLocalState.readDetail(
              isar,
              personal.accountId,
            );
            await PersonalMultisigLocalState.putDetailInTxn(
              isar,
              personal.accountId,
              MultisigLocalDetailSnapshot(
                status: status,
                admins: info.admins,
                threshold: info.threshold,
                balanceYuan: previousDetail?.balanceYuan,
                lastBalanceRefreshAtMillis:
                    previousDetail?.lastBalanceRefreshAtMillis,
                updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
                lastChainRefreshAtMillis: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
        });
      } catch (_) {
        // 单个账户刷新失败只跳过该账户，避免影响整页列表。
      }
    }
  }

  Future<void> _deletePersonalGhost(String personalAccountId) async {
    await WalletIsar.instance.writeTxn((isar) async {
      // 旧版本曾在 txHash 返回后提前写入本地多签；若链上没有账户
      // 且创建提案也不存在，说明它从未上链，不能展示为“已注销”。
      await isar.personalAccountEntitys
          .where()
          .accountIdEqualTo(_requireAccountId(personalAccountId))
          .deleteAll();
      await isar.personalAccountProposalEntitys
          .filter()
          .personalAccountIdEqualTo(personalAccountId)
          .deleteAll();
      await PersonalMultisigLocalState.deleteStatusInTxn(
        isar,
        personalAccountId,
      );
      await PersonalMultisigLocalState.deleteDetailInTxn(
        isar,
        personalAccountId,
      );
    });
  }

  Future<({bool anyChanged, bool completed})> _runBackgroundDiscovery() async {
    if (_scanning) return (anyChanged: false, completed: false);

    final myAccountIds = await _currentWalletAccountIds();
    if (myAccountIds.isEmpty) return (anyChanged: false, completed: true);

    setState(() {
      _scanning = true;
      _scanProgress = '扫描个人多签中...';
    });

    var anyChanged = false;
    var completed = false;
    try {
      // 这里只做个人多签发现，扫描结果直接交给个人多签服务处理。
      final scan = await _scanService.scanAll(
        onProgress: (scanned, total, decoded) {
          if (!mounted) return;
          setState(() {
            _scanProgress =
                '个人多签扫描 $scanned${total == null ? '' : '/$total'} · 已解码 $decoded';
          });
        },
      );
      final stats = await _discoveryService.processScanned(
        scan,
        myAccountIds: myAccountIds,
      );
      anyChanged = stats.newlyAdded > 0 || stats.orphansRemoved > 0;
      completed = !stats.partialFailure;
    } catch (e) {
      AppLog.d('[PersonalAccountListPage] discovery 失败: $e');
    } finally {
      if (anyChanged) {
        await _readFromIsar();
      }
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanProgress = null;
        });
      }
    }
    return (anyChanged: anyChanged, completed: completed);
  }

  Future<void> _runDiscoveryIfWalletsChanged() async {
    final fingerprint = await _currentWalletFingerprint();
    if (fingerprint.isEmpty) return;
    final lastFingerprint = await _readDiscoveryWalletFingerprint();
    if (lastFingerprint == fingerprint) return;
    final result = await _runBackgroundDiscovery();
    if (result.completed) {
      await _writeDiscoveryWalletFingerprint(fingerprint);
    }
  }

  Future<void> _onPullRefresh() async {
    await _refreshKnownStatuses(force: true);
    final result = await _runBackgroundDiscovery();
    if (result.completed) {
      await _writeDiscoveryWalletFingerprint(await _currentWalletFingerprint());
    }
    await _readFromIsar();
  }

  Future<void> _openCreatePersonal() async {
    final createdAddress = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PersonalAccountCreatePage()),
    );
    if (createdAddress != null) {
      await _refreshKnownStatuses(
        force: true,
        personalAccounts: {createdAddress},
      );
    }
  }

  void _onCardTap(PersonalAccountEntity item) {
    final localStatus = _statuses[_requireAccountId(item.accountId)];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalManageAccountInfoPage(
          institution: InstitutionInfo(
            cidFullName: item.accountName,
            cidShortName: item.accountName,
            cidFullNameEn:
                'Personal Multisig ${item.accountId.substring(0, 8)}',
            cidShortNameEn:
                'Personal Multisig ${item.accountId.substring(0, 8)}',
            cidNumber: 'personal-account:${item.accountId}',
            orgType: OrgType.personalMultisig,
            personalAccountId: item.accountId,
          ),
          initialLocalStatus: localStatus,
          initialAdminAccountIds: item.matchedAdminAccountIds,
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      unawaited(_refreshKnownStatuses(
        force: true,
        personalAccounts: {item.accountId},
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '多签账户',
          style: TextStyle(
              fontSize: AppLayout.scaled(context, 17),
              fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primaryDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增个人多签',
            onPressed: _openCreatePersonal,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning && _scanProgress != null) _buildScanBanner(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildScanBanner() {
    return Container(
      width: double.infinity,
      color: AppTheme.primaryDark.withValues(alpha: 0.06),
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaledValue(16),
          vertical: AppLayout.scaledValue(8)),
      child: Row(
        children: [
          SizedBox(
            width: AppLayout.scaledValue(12),
            height: AppLayout.scaledValue(12),
            child: const CircularProgressIndicator(strokeWidth: 1.5),
          ),
          SizedBox(width: AppLayout.scaledValue(8)),
          Expanded(
            child: Text(
              _scanProgress!,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(12),
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: _onPullRefresh,
      child: ListView(
        children: [
          SizedBox(height: AppLayout.scaledValue(80)),
          Icon(Icons.account_tree_outlined,
              size: AppLayout.scaledValue(64), color: AppTheme.border),
          SizedBox(height: AppLayout.scaledValue(12)),
          Center(
            child: Text(
              '暂无多签账户',
              style: TextStyle(
                  fontSize: AppLayout.scaledValue(16),
                  color: AppTheme.textTertiary),
            ),
          ),
          SizedBox(height: AppLayout.scaledValue(6)),
          Center(
            child: Text(
              '点击右上角 + 新增个人多签;\n你作为管理员参与的个人多签会自动出现在此',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppLayout.scaledValue(13),
                  color: AppTheme.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _onPullRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _items.length,
        separatorBuilder: (_, __) => SizedBox(height: AppLayout.scaledValue(8)),
        itemBuilder: (_, index) => _buildCard(_items[index]),
      ),
    );
  }

  Widget _buildCard(PersonalAccountEntity item) {
    final ss58 = _accountAddressLabel(item.accountId);
    final localStatus = _statuses[_requireAccountId(item.accountId)];
    final isClosed = localStatus == PersonalMultisigLocalState.statusClosed;
    final subtitleParts = <String>[
      _truncateAddress(ss58),
      if (item.discoveredViaAdmin)
        '我作为 ${item.matchedAdminAccountIds.length} 位管理员之一参与',
    ];
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        onTap: () => _onCardTap(item),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaledValue(14),
              vertical: AppLayout.scaledValue(12)),
          child: Row(
            children: [
              Container(
                width: AppLayout.scaledValue(40),
                height: AppLayout.scaledValue(40),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(AppLayout.scaledValue(10)),
                ),
                child: Icon(
                  Icons.person,
                  size: AppLayout.scaledValue(20),
                  color: AppTheme.accent,
                ),
              ),
              SizedBox(width: AppLayout.scaledValue(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: AppLayout.scaledValue(6),
                              vertical: AppLayout.scaledValue(2)),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppLayout.scaledValue(4)),
                          ),
                          child: Text(
                            '个人',
                            style: TextStyle(
                              fontSize: AppLayout.scaledValue(11),
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                        if (isClosed) ...[
                          SizedBox(width: AppLayout.scaledValue(6)),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: AppLayout.scaledValue(6),
                                vertical: AppLayout.scaledValue(2)),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.textTertiary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                  AppLayout.scaledValue(4)),
                            ),
                            child: Text(
                              '已注销',
                              style: TextStyle(
                                fontSize: AppLayout.scaledValue(11),
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(width: AppLayout.scaledValue(6)),
                        Expanded(
                          child: Text(
                            item.accountName,
                            style: TextStyle(
                              fontSize: AppLayout.scaledValue(15),
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppLayout.scaledValue(2)),
                    Text(
                      subtitleParts.join(' · '),
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

  String _accountAddressLabel(String hex) {
    try {
      return _hexToSs58(hex);
    } catch (_) {
      return hex;
    }
  }

  String _hexToSs58(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    final bytes = Uint8List(h.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return Keyring().encodeAddress(bytes, kGmbSs58Prefix);
  }

  String _truncateAddress(String address) {
    if (address.length <= 14) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
  }

  String _requireAccountId(String accountId) {
    if (!isAccountIdText(accountId)) {
      throw const FormatException('account_id 必须为小写 0x + 64 位十六进制');
    }
    return accountId;
  }

  Future<Set<String>> _currentWalletAccountIds() async {
    final wallets =
        (await context.read<CitizenSdk>().wallet.getState()).accounts;
    return wallets.map((wallet) => wallet.accountId).toSet();
  }

  Future<String> _currentWalletFingerprint() async {
    final accountIds = (await _currentWalletAccountIds()).toList()..sort();
    return accountIds.join('|');
  }

  Future<String?> _readDiscoveryWalletFingerprint() {
    return WalletIsar.instance.read((isar) async {
      return (await isar.walletPersonalMultisigDiscoveryEntitys.get(0))
          ?.walletFingerprint;
    });
  }

  Future<void> _writeDiscoveryWalletFingerprint(String fingerprint) {
    return WalletIsar.instance.writeTxn((isar) async {
      await isar.walletPersonalMultisigDiscoveryEntitys.put(
        WalletPersonalMultisigDiscoveryEntity()
          ..id = 0
          ..walletFingerprint = fingerprint
          ..updatedAtMillis = DateTime.now().millisecondsSinceEpoch,
      );
    });
  }
}
