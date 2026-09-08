import 'package:flutter/widgets.dart';

/// 设备识别结果回调。一次捕获可能包含多个二维码或空值。
typedef ScannerCandidatesCallback = void Function(Iterable<String?> values);

/// Flutter 扫码设备后端接口。
///
/// 正式环境由 mobile_scanner 实现；接口公开仅用于包测试和特殊宿主注入，业务页面不得
/// 借此实现第二套 QR_V1 解析器。
abstract interface class ScannerDeviceBackend {
  Widget buildPreview({required ScannerCandidatesCallback onCandidates});

  Future<void> start();

  Future<void> stop();

  Future<void> toggleTorch();

  Future<Iterable<String?>> analyzeImage(String imagePath);

  Future<void> dispose();
}
