import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';

import 'package:citizenapp/8964/compose/article/article_blocks.dart';
import 'package:citizenapp/8964/compose/article/article_section_editor.dart';
import 'package:citizenapp/8964/compose/compose_media_picker.dart';
import 'package:citizenapp/8964/compose/compose_payload.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/widgets/compose_media_widgets.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/services/square_media_draft.dart';
import 'package:citizenapp/8964/widgets/square_media_carousel.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';

sealed class _EditSectionMedia {
  const _EditSectionMedia();
}

final class _EditGallery extends _EditSectionMedia {
  _EditGallery(List<SquareLocalMediaDraft> drafts)
      : drafts = List<SquareLocalMediaDraft>.unmodifiable(drafts);
  final List<SquareLocalMediaDraft> drafts;
}

final class _EditVideo extends _EditSectionMedia {
  const _EditVideo(this.draft);
  final SquareLocalMediaDraft draft;
}

final class _EditSection {
  _EditSection({
    required this.id,
    required this.controller,
    required this.focusNode,
    this.media,
  }) : lastDeltaJson = jsonEncode(articleControllerDelta(controller));

  final int id;
  final QuillController controller;
  final FocusNode focusNode;
  _EditSectionMedia? media;
  String lastDeltaJson;

  String get plainText =>
      articleDeltaPlainText(articleControllerDelta(controller));

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

/// 文章编辑区：标题、首图和“富文本 + 可选媒体”的段落单元。
class SquareArticleComposeBody extends StatefulWidget {
  const SquareArticleComposeBody({
    super.key,
    this.initialTitle,
    this.initialText,
    this.onChanged,
    this.persistMedia,
    this.imagePicker,
    this.mediaPicker = const DeviceComposeMediaPicker(),
    this.mediaDraftBuilder = buildSquareMediaDraft,
  });

  final String? initialTitle;
  final String? initialText;
  final VoidCallback? onChanged;
  final ComposeMediaPersistor? persistMedia;
  final ImagePicker? imagePicker;
  final ComposeMediaPicker mediaPicker;
  final SquareMediaDraftBuilder mediaDraftBuilder;

  @override
  State<SquareArticleComposeBody> createState() =>
      SquareArticleComposeBodyState();
}

class SquareArticleComposeBodyState extends State<SquareArticleComposeBody>
    implements ComposeBodyCollector {
  static const _titleToggleDistance = 12.0;

  final TextEditingController _title = TextEditingController();
  late final ImagePicker _picker;
  SquareLocalMediaDraft? _cover;
  final List<_EditSection> _sections = [];
  _EditSection? _activeSection;
  _EditSection? _invalidSection;
  var _nextSectionId = 0;
  bool _titleRegionVisible = true;
  bool? _trackingUpwardScroll;
  double _trackedScrollDistance = 0;

  @override
  void initState() {
    super.initState();
    _picker = widget.imagePicker ?? ImagePicker();
    _title.text = widget.initialTitle ?? '';
    _title.addListener(_onChanged);
    final initial = widget.initialText?.trim() ?? '';
    final section = _newSection(
      initial.isEmpty
          ? null
          : [
              {'insert': initial},
              const {'insert': '\n'},
            ],
    );
    _sections.add(section);
    _activeSection = section;
  }

  @override
  void dispose() {
    _title.dispose();
    for (final section in _sections) {
      section.dispose();
    }
    super.dispose();
  }

  _EditSection _newSection([Object? delta, _EditSectionMedia? media]) {
    final controller = articleQuillController(delta);
    final focusNode = FocusNode();
    final section = _EditSection(
      id: _nextSectionId++,
      controller: controller,
      focusNode: focusNode,
      media: media,
    );
    controller.addListener(() => _onSectionControllerChanged(section));
    focusNode.addListener(() {
      if (!focusNode.hasFocus || !mounted) return;
      setState(() => _activeSection = section);
    });
    return section;
  }

  void _onSectionControllerChanged(_EditSection section) {
    final deltaJson = jsonEncode(articleControllerDelta(section.controller));
    if (deltaJson == section.lastDeltaJson) return;
    section.lastDeltaJson = deltaJson;
    if (identical(_invalidSection, section) &&
        section.plainText.runes.length >= articleSectionTextMin) {
      _invalidSection = null;
    }
    _onChanged();
  }

  void _onChanged() {
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }

  int get _bodyLength => _sections.fold<int>(
        0,
        (sum, section) => sum + section.plainText.runes.length,
      );

  @override
  bool get isContentValid {
    final textParts = <String>[];
    for (final section in _sections) {
      final text = section.plainText;
      if (text.isEmpty) {
        if (section.media != null) return false;
        continue;
      }
      if (text.runes.length < articleSectionTextMin) return false;
      textParts.add(text);
    }
    return articleValidationError(
          title: _title.text,
          hasCover: _cover != null,
          body: textParts.join('\n\n'),
        ) ==
        null;
  }

  @override
  ComposePayload collect() {
    final cover = _cover;
    final draftSections = <ArticleDraftSection>[];
    final textParts = <String>[];
    for (final section in _sections) {
      final text = section.plainText;
      if (text.isEmpty) {
        if (section.media == null) continue;
        _focusInvalidSection(section);
        return const ComposePayload.invalid('插入媒体的段落必须输入不少于 10 个字');
      }
      if (text.runes.length < articleSectionTextMin) {
        _focusInvalidSection(section);
        return const ComposePayload.invalid('文章每个段落不少于 10 个字');
      }
      final media = switch (section.media) {
        _EditGallery(:final drafts) => ArticleDraftGallery(drafts),
        _EditVideo(:final draft) => ArticleDraftVideo(draft),
        null => null,
      };
      draftSections.add(
        ArticleDraftSection(
          delta: articleControllerDelta(section.controller),
          media: media,
        ),
      );
      textParts.add(text);
    }
    final error = articleValidationError(
      title: _title.text,
      hasCover: cover != null,
      body: textParts.join('\n\n'),
    );
    if (error != null) return ComposePayload.invalid(error);
    if (_invalidSection != null) setState(() => _invalidSection = null);
    final parts = buildArticleManifest(cover: cover!, sections: draftSections);
    return ComposePayload.ok(
      text: parts.text,
      title: _title.text.trim(),
      mediaDrafts: parts.mediaDrafts,
      contentSections: parts.contentSections,
    );
  }

  @override
  ComposeSnapshot snapshot() {
    final media = <SquareLocalMediaDraft>[?_cover];
    final sections = <Map<String, Object?>>[];
    final textParts = <String>[];
    for (final section in _sections) {
      final text = section.plainText;
      if (text.isEmpty && section.media == null) continue;
      final encoded = <String, Object?>{
        'text_delta': articleControllerDelta(section.controller),
      };
      switch (section.media) {
        case _EditGallery(:final drafts):
          final indices = <int>[];
          for (final draft in drafts) {
            media.add(draft);
            indices.add(media.length - 1);
          }
          encoded['gallery_media_indices'] = indices;
        case _EditVideo(:final draft):
          media.add(draft);
          encoded['video_media_index'] = media.length - 1;
        case null:
          break;
      }
      sections.add(encoded);
      if (text.isNotEmpty) textParts.add(text);
    }
    return ComposeSnapshot(
      text: textParts.join('\n\n'),
      title: _title.text,
      media: media,
      contentSections: sections,
    );
  }

  /// 草稿只接受第 7 步唯一 `content_sections`，不恢复旧平铺块。
  void restore(SquareComposeDraft draft) {
    if (draft.postType != SquarePostType.article) {
      throw const FormatException('文章草稿类型不合法');
    }
    final rawSections = draft.contentSections;
    if (rawSections == null || rawSections.isEmpty) {
      throw const FormatException('文章草稿缺少正文段落');
    }
    final media = draft.media;
    final referenced = <int>{};
    final rebuilt = <_EditSection>[];
    for (final raw in rawSections) {
      final gallery = raw['gallery_media_indices'];
      final video = raw['video_media_index'];
      if (gallery != null && video != null) {
        throw const FormatException('文章草稿段落媒体不合法');
      }
      _EditSectionMedia? sectionMedia;
      if (gallery is List) {
        if (gallery.isEmpty || gallery.length > 9) {
          throw const FormatException('文章草稿图集数量不合法');
        }
        final drafts = <SquareLocalMediaDraft>[];
        for (final value in gallery) {
          if (value is! int ||
              value < 0 ||
              value >= media.length ||
              !referenced.add(value) ||
              media[value].mediaKind != SquareMediaKind.image) {
            throw const FormatException('文章草稿图集引用不合法');
          }
          drafts.add(media[value]);
        }
        sectionMedia = _EditGallery(drafts);
      } else if (video is int) {
        if (video < 0 ||
            video >= media.length ||
            !referenced.add(video) ||
            media[video].mediaKind != SquareMediaKind.video) {
          throw const FormatException('文章草稿视频引用不合法');
        }
        sectionMedia = _EditVideo(media[video]);
      }
      rebuilt.add(_newSection(raw['text_delta'], sectionMedia));
    }
    final cover = media.isNotEmpty &&
            media.first.mediaKind == SquareMediaKind.image &&
            !referenced.contains(0)
        ? media.first
        : null;
    for (final section in _sections) {
      section.dispose();
    }
    setState(() {
      _cover = cover;
      _invalidSection = null;
      _sections
        ..clear()
        ..addAll(rebuilt);
      _activeSection = rebuilt.first;
      _title.text = draft.title ?? '';
    });
  }

  Future<void> pickCover() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    if (_supportedMediaKind(image) != SquareMediaKind.image) {
      _showMediaError('首图只支持 JPEG、PNG 或 WebP 图片');
      return;
    }
    var draft = await widget.mediaDraftBuilder(image, SquareMediaKind.image);
    final persist = widget.persistMedia;
    if (persist != null) draft = await persist(draft);
    if (!mounted) return;
    setState(() => _cover = draft);
    widget.onChanged?.call();
  }

  void removeCover() {
    if (_cover == null) return;
    setState(() => _cover = null);
    widget.onChanged?.call();
  }

  Future<void> _insertMediaForSection(_EditSection section) async {
    if (section.media is _EditGallery) {
      await _replaceGallery(section);
      return;
    }
    List<ComposePickedMedia> selected;
    try {
      selected = await widget.mediaPicker.pickArticleMedia(context);
    } on FormatException catch (error) {
      if (mounted) _showMediaError(error.message.toString());
      return;
    }
    if (selected.isEmpty || !mounted) return;
    final videoCount = selected
        .where((item) => item.mediaKind == SquareMediaKind.video)
        .length;
    if ((videoCount > 0 && (selected.length != 1 || videoCount != 1)) ||
        (videoCount == 0 && selected.length > 9)) {
      _showMediaError('一次只能选择 1 个视频，或 1–9 张图片');
      return;
    }
    final drafts = <SquareLocalMediaDraft>[];
    for (final item in selected) {
      var draft = (await widget.mediaDraftBuilder(item.file, item.mediaKind))
          .copyWith(photoManagerAssetId: item.photoManagerAssetId);
      final persist = widget.persistMedia;
      if (persist != null) draft = await persist(draft);
      drafts.add(draft);
    }
    if (!mounted) return;
    final sectionMedia =
        videoCount == 1 ? _EditVideo(drafts.single) : _EditGallery(drafts);
    if (!_sections.contains(section)) return;
    setState(() {
      section.media = sectionMedia;
      _activeSection = section;
    });
    widget.onChanged?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) section.focusNode.requestFocus();
    });
  }

  /// 轻点已有图集只替换该段图片，不新增段落、不改变文本；取消或失败保留原图集。
  Future<void> _replaceGallery(_EditSection section) async {
    try {
      final current = (section.media as _EditGallery).drafts;
      final fixedWithoutAssetId = current
          .where((draft) => draft.photoManagerAssetId == null)
          .toList(growable: false);
      if (fixedWithoutAssetId.length >= 9) {
        throw const FormatException('现有照片已达到9张，请先删除一张再增加');
      }
      final selection = await widget.mediaPicker.pickImagesWithSelection(
        context,
        9 - fixedWithoutAssetId.length,
        selectedPhotoManagerAssetIds: [
          for (final draft in current)
            if (draft.photoManagerAssetId case final String id) id,
        ],
      );
      if (selection == null || !mounted || !_sections.contains(section)) return;
      if (selection.selected.any(
        (item) => item.mediaKind != SquareMediaKind.image,
      )) {
        throw const FormatException('图集只能选择 1–9 张图片');
      }
      final unavailable = selection.unavailablePhotoManagerAssetIds.toSet();
      final fixed = <SquareLocalMediaDraft>[
        ...fixedWithoutAssetId,
        ...current.where(
          (draft) => unavailable.contains(draft.photoManagerAssetId),
        ),
      ];
      final currentByAssetId = {
        for (final draft in current)
          if (draft.photoManagerAssetId case final String id) id: draft,
      };
      final selectedDrafts = <SquareLocalMediaDraft>[];
      for (final item in selection.selected) {
        final existing = currentByAssetId[item.photoManagerAssetId];
        if (existing != null) {
          selectedDrafts.add(existing);
          continue;
        }
        var draft = (await widget.mediaDraftBuilder(
          item.file,
          SquareMediaKind.image,
        ))
            .copyWith(photoManagerAssetId: item.photoManagerAssetId);
        final persist = widget.persistMedia;
        if (persist != null) draft = await persist(draft);
        selectedDrafts.add(draft);
      }
      final drafts = [...fixed, ...selectedDrafts];
      if (drafts.length > 9) throw const FormatException('图集只能选择 1–9 张图片');
      if (!mounted || !_sections.contains(section)) return;
      if (drafts.isEmpty) {
        _removeSectionMedia(section);
        return;
      }
      setState(() {
        section.media = _EditGallery(drafts);
        _activeSection = section;
      });
      widget.onChanged?.call();
    } on FormatException catch (error) {
      if (mounted) _showMediaError(error.message.toString());
    } catch (_) {
      if (mounted) _showMediaError('更换照片失败，请重试');
    }
  }

  void addTextSection() {
    final active = _activeSection ?? _sections.last;
    final section = _newSection();
    setState(() {
      _sections.insert(_sections.indexOf(active) + 1, section);
      _activeSection = section;
    });
    widget.onChanged?.call();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => section.focusNode.requestFocus());
  }

  Future<bool> _confirmDeleteSection(_EditSection section) async {
    if (section.plainText.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除这一段？'),
            content: const Text('段落已有文字，删除后关联的图片或视频也会一并删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _deleteSection(_EditSection section) {
    final index = _sections.indexOf(section);
    if (index < 0) return;
    setState(() {
      _sections.removeAt(index);
      if (identical(_invalidSection, section)) _invalidSection = null;
      if (_sections.isEmpty) _sections.add(_newSection());
      _activeSection = _sections[index.clamp(0, _sections.length - 1)];
    });
    section.dispose();
    widget.onChanged?.call();
  }

  void _removeSectionMedia(_EditSection section) {
    if (section.plainText.isEmpty) {
      _deleteSection(section);
      return;
    }
    setState(() => section.media = null);
    widget.onChanged?.call();
  }

  void _removeGalleryImage(_EditSection section, int imageIndex) {
    final gallery = section.media as _EditGallery;
    if (gallery.drafts.length == 1) {
      _removeSectionMedia(section);
      return;
    }
    final drafts = List<SquareLocalMediaDraft>.of(gallery.drafts)
      ..removeAt(imageIndex);
    setState(() => section.media = _EditGallery(drafts));
    widget.onChanged?.call();
  }

  void _focusInvalidSection(_EditSection section) {
    if (!identical(_invalidSection, section)) {
      setState(() => _invalidSection = section);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) section.focusNode.requestFocus();
    });
  }

  SquareMediaKind? _supportedMediaKind(XFile file) {
    final contentType = file.mimeType?.toLowerCase();
    if (const {'image/jpeg', 'image/png', 'image/webp'}.contains(contentType)) {
      return SquareMediaKind.image;
    }
    if (const {'video/mp4', 'video/webm'}.contains(contentType)) {
      return SquareMediaKind.video;
    }
    final path = file.path.toLowerCase();
    if (path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp')) {
      return SquareMediaKind.image;
    }
    if (path.endsWith('.mp4') || path.endsWith('.webm')) {
      return SquareMediaKind.video;
    }
    return null;
  }

  void _showMediaError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 只响应用户在图文框区域的拖动。连续上滑超过阈值收起标题、首图和分隔线，
  /// 连续下滑超过阈值恢复；两个字数计数位于折叠区之外，始终保留。
  bool _handleSectionScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      _trackingUpwardScroll = null;
      _trackedScrollDistance = 0;
      return false;
    }
    if (notification is ScrollEndNotification) {
      _trackingUpwardScroll = null;
      _trackedScrollDistance = 0;
      return false;
    }
    if (notification is! ScrollUpdateNotification ||
        notification.dragDetails == null) {
      return false;
    }
    if (notification.metrics.pixels <= 0) {
      _trackingUpwardScroll = null;
      _trackedScrollDistance = 0;
      if (!_titleRegionVisible) setState(() => _titleRegionVisible = true);
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    // scrollDelta 为正表示手指上滑、正文向上推进。
    final upward = delta > 0;
    if (_trackingUpwardScroll != upward) {
      _trackingUpwardScroll = upward;
      _trackedScrollDistance = 0;
    }
    _trackedScrollDistance += delta.abs();
    if (_trackedScrollDistance < _titleToggleDistance) return false;
    _trackedScrollDistance = 0;
    final visible = !upward;
    if (_titleRegionVisible != visible) {
      setState(() => _titleRegionVisible = visible);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppTheme.surfaceCard,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ClipRect(
                child: AnimatedAlign(
                  key: const ValueKey('article-title-region'),
                  alignment: Alignment.topCenter,
                  heightFactor: _titleRegionVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: IgnorePointer(
                    ignoring: !_titleRegionVisible,
                    child: AnimatedOpacity(
                      opacity: _titleRegionVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const ValueKey('article-title-field'),
                                    controller: _title,
                                    minLines: 1,
                                    maxLines: 2,
                                    maxLength: articleTitleMax,
                                    maxLengthEnforcement:
                                        MaxLengthEnforcement.enforced,
                                    inputFormatters: const [
                                      _UnicodeScalarLengthFormatter(
                                        articleTitleMax,
                                      )
                                    ],
                                    buildCounter: (_,
                                            {required currentLength,
                                            required isFocused,
                                            maxLength}) =>
                                        null,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      hintText: '请输入文章标题',
                                    ),
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: AppLayout.scaled(context, 16),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                SizedBox(width: AppLayout.scaled(context, 8)),
                                Padding(
                                  // 与顶部“添加图文框”和正文媒体入口共享同一内容右边界。
                                  padding: EdgeInsets.only(
                                    top: AppLayout.scaled(context, 7),
                                  ),
                                  child: _ArticleCoverAction(
                                    draft: _cover,
                                    onPick: pickCover,
                                    onRemove: removeCover,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            // 计数行左右各留 16；细线只留 8，因此两端分别超过计数文字。
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Container(
                              key: const ValueKey('article-title-divider'),
                              height: 1,
                              color: AppTheme.border,
                            ),
                          ),
                          SizedBox(height: AppLayout.scaled(context, 4)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      '正文 $_bodyLength/$articleBodyMax',
                      key: const ValueKey('article-body-counter'),
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: AppLayout.scaled(context, 11),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_title.text.runes.length}/$articleTitleMax',
                      key: const ValueKey('article-title-counter'),
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: AppLayout.scaled(context, 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleSectionScroll,
            child: ListView.builder(
              key: const ValueKey('article-sections-list'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _sections.length,
              itemBuilder: (context, index) {
                final section = _sections[index];
                return Padding(
                  padding:
                      EdgeInsets.only(bottom: AppLayout.scaled(context, 14)),
                  child: _ArticleSectionGroup(
                    connectorKey:
                        ValueKey('article-section-connector-${section.id}'),
                    child: Column(
                      children: [
                        ArticleSectionEditor(
                          sectionKey: ValueKey('article-section-${section.id}'),
                          controller: section.controller,
                          focusNode: section.focusNode,
                          invalid: identical(_invalidSection, section),
                          mediaAction: ComposeMediaAddButton(
                            key: ValueKey(
                              'article-insert-media-${section.id}',
                            ),
                            icon: Icons.add_photo_alternate_outlined,
                            // 只缩小图形，保持按钮点击区不变；入口随段落框内边距
                            // 一并向右下校准，避免侵占富文本输入区域。
                            iconSize: 24,
                            tooltip:
                                section.media == null ? '插入图片或视频' : '更换本段图片或视频',
                            onPressed: () => _insertMediaForSection(section),
                          ),
                          confirmDelete: () => _confirmDeleteSection(section),
                          onDeleted: () => _deleteSection(section),
                        ),
                        if (section.media case _EditGallery(:final drafts))
                          Padding(
                            padding: EdgeInsets.only(
                                top: AppLayout.scaled(context, 8)),
                            child: Semantics(
                              button: true,
                              label: '重新选择本组照片',
                              child: GestureDetector(
                                key: ValueKey(
                                  'article-replace-gallery-${section.id}',
                                ),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _replaceGallery(section),
                                child: SquareMediaCarousel(
                                  children: [
                                    for (var imageIndex = 0;
                                        imageIndex < drafts.length;
                                        imageIndex++)
                                      _InlineImage(
                                        draft: drafts[imageIndex],
                                        onRemove: () => _removeGalleryImage(
                                          section,
                                          imageIndex,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else if (section.media case _EditVideo(:final draft))
                          Padding(
                            padding: EdgeInsets.only(
                                top: AppLayout.scaled(context, 8)),
                            child: _InlineVideo(
                              draft: draft,
                              onRemove: () => _removeSectionMedia(section),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Container(
          key: const ValueKey('article-bottom-toolbar'),
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppTheme.surfaceCard,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: ArticleRichTextToolbar(
            controller: (_activeSection ?? _sections.first).controller,
          ),
        ),
      ],
    );
  }
}

/// 首图入口固定在标题右侧；选中后在同一位置显示缩略图和删除入口。
class _ArticleCoverAction extends StatelessWidget {
  const _ArticleCoverAction({
    required this.draft,
    required this.onPick,
    required this.onRemove,
  });

  final SquareLocalMediaDraft? draft;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final media = draft;
    if (media == null) {
      return ComposeMediaAddButton(
        key: const ValueKey('article-cover-picker'),
        icon: Icons.add_photo_alternate_outlined,
        tooltip: '选择首图',
        onPressed: onPick,
      );
    }
    return SizedBox.square(
      key: const ValueKey('article-cover-picker'),
      dimension: AppLayout.scaled(context, 36),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(AppLayout.scaledValue(6)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPick,
                child: Image.file(
                  File(media.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: ComposeMediaRemoveButton(
              tooltip: '删除首图',
              onPressed: onRemove,
              size: AppLayout.scaled(context, 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一个段落只绘制一条连接线，文本或媒体高度变化时由布局自动更新线长。
class _ArticleSectionGroup extends StatelessWidget {
  const _ArticleSectionGroup({
    required this.connectorKey,
    required this.child,
  });

  final Key connectorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(left: AppLayout.scaled(context, 14)),
          child: child,
        ),
        Positioned(
          left: AppLayout.scaled(context, 4),
          top: AppTheme.radiusMd,
          bottom: AppTheme.radiusMd,
          child: SizedBox(
            width: 1,
            child: CustomPaint(
              key: connectorKey,
              painter: _SectionConnectorPainter(
                color: AppTheme.primary.withValues(alpha: 0.48),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionConnectorPainter extends CustomPainter {
  const _SectionConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const dash = 4.0;
    const gap = 4.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(0, y),
        Offset(0, (y + dash).clamp(0, size.height)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SectionConnectorPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _InlineImage extends StatelessWidget {
  const _InlineImage({required this.draft, required this.onRemove});
  final SquareLocalMediaDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(draft.path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AppTheme.surfaceElevated,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: ComposeMediaRemoveButton(
                  tooltip: '删除图片',
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
        ),
      );
}

class _InlineVideo extends StatelessWidget {
  const _InlineVideo({required this.draft, required this.onRemove});
  final SquareLocalMediaDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ComposeLocalVideoPreview(path: draft.path, interactive: true),
              Positioned(
                top: 6,
                right: 6,
                child: ComposeMediaRemoveButton(
                  tooltip: '删除视频',
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
        ),
      );
}

class _UnicodeScalarLengthFormatter extends TextInputFormatter {
  const _UnicodeScalarLengthFormatter(this.maxLength);
  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxLength) return newValue;
    final text = String.fromCharCodes(newValue.text.runes.take(maxLength));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
