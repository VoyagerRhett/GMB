import 'package:citizen_sdk/citizen_sdk.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/citizen/public/data/admin_division_store.dart';
import 'package:citizenapp/citizen/public/data/area_path_formatter.dart';
import 'package:citizenapp/citizen/public/data/isar_admin_division_store.dart';
import 'package:citizenapp/citizen/public/data/public_provinces.dart';
import 'package:citizenapp/citizen/cid/cid_generator.dart';
import 'package:citizenapp/chat/tatachat_sdk_adapter.dart';
import 'package:citizenapp/my/user/contact_service.dart';
import 'package:citizenapp/my/myid/citizen_identity_transaction.dart';
import 'package:citizenapp/my/myid/citizen_identity_chain_reader.dart';
import 'package:citizenapp/qr/pages/qr_sign_session_page.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/signer/signing.dart' show kOpSignCidRebind;

import 'current_user_context.dart';
import 'finalized_identity_resolver.dart';
import 'identity_badge_snapshot_store.dart';

/// 身份页身份档。
///
/// 身份钥匙 = **CID 绑定的钱包账户**（经 [FinalizedIdentityResolver] 对当前默认账户
/// 做 finalized 闭环验证）。身份主键是 CID 号，
/// 绑定账户切换(换绑)即跟随;链上一人一 CID 一账户一身份,故无多身份冲突。
enum MyIdTier {
  /// 访客(默认匿名)。含两子态,均用同一张访客卡、同一枚访客徽章:
  /// - **纯访客**:账户从未占号(`cidNumber` 为空)。
  /// - **匿名已注册**:账户自助占了一个 CID 并双向绑定,但链上无 `VotingIdentityByCid`
  ///   (`cidNumber` 非空,见 [MyIdState.isAnonymousRegistered])。仅在第 1 卡展示该 CID 号,
  ///   不升级徽章色/卡片(投票/竞选身份只能经注册局线下升级)。
  visitor,

  /// 钱包与永久 CID 双向绑定闭环完整，且存在 `VotingIdentityByCid`。
  voting,

  /// 在投票公民之上再有 `CandidateIdentityByCid` 对应的竞选身份。
  candidate,
}

/// 护照有效期/生命周期状态(仅公民档有意义;`queryFailed` 为链读失败兜底)。
enum MyIdStatus { normal, notYetValid, expired, revoked, queryFailed }

/// CID 钱包换绑的私有数据交接编排；只调用客户端端到端加密边界。
class CidAccountDataHandover {
  CidAccountDataHandover({
    required UserContactService contactService,
    required AccountSecurityService accountSecurity,
    required ChatSdk chatRuntime,
  }) : _contactService = contactService,
       _chatRuntime = chatRuntime,
       _accountSecurity = accountSecurity;

  final UserContactService _contactService;
  final ChatSdk _chatRuntime;
  final AccountSecurityService _accountSecurity;

  Future<void> stage({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    // 顶层 intent 必须先于任何子域 stage 持久化；中途崩溃会保留 preparing，
    // finalized 恢复不得把尚未完成的子域猜成空库。
    await _accountSecurity.recordPendingAccountDataHandover(
      source: source,
      target: target,
    );
    try {
      await _chatRuntime.stageAccountHandover(
        source: source.toChatDataBinding(),
        target: target.toChatDataBinding(),
      );
      await _contactService.stageAccountHandover(
        source: source,
        target: target,
      );
      await _accountSecurity.markPendingAccountDataHandoverReady(
        source: source,
        target: target,
      );
    } catch (stageError, stageStackTrace) {
      // 普通异常仍在当前调用栈内，必须主动聚合丢弃两个子域，避免 preparing
      // 长期阻断 Chat；进程崩溃不会执行此 catch，持久 intent 会留给显式恢复。
      try {
        await discard(source: source, target: target);
      } catch (discardError, discardStackTrace) {
        Error.throwWithStackTrace(
          StateError(
            'CID 私有数据交接 stage 失败且自动丢弃失败：'
            'stage=$stageError；discard=$discardError',
          ),
          discardStackTrace,
        );
      }
      Error.throwWithStackTrace(stageError, stageStackTrace);
    }
  }

  Future<void> commit({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    final pending = await _requirePendingIntent(source: source, target: target);
    if (pending.state != AccountDataHandoverState.ready) {
      throw StateError('CID 私有数据交接仍处于 preparing，禁止 commit');
    }
    await _chatRuntime.commitAccountHandover(
      source: source.toChatDataBinding(),
      target: target.toChatDataBinding(),
    );
    await _contactService.commitAccountHandover(source: source, target: target);
    await _accountSecurity.clearPendingAccountDataHandover(
      source: source,
      target: target,
    );
  }

  Future<void> discard({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    final pending = await _accountSecurity.readPendingAccountDataHandover();
    if (pending == null) return;
    if (!_sameBinding(pending.source, source) ||
        !_sameBinding(pending.target, target)) {
      throw StateError('CID 私有数据交接 intent 与 discard 参数不一致');
    }
    final failures = <String>[];
    try {
      await _chatRuntime.discardAccountHandover(
        source: source.toChatDataBinding(),
        target: target.toChatDataBinding(),
      );
    } catch (error) {
      failures.add('Chat：$error');
    }
    try {
      await _contactService.discardAccountHandover(
        source: source,
        target: target,
      );
    } catch (error) {
      failures.add('通讯录：$error');
    }
    if (failures.isNotEmpty) {
      // 任一子域失败都保留唯一恢复 intent；下一次显式 discard 继续逐域重试。
      throw StateError('CID 私有数据交接丢弃失败：${failures.join('；')}');
    }
    await _accountSecurity.clearPendingAccountDataHandover(
      source: source,
      target: target,
    );
  }

  Future<void> resumeForFinalizedBinding(AccountDataBinding current) async {
    final pending = await _accountSecurity.readPendingAccountDataHandover();
    if (pending == null) return;
    final target = pending.target;
    if (target.genesisHash != current.genesisHash ||
        target.cidNumber != current.cidNumber ||
        target.bindingRevision != current.bindingRevision ||
        target.accountId != current.accountId) {
      return;
    }
    if (pending.state != AccountDataHandoverState.ready) {
      throw StateError('CID 私有数据交接仍处于 preparing，禁止 finalized commit');
    }
    await commit(source: pending.source, target: target);
  }

  /// 只按 finalized 公开真值准备端内私有数据状态，不读取钱包账户 child。
  ///
  /// 精确命中交接目标时保留暂存，等待 [completeFinalizedBinding] 提交；确认交易未生效
  /// 或链上版本已经越过目标时清掉旁路暂存。没有可提交交接且绑定确实变化时，只隔离
  /// 此前密文和派生状态，不读取此前账户、此前设备或任何额外密钥。
  Future<void> prepareFinalizedBinding({
    required AccountDataBinding current,
    AccountDataBinding? previous,
  }) async {
    final pending = await _accountSecurity.readPendingAccountDataHandover();
    if (pending != null && _sameBinding(pending.target, current)) {
      if (pending.state != AccountDataHandoverState.ready) {
        throw StateError('CID 私有数据交接仍处于 preparing，禁止收敛 finalized binding');
      }
      return;
    }
    if (pending != null &&
        pending.target.genesisHash == current.genesisHash &&
        pending.target.cidNumber == current.cidNumber &&
        (_sameBinding(pending.source, current) ||
            current.bindingRevision >= pending.target.bindingRevision)) {
      await discard(source: pending.source, target: pending.target);
    }
    if (previous == null ||
        _sameBinding(previous, current) ||
        previous.genesisHash != current.genesisHash ||
        previous.cidNumber != current.cidNumber ||
        previous.bindingRevision >= current.bindingRevision) {
      return;
    }
    await _contactService.isolateInaccessibleBinding(previous);
    await _chatRuntime.isolateInaccessibleBinding(
      previous: previous.toChatDataBinding(),
      current: current.toChatDataBinding(),
    );
  }

  /// 当前设备子钥登记成功后收敛 Session、交接密文和 Chat 当前设备状态。
  Future<void> completeFinalizedBinding(AccountDataBinding current) async {
    SquareApiClient.activateFinalizedBinding(
      cidNumber: current.cidNumber,
      bindingRevision: current.bindingRevision,
      accountId: current.accountId,
    );
    await resumeForFinalizedBinding(current);
    try {
      await _chatRuntime.convergeFinalizedBinding(current.toChatDataBinding());
    } catch (error) {
      // Chat 初始化依赖推送与网络；失败不能回滚已经 finalized 的 CID 控制权。
      // 当前绑定已生效且此前凭证已由 Worker 撤销，进入 Chat 时会继续幂等补齐。
      AppLog.d('chat finalized binding convergence deferred: $error');
    }
  }

  static bool _sameBinding(AccountDataBinding left, AccountDataBinding right) =>
      left.genesisHash == right.genesisHash &&
      left.cidNumber == right.cidNumber &&
      left.bindingRevision == right.bindingRevision &&
      left.accountId == right.accountId;

  Future<
    ({
      AccountDataBinding source,
      AccountDataBinding target,
      AccountDataHandoverState state,
    })
  >
  _requirePendingIntent({
    required AccountDataBinding source,
    required AccountDataBinding target,
  }) async {
    final pending = await _accountSecurity.readPendingAccountDataHandover();
    if (pending == null ||
        !_sameBinding(pending.source, source) ||
        !_sameBinding(pending.target, target)) {
      throw StateError('CID 私有数据交接 intent 缺失或已变化');
    }
    return pending;
  }
}

/// 身份页只读链上状态(身份账户维度)。
class MyIdState {
  const MyIdState({
    required this.tier,
    this.status,
    this.votingAccountId,
    this.cidNumber,
    this.residenceDistrict,
    this.passportValidFrom,
    this.passportValidUntil,
    this.familyName,
    this.givenName,
    this.citizenSexLabel,
    this.birthDistrict,
    this.citizenBirthDate,
    this.errorMessage,
  });

  final MyIdTier tier;

  /// 公民档的护照状态;访客为 null,链读失败为 [MyIdStatus.queryFailed]。
  final MyIdStatus? status;

  /// 链上投票绑定账户 = CID 绑定账户地址(SS58)。访客不显示,为 null。
  final String? votingAccountId;
  final String? cidNumber;

  /// 预 join 的居住选区「省·市·镇」(service 层查字典拼好,UI 直接展示)。
  final String? residenceDistrict;

  /// YYYY-MM-DD,来自链上 YYYYMMDD 整数。
  final String? passportValidFrom;
  final String? passportValidUntil;

  // ── 竞选公民专属公开字段 ──
  final String? familyName;
  final String? givenName;

  /// 男/女。
  final String? citizenSexLabel;
  final String? birthDistrict;

  /// 出生日期 YYYY-MM-DD,来自链上竞选身份 birth_date(YYYYMMDD 整数)。
  final String? citizenBirthDate;

  final String? errorMessage;

  bool get isCitizen => tier == MyIdTier.voting || tier == MyIdTier.candidate;

  /// 访客卡的「已占匿名 CID」子态:访客档 + 已绑定 CID 号(无投票身份)。
  /// UI 据此在第 1 卡展示 CID 号、把右上按钮从「注册」切成「更换」。
  bool get isAnonymousRegistered =>
      tier == MyIdTier.visitor && (cidNumber?.trim().isNotEmpty ?? false);

  /// 徽章分色信号:visitor/voting/candidate,与 [IdentityBadgeSnapshotStore] 契约一致。
  String get identityLevel => switch (tier) {
    MyIdTier.candidate => 'candidate',
    MyIdTier.voting => 'voting',
    MyIdTier.visitor => 'visitor',
  };
}

class MyIdService {
  MyIdService({
    required CitizenSdkWallet wallet,
    required CitizenSigning signing,
    required AccountSecurityService accountSecurity,
    required CurrentUserContext currentUserContext,
    required FinalizedIdentityResolver identityResolver,
    required SquareSessionProvider sessionProvider,
    required ChatSdk Function() chatRuntime,
    UserContactService? contactService,
    required CitizenChain chain,
    required CitizenTransactions transactions,
    AdminDivisionStore? divisionStore,
    IdentityBadgeSnapshotStore? badgeSnapshotStore,
    CitizenIdentityTransaction? identityTransaction,
    CidAccountDataHandover? dataHandover,
    DateTime Function()? nowProvider,
    int Function()? cidYearProvider,
  }) : _wallet = wallet,
       _signing = signing,
       _accountSecurity = accountSecurity,
       _currentUserContext = currentUserContext,
       _sessionProvider = sessionProvider,
       _chatRuntime = chatRuntime,
       _contactService = contactService,
       _divisionStore = divisionStore ?? IsarAdminDivisionStore(),
       _badgeSnapshotStore = badgeSnapshotStore ?? IdentityBadgeSnapshotStore(),
       _identityResolver = identityResolver,
       _identityTransaction =
           identityTransaction ??
           CitizenIdentityTransaction(chain: chain, transactions: transactions),
       _dataHandoverOverride = dataHandover,
       _chain = chain,
       _nowProvider = nowProvider ?? _beijingNow,
       _cidYearProvider = cidYearProvider ?? _utcYear;

  final CitizenSdkWallet _wallet;
  final CitizenSigning _signing;
  final AccountSecurityService _accountSecurity;
  final CurrentUserContext _currentUserContext;
  final SquareSessionProvider _sessionProvider;
  final ChatSdk Function() _chatRuntime;
  final UserContactService? _contactService;
  final AdminDivisionStore _divisionStore;
  final IdentityBadgeSnapshotStore _badgeSnapshotStore;
  final FinalizedIdentityResolver _identityResolver;
  final CitizenIdentityTransaction _identityTransaction;
  final CidAccountDataHandover? _dataHandoverOverride;

  /// 身份只读与 Wallet 页面不得构造 Chat 运行态；只有实际 CID 换绑动作首次访问时
  /// 才创建跨域交接编排，并复用本服务已经确定的钱包边界。
  late final CidAccountDataHandover _dataHandover =
      _dataHandoverOverride ??
      CidAccountDataHandover(
        contactService:
            _contactService ??
            UserContactService(
              accountSecurity: _accountSecurity,
              currentUserContext: _currentUserContext,
              sessionProvider: _sessionProvider,
              chainReader: CitizenIdentityChainReader(chain: _chain),
              autoSync: false,
            ),
        accountSecurity: _accountSecurity,
        chatRuntime: _chatRuntime(),
      );

  final CitizenChain _chain;

  final DateTime Function() _nowProvider;
  final int Function() _cidYearProvider;

  /// 链上护照有效期窗口按 UTC+8 判定(与 runtime `can_vote` 口径一致),
  /// 避免本机时区在跨日边界把"今天"算差一天。
  static DateTime _beijingNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  /// 自助占号的 CID 年份取 **UTC 当前年**(与 CID 生成金标口径一致,不随本机时区漂移)。
  static int _utcYear() => DateTime.now().toUtc().year;

  /// 读取当前默认账户对应用户的身份状态。
  ///
  /// 身份主键 = CID 号；[FinalizedIdentityResolver] 只读取账户顺序第一项。该账户没有
  /// CID 时就是访客，禁止扫描其它账户；命中后再取 finalized 身份闭环：CID Active、
  /// CID↔账户双向绑定、`VotingIdentityByCid`（有 `Candidate` 才是竞选身份）。
  Future<MyIdState> getState() async {
    FinalizedIdentity? resolved;
    try {
      resolved = await _identityResolver.resolve();
    } catch (e) {
      AppLog.d('myid identity resolve failed: $e');
      // 链读失败不静默降级访客、不覆盖徽章快照,交由 UI 提示重试。
      return const MyIdState(
        tier: MyIdTier.visitor,
        status: MyIdStatus.queryFailed,
        errorMessage: '链上身份读取失败',
      );
    }
    if (resolved == null) {
      // 没有任何有效热、冷账户 → 无默认账户 → 访客（引导创建钱包）。
      return const MyIdState(tier: MyIdTier.visitor, errorMessage: '请先创建钱包');
    }

    final identityAccountId = resolved.accountId;
    final chainIdentity = resolved.snapshot;

    if (chainIdentity == null) {
      return const MyIdState(tier: MyIdTier.visitor);
    }

    if (chainIdentity.isAnonymous) {
      // 匿名已注册:访客卡 + 展示 CID;徽章仍访客色(决策:不新增卡/色)。
      await _persistBadgeSnapshot(chainIdentity.cidNumber, 'visitor');
      return MyIdState(
        tier: MyIdTier.visitor,
        votingAccountId: identityAccountId,
        cidNumber: chainIdentity.cidNumber,
      );
    }

    final voting = _decodeVotingIdentity(chainIdentity.votingIdentity!);
    if (voting == null) {
      // 有记录但解不开 = 数据异常,不静默当访客。
      return const MyIdState(
        tier: MyIdTier.visitor,
        status: MyIdStatus.queryFailed,
        errorMessage: '身份数据解析失败',
      );
    }

    final status = _deriveStatus(voting);
    final residence = await _resolveDistrict(
      voting.resProvince,
      voting.resCity,
      voting.resTown,
    );

    final candidateRaw = chainIdentity.candidateIdentity;
    final candidate = candidateRaw == null
        ? null
        : _decodeCandidateIdentity(candidateRaw);
    final tier = candidate != null ? MyIdTier.candidate : MyIdTier.voting;
    await _persistBadgeSnapshot(
      chainIdentity.cidNumber,
      tier == MyIdTier.candidate ? 'candidate' : 'voting',
    );

    final birth = candidate == null
        ? null
        : await _resolveDistrict(
            candidate.birthProvince,
            candidate.birthCity,
            candidate.birthTown,
          );

    return MyIdState(
      tier: tier,
      status: status,
      votingAccountId: identityAccountId,
      cidNumber: chainIdentity.cidNumber,
      residenceDistrict: residence,
      passportValidFrom: _formatDateInt(voting.passportValidFrom),
      passportValidUntil: _formatDateInt(voting.passportValidUntil),
      familyName: candidate?.familyName,
      givenName: candidate?.givenName,
      citizenSexLabel: candidate == null
          ? null
          : (candidate.sex == 1 ? '女' : '男'),
      birthDistrict: birth,
      citizenBirthDate: candidate == null
          ? null
          : _formatDateInt(candidate.birthDate),
    );
  }

  /// 自助占一个匿名 CID,把它绑定到用户所选的钱包账户 [bindAccountId](null = 账户0),
  /// 返回占用的 CID 号。
  ///
  /// 身份主键 = CID 号;绑定账户是用户自选的鉴权凭证(可任意 `//n`,私钥泄漏可换绑)。
  /// [institution] 取 [kCidInstitutionCitizen](公民)/ [kCidInstitutionResident](居民)。
  /// 年份取 UTC 当前年;CID = f(绑定 accountId, institution, year),撞号由链端 registry
  /// 兜底吸收。提交经 `self_occupy_cid` 由绑定账户自签自付费(触发一次生物识别);成功后
  /// 广播身份绑定变化,常驻页重读身份。
  Future<String> registerAnonymousCid({
    required BuildContext? context,
    required String institution,
    String? bindAccountId,
  }) async {
    final state = await _wallet.getState();
    final defaultAccount = state.defaultAccount;
    if (defaultAccount == null) {
      throw const AccountSecurityException('无钱包账户,请先创建钱包');
    }
    // 绑定账户为当前默认账户，或用户从 SDK 统一热／冷账户目录中选择的账户。
    final String resolvedBindAccountId;
    if (bindAccountId == null || bindAccountId == defaultAccount.accountId) {
      resolvedBindAccountId = defaultAccount.accountId;
    } else {
      final account = _findAccount(state, bindAccountId);
      if (account == null) {
        throw const AccountSecurityException('绑定账户不存在');
      }
      resolvedBindAccountId = account.accountId;
    }
    final cid = generateCitizenCid(
      accountId: resolvedBindAccountId,
      institution: institution,
      year: _cidYearProvider(),
    );
    await _identityTransaction.selfOccupyCid(
      cidNumber: cid,
      accountId: resolvedBindAccountId,
      externalSigning: (pending) => context == null || !context.mounted
          ? Future<String?>.value()
          : showCitizenSdkQrResponse(
              context,
              request: pending.qrRequest,
              expiresAt: BigInt.from(
                pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
              ),
            ),
    );
    final finalized = await _requireFinalizedBinding(
      cidNumber: cid,
      accountId: resolvedBindAccountId,
    );
    // CID 注册是正式交易；finalized 后这里只推进公开绑定与数据交接。设备数据钥和
    // P-256 子钥分别由真实数据缺钥、Worker 明确未登记触发，禁止在此额外鉴权。
    try {
      await _finishResolvedBinding(finalized);
    } on Object catch (error) {
      // finalized 链身份已经成立，本机公开绑定或数据收敛失败不能反向冒充“注册失败”。
      // `_finishFinalizedBinding` 的 finally 已广播新身份；具体本机能力在真实访问时
      // 继续按安全边界自愈或显示自身错误。
      AppLog.d('CID finalized 后本机绑定收敛待后续自愈: $error');
    }
    return cid;
  }

  /// 把当前身份 CID [cidNumber] 换绑到另一本地账户 [newAccountId]。
  ///
  /// 当前账户 = **当前 CID 绑定账户**(经 [FinalizedIdentityResolver] 解析,可为任意 `//n`,
  /// 非恒账户0),对含创世、当前绑定、revision 与 expires_at 的授权载荷签名;新账户自签
  /// 提交 `self_rebind_cid_account_id`(当前、新账户各签名一次)。换绑成功后 CID 归
  /// 新账户、广播身份绑定变化,常驻页/身份页跟随。
  /// 仅**匿名 CID** 可自助换绑;投票/竞选链端强制走注册局(`CivicRebindRequiresRegistrar`)。
  Future<void> rebindCidTo({
    required BuildContext? buildContext,
    required String cidNumber,
    required String newAccountId,
  }) async {
    final resolved = await _identityResolver.resolve();
    if (resolved == null || !resolved.isRegistered) {
      throw const AccountSecurityException('当前无已注册身份,无法换绑');
    }
    final currentAccountId = resolved.accountId;
    final resolvedCidNumber = resolved.snapshot?.cidNumber;
    if (resolvedCidNumber == null || resolvedCidNumber != cidNumber) {
      throw const AccountSecurityException('当前链上身份与待换绑 CID 不一致');
    }
    final newAccount = _findAccount(await _wallet.getState(), newAccountId);
    if (newAccount == null) {
      throw const AccountSecurityException('目标账户不存在');
    }
    if (newAccount.accountId == currentAccountId) {
      throw const AccountSecurityException('目标账户与当前身份账户相同');
    }
    final context = await _identityTransaction
        .fetchSelfRebindAuthorizationContext(cidNumber);
    if (context.currentAccountId != currentAccountId) {
      throw const AccountSecurityException('CID 当前绑定账户已经变化，请刷新后重试');
    }
    final source = AccountDataBinding(
      genesisHash: '0x${_bytesToHex(context.genesisHash)}',
      cidNumber: cidNumber,
      bindingRevision: context.expectedBindingRevision.toInt(),
      accountId: currentAccountId,
    );
    final target = AccountDataBinding(
      genesisHash: source.genesisHash,
      cidNumber: cidNumber,
      bindingRevision: source.bindingRevision + 1,
      accountId: newAccount.accountId,
    );
    final currentAccountDigest =
        CitizenIdentityTransaction.buildRebindSigningDigest(
          genesisHash: context.genesisHash,
          cidNumber: cidNumber,
          currentAccountId: currentAccountId,
          newAccountId: newAccount.accountId,
          expectedBindingRevision: context.expectedBindingRevision,
          expiresAt: context.expiresAt,
        );
    if (buildContext != null && !buildContext.mounted) {
      throw const AccountSecurityException('当前页面已经关闭');
    }
    final currentAccountSignature = await signCitizenPayload(
      signing: _signing,
      context: buildContext,
      accountId: currentAccountId,
      payload: currentAccountDigest,
      action: kOpSignCidRebind,
    );
    await _dataHandover.stage(source: source, target: target);
    try {
      await _identityTransaction.selfRebindCidAccount(
        cidNumber: cidNumber,
        newAccountId: newAccount.accountId,
        currentAccountId: currentAccountId,
        context: context,
        currentAccountSignature: currentAccountSignature,
        externalSigning: (pending) =>
            buildContext == null || !buildContext.mounted
            ? Future<String?>.value()
            : showCitizenSdkQrResponse(
                buildContext,
                request: pending.qrRequest,
                expiresAt: BigInt.from(
                  pending.expiresAt.millisecondsSinceEpoch ~/ 1000,
                ),
              ),
      );
    } catch (error, stackTrace) {
      try {
        await _dataHandover.discard(source: source, target: target);
      } catch (cleanupError) {
        // 原交易失败才是本次换绑结果；清理失败保留幂等暂存，下一次 finalized 对账再清。
        AppLog.d('CID 换绑失败后的私有数据暂存清理待重试: $cleanupError');
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    // SDK 已核验交易执行，业务层已在同一 finalized 块核对目标绑定。
    await _finishFinalizedBinding(target);
  }

  /// 注册身份前的自付能力测算:返回门槛与该账户当前余额(均为**分**)。
  ///
  /// 门槛 = 链上 `OnchainMinFee + ExistentialDeposit`,两个数都现取自链上 metadata——
  /// 交易费常量真源恒在区块链常量库,App 侧不留任何副本。余额走 `forceFresh` 绕开块内
  /// 缓存,否则会拿到充值前的旧值,把刚充完钱的用户又踢回充值页。
  ///
  /// 链读失败**不吞**:上抛给调用方 fail-closed 处理,绝不静默当成「余额不足」或「充足」。
  Future<({BigInt requiredFen, BigInt balanceFen})>
  fetchRegistrationAffordability(String bindAccountId) async {
    final fees = await _chain.getFeeSnapshot();
    final requiredFen = fees.minimumFeeFen + fees.existentialDepositFen;
    final balance = await _chain.getAccountBalance(bindAccountId);
    return (requiredFen: requiredFen, balanceFen: balance.freeFen);
  }

  Future<AccountDataBinding> _bindingForFinalizedIdentity(
    FinalizedIdentity resolved,
  ) async {
    final snapshot = resolved.snapshot;
    if (snapshot == null) {
      throw const AccountSecurityException('当前无已注册身份，无法解析设备子钥绑定');
    }
    final genesisHash = await _chain.getGenesisHash();
    if (!RegExp(r'^0x[0-9a-f]{64}$').hasMatch(genesisHash)) {
      throw const AccountSecurityException('创世哈希无效，禁止派生当前钱包私有数据密钥');
    }
    return AccountDataBinding(
      genesisHash: genesisHash,
      cidNumber: snapshot.cidNumber,
      bindingRevision: snapshot.bindingRevision,
      accountId: resolved.accountId,
    );
  }

  /// 只供 CID 注册 finalized 调用；页面门禁与 finalized 均不得初始化任何设备密钥。
  Future<void> _finishResolvedBinding(FinalizedIdentity resolved) async {
    await _finishFinalizedBinding(await _bindingForFinalizedIdentity(resolved));
  }

  /// finalized 只推进公开绑定与数据交接，不生成本地数据钥，也不登记 P-256 设备子钥。
  /// 前者仅在真实数据访问缺钥时生成，后者仅在 Worker 明确报告未登记时登记。
  Future<void> _finishFinalizedBinding(AccountDataBinding current) async {
    try {
      final previous = await _accountSecurity.readAccountDataBindingForCid(
        current.cidNumber,
      );
      await _accountSecurity.activateAccountDataBinding(
        genesisHash: current.genesisHash,
        cidNumber: current.cidNumber,
        bindingRevision: current.bindingRevision,
        accountId: current.accountId,
      );
      await _dataHandover.prepareFinalizedBinding(
        current: current,
        previous: previous,
      );
      await _dataHandover.completeFinalizedBinding(current);
    } finally {
      // CID 占号与换绑不一定改变 account_id，必须先清“未注册”快照再广播；所有常驻
      // 页面收到 revision 后按 cid_number + account_id 重读，禁止依赖重启 App。
      _currentUserContext.invalidate();
      _accountSecurity.notifyIdentityBindingChanged();
    }
  }

  static String _bytesToHex(List<int> bytes) {
    const alphabet = '0123456789abcdef';
    final output = StringBuffer();
    for (final byte in bytes) {
      output
        ..write(alphabet[(byte >> 4) & 0x0f])
        ..write(alphabet[byte & 0x0f]);
    }
    return output.toString();
  }

  Future<FinalizedIdentity> _requireFinalizedBinding({
    required String cidNumber,
    required String accountId,
  }) async {
    final resolved = await _identityResolver.resolve();
    final snapshot = resolved?.snapshot;
    if (resolved == null ||
        snapshot == null ||
        snapshot.cidNumber != cidNumber ||
        resolved.accountId != accountId) {
      throw const AccountSecurityException('finalized CID 当前绑定与预期不一致');
    }
    return resolved;
  }

  /// 列出可作换绑目标的本地账户(当前身份账户以外的全部账户)。
  Future<List<CitizenWalletStateAccount>> listRebindTargets() async {
    final state = await _wallet.getState();
    final defaultAccount = state.defaultAccount;
    if (defaultAccount == null) return const <CitizenWalletStateAccount>[];
    final resolved = await _identityResolver.resolve();
    final currentIdentityAccountId =
        resolved?.accountId ?? defaultAccount.accountId;
    return state.accounts
        .where((account) => account.accountId != currentIdentityAccountId)
        .toList(growable: false);
  }

  /// 列出注册 CID 时可选的绑定账户(当前热钱包下全部本地账户,含账户0)。
  Future<List<CitizenWalletStateAccount>> listBindableAccounts() async {
    return (await _wallet.getState()).accounts;
  }

  static CitizenWalletStateAccount? _findAccount(
    CitizenWalletState state,
    String accountId,
  ) {
    for (final account in state.accounts) {
      if (account.accountId == accountId) return account;
    }
    return null;
  }

  /// 把三段行政区码预 join 成「省·市·镇」展示串;省码空则返回空串。
  ///
  /// [formatAreaPath] 内部字典缺失会回退显 code(绝不崩、绝不空);再包一层
  /// 兜底防字典异常,避免选区展示阻断整卡。
  Future<String> _resolveDistrict(
    String province,
    String city,
    String town,
  ) async {
    if (province.isEmpty) return '';
    try {
      return await formatAreaPath(
        _divisionStore,
        provinceName: provinceDisplayNameByCode(province),
        provinceCode: province,
        cityCode: city,
        townCode: town,
      );
    } catch (e) {
      AppLog.d('myid area path resolve failed: $e');
      return [
        provinceDisplayNameByCode(province),
        city,
        town,
      ].where((s) => s.isNotEmpty).join(' · ');
    }
  }

  /// 写永久 CID 的身份徽章快照，供非链页面（个人页/广场）展示，不作权限依据。
  Future<void> _persistBadgeSnapshot(String cidNumber, String level) async {
    try {
      await _badgeSnapshotStore.write(
        cidNumber: cidNumber,
        identityLevel: level,
      );
    } catch (e) {
      // 快照只服务展示,写失败不改变本次真实链查询结果。
      AppLog.d('myid badge snapshot save failed: $e');
    }
  }

  MyIdStatus _deriveStatus(_VotingIdentity identity) {
    if (identity.citizenStatus == _CitizenStatus.revoked) {
      return MyIdStatus.revoked;
    }
    final today = _dateInt(_nowProvider());
    if (today < identity.passportValidFrom) return MyIdStatus.notYetValid;
    if (today > identity.passportValidUntil) return MyIdStatus.expired;
    return MyIdStatus.normal;
  }

  /// 解码链上 `VotingIdentity<BlockNumber>`,字段序与
  /// `citizenchain/runtime/misc/citizen-identity/src/lib.rs` 逐字节一致:
  /// valid_from(u32) + valid_until(u32) + status(u8) + residence_省/市/镇码
  /// + updated_at(u32)。永久 CID 只存在于 storage key，不在值中重复保存。
  _VotingIdentity? _decodeVotingIdentity(Uint8List data) {
    try {
      var offset = 0;
      if (offset + 4 + 4 + 1 > data.length) return null;
      final validFrom = _readU32Le(data, offset);
      offset += 4;
      final validUntil = _readU32Le(data, offset);
      offset += 4;
      if (!_isValidDateInt(validFrom) || !_isValidDateInt(validUntil)) {
        return null;
      }
      final status = switch (data[offset]) {
        0 => _CitizenStatus.normal,
        1 => _CitizenStatus.revoked,
        _ => null,
      };
      if (status == null) return null;
      offset += 1;
      // 居住 3 码允许空(区划码可能只到市;空段绝不能把整条身份误判为不存在)。
      final prov = _readUtf8VecAllowEmpty(data, offset, maxLen: 16);
      offset = prov.nextOffset;
      final city = _readUtf8VecAllowEmpty(data, offset, maxLen: 16);
      offset = city.nextOffset;
      final town = _readUtf8VecAllowEmpty(data, offset, maxLen: 16);
      offset = town.nextOffset;
      // updated_at(BlockNumber=u32):只校验尾部存在,展示不使用。
      if (offset + 4 > data.length) return null;
      return _VotingIdentity(
        passportValidFrom: validFrom,
        passportValidUntil: validUntil,
        citizenStatus: status,
        resProvince: prov.value,
        resCity: city.value,
        resTown: town.value,
      );
    } catch (_) {
      return null;
    }
  }

  /// 解码链上 `CandidateIdentity<BlockNumber>`(增量存储,不含 voting 基础字段):
  /// birth_省/市/镇码 + family_name + given_name + citizen_sex(u8,0男1女)
  /// + birth_date(u32 YYYYMMDD) + updated_at(u32)。
  _CandidateIdentity? _decodeCandidateIdentity(Uint8List data) {
    try {
      var offset = 0;
      final prov = _readUtf8VecAllowEmpty(data, offset, maxLen: 16);
      offset = prov.nextOffset;
      final city = _readUtf8VecAllowEmpty(data, offset, maxLen: 16);
      offset = city.nextOffset;
      final town = _readUtf8VecAllowEmpty(data, offset, maxLen: 16);
      offset = town.nextOffset;
      final familyName = _readUtf8VecAllowEmpty(data, offset, maxLen: 128);
      offset = familyName.nextOffset;
      final givenName = _readUtf8VecAllowEmpty(data, offset, maxLen: 128);
      offset = givenName.nextOffset;
      if (offset + 1 > data.length) return null;
      final sex = data[offset];
      offset += 1;
      if (sex != 0 && sex != 1) return null;
      // birth_date(u32 YYYYMMDD) + 尾部 updated_at(u32)。
      if (offset + 4 > data.length) return null;
      final birthDate = _readU32Le(data, offset);
      offset += 4;
      if (!_isValidDateInt(birthDate)) return null;
      if (offset + 4 > data.length) return null;
      return _CandidateIdentity(
        birthProvince: prov.value,
        birthCity: city.value,
        birthTown: town.value,
        familyName: familyName.value,
        givenName: givenName.value,
        sex: sex,
        birthDate: birthDate,
      );
    } catch (_) {
      return null;
    }
  }

  /// 读 `BoundedVec<u8>`,允许空(长度 0 返回空串)。区划码/姓名用。
  static ({String value, int nextOffset}) _readUtf8VecAllowEmpty(
    Uint8List data,
    int offset, {
    required int maxLen,
  }) {
    final (length, lengthSize) = _readCompactU32(data, offset);
    final start = offset + lengthSize;
    final end = start + length;
    if (length < 0 || length > maxLen || end > data.length) {
      throw const FormatException('BoundedVec 长度不合法');
    }
    if (length == 0) return (value: '', nextOffset: start);
    return (
      value: utf8.decode(data.sublist(start, end), allowMalformed: false),
      nextOffset: end,
    );
  }

  static (int, int) _readCompactU32(Uint8List data, int offset) {
    if (offset >= data.length) {
      throw const FormatException('Compact<u32> offset 越界');
    }
    final first = data[offset];
    final mode = first & 0x03;
    if (mode == 0) return (first >> 2, 1);
    if (mode == 1) {
      if (offset + 1 >= data.length) {
        throw const FormatException('Compact<u32> mode1 长度不足');
      }
      return ((first >> 2) | (data[offset + 1] << 6), 2);
    }
    if (mode == 2) {
      if (offset + 3 >= data.length) {
        throw const FormatException('Compact<u32> mode2 长度不足');
      }
      return (
        (first >> 2) |
            (data[offset + 1] << 6) |
            (data[offset + 2] << 14) |
            (data[offset + 3] << 22),
        4,
      );
    }
    throw const FormatException('Compact<u32> big-integer 模式暂不支持');
  }

  static int _readU32Le(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static bool _isValidDateInt(int value) {
    final year = value ~/ 10000;
    final month = (value ~/ 100) % 100;
    final day = value % 100;
    return year >= 1900 &&
        year <= 9999 &&
        month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= 31;
  }

  static int _dateInt(DateTime value) =>
      value.year * 10000 + value.month * 100 + value.day;

  static String _formatDateInt(int value) {
    final year = value ~/ 10000;
    final month = (value ~/ 100) % 100;
    final day = value % 100;
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }
}

class _VotingIdentity {
  const _VotingIdentity({
    required this.passportValidFrom,
    required this.passportValidUntil,
    required this.citizenStatus,
    required this.resProvince,
    required this.resCity,
    required this.resTown,
  });

  final int passportValidFrom;
  final int passportValidUntil;
  final _CitizenStatus citizenStatus;
  final String resProvince;
  final String resCity;
  final String resTown;
}

class _CandidateIdentity {
  const _CandidateIdentity({
    required this.birthProvince,
    required this.birthCity,
    required this.birthTown,
    required this.familyName,
    required this.givenName,
    required this.sex,
    required this.birthDate,
  });

  final String birthProvince;
  final String birthCity;
  final String birthTown;
  final String familyName;
  final String givenName;
  final int sex;

  /// 出生日期(YYYYMMDD 整数),竞选身份专属。
  final int birthDate;
}

enum _CitizenStatus { normal, revoked }
