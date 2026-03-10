import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../ulinq_logger.dart';
import 'event_queue_storage.dart';

class UlinqBatchItemResult {
  const UlinqBatchItemResult({
    required this.success,
    this.statusCode,
    this.response,
    this.error,
  });

  final bool success;
  final int? statusCode;
  final Map<String, dynamic>? response;
  final String? error;
}

typedef UlinqSendBatch = Future<List<UlinqBatchItemResult>> Function(
  List<UlinqQueuedEventData> events,
);
typedef UlinqRestoredEventSender = Future<dynamic> Function(
  UlinqQueuedEventData event,
);

class UlinqEventQueue {
  UlinqEventQueue({
    required UlinqLogger logger,
    required bool Function() isDebugEnabled,
    UlinqEventQueueStorage? storage,
    this.sendBatch,
    this.flushInterval = const Duration(seconds: 5),
    this.flushThreshold = 10,
    this.maxRetries = 3,
    this.baseBackoff = const Duration(milliseconds: 250),
    this.persistDebounce = const Duration(milliseconds: 300),
    this.batchSize = 10,
  })  : _logger = logger,
        _isDebugEnabled = isDebugEnabled,
        _storage = storage {
    _timer = Timer.periodic(flushInterval, (_) {
      unawaited(flush(reason: 'timer'));
    });
  }

  final UlinqLogger _logger;
  final bool Function() _isDebugEnabled;
  final UlinqEventQueueStorage? _storage;
  final UlinqSendBatch? sendBatch;
  final Duration flushInterval;
  final int flushThreshold;
  final int maxRetries;
  final Duration baseBackoff;
  final Duration persistDebounce;
  final int batchSize;

  final Queue<_QueuedEvent<dynamic>> _queue = Queue<_QueuedEvent<dynamic>>();
  Timer? _timer;
  Timer? _persistTimer;
  bool _flushing = false;

  int get pendingCount => _queue.length;

  Future<T> add<T>({
    required String name,
    required Map<String, dynamic> payload,
    required Future<T> Function() send,
    T Function(Map<String, dynamic> response)? parseBatchResponse,
    bool flushNow = false,
  }) {
    final completer = Completer<T>();
    _queue.add(
      _QueuedEvent<T>(
        name: name,
        payload: payload,
        send: send,
        parseBatchResponse: parseBatchResponse,
        completer: completer,
      ),
    );
    _debug('event queued name=$name size=${_queue.length}');
    _schedulePersist();

    if (flushNow || _queue.length >= flushThreshold) {
      unawaited(flush(reason: flushNow ? 'immediate' : 'threshold'));
    }

    return completer.future;
  }

  Future<int> restorePersistedEvents({
    required UlinqRestoredEventSender sender,
  }) async {
    final storage = _storage;
    if (storage == null) {
      return 0;
    }

    final restored = await storage.load();
    if (restored.isEmpty) {
      return 0;
    }

    for (final eventData in restored) {
      _queue.add(
        _QueuedEvent<dynamic>(
          name: eventData.name,
          payload: eventData.payload,
          createdAtUtc: eventData.createdAtUtc,
          retryCount: eventData.retryCount,
          send: () => sender(eventData),
          completer: Completer<dynamic>(),
        ),
      );
    }
    _debug('event queue restored count=${restored.length}');
    _schedulePersist();
    return restored.length;
  }

  Future<void> flush({String reason = 'manual'}) async {
    if (_flushing || _queue.isEmpty) {
      return;
    }

    _flushing = true;
    _debug('event queue flush start reason=$reason size=${_queue.length}');
    try {
      while (_queue.isNotEmpty) {
        if (sendBatch != null) {
          await _flushBatch();
        } else {
          final event = _queue.first;
          final completed = await _sendWithRetry(event);
          if (!completed) {
            break;
          }
          _queue.removeFirst();
        }
      }
    } finally {
      _flushing = false;
      _debug('event queue flush done reason=$reason size=${_queue.length}');
      _schedulePersist();
    }
  }

  Future<void> _flushBatch() async {
    final count = math.min(batchSize, _queue.length);
    if (count <= 0) {
      return;
    }

    final events = <_QueuedEvent<dynamic>>[];
    for (var i = 0; i < count; i++) {
      events.add(_queue.removeFirst());
    }
    final serialized = events
        .map(
          (event) => UlinqQueuedEventData(
            name: event.name,
            payload: event.payload,
            retryCount: event.retryCount,
            createdAtUtc: event.createdAtUtc,
          ),
        )
        .toList(growable: false);

    List<UlinqBatchItemResult>? results;
    Object? batchError;
    StackTrace? batchStack;
    try {
      results = await sendBatch!(serialized);
    } catch (e, st) {
      batchError = e;
      batchStack = st;
    }

    if (results == null || results.length != events.length) {
      _debug('batch send failed size=${events.length} error=$batchError');
      await _requeueWithRetry(events, batchError, batchStack);
      return;
    }

    final retryEvents = <_QueuedEvent<dynamic>>[];
    var retryAttempt = 0;
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      final result = results[i];
      if (result.success) {
        _completeBatchSuccess(event, result.response);
        continue;
      }

      event.retryCount += 1;
      retryAttempt = math.max(retryAttempt, event.retryCount);
      final errorText = result.error ?? 'batch item failed';
      _debug(
        'batch item failed name=${event.name} attempt=${event.retryCount} error=$errorText',
      );
      if (event.retryCount >= maxRetries) {
        if (!event.completer.isCompleted) {
          event.completer.completeError(StateError(errorText));
        }
        _logger.warn(
            'event dropped name=${event.name} attempts=${event.retryCount}');
        continue;
      }
      retryEvents.add(event);
    }

    _requeueAtFront(retryEvents);
    if (retryEvents.isNotEmpty) {
      _schedulePersist();
      final wait = _backoff(retryAttempt);
      _debug(
        'batch retry scheduled count=${retryEvents.length} wait_ms=${wait.inMilliseconds}',
      );
      await Future<void>.delayed(wait);
    }
  }

  Future<void> _requeueWithRetry(
    List<_QueuedEvent<dynamic>> events,
    Object? error,
    StackTrace? stackTrace,
  ) async {
    if (events.isEmpty) {
      return;
    }
    final retryEvents = <_QueuedEvent<dynamic>>[];
    var retryAttempt = 0;
    for (final event in events) {
      event.retryCount += 1;
      retryAttempt = math.max(retryAttempt, event.retryCount);
      if (event.retryCount >= maxRetries) {
        if (!event.completer.isCompleted) {
          event.completer.completeError(
            error ?? StateError('batch event send failed'),
            stackTrace,
          );
        }
        _logger.warn(
            'event dropped name=${event.name} attempts=${event.retryCount}');
        continue;
      }
      retryEvents.add(event);
    }

    _requeueAtFront(retryEvents);
    if (retryEvents.isNotEmpty) {
      _schedulePersist();
      final wait = _backoff(retryAttempt);
      _debug(
        'batch retry scheduled count=${retryEvents.length} wait_ms=${wait.inMilliseconds}',
      );
      await Future<void>.delayed(wait);
    }
  }

  void _completeBatchSuccess(
    _QueuedEvent<dynamic> event,
    Map<String, dynamic>? response,
  ) {
    if (event.completer.isCompleted) {
      return;
    }
    try {
      if (event.parseBatchResponse != null) {
        if (response == null) {
          throw StateError('missing batch response for event ${event.name}');
        }
        event.completer.complete(event.parseBatchResponse!(response));
      } else {
        event.completer.complete(response);
      }
      _debug(
          'batch item sent name=${event.name} attempt=${event.retryCount + 1}');
    } catch (e, st) {
      event.completer.completeError(e, st);
    }
  }

  void _requeueAtFront(List<_QueuedEvent<dynamic>> events) {
    for (var i = events.length - 1; i >= 0; i--) {
      _queue.addFirst(events[i]);
    }
  }

  Future<bool> _sendWithRetry(_QueuedEvent<dynamic> event) async {
    while (true) {
      try {
        event.retryCount += 1;
        final result = await event.send();
        if (!event.completer.isCompleted) {
          event.completer.complete(result);
        }
        _debug('event sent name=${event.name} attempt=${event.retryCount}');
        return true;
      } catch (e, st) {
        _debug(
          'event send failed name=${event.name} attempt=${event.retryCount} error=$e',
        );
        if (event.retryCount >= maxRetries) {
          if (!event.completer.isCompleted) {
            event.completer.completeError(e, st);
          }
          _logger.warn(
              'event dropped name=${event.name} attempts=${event.retryCount}');
          return true;
        }
        _schedulePersist();
        final wait = _backoff(event.retryCount);
        _debug(
          'event retry scheduled name=${event.name} wait_ms=${wait.inMilliseconds}',
        );
        await Future<void>.delayed(wait);
      }
    }
  }

  Duration _backoff(int attempt) {
    final multiplier = 1 << (attempt - 1);
    return Duration(milliseconds: baseBackoff.inMilliseconds * multiplier);
  }

  void _schedulePersist() {
    if (_storage == null) {
      return;
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, () {
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() async {
    final storage = _storage;
    if (storage == null) {
      return;
    }
    final snapshot = _queue
        .map(
          (event) => UlinqQueuedEventData(
            name: event.name,
            payload: event.payload,
            retryCount: event.retryCount,
            createdAtUtc: event.createdAtUtc,
          ),
        )
        .toList(growable: false);
    await storage.save(snapshot);
    _debug('event queue persisted size=${snapshot.length}');
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persistNow();
    while (_queue.isNotEmpty) {
      final event = _queue.removeFirst();
      if (!event.completer.isCompleted) {
        event.completer.completeError(
          StateError('UlinqEventQueue disposed before event flush'),
        );
      }
    }
  }

  void _debug(String message) {
    if (_isDebugEnabled()) {
      _logger.debug(message);
    }
  }
}

class _QueuedEvent<T> {
  _QueuedEvent({
    required this.name,
    required this.payload,
    required this.send,
    required this.completer,
    this.parseBatchResponse,
    DateTime? createdAtUtc,
    this.retryCount = 0,
  }) : createdAtUtc = createdAtUtc ?? DateTime.now().toUtc();

  final String name;
  final Map<String, dynamic> payload;
  final Future<T> Function() send;
  final T Function(Map<String, dynamic> response)? parseBatchResponse;
  final Completer<T> completer;
  final DateTime createdAtUtc;
  int retryCount;
}
