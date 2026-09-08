/// GMB Flutter 产品统一二维码设备适配器。
///
/// 本包只输出二维码原始字符串，不解析 QR_V1、不判断业务码型，也不执行页面导航。
library;

export 'src/scanner_backend.dart'
    show ScannerCandidatesCallback, ScannerDeviceBackend;
export 'src/scanner_controller.dart' show ScannerController;
export 'src/scanner_failure.dart' show ScannerFailure, ScannerFailureKind;
export 'src/scanner_view.dart' show ScannerView;
