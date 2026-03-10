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

  test('parses uri query with install_token and dl', () {
    final id = parser
        .parseFromString('myapp://open?install_token=abc123&dl=%2Fr%2Fsummer');
    expect(id.installToken, 'abc123');
    expect(id.slug, 'summer');
  });

  test('parses uri query with dl only', () {
    final id = parser.parseFromString('https://demo.ulinq.cc/open?dl=/r/promo');
    expect(id.slug, 'promo');
  });

  test('parses legacy direct slug path', () {
    final id = parser.parseFromString('https://kashcool.ulinq.cc/sale');
    expect(id.slug, 'sale');
  });
}
