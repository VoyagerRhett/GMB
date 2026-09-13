import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/local_data_key.dart';

/// 普通业务的当前用户快照；账户直接使用 CitizenSDK 公开模型。
final class CurrentUser {
  const CurrentUser({required this.account, required this.binding});

  final CitizenWalletStateAccount account;
  final AccountDataBinding? binding;

  String get accountId => account.accountId;
  String get ss58Address => account.ss58Address;
  String get cidNumber => binding?.cidNumber ?? '';
  int get bindingRevision => binding?.bindingRevision ?? 0;
  bool get isRegistered => binding != null;
}

typedef CurrentUserBindingReader = Future<AccountDataBinding?> Function(
  String accountId,
);

/// Chat、通讯录、主页和动态共用的本机当前用户入口。
///
/// 默认账户来自 CitizenSDK 全局顺序第一项；绑定是 CitizenApp 自己的 finalized 业务缓存。
interface class CurrentUserContext {
  CurrentUserContext({
    required CitizenSdkWallet wallet,
    required AccountSecurityService accountSecurity,
    CurrentUserBindingReader? bindingReader,
  })  : _wallet = wallet,
        _accountSecurity = accountSecurity,
        _bindingReader = bindingReader;

  final CitizenSdkWallet _wallet;
  final AccountSecurityService _accountSecurity;
  final CurrentUserBindingReader? _bindingReader;

  CurrentUser? _cached;
  int _cachedRevision = -1;
  Future<CurrentUser?>? _inflight;
  int _generation = 0;

  Future<CurrentUser?> resolve() async {
    final revision = _accountSecurity.revision.value;
    final cached = _cached;
    if (cached != null && _cachedRevision == revision) return cached;
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final generation = _generation;
    final future = _resolveFresh(revision, generation);
    _inflight = future;
    try {
      return await future;
    } finally {
      if (identical(_inflight, future)) _inflight = null;
    }
  }

  Future<String?> accountId() async => (await resolve())?.accountId;

  Future<AccountDataBinding?> binding() async => (await resolve())?.binding;

  Future<CurrentUser?> _resolveFresh(int revision, int generation) async {
    final account = (await _wallet.getState()).defaultAccount;
    if (account == null) return null;
    final binding = await (_bindingReader?.call(account.accountId) ??
        _accountSecurity.readAccountDataBindingForAccountId(account.accountId));
    final current = CurrentUser(account: account, binding: binding);
    if (_generation == generation &&
        _accountSecurity.revision.value == revision) {
      _cached = current;
      _cachedRevision = revision;
    }
    return current;
  }

  void invalidate() {
    _generation += 1;
    _cached = null;
    _cachedRevision = -1;
    _inflight = null;
  }
}
