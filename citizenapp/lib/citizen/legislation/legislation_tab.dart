import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/institution/institution.dart';
import 'package:citizenapp/citizen/institution/institution_detail_page.dart';
import 'package:citizenapp/citizen/institution/institution_repository.dart';
import 'package:citizenapp/citizen/public/data/public_provinces.dart';
import 'package:citizenapp/citizen/legislation/law_reader_page.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 立法 tab 视图(ADR-028 P3-1)。
///
/// 固定顶部 5 卡(公民宪法整行 + 国家立法院/国家教委会 + 国家众议会/国家参议会)
/// +「省市立法机构」标签(不滚);下方省竖导航(去关注组)+ 选中省的 省立法院/省参议会/
/// 省众议会 + 该省全部市立法会(按市代码 001、002… 升序)。机构卡 → 统一详情页;
/// 宪法卡 → 条款项阅读器。
class LegislationTab extends StatefulWidget {
  const LegislationTab({super.key, this.repository});

  final InstitutionRepository? repository;

  @override
  State<LegislationTab> createState() => _LegislationTabState();
}

/// 立法宪法 law_id 固定为 0。
const int _kConstitutionLawId = 0;

// 国家级立法机构码(顶部卡)。
const String _codeNlg = 'NLG'; // 国家立法院
const String _codeNed = 'NED'; // 国家公民教育委员会
const String _codeNrp = 'NRP'; // 国家众议会
const String _codeNsn = 'NSN'; // 国家参议会

/// 顶部卡图标 chip 规格(方案二·五色语义):圆角方形浅底 + 深色图标。
class _CardIcon {
  const _CardIcon(this.icon, this.bg, this.fg);
  final IconData icon;
  final Color bg; // chip 底色(浅)
  final Color fg; // 图标色(深)
}

// 公民宪法卡:书本 + 翠绿。
const _CardIcon _constitutionIcon =
    _CardIcon(Icons.menu_book, Color(0xFFE1F5EE), Color(0xFF0F6E56));

// 四院卡:机构码 → 图标 chip,颜色按机构固定(与展示位置解耦)。
const Map<String, _CardIcon> _nationalIcons = {
  _codeNlg:
      _CardIcon(Icons.account_balance, Color(0xFFFAEEDA), Color(0xFF854F0B)),
  _codeNed: _CardIcon(Icons.school, Color(0xFFE6F1FB), Color(0xFF185FA5)),
  _codeNsn: _CardIcon(Icons.gavel, Color(0xFFEEEDFE), Color(0xFF3C3489)),
  _codeNrp: _CardIcon(Icons.groups, Color(0xFFEAF3DE), Color(0xFF3B6D11)),
};

// 省内立法机构码(省导航右侧内容),按展示顺序。
const List<String> _provinceCodeOrder = ['PLG', 'PSN', 'PRP', 'CLEG'];
const Set<String> _provinceCodes = {'PLG', 'PRP', 'PSN', 'CLEG'};

/// 省选中后的机构排序：先按 [_provinceCodeOrder]（省立法院→省参议会→省众议会→市立法会），
/// 同码内（即各市立法会）按市代码 001、002… 升序；省三机构各单条，此键对其无影响。
/// 抽成顶层函数以便单测。
@visibleForTesting
List<Institution> sortProvinceLegislationRows(List<Institution> rows) {
  return [...rows]..sort((a, b) {
      final oa = _provinceCodeOrder.indexOf(a.institutionCode);
      final ob = _provinceCodeOrder.indexOf(b.institutionCode);
      if (oa != ob) return oa.compareTo(ob);
      return (int.tryParse(a.cityCode) ?? 0)
          .compareTo(int.tryParse(b.cityCode) ?? 0);
    });
}

class _LegislationTabState extends State<LegislationTab> {
  late final InstitutionRepository _repo =
      widget.repository ?? InstitutionRepository();

  /// 国家级机构(code → Institution),缺失则该卡占位。
  final Map<String, Institution> _national = {};

  List<PublicProvinceItem> _provinces = const [];
  String? _selectedProvince;
  List<Institution> _provinceContent = const [];
  bool _contentLoading = true;
  String? _contentError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _provinces = publicProvinceItems();
    try {
      final nationals =
          await _repo.listByCodes({_codeNlg, _codeNed, _codeNrp, _codeNsn});
      for (final inst in nationals) {
        _national[inst.institutionCode] = inst;
      }
    } on Object {
      // 国家机构卡保持禁用占位；省市目录仍继续读取，不以单组失败阻塞整个页面。
    }
    if (!mounted) return;
    setState(() {});
    if (_provinces.isNotEmpty) {
      await _selectProvince(_provinces.first.code);
    } else {
      if (mounted) setState(() => _contentLoading = false);
    }
  }

  Future<void> _selectProvince(String provinceCode) async {
    setState(() {
      _selectedProvince = provinceCode;
      _contentLoading = true;
      _contentError = null;
    });
    try {
      final rows =
          await _repo.listByProvinceAndCodes(provinceCode, _provinceCodes);
      final sorted = sortProvinceLegislationRows(rows);
      if (!mounted || _selectedProvince != provinceCode) return;
      setState(() {
        _provinceContent = sorted;
        _contentLoading = false;
      });
    } on Object {
      if (!mounted || _selectedProvince != provinceCode) return;
      setState(() {
        _contentLoading = false;
        _contentError = '立法机构读取失败，请重试';
      });
    }
  }

  void _openDetail(String cidNumber) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InstitutionDetailPage(cidNumber: cidNumber, repository: _repo),
      ),
    );
  }

  void _openConstitution() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LawReaderPage(lawId: _kConstitutionLawId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 固定顶部(不滚)──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                AppLayout.citizenSubtabFirstRowTopInset,
                16,
                0,
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: AppLayout.scaled(
                      context,
                      AppLayout.citizenSubtabFirstRowHeight,
                    ),
                    child: _constitutionCard(),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 8)),
                  Row(children: [
                    Expanded(child: _nationalCard(_codeNlg, '国家立法院')),
                    SizedBox(width: AppLayout.scaled(context, 8)),
                    Expanded(child: _nationalCard(_codeNed, '国家教委会')),
                  ]),
                  SizedBox(height: AppLayout.scaled(context, 8)),
                  Row(children: [
                    Expanded(child: _nationalCard(_codeNsn, '国家参议会')),
                    SizedBox(width: AppLayout.scaled(context, 8)),
                    Expanded(child: _nationalCard(_codeNrp, '国家众议会')),
                  ]),
                  SizedBox(height: AppLayout.scaled(context, 14)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('省市立法机构',
                        style: TextStyle(
                            fontSize: AppLayout.scaled(context, 15),
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                  ),
                  SizedBox(height: AppLayout.scaled(context, 6)),
                ],
              ),
            ),
            // ── 省导航 body(左省栏 + 右内容,各自滚)──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _provinceRail(),
                  Expanded(child: _provinceContentView()),
                ],
              ),
            ),
          ],
        ),
        // 加载线只覆盖页面顶部，不得挤压首行卡片与导航栏的距离。
        if (_contentLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              key: const ValueKey('legislation-load-progress'),
              minHeight: AppLayout.scaled(context, 2),
            ),
          ),
      ],
    );
  }

  Widget _constitutionCard() {
    return InkWell(
      onTap: _openConstitution,
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
      child: Container(
        key: const ValueKey<String>('citizen-constitution-card'),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
          border:
              Border.all(color: AppTheme.primaryDark.withValues(alpha: 0.22)),
        ),
        padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(12),
            vertical: AppLayout.scaledValue(12)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _iconChip(
                  _constitutionIcon,
                  size: AppLayout.scaledValue(38),
                ),
                Icon(
                  Icons.chevron_right,
                  size: AppLayout.scaledValue(20),
                  color: AppTheme.textTertiary,
                ),
              ],
            ),
            Text(
              '《公民宪法》',
              key: const ValueKey<String>('citizen-constitution-title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppLayout.scaledValue(18),
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nationalCard(String code, String fallbackLabel) {
    final inst = _national[code];
    final label = inst != null ? inst.cidShortNameOrFullName : fallbackLabel;
    final enabled = inst != null;
    final spec = _nationalIcons[code]!;
    return InkWell(
      onTap: enabled ? () => _openDetail(inst.cidNumber) : null,
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
          border: Border.all(color: AppTheme.border),
        ),
        padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaledValue(12),
            vertical: AppLayout.scaledValue(12)),
        child: Row(
          children: [
            _iconChip(
              spec,
              size: AppLayout.scaledValue(34),
              enabled: enabled,
            ),
            SizedBox(width: AppLayout.scaledValue(10)),
            Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: AppLayout.scaledValue(13),
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? AppTheme.textPrimary
                          : AppTheme.textTertiary)),
            ),
            Icon(Icons.chevron_right,
                size: AppLayout.scaledValue(18), color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  /// 圆角方形图标 chip(方案二):浅底 + 深图标;禁用态转灰。
  Widget _iconChip(_CardIcon spec, {double size = 34, bool enabled = true}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled ? spec.bg : AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
      ),
      child: Icon(spec.icon,
          size: size * 0.52, color: enabled ? spec.fg : AppTheme.textTertiary),
    );
  }

  Widget _provinceRail() {
    return SizedBox(
      width: AppLayout.scaledValue(84),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        itemCount: _provinces.length,
        itemBuilder: (context, i) {
          final p = _provinces[i];
          final active = p.code == _selectedProvince;
          return Padding(
            padding: EdgeInsets.only(bottom: AppLayout.scaled(context, 4)),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
              onTap: () => _selectProvince(p.code),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    vertical: AppLayout.scaled(context, 11),
                    horizontal: AppLayout.scaled(context, 6)),
                decoration: BoxDecoration(
                  color: active ? AppTheme.surfaceElevated : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(AppLayout.scaledValue(10)),
                ),
                child: Text(p.provinceDisplayName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: AppLayout.scaledValue(active ? 16 : 15),
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? AppTheme.primary
                            : AppTheme.textSecondary)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _provinceContentView() {
    if (_contentLoading) {
      return const Center(
        child: Text(
          '正在读取立法机构',
          style: TextStyle(color: AppTheme.textTertiary),
        ),
      );
    }
    if (_contentError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _contentError!,
              style: const TextStyle(color: AppTheme.textTertiary),
            ),
            SizedBox(height: AppLayout.scaledValue(8)),
            TextButton(
              onPressed: _selectedProvince == null
                  ? null
                  : () => _selectProvince(_selectedProvince!),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_provinceContent.isEmpty) {
      return Center(
        child: Text('该省暂无立法机构数据',
            style: TextStyle(
                fontSize: AppLayout.scaledValue(13),
                color: AppTheme.textTertiary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 12),
      itemCount: _provinceContent.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppTheme.divider),
      itemBuilder: (context, i) {
        final inst = _provinceContent[i];
        return ListTile(
          dense: true,
          title: Text(inst.cidShortNameOrFullName,
              style: TextStyle(
                  fontSize: AppLayout.scaled(context, 14),
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          trailing: Icon(Icons.chevron_right,
              color: AppTheme.textTertiary,
              size: AppLayout.scaled(context, 20)),
          onTap: () => _openDetail(inst.cidNumber),
        );
      },
    );
  }
}
