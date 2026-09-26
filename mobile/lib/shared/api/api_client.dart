import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/error/app_exception.dart';
import 'token_storage.dart';

/// Thin wrapper around the backend's HTTP API. Attaches the access token
/// automatically for authenticated calls, and transparently retries
/// EXACTLY ONCE after a silent refresh on a 401 -- never loops, so a
/// genuinely dead session (refresh also rejected) surfaces as a real
/// error the caller can react to (e.g. route back to login), rather than
/// hanging.
class ApiClient {
  ApiClient({http.Client? httpClient, TokenStorage? tokenStorage})
      : _http = httpClient ?? http.Client(),
        _tokenStorage = tokenStorage ?? TokenStorage();

  final http.Client _http;
  final TokenStorage _tokenStorage;

  // Backend applies a global 'v1' prefix to every route except its bare
  // root health check (main.ts's setGlobalPrefix) -- prepended once here
  // so no call site (auth, profile, discovery, etc.) needs to know about
  // versioning individually.
  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}/v1$path');

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic> body = const {},
    bool authenticated = false,
  }) async {
    final response = await _send('POST', path, body, authenticated);
    return _decode(response);
  }

  Future<Map<String, dynamic>> get(String path, {bool authenticated = true}) async {
    final response = await _send('GET', path, null, authenticated);
    return _decode(response);
  }

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
    bool authenticated,
  ) async {
    final uri = _uri(path);
    var headers = await _headers(authenticated);
    var response = await _request(method, uri, headers, body);

    if (response.statusCode == 401 && authenticated) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        headers = await _headers(authenticated);
        response = await _request(method, uri, headers, body);
      }
    }
    return response;
  }

  Future<http.Response> _request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic>? body,
  ) {
    if (method == 'GET') return _http.get(uri, headers: headers);
    return _http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
  }

  Future<Map<String, String>> _headers(bool authenticated) async {
    final headers = {'Content-Type': 'application/json'};
    if (authenticated) {
      final token = await _tokenStorage.readAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await _http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _tokenStorage.clear();
        return false;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _tokenStorage.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Map<String, dynamic> body =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    // Nest's ValidationPipe returns `message` as a single string OR an
    // array of strings (one per failed validator) depending on the error.
    final rawMessage = body['message'];
    final message = rawMessage is List ? rawMessage.join(', ') : rawMessage?.toString() ?? 'Request failed';
    throw AppException(message, statusCode: response.statusCode);
  }
}
