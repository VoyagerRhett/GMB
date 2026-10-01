import 'package:citizenapp/wallet/account_balance_snapshot_store.dart';

import 'package:citizenapp/isar/social_isar.dart';
import 'package:citizenapp/8964/compose/drafts/compose_draft_store.dart';
import 'package:citizenapp/8964/services/square_local_post_presenter.dart';

import 'package:citizenapp/my/myid/finalized_identity_resolver.dart';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:citizenapp/app_log.dart';

import 'package:citizenapp/8964/services/square_chain_service.dart';
import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_identity_state.dart';
import 'package:citizenapp/8964/services/square_post_deletion_coordinator.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';
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

  /// 远端已发布、本地收尾或原帖删除仍待显式恢复时的成功告警。
  final String? completionWarning;
}

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
    final balance = await AccountBalanceSnapshotStore.forChain(_chain)
        .getAccountBalance(accountId, forceRefresh: true);
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
    required FinalizedIdentityResolver identityResolver,
    required CitizenChain chain,
    required CitizenTransactions transactions,
    SquarePostChainPublisher? chainService,
    SquarePublicationConfirmer? publicationConfirmer,
    SquarePostDeleteCoordinator? postDeletionCoordinator,
    SquarePublishBalanceReader? balanceReader,
    SquareLocalPostWriter? localPostWriter,
  }) : _identityResolver = identityResolver,
       _uploadService = uploadService,
       _chainService =
           chainService ??
           SquareChainService(chain: chain, transactions: transactions),
       _publicationConfirmer = publicationConfirmer ?? SquareApiClient(),
       _postDeletionCoordinator =
           postDeletionCoordinator ?? SquarePostDeletionCoordinator(),
       _balanceReader = balanceReader ?? SquareChainBalanceReader(chain),
       _localPostWriter = localPostWriter ?? const SquarePostStore();

  final FinalizedIdentityResolver _identityResolver;
  final SquareContentUploader _uploadService;
  final SquarePostChainPublisher _chainService;
  final SquarePublicationConfirmer _publicationConfirmer;
  final SquarePostDeleteCoordinator _postDeletionCoordinator;
  final SquarePublishBalanceReader _balanceReader;
  final SquareLocalPostWriter _localPostWriter;
  static const _postStore = SquarePostStore();

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
    required String draftId,
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
    if (trimmedText.isEmpty && mediaDrafts.isEmpty) {
      throw const SquarePublishException('发布内容不能为空');
    }

    final cid = identity.cidNumber;
    final pending = cid == null
        ? null
        : await _postStore.readPublication(cid, draftId);
    if (pending?.publicationState == 'confirmed') {
      // 远端成功事实已在本机：仅恢复本地事务，不再验真、上传或发起交易。
      final local = SquarePostStore.confirmedPublication(pending!);
      final warning = await _finishLocal(pending);
      return SquarePublishResult(
        post: const SquareLocalPostPresenter().present(local).post,
        txHash: pending.transactionHash!,
        blockHashHex: pending.blockHash!,
        completionWarning:
            warning ??
            (pending.replacePostId == null ? null : '本地副本已恢复，请检查原帖删除状态'),
      );
    }

    // 点击发布才验真一次；后续上传与签名只复用此结果和本机版本校验。
    final verified = await _identityResolver.resolve();
    if (verified == null || verified.snapshot == null) {
      throw const SquarePublishException('请先注册公民号');
    }
    if (verified.accountId != identity.accountId ||
        (identity.cidNumber?.isNotEmpty == true &&
            identity.cidNumber != verified.snapshot!.cidNumber)) {
      throw const SquarePublishException('身份已变化，请重新进入发布');
    }
    final snapshot = verified.snapshot!;
    identity = SquareIdentityState(
      accountId: verified.accountId,
      cidNumber: snapshot.cidNumber,
      ss58Address: verified.ss58Address,
      displayName: identity.displayName,
      walletIndex: identity.walletIndex,
      signMode: identity.signMode,
      identityLevel: snapshot.votingIdentity == null
          ? 'visitor'
          : snapshot.candidateIdentity == null
          ? 'voting'
          : 'candidate',
    );
    await _identityResolver.assertCurrent(verified);

    if (pending != null) {
      final session = await _uploadService.resumeSession(
        identity.accountId,
        signLoginPayload,
      );
      if (session.cidNumber != pending.cidNumber ||
          session.accountId != pending.accountId) {
        throw const SquarePublishException('发布恢复会话与原发布归属不一致');
      }
      if (pending.publicationState == 'submitting') {
        // 进程可能在交易提交后退出。只查询已有发布证明，绝不再次签名或提交。
        final proof = await _publicationConfirmer.readPublishedProof(
          session: session,
          postId: pending.postId,
        );
        _recordConfirmation(pending, proof.post);
        pending
          ..blockHash = proof.blockHash
          ..transactionHash = proof.transactionHash
          ..publicationState = 'finalized';
        await _postStore.savePublication(pending);
        pending.publicationState = 'confirmed';
        await _postStore.savePublication(pending);
        final warning = await _finishLocal(pending);
        return SquarePublishResult(
          post: proof.post,
          txHash: proof.transactionHash,
          blockHashHex: proof.blockHash,
          completionWarning: warning,
        );
      }
      if (pending.publicationState == 'finalized') {
        final post = await _publicationConfirmer.confirmPublishedPost(
          session: session,
          postId: pending.postId,
          blockHashHex: pending.blockHash!,
          txHash: pending.transactionHash!,
        );
        _recordConfirmation(pending, post);
        await _postStore.savePublication(pending);
        final warning = await _finishLocal(pending);
        return SquarePublishResult(
          post: post,
          txHash: pending.transactionHash!,
          blockHashHex: pending.blockHash!,
          completionWarning: warning,
        );
      }
      // 尚未进入交易的遗留准备可先由服务端核实释放，再重新准备当前草稿。
      await _publicationConfirmer.abortUpload(
        session: session,
        uploadId: pending.uploadId,
      );
      await _postStore.discardPublication(
        pending.cidNumber,
        draftId,
        pending.postId,
      );
    }

    SquarePublicationEntity? publication;
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

      if (prepared.session.accountId != verified.accountId ||
          prepared.session.cidNumber != snapshot.cidNumber ||
          prepared.session.bindingRevision != snapshot.bindingRevision) {
        throw const SquarePublishException('发布会话与已验证身份不一致，请重新操作');
      }
      publication = SquarePublicationEntity()
        ..cidNumber = prepared.session.cidNumber
        ..draftId = draftId
        ..accountId = identity.accountId
        ..postId = prepared.postId
        ..postType = postType.workerValue
        ..contentHash = prepared.contentHash
        ..storageReceiptId = prepared.storageReceiptId
        ..uploadId = prepared.preparedUpload.uploadId
        ..manifestBytes = prepared.manifestBytes
        ..publicationState = 'prepared'
        ..replacePostId = replacePostId;
      await _postStore.savePublication(
        publication,
        references: prepared.mediaReferences,
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
      await _identityResolver.assertCurrent(verified);
      publication.publicationState = 'submitting';
      await _postStore.savePublication(publication);
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
      publication
        ..publicationState = 'finalized'
        ..transactionHash = chainResult.txHash
        ..blockHash = chainResult.blockHashHex;
      await _postStore.savePublication(publication);

      onStage?.call(SquarePublishStage.confirmingPost);
      final confirmedPost = await _publicationConfirmer.confirmPublishedPost(
        session: uploaded.session,
        postId: uploaded.postId,
        blockHashHex: chainResult.blockHashHex,
        txHash: chainResult.txHash,
      );

      final localCopyWarning = await _saveLocalCopyAfterSuccess(
        publication: publication,
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
        ?localCopyWarning,
        ?cleanupWarning,
      ].join('\n');
      onStage?.call(SquarePublishStage.completed);
      return SquarePublishResult(
        post: confirmedPost,
        txHash: chainResult.txHash,
        blockHashHex: chainResult.blockHashHex,
        completionWarning: completionWarning.isEmpty ? null : completionWarning,
      );
    } catch (e) {
      var temporaryWarning = '';
      if (prepared != null && uploaded == null) {
        try {
          await prepared.deleteTemporaryMedia();
        } catch (_) {
          temporaryWarning = '\n临时处理文件尚未清理';
        }
      }
      // 已完成上传但尚未取得 finalized 发布结果时，必须请求 Worker 再查链后硬清理。
      // confirm 失败时 chainResult 已存在，保留云端正文供同一 finalized 事实重试确认。
      final chainFailureAllowsAbort =
          e is SquareChainPublishException && e.canAbortUpload;
      final canAbortUpload = !chainExecutionStarted || chainFailureAllowsAbort;
      if (prepared != null && chainResult == null && canAbortUpload) {
        try {
          await _publicationConfirmer.abortUpload(
            session: prepared.session,
            uploadId: prepared.preparedUpload.uploadId,
          );
          await _postStore.discardPublication(
            prepared.session.cidNumber,
            draftId,
            prepared.postId,
            definitiveFailure: chainFailureAllowsAbort,
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
      // 发布前已保存草稿，失败时不以自动保存覆盖本次恢复事实。
      throw SquarePublishException('${_messageOf(e)}$temporaryWarning');
    }
  }

  Future<String?> _saveLocalCopyAfterSuccess({
    required SquarePublicationEntity publication,
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
      _recordConfirmation(publication, confirmedPost);
      await _postStore.savePublication(publication);
      return await _finishLocal(publication);
    } catch (error) {
      // 链上和 Worker 已确认后绝不能把本地磁盘失败包装成“发布失败”供用户重试，
      // 否则会重复扣费、重复发帖；持久恢复行保留，用户重试只收尾，不后台回灌。
      AppLog.d('[SquarePublishService] local copy pending: $error');
      return '内容已发布，本地收尾尚未完成；请从草稿重试恢复，不会重复发布';
    }
  }

  Future<String?> _finishLocal(SquarePublicationEntity row) async {
    try {
      await _localPostWriter.save(
        SquarePostStore.confirmedPublication(row),
        draftId: row.draftId,
      );
    } catch (_) {
      return '内容已发布，本地收尾尚未完成；请从草稿重试恢复，不会重复发布';
    }
    try {
      await SquareComposeDraftStore.instance.retryPendingFileCleanup(
        cidNumber: row.cidNumber,
      );
      return null;
    } catch (_) {
      return '内容已发布并保存在数据库，临时媒体文件仍待清理';
    }
  }

  static void _recordConfirmation(
    SquarePublicationEntity row,
    SquarePost post,
  ) {
    if (post.postId != row.postId ||
        post.author.cidNumber != row.cidNumber ||
        post.author.accountId != row.accountId ||
        post.contentHash != row.contentHash ||
        post.storageReceiptId != row.storageReceiptId ||
        post.postType.workerValue != row.postType) {
      throw const SquarePublishException('远端确认与本机发布记录不一致');
    }
    row
      ..publicationState = 'confirmed'
      ..postCategory = post.postCategory.workerValue
      ..chainBlock = post.chainBlock
      ..createdAt = post.createdAt.millisecondsSinceEpoch;
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
