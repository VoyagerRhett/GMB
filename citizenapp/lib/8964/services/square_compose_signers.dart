import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:citizenapp/8964/services/square_identity_state.dart';
import 'package:citizenapp/8964/services/square_publish_service.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/security/device_subkey.dart';

/// 广场公文、文章和视频共用的发布签名器。
///
/// 登录挑战 = 后端会话握手 → **P-256 硬件设备子钥静默签名**（不读 seed、不弹）。
/// 发布上链属于钱包账户签名：统一交给 CitizenSDK 按账户既定冷热模式完成；
/// 设备子钥与钱包账户签名模式相互独立。
class SquareComposeSigners {
  SquareComposeSigners({
    required this.context,
    required this.identity,
    DeviceSubkey? deviceSubkey,
  }) : _deviceSubkey = deviceSubkey ?? DeviceSubkey();

  final BuildContext context;
  final SquareIdentityState identity;
  final DeviceSubkey _deviceSubkey;

  Future<String> signLogin(
    SquareLoginContext loginContext,
    Uint8List loginMessage,
  ) async {
    final cidNumber = identity.cidNumber ?? '';
    if (cidNumber.isEmpty ||
        loginContext.cidNumber != cidNumber ||
        loginContext.accountId != identity.accountId) {
      throw const SquarePublishException('Cloudflare 登录挑战与当前发布身份不一致');
    }
    // 会话握手 = 非用户动权 → P-256 硬件子钥静默签名 signing_message(0x1B) 摘要，后端 ES256 验。
    // P-256 子钥按 CID 隔离，与冷热钱包签名方式无关。
    final raw = await _deviceSubkey.signRawHex(cidNumber, loginMessage);
    return '0x$raw';
  }

}
