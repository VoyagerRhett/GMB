import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

import '../api/citizen_sdk_error.dart';
import '../api/citizen_sdk_events.dart';
import '../models/citizen_capability.dart';
import '../models/citizen_chain_state.dart';
import 'citizen_sdk_flutter_codec.dart';
import 'citizen_sdk_platform.dart';

/// 一个隔离 Flutter session 的并发接纳、序列、事件和关闭状态机。
final class CitizenSdkFlutterSession {
  CitizenSdkFlutterSession._({
    required CitizenSdkPlatform platform,
    required CitizenSdkFlutterCodec codec,
  }) : _platform = platform,
       _codec = codec;

  static Future<CitizenSdkFlutterSession> open({
    CitizenSdkPlatform? platform,
    CitizenSdkFlutterCodec codec = const CitizenSdkFlutterCodec(),
    int modules = CitizenSdkModules.full,
  }) async {
    final selectedPlatform =
        platform ??
        CitizenSdkPlatform.instance ??
        (throw const CitizenSdkException(
          code: CitizenSdkErrorCode.unsupported,
          message: '当前平台尚未安装 CitizenSDK 官方 binding',
        ));
    // 进程路由器必须在 native open 之前持续监听唯一 EventChannel。第二个
    // session 打开时原生 sink 已经激活，逐 session 临时 listen 会丢失窗口事件。
    final eventRouter = _CitizenSdkProcessEventRouter.acquireForOpen(
      selectedPlatform,
    );
    final session = CitizenSdkFlutterSession._(
      platform: selectedPlatform,
      codec: codec,
    );
    try {
      final raw = await session._platform.invoke(
        'open',
        codec.encodeOpen(modules),
      );
      // 先记录外壳中的原生 sessionId，再验证 open value。若 value 损坏，
      // catch 路径仍有足够身份关闭已经创建的原生实例。
      final response = codec.decodeResponseEnvelope(
        raw: raw,
        expectedRequestSequence: 0,
        valueName: 'open value',
      );
      session._sessionId = response.sessionId;
      codec.validateResponseValue('open', response.value);
      session._lifecycle = codec.decodeLifecycle(response.value[0]);
      session._nextEventSequence = response.value[1]! as int;
      session._eventRegistration = eventRouter.register(
        response.sessionId,
        session._receiveRawEvent,
        session._receiveEventError,
      );
      final pendingError = session._eventProtocolError;
      if (pendingError != null) throw pendingError;
      return session;
    } on Object {
      session._detachEventRouter();
      await session._closeAfterOpenFailure();
      await session._closeEventControllerBestEffort();
      rethrow;
    } finally {
      eventRouter.finishOpen();
    }
  }

  final CitizenSdkPlatform _platform;
  final CitizenSdkFlutterCodec _codec;
  final StreamController<CitizenSdkEvent> _events =
      StreamController<CitizenSdkEvent>.broadcast(sync: true);

  _CitizenSdkEventRegistration? _eventRegistration;
  String? _sessionId;
  int _nextRequestSequence = 1;
  int _nextEventSequence = 1;
  int _activeOperations = 0;
  Completer<void>? _idleCompleter;
  CitizenSdkLifecycle _lifecycle = CitizenSdkLifecycle.created;
  CitizenSdkException? _eventProtocolError;
  Future<void>? _closeFuture;
  bool _exclusiveLifecycle = false;
  bool _closing = false;
  bool _closed = false;

  Stream<CitizenSdkEvent> get events => _events.stream;
  CitizenSdkLifecycle get lifecycle => _lifecycle;

  Future<List<Object?>> invoke(
    String method, {
    List<Object?> fields = const <Object?>[],
  }) {
    if (method == 'open' || method == 'close') {
      return Future<List<Object?>>.error(
        const CitizenSdkException(
          code: CitizenSdkErrorCode.invalidArgument,
          message: 'open/close 只能通过 session 生命周期入口调用',
        ),
      );
    }
    if (_closing || _closed) {
      return Future<List<Object?>>.error(
        CitizenSdkException(
          code: CitizenSdkErrorCode.invalidState,
          message: 'CitizenSDK session 正在关闭或已经关闭',
        ),
      );
    }
    if (method == 'start' || method == 'stop') {
      return _invokeExclusiveLifecycle(method, fields);
    }
    if (_exclusiveLifecycle) {
      return Future<List<Object?>>.error(
        const CitizenSdkException(
          code: CitizenSdkErrorCode.busy,
          message: 'CitizenSDK 生命周期转换正在独占 session',
        ),
      );
    }
    return _invokeTracked(method, fields);
  }

  Future<void> close() {
    if (_closed) return Future<void>.value();
    final existing = _closeFuture;
    if (existing != null) return existing;
    final operation = _performClose();
    _closeFuture = operation;
    return operation;
  }

  Future<void> _performClose() async {
    _closing = true;
    try {
      final value = await _invokeTransport('close', const <Object?>[]);
      await _waitUntilIdle();
      final lifecycle = _codec.decodeLifecycle(value[0]);
      if (lifecycle != CitizenSdkLifecycle.disposed) {
        throw CitizenSdkException(
          code: CitizenSdkErrorCode.decode,
          message: 'close 未返回 disposed 生命周期',
        );
      }
      _lifecycle = lifecycle;
      _closed = true;
      _detachEventRouter();
      // 原生 disposed 是不可逆事实。公共 stream 可能有暂停的订阅，不能让它
      // 反向阻塞 close；清理异步且吞掉 transport/controller 的迟到错误。
      unawaited(_closeEventControllerBestEffort());
    } on Object {
      if (!_closed) {
        _closing = false;
        _closeFuture = null;
      }
      rethrow;
    }
  }

  Future<void> _closeAfterOpenFailure() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      final arguments = _codec.encodeRequest(
        method: 'close',
        sessionId: sessionId,
        requestSequence: _nextRequestSequence,
      );
      final raw = await _platform.invoke('close', arguments);
      _codec.decodeResponse(
        method: 'close',
        raw: raw,
        expectedSessionId: sessionId,
        expectedRequestSequence: _nextRequestSequence,
      );
    } on Object {
      // 保留最先导致 open 失败的协议错误；原生 engine detach 仍负责最终兜底收口。
    }
  }

  Future<List<Object?>> _invokeExclusiveLifecycle(
    String method,
    List<Object?> fields,
  ) async {
    if (_exclusiveLifecycle) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.busy,
        message: 'CitizenSDK 生命周期转换已经在执行',
      );
    }
    _exclusiveLifecycle = true;
    try {
      await _waitUntilIdle();
      if (_closing || _closed) {
        throw const CitizenSdkException(
          code: CitizenSdkErrorCode.invalidState,
          message: 'CitizenSDK session 正在关闭或已经关闭',
        );
      }
      return await _invokeTracked(method, fields);
    } finally {
      _exclusiveLifecycle = false;
    }
  }

  Future<List<Object?>> _invokeTracked(
    String method,
    List<Object?> fields,
  ) async {
    final protocolError = _eventProtocolError;
    if (protocolError != null) throw protocolError;
    _activeOperations += 1;
    try {
      return await _invokeTransport(method, fields);
    } finally {
      _activeOperations -= 1;
      if (_activeOperations == 0) {
        _idleCompleter?.complete();
        _idleCompleter = null;
      }
    }
  }

  Future<List<Object?>> _invokeTransport(
    String method,
    List<Object?> fields,
  ) async {
    final sessionId = _sessionId;
    if (sessionId == null || _closed) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidState,
        message: 'CitizenSDK session 不可用',
      );
    }
    final requestSequence = _nextRequestSequence;
    final arguments = _codec.encodeRequest(
      method: method,
      sessionId: sessionId,
      requestSequence: requestSequence,
      fields: fields,
    );
    _nextRequestSequence += 1;
    Object? raw;
    try {
      raw = await _platform.invoke(method, arguments);
    } on CitizenSdkException catch (error) {
      if (error.sessionId != sessionId ||
          error.requestSequence != requestSequence) {
        throw CitizenSdkException(
          code: CitizenSdkErrorCode.decode,
          message: '原生错误未精确关联当前 session/request',
          sessionId: sessionId,
          requestSequence: requestSequence,
        );
      }
      rethrow;
    }
    final response = _codec.decodeResponse(
      method: method,
      raw: raw,
      expectedSessionId: sessionId,
      expectedRequestSequence: requestSequence,
    );
    if (!_closing && (method == 'start' || method == 'stop')) {
      _lifecycle = _codec.decodeLifecycle(response.value[0]);
    }
    return response.value;
  }

  Future<void> _waitUntilIdle() async {
    if (_activeOperations == 0) return;
    final completer = _idleCompleter ??= Completer<void>();
    await completer.future;
  }

  void _receiveRawEvent(Object? raw) {
    try {
      final sessionId = _sessionId;
      if (sessionId == null || _closed) return;
      final event = _codec.decodeEventForSession(raw, sessionId);
      if (event == null) return;
      _acceptDecodedEvent(event);
    } on CitizenSdkException catch (error, stackTrace) {
      _failEventProtocol(error, stackTrace);
    } on Object catch (error, stackTrace) {
      _failEventProtocol(
        CitizenSdkException(
          code: CitizenSdkErrorCode.decode,
          message: '事件解码失败：$error',
        ),
        stackTrace,
      );
    }
  }

  void _acceptDecodedEvent(DecodedCitizenSdkEvent decoded) {
    if (decoded.sessionId != _sessionId || _closed) return;
    if (decoded.eventSequence != _nextEventSequence) {
      throw CitizenSdkException(
        code: CitizenSdkErrorCode.decode,
        message: '事件序号不连续：期望 $_nextEventSequence，收到 ${decoded.eventSequence}',
        sessionId: _sessionId,
      );
    }
    _nextEventSequence += 1;
    final event = decoded.event;
    if (event is CitizenSdkLifecycleChanged) {
      _lifecycle = event.lifecycle;
    }
    _events.add(event);
  }

  void _receiveEventError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    CitizenSdkException normalized;
    if (error is CitizenSdkException) {
      normalized = error;
    } else if (error is PlatformException) {
      try {
        normalized = _codec.decodePlatformException(error);
      } on CitizenSdkException catch (decodeError) {
        normalized = decodeError;
      }
    } else {
      normalized = CitizenSdkException(
        code: CitizenSdkErrorCode.internal,
        message: 'CitizenSDK EventChannel 失败：$error',
        sessionId: _sessionId,
      );
    }
    _failEventProtocol(normalized, stackTrace);
  }

  void _failEventProtocol(CitizenSdkException error, StackTrace stackTrace) {
    if (_closed) return;
    _eventProtocolError ??= error;
    if (!_events.isClosed) _events.addError(error, stackTrace);
  }

  void _detachEventRouter() {
    _eventRegistration?.close();
    _eventRegistration = null;
  }

  Future<void> _closeEventControllerBestEffort() async {
    if (_events.isClosed) return;
    try {
      await _events.close();
    } on Object {
      // public listener 的清理失败不覆盖原始 open/close 结果。
    }
  }
}

typedef _CitizenSdkRawEventHandler = void Function(Object? raw);
typedef _CitizenSdkRawErrorHandler =
    void Function(Object error, StackTrace stackTrace);

final class _CitizenSdkEventHandler {
  const _CitizenSdkEventHandler(this.onData, this.onError);

  final _CitizenSdkRawEventHandler onData;
  final _CitizenSdkRawErrorHandler onError;
}

final class _CitizenSdkPendingEvents {
  final List<Object?> values = <Object?>[];
  CitizenSdkException? overflow;
}

/// 每个官方 platform 实例唯一的进程级 EventChannel 路由器。
///
/// 路由器在 native `open` 前订阅，按顶层 sessionId 缓冲尚未完成绑定的窗口
/// 事件。其他 session 的坏 payload 永远不会在这里深解码；未知 session 的缓冲
/// 按 session 隔离并有界。缓冲饱和时不会静默驱逐已有 session，而是让无法证明
/// 窗口完整的 open 以 queueFull 失败，避免丢失 sequence 1 基线事件。
final class _CitizenSdkProcessEventRouter {
  _CitizenSdkProcessEventRouter._(this._platform) : _opening = 1 {
    _subscription = _platform.events.listen(
      _route,
      onError: _routeError,
      onDone: () => _routeError(
        const CitizenSdkException(
          code: CitizenSdkErrorCode.unavailable,
          message: 'CitizenSDK EventChannel 已关闭',
        ),
        StackTrace.current,
      ),
    );
  }

  static final Expando<_CitizenSdkProcessEventRouter> _routers =
      Expando<_CitizenSdkProcessEventRouter>('CitizenSDK event routers');

  static _CitizenSdkProcessEventRouter acquireForOpen(
    CitizenSdkPlatform platform,
  ) {
    final existing = _routers[platform];
    if (existing != null) {
      if (existing._opening >= _maximumConcurrentOpens) {
        throw const CitizenSdkException(
          code: CitizenSdkErrorCode.queueFull,
          message: 'CitizenSDK 并发 open 超过上限',
        );
      }
      existing._opening += 1;
      return existing;
    }
    final created = _CitizenSdkProcessEventRouter._(platform);
    _routers[platform] = created;
    return created;
  }

  static const int _maximumConcurrentOpens = 64;
  static const int _maximumPendingSessions = _maximumConcurrentOpens;
  static const int _maximumPendingEventsPerSession = 64;

  final CitizenSdkPlatform _platform;
  final CitizenSdkFlutterCodec _routingCodec = const CitizenSdkFlutterCodec();
  final Map<String, _CitizenSdkEventHandler> _handlers =
      <String, _CitizenSdkEventHandler>{};
  final LinkedHashMap<String, _CitizenSdkPendingEvents> _pending =
      LinkedHashMap<String, _CitizenSdkPendingEvents>();
  late final StreamSubscription<Object?> _subscription;

  int _opening;
  Object? _channelError;
  StackTrace? _channelErrorStack;
  bool _pendingWindowOverflow = false;

  _CitizenSdkEventRegistration register(
    String sessionId,
    _CitizenSdkRawEventHandler onData,
    _CitizenSdkRawErrorHandler onError,
  ) {
    if (_subscription.isPaused) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.invalidState,
        message: 'CitizenSDK 进程事件路由器被意外暂停',
      );
    }
    if (_handlers.containsKey(sessionId)) {
      throw const CitizenSdkException(
        code: CitizenSdkErrorCode.conflict,
        message: 'CitizenSDK session 已注册事件路由',
      );
    }
    final handler = _CitizenSdkEventHandler(onData, onError);
    _handlers[sessionId] = handler;
    final registration = _CitizenSdkEventRegistration._(
      this,
      sessionId,
      handler,
    );

    final channelError = _channelError;
    if (channelError != null) {
      onError(channelError, _channelErrorStack ?? StackTrace.current);
      return registration;
    }
    final pending = _pending.remove(sessionId);
    if (pending != null) {
      for (final raw in pending.values) {
        onData(raw);
      }
      final overflow = pending.overflow;
      if (overflow != null) onError(overflow, StackTrace.current);
    } else if (_pendingWindowOverflow) {
      // 该 session 在饱和窗口中没有完整缓冲证据：它可能没有事件，
      // 也可能是基线事件被拒收。必须 fail-closed，不能静默继续。
      onError(
        CitizenSdkException(
          code: CitizenSdkErrorCode.queueFull,
          message: 'session $sessionId 的 open 窗口无法证明完整',
          sessionId: sessionId,
        ),
        StackTrace.current,
      );
    }
    return registration;
  }

  void finishOpen() {
    if (_opening <= 0) return;
    _opening -= 1;
    if (_opening == 0) {
      _pending.removeWhere((sessionId, _) => !_handlers.containsKey(sessionId));
      _pendingWindowOverflow = false;
    }
  }

  void _unregister(String sessionId, _CitizenSdkEventHandler expected) {
    if (identical(_handlers[sessionId], expected)) {
      _handlers.remove(sessionId);
    }
    _pending.remove(sessionId);
  }

  void _route(Object? raw) {
    String sessionId;
    try {
      sessionId = _routingCodec.eventSessionIdForRouting(raw);
    } on Object catch (error, stackTrace) {
      _routeError(error, stackTrace);
      return;
    }
    final handler = _handlers[sessionId];
    if (handler != null) {
      handler.onData(raw);
      return;
    }
    if (_opening == 0) return;

    var pending = _pending[sessionId];
    if (pending == null) {
      if (_pending.length >= _maximumPendingSessions) {
        _pendingWindowOverflow = true;
        return;
      }
      pending = _CitizenSdkPendingEvents();
      _pending[sessionId] = pending;
    }
    if (pending.values.length < _maximumPendingEventsPerSession) {
      pending.values.add(raw);
    } else {
      pending.overflow ??= CitizenSdkException(
        code: CitizenSdkErrorCode.queueFull,
        message: 'session $sessionId 的 open 窗口事件超过上限',
        sessionId: sessionId,
      );
    }
  }

  void _routeError(Object error, StackTrace stackTrace) {
    // 保留 PlatformException 的固定 tuple，让每个 session 使用自己的 v1 codec
    // 规范化；无法路由的数据已在 _route 中转换成 CitizenSdkException。
    _channelError ??= error;
    _channelErrorStack ??= stackTrace;
    for (final handler in List<_CitizenSdkEventHandler>.of(_handlers.values)) {
      handler.onError(error, stackTrace);
    }
  }
}

final class _CitizenSdkEventRegistration {
  _CitizenSdkEventRegistration._(this._router, this._sessionId, this._handler);

  final _CitizenSdkProcessEventRouter _router;
  final String _sessionId;
  final _CitizenSdkEventHandler _handler;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _router._unregister(_sessionId, _handler);
  }
}
