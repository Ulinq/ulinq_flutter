import 'package:flutter/foundation.dart';

@immutable
class UlinqResolvedLink {
  const UlinqResolvedLink({
    this.deeplinkId,
    this.appId,
    this.projectId,
    this.slug,
    this.subdomain,
    this.payload = const <String, dynamic>{},
    this.metadata = const <String, dynamic>{},
  });

  final String? deeplinkId;
  final String? appId;
  final String? projectId;
  final String? slug;
  final String? subdomain;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> metadata;

  factory UlinqResolvedLink.fromJson(Map<String, dynamic> json) {
    final payload = Map<String, dynamic>.from(
        json['payload'] as Map? ?? const <String, dynamic>{});
    final metadata = Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const <String, dynamic>{});
    return UlinqResolvedLink(
      deeplinkId: (json['deeplink_id'] ?? json['id']) as String?,
      appId: json['app_id'] as String?,
      projectId: json['project_id'] as String?,
      slug: json['slug'] as String?,
      subdomain: json['subdomain'] as String?,
      payload: payload,
      metadata: metadata,
    );
  }
}

@immutable
class UlinqInstallAttribution {
  const UlinqInstallAttribution({
    required this.attributed,
    required this.status,
    this.deeplinkId,
    this.appId,
    this.idempotent = false,
    this.reason,
  });

  final bool attributed;
  final String status;
  final String? deeplinkId;
  final String? appId;
  final bool idempotent;
  final String? reason;

  factory UlinqInstallAttribution.fromJson(Map<String, dynamic> json) {
    return UlinqInstallAttribution(
      attributed: json['attributed'] == true,
      status: (json['status'] as String?) ?? 'unattributed',
      deeplinkId: json['deeplink_id'] as String?,
      appId: json['app_id'] as String?,
      idempotent: json['idempotent'] == true,
      reason: json['reason'] as String?,
    );
  }
}

@immutable
class UlinqConversionResult {
  const UlinqConversionResult({
    required this.attributed,
    required this.idempotent,
    this.installId,
    this.deeplinkId,
  });

  final bool attributed;
  final bool idempotent;
  final String? installId;
  final String? deeplinkId;

  factory UlinqConversionResult.fromJson(Map<String, dynamic> json) {
    return UlinqConversionResult(
      attributed: json['attributed'] == true,
      idempotent: json['idempotent'] == true,
      installId: json['install_id'] as String?,
      deeplinkId: json['deeplink_id'] as String?,
    );
  }
}
