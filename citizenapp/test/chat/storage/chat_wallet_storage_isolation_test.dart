import 'package:citizenapp/chat/tatachat_sdk_adapter.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/isar/social_isar.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'package:citizenapp/isar/app_isar.dart';
import 'package:citizenapp/isar/isar_core_bootstrap.dart';
import 'package:citizenapp/isar/user_isar.dart';
import 'package:citizenapp/security/app_lock_service.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/security/pin_input_page.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:citizenapp/isar/wallet_isar.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import '../../support/isar_test_env.dart';

class _TestBinding extends AccountDataBinding implements ChatDataBinding {
  const _TestBinding({
    required super.genesisHash,
    required super.cidNumber,
    required super.bindingRevision,
    required super.accountId,
  });

  @override
  String get keyDomain => genesisHash;

  @override
  String get userId => cidNumber;

  @override
  String get id => '$keyDomain|$userId|$bindingRevision|$accountId';
}

const Duration _shortQueueTimeout = Duration(seconds: 1);
const Duration _wipeTimeout = Duration(seconds: 8);
const String _accountId =
    '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _ownerUserId = 'CN220-CTZN2-100000001-2026';
const String _peerUserId = 'CN220-CTZN2-100000002-2026';
const _TestBinding _binding = _TestBinding(
  genesisHash:
      '0x1111111111111111111111111111111111111111111111111111111111111111',
  cidNumber: _ownerUserId,
  bindingRevision: 7,
  accountId: _accountId,
);

/// 把 ChatCrypto 的公开绑定和用途钥读取都强制送进真实 WalletIsar 队列。
///
/// 返回值虽然是确定测试数据，但队列、数据库打开和读回 marker 都是真实路径；这样
/// ChatStore 一旦又在 ChatIsar 回调内等待钱包读取，本测试就会在短超时内失败。
class _WalletIsarReadingManager implements AccountSecurityService {
  static const String markerKey = 'test:chat-wallet-storage-isolation';

  int bindingReadCount = 0;
  int keyReadCount = 0;
  bool allReadsObservedWalletQueue = true;
  bool anyReadObservedChatQueue = false;
  final Set<LocalKeyPurpose> purposesRead = <LocalKeyPurpose>{};

  Future<T> _readThroughWalletIsar<T>(T Function() value) {
    return WalletIsar.instance.read((isar) async {
      final marker = await isar.walletAttestationEntitys.get(0);
      if (marker?.lastRequestPayload != markerKey) {
        throw StateError('钱包测试 marker 未从 WalletIsar 读回');
      }
      allReadsObservedWalletQueue &= WalletIsar.instance.hasActiveOperation;
      anyReadObservedChatQueue |= ChatIsar.instance.hasActiveOperation;
      return value();
    });
  }

  @override
  Future<_TestBinding> accountDataBindingForAccountId(String accountId) {
    return _readThroughWalletIsar(() {
      bindingReadCount += 1;
      if (accountId != _binding.accountId) {
        throw StateError('测试账户不是当前 finalized 绑定账户');
      }
      return _binding;
    });
  }

  @override
  Future<List<Uint8List>> readDataKeysForBinding(
    AccountDataBinding binding,
    List<({String? context, LocalKeyPurpose purpose})> requests,
  ) {
    return _readThroughWalletIsar(() {
      keyReadCount += 1;
      if (binding.accountId != _binding.accountId ||
          binding.cidNumber != _binding.cidNumber ||
          binding.bindingRevision != _binding.bindingRevision) {
        throw StateError('聊天用途钥请求了错误的钱包绑定');
      }
      purposesRead.addAll(requests.map((request) => request.purpose));
      // 每次返回新副本；ChatCrypto 会在 finally 中主动清零自己拿到的用途钥。
      return requests
          .map(
            (request) => Uint8List.fromList(
              List<int>.generate(
                32,
                (index) => (index + 17 + request.purpose.index * 41) & 0xff,
              ),
            ),
          )
          .toList(growable: false);
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedAccountSecurity implements AccountSecurityService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCurrentUserContext implements CurrentUserContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 测试显式从服务模块提供 CitizenServe 会话所有者，聊天工厂不得自行创建第二份。
ChatSdk _createTestChatRuntime(
  Future<Directory> Function() documentsDirectoryProvider,
) {
  final accountSecurity = _UnusedAccountSecurity();
  final currentUserContext = _UnusedCurrentUserContext();
  return createCitizenChatRuntime(
    accountSecurity: accountSecurity,
    currentUserContext: currentUserContext,
    squareSessionProvider: SquareSessionProvider(
      accountSecurity: accountSecurity,
      currentUserContext: currentUserContext,
    ),
    documentsDirectoryProvider: documentsDirectoryProvider,
  );
}

EncryptedMessage _incomingMessage() {
  return EncryptedMessage()
    ..messageId = 'env-storage-isolation'
    ..conversationId = 'conv-storage-isolation'
    ..senderUserId = _peerUserId
    ..deliveries.add(
      EncryptedDelivery(recipient: Recipient(userId: _ownerUserId)),
    )
    ..senderDeviceId = 'device-storage-isolation'
    ..createdAtMillis = Int64(1700000000000);
}

Future<void> _enterSixDigitPin(WidgetTester tester) async {
  for (final digit in <int>[1, 2, 3, 4, 5, 6]) {
    await tester.tap(find.text('$digit'));
    await tester.pump();
  }
}

void main() {
  useIsolatedIsar();
  late Directory chatDocumentsRoot;

  setUp(() async {
    chatDocumentsRoot = await Directory.systemTemp.createTemp(
      'tatachat_sdk_chat_documents_',
    );
    await ChatRuntimeCore.debugResetProcessWipeForTest(
      documentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    AppLockService.debugResetForTest();
  });

  tearDown(() async {
    AppLockService.debugResetForTest();
    await ChatRuntimeCore.debugResetProcessWipeForTest(
      documentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    if (await chatDocumentsRoot.exists()) {
      await chatDocumentsRoot.delete(recursive: true);
    }
  });

  test('ChatIsar 队列挂起时 WalletIsar 读写仍在短超时内完成', () async {
    // 先打开两库，把本测试关注点限定为独立操作队列，而不是首次加载原生库耗时。
    await Future.wait<void>(<Future<void>>[
      ChatIsar.instance.db().then<void>((_) {}),
      WalletIsar.instance.db().then<void>((_) {}),
    ]);

    final chatEntered = Completer<void>();
    final releaseChat = Completer<void>();
    final blockedChat = ChatIsar.instance.read<void>((_) async {
      chatEntered.complete();
      await releaseChat.future;
    });
    Future<void>? walletWrite;
    Future<String?>? walletRead;

    try {
      await chatEntered.future.timeout(_shortQueueTimeout);
      expect(ChatIsar.instance.hasActiveOperation, isTrue);

      walletWrite = WalletIsar.instance.writeTxn<void>((isar) async {
        await isar.walletAttestationEntitys.put(
          WalletAttestationEntity()
            ..id = 0
            ..lastRequestPayload = 'wallet-ready',
        );
      });
      await walletWrite.timeout(_shortQueueTimeout);

      walletRead = WalletIsar.instance.read<String?>((isar) async {
        final row = await isar.walletAttestationEntitys.get(0);
        return row?.lastRequestPayload;
      });
      expect(await walletRead.timeout(_shortQueueTimeout), 'wallet-ready');
      expect(ChatIsar.instance.hasActiveOperation, isTrue);
    } finally {
      // 即使断言或超时失败，也先放行 Chat，避免污染本文件后续测试的队列。
      if (!releaseChat.isCompleted) releaseChat.complete();
      await blockedChat;
      await walletWrite;
      await walletRead;
    }
  });

  test('启动明文附件清扫不构造 ChatSdk，也不等待 WalletIsar', () async {
    await WalletIsar.instance.db();
    final plain = File(
      '${chatDocumentsRoot.path}/chat/by_user/cid-fixture/by_binding/7/'
      '$_accountId/attachments/.plain/visible.bin',
    );
    final cipher = File('${plain.parent.parent.path}/cipher.enc');
    await plain.parent.create(recursive: true);
    await plain.writeAsString('short-lived-plain');
    await cipher.writeAsBytes(const <int>[1, 2, 3]);

    final walletEntered = Completer<void>();
    final releaseWallet = Completer<void>();
    final blockedWallet = WalletIsar.instance.read<void>((_) async {
      walletEntered.complete();
      await releaseWallet.future;
    });
    try {
      await walletEntered.future.timeout(_shortQueueTimeout);
      final liveRuntimeCount = ChatRuntimeCore.debugLiveInstanceCount;
      await ChatRuntimeCore.purgePlainAttachmentsWithoutAccount(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ).timeout(_shortQueueTimeout);
      expect(plain.existsSync(), isFalse);
      expect(cipher.existsSync(), isTrue);
      expect(
        ChatRuntimeCore.debugLiveInstanceCount,
        lessThanOrEqualTo(liveRuntimeCount),
      );
    } finally {
      if (!releaseWallet.isCompleted) releaseWallet.complete();
      await blockedWallet;
    }
  });

  test('密文保存、会话读取、消息读取与搜索不会形成 Chat 到 Wallet 队列自锁', () async {
    final manager = _WalletIsarReadingManager();
    await WalletIsar.instance.writeTxn<void>((isar) async {
      await isar.walletAttestationEntitys.put(
        WalletAttestationEntity()
          ..id = 0
          ..lastRequestPayload = _WalletIsarReadingManager.markerKey,
      );
    });
    await ChatIsar.instance.db();

    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      final bindingToken = await store.activateBindingFence(_binding);
      const messageText = '聊天和钱包独立队列回归消息';
      final plaintext = ChatPayloadCodec.encode(ChatContent.text(messageText));

      await store
          .saveIncomingMessage(
            ownerUserId: _ownerUserId,
            currentAccountId: _accountId,
            message: _incomingMessage(),
            messageBytes: const <int>[1, 2, 3, 4],
            messageKind: ChatMessageKind.text,
            plaintext: plaintext,
            bindingToken: bindingToken,
          )
          .timeout(_shortQueueTimeout);

      final raw = await ChatIsar.instance.read((isar) async {
        return isar.chatMessageEntitys.getByOwnerUserIdMessageId(
          _ownerUserId,
          'env-storage-isolation',
        );
      });
      expect(raw, isNotNull);
      expect(raw!.plaintextCipher, isNot(contains(plaintext)));
      expect(raw.searchTokens, isNotEmpty);

      final previews = await store
          .readConversationPreviews(
            ownerUserId: _ownerUserId,
            currentAccountId: _accountId,
          )
          .timeout(_shortQueueTimeout);
      expect(previews.single.lastMessage, messageText);

      final messages = await store
          .readMessages(
            ownerUserId: _ownerUserId,
            currentAccountId: _accountId,
            conversationId: 'conv-storage-isolation',
          )
          .timeout(_shortQueueTimeout);
      expect(messages.single.plaintext, plaintext);

      final hits = await store
          .searchMessages(
            ownerUserId: _ownerUserId,
            currentAccountId: _accountId,
            keyword: '独立队列',
          )
          .timeout(_shortQueueTimeout);
      expect(hits.map((message) => message.messageId), <String>[
        'env-storage-isolation',
      ]);

      expect(manager.bindingReadCount, greaterThanOrEqualTo(4));
      expect(manager.keyReadCount, greaterThanOrEqualTo(7));
      expect(
        manager.purposesRead,
        containsAll(<LocalKeyPurpose>[
          LocalKeyPurpose.chat,
          LocalKeyPurpose.chatIndex,
        ]),
      );
      expect(manager.allReadsObservedWalletQueue, isTrue);
      expect(
        manager.anyReadObservedChatQueue,
        isFalse,
        reason: '绑定与用途钥必须在 ChatIsar 返回快照后读取，不能从 Chat 回调跨域等待',
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('ChatIsar 回调内嵌套 ChatIsar.read 会快速抛 StateError', () async {
    final nestedRead = ChatIsar.instance.read<void>((_) async {
      await ChatIsar.instance.read<void>((_) async {});
    });

    await expectLater(
      nestedRead.timeout(_shortQueueTimeout),
      throwsA(isA<StateError>()),
    );
  });

  test('WalletIsar 回调内嵌套 WalletIsar.read 会快速抛 StateError', () async {
    final nestedRead = WalletIsar.instance.read<void>((_) async {
      await WalletIsar.instance.read<void>((_) async {});
    });

    await expectLater(
      nestedRead.timeout(_shortQueueTimeout),
      throwsA(isA<StateError>()),
    );
  });

  test('同名 ChatIsar 已打开但 schema 不完整时失败关闭且不重开', () async {
    final incomplete = await Isar.open(
      <CollectionSchema<dynamic>>[ChatConversationEntitySchema],
      name: 'tatachat_sdk_chat',
      directory: await IsarCoreBootstrap.resolveDirectory(),
    );
    try {
      await expectLater(ChatIsar.instance.db(), throwsA(isA<StateError>()));
      expect(incomplete.isOpen, isTrue, reason: '失败关闭不得静默关闭/重开别人的实例');
      expect(Isar.getInstance('tatachat_sdk_chat'), same(incomplete));
    } finally {
      if (incomplete.isOpen) {
        await incomplete.close(deleteFromDisk: true);
      }
    }
  });

  test('现有业务库真实删除后保持终态，只有 resetForTest 能恢复空库', () async {
    const appNamespace = 'test-app-delete-marker';
    const walletMarkerKey = 'test:wallet-delete-marker';
    const handoverKey = 'test:chat-delete-marker';
    const socialCidNumber = 'R5-K3P1C1-N7-D6';
    const userCidNumber = 'R5-K3P1C1-N8-D5';

    await WalletIsar.instance.writeTxn<void>((isar) async {
      await isar.walletAttestationEntitys.put(
        WalletAttestationEntity()
          ..id = 0
          ..lastRequestPayload = walletMarkerKey,
      );
    });
    await ChatIsar.instance.writeTxn<void>((isar) async {
      await isar.chatAccountHandoverEntitys.put(
        ChatAccountHandoverEntity()
          ..handoverKey = handoverKey
          ..ownerUserId = _ownerUserId
          ..sourceBindingRevision = 6
          ..sourceAccountId = _accountId
          ..targetBindingRevision = 7
          ..targetAccountId = _accountId
          ..manifestJson = '{}',
      );
    });
    await SocialIsar.instance.writeTxn<void>((isar) async {
      await isar.squarePostSyncCheckpointEntitys.putByCidNumber(
        SquarePostSyncCheckpointEntity()
          ..cidNumber = socialCidNumber
          ..newestPostId = 'sqp_delete_marker'
          ..newestCreatedAt = 1,
      );
    });
    await UserIsar.instance.writeTxn<void>((isar) async {
      await isar.userIdentityBadgeSnapshotEntitys.putByCidNumber(
        UserIdentityBadgeSnapshotEntity()
          ..cidNumber = userCidNumber
          ..identityLevel = 'candidate'
          ..updatedAtMillis = 1,
      );
    });
    await AppIsar.instance.writeTxn<void>((isar) async {
      await isar.appDataVersionEntitys.putByNamespace(
        AppDataVersionEntity()
          ..namespace = appNamespace
          ..globalVersion = 'must-be-deleted'
          ..updatedAtMillis = 1,
      );
    });

    await WalletIsar.instance.closeAndDeleteFromDisk().timeout(_wipeTimeout);
    await ChatIsar.instance.closeAndDeleteFromDisk().timeout(_wipeTimeout);
    await SocialIsar.instance.closeAndDeleteFromDisk().timeout(_wipeTimeout);
    await UserIsar.instance.closeAndDeleteFromDisk().timeout(_wipeTimeout);
    await AppIsar.instance.closeAndDeleteFromDisk().timeout(_wipeTimeout);

    await expectLater(WalletIsar.instance.db(), throwsA(isA<StateError>()));
    await expectLater(ChatIsar.instance.db(), throwsA(isA<StateError>()));
    await expectLater(SocialIsar.instance.db(), throwsA(isA<StateError>()));
    await expectLater(UserIsar.instance.db(), throwsA(isA<StateError>()));
    await expectLater(AppIsar.instance.db(), throwsA(isA<StateError>()));
    expect(
      () => WalletIsar.instance.read<void>((_) async {}),
      throwsA(isA<StateError>()),
    );
    expect(
      () => ChatIsar.instance.read<void>((_) async {}),
      throwsA(isA<StateError>()),
    );
    expect(
      () => SocialIsar.instance.read<void>((_) async {}),
      throwsA(isA<StateError>()),
    );
    expect(
      () => UserIsar.instance.read<void>((_) async {}),
      throwsA(isA<StateError>()),
    );
    expect(
      () => AppIsar.instance.read<void>((_) async {}),
      throwsA(isA<StateError>()),
    );

    await WalletIsar.instance.resetForTest().timeout(_wipeTimeout);
    await ChatIsar.instance.resetForTest().timeout(_wipeTimeout);
    await SocialIsar.instance.resetForTest().timeout(_wipeTimeout);
    await UserIsar.instance.resetForTest().timeout(_wipeTimeout);
    await AppIsar.instance.resetForTest().timeout(_wipeTimeout);

    final walletMarker = await WalletIsar.instance.read<String?>((isar) async {
      return (await isar.walletAttestationEntitys.get(0))?.lastRequestPayload;
    });
    final handover = await ChatIsar.instance.read((isar) async {
      return isar.chatAccountHandoverEntitys.getByHandoverKey(handoverKey);
    });
    final socialCheckpoint = await SocialIsar.instance.read((isar) async {
      return isar.squarePostSyncCheckpointEntitys.getByCidNumber(
        socialCidNumber,
      );
    });
    final userBadge = await UserIsar.instance.read((isar) async {
      return isar.userIdentityBadgeSnapshotEntitys.getByCidNumber(
        userCidNumber,
      );
    });
    final appMarker = await AppIsar.instance.read((isar) async {
      return isar.appDataVersionEntitys.getByNamespace(appNamespace);
    });
    expect(walletMarker, isNull);
    expect(handover, isNull);
    expect(socialCheckpoint, isNull);
    expect(userBadge, isNull);
    expect(appMarker, isNull);
  });

  test('现有业务库与广场文件仅留冷数据时显式擦除仍真实删除', () async {
    const appNamespace = 'test-cold-app-delete-marker';
    const walletMarkerKey = 'test:cold-wallet-delete-marker';
    const handoverKey = 'test:cold-chat-delete-marker';
    const socialCidNumber = 'R5-K3P1C1-N6-D7';
    const userCidNumber = 'R5-K3P1C1-N5-D8';
    final wallet = await WalletIsar.instance.db();
    final chat = await ChatIsar.instance.db();
    final social = await SocialIsar.instance.db();
    final user = await UserIsar.instance.db();
    final app = await AppIsar.instance.db();
    await wallet.writeTxn(() async {
      await wallet.walletAttestationEntitys.put(
        WalletAttestationEntity()
          ..id = 0
          ..lastRequestPayload = walletMarkerKey,
      );
    });
    await chat.writeTxn(() async {
      await chat.chatAccountHandoverEntitys.putByHandoverKey(
        ChatAccountHandoverEntity()
          ..handoverKey = handoverKey
          ..ownerUserId = _ownerUserId
          ..sourceBindingRevision = 6
          ..sourceAccountId = _accountId
          ..targetBindingRevision = 7
          ..targetAccountId = _accountId
          ..manifestJson = '{}',
      );
    });
    await social.writeTxn(() async {
      await social.squarePostSyncCheckpointEntitys.putByCidNumber(
        SquarePostSyncCheckpointEntity()
          ..cidNumber = socialCidNumber
          ..newestPostId = 'sqp_cold_marker'
          ..newestCreatedAt = 1,
      );
    });
    await user.writeTxn(() async {
      await user.userIdentityBadgeSnapshotEntitys.putByCidNumber(
        UserIdentityBadgeSnapshotEntity()
          ..cidNumber = userCidNumber
          ..identityLevel = 'voting'
          ..updatedAtMillis = 1,
      );
    });
    await app.writeTxn(() async {
      await app.appDataVersionEntitys.putByNamespace(
        AppDataVersionEntity()
          ..namespace = appNamespace
          ..globalVersion = 'must-not-survive-cold-delete'
          ..updatedAtMillis = 1,
      );
    });
    final socialMediaMarker = File(
      '${chatDocumentsRoot.path}/square_drafts/cid/draft/marker.bin',
    );
    await socialMediaMarker.create(recursive: true);
    await socialMediaMarker.writeAsBytes(<int>[1, 2, 3]);

    // 模拟上一进程只关闭句柄而保留磁盘库；五个单例仍为 active，但没有可用注册实例。
    expect(await wallet.close(), isTrue);
    expect(await chat.close(), isTrue);
    expect(await social.close(), isTrue);
    expect(await user.close(), isTrue);
    expect(await app.close(), isTrue);
    expect(Isar.getInstance('citizenapp_wallet'), isNull);
    expect(Isar.getInstance('tatachat_sdk_chat'), isNull);
    expect(Isar.getInstance('citizenapp_social'), isNull);
    expect(Isar.getInstance('citizenapp_user'), isNull);
    expect(Isar.getInstance('citizenapp_app'), isNull);

    await AppLockService.wipeAllData(
      wallet: null,
      accountSecurity: null,
      debugDeleteCitizenSdkWallet: () async {},
      debugDeleteSecureStorage: () async {},
      debugClearSharedPreferences: () async {},
      debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
    ).timeout(_wipeTimeout);

    await expectLater(WalletIsar.instance.db(), throwsA(isA<StateError>()));
    await expectLater(ChatIsar.instance.db(), throwsA(isA<StateError>()));
    await expectLater(SocialIsar.instance.db(), throwsA(isA<StateError>()));
    await expectLater(UserIsar.instance.db(), throwsA(isA<StateError>()));
    await expectLater(AppIsar.instance.db(), throwsA(isA<StateError>()));
    expect(socialMediaMarker.existsSync(), isFalse);
    await WalletIsar.instance.resetForTest().timeout(_wipeTimeout);
    await ChatIsar.instance.resetForTest().timeout(_wipeTimeout);
    await SocialIsar.instance.resetForTest().timeout(_wipeTimeout);
    await UserIsar.instance.resetForTest().timeout(_wipeTimeout);
    await AppIsar.instance.resetForTest().timeout(_wipeTimeout);

    final walletMarker = await WalletIsar.instance.read<String?>((isar) async {
      return (await isar.walletAttestationEntitys.get(0))?.lastRequestPayload;
    });
    final handover = await ChatIsar.instance.read((isar) async {
      return isar.chatAccountHandoverEntitys.getByHandoverKey(handoverKey);
    });
    final socialCheckpoint = await SocialIsar.instance.read((isar) async {
      return isar.squarePostSyncCheckpointEntitys.getByCidNumber(
        socialCidNumber,
      );
    });
    final userBadge = await UserIsar.instance.read((isar) async {
      return isar.userIdentityBadgeSnapshotEntitys.getByCidNumber(
        userCidNumber,
      );
    });
    final appMarker = await AppIsar.instance.read((isar) async {
      return isar.appDataVersionEntitys.getByNamespace(appNamespace);
    });
    expect(walletMarker, isNull);
    expect(handover, isNull);
    expect(socialCheckpoint, isNull);
    expect(userBadge, isNull);
    expect(appMarker, isNull);
  });

  test('全量擦除只删除 Documents/chat 并让当前进程 ChatSdk 永久终止', () async {
    final chatRoot = Directory('${chatDocumentsRoot.path}/chat');
    final plainFile = File('${chatRoot.path}/by_cid/cid/attachments/.plain/a');
    final mlsFile = File('${chatRoot.path}/by_cid/cid/mls/device/state.bin');
    final sibling = File('${chatDocumentsRoot.path}/must-remain.txt');
    await plainFile.parent.create(recursive: true);
    await plainFile.writeAsString('plain-chat-test-data');
    await mlsFile.parent.create(recursive: true);
    await mlsFile.writeAsBytes(const <int>[1, 2, 3]);
    await sibling.writeAsString('outside-chat-root');

    final runtime = _createTestChatRuntime(() async => chatDocumentsRoot);
    await expectLater(
      ChatRuntimeCore.closeAndDeleteLocalFiles(
        documentsDirectoryProvider: () async {
          throw StateError('chat-documents-provider-first-attempt-failed');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(await chatRoot.exists(), isTrue, reason: '首次关闭失败时不得先删文件树');

    // 进程终态不撤销，但下一次全量擦除必须能重试同一 runtime 与目录。
    await AppLockService.wipeAllData(
      wallet: null,
      accountSecurity: null,
      debugDeleteCitizenSdkWallet: () async {},
      debugDeleteSecureStorage: () async {},
      debugClearSharedPreferences: () async {},
      debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
    ).timeout(_wipeTimeout);

    expect(await chatRoot.exists(), isFalse);
    expect(await sibling.readAsString(), 'outside-chat-root');
    await expectLater(
      runtime.purgePlainAttachments(),
      throwsA(isA<StateError>()),
    );
    expect(
      () => _createTestChatRuntime(() async => chatDocumentsRoot),
      throwsA(isA<StateError>()),
    );
    expect(await chatRoot.exists(), isFalse, reason: '终态检查不得重新创建 Chat 根目录');
  });

  test('Chat 上下文首次关闭失败后二次真实重试，成功后才删根目录', () async {
    final chatRoot = Directory('${chatDocumentsRoot.path}/chat');
    final marker = File('${chatRoot.path}/context-dispose-marker.bin');
    await marker.parent.create(recursive: true);
    await marker.writeAsBytes(const <int>[1]);

    var disposeCalls = 0;
    ChatSdk? runtime = _createTestChatRuntime(() async => chatDocumentsRoot);
    runtime.debugRegisterContextDisposerForTest(() async {
      disposeCalls += 1;
      if (disposeCalls == 1) {
        throw StateError('context-dispose-first-attempt-failed');
      }
    });

    await expectLater(
      ChatRuntimeCore.closeAndDeleteLocalFiles(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      throwsA(isA<StateError>()),
    );
    expect(disposeCalls, 1);
    expect(await chatRoot.exists(), isTrue, reason: '上下文未关闭时不得先删 Chat 根');
    expect(ChatRuntimeCore.debugPendingCloseInstanceCount, 1);

    // 模拟 UI 放弃最后一个强引用；静态 pending-close 集合仍必须保活失败实例。
    runtime = null;

    await ChatRuntimeCore.closeAndDeleteLocalFiles(
      documentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    expect(disposeCalls, 2, reason: '二次擦除必须重新执行关闭，不得复用失败 Future');
    expect(await chatRoot.exists(), isFalse);
    expect(ChatRuntimeCore.debugPendingCloseInstanceCount, 0);

    await ChatRuntimeCore.closeAndDeleteLocalFiles(
      documentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    expect(disposeCalls, 2, reason: '关闭成功后必须保持幂等');
  });

  test('全量擦除等待已登记的 Chat 文件改写收口后再删根目录', () async {
    final chatRoot = Directory('${chatDocumentsRoot.path}/chat');
    final initialFile = File('${chatRoot.path}/initial.bin');
    await initialFile.parent.create(recursive: true);
    await initialFile.writeAsBytes(const <int>[1]);

    final runtime = _createTestChatRuntime(() async => chatDocumentsRoot);
    final mutationEntered = Completer<void>();
    final releaseMutation = Completer<void>();
    final mutation = runtime.debugRunFileMutationForTest<void>(() async {
      mutationEntered.complete();
      await releaseMutation.future;
      final lateFile = File('${chatRoot.path}/late/after-wipe-request.bin');
      await lateFile.parent.create(recursive: true);
      await lateFile.writeAsBytes(const <int>[2]);
    });
    await mutationEntered.future.timeout(_shortQueueTimeout);

    var wipeCompleted = false;
    final wipe = AppLockService.wipeAllData(
      wallet: null,
      accountSecurity: null,
      debugDeleteCitizenSdkWallet: () async {},
      debugDeleteSecureStorage: () async {},
      debugClearSharedPreferences: () async {},
      debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    wipe.then<void>(
      (_) => wipeCompleted = true,
      onError: (Object _, StackTrace __) {
        wipeCompleted = true;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(wipeCompleted, isFalse);
    expect(await chatRoot.exists(), isTrue, reason: '在途改写收口前不得先删根目录');

    releaseMutation.complete();
    await mutation.timeout(_shortQueueTimeout);
    await wipe.timeout(_wipeTimeout);
    expect(await chatRoot.exists(), isFalse);
  });

  test('invalidateAccount 后仍追踪在途 ready flight，禁止擦除成功后复活文件', () async {
    final chatRoot = Directory('${chatDocumentsRoot.path}/chat');
    final initial = File('${chatRoot.path}/ready-flight-initial.bin');
    await initial.parent.create(recursive: true);
    await initial.writeAsBytes(const <int>[1]);

    final runtime = _createTestChatRuntime(() async => chatDocumentsRoot);
    final flightEntered = Completer<void>();
    final releaseFlight = Completer<void>();
    final flightOperation = () async {
      flightEntered.complete();
      await releaseFlight.future;
      final late = File('${chatRoot.path}/late/ready-flight.bin');
      await late.parent.create(recursive: true);
      await late.writeAsBytes(const <int>[2]);
    }();
    runtime.debugRegisterReadyFlightForTest(_accountId, flightOperation);
    final invalidation = runtime.invalidateAccount(_accountId);
    await flightEntered.future.timeout(_shortQueueTimeout);

    var wipeCompleted = false;
    final wipe = AppLockService.wipeAllData(
      wallet: null,
      accountSecurity: null,
      debugDeleteCitizenSdkWallet: () async {},
      debugDeleteSecureStorage: () async {},
      debugClearSharedPreferences: () async {},
      debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    wipe.whenComplete(() => wipeCompleted = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(wipeCompleted, isFalse);
    expect(await chatRoot.exists(), isTrue);

    releaseFlight.complete();
    await flightOperation.timeout(_shortQueueTimeout);
    await invalidation.timeout(_shortQueueTimeout);
    await wipe.timeout(_wipeTimeout);
    expect(await chatRoot.exists(), isFalse);
  });

  test('Chat 实时 socket 与两订阅独立重试关闭，终态后不再执行回调', () async {
    final chatRoot = Directory('${chatDocumentsRoot.path}/chat');
    final marker = File('${chatRoot.path}/realtime-marker.bin');
    await marker.parent.create(recursive: true);
    await marker.writeAsBytes(const <int>[1]);

    final runtime = _createTestChatRuntime(() async => chatDocumentsRoot);
    var socketStops = 0;
    var wakeCancels = 0;
    var tokenCancels = 0;
    final stop = runtime.debugRegisterRealtimeSessionForTest(
      stopSocket: () async {
        socketStops += 1;
        if (socketStops == 1) {
          throw StateError('socket-stop-first-attempt-failed');
        }
      },
      cancelWakeSubscription: () async => wakeCancels += 1,
      cancelTokenSubscription: () async => tokenCancels += 1,
    );

    await expectLater(
      ChatRuntimeCore.closeAndDeleteLocalFiles(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      throwsA(isA<StateError>()),
    );
    expect((socketStops, wakeCancels, tokenCancels), (1, 1, 1));
    expect(await chatRoot.exists(), isTrue);

    await ChatRuntimeCore.closeAndDeleteLocalFiles(
      documentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    expect((socketStops, wakeCancels, tokenCancels), (2, 1, 1));
    expect(await chatRoot.exists(), isFalse);

    await stop();
    expect((socketStops, wakeCancels, tokenCancels), (2, 1, 1));
    var callbackRan = false;
    await expectLater(
      runtime.debugRunRuntimeOperationForTest<void>(() async {
        callbackRan = true;
      }),
      throwsA(isA<StateError>()),
    );
    expect(callbackRan, isFalse);
  });

  test('后台 handler 在 stop 后仍等待已触发 callback，完成前不得释放运行态', () async {
    final runtime = _createTestChatRuntime(() async => chatDocumentsRoot);
    final callbackEntered = Completer<void>();
    final releaseCallback = Completer<void>();
    final callback = runtime.debugRunRuntimeOperationForTest<void>(() async {
      callbackEntered.complete();
      await releaseCallback.future;
    });
    await callbackEntered.future.timeout(_shortQueueTimeout);

    final stop = runtime.debugRegisterRealtimeSessionForTest(
      stopSocket: () async {},
      cancelWakeSubscription: () async {},
      cancelTokenSubscription: () async {},
    );
    await stop();

    var drained = false;
    final drain = runtime.debugDrainBackgroundRuntimeForTest();
    drain.whenComplete(() => drained = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(drained, isFalse, reason: 'stop 不等价于已触发 callback 收口');

    releaseCallback.complete();
    await callback.timeout(_shortQueueTimeout);
    await drain.timeout(_shortQueueTimeout);
    expect(drained, isTrue);
  });

  test('后台 cleanup 失败保留孤儿 lease，全量擦除必须有界失败不得误报成功', () async {
    await expectLater(
      ChatRuntimeCore.debugRunBackgroundLeaseForTest<void>(
        () async => throw StateError('background-cleanup-failed'),
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      throwsA(isA<StateError>()),
    );
    final orphanLeases = await chatDocumentsRoot
        .list(followLinks: false)
        .where(
          (entity) => entity.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('.tatachat_sdk_chat_lease_${pid}_'),
        )
        .toList();
    expect(orphanLeases, hasLength(1));

    await expectLater(
      AppLockService.wipeAllData(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugDeleteSecureStorage: () async {},
        debugClearSharedPreferences: () async {},
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ).timeout(_wipeTimeout),
      throwsA(
        isA<AppDataWipeException>().having(
          (error) => error.failures,
          'failures',
          contains(contains('ChatFiles')),
        ),
      ),
    );
    expect(
      await ChatRuntimeCore.readPersistentAppDataWipeState(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      ChatPersistentWipeState.pending,
    );
    expect(await orphanLeases.single.exists(), isTrue);
  });

  test('跨 isolate lease 封住平台清理竞态，complete 后新后台任务仍被拒绝', () async {
    final backgroundEntered = Completer<void>();
    final releaseBackground = Completer<void>();
    final background = ChatRuntimeCore.debugRunBackgroundLeaseForTest<void>(
      () async {
        backgroundEntered.complete();
        await releaseBackground.future;
      },
      documentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    await backgroundEntered.future.timeout(_shortQueueTimeout);

    var secureStorageAttempted = false;
    var sharedPreferencesAttempted = false;
    var wipeCompleted = false;
    final wipe = AppLockService.wipeAllData(
      wallet: null,
      accountSecurity: null,
      debugDeleteCitizenSdkWallet: () async {},
      debugDeleteSecureStorage: () async => secureStorageAttempted = true,
      debugClearSharedPreferences: () async =>
          sharedPreferencesAttempted = true,
      debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    wipe.whenComplete(() => wipeCompleted = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(wipeCompleted, isFalse);
    expect(secureStorageAttempted, isFalse);
    expect(sharedPreferencesAttempted, isFalse);

    releaseBackground.complete();
    await background.timeout(_shortQueueTimeout);
    await wipe.timeout(_wipeTimeout);
    expect(secureStorageAttempted, isTrue);
    expect(sharedPreferencesAttempted, isTrue);
    expect(
      await ChatRuntimeCore.readPersistentAppDataWipeState(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      ChatPersistentWipeState.complete,
    );

    var lateBackgroundRan = false;
    await expectLater(
      ChatRuntimeCore.debugRunBackgroundLeaseForTest<void>(
        () async => lateBackgroundRan = true,
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      throwsA(isA<StateError>()),
    );
    expect(lateBackgroundRan, isFalse);

    // 模拟新进程：complete 只有在当前 PID 无孤儿 lease 时才能清理。
    await ChatRuntimeCore.debugResetProcessWipeForTest();
    final staleLease = File(
      '${chatDocumentsRoot.path}/.tatachat_sdk_chat_lease_${pid}_stale.lease',
    );
    await staleLease.create();
    expect(
      await AppLockService.recoverPersistentWipeAtStartup(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      AppDataWipeStartupResult.preflightBlocked,
    );
    expect(await staleLease.exists(), isTrue);
    await staleLease.delete();
    expect(
      await AppLockService.recoverPersistentWipeAtStartup(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      AppDataWipeStartupResult.ready,
    );
    expect(
      await ChatRuntimeCore.readPersistentAppDataWipeState(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      ChatPersistentWipeState.none,
    );
  });

  test('普通启动没有 wipe marker 时直接放行，绝不触发擦除或数据转换', () async {
    var secureStorageCalls = 0;
    var sharedPreferencesCalls = 0;
    expect(
      await AppLockService.recoverPersistentWipeAtStartup(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugDeleteSecureStorage: () async => secureStorageCalls += 1,
        debugClearSharedPreferences: () async => sharedPreferencesCalls += 1,
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      AppDataWipeStartupResult.ready,
    );
    expect(secureStorageCalls, 0);
    expect(sharedPreferencesCalls, 0);
    expect(
      await ChatRuntimeCore.readPersistentAppDataWipeState(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      ChatPersistentWipeState.none,
    );
  });

  // 普通启动只判断擦除 marker；后台收件 lease 由独立恢复阶段整理。
  test('普通启动没有 wipe marker 时不等待正在运行的后台收件 lease', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final background = ChatRuntimeCore.debugRunBackgroundLeaseForTest<void>(
      () async {
        entered.complete();
        await release.future;
      },
      documentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    await entered.future.timeout(_shortQueueTimeout);
    try {
      expect(
        await AppLockService.recoverPersistentWipeAtStartup(
          wallet: null,
          accountSecurity: null,
          debugDeleteCitizenSdkWallet: () async {},
          debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
        ).timeout(_shortQueueTimeout),
        AppDataWipeStartupResult.ready,
      );
    } finally {
      if (!release.isCompleted) release.complete();
      await background;
    }
  });

  // 覆盖安装先放行启动，再由显式恢复入口退役旧进程 lease，绝不删除聊天密文。
  test('覆盖安装后的新进程立即退役上一 PID 的新鲜 CID lease 且保留 Chat 数据', () async {
    final digest = crypto.sha256.convert(_ownerUserId.codeUnits).toString();
    final orphanLease = File(
      '${chatDocumentsRoot.path}/.tatachat_sdk_chat_user_'
      '$digest.mutation_lease',
    );
    await orphanLease.writeAsString(
      '${pid + 100000}\nother-process-generation\nother-process-nonce\n',
      flush: true,
    );
    await orphanLease.setLastModified(DateTime.now());
    final retainedCiphertext = File(
      '${chatDocumentsRoot.path}/chat/by_user/retained/ciphertext.bin',
    );
    await retainedCiphertext.parent.create(recursive: true);
    await retainedCiphertext.writeAsBytes(const <int>[7, 8, 9], flush: true);

    expect(
      await AppLockService.recoverPersistentWipeAtStartup(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ).timeout(_shortQueueTimeout),
      AppDataWipeStartupResult.ready,
    );
    expect(await orphanLease.exists(), isTrue);
    await ChatRuntimeCore.recoverStartupArtifacts(
      documentsDirectoryProvider: () async => chatDocumentsRoot,
    );
    expect(await orphanLease.exists(), isFalse);
    expect(await retainedCiphertext.readAsBytes(), const <int>[7, 8, 9]);
    expect(
      await ChatRuntimeCore.readPersistentAppDataWipeState(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      ChatPersistentWipeState.none,
    );
  });

  test('普通启动遇到当前进程 CID lease 时放行且不删除活锁', () async {
    final leaseEntered = Completer<void>();
    final releaseLease = Completer<void>();
    final heldLease = ChatRuntimeCore.debugRunUserMutationLeaseForTest<void>(
      userId: _ownerUserId,
      documentsDirectoryProvider: () async => chatDocumentsRoot,
      operation: () async {
        leaseEntered.complete();
        await releaseLease.future;
      },
    );
    try {
      await leaseEntered.future.timeout(_shortQueueTimeout);
      expect(
        await AppLockService.recoverPersistentWipeAtStartup(
          wallet: null,
          accountSecurity: null,
          debugDeleteCitizenSdkWallet: () async {},
          debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
        ).timeout(_shortQueueTimeout),
        AppDataWipeStartupResult.ready,
      );
      final digest = crypto.sha256.convert(_ownerUserId.codeUnits).toString();
      expect(
        File(
          '${chatDocumentsRoot.path}/.tatachat_sdk_chat_user_'
          '$digest.mutation_lease',
        ).existsSync(),
        isTrue,
      );
    } finally {
      if (!releaseLease.isCompleted) releaseLease.complete();
      await heldLease;
    }
  });

  test('普通启动遇到损坏的 CID lease 时放行且后台整理失败关闭', () async {
    final digest = crypto.sha256.convert(_ownerUserId.codeUnits).toString();
    final damagedLease = File(
      '${chatDocumentsRoot.path}/.tatachat_sdk_chat_user_'
      '$digest.mutation_lease',
    );
    await damagedLease.writeAsString('damaged-owner', flush: true);
    final retainedCiphertext = File(
      '${chatDocumentsRoot.path}/chat/by_user/retained/ciphertext.bin',
    );
    await retainedCiphertext.parent.create(recursive: true);
    await retainedCiphertext.writeAsBytes(const <int>[4, 5, 6], flush: true);

    expect(
      await AppLockService.recoverPersistentWipeAtStartup(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ).timeout(_shortQueueTimeout),
      AppDataWipeStartupResult.ready,
    );
    await expectLater(
      ChatRuntimeCore.recoverStartupArtifacts(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await damagedLease.readAsString(), 'damaged-owner');
    expect(await retainedCiphertext.readAsBytes(), const <int>[4, 5, 6]);
  });

  test('普通启动无法读取 marker 时只 fail-closed，不得猜测 pending 并擦除', () async {
    var secureStorageCalls = 0;
    var sharedPreferencesCalls = 0;
    expect(
      await AppLockService.recoverPersistentWipeAtStartup(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugDeleteSecureStorage: () async => secureStorageCalls += 1,
        debugClearSharedPreferences: () async => sharedPreferencesCalls += 1,
        debugChatDocumentsDirectoryProvider: () async {
          throw StateError('documents-root-unavailable');
        },
      ),
      AppDataWipeStartupResult.preflightBlocked,
    );
    expect(secureStorageCalls, 0);
    expect(sharedPreferencesCalls, 0);
  });

  test('部分擦除保留 pending 跨重启拒绝 Chat，无 PIN 重试成功才转 complete', () async {
    await expectLater(
      AppLockService.wipeAllData(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugDeleteSecureStorage: () async {
          throw StateError('secure-storage-partial-failure');
        },
        debugClearSharedPreferences: () async {},
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      throwsA(isA<AppDataWipeException>()),
    );
    expect(
      await ChatRuntimeCore.readPersistentAppDataWipeState(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      ChatPersistentWipeState.pending,
    );

    await ChatRuntimeCore.debugResetProcessWipeForTest();
    var backgroundRan = false;
    await expectLater(
      ChatRuntimeCore.debugRunBackgroundLeaseForTest<void>(
        () async => backgroundRan = true,
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      throwsA(isA<StateError>()),
    );
    expect(backgroundRan, isFalse);

    expect(
      await AppLockService.recoverPersistentWipeAtStartup(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugDeleteSecureStorage: () async {},
        debugClearSharedPreferences: () async {},
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ).timeout(_wipeTimeout),
      AppDataWipeStartupResult.dataWiped,
    );
    expect(
      await ChatRuntimeCore.readPersistentAppDataWipeState(
        documentsDirectoryProvider: () async => chatDocumentsRoot,
      ),
      ChatPersistentWipeState.complete,
    );
  });

  test('Chat 操作永久挂起时全量擦除仍推进 Wallet 与平台存储清理', () async {
    const walletMarkerKey = 'test:wipe-progress-wallet-marker';
    await Future.wait<void>(<Future<void>>[
      ChatIsar.instance.db().then<void>((_) {}),
      WalletIsar.instance.writeTxn<void>((isar) async {
        await isar.walletAttestationEntitys.put(
          WalletAttestationEntity()
            ..id = 0
            ..lastRequestPayload = walletMarkerKey,
        );
      }),
    ]);

    final chatEntered = Completer<void>();
    final releaseChat = Completer<void>();
    final secureStorageAttempted = Completer<void>();
    final sharedPreferencesAttempted = Completer<void>();
    final blockedChat = ChatIsar.instance.read<void>((_) async {
      chatEntered.complete();
      await releaseChat.future;
    });

    AppDataWipeException? wipeFailure;
    var blockedResultChecked = false;
    try {
      await chatEntered.future.timeout(_shortQueueTimeout);
      final wipe = AppLockService.wipeAllData(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugDeleteSecureStorage: () async {
          secureStorageAttempted.complete();
        },
        debugClearSharedPreferences: () async {
          sharedPreferencesAttempted.complete();
        },
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      );

      await Future.wait<void>(<Future<void>>[
        secureStorageAttempted.future,
        sharedPreferencesAttempted.future,
      ]).timeout(_shortQueueTimeout);
      expect(releaseChat.isCompleted, isFalse);

      try {
        await wipe.timeout(_wipeTimeout);
      } on AppDataWipeException catch (error) {
        // 原生库若无法强制关闭活动句柄，必须有界返回且明确暴露 Chat 删除失败。
        wipeFailure = error;
      }
      if (wipeFailure != null) {
        expect(
          wipeFailure.failures.any((failure) => failure.contains('ChatIsar')),
          isTrue,
        );
        expect(
          wipeFailure.failures.any(
            (failure) =>
                failure.contains('WalletIsar') ||
                failure.contains('SecureStorage') ||
                failure.contains('SharedPreferences'),
          ),
          isFalse,
        );
      }

      await expectLater(WalletIsar.instance.db(), throwsA(isA<StateError>()));
      await expectLater(ChatIsar.instance.db(), throwsA(isA<StateError>()));

      releaseChat.complete();
      await expectLater(blockedChat, throwsA(isA<StateError>()));
      blockedResultChecked = true;

      await Future.wait<void>(<Future<void>>[
        WalletIsar.instance.resetForTest(),
        ChatIsar.instance.resetForTest(),
      ]).timeout(_wipeTimeout);
      final walletMarker = await WalletIsar.instance.read<String?>((
        isar,
      ) async {
        return (await isar.walletAttestationEntitys.get(0))?.lastRequestPayload;
      });
      expect(walletMarker, isNull);
    } finally {
      if (!releaseChat.isCompleted) releaseChat.complete();
      if (!blockedResultChecked) {
        await blockedChat.catchError((_) {});
      }
    }
  });

  test('双库 reset 后旧 action 失败且旧 finally 不污染新 generation', () async {
    await Future.wait<void>(<Future<void>>[
      ChatIsar.instance.db().then<void>((_) {}),
      WalletIsar.instance.db().then<void>((_) {}),
    ]);

    final oldChatEntered = Completer<void>();
    final oldWalletEntered = Completer<void>();
    final releaseOldChat = Completer<void>();
    final releaseOldWallet = Completer<void>();
    final releaseNewChat = Completer<void>();
    final releaseNewWallet = Completer<void>();
    final oldChat = ChatIsar.instance.read<String>((_) async {
      oldChatEntered.complete();
      await releaseOldChat.future;
      return 'old-chat-result';
    });
    final oldWallet = WalletIsar.instance.read<String>((_) async {
      oldWalletEntered.complete();
      await releaseOldWallet.future;
      return 'old-wallet-result';
    });
    Future<String>? newChat;
    Future<String>? newWallet;

    try {
      await Future.wait<void>(<Future<void>>[
        oldChatEntered.future,
        oldWalletEntered.future,
      ]).timeout(_shortQueueTimeout);
      await Future.wait<void>(<Future<void>>[
        ChatIsar.instance.resetForTest(),
        WalletIsar.instance.resetForTest(),
      ]).timeout(_wipeTimeout);

      final newChatEntered = Completer<void>();
      final newWalletEntered = Completer<void>();
      newChat = ChatIsar.instance.read<String>((_) async {
        newChatEntered.complete();
        await releaseNewChat.future;
        return 'new-chat-result';
      });
      newWallet = WalletIsar.instance.read<String>((_) async {
        newWalletEntered.complete();
        await releaseNewWallet.future;
        return 'new-wallet-result';
      });
      await Future.wait<void>(<Future<void>>[
        newChatEntered.future,
        newWalletEntered.future,
      ]).timeout(_shortQueueTimeout);

      final oldChatRejected = expectLater(oldChat, throwsA(isA<StateError>()));
      final oldWalletRejected = expectLater(
        oldWallet,
        throwsA(isA<StateError>()),
      );
      releaseOldChat.complete();
      releaseOldWallet.complete();
      await Future.wait<void>(<Future<void>>[
        oldChatRejected,
        oldWalletRejected,
      ]).timeout(_shortQueueTimeout);

      expect(ChatIsar.instance.hasActiveOperation, isTrue);
      expect(WalletIsar.instance.hasActiveOperation, isTrue);

      releaseNewChat.complete();
      releaseNewWallet.complete();
      expect(await newChat.timeout(_shortQueueTimeout), 'new-chat-result');
      expect(await newWallet.timeout(_shortQueueTimeout), 'new-wallet-result');
      expect(ChatIsar.instance.hasActiveOperation, isFalse);
      expect(WalletIsar.instance.hasActiveOperation, isFalse);
    } finally {
      if (!releaseOldChat.isCompleted) releaseOldChat.complete();
      if (!releaseOldWallet.isCompleted) releaseOldWallet.complete();
      if (!releaseNewChat.isCompleted) releaseNewChat.complete();
      if (!releaseNewWallet.isCompleted) releaseNewWallet.complete();
      await Future.wait<void>(<Future<void>>[
        oldChat.then<void>((_) {}, onError: (_, __) {}),
        oldWallet.then<void>((_) {}, onError: (_, __) {}),
        if (newChat != null) newChat.then<void>((_) {}, onError: (_, __) {}),
        if (newWallet != null)
          newWallet.then<void>((_) {}, onError: (_, __) {}),
      ]);
    }
  });

  test('任一擦除步骤失败会聚合报错且不阻止其它步骤', () async {
    var sharedPreferencesAttempted = false;

    await expectLater(
      AppLockService.wipeAllData(
        wallet: null,
        accountSecurity: null,
        debugDeleteCitizenSdkWallet: () async {},
        debugDeleteSecureStorage: () async {
          throw StateError('secure-storage-test-failure');
        },
        debugClearSharedPreferences: () async {
          sharedPreferencesAttempted = true;
        },
        debugChatDocumentsDirectoryProvider: () async => chatDocumentsRoot,
      ).timeout(_wipeTimeout),
      throwsA(
        isA<AppDataWipeException>().having(
          (error) => error.failures,
          'failures',
          contains(
            contains('SecureStorage：Bad state: secure-storage-test-failure'),
          ),
        ),
      ),
    );
    expect(sharedPreferencesAttempted, isTrue);
  });

  test('resetForTest 与正在打开的双库串行收口并恢复新实例', () async {
    final walletOpening = WalletIsar.instance.db();
    final chatOpening = ChatIsar.instance.db();
    final walletOpeningRejected = expectLater(
      walletOpening,
      throwsA(isA<Exception>()),
    );
    final chatOpeningRejected = expectLater(
      chatOpening,
      throwsA(isA<Exception>()),
    );

    await Future.wait<void>(<Future<void>>[
      WalletIsar.instance.resetForTest(),
      ChatIsar.instance.resetForTest(),
    ]).timeout(_wipeTimeout);
    await Future.wait<void>(<Future<void>>[
      walletOpeningRejected,
      chatOpeningRejected,
    ]);

    await Future.wait<void>(<Future<void>>[
      WalletIsar.instance.db().then<void>((_) {}),
      ChatIsar.instance.db().then<void>((_) {}),
    ]).timeout(_wipeTimeout);
  });

  testWidgets('PIN 验证收到 dataWiped 显示不可继续的退出终态', (tester) async {
    AppLockService.debugConfigureForTest(
      isLocked: () async => false,
      verifyPin: (_) async => AppPinVerificationResult.dataWiped,
    );
    await tester.pumpWidget(
      const MaterialApp(home: PinInputPage(mode: PinInputMode.verify)),
    );
    await tester.pump();

    await _enterSixDigitPin(tester);
    await tester.pumpAndSettle();

    expect(find.text('数据已清空'), findsOneWidget);
    expect(find.text('退出'), findsOneWidget);
    expect(find.textContaining('还可尝试'), findsNothing);
  });

  testWidgets('PIN 关闭模式收到 dataWiped 不会继续 removePin', (tester) async {
    var removeCalls = 0;
    AppLockService.debugConfigureForTest(
      verifyPin: (_) async => AppPinVerificationResult.dataWiped,
      removePin: () async => removeCalls += 1,
    );
    await tester.pumpWidget(
      const MaterialApp(home: PinInputPage(mode: PinInputMode.remove)),
    );
    await tester.pump();

    await _enterSixDigitPin(tester);
    await tester.pumpAndSettle();

    expect(find.text('数据已清空'), findsOneWidget);
    expect(removeCalls, 0);
  });

  testWidgets('PIN 部分擦除只显示重试/退出且不泄漏底层失败', (tester) async {
    var retryCalls = 0;
    AppLockService.debugConfigureForTest(
      isLocked: () async => false,
      verifyPin: (_) async {
        throw AppDataWipeException(<String>[
          'SecureStorage:/private/secret-domain-marker',
        ]);
      },
      wipeAllData: () async => retryCalls += 1,
    );
    await tester.pumpWidget(
      const MaterialApp(home: PinInputPage(mode: PinInputMode.verify)),
    );
    await tester.pump();

    await _enterSixDigitPin(tester);
    await tester.pumpAndSettle();
    expect(find.text('数据清理未完成'), findsOneWidget);
    expect(find.text('重试擦除'), findsOneWidget);
    expect(find.text('退出'), findsOneWidget);
    expect(find.textContaining('secret-domain-marker'), findsNothing);

    await tester.tap(find.text('重试擦除'));
    await tester.pumpAndSettle();
    expect(retryCalls, 1);
    expect(find.text('数据已清空'), findsOneWidget);
  });

  testWidgets('PIN 提交期间键盘失效且只发起一次验证', (tester) async {
    final verifyResult = Completer<AppPinVerificationResult>();
    var verifyCalls = 0;
    AppLockService.debugConfigureForTest(
      isLocked: () async => false,
      verifyPin: (_) {
        verifyCalls += 1;
        return verifyResult.future;
      },
    );
    await tester.pumpWidget(
      const MaterialApp(home: PinInputPage(mode: PinInputMode.verify)),
    );
    await tester.pump();

    await _enterSixDigitPin(tester);
    expect(verifyCalls, 1);
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.tap(find.text('7'));
    await tester.tap(find.text('6'));
    await tester.pump();
    expect(verifyCalls, 1);

    verifyResult.complete(AppPinVerificationResult.dataWiped);
    await tester.pumpAndSettle();
    expect(find.text('数据已清空'), findsOneWidget);
  });
}
