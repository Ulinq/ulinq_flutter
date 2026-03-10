import 'dart:async';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import '../ulinq_logger.dart';
import '../ulinq_models.dart';
import 'link_identifier.dart';
import 'link_parser.dart';

typedef SessionResolver = Future<UlinqResolvedLink?> Function(
  LinkIdentifier identifier,
  SessionLinkSource source,
);

enum SessionLinkSource {
  initial,
  resume,
  stream,
}

class UlinqSessionManager with WidgetsBindingObserver {
  UlinqSessionManager({
    required AppLinks appLinks,
    required LinkParser parser,
    required SessionResolver resolver,
    required UlinqLogger logger,
    required bool Function() isDebugEnabled,
    Future<void> Function()? onForeground,
    this.sessionResetThreshold = const Duration(seconds: 30),
  })  : _appLinks = appLinks,
        _parser = parser,
        _resolver = resolver,
        _logger = logger,
        _isDebugEnabled = isDebugEnabled,
        _onForeground = onForeground;

  final AppLinks _appLinks;
  final LinkParser _parser;
  final SessionResolver _resolver;
  final UlinqLogger _logger;
  final bool Function() _isDebugEnabled;
  final Future<void> Function()? _onForeground;
  final Duration sessionResetThreshold;

  final StreamController<UlinqResolvedLink> _onLinkController =
      StreamController<UlinqResolvedLink>.broadcast();
  final Set<String> _handledDeeplinksInSession = <String>{};
  final Random _random = Random.secure();

  StreamSubscription<Uri?>? _uriSubscription;
  String? _lastHandledLink;
  DateTime? _lastPausedAtUtc;
  int _sessionCount = 0;
  String _sessionId = '';

  Stream<UlinqResolvedLink> get onLinkReceived => _onLinkController.stream;
  String get currentSessionId => _sessionId;

  Future<void> initSession() async {
    WidgetsBinding.instance.addObserver(this);
    _startSession(isColdStart: true);
    await _resolveFromInitialLink();

    await _uriSubscription?.cancel();
    _uriSubscription = _appLinks.uriLinkStream.listen(
      (uri) async {
        try {
          await _processIncomingUri(uri, SessionLinkSource.stream);
        } catch (e, st) {
          if (_isDebugEnabled()) {
            _logger.error('Session stream link handling failed',
                error: e, stackTrace: st);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_isDebugEnabled()) {
          _logger.error('uriLinkStream failure',
              error: error, stackTrace: stackTrace);
        }
      },
      cancelOnError: false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final pausedAt = _lastPausedAtUtc;
      final shouldResetSession = pausedAt != null &&
          DateTime.now().toUtc().difference(pausedAt) > sessionResetThreshold;
      if (shouldResetSession) {
        _startSession(isColdStart: false);
      } else {
        _debug('session resume keep session_id=$_sessionId');
      }
      Future<void>(() async {
        try {
          await _onForeground?.call();
          await _resolveFromResume();
        } catch (e, st) {
          if (_isDebugEnabled()) {
            _logger.error('Session resume handling failed',
                error: e, stackTrace: st);
          }
        }
      });
    } else if (state == AppLifecycleState.paused) {
      _lastPausedAtUtc = DateTime.now().toUtc();
      _debug('session paused');
    }
  }

  Future<void> _resolveFromInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      await _processIncomingUri(uri, SessionLinkSource.initial);
    } catch (_) {
      // Ignore platform errors; stream listener still covers runtime links.
    }
  }

  Future<void> _resolveFromResume() async {
    try {
      final uri = await _appLinks.getInitialLink();
      await _processIncomingUri(uri, SessionLinkSource.resume);
    } catch (_) {
      // Ignore platform errors on resume checks.
    }
  }

  Future<void> _processIncomingUri(Uri? uri, SessionLinkSource source) async {
    if (uri == null) return;

    final normalized = uri.toString();
    if (normalized.isEmpty || normalized == _lastHandledLink) {
      return;
    }

    final identifier = _parser.parseFromUri(uri);
    if (identifier.isEmpty) {
      return;
    }

    _debug('ulinq link detected source=${source.name} uri=$normalized');
    final resolved = await _resolver(identifier, source);
    _lastHandledLink = normalized;
    if (resolved != null) {
      final deeplinkID = resolved.deeplinkId?.trim();
      if (deeplinkID != null && deeplinkID.isNotEmpty) {
        final dedupeKey = '$_sessionId:$deeplinkID';
        if (_handledDeeplinksInSession.contains(dedupeKey)) {
          _debug('session dedupe hit key=$dedupeKey');
          return;
        }
        _handledDeeplinksInSession.add(dedupeKey);
      }
      _onLinkController.add(resolved);
      _debug(
          'session resolved deeplink_id=${resolved.deeplinkId} session_id=$_sessionId');
    }
  }

  void _startSession({required bool isColdStart}) {
    _sessionCount += 1;
    _sessionId = _newSessionId();
    _lastHandledLink = null;
    _handledDeeplinksInSession.clear();
    _debug(
      'ulinq session start #$_sessionCount type=${isColdStart ? 'cold' : 'warm'} session_id=$_sessionId',
    );
  }

  String _newSessionId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).join();
    return '${b.substring(0, 8)}-'
        '${b.substring(8, 12)}-'
        '${b.substring(12, 16)}-'
        '${b.substring(16, 20)}-'
        '${b.substring(20, 32)}';
  }

  void _debug(String message) {
    if (_isDebugEnabled()) {
      _logger.debug(message);
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _uriSubscription?.cancel();
    _uriSubscription = null;
    await _onLinkController.close();
  }
}
