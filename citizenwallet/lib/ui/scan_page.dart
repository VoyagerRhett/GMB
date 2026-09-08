import 'dart:async';

import 'package:flutter/material.dart';
import 'package:citizenwallet/qr/scanner/scanner.dart';
import 'package:image_picker/image_picker.dart';

import '../qr/qr_protocols.dart';
import '../qr/envelope.dart';
import '../qr/bodies/sign_request_body.dart';
import '../wallet/wallet_manager.dart';
import 'app_theme.dart';
import 'login_sign_page.dart';
import 'offline_sign_page.dart';
import 'scan_overlay.dart';

/// 本钱包扫码签名页面（对准框 + 相册 + 手电筒）。
///
/// 只扫本钱包（widget.wallet）账户的签名请求：按 QR 的 signerPublicKey 定位账户，
/// 账户不属于本钱包（masterId 不符）或本设备无此账户，一律拒绝并提示。

/// 扫码作用域谓词(纯函数,可单测):账户 masterId 与本钱包 masterId 一致才允许签名。
bool accountBelongsToWallet(String accountMasterId, String walletMasterId) =>
    accountMasterId == walletMasterId;

class ScanPage extends StatefulWidget {
  const ScanPage({
    super.key,
    required this.wallet,
    this.scannerController,
  });

  /// 只扫本钱包账户的签名请求;跨钱包(账户不属于本钱包)一律拒绝。
  final Wallet wallet;

  /// 扫码设备测试注入；产品运行统一使用共享 Flutter 扫码适配器。
  final ScannerController? scannerController;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  late final ScannerController _controller =
      widget.scannerController ?? ScannerController();
  final WalletManager _walletManager = WalletManager();
  bool _handled = false;
  bool _torchOn = false;
  bool _closing = false;

  bool get _ownsController => widget.scannerController == null;

  @override
  void dispose() {
    if (_ownsController) {
      unawaited(_controller.dispose());
    }
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

  /// 单次解析签名请求信封;非签名请求返回 null。
  SignRequestBody? _parseSignRequest(String raw) {
    try {
      final env = QrEnvelope.parse(raw);
      final body = env.body;
      if (env.kind == QrKind.signRequest && body is SignRequestBody) {
        return body;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleCode(String raw) async {
    if (_handled) return;
    _handled = true;
    try {
      await _controller.stop();
    } on ScannerFailure catch (failure) {
      _handled = false;
      _controller.resetDetection();
      _showScannerFailure(failure);
      return;
    }
    if (!mounted) return;

    // 只解析一次:signerPublicKey(目标账户)与 action(登录/普通)同源取自 body,
    // 避免两套解析逻辑漂移。
    final body = _parseSignRequest(raw);
    if (body == null) {
      await _showErrorAndResume('无法识别签名请求二维码');
      return;
    }

    final Account? account;
    if (QrActions.isSelfAccountDomainAction(body.action)) {
      // 注册局占号/换绑:b.u 留空,由用户从本钱包账户中自选一个绑定到该 CID。
      account = await _pickBindingAccount();
      if (!mounted) return;
      if (account == null) {
        // 用户取消选择,恢复扫描。
        _handled = false;
        _controller.resetDetection();
        await _controller.start();
        return;
      }
    } else {
      account =
          await _walletManager.getAccountByAccountId(body.signerPublicKeyHex);
      if (!mounted) return;
      if (account == null) {
        await _showErrorAndResume('本设备没有该签名请求指定的账户，无法签名');
        return;
      }
      if (!accountBelongsToWallet(account.masterId, widget.wallet.masterId)) {
        await _showErrorAndResume(
            '该签名请求的账户不属于「${widget.wallet.walletName}」，无法在此钱包签名');
        return;
      }
    }

    final walletName = widget.wallet.walletName;
    final signingAccount = account; // 上方两支均已对 null 提前 return,此处必非空。

    final isLogin = body.action == QrActions.login;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isLogin
            ? LoginSignPage(
                account: signingAccount, walletName: walletName, raw: raw)
            : OfflineSignPage(
                account: signingAccount, walletName: walletName, raw: raw),
      ),
    );

    if (!mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  /// 占号/换绑:从本钱包账户中选一个绑定到该 CID(占即绑一账户)。返回 null=取消。
  Future<Account?> _pickBindingAccount() async {
    final accounts = await _walletManager.getAccounts(widget.wallet.masterId);
    if (!mounted) return null;
    if (accounts.isEmpty) {
      await _showErrorAndResume('本钱包没有可绑定的账户');
      return null;
    }
    return showModalBottomSheet<Account>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择要绑定到该 CID 的账户',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final account in accounts)
              ListTile(
                title: Text(account.accountName),
                subtitle: Text(_shortAccountId(account.accountId)),
                onTap: () => Navigator.of(sheetContext).pop(account),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _shortAccountId(String accountId) => accountId.length <= 14
      ? accountId
      : '${accountId.substring(0, 8)}…${accountId.substring(accountId.length - 6)}';

  Future<void> _showErrorAndResume(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('无法签名'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('继续扫描'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _handled = false;
    _controller.resetDetection();
    try {
      await _controller.start();
    } on ScannerFailure catch (failure) {
      _showScannerFailure(failure);
    }
  }

  void _showScannerFailure(ScannerFailure failure) {
    if (!mounted || _closing) return;
    final message = failure.kind == ScannerFailureKind.noQrCode
        ? '未识别到二维码'
        : failure.message;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('扫码签名'),
        centerTitle: true,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ScannerView(
            controller: _controller,
            onRawValue: (raw) => unawaited(_handleCode(raw)),
            onFailure: _showScannerFailure,
          ),
          CustomPaint(
            painter: ScanOverlayPainter(
                scanBoxSize: scanBoxSize, offsetY: scanBoxOffsetY),
            child: const SizedBox.expand(),
          ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, scanBoxOffsetY),
              child: SizedBox(
                width: scanBoxSize,
                height: scanBoxSize,
                child: CustomPaint(painter: ScanCornerPainter()),
              ),
            ),
          ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, scanBoxOffsetY + scanBoxSize / 2 + 28),
              child: Text(
                '扫描「${widget.wallet.walletName}」的签名请求',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 14, letterSpacing: 0.3),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 48, left: 48, right: 48),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceCard.withAlpha(200),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: AppTheme.border.withAlpha(80)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildToolButton(
                    icon: Icons.photo_library_outlined,
                    label: '相册',
                    onTap: _scanFromGallery,
                    active: false,
                  ),
                  Container(width: 1, height: 32, color: AppTheme.border),
                  _buildToolButton(
                    icon: _torchOn
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_outlined,
                    label: _torchOn ? '关闭' : '手电筒',
                    onTap: _toggleTorch,
                    active: _torchOn,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool active,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: active ? AppTheme.gold : Colors.white),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: active ? AppTheme.gold : Colors.white70,
                  fontSize: 12)),
        ],
      ),
    );
  }
}
