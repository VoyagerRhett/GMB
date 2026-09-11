import 'dart:async';

import 'package:citizen_sdk/src/api/citizen_sdk_error.dart';
import 'package:citizen_sdk/src/api/citizen_sdk_events.dart';
import 'package:citizen_sdk/src/models/citizen_chain_state.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_flutter_sessions.dart';
import 'package:citizen_sdk/src/platform/citizen_sdk_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('历史通知按 session 隔离，关闭后不接收迟到通知', () async {
    final platform = _SessionPlatform();
    addTearDown(platform.dispose);
    final session = await CitizenSdkFlutterSession.open(platform: platform);
    final events = <CitizenSdkEvent>[];
    final subscription = session.events.listen(events.add);
    platform.emit(<Object?>[1, 'foreign', 1, 'historyChanged', <Object?>[]]);
    platform.emit(<Object?>[1, 'session-a', 1, 'historyChanged', <Object?>[]]);
    await Future<void>.delayed(Duration.zero);
    expect(events.single, isA<CitizenSdkHistoryChanged>());
    await session.close();
    platform.emit(<Object?>[1, 'session-a', 2, 'historyChanged', <Object?>[]]);
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    await subscription.cancel();
  });
  test('Flutter open后按session浅路由事件，其他session的坏payload不会毒化本session', () async {
    final platform = _SessionPlatform();
    addTearDown(platform.dispose);
    final session = await CitizenSdkFlutterSession.open(platform: platform);
    final events = <CitizenSdkEvent>[];
    final subscription = session.events.listen(events.add);

    for (var index = 0; index < 100; index++) {
      platform.emit(<Object?>[
        1,
        'foreign-session',
        'malformed-sequence-is-ignored-after-routing',
        'unknown',
        <Object?>[
          <String, Object?>{'forbidden': true},
        ],
      ]);
    }
    platform.emit(<Object?>[
      1,
      'session-a',
      1,
      'lifecycleChanged',
      <Object?>['running'],
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(
      (events.single as CitizenSdkLifecycleChanged).lifecycle,
      CitizenSdkLifecycle.running,
    );
    await subscription.cancel();
    await session.close();
  });

  test('open value损坏时仍使用响应外壳sessionId关闭原生实例', () async {
    final platform = _SessionPlatform(invalidOpenValue: true);
    addTearDown(platform.dispose);

    await expectLater(
      CitizenSdkFlutterSession.open(platform: platform),
      throwsA(isA<CitizenSdkException>()),
    );

    expect(platform.requestSequences, <int>[1]);
    expect(platform.methods, contains('close'));
  });

  test('原生错误必须精确关联当前session和request sequence', () async {
    final platform = _SessionPlatform(mismatchedHeadError: true);
    addTearDown(platform.dispose);
    final session = await CitizenSdkFlutterSession.open(platform: platform);

    await expectLater(
      session.invoke('getFinalizedHead'),
      throwsA(
        isA<CitizenSdkException>()
            .having((error) => error.code, 'code', CitizenSdkErrorCode.decode)
            .having((error) => error.sessionId, 'sessionId', 'session-a')
            .having((error) => error.requestSequence, 'sequence', 1),
      ),
    );
    await session.close();
  });

  test('暂停的公共事件监听不能阻塞已经disposed的close', () async {
    final platform = _SessionPlatform();
    addTearDown(platform.dispose);
    final session = await CitizenSdkFlutterSession.open(platform: platform);
    final subscription = session.events.listen((_) {});
    subscription.pause();

    await session.close().timeout(const Duration(seconds: 1));

    await subscription.cancel();
  });

  test('第二个session的open窗口事件由进程路由器缓存且不产生序号缺口', () async {
    final platform = _MultiSessionPlatform();
    addTearDown(platform.dispose);
    final first = await CitizenSdkFlutterSession.open(platform: platform);
    final secondFuture = CitizenSdkFlutterSession.open(platform: platform);
    final second = await secondFuture;
    final secondEvents = <CitizenSdkEvent>[];
    final subscription = second.events.listen(secondEvents.add);

    // 第二次 native open 在返回 envelope 前发出了 session-b 的 sequence 1。
    // register 时必须从按 session 隔离的进程缓冲中精确交付。
    expect(second.lifecycle, CitizenSdkLifecycle.running);
    platform.emit(<Object?>[
      1,
      'session-b',
      2,
      'lifecycleChanged',
      <Object?>['stopped'],
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(secondEvents, hasLength(1));
    expect(second.lifecycle, CitizenSdkLifecycle.stopped);

    await subscription.cancel();
    await second.close();
    await first.close();
  });

  test('进程路由器显式拒绝第65个并发open', () async {
    final platform = _ConcurrentOpenPlatform();
    addTearDown(platform.dispose);

    final opens = <Future<CitizenSdkFlutterSession>>[
      for (var index = 0; index < 64; index++)
        CitizenSdkFlutterSession.open(platform: platform),
    ];
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      CitizenSdkFlutterSession.open(platform: platform),
      throwsA(
        isA<CitizenSdkException>().having(
          (error) => error.code,
          'code',
          CitizenSdkErrorCode.queueFull,
        ),
      ),
    );

    platform.releaseOpens();
    final sessions = await Future.wait(opens);
    await Future.wait(sessions.map((session) => session.close()));
  });

  test('open窗口未知session饱和时fail-closed而不静默驱逐基线', () async {
    final platform = _PendingOverflowPlatform();
    addTearDown(platform.dispose);

    await expectLater(
      CitizenSdkFlutterSession.open(platform: platform),
      throwsA(
        isA<CitizenSdkException>().having(
          (error) => error.code,
          'code',
          CitizenSdkErrorCode.queueFull,
        ),
      ),
    );
    expect(platform.closedSessions, <String>['session-real']);
  });

  test('普通请求可并发、sequence单调且close后拒绝新请求', () async {
    final gate = Completer<void>();
    final platform = _SessionPlatform(firstHeadGate: gate);
    addTearDown(platform.dispose);
    final session = await CitizenSdkFlutterSession.open(platform: platform);

    final first = session.invoke('getFinalizedHead');
    await Future<void>.delayed(Duration.zero);
    final second = session.invoke('getFinalizedHead');
    await Future<void>.delayed(Duration.zero);
    expect(platform.requestSequences, <int>[1, 2]);
    gate.complete();
    await Future.wait(<Future<List<Object?>>>[first, second]);
    await session.close();

    expect(platform.requestSequences, <int>[1, 2, 3]);
    await expectLater(
      session.invoke('getFinalizedHead'),
      throwsA(
        isA<CitizenSdkException>().having(
          (error) => error.code,
          'code',
          CitizenSdkErrorCode.invalidState,
        ),
      ),
    );
  });

  test('Dart侧拒绝的非法请求不消耗原生request sequence', () async {
    final platform = _SessionPlatform();
    addTearDown(platform.dispose);
    final session = await CitizenSdkFlutterSession.open(platform: platform);

    await expectLater(
      session.invoke('getTransactionHistory', fields: <Object?>[null, 0]),
      throwsA(isA<CitizenSdkException>()),
    );
    await session.invoke('getFinalizedHead');
    await session.close();

    expect(platform.requestSequences, <int>[1, 2]);
  });

  test('start/stop等待既有请求并独占后续接纳', () async {
    final gate = Completer<void>();
    final platform = _SessionPlatform(firstHeadGate: gate);
    addTearDown(platform.dispose);
    final session = await CitizenSdkFlutterSession.open(platform: platform);

    final read = session.invoke('getFinalizedHead');
    await Future<void>.delayed(Duration.zero);
    final start = session.invoke('start');
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      session.invoke('getFinalizedHead'),
      throwsA(
        isA<CitizenSdkException>().having(
          (error) => error.code,
          'code',
          CitizenSdkErrorCode.busy,
        ),
      ),
    );
    expect(platform.requestSequences, <int>[1]);

    gate.complete();
    await read;
    await start;
    expect(platform.requestSequences, <int>[1, 2]);
    await session.close();
  });

  test('事件缺号或跨协议失败关闭后续请求', () async {
    final platform = _SessionPlatform();
    addTearDown(platform.dispose);
    final session = await CitizenSdkFlutterSession.open(platform: platform);
    final errors = <Object>[];
    final subscription = session.events.listen(
      (_) {},
      onError: (Object error) => errors.add(error),
    );

    platform.emit(<Object?>[
      1,
      'session-a',
      2,
      'lifecycleChanged',
      <Object?>['running'],
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(errors.single, isA<CitizenSdkException>());
    await expectLater(
      session.invoke('getFinalizedHead'),
      throwsA(isA<CitizenSdkException>()),
    );
    await subscription.cancel();
  });
}

final class _SessionPlatform implements CitizenSdkPlatform {
  _SessionPlatform({
    this.firstHeadGate,
    this.invalidOpenValue = false,
    this.mismatchedHeadError = false,
  });

  final Completer<void>? firstHeadGate;
  final bool invalidOpenValue;
  final bool mismatchedHeadError;
  final StreamController<Object?> _events =
      StreamController<Object?>.broadcast();
  final List<int> requestSequences = <int>[];
  final List<String> methods = <String>[];
  int _headCalls = 0;

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<Object?> invoke(String method, List<Object?> arguments) async {
    if (method == 'open') {
      return <Object?>[
        1,
        'session-a',
        0,
        invalidOpenValue
            ? <Object?>['created', 'not-an-event-sequence']
            : <Object?>['created', 1],
      ];
    }
    final sequence = arguments[2]! as int;
    requestSequences.add(sequence);
    methods.add(method);
    if (method == 'getFinalizedHead') {
      _headCalls += 1;
      if (_headCalls == 1 && firstHeadGate != null) {
        await firstHeadGate!.future;
      }
      if (mismatchedHeadError) {
        throw CitizenSdkException(
          code: CitizenSdkErrorCode.network,
          message: 'wrong correlation',
          sessionId: 'foreign-session',
          requestSequence: sequence,
        );
      }
    }
    return switch (method) {
      'getFinalizedHead' => <Object?>[
        1,
        'session-a',
        sequence,
        <Object?>[
          <Object?>[_account(1), '1', 'finalized'],
        ],
      ],
      'start' => <Object?>[
        1,
        'session-a',
        sequence,
        <Object?>['running'],
      ],
      'close' => <Object?>[
        1,
        'session-a',
        sequence,
        <Object?>['disposed'],
      ],
      _ => throw StateError('未预期 method：$method'),
    };
  }

  void emit(Object? event) => _events.add(event);

  Future<void> dispose() => _events.close();
}

final class _MultiSessionPlatform implements CitizenSdkPlatform {
  final StreamController<Object?> _events =
      StreamController<Object?>.broadcast();
  var _openCount = 0;

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<Object?> invoke(String method, List<Object?> arguments) async {
    if (method == 'open') {
      _openCount += 1;
      final sessionId = _openCount == 1 ? 'session-a' : 'session-b';
      if (_openCount == 2) {
        emit(<Object?>[
          1,
          sessionId,
          1,
          'lifecycleChanged',
          <Object?>['running'],
        ]);
        await Future<void>.delayed(Duration.zero);
      }
      return <Object?>[
        1,
        sessionId,
        0,
        <Object?>['created', 1],
      ];
    }
    final sessionId = arguments[1]! as String;
    final sequence = arguments[2]! as int;
    if (method == 'close') {
      return <Object?>[
        1,
        sessionId,
        sequence,
        <Object?>['disposed'],
      ];
    }
    throw StateError('未预期 method：$method');
  }

  void emit(Object? event) => _events.add(event);

  Future<void> dispose() => _events.close();
}

final class _ConcurrentOpenPlatform implements CitizenSdkPlatform {
  final StreamController<Object?> _events =
      StreamController<Object?>.broadcast();
  final Completer<void> _openGate = Completer<void>();
  var _nextSession = 0;

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<Object?> invoke(String method, List<Object?> arguments) async {
    if (method == 'open') {
      final sessionId = 'session-${++_nextSession}';
      await _openGate.future;
      return <Object?>[
        1,
        sessionId,
        0,
        <Object?>['created', 1],
      ];
    }
    if (method == 'close') {
      return <Object?>[
        1,
        arguments[1],
        arguments[2],
        <Object?>['disposed'],
      ];
    }
    throw StateError('未预期 method：$method');
  }

  void releaseOpens() => _openGate.complete();

  Future<void> dispose() => _events.close();
}

final class _PendingOverflowPlatform implements CitizenSdkPlatform {
  final StreamController<Object?> _events = StreamController<Object?>.broadcast(
    sync: true,
  );
  final List<String> closedSessions = <String>[];

  @override
  Stream<Object?> get events => _events.stream;

  @override
  Future<Object?> invoke(String method, List<Object?> arguments) async {
    if (method == 'open') {
      for (var index = 0; index < 65; index++) {
        _events.add(<Object?>[
          1,
          'foreign-$index',
          1,
          'lifecycleChanged',
          <Object?>['running'],
        ]);
      }
      return <Object?>[
        1,
        'session-real',
        0,
        <Object?>['created', 1],
      ];
    }
    if (method == 'close') {
      closedSessions.add(arguments[1]! as String);
      return <Object?>[
        1,
        arguments[1],
        arguments[2],
        <Object?>['disposed'],
      ];
    }
    throw StateError('未预期 method：$method');
  }

  Future<void> dispose() => _events.close();
}

String _account(int byte) =>
    '0x${List<String>.filled(32, byte.toRadixString(16).padLeft(2, '0')).join()}';
