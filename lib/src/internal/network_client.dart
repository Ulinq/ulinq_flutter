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
    final headers = _authHeaders();
    final response = await _requestWithRetry(
      method: 'GET',
      path: path,
      query: query,
      headers: headers,
      send: () => _dio.get<dynamic>(path,
          queryParameters: query, options: Options(headers: headers)),
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
      method: 'POST',
      path: path,
      body: body,
      headers: headers,
      send: () => _dio.post<dynamic>(path,
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

  Future<Response<dynamic>> _requestWithRetry({
    required String method,
    required String path,
    required Future<Response<dynamic>> Function() send,
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final startedAt = DateTime.now();
    _logRequest(
      method: method,
      path: path,
      query: query,
      body: body,
      headers: headers,
      attempt: 1,
    );
    try {
      final response = await send();
      _logSuccess(
        method: method,
        path: path,
        response: response,
        startedAt: startedAt,
        attempt: 1,
      );
      return response;
    } on DioException catch (e) {
      final retryable = _isRetryable(e);
      _logFailure(
        method: method,
        path: path,
        error: e,
        startedAt: startedAt,
        attempt: 1,
        willRetry: retryable,
      );
      if (!retryable) {
        throw _mapError(e);
      }

      final jitterMs = 100 + _random.nextInt(150);
      await Future<void>.delayed(Duration(milliseconds: jitterMs));

      _logRequest(
        method: method,
        path: path,
        query: query,
        body: body,
        headers: headers,
        attempt: 2,
      );
      try {
        final response = await send();
        _logSuccess(
          method: method,
          path: path,
          response: response,
          startedAt: startedAt,
          attempt: 2,
        );
        return response;
      } on DioException catch (second) {
        _logFailure(
          method: method,
          path: path,
          error: second,
          startedAt: startedAt,
          attempt: 2,
          willRetry: false,
        );
        throw _mapError(second);
      }
    }
  }

  void _logRequest({
    required String method,
    required String path,
    required int attempt,
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    if (!_config.enableLogging) return;
    _logger.debug(
      'HTTP request[$attempt] method=$method '
      'url=${_fullUrl(path)} '
      'auth=${_config.authHeaderMode.name} '
      'headers=${_formatJson(_sanitizeHeaders(headers))} '
      'query=${_formatJson(query)} '
      'body=${_formatJson(body)}',
    );
  }

  void _logSuccess({
    required String method,
    required String path,
    required Response<dynamic> response,
    required DateTime startedAt,
    required int attempt,
  }) {
    if (!_config.enableLogging) return;
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    _logger.debug(
      'HTTP success[$attempt] method=$method '
      'url=${_fullUrl(path)} '
      'status=${response.statusCode ?? 'n/a'} '
      'duration_ms=$elapsedMs '
      'response=${_formatJson(response.data)}',
    );
  }

  void _logFailure({
    required String method,
    required String path,
    required DioException error,
    required DateTime startedAt,
    required int attempt,
    required bool willRetry,
  }) {
    if (!_config.enableLogging) return;
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    _logger.warn(
      'HTTP failure[$attempt] method=$method '
      'url=${_fullUrl(path)} '
      'status=${error.response?.statusCode ?? 'n/a'} '
      'type=${error.type.name} '
      'retry=${willRetry ? 'yes' : 'no'} '
      'duration_ms=$elapsedMs '
      'message=${error.message ?? 'n/a'} '
      'response=${_formatJson(error.response?.data)}',
    );
  }

  String _fullUrl(String path) => _dio.options.baseUrl + path;

  Map<String, String> _sanitizeHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return const <String, String>{};
    return headers.map((key, value) {
      final lowerKey = key.toLowerCase();
      if (lowerKey == 'authorization') {
        return MapEntry<String, String>(key, _maskBearer(value));
      }
      if (lowerKey == 'x-sdk-key') {
        return MapEntry<String, String>(key, _maskValue(value));
      }
      return MapEntry<String, String>(key, value);
    });
  }

  String _maskBearer(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('Bearer ')) return _maskValue(trimmed);
    final token = trimmed.substring(7);
    return 'Bearer ${_maskValue(token)}';
  }

  String _maskValue(String value) {
    if (value.length <= 6) return '***';
    return '${value.substring(0, 3)}***${value.substring(value.length - 3)}';
  }

  String _formatJson(Object? value) {
    if (value == null) return 'null';
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
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
