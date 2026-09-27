import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenwallet/chain/chain_constants.dart';
import 'package:citizenwallet/signer/action_labels.dart';
import 'package:citizenwallet/signer/field_labels.dart';

void main() {
  group('action labels', () {
    test('已登记 action code 必须有中文动作名', () {
      for (final entry in actionKeyByCode.entries) {
        expect(
          actionLabelForDecodedAction(entry.value),
          isNotNull,
          reason: '0x${entry.key.toRadixString(16)} 缺少中文动作名',
        );
      }
      expect(actionLabelForQrAction(9), '广场账户动作签名');
      expect(actionLabelForQrAction(0x7fff), isNull);
    });
  });

  group('fieldLabelText', () {
    test('公民签名确认(citizen_identity)全部 reviewFields key 有中文标签', () {
      const keys = [
        'cid_number',
        'account_id',
        'valid_range',
        'citizen_status',
        'residence',
      ];
      for (final key in keys) {
        expect(hasFieldLabel(key), isTrue, reason: key);
      }
    });

    test('公民身份上链交易(register_voting_identity)全部 reviewFields key 有中文标签', () {
      const keys = [
        'actor_cid_number',
        'actor_role_code',
        'cid_number',
        'account_id',
        'valid_range',
        'citizen_status',
        'residence',
      ];
      for (final key in keys) {
        expect(hasFieldLabel(key), isTrue, reason: key);
      }
    });

    test('公民参选身份上链交易全部 reviewFields key 有中文标签', () {
      const keys = [
        'actor_cid_number',
        'identity_level',
        'cid_number',
        'account_id',
        'valid_range',
        'citizen_status',
        'residence',
        'birth_place',
        'family_name',
        'given_name',
        'citizen_sex',
      ];
      for (final key in keys) {
        expect(hasFieldLabel(key), isTrue, reason: key);
      }
    });

    test('公民身份字段翻译正确', () {
      expect(fieldLabelText('actor_cid_number'), '操作机构CID');
      expect(fieldLabelText('actor_role_code'), '操作岗位码');
      expect(fieldLabelText('account_id'), '账户');
      expect(fieldLabelText('valid_range'), '护照有效期');
      expect(fieldLabelText('citizen_status'), '身份状态');
      expect(fieldLabelText('residence'), '居住地');
      expect(fieldLabelText('birth_place'), '出生地');
      expect(fieldLabelText('family_name'), '姓');
      expect(fieldLabelText('given_name'), '名');
      expect(fieldLabelText('citizen_sex'), '公民性别');
    });

    test('机构协议新增字段翻译正确', () {
      expect(fieldLabelText('institution_account_id'), '机构账户');
      expect(fieldLabelText('account_names'), '机构账户名称');
      expect(fieldLabelText('effective_at'), '生效时间戳');
    });

    test('链上资产全部 reviewFields key 有中文标签', () {
      const keys = [
        'actor_cid_number',
        'execution_account_id',
        'asset_id',
        'asset_class',
        'asset_name',
        'asset_symbol',
        'asset_description',
        'decimals',
        'initial_supply_raw',
        'amount_raw',
        'sender_account_id',
        'recipient_account_id',
        'account_id',
        'reason_hash',
      ];
      for (final key in keys) {
        expect(hasFieldLabel(key), isTrue, reason: key);
      }
    });

    test('amount_ 金额字段标签走注册表,无英文兜底', () {
      // 历史上 `amount_` 前缀规则把 `amount_yuan` 误拆成「yuan金额」；
      // 现全部走生成表,未登记的 amount_* 一律拒绝,不再泄漏英文 key。
      expect(fieldLabelText('amount_yuan'), '金额');
      expect(fieldLabelText('amount_raw'), '资产数量(raw)');
      expect(fieldLabelTextOrNull('amount_'), isNull);
      expect(fieldLabelTextOrNull('amount_主账户'), isNull);
    });

    test('未登记 key 不允许生成展示兜底', () {
      expect(fieldLabelTextOrNull('never_registered_key'), isNull);
      expect(hasFieldLabel('never_registered_key'), isFalse);
      expect(() => fieldLabelText('never_registered_key'), throwsStateError);
    });
  });

  group('fieldValueText', () {
    test('approve 转换为赞成/反对', () {
      expect(fieldValueText('approve', 'true'), '赞成');
      expect(fieldValueText('approve', 'false'), '反对');
    });

    test('其他 key 原样返回', () {
      expect(fieldValueText('residence', '11 / 01 / 001'), '11 / 01 / 001');
    });

    test('账户字段 hex 统一转 SS58 展示,公钥/哈希保持 0x hex', () {
      const hex =
          '0x9c0c5bc3b65f2b1aeecec2a0e70e6f0ef3f2dc8d59c12a9fa79ca88e3f2c82a3';
      final bytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        bytes[i] = int.parse(hex.substring(2 + i * 2, 4 + i * 2), radix: 16);
      }
      final expectedSs58 = Keyring().encodeAddress(
        bytes,
        ChainConstants.ss58Prefix,
      );

      // `account_id` / `*_account_id` 账户字段一律 SS58 展示。
      expect(fieldValueText('account_id', hex), expectedSs58);
      expect(fieldValueText('recipient_account_id', hex), expectedSs58);
      expect(fieldValueText('beneficiary_account_id', hex), expectedSs58);
      expect(fieldValueText('institution_account_id', hex), expectedSs58);
      expect(expectedSs58, isNot(startsWith('0x')));

      // 明确标注的公钥、哈希保持 0x hex,不转 SS58。
      expect(fieldValueText('signer_public_key', hex), hex);
      expect(fieldValueText('actor_public_key', hex), hex);
      expect(fieldValueText('reason_hash', hex), hex);
    });
  });
}
