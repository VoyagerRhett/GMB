import 'dart:ui' as ui;
import 'dart:async';
import 'dart:typed_data';
import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:provider/provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:saver_gallery/saver_gallery.dart';

import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 展示型二维码的共用外壳：标题、顶部大字、完整二维码、SS58 地址和底部说明。
///
/// 三种展示型码(用户码 / 账户码 / 收款码)共用同一套外观,只有载荷与文案不同。
/// 本组件不构造任何载荷,由调用方传入已序列化好的 [qrData],避免在展示层混入
/// 「该出哪种码」的运行时判断。
class QrDisplayScaffold extends StatefulWidget {
  const QrDisplayScaffold({
    super.key,
    required this.headline,
    required this.qrData,
    required this.ss58Address,
    required this.footerText,
    this.title = '二维码',
  });

  /// AppBar 标题。
  final String title;

  /// 顶部大字。用户码为公开昵称,账户码为本机账户标签(只在本机显示,不进载荷)。
  final String headline;

  /// 已序列化的 QR_V1 载荷。
  final String qrData;

  /// 展示态 SS58 地址(可复制);accountId 才是授权真源。
  final String ss58Address;

  /// 底部说明,必须如实覆盖该码的全部合法扫码场景。
  final String footerText;

  @override
  State<QrDisplayScaffold> createState() => _QrDisplayScaffoldState();
}

class _QrDisplayScaffoldState extends State<QrDisplayScaffold> {
  final GlobalKey _qrKey = GlobalKey();
  bool _saving = false;

  void _copyAddress() {
    Clipboard.setData(ClipboardData(text: widget.ss58Address));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('SS58 地址已复制')));
  }

  Future<void> _saveQr() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || !mounted) return;
      final result = await SaverGallery.saveImage(
        byteData.buffer.asUint8List(),
        fileName: 'my_qr_${DateTime.now().millisecondsSinceEpoch}.png',
        albumPath: 'CitizenApp',
        skipIfExists: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.isSuccess ? '已保存到相册' : '保存失败')),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '保存二维码',
            onPressed: _saving ? null : _saveQr,
            icon: _saving
                ? SizedBox(
                    width: AppLayout.scaled(context, 18),
                    height: AppLayout.scaled(context, 18),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          const Spacer(),
          Text(
            widget.headline,
            style: TextStyle(
              fontSize: AppLayout.scaled(context, 20),
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 24)),
          RepaintBoundary(
            key: _qrKey,
            child: Container(
              color: Colors.white,
              padding: EdgeInsets.all(AppLayout.scaled(context, 12)),
              child: AppQrImage(
                data: widget.qrData,
                size: AppLayout.scaled(context, 240),
              ),
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 16)),
          // 地址居中显示，复制图标浮右不抢中心。
          Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppLayout.scaled(context, 48),
                ),
                child: GestureDetector(
                  onTap: _copyAddress,
                  child: Text(
                    widget.ss58Address,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppLayout.scaled(context, 13),
                      color: AppTheme.textTertiary,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: AppLayout.scaled(context, 16),
                child: IconButton(
                  icon: Icon(Icons.copy, size: AppLayout.scaled(context, 16)),
                  color: AppTheme.textTertiary,
                  tooltip: '复制地址',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: AppLayout.scaled(context, 24),
                    minHeight: AppLayout.scaled(context, 24),
                  ),
                  onPressed: _copyAddress,
                ),
              ),
            ],
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.only(bottom: AppLayout.scaled(context, 32)),
            child: Text(
              widget.footerText,
              style: TextStyle(
                color: AppTheme.textTertiary,
                fontSize: AppLayout.scaled(context, 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// 只显示SDK生成的像素；沿用原方形码、尺寸、颜色和10px内边距，不在App编码QR。
class AppQrImage extends StatefulWidget {
  const AppQrImage({super.key, required this.data, required this.size,
    this.color = Colors.black, this.errorStateBuilder, this.qr});
  final String data;
  final double size;
  final Color color;
  final Widget Function(BuildContext, Object?)? errorStateBuilder;
  final CitizenQr? qr;
  @override State<AppQrImage> createState() => _AppQrImageState();
}

class _AppQrImageState extends State<AppQrImage> {
  ui.Image? _image;
  Object? _error;
  CitizenQr? _qr;
  int _generation = 0;

  @override void didChangeDependencies() {
    super.didChangeDependencies();
    final qr = widget.qr ?? context.read<CitizenSdk>().qr;
    if (!identical(qr, _qr)) { _qr = qr; unawaited(_load(qr)); }
  }

  @override void didUpdateWidget(covariant AppQrImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data || !identical(oldWidget.qr, widget.qr)) {
      _qr = widget.qr ?? context.read<CitizenSdk>().qr;
      unawaited(_load(_qr!));
    }
  }

  Future<void> _load(CitizenQr qr) async {
    final generation = ++_generation;
    _image?.dispose();
    _image = null;
    _error = null;
    try {
      final pixels = await qr.encode(widget.data, scale: 1);
      if (!mounted || generation != _generation) return;
      if (pixels.width <= 8 || pixels.height <= 8 ||
          pixels.width != pixels.height || pixels.luminance.length != pixels.width * pixels.height) {
        throw const CitizenSdkException(code: CitizenSdkErrorCode.integrity, message: '二维码图像尺寸无效');
      }
      // 灰度只转换成显示透明度；模块选择、纠错、掩码与协议均已由SDK完成。
      final rgba = Uint8List(pixels.width * pixels.height * 4);
      for (var i = 0; i < pixels.luminance.length; i++) {
        rgba[i * 4 + 3] = 255 - pixels.luminance[i];
      }
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, pixels.width, pixels.height, ui.PixelFormat.rgba8888, decoded.complete);
      final image = await decoded.future;
      if (!mounted || generation != _generation) { image.dispose(); return; }
      setState(() => _image = image);
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    }
  }

  @override void dispose() {
    ++_generation;
    _image?.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext context) {
    if (_error != null && widget.errorStateBuilder != null) {
      return widget.errorStateBuilder!(context, _error);
    }
    return SizedBox(
      width: widget.size, height: widget.size,
      child: Padding(padding: const EdgeInsets.all(10),
        child: _image == null ? const SizedBox.expand()
            : CustomPaint(painter: _SdkQrPixels(_image!, widget.color)),
      ),
    );
  }
}

class _SdkQrPixels extends CustomPainter {
  const _SdkQrPixels(this.image, this.color);
  final ui.Image image;
  final Color color;
  @override void paint(Canvas canvas, Size size) {
    // SDK scale=1图像包含标准4模块静区；原控件的10px内边距保留在外层。
    canvas.drawImageRect(
      image, Rect.fromLTWH(4, 4, image.width - 8.0, image.height - 8.0),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none
        ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
  @override bool shouldRepaint(covariant _SdkQrPixels oldDelegate) =>
      oldDelegate.image != image || oldDelegate.color != color;
}
