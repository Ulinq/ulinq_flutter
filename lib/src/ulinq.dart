import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' as services;

import 'internal/device_id_store.dart';
import 'internal/event_queue.dart';
import 'internal/event_queue_storage.dart';
import 'internal/install_token_provider.dart';
import 'internal/launch_state_store.dart';
import 'internal/link_identifier.dart';
import 'internal/link_parser.dart';
import 'internal/network_client.dart';
import 'internal/session_manager.dart';
import 'internal/skadnetwork_tracker.dart';
import 'ulinq_config.dart';
import 'ulinq_errors.dart';
import 'ulinq_events.dart';
import 'ulinq_logger.dart';
import 'ulinq_models.dart';

class Ulinq {
  Ulinq._();

  static UlinqConfig? _config;
  static NetworkClient? _network;
  static AppLinks? _appLinks;
  static DeviceIdStore? _deviceIdStore;
  static InstallTokenProvider? _installTokenProvider;
  static LaunchStateStore? _launchStateStore;
  static SkAdNetworkTracker? _skAdNetworkTracker;
  static UlinqSessionManager? _sessionManager;
  static UlinqEventQueue? _eventQueue;
  static final StreamController<UlinqResolvedLink> _onLinkController =
      StreamController<UlinqResolvedLink>.broadcast();
  static final Set<String> _deliveredSessionKeys = <String>{};
  static const LinkParser _linkParser = LinkParser();
  static String? _pendingInstallToken;
  static bool? _isFirstLaunch;
  static bool _debugEnabled = false;
  static UlinqLogger _logger = const UlinqNoopLogger();

  static Future<void> initialize(UlinqConfig config) async {
    config.validate();

    _config = config;
    _logger = config.logger ?? const UlinqNoopLogger();
    _network = NetworkClient(config: config);
    _appLinks = AppLinks();
    _deviceIdStore = DeviceIdStore();
    _installTokenProvider = InstallTokenProvider();
    _launchStateStore = LaunchStateStore();
    _skAdNetworkTracker = const SkAdNetworkTracker();
    _isFirstLaunch = await _launchStateStore!.markLaunchedAndCheckIfFirst();
    await _eventQueue?.dispose();
    _eventQueue = UlinqEventQueue(
      logger: _logger,
      isDebugEnabled: _isDebugEnabledFlag,
      storage: SharedPrefsEventQueueStorage(),
      sendBatch: _sendBatchQueuedEvents,
    );
    _deliveredSessionKeys.clear();
    final restored = await _eventQueue!.restorePersistedEvents(
      sender: _sendRestoredQueuedEvent,
    );
    if (restored > 0) {
      _debug('restored persisted events count=$restored');
      unawaited(_eventQueue!.flush(reason: 'startup_restore'));
    }

    await _sessionManager?.dispose();
    _sessionManager = UlinqSessionManager(
      appLinks: _appLinks!,
      parser: _linkParser,
      resolver: _resolveIdentifierForSession,
      logger: _logger,
      isDebugEnabled: _isDebugEnabledFlag,
      onForeground: () => _eventQueue!.flush(reason: 'foreground'),
    );
    _sessionManager!.onLinkReceived.listen(
      (resolved) => _emitResolvedLink(
        resolved,
        source: 'session_manager',
      ),
    );
    await _sessionManager!.initSession();
    _debug('ulinq deferred attribution attempted');
    await _attemptAutomaticDeferredAttribution();
  }

  static void enableDebug([bool enabled = true]) {
    _debugEnabled = enabled;
  }

  static void setPendingInstallToken(String token) {
    final cleaned = token.trim();
    if (cleaned.isNotEmpty) {
      _pendingInstallToken = cleaned;
    }
  }

  static Stream<UlinqResolvedLink> get onLink => _onLinkController.stream;
  static Stream<UlinqResolvedLink> get onLinkReceived => onLink;

  static Future<bool> isFirstLaunch() async {
    _ensureInitialized();
    if (_isFirstLaunch != null) {
      return _isFirstLaunch!;
    }

    _isFirstLaunch = await _launchStateStore!.isFirstLaunch();
    return _isFirstLaunch!;
  }

  static Future<UlinqInstallAttribution?> claimInstallAttribution({
    String? deviceIdOverride,
  }) async {
    _ensureInitialized();

    final token = await _resolveInstallToken();

    final deviceId =
        (deviceIdOverride != null && deviceIdOverride.trim().isNotEmpty)
            ? deviceIdOverride.trim()
            : await _deviceIdStore!.getOrCreate();

    final platform = _platformString();
    if (platform == 'unknown') {
      return null;
    }

    final body = <String, dynamic>{
      'platform': platform,
      'device_id': deviceId,
    };
    if (token != null && token.isNotEmpty) {
      body['install_token'] = token;
    }

    final payload = await _network!.postJson(
      '/sdk/v1/install',
      body: body,
    );

    if (token != null && token.isNotEmpty) {
      _pendingInstallToken = null;
    }
    final attribution = UlinqInstallAttribution.fromJson(payload);
    if (attribution.attributed) {
      await _skAdNetworkTracker?.updateConversionValue(0);
      final deeplinkId = attribution.deeplinkId?.trim();
      if (deeplinkId != null && deeplinkId.isNotEmpty) {
        try {
          _debug(
              'ulinq resolving identifier source=deferred deeplink_id=$deeplinkId');
          final resolved = await _resolveByDeeplinkId(deeplinkId);
          if (resolved != null) {
            _emitResolvedLink(
              resolved,
              source: 'deferred_attribution',
            );
            _debug(
                'ulinq deferred deeplink resolved deeplink_id=${resolved.deeplinkId}');
          }
        } on UlinqException {
          // Attribution succeeded even if resolve fails.
        }
      }
    }
    return attribution;
  }

  static Future<UlinqResolvedLink?> claimDeferredDeeplink({
    String? deviceIdOverride,
    bool onlyOnFirstLaunch = true,
  }) async {
    _ensureInitialized();

    if (onlyOnFirstLaunch && !await isFirstLaunch()) {
      return null;
    }

    try {
      final attribution = await claimInstallAttribution(
        deviceIdOverride: deviceIdOverride,
      );
      if (attribution != null && attribution.attributed) {
        final deeplinkId = attribution.deeplinkId?.trim();
        if (deeplinkId != null && deeplinkId.isNotEmpty) {
          return _resolveByDeeplinkId(deeplinkId);
        }
      }
      return null;
    } on UlinqInvalidResponseException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 404) {
        if (_config!.enableLogging) {
          _logger
              .info('deferred attribution unavailable or no match; ignoring');
        }
        return null;
      }
      rethrow;
    }
  }

  static Future<UlinqResolvedLink?> resolve({required String token}) async {
    _ensureInitialized();

    final cleaned = token.trim();
    if (cleaned.isEmpty) {
      throw UlinqInvalidResponseException('token is required');
    }

    return _resolveByToken(cleaned);
  }

  static Future<void> trackOpen({
    String? deeplinkId,
    Map<String, Object?>? properties,
  }) async {
    _ensureInitialized();

    final installToken = await _resolveInstallToken();
    final sessionId = _sessionManager!.currentSessionId;
    final body = <String, dynamic>{
      'platform': _platformString(),
      'device_id': await _deviceIdStore!.getOrCreate(),
      'opened_at_utc': DateTime.now().toUtc().toIso8601String(),
      'session_id': sessionId,
    };
    if (installToken != null && installToken.isNotEmpty) {
      body['install_token'] = installToken;
    }
    if (deeplinkId != null && deeplinkId.trim().isNotEmpty) {
      body['deeplink_id'] = deeplinkId.trim();
    }
    if (properties != null) {
      body['properties'] = properties;
    }
    body['first_open'] = await isFirstLaunch();

    await _eventQueue!.add<void>(
      name: 'app_open',
      payload: body,
      send: () async {
        try {
          final response =
              await _network!.postJson('/sdk/v1/events/app-open', body: body);
          if (response['first_open'] == true) {
            _pendingInstallToken = null;
          }
          await _skAdNetworkTracker?.updateConversionValue(0);
        } on UlinqInvalidResponseException catch (e) {
          if (e.statusCode == 404) {
            if (_config!.enableLogging) {
              _logger.info('trackOpen endpoint not enabled; ignoring');
            }
            return;
          }
          rethrow;
        }
      },
      parseBatchResponse: (_) {},
      flushNow: true,
    );
  }

  static Future<UlinqConversionResult> trackConversion({
    required String eventName,
    required String eventId,
    double? value,
    String? currency,
    Map<String, Object?>? properties,
    String? deviceIdOverride,
  }) async {
    _ensureInitialized();

    final normalizedEventName = eventName.trim();
    final normalizedEventId = eventId.trim();
    if (normalizedEventName.isEmpty) {
      throw UlinqInvalidResponseException('eventName is required');
    }
    if (UlinqSystemEvents.immutable.contains(normalizedEventName)) {
      throw UlinqInvalidResponseException(
        'eventName is reserved for system lifecycle events. '
        'Use claimInstallAttribution() and trackOpen() for install/app_open.',
      );
    }
    if (normalizedEventId.isEmpty) {
      throw UlinqInvalidResponseException('eventId is required');
    }
    if (value != null && value < 0) {
      throw UlinqInvalidResponseException('value must be >= 0');
    }

    final deviceId =
        (deviceIdOverride != null && deviceIdOverride.trim().isNotEmpty)
            ? deviceIdOverride.trim()
            : await _deviceIdStore!.getOrCreate();
    final installToken = await _resolveInstallToken();
    final sessionId = _sessionManager!.currentSessionId;

    final body = <String, dynamic>{
      'device_id': deviceId,
      'platform': _platformString(),
      'event_name': normalizedEventName,
      'event_id': normalizedEventId,
      'occurred_at_utc': DateTime.now().toUtc().toIso8601String(),
      'session_id': sessionId,
    };
    if (installToken != null && installToken.isNotEmpty) {
      body['install_token'] = installToken;
    }
    if (value != null) {
      body['value'] = value;
    }
    if (currency != null && currency.trim().isNotEmpty) {
      body['currency'] = currency.trim().toUpperCase();
    }
    if (properties != null) {
      body['properties'] = properties;
    }

    return _eventQueue!.add<UlinqConversionResult>(
      name: normalizedEventName,
      payload: body,
      send: () async {
        final response =
            await _network!.postJson('/sdk/v1/events/conversion', body: body);
        final conversion = UlinqConversionResult.fromJson(response);
        final skadValue = _skAdConversionValueForEvent(normalizedEventName);
        if (skadValue != null) {
          await _skAdNetworkTracker?.updateConversionValue(skadValue);
        }
        return conversion;
      },
      parseBatchResponse: UlinqConversionResult.fromJson,
    );
  }

  static Future<void> dispose() async {
    await _sessionManager?.dispose();
    _sessionManager = null;
    await _eventQueue?.dispose();
    _eventQueue = null;
    _network = null;
    _config = null;
    _appLinks = null;
    _deviceIdStore = null;
    _installTokenProvider = null;
    _launchStateStore = null;
    _skAdNetworkTracker = null;
    _pendingInstallToken = null;
    _isFirstLaunch = null;
    _debugEnabled = false;
    _deliveredSessionKeys.clear();
  }

  static Future<UlinqResolvedLink?> _resolveIdentifierForSession(
    LinkIdentifier identifier,
    SessionLinkSource source,
  ) async {
    _debug('ulinq resolving identifier source=${source.name}');
    return _resolveIdentifier(identifier);
  }

  static Future<dynamic> _sendRestoredQueuedEvent(
    UlinqQueuedEventData event,
  ) async {
    if (event.name == 'app_open') {
      try {
        return _network!
            .postJson('/sdk/v1/events/app-open', body: event.payload);
      } on UlinqInvalidResponseException catch (e) {
        if (e.statusCode == 404) {
          return <String, dynamic>{};
        }
        rethrow;
      }
    }
    return _network!.postJson('/sdk/v1/events/conversion', body: event.payload);
  }

  static Future<List<UlinqBatchItemResult>> _sendBatchQueuedEvents(
    List<UlinqQueuedEventData> events,
  ) async {
    if (events.isEmpty) {
      return const <UlinqBatchItemResult>[];
    }

    final payload = <String, dynamic>{
      'events': events
          .map((event) => <String, dynamic>{
                'type': event.name == 'app_open' ? 'app_open' : 'conversion',
                'payload': event.payload,
              })
          .toList(growable: false),
    };
    final response =
        await _network!.postJson('/sdk/v1/events/batch', body: payload);
    final rawResults = response['results'];
    if (rawResults is! List) {
      throw UlinqInvalidResponseException('invalid batch response: results');
    }

    final byIndex = <int, UlinqBatchItemResult>{};
    for (final item in rawResults) {
      if (item is! Map) continue;
      final mapped = Map<String, dynamic>.from(item);
      final index = mapped['index'];
      if (index is! num) continue;
      final success = mapped['success'] == true;
      final status = mapped['status'];
      final responseMap = mapped['response'] is Map
          ? Map<String, dynamic>.from(mapped['response'] as Map)
          : null;
      byIndex[index.toInt()] = UlinqBatchItemResult(
        success: success,
        statusCode: status is num ? status.toInt() : null,
        response: responseMap,
        error: mapped['error'] as String?,
      );
    }

    final ordered = <UlinqBatchItemResult>[];
    for (var i = 0; i < events.length; i++) {
      ordered.add(byIndex[i] ??
          const UlinqBatchItemResult(
            success: false,
            error: 'missing batch item result',
          ));
    }
    return ordered;
  }

  static Future<UlinqResolvedLink?> _resolveIdentifier(
    LinkIdentifier identifier,
  ) async {
    if (identifier.token != null && identifier.token!.isNotEmpty) {
      return _resolveByToken(identifier.token!);
    }

    if (identifier.slug != null && identifier.slug!.isNotEmpty) {
      return _resolveBySlug(identifier.slug!);
    }

    if (identifier.installToken != null &&
        identifier.installToken!.isNotEmpty) {
      await claimInstallAttribution();
      if (identifier.token != null && identifier.token!.isNotEmpty) {
        return _resolveByToken(identifier.token!);
      }
      if (identifier.slug != null && identifier.slug!.isNotEmpty) {
        return _resolveBySlug(identifier.slug!);
      }
    }

    return null;
  }

  static Future<UlinqResolvedLink?> _resolveByToken(String token) async {
    _debug('ulinq resolve request query=token');
    final payload = await _network!.getJson('/sdk/v1/deeplinks/resolve',
        query: <String, dynamic>{'token': token});
    final resolved = UlinqResolvedLink.fromJson(payload);
    _debug(
        'ulinq resolve success via token deeplink_id=${resolved.deeplinkId}');
    return resolved;
  }

  static Future<UlinqResolvedLink?> _resolveBySlug(String slug) async {
    _debug('ulinq resolve request query=slug');
    final payload = await _network!.getJson('/sdk/v1/deeplinks/resolve',
        query: <String, dynamic>{'slug': slug});
    final resolved = UlinqResolvedLink.fromJson(payload);
    _debug('ulinq resolve success via slug deeplink_id=${resolved.deeplinkId}');
    return resolved;
  }

  static Future<UlinqResolvedLink?> _resolveByDeeplinkId(
      String deeplinkId) async {
    _debug('ulinq resolve request query=deeplink_id');
    final payload = await _network!.getJson('/sdk/v1/deeplinks/resolve',
        query: <String, dynamic>{'deeplink_id': deeplinkId});
    final resolved = UlinqResolvedLink.fromJson(payload);
    _debug(
        'ulinq resolve success via deeplink_id deeplink_id=${resolved.deeplinkId}');
    return resolved;
  }

  static Future<void> _attemptAutomaticDeferredAttribution() async {
    final firstLaunch = await isFirstLaunch();
    if (!firstLaunch) {
      return;
    }

    final hasDirectLink = await _hasResolvableInitialLink();
    if (hasDirectLink) {
      _debug('skip automatic deferred attribution: initial deep link present');
      return;
    }

    try {
      await claimInstallAttribution();
    } on UlinqInvalidResponseException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 404) {
        _debug('automatic deferred attribution unavailable');
      }
    } on UlinqException catch (_) {
      // Do not block initialization if deferred attribution cannot be claimed.
    }
  }

  static void _emitResolvedLink(
    UlinqResolvedLink resolved, {
    required String source,
  }) {
    final deeplinkId = resolved.deeplinkId?.trim();
    final sessionId = _sessionManager?.currentSessionId.trim();
    if (sessionId != null &&
        sessionId.isNotEmpty &&
        deeplinkId != null &&
        deeplinkId.isNotEmpty) {
      final key = '$sessionId:$deeplinkId';
      if (_deliveredSessionKeys.contains(key)) {
        _debug('ulinq payload delivery dedupe hit key=$key source=$source');
        return;
      }
      _deliveredSessionKeys.add(key);
    }
    _onLinkController.add(resolved);
    _debug(
        'ulinq payload delivered source=$source deeplink_id=${resolved.deeplinkId} session_id=${_sessionManager?.currentSessionId}');
  }

  static Future<bool> _hasResolvableInitialLink() async {
    try {
      final uri = await _appLinks!.getInitialLink();
      final parsed = _linkParser.parseFromUri(uri);
      return (parsed.token != null && parsed.token!.isNotEmpty) ||
          (parsed.slug != null && parsed.slug!.isNotEmpty);
    } on services.PlatformException {
      return false;
    }
  }

  static Future<String?> _resolveInstallToken() async {
    if (_pendingInstallToken != null && _pendingInstallToken!.isNotEmpty) {
      _debug('install token source=pending');
      return _pendingInstallToken;
    }

    final initial = await _readInstallTokenFromInitialLink();
    if (initial != null) {
      _debug('install token source=initial_link');
      return initial;
    }

    final native = await _installTokenProvider!.fromNative();
    if (native.installToken != null && native.installToken!.isNotEmpty) {
      _debug('install token source=native');
      return native.installToken;
    }

    final clipboard = await _readClipboardToken();
    if (clipboard != null) {
      _debug('install token source=clipboard');
      return clipboard;
    }

    _debug('install token source=none');
    return null;
  }

  static Future<String?> _readInstallTokenFromInitialLink() async {
    try {
      final uri = await _appLinks!.getInitialLink();
      final parsed = _linkParser.parseFromUri(uri);
      return parsed.installToken;
    } on services.PlatformException {
      return null;
    }
  }

  static Future<String?> _readClipboardToken() async {
    if (kIsWeb) return null;
    try {
      final data = await services.Clipboard.getData('text/plain');
      final text = data?.text;
      if (text == null || text.trim().isEmpty) return null;
      final parsed = _linkParser.parseFromString(text);
      return parsed.installToken;
    } catch (_) {
      return null;
    }
  }

  static String _platformString() {
    if (kIsWeb) return 'unknown';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'unknown';
    }
  }

  static int? _skAdConversionValueForEvent(String eventName) {
    final normalized = eventName.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    switch (normalized) {
      case 'install':
      case 'app_open':
        return 0;
      case 'signup':
      case 'sign_up':
      case 'register':
      case 'registration_complete':
        return 1;
      case 'purchase':
      case 'subscribe':
      case 'subscription':
      case 'start_trial':
        return 3;
      default:
        return null;
    }
  }

  static void _ensureInitialized() {
    if (_config == null ||
        _network == null ||
        _appLinks == null ||
        _deviceIdStore == null ||
        _installTokenProvider == null ||
        _launchStateStore == null ||
        _skAdNetworkTracker == null ||
        _sessionManager == null ||
        _eventQueue == null) {
      throw UlinqInvalidResponseException(
          'Ulinq.initialize must be called first');
    }
  }

  static bool _isDebugEnabledFlag() => _debugEnabled;

  static void _debug(String message) {
    if (_debugEnabled) {
      _logger.debug(message);
    }
  }
}
