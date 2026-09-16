import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
              child: QrImageView(
                data: widget.qrData,
                version: QrVersions.auto,
                size: AppLayout.scaled(context, 240),
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
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
