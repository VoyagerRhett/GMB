import 'package:provider/provider.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/institution/institution_detail_page.dart';
import 'package:citizenapp/citizen/institution/institution_repository.dart';
import 'package:citizenapp/citizen/public/city_institution_list_page.dart';
import 'package:citizenapp/citizen/public/data/public_institution_repository.dart';
import 'package:citizenapp/citizen/public/data/public_provinces.dart';
import 'package:citizenapp/isar/app_isar.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 公民-公权 tab:公权机构目录浏览 + 订阅(ADR-018 §九 卡B)。
///
/// 左侧导航——「关注」**钉顶固定不滚**,下方 43 省可上下滚动;展示去"省"
/// (匹配仍用全名)。右侧按选中项展示:关注=我订阅的机构(跨省扁平);某省=该省市列表
/// (点市进机构列表)。**读全程本地优先(秒开),在线增量丢后台**,绝不阻塞转圈。
class PublicTab extends StatefulWidget {
  const PublicTab({super.key, this.repository, this.cidNumberProvider});

  /// 测试注入;生产为本地 Isar 实现。
  final PublicInstitutionRepository? repository;

  /// 当前已注册公民的永久 CID；关注关系按 CID 隔离，换绑账户后保持不变。
  final Future<String?> Function()? cidNumberProvider;

  @override
  State<PublicTab> createState() => _PublicPageState();
}

/// 关注分组的固定标签(置顶,非省份)。
const String _kFollowGroup = '关注';

/// 市列表行 view-model:cityCode(查询/导航键)+ 预 join 的市名(显示)。
///
/// (ADR-021):机构只存 code,市名查字典 join。**不在 widget build 里
/// await**——在 state 层预 join 成此 view-model,UI 直接读 [name]。
class _CityVm {
  const _CityVm({required this.code, required this.name});
  final String code;
  final String name;
}

class _PublicPageState extends State<PublicTab> {
  late final PublicInstitutionRepository _repo =
      widget.repository ?? PublicInstitutionRepository();

  /// 统一详情页入口仓库门面(包装目录仓库;ADR-028 决策 2)。
  late final InstitutionRepository _institutionRepo =
      InstitutionRepository(directory: _repo);

  List<PublicProvinceItem> _provinces = const [];

  /// 当前选中:`关注` 或省 code;省名/展示名由 [_selectedProvince] 解析。
  String _selected = _kFollowGroup;
  String? _subscriberCidNumber;

  List<_CityVm> _cities = const [];
  List<PublicInstitutionEntity> _subscribed = const [];

  /// 已 join 的各省市列表内存缓存:再次进入同一省直接秒显,不重跑、不转圈。
  /// 后台增量刷新成功后回写本缓存,保证再次进入既快又新。
  final Map<String, List<_CityVm>> _cityCache = {};

  /// 关注分组每条机构的预 join 所属地(cidNumber → 「省名·市名」)。
  Map<String, String> _subscribedArea = const {};
  bool _contentLoading = true;
  String? _contentError;

  @override
  void initState() {
    super.initState();
    // 固定省份导航不依赖身份或目录读取，首帧直接提供完整页面定位。
    _provinces = publicProvinceItems();
    unawaited(_bootstrap());
  }

  Future<String?> _resolveCidNumber() async {
    final provider = widget.cidNumberProvider;
    if (provider != null) return provider();
    final identity = await context.read<CurrentUserContext>().resolve();
    return identity?.cidNumber;
  }

  Future<void> _bootstrap() async {
    // 后台版本驱动增量同步数据包 + 行政区字典(包版本变了就增量刷新,非阻塞)。
    // 关键:同步是后台任务,但**完成后必须回刷当前视图**——首装时 4.2 万条行政区
    // 字典还在灌 Isar,市名会暂时回退 code(001),字典就绪后须清脏缓存重新 join,
    // 否则永远停在 001(根因见任务卡 20260623-citizenapp-public-city-001-timing-fix)。
    unawaited(_syncThenRefresh());
    String? cidNumber;
    try {
      cidNumber = await _resolveCidNumber();
    } on Object {
      // 浏览公权目录不以身份缓存为前置条件；解析失败按未登录展示关注空态。
      cidNumber = null;
    }
    if (!mounted) return;
    setState(() => _subscriberCidNumber = cidNumber);
    await _selectGroup(_kFollowGroup);
  }

  /// 后台对账 finalized 链快照数据包 + 行政区字典,**完成后回刷当前视图**。
  ///
  /// `ensureSynced` 首装要把 4.2 万条行政区字典灌进 Isar(秒级~十几秒),
  /// 期间 `cityNameMap` 查到的是空字典 → 市名回退 code。等灌完后丢弃「字典未就绪时
  /// join 的脏市名缓存」,按当前选中(关注/某省)用就绪字典重新 join,消除持续显示 001。
  Future<void> _syncThenRefresh() async {
    try {
      await _repo.ensureSynced();
    } on Object {
      return;
    }
    if (!mounted) return;
    _cityCache.clear(); // 关键:清掉灌库未完成时缓存的脏市名(001)。
    await _selectGroup(_selected);
  }

  Future<void> _selectGroup(String group) async {
    try {
      if (group == _kFollowGroup) {
        setState(() {
          _selected = group;
          _contentLoading = true;
          _contentError = null;
        });
        final subs = _subscriberCidNumber == null
            ? <PublicInstitutionEntity>[]
            : await _repo.listSubscribed(_subscriberCidNumber!);
        // 预 join 关注机构的所属地(省名·市名),不在 build 里 await。
        final areas = <String, String>{};
        for (final inst in subs) {
          areas[inst.cidNumber] = await _repo.areaPath(
            provinceCode: inst.provinceCode,
            cityCode: inst.cityCode,
          );
        }
        if (!mounted) return;
        setState(() {
          _subscribed = subs;
          _subscribedArea = areas;
          _contentLoading = false;
        });
        return;
      }
      // 省(group=省 code):命中内存缓存 → **秒显不转圈**;未命中时保留页面结构读本地一次。
      // 之后后台增量刷新(成功会回写缓存与列表)。
      final cached = _cityCache[group];
      setState(() {
        _selected = group;
        _contentError = null;
        _cities = cached ?? const [];
        _contentLoading = cached == null;
      });
      if (cached == null) {
        final localCities = await _loadCityVms(group);
        if (!mounted || _selected != group) return;
        // 加固:字典就绪(至少一个市 join 到非 code 的真名)才写缓存;首装字典未灌完时
        // 市名全回退 code,这种脏列表不入缓存,等 _syncThenRefresh 灌完后重 join。
        final dictReady = localCities.any((c) => c.name != c.code);
        if (dictReady) _cityCache[group] = localCities;
        setState(() {
          _cities = localCities;
          _contentLoading = false;
        });
      }
      unawaited(_refreshProvince(group));
    } on Object {
      if (!mounted || _selected != group) return;
      setState(() {
        _contentLoading = false;
        _contentError = '公权机构目录读取失败，请稍后重试';
      });
    }
  }

  /// 读某省市 code 列表 + **一次批量 join 市名**(消 N+1)成 view-model。
  Future<List<_CityVm>> _loadCityVms(String provinceCode) async {
    final codes = await _repo.listCities(provinceCode);
    if (codes.isEmpty) return const [];
    // 一次取全省市名映射,避免逐市查字典的 N+1(ADR-018 R2)。
    final nameMap = await _repo.cityNameMap(provinceCode);
    return codes.map((code) {
      // 字典名缺失(null)或为空串都回退 code,绝不渲染留白(ADR-021 字典 join)。
      final joined = nameMap[code];
      return _CityVm(
        code: code,
        name: (joined != null && joined.isNotEmpty) ? joined : code,
      );
    }).toList(growable: false);
  }

  /// 按省 code 刷新本地 finalized 链快照索引；省名只用于展示。
  Future<void> _refreshProvince(String provinceCode) async {
    try {
      await _repo.refreshProvince(provinceFullNameByCode(provinceCode));
      final cities = await _loadCityVms(provinceCode);
      // 加固同 _selectGroup:字典就绪才回写缓存,避免缓存住字典未就绪时的脏 code。
      final dictReady = cities.any((c) => c.name != c.code);
      if (dictReady) _cityCache[provinceCode] = cities;
      if (!mounted || _selected != provinceCode) return;
      setState(() => _cities = cities);
    } on Exception {
      if (!mounted || _selected != provinceCode) return;
      if (_cities.isEmpty) {
        setState(() => _contentError = '目录同步失败,请检查 CID 连接后重试');
      }
    }
  }

  /// 当前选中的省条目(非"关注"时);未命中返回 null。
  PublicProvinceItem? get _selectedProvince {
    for (final p in _provinces) {
      if (p.code == _selected) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_contentLoading)
          LinearProgressIndicator(
            key: const ValueKey('public-directory-load-progress'),
            minHeight: AppLayout.scaled(context, 2),
          ),
        // 标题与治理 tab"治理机构"对称。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Text(
            '公权机构',
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 22),
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProvinceRail(
                provinces: _provinces,
                selectedCode: _selected,
                onSelectFollow: () => _selectGroup(_kFollowGroup),
                onSelectProvince: (code) => _selectGroup(code),
              ),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_contentLoading) {
      return const Center(
        child: Text(
          '正在读取公权机构目录',
          style: TextStyle(color: AppTheme.textTertiary),
        ),
      );
    }
    if (_selected == _kFollowGroup && _contentError != null) {
      return _emptyHint(
        icon: Icons.cloud_off_outlined,
        title: _contentError!,
        subtitle: '稍后重试，公权目录浏览不受身份状态阻塞',
      );
    }
    if (_selected == _kFollowGroup) {
      return _buildFollowList();
    }
    return _buildCityList();
  }

  Widget _buildFollowList() {
    if (_subscribed.isEmpty) {
      return _emptyHint(
        icon: Icons.bookmark_border,
        title: '还没有关注的公权机构',
        subtitle: '进入机构详情页,点右上角订阅即可加入关注',
      );
    }
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(8)),
      itemCount: _subscribed.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppTheme.divider),
      itemBuilder: (context, i) {
        final inst = _subscribed[i];
        return _InstitutionTile(
          title: inst.cidShortName?.isNotEmpty == true
              ? inst.cidShortName!
              : inst.cidFullName,
          // 预 join 的所属地(省名·市名),字典缺失回退 code(repo 已兜底)。
          subtitle: _subscribedArea[inst.cidNumber] ?? '',
          onTap: () => _openDetail(inst.cidNumber),
        );
      },
    );
  }

  Widget _buildCityList() {
    final provinceDisplay = _selectedProvince?.provinceDisplayName ?? _selected;
    if (_cities.isEmpty) {
      return _emptyHint(
        icon: _contentError != null
            ? Icons.cloud_off_outlined
            : Icons.location_city_outlined,
        title: _contentError ?? '$provinceDisplay 暂无可显示的公权机构',
        subtitle: _contentError != null ? '稍后重试,或先在桌面端生成数据包' : '目录尚未同步或该省无机构数据',
      );
    }
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(8)),
      itemCount: _cities.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppTheme.divider),
      itemBuilder: (context, i) {
        final city = _cities[i];
        return _InstitutionTile(
          // 市卡片只显市名「xx市」;进入后由列表页顶部展示「xx市公权机构」。
          title: city.name,
          trailing: Icon(Icons.chevron_right,
              color: AppTheme.textTertiary,
              size: AppLayout.scaled(context, 20)),
          onTap: () => _openCity(city),
        );
      },
    );
  }

  void _openCity(_CityVm city) {
    final province = _selectedProvince;
    if (province == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CityInstitutionListPage(
          provinceCode: province.code,
          cityCode: city.code,
          cityName: city.name,
          repository: _repo,
        ),
      ),
    );
  }

  void _openDetail(String cidNumber) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InstitutionDetailPage(
          cidNumber: cidNumber,
          repository: _institutionRepo,
        ),
      ),
    );
  }

  Widget _emptyHint({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppLayout.scaledValue(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: AppLayout.scaledValue(44), color: AppTheme.textTertiary),
            SizedBox(height: AppLayout.scaledValue(12)),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppLayout.scaledValue(15),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
            SizedBox(height: AppLayout.scaledValue(6)),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppLayout.scaledValue(12.5),
                    color: AppTheme.textTertiary)),
          ],
        ),
      ),
    );
  }
}

/// 左侧竖向导航:关注**钉顶固定**,下方省份可上下滚动。无竖线、无独立面板,
/// 直接在页面背景上;选中态用文字加粗变色 + 轻量圆角 pill(方案A)。
class _ProvinceRail extends StatelessWidget {
  const _ProvinceRail({
    required this.provinces,
    required this.selectedCode,
    required this.onSelectFollow,
    required this.onSelectProvince,
  });

  final List<PublicProvinceItem> provinces;

  /// 当前选中键:`关注` 或省 code。
  final String selectedCode;
  final VoidCallback onSelectFollow;
  final ValueChanged<String> onSelectProvince;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppLayout.scaled(context, 88),
      child: Column(
        children: [
          // 关注:钉顶固定,不随省份滚动。
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
            child: _railItem(
              label: _kFollowGroup,
              active: selectedCode == _kFollowGroup,
              onTap: onSelectFollow,
            ),
          ),
          Divider(
              height: AppLayout.scaled(context, 9),
              indent: AppLayout.scaled(context, 14),
              endIndent: AppLayout.scaled(context, 14)),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
              itemCount: provinces.length,
              itemBuilder: (context, i) {
                final p = provinces[i];
                return Padding(
                  padding:
                      EdgeInsets.only(bottom: AppLayout.scaled(context, 4)),
                  child: _railItem(
                    // 展示去"省";选中键用省 code。
                    label: p.provinceDisplayName,
                    active: p.code == selectedCode,
                    onTap: () => onSelectProvince(p.code),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _railItem({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        // width 撑满:让"关注"(在 Column 里)与省份(在 ListView 里)选中背景同宽。
        width: double.infinity,
        padding: EdgeInsets.symmetric(
            vertical: AppLayout.scaledValue(12),
            horizontal: AppLayout.scaledValue(6)),
        decoration: BoxDecoration(
          color: active ? AppTheme.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(AppLayout.scaledValue(10)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppLayout.scaledValue(active ? 18 : 16),
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 机构/市通用行。
///
/// [subtitle] 可空——市卡片只显市名「xx市」时不传副文,
/// 关注列表项才传所属地副文。
class _InstitutionTile extends StatelessWidget {
  const _InstitutionTile({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return ListTile(
      onTap: onTap,
      title: Text(
        title,
        style: TextStyle(
          fontSize: AppLayout.scaled(context, 15),
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: (sub != null && sub.isNotEmpty)
          ? Text(
              sub,
              style: TextStyle(
                  fontSize: AppLayout.scaled(context, 12.5),
                  color: AppTheme.textTertiary),
            )
          : null,
      trailing: trailing,
    );
  }
}
