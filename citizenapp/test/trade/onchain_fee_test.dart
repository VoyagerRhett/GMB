import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_transfer_call.dart';
import 'package:citizenapp/transaction/multisig-transfer/multisig_transfer_balance_guard.dart';

void main() {
  group('OnchainTransferCall.estimateTransferFeeYuan', () {
    // 链上常量：费率 0.1%（Perbill(1_000_000)），最低手续费 10 fen = 0.10 元

    test('small amount → minimum fee 0.10 yuan', () {
      // 1 元 → 1 fen by rate → min(1,10) → 10 fen = 0.10 元
      expect(OnchainTransferCall.estimateTransferFeeYuan(1.0), 0.10);
    });

    test('50 yuan → below minimum → 0.10 yuan', () {
      // 50 元 → 5000 fen * 1_000_000 / 1_000_000_000 = 5 fen → min fee
      expect(OnchainTransferCall.estimateTransferFeeYuan(50.0), 0.10);
    });

    test('100 yuan → exactly at minimum → 0.10 yuan', () {
      // 100 元 = 10000 fen → 10000 * 1_000_000 / 1_000_000_000 = 10 fen
      expect(OnchainTransferCall.estimateTransferFeeYuan(100.0), 0.10);
    });

    test('500 yuan → 0.50 yuan', () {
      // 500 元 = 50000 fen → 50 fen = 0.50 元
      expect(OnchainTransferCall.estimateTransferFeeYuan(500.0), 0.50);
    });

    test('10000 yuan → 10.00 yuan', () {
      // 10000 元 = 1000000 fen → 1000 fen = 10.00 元
      expect(OnchainTransferCall.estimateTransferFeeYuan(10000.0), 10.00);
    });

    test('0 yuan → minimum fee 0.10 yuan', () {
      expect(OnchainTransferCall.estimateTransferFeeYuan(0.0), 0.10);
    });

    test('0.01 yuan → minimum fee 0.10 yuan', () {
      // 0.01 元 = 1 fen → 0 by rate → min fee
      expect(OnchainTransferCall.estimateTransferFeeYuan(0.01), 0.10);
    });

    test('99.99 yuan → below minimum → 0.10 yuan', () {
      // 99.99 元 = 9999 fen → 9999 * 1_000_000 / 1_000_000_000
      // = 9_999_000_000 / 1_000_000_000 ≈ 9.999 → half-up → 10 fen
      // (9999 * 1_000_000 + 500_000_000) ~/ 1_000_000_000
      // = 10_499_000_000 ~/ 1_000_000_000 = 10 fen
      expect(OnchainTransferCall.estimateTransferFeeYuan(99.99), 0.10);
    });

    test('large amount 1000000 yuan → 1000.00 yuan', () {
      // 1_000_000 元 = 100_000_000 fen → 100_000 fen = 1000.00 元
      expect(OnchainTransferCall.estimateTransferFeeYuan(1000000.0), 1000.00);
    });

    test('fractional amount 123.45 yuan', () {
      // 123.45 元 = 12345 fen
      // byRate = (12345 * 1_000_000 + 500_000_000) ~/ 1_000_000_000
      //        = (12_345_000_000 + 500_000_000) ~/ 1_000_000_000
      //        = 12_845_000_000 ~/ 1_000_000_000 = 12 fen = 0.12 元
      expect(OnchainTransferCall.estimateTransferFeeYuan(123.45), 0.12);
    });
  });

  group('机构费用账户分离扣款', () {
    test('机构转账要求操作费、执行费和费用账户自身 ED', () {
      final executionFee = OnchainTransferCall.estimateTransferFeeYuan(500);
      expect(executionFee, 0.50);
      expect(
        MultisigTransferBalanceGuard.institutionFeeAccountRequiredYuan(
          additionalDebitYuan: executionFee,
        ),
        1.71,
      );
    });

    test('费用账户归集还必须把划转本金计入同一账户总支出', () {
      final executionFee = OnchainTransferCall.estimateTransferFeeYuan(500);
      expect(
        MultisigTransferBalanceGuard.institutionFeeAccountRequiredYuan(
          additionalDebitYuan: 500 + executionFee,
        ),
        501.71,
      );
    });
  });
}
