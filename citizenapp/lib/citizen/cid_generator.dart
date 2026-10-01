// 公民 / 居民「人主体」CID 号客户端生成器 —— 全 App 唯一入口。
//
// 逐字节镜像 citizenchain `runtime/primitives/cid/generator.rs` 的**人主体码分支**
// (`is_person_code`:公民 CTZN / 居民 NATP)。人主体去地域化:
//   input  = "{accountId}|{institution}|{year}"        // 竖线字面量连接
//   n      = u64::from_le_bytes(blake2_256(input)[..8]) // 前 8 字节小端 → 无符号 u64
//   number = n % 1e12                                   // 12 位十进制号段(1e12/年)
//   high3  = number / 1e9  (0..=999)  → R5 = "CN" + high3(3 位补零)
//   low9   = number % 1e9             → N9 = low9(9 位补零)
// CTZN / NATP 均为 4 字符码、盈利策略 = Profit ⇒ 核心段用 M1(digit)校验位:
//   payload = R5 + institution + N9 + year
//   acc     = Σ (i+1) * alphabetIndex(payload[i])       // 见 checksum_char_m1
//   M1      = '0' + (acc % 10)
//   结果    = "{R5}-{institution}{M1}-{N9}-{year}"
//
// 号段撞号由链上 registry nonce 探测吸收;本地生成只做"首选候选号"。任何模块
// 禁止另拼一份人主体 CID 规则,一律调用本文件,靠金标 CN951-CTZN1-539598435-2026
// (`test/citizen/cid_generator_golden_test.dart`)钉死防跨语言漂移。

import 'dart:convert';
import 'dart:typed_data';

import 'package:polkadart/polkadart.dart' show Hasher;

/// 人主体机构码:公民。
const String kCidInstitutionCitizen = 'CTZN';

/// 人主体机构码:居民。
const String kCidInstitutionResident = 'NATP';

/// 校验位字母表(对齐 number.rs `CHECKSUM_ALPHABET`)。
const String _checksumAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// 人主体号段容量:12 位十进制 = 1e12/年。
final BigInt _numberModulus = BigInt.from(1000000000000);

/// R5 高 3 位 / N9 低 9 位分界:1e9。
final BigInt _highLowSplit = BigInt.from(1000000000);

/// 生成公民 / 居民「人主体」CID 号(链上自助占号首选候选号)。
///
/// [accountId] 必须为小写 `0x` + 64 位十六进制的账户文本(与链端 `public_key`
/// 输入逐字节一致,原样进 hash,不做大小写归一)。[institution] 取 `CTZN`(公民)
/// 或 `NATP`(居民)。[year] 为 4 位公历年份 YYYY。
String generateCitizenCid({
  required String accountId,
  required String institution,
  required int year,
}) {
  if (institution != kCidInstitutionCitizen &&
      institution != kCidInstitutionResident) {
    throw ArgumentError.value(
      institution,
      'institution',
      '人主体 CID 仅支持 CTZN(公民)/ NATP(居民)',
    );
  }
  if (year < 1000 || year > 9999) {
    throw ArgumentError.value(year, 'year', 'year 必须为 4 位公历年份 YYYY');
  }
  final yearText = year.toString();

  final input = '$accountId|$institution|$yearText';
  final digest = Hasher.blake2b256.hash(Uint8List.fromList(utf8.encode(input)));

  // 前 8 字节小端 → 无符号 u64。用 BigInt 承载,避免 Dart 有符号 int 在高位溢出。
  var n = BigInt.zero;
  for (var i = 7; i >= 0; i--) {
    n = (n << 8) | BigInt.from(digest[i]);
  }
  final number = n % _numberModulus;
  final high3 = (number ~/ _highLowSplit).toInt(); // 0..=999
  final low9 = (number % _highLowSplit).toInt();

  final r5 = 'CN${high3.toString().padLeft(3, '0')}';
  final n9 = low9.toString().padLeft(9, '0');

  final payload = '$r5$institution$n9$yearText';
  final m1 = _checksumCharM1(payload);

  return '$r5-$institution$m1-$n9-$yearText';
}

/// 4 字符布局盈利码(Profit)的 M1 校验位 —— 对齐 number.rs
/// `checksum_char_m1(payload, profit = true)`:`'0' + (acc % 10)`。
String _checksumCharM1(String payload) {
  final acc = _checksumAcc(payload);
  final zero = '0'.codeUnitAt(0);
  return String.fromCharCode(zero + (acc % 10));
}

/// 校验和累加器 —— 对齐 number.rs `checksum_acc`:
/// `Σ (idx+1) * alphabetIndex(ch)`,字母表外字符按索引 0 计。
int _checksumAcc(String payload) {
  var total = 0;
  for (var idx = 0; idx < payload.length; idx++) {
    final pos = _checksumAlphabet.indexOf(payload[idx]);
    total += (idx + 1) * (pos < 0 ? 0 : pos);
  }
  return total;
}
