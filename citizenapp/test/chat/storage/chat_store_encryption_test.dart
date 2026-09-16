import 'package:citizenapp/chat/tatachat_sdk_adapter.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:tatachat_sdk/tatachat_sdk.dart';
import 'package:citizenapp/security/local_data_key.dart';
import 'package:citizenapp/security/account_security_service.dart';
import 'package:citizenapp/my/myid/current_user_context.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:fixnum/fixnum.dart';
import 'package:isar_community/isar.dart';
import 'package:flutter_test/flutter_test.dart';

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

  @override
  Map<String, Object> toJson() => <String, Object>{
    'key_domain': keyDomain,
    'user_id': userId,
    'binding_revision': bindingRevision,
    'account_id': accountId,
  };
}

class _HandoverWalletManager implements AccountSecurityService {
  _HandoverWalletManager(_TestBinding sourceBinding)
    : sourceBinding = sourceBinding,
      activeBinding = sourceBinding;

  final _TestBinding sourceBinding;
  _TestBinding activeBinding;

  Uint8List _key(String accountId, LocalKeyPurpose purpose) {
    if (accountId == sourceBinding.accountId) {
      final fixed = debugChatKeys[purpose];
      if (fixed != null) return Uint8List.fromList(fixed);
      return Uint8List.fromList(
        List<int>.generate(
          32,
          (index) => (0x20 + purpose.index * 13 + index) & 0xff,
        ),
      );
    }
    return Uint8List.fromList(
      List<int>.generate(
        32,
        (index) => (0x80 + purpose.index * 13 + index) & 0xff,
      ),
    );
  }

  @override
  Future<_TestBinding> accountDataBindingForAccountId(String accountId) async {
    if (activeBinding.accountId != accountId) {
      throw StateError('测试账户不是当前绑定账户');
    }
    return activeBinding;
  }

  @override
  Future<Uint8List> readDataKeyForCurrentBinding(
    String accountId,
    LocalKeyPurpose purpose, {
    String? context,
  }) async => _key(accountId, purpose);

  @override
  Future<List<Uint8List>> readDataKeysForBinding(
    AccountDataBinding binding,
    List<({String? context, LocalKeyPurpose purpose})> requests,
  ) async => requests
      .map((request) => _key(binding.accountId, request.purpose))
      .toList(growable: false);

  @override
  Future<List<Uint8List>> deriveDataKeysForBindingHandover(
    AccountDataBinding binding,
    List<({String? context, LocalKeyPurpose purpose})> requests,
  ) => readDataKeysForBinding(binding, requests);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCurrentUserContext implements CurrentUserContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingTargetHandoverWalletManager extends _HandoverWalletManager {
  _FailingTargetHandoverWalletManager(
    super.sourceBinding,
    this.targetAccountId,
  );

  final String targetAccountId;
  final List<Uint8List> issuedSourceKeys = <Uint8List>[];

  bool get sourceKeysDisposed =>
      issuedSourceKeys.isNotEmpty &&
      issuedSourceKeys.every((key) => key.every((value) => value == 0));

  @override
  Future<List<Uint8List>> deriveDataKeysForBindingHandover(
    AccountDataBinding binding,
    List<({String? context, LocalKeyPurpose purpose})> requests,
  ) async {
    if (binding.accountId == targetAccountId) {
      throw StateError('测试目标绑定子钥获取失败');
    }
    final keys = await super.deriveDataKeysForBindingHandover(
      binding,
      requests,
    );
    issuedSourceKeys.addAll(keys);
    return keys;
  }
}

class _FailOnceCommitChatStore extends ChatStore {
  _FailOnceCommitChatStore({required ChatCrypto crypto})
    : super(crypto: crypto);

  int commitCalls = 0;

  @override
  Future<void> commitAccountHandover({
    required ChatDataBinding source,
    required ChatDataBinding target,
  }) async {
    commitCalls += 1;
    if (commitCalls == 1) {
      throw StateError('测试注入 Store commit 首次失败');
    }
    return super.commitAccountHandover(source: source, target: target);
  }
}

/// 把一条来源绑定消息暂停在摘要已加密、尚未写入 ChatIsar 的窗口。
class _PausingSummaryChatCrypto extends ChatCrypto {
  _PausingSummaryChatCrypto(AccountSecurityService accountSecurity)
    : super(CitizenChatStorageKeyProvider(accountSecurity));

  Completer<void>? _paused;
  Completer<void>? _resume;
  int _remainingEncryptions = 0;

  void pauseNextMessageBeforeWrite() {
    _paused = Completer<void>();
    _resume = Completer<void>();
    // saveIncomingMessage 先加密正文，再加密会话摘要。
    _remainingEncryptions = 2;
  }

  Future<void> waitUntilPaused() => _paused!.future;

  void resume() {
    final gate = _resume;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<String> encryptText({
    required String ownerUserId,
    required String currentAccountId,
    required String recordId,
    required String plaintext,
    ChatCipherBinding? binding,
  }) async {
    final cipher = await super.encryptText(
      ownerUserId: ownerUserId,
      currentAccountId: currentAccountId,
      recordId: recordId,
      plaintext: plaintext,
      binding: binding,
    );
    if (_remainingEncryptions > 0) {
      _remainingEncryptions -= 1;
      if (_remainingEncryptions == 0) {
        _paused!.complete();
        await _resume!.future;
      }
    }
    return cipher;
  }
}

/// 空会话读取不应触碰钱包绑定或聊天用途钥；任一入口被调用都由测试立即失败。
class _FailIfEmptyChatOpensKeys extends ChatCrypto {
  int bindingResolveCount = 0;
  int sessionOpenCount = 0;

  @override
  Future<ChatCipherBinding> resolveCipherBinding({
    required String ownerUserId,
    required String currentAccountId,
    String? expectedKeyDomain,
  }) async {
    bindingResolveCount += 1;
    throw StateError('空会话不应解析钱包绑定');
  }

  @override
  Future<ChatCipherSession> openCipherSession({
    required String ownerUserId,
    required String currentAccountId,
    ChatCipherBinding? binding,
  }) async {
    sessionOpenCount += 1;
    throw StateError('空会话不应打开聊天用途钥');
  }
}

/// 聊天正文静止态加密 + HMAC 分词搜索的端到端验收。
///
/// 重点不是"能存能取"，而是：**Isar 原始行里不得出现明文**，且加密后搜索
/// 语义与解码后摘要的 `contains` 完全一致（含假阳性必须被复验滤掉）。
void main() {
  useIsolatedIsar();

  const accountId =
      '0x'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const ownerUserId = 'CN220-CTZN2-100000001-2026';
  const peerUserId = 'CN220-CTZN2-100000002-2026';
  const handoverGenesisHash =
      '0x1111111111111111111111111111111111111111111111111111111111111111';
  const handoverTargetAccountId =
      '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const handoverSource = _TestBinding(
    genesisHash: handoverGenesisHash,
    cidNumber: ownerUserId,
    bindingRevision: 1,
    accountId: accountId,
  );
  const handoverTarget = _TestBinding(
    genesisHash: handoverGenesisHash,
    cidNumber: ownerUserId,
    bindingRevision: 2,
    accountId: handoverTargetAccountId,
  );

  Directory bindingDirectory(Directory root, _TestBinding binding) => Directory(
    '${root.path}/chat/by_user/${binding.cidNumber}/by_binding/'
    '${binding.bindingRevision}/${binding.accountId}',
  );

  Map<String, dynamic> receiptMessage(File marker) =>
      jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;

  Map<String, dynamic> receiptPayload(File marker) =>
      jsonDecode(receiptMessage(marker)['payload_json'] as String)
          as Map<String, dynamic>;

  Future<
    ({
      Directory root,
      Directory sourceDirectory,
      Directory targetDirectory,
      File receipt,
      _HandoverWalletManager manager,
      ChatStore store,
      ChatSdk runtime,
    })
  >
  createRuntimeHandoverFixture({
    ChatStore Function(_HandoverWalletManager manager)? createStore,
  }) async {
    final root = await Directory.systemTemp.createTemp('gmb-chat-binding-');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final manager = _HandoverWalletManager(handoverSource);
    final store =
        createStore?.call(manager) ??
        ChatStore(crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)));
    await store.activateBindingFence(handoverSource);
    final currentUserContext = _UnusedCurrentUserContext();
    final runtime = createCitizenChatRuntime(
      store: store,
      accountSecurity: manager,
      currentUserContext: currentUserContext,
      squareSessionProvider: SquareSessionProvider(
        accountSecurity: manager,
        currentUserContext: currentUserContext,
      ),
      documentsDirectoryProvider: () async => root,
    );
    final sourceDirectory = bindingDirectory(root, handoverSource);
    final targetDirectory = bindingDirectory(root, handoverTarget);
    final receipt = File(
      ChatRuntimeCore.debugFileHandoverReceiptPathForTest(
        bindingDirectory: sourceDirectory,
        target: handoverTarget,
      ),
    );
    return (
      root: root,
      sourceDirectory: sourceDirectory,
      targetDirectory: targetDirectory,
      receipt: receipt,
      manager: manager,
      store: store,
      runtime: runtime,
    );
  }

  EncryptedMessage messageOf({
    required String messageId,
    required String conversationId,
    int createdAtMillis = 1000,
  }) {
    return EncryptedMessage()
      ..messageId = messageId
      ..conversationId = conversationId
      ..senderUserId = peerUserId
      ..deliveries.add(
        EncryptedDelivery(recipient: Recipient(userId: ownerUserId)),
      )
      ..senderDeviceId = 'dev-1'
      ..createdAtMillis = Int64(createdAtMillis);
  }

  Future<void> saveText(
    ChatStore store,
    String messageId,
    String text, {
    String conversationId = 'conv-1',
    int at = 1000,
    String currentAccountId = accountId,
  }) async {
    final binding = _TestBinding(
      genesisHash:
          '0x1111111111111111111111111111111111111111111111111111111111111111',
      cidNumber: ownerUserId,
      bindingRevision: currentAccountId == accountId ? 1 : 2,
      accountId: currentAccountId,
    );
    late ChatBindingFenceToken bindingToken;
    try {
      bindingToken = await store.captureBindingFenceToken(binding);
    } on StateError {
      bindingToken = await store.activateBindingFence(binding);
    }
    return store.saveIncomingMessage(
      bindingToken: bindingToken,
      ownerUserId: ownerUserId,
      currentAccountId: currentAccountId,
      message: messageOf(
        messageId: messageId,
        conversationId: conversationId,
        createdAtMillis: at,
      ),
      messageBytes: const <int>[1, 2, 3],
      messageKind: ChatMessageKind.text,
      plaintext: ChatPayloadCodec.encode(ChatContent.text(text)),
    );
  }

  test('正文与会话摘要落盘为密文，Isar 原始行不含明文', () async {
    final store = ChatStore();
    const secret = '这是一条不该出现在磁盘上的悄悄话';
    await saveText(store, 'env-1', secret);

    // 绕过 ChatStore 直接查原始行，确认磁盘上没有明文。
    final rows = await ChatIsar.instance.read((isar) async {
      return isar.chatMessageEntitys
          .filter()
          .idGreaterThan(0, include: true)
          .findAll();
    });
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.plaintextCipher, isNotNull);
    expect(row.plaintextCipher, isNot(contains(secret)));
    expect(row.searchTokens, isNotEmpty);
    // 索引里存的是 HMAC 截断值，不得出现任何明文片段
    for (final token in row.searchTokens) {
      expect(secret.contains(token), isFalse);
    }

    final conversations = await ChatIsar.instance.read((isar) async {
      return isar.chatConversationEntitys
          .filter()
          .idGreaterThan(0, include: true)
          .findAll();
    });
    expect(conversations.single.lastMessageCipher, isNot(contains(secret)));
  });

  test('待发送消息先以本机密文进入会话，再与正式 Message 原子替换', () async {
    final store = ChatStore();
    final token = await store.activateBindingFence(handoverSource);
    const localMessageId = 'pending:conv-pending:1000:nonce';
    final payload = ChatPayloadCodec.encode(ChatContent.text('离线先保存'));

    await store.savePendingOutgoingMessage(
      bindingToken: token,
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      localMessageId: localMessageId,
      conversationId: 'conv-pending',
      recipientUserId: peerUserId,
      messageKind: ChatMessageKind.text,
      payload: payload,
      createdAtMillis: 1000,
    );

    final rawPending = await ChatIsar.instance.read(
      (isar) => isar.chatMessageEntitys.getByOwnerUserIdMessageId(
        ownerUserId,
        localMessageId,
      ),
    );
    expect(rawPending, isNotNull);
    expect(rawPending!.messageBytesHex, isEmpty);
    expect(rawPending.plaintextCipher, isNot(contains('离线先保存')));
    expect(
      (await store.readMessages(
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
        conversationId: 'conv-pending',
      )).single.plaintext,
      payload,
    );
    expect(
      (await store.readPendingOutgoingMessages(
        bindingToken: token,
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
      )).single.localMessageId,
      localMessageId,
    );

    final message = EncryptedMessage()
      ..messageId = 'env-pending-formal'
      ..conversationId = 'conv-pending'
      ..senderUserId = ownerUserId
      ..deliveries.add(
        EncryptedDelivery(recipient: Recipient(userId: peerUserId)),
      )
      ..senderDeviceId = 'alice-phone'
      ..createdAtMillis = Int64(1001);
    await store.saveOutgoingMessage(
      bindingToken: token,
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      message: message,
      messageBytes: message.writeToBuffer(),
      recipientUserId: peerUserId,
      messageKind: ChatMessageKind.text,
      deliveryState: ChatMessageDeliveryState.queued,
      plaintext: payload,
      pendingLocalMessageId: localMessageId,
    );

    final rows = await ChatIsar.instance.read(
      (isar) => isar.chatMessageEntitys
          .filter()
          .ownerUserIdEqualTo(ownerUserId)
          .conversationIdEqualTo('conv-pending')
          .findAll(),
    );
    expect(rows.map((row) => row.messageId), ['env-pending-formal']);
    expect(
      await store.readPendingOutgoingMessages(
        bindingToken: token,
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
      ),
      isEmpty,
    );
    expect(await store.outboundQueueCount(ownerUserId), 1);
  });

  test('较早待发送消息转正式 Message 时不回退较新的会话摘要', () async {
    final store = ChatStore();
    final token = await store.activateBindingFence(handoverSource);
    const conversationId = 'conv-pending-order';
    const firstLocalId = 'pending:conv-pending-order:1000:first';
    const latestLocalId = 'pending:conv-pending-order:2000:latest';
    final firstPayload = ChatPayloadCodec.encode(ChatContent.text('第一条'));
    final latestPayload = ChatPayloadCodec.encode(ChatContent.text('第二条'));

    for (final pending in <(String, String, int)>[
      (firstLocalId, firstPayload, 1000),
      (latestLocalId, latestPayload, 2000),
    ]) {
      await store.savePendingOutgoingMessage(
        bindingToken: token,
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
        localMessageId: pending.$1,
        conversationId: conversationId,
        recipientUserId: peerUserId,
        messageKind: ChatMessageKind.text,
        payload: pending.$2,
        createdAtMillis: pending.$3,
      );
    }

    final firstMessage = EncryptedMessage()
      ..messageId = 'env-pending-order-first'
      ..conversationId = conversationId
      ..senderUserId = ownerUserId
      ..deliveries.add(
        EncryptedDelivery(recipient: Recipient(userId: peerUserId)),
      )
      ..senderDeviceId = 'alice-phone'
      ..createdAtMillis = Int64(1000);
    await store.saveOutgoingMessage(
      bindingToken: token,
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      message: firstMessage,
      messageBytes: firstMessage.writeToBuffer(),
      recipientUserId: peerUserId,
      messageKind: ChatMessageKind.text,
      deliveryState: ChatMessageDeliveryState.queued,
      plaintext: firstPayload,
      pendingLocalMessageId: firstLocalId,
    );

    final preview = (await store.readConversationPreviews(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
    )).single;
    expect(preview.lastMessage, '第二条');
    expect(preview.lastUpdatedAt.millisecondsSinceEpoch, 2000);
    expect(
      (await store.readPendingOutgoingMessages(
        bindingToken: token,
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
        conversationId: conversationId,
      )).single.localMessageId,
      latestLocalId,
    );
  });

  test('读取侧解密还原，UI 拿到的仍是明文', () async {
    final store = ChatStore();
    const secret = '你好，公民';
    await saveText(store, 'env-1', secret);

    final messages = await store.readMessages(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      conversationId: 'conv-1',
    );
    expect(ChatPayloadCodec.decode(messages.single.plaintext!).text, secret);

    final previews = await store.readConversationPreviews(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
    );
    expect(previews.single.lastMessage, secret);
    expect(
      await store.readMessages(
        ownerUserId: 'CN220-CTZN2-999999999-2026',
        currentAccountId: accountId,
        conversationId: 'conv-1',
      ),
      isEmpty,
    );
  });

  test('空会话列表在 ChatIsar 返回后直接结束，不读取钱包绑定或用途钥', () async {
    final crypto = _FailIfEmptyChatOpensKeys();
    final store = ChatStore(crypto: crypto);

    final previews = await store.readConversationPreviews(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
    );

    expect(previews, isEmpty);
    expect(crypto.bindingResolveCount, 0);
    expect(crypto.sessionOpenCount, 0);
  });

  test('空聊天窗口按会话索引直接结束，不读取钱包绑定或用途钥', () async {
    final crypto = _FailIfEmptyChatOpensKeys();
    final store = ChatStore(crypto: crypto);

    final messages = await store.readMessages(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      conversationId: 'conv-empty-window',
    );

    expect(messages, isEmpty);
    expect(crypto.bindingResolveCount, 0);
    expect(crypto.sessionOpenCount, 0);
  });

  test('搜索：中文、英文、数字均可子串命中', () async {
    final store = ChatStore();
    await saveText(store, 'env-1', '今天天气很好', at: 1000);
    await saveText(store, 'env-2', 'hello world', at: 2000);
    await saveText(store, 'env-3', 'order 12345', at: 3000);

    Future<List<String>> hit(String q) async {
      final rows = await store.searchMessages(
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
        keyword: q,
      );
      return rows.map((r) => r.messageId).toList()..sort();
    }

    expect(await hit('天气'), <String>['env-1']);
    expect(await hit('ello'), <String>['env-2']);
    expect(await hit('234'), <String>['env-3']);
  });

  test('搜索大小写不敏感', () async {
    final store = ChatStore();
    await saveText(store, 'env-1', 'Hello World');
    final rows = await store.searchMessages(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      keyword: 'HELLO',
    );
    expect(rows, hasLength(1));
  });

  test('搜索：bigram 假阳性必须被解密复验滤掉', () async {
    final store = ChatStore();
    // "bcab" 的 bigram 含 ab 与 bc，会被索引当成 "abc" 的候选，
    // 但它并不真的包含 "abc"，必须在复验阶段被剔除。
    await saveText(store, 'env-1', 'bcab', at: 1000);
    await saveText(store, 'env-2', 'xabcx', at: 2000);

    final rows = await store.searchMessages(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      keyword: 'abc',
    );
    expect(rows.map((r) => r.messageId), <String>[
      'env-2',
    ], reason: '假阳性 bcab 必须被滤掉，只留真正包含 abc 的记录');
  });

  test('搜索：单字符查询无 bigram，仍能通过回落扫描命中', () async {
    final store = ChatStore();
    await saveText(store, 'env-1', '公民钱包');
    final rows = await store.searchMessages(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      keyword: '钱',
    );
    expect(rows, hasLength(1));
  });

  test('搜索：不命中返回空', () async {
    final store = ChatStore();
    await saveText(store, 'env-1', '今天天气很好');
    final rows = await store.searchMessages(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      keyword: '完全不相干的词',
    );
    expect(rows, isEmpty);
  });

  test('换错密钥解密必须抛错，不得静默返回空白', () async {
    final store = ChatStore();
    await saveText(store, 'env-1', '机密内容');
    await saveText(store, 'env-2', '仍可验证的内容', at: 2000);

    // 直接篡改密文，模拟密钥不匹配/密文损坏
    await ChatIsar.instance.writeTxn((isar) async {
      final row = await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
        ownerUserId,
        'env-1',
      );
      row!.plaintextCipher = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      await isar.chatMessageEntitys.putByOwnerUserIdMessageId(row);
    });

    await expectLater(
      store.readMessages(
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
        conversationId: 'conv-1',
      ),
      throwsA(isA<ChatLocalCipherException>()),
    );

    final display = await store.readMessagesForDisplay(
      ownerUserId: ownerUserId,
      currentAccountId: accountId,
      conversationId: 'conv-1',
    );
    expect(display.integrityFailureCount, 1);
    expect(display.messages.map((message) => message.messageId), ['env-2']);
    expect(
      ChatPayloadCodec.decode(display.messages.single.plaintext!).text,
      '仍可验证的内容',
      reason: '聊天窗口只隔离损坏行，严格 readMessages 仍保持 fail-closed',
    );
  });

  test('当前钱包签名换绑：pending 阻断两个绑定普通写，提交后新钱包解密历史消息', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(store, 'env-handover', '只有内存中出现的交接明文');
      final before = await ChatIsar.instance.read(
        (isar) async =>
            (await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
              ownerUserId,
              'env-handover',
            ))!.plaintextCipher!,
      );

      await store.stageAccountHandover(source: source, target: target);
      final stagedRows = await ChatIsar.instance.read(
        (isar) async => isar.chatAccountHandoverEntitys.where().findAll(),
      );
      expect(stagedRows, hasLength(1));
      expect(stagedRows.single.manifestJson, isNot(contains('只有内存中出现的交接明文')));
      final stagedManifest =
          jsonDecode(stagedRows.single.manifestJson) as Map<String, dynamic>;
      final stagedPayload = stagedManifest['payload_json'] as String;
      expect(stagedManifest.keys.toSet(), <String>{'payload_json', 'mac'});
      expect(stagedPayload, isNot(contains('"cipher"')));
      expect(stagedPayload, isNot(contains('"tokens"')));
      final stillSource = await ChatIsar.instance.read(
        (isar) async =>
            (await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
              ownerUserId,
              'env-handover',
            ))!.plaintextCipher!,
      );
      expect(stillSource, before, reason: 'finalized 前正式消息行不得切换');

      await expectLater(
        saveText(
          store,
          'env-handover-source-blocked',
          '交接窗口来源写入必须被拒绝',
          at: 2000,
        ),
        throwsA(isA<StateError>()),
      );
      manager.activeBinding = target;
      await expectLater(
        saveText(
          store,
          'env-handover-target-blocked',
          '交接窗口目标写入必须被拒绝',
          at: 3000,
          currentAccountId: newAccountId,
        ),
        throwsA(isA<StateError>()),
      );
      await store.commitAccountHandover(source: source, target: target);
      final committed = await ChatIsar.instance.read(
        (isar) async => (await isar.chatMessageEntitys
            .getByOwnerUserIdMessageId(ownerUserId, 'env-handover'))!,
      );
      final after = committed.plaintextCipher!;
      expect(after, isNot(before));
      expect(committed.bindingRevision, target.bindingRevision);
      expect(committed.accountId, target.accountId);
      final messages = await store.readMessages(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
        conversationId: 'conv-1',
      );
      expect(
        messages.map(
          (message) => ChatPayloadCodec.decode(message.plaintext!).text,
        ),
        <String>['只有内存中出现的交接明文'],
      );
      final previews = await store.readConversationPreviews(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
      );
      expect(previews.single.lastMessage, '只有内存中出现的交接明文');
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        0,
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('换绑 marker 整行缺失且来源密文仍在时必须失败，不能伪装成幂等完成', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(store, 'env-missing-marker', '清单不能静默消失');
      await store.stageAccountHandover(source: source, target: target);
      final before = await ChatIsar.instance.read(
        (isar) async => (await isar.chatMessageEntitys
            .getByOwnerUserIdMessageId(ownerUserId, 'env-missing-marker'))!,
      );
      await ChatIsar.instance.writeTxn((isar) async {
        final marker = await isar.chatAccountHandoverEntitys
            .where()
            .findFirst();
        await isar.chatAccountHandoverEntitys.delete(marker!.id);
      });

      await expectLater(
        store.commitAccountHandover(source: source, target: target),
        throwsA(isA<StateError>()),
      );
      final preserved = await ChatIsar.instance.read(
        (isar) async => (await isar.chatMessageEntitys.get(before.id))!,
      );
      expect(preserved.bindingRevision, source.bindingRevision);
      expect(preserved.accountId, source.accountId);
      expect(preserved.plaintextCipher, before.plaintextCipher);
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('换绑成功后重复 commit 只在来源为空且目标密文完整认证时幂等成功', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(store, 'env-idempotent', '重复提交仍须验真');
      await store.stageAccountHandover(source: source, target: target);
      manager.activeBinding = target;
      await store.commitAccountHandover(source: source, target: target);
      await store.commitAccountHandover(source: source, target: target);

      final messages = await store.readMessages(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
        conversationId: 'conv-1',
      );
      expect(
        ChatPayloadCodec.decode(messages.single.plaintext!).text,
        '重复提交仍须验真',
      );
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        0,
      );
      await ChatIsar.instance.writeTxn((isar) async {
        final row = await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
          ownerUserId,
          'env-idempotent',
        );
        row!.plaintextCipher = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
        await isar.chatMessageEntitys.put(row);
      });
      await expectLater(
        store.commitAccountHandover(source: source, target: target),
        throwsA(isA<ChatLocalCipherException>()),
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('清单覆盖消息被分别篡改到第三 owner 或 binding/account 时都失败并保留 marker', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const thirdAccountId =
        '0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(store, 'env-third-binding', '不能从过滤快照里消失');
      await store.stageAccountHandover(source: source, target: target);
      final rowId = await ChatIsar.instance.read(
        (isar) async =>
            (await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
              ownerUserId,
              'env-third-binding',
            ))!.id,
      );

      Future<void> expectTamperRejected(
        void Function(ChatMessageEntity) corrupt,
      ) async {
        await ChatIsar.instance.writeTxn((isar) async {
          final row = await isar.chatMessageEntitys.get(rowId);
          row!
            ..ownerUserId = source.cidNumber
            ..bindingRevision = source.bindingRevision
            ..accountId = source.accountId;
          corrupt(row);
          await isar.chatMessageEntitys.put(row);
        });
        await expectLater(
          store.commitAccountHandover(source: source, target: target),
          throwsA(isA<FormatException>()),
        );
      }

      await expectTamperRejected((row) => row.ownerUserId = peerUserId);
      await expectTamperRejected(
        (row) => row
          ..bindingRevision = 77
          ..accountId = thirdAccountId,
      );
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        1,
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('正确 MAC 清单中的非空会话摘要被清空时必须失败并保留 marker', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(store, 'env-clear-summary', '会话摘要不可降级为空');
      await store.stageAccountHandover(source: source, target: target);
      await ChatIsar.instance.writeTxn((isar) async {
        final row = await isar.chatConversationEntitys
            .getByOwnerUserIdConversationId(ownerUserId, 'conv-1');
        row!.lastMessageCipher = '';
        await isar.chatConversationEntitys.put(row);
      });

      await expectLater(
        store.commitAccountHandover(source: source, target: target),
        throwsA(isA<FormatException>()),
      );
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        1,
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('正确 MAC 清单中的非空消息正文被清空时必须失败并保留 marker', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(store, 'env-clear-message', '消息正文不可降级为空');
      await store.stageAccountHandover(source: source, target: target);
      await ChatIsar.instance.writeTxn((isar) async {
        final row = await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
          ownerUserId,
          'env-clear-message',
        );
        row!
          ..plaintextCipher = null
          ..searchTokens = const <String>[];
        await isar.chatMessageEntitys.put(row);
      });

      await expectLater(
        store.commitAccountHandover(source: source, target: target),
        throwsA(isA<FormatException>()),
      );
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        1,
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('stage 前合法删除会话仍可提交，并只迁移其余现存历史', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(
        store,
        'env-delete-during-handover',
        '交接窗口应删除',
        conversationId: 'conv-delete-during-handover',
      );
      await saveText(
        store,
        'env-keep-during-handover',
        '交接窗口应保留',
        conversationId: 'conv-keep-during-handover',
        at: 2000,
      );
      final sourceToken = await store.captureBindingFenceToken(source);
      await store.deleteConversation(
        ownerUserId,
        'conv-delete-during-handover',
        bindingToken: sourceToken,
      );
      await store.stageAccountHandover(source: source, target: target);
      manager.activeBinding = target;
      await store.commitAccountHandover(source: source, target: target);

      expect(
        await store.readMessages(
          ownerUserId: ownerUserId,
          currentAccountId: newAccountId,
          conversationId: 'conv-delete-during-handover',
        ),
        isEmpty,
      );
      final kept = await store.readMessages(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
        conversationId: 'conv-keep-during-handover',
      );
      expect(ChatPayloadCodec.decode(kept.single.plaintext!).text, '交接窗口应保留');
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        0,
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('stage 时原本为空的摘要与正文可保持为空，也可在窗口内更新为认证密文', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final chatCrypto = ChatCrypto(CitizenChatStorageKeyProvider(manager));
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(crypto: chatCrypto);

      Future<void> saveEmpty(String messageId, String conversationId) {
        return saveText(
          store,
          messageId,
          '建立记录后立即清空',
          conversationId: conversationId,
        );
      }

      await saveEmpty('env-empty-stays', 'conv-empty-stays');
      await saveEmpty('env-empty-late', 'conv-empty-late');
      await ChatIsar.instance.writeTxn((isar) async {
        for (final conversationId in const <String>[
          'conv-empty-stays',
          'conv-empty-late',
        ]) {
          final row = await isar.chatConversationEntitys
              .getByOwnerUserIdConversationId(ownerUserId, conversationId);
          row!.lastMessageCipher = '';
          await isar.chatConversationEntitys.put(row);
        }
        for (final messageId in const <String>[
          'env-empty-stays',
          'env-empty-late',
        ]) {
          final row = await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
            ownerUserId,
            messageId,
          );
          row!
            ..plaintextCipher = null
            ..searchTokens = const <String>[];
          await isar.chatMessageEntitys.put(row);
        }
      });
      await store.stageAccountHandover(source: source, target: target);

      const latePlaintext = '空记录窗口内合法更新';
      final latePayload = ChatPayloadCodec.encode(
        ChatContent.text(latePlaintext),
      );
      final lateMessageCipher = await chatCrypto.encryptText(
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
        recordId: 'env-empty-late',
        plaintext: latePayload,
      );
      final lateTokens = await chatCrypto.buildSearchTokens(
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
        text: latePlaintext,
      );
      final lateSummaryCipher = await chatCrypto.encryptText(
        ownerUserId: ownerUserId,
        currentAccountId: accountId,
        recordId: 'conv-empty-late',
        plaintext: latePlaintext,
      );
      await ChatIsar.instance.writeTxn((isar) async {
        final message = await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
          ownerUserId,
          'env-empty-late',
        );
        message!
          ..plaintextCipher = lateMessageCipher
          ..searchTokens = const <String>['0000000000000000'];
        await isar.chatMessageEntitys.put(message);
        final conversation = await isar.chatConversationEntitys
            .getByOwnerUserIdConversationId(ownerUserId, 'conv-empty-late');
        conversation!.lastMessageCipher = lateSummaryCipher;
        await isar.chatConversationEntitys.put(conversation);
      });

      await expectLater(
        store.commitAccountHandover(source: source, target: target),
        throwsA(isA<FormatException>()),
      );
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        1,
        reason: 'late nonempty 正文的来源 token 未通过来源索引钥认证时必须保留清单',
      );
      await ChatIsar.instance.writeTxn((isar) async {
        final message = await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
          ownerUserId,
          'env-empty-late',
        );
        message!.searchTokens = lateTokens;
        await isar.chatMessageEntitys.put(message);
      });

      manager.activeBinding = target;
      await store.commitAccountHandover(source: source, target: target);
      final emptyMessages = await store.readMessages(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
        conversationId: 'conv-empty-stays',
      );
      expect(emptyMessages.single.plaintext, isNull);
      final lateMessages = await store.readMessages(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
        conversationId: 'conv-empty-late',
      );
      expect(
        ChatPayloadCodec.decode(lateMessages.single.plaintext!).text,
        latePlaintext,
      );
      final previews = await store.readConversationPreviews(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
      );
      expect(
        previews
            .singleWhere(
              (preview) => preview.conversationId == 'conv-empty-stays',
            )
            .lastMessage,
        '',
      );
      expect(
        previews
            .singleWhere(
              (preview) => preview.conversationId == 'conv-empty-late',
            )
            .lastMessage,
        latePlaintext,
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('换绑 stage 等待已开始加密但尚未写入的来源消息，再封闭普通写', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final crypto = _PausingSummaryChatCrypto(manager);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(crypto: crypto);
      await saveText(store, 'env-before-race', '交接前消息');

      crypto.pauseNextMessageBeforeWrite();
      final lateWrite = saveText(
        store,
        'env-racing-late',
        '加密已开始的窗口消息',
        at: 2000,
      );
      await crypto.waitUntilPaused();
      var stageFinished = false;
      final stage = store
          .stageAccountHandover(source: source, target: target)
          .whenComplete(() => stageFinished = true);
      await Future<void>.delayed(Duration.zero);
      expect(stageFinished, isFalse, reason: 'stage 必须等待此前已开始的 Chat 密文写入');

      crypto.resume();
      await lateWrite;
      await stage;
      manager.activeBinding = target;
      final commit = store.commitAccountHandover(
        source: source,
        target: target,
      );
      await commit;
      final messages = await store.readMessages(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
        conversationId: 'conv-1',
      );
      expect(
        messages.map(
          (message) => ChatPayloadCodec.decode(message.plaintext!).text,
        ),
        <String>['交接前消息', '加密已开始的窗口消息'],
      );
      final previews = await store.readConversationPreviews(
        ownerUserId: ownerUserId,
        currentAccountId: newAccountId,
      );
      expect(previews.single.lastMessage, '加密已开始的窗口消息');
    } finally {
      crypto.resume();
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('换绑清单严格拒绝缺字段、错误结构、旧字段、异常 ID 与指纹篡改，并保留清单', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(store, 'env-manifest-1', '严格清单消息一');
      await saveText(store, 'env-manifest-2', '严格清单消息二', at: 2000);
      await store.stageAccountHandover(source: source, target: target);
      final originalManifest = await ChatIsar.instance.read(
        (isar) async =>
            (await isar.chatAccountHandoverEntitys.where().findFirst())!
                .manifestJson,
      );

      Future<void> expectRejected(
        void Function(Map<String, dynamic>) corrupt,
      ) async {
        final candidate = jsonDecode(originalManifest) as Map<String, dynamic>;
        corrupt(candidate);
        await ChatIsar.instance.writeTxn((isar) async {
          final row = await isar.chatAccountHandoverEntitys.where().findFirst();
          row!.manifestJson = jsonEncode(candidate);
          await isar.chatAccountHandoverEntitys.putByHandoverKey(row);
        });
        await expectLater(
          store.commitAccountHandover(source: source, target: target),
          throwsA(isA<FormatException>()),
        );
        expect(
          await ChatIsar.instance.read(
            (isar) async => isar.chatAccountHandoverEntitys.where().count(),
          ),
          1,
          reason: '畸形清单失败后必须保留，不能伪装成交接完成',
        );
      }

      Map<String, dynamic> payloadOf(Map<String, dynamic> value) =>
          jsonDecode(value['payload_json'] as String) as Map<String, dynamic>;

      String manifestMac(String payloadJson) {
        final key = manager._key(target.accountId, LocalKeyPurpose.chatIndex);
        try {
          return crypto.Hmac(crypto.sha256, key)
              .convert(
                utf8.encode(
                  'tatachat_sdk.local/chat-handover-manifest|$payloadJson',
                ),
              )
              .toString();
        } finally {
          key.fillRange(0, key.length, 0);
        }
      }

      void replaceRawPayload(
        Map<String, dynamic> value,
        String payloadJson, {
        bool authenticate = true,
      }) {
        value['payload_json'] = payloadJson;
        if (authenticate) value['mac'] = manifestMac(payloadJson);
      }

      void replacePayload(
        Map<String, dynamic> value,
        Object payload, {
        bool authenticate = true,
      }) {
        replaceRawPayload(
          value,
          jsonEncode(payload),
          authenticate: authenticate,
        );
      }

      await expectRejected((value) => value.remove('mac'));
      await expectRejected((value) {
        replacePayload(value, <Object>['not-a-map']);
      });
      await expectRejected((value) {
        final payload = payloadOf(value);
        final messages = payload['messages'] as List<dynamic>;
        messages[0] = 'not-a-map';
        replacePayload(value, payload);
      });
      await expectRejected((value) {
        final payload = payloadOf(value);
        final messages = payload['messages'] as List<dynamic>;
        (messages[0] as Map<String, dynamic>).remove('message_id');
        replacePayload(value, payload);
      });
      await expectRejected((value) {
        final payload = payloadOf(value);
        final messages = payload['messages'] as List<dynamic>;
        (messages[0] as Map<String, dynamic>)['source_has_cipher'] = 'true';
        replacePayload(value, payload);
      });
      await expectRejected((value) {
        final payload = payloadOf(value);
        final messages = payload['messages'] as List<dynamic>;
        (messages[0] as Map<String, dynamic>)['tokens'] = <String>[
          '0000000000000000',
        ];
        replacePayload(value, payload);
      });
      await expectRejected((value) {
        final payload = payloadOf(value);
        final messages = payload['messages'] as List<dynamic>;
        final first = messages[0] as Map<String, dynamic>;
        final second = messages[1] as Map<String, dynamic>;
        second['id'] = first['id'];
        replacePayload(value, payload);
      });
      await expectRejected((value) {
        final payload = payloadOf(value);
        final messages = payload['messages'] as List<dynamic>;
        (messages[0] as Map<String, dynamic>)['id'] = 0;
        replacePayload(value, payload);
      });
      await expectRejected((value) {
        final payload = payloadOf(value);
        final messages = payload['messages'] as List<dynamic>;
        (messages[0] as Map<String, dynamic>)['source_fingerprint'] = '损坏';
        replacePayload(value, payload);
      });
      await expectRejected((value) {
        final payload = payloadOf(value);
        final messages = payload['messages'] as List<dynamic>;
        (messages[0] as Map<String, dynamic>)['source_fingerprint'] =
            'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
        replacePayload(value, payload, authenticate: false);
      });
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('stage 与 commit 获取目标子钥失败时都立即清零已获取的来源子钥', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final failingStageManager = _FailingTargetHandoverWalletManager(
        source,
        target.accountId,
      );
      final failingStageStore = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(failingStageManager)),
      );
      await failingStageStore.activateBindingFence(source);
      await expectLater(
        failingStageStore.stageAccountHandover(source: source, target: target),
        throwsA(isA<StateError>()),
      );
      expect(failingStageManager.sourceKeysDisposed, isTrue);
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        0,
      );

      final normalManager = _HandoverWalletManager(source);
      final normalStore = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(normalManager)),
      );
      await saveText(normalStore, 'env-key-dispose', '子钥失败清零');
      await normalStore.stageAccountHandover(source: source, target: target);

      final failingCommitManager = _FailingTargetHandoverWalletManager(
        source,
        target.accountId,
      );
      await expectLater(
        ChatStore(
          crypto: ChatCrypto(
            CitizenChatStorageKeyProvider(failingCommitManager),
          ),
        ).commitAccountHandover(source: source, target: target),
        throwsA(isA<StateError>()),
      );
      expect(failingCommitManager.sourceKeysDisposed, isTrue);
      expect(
        await ChatIsar.instance.read(
          (isar) async => isar.chatAccountHandoverEntitys.where().count(),
        ),
        1,
        reason: 'commit 获取目标子钥失败时必须保留认证清单以便重试',
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('无当前账户签名换绑：此前聊天密文保留但新绑定不可见，当前密文损坏仍上抛', () async {
    const genesisHash =
        '0x1111111111111111111111111111111111111111111111111111111111111111';
    const newAccountId =
        '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    const source = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 1,
      accountId: accountId,
    );
    const target = _TestBinding(
      genesisHash: genesisHash,
      cidNumber: ownerUserId,
      bindingRevision: 2,
      accountId: newAccountId,
    );
    final manager = _HandoverWalletManager(source);
    final previousFixedKeys = ChatCrypto.debugFixedKeys;
    ChatCrypto.debugFixedKeys = null;
    try {
      final store = ChatStore(
        crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
      );
      await saveText(store, 'env-inaccessible', '没有交接签名的历史内容');
      final before = await ChatIsar.instance.read(
        (isar) async => (await isar.chatMessageEntitys
            .getByOwnerUserIdMessageId(ownerUserId, 'env-inaccessible'))!,
      );

      manager.activeBinding = target;
      expect(
        await store.readMessages(
          ownerUserId: ownerUserId,
          currentAccountId: newAccountId,
          conversationId: 'conv-1',
        ),
        isEmpty,
      );
      final preserved = await ChatIsar.instance.read(
        (isar) async => (await isar.chatMessageEntitys
            .getByOwnerUserIdMessageId(ownerUserId, 'env-inaccessible'))!,
      );
      expect(preserved.plaintextCipher, before.plaintextCipher);
      expect(preserved.bindingRevision, source.bindingRevision);
      expect(preserved.accountId, source.accountId);

      await store.isolateInaccessibleBinding(previous: source, current: target);
      await saveText(
        store,
        'env-current',
        '当前绑定密文',
        currentAccountId: newAccountId,
      );
      await ChatIsar.instance.writeTxn((isar) async {
        final current = await isar.chatMessageEntitys.getByOwnerUserIdMessageId(
          ownerUserId,
          'env-current',
        );
        current!.plaintextCipher = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
        await isar.chatMessageEntitys.putByOwnerUserIdMessageId(current);
      });
      await expectLater(
        store.readMessages(
          ownerUserId: ownerUserId,
          currentAccountId: newAccountId,
          conversationId: 'conv-1',
        ),
        throwsA(isA<ChatLocalCipherException>()),
      );
    } finally {
      ChatCrypto.debugFixedKeys = previousFixedKeys;
    }
  });

  test('空文件域 stage 持久化完成 receipt，模糊重试不重写，commit 可精确重复', () async {
    final fixture = await createRuntimeHandoverFixture();

    await fixture.runtime.stageAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );

    expect(fixture.receipt.existsSync(), isTrue);
    final stagedPayload = receiptPayload(fixture.receipt);
    expect(stagedPayload['state'], 'staged');
    expect(stagedPayload['files'], isEmpty);
    expect(stagedPayload['mls_devices'], isEmpty);

    final fixedModified = DateTime.utc(2001, 1, 1);
    await fixture.receipt.setLastModified(fixedModified);
    await fixture.runtime.stageAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );
    expect(
      (await fixture.receipt.lastModified()).millisecondsSinceEpoch,
      fixedModified.millisecondsSinceEpoch,
      reason: 'staged 模糊重试只能认证快照，不能覆盖完成 receipt',
    );

    fixture.manager.activeBinding = handoverTarget;
    await fixture.runtime.commitAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );
    await fixture.runtime.commitAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );

    expect(fixture.sourceDirectory.existsSync(), isFalse);
    expect(fixture.targetDirectory.existsSync(), isTrue);
    expect(
      File(
        ChatRuntimeCore.debugFileHandoverReceiptPathForTest(
          bindingDirectory: fixture.targetDirectory,
          target: handoverTarget,
        ),
      ).existsSync(),
      isFalse,
    );
  });

  test('从未 stage 的空文件域禁止直接 commit', () async {
    final fixture = await createRuntimeHandoverFixture();
    fixture.manager.activeBinding = handoverTarget;

    await expectLater(
      fixture.runtime.commitAccountHandover(
        source: handoverSource,
        target: handoverTarget,
      ),
      throwsA(isA<StateError>()),
    );
    expect(fixture.sourceDirectory.existsSync(), isFalse);
    expect(fixture.targetDirectory.existsSync(), isFalse);
  });

  test('Store pending 存在但文件域 receipt 缺失时 commit fail-closed', () async {
    final fixture = await createRuntimeHandoverFixture();
    await fixture.runtime.stageAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );
    await fixture.receipt.delete();
    fixture.manager.activeBinding = handoverTarget;

    await expectLater(
      fixture.runtime.commitAccountHandover(
        source: handoverSource,
        target: handoverTarget,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await ChatIsar.instance.read(
        (isar) async => isar.chatAccountHandoverEntitys.where().count(),
      ),
      1,
      reason: '缺 receipt 时 Store pending 必须保留供明确恢复',
    );
  });

  test('文件域 receipt 结构损坏时 commit fail-closed', () async {
    final fixture = await createRuntimeHandoverFixture();
    await fixture.runtime.stageAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );
    await fixture.receipt.writeAsString('{"broken":true}', flush: true);
    fixture.manager.activeBinding = handoverTarget;

    await expectLater(
      fixture.runtime.commitAccountHandover(
        source: handoverSource,
        target: handoverTarget,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(fixture.sourceDirectory.existsSync(), isTrue);
    expect(fixture.targetDirectory.existsSync(), isFalse);
  });

  test('文件域 receipt MAC 被篡改时 commit fail-closed', () async {
    final fixture = await createRuntimeHandoverFixture();
    await fixture.runtime.stageAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );
    final message = receiptMessage(fixture.receipt);
    message['mac'] = List<String>.filled(64, '0').join();
    await fixture.receipt.writeAsString(jsonEncode(message), flush: true);
    fixture.manager.activeBinding = handoverTarget;

    await expectLater(
      fixture.runtime.commitAccountHandover(
        source: handoverSource,
        target: handoverTarget,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(fixture.sourceDirectory.existsSync(), isTrue);
    expect(fixture.targetDirectory.existsSync(), isFalse);
  });

  test('handover 严格清除 plain/tmp，清单与目标目录都不继承短命明文', () async {
    final fixture = await createRuntimeHandoverFixture();
    final stable = File('${fixture.sourceDirectory.path}/cipher-marker.bin');
    final plain = File(
      '${fixture.sourceDirectory.path}/attachments/.plain/visible.bin',
    );
    final partial = File(
      '${fixture.sourceDirectory.path}/attachments/.tmp/pending.part',
    );
    await stable.parent.create(recursive: true);
    await stable.writeAsBytes(const <int>[1, 2, 3]);
    await plain.parent.create(recursive: true);
    await plain.writeAsString('short-lived-plain');
    await partial.parent.create(recursive: true);
    await partial.writeAsString('partial-frame');

    await fixture.runtime.stageAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );

    expect(plain.existsSync(), isFalse);
    expect(partial.existsSync(), isFalse);
    final files = (receiptPayload(fixture.receipt)['files'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(files.map((item) => item['relative_path']), <String>[
      'cipher-marker.bin',
    ]);

    fixture.manager.activeBinding = handoverTarget;
    await fixture.runtime.commitAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );
    expect(
      File('${fixture.targetDirectory.path}/cipher-marker.bin').existsSync(),
      isTrue,
    );
    expect(
      Directory('${fixture.targetDirectory.path}/attachments/.plain')
          .existsSync(),
      isFalse,
    );
    expect(
      Directory('${fixture.targetDirectory.path}/attachments/.tmp')
          .existsSync(),
      isFalse,
    );
  });

  test('receipt 临时路径类型异常时保留 staged 正式 marker，清理后可重试 commit', () async {
    final fixture = await createRuntimeHandoverFixture();
    await fixture.runtime.stageAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );
    final stagedBytes = await fixture.receipt.readAsBytes();
    final invalidTemp = Directory('${fixture.receipt.path}.writing');
    await invalidTemp.create();
    fixture.manager.activeBinding = handoverTarget;

    await expectLater(
      fixture.runtime.commitAccountHandover(
        source: handoverSource,
        target: handoverTarget,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await fixture.receipt.readAsBytes(), stagedBytes);
    expect(receiptPayload(fixture.receipt)['state'], 'staged');

    await invalidTemp.delete();
    await fixture.runtime.commitAccountHandover(
      source: handoverSource,
      target: handoverTarget,
    );
    expect(fixture.targetDirectory.existsSync(), isTrue);
  });

  test(
    '文件已切到 target 但 Store commit 首败时保留 committing receipt，stage 拒绝降级并可重试',
    () async {
      late _FailOnceCommitChatStore failingStore;
      final fixture = await createRuntimeHandoverFixture(
        createStore: (manager) {
          failingStore = _FailOnceCommitChatStore(
            crypto: ChatCrypto(CitizenChatStorageKeyProvider(manager)),
          );
          return failingStore;
        },
      );
      await File('${fixture.sourceDirectory.path}/cipher-marker.bin')
          .create(recursive: true);
      await fixture.runtime.stageAccountHandover(
        source: handoverSource,
        target: handoverTarget,
      );
      fixture.manager.activeBinding = handoverTarget;

      await expectLater(
        fixture.runtime.commitAccountHandover(
          source: handoverSource,
          target: handoverTarget,
        ),
        throwsA(isA<StateError>()),
      );
      expect(failingStore.commitCalls, 1);
      expect(fixture.sourceDirectory.existsSync(), isFalse);
      expect(fixture.targetDirectory.existsSync(), isTrue);
      final targetReceipt = File(
        ChatRuntimeCore.debugFileHandoverReceiptPathForTest(
          bindingDirectory: fixture.targetDirectory,
          target: handoverTarget,
        ),
      );
      expect(receiptPayload(targetReceipt)['state'], 'committing');
      final committingBytes = await targetReceipt.readAsBytes();

      await expectLater(
        fixture.runtime.stageAccountHandover(
          source: handoverSource,
          target: handoverTarget,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await targetReceipt.readAsBytes(), committingBytes);
      expect(receiptPayload(targetReceipt)['state'], 'committing');

      await fixture.runtime.commitAccountHandover(
        source: handoverSource,
        target: handoverTarget,
      );
      expect(failingStore.commitCalls, 2);
      expect(targetReceipt.existsSync(), isFalse);
      await fixture.runtime.commitAccountHandover(
        source: handoverSource,
        target: handoverTarget,
      );
      expect(failingStore.commitCalls, 3);
    },
  );
}
