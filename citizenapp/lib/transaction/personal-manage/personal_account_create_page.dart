import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:citizenapp/citizen/shared/multisig_create_amount_rules.dart';
import 'package:citizenapp/qr/bodies/user_contact_body.dart';
import 'package:citizenapp/qr/envelope.dart';
import 'package:citizenapp/qr/pages/qr_scan_page.dart'
    show QrScanMode, QrScanPage;
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/my/util/amount_format.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';

import 'personal_manage_service.dart';
import 'personal_proposal_history_service.dart';

import 'package:citizenapp/ui/app_layout.dart';

/// 个人多签账户创建页面（无需 CID）。
class PersonalAccountCreatePage extends StatefulWidget {
  const PersonalAccountCreatePage({
    super.key,
    this.walletStateLoader,
    this.manageService,
  });

  /// Widget 测试可只注入公开钱包目录；正式运行从根 CitizenSDK 读取。
  final Future<CitizenWalletState> Function()? walletStateLoader;
  final PersonalManageService? manageService;

  @override
  State<PersonalAccountCreatePage> createState() =>
      _PersonalAccountCreatePageState();
}

class _PersonalAccountCreatePageState extends State<PersonalAccountCreatePage> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _thresholdController = TextEditingController();

  PersonalManageService? _manageService;
  late final Future<CitizenWalletState> Function() _walletStateLoader;
  bool _dependenciesReady = false;

  bool _submitting = false;
  final List<AdminPerson> _admins = [];
  CitizenWalletStateAccount? _selectedWallet;
  List<CitizenWalletStateAccount> _wallets = [];

  /// 创建人规范 AccountId（始终占管理员列表第一位，不可移除）。
  String? _creatorAccountId;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    final injectedWalletLoader = widget.walletStateLoader;
    if (injectedWalletLoader != null) {
      _walletStateLoader = injectedWalletLoader;
      _manageService = widget.manageService;
      _dependenciesReady = true;
      _loadWallets();
      return;
    }
    final sdk = context.read<CitizenSdk>();
    _walletStateLoader = sdk.wallet.getState;
    _manageService =
        widget.manageService ??
        PersonalManageService(chain: sdk.chain, transactions: sdk.transactions);
    _dependenciesReady = true;
    _loadWallets();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  Future<void> _loadWallets() async {
    final wallets = (await _walletStateLoader()).accounts;
    if (!mounted) return;
    setState(() {
      _wallets = wallets;
      if (wallets.isNotEmpty) {
        _selectedWallet = wallets.first;
        _syncCreatorAdmin(wallets.first);
        _syncThresholdInput();
      }
    });
  }

  /// 钱包切换时同步更新创建人在管理员列表中的位置。
  void _syncCreatorAdmin(CitizenWalletStateAccount wallet) {
    final accountId = wallet.accountId;
    // 移除旧创建人
    if (_creatorAccountId != null) {
      _admins.removeWhere((admin) => admin.account_id == _creatorAccountId);
    }
    _creatorAccountId = accountId;
    _admins.removeWhere((admin) => admin.account_id == accountId); // 防重复
    _admins.insert(
      0,
      AdminPerson(account_id: accountId, family_name: '管理', given_name: '员'),
    );
  }

  // ──── 地址预览 ────

  String? _previewAddress() {
    final wallet = _selectedWallet;
    final name = _nameController.text.trim();
    if (wallet == null || name.isEmpty) return null;

    try {
      // 个人多签账户派生统一走 [derivePersonalAccountSs58]，全 app 仅此一处。
      return derivePersonalAccountSs58(
        creatorAccountId: Uint8List.fromList(_hexDecode(wallet.accountId)),
        accountName: name,
        ss58Prefix: kGmbSs58Prefix,
      );
    } catch (_) {
      return null;
    }
  }

  // ──── 管理员管理 ────

  Future<void> _addAdminByQr() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScanPage(
          mode: QrScanMode.userContactValue,
          customTitle: '扫码添加管理员',
        ),
      ),
    );
    if (result == null || !mounted) return;

    // 只接受用户码(k=3):管理员必须是有 CID 的真人,账户码只声明账户、不含身份。
    //
    // 曾经这里写 `(env.body as dynamic).address` —— `UserContactBody` 从来没有
    // `address` 字段(旧版是 `ss58Address`,现在是 `accountId`),`as dynamic`
    // 绕过了类型检查,于是合法用户码必抛 NoSuchMethodError,被下方 catch 吞成
    // “请扫描有效的用户码”，功能 100% 失效且用户看不到真因。
    // 现改为与全仓其它扫码点同一条路径:强类型 body + 直接取 `accountId`
    // (它本身就是 0x + 64hex 的账户标识,无需再从 SS58 解码)。
    try {
      final env = QrEnvelope.parse(result.trim());
      if (env.kind != QrKind.userContact) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请扫描用户主页中的用户码')));
        return;
      }
      final body = env.body as UserContactBody;
      await _promptAdminNamesAndAdd(body.accountId);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('二维码格式错误：$e')));
    }
  }

  Future<void> _promptAdminNamesAndAdd(String accountId) async {
    final names = await _editNamesDialog();
    if (names == null || !mounted) return;
    _addAdmin(
      AdminPerson(
        account_id: accountId,
        family_name: names.$1,
        given_name: names.$2,
      ),
    );
  }

  void _addAdmin(AdminPerson admin) {
    if (_admins.any((item) => item.account_id == admin.account_id)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该管理员已在列表中')));
      return;
    }
    if (_admins.length >= 64) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('管理员数量已达上限（64）')));
      return;
    }
    setState(() {
      _admins.add(admin);
      _syncThresholdInput();
    });
  }

  void _removeAdmin(int index) {
    // 创建人不可移除
    if (_admins[index].account_id == _creatorAccountId) return;
    setState(() {
      _admins.removeAt(index);
      _syncThresholdInput();
    });
  }

  Future<(String, String)?> _editNamesDialog({AdminPerson? admin}) async {
    final familyController = TextEditingController(
      text: admin?.family_name ?? '管理',
    );
    final givenController = TextEditingController(
      text: admin?.given_name ?? '员',
    );
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('管理员姓名'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: familyController,
                decoration: const InputDecoration(labelText: '姓'),
              ),
            ),
            SizedBox(width: AppLayout.scaledValue(8)),
            Expanded(
              child: TextField(
                controller: givenController,
                decoration: const InputDecoration(labelText: '名'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final family = familyController.text.trim();
              final given = givenController.text.trim();
              Navigator.pop(dialogContext, (
                family.isEmpty ? '管理' : family,
                given.isEmpty ? '员' : given,
              ));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    familyController.dispose();
    givenController.dispose();
    return result;
  }

  Future<void> _editAdminNames(int index) async {
    final current = _admins[index];
    final names = await _editNamesDialog(admin: current);
    if (names == null || !mounted) return;
    setState(() {
      _admins[index] = current.copyWith(
        family_name: names.$1,
        given_name: names.$2,
      );
    });
  }

  int? get _minimumRegularThreshold {
    final count = _admins.length;
    if (count < 2) return null;
    return PersonalManageService.minimumRegularThreshold(count);
  }

  int? get _regularThreshold {
    if (_admins.length < 2) return null;
    return int.tryParse(_thresholdController.text.trim());
  }

  /// 管理员数量变化时只把普通阈值拉回合法范围，
  /// 不把阈值固定死；用户仍可在最低过半到全员之间自由输入。
  void _syncThresholdInput() {
    final min = _minimumRegularThreshold;
    if (min == null) {
      _thresholdController.clear();
      return;
    }
    final max = _admins.length;
    final current = int.tryParse(_thresholdController.text.trim());
    final next = current == null
        ? min
        : current < min
        ? min
        : current > max
        ? max
        : current;
    _thresholdController.text = next.toString();
  }

  // ──── 提交 ────

  String? _validate() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return '请输入多签账户名称';
    if (utf8.encode(name).length > 128) return '名称超过最大长度（128 字节）';
    if (_admins.length < 2) return '管理员至少 2 人';
    if (_admins.length > 64) return '管理员最多 64 人';
    if (_selectedWallet == null) return '请先导入钱包';
    final minThreshold = _minimumRegularThreshold;
    final regularThreshold = _regularThreshold;
    if (minThreshold == null || regularThreshold == null) {
      return '请输入有效的普通阈值';
    }
    if (regularThreshold < minThreshold) {
      return '普通阈值不能小于 $minThreshold（必须过半）';
    }
    if (regularThreshold > _admins.length) {
      return '普通阈值不能超过管理员数量';
    }

    final amount = AmountFormat.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return '请输入有效金额';
    if ((amount * 100).round() < 111) return '初始资金不能低于 1.11 元';

    return null;
  }

  Future<String?> _checkCreatorBalance({
    required CitizenWalletStateAccount wallet,
    required BigInt initialAmountFen,
  }) async {
    final balance = await context.read<CitizenSdk>().chain.getAccountBalance(
      wallet.accountId,
    );
    final balanceYuan = balance.freeFen.toDouble() / 100;
    final balanceFen = MultisigCreateAmountRules.yuanToFen(balanceYuan);
    final requiredFen = MultisigCreateAmountRules.requiredBalanceFen(
      initialAmountFen,
    );
    if (balanceFen >= requiredFen) return null;
    return MultisigCreateAmountRules.insufficientBalanceMessage(
      actionLabel: '创建个人多签',
      balanceYuan: balanceYuan,
      initialAmountFen: initialAmountFen,
    );
  }

  Future<void> _submit() async {
    final chain = context.read<CitizenSdk>().chain;
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _submitting = true);

    try {
      final manageService = _manageService;
      if (manageService == null) {
        throw StateError('个人多签交易服务不可用');
      }
      final wallet = _selectedWallet!;
      final nameText = _nameController.text.trim();
      final nameBytes = Uint8List.fromList(utf8.encode(nameText));
      final regularThreshold = _regularThreshold!;
      final createThreshold = _admins.length;
      final amountYuan = AmountFormat.tryParse(_amountController.text) ?? 0;
      final amountFen = BigInt.from((amountYuan * 100).round());
      final balanceError = await _checkCreatorBalance(
        wallet: wallet,
        initialAmountFen: amountFen,
      );
      if (balanceError != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(balanceError),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }

      final publicKeyBytes = _hexDecode(wallet.accountId);

      final result = await manageService.submitProposeCreatePersonal(
        accountName: nameBytes,
        admins: _admins,
        regularThreshold: regularThreshold,
        amountFen: amountFen,
        signerPublicKey: Uint8List.fromList(publicKeyBytes),
        externalSigning: (pending) => showCitizenSdkQrResponse(
          context,
          request: pending.qrRequest,
          expiresAt: BigInt.from(
            pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
      );

      final addrHex = result.accountId;
      await WalletIsar.instance.writeTxn((isar) async {
        final entity = PersonalAccountEntity()
          ..accountId = '0x$addrHex'
          ..accountName = nameText
          ..creatorAccountId = wallet.accountId
          ..addedAtMillis = DateTime.now().millisecondsSinceEpoch;
        await isar.personalAccountEntitys.put(entity);
        await PersonalMultisigLocalState.putStatusInTxn(
          isar,
          addrHex,
          PersonalMultisigLocalState.statusPending,
        );
      });

      // 只有入块并确认 个人账户创建成功事件 事件后，才写本地
      // 创建提案；proposalId 使用链上事件返回值，不能再预测 NextProposalId。
      await PersonalProposalHistoryService(chain: chain).recordOrUpdate(
        personalAccountId: addrHex,
        proposalId: result.proposalId,
        action: PersonalProposalAction.create,
        status: PersonalProposalStatus.voting,
        // runtime 投票引擎创建提案后会在同一事务自动给发起人记一票赞成。
        yesVotes: 1,
        noVotes: 0,
        snapshot: {
          'name': nameText,
          'admins_len': _admins.length,
          'regular_threshold': regularThreshold,
          'create_threshold': createThreshold,
          'amount_fen': amountFen.toString(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '提案已确认 #${result.proposalId}：${_truncateAddress(result.txHash)}',
          ),
          backgroundColor: AppTheme.primaryDark,
        ),
      );
      Navigator.of(context).pop(addrHex);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败：$e'), backgroundColor: AppTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ──── UI ────

  @override
  Widget build(BuildContext context) {
    final preview = _previewAddress();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          '创建个人多签',
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildSectionTitle('多签账户名称'),
          SizedBox(height: AppLayout.scaled(context, 8)),
          TextField(
            controller: _nameController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '输入名称（如：家庭基金）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaled(context, 12),
                vertical: AppLayout.scaled(context, 10),
              ),
            ),
          ),
          if (preview != null) ...[
            SizedBox(height: AppLayout.scaled(context, 8)),
            Container(
              padding: EdgeInsets.all(AppLayout.scaled(context, 10)),
              decoration: BoxDecoration(
                color: AppTheme.primaryDark.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '派生多签账户：',
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 12),
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 4)),
                  Text(
                    preview,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 12),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: AppLayout.scaled(context, 20)),
          _buildAdminSectionHeader(),
          SizedBox(height: AppLayout.scaled(context, 8)),
          ..._admins.asMap().entries.map((entry) {
            final admin = entry.value;
            final ss58 = _hexToSs58(admin.account_id);
            final isCreator = admin.account_id == _creatorAccountId;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: AppLayout.scaled(context, 14),
                backgroundColor: AppTheme.primaryDark.withValues(alpha: 0.08),
                child: Text(
                  '${entry.key + 1}',
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 11),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryDark,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      _truncateAddress(ss58),
                      style: TextStyle(fontSize: AppLayout.scaled(context, 13)),
                    ),
                  ),
                  if (isCreator) ...[
                    SizedBox(width: AppLayout.scaled(context, 6)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppLayout.scaled(context, 5),
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          AppLayout.scaledValue(6),
                        ),
                      ),
                      child: Text(
                        '创建人',
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 10),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.success,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text('${admin.family_name}${admin.given_name}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '编辑姓名',
                    icon: Icon(
                      Icons.edit_outlined,
                      size: AppLayout.scaled(context, 18),
                    ),
                    onPressed: () => _editAdminNames(entry.key),
                  ),
                  if (!isCreator)
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: AppLayout.scaled(context, 18),
                        color: AppTheme.danger,
                      ),
                      onPressed: () => _removeAdmin(entry.key),
                    ),
                ],
              ),
            );
          }),
          SizedBox(height: AppLayout.scaled(context, 20)),
          _buildSectionTitle('阈值规则', note: '注册须全员同意'),
          SizedBox(height: AppLayout.scaled(context, 8)),
          _buildThresholdPreview(),
          SizedBox(height: AppLayout.scaled(context, 20)),
          _buildSectionTitle('初始资金（元）'),
          SizedBox(height: AppLayout.scaled(context, 8)),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandSeparatorFormatter()],
            decoration: InputDecoration(
              hintText: '最低 1.11 元',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaled(context, 12),
                vertical: AppLayout.scaled(context, 10),
              ),
            ),
          ),
          if (_wallets.length > 1) ...[
            SizedBox(height: AppLayout.scaled(context, 20)),
            _buildSectionTitle('签名钱包'),
            SizedBox(height: AppLayout.scaled(context, 8)),
            DropdownButtonFormField<CitizenWalletStateAccount>(
              initialValue: _selectedWallet,
              items: _wallets
                  .map(
                    (w) => DropdownMenuItem(
                      value: w,
                      child: Text(
                        '${w.name} (${_truncateAddress(w.ss58Address)})',
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 13),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (w) {
                if (w != null) {
                  setState(() {
                    _selectedWallet = w;
                    _syncCreatorAdmin(w);
                    _syncThresholdInput();
                  });
                }
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryDark,
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
                      '发起创建提案',
                      style: TextStyle(
                        fontSize: AppLayout.scaled(context, 16),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {String? note}) => Row(
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

  /// 管理员扫码入口属于列表操作，固定收进标题行右侧，避免独立按钮挤占列表纵向空间。
  Widget _buildAdminSectionHeader() => Row(
    children: [
      Expanded(
        child: Text(
          '管理员列表（${_admins.length}/64）',
          style: TextStyle(
            fontSize: AppLayout.scaledValue(14),
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryDark,
          ),
        ),
      ),
      IconButton(
        key: const ValueKey('personal-admin-scan-button'),
        tooltip: '扫码添加管理员',
        onPressed: _addAdminByQr,
        icon: SvgPicture.asset(
          'assets/icons/scan-line.svg',
          width: AppLayout.scaled(context, 20),
          height: AppLayout.scaled(context, 20),
          colorFilter: const ColorFilter.mode(
            AppTheme.primaryDark,
            BlendMode.srcIn,
          ),
        ),
      ),
    ],
  );

  Widget _buildThresholdPreview() {
    final count = _admins.length;
    final min = _minimumRegularThreshold;
    final createText = count < 2 ? '至少添加 2 名管理员' : '$count/$count';
    return Container(
      padding: EdgeInsets.all(AppLayout.scaledValue(12)),
      decoration: BoxDecoration(
        color: AppTheme.primaryDark.withValues(alpha: 0.04),
        border: Border.all(color: AppTheme.primaryDark.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _thresholdController,
            enabled: count >= 2,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '普通提案阈值',
              hintText: min == null ? '至少添加 2 名管理员' : '$min 到 $count',
              helperText: min == null
                  ? '至少添加 2 名管理员'
                  : '可输入 $min/$count 到 $count/$count',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaledValue(12),
                vertical: AppLayout.scaledValue(10),
              ),
            ),
          ),
          SizedBox(height: AppLayout.scaledValue(8)),
          _buildThresholdRow('注册提案阈值', createText),
        ],
      ),
    );
  }

  Widget _buildThresholdRow(String label, String value) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppLayout.scaledValue(13),
            color: AppTheme.textSecondary,
          ),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: AppLayout.scaledValue(13),
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryDark,
        ),
      ),
    ],
  );

  String _truncateAddress(String a) => a.length <= 14
      ? a
      : '${a.substring(0, 6)}...${a.substring(a.length - 6)}';
  String _hexToSs58(String hex) => Keyring().encodeAddress(
    Uint8List.fromList(_hexDecode(hex)),
    kGmbSs58Prefix,
  );
  List<int> _hexDecode(String hex) {
    final h = hex.startsWith('0x') ? hex.substring(2) : hex;
    return List.generate(
      h.length ~/ 2,
      (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16),
    );
  }
}
