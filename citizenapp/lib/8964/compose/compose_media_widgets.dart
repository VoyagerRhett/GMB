import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:citizenapp/ui/app_theme.dart';

/// 公文、文章、视频共用的无外框媒体入口；禁用时保留位置并显示灰色。
class ComposeMediaAddButton extends StatelessWidget {
  const ComposeMediaAddButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 34,
    this.iconSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  /// 图形自身留白不同时可独立校准视觉尺寸，按钮点击区域仍由 [size] 统一控制。
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      iconSize: iconSize ?? size * 0.66,
      color: AppTheme.primary,
      disabledColor: AppTheme.textTertiary,
      icon: Icon(icon),
    );
  }
}

/// 所有发布媒体统一使用的圆形叉号，禁止各编辑器另造删除按钮。
class ComposeMediaRemoveButton extends StatelessWidget {
  const ComposeMediaRemoveButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.size = 28,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.black.withAlpha(0x99),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              Icons.close_rounded,
              size: size * 0.64,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 本地视频真实画面组件。使用仓库现有 video_player，不生成第二份封面文件。
/// [interactive] 为 true 时点击切换播放；缩略图模式固定停在首帧。
class ComposeLocalVideoPreview extends StatefulWidget {
  const ComposeLocalVideoPreview({
    super.key,
    required this.path,
    this.interactive = false,
    this.fit = BoxFit.cover,
  });

  final String path;
  final bool interactive;
  final BoxFit fit;

  @override
  State<ComposeLocalVideoPreview> createState() =>
      _ComposeLocalVideoPreviewState();
}

class _ComposeLocalVideoPreviewState extends State<ComposeLocalVideoPreview> {
  VideoPlayerController? _controller;
  Object? _error;
  int _initializationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant ComposeLocalVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _initialize();
  }

  Future<void> _initialize() async {
    final generation = ++_initializationGeneration;
    final previous = _controller;
    _controller = null;
    if (previous != null) await previous.dispose();
    if (!mounted || generation != _initializationGeneration) return;
    setState(() => _error = null);
    final file = File(widget.path);
    if (!file.existsSync()) {
      setState(() => _error = const FormatException('视频文件不存在'));
      return;
    }
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.seekTo(Duration.zero);
      if (!mounted || generation != _initializationGeneration) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on Object catch (error) {
      await controller.dispose();
      if (mounted && generation == _initializationGeneration) {
        setState(() => _error = error);
      }
    }
  }

  @override
  void dispose() {
    _initializationGeneration++;
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (!widget.interactive || controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null ||
        controller == null ||
        !controller.value.isInitialized) {
      return const ColoredBox(
        color: AppTheme.surfaceElevated,
        child: Center(
          child: Icon(
            Icons.videocam_off_outlined,
            color: AppTheme.textTertiary,
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.interactive ? _togglePlayback : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
          if (widget.interactive)
            Center(
              child: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                size: 46,
                color: Colors.white.withAlpha(0xDD),
              ),
            ),
        ],
      ),
    );
  }
}

/// 视频选中后占用原视频图标位置，显示同一文件首帧；点击可重新选择。
class ComposeVideoThumbnailButton extends StatelessWidget {
  const ComposeVideoThumbnailButton({
    super.key,
    required this.path,
    required this.onPressed,
    this.size = 34,
  });

  final String path;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '重新选择视频',
      child: Material(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: ComposeLocalVideoPreview(path: path),
          ),
        ),
      ),
    );
  }
}
