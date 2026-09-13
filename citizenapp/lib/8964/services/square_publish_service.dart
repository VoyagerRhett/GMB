import 'dart:async';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/log/app_log.dart';

import 'package:citizenapp/8964/chain/square_chain_service.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_identity_state.dart';
import 'package:citizenapp/8964/services/square_post_deletion_coordinator.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';
import 'package:citizenapp/8964/services/square_post_sync_service.dart';
import 'package:citizenapp/8964/services/square_upload_service.dart';

class SquarePublishException implements Exception {
  const SquarePublishException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SquarePublishResult {
  const SquarePublishResult({
    required this.post,
    required this.txHash,
    required this.blockHashHex,
    this.completionWarning,
  });

  final SquarePost post;
  final String txHash;
  final String blockHashHex;

  /// 远端发布已经完成，但本地副本或被替换内容清理仍需后台收敛时的成功告警。
  final String? completionWarning;
}

typedef SquarePostRecoveryScheduler = void Function(SquareSession session);

abstract class SquarePublishBalanceReader {
  Future<double> fetchFreshFinalizedBalanceYuan(String accountId);

  /// 自付一笔最低链上交易所需的余额门槛(分),取自链上常量,App 侧无副本。
  Future<BigInt> fetchMinSelfPayBalanceFen();
}

class SquareChainBalanceReader implements SquarePublishBalanceReader {
  const SquareChainBalanceReader(this._chain);

  final CitizenChain _chain;

  @override
  Future<double> fetchFreshFinalizedBalanceYuan(String accountId) async {
    final balance = await _chain.getAccountBalance(accountId);
    return balance.freeFen.toDouble() / 100;
  }

  @override
  Future<BigInt> fetchMinSelfPayBalanceFen() async {
    final fees = await _chain.getFeeSnapshot();
    return fees.minimumFeeFen + fees.existentialDepositFen;
  }
}

class SquarePublishService {
  SquarePublishService({
    required SquareContentUploader uploadService,
    required CitizenChain chain,
    required CitizenTransactions transactions,
    SquarePostChainPublisher? chainService,
    SquarePublicationConfirmer? publicationConfirmer,
    SquarePostDeleteCoordinator? postDeletionCoordinator,
    SquarePublishBalanceReader? balanceReader,
    SquareLocalPostWriter? localPostWriter,
    SquarePostRecoveryScheduler? recoveryScheduler,
  }) : _uploadService = uploadService,
       _chainService =
           chainService ??
           SquareChainService(chain: chain, transactions: transactions),
       _publicationConfirmer = publicationConfirmer ?? SquareApiClient(),
       _postDeletionCoordinator =
           postDeletionCoordinator ?? SquarePostDeletionCoordinator(),
       _balanceReader = balanceReader ?? SquareChainBalanceReader(chain),
       _localPostWriter = localPostWriter ?? const SquarePostStore(),
       _recoveryScheduler = recoveryScheduler ?? _scheduleDefaultLocalRecovery;

  final SquareContentUploader _uploadService;
  final SquarePostChainPublisher _chainService;
  final SquarePublicationConfirmer _publicationConfirmer;
  final SquarePostDeleteCoordinator _postDeletionCoordinator;
  final SquarePublishBalanceReader _balanceReader;
  final SquareLocalPostWriter _localPostWriter;
  final SquarePostRecoveryScheduler _recoveryScheduler;

  /// 只取消尚未上传的本地媒体处理；链上或云端阶段不接受客户端取消。
  Future<void> cancelMediaProcessing() async {
    final uploader = _uploadService;
    if (uploader is SquareMediaProcessingController) {
      await (uploader as SquareMediaProcessingController)
          .cancelMediaProcessing();
    }
  }

  Future<SquarePublishResult> publish({
    required SquareIdentityState identity,
    required SquarePostType postType,
    required String text,
    required List<SquareLocalMediaDraft> mediaDrafts,
    required SquareLoginSigner signLoginPayload,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
    String? title,
    List<Map<String, Object?>>? contentSections,
    String? replacePostId,
    void Function(SquarePublishStage stage)? onStage,
  }) async {
    final trimmedText = text.trim();
    if (!identity.hasWallet || identity.ss58Address == null) {
      throw const SquarePublishException('请先创建或选择钱包');
    }
    if (identity.cidNumber?.trim().isEmpty ?? true) {
      throw const SquarePublishException('请先注册公民号');
    }
    if (trimmedText.isEmpty && mediaDrafts.isEmpty) {
      throw const SquarePublishException('发布内容不能为空');
    }

    SquarePreparedContent? prepared;
    SquareUploadedContent? uploaded;
    SquareChainPublishedResult? chainResult;
    var chainExecutionStarted = false;
    try {
      prepared = await _uploadService.preparePostContent(
        accountId: identity.accountId,
        postType: postType,
        text: trimmedText,
        mediaDrafts: mediaDrafts,
        signLoginPayload: signLoginPayload,
        title: title,
        contentSections: contentSections,
        onStage: onStage,
      );

      uploaded = await _uploadService.uploadPreparedContent(
        prepared,
        onStage: onStage,
      );

      // 只有所有 Cloudflare 内容已完整落盘后才进入唯一链上阶段；余额、nonce、metadata、
      // runtime 版本与最终生物识别签名全部集中在这里读取和执行。
      onStage?.call(SquarePublishStage.checkingBalance);
      await _ensurePublishBalance(identity.accountId);
      onStage?.call(SquarePublishStage.submittingChain);
      chainExecutionStarted = true;
      final chainFuture = _chainService.publishPost(
        signerPublicKey: SquareChainService.hexDecode(identity.accountId),
        postId: prepared.postId,
        postType: postType,
        contentHashHex: prepared.contentHash,
        storageReceiptId: prepared.storageReceiptId,
        externalSigning: externalSigning,
      );
      // CitizenSDK 接管交易观察并只在 Runtime finalized 终态返回；App 不再
      // 自建交易池监听，只把这段唯一等待期映射到现有发布进度 UI。
      onStage?.call(SquarePublishStage.waitingInBlock);
      chainResult = await chainFuture;

      onStage?.call(SquarePublishStage.confirmingPost);
      final confirmedPost = await _publicationConfirmer.confirmPublishedPost(
        session: uploaded.session,
        postId: uploaded.postId,
        blockHashHex: chainResult.blockHashHex,
        txHash: chainResult.txHash,
      );

      final localCopyWarning = await _saveLocalCopyAfterSuccess(
        identity: identity,
        session: uploaded.session,
        prepared: prepared,
        confirmedPost: confirmedPost,
        postType: postType,
      );
      final cleanupWarning = await _deleteReplacedPostAfterSuccess(
        session: uploaded.session,
        newPostId: uploaded.postId,
        replacePostId: replacePostId,
      );
      final completionWarning = <String>[
        if (localCopyWarning != null) localCopyWarning,
        if (cleanupWarning != null) cleanupWarning,
      ].join('\n');
      onStage?.call(SquarePublishStage.completed);
      return SquarePublishResult(
        post: confirmedPost,
        txHash: chainResult.txHash,
        blockHashHex: chainResult.blockHashHex,
        completionWarning: completionWarning.isEmpty ? null : completionWarning,
      );
    } catch (e) {
      // 已完成上传但尚未取得 finalized 发布结果时，必须请求 Worker 再查链后硬清理。
      // confirm 失败时 chainResult 已存在，保留云端正文供同一 finalized 事实重试确认。
      final chainFailureAllowsAbort =
          e is SquareChainPublishException && e.canAbortUpload;
      final canAbortUpload = !chainExecutionStarted || chainFailureAllowsAbort;
      if (uploaded != null && chainResult == null && canAbortUpload) {
        try {
          await _publicationConfirmer.abortUpload(
            session: uploaded.session,
            uploadId: prepared!.preparedUpload.uploadId,
          );
        } catch (cleanupError) {
          throw SquarePublishException(
            '${_messageOf(e)}\n孤儿上传清理失败：${_messageOf(cleanupError)}',
          );
        }
      }
      if (uploaded != null && chainResult == null && !canAbortUpload) {
        throw SquarePublishException(
          '${_messageOf(e)}\n交易终态尚未确定，上传内容已保留，禁止重复发布',
        );
      }
      // 失败内容由发布页持续自动保存兜底进草稿箱；此处只规整错误消息后上抛。
      throw SquarePublishException(_messageOf(e));
    }
  }

  Future<String?> _saveLocalCopyAfterSuccess({
    required SquareIdentityState identity,
    required SquareSession session,
    required SquarePreparedContent prepared,
    required SquarePost confirmedPost,
    required SquarePostType postType,
  }) async {
    try {
      if (confirmedPost.postId != prepared.postId ||
          confirmedPost.author.cidNumber != session.cidNumber ||
          confirmedPost.author.accountId != identity.accountId ||
          session.accountId != identity.accountId ||
          confirmedPost.postType != postType ||
          confirmedPost.contentHash != prepared.contentHash ||
          confirmedPost.storageReceiptId != prepared.storageReceiptId) {
        throw const SquarePostStoreException('发布确认字段与本地 manifest 不一致');
      }
      await _localPostWriter.save(
        SquareLocalPost(
          postId: prepared.postId,
          cidNumber: session.cidNumber,
          accountId: identity.accountId,
          postCategory: confirmedPost.postCategory.workerValue,
          postType: postType.workerValue,
          manifestBytes: prepared.manifestBytes,
          contentHash: prepared.contentHash,
          storageReceiptId: prepared.storageReceiptId,
          chainBlock: confirmedPost.chainBlock,
          createdAt: confirmedPost.createdAt.millisecondsSinceEpoch,
          postState: SquarePostStore.publishedState,
        ),
      );
      return null;
    } catch (error) {
      // 链上和 Worker 已确认后绝不能把本地磁盘失败包装成“发布失败”供用户重试，
      // 否则会重复扣费、重复发帖；立即调度本人回灌，并以成功告警说明收敛状态。
      AppLog.d('[SquarePublishService] local copy pending: $error');
      _recoveryScheduler(session);
      return '内容已发布，本地副本将在后台重新同步';
    }
  }

  static void _scheduleDefaultLocalRecovery(SquareSession session) {
    unawaited(
      SquarePostSyncService().sync(session).catchError((Object error) {
        AppLog.d('[SquarePublishService] local copy recovery failed: $error');
      }),
    );
  }

  Future<String?> _deleteReplacedPostAfterSuccess({
    required SquareSession session,
    required String newPostId,
    required String? replacePostId,
  }) async {
    final oldPostId = replacePostId?.trim();
    if (oldPostId == null || oldPostId.isEmpty || oldPostId == newPostId) {
      return null;
    }
    try {
      // 修改视为重新发布：新帖成功后再清旧帖，避免发布失败导致原内容丢失。
      await _postDeletionCoordinator.delete(
        session: session,
        cidNumber: session.cidNumber,
        postId: oldPostId,
      );
      return null;
    } catch (error) {
      final message = '新内容已发布，但旧内容清理失败：${_messageOf(error)}';
      AppLog.d('[SquarePublishService] $message');
      return message;
    }
  }

  /// 发布前余额闸。发布是自签自付的链上交易，余额不够连入池预检都过不了。
  ///
  /// 门槛 = 链上 `OnchainMinFee + ExistentialDeposit`，两个数**现取自链上 metadata**：
  /// 交易费常量的真源恒为区块链常量库（`primitives::fee_policy`，经 runtime 转发），
  /// App 侧一律不留副本。链读失败不吞，上抛由发布流程按失败处理。
  Future<void> _ensurePublishBalance(String accountId) async {
    final requiredFen = await _balanceReader.fetchMinSelfPayBalanceFen();
    final balance = await _balanceReader.fetchFreshFinalizedBalanceYuan(
      accountId,
    );
    final balanceFen = BigInt.from((balance * 100).round());
    if (balanceFen < requiredFen) {
      throw SquarePublishException(
        '钱包余额不足，发布内容需至少 ${_formatFen(requiredFen)} 元'
        '（含账户存在最低余额与链上最低交易费）',
      );
    }
  }

  static String _formatFen(BigInt fen) =>
      (fen / BigInt.from(100)).toStringAsFixed(2);

  static String _messageOf(Object error) {
    if (error is SquarePublishException) return error.message;
    if (error is SquareApiException) return error.message;
    return error.toString();
  }
}
