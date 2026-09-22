import 'package:citizen_sdk/citizen_sdk.dart';
import 'dart:math';
import 'dart:typed_data';


/// 扫码支付 Step 2c-i:**L3 扫码支付意图**(`NodePaymentIntent`)。
///
///
/// - 与 `citizenchain/node/src/transaction/offchain_transaction/ledger.rs::NodePaymentIntent` 字段顺序
///   与字节布局**严格一致**,否则 SCALE 编解码跨端不对称、签名消息哈希不匹配、
///   节点侧 `sr25519_verify` 必然失败。
/// - L3 客户端(CitizenApp)构造本对象 → `scaleEncode()` 得定长 204 字节 →
///   `signingHash()` 得 32 字节摘要 → 用本人 sr25519 私钥签名 → 得 64 字节签名 →
///   通过 `offchain_submitPayment(intent_hex, sig_hex)` 提交清算行节点。
/// - 字段语义与单位:
///     - 所有地址(`payer/payerBank/recipient/recipientBank`)是 `AccountId32`
///       32 字节原始 publicKey。
///     - `amount` / `fee` 以**分**为单位。
///     - `nonce` 单调递增,从节点 `offchain_queryNextNonce` 取。
///     - `expiresAt` 是链上**块高**(block number),runtime `execute_clearing_bank_batch`
///       会校验 `now <= expires_at`;CitizenApp 端设为"当前块高 + 合理缓冲"(例如
///       100 块)。Step 2c-i 暂由调用方传入,后续可 wrap 成自动补充。
///     - `txId` 是 L3 本地生成的 32 字节随机数,作为本笔支付唯一标识 + 防重放键。
///
/// 布局(固定 204 字节):
/// ```
/// [0..32)    tx_id (H256)
/// [32..64)   payer (AccountId32)
/// [64..96)   payer_bank
/// [96..128)  recipient
/// [128..160) recipient_bank
/// [160..176) amount (u128 little-endian)
/// [176..192) fee    (u128 little-endian)
/// [192..200) nonce  (u64 little-endian)
/// [200..204) expires_at (u32 little-endian)
/// ```
class NodePaymentIntent {
  NodePaymentIntent({
    required this.txId,
    required this.payer,
    required this.payerBankCid,
    required this.recipient,
    required this.recipientBankCid,
    required this.amount,
    required this.fee,
    required this.nonce,
    required this.expiresAt,
  })  : assert(txId.length == 32, 'tx_id 必须 32 字节'),
        assert(payer.length == 32, 'payer 必须 32 字节'),
        assert(payerBankCid.isNotEmpty && payerBankCid.length <= 32,
            'payer_bank_cid 长度必须 1..32'),
        assert(recipient.length == 32, 'recipient 必须 32 字节'),
        assert(recipientBankCid.isNotEmpty && recipientBankCid.length <= 32,
            'recipient_bank_cid 长度必须 1..32'),
        assert(amount >= BigInt.zero, 'amount 不得为负'),
        assert(fee >= BigInt.zero, 'fee 不得为负'),
        assert(nonce >= BigInt.zero, 'nonce 不得为负'),
        assert(
            expiresAt >= 0 && expiresAt <= 0xFFFFFFFF, 'expires_at 必须 u32 范围');

  final Uint8List txId;
  final Uint8List payer;

  /// 付款方绑定清算行 CID(机构唯一永久主键);SCALE = Compact(len)||bytes。
  final Uint8List payerBankCid;
  final Uint8List recipient;

  /// 收款方绑定清算行 CID。
  final Uint8List recipientBankCid;
  final BigInt amount;
  final BigInt fee;
  final BigInt nonce;
  final int expiresAt;

  /// SCALE 编码(变长:bank 字段为 CID = Compact(len)||bytes,与 runtime
  /// `InstitutionCidNumber = BoundedVec<u8>` 逐字节等价)。
  Uint8List scaleEncode() {
    // 运行时强制 CID 长度不变量:assert 在 release 被裁剪,而 CID 来自扫码原始输入,
    // 编码进签名前必须显式校验,不能只靠调用方前置检查兜底。
    if (payerBankCid.isEmpty || payerBankCid.length > 32) {
      throw ArgumentError('payerBankCid 长度须 1..=32,实际 ${payerBankCid.length}');
    }
    if (recipientBankCid.isEmpty || recipientBankCid.length > 32) {
      throw ArgumentError(
          'recipientBankCid 长度须 1..=32,实际 ${recipientBankCid.length}');
    }
    final out = BytesBuilder(copy: false);
    out.add(txId);
    out.add(payer);
    out.add(_compactU32(payerBankCid.length));
    out.add(payerBankCid);
    out.add(recipient);
    out.add(_compactU32(recipientBankCid.length));
    out.add(recipientBankCid);
    out.add(_u128Le(amount));
    out.add(_u128Le(fee));
    out.add(_u64Le(nonce));
    out.add(_u32Le(BigInt.from(expiresAt)));
    return out.toBytes();
  }

  /// 待签名哈希:`blake2_256(GMB || OP_SIGN_L3_PAY(0x15) || scaleEncode())`。
  ///
  /// 经全仓签名唯一原语 [CitizenSigning.encodePayload] 构造,逐字节对齐链端
  /// `primitives::sign::signing_message(OP_SIGN_L3_PAY, SCALE(intent))`。
  Future<Uint8List> signingHash() =>
      CitizenSigning.encodePayload(CitizenSigningPayload.message(
        opTag: kOpSignL3Pay, scalePayload: scaleEncode(),
      ));

  /// 生成一个加密随机的 32 字节 `tx_id`,用作本笔支付的唯一标识 + 防重放键。
  ///
  /// `dart:math.Random.secure()` 在桌面/移动端均由 OS CSPRNG 提供。调用方不需要
  /// 自行维护熵源。
  static Uint8List randomTxId() {
    final rng = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }

  /// 按 runtime `fee_config::calc_fee` 语义计算手续费(分)。
  ///
  /// 公式:`fee = max(round(amount * rate_bp / 10_000), min_fee_fen)`,四舍五入
  /// 规则:`amount * rate_bp % 10_000 >= 5_000` 时进位。单位均为**分**。
  static BigInt calcFeeFen({
    required BigInt amountFen,
    required int rateBp,
    required int minFeeFen,
  }) {
    if (rateBp <= 0) {
      throw ArgumentError('rateBp 必须 > 0(清算行费率未设置时 RPC 返回 0)');
    }
    if (amountFen <= BigInt.zero) {
      throw ArgumentError('amountFen 必须 > 0');
    }
    final numerator = amountFen * BigInt.from(rateBp);
    final denom = BigInt.from(10000);
    final quotient = numerator ~/ denom;
    final remainder = numerator % denom;
    final rounded =
        remainder >= BigInt.from(5000) ? quotient + BigInt.one : quotient;
    final minFen = BigInt.from(minFeeFen);
    return rounded >= minFen ? rounded : minFen;
  }
}

/// SCALE `Compact<u32>` 编码。CID 长度 < 64 → 单字节 `(n<<2)`。
Uint8List _compactU32(int n) {
  if (n < 0) throw ArgumentError('长度不得为负:$n');
  if (n <= 0x3F) {
    return Uint8List.fromList([n << 2]);
  } else if (n <= 0x3FFF) {
    final v = (n << 2) | 0x01;
    return Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);
  } else if (n <= 0x3FFFFFFF) {
    final v = (n << 2) | 0x02;
    return Uint8List.fromList(
        [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  }
  throw ArgumentError('长度过大,超出单/双/四字节 Compact:$n');
}

Uint8List _u32Le(BigInt v) {
  final out = Uint8List(4);
  var x = v;
  for (var i = 0; i < 4; i++) {
    out[i] = (x & BigInt.from(0xFF)).toInt();
    x = x >> 8;
  }
  return out;
}

Uint8List _u64Le(BigInt v) {
  final out = Uint8List(8);
  var x = v;
  for (var i = 0; i < 8; i++) {
    out[i] = (x & BigInt.from(0xFF)).toInt();
    x = x >> 8;
  }
  return out;
}

Uint8List _u128Le(BigInt v) {
  final out = Uint8List(16);
  var x = v;
  for (var i = 0; i < 16; i++) {
    out[i] = (x & BigInt.from(0xFF)).toInt();
    x = x >> 8;
  }
  return out;
}

/// hex utils(含 `0x` 前缀 decode + encode)。
String bytesToHex(Uint8List bytes) {
  final buf = StringBuffer('0x');
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

Uint8List hexToBytes(String hex) {
  final text = hex.startsWith('0x') ? hex.substring(2) : hex;
  if (text.length.isOdd) {
    throw FormatException('hex 长度必须偶数:$hex');
  }
  final out = Uint8List(text.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(text.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
