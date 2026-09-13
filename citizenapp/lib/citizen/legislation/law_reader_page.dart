import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/citizen/legislation/data/law_models.dart';
import 'package:citizenapp/citizen/legislation/data/legislation_api.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 法律条款阅读器(ADR-028 P3-1)——宪法与普通法律共用。
///
/// 渲染 章>节>条>款;宪法(tier=宪法)对不可修改条款渲染徽章、双语可切;
/// 顶部显状态 + 链上生效时间。读链:law + law_version(公民端默认生效版本)
/// + (宪法)immutableManifest;若存在待生效修订,额外读取待生效版时间用于提示。
class LawReaderPage extends StatefulWidget {
  const LawReaderPage({
    super.key,
    required this.lawId,
    this.api,
  });

  final int lawId;
  final LegislationApi? api;

  @override
  State<LawReaderPage> createState() => _LawReaderPageState();
}

class _LawReaderPageState extends State<LawReaderPage> {
  late final LegislationApi _api;
  bool _dependenciesReady = false;

  Law? _law;
  LawVersion? _version;
  Map<int, LawVersionLabel> _versionLabels = const {};
  ImmutableManifest? _manifest;
  int? _effectiveAt;
  int? _pendingEffectiveAt;
  bool _loading = true;
  String? _error;
  bool _showEn = false;
  final Set<int> _expanded = {};
  final Set<String> _expandedSections = {};

  /// 当前查看的版本号(默认=当前生效版本;版本史可切到历史版本)。
  int _selectedVersion = 0;

  bool get _isConstitution => _law?.tier == LawTier.constitution;

  @override
  void initState() {
    super.initState();
    if (widget.api != null) {
      _api = widget.api!;
      _dependenciesReady = true;
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _api = LegislationApi(chain: context.read<CitizenSdk>().chain);
    _dependenciesReady = true;
    _load();
  }

  Future<void> _load() async {
    final hasLocal = await _loadLocalSnapshot();
    await _refreshFromChain(showSpinner: !hasLocal);
  }

  /// 先读本机快照，避免用户每次进入公民宪法都等待链上 RPC。
  Future<bool> _loadLocalSnapshot() async {
    final law = await _api.localLaw(widget.lawId);
    final versionId = law?.readerVersion;
    if (law == null || versionId == null) return false;
    final version = await _api.localLawVersion(law.lawId, versionId);
    if (version == null) return false;
    final manifest = law.tier == LawTier.constitution
        ? await _api.localImmutableManifest()
        : null;
    final versionLabels = await _loadLocalVersionLabels(law);
    final pendingVersionId = law.pendingVersion;
    int? pendingEffectiveAt;
    if (pendingVersionId != null && pendingVersionId != versionId) {
      final pendingVersion =
          await _api.localLawVersion(law.lawId, pendingVersionId);
      pendingEffectiveAt = pendingVersion?.effectiveAt;
    }
    if (!mounted) return false;
    setState(() {
      _applySnapshot(
        law,
        version,
        manifest,
        versionLabels: versionLabels,
        pendingEffectiveAt: pendingEffectiveAt,
      );
      _loading = false;
      _error = null;
    });
    return true;
  }

  Future<void> _refreshFromChain({required bool showSpinner}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final law = await _api.law(widget.lawId, forceRefresh: true);
      if (law == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = _showEn ? 'Law not found' : '未找到该法律';
          });
        }
        return;
      }
      final versionId = law.readerVersion;
      if (versionId == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = _showEn ? 'No readable version is available' : '该法律暂无可读版本';
          });
        }
        return;
      }
      final version =
          await _api.lawVersion(law.lawId, versionId, forceRefresh: true);
      final manifest = law.tier == LawTier.constitution
          ? await _api.immutableManifest(forceRefresh: true)
          : null;
      final versionLabels = await _loadVersionLabels(law, forceRefresh: true);
      final pendingVersionId = law.pendingVersion;
      int? pendingEffectiveAt;
      if (pendingVersionId != null && pendingVersionId != versionId) {
        final pendingVersion = await _api.lawVersion(
          law.lawId,
          pendingVersionId,
          forceRefresh: true,
        );
        pendingEffectiveAt = pendingVersion?.effectiveAt;
      }
      if (!mounted) return;
      if (!showSpinner &&
          _sameSnapshot(law, version, manifest,
              versionLabels: versionLabels,
              pendingEffectiveAt: pendingEffectiveAt)) {
        return;
      }
      setState(() {
        _applySnapshot(
          law,
          version,
          manifest,
          versionLabels: versionLabels,
          pendingEffectiveAt: pendingEffectiveAt,
        );
        _loading = false;
        _error = null;
      });
    } on Object {
      if (mounted) {
        if (showSpinner) {
          setState(() {
            _loading = false;
            _error =
                _showEn ? 'Failed to read law from chain' : '法律读取失败，请检查网络后重试';
          });
        }
      }
    }
  }

  /// 切换到历史版本(版本史)。重新拉取该版本正文并重置展开态。
  Future<void> _changeVersion(int version) async {
    final law = _law;
    if (law == null || version == _selectedVersion) return;
    final local = await _api.localLawVersion(law.lawId, version);
    final localLabel = await _api.localLawVersionLabel(law.lawId, version);
    if (local != null && mounted) {
      setState(() {
        _version = local;
        _selectedVersion = version;
        _effectiveAt = local.effectiveAt;
        _setVersionLabel(version, localLabel);
        _expanded.clear();
        _expandedSections.clear();
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final v = await _api.lawVersion(
        law.lawId,
        version,
        forceRefresh: true,
      );
      final label = await _api.lawVersionLabel(
        law.lawId,
        version,
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() {
        _version = v;
        _selectedVersion = version;
        _effectiveAt = v?.effectiveAt;
        _setVersionLabel(version, label);
        _expanded.clear();
        _expandedSections.clear();
        _loading = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _showEn ? 'Failed to read this version' : '版本读取失败，请检查网络后重试';
        });
      }
    }
  }

  void _applySnapshot(
    Law law,
    LawVersion? version,
    ImmutableManifest? manifest, {
    required Map<int, LawVersionLabel> versionLabels,
    required int? pendingEffectiveAt,
  }) {
    _law = law;
    _version = version;
    _selectedVersion = version?.version ?? law.readerVersion ?? 0;
    _versionLabels = Map<int, LawVersionLabel>.unmodifiable(versionLabels);
    _manifest = manifest;
    _effectiveAt = version?.effectiveAt;
    _pendingEffectiveAt = pendingEffectiveAt;
  }

  Future<Map<int, LawVersionLabel>> _loadLocalVersionLabels(Law law) async {
    final labels = <int, LawVersionLabel>{};
    for (var version = 1; version <= law.latestVersion; version++) {
      final label = await _api.localLawVersionLabel(law.lawId, version);
      if (label != null) labels[version] = label;
    }
    return labels;
  }

  Future<Map<int, LawVersionLabel>> _loadVersionLabels(
    Law law, {
    required bool forceRefresh,
  }) async {
    final labels = <int, LawVersionLabel>{};
    for (var version = 1; version <= law.latestVersion; version++) {
      final label = await _api.lawVersionLabel(
        law.lawId,
        version,
        forceRefresh: forceRefresh,
      );
      if (label != null) labels[version] = label;
    }
    return labels;
  }

  void _setVersionLabel(int version, LawVersionLabel? label) {
    final next = Map<int, LawVersionLabel>.of(_versionLabels);
    if (label == null) {
      next.remove(version);
    } else {
      next[version] = label;
    }
    _versionLabels = Map<int, LawVersionLabel>.unmodifiable(next);
  }

  bool _sameSnapshot(
    Law law,
    LawVersion? version,
    ImmutableManifest? manifest, {
    required Map<int, LawVersionLabel> versionLabels,
    required int? pendingEffectiveAt,
  }) {
    final currentLaw = _law;
    final currentVersion = _version;
    if (currentLaw == null || currentVersion == null || version == null) {
      return false;
    }
    return currentLaw.lawId == law.lawId &&
        currentLaw.effectiveVersion == law.effectiveVersion &&
        currentLaw.latestVersion == law.latestVersion &&
        currentLaw.pendingVersion == law.pendingVersion &&
        currentLaw.status == law.status &&
        currentVersion.version == version.version &&
        currentVersion.contentHash == version.contentHash &&
        _pendingEffectiveAt == pendingEffectiveAt &&
        _sameVersionLabels(_versionLabels, versionLabels) &&
        _sameManifest(_manifest, manifest);
  }

  bool _sameVersionLabels(
    Map<int, LawVersionLabel> a,
    Map<int, LawVersionLabel> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (entry.value.title != other.title ||
          entry.value.titleEn != other.titleEn) {
        return false;
      }
    }
    return true;
  }

  bool _sameManifest(ImmutableManifest? a, ImmutableManifest? b) {
    if (a == null || b == null) return a == b;
    if (a.articleNumbers.length != b.articleNumbers.length ||
        a.articleHashes.length != b.articleHashes.length) {
      return false;
    }
    for (var i = 0; i < a.articleNumbers.length; i++) {
      if (a.articleNumbers[i] != b.articleNumbers[i]) return false;
    }
    for (var i = 0; i < a.articleHashes.length; i++) {
      if (a.articleHashes[i] != b.articleHashes[i]) return false;
    }
    return true;
  }

  String _t(String zh, String? en) =>
      (_showEn && en != null && en.isNotEmpty) ? en : zh;

  String _formatMillis(int ms) {
    if (ms <= 0) {
      return _showEn ? 'immediately' : '立即';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  String _tierLabel(LawTier tier) => _showEn
      ? switch (tier) {
          LawTier.constitution => 'Constitution',
          LawTier.national => 'National',
          LawTier.provincial => 'Provincial',
          LawTier.municipal => 'Municipal',
        }
      : tier.label;

  String _voteTypeLabel(VoteType voteType) => _showEn
      ? switch (voteType) {
          VoteType.regular => 'Regular Bill',
          VoteType.regularEducation => 'Regular Education Bill',
          VoteType.major => 'Major Bill',
          VoteType.majorEducation => 'Major Education Bill',
          VoteType.special => 'Special Bill',
        }
      : voteType.label;

  String _headingTitle({
    required String title,
    required String? titleEn,
    required String fallback,
  }) {
    final text = _t(title, titleEn).trim();
    return text.isEmpty ? fallback : text;
  }

  @override
  Widget build(BuildContext context) {
    final v = _version;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: Text(v == null ? '法律' : _t(v.title, v.titleEn)),
        backgroundColor: AppTheme.surfaceCard,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          if (_isConstitution && v?.titleEn != null)
            TextButton(
              onPressed: () => setState(() => _showEn = !_showEn),
              child: Text(_showEn ? '中' : 'EN',
                  style: TextStyle(
                      fontSize: AppLayout.scaled(context, 13),
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(
              key: const ValueKey('law-reader-load-progress'),
              minHeight: AppLayout.scaled(context, 2),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final v = _version;
    final law = _law;
    if (_loading && (v == null || law == null)) {
      // 标题栏与阅读区域先出现，正文读取不再用整页圆形转圈替换页面。
      return ListView(
        padding: EdgeInsets.all(AppLayout.scaledValue(16)),
        children: [
          Container(
            key: const ValueKey('law-reader-loading-shell'),
            padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaledValue(14),
                vertical: AppLayout.scaledValue(18)),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正在读取法律正文',
                  style: TextStyle(
                    fontSize: AppLayout.scaledValue(15),
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: AppLayout.scaledValue(6)),
                const Text(
                  '正文将在本地快照或 finalized 链数据返回后显示',
                  style: TextStyle(color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
        ],
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
            TextButton(
              onPressed: _load,
              child: Text(_showEn ? 'Retry' : '重试'),
            ),
          ],
        ),
      );
    }
    if (v == null || law == null) {
      return Center(child: Text(_showEn ? 'No content' : '暂无正文'));
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          sliver: SliverToBoxAdapter(child: _header(law, v)),
        ),
        for (final chapter in v.chapters) ..._chapterSlivers(chapter),
        SliverToBoxAdapter(child: SizedBox(height: AppLayout.scaledValue(16))),
      ],
    );
  }

  Widget _header(Law law, LawVersion v) {
    final statusColor = switch (law.status) {
      LawStatus.effective => AppTheme.success,
      LawStatus.repealed => AppTheme.danger,
      LawStatus.pending => AppTheme.primary,
    };
    final dateLabel = switch (law.status) {
      LawStatus.effective => _showEn
          ? 'Effective at ${_effectiveAt == null ? '—' : _formatMillis(_effectiveAt!)}'
          : '生效时间 ${_effectiveAt == null ? '—' : _formatMillis(_effectiveAt!)}',
      LawStatus.repealed => _showEn ? 'Repealed' : '已废止',
      LawStatus.pending => law.pendingVersion != null &&
              law.pendingVersion != v.version
          ? (_showEn
              ? 'Pending amendment takes effect at ${_pendingEffectiveAt == null ? '—' : _formatMillis(_pendingEffectiveAt!)}'
              : '待生效修订将于 ${_pendingEffectiveAt == null ? '—' : _formatMillis(_pendingEffectiveAt!)} 生效')
          : (_showEn
              ? 'Takes effect at ${_effectiveAt == null ? '—' : _formatMillis(_effectiveAt!)}'
              : '将于 ${_effectiveAt == null ? '—' : _formatMillis(_effectiveAt!)} 生效'),
    };
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaledValue(14),
          vertical: AppLayout.scaledValue(12)),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaledValue(8),
                vertical: AppLayout.scaledValue(3)),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
            ),
            child: Text('${_tierLabel(law.tier)} · ${_versionName(v.version)}',
                style: TextStyle(
                    fontSize: AppLayout.scaledValue(11),
                    fontWeight: FontWeight.w600,
                    color: statusColor)),
          ),
          // 表决类型徽章(创世宪法 proposalId=0 不显示)。
          if (v.proposalId != 0) ...[
            SizedBox(width: AppLayout.scaledValue(6)),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: AppLayout.scaledValue(8),
                  vertical: AppLayout.scaledValue(3)),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppLayout.scaledValue(8)),
              ),
              child: Text(_voteTypeLabel(v.voteTypeEnum),
                  style: TextStyle(
                      fontSize: AppLayout.scaledValue(11),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary)),
            ),
          ],
          SizedBox(width: AppLayout.scaledValue(10)),
          Expanded(
            child: Text(dateLabel,
                style: TextStyle(
                    fontSize: AppLayout.scaledValue(12.5),
                    color: AppTheme.textSecondary)),
          ),
          // 版本史:多版本时可切换查看历史版本。
          if (law.latestVersion > 1) _versionMenu(law),
        ],
      ),
    );
  }

  Widget _versionMenu(Law law) {
    return PopupMenuButton<int>(
      tooltip: _showEn ? 'Version history' : '版本历史',
      onSelected: _changeVersion,
      itemBuilder: (_) => [
        for (var ver = law.latestVersion; ver >= 1; ver--)
          PopupMenuItem<int>(
            value: ver,
            child: Text(
              _versionLabel(law, ver),
              style: TextStyle(
                fontWeight:
                    ver == _selectedVersion ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history,
              size: AppLayout.scaledValue(16), color: AppTheme.textSecondary),
          SizedBox(width: AppLayout.scaledValue(2)),
          Text(_showEn ? 'History' : '版本史',
              style: TextStyle(
                  fontSize: AppLayout.scaledValue(12),
                  color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  String _versionLabel(Law law, int version) {
    final name = _versionName(version);
    if (law.effectiveVersion == version) {
      return _showEn ? '$name (effective)' : '$name(生效)';
    }
    if (law.pendingVersion == version) {
      return _showEn ? '$name (pending)' : '$name(待生效)';
    }
    return name;
  }

  String _versionName(int version) {
    final label = _versionLabels[version];
    if (label == null) return 'v$version';
    final text = _t(label.title, label.titleEn).trim();
    return text.isEmpty ? 'v$version' : text;
  }

  List<Widget> _chapterSlivers(LawChapter ch) {
    final expanded = _expanded.contains(ch.number);
    return [
      SliverMainAxisGroup(
        slivers: [
          PinnedHeaderSliver(
            child: _chapterHeader(ch, expanded),
          ),
          if (expanded)
            SliverPadding(
              padding:
                  EdgeInsets.symmetric(horizontal: AppLayout.scaledValue(16)),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _sectionTile(ch, ch.sections[index]),
                  childCount: ch.sections.length,
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaledValue(16),
            ),
            sliver: const SliverToBoxAdapter(
              child: Divider(height: 1, color: AppTheme.divider),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _chapterHeader(LawChapter ch, bool expanded) {
    final title = _headingTitle(
      title: ch.title,
      titleEn: ch.titleEn,
      fallback: _showEn ? 'Chapter ${ch.number}' : '第${ch.number}章',
    );
    final tooltip = _showEn
        ? (expanded ? 'Collapse chapter' : 'Expand chapter')
        : (expanded ? '收起本章' : '展开本章');
    return Container(
      height: AppLayout.scaledValue(54),
      color: AppTheme.scaffoldBg,
      padding: EdgeInsets.symmetric(horizontal: AppLayout.scaledValue(16)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppTheme.scaffoldBg,
          border: Border(bottom: BorderSide(color: AppTheme.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppLayout.scaledValue(16),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryDark,
                ),
              ),
            ),
            IconButton(
              tooltip: tooltip,
              onPressed: () => _toggleChapter(ch.number),
              icon: Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleChapter(int chapterNumber) {
    setState(() {
      if (_expanded.remove(chapterNumber)) {
        _expandedSections
            .removeWhere((key) => key.startsWith('$chapterNumber:'));
      } else {
        _expanded.add(chapterNumber);
      }
    });
  }

  Widget _sectionTile(LawChapter chapter, LawSection sec) {
    final key = _sectionKey(chapter.number, sec.number);
    final expanded = _expandedSections.contains(key);
    return Padding(
      padding: EdgeInsets.only(
          left: AppLayout.scaledValue(6),
          top: AppLayout.scaledValue(6),
          bottom: AppLayout.scaledValue(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _headingTitle(
                    title: sec.title,
                    titleEn: sec.titleEn,
                    fallback:
                        _showEn ? 'Section ${sec.number}' : '第${sec.number}节',
                  ),
                  style: TextStyle(
                      fontSize: AppLayout.scaledValue(14),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary),
                ),
              ),
              IconButton(
                tooltip: _showEn
                    ? (expanded ? 'Collapse section' : 'Expand section')
                    : (expanded ? '收起本节' : '展开本节'),
                onPressed: () => _toggleSection(key),
                icon: Icon(
                  expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (expanded) ...sec.articles.map(_articleTile),
        ],
      ),
    );
  }

  String _sectionKey(int chapterNumber, int sectionNumber) =>
      '$chapterNumber:$sectionNumber';

  void _toggleSection(String key) {
    setState(() {
      if (!_expandedSections.remove(key)) {
        _expandedSections.add(key);
      }
    });
  }

  Widget _articleTile(LawArticle art) {
    final immutable = _manifest?.isImmutable(art.number) ?? false;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppLayout.scaledValue(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                    _headingTitle(
                      title: art.title,
                      titleEn: art.titleEn,
                      fallback:
                          _showEn ? 'Article ${art.number}' : '第${art.number}条',
                    ),
                    style: TextStyle(
                        fontSize: AppLayout.scaledValue(14.5),
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
              ),
              if (immutable) ...[
                SizedBox(width: AppLayout.scaledValue(8)),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: AppLayout.scaledValue(6), vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppLayout.scaledValue(6)),
                  ),
                  child: Text(_showEn ? 'Immutable Clause' : '不可修改条款',
                      style: TextStyle(
                          fontSize: AppLayout.scaledValue(10),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.danger)),
                ),
              ],
            ],
          ),
          if (art.body.isNotEmpty) ...[
            SizedBox(height: AppLayout.scaledValue(4)),
            Text(_t(art.body, art.bodyEn),
                style: TextStyle(
                    fontSize: AppLayout.scaledValue(13.5),
                    height: 1.6,
                    color: AppTheme.textPrimary)),
          ],
          ...art.clauses.map((c) => Padding(
                padding: EdgeInsets.only(
                    top: AppLayout.scaledValue(6),
                    left: AppLayout.scaledValue(8)),
                // 链上款正文已自带“第一款 / Paragraph 1”前缀,UI 不再二次拼接。
                child: Text(_t(c.text, c.textEn),
                    style: TextStyle(
                        fontSize: AppLayout.scaledValue(13),
                        height: 1.6,
                        color: AppTheme.textSecondary)),
              )),
        ],
      ),
    );
  }
}
