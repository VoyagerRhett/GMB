import 'dart:convert';
import 'dart:typed_data';

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/8964/chain/square_chain_service.dart';
import 'package:citizenapp/8964/models/square_models.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/8964/services/square_identity_state.dart';
import 'package:citizenapp/8964/services/square_post_deletion_coordinator.dart';
import 'package:citizenapp/8964/services/square_post_store.dart';
import 'package:citizenapp/8964/services/square_publish_service.dart';
import 'package:citizenapp/8964/services/square_upload_service.dart';

import '../support/isar_test_env.dart';
import '../support/fake_citizen_sdk.dart';

void main() {
  useIsolatedIsar();
  TestWidgetsFlutterBinding.ensureInitialized();

  test('广场发布余额门槛由链上动态读取且 App 不保留费用常量副本', () async {
    final reader = _FakeBalanceReader(<String>[]);
    expect(await reader.fetchMinSelfPayBalanceFen(), BigInt.from(121));
  });

  test('未注册 CID 不能发布，且不会进入存储准备', () async {
    final order = <String>[];
    final upload = _FakeUploader(order);
    final chain = _FakeChainPublisher(order);
    final service = SquarePublishService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      uploadService: upload,
      chainService: chain,
      publicationConfirmer: _FakePublicationConfirmer(),
      balanceReader: _FakeBalanceReader(order),
      localPostWriter: _FakeLocalPostWriter(),
    );

    await expectLater(
      service.publish(
        identity: _identity(cidNumber: null),
        postType: SquarePostType.document,
        text: '竞选说明',
        mediaDrafts: [_media()],
        signLoginPayload: (_, __) async => '0x11',
        externalSigning: (_) async => 'QR_V1',
      ),
      throwsA(isA<SquarePublishException>()),
    );
    expect(upload.called, isFalse);
    expect(chain.called, isFalse);
    expect(order, isEmpty);
  });

  test('公文按准备上传、最终余额与链签名、finalized 确认顺序发布', () async {
    final order = <String>[];
    final upload = _FakeUploader(order);
    final chain = _FakeChainPublisher(order);
    final localWriter = _FakeLocalPostWriter();
    final stages = <SquarePublishStage>[];
    final service = SquarePublishService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      uploadService: upload,
      chainService: chain,
      publicationConfirmer: _FakePublicationConfirmer(order),
      balanceReader: _FakeBalanceReader(order),
      localPostWriter: localWriter,
    );

    final result = await service.publish(
      identity: _identity(cidNumber: 'CN001-CTZN-000000001-2026'),
      postType: SquarePostType.document,
      text: '公文',
      mediaDrafts: [_media()],
      signLoginPayload: (_, __) async => '0x11',
      externalSigning: (_) async => 'QR_V1',
      onStage: stages.add,
    );

    expect(upload.called, isTrue);
    expect(chain.called, isTrue);
    expect(chain.postId, 'sqp_test');
    expect(chain.storageReceiptId, 'sqr_test');
    expect(result.post.contentHash, '11' * 32);
    expect(localWriter.saved?.postId, 'sqp_test');
    expect(localWriter.saved?.cidNumber, 'CN220-CTZN2-198805200-2026');
    expect(localWriter.saved?.createdAt, 1800000000000);
    expect(order, ['prepare', 'upload', 'balance', 'chain', 'confirm']);
    expect(
      stages,
      containsAllInOrder([
        SquarePublishStage.preparingStorage,
        SquarePublishStage.uploadingMedia,
        SquarePublishStage.completingStorage,
        SquarePublishStage.checkingBalance,
        SquarePublishStage.submittingChain,
        SquarePublishStage.waitingInBlock,
        SquarePublishStage.confirmingPost,
        SquarePublishStage.completed,
      ]),
    );
  });

  test('修改内容时新发布确认成功后再删除旧内容', () async {
    final order = <String>[];
    final oldPostDeleter = _FakePostDeleteCoordinator(order);
    final service = SquarePublishService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      uploadService: _FakeUploader(order),
      chainService: _FakeChainPublisher(order),
      publicationConfirmer: _FakePublicationConfirmer(order),
      postDeletionCoordinator: oldPostDeleter,
      balanceReader: _FakeBalanceReader(order),
      localPostWriter: _FakeLocalPostWriter(),
    );

    final result = await service.publish(
      identity: _identity(cidNumber: 'CN001-CTZN-000000001-2026'),
      postType: SquarePostType.document,
      text: '修改后的公文',
      mediaDrafts: [_media()],
      signLoginPayload: (_, __) async => '0x11',
      externalSigning: (_) async => 'QR_V1',
      replacePostId: 'sqp_old',
    );

    expect(result.completionWarning, isNull);
    expect(oldPostDeleter.deletedPostId, 'sqp_old');
    expect(order, [
      'prepare',
      'upload',
      'balance',
      'chain',
      'confirm',
      'delete_old',
    ]);
  });

  test('最终余额不足时清理已完成上传且不提交链上', () async {
    final order = <String>[];
    final upload = _FakeUploader(order);
    final chain = _FakeChainPublisher(order);
    final service = SquarePublishService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      uploadService: upload,
      chainService: chain,
      publicationConfirmer: _FakePublicationConfirmer(order),
      balanceReader: _FakeBalanceReader(order, balanceYuan: 1.20),
      localPostWriter: _FakeLocalPostWriter(),
    );

    await expectLater(
      service.publish(
        identity: _identity(cidNumber: 'CN001-CTZN-000000001-2026'),
        postType: SquarePostType.document,
        text: '余额不足的公文',
        mediaDrafts: [_media()],
        signLoginPayload: (_, __) async => '0x11',
        externalSigning: (_) async => 'QR_V1',
      ),
      throwsA(isA<SquarePublishException>()),
    );

    expect(order, ['prepare', 'upload', 'balance', 'abort']);
    expect(upload.called, isTrue);
    expect(upload.uploadCalled, isTrue);
    expect(chain.called, isFalse);
  });

  test('链上发布失败时清理已完成上传', () async {
    final order = <String>[];
    final upload = _FakeUploader(order);
    final chain = _FakeChainPublisher(order)..throwOnPublish = true;
    final service = SquarePublishService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      uploadService: upload,
      chainService: chain,
      publicationConfirmer: _FakePublicationConfirmer(order),
      balanceReader: _FakeBalanceReader(order),
      localPostWriter: _FakeLocalPostWriter(),
    );

    await expectLater(
      service.publish(
        identity: _identity(cidNumber: 'CN001-CTZN-000000001-2026'),
        postType: SquarePostType.document,
        text: '链上未入块的公文',
        mediaDrafts: [_media()],
        signLoginPayload: (_, __) async => '0x11',
        externalSigning: (_) async => 'QR_V1',
      ),
      throwsA(isA<SquarePublishException>()),
    );

    expect(order, ['prepare', 'upload', 'balance', 'chain', 'abort']);
    expect(upload.uploadCalled, isTrue);
  });

  test('签名后链终态不确定时保留上传且禁止重复发布', () async {
    final order = <String>[];
    final chain = _FakeChainPublisher(order)..throwAfterSign = true;
    final service = SquarePublishService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      uploadService: _FakeUploader(order),
      chainService: chain,
      publicationConfirmer: _FakePublicationConfirmer(order),
      balanceReader: _FakeBalanceReader(order),
      localPostWriter: _FakeLocalPostWriter(),
    );

    await expectLater(
      service.publish(
        identity: _identity(cidNumber: 'CN001-CTZN-000000001-2026'),
        postType: SquarePostType.document,
        text: '终态不确定的公文',
        mediaDrafts: [_media()],
        signLoginPayload: (_, __) async => '0x11',
        externalSigning: (_) async => 'QR_V1',
      ),
      throwsA(
        isA<SquarePublishException>().having(
          (error) => error.message,
          'message',
          contains('禁止重复发布'),
        ),
      ),
    );

    expect(order, ['prepare', 'upload', 'balance', 'chain']);
  });

  test('远端确认后本地落盘失败仍返回发布成功并立即调度回灌', () async {
    final order = <String>[];
    final localWriter = _FakeLocalPostWriter()..throwOnSave = true;
    SquareSession? scheduledSession;
    final service = SquarePublishService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      uploadService: _FakeUploader(order),
      chainService: _FakeChainPublisher(order),
      publicationConfirmer: _FakePublicationConfirmer(order),
      balanceReader: _FakeBalanceReader(order),
      localPostWriter: localWriter,
      recoveryScheduler: (session) => scheduledSession = session,
    );

    final result = await service.publish(
      identity: _identity(cidNumber: 'CN001-CTZN-000000001-2026'),
      postType: SquarePostType.document,
      text: '远端已成功的公文',
      mediaDrafts: [_media()],
      signLoginPayload: (_, __) async => '0x11',
      externalSigning: (_) async => 'QR_V1',
    );

    expect(result.post.postId, 'sqp_test');
    expect(result.completionWarning, contains('本地副本将在后台重新同步'));
    expect(scheduledSession?.cidNumber, 'CN220-CTZN2-198805200-2026');
  });

  test('远端确认成功后把同一份规范 manifest 原始字节写入真实 Isar', () async {
    final order = <String>[];
    final manifestBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': SquarePostStore.manifestSchema,
          'cid_number': 'CN220-CTZN2-198805200-2026',
          'post_type': 'document',
          'text': '真实本地副本',
          'media_items': const <Object>[],
        }),
      ),
    );
    final contentHash = sha256.convert(manifestBytes).toString();
    final service = SquarePublishService(
      chain: TestCitizenChain(),
      transactions: TestCitizenTransactions(),
      uploadService: _FakeUploader(order, manifestBytes: manifestBytes),
      chainService: _FakeChainPublisher(order),
      publicationConfirmer: _FakePublicationConfirmer.withHash(
        order,
        contentHash,
      ),
      balanceReader: _FakeBalanceReader(order),
    );

    await service.publish(
      identity: _identity(cidNumber: 'CN220-CTZN2-198805200-2026'),
      postType: SquarePostType.document,
      text: '真实本地副本',
      mediaDrafts: [_media()],
      signLoginPayload: (_, __) async => '0x11',
      externalSigning: (_) async => 'QR_V1',
    );

    final saved = await const SquarePostStore().read(
      cidNumber: 'CN220-CTZN2-198805200-2026',
      postId: 'sqp_test',
    );
    expect(saved?.manifestBytes, orderedEquals(manifestBytes));
    expect(saved?.contentHash, contentHash);
    expect(saved?.createdAt, 1800000000000);
  });
}

SquareIdentityState _identity({required String? cidNumber}) {
  return SquareIdentityState(
    accountId:
        '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    displayName: '公开昵称',
    cidNumber: cidNumber,
    walletIndex: 1,
    ss58Address: 'citizen_test_signer_ss58_address',
    signMode: CitizenWalletSignMode.hot,
  );
}

SquareLocalMediaDraft _media() {
  return const SquareLocalMediaDraft(
    mediaKind: SquareMediaKind.image,
    path: '/tmp/square-test.jpg',
    fileName: 'square-test.jpg',
    contentType: 'image/jpeg',
    byteSize: 1024,
  );
}

class _FakeUploader implements SquareContentUploader {
  _FakeUploader(this.order, {this.manifestBytes});

  final List<String> order;
  final Uint8List? manifestBytes;
  bool called = false;
  bool uploadCalled = false;

  @override
  Future<SquarePreparedContent> preparePostContent({
    required String accountId,
    required SquarePostType postType,
    required String text,
    required List<SquareLocalMediaDraft> mediaDrafts,
    required SquareLoginSigner signLoginPayload,
    String? title,
    List<Map<String, Object?>>? contentSections,
    void Function(SquarePublishStage stage)? onStage,
  }) async {
    called = true;
    order.add('prepare');
    onStage?.call(SquarePublishStage.preparingStorage);
    final bytes = manifestBytes ?? Uint8List.fromList([1, 2, 3]);
    final contentHash = manifestBytes == null
        ? '11' * 32
        : sha256.convert(bytes).toString();
    return SquarePreparedContent(
      session: const SquareSession(
        sessionToken: 'sqs_test',
        cidNumber: "CN220-CTZN2-198805200-2026",
        bindingRevision: 1,
        accountId:
            '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        expiresAt: 1800000000000,
      ),
      preparedUpload: const SquarePreparedUpload(
        uploadId: 'squ_test',
        postId: 'sqp_test',
        storageReceiptId: 'sqr_test',
        expiresAt: 1800000000000,
        estimatedBytes: 1024,
        manifestObjectKey: 'square/test/manifest.json',
        manifestUploadUrl: 'http://127.0.0.1/manifest',
        mediaItems: [
          SquarePreparedMediaUpload(
            mediaKind: SquareMediaKind.image,
            contentType: 'image/webp',
            byteSize: 1024,
            objectKey: 'square/cid/posts/sqp_test/media/0/source.webp',
            uploadMethod: 'r2_put',
            uploadUrl: 'http://127.0.0.1/media',
            uploadHeaders: {
              'content-type': 'image/webp',
              'content-length': '1024',
            },
            derivativeKind: 'thumbnail',
            derivativeByteSize: 256,
            derivativeObjectKey:
                'square/cid/posts/sqp_test/media/0/thumbnail.webp',
            derivativeUploadUrl: 'http://127.0.0.1/thumbnail',
            derivativeUploadHeaders: {
              'content-type': 'image/webp',
              'content-length': '256',
            },
          ),
        ],
      ),
      postId: 'sqp_test',
      contentHash: contentHash,
      storageReceiptId: 'sqr_test',
      manifestHash: contentHash,
      manifestBytes: bytes,
      mediaDrafts: mediaDrafts,
    );
  }

  @override
  Future<SquareUploadedContent> uploadPreparedContent(
    SquarePreparedContent prepared, {
    void Function(SquarePublishStage stage)? onStage,
  }) async {
    uploadCalled = true;
    order.add('upload');
    onStage?.call(SquarePublishStage.uploadingMedia);
    onStage?.call(SquarePublishStage.completingStorage);
    return SquareUploadedContent(
      session: prepared.session,
      postId: prepared.postId,
      contentHash: prepared.contentHash,
      storageReceiptId: prepared.storageReceiptId,
      manifestHash: prepared.manifestHash,
    );
  }
}

class _FakePublicationConfirmer implements SquarePublicationConfirmer {
  _FakePublicationConfirmer([this.order]) : contentHash = '11' * 32;

  _FakePublicationConfirmer.withHash(this.order, this.contentHash);

  final List<String>? order;
  final String contentHash;

  @override
  Future<void> abortUpload({
    required SquareSession session,
    required String uploadId,
  }) async {
    order?.add('abort');
  }

  @override
  Future<SquarePost> confirmPublishedPost({
    required SquareSession session,
    required String postId,
    required String blockHashHex,
    required String txHash,
  }) async {
    order?.add('confirm');
    return SquarePost(
      postId: postId,
      author: SquareAuthor(
        accountId: session.accountId,
        cidNumber: session.cidNumber,
      ),
      postCategory: SquarePostCategory.normal,
      postType: SquarePostType.document,
      text: '公文',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1800000000000),
      contentHash: contentHash,
      storageReceiptId: 'sqr_test',
      chainBlock: 88,
    );
  }
}

class _FakeLocalPostWriter implements SquareLocalPostWriter {
  SquareLocalPost? saved;
  bool throwOnSave = false;

  @override
  Future<void> save(SquareLocalPost post) async {
    if (throwOnSave) {
      throw StateError('disk unavailable');
    }
    saved = post;
  }
}

class _FakePostDeleteCoordinator implements SquarePostDeleteCoordinator {
  _FakePostDeleteCoordinator(this.order);

  final List<String> order;
  String? deletedPostId;

  @override
  Future<void> delete({
    required SquareSession session,
    required String cidNumber,
    required String postId,
  }) async {
    order.add('delete_old');
    deletedPostId = postId;
  }
}

class _FakeChainPublisher implements SquarePostChainPublisher {
  _FakeChainPublisher(this.order);

  final List<String> order;
  bool called = false;
  String? postId;
  String? storageReceiptId;
  bool throwOnPublish = false;
  bool throwAfterSign = false;

  @override
  Future<SquareChainPublishedResult> publishPost({
    required Uint8List signerPublicKey,
    required String postId,
    required SquarePostType postType,
    required String contentHashHex,
    required String storageReceiptId,
    required Future<String?> Function(
      CitizenTransactionExternalSigningPending pending,
    )
    externalSigning,
  }) async {
    called = true;
    order.add('chain');
    this.postId = postId;
    this.storageReceiptId = storageReceiptId;
    if (throwOnPublish) {
      throw const SquareChainPublishException(
        '交易执行已确定失败',
        canAbortUpload: true,
      );
    }
    if (throwAfterSign) {
      throw const SquareChainPublishException(
        '交易终态尚未确定',
        canAbortUpload: false,
      );
    }
    return const SquareChainPublishedResult(
      txHash: '0xtest',
      usedNonce: 1,
      blockHashHex: '0xblock',
    );
  }
}

class _FakeBalanceReader implements SquarePublishBalanceReader {
  _FakeBalanceReader(
    this.order, {
    this.balanceYuan = 1.21,
    BigInt? minimumBalanceFen,
  }) : minimumBalanceFen = minimumBalanceFen ?? BigInt.from(121);

  final List<String> order;
  final double balanceYuan;
  final BigInt minimumBalanceFen;

  @override
  Future<BigInt> fetchMinSelfPayBalanceFen() async => minimumBalanceFen;

  @override
  Future<double> fetchFreshFinalizedBalanceYuan(String publicKey) async {
    order.add('balance');
    return balanceYuan;
  }
}
