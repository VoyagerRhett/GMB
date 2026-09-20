import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:citizenapp/8964/compose/compose_payload.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft.dart';
import 'package:citizenapp/8964/compose/widgets/compose_media_widgets.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/services/square_media_draft.dart';
import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';

const int videoTextMax = 300;

/// 视频编辑器：固定一个视频，可附带最多300字配文，不接受图片。
class SquareVideoComposeBody extends StatefulWidget {
  const SquareVideoComposeBody({
    super.key,
    this.initialText,
    this.initialMedia = const <SquareLocalMediaDraft>[],
    this.onChanged,
    this.persistMedia,
    this.imagePicker,
    this.mediaDraftBuilder = buildSquareMediaDraft,
    this.onVideoChanged,
  });

  final String? initialText;
  final List<SquareLocalMediaDraft> initialMedia;
  final VoidCallback? onChanged;
  final ComposeMediaPersistor? persistMedia;
  final ImagePicker? imagePicker;
  final SquareMediaDraftBuilder mediaDraftBuilder;
  final ValueChanged<SquareLocalMediaDraft?>? onVideoChanged;

  @override
  State<SquareVideoComposeBody> createState() => SquareVideoComposeBodyState();
}

class SquareVideoComposeBodyState extends State<SquareVideoComposeBody>
    implements ComposeBodyCollector {
  final TextEditingController _text = TextEditingController();
  late final ImagePicker _picker;
  SquareLocalMediaDraft? _video;

  @override
  void initState() {
    super.initState();
    _picker = widget.imagePicker ?? ImagePicker();
    _text.text = widget.initialText ?? '';
    if (widget.initialMedia.length == 1 &&
        widget.initialMedia.single.mediaKind == SquareMediaKind.video) {
      _video = widget.initialMedia.single;
    }
    _text.addListener(() => widget.onChanged?.call());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onVideoChanged?.call(_video);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void restore(SquareComposeDraft draft) {
    if (draft.postType != SquarePostType.video ||
        draft.media.length != 1 ||
        draft.media.single.mediaKind != SquareMediaKind.video) {
      throw const FormatException('视频草稿类型或媒体不合法');
    }
    setState(() {
      _text.text = draft.text;
      _video = draft.media.single;
    });
    widget.onVideoChanged?.call(_video);
  }

  @override
  bool get isContentValid {
    final video = _video;
    return _text.text.trim().runes.length <= videoTextMax &&
        video != null &&
        video.mediaKind == SquareMediaKind.video;
  }

  @override
  ComposePayload collect() {
    final text = _text.text.trim();
    if (text.runes.length > videoTextMax) {
      return const ComposePayload.invalid('视频配文不能超过300字');
    }
    final video = _video;
    if (video == null || video.mediaKind != SquareMediaKind.video) {
      return const ComposePayload.invalid('请选择1个视频');
    }
    return ComposePayload.ok(text: text, mediaDrafts: [video]);
  }

  @override
  ComposeSnapshot snapshot() =>
      ComposeSnapshot(text: _text.text, media: [?_video]);

  Future<void> pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    var draft = await widget.mediaDraftBuilder(file, SquareMediaKind.video);
    final persist = widget.persistMedia;
    if (persist != null) draft = await persist(draft);
    if (!mounted) return;
    setState(() => _video = draft);
    widget.onVideoChanged?.call(_video);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          key: const ValueKey('video-text-field'),
          controller: _text,
          minLines: 4,
          maxLines: 8,
          maxLength: videoTextMax,
          decoration: const InputDecoration(hintText: '添加视频配文…'),
        ),
        SizedBox(height: AppLayout.scaled(context, 12)),
        if (video != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ComposeLocalVideoPreview(
                    key: const ValueKey('video-local-preview'),
                    path: video.path,
                    interactive: true,
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: ComposeMediaRemoveButton(
                      tooltip: '删除视频',
                      onPressed: () {
                        setState(() => _video = null);
                        widget.onVideoChanged?.call(null);
                        widget.onChanged?.call();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
