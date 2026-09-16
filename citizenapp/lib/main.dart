import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart' as sdk;
import 'package:citizenapp/8964/square_tab_page.dart';
import 'package:citizenapp/citizen/citizen_tab_page.dart';
import 'package:citizenapp/chat/chat_product_configuration.dart';
import 'package:citizenapp/chat/tatachat_sdk_adapter.dart';
import 'package:citizenapp/chat/chat_entry.dart';
import 'package:citizenapp/security/app_lock_service.dart';
import 'package:citizenapp/security/emergency_wipe_platform.dart';
import 'package:citizenapp/security/pin_input_page.dart';
import 'package:citizenapp/security/secure_storage.dart';
import 'package:citizenapp/transaction/transaction_tab_page.dart';
import 'package:citizenapp/transaction/history/wallet_transaction_history_service.dart';
import 'package:citizenapp/my/util/screenshot_guard.dart';
import 'package:citizenapp/my/user/user.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/security/app_permission_gate.dart';
import 'package:citizenapp/update/app_update.dart';
import 'package:citizenapp/update/update_badge.dart';
import 'package:citizenapp/8964/services/device_subkey_registrar.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/notifications/app_push_service.dart';
import 'package:citizenapp/notifications/app_push_token.dart';
import 'package:citizenapp/8964/pages/square_turnstile_page.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/qr/qr_protocols.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/security/account_data_key_provision.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/qr/bodies/account_data_key_response_body.dart';
import 'package:citizenapp/qr/envelope.dart';
import 'package:citizenapp/signer/app_business_qr_codec.dart';
import 'package:citizenapp/signer/signing.dart'
    show kGmbSignDomain, kOpSignSquareDeviceBind;
import 'package:citizenapp/wallet/wallet_gate.dart';

import 'ui/app_theme.dart';
import 'ui/app_layout.dart';
import 'ui/biometric_auth_text.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // CitizenApp 只打开一个完整 CitizenSDK session。钱包、签名、QR_V1、
  // 轻节点、交易与 execution history 共用同一个 Engine generation。
  final citizenSdk = await CitizenSdk.open(modules: CitizenSdkModules.full);
  final registrar = DeviceSubkeyRegistrar(
    turnstileToken: () => acquireDeviceBindingTurnstileToken(
      isUiReady: () => appNavigatorKey.currentState != null,
      present: () {
        final navigator = appNavigatorKey.currentState;
        if (navigator == null) return Future<String?>.value();
        return navigator.push<String>(
          MaterialPageRoute(builder: (_) => const SquareTurnstilePage()),
        );
      },
    ),
  );
  final accountSecurity = AccountSecurityService(
    wallet: citizenSdk.wallet,
    signing: citizenSdk.signing,
    subkeyRegistrar: registrar.register,
    coldDeviceBindingSigner:
        ({
          required binding,
          required payload,
          required signingMessage,
          required devicePublicKey,
          required issuedAtMillis,
        }) => _signColdDeviceBinding(
          wallet: citizenSdk.wallet,
          signing: citizenSdk.signing,
          binding: binding,
          payload: payload,
          signingMessage: signingMessage,
          devicePublicKey: devicePublicKey,
          issuedAtMillis: issuedAtMillis,
        ),
    coldAccountDataKeyProvider: ({required binding, required requests}) =>
        _provideColdAccountDataKeys(
          wallet: citizenSdk.wallet,
          binding: binding,
          requests: requests,
        ),
  );
  final currentUserContext = CurrentUserContext(
    wallet: citizenSdk.wallet,
    accountSecurity: accountSecurity,
  );
  final finalizedIdentityResolver = FinalizedIdentityResolver(
    wallet: citizenSdk.wallet,
    chain: citizenSdk.chain,
  );
  final squareApiClient = SquareApiClient();
  final appPushService = AppPushService();
  final squareSessionProvider = SquareSessionProvider(
    accountSecurity: accountSecurity,
    currentUserContext: currentUserContext,
    client: squareApiClient,
  );

  // 任何 ChatSdk、钱包页或 PIN 门禁构造前先处理跨重启擦除门闩。
  // pending 不依赖已被平台阶段删除的 PIN，直接继续全量擦除；
  // 当前进程无论成败都只允许重试或退出，禁止恢复业务运行态。
  var wipeStartupResult = await AppLockService.recoverPersistentWipeAtStartup(
    wallet: citizenSdk.wallet,
    accountSecurity: accountSecurity,
  );
  // Documents 暂时不可用时先在业务初始化前有界复查；只有连续失败才进入
  // 安全阻断页，不能要求用户通过强退重开代替正常的启动恢复。
  if (wipeStartupResult == AppDataWipeStartupResult.preflightBlocked) {
    for (final delay in <Duration>[
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 300),
      const Duration(milliseconds: 900),
    ]) {
      await Future<void>.delayed(delay);
      wipeStartupResult = await AppLockService.recoverPersistentWipeAtStartup(
        wallet: citizenSdk.wallet,
        accountSecurity: accountSecurity,
      );
      if (wipeStartupResult != AppDataWipeStartupResult.preflightBlocked) {
        break;
      }
    }
  }
  if (wipeStartupResult != AppDataWipeStartupResult.ready) {
    runApp(
      _DataWipeRecoveryApp(
        initialResult: wipeStartupResult,
        sdk: citizenSdk,
        accountSecurity: accountSecurity,
      ),
    );
    return;
  }

  // 擦除门闩通过后才启动 SDK 唯一轻节点。启动失败保留 SDK
  // startFailed 事实并继续进入 App，交易顶栏按现有不可用状态呈现；
  // 禁止回退到 CitizenApp 旧轻节点。
  try {
    await citizenSdk.start();
  } on Object catch (error, stackTrace) {
    AppLog.d('[CitizenSDK] 唯一轻节点启动失败: $error\n$stackTrace');
  }
  final transactionHistory = WalletTransactionHistoryService(
    history: citizenSdk.history,
    chain: citizenSdk.chain,
    wallet: citizenSdk.wallet,
    events: citizenSdk.events,
  );
  try {
    await transactionHistory.start();
  } on Object catch (error, stackTrace) {
    AppLog.d('[TransactionHistory] 初始同步失败: $error\n$stackTrace');
  }

  // 只有持久擦除门闩、上一进程 CID lease 和 SDK 启动尝试完成后，
  // 才允许注册会构造 ChatSdk 的后台入口。
  registerAppPushBackgroundHandler(chatRuntimeBackgroundHandler);

  // 诊断 — 把所有 framework / widget 静默吞掉的异常都打到 logcat。
  // 默认 ErrorWidget 在某些场景下表现为空白方块（白屏），这里换成显眼的红框 + 文字。
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    AppLog.d(
      '[FlutterError-Diag] library=${details.library} ctx=${details.context} '
      'exception=${details.exception}',
    );
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppLog.d(
      '[ErrorWidget-Diag] exception=${details.exception}\nstack=${details.stack}',
    );
    return Material(
      color: const Color(0xFFFFEEEE),
      child: Padding(
        padding: EdgeInsets.all(AppLayout.scaledValue(12)),
        child: SingleChildScrollView(
          child: Text(
            'WIDGET ERROR:\n${details.exception}\n\n${details.stack}',
            style: TextStyle(
              color: const Color(0xFFB00020),
              fontSize: AppLayout.scaledValue(12),
            ),
          ),
        ),
      ),
    );
  };

  // 状态栏样式
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppTheme.surfaceCard,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    CitizenApp(
      sdk: citizenSdk,
      accountSecurity: accountSecurity,
      currentUserContext: currentUserContext,
      finalizedIdentityResolver: finalizedIdentityResolver,
      squareSessionProvider: squareSessionProvider,
      squareApiClient: squareApiClient,
      appPushService: appPushService,
      transactionHistory: transactionHistory,
    ),
  );
}

/// 持久 pending marker 的唯一启动终态：不构造任何业务页面。
class _DataWipeRecoveryApp extends StatelessWidget {
  const _DataWipeRecoveryApp({
    required this.initialResult,
    required this.sdk,
    required this.accountSecurity,
  });

  final AppDataWipeStartupResult initialResult;
  final CitizenSdk sdk;
  final AccountSecurityService accountSecurity;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '公民',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _DataWipeRecoveryPage(
        initialResult: initialResult,
        sdk: sdk,
        accountSecurity: accountSecurity,
      ),
    );
  }
}

class _DataWipeRecoveryPage extends StatefulWidget {
  const _DataWipeRecoveryPage({
    required this.initialResult,
    required this.sdk,
    required this.accountSecurity,
  });

  final AppDataWipeStartupResult initialResult;
  final CitizenSdk sdk;
  final AccountSecurityService accountSecurity;

  @override
  State<_DataWipeRecoveryPage> createState() => _DataWipeRecoveryPageState();
}

class _DataWipeRecoveryPageState extends State<_DataWipeRecoveryPage> {
  late AppDataWipeStartupResult _result;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    // 擦除待重试时不再等待用户操作；完成态也立即退出，禁止停留在恢复页面重新进入业务流程。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_result == AppDataWipeStartupResult.retryRequired) {
        unawaited(_retryUntilComplete());
      } else if (_result == AppDataWipeStartupResult.dataWiped) {
        unawaited(SystemNavigator.pop());
      }
    });
  }

  Future<void> _retryUntilComplete() async {
    if (_retrying || _result != AppDataWipeStartupResult.retryRequired) return;
    setState(() => _retrying = true);
    await EmergencyWipePlatform.beginProtectedExecution();
    while (mounted) {
      try {
        await AppLockService.wipeAllData(
          wallet: widget.sdk.wallet,
          accountSecurity: widget.accountSecurity,
        );
        if (!mounted) return;
        setState(() => _result = AppDataWipeStartupResult.dataWiped);
        await EmergencyWipePlatform.finishProtectedExecution();
        await SystemNavigator.pop();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preflightBlocked =
        _result == AppDataWipeStartupResult.preflightBlocked;
    if (!preflightBlocked) {
      return const PopScope(
        canPop: false,
        child: ColoredBox(color: Colors.black),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber,
                  size: 56,
                  color: AppTheme.danger,
                ),
                const SizedBox(height: 20),
                const Text(
                  '安全状态无法确认',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  '应用不会擅自清理任何数据。请退出后重新启动。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text('退出'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 当前默认账户是冷账户时，用 CitizenWallet 扫码签署既有 0x1C 设备绑定摘要。
Future<String> _signColdDeviceBinding({
  required CitizenSdkWallet wallet,
  required CitizenSigning signing,
  required AccountDataBinding binding,
  required Uint8List payload,
  required Uint8List signingMessage,
  required String devicePublicKey,
  required int issuedAtMillis,
}) async {
  final account = (await wallet.getState()).defaultAccount;
  if (account == null ||
      account.signMode != CitizenWalletSignMode.cold ||
      account.accountId != binding.accountId ||
      !RegExp(r'^04[0-9a-f]{128}$').hasMatch(devicePublicKey)) {
    throw const AccountSecurityException('当前默认账户不是该 CID 的冷钱包账户');
  }
  final context = appNavigatorKey.currentContext;
  if (context == null) {
    throw const AccountSecurityException('当前页面无法发起冷钱包设备绑定签名');
  }
  if (!context.mounted) {
    throw const AccountSecurityException('当前页面已经关闭');
  }
  final signature = await signCitizenPayload(
    signing: signing,
    context: context,
    accountId: binding.accountId,
    payload: payload,
    action: QrActions.squareDeviceBind,
    transform: CitizenSigningTransform.blake2Domain(
      Uint8List.fromList(<int>[...kGmbSignDomain, kOpSignSquareDeviceBind]),
    ),
  );
  final current = (await wallet.getState()).defaultAccount;
  if (current == null ||
      current.signMode != CitizenWalletSignMode.cold ||
      current.accountId != binding.accountId ||
      !await CitizenSigning.verify(
        accountId: binding.accountId,
        signature: signature,
        payload: signingMessage,
      )) {
    throw const AccountSecurityException('冷钱包设备绑定签名无效');
  }
  return '0x${_lowerHex(signature)}';
}

/// 冷账户真实缺少用途钥时，使用一次性 X25519 会话从 CitizenWallet 加密领取。
Future<List<Uint8List>> _provideColdAccountDataKeys({
  required CitizenSdkWallet wallet,
  required AccountDataBinding binding,
  required List<({LocalKeyPurpose purpose, String? context})> requests,
}) async {
  final account = (await wallet.getState()).defaultAccount;
  if (account == null ||
      account.signMode != CitizenWalletSignMode.cold ||
      account.accountId != binding.accountId) {
    throw const AccountSecurityException('当前默认账户不是该 CID 的冷钱包账户');
  }
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    throw const AccountSecurityException('当前页面无法发起冷钱包用途钥请求');
  }
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final session = await AccountDataKeyProvisionSession.create(
    binding: binding,
    requests: requests,
    expiresAt: now + 120,
  );
  try {
    final signer = AppBusinessQrCodec();
    final request = signer.buildRequest(
      requestId: AppBusinessQrCodec.generateRequestId(prefix: 'data-key-'),
      signerPublicKey: binding.accountId,
      payloadHex: '0x${_lowerHex(session.payload)}',
      action: QrActions.accountDataKeyProvision,
      nowEpochSeconds: now,
      ttlSeconds: 120,
    );
    final response = await navigator
        .push<QrEnvelope<AccountDataKeyResponseBody>>(
          MaterialPageRoute(
            builder: (_) => QrSignSessionPage(
              request: request,
              requestJson: signer.encodeRequest(request),
              expectedSignerPublicKey: binding.accountId,
              responseKind: QrKind.accountDataKeyResponse,
            ),
          ),
        );
    if (response == null) {
      throw const AccountSecurityException('冷钱包用途钥提供已取消');
    }
    final current = (await wallet.getState()).defaultAccount;
    if (current == null ||
        current.signMode != CitizenWalletSignMode.cold ||
        current.accountId != binding.accountId ||
        response.id != request.id ||
        response.expiresAt != request.expiresAt) {
      throw const AccountSecurityException('冷钱包用途钥响应会话已失效');
    }
    return await session.open(response.body);
  } on AccountDataKeyException catch (error) {
    throw AccountSecurityException(error.message);
  } finally {
    session.dispose();
  }
}

String _lowerHex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

class CitizenApp extends StatefulWidget {
  const CitizenApp({
    super.key,
    required this.sdk,
    required this.accountSecurity,
    required this.currentUserContext,
    required this.finalizedIdentityResolver,
    required this.squareSessionProvider,
    required this.squareApiClient,
    required this.appPushService,
    required this.transactionHistory,
  });

  final CitizenSdk sdk;
  final AccountSecurityService accountSecurity;
  final CurrentUserContext currentUserContext;
  final FinalizedIdentityResolver finalizedIdentityResolver;
  final SquareSessionProvider squareSessionProvider;
  final SquareApiClient squareApiClient;
  final AppPushService appPushService;
  final WalletTransactionHistoryService transactionHistory;

  @override
  State<CitizenApp> createState() => _CitizenAppState();
}

class _CitizenAppState extends State<CitizenApp> {
  @override
  void dispose() {
    widget.accountSecurity.dispose();
    unawaited(_closeCitizenSdk(widget.sdk, widget.transactionHistory));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<CitizenSdk>.value(value: widget.sdk),
        Provider<AccountSecurityService>.value(value: widget.accountSecurity),
        Provider<CurrentUserContext>.value(value: widget.currentUserContext),
        Provider<FinalizedIdentityResolver>.value(
          value: widget.finalizedIdentityResolver,
        ),
        Provider<SquareSessionProvider>.value(
          value: widget.squareSessionProvider,
        ),
        Provider<SquareApiClient>.value(value: widget.squareApiClient),
        Provider<AppPushService>.value(value: widget.appPushService),
        Provider<WalletTransactionHistoryService>.value(
          value: widget.transactionHistory,
        ),
        Provider<sdk.ChatSdk>(
          create: (_) => createCitizenChatRuntime(
            accountSecurity: widget.accountSecurity,
            currentUserContext: widget.currentUserContext,
            squareSessionProvider: widget.squareSessionProvider,
            appPushService: widget.appPushService,
          ),
          dispose: (_, runtime) => unawaited(runtime.close()),
        ),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: '公民',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        // 只根据完整逻辑视口注入动态 UI 主题；不覆盖 MediaQuery。
        builder: (context, child) =>
            Theme(data: AppTheme.lightThemeFor(context), child: child!),
        home: const _AppLockGate(),
      ),
    );
  }
}

/// 按 CitizenSDK 的 checkpoint 合同先停止唯一轻节点，再释放 session。
///
/// App 生命周期回调不能等待 Future，因此调用方使用 [unawaited]；
/// 本函数内仍保证 stop 与 close 顺序，不用 close 绕过节点持久化。
Future<void> _closeCitizenSdk(
  CitizenSdk sdk,
  WalletTransactionHistoryService transactionHistory,
) async {
  await transactionHistory.stop();
  try {
    if (sdk.lifecycle == CitizenSdkLifecycle.running) {
      await sdk.stop();
    }
  } on Object catch (error, stackTrace) {
    AppLog.d('[CitizenSDK] 轻节点停止失败: $error\n$stackTrace');
    return;
  }
  try {
    await sdk.close();
  } on Object catch (error, stackTrace) {
    AppLog.d('[CitizenSDK] session 关闭失败: $error\n$stackTrace');
  }
}

/// 应用锁入口：先检查 PIN 锁 → 再检查设备锁 → 进入主界面。
class _AppLockGate extends StatefulWidget {
  const _AppLockGate();

  @override
  State<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<_AppLockGate>
    with WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _authenticated = false;
  bool _checking = true;
  bool _showDeviceLock = false;

  /// 后台超过此时长后回到前台需重新验证。
  static const Duration _sessionTimeout = Duration(minutes: 5);
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 短命 Chat 明文附件 purge 点之一：启动即清上次会话残留。
    // 崩溃/强杀会跳过退后台那次清理，没有这道兜底明文就会跨会话留在盘上。
    unawaited(_recoverChatArtifactsAndPurge());
    _checkLock();
  }

  /// 普通 Chat artifact 在首帧后整理，不能参与全局数据擦除启动门禁。
  Future<void> _recoverChatArtifactsAndPurge() async {
    try {
      await sdk.ChatRuntimeCore.recoverStartupArtifacts();
    } catch (error) {
      debugPrint('chat_startup_artifacts:recovery_failed:${error.runtimeType}');
    }
    await _purgePlainAttachments();
  }

  /// 清空解密出来的短命 Chat 附件。失败静默，不阻断 App 启动/切换。
  Future<void> _purgePlainAttachments() async {
    try {
      await sdk.ChatRuntimeCore.purgePlainAttachmentsWithoutAccount();
    } catch (_) {
      // 忽略：下次启动/切后台会再清一次。
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      // purge 点之二:退到后台即清明文，把明文窗口压到一次前台会话内。
      unawaited(_purgePlainAttachments());
    } else if (state == AppLifecycleState.resumed && _authenticated) {
      final paused = _pausedAt;
      if (paused != null &&
          DateTime.now().difference(paused) > _sessionTimeout) {
        AppLog.d('[AppLock] 后台超过 ${_sessionTimeout.inMinutes} 分钟,重锁入口');
        // 超时只重新锁定 App 入口（PIN/设备锁），不清会话签名密钥：
        // App 锁已拦住入口，会话密钥留到进程结束，避免每次重进都为发广场
        // 动态等低敏感操作重复生物识别。转账/投票/切换身份仍每次强制认证。
        setState(() {
          _authenticated = false;
          _checking = true;
          _showDeviceLock = false;
        });
        _checkLock();
      }
      _pausedAt = null;
    }
  }

  Future<void> _checkLock() async {
    // 1. 检查 PIN 锁
    final pinSet = await AppLockService.isPinSet();
    if (pinSet) {
      if (!mounted) return;
      setState(() => _checking = false);
      _showPinVerify();
      return;
    }

    // 2. 检查设备锁（存储在 SecureStorage，防 root 篡改）
    final deviceLockStr = await appSecureStorage.read(
      key: 'device_lock_enabled',
    );
    final deviceLockEnabled = deviceLockStr == 'true';
    if (deviceLockEnabled) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _showDeviceLock = true;
      });
      _authenticateDevice();
      return;
    }

    // 3. 无锁，直接进入
    if (!mounted) return;
    setState(() {
      _authenticated = true;
      _checking = false;
    });
  }

  Future<void> _showPinVerify() async {
    if (!mounted) return;
    // 诊断:定位"签名后多弹一次输入框"到底是谁 —— 若是本页,日志会给出时点。
    AppLog.d('[AppLock] 弹出 PIN 验证输入框');
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const PinInputPage(mode: PinInputMode.verify),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      setState(() => _authenticated = true);
    }
  }

  Future<void> _authenticateDevice() async {
    AppLog.d('[AppLock] 弹出设备锁验证');
    try {
      final success = await _localAuth.authenticate(
        localizedReason: BiometricAuthText.pick(
          zh: '请验证身份以进入应用',
          en: 'Verify your identity to open CitizenApp',
        ),
        authMessages: BiometricAuthText.messages(),
        biometricOnly: false,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: true,
      );
      if (!mounted) return;
      if (success) {
        setState(() => _authenticated = true);
      }
    } catch (_) {
      // 认证失败，保持锁定状态
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        body: Center(
          child: SizedBox(
            width: AppLayout.scaled(context, 24),
            height: AppLayout.scaled(context, 24),
            child: const CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primary,
            ),
          ),
        ),
      );
    }

    if (_authenticated) {
      // 账户门禁排在最后一环：无热钱包先进强制创建页，再放行主界面。
      return const AppPermissionGate(child: WalletGate(child: HomeTabGate()));
    }

    if (_showDeviceLock) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: AppLayout.scaled(context, 80),
                height: AppLayout.scaled(context, 80),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(
                    AppLayout.scaledValue(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withAlpha(50),
                      blurRadius: AppLayout.scaled(context, 24),
                      offset: Offset(0, AppLayout.scaled(context, 8)),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.lock_outline,
                  color: Colors.white,
                  size: AppLayout.scaled(context, 36),
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 32)),
              Text(
                '应用已锁定',
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 22),
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 8)),
              Text(
                '请验证身份以继续',
                style: TextStyle(
                  fontSize: AppLayout.scaled(context, 14),
                  color: AppTheme.textSecondary,
                ),
              ),
              SizedBox(height: AppLayout.scaled(context, 40)),
              SizedBox(
                width: AppLayout.scaled(context, 200),
                child: FilledButton.icon(
                  onPressed: _authenticateDevice,
                  icon: Icon(
                    Icons.fingerprint,
                    size: AppLayout.scaled(context, 22),
                  ),
                  label: const Text('验证身份'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // PIN 锁模式下，PinInputPage 已通过 Navigator 展示
    return Scaffold(
      body: Center(
        child: Container(
          width: AppLayout.scaled(context, 64),
          height: AppLayout.scaled(context, 64),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(AppLayout.scaledValue(16)),
          ),
          child: Icon(
            Icons.how_to_vote_outlined,
            color: Colors.white,
            size: AppLayout.scaled(context, 30),
          ),
        ),
      ),
    );
  }
}

/// AppShell 构造前读取用户首页偏好，避免先创建广场再异步跳到聊天。
class HomeTabGate extends StatefulWidget {
  const HomeTabGate({super.key, this.preferenceReader, this.shellBuilder});

  /// 测试只替换 UserIsar 读取。
  @visibleForTesting
  final Future<bool> Function()? preferenceReader;

  /// 测试只观察解析后的唯一初始索引，不构造真实五个业务 Tab。
  @visibleForTesting
  final Widget Function(int initialTabIndex)? shellBuilder;

  @override
  State<HomeTabGate> createState() => _HomeTabGateState();
}

class _HomeTabGateState extends State<HomeTabGate> {
  static const Duration _readTimeout = Duration(seconds: 5);
  int? _initialTabIndex;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _initialTabIndex = null;
      _error = null;
    });
    try {
      final openChat =
          await (widget.preferenceReader ??
                  UserIsar.instance.readOpenChatOnLaunch)()
              .timeout(_readTimeout);
      if (!mounted || generation != _generation) return;
      setState(() => _initialTabIndex = openChat ? 2 : 0);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '首页设置读取失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, key: const ValueKey('home-tab-gate-error')),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('home-tab-gate-retry'),
                onPressed: _load,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final initialTabIndex = _initialTabIndex;
    if (initialTabIndex == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppTheme.primary,
          ),
        ),
      );
    }
    return widget.shellBuilder?.call(initialTabIndex) ??
        AppShell(initialTabIndex: initialTabIndex);
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialTabIndex = 0,
    this.chatRuntimeFactory,
    this.tabBuilder,
    this.openedPushData,
    this.initialPushDataLoader,
  }) : assert(initialTabIndex == 0 || initialTabIndex == 2);

  /// 只允许广场(0)或聊天(2)作为普通启动首页。
  final int initialTabIndex;

  /// 测试只注入构造计数；生产固定首次进入 Chat Tab 时才创建 [sdk.ChatSdk]。
  @visibleForTesting
  final sdk.ChatSdk Function()? chatRuntimeFactory;

  /// 测试只替换五个主页面，避免为了验证壳层懒加载而启动真实链、网络或数据库。
  @visibleForTesting
  final Widget Function(int tabIndex, sdk.ChatSdk? chatRuntime)? tabBuilder;

  /// 测试只注入 App 级“点击推送打开”数据；生产直接监听 Firebase。
  @visibleForTesting
  final Stream<Map<String, dynamic>>? openedPushData;

  /// 测试只注入冷启动推送；生产读取 Firebase 唯一 initial message。
  @visibleForTesting
  final Future<Map<String, dynamic>?> Function()? initialPushDataLoader;

  /// 主 Tab 的系统栏样式由壳层单源控制，避免保活页面留下上一页的明暗状态。
  ///
  /// 「我的」顶部是照片，使用浅色图标；其余四个主 Tab 都是浅色背景，必须使用深色
  /// 图标。子路由的 AppBar 仍可用更靠前的 AnnotatedRegion 覆盖本样式。
  static SystemUiOverlayStyle systemUiOverlayStyleForTab(int tabIndex) {
    final statusStyle = tabIndex == 4
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return statusStyle.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: AppTheme.surfaceCard,
      systemNavigationBarIconBrightness: Brightness.dark,
    );
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final AppUpdateController _updateController = AppUpdateController.instance;
  late final ValueNotifier<int> _selectedTab;
  sdk.ChatSdk? _chatRuntime;
  late int _currentIndex;
  int _pendingVoteCount = 0;
  int _squareNotifyCount = 0;
  bool _isRooted = false;
  StreamSubscription<Map<String, dynamic>>? _pushOpenSub;
  StreamSubscription<AppPushToken>? _pushTokenSub;

  /// Chat 运行态只在用户首次打开聊天 Tab 时创建。广场、用户、钱包或公民页启动
  /// 不得因为构造 ChatSdk 而进入 Chat 的文件、密钥或网络生命周期。
  sdk.ChatSdk get _chatRuntimeForTab => _chatRuntime ??=
      (widget.chatRuntimeFactory ?? () => context.read<sdk.ChatSdk>())();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _selectedTab = ValueNotifier<int>(_currentIndex);
    _updateController.addListener(_handleUpdateStateChanged);
    _checkRootStatus();
    // 启动后异步检查 Release 更新，只更新设置页状态，不阻塞主界面进入。
    _updateController.check();
    // 点击推送属于 App 导航，不得为此提前构造 ChatSdk。聊天推送只表示邮箱变化；
    // 广场推送仍直接切广场 Tab。
    unawaited(_startPushOpenRouting());
  }

  Future<void> _startPushOpenRouting() async {
    try {
      final injectedOpened = widget.openedPushData;
      if (injectedOpened != null) {
        _pushOpenSub = injectedOpened.listen(
          (data) => unawaited(_handleOpenedPushData(data)),
        );
        final initial = await widget.initialPushDataLoader?.call();
        if (initial != null) await _handleOpenedPushData(initial);
        return;
      }

      final appPush = context.read<AppPushService>();
      final endpoint = await appPush.initialize();
      await _registerCitizenServePush(endpoint);
      if (!mounted) return;
      _pushOpenSub = appPush.openedMessages.listen(
        (data) => unawaited(_handleOpenedPushData(data)),
      );
      _pushTokenSub = appPush.tokenChanges.listen(
        (token) => unawaited(_registerCitizenServePush(token)),
      );
      final initial = await appPush.initialMessage();
      if (initial != null) await _handleOpenedPushData(initial);
    } catch (error, stackTrace) {
      AppLog.d('[AppPush] 打开路由初始化失败: $error\n$stackTrace');
    }
  }

  Future<void> _handleOpenedPushData(Map<String, dynamic> data) async {
    if (!mounted) return;
    if (data['kind'] == 'square_post' || data['kind'] == 'storage_cleanup') {
      _openSquareTab();
      return;
    }
    if (ChatPushService.isWakeData(data)) {
      try {
        await _chatRuntimeForTab.handleWake();
      } catch (_) {
        // 点击通知时若会话或网络尚未恢复，持久保存一次邮箱变化提示。
        await ChatPushService.storeWake();
      }
    }
  }

  Future<void> _registerCitizenServePush(AppPushToken endpoint) async {
    try {
      final sessionProvider = context.read<SquareSessionProvider>();
      final client = context.read<SquareApiClient>();
      final session = await sessionProvider.ensureSession();
      if (session == null) return;
      await client.registerPushEndpoint(session: session, endpoint: endpoint);
    } catch (error, stackTrace) {
      // 普通通知是软功能；登记失败不得阻断主界面、聊天或广场读取，Token刷新会再次尝试。
      AppLog.d('[AppPush] CitizenServe端点登记失败: $error\n$stackTrace');
    }
  }

  void _openSquareTab() {
    if (!mounted || _currentIndex == 0) return;
    _selectedTab.value = 0;
    setState(() => _currentIndex = 0);
  }

  @override
  void dispose() {
    _updateController.removeListener(_handleUpdateStateChanged);
    unawaited(_pushOpenSub?.cancel());
    unawaited(_pushTokenSub?.cancel());
    _selectedTab.dispose();
    super.dispose();
  }

  void _handleUpdateStateChanged() {
    if (!mounted) return;
    // 我的页懒建缓存失效以刷新「设置有更新」红点。
    _tabCache[4] = null;
    setState(() {});
  }

  Future<void> _checkRootStatus() async {
    final rooted = await ScreenshotGuard.isDeviceRooted();
    if (!mounted) return;
    setState(() => _isRooted = rooted);
  }

  late final Widget _citizenPage = CitizenTabPage(
    onPendingVoteCountChanged: (count) {
      if (mounted && count != _pendingVoteCount) {
        setState(() => _pendingVoteCount = count);
      }
    },
  );

  /// 广场落地页（index 0）：发帖通知红点数经回调上抛到底部 tab；selectedTab
  /// 广播让广场在被切回时清广场红点（进广场清广场、关注红点另在关注子 tab 清）。
  late final Widget _squarePage = SquareTab(
    selectedTab: _selectedTab,
    tabIndex: 0,
    onSquareUnreadChanged: (count) {
      if (mounted && count != _squareNotifyCount) {
        setState(() => _squareNotifyCount = count);
      }
    },
  );

  /// 顶层 tab 懒建缓存：仅访问过的 index 建真页并由 IndexedStack 保活，未访问
  /// 的用占位，避免「打开即全建」把 42k 行政区同步 / Chat runtime / 广场拉流等
  /// 全拖到启动。UserIsar 选定的广场(0)或聊天(2)首页只建其一，其余点到才建。
  static const int _tabCount = 5;
  final List<Widget?> _tabCache = List<Widget?>.filled(_tabCount, null);

  Widget _buildTab(int index) {
    final injected = widget.tabBuilder;
    if (injected != null) {
      return injected(index, index == 2 ? _chatRuntimeForTab : null);
    }
    switch (index) {
      case 0:
        return _squarePage;
      case 1:
        return _citizenPage;
      case 2:
        return ChatTab(
          runtime: _chatRuntimeForTab,
          selectedTab: _selectedTab,
          tabIndex: 2,
        );
      case 3:
        return const TransactionTabPage();
      case 4:
        return MyTab(showSettingsUpdateDot: _updateController.state.hasUpdate);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 当前页按需建入缓存并保活，未访问的页用占位，避免启动即全建。
  List<Widget> _lazyPages() {
    _tabCache[_currentIndex] ??= _buildTab(_currentIndex);
    return List<Widget>.generate(
      _tabCount,
      (i) => _tabCache[i] ?? const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      body: Column(
        children: [
          if (_isRooted)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              padding: EdgeInsets.symmetric(
                horizontal: AppLayout.scaled(context, 12),
                vertical: AppLayout.scaled(context, 10),
              ),
              decoration: AppTheme.bannerDecoration(AppTheme.danger),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      color: AppTheme.danger,
                      size: AppLayout.scaled(context, 18),
                    ),
                    SizedBox(width: AppLayout.scaled(context, 8)),
                    Expanded(
                      child: Text(
                        '检测到设备已 root/越狱，密钥安全无法保障',
                        style: TextStyle(
                          color: AppTheme.danger,
                          fontSize: AppLayout.scaled(context, 13),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _lazyPages()),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceCard,
          border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
        ),
        child: NavigationBar(
          // 只补充放大后导航文字需要的高度，图标、边距和指示器保持结构令牌尺寸。
          height: AppLayout.navigationBarHeight(context),
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            // IndexedStack 会保活旧页面，因此必须额外广播唯一活动 Tab；
            // ChatTab 不能把“仍在 widget tree”误判为“当前可同步”。
            _selectedTab.value = index;
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _squareNotifyCount > 0,
                label: Text(
                  _squareNotifyCount > 99 ? '99+' : '$_squareNotifyCount',
                  style: TextStyle(fontSize: AppLayout.scaled(context, 10)),
                ),
                child: SvgPicture.asset(
                  'assets/icons/tank.svg',
                  width: AppLayout.scaled(context, 26),
                  height: AppLayout.scaled(context, 26),
                  colorFilter: const ColorFilter.mode(
                    AppTheme.textTertiary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              selectedIcon: Badge(
                isLabelVisible: _squareNotifyCount > 0,
                label: Text(
                  _squareNotifyCount > 99 ? '99+' : '$_squareNotifyCount',
                  style: TextStyle(fontSize: AppLayout.scaled(context, 10)),
                ),
                child: SvgPicture.asset(
                  'assets/icons/tank.svg',
                  width: AppLayout.scaled(context, 26),
                  height: AppLayout.scaled(context, 26),
                  colorFilter: const ColorFilter.mode(
                    AppTheme.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              label: '广场',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _pendingVoteCount > 0,
                label: Text(
                  '$_pendingVoteCount',
                  style: TextStyle(fontSize: AppLayout.scaled(context, 10)),
                ),
                child: const Icon(Icons.how_to_vote_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _pendingVoteCount > 0,
                label: Text(
                  '$_pendingVoteCount',
                  style: TextStyle(fontSize: AppLayout.scaled(context, 10)),
                ),
                child: const Icon(Icons.how_to_vote),
              ),
              label: '公民',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.textsms_outlined,
                size: AppLayout.scaled(context, 22),
              ),
              selectedIcon: Icon(
                Icons.textsms_rounded,
                size: AppLayout.scaled(context, 22),
              ),
              label: '聊天',
            ),
            NavigationDestination(
              icon: SvgPicture.asset(
                'assets/icons/scale.svg',
                width: AppLayout.scaled(context, 22),
                height: AppLayout.scaled(context, 22),
                colorFilter: const ColorFilter.mode(
                  AppTheme.textTertiary,
                  BlendMode.srcIn,
                ),
              ),
              selectedIcon: SvgPicture.asset(
                'assets/icons/scale.svg',
                width: AppLayout.scaled(context, 22),
                height: AppLayout.scaled(context, 22),
                colorFilter: const ColorFilter.mode(
                  AppTheme.primary,
                  BlendMode.srcIn,
                ),
              ),
              label: '交易',
            ),
            NavigationDestination(
              icon: UpdateDotBadge(
                show: _updateController.state.hasUpdate,
                dotKey: const Key('my-tab-update-dot'),
                child: const Icon(Icons.person_outline),
              ),
              selectedIcon: UpdateDotBadge(
                show: _updateController.state.hasUpdate,
                dotKey: const Key('my-tab-selected-update-dot'),
                child: const Icon(Icons.person),
              ),
              label: '我的',
            ),
          ],
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('app-shell-system-ui-style'),
      value: AppShell.systemUiOverlayStyleForTab(_currentIndex),
      child: scaffold,
    );
  }
}
