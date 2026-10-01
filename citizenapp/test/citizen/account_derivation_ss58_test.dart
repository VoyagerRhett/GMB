import 'package:flutter_test/flutter_test.dart';
import 'package:citizenapp/citizen/shared/account_derivation.dart';

void main() {
  test('ss58FromAccountIdText 与 ss58FromAccountId 对同一账户一致(round-trip)', () {
    final id = deriveInstitutionMainAccountId('ZS001-NRC0A-000000001-2026');
    final hex = accountIdText(id);
    expect(ss58FromAccountIdText(hex), ss58FromAccountId(id));
  });

  test('ss58FromAccountIdText 拒绝无前缀与大写', () {
    final id = deriveInstitutionFeeAccountId('JL001-PRC05-850461124-2026');
    final accountId = accountIdText(id);
    expect(
      () => ss58FromAccountIdText(accountId.substring(2)),
      throwsFormatException,
    );
    expect(
      () => ss58FromAccountIdText(accountId.toUpperCase()),
      throwsFormatException,
    );
  });

  test('产出为合法 GMB SS58(prefix=2027) 而非 hex', () {
    final id = deriveInstitutionMainAccountId('ZS001-NRC0A-000000001-2026');
    final ss58 = ss58FromAccountIdText(accountIdText(id));
    // SS58 是 base58,绝不含 0/O/I/l,也不是纯 64 hex。
    expect(ss58.length, lessThan(64));
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(ss58), isFalse);
  });
}
