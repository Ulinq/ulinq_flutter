import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SkAdNetworkTracker {
  const SkAdNetworkTracker({MethodChannel? methodChannel})
      : _channel =
            methodChannel ?? const MethodChannel('ulinq/install_referrer');

  final MethodChannel _channel;

  Future<void> updateConversionValue(int value) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    if (value < 0 || value > 63) {
      return;
    }

    try {
      await _channel
          .invokeMethod<bool>('updateSkAdConversionValue', <String, dynamic>{
        'value': value,
      });
    } catch (_) {
      // Best effort only.
    }
  }
}
