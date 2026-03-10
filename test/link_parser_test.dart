import 'package:flutter_test/flutter_test.dart';
import 'package:ulinq_sdk/src/internal/link_parser.dart';

void main() {
  const parser = LinkParser();

  test('parses android referrer with install token and dl', () {
    final id = parser.parseFromString('install_token=abc123&dl=/r/summer');
    expect(id.installToken, 'abc123');
    expect(id.slug, 'summer');
  });

  test('parses URL encoded referrer', () {
    final id = parser.parseFromString(
        'referrer=install_token%3Dxyz987%26dl%3D%252Fr%252Fpromo');
    expect(id.installToken, 'xyz987');
    expect(id.slug, 'promo');
  });
}
