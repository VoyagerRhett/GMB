import 'package:citizen_sdk/citizen_sdk.dart';

/// 只将SDK已解析的公开事实映射到原页面流向，不解析QR_V1或提供拒绝后的第二入口。
enum QrRouteType { userContact, userTransfer, accountDataKeyResponse, unknown }

class QrRouteResult {
  const QrRouteResult({required this.type, required this.raw, this.document});
  final QrRouteType type;
  final String raw;
  final CitizenQrDocument? document;
}

class QrRouter {
  QrRouteResult route({required String raw, CitizenQrDocument? document}) {
    final type = switch (document?.kind) {
      CitizenQrKind.userContact => QrRouteType.userContact,
      CitizenQrKind.userTransfer => QrRouteType.userTransfer,
      CitizenQrKind.accountDataKeyResponse => QrRouteType.accountDataKeyResponse,
      CitizenQrKind.signRequest || CitizenQrKind.signResponse ||
      CitizenQrKind.accountId || null => QrRouteType.unknown,
    };
    return QrRouteResult(
      type: type, raw: raw,
      document: type == QrRouteType.unknown ? null : document,
    );
  }
}
