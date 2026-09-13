import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/qr/scanner/scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/qr/bodies/user_contact_body.dart';
import 'package:citizenapp/qr/bodies/user_transfer_body.dart';
import 'package:citizenapp/qr/qr_router.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/signer/app_business_qr_codec.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 扫码结果：收款码预填数据。
class QrScanTransferResult {
  const QrScanTransferResult({
    required this.toSs58Address,
    this.amount,
    this.symbol,
    this.memo,
    this.bank,
  });

  final String toSs58Address;
  final String? amount;
  final String? symbol;
  final String? memo;
  final String? bank;
}

/// 把用户名片码转成 CID 通讯录关系。
///
/// 码内 CID 只是声明值，必须拿码内 `account_id` 经链上双向绑定重新解析，
/// 两者完全一致才允许入库。码内不含昵称：真实公开昵称由资料接口按 CID 拉取。
Future<ContactImportResult> addUserQrContact({
  required UserContactBody body,
  required CidByAccountIdResolver cidResolver,
  required UserContactService contactService,
}) async {
  final resolvedCidNumber = await cidResolver.resolve(body.accountId);
  if (resolvedCidNumber != body.cidNumber) {
    throw const FormatException('用户码 CID 与 account_id 的链上绑定不一致');
  }
  return contactService.addContact(
    cidNumber: body.cidNumber,
    ss58Address: ss58FromAccountIdText(body.accountId),
    contactRemark: '',
  );
}

/// 扫码模式。
enum QrScanMode {
  /// 扫码支付：按当前入口只识别 QR_V1 收款码、用户码与账户码。
  transfer,

  /// 扫码添加好友：仅识别用户码。
  contact,

  /// 账户目标入口：只返回用户码或账户码的 QR_V1 原文。
  accountTarget,

  /// 签名入口：只返回签名请求码的 QR_V1 原文。
  signRequest,

  /// 需要自行处理用户资料的业务入口：只返回用户码的 QR_V1 原文。
  userContactValue,

  /// 统一「扫一扫」：按协议分类后交调用方分派——收款码/用户码/账户码 pop
  /// [QrScanTransferResult]（走支付）；signRequest pop 原始字符串（走签名）；未来类型再加。
  dispatch,
}

/// 统一扫码页。
///
/// 通过 [mode] 区分两种独立功能：
/// - [QrScanMode.transfer] → 扫码支付
/// - [QrScanMode.contact]  → 扫码添加好友
class QrScanPage extends StatefulWidget {
  const QrScanPage({
    super.key,
    required this.mode,
    this.initialCode,
    this.customTitle,
    this.contactService,
    this.cidResolver,
    this.scannerController,
    this.qr,
  });

  /// 扫码模式。
  final QrScanMode mode;

  /// 如果已扫码，可直接传入原始字符串跳过扫码步骤。
  final String? initialCode;

  /// 自定义标题（为 null 时使用默认标题）。
  final String? customTitle;

  /// 测试注入；正式运行使用统一加密通讯录服务。
  final UserContactService? contactService;

  /// 测试注入；正式运行通过链上双向绑定把二维码账户解析为永久 CID。
  final CidByAccountIdResolver? cidResolver;

  /// 扫码设备测试注入；产品运行统一使用共享 Flutter 扫码适配器。
  final ScannerController? scannerController;

  /// CitizenSDK QR 公开端口；仅测试可注入，生产从根 Provider 读取同一实例。
  final CitizenQr? qr;

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  late final ScannerController _controller =
      widget.scannerController ?? ScannerController();
  final QrRouter _router = QrRouter();
  UserContactService? _contactService;
  CidByAccountIdResolver? _cidResolver;
  bool _handled = false;
  bool _torchOn = false;
  // 本页正在 pop/dispose 时置真，阻止 _handleCode 的 finally 重启相机（避免与 dispose 竞态）。
  bool _closing = false;

  bool get _ownsController => widget.scannerController == null;

  @override
  void initState() {
    super.initState();
    _contactService = widget.contactService;
    _cidResolver = widget.cidResolver;
    final code = widget.initialCode;
    if (code != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleCode(code));
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      unawaited(_controller.dispose());
    }
    super.dispose();
  }

  /// 从相册选取图片识别二维码
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

  /// 切换手电筒
  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
    } on ScannerFailure catch (failure) {
      _showScannerFailure(failure);
    }
  }

  Future<void> _handleCode(String raw) async {
    if (_handled) {
      return;
    }
    _handled = true;

    try {
      await _controller.stop();
      final sdkDocument = await _parseSdkDocument(raw);
      if (sdkDocument != null && await _handleSdkDocument(raw, sdkDocument)) {
        return;
      }
      if (sdkDocument == null && await _handleAppBusinessSignRequest(raw)) {
        return;
      }
      final result = _router.route(raw);

      switch (widget.mode) {
        case QrScanMode.transfer:
          // 扫码支付只接受 QR_V1 收款码 / 用户码 / 账户码。
          // (多签发现走反向索引)
          if (result.type == QrRouteType.userTransfer) {
            _handleTransfer(result);
          } else if (result.type == QrRouteType.userContact) {
            _handleContactAsRecipient(result);
          } else {
            await _showUnrecognized();
          }
        case QrScanMode.contact:
          // 通讯录关系必须锚永久 CID,只有用户码携带 CID。
          // 账户码与收款码只声明账户/一笔收款,不得写入通讯录。
          if (result.type == QrRouteType.userContact) {
            await _handleContact(result);
          } else if (result.type == QrRouteType.userTransfer) {
            await _showNotAContactCode();
          } else {
            await _showUnrecognized();
          }
        case QrScanMode.accountTarget:
          if (result.type == QrRouteType.userContact) {
            if (!mounted) return;
            _popPage(raw);
          } else {
            await _showExpectedCode('请扫描用户码或账户码');
          }
        case QrScanMode.signRequest:
          await _showExpectedCode('请扫描签名请求二维码');
        case QrScanMode.userContactValue:
          if (result.type == QrRouteType.userContact) {
            if (!mounted) return;
            _popPage(raw);
          } else {
            await _showNotAContactCode();
          }
        case QrScanMode.dispatch:
          // 统一扫一扫:收款/用户/账户码→支付结果;signRequest→原始串交调用方签名。
          if (result.type == QrRouteType.userTransfer) {
            _handleTransfer(result);
          } else if (result.type == QrRouteType.userContact) {
            // 扫一扫扫到用户码 = 按收款人进入转账;
            // 加好友走 contact 模式扫同一张用户码,按扫描场景分流。
            _handleContactAsRecipient(result);
          } else {
            await _showUnrecognized();
          }
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('扫码处理异常'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
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

  Future<CitizenQrDocument?> _parseSdkDocument(String raw) async {
    try {
      return await (widget.qr ?? context.read<CitizenSdk>().qr).parse(raw);
    } on Object {
      return null;
    }
  }

  Future<bool> _handleSdkDocument(
    String raw,
    CitizenQrDocument document,
  ) async {
    if (document.kind == CitizenQrKind.accountId &&
        document.accountId != null) {
      switch (widget.mode) {
        case QrScanMode.transfer || QrScanMode.dispatch:
          _popPage(
            QrScanTransferResult(
              toSs58Address: ss58FromAccountIdText(document.accountId!),
            ),
          );
          return true;
        case QrScanMode.accountTarget:
          _popPage(raw);
          return true;
        case QrScanMode.contact || QrScanMode.userContactValue:
          await _showNotAContactCode();
          return true;
        case QrScanMode.signRequest:
          await _showExpectedCode('请扫描签名请求二维码');
          return true;
      }
    }
    if (document.kind == CitizenQrKind.signRequest) {
      switch (widget.mode) {
        case QrScanMode.signRequest || QrScanMode.dispatch:
          _popPage(raw);
          return true;
        case QrScanMode.transfer:
          await _showSignRequestNotHere();
          return true;
        case QrScanMode.accountTarget:
          await _showExpectedCode('请扫描用户码或账户码');
          return true;
        case QrScanMode.contact || QrScanMode.userContactValue:
          await _showExpectedCode('请扫描当前入口支持的二维码');
          return true;
      }
    }
    return false;
  }

  Future<bool> _handleAppBusinessSignRequest(String raw) async {
    try {
      AppBusinessQrCodec().parseRequest(raw);
    } on AppBusinessQrException {
      return false;
    }
    switch (widget.mode) {
      case QrScanMode.signRequest || QrScanMode.dispatch:
        _popPage(raw);
        return true;
      case QrScanMode.transfer:
        await _showSignRequestNotHere();
        return true;
      case QrScanMode.accountTarget:
        await _showExpectedCode('请扫描用户码或账户码');
        return true;
      case QrScanMode.contact || QrScanMode.userContactValue:
        await _showExpectedCode('请扫描当前入口支持的二维码');
        return true;
    }
  }

  /// 设备层只报告相机、权限或图片识别失败；码型错误仍由当前业务入口解释。
  void _showScannerFailure(ScannerFailure failure) {
    if (!mounted || _closing) return;
    final message = failure.kind == ScannerFailureKind.noQrCode
        ? '未识别到二维码'
        : failure.message;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 页级返回：先置 _closing，让 _handleCode 的 finally 不再重启相机
  /// （本页正在 pop/dispose，重启相机会与 dispose 竞争抛错）。
  void _popPage([Object? result]) {
    _closing = true;
    Navigator.of(context).pop(result);
  }

  // 收款码
  void _handleTransfer(QrRouteResult result) {
    if (!mounted) {
      return;
    }
    final body = result.envelope!.body as UserTransferBody;
    _popPage(
      QrScanTransferResult(
        toSs58Address: ss58FromAccountIdText(body.accountId),
        amount: body.amount.isEmpty ? null : body.amount,
        symbol: body.symbol.isEmpty ? null : body.symbol,
        memo: body.memo.isEmpty ? null : body.memo,
        bank: body.bank.isEmpty ? null : body.bank,
      ),
    );
  }

  void _handleContactAsRecipient(QrRouteResult result) {
    if (!mounted) return;
    final body = result.envelope!.body as UserContactBody;
    // 用户码只声明账户,展示地址在本机由 account_id 派生。
    _popPage(
      QrScanTransferResult(
        toSs58Address: ss58FromAccountIdText(body.accountId),
      ),
    );
  }

  // 用户码
  Future<void> _handleContact(QrRouteResult result) async {
    if (!mounted) return;
    try {
      final body = result.envelope!.body as UserContactBody;
      final contactService = _contactService ??= UserContactService(
        accountSecurity: context.read<AccountSecurityService>(),
        currentUserContext: context.read<CurrentUserContext>(),
        sessionProvider: context.read<SquareSessionProvider>(),
        chainReader: CitizenIdentityChainReader(
          chain: context.read<CitizenSdk>().chain,
        ),
      );
      final addResult = await addUserQrContact(
        body: body,
        cidResolver: _cidResolver ??= CidByAccountIdResolver(
          chainReader: CitizenIdentityChainReader(
            chain: context.read<CitizenSdk>().chain,
          ),
        ),
        contactService: contactService,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // 码内不含昵称;这里只报 CID,真实昵称由通讯录按 CID 拉资料后展示。
            addResult.created
                ? '已加入通讯录：${body.cidNumber}'
                : '已更新通讯录：${body.cidNumber}',
          ),
        ),
      );
      _popPage();
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('无法识别二维码'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('继续扫描'),
            ),
          ],
        ),
      );
    }
  }

  // 未识别
  String get _hintText =>
      widget.customTitle ??
      switch (widget.mode) {
        QrScanMode.transfer => '扫描收款码',
        QrScanMode.contact => '扫描对方用户码',
        QrScanMode.accountTarget => '扫描用户码或账户码',
        QrScanMode.signRequest => '扫描签名请求二维码',
        QrScanMode.userContactValue => '扫描用户码',
        QrScanMode.dispatch => '扫描二维码',
      };

  String get _titleText =>
      widget.customTitle ??
      switch (widget.mode) {
        QrScanMode.transfer => '扫码支付',
        QrScanMode.contact => '扫码添加好友',
        QrScanMode.accountTarget => '扫描账户',
        QrScanMode.signRequest => '扫码签名',
        QrScanMode.userContactValue => '扫描用户码',
        QrScanMode.dispatch => '扫一扫',
      };

  /// 扫到不能加联系人的码时给明确原因,不用「无法识别」含糊过去。
  Future<void> _showNotAContactCode() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('这不是用户码'),
        content: const Text(
          '通讯录关系必须锚定对方的永久 CID，只有「用户主页」出示的用户码携带 CID。'
          '账户码和收款码只声明账户，不能加为联系人。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _showExpectedCode(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('二维码类型不符'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('继续扫描'),
          ),
        ],
      ),
    );
  }

  /// 扫码填地址时扫到签名请求：只指路，不解释。
  Future<void> _showSignRequestNotHere() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('这是签名请求'),
        content: const Text('此处只扫收款地址。请到「聊天 → 扫一扫」。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUnrecognized() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('无法识别二维码'),
        content: Text('请$_hintText。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double scanBoxSize = 240;
    // 扫描框偏移：向上移动 80 像素
    const double scanBoxOffsetY = -80;

    return Scaffold(
      appBar: AppBar(title: Text(_titleText), centerTitle: true),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 摄像头画面
          ScannerView(
            controller: _controller,
            onRawValue: (raw) => unawaited(_handleCode(raw)),
            onFailure: _showScannerFailure,
          ),

          // 扫描框 + 半透明遮罩
          CustomPaint(
            painter: _ScanOverlayPainter(
              scanBoxSize: scanBoxSize,
              offsetY: scanBoxOffsetY,
            ),
            child: const SizedBox.expand(),
          ),

          // 扫描框四角装饰（与遮罩使用相同像素偏移）
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

          // 提示文字（扫描框下方）
          Center(
            child: Transform.translate(
              offset: const Offset(0, scanBoxOffsetY + scanBoxSize / 2 + 24),
              child: Text(
                _hintText,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: AppLayout.scaled(context, 14),
                ),
              ),
            ),
          ),

          // 底部工具栏：相册 + 手电筒
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
                  // 相册图标
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
                  // 手电筒图标
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

// 扫描框半透明遮罩
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

// 扫描框四角装饰线
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

    // 左上
    canvas.drawLine(const Offset(0, 0), const Offset(cornerLen, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLen), paint);
    // 右上
    canvas.drawLine(Offset(w, 0), Offset(w - cornerLen, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, cornerLen), paint);
    // 左下
    canvas.drawLine(Offset(0, h), Offset(cornerLen, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - cornerLen), paint);
    // 右下
    canvas.drawLine(Offset(w, h), Offset(w - cornerLen, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - cornerLen), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
