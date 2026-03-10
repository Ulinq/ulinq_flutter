import 'dart:core';

import 'link_identifier.dart';

class LinkParser {
  const LinkParser();

  LinkIdentifier parseFromString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const LinkIdentifier();

    final uri = Uri.tryParse(trimmed);
    final shouldParseAsUri =
        uri != null && (uri.hasScheme || trimmed.startsWith('/'));
    if (uri != null && shouldParseAsUri) {
      final token = uri.queryParameters['token']?.trim();
      final installToken = uri.queryParameters['install_token']?.trim();

      LinkIdentifier fromReferrer = const LinkIdentifier();

      final referrerParam = uri.queryParameters['referrer']?.trim();
      if (referrerParam != null && referrerParam.isNotEmpty) {
        final parsedReferrer = _parseReferrer(referrerParam);
        if (!parsedReferrer.isEmpty) {
          fromReferrer = parsedReferrer;
        }
      }

      LinkIdentifier fromDl = const LinkIdentifier();
      final dl = uri.queryParameters['dl']?.trim();
      if (dl != null && dl.isNotEmpty) {
        fromDl = parseFromString(Uri.decodeQueryComponent(dl));
      }

      final resolvedToken = token != null && token.isNotEmpty
          ? token
          : fromReferrer.token ?? fromDl.token;
      final resolvedInstallToken =
          installToken != null && installToken.isNotEmpty
              ? installToken
              : fromReferrer.installToken;
      final resolvedSlug =
          fromReferrer.slug ?? fromDl.slug ?? _slugFromUri(uri);

      if ((resolvedToken != null && resolvedToken.isNotEmpty) ||
          (resolvedInstallToken != null && resolvedInstallToken.isNotEmpty) ||
          (resolvedSlug != null && resolvedSlug.isNotEmpty)) {
        return LinkIdentifier(
          token: resolvedToken,
          installToken: resolvedInstallToken,
          slug: resolvedSlug,
        );
      }
    }

    final referrer = _parseReferrer(trimmed);
    if (!referrer.isEmpty) return referrer;

    final slugMatch = RegExp(r'/r/([^/?]+)').firstMatch(trimmed);
    if (slugMatch != null) {
      return LinkIdentifier(slug: slugMatch.group(1));
    }

    return const LinkIdentifier();
  }

  LinkIdentifier parseFromUri(Uri? uri) {
    if (uri == null) return const LinkIdentifier();
    return parseFromString(uri.toString());
  }

  LinkIdentifier _parseReferrer(String value) {
    Map<String, String> map;
    try {
      map = Uri.splitQueryString(Uri.decodeQueryComponent(value));
    } catch (_) {
      try {
        map = Uri.splitQueryString(value);
      } catch (_) {
        return const LinkIdentifier();
      }
    }

    final nestedReferrer = (map['referrer'] ?? '').trim();
    final installToken = (map['install_token'] ?? '').trim();
    final token = (map['token'] ?? '').trim();
    final dl = (map['dl'] ?? '').trim();

    if (nestedReferrer.isNotEmpty) {
      final nested = _parseReferrer(nestedReferrer);
      if (!nested.isEmpty) {
        if (dl.isNotEmpty) {
          final fromDl = parseFromString(Uri.decodeQueryComponent(dl));
          return LinkIdentifier(
            installToken: nested.installToken,
            token: nested.token ?? fromDl.token,
            slug: nested.slug ?? fromDl.slug,
          );
        }
        return nested;
      }
    }

    if (installToken.isNotEmpty) {
      final fromDl = dl.isEmpty ? const LinkIdentifier() : parseFromString(dl);
      return LinkIdentifier(
        installToken: installToken,
        token: fromDl.token,
        slug: fromDl.slug,
      );
    }

    if (token.isNotEmpty) {
      return LinkIdentifier(token: token);
    }

    if (dl.isNotEmpty) {
      final decodedDl = Uri.decodeQueryComponent(dl);
      return parseFromString(decodedDl);
    }

    return const LinkIdentifier();
  }

  String? _slugFromUri(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[segments.length - 2] == 'r') {
      return segments.last;
    }
    if (segments.length == 1) {
      final only = segments.first.trim();
      if (only.isNotEmpty) {
        return only;
      }
    }
    return null;
  }
}
