import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:citizenapp/8964/services/square_media_store.dart';
import 'package:citizenapp/8964/services/square_media_policy.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_media_processor.dart';
import 'package:citizenapp/8964/widgets/square_media_carousel.dart';
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

    // 详情按顺序展示全部原图；列表仍只读缩略图并保留既定两图布局。
    if (enableVideoPlayback && mediaItems.length > 1) {
      return SquareMediaCarousel(
        children: [
          for (final item in mediaItems)
            SquareMediaTile(
              item: item,
              radius: BorderRadius.circular(r),
              enableVideoPlayback: true,
            ),
        ],
      );
    }

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
    return ClipRRect(
      borderRadius: radius,
      child: isVideo && enableVideoPlayback
          ? SquareVideo(url: item.url, thumbnailUrl: item.coverUrl, item: item)
          : _buildCover(context, isVideo),
    );
  }

  Widget _buildCover(BuildContext context, bool isVideo) => DecoratedBox(
    decoration: const BoxDecoration(color: AppTheme.surfaceElevated),
    child: Stack(
      fit: StackFit.expand,
      children: [
        SquareMediaImage(item: item, preview: !enableVideoPlayback),
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
}

/// 广场单版本HEVC播放器，本地来源只通过数据库Range适配读取。
///
/// Feed 只渲染封面；详情页点击后才检查设备解码能力并初始化。本地来源按范围读库，
/// 他人公开来源使用HTTPS；两者均不生成或切换不存在的多清晰度版本。
class SquareVideo extends StatefulWidget {
  const SquareVideo({
    super.key,
    required this.url,
    this.thumbnailUrl,
    this.item,
  });

  final String url;
  final String? thumbnailUrl;
  final SquareMediaItem? item;

  @override
  State<SquareVideo> createState() => _SquareVideoState();
}

class _SquareVideoState extends State<SquareVideo> {
  VideoPlayerController? _controller;
  SquareLocalVideoSource? _localSource;
  int _initializationGeneration = 0;
  bool _initializing = false;
  bool _isBuffering = false;
  String? _failureMessage;

  @override
  void didUpdateWidget(covariant SquareVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.item?.cidNumber != widget.item?.cidNumber ||
        oldWidget.item?.postId != widget.item?.postId ||
        oldWidget.item?.mediaIndex != widget.item?.mediaIndex) {
      _reset();
    }
  }

  Future<void> _reset() async {
    _initializationGeneration++;
    final previous = _controller;
    final source = _localSource;
    _localSource = null;
    previous?.removeListener(_handleControllerValueChanged);
    _controller = null;
    _initializing = false;
    _isBuffering = false;
    _failureMessage = null;
    if (previous != null) await previous.dispose();
    await source?.close();
    if (mounted) setState(() {});
  }

  Future<void> _initializeAndPlay() async {
    if (_initializing) return;
    final generation = ++_initializationGeneration;
    final uri = Uri.tryParse(widget.url);
    if (!mounted ||
        (widget.item?.isLocal != true &&
            (uri == null || uri.scheme != 'https'))) {
      return;
    }
    setState(() {
      _initializing = true;
      _failureMessage = null;
    });
    VideoPlayerController? controller;
    SquareLocalVideoSource? source;
    try {
      final capability = await const MethodChannelSquareVideoBridge()
          .capabilities();
      if (!capability.canDecodeHevc) {
        throw const SquareApiException('当前设备不支持播放 HEVC 视频');
      }
      if (widget.item?.isLocal == true) {
        source = await SquareLocalVideoSource.open(widget.item!);
      }
      if (!mounted || generation != _initializationGeneration) {
        await source?.close();
        return;
      }
      // 初始化尚未完成时退出页面，也必须立即关闭本机监听。
      _localSource = source;
      controller = VideoPlayerController.networkUrl(source?.uri ?? uri!);
      await controller.initialize();
      await controller.seekTo(Duration.zero);
      if (!mounted || generation != _initializationGeneration) {
        await controller.dispose();
        await source?.close();
        return;
      }
      _controller = controller;
      _localSource = source;
      controller.addListener(_handleControllerValueChanged);
      _isBuffering = controller.value.isBuffering;
      await controller.play();
    } on Object catch (error) {
      await controller?.dispose();
      await source?.close();
      if (mounted && generation == _initializationGeneration) {
        _controller = null;
        _localSource = null;
        _isBuffering = false;
        _failureMessage = error is SquareApiException
            ? error.message
            : widget.item?.isLocal == true
            ? '本地视频读取失败'
            : '加载失败，点击重试';
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
    _localSource?.close();
    super.dispose();
  }

  void _handleControllerValueChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    final nextFailure = value.hasError
        ? (widget.item?.isLocal == true ? '本地视频读取失败' : '加载失败，点击重试')
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
          else if (widget.item?.isLocal == true)
            SquareMediaImage(item: widget.item!, preview: true)
          else if (Uri.tryParse(widget.thumbnailUrl ?? '')?.scheme == 'https')
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

/// 按CID、帖子、槽位查找数据库媒体，实际字节不来自URL。
Future<SquareStoredMedia?> _localMedia(
  SquareMediaItem item,
  String role,
) async {
  if (!item.isLocal) throw ArgumentError('缺少本地媒体归属');
  const store = SquareMediaStore();
  final refs = await store.referencesForContent(
    cidNumber: item.cidNumber!,
    contentKind: 'post',
    contentId: item.postId!,
  );
  final selected = refs
      .where((r) => r.mediaIndex == item.mediaIndex && r.mediaRole == role)
      .toList();
  if (selected.isEmpty) return null;
  if (selected.length != 1) throw StateError('媒体槽位重复');
  final media = await store.get(
    cidNumber: item.cidNumber!,
    mediaId: selected.single.mediaId,
  );
  if (media == null || !media.complete) return null;
  if (media.mediaKind !=
      (role == 'main' && item.mediaKind == SquareMediaKind.video
          ? 'video'
          : 'image')) {
    throw StateError('媒体类型不一致');
  }
  return media;
}

/// 图片统一展示适配。本地来源缺失或损坏时不隐式联网。
class SquareMediaImage extends StatefulWidget {
  const SquareMediaImage({
    super.key,
    required this.item,
    this.preview = false,
    this.fit = BoxFit.cover,
  });
  final SquareMediaItem item;
  final bool preview;
  final BoxFit fit;
  @override
  State<SquareMediaImage> createState() => _SquareMediaImageState();
}

class _SquareMediaImageState extends State<SquareMediaImage> {
  Future<Uint8List?>? _bytes;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant SquareMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item || oldWidget.preview != widget.preview) {
      _reload();
    }
  }

  void _reload() {
    _bytes = widget.item.isLocal ? _read(widget.item, widget.preview) : null;
  }

  Future<Uint8List?> _read(SquareMediaItem item, bool preview) async {
    final role = item.mediaKind == SquareMediaKind.video
        ? 'cover'
        : preview
        ? 'thumbnail'
        : 'main';
    final media = await _localMedia(item, role);
    if (media == null) return null;
    final limit = role == 'main'
        ? SquareMediaPolicy.spark.imageMaxBytes
        : 4 * 1024 * 1024; // 与显式同步的衍生图接收上限一致。
    if (media.byteSize > limit) throw StateError('图片大小无效');
    final bytes = BytesBuilder(copy: false);
    for (
      var offset = 0;
      offset < media.byteSize;
      offset += SquareMediaStore.chunkSize
    ) {
      bytes.add(
        await const SquareMediaStore().readRange(
          cidNumber: media.cidNumber,
          mediaId: media.mediaId,
          offset: offset,
          length: math.min(SquareMediaStore.chunkSize, media.byteSize - offset),
        ),
      );
    }
    return bytes.takeBytes();
  }

  Widget _message(String text) => ColoredBox(
    color: AppTheme.surfaceElevated,
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (widget.item.isLocal) {
      return FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _message('本地媒体读取失败');
          if (snapshot.connectionState != ConnectionState.done) {
            return const ColoredBox(color: AppTheme.surfaceElevated);
          }
          final bytes = snapshot.data;
          if (bytes == null) return _message('本地尚未保存媒体');
          return Image.memory(
            bytes,
            fit: widget.fit,
            errorBuilder: (_, _, _) => _message('本地媒体读取失败'),
          );
        },
      );
    }
    final url = widget.item.mediaKind == SquareMediaKind.video
        ? widget.item.coverUrl
        : widget.item.url;
    if (url == null || Uri.tryParse(url)?.scheme != 'https') {
      return _message('媒体不可用');
    }
    return Image.network(
      url,
      fit: widget.fit,
      errorBuilder: (_, _, _) => _message('媒体加载失败'),
    );
  }
}

/// 原生播放器到数据库的本机Range适配。仅监听回环、随机端口和随机单媒体路径。
/// 不暴露CID/哈希、不创建永久文件、不转发远端请求；随播放器关闭并按块处理背压。
class SquareLocalVideoSource {
  SquareLocalVideoSource._(this._server, this._media, this._path);
  final HttpServer _server;
  final SquareStoredMedia _media;
  final String _path;
  bool _closed = false;
  Uri get uri =>
      Uri(scheme: 'http', host: '127.0.0.1', port: _server.port, path: _path);

  static Future<SquareLocalVideoSource> open(SquareMediaItem item) async {
    if (item.mediaKind != SquareMediaKind.video) throw ArgumentError('不是视频');
    final media = await _localMedia(item, 'main');
    if (media == null) throw StateError('本地尚未保存视频');
    final random = math.Random.secure();
    final path =
        '/${base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '')}';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.idleTimeout = const Duration(seconds: 30);
    final source = SquareLocalVideoSource._(server, media, path);
    server.listen(source._serve, onError: (_) => source.close());
    return source;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (_closed ||
          request.uri.path != _path ||
          request.uri.hasQuery ||
          request.headers.value(HttpHeaders.hostHeader) !=
              '127.0.0.1:${_server.port}' ||
          request.headers.value('origin') != null ||
          request.connectionInfo?.remoteAddress.isLoopback != true) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        await response.close();
        return;
      }
      var start = 0, end = _media.byteSize - 1;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
          throw const FormatException('range');
        }
        if (match[1]!.isEmpty) {
          final suffix = int.parse(match[2]!);
          if (suffix <= 0) throw const FormatException('range');
          start = math.max(0, _media.byteSize - suffix);
        } else {
          start = int.parse(match[1]!);
          if (match[2]!.isNotEmpty) end = math.min(end, int.parse(match[2]!));
        }
        if (start >= _media.byteSize || end < start) {
          throw const FormatException('range');
        }
      }
      // 首块先验证再发送成功响应；后续损坏断开连接，不返回伪完整视频。
      final firstLength = math.min(SquareMediaStore.chunkSize, end - start + 1);
      final first = request.method == 'GET'
          ? await const SquareMediaStore().readRange(
              cidNumber: _media.cidNumber,
              mediaId: _media.mediaId,
              offset: start,
              length: firstLength,
            )
          : null;
      response.statusCode = range == null
          ? HttpStatus.ok
          : HttpStatus.partialContent;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.contentType = ContentType.parse(_media.contentType);
      response.contentLength = end - start + 1;
      if (range != null) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${_media.byteSize}',
        );
      }
      if (first != null) {
        response.add(first);
        await response.flush();
        for (
          var offset = start + first.length;
          offset <= end;
          offset += SquareMediaStore.chunkSize
        ) {
          if (_closed) throw StateError('播放已关闭');
          response.add(
            await const SquareMediaStore().readRange(
              cidNumber: _media.cidNumber,
              mediaId: _media.mediaId,
              offset: offset,
              length: math.min(SquareMediaStore.chunkSize, end - offset + 1),
            ),
          );
          await response.flush();
        }
      }
      await response.close();
    } on FormatException {
      try {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */${_media.byteSize}',
        );
        await response.close();
      } catch (_) {
        /* 播放器取消请求时连接可能已经关闭。 */
      }
    } catch (_) {
      // 不输出播放地址或媒体数据。
      try {
        (await response.detachSocket(writeHeaders: false)).destroy();
      } catch (_) {
        /* 已关闭 */
      }
    }
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
