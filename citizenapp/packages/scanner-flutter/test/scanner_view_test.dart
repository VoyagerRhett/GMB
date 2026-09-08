import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gmb_scanner_flutter/scanner_flutter.dart';

void main() {
  testWidgets('预览启动后只回调一次原始字符串', (tester) async {
    final backend = ViewScannerBackend();
    final controller = ScannerController(backend: backend);
    final values = <String>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ScannerView(controller: controller, onRawValue: values.add),
      ),
    );
    await tester.pump();
    expect(backend.startCount, 1);

    backend.emit(['QR_V1 raw', 'ignored']);
    backend.emit(['repeated']);
    await tester.pump();
    expect(values, ['QR_V1 raw']);
  });

  testWidgets('启动错误通过统一 failure 回调', (tester) async {
    final backend = ViewScannerBackend()
      ..startError = StateError('camera unavailable');
    final failures = <ScannerFailure>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ScannerView(
          controller: ScannerController(backend: backend),
          onRawValue: (_) {},
          onFailure: failures.add,
        ),
      ),
    );
    await tester.pump();
    expect(failures.single.kind, ScannerFailureKind.cameraUnavailable);
  });
}

final class ViewScannerBackend implements ScannerDeviceBackend {
  ScannerCandidatesCallback? _onCandidates;
  Object? startError;
  int startCount = 0;

  void emit(Iterable<String?> values) => _onCandidates?.call(values);

  @override
  Future<Iterable<String?>> analyzeImage(String imagePath) async => const [];

  @override
  Widget buildPreview({required ScannerCandidatesCallback onCandidates}) {
    _onCandidates = onCandidates;
    return const SizedBox.expand();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> start() async {
    startCount += 1;
    if (startError case final Object error) throw error;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> toggleTorch() async {}
}
