import 'dart:convert';
import 'package:http/http.dart' as http;

class _PendingRequest {
  final String method;
  final String path;
  final Map<String, dynamic>? body;
  _PendingRequest(this.method, this.path, this.body);
}

class ApiClient {
  final String baseUrl;
  final http.Client _client;
  String? accessToken;
  String? refreshToken;
  _PendingRequest? _lastRequest;

  ApiClient(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Future<Map<String, dynamic>> get(String path) async {
    final response = await _send('GET', path, null);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getList(String path) async {
    final response = await _send('GET', path, null);
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _send('POST', path, body);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    _lastRequest = _PendingRequest(method, path, body);
    var response = await _do(method, path, body);

    if (response.statusCode == 401 && refreshToken != null) {
      if (await _tryRefresh() && _lastRequest != null) {
        final req = _lastRequest!;
        response = await _do(req.method, req.path, req.body);
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw ApiException.fromResponse(response);
  }

  Future<http.Response> _do(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: _headers);
      case 'POST':
        return _client.post(
          uri,
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        );
      default:
        throw ArgumentError('Unsupported method: $method');
    }
  }

  Future<bool> _tryRefresh() async {
    if (refreshToken == null) return false;
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        accessToken = data['access_token'] as String;
        refreshToken = data['refresh_token'] as String;
        return true;
      }
    } catch (_) {}
    return false;
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  factory ApiException.fromResponse(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      return ApiException(
        response.statusCode,
        body['error'] as String? ?? 'Unknown error',
      );
    } catch (_) {
      return ApiException(response.statusCode, 'Request failed');
    }
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
