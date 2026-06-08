import 'dart:math';

class ApiError implements Exception {
  final int statusCode;
  final String message;
  final String? body;
  final Map<String, String> headers;

  const ApiError({
    required this.statusCode,
    required this.message,
    this.body,
    this.headers = const {},
  });

  factory ApiError.fromResponse(int statusCode, String body, {Map<String, String> headers = const {}}) {
    final msg = 'HTTP $statusCode: $body';
    return switch (statusCode) {
      400 => BadRequestError(message: msg, body: body, headers: headers),
      401 => AuthenticationError(message: msg, body: body, headers: headers),
      403 => PermissionDeniedError(message: msg, body: body, headers: headers),
      404 => NotFoundError(message: msg, body: body, headers: headers),
      408 => RequestTimeoutError(message: msg, body: body, headers: headers),
      409 => ConflictError(message: msg, body: body, headers: headers),
      422 => UnprocessableEntityError(message: msg, body: body, headers: headers),
      429 => RateLimitError(message: msg, body: body, headers: headers),
      _ when statusCode >= 500 => ServerError(statusCode: statusCode, message: msg, body: body, headers: headers),
      _ => ApiError(statusCode: statusCode, message: msg, body: body, headers: headers),
    };
  }

  bool get isRetryable {
    final shouldRetry = headers['x-should-retry'];
    if (shouldRetry == 'true') return true;
    if (shouldRetry == 'false') return false;
    return statusCode == 408 || statusCode == 409 || statusCode == 429 || statusCode >= 500;
  }

  Duration? get retryAfter {
    final ms = headers['retry-after-ms'];
    if (ms != null) {
      final parsed = int.tryParse(ms);
      if (parsed != null) return Duration(milliseconds: min(parsed, 60000));
    }
    final secs = headers['retry-after'];
    if (secs != null) {
      final parsed = int.tryParse(secs);
      if (parsed != null) return Duration(seconds: min(parsed, 60));
    }
    return null;
  }

  @override
  String toString() => message;
}

class BadRequestError extends ApiError {
  const BadRequestError({required super.message, super.body, super.headers}) : super(statusCode: 400);
}

class AuthenticationError extends ApiError {
  const AuthenticationError({required super.message, super.body, super.headers}) : super(statusCode: 401);
}

class PermissionDeniedError extends ApiError {
  const PermissionDeniedError({required super.message, super.body, super.headers}) : super(statusCode: 403);
}

class NotFoundError extends ApiError {
  const NotFoundError({required super.message, super.body, super.headers}) : super(statusCode: 404);
}

class RequestTimeoutError extends ApiError {
  const RequestTimeoutError({required super.message, super.body, super.headers}) : super(statusCode: 408);
}

class ConflictError extends ApiError {
  const ConflictError({required super.message, super.body, super.headers}) : super(statusCode: 409);
}

class UnprocessableEntityError extends ApiError {
  const UnprocessableEntityError({required super.message, super.body, super.headers}) : super(statusCode: 422);
}

class RateLimitError extends ApiError {
  const RateLimitError({required super.message, super.body, super.headers}) : super(statusCode: 429);
}

class ServerError extends ApiError {
  const ServerError({super.statusCode = 500, required super.message, super.body, super.headers});
}

class ApiConnectionError extends ApiError {
  const ApiConnectionError({required super.message}) : super(statusCode: 0);

  @override
  bool get isRetryable => true;
}

class ApiTimeoutError extends ApiError {
  const ApiTimeoutError({required super.message}) : super(statusCode: 0);

  @override
  bool get isRetryable => true;
}
