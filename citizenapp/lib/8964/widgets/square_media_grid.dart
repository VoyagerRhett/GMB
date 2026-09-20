import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_media_processor.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 广场卡片媒体区（单块 / 2 个及以上取前两个）。
///
/// 公文照片只有一套动态流规则：单张固定 16:9；两张及以上只显示前两张，
/// 每张都是 16:9 横向长方形，左右等宽、外侧圆角、中缝直角、2px 细缝；
/// 超过两张时在第二张右下角显示 `+N`（N = 总数 - 2）。视频只允许单个，
/// 继续按自身横竖方向使用 16:9 或 3:4 封面，不受公文照片收口影响。
class SquareMediaGrid extends StatelessWidget {
  const SquareMediaGrid({
    super.key,
    required this.mediaItems,
    this.enableVideoPlayback = false,
  });

  final List<SquareMediaItem> mediaItems;
  final bool enableVideoPlayback;

  @override
  Widget build(BuildContext context) {
    if (mediaItems.isEmpty) return const SizedBox.shrink();

    const r = AppTheme.radiusMd;

    if (mediaItems.length == 1) {
      final item = mediaItems.first;
      final isPortraitVideo =
          item.mediaKind == SquareMediaKind.video && item.isPortrait;
      return AspectRatio(
        aspectRatio: isPortraitVideo ? 3 / 4 : 16 / 9,
        child: SquareMediaTile(
          item: item,
          radius: BorderRadius.circular(r),
          enableVideoPlayback: enableVideoPlayback,
        ),
      );
    }

    // 两个 16:9 横向长方形左右相接，整组比例为 32:9；2px 中缝由 Row 单独占用，
    // 不参与任一照片的圆角，保证四个外角为圆角、相接处始终为直角。
    final hidden = mediaItems.length - 2;
    return AspectRatio(
      aspectRatio: 32 / 9,
      child: Row(
        children: [
          Expanded(
            child: SquareMediaTile(
              item: mediaItems[0],
              radius: const BorderRadius.only(
                topLeft: Radius.circular(r),
                bottomLeft: Radius.circular(r),
              ),
            ),
          ),
          // 视觉规范要求中缝固定为 2 逻辑像素，不跟随设备宽度缩放。
          const SizedBox(width: 2),
          Expanded(
            child: SquareMediaTile(
              item: mediaItems[1],
              radius: const BorderRadius.only(
                topRight: Radius.circular(r),
                bottomRight: Radius.circular(r),
              ),
              overlayCount: hidden > 0 ? hidden : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个媒体块：图片/视频封面 + 视频播放键 + 右下角 `+N` 角标。
/// 所有动态流媒体统一由 [SquareMediaGrid] 组合，本组件只负责单块裁切和角标。
class SquareMediaTile extends StatelessWidget {
  const SquareMediaTile({
    super.key,
    required this.item,
    required this.radius,
    this.enableVideoPlayback = false,
    this.overlayCount,
  });

  final SquareMediaItem item;
  final BorderRadius radius;
  final bool enableVideoPlayback;

  /// 非空时在右下角显示 `+N`，表示还有 N 张未展开。
  final int? overlayCount;

  @override
  Widget build(BuildContext context) {
    final isVideo = item.mediaKind == SquareMediaKind.video;
    final imageUrl = isVideo ? (item.coverUrl ?? '') : item.url;
    return ClipRRect(
      borderRadius: radius,
      child: isVideo && enableVideoPlayback
          ? SquareNetworkVideo(url: item.url, thumbnailUrl: item.coverUrl)
          : _buildCover(context, isVideo, imageUrl),
    );
  }

  Widget _buildCover(
    BuildContext context,
    bool isVideo,
    String imageUrl,
  ) =>
      DecoratedBox(
        decoration: const BoxDecoration(color: AppTheme.surfaceElevated),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallbackIcon(isVideo),
              )
            else
              _fallbackIcon(isVideo),
            if (isVideo)
              Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  size: AppLayout.scaled(context, 42),
                  color: Colors.white70,
                ),
              ),
            if (overlayCount != null)
              Positioned(
                right: AppLayout.scaled(context, 8),
                bottom: AppLayout.scaled(context, 8),
                child: _CountBadge(count: overlayCount!),
              ),
          ],
        ),
      );

  Widget _fallbackIcon(bool isVideo) {
    return Icon(
      isVideo ? Icons.play_circle_fill_rounded : Icons.image_rounded,
      size: AppLayout.scaledValue(42),
      color: AppTheme.textTertiary,
    );
  }
}

/// R2 自定义域名交付的单版本 HEVC MP4 播放器。
///
/// Feed 只渲染封面；详情页点击后才检查设备解码能力并初始化。原生播放器利用 HTTP Range
/// 缓冲同一文件，弱网时显示等待/重试，不生成或假装切换不存在的多清晰度版本。
class SquareNetworkVideo extends StatefulWidget {
  const SquareNetworkVideo({super.key, required this.url, this.thumbnailUrl});

  final String url;
  final String? thumbnailUrl;

  @override
  State<SquareNetworkVideo> createState() => _SquareNetworkVideoState();
}

class _SquareNetworkVideoState extends State<SquareNetworkVideo> {
  VideoPlayerController? _controller;
  int _initializationGeneration = 0;
  bool _initializing = false;
  bool _isBuffering = false;
  String? _failureMessage;

  @override
  void didUpdateWidget(covariant SquareNetworkVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _reset();
  }

  Future<void> _reset() async {
    _initializationGeneration++;
    final previous = _controller;
    previous?.removeListener(_handleControllerValueChanged);
    _controller = null;
    _initializing = false;
    _isBuffering = false;
    _failureMessage = null;
    if (previous != null) await previous.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _initializeAndPlay() async {
    if (_initializing) return;
    final generation = ++_initializationGeneration;
    final uri = Uri.tryParse(widget.url);
    if (!mounted || uri == null || uri.scheme != 'https') {
      return;
    }
    setState(() {
      _initializing = true;
      _failureMessage = null;
    });
    VideoPlayerController? controller;
    try {
      final capability =
          await const MethodChannelSquareVideoBridge().capabilities();
      if (!capability.canDecodeHevc) {
        throw const SquareApiException('当前设备不支持播放 HEVC 视频');
      }
      controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      await controller.seekTo(Duration.zero);
      if (!mounted || generation != _initializationGeneration) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      controller.addListener(_handleControllerValueChanged);
      _isBuffering = controller.value.isBuffering;
      await controller.play();
    } on Object catch (error) {
      await controller?.dispose();
      if (mounted && generation == _initializationGeneration) {
        _controller = null;
        _isBuffering = false;
        _failureMessage =
            error is SquareApiException ? error.message : '加载失败，点击重试';
      }
    } finally {
      if (mounted && generation == _initializationGeneration) {
        setState(() => _initializing = false);
      }
    }
  }

  @override
  void dispose() {
    _initializationGeneration++;
    _controller?.removeListener(_handleControllerValueChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _handleControllerValueChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    final nextFailure = value.hasError
        ? (value.errorDescription ?? '加载失败，点击重试')
        : _failureMessage;
    if (_isBuffering == value.isBuffering && nextFailure == _failureMessage) {
      return;
    }
    setState(() {
      _isBuffering = value.isBuffering;
      _failureMessage = nextFailure;
    });
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  Future<void> _handleTap() async {
    if (_initializing) return;
    if (_failureMessage != null) {
      await _reset();
      await _initializeAndPlay();
      return;
    }
    if (_controller == null) {
      await _initializeAndPlay();
    } else {
      _togglePlayback();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized == true;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _initializing ? null : _handleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (initialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller!.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          else if (widget.thumbnailUrl?.isNotEmpty == true)
            Image.network(
              widget.thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: AppTheme.surfaceElevated),
            )
          else
            const ColoredBox(color: AppTheme.surfaceElevated),
          if (initialized)
            Align(
              alignment: Alignment.bottomCenter,
              child: VideoProgressIndicator(
                controller!,
                allowScrubbing: true,
                padding: EdgeInsets.zero,
              ),
            ),
          Center(
            child: _initializing || _isBuffering
                ? const CircularProgressIndicator(color: Colors.white)
                : _failureMessage != null
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            _failureMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    : Icon(
                        controller?.value.isPlaying == true
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppLayout.scaled(context, 8),
        vertical: AppLayout.scaled(context, 2),
      ),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(0x80),
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(20)),
      ),
      child: Text(
        '+$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: AppLayout.scaled(context, 12),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
