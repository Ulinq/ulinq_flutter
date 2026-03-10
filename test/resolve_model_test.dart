import 'package:flutter_test/flutter_test.dart';
import 'package:ulinq_sdk/ulinq_sdk.dart';

void main() {
  test('parses resolved link payload and metadata', () {
    final model = UlinqResolvedLink.fromJson(const <String, dynamic>{
      'id': 'dl_123',
      'app_id': 'app_1',
      'project_id': 'project_1',
      'slug': 'promo',
      'subdomain': 'kashcool',
      'payload': <String, dynamic>{'screen': 'offer', 'offer_id': 12},
      'metadata': <String, dynamic>{'channel': 'email'},
    });

    expect(model.deeplinkId, 'dl_123');
    expect(model.appId, 'app_1');
    expect(model.projectId, 'project_1');
    expect(model.slug, 'promo');
    expect(model.subdomain, 'kashcool');
    expect(model.payload['screen'], 'offer');
    expect(model.metadata['channel'], 'email');
  });
}
