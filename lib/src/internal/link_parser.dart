import 'dart:core';

import 'link_identifier.dart';

class LinkParser {
  const LinkParser();

  LinkIdentifier parseFromString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const LinkIdentifier();

    final referrer = _parseReferrer(trimmed);
    if (!referrer.isEmpty) return referrer;

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final token = uri.queryParameters['token']?.trim();
      if (token != null && token.isNotEmpty) {
        return LinkIdentifier(token: token);
      }

      final installToken = uri.queryParameters['install_token']?.trim();
      if (installToken != null && installToken.isNotEmpty) {
        return LinkIdentifier(installToken: installToken);
      }

      final referrerParam = uri.queryParameters['referrer']?.trim();
      if (referrerParam != null && referrerParam.isNotEmpty) {
        final parsedReferrer = _parseReferrer(referrerParam);
        if (!parsedReferrer.isEmpty) {
          return parsedReferrer;
        }
      }

      final slug = _slugFromUri(uri);
      if (slug != null) {
        return LinkIdentifier(slug: slug);
      }
    }

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
    return null;
  }
}
