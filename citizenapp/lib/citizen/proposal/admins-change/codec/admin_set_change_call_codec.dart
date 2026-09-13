import 'dart:convert';

import 'package:citizenapp/citizen/shared/pallet_registry.dart';
import 'dart:typed_data';

import 'package:polkadart/scale_codec.dart' show ByteOutput, CompactBigIntCodec;
import 'package:citizenapp/citizen/proposal/admins-change/codec/account_id_codec.dart';
import 'package:citizenapp/citizen/proposal/admins-change/models/admin_account.dart';
import 'package:citizenapp/citizen/shared/institution_code_label.dart';

class PersonalAdminsChangeCallCodec {
  PersonalAdminsChangeCallCodec._();

  static const int personalAdminsPalletIndex = PalletRegistry.personalAdminsPallet;
  static const int proposePersonalAdminsChangeCallIndex =
      PalletRegistry.proposePersonalAdminSetChangeCall;

  static Uint8List build({
    required String institutionCode,
    required int adminKind,
    required Uint8List accountId,
    required List<AdminPerson> admins,
    required int newThreshold,
  }) {
    if (accountId.length != 32) {
      throw ArgumentError('accountId 必须为 32 字节');
    }
    if (institutionCode != 'PMUL' || adminKind != 2) {
      throw ArgumentError('机构管理员由 entity 任职结果管理；本调用只允许个人多签');
    }
    if (newThreshold <= 0) {
      throw ArgumentError('newThreshold 必须大于 0');
    }
    final output = ByteOutput();
    output.pushByte(personalAdminsPalletIndex);
    output.pushByte(proposePersonalAdminsChangeCallIndex);
    // institution_code: [u8;4]
    output.write(
        Uint8List.fromList(InstitutionCodeLabel.codeBytes(institutionCode)));
    output.write(accountId);
    output.write(CompactBigIntCodec.codec.encode(BigInt.from(admins.length)));
    for (final admin in admins) {
      final bytes = AdminAccountIdCodec.fromAccountIdText(admin.account_id);
      if (bytes.length != 32) {
        throw ArgumentError('管理员公钥必须为 32 字节');
      }
      output.write(bytes);
      // 统一 Admin 恒带公民 CID（个人多签为空 → Compact(0)）。
      final cidBytes = utf8.encode(admin.cid_number);
      output
          .write(CompactBigIntCodec.codec.encode(BigInt.from(cidBytes.length)));
      output.write(Uint8List.fromList(cidBytes));
      _writeName(output, admin.family_name, 'family_name');
      _writeName(output, admin.given_name, 'given_name');
    }
    final thresholdBytes = Uint8List(4);
    ByteData.sublistView(thresholdBytes)
        .setUint32(0, newThreshold, Endian.little);
    output.write(thresholdBytes);
    return output.toBytes();
  }

  static void _writeName(ByteOutput output, String value, String field) {
    final bytes = utf8.encode(value.trim());
    if (bytes.isEmpty || bytes.length > 128) {
      throw ArgumentError('$field 长度必须在 1..=128 字节');
    }
    output.write(CompactBigIntCodec.codec.encode(BigInt.from(bytes.length)));
    output.write(Uint8List.fromList(bytes));
  }
}
