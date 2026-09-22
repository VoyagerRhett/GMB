import 'package:citizen_sdk/citizen_sdk.dart';

/// CitizenApp 扫码设备层错误分类。
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
    // 只投影SDK稳定错误类别供原页面显示，不猜测平台错误字符串。
    final kind = error is CitizenSdkException ? switch (error.code) {
      CitizenSdkErrorCode.permissionDenied => ScannerFailureKind.permissionDenied,
      CitizenSdkErrorCode.unavailable || CitizenSdkErrorCode.unsupported => ScannerFailureKind.cameraUnavailable,
      CitizenSdkErrorCode.notFound || CitizenSdkErrorCode.decode => ScannerFailureKind.noQrCode,
      CitizenSdkErrorCode.invalidHandle || CitizenSdkErrorCode.cancelled => ScannerFailureKind.disposed,
      _ => ScannerFailureKind.operationFailed,
    } : ScannerFailureKind.operationFailed;
    return ScannerFailure(kind: kind, message: '$operation失败', cause: error);
  }

  @override
  String toString() => 'ScannerFailure($kind): $message';
}
