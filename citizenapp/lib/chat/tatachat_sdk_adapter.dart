import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart' as sdk;
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_request_signer.dart';
import 'package:citizenapp/chat/chat_product_configuration.dart';
import 'package:citizenapp/chat/chat_product_policy.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/security/chain_bootstrap_api.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/security/device_subkey.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';

/// Maps CitizenServe's product error contract without leaking it into TataChatSDK.
String chatUserErrorMessage(
  Object error, {
  String fallback = '聊天暂时无法使用，请稍后重试',
}) {
  if (error is SquareApiException) {
    return switch (error.errorCode) {
      'cid_not_bound' => '当前默认账户尚未注册公民号，无法使用聊天',
      'device_not_registered' ||
      'chat_device_not_registered' ||
      'invalid_signature' =>
        '聊天设备身份尚未就绪，请重试',
      'cid_binding_changed' => '当前登录用户已切换，请重新进入聊天',
      'missing_session' ||
      'invalid_session' ||
      'session_expired' =>
        '聊天会话已失效，请重试',
      'chat_membership_required' ||
      'membership_required' ||
      'chat_disabled' =>
        '当前账户尚未开通聊天会员权益',
      'chat_server_not_configured' => '聊天服务尚未配置',
      _ => error.statusCode == null || error.statusCode! >= 500
          ? '聊天服务暂时无法连接，请稍后重试'
          : fallback,
    };
  }
  return chatSdkUserErrorMessage(error, fallback: fallback);
}

/// CitizenApp's product boundary for TataChatSDK's deployment-neutral identities.
///
/// A citizen number is passed to TataChatSDK as `userId`. These extensions keep the
/// CitizenApp domain vocabulary outside the reusable SDK while avoiding a
/// second protocol or cryptographic implementation.
extension CitizenEncryptedMessageFields on EncryptedMessage {
  EncryptedDelivery get _deliveryForWrite {
    if (deliveries.isEmpty) {
      deliveries.add(EncryptedDelivery(recipient: Recipient()));
    }
    if (deliveries.length != 1) {
      throw StateError('CitizenApp message must contain exactly one delivery');
    }
    final delivery = deliveries.single;
    if (!delivery.hasRecipient()) delivery.recipient = Recipient();
    return delivery;
  }

  String get senderCidNumber => senderUserId;
  set senderCidNumber(String value) => senderUserId = value;

  String get recipientCidNumber => recipientUserId;
  set recipientCidNumber(String value) =>
      _deliveryForWrite.recipient.userId = value;

  List<int> get mlsWireMessage => openmlsCiphertext;
  set mlsWireMessage(List<int> value) =>
      _deliveryForWrite.openmlsCiphertext = value;
}

extension CitizenChatRouteFields on ChatRouteRecord {
  String get peerCidNumber => peerUserId;
}

extension CitizenChatConversationPreviewFields on ChatConversationPreview {
  String get peerCidNumber => peerUserId;
}

extension CitizenChatDataBindingMapping on AccountDataBinding {
  sdk.ChatDataBinding toChatDataBinding() => sdk.ChatDataBinding(
        keyDomain: genesisHash,
        userId: cidNumber,
        bindingRevision: bindingRevision,
        accountId: accountId,
      );
}

extension CitizenChatDeviceFields on ChatDevice {
  String get cidNumber => userId;
}

extension CitizenMlsKeyPackageFields on MlsKeyPackage {
  String get cidNumber => userId;
}

extension CitizenMlsStateStoreFields on MlsStateStore {
  String get ownerCidNumber => ownerUserId;
}

extension CitizenGroupCommitFields on GroupCommitBundle {
  List<String> get removedCidNumbers => removedUserIds;
}

String cidNumberFromMemberIdentity(String identity) =>
    userIdFromMemberIdentity(identity);

List<String> cidNumbersFromMemberIdentities(
  Iterable<String> identities, {
  String? excludeCidNumber,
}) =>
    userIdsFromMemberIdentities(identities, excludeUserId: excludeCidNumber);

extension CitizenChatStoredMessageFields on ChatStoredMessage {
  String get senderCidNumber => senderUserId;
  String get recipientCidNumber => recipientUserId;
}

extension CitizenChatQueuedMessageFields on ChatQueuedMessage {
  String get recipientCidNumber => recipientUserId;
}

extension CitizenChatPendingOutgoingFields on ChatPendingOutgoingMessage {
  String get recipientCidNumber => recipientUserId;
}

extension CitizenChatPendingMediaFields on ChatPendingMedia {
  String get recipientCidNumber => recipientUserId;
}

extension CitizenGroupMemberFields on GroupMember {
  String get cidNumber => userId;
}

extension CitizenChatGroupFields on ChatGroup {
  String get creatorCidNumber => creatorUserId;
  List<String> get memberCidNumbers => memberUserIds;
}

/// CitizenApp 登录挑战签名适配；CID 只存在于本产品边界。
typedef ChatLoginSigner = Future<String> Function({
  required String cidNumber,
  required String accountId,
  required Uint8List loginMessage,
});

typedef ChatPushTokenProvider = Future<sdk.ChatPushToken> Function();

/// 把公民钱包用途钥映射为 TataChatSDK 的中性用途钥接口。
final class CitizenChatStorageKeyProvider
    implements sdk.ChatStorageKeyProvider {
  CitizenChatStorageKeyProvider(this.accountSecurity);

  final AccountSecurityService accountSecurity;

  static sdk.ChatDataBinding toChatBinding(AccountDataBinding binding) =>
      sdk.ChatDataBinding(
        keyDomain: binding.genesisHash,
        userId: binding.cidNumber,
        bindingRevision: binding.bindingRevision,
        accountId: binding.accountId,
      );

  static AccountDataBinding toCitizenBinding(sdk.ChatDataBinding binding) =>
      AccountDataBinding(
        genesisHash: binding.keyDomain,
        cidNumber: binding.userId,
        bindingRevision: binding.bindingRevision,
        accountId: binding.accountId,
      );

  static LocalKeyPurpose _purpose(sdk.ChatStorageKeyPurpose purpose) =>
      switch (purpose) {
        sdk.ChatStorageKeyPurpose.chat => LocalKeyPurpose.chat,
        sdk.ChatStorageKeyPurpose.chatIndex => LocalKeyPurpose.chatIndex,
        sdk.ChatStorageKeyPurpose.mls => LocalKeyPurpose.mls,
        sdk.ChatStorageKeyPurpose.attachment => LocalKeyPurpose.attachment,
      };

  @override
  Future<sdk.ChatDataBinding> resolveBinding({
    required String ownerUserId,
    required String currentAccountId,
    String? expectedKeyDomain,
  }) async {
    final binding = await accountSecurity.accountDataBindingForAccountId(
      currentAccountId,
    );
    if (binding.cidNumber != ownerUserId ||
        (expectedKeyDomain != null &&
            binding.genesisHash != expectedKeyDomain)) {
      throw StateError('聊天属主公民号与当前钱包绑定不一致');
    }
    return toChatBinding(binding);
  }

  @override
  Future<List<Uint8List>> readDataKeysForBinding(
    sdk.ChatDataBinding binding,
    List<({sdk.ChatStorageKeyPurpose purpose, String? context})> requests,
  ) =>
      accountSecurity.readDataKeysForBinding(
        toCitizenBinding(binding),
        requests
            .map(
              (request) => (
                purpose: _purpose(request.purpose),
                context: request.context
              ),
            )
            .toList(growable: false),
      );

  @override
  Future<List<Uint8List>> deriveDataKeysForBindingHandover(
    sdk.ChatDataBinding binding,
    List<({sdk.ChatStorageKeyPurpose purpose, String? context})> requests,
  ) =>
      accountSecurity.deriveDataKeysForBindingHandover(
        toCitizenBinding(binding),
        requests
            .map(
              (request) => (
                purpose: _purpose(request.purpose),
                context: request.context
              ),
            )
            .toList(growable: false),
      );
}

/// CitizenApp 身份、会员、Firebase 与 CitizenServe 的唯一宿主适配。
final class CitizenChatRuntimeHost implements sdk.ChatRuntimeHost {
  CitizenChatRuntimeHost({
    required this.accountSecurity,
    required this.currentUserContext,
    required this.bootstrapApi,
    required this.squareApiClient,
    required this.deviceSubkey,
    required this.pushService,
    this.loginSigner,
  }) : keyProvider = CitizenChatStorageKeyProvider(accountSecurity);

  final AccountSecurityService accountSecurity;
  final CurrentUserContext currentUserContext;
  final ChainBootstrapApi bootstrapApi;
  final SquareApiClient squareApiClient;
  final DeviceSubkey deviceSubkey;
  final ChatPushService pushService;
  final ChatLoginSigner? loginSigner;

  @override
  final CitizenChatStorageKeyProvider keyProvider;

  @override
  sdk.ChatPushBridge get push => pushService;

  @override
  sdk.ChatMediaLimitPolicy get mediaLimits =>
      const CitizenChatMediaLimitPolicy();

  @override
  Future<bool> canSend(String userId) async =>
      ChatMediaLimits.chatAuthorizedFor(userId);

  Future<AccountDataBinding> _bindingForLogin(
    SquareLoginContext context,
  ) async {
    final existing = await accountSecurity.readAccountDataBindingForAccountId(
      context.accountId,
    );
    if (existing != null &&
        existing.cidNumber == context.cidNumber &&
        existing.bindingRevision == context.bindingRevision) {
      return existing;
    }
    final manifest = await bootstrapApi.fetchManifest();
    return AccountDataBinding(
      genesisHash: manifest.chain.genesisHash,
      cidNumber: context.cidNumber,
      bindingRevision: context.bindingRevision,
      accountId: context.accountId,
    );
  }

  Future<String> _signLogin(
    SquareLoginContext context,
    Uint8List message,
  ) async {
    final custom = loginSigner;
    if (custom != null) {
      return custom(
        cidNumber: context.cidNumber,
        accountId: context.accountId,
        loginMessage: message,
      );
    }
    final raw = await deviceSubkey.signRawHex(context.cidNumber, message);
    return '0x$raw';
  }

  Future<void> _registerMissingDevice(SquareLoginContext context) async {
    final binding = await _bindingForLogin(context);
    await accountSecurity.registerDeviceSubkeyForBinding(binding);
    currentUserContext.invalidate();
  }

  @override
  Future<sdk.ChatRuntimeAccount?> currentAccount({
    String? expectedAccountId,
  }) async {
    final current = await currentUserContext.resolve();
    if (current == null) return null;
    final defaultAccount = current.account;
    if (expectedAccountId != null &&
        defaultAccount.accountId != expectedAccountId) {
      throw StateError('身份账户已切换，请重新进入聊天');
    }

    var binding = current.binding;
    if (binding == null) {
      final session = await squareApiClient.ensureSession(
        accountId: defaultAccount.accountId,
        signLoginPayload: _signLogin,
        onDeviceNotRegistered: _registerMissingDevice,
      );
      binding = await _bindingForLogin(
        SquareLoginContext(
          cidNumber: session.cidNumber,
          bindingRevision: session.bindingRevision,
          accountId: session.accountId,
        ),
      );
      await accountSecurity.activateAccountDataBinding(
        genesisHash: binding.genesisHash,
        cidNumber: binding.cidNumber,
        bindingRevision: binding.bindingRevision,
        accountId: binding.accountId,
      );
      currentUserContext.invalidate();
    }
    if (binding.accountId != defaultAccount.accountId) {
      throw StateError('CitizenServe 用户投影与当前默认账户不一致');
    }
    return sdk.ChatRuntimeAccount(
      hostIndex: defaultAccount.walletIndex,
      keyDomain: binding.genesisHash,
      userId: binding.cidNumber,
      bindingRevision: binding.bindingRevision,
      accountId: binding.accountId,
      displayName: defaultAccount.name,
    );
  }

  @override
  Future<sdk.TataChatServerAccess> requestTataChatServerAccess({
    required sdk.ChatRuntimeAccount account,
    required ChatDevice identity,
  }) async {
    var session = await squareApiClient.ensureSession(
      accountId: account.accountId,
      signLoginPayload: _signLogin,
      onDeviceNotRegistered: _registerMissingDevice,
    );
    if (session.cidNumber != account.userId ||
        session.bindingRevision != account.bindingRevision ||
        session.accountId != account.accountId) {
      squareApiClient.clearSession(account.accountId);
      session = await squareApiClient.ensureSession(
        accountId: account.accountId,
        signLoginPayload: _signLogin,
        onDeviceNotRegistered: _registerMissingDevice,
      );
    }
    if (session.cidNumber != account.userId ||
        session.bindingRevision != account.bindingRevision ||
        session.accountId != account.accountId) {
      throw StateError('聊天会话与 CitizenServe 当前用户投影不一致');
    }
    final signer = session.signRequest;
    if (signer == null) {
      throw const SquareApiException('聊天设备请求签名器缺失');
    }
    final uri = Uri.parse('${squareApiClient.baseUrl}/auth/chatserver/access');
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const SquareApiException('TataChatServer 凭证端点必须使用 HTTPS');
    }
    final body = jsonEncode(<String, String>{'device_id': identity.deviceId});
    final headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'authorization': 'Bearer ${session.sessionToken}',
      ...await squareRequestHeaders(
        method: 'POST',
        uri: uri,
        body: body,
        sessionToken: session.sessionToken,
        sign: signer,
      ),
    };
    final client = http.Client();
    try {
      final response = await client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 20));
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(response.body);
        if (value is Map<String, dynamic>) decoded = value;
      } catch (_) {}
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SquareApiException(
          'TataChatServer 访问凭证签发失败',
          statusCode: response.statusCode,
          errorCode: decoded?['error_code']?.toString(),
        );
      }
      final tataChatServerUrl = decoded?['chat_server_url'];
      final tataChatServerToken = decoded?['chat_server_token'];
      final expiresAtMillis = decoded?['expires_at_millis'];
      if (decoded?['ok'] != true ||
          tataChatServerUrl is! String ||
          tataChatServerToken is! String ||
          expiresAtMillis is! num) {
        throw const SquareApiException('TataChatServer 访问凭证响应不合法');
      }
      final access = sdk.TataChatServerAccess(
        tataChatServerUrl: Uri.parse(tataChatServerUrl),
        tataChatServerToken: tataChatServerToken,
        expiresAtMillis: expiresAtMillis.toInt(),
      );
      access.validate(DateTime.now().millisecondsSinceEpoch);
      return access;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> invalidateAccount(String accountId) async {
    squareApiClient.clearSession(accountId);
  }
}

/// 使用 CitizenApp 产品依赖创建真实的 [sdk.ChatSdk]。
///
sdk.ChatSdk createCitizenChatRuntime({
  required AccountSecurityService accountSecurity,
  required CurrentUserContext currentUserContext,
  sdk.ChatStore? store,
  SharedPreferences? preferences,
  SquareApiClient? squareApiClient,
  ChatLoginSigner? loginSigner,
  DeviceSubkey? deviceSubkey,
  sdk.MlsStateStoreFactory? stateStoreFactory,
  MlsGroupCrypto Function(ChatDevice identity, MlsStateStore stateStore)?
      cryptoFactory,
  sdk.ChatServiceTransportFactory? transportFactory,
  ChatPushService? pushService,
  ChatPushTokenProvider? pushTokenProvider,
  ChainBootstrapApi? bootstrapApi,
  Future<Directory> Function()? documentsDirectoryProvider,
  bool receiveOnly = false,
}) =>
    sdk.ChatSdk(
      host: createCitizenChatRuntimeHost(
        accountSecurity: accountSecurity,
        squareApiClient: squareApiClient,
        loginSigner: loginSigner,
        deviceSubkey: deviceSubkey,
        pushService: pushService,
        pushTokenProvider: pushTokenProvider,
        currentUserContext: currentUserContext,
        bootstrapApi: bootstrapApi,
      ),
      store: store,
      preferences: preferences,
      stateStoreFactory: stateStoreFactory,
      cryptoFactory: cryptoFactory,
      documentsDirectoryProvider: documentsDirectoryProvider,
      transportFactory: transportFactory,
      receiveOnly: receiveOnly,
    );

/// 构造 SDK 需要的 CitizenApp 产品宿主，仅供组合与测试注入。
sdk.ChatRuntimeHost createCitizenChatRuntimeHost({
  required AccountSecurityService accountSecurity,
  required CurrentUserContext currentUserContext,
  SquareApiClient? squareApiClient,
  ChatLoginSigner? loginSigner,
  DeviceSubkey? deviceSubkey,
  ChatPushService? pushService,
  ChatPushTokenProvider? pushTokenProvider,
  ChainBootstrapApi? bootstrapApi,
}) {
  final push = pushService ?? ChatPushService(tokenProvider: pushTokenProvider);
  final host = CitizenChatRuntimeHost(
    accountSecurity: accountSecurity,
    currentUserContext: currentUserContext,
    bootstrapApi: bootstrapApi ?? ChainBootstrapApi(),
    squareApiClient: squareApiClient ?? SquareApiClient(),
    deviceSubkey: deviceSubkey ?? DeviceSubkey(),
    pushService: push,
    loginSigner: loginSigner,
  );
  sdk.ChatCrypto.defaultKeyProvider = host.keyProvider;
  return host;
}
