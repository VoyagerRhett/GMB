import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/qr/envelope.dart';

/// 扫码内容的路由分类结果。统一协议 QR_V1 下按 `k` 分派。
enum QrRouteType {
  /// 用户码 - 人/永久 CID(user_contact)
  userContact,

  /// 收款码 - 一笔收款请求(user_transfer)
  userTransfer,

  /// 冷钱包账户数据用途钥加密响应(account_data_key_response)
  accountDataKeyResponse,

  /// 无法识别。
  unknown,
}

/// 路由分析结果。
class QrRouteResult {
  const QrRouteResult({required this.type, required this.raw, this.envelope});

  final QrRouteType type;
  final String raw;

  /// 成功解析的 QR_V1 envelope。
  final QrEnvelope<QrBody>? envelope;
}

/// 统一 QR 码路由器。
///
/// 接收扫码原始字符串,返回 [QrRouteResult] 供上层页面分发处理。
class QrRouter {
  /// 分析扫码内容并返回路由结果。
  QrRouteResult route(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return QrRouteResult(type: QrRouteType.unknown, raw: raw);
    }

    // 1. 尝试 QR_V1 envelope
    if (text.startsWith('{')) {
      try {
        final env = QrEnvelope.parse(text);
        final type = switch (env.kind) {
          // 通用签名请求、响应和账户码由 CitizenSDK 解析；App 路由器只识别业务码。
          QrKind.signRequest || QrKind.signResponse || QrKind.accountIdCode =>
            QrRouteType.unknown,
          QrKind.userContact => QrRouteType.userContact,
          QrKind.userTransfer => QrRouteType.userTransfer,
          QrKind.accountDataKeyResponse => QrRouteType.accountDataKeyResponse,
        };
        return QrRouteResult(
          type: type,
          raw: raw,
          envelope: type == QrRouteType.unknown ? null : env,
        );
      } on FormatException {
        // 非规范 QR_V1 一律拒绝，不进入任何旧格式兜底。
      }
    }

    return QrRouteResult(type: QrRouteType.unknown, raw: raw);
  }
}
