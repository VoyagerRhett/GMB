import 'dart:io';

import 'package:flutter/material.dart';

import 'package:citizenapp/8964/compose/compose_media_picker.dart';
import 'package:citizenapp/8964/compose/compose_payload.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/widgets/compose_media_widgets.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/services/square_media_draft.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';

const int documentTextMax = 300;
const int documentMaxImages = 9;

/// 公文编辑器：只允许纯文字、纯图片或图文，不接收视频。
class SquareDocumentComposeBody extends StatefulWidget {
  const SquareDocumentComposeBody({
    super.key,
    this.initialText,
    this.initialMedia = const <SquareLocalMediaDraft>[],
    this.onChanged,
    this.persistMedia,
    this.mediaPicker = const DeviceComposeMediaPicker(),
    this.mediaDraftBuilder = buildSquareMediaDraft,
    this.onMediaCountChanged,
  });

  final String? initialText;
  final List<SquareLocalMediaDraft> initialMedia;
  final VoidCallback? onChanged;
  final ComposeMediaPersistor? persistMedia;
  final ComposeMediaPicker mediaPicker;
  final SquareMediaDraftBuilder mediaDraftBuilder;
  final ValueChanged<int>? onMediaCountChanged;

  @override
  State<SquareDocumentComposeBody> createState() =>
      SquareDocumentComposeBodyState();
}

class SquareDocumentComposeBodyState extends State<SquareDocumentComposeBody>
    implements ComposeBodyCollector {
  final TextEditingController _text = TextEditingController();
  final List<SquareLocalMediaDraft> _media = [];

  @override
  void initState() {
    super.initState();
    _text.text = widget.initialText ?? '';
    _media.addAll(
      widget.initialMedia.where(
        (item) => item.mediaKind == SquareMediaKind.image,
      ),
    );
    _text.addListener(() => widget.onChanged?.call());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMediaCountChanged?.call(_media.length);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void restore(SquareComposeDraft draft) {
    if (draft.postType != SquarePostType.document ||
        draft.media.any((item) => item.mediaKind != SquareMediaKind.image)) {
      throw const FormatException('公文草稿类型或媒体不合法');
    }
    setState(() {
      _text.text = draft.text;
      _media
        ..clear()
        ..addAll(draft.media);
    });
    widget.onMediaCountChanged?.call(_media.length);
  }

  @override
  bool get isContentValid {
    final text = _text.text.trim();
    return text.runes.length <= documentTextMax &&
        _media.length <= documentMaxImages &&
        _media.every((item) => item.mediaKind == SquareMediaKind.image) &&
        (text.isNotEmpty || _media.isNotEmpty);
  }

  @override
  ComposePayload collect() {
    final text = _text.text.trim();
    if (text.runes.length > documentTextMax) {
      return const ComposePayload.invalid('公文文字不能超过300字');
    }
    if (_media.length > documentMaxImages) {
      return const ComposePayload.invalid('公文图片不能超过9张');
    }
    if (_media.any((item) => item.mediaKind != SquareMediaKind.image)) {
      return const ComposePayload.invalid('公文只能使用图片');
    }
    if (text.isEmpty && _media.isEmpty) {
      return const ComposePayload.invalid('公文内容不能为空');
    }
    return ComposePayload.ok(
      text: text,
      mediaDrafts: List<SquareLocalMediaDraft>.unmodifiable(_media),
    );
  }

  @override
  ComposeSnapshot snapshot() => ComposeSnapshot(
        text: _text.text,
        media: List<SquareLocalMediaDraft>.of(_media),
      );

  Future<void> pickImages() async {
    final remaining = documentMaxImages - _media.length;
    if (remaining <= 0) return;
    // 选择器与落盘逻辑都按剩余数量截断，避免平台实现忽略 limit 时突破 9 张。
    final images = await widget.mediaPicker.pickImages(context, remaining);
    if (images.isEmpty || !mounted) return;
    final next = <SquareLocalMediaDraft>[];
    for (final image in images.take(remaining)) {
      var draft = await widget.mediaDraftBuilder(image, SquareMediaKind.image);
      final persist = widget.persistMedia;
      if (persist != null) draft = await persist(draft);
      next.add(draft);
    }
    if (!mounted) return;
    setState(() {
      _media.addAll(next);
    });
    widget.onMediaCountChanged?.call(_media.length);
    widget.onChanged?.call();
  }

  void _remove(int index) {
    setState(() => _media.removeAt(index));
    widget.onMediaCountChanged?.call(_media.length);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          key: const ValueKey('document-text-field'),
          controller: _text,
          minLines: 5,
          maxLines: 10,
          maxLength: documentTextMax,
          decoration: const InputDecoration(hintText: '写下你的公文…'),
        ),
        if (_media.isNotEmpty) ...[
          SizedBox(height: AppLayout.scaled(context, 10)),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _media.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppLayout.scaled(context, 6),
              mainAxisSpacing: AppLayout.scaled(context, 6),
            ),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(_media[index].path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppTheme.surfaceElevated,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: ComposeMediaRemoveButton(
                      tooltip: '删除图片',
                      onPressed: () => _remove(index),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
