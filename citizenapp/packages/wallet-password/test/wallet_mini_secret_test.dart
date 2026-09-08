import 'package:flutter_test/flutter_test.dart';
import 'package:gmb_wallet_password/wallet_mini_secret.dart';
import 'package:gmb_wallet_password/wallet_password.dart';

void main() {
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  test('相同助记词与 password 派生逐字节稳定，password 改变即得到不同结果', () async {
    final first = await WalletMiniSecret.fromMnemonic(
      mnemonic,
      password: '安全密码A1!',
    );
    final second = await WalletMiniSecret.fromMnemonic(
      mnemonic,
      password: '安全密码A1!',
    );
    final different = await WalletMiniSecret.fromMnemonic(
      mnemonic,
      password: '安全密码A2!',
    );
    try {
      expect(first, hasLength(32));
      expect(second, orderedEquals(first));
      expect(different, isNot(orderedEquals(first)));
    } finally {
      WalletMiniSecret.clear(first);
      WalletMiniSecret.clear(second);
      WalletMiniSecret.clear(different);
    }
  });

  test('空 password 保持既有 Substrate BIP-39 向量', () async {
    final miniSecret = await WalletMiniSecret.fromMnemonic(mnemonic);
    try {
      expect(
        miniSecret,
        orderedEquals(<int>[
          0x4e,
          0xd8,
          0xd4,
          0xb1,
          0x76,
          0x98,
          0xdd,
          0xea,
          0xa1,
          0xf1,
          0x55,
          0x9f,
          0x15,
          0x2f,
          0x87,
          0xb5,
          0xd4,
          0x72,
          0xf7,
          0x25,
          0xca,
          0x86,
          0xd3,
          0x41,
          0xbd,
          0x02,
          0x76,
          0xf1,
          0xb6,
          0x11,
          0x97,
          0xe2,
        ]),
      );
    } finally {
      WalletMiniSecret.clear(miniSecret);
    }
  });

  test('非法 password 在派生真源再次 fail-closed', () async {
    await expectLater(
      WalletMiniSecret.fromMnemonic(mnemonic, password: 'A1!'),
      throwsA(isA<WalletPasswordException>()),
    );
  });
}
