import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'link_identifier.dart';
import 'link_parser.dart';

class InstallTokenProvider {
  InstallTokenProvider({
    MethodChannel? methodChannel,
    LinkParser? parser,
  })  : _channel =
            methodChannel ?? const MethodChannel('ulinq/install_referrer'),
        _parser = parser ?? const LinkParser();

  final MethodChannel _channel;
  final LinkParser _parser;

  Future<LinkIdentifier> fromNative() async {
    try {
      if (kIsWeb) return const LinkIdentifier();

      if (defaultTargetPlatform == TargetPlatform.android) {
        final referrer =
            await _channel.invokeMethod<String>('getInstallReferrer');
        if (referrer != null && referrer.trim().isNotEmpty) {
          return _parser.parseFromString(referrer);
        }
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final token =
            await _channel.invokeMethod<String>('getPendingInstallToken');
        if (token != null && token.trim().isNotEmpty) {
          return _parser.parseFromString(token);
        }
      }
    } catch (_) {
      return const LinkIdentifier();
    }
    return const LinkIdentifier();
  }
}
