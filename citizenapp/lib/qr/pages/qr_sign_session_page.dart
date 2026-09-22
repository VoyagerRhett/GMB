import 'package:citizenapp/qr/widgets/qr_display_scaffold.dart' show AppQrImage;
import 'dart:async';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:citizenapp/qr/scanner/scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/ui/app_layout.dart';

import 'package:provider/provider.dart';

/// 使用原冷签页面；非消费预检通过后关闭，交易提交继续留在原调用方。
Future<String?> showCitizenSdkQrResponse(
  BuildContext context, {
  required String request,
  required BigInt expiresAt,
}) async {
  final qr = context.read<CitizenSdk>().qr;
  final document = await qr.parse(request);
  if (!context.mounted) return null;
  if (document.kind != CitizenQrKind.signRequest ||
      document.expiresAt == null || BigInt.from(document.expiresAt!) != expiresAt) {
    throw const AccountSecurityException('签名请求与当前会话不一致');
  }
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => QrSignSessionPage(
        request: document,
        requestJson: document.canonicalText,
        expectedSignerPublicKey: document.signerAccountId!,
        qr: qr,
      ),
    ),
  );
}

/// 钱包账户签名的唯一 Hot/Cold 分流器。
///
/// 热账户由 CitizenSDK 在本机安全签名；冷账户只生成 QR_V1 请求并等待独立公民钱包回扫。
/// 模式缺失、账户不完整或冷签取消都直接拒绝，不得降级到另一路径。
Future<Uint8List> signCitizenPayload({
  required CitizenSigning signing,
  required BuildContext? context,
  required String accountId,
  required Uint8List payload,
  required int action,
  CitizenSigningTransform? transform,
}) async {
  final signingTransform = transform ??
      (CitizenQrActions.isChainAction(action)
          ? CitizenSigningTransform.substrateSigningPayload()
          : CitizenSigningTransform.raw());
  final outcome = await signing.begin(
    CitizenSigningIntent(
      accountId: accountId,
      payload: payload,
      transform: signingTransform,
      externalSignerTransport: CitizenExternalSignerTransport.qrV1,
      opaqueAction: action,
      ttlSeconds: 120,
    ),
  ).result;
  if (outcome is CitizenSigningCompleted) {
    return Uint8List.fromList(outcome.signature);
  }
  final pending = outcome as CitizenExternalSigningPending;
  if (context == null || !context.mounted) {
    await signing.cancel(pending.sessionId);
    throw const AccountSecurityException('冷签缺少扫码页面上下文，已拒绝签名');
  }
  try {
    final response = await showCitizenSdkQrResponse(
      context,
      request: pending.transportRequest,
      expiresAt: pending.expiresAt,
    );
    if (response == null) throw const AccountSecurityException('签名已取消');
    final completed = await signing.consumeExternalSignature(
      sessionId: pending.sessionId,
      response: response,
    ).result;
    return Uint8List.fromList(completed.signature);
  } finally {
    // 页面取消、过期或消费失败均结束原外部会话；成功后取消是幂等空操作。
    await signing.cancel(pending.sessionId);
  }
}

/// 冷钱包扫码签名会话页面。
///
/// 两阶段交互：
/// 1. 展示签名请求二维码，等待离线设备扫描。
/// 2. 用户点击"扫描响应"，打开相机扫描离线设备生成的签名响应二维码。
///
/// 普通签名返回已预检的响应原文；用途钥返回[CitizenQrDocument]；取消返回null。
class QrSignSessionPage extends StatefulWidget {
  const QrSignSessionPage({
    super.key,
    required this.request,
    required this.requestJson,
    required this.expectedSignerPublicKey,
    this.responseKind = CitizenQrKind.signResponse,
    this.qr,
    this.scanResponse,
  });

  /// 仅用于测试注入同一SDK端口和原扫码路由；生产仍使用根实例与原扫码页面。
  final CitizenQr? qr;
  final Future<String?> Function(BuildContext, CitizenQrKind)? scanResponse;

  /// SDK已解析的签名请求。
  final CitizenQrDocument request;

  /// 编码后的 JSON 字符串,直接用于二维码展示。
  final String requestJson;
  final String expectedSignerPublicKey;

  /// 普通冷签收 `k=2`；账户数据用途钥提供收独立 `k=6`。
  final CitizenQrKind responseKind;

  @override
  State<QrSignSessionPage> createState() => _QrSignSessionPageState();
}

class _QrSignSessionPageState extends State<QrSignSessionPage> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _secondsLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds = _secondsLeft();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _secondsLeft() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = (widget.request.expiresAt ?? 0) - now;
    return left > 0 ? left : 0;
  }

  Future<void> _scanResponse() async {
    final raw = widget.scanResponse != null
        ? await widget.scanResponse!(context, widget.responseKind)
        : await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => _SimpleScanner(acceptedKind: widget.responseKind),
            ),
          );
    if (raw == null || !mounted) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if ((widget.request.expiresAt ?? 0) <= now) {
        throw const FormatException('当前请求已过期，请重新生成二维码');
      }
      final qr = widget.qr ?? context.read<CitizenSdk>().qr;
      final Object response;
      if (widget.responseKind == CitizenQrKind.accountDataKeyResponse) {
        final document = (await qr.parseForPurpose(raw, CitizenQrScanPurpose.accountDataKey)).document;
        if (document.requestId != widget.request.requestId ||
            document.expiresAt != widget.request.expiresAt ||
            document.signerAccountId != widget.expectedSignerPublicKey) {
          throw const FormatException('用途钥响应与当前请求不一致');
        }
        response = document;
      } else {
        await qr.validateSignResponse(sessionId: widget.request.requestId!, response: raw);
        response = raw;
      }
      if (!mounted) return;
      Navigator.of(context).pop(response);
    } on CitizenSdkException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('签名响应解析失败'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('用途钥响应解析失败'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remainingSeconds <= 0;
    return Scaffold(
      appBar: AppBar(title: const Text('公民钱包签名'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        children: [
          // 倒计时状态栏
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: AppLayout.scaled(context, 12),
              vertical: AppLayout.scaled(context, 8),
            ),
            decoration: AppTheme.bannerDecoration(
              expired ? AppTheme.danger : AppTheme.success,
            ),
            child: Row(
              children: [
                Icon(
                  expired ? Icons.timer_off : Icons.timer_outlined,
                  size: AppLayout.scaled(context, 18),
                  color: expired ? AppTheme.danger : AppTheme.success,
                ),
                SizedBox(width: AppLayout.scaled(context, 8)),
                Expanded(
                  child: Text(
                    expired
                        ? '签名请求已过期，请返回重新提交'
                        : '签名请求有效期剩余：${_remainingSeconds}s',
                    style: TextStyle(
                      color: expired ? AppTheme.danger : AppTheme.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 16)),

          // 请求二维码
          Center(
            child: AppQrImage(
              data: widget.requestJson,
              qr: widget.qr,
              size: AppLayout.scaled(context, 240),
              errorStateBuilder: (cxt, err) {
                return Container(
                  width: AppLayout.scaled(context, 240),
                  height: AppLayout.scaled(context, 240),
                  padding: EdgeInsets.all(AppLayout.scaled(context, 10)),
                  decoration: AppTheme.bannerDecoration(AppTheme.danger),
                  child: const Center(
                    child: Text(
                      '二维码渲染失败',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 16)),

          // 提示文字
          const Text(
            '请用离线设备扫描此二维码完成签名，\n然后点击下方按钮扫描签名响应二维码。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          SizedBox(height: AppLayout.scaled(context, 24)),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              SizedBox(width: AppLayout.scaled(context, 12)),
              Expanded(
                child: FilledButton(
                  onPressed: expired ? null : _scanResponse,
                  child: const Text('扫描响应'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 签名响应扫码入口：设备层统一复用共享适配器，本页只接受 QR_V1 签名响应码。
class _SimpleScanner extends StatefulWidget {
  const _SimpleScanner({required this.acceptedKind});

  final CitizenQrKind acceptedKind;

  @override
  State<_SimpleScanner> createState() => _SimpleScannerState();
}

class _SimpleScannerState extends State<_SimpleScanner> {
  static const double scanBoxSize = 260;
  static const double scanBoxOffsetY = -40;

  CitizenQrCapture? _capture;
  CitizenQr get _qr => context.read<CitizenSdk>().qr;
  CitizenQrScanPurpose get _purpose => widget.acceptedKind == CitizenQrKind.accountDataKeyResponse
      ? CitizenQrScanPurpose.accountDataKey : CitizenQrScanPurpose.externalSignature;
  bool _handled = false;
  bool _torchOn = false;
  bool _closing = false;

  Future<void> _toggleTorch() async {
    try {
      await _capture?.setTorch(!_torchOn);
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
    } on ScannerFailure catch (failure) {
      _showScannerFailure(failure);
    } on CitizenSdkException catch (error) {
      _showScannerFailure(ScannerFailure.fromDeviceError(error, operation: '扫码'));
    }
  }

  Future<void> _scanFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    try {
      final results = await _qr.decodeImage(await image.readAsBytes(), _purpose);
      if (results.isEmpty) {
        throw const ScannerFailure(kind: ScannerFailureKind.noQrCode, message: '图片中未识别到二维码');
      }
      await _handleCode(results.first.canonicalText);
    } on ScannerFailure catch (failure) {
      _showScannerFailure(failure);
    } on CitizenSdkException catch (error) {
      _showScannerFailure(ScannerFailure.fromDeviceError(error, operation: '扫码'));
    }
  }

  Future<void> _handleCode(String raw) async {
    if (_handled) return;
    _handled = true;
    try {
      await _capture?.pause();
      try {
        await context.read<CitizenSdk>().qr.parseForPurpose(
          raw,
          widget.acceptedKind == CitizenQrKind.accountDataKeyResponse
              ? CitizenQrScanPurpose.accountDataKey : CitizenQrScanPurpose.externalSignature,
        );
      } on CitizenSdkException {
        throw FormatException(
          widget.acceptedKind == CitizenQrKind.accountDataKeyResponse
              ? '请扫描账户数据用途钥响应二维码'
              : '请扫描签名响应二维码',
        );
      }
      if (!mounted) return;
      _closing = true;
      Navigator.of(context).pop(raw);
    } on FormatException catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('二维码类型不符'),
          content: Text(error.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('继续扫描'),
            ),
          ],
        ),
      );
    } on ScannerFailure catch (failure) {
      _showScannerFailure(failure);
    } on CitizenSdkException catch (error) {
      _showScannerFailure(ScannerFailure.fromDeviceError(error, operation: '扫码'));
    } finally {
      if (mounted && !_closing) {
        _handled = false;
        try {
          await _capture?.resume();
        } on CitizenSdkException catch (error) {
          _showScannerFailure(ScannerFailure.fromDeviceError(error, operation: '继续扫码'));
        }
      }
    }
  }

  void _showScannerFailure(ScannerFailure failure) {
    if (!mounted || _closing) return;
    final message = failure.kind == ScannerFailureKind.noQrCode
        ? '未识别到二维码'
        : failure.message;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描签名响应'), centerTitle: true),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ScannerView(
            qr: _qr,
            purpose: _purpose,
            onCapture: (capture) {
              _capture = capture;
              if (_handled || _closing) unawaited(capture?.pause());
            },
            onRawValue: (raw) => unawaited(_handleCode(raw)),
            onFailure: _showScannerFailure,
          ),
          CustomPaint(
            painter: _ScanOverlayPainter(
              scanBoxSize: scanBoxSize,
              offsetY: scanBoxOffsetY,
            ),
            child: const SizedBox.expand(),
          ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, scanBoxOffsetY),
              child: SizedBox(
                width: scanBoxSize,
                height: scanBoxSize,
                child: CustomPaint(painter: _ScanCornerPainter()),
              ),
            ),
          ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, scanBoxOffsetY + scanBoxSize / 2 + 24),
              child: Text(
                '扫描离线设备上的签名响应二维码',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: AppLayout.scaled(context, 14),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: AppLayout.scaled(context, 60),
                left: AppLayout.scaled(context, 48),
                right: AppLayout.scaled(context, 48),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _scanFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        iconSize: AppLayout.scaled(context, 32),
                        color: Colors.white,
                      ),
                      Text(
                        '相册',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppLayout.scaled(context, 12),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _toggleTorch,
                        icon: Icon(
                          _torchOn
                              ? Icons.flashlight_on
                              : Icons.flashlight_off_outlined,
                        ),
                        iconSize: AppLayout.scaled(context, 32),
                        color: _torchOn ? Colors.amber : Colors.white,
                      ),
                      Text(
                        _torchOn ? '关闭' : '手电筒',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppLayout.scaled(context, 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.scanBoxSize, this.offsetY = 0});

  final double scanBoxSize;
  final double offsetY;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.black.withAlpha(140);
    final clearPaint = Paint()..blendMode = BlendMode.clear;

    final center = Offset(size.width / 2, size.height / 2 + offsetY);
    final rect = Rect.fromCenter(
      center: center,
      width: scanBoxSize,
      height: scanBoxSize,
    );

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, bgPaint);
    canvas.drawRect(rect, clearPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) =>
      oldDelegate.scanBoxSize != scanBoxSize || oldDelegate.offsetY != offsetY;
}

class _ScanCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cornerLen = 24.0;
    const strokeWidth = 4.0;

    final paint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    canvas.drawLine(const Offset(0, 0), const Offset(cornerLen, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLen), paint);
    canvas.drawLine(Offset(w, 0), Offset(w - cornerLen, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, cornerLen), paint);
    canvas.drawLine(Offset(0, h), Offset(cornerLen, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - cornerLen), paint);
    canvas.drawLine(Offset(w, h), Offset(w - cornerLen, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - cornerLen), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
