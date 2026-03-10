import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../ulinq_config.dart';
import '../ulinq_errors.dart';
import '../ulinq_logger.dart';

class NetworkClient {
  NetworkClient({
    required UlinqConfig config,
    Dio? dio,
    Random? random,
  })  : _config = config,
        _logger = config.logger ?? const UlinqNoopLogger(),
        _random = random ?? Random.secure(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: config.baseUrl.toString(),
              connectTimeout: config.timeout,
              receiveTimeout: config.timeout,
              sendTimeout: config.timeout,
              responseType: ResponseType.json,
            ));

  final UlinqConfig _config;
  final Dio _dio;
  final UlinqLogger _logger;
  final Random _random;

  Map<String, String> _authHeaders() {
    final sdkKey = _config.sdkKey;
    switch (_config.authHeaderMode) {
      case UlinqAuthHeaderMode.authorization:
        return <String, String>{'Authorization': 'Bearer $sdkKey'};
      case UlinqAuthHeaderMode.xSdkKey:
        return <String, String>{'X-SDK-Key': sdkKey};
      case UlinqAuthHeaderMode.both:
        return <String, String>{
          'Authorization': 'Bearer $sdkKey',
          'X-SDK-Key': sdkKey,
        };
    }
  }

  Future<Map<String, dynamic>> getJson(String path,
      {Map<String, dynamic>? query}) async {
    final response = await _requestWithRetry(
      () => _dio.get<dynamic>(path,
          queryParameters: query, options: Options(headers: _authHeaders())),
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    throw UlinqInvalidResponseException('Expected JSON object response');
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final headers = <String, String>{
      ..._authHeaders(),
      'Content-Type': 'application/json',
    };
    final response = await _requestWithRetry(
      () => _dio.post<dynamic>(path,
          data: body, options: Options(headers: headers)),
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return <String, dynamic>{};
  }

  Future<Response<dynamic>> _requestWithRetry(
      Future<Response<dynamic>> Function() send) async {
    try {
      return await send();
    } on DioException catch (e) {
      final retryable = _isRetryable(e);
      if (!retryable) {
        throw _mapError(e);
      }

      final jitterMs = 100 + _random.nextInt(150);
      await Future<void>.delayed(Duration(milliseconds: jitterMs));

      try {
        return await send();
      } on DioException catch (second) {
        throw _mapError(second);
      }
    }
  }

  bool _isRetryable(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) {
      if (status >= 500) return true;
      return false;
    }

    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
  }

  UlinqException _mapError(DioException e) {
    final status = e.response?.statusCode;
    final requestId = _extractRequestId(e.response?.data);
    final message =
        _extractMessage(e.response?.data) ?? e.message ?? 'Network error';

    if (_config.enableLogging) {
      _logger.warn(
          'Ulinq request failed: status=${status ?? 'n/a'}, message=$message');
    }

    if (status == 401 || status == 403) {
      return UlinqAuthException(message,
          cause: e, statusCode: status, requestId: requestId);
    }

    if (status == 429) {
      final waitSeconds =
          _parseRetryAfter(e.response?.headers.map['retry-after']?.first);
      return UlinqRateLimitException(
        message,
        waitSeconds: waitSeconds,
        cause: e,
        statusCode: status,
        requestId: requestId,
      );
    }

    if (status != null && status >= 400 && status < 500) {
      return UlinqInvalidResponseException(
        message,
        cause: e,
        statusCode: status,
        requestId: requestId,
      );
    }

    return UlinqNetworkException(
      message,
      cause: e,
      statusCode: status,
      requestId: requestId,
    );
  }

  String? _extractMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return null;
  }

  String? _extractRequestId(dynamic data) {
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        final id = error['request_id'];
        if (id is String && id.trim().isNotEmpty) return id.trim();
      }
      final id = data['request_id'];
      if (id is String && id.trim().isNotEmpty) return id.trim();
    }
    return null;
  }

  int? _parseRetryAfter(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return int.tryParse(raw.trim());
  }
}
