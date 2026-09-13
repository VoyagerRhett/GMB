import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/cid/cid_generator.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizen_sdk/citizen_sdk.dart' show CitizenWalletStateAccount;
import 'package:citizenapp/ui/app_layout.dart';

/// 「注册身份」的选择结果:主体类型 + 绑定的钱包账户。
class RegisterChoice {
  const RegisterChoice({
    required this.institution,
    required this.bindAccountId,
  });

  /// [kCidInstitutionCitizen](公民)/ [kCidInstitutionResident](居民)。
  final String institution;

  /// CID 绑定的钱包账户 accountId(鉴权凭证,可任意 `//n`;私钥泄漏可换绑)。
  final String bindAccountId;
}

/// 弹出「注册身份」底部面板:自助占一个匿名 CID 前先选主体类型 + 绑定账户。
///
/// 返回 [RegisterChoice];取消返回 `null`。[accounts] 为当前热钱包下全部本地账户
/// (含账户0);多于 1 个时露出绑定账户选择,否则默认绑账户0。占号与提交由调用方
/// ([MyIdService.registerAnonymousCid])承接,本面板只负责选择与风险知情。
Future<RegisterChoice?> showRegisterIdentitySheet(
  BuildContext context, {
  required List<CitizenWalletStateAccount> accounts,
}) {
  return showModalBottomSheet<RegisterChoice>(
    context: context,
    isScrollControlled: true,
    builder: (_) => RegisterIdentitySheet(accounts: accounts),
  );
}

class RegisterIdentitySheet extends StatefulWidget {
  const RegisterIdentitySheet({super.key, required this.accounts});

  final List<CitizenWalletStateAccount> accounts;

  @override
  State<RegisterIdentitySheet> createState() => _RegisterIdentitySheetState();
}

class _RegisterIdentitySheetState extends State<RegisterIdentitySheet> {
  String _institution = kCidInstitutionCitizen;
  late final List<CitizenWalletStateAccount> _sortedAccounts;
  late String _bindAccountId;

  @override
  void initState() {
    super.initState();
    _sortedAccounts = [...widget.accounts]
      ..sort(
        (a, b) => (a.accountIndex ?? 0x7fffffff).compareTo(
          b.accountIndex ?? 0x7fffffff,
        ),
      );
    // 默认绑账户0(序号最小者);列表为空是异常兜底,留空由 service 拒。
    _bindAccountId = _sortedAccounts.isEmpty
        ? ''
        : _sortedAccounts.first.accountId;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: AppLayout.scaled(context, 36),
                  height: AppLayout.scaled(context, 4),
                  margin: EdgeInsets.only(
                    bottom: AppLayout.scaled(context, 16),
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(
                      AppLayout.scaledValue(2),
                    ),
                  ),
                ),
              ),
              Text(
                '注册身份',
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 17),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 6)),
              Text(
                '占用一个匿名身份 CID 号并绑定到你选的钱包账户,自付最低链上费。身份主键是'
                'CID 号,绑定账户只是鉴权凭证——私钥泄漏可换绑到新账户,CID 不丢失。',
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 12),
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 16)),
              const _SectionLabel('主体类型'),
              SizedBox(height: AppLayout.scaled(context, 8)),
              _TypeOption(
                label: '公民',
                code: kCidInstitutionCitizen,
                desc: '可后续到注册局线下升级为投票 / 竞选公民。',
                selected: _institution == kCidInstitutionCitizen,
                onTap: () =>
                    setState(() => _institution = kCidInstitutionCitizen),
              ),
              SizedBox(height: AppLayout.scaled(context, 10)),
              _TypeOption(
                label: '居民',
                code: kCidInstitutionResident,
                desc: '永久匿名身份,不可升级为投票 / 竞选公民。',
                selected: _institution == kCidInstitutionResident,
                onTap: () =>
                    setState(() => _institution = kCidInstitutionResident),
              ),
              if (_sortedAccounts.length > 1) ...[
                SizedBox(height: AppLayout.scaled(context, 16)),
                const _SectionLabel('绑定钱包账户'),
                SizedBox(height: AppLayout.scaled(context, 8)),
                ..._sortedAccounts.map(
                  (account) => Padding(
                    padding: EdgeInsets.only(
                      bottom: AppLayout.scaled(context, 8),
                    ),
                    child: _AccountRadio(
                      account: account,
                      selected: _bindAccountId == account.accountId,
                      onTap: () =>
                          setState(() => _bindAccountId = account.accountId),
                    ),
                  ),
                ),
              ],
              SizedBox(height: AppLayout.scaled(context, 14)),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: AppTheme.bannerDecoration(AppTheme.warning),
                child: Text(
                  '自助注册只产生匿名身份。投票公民、竞选公民只能在对应注册局线下注册,'
                  '本页无法自助升级。',
                  style: TextStyle(
                    fontSize: AppLayout.scaled(context, 12),
                    height: 1.5,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 16)),
              SizedBox(
                width: double.infinity,
                height: AppLayout.scaled(context, 46),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    RegisterChoice(
                      institution: _institution,
                      bindAccountId: _bindAccountId,
                    ),
                  ),
                  child: const Text('确认注册'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppLayout.scaled(context, 12),
        color: AppTheme.textTertiary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// 主体类型选项卡:选中态描边加粗、附机构码与说明。
class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.label,
    required this.code,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String code;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.border;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppLayout.scaled(context, 14)),
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(
                  AppTheme.primary.withAlpha(10),
                  AppTheme.surfaceCard,
                )
              : AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: color, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppTheme.primary : AppTheme.textTertiary,
              size: AppLayout.scaled(context, 20),
            ),
            SizedBox(width: AppLayout.scaled(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 15),
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(width: AppLayout.scaled(context, 8)),
                      Text(
                        code,
                        style: TextStyle(
                          fontSize: AppLayout.scaled(context, 12),
                          fontFamily: 'monospace',
                          color: AppTheme.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: AppLayout.scaled(context, 3)),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 12),
                      height: 1.4,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 绑定账户单选行:账户名 + 序号 + 短地址。
class _AccountRadio extends StatelessWidget {
  const _AccountRadio({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final CitizenWalletStateAccount account;
  final bool selected;
  final VoidCallback onTap;

  String get _shortAddress {
    final value = account.ss58Address;
    if (value.length <= 18) return value;
    return '${value.substring(0, 8)}…${value.substring(value.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.border;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(AppLayout.scaled(context, 12)),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: color, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppTheme.primary : AppTheme.textTertiary,
              size: AppLayout.scaled(context, 20),
            ),
            SizedBox(width: AppLayout.scaled(context, 12)),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppLayout.scaled(context, 14),
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: AppLayout.scaled(context, 8)),
                  Text(
                    '#${account.accountIndex}',
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 12),
                      color: AppTheme.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _shortAddress,
              style: TextStyle(
                fontSize: AppLayout.scaled(context, 11),
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
