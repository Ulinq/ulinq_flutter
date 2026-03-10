import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceIdStore {
  DeviceIdStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _deviceIdStorageKey = 'ulinq.sdk.device_id';

  final FlutterSecureStorage _storage;

  Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _deviceIdStorageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final random = Random.secure();
    final buffer = StringBuffer('ulinq_');
    for (int i = 0; i < 32; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    final created = buffer.toString();
    await _storage.write(key: _deviceIdStorageKey, value: created);
    return created;
  }
}
