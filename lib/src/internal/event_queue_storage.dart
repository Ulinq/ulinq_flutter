import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UlinqQueuedEventData {
  const UlinqQueuedEventData({
    required this.name,
    required this.payload,
    required this.retryCount,
    required this.createdAtUtc,
  });

  final String name;
  final Map<String, dynamic> payload;
  final int retryCount;
  final DateTime createdAtUtc;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'payload': payload,
      'retryCount': retryCount,
      'createdAt': createdAtUtc.toIso8601String(),
    };
  }

  factory UlinqQueuedEventData.fromJson(Map<String, dynamic> json) {
    final payload = Map<String, dynamic>.from(
        json['payload'] as Map? ?? const <String, dynamic>{});
    final retryCount =
        (json['retryCount'] is num) ? (json['retryCount'] as num).toInt() : 0;
    final createdAtRaw = json['createdAt'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)?.toUtc()
        : null;

    return UlinqQueuedEventData(
      name: (json['name'] as String?)?.trim() ?? '',
      payload: payload,
      retryCount: retryCount < 0 ? 0 : retryCount,
      createdAtUtc: createdAt ?? DateTime.now().toUtc(),
    );
  }
}

abstract class UlinqEventQueueStorage {
  Future<List<UlinqQueuedEventData>> load();
  Future<void> save(List<UlinqQueuedEventData> events);
}

class SharedPrefsEventQueueStorage implements UlinqEventQueueStorage {
  static const String _storageKey = 'ulinq.sdk.event_queue.v1';
  static const int maxPersistedEvents = 100;

  @override
  Future<List<UlinqQueuedEventData>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <UlinqQueuedEventData>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <UlinqQueuedEventData>[];
      }

      final events = <UlinqQueuedEventData>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final event =
            UlinqQueuedEventData.fromJson(Map<String, dynamic>.from(item));
        if (event.name.isEmpty) continue;
        events.add(event);
      }
      return events;
    } catch (_) {
      return const <UlinqQueuedEventData>[];
    }
  }

  @override
  Future<void> save(List<UlinqQueuedEventData> events) async {
    final prefs = await SharedPreferences.getInstance();
    if (events.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }

    final trimmed = events.length <= maxPersistedEvents
        ? events
        : events.sublist(events.length - maxPersistedEvents);
    final encoded = jsonEncode(trimmed.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}
