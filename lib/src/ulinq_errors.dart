class UlinqException implements Exception {
  UlinqException(this.message, {this.cause, this.statusCode, this.requestId});

  final String message;
  final Object? cause;
  final int? statusCode;
  final String? requestId;

  @override
  String toString() =>
      'UlinqException(message: $message, statusCode: $statusCode, requestId: $requestId)';
}

class UlinqAuthException extends UlinqException {
  UlinqAuthException(super.message,
      {super.cause, super.statusCode, super.requestId});
}

class UlinqNetworkException extends UlinqException {
  UlinqNetworkException(super.message,
      {super.cause, super.statusCode, super.requestId});
}

class UlinqRateLimitException extends UlinqException {
  UlinqRateLimitException(
    super.message, {
    required this.waitSeconds,
    super.cause,
    super.statusCode,
    super.requestId,
  });

  final int? waitSeconds;
}

class UlinqInvalidResponseException extends UlinqException {
  UlinqInvalidResponseException(super.message,
      {super.cause, super.statusCode, super.requestId});
}
