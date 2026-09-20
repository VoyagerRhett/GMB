import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/institution/institution_detail_page.dart';
import 'package:citizenapp/citizen/institution/institution_repository.dart';
import 'package:citizenapp/citizen/public/data/public_institution_repository.dart';
import 'package:citizenapp/isar/app_isar.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 某市公权机构列表(ADR-018 §九 卡B)。
///
/// 读本地 repo,展示该市全部公权机构简要信息;点进详情页(卡C)。
class CityInstitutionListPage extends StatefulWidget {
  const CityInstitutionListPage({
    super.key,
    required this.provinceCode,
    required this.cityCode,
    required this.cityName,
    required this.repository,
  });

  final String provinceCode;
  final String cityCode;

  /// 市名(调用方从字典预 join 传入;字典缺失时为 code,绝不空)。
  final String cityName;
  final PublicInstitutionRepository repository;

  @override
  State<CityInstitutionListPage> createState() =>
      _CityInstitutionListPageState();
}

class _CityInstitutionListPageState extends State<CityInstitutionListPage> {
  List<PublicInstitutionEntity> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository
          .listInstitutionsByCity(widget.provinceCode, widget.cityCode);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '公权机构列表读取失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: Text('${widget.cityName}公权机构'),
        backgroundColor: AppTheme.surfaceCard,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(
              key: const ValueKey('city-institution-load-progress'),
              minHeight: AppLayout.scaled(context, 2),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Text(
          '正在读取公权机构',
          style: TextStyle(color: AppTheme.textTertiary),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.textTertiary),
            ),
            SizedBox(height: AppLayout.scaledValue(8)),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '${widget.cityName}暂无公权机构数据',
          style: const TextStyle(color: AppTheme.textTertiary),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(8)),
      itemCount: _items.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppTheme.divider),
      itemBuilder: (context, i) {
        final inst = _items[i];
        final title = inst.cidShortName?.isNotEmpty == true
            ? inst.cidShortName!
            : inst.cidFullName;
        return ListTile(
          title: Text(
            title,
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 15),
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            '身份ID ${inst.cidNumber}',
            style: TextStyle(
                fontSize: AppLayout.scaled(context, 12.5),
                color: AppTheme.textTertiary),
          ),
          trailing: Icon(Icons.chevron_right,
              color: AppTheme.textTertiary,
              size: AppLayout.scaled(context, 20)),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => InstitutionDetailPage(
                cidNumber: inst.cidNumber,
                repository: InstitutionRepository(directory: widget.repository),
              ),
            ),
          ),
        );
      },
    );
  }
}
