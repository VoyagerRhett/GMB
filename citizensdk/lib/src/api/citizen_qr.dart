import 'dart:typed_data';

/// CitizenSDK 当前唯一接受的 QR_V1 区块链二维码类型。
enum CitizenQrKind {
  signRequest(1),
  signResponse(2),
  userTransfer(4),
  accountId(5);

  const CitizenQrKind(this.value);
  final int value;
}

/// Rust 已严格解析的统一公开二维码结构，不是可提交的授权凭证。
///
/// 不同 kind 只含所属字段：签名请求含 action/reviewPayload，响应含 signature，
/// 收款含 amount/symbol/memo/bankCidNumber，账户码只含 accountId。
/// 业务只读取这些公开字段，不自行解析 QR_V1 短键或构造待签字节。
final class CitizenQrDocument {
  CitizenQrDocument({
    required this.kind,
    required this.canonicalText,
    this.requestId,
    this.expiresAt,
    this.action,
    this.signerAccountId,
    Uint8List? reviewPayload,
    Uint8List? signature,
    this.accountId,
    this.amount,
    this.symbol,
    this.memo,
    this.bankCidNumber,
    this.signRequest,
  }) : reviewPayload = reviewPayload == null
           ? null
           : Uint8List.fromList(reviewPayload).asUnmodifiableView(),
       signature = signature == null
           ? null
           : Uint8List.fromList(signature).asUnmodifiableView();

  final CitizenQrKind kind;
  final String canonicalText;
  final String? requestId;
  final int? expiresAt;
  final int? action;
  final String? signerAccountId;
  final Uint8List? reviewPayload;
  final Uint8List? signature;
  final String? accountId;
  final String? amount;
  final String? symbol;
  final String? memo;
  final String? bankCidNumber;

  /// 安全签名结果中的原请求规范文本；普通 parse 文档不含此字段。
  final String? signRequest;
}

/// ZXing-C++ 生成的 8 位灰度 QR Code Model 2 图像。
final class CitizenQrImage {
  CitizenQrImage({
    required this.width,
    required this.height,
    required Uint8List luminance,
  }) : luminance = Uint8List.fromList(luminance).asUnmodifiableView();

  final int width;
  final int height;
  final Uint8List luminance;
}

/// SDK 原生审阅确认及设备认证完成后的完整扫码签名结果。
/// QR 图像和 canonicalText 由同一响应组成，没有私钥、待签字节或内部句柄。
final class CitizenQrSigned {
  CitizenQrSigned({
    required this.canonicalText,
    required this.qrImage,
    required this.requestId,
    required this.signerAccountId,
    required Uint8List signature,
    required this.signRequest,
  }) : signature = Uint8List.fromList(signature).asUnmodifiableView();

  final String canonicalText;
  final CitizenQrImage qrImage;
  final String requestId;
  final String signerAccountId;
  final Uint8List signature;
  final String signRequest;
}

/// 唯一 QR_V1 协议、扫码会话及 ZXing-C++ 图像模块。
///
/// QR-only 不创建钱包、金库或轻节点；所有过期判断由 Core 系统时钟完成。
/// 安全扫码签名使用 signing.signQrRequest，SDK 内部完成不可变审阅、
/// 用户确认和设备安全签名，不向调用方开放拆开的待签字节或响应拼装。
abstract interface class CitizenQr {
  /// SDK 原生摄像头预览；单码由 ZXing-C++ 识别并交 Rust 严格解析。
  /// 后台、关闭、权限拒绝和设备断开结束本次扫描，不自动恢复。
  Future<CitizenQrDocument> scan();

  Future<CitizenQrDocument> parse(String text);

  Future<String> createSignRequest({
    required int action,
    required String signerAccountId,
    required Uint8List reviewPayload,
    int ttlSeconds = 120,
  });

  /// 只在请求绑定验签、过期和单次消费全部通过后返回准确 64 字节签名。
  Future<Uint8List> consumeSignResponse(String signResponse);

  Future<bool> cancelSignRequest(String requestId);
  Future<String> encodeAccountId(String accountId);
  Future<String> encodeUserTransfer({
    required String requestId,
    required int expiresAt,
    required String accountId,
    required String amount,
    required String symbol,
    String memo = '',
    required String bankCidNumber,
  });

  /// 既有图片输入同样返回 Rust 文档，不暴露未经解析的扫描文本。
  Future<CitizenQrDocument> decodeLuminance({
    required Uint8List data,
    required int width,
    required int height,
    required int rowStride,
  });

  Future<CitizenQrImage> encode(String text, {int scale = 4});
}
