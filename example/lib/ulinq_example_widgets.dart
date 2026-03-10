import 'dart:convert';

import 'package:flutter/material.dart';

class ExampleInputField extends StatelessWidget {
  const ExampleInputField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}

class ExampleJsonCard extends StatelessWidget {
  const ExampleJsonCard({super.key, required this.title, required this.data});

  final String title;
  final Object? data;

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(pretty),
          ],
        ),
      ),
    );
  }
}

class ExampleLogCard extends StatelessWidget {
  const ExampleLogCard({super.key, required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in logs) Text(entry),
          ],
        ),
      ),
    );
  }
}
