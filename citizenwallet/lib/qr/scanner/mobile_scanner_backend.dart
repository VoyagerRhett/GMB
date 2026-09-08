import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'scanner_backend.dart';

/// `mobile_scanner` 唯一设备接线层。
final class MobileScannerBackend implements ScannerDeviceBackend {
  MobileScannerBackend()
    : _controller = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );

  final MobileScannerController _controller;

  @override
  Widget buildPreview({required ScannerCandidatesCallback onCandidates}) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        onCandidates(capture.barcodes.map((barcode) => barcode.rawValue));
      },
    );
  }

  @override
  Future<Iterable<String?>> analyzeImage(String imagePath) async {
    final capture = await _controller.analyzeImage(imagePath);
    return capture?.barcodes.map((barcode) => barcode.rawValue) ??
        const <String?>[];
  }

  @override
  Future<void> dispose() => _controller.dispose();

  @override
  Future<void> start() => _controller.start();

  @override
  Future<void> stop() => _controller.stop();

  @override
  Future<void> toggleTorch() => _controller.toggleTorch();
}
