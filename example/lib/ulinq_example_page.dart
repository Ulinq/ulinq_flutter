import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ulinq_sdk/ulinq_sdk.dart';
import 'ulinq_example_actions.dart';
import 'ulinq_example_content.dart';

class UlinqExamplePage extends StatefulWidget {
  const UlinqExamplePage({super.key});
  @override
  State<UlinqExamplePage> createState() => _UlinqExamplePageState();
}

class _UlinqExamplePageState extends State<UlinqExamplePage> {
  final _token = TextEditingController(), _pending = TextEditingController();
  final _eventName = TextEditingController(text: 'purchase'), _eventId = TextEditingController(text: 'example-event-1');
  final _value = TextEditingController(text: '10.0'), _currency = TextEditingController(text: 'USD');
  final List<String> _logs = <String>[];
  StreamSubscription<UlinqResolvedLink>? _sub;
  UlinqResolvedLink? _resolved;
  UlinqInstallAttribution? _attribution;
  bool? _isFirstLaunch;
  String _status = 'Idle';

  @override
  void initState() {
    super.initState();
    _sub = Ulinq.onLinkReceived.listen((link) {
      if (!mounted) return;
      setState(() {
        _resolved = link;
        _status = 'onLinkReceived fired';
      });
      _log('onLinkReceived deeplink=${link.deeplinkId ?? '-'}');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final c in [_token, _pending, _eventName, _eventId, _value, _currency]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(String name, Future<void> Function() action) async {
    setState(() => _status = 'Running: $name');
    try {
      await action();
      if (!mounted) return;
      setState(() => _status = 'Success: $name');
      _log('Success: $name');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = e is UlinqException ? 'Ulinq error: ${e.message}' : 'Error: $e');
      _log('Error on $name: $e');
    }
  }

  void _log(String text) {
    final ts = DateTime.now().toIso8601String();
    setState(() => _logs.insert(0, '[$ts] $text'));
    if (_logs.length > 15) _logs.removeRange(15, _logs.length);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ulinq Full Feature Example')),
        body: UlinqExampleContent(
          status: _status,
          isFirstLaunch: _isFirstLaunch,
          attribution: _attribution,
          resolved: _resolved,
          lastPayload: Ulinq.getLastPayload(),
          lastMetadata: Ulinq.getLastMetadata(),
          logs: _logs,
          token: _token,
          pendingInstallToken: _pending,
          eventName: _eventName,
          eventId: _eventId,
          value: _value,
          currency: _currency,
          actions: buildActionButtons(
            initialize: () => _run('Initialize', () async { Ulinq.enableDebug(true); final t = _pending.text.trim(); if (t.isNotEmpty) Ulinq.setPendingInstallToken(t); await Ulinq.initialize(UlinqConfig(sdkKey: const String.fromEnvironment('ULINQ_SDK_KEY', defaultValue: ''), authHeaderMode: UlinqAuthHeaderMode.both, enableLogging: true)); }),
            firstLaunch: () => _run('isFirstLaunch', () async { final v = await Ulinq.isFirstLaunch(); setState(() => _isFirstLaunch = v); }),
            claimInstall: () => _run('claimInstallAttribution', () async { final a = await Ulinq.claimInstallAttribution(); setState(() => _attribution = a); }),
            claimDeferred: () => _run('claimDeferredDeeplink', () async { final r = await Ulinq.claimDeferredDeeplink(onlyOnFirstLaunch: false); if (r != null) setState(() => _resolved = r); }),
            resolveToken: () => _run('resolve(token)', () async { final r = await Ulinq.resolve(token: _token.text.trim()); setState(() => _resolved = r); }),
            trackOpen: () => _run('trackOpen', () => Ulinq.trackOpen(deeplinkId: _resolved?.deeplinkId, properties: {'source': 'example'})),
            trackConversion: () => _run('trackConversion', () => Ulinq.trackConversion(eventName: _eventName.text.trim(), eventId: _eventId.text.trim(), value: double.tryParse(_value.text.trim()), currency: _currency.text.trim(), properties: {'from': 'example_app'})),
            readLast: () => _run('getLast cache', () async { _log('payload=${Ulinq.getLastPayload()}'); _log('metadata=${Ulinq.getLastMetadata()}'); setState(() {}); }),
            disposeSdk: () => _run('dispose', Ulinq.dispose),
          ),
        ),
      );
}
