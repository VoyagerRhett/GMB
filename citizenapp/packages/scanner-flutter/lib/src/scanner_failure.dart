/// 扫码设备层错误分类。
///
/// 这里只描述设备和生命周期失败；“二维码码型不符合当前业务”属于产品页面职责。
enum ScannerFailureKind {
  permissionDenied,
  cameraUnavailable,
  noQrCode,
  disposed,
  operationFailed,
}

/// 统一扫码设备错误。
class ScannerFailure implements Exception {
  const ScannerFailure({required this.kind, required this.message, this.cause});

  final ScannerFailureKind kind;
  final String message;
  final Object? cause;

  factory ScannerFailure.fromDeviceError(
    Object error, {
    required String operation,
  }) {
    final normalized = error.toString().toLowerCase();
    final ScannerFailureKind kind;
    if (normalized.contains('permission') || normalized.contains('denied')) {
      kind = ScannerFailureKind.permissionDenied;
    } else if (normalized.contains('unavailable') ||
        normalized.contains('not available') ||
        normalized.contains('no camera')) {
      kind = ScannerFailureKind.cameraUnavailable;
    } else {
      kind = ScannerFailureKind.operationFailed;
    }
    return ScannerFailure(kind: kind, message: '$operation失败', cause: error);
  }

  @override
  String toString() => 'ScannerFailure($kind): $message';
}
