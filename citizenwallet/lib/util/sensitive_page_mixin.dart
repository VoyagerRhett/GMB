import 'dart:async';

import 'package:flutter/material.dart';

import 'screenshot_guard.dart';

/// 敏感页面 mixin：自动启用截屏保护，响应截屏/录屏事件隐藏内容。
///
/// 使用方式：
/// ```dart
/// class _MyPageState extends State<MyPage> with SensitivePageMixin {
///   @override
///   Widget build(BuildContext context) {
///     if (sensitiveContentHidden) {
///       return buildHiddenPlaceholder(); // mixin 提供的遮罩
///     }
///     return ... // 正常内容
///   }
/// }
/// ```
mixin SensitivePageMixin<T extends StatefulWidget> on State<T> {
  /// 原生保护确认前及截屏/录屏后始终隐藏敏感内容。
  bool sensitiveContentHidden = true;
  bool sensitiveProtectionFailed = false;
  bool _guardAcquired = false;
  Future<void>? _guardOpening;
  bool _securityEventSeen = false;

  @override
  void initState() {
    super.initState();
    unawaited(retryScreenshotProtection());
  }

  /// 保护失败时允许重试；只在原生确认成功且期间没有安全事件时解除遮罩。
  Future<void> retryScreenshotProtection() =>
      _guardOpening ??= _openScreenshotProtection().whenComplete(() {
        _guardOpening = null;
      });

  /// 非敏感的创建选项可先显示，但生成钱包前必须确认保护可用。
  Future<bool> ensureScreenshotProtection() async {
    if (sensitiveContentHidden || !_guardAcquired) {
      await retryScreenshotProtection();
    }
    return mounted &&
        _guardAcquired &&
        !sensitiveContentHidden &&
        !sensitiveProtectionFailed &&
        ScreenshotGuard.canDisplaySensitiveContent;
  }

  Future<void> _openScreenshotProtection() async {
    try {
      if (_guardAcquired) {
        await ScreenshotGuard.disable(_onSecurityEvent);
        _guardAcquired = false;
      }
      _securityEventSeen = false;
      sensitiveProtectionFailed = false;
      await ScreenshotGuard.enable(_onSecurityEvent);
      if (!mounted) {
        await ScreenshotGuard.disable(_onSecurityEvent);
        return;
      }
      _guardAcquired = true;
      setState(() => sensitiveContentHidden = _securityEventSeen);
    } catch (_) {
      if (mounted) {
        setState(() {
          sensitiveProtectionFailed = true;
          sensitiveContentHidden = true;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_guardAcquired) unawaited(ScreenshotGuard.disable(_onSecurityEvent));
    super.dispose();
  }

  void _onSecurityEvent(String event) {
    if (!mounted) return;
    if (event == 'screenshot_taken' || event == 'protection_failed') {
      _securityEventSeen = true;
      // 截屏已发生或事件通道失效，隐藏内容并提醒用户。
      setState(() {
        sensitiveContentHidden = true;
        if (event == 'protection_failed') sensitiveProtectionFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            event == 'protection_failed'
                ? '屏幕保护不可用，敏感信息已隐藏'
                : '检测到截屏，敏感信息已隐藏。请勿截屏保存密钥信息。',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (event == 'screen_recording_started') {
      _securityEventSeen = true;
      // 录屏开始，立即隐藏
      setState(() => sensitiveContentHidden = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('检测到屏幕录制，敏感信息已隐藏'),
          duration: Duration(seconds: 3),
        ),
      );
    } else if (event == 'screen_recording_stopped') {
      // 录屏结束，可恢复显示（用户需重新点击查看）
      // 不自动恢复，保持隐藏状态
    }
  }

  /// 敏感内容被隐藏时的占位 Widget。
  Widget buildHiddenPlaceholder({String message = '敏感信息已隐藏'}) {
    return Scaffold(
      appBar: AppBar(title: const Text('安全提醒'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield, size: 64, color: Colors.orange.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              sensitiveProtectionFailed ? '请重试屏幕保护' : '请返回上一页重新操作',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: sensitiveProtectionFailed
                  ? retryScreenshotProtection
                  : () => Navigator.of(context).pop(),
              child: Text(sensitiveProtectionFailed ? '重试' : '返回'),
            ),
          ],
        ),
      ),
    );
  }
}
