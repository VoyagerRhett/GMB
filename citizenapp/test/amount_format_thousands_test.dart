import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/my/util/amount_format.dart';

/// AmountFormat.formatThousands 边界覆盖。
void main() {
  group('AmountFormat.formatThousands', () {
    test('零', () {
      expect(AmountFormat.formatThousands(0.0), '0.00');
    });

    test('正整数', () {
      expect(AmountFormat.formatThousands(1234567.89), '1,234,567.89');
    });

    test('负数', () {
      expect(AmountFormat.formatThousands(-1000.5), '-1,000.50');
    });

    test('小于千的正小数不带逗号', () {
      expect(AmountFormat.formatThousands(99.5), '99.50');
    });

    test('null 返回 --', () {
      expect(AmountFormat.formatThousands(null), '--');
    });

    test('NaN 返回 --', () {
      expect(AmountFormat.formatThousands(double.nan), '--');
    });

    test('Infinity 返回 --', () {
      expect(AmountFormat.formatThousands(double.infinity), '--');
    });

    test('负 Infinity 返回 --', () {
      expect(AmountFormat.formatThousands(double.negativeInfinity), '--');
    });

    test('自定义小数位 decimals=0 不带小数点', () {
      expect(AmountFormat.formatThousands(1234567.0, decimals: 0), '1,234,567');
    });

    test('亿级大数', () {
      expect(
          AmountFormat.formatThousands(123456789012.34), '123,456,789,012.34');
    });
  });
}
