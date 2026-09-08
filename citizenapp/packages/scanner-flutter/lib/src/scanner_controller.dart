import 'package:flutter/widgets.dart';

import 'mobile_scanner_backend.dart';
import 'scanner_backend.dart';
import 'scanner_failure.dart';

/// 统一扫码设备生命周期与单次识别门控。
final class ScannerController {
  ScannerController({ScannerDeviceBackend? backend})
    : _backend = backend ?? MobileScannerBackend();

  final ScannerDeviceBackend _backend;
  bool _claimed = false;
  bool _running = false;
  bool _disposed = false;

  bool get hasClaimedValue => _claimed;

  Widget buildPreview({required ScannerCandidatesCallback onCandidates}) {
    _ensureActive();
    return _backend.buildPreview(onCandidates: onCandidates);
  }

  /// 从一次捕获中领取第一个非空原文；领取后忽略后续重复帧，直至 [resetDetection]。
  String? claimFirst(Iterable<String?> values) {
    _ensureActive();
    if (_claimed) return null;
    for (final value in values) {
      if (value != null && value.isNotEmpty) {
        _claimed = true;
        return value;
      }
    }
    return null;
  }

  void resetDetection() {
    _ensureActive();
    _claimed = false;
  }

  Future<void> start() async {
    _ensureActive();
    if (_running) return;
    await _run('启动摄像头', _backend.start);
    _running = true;
  }

  Future<void> stop() async {
    _ensureActive();
    if (!_running) return;
    await _run('停止摄像头', _backend.stop);
    _running = false;
  }

  Future<void> toggleTorch() => _run('切换手电筒', _backend.toggleTorch);

  /// 识别业务页面已经选择的本地图片，只返回二维码原文。
  Future<String> scanImage(String imagePath) async {
    _ensureActive();
    try {
      final values = await _backend.analyzeImage(imagePath);
      final raw = claimFirst(values);
      if (raw == null) {
        throw const ScannerFailure(
          kind: ScannerFailureKind.noQrCode,
          message: '图片中未识别到二维码',
        );
      }
      return raw;
    } on ScannerFailure {
      rethrow;
    } catch (error) {
      throw ScannerFailure.fromDeviceError(error, operation: '识别图片');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (_running) await _backend.stop();
      await _backend.dispose();
      _running = false;
    } catch (error) {
      throw ScannerFailure.fromDeviceError(error, operation: '释放扫码设备');
    }
  }

  Future<void> _run(String operation, Future<void> Function() action) async {
    _ensureActive();
    try {
      await action();
    } catch (error) {
      throw ScannerFailure.fromDeviceError(error, operation: operation);
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw const ScannerFailure(
        kind: ScannerFailureKind.disposed,
        message: '扫码设备已经释放',
      );
    }
  }
}
