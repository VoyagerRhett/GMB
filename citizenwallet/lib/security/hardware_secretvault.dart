import 'dart:convert';

import 'package:flutter/services.dart';

/// 硬件严档中的机密类型；名称直接对应 Substrate 密钥材料或 BIP-39 助记词。
enum HardwareSecretType {
  accountMiniSecret('account_mini_secret'),
  masterMiniSecret('master_mini_secret'),
  mnemonic('mnemonic');

  const HardwareSecretType(this.storageName);
  final String storageName;
}

/// 一条机密的不可歧义身份。AAD 必须包含这些字段，密文调换后解密必然失败。
final class HardwareSecretContext {
  HardwareSecretContext({
    required this.product,
    required this.scope,
    required this.secretType,
    this.accountId,
  }) {
    if (!_productPattern.hasMatch(product)) {
      throw ArgumentError.value(product, 'product', '产品标识格式无效');
    }
    if (!_scopePattern.hasMatch(scope)) {
      throw ArgumentError.value(scope, 'scope', '钱包作用域格式无效');
    }
    final value = accountId;
    if (value != null && !_accountIdPattern.hasMatch(value)) {
      throw ArgumentError.value(value, 'accountId', 'AccountId 格式无效');
    }
    if (secretType == HardwareSecretType.accountMiniSecret && value == null) {
      throw ArgumentError('账户 MiniSecretKey 必须绑定 AccountId');
    }
  }

  static final RegExp _productPattern = RegExp(r'^[a-z][a-z0-9]{2,31}$');
  static final RegExp _scopePattern = RegExp(r'^[a-z0-9._:-]{1,80}$');
  static final RegExp _accountIdPattern = RegExp(r'^0x[0-9a-f]{64}$');

  final String product;
  final String scope;
  final String? accountId;
  final HardwareSecretType secretType;

  /// 硬件密钥按产品和钱包作用域独立；同钱包多条密文可以共用一把硬件 KEK。
  String get keyScope => '$product:$scope';

  /// AAD 采用固定字段顺序与换行分隔；所有字段均经正则禁止换行，因而不可歧义。
  Uint8List associatedData() => Uint8List.fromList(
        utf8.encode(
          'GMB\n$product\n$scope\n${accountId ?? ''}\n${secretType.storageName}',
        ),
      );
}

enum HardwareSecretvaultAvailability {
  available,
  noStrongBiometric,
  unsupported,
}

/// 共享硬件严档金库。原生通道只接受字节数组，禁止以不可擦除 String 传递机密。
final class HardwareSecretvault {
  HardwareSecretvault({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'gmb/hardware_secretvault';
  final MethodChannel _channel;

  Future<HardwareSecretvaultAvailability> availability() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'securityStatus',
      );
      if (result?['strongBiometricEnrolled'] != true) {
        return HardwareSecretvaultAvailability.noStrongBiometric;
      }
      return result?['supported'] == true
          ? HardwareSecretvaultAvailability.available
          : HardwareSecretvaultAvailability.unsupported;
    } on PlatformException {
      return HardwareSecretvaultAvailability.unsupported;
    } on MissingPluginException {
      return HardwareSecretvaultAvailability.unsupported;
    }
  }

  Future<Uint8List> encrypt(
    HardwareSecretContext context,
    Uint8List plaintext,
  ) async {
    if (plaintext.isEmpty) {
      throw ArgumentError.value(plaintext, 'plaintext', '机密不能为空');
    }
    final aad = context.associatedData();
    try {
      final result = await _channel.invokeMethod<Uint8List>('encrypt', {
        'scope': context.keyScope,
        'associatedData': aad,
        'plaintext': plaintext,
      });
      if (result == null || result.isEmpty) {
        throw const HardwareSecretvaultException(
          'encryptFailed',
          '硬件金库返回空密文',
        );
      }
      return Uint8List.fromList(result);
    } on PlatformException catch (error) {
      throw HardwareSecretvaultException(
        error.code,
        error.message ?? error.code,
      );
    } finally {
      clearBytes(aad);
    }
  }

  Future<Uint8List> decrypt(
    HardwareSecretContext context,
    Uint8List ciphertext,
  ) async {
    if (ciphertext.isEmpty) {
      throw ArgumentError.value(ciphertext, 'ciphertext', '密文不能为空');
    }
    final aad = context.associatedData();
    try {
      final borrowed = await _channel.invokeMethod<Uint8List>('decrypt', {
        'scope': context.keyScope,
        'associatedData': aad,
        'ciphertext': ciphertext,
      });
      if (borrowed == null || borrowed.isEmpty) {
        throw const HardwareSecretvaultException(
          'decryptFailed',
          '硬件金库返回空明文',
        );
      }
      // Flutter 平台通道返回的 TypedData 由引擎所有，真机上可能是只读视图；这里只读
      // 取值并立即复制到本包拥有的可修改缓冲区。调用方可在 finally 中可靠清零返回值。
      // 禁止尝试清零 borrowed：对借用缓冲区写入会抛 UnsupportedError，并覆盖成功结果。
      return Uint8List.fromList(borrowed);
    } on PlatformException catch (error) {
      throw HardwareSecretvaultException(
        error.code,
        error.message ?? error.code,
      );
    } finally {
      clearBytes(aad);
    }
  }

  Future<void> deleteKey(
      {required String product, required String scope}) async {
    final context = HardwareSecretContext(
      product: product,
      scope: scope,
      secretType: HardwareSecretType.masterMiniSecret,
    );
    try {
      await _channel
          .invokeMethod<void>('deleteKey', {'scope': context.keyScope});
    } on PlatformException catch (error) {
      throw HardwareSecretvaultException(
        error.code,
        error.message ?? error.code,
      );
    }
  }

  Future<bool> containsKey(
      {required String product, required String scope}) async {
    final context = HardwareSecretContext(
      product: product,
      scope: scope,
      secretType: HardwareSecretType.masterMiniSecret,
    );
    try {
      return await _channel.invokeMethod<bool>(
            'containsKey',
            {'scope': context.keyScope},
          ) ??
          false;
    } on PlatformException catch (error) {
      throw HardwareSecretvaultException(
        error.code,
        error.message ?? error.code,
      );
    }
  }

  /// 清零调用方拥有的可修改字节缓冲区。
  ///
  /// 该方法故意不吞 [UnsupportedError]：把平台借用只读视图误当作自有机密属于所有权
  /// 错误，必须由测试暴露；生产调用点只允许传入本包返回的副本或调用方自己分配的数组。
  static void clearBytes(List<int> bytes) {
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = 0;
    }
  }
}

final class HardwareSecretvaultException implements Exception {
  const HardwareSecretvaultException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
