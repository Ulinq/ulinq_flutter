import 'package:flutter/material.dart';
import 'package:ulinq_sdk/ulinq_sdk.dart';

import 'ulinq_example_widgets.dart';

class UlinqExampleContent extends StatelessWidget {
  const UlinqExampleContent({
    super.key,
    required this.status,
    required this.isFirstLaunch,
    required this.attribution,
    required this.resolved,
    required this.lastPayload,
    required this.lastMetadata,
    required this.logs,
    required this.token,
    required this.pendingInstallToken,
    required this.eventName,
    required this.eventId,
    required this.value,
    required this.currency,
    required this.actions,
  });

  final String status;
  final bool? isFirstLaunch;
  final UlinqInstallAttribution? attribution;
  final UlinqResolvedLink? resolved;
  final Map<String, dynamic>? lastPayload;
  final Map<String, dynamic>? lastMetadata;
  final List<String> logs;
  final TextEditingController token;
  final TextEditingController pendingInstallToken;
  final TextEditingController eventName;
  final TextEditingController eventId;
  final TextEditingController value;
  final TextEditingController currency;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Status: $status'),
        const SizedBox(height: 8),
        Text('First launch: ${isFirstLaunch?.toString() ?? 'unknown'}'),
        Text('Attribution: ${attribution?.status ?? 'none'}'),
        Text('Resolved deeplink: ${resolved?.deeplinkId ?? '-'}'),
        const SizedBox(height: 12),
        ExampleInputField(label: 'Manual resolve token', controller: token),
        const SizedBox(height: 8),
        ExampleInputField(
            label: 'Pending install token', controller: pendingInstallToken),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child:
                  ExampleInputField(label: 'eventName', controller: eventName)),
          const SizedBox(width: 8),
          Expanded(
              child: ExampleInputField(label: 'eventId', controller: eventId)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: ExampleInputField(
                  label: 'value',
                  controller: value,
                  keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(
              child:
                  ExampleInputField(label: 'currency', controller: currency)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
        const SizedBox(height: 12),
        ExampleJsonCard(title: 'Last Payload', data: lastPayload),
        ExampleJsonCard(title: 'Last Metadata', data: lastMetadata),
        ExampleLogCard(logs: logs),
      ],
    );
  }
}
