import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../login_qr_handler.dart';
import '../wallet/wallet_manager.dart';
import 'app_theme.dart';

/// 登录签名页面：显示登录签名请求详情 → 用户确认 → 签名 → 展示签名响应 QR。
class LoginSignPage extends StatefulWidget {
  const LoginSignPage({
    super.key,
    required this.account,
    required this.walletName,
    required this.raw,
  });

  /// 签名主体账户（由 ScanPage 按 QR 的 signerPublicKey 定位后传入）。
  final Account account;
  final String walletName;
  final String raw;

  @override
  State<LoginSignPage> createState() => _LoginSignPageState();
}

class _LoginSignPageState extends State<LoginSignPage> {
  LoginSignRequestEnvelope? _request;
  LoginSignResponseEnvelope? _response;
  String? _error;
  bool _signing = false;
  Timer? _timer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _parseSignRequest();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _parseSignRequest() {
    try {
      final request = parseLoginSignRequest(widget.raw);
      if (isLoginSignRequestExpired(request)) {
        setState(() => _error = '登录二维码已过期');
        return;
      }
      if (!loginRequestTargetsAccountId(request, widget.account.accountId)) {
        setState(() => _error = '登录二维码指定的账户与当前账户不一致');
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      setState(() {
        _request = request;
        _remainingSeconds = (request.expiresAt ?? 0) - now;
      });
      _startCountdown();
    } on LoginQrException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '解析失败: $e');
    }
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _timer?.cancel();
          if (_response == null) {
            _error = '登录二维码已过期';
          }
        }
      });
    });
  }

  Future<void> _confirmAndSign() async {
    final request = _request;
    if (request == null || _signing) return;
    // 私钥调用前再次校验目标账户，避免页面状态变化后误用其他账户签名。
    if (!loginRequestTargetsAccountId(request, widget.account.accountId)) {
      setState(() => _error = '登录二维码指定的账户与当前账户不一致');
      return;
    }

    setState(() => _signing = true);

    try {
      final walletManager = WalletManager();
      // 当前 sr25519 的 AccountId32 与 signer public key 字节相同。
      final signMessage = buildSignMessage(request, widget.account.accountId);
      final result = await walletManager.signUtf8ForAccount(
        widget.account.accountId,
        signMessage,
      );

      final response = buildLoginSignResponse(
        request: request,
        signerPublicKey: result.signerPublicKey,
        signatureHex: result.signatureHex,
      );

      if (!mounted) return;
      setState(() {
        _response = response;
        _signing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '签名失败: $e';
        _signing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceDark,
      appBar: AppBar(
        title: const Text('登录确认'),
        backgroundColor: AppTheme.surfaceDark,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _error != null
            ? _buildError()
            : _response != null
                ? _buildResponse()
                : _request != null
                    ? _buildConfirm()
                    : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirm() {
    final c = _request!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: AppTheme.surfaceCard,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '扫码登录',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _infoRow('系统', loginSystemDisplayName(c)),
                  _infoRow(
                    '账户',
                    '${widget.walletName} · ${widget.account.accountName}',
                  ),
                  _infoRow(
                    '地址',
                    _shortenSs58Address(widget.account.ss58Address),
                  ),
                  _infoRow(
                    '剩余时间',
                    _remainingSeconds > 0 ? '$_remainingSeconds秒' : '已过期',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '确认后将使用当前钱包签名登录 ${loginSystemDisplayName(c)}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          ElevatedButton(
            onPressed:
                _signing || _remainingSeconds <= 0 ? null : _confirmAndSign,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppTheme.primary,
            ),
            child: _signing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('确认登录', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildResponse() {
    final json = _response!.toRawJson();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Text(
            '请用登录页面扫描此二维码',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            loginSystemDisplayName(_request!),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: QrImageView(
                  data: json,
                  version: QrVersions.auto,
                  size: 280,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _shortenSs58Address(String ss58Address) {
    if (ss58Address.length <= 16) return ss58Address;
    return '${ss58Address.substring(0, 8)}...'
        '${ss58Address.substring(ss58Address.length - 8)}';
  }
}
