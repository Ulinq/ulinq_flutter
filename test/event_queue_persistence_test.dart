
import 'package:flutter_test/flutter_test.dart';
import 'package:ulinq_sdk/src/internal/event_queue.dart';
import 'package:ulinq_sdk/src/internal/event_queue_storage.dart';
import 'package:ulinq_sdk/src/ulinq_logger.dart';

class _TestLogger extends UlinqLogger {
  const _TestLogger();

  @override
  void debug(String message) {}

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}
}

class _MemoryQueueStorage implements UlinqEventQueueStorage {
  List<UlinqQueuedEventData> _events = <UlinqQueuedEventData>[];

  @override
  Future<List<UlinqQueuedEventData>> load() async {
    return List<UlinqQueuedEventData>.from(_events);
  }

  @override
  Future<void> save(List<UlinqQueuedEventData> events) async {
    _events = List<UlinqQueuedEventData>.from(events);
  }
}

void main() {
  test('persists queue and restores across queue instances', () async {
    final storage = _MemoryQueueStorage();
    final firstQueue = UlinqEventQueue(
      logger: const _TestLogger(),
      isDebugEnabled: () => false,
      storage: storage,
      flushInterval: const Duration(minutes: 10),
      persistDebounce: const Duration(milliseconds: 20),
    );

    final pending = firstQueue.add<void>(
      name: 'app_open',
      payload: <String, dynamic>{'platform': 'ios'},
      send: () async {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect((await storage.load()).length, 1);
    await firstQueue.dispose();
    await expectLater(pending, throwsA(isA<StateError>()));

    final restoredQueue = UlinqEventQueue(
      logger: const _TestLogger(),
      isDebugEnabled: () => false,
      storage: storage,
      flushInterval: const Duration(minutes: 10),
      persistDebounce: const Duration(milliseconds: 20),
    );

    var sent = 0;
    final restored = await restoredQueue.restorePersistedEvents(
      sender: (event) async {
        sent += 1;
      },
    );
    expect(restored, 1);

    await restoredQueue.flush(reason: 'test');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(sent, 1);
    expect((await storage.load()).isEmpty, isTrue);
    await restoredQueue.dispose();
  });
}
