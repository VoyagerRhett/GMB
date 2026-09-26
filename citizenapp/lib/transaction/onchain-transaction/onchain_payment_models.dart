import 'package:citizen_sdk/citizen_sdk.dart';

enum OnchainPaymentErrorCode {
  walletMissing,
  invalidDraft,
}

/// 页面只按已进入的真实交易步骤解释 SDK 错误，不把准备失败写成已发送失败。
enum OnchainPaymentStep { preparation, execution, externalSignature }

String onchainPaymentFailureText(
  OnchainPaymentStep step,
  CitizenSdkErrorCode code,
) {
  final action = switch (step) {
    OnchainPaymentStep.preparation => '交易准备',
    OnchainPaymentStep.execution => '交易执行',
    OnchainPaymentStep.externalSignature => '交易签名',
  };
  final reason = switch (code) {
    CitizenSdkErrorCode.decode => '链上数据解析异常',
    CitizenSdkErrorCode.network ||
    CitizenSdkErrorCode.unavailable ||
    CitizenSdkErrorCode.notReady ||
    CitizenSdkErrorCode.timeout => '区块链暂不可用',
    CitizenSdkErrorCode.invalidArgument => '交易参数无效',
    CitizenSdkErrorCode.authenticationCancelled ||
    CitizenSdkErrorCode.cancelled => '操作已取消',
    CitizenSdkErrorCode.authenticationRequired ||
    CitizenSdkErrorCode.permissionDenied => '需要完成授权',
    _ => '请稍后重试',
  };
  return '$action失败：$reason';
}

class OnchainPaymentException implements Exception {
  const OnchainPaymentException(this.code, this.message);

  final OnchainPaymentErrorCode code;
  final String message;

  @override
  String toString() {
    return 'OnchainPaymentException(${code.name}): $message';
  }
}

class OnchainPaymentDraft {
  const OnchainPaymentDraft({
    required this.toSs58Address,
    required this.amount,
    required this.symbol,
    required this.remark,
  });

  final String toSs58Address;
  final double amount;
  final String symbol;
  final String remark;
}
