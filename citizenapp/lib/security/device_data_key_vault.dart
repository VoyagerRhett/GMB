import 'dart:convert';
import 'package:flutter/services.dart';

/// CitizenApp 本机设备数据钥金库异常。
///
/// 这里的“设备数据钥”只负责静默封装 Chat、MLS、附件和通讯录用途钥，绝不保存、
/// 返回或替代钱包账户 child mini-secret。
class DeviceDataKeyVaultException implements Exception {
  const DeviceDataKeyVaultException(this.message);

  final String message;

  @override
  String toString() => 'DeviceDataKeyVaultException: $message';
}

/// 硬件绑定、不可导出的本机数据钥封装边界。
///
/// - Android 使用独立 Android Keystore AES-GCM 钥；
/// - iOS 使用独立 Secure Enclave P-256 ECIES 钥；
/// - 两端都不设置生物识别门禁，日常 Chat/通讯录只能走本边界静默解封；
/// - 钱包账户私钥始终由 CitizenSDK 自有金库持有，本边界无法读取。
class DeviceDataKeyVault {
  DeviceDataKeyVault({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'citizenapp/device_data_key_vault';

  final MethodChannel _channel;

  /// 用设备硬件钥封装一把用途钥。AAD 必须包含完整绑定与用途，防止跨域替换。
  Future<String> seal({
    required int walletIndex,
    required Uint8List plaintext,
    required Uint8List aad,
  }) async {
    if (walletIndex < 0 || plaintext.isEmpty || aad.isEmpty) {
      throw const DeviceDataKeyVaultException('设备数据钥封装参数不合法');
    }
    try {
      final result = await _channel.invokeMethod<String>(
        'seal',
        <String, dynamic>{
          'walletIndex': walletIndex,
          'plaintext': base64Encode(plaintext),
          'aad': base64Encode(aad),
        },
      );
      if (result == null || result.isEmpty) {
        throw const DeviceDataKeyVaultException('设备数据钥封装结果为空');
      }
      return result;
    } on PlatformException catch (error) {
      throw DeviceDataKeyVaultException(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      throw DeviceDataKeyVaultException(error.message ?? '设备数据钥原生通道不可用');
    }
  }

  /// 静默解封一把用途钥；AAD 不匹配、硬件钥失效或设备尚不可用时一律失败关闭。
  Future<Uint8List> open({
    required int walletIndex,
    required String blob,
    required Uint8List aad,
  }) async {
    if (walletIndex < 0 || blob.isEmpty || aad.isEmpty) {
      throw const DeviceDataKeyVaultException('设备数据钥解封参数不合法');
    }
    try {
      final result = await _channel.invokeMethod<String>(
        'open',
        <String, dynamic>{
          'walletIndex': walletIndex,
          'blob': blob,
          'aad': base64Encode(aad),
        },
      );
      if (result == null || result.isEmpty) {
        throw const DeviceDataKeyVaultException('设备数据钥解封结果为空');
      }
      return Uint8List.fromList(base64Decode(result));
    } on FormatException catch (error) {
      throw DeviceDataKeyVaultException('设备数据钥明文格式损坏：$error');
    } on PlatformException catch (error) {
      throw DeviceDataKeyVaultException(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      throw DeviceDataKeyVaultException(error.message ?? '设备数据钥原生通道不可用');
    }
  }

  /// 整只热钱包删除时删除其设备封装硬件钥；失去硬件钥后旧 blob 必须不可恢复。
  Future<void> delete(int walletIndex) async {
    if (walletIndex < 0) {
      throw const DeviceDataKeyVaultException('walletIndex 不合法');
    }
    try {
      await _channel.invokeMethod<void>(
        'delete',
        <String, dynamic>{'walletIndex': walletIndex},
      );
    } on PlatformException catch (error) {
      throw DeviceDataKeyVaultException(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      throw DeviceDataKeyVaultException(error.message ?? '设备数据钥原生通道不可用');
    }
  }

  /// 只回读指定钱包的设备硬件钥是否仍存在；绝不创建新钥。
  Future<bool> contains(int walletIndex) async {
    if (walletIndex < 0) {
      throw const DeviceDataKeyVaultException('walletIndex 不合法');
    }
    try {
      final exists = await _channel.invokeMethod<bool>(
        'contains',
        <String, dynamic>{'walletIndex': walletIndex},
      );
      if (exists == null) {
        throw const DeviceDataKeyVaultException('设备数据钥存在性复核失败');
      }
      return exists;
    } on PlatformException catch (error) {
      throw DeviceDataKeyVaultException(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      throw DeviceDataKeyVaultException(error.message ?? '设备数据钥原生通道不可用');
    }
  }
}
