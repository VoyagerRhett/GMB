import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmb_scanner_flutter/scanner_flutter.dart';

void main() {
  test('同一次扫描只领取第一个非空原文，重置后才能再次领取', () {
    final controller = ScannerController(backend: FakeScannerBackend());
    expect(controller.claimFirst([null, '', 'first', 'second']), 'first');
    expect(controller.claimFirst(['repeated']), isNull);
    controller.resetDetection();
    expect(controller.claimFirst(['next']), 'next');
  });

  test('图片识别复用单次门控并把无二维码映射为统一错误', () async {
    final backend = FakeScannerBackend()..imageValues = ['image-qr'];
    final controller = ScannerController(backend: backend);
    expect(await controller.scanImage('/tmp/qr.png'), 'image-qr');

    controller.resetDetection();
    backend.imageValues = const [];
    await expectLater(
      controller.scanImage('/tmp/empty.png'),
      throwsA(
        isA<ScannerFailure>().having(
          (failure) => failure.kind,
          'kind',
          ScannerFailureKind.noQrCode,
        ),
      ),
    );
  });

  test('生命周期与设备错误统一经控制器转发', () async {
    final backend = FakeScannerBackend();
    final controller = ScannerController(backend: backend);
    await controller.start();
    await controller.start();
    await controller.stop();
    await controller.stop();
    await controller.toggleTorch();
    expect(
      (backend.startCount, backend.stopCount, backend.torchCount),
      (1, 1, 1),
    );

    backend.startError = StateError('camera permission denied');
    await expectLater(
      controller.start(),
      throwsA(
        isA<ScannerFailure>().having(
          (failure) => failure.kind,
          'kind',
          ScannerFailureKind.permissionDenied,
        ),
      ),
    );
  });

  test('释放幂等，释放后拒绝继续操作', () async {
    final backend = FakeScannerBackend();
    final controller = ScannerController(backend: backend);
    await controller.dispose();
    await controller.dispose();
    expect(backend.disposeCount, 1);
    expect(
      controller.resetDetection,
      throwsA(
        isA<ScannerFailure>().having(
          (failure) => failure.kind,
          'kind',
          ScannerFailureKind.disposed,
        ),
      ),
    );
  });
}

final class FakeScannerBackend implements ScannerDeviceBackend {
  Iterable<String?> imageValues = const [];
  Object? startError;
  int startCount = 0;
  int stopCount = 0;
  int torchCount = 0;
  int disposeCount = 0;

  @override
  Future<Iterable<String?>> analyzeImage(String imagePath) async => imageValues;

  @override
  Widget buildPreview({required ScannerCandidatesCallback onCandidates}) =>
      const SizedBox.shrink();

  @override
  Future<void> dispose() async => disposeCount += 1;

  @override
  Future<void> start() async {
    startCount += 1;
    if (startError case final Object error) throw error;
  }

  @override
  Future<void> stop() async => stopCount += 1;

  @override
  Future<void> toggleTorch() async => torchCount += 1;
}
