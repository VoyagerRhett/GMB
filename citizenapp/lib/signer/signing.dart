// GMB 全仓签名消息唯一原语 —— Dart 镜像。
//
// canonical 真源 = citizenchain `primitives::sign::signing_message`:
//   message = blake2_256( GMB(3B) || op_tag(1B) || scale_payload )
// 其中 GMB = core_const::GMB(字节 0x47 0x4D 0x42 = "GMB")。
//
// 与账户派生原语(account_derivation.dart)的区别:签名消息 **不含** ss58 字节,
// 域前缀只有 GMB(3B) + op_tag(1B)。op_tag 命名空间 0x10-0x1F 为签名段,与派生段
// 0x00-0x0F 不重叠。
//
// 本文件无编译期保证与链端一致,靠金标向量
//   citizenchain/runtime/primitives/tests/fixtures/signing_domain_vectors.json
// 的副本逐字节断言(见 test/signer/signing_golden_test.dart),防跨语言漂移。
//
// 单源纪律:任何模块禁止本地拼 `GMB || op_tag || payload` 或另造版本化字符串域,
// 一律调用本文件的 signingMessage。全仓唯一允许的版本化协议标识是 `QR_V1`。

import 'dart:convert';
import 'dart:typed_data';

import 'package:polkadart/polkadart.dart' show Hasher;

// ── 签名 payload op_tag 注册表(0x10-0x1F),逐字节对齐 primitives::sign ──
//
// 0x10-0x14 治理/身份签名。
// 0x15-0x1A 业务签名段。

/// 公民身份上链确认(对齐 OP_SIGN_CITIZEN_IDENTITY)。
const int kOpSignCitizenIdentity = 0x10;

/// 匿名 CID 自助换绑：当前绑定账户对含创世、当前绑定、目标账户、绑定 revision 与
/// expires_at 的 `CidRebindAuthorization` 授权签名。
const int kOpSignCidRebind = 0x11;

/// 注册局代办首次占号：公民钱包对含创世、CID、目标账户、revision=0 与 expires_at
/// 的 `CidOccupyAuthorization` 授权签名。
const int kOpSignCidOccupy = 0x12;

/// 机构登记(对齐 OP_SIGN_INST)。
const int kOpSignInst = 0x13;

/// 机构/账户注销凭证(对齐 OP_SIGN_DEREGISTER)。
const int kOpSignDeregister = 0x14;

/// L3 支付(对齐 OP_SIGN_L3_PAY)。
const int kOpSignL3Pay = 0x15;

/// 链下批次结算(对齐 OP_SIGN_OFFCHAIN_BATCH)。
const int kOpSignOffchainBatch = 0x16;

/// L2 确认(对齐 OP_SIGN_L2_ACK)。
const int kOpSignL2Ack = 0x17;

/// 管理员激活(对齐 OP_SIGN_ACTIVATE_ADMIN)。
const int kOpSignActivateAdmin = 0x18;

/// 解密授权(对齐 OP_SIGN_DECRYPT)。
const int kOpSignDecrypt = 0x19;

/// 广场 BFF 登录挑战(对齐 OP_SIGN_SQUARE_LOGIN;链下 Worker 验签,设备子钥 ES256 签 digest)。
const int kOpSignSquareLogin = 0x1B;

/// 广场 BFF 设备子钥绑定(对齐 OP_SIGN_SQUARE_DEVICE_BIND；链下 Worker 验签，
/// 由当前 `account_id` 对应的 sr25519 账户密钥签名)。
const int kOpSignSquareDeviceBind = 0x1C;

/// 广场 BFF 账户敏感动作：注销/退订(对齐 OP_SIGN_SQUARE_ACTION；链下 Worker 验签，
/// 由当前 `account_id` 对应的 sr25519 账户密钥签名)。
const int kOpSignSquareAction = 0x1D;

/// 本机默认账户切换：由变化前的原默认账户签署完整目标账户顺序。
/// 只作本机动权校验，不包含 CID/绑定版本，也不提交链。
const int kOpSignSwitchDefaultAccount = 0x21;

/// 冷钱包账户数据用途钥加密交付：当前绑定账户签署精确 CID/绑定版本、用途、
/// 一次性会话公钥、nonce 与密文摘要。只作本机验签，不提交链。
const int kOpSignAccountDataKeyProvision = 0x22;

/// 钱包账户签名模式确认：本机私钥签署目标账户、`hot` 模式与一次性挑战。
/// 只用于 CitizenApp 本机重标验证，不提交链。
const int kOpSignWalletMode = 0x23;

/// 产品正式发布授权；CitizenApp 不签此域，仅镜像全仓签名真源。
const int kOpSignPublish = 0x24;

/// 注册局代办换绑：新钱包对完整 `CidRebindAuthorization` 的授权签名；载荷与自助
/// 换绑相同，签名域与自助换绑 0x11、首次占号 0x12 分离。
const int kOpSignCidAdminRebind = 0x1F;

// ── 二进制前缀域(0x18/0x19)──
//
// ACTIVATE_ADMIN / DECRYPT 不经 signingMessage 做 blake2 hash:冷钱包对整段
// 原始可解析 payload 直接 sr25519 签名,node 按字节偏移解析。其 op_tag
// (kOpSignActivateAdmin/kOpSignDecrypt)仅作 payload **前 4 字节**
// GMB(3B) || op_tag(1B) 二进制前缀。单源对齐 primitives::sign::
// binary_domain_prefix / BINARY_PREFIX_LEN。金标布局见
// test/signer/fixtures/binary_prefix_domain_vectors.json。

/// 二进制前缀域统一前缀长度 = GMB(3B) + op_tag(1B) = 4(对齐 BINARY_PREFIX_LEN)。
const int kBinaryPrefixLen = 4;

/// 管理员激活/解密载荷中的机构 CID 固定槽长度。
/// 与 runtime `CID_NUMBER_MAX_BYTES`/`ACTIVATE_ADMIN_CID_LEN` 唯一对齐。
const int kAdminCidSlotLength = 32;

/// 管理员原始签名载荷中的固定字段长度。
const int kSignerPublicKeyLength = 32;
const int kAdminNonceLength = 16;

/// 签名域分隔符 GMB(3 字节 ASCII),单源对齐 core_const::GMB。
const List<int> kGmbSignDomain = [0x47, 0x4D, 0x42]; // "GMB"

/// 构造二进制前缀域的 4 字节前缀 GMB || op_tag(0x18/0x19 用)。
///
/// 仅用于**原始字节签名**的二进制前缀域(ACTIVATE_ADMIN/DECRYPT),不做 hash。
/// 哈希域(0x10-0x17)请改调 [signingMessage]。对齐
/// primitives::sign::binary_domain_prefix。
Uint8List binaryDomainPrefix(int opTag) {
  return Uint8List.fromList([...kGmbSignDomain, opTag & 0xFF]);
}

/// 构造机构管理员激活原始签名载荷。
///
/// 布局唯一镜像 runtime `primitives::sign::activate_admin_payload`：
/// `GMB || 0x18 || cid_number(32B 右补零) || institution_code(4B) || kind(1B)
/// || signer_public_key(32B) || timestamp_le(8B) || nonce(16B)`。
Uint8List activateAdminPayload({
  required String cidNumber,
  required List<int> institutionCode,
  required int kind,
  required List<int> signerPublicKey,
  required int timestamp,
  required List<int> nonce,
}) {
  if (institutionCode.length != 4) {
    throw ArgumentError('institutionCode 必须为 4 字节');
  }
  if (kind < 0 || kind > 0xff) {
    throw ArgumentError.value(kind, 'kind', 'kind 必须为 u8');
  }
  return _adminBinaryPayload(
    opTag: kOpSignActivateAdmin,
    cidNumber: cidNumber,
    fixedFields: [
      ...institutionCode,
      kind,
      ..._requireFixedBytes(
        signerPublicKey,
        kSignerPublicKeyLength,
        'signerPublicKey',
      ),
    ],
    timestamp: timestamp,
    nonce: nonce,
  );
}

/// 构造机构管理员解密原始签名载荷。
///
/// 布局唯一镜像 runtime `primitives::sign::decrypt_admin_payload`：
/// `GMB || 0x19 || cid_number(32B 右补零) || signer_public_key(32B)
/// || timestamp_le(8B) || nonce(16B)`。
Uint8List decryptAdminPayload({
  required String cidNumber,
  required List<int> signerPublicKey,
  required int timestamp,
  required List<int> nonce,
}) {
  return _adminBinaryPayload(
    opTag: kOpSignDecrypt,
    cidNumber: cidNumber,
    fixedFields: _requireFixedBytes(
      signerPublicKey,
      kSignerPublicKeyLength,
      'signerPublicKey',
    ),
    timestamp: timestamp,
    nonce: nonce,
  );
}

Uint8List _adminBinaryPayload({
  required int opTag,
  required String cidNumber,
  required List<int> fixedFields,
  required int timestamp,
  required List<int> nonce,
}) {
  final cidBytes = utf8.encode(cidNumber);
  if (cidBytes.isEmpty || cidBytes.length > kAdminCidSlotLength) {
    throw ArgumentError('机构 CID 的 UTF-8 长度必须为 1..$kAdminCidSlotLength 字节');
  }
  final nonceBytes = _requireFixedBytes(nonce, kAdminNonceLength, 'nonce');
  return Uint8List.fromList([
    ...binaryDomainPrefix(opTag),
    ...cidBytes,
    ...List<int>.filled(kAdminCidSlotLength - cidBytes.length, 0),
    ...fixedFields,
    ...u64Le(timestamp),
    ...nonceBytes,
  ]);
}

List<int> _requireFixedBytes(List<int> value, int length, String name) {
  if (value.length != length) {
    throw ArgumentError('$name 必须为 $length 字节');
  }
  return value;
}

/// 全仓签名消息唯一原语:`blake2_256(GMB || op_tag || scalePayload)`。
///
/// [opTag] 取本文件 kOpSign* 常量;[scalePayload] 为调用方对业务字段做的
/// SCALE 编码字节(定长字段直接拼接即等价 SCALE)。返回 32 字节摘要。
Uint8List signingMessage({
  required int opTag,
  required List<int> scalePayload,
}) {
  final input = <int>[...kGmbSignDomain, opTag & 0xFF, ...scalePayload];
  return Hasher.blake2b256.hash(Uint8List.fromList(input));
}

// ── SCALE 编码原语(签名 payload 拼装用),逐字节对齐链端/Worker ──

/// SCALE 编码字符串:`compact(len) || utf8(value)`。
Uint8List scaleString(String value) {
  final bytes = utf8.encode(value);
  return Uint8List.fromList([..._scaleCompact(bytes.length), ...bytes]);
}

/// u64 小端 8 字节(时间戳等定长字段)。
Uint8List u64Le(int value) {
  if (value < 0) {
    throw ArgumentError.value(value, 'value', 'u64 不允许负数');
  }
  final out = Uint8List(8);
  var current = value;
  for (var i = 0; i < out.length; i++) {
    out[i] = current & 0xff;
    current >>= 8;
  }
  return out;
}

/// SCALE compact 编码非负整数(支持到 2^30-1)。
List<int> _scaleCompact(int value) {
  if (value < 0) {
    throw ArgumentError.value(value, 'value', 'SCALE compact 不允许负数');
  }
  if (value < 1 << 6) {
    return [value << 2];
  }
  if (value < 1 << 14) {
    final v = (value << 2) | 0x01;
    return [v & 0xff, (v >> 8) & 0xff];
  }
  if (value < 1 << 30) {
    final v = (value << 2) | 0x02;
    return [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  }
  throw ArgumentError.value(value, 'value', 'SCALE compact 超出本地支持范围');
}
