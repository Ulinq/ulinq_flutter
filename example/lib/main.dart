// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:ulinq_sdk/ulinq_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Ulinq.initialize(
    UlinqConfig(
      sdkKey: String.fromEnvironment('ULINQ_SDK_KEY', defaultValue: ''),
      enableLogging: true,
      authHeaderMode: UlinqAuthHeaderMode.both,
    ),
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  UlinqResolvedLink? _resolved;
  UlinqInstallAttribution? _attribution;
  bool _isFirstLaunch = false;
  String _status = 'Idle';

  @override
  void initState() {
    super.initState();
    _bootstrap();
    Ulinq.onLink.listen((link) {
      setState(() {
        _resolved = link;
        _status = 'Received in-app link';
      });
    });
  }

  Future<void> _bootstrap() async {
    final firstLaunch = await Ulinq.isFirstLaunch();
    final attribution = await Ulinq.claimInstallAttribution();
    final deferred = attribution?.attributed == true
        ? await Ulinq.claimDeferredDeeplink()
        : null;
    setState(() {
      _isFirstLaunch = firstLaunch;
      _attribution = attribution;
      _resolved = deferred ?? _resolved;
      _status = 'Startup checks completed';
    });
  }

  Future<void> _resolveManually() async {
    try {
      final result = await Ulinq.resolve(token: 'replace_with_token');
      setState(() {
        _resolved = result;
        _status = 'Resolved manually';
      });
    } on UlinqException catch (e) {
      setState(() {
        _status = 'Resolve error: ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Ulinq SDK Example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Status: $_status'),
              const SizedBox(height: 12),
              Text('Attribution: ${_attribution?.status ?? 'none'}'),
              const SizedBox(height: 12),
              Text('First launch: $_isFirstLaunch'),
              const SizedBox(height: 12),
              Text('Resolved deeplink: ${_resolved?.deeplinkId ?? '-'}'),
              const SizedBox(height: 8),
              Text(
                  'Payload: ${_resolved?.payload ?? const <String, dynamic>{}}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _resolveManually,
                child: const Text('Resolve sample token'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
