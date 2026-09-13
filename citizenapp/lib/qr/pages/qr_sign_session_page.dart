import 'dart:async';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:citizenapp/qr/scanner/scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:citizenapp/qr/envelope.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/qr/bodies/account_data_key_response_body.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/signer/app_business_qr_codec.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 展示 CitizenSDK 已生成的唯一 QR_V1 请求，并只把扫描原文交回 SDK 验证。
Future<String?> showCitizenSdkQrResponse(
  BuildContext context, {
  required String request,
  required BigInt expiresAt,
}) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _CitizenSdkQrSessionPage(
          request: request,
          expiresAt: expiresAt,
        ),
      ),
    );

class _CitizenSdkQrSessionPage extends StatefulWidget {
  const _CitizenSdkQrSessionPage({
    required this.request,
    required this.expiresAt,
  });

  final String request;
  final BigInt expiresAt;

  @override
  State<_CitizenSdkQrSessionPage> createState() =>
      _CitizenSdkQrSessionPageState();
}

class _CitizenSdkQrSessionPageState extends State<_CitizenSdkQrSessionPage> {
  Timer? _timer;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = _secondsLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _remaining = _secondsLeft());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _secondsLeft() {
    final now = BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final remaining = widget.expiresAt - now;
    return remaining.isNegative ? 0 : remaining.toInt();
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _SimpleScanner()),
    );
    if (mounted && raw != null) Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining <= 0;
    return Scaffold(
      appBar: AppBar(title: const Text('公民钱包签名'), centerTitle: true),
      body: ListView(
        padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
        children: [
          Container(
            padding: EdgeInsets.all(AppLayout.scaled(context, 12)),
            decoration: AppTheme.bannerDecoration(
              expired ? AppTheme.danger : AppTheme.success,
            ),
            child: Text(
              expired ? '签名请求已过期，请返回重新提交' : '签名请求有效期剩余：${_remaining}s',
              style: TextStyle(
                color: expired ? AppTheme.danger : AppTheme.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 16)),
          Center(
            child: QrImageView(
              data: widget.request,
              version: QrVersions.auto,
              size: AppLayout.scaled(context, 240),
            ),
          ),
          SizedBox(height: AppLayout.scaled(context, 16)),
          const Text(
            '请用公民钱包扫描此二维码完成签名，然后扫描公民钱包生成的响应二维码。',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          SizedBox(height: AppLayout.scaled(context, 24)),
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
                  onPressed: expired ? null : _scan,
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
      (QrActions.isChainAction(action)
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
  );
  if (outcome is CitizenSigningCompleted) {
    return Uint8List.fromList(outcome.signature);
  }
  final pending = outcome as CitizenExternalSigningPending;
  if (context == null || !context.mounted) {
    await signing.cancel(pending.sessionId);
    throw const AccountSecurityException('冷签缺少扫码页面上下文，已拒绝签名');
  }
  final response = await showCitizenSdkQrResponse(
    context,
    request: pending.transportRequest,
    expiresAt: pending.expiresAt,
  );
  if (response == null) {
    await signing.cancel(pending.sessionId);
    throw const AccountSecurityException('签名已取消');
  }
  final completed = await signing.consumeExternalSignature(
    sessionId: pending.sessionId,
    response: response,
  );
  return Uint8List.fromList(completed.signature);
}


/// 冷钱包扫码签名会话页面。
///
/// 两阶段交互：
/// 1. 展示签名请求二维码，等待离线设备扫描。
/// 2. 用户点击"扫描响应"，打开相机扫描离线设备生成的签名响应二维码。
///
/// 返回 [SignResponseEnvelope](成功)或 `null`(取消/超时)。
class QrSignSessionPage extends StatefulWidget {
  const QrSignSessionPage({
    super.key,
    required this.request,
    required this.requestJson,
    required this.expectedSignerPublicKey,
    this.responseKind = QrKind.accountDataKeyResponse,
  });

  /// 已构建的签名请求 envelope。
  final SignRequestEnvelope request;

  /// 编码后的 JSON 字符串,直接用于二维码展示。
  final String requestJson;
  final String expectedSignerPublicKey;

  /// 本页面只承接 CitizenApp 账户数据用途钥业务的 `k=6` 响应。
  final QrKind responseKind;

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
    final raw = await Navigator.of(context).push<String>(
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
      if (widget.responseKind != QrKind.accountDataKeyResponse) {
        throw const FormatException('此页面只接受用途钥响应');
      }
      final envelope = QrEnvelope.parse(raw);
      if (envelope.kind != QrKind.accountDataKeyResponse ||
          envelope.id != widget.request.id ||
          envelope.expiresAt != widget.request.expiresAt ||
          envelope.body is! AccountDataKeyResponseBody ||
          (envelope.body as AccountDataKeyResponseBody).signerPublicKeyHex !=
              widget.expectedSignerPublicKey) {
        throw const FormatException('用途钥响应与当前请求不一致');
      }
      final response = QrEnvelope<AccountDataKeyResponseBody>(
        kind: envelope.kind,
        id: envelope.id,
        issuedAt: envelope.issuedAt,
        expiresAt: envelope.expiresAt,
        body: envelope.body as AccountDataKeyResponseBody,
      );
      if (!mounted) return;
      Navigator.of(context).pop(response);
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
            child: QrImageView(
              data: widget.requestJson,
              version: QrVersions.auto,
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
  const _SimpleScanner({this.acceptedKind});

  final QrKind? acceptedKind;

  @override
  State<_SimpleScanner> createState() => _SimpleScannerState();
}

class _SimpleScannerState extends State<_SimpleScanner> {
  static const double scanBoxSize = 260;
  static const double scanBoxOffsetY = -40;

  final ScannerController _controller = ScannerController();
  bool _handled = false;
  bool _torchOn = false;
  bool _closing = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
    } on ScannerFailure catch (failure) {
      _showScannerFailure(failure);
    }
  }

  Future<void> _scanFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    try {
      final raw = await _controller.scanImage(image.path);
      await _handleCode(raw);
    } on ScannerFailure catch (failure) {
      _showScannerFailure(failure);
    }
  }

  Future<void> _handleCode(String raw) async {
    if (_handled) return;
    _handled = true;
    try {
      await _controller.stop();
      final acceptedKind = widget.acceptedKind;
      if (acceptedKind != null && QrEnvelope.parse(raw).kind != acceptedKind) {
        throw FormatException(
          acceptedKind == QrKind.accountDataKeyResponse
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
    } finally {
      if (mounted && !_closing) {
        _handled = false;
        _controller.resetDetection();
        try {
          await _controller.start();
        } on ScannerFailure catch (failure) {
          _showScannerFailure(failure);
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
            controller: _controller,
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
