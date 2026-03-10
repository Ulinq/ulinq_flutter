import 'package:flutter_test/flutter_test.dart';
import 'package:ulinq_sdk/src/internal/event_queue.dart';
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

void main() {
  test('flush uses batch transport and parses per-event responses', () async {
    var batchCalls = 0;
    final queue = UlinqEventQueue(
      logger: const _TestLogger(),
      isDebugEnabled: () => false,
      flushInterval: const Duration(minutes: 10),
      sendBatch: (events) async {
        batchCalls += 1;
        expect(events.length, 2);
        return const <UlinqBatchItemResult>[
          UlinqBatchItemResult(
              success: true, response: <String, dynamic>{'ok': true}),
          UlinqBatchItemResult(
              success: true, response: <String, dynamic>{'idempotent': false}),
        ];
      },
    );

    final openFuture = queue.add<void>(
      name: 'app_open',
      payload: <String, dynamic>{'platform': 'ios'},
      send: () async {},
      parseBatchResponse: (_) {},
    );
    final conversionFuture = queue.add<bool>(
      name: 'purchase',
      payload: <String, dynamic>{'event_name': 'purchase'},
      send: () async => true,
      parseBatchResponse: (response) => response['idempotent'] == true,
    );

    await queue.flush(reason: 'test');
    await openFuture;
    expect(await conversionFuture, isFalse);
    expect(batchCalls, 1);
    await queue.dispose();
  });
}
