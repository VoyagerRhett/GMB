/// GMB Flutter 产品统一二维码设备适配器。
///
/// 本包只输出二维码原始字符串，不解析 QR_V1、不判断业务码型，也不执行页面导航。
library;

export 'scanner_backend.dart'
    show ScannerCandidatesCallback, ScannerDeviceBackend;
export 'scanner_controller.dart' show ScannerController;
export 'scanner_failure.dart' show ScannerFailure, ScannerFailureKind;
export 'scanner_view.dart' show ScannerView;
