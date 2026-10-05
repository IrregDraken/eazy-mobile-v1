import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const defaultBaseUrl = 'https://eazy-mobile-v2-production.up.railway.app/v1';
  final http.Client _client;
  final FlutterSecureStorage _storage;

  String get baseUrl => const String.fromEnvironment('EAZY_API_URL', defaultValue: defaultBaseUrl);

  Future<Map<String, dynamic>> get(String path, {bool auth = false, Map<String, String>? headers}) =>
      _send('GET', path, auth: auth, headers: headers);
  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, bool auth = false, Map<String, String>? headers}) =>
      _send('POST', path, body: body, auth: auth, headers: headers);
  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body, bool auth = false, Map<String, String>? headers}) =>
      _send('PATCH', path, body: body, auth: auth, headers: headers);
  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body, bool auth = false, Map<String, String>? headers}) =>
      _send('PUT', path, body: body, auth: auth, headers: headers);
  Future<Map<String, dynamic>> delete(String path, {bool auth = false, Map<String, String>? headers}) =>
      _send('DELETE', path, auth: auth, headers: headers);

  Future<void> saveToken(String token) => _storage.write(key: 'eazy.accessToken', value: token);
  Future<String?> readToken() => _storage.read(key: 'eazy.accessToken');
  Future<void> clearToken() => _storage.delete(key: 'eazy.accessToken');

  Future<Map<String, dynamic>> _send(String method, String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(baseUrl + (path.startsWith('/') ? path : '/$path'));
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...?headers,
    };

    if (auth) {
      final token = await readToken();
      if (token == null || token.isEmpty) {
        throw const ApiException('Sign in is required.', statusCode: 401, kind: ApiErrorKind.unauthorized);
      }
      requestHeaders['Authorization'] = 'Bearer $token';
    }

    try {
      final request = http.Request(method, uri)..headers.addAll(requestHeaders);
      if (body != null) request.body = jsonEncode(body);
      final response = await _client.send(request).timeout(const Duration(seconds: 20)).then(http.Response.fromStream);
      dynamic decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) {
          final data = decoded['data'];
          if (data is Map<String, dynamic>) return data;
          if (data is List) return {'items': data};
          if (data == null) return decoded;
          return {'value': data};
        }
        return {'value': decoded};
      }
      throw _mapError(response.statusCode, decoded);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('Eazy is taking too long to respond. Check your connection and try again.', kind: ApiErrorKind.timeout);
    } on http.ClientException {
      throw const ApiException('We could not reach Eazy right now. Check your internet connection and try again.', kind: ApiErrorKind.network);
    } on FormatException {
      throw const ApiException('Eazy returned an unexpected response. Please try again.', kind: ApiErrorKind.server);
    }
  }

  ApiException _mapError(int status, dynamic decoded) {
    String? message;
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      message = error is Map<String, dynamic> ? error['message']?.toString() : decoded['message']?.toString();
    }
    final friendly = switch (status) {
      400 || 422 => message ?? 'Please check the information and try again.',
      401 => message ?? 'Your session has expired. Please sign in again.',
      403 => message ?? 'You do not have permission to do that.',
      404 => message ?? 'That Eazy resource could not be found.',
      409 => message ?? 'That action conflicts with an existing Eazy record.',
      429 => message ?? 'Too many attempts. Please wait a moment and try again.',
      503 => message ?? 'This Eazy provider is temporarily unavailable.',
      >= 500 => message ?? 'Eazy is having trouble right now. Please try again shortly.',
      _ => message ?? 'Something went wrong. Please try again.',
    };
    final kind = switch (status) {
      400 || 422 => ApiErrorKind.validation,
      401 => ApiErrorKind.unauthorized,
      403 => ApiErrorKind.forbidden,
      409 => ApiErrorKind.conflict,
      429 => ApiErrorKind.rateLimited,
      503 => ApiErrorKind.provider,
      >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.unknown,
    };
    return ApiException(friendly, statusCode: status, kind: kind);
  }
}
