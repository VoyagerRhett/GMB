/// 操作系统推送端点的中性产品值；不携带聊天、广场或账户业务状态。
final class AppPushToken {
  const AppPushToken({
    required this.provider,
    required this.token,
    required this.apnsEnvironment,
  });

  final String provider;
  final String token;
  final String? apnsEnvironment;

  String get registrationCacheValue =>
      '$provider|${apnsEnvironment ?? ''}|$token';
}
