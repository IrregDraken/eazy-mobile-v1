enum ApiErrorKind { network, timeout, unauthorized, forbidden, validation, conflict, rateLimited, provider, server, unknown }

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.kind = ApiErrorKind.unknown});
  final String message;
  final int? statusCode;
  final ApiErrorKind kind;
  @override
  String toString() => message;
}
