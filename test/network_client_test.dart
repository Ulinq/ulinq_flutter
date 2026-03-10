import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ulinq_sdk/src/internal/network_client.dart';
import 'package:ulinq_sdk/src/ulinq_config.dart';

void main() {
  test('sends authorization header by default', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.ulinq.cc'));
    RequestOptions? captured;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{'ok': true},
            ),
          );
        },
      ),
    );

    final client = NetworkClient(
      config: UlinqConfig(sdkKey: 'sdk_live_test'),
      dio: dio,
    );

    await client.getJson('/sdk/v1/deeplinks/resolve',
        query: <String, dynamic>{'token': 'abc'});

    expect(captured?.headers['Authorization'], 'Bearer sdk_live_test');
  });

  test('sends x-sdk-key when configured', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.ulinq.cc'));
    RequestOptions? captured;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: <String, dynamic>{'ok': true},
            ),
          );
        },
      ),
    );

    final client = NetworkClient(
      config: UlinqConfig(
        sdkKey: 'sdk_live_test',
        authHeaderMode: UlinqAuthHeaderMode.xSdkKey,
      ),
      dio: dio,
    );

    await client.getJson('/sdk/v1/deeplinks/resolve',
        query: <String, dynamic>{'token': 'abc'});

    expect(captured?.headers['X-SDK-Key'], 'sdk_live_test');
    expect(captured?.headers.containsKey('Authorization'), isFalse);
  });
}
