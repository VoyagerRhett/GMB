import 'dart:async';
import 'dart:io';

import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/security/chain_bootstrap_api.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/security/device_subkey.dart';

/// 页面建立 CitizenServe 会话后的互斥结果。
///
/// `noWallet` 只来自本地默认账户不存在；远端投影、网络和设备认证故障必须保留自己的
/// 状态，禁止再用 nullable session 把它们伪装成“没有钱包”。
enum SquareSessionStatus {
  ready,
  noWallet,
  identityUnavailable,
  identityUnbound,
  serviceUnavailable,
  networkUnavailable,
  deviceUnavailable,
}

extension SquareSessionStatusText on SquareSessionStatus {
  String get message => switch (this) {
        SquareSessionStatus.ready => '',
        SquareSessionStatus.noWallet => '请先添加钱包账户',
        SquareSessionStatus.identityUnavailable => '当前钱包身份尚未同步或绑定，请稍后重试',
        SquareSessionStatus.identityUnbound => '当前默认钱包账户尚未绑定 CID',
        SquareSessionStatus.serviceUnavailable => '公民服务暂时不可用，请稍后重试',
        SquareSessionStatus.networkUnavailable => '网络连接失败，请检查网络后重试',
        SquareSessionStatus.deviceUnavailable => '钱包设备认证暂时不可用，请稍后重试',
      };
}

class SquareSessionResolution {
  const SquareSessionResolution(this.status, {this.session});

  final SquareSessionStatus status;
  final SquareSession? session;

  String get message => status.message;
}

/// 广场登录态提供器（全 App 共享单例）。
///
/// 后端会话握手用**当前 CID 的 P-256 硬件设备子钥静默签名**（不读 seed、不弹
/// 生物识别）换取 session token，由 [SquareApiClient] 内部按 accountId 缓存复用。
///
/// 已有子钥直接静默登录。实际登录被 Worker 明确拒绝为 `device_not_registered` 或
/// `invalid_signature` 时，底层客户端才鉴权一次登记本机子钥并重试；页面门禁不检查、
/// 不生成设备子钥。
class SquareSessionProvider {
  SquareSessionProvider({
    required AccountSecurityService accountSecurity,
    required CurrentUserContext currentUserContext,
    SquareApiClient? client,
    DeviceSubkey? deviceSubkey,
    ChainBootstrapApi? bootstrapApi,
  })  : _client = client ?? SquareApiClient(),
        _accountSecurity = accountSecurity,
        _deviceSubkey = deviceSubkey ?? DeviceSubkey(),
        _currentUserContext = currentUserContext,
        _bootstrapApi = bootstrapApi ?? ChainBootstrapApi();

  final SquareApiClient _client;
  final AccountSecurityService _accountSecurity;
  final DeviceSubkey _deviceSubkey;
  final CurrentUserContext _currentUserContext;
  final ChainBootstrapApi _bootstrapApi;

  CurrentUserContext get _currentUser => _currentUserContext;

  /// 返回当前默认用户的可用 session；访客返回 null（调用方按不可用处理）。
  ///
  /// **身份主键 = CID 号**：会话 `accountId` 取当前默认账户，P-256 子钥按该 CID
  /// 隔离。冷热账户走同一静默设备会话；只有设备首次登记的 sr25519 证明区分热签/冷签。
  Future<SquareSession?> ensureSession() async {
    final current = await _currentUser.resolve();
    if (current == null || current.accountId.isEmpty) return null;
    final session = await _client.ensureSession(
      accountId: current.accountId,
      signLoginPayload: (context, loginMessage) async {
        _requireCurrentAccount(current.accountId, context);
        // 会话握手 = 非用户动权 → 按挑战 CID 选择 P-256 硬件子钥静默签名。
        // CID 来自 Cloudflare finalized 用户投影，不再为登录预读链。
        final raw = await _deviceSubkey.signRawHex(
          context.cidNumber,
          loginMessage,
        );
        return '0x$raw';
      },
      onDeviceNotRegistered: (context) async {
        _requireCurrentAccount(current.accountId, context);
        await _registerMissingDeviceSubkey(
          await _bindingForContext(context),
        );
      },
    );
    await _activateSessionBinding(session);
    return session;
  }

  /// 为页面保留失败原因；动作服务仍可使用 [ensureSession] 让异常失败关闭。
  Future<SquareSessionResolution> resolveSession({bool refresh = false}) async {
    try {
      final session = await (refresh ? refreshSession() : ensureSession());
      if (session == null) {
        return const SquareSessionResolution(SquareSessionStatus.noWallet);
      }
      return SquareSessionResolution(
        SquareSessionStatus.ready,
        session: session,
      );
    } on SquareApiException catch (error) {
      if (error.errorCode == 'cid_not_bound' ||
          error.errorCode == 'identity_projection_pending') {
        if (error.errorCode == 'cid_not_bound') {
          final current = await _currentUser.resolve();
          if (current?.binding == null) {
            return const SquareSessionResolution(
              SquareSessionStatus.identityUnbound,
            );
          }
        }
        // 本机已有 finalized 绑定时，旧 Worker 的 cid_not_bound 只能视为投影未同步。
        return const SquareSessionResolution(
          SquareSessionStatus.identityUnavailable,
        );
      }
      if (error.errorCode == 'identity_projection_unavailable' ||
          (error.statusCode ?? 0) >= 500) {
        return const SquareSessionResolution(
          SquareSessionStatus.serviceUnavailable,
        );
      }
      return const SquareSessionResolution(
        SquareSessionStatus.deviceUnavailable,
      );
    } on SocketException {
      return const SquareSessionResolution(
        SquareSessionStatus.networkUnavailable,
      );
    } on TimeoutException {
      return const SquareSessionResolution(
        SquareSessionStatus.networkUnavailable,
      );
    } on AccountSecurityException {
      return const SquareSessionResolution(
        SquareSessionStatus.deviceUnavailable,
      );
    } on Exception {
      return const SquareSessionResolution(
        SquareSessionStatus.serviceUnavailable,
      );
    }
  }

  /// Worker 明确返回 401 后清除当前身份账户的本地缓存并重新握手一次。
  ///
  /// 仅供已经收到未授权响应的前台请求调用；普通首次加载仍走 [ensureSession] 的缓存与
  /// in-flight 去重，避免把每次页面进入都放大成新的登录挑战。
  Future<SquareSession?> refreshSession() async {
    final current = await _currentUser.resolve();
    if (current == null || current.accountId.isEmpty) return null;
    _client.clearSession(current.accountId);
    return ensureSession();
  }

  /// 已由精确 finalized 交易结果确认换绑后，为目标账户建立新会话。
  ///
  /// 本入口不再自行解析身份或读链；Worker 登录挑战仍会按链上当前绑定 fail-closed。
  /// 只供同一次换绑交接提交目标密文使用。
  Future<SquareSession?> ensureSessionForAccountId(String accountId) async {
    final binding = await _accountSecurity.accountDataBindingForAccountId(
      accountId,
    );
    return _client.ensureSession(
      accountId: accountId,
      signLoginPayload: (context, loginMessage) async {
        if (context.accountId != accountId ||
            context.cidNumber != binding.cidNumber ||
            context.bindingRevision != binding.bindingRevision) {
          throw const AccountSecurityException('换绑目标会话与 finalized 绑定不一致');
        }
        final raw = await _deviceSubkey.signRawHex(
          binding.cidNumber,
          loginMessage,
        );
        return '0x$raw';
      },
      onDeviceNotRegistered: (_) => _registerMissingDeviceSubkey(binding),
    );
  }

  /// Worker 是设备登记状态真源；只有它明确报告缺钥时才进入一次钱包鉴权。
  Future<void> _registerMissingDeviceSubkey(AccountDataBinding binding) async {
    await _accountSecurity.registerDeviceSubkeyForBinding(binding);
    _currentUser.invalidate();
  }

  Future<AccountDataBinding> _bindingForContext(
    SquareLoginContext context,
  ) async {
    final existing = await _accountSecurity.readAccountDataBindingForAccountId(
      context.accountId,
    );
    if (existing != null &&
        existing.cidNumber == context.cidNumber &&
        existing.bindingRevision == context.bindingRevision) {
      return existing;
    }
    final manifest = await _bootstrapApi.fetchManifest();
    return AccountDataBinding(
      genesisHash: manifest.chain.genesisHash,
      cidNumber: context.cidNumber,
      bindingRevision: context.bindingRevision,
      accountId: context.accountId,
    );
  }

  Future<void> _activateSessionBinding(SquareSession session) async {
    final binding = await _bindingForContext(
      SquareLoginContext(
        cidNumber: session.cidNumber,
        bindingRevision: session.bindingRevision,
        accountId: session.accountId,
      ),
    );
    await _accountSecurity.activateAccountDataBinding(
      genesisHash: binding.genesisHash,
      cidNumber: binding.cidNumber,
      bindingRevision: binding.bindingRevision,
      accountId: binding.accountId,
    );
    _currentUser.invalidate();
  }

  static void _requireCurrentAccount(
    String expectedAccountId,
    SquareLoginContext context,
  ) {
    if (context.accountId != expectedAccountId) {
      throw const AccountSecurityException('Cloudflare 登录挑战与当前默认账户不一致');
    }
  }
}
