import 'package:flutter/foundation.dart';

import 'ulinq_logger.dart';

const String _defaultBaseUrl = String.fromEnvironment(
  'ULINQ_BASE_URL',
  defaultValue: 'https://api.ulinq.cc',
);
const String _defaultSdkKey = String.fromEnvironment(
  'ULINQ_SDK_KEY',
  defaultValue: '',
);

enum UlinqAuthHeaderMode {
  authorization,
  xSdkKey,
  both,
}

@immutable
class UlinqConfig {
  UlinqConfig({
    String? sdkKey,
    this.timeout = const Duration(seconds: 8),
    this.enableLogging = false,
    this.authHeaderMode = UlinqAuthHeaderMode.authorization,
    this.logger,
  })  : sdkKey = (sdkKey == null || sdkKey == '') ? _defaultSdkKey : sdkKey,
        baseUrl = Uri.parse(_defaultBaseUrl);

  final String sdkKey;
  // Base URL is SDK-managed internally via ULINQ_BASE_URL dart-define.
  final Uri baseUrl;
  final Duration timeout;
  final bool enableLogging;
  final UlinqAuthHeaderMode authHeaderMode;
  final UlinqLogger? logger;

  void validate() {
    if (sdkKey.trim().isEmpty) {
      throw ArgumentError('sdkKey is required');
    }
    if (!baseUrl.hasScheme ||
        (baseUrl.scheme != 'http' && baseUrl.scheme != 'https')) {
      throw ArgumentError('baseUrl must be a valid http/https URL');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be greater than zero');
    }
  }
}
