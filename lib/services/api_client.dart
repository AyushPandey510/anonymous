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
  final http.Client _client = http.Client();
  String? accessToken;
  String? refreshToken;
  _PendingRequest? _lastRequest;

  ApiClient(this.baseUrl);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Future<Map<String, dynamic>> get(String path) async {
    _lastRequest = _PendingRequest('GET', path, null);
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
    );
    return _handleResponse(response);
  }

  Future<List<dynamic>> getList(String path) async {
    _lastRequest = _PendingRequest('GET', path, null);
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw ApiException.fromResponse(response);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    _lastRequest = _PendingRequest('POST', path, body);
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode == 401 && refreshToken != null) {
      final refreshed = await _tryRefresh();
      if (refreshed && _lastRequest != null) {
        final req = _lastRequest!;
        if (req.method == 'POST') {
          final retry = await _client.post(
            Uri.parse('$baseUrl${req.path}'),
            headers: _headers,
            body: req.body != null ? jsonEncode(req.body) : null,
          );
          if (retry.statusCode >= 200 && retry.statusCode < 300) {
            return jsonDecode(retry.body) as Map<String, dynamic>;
          }
        } else {
          final retry = await _client.get(
            Uri.parse('$baseUrl${req.path}'),
            headers: _headers,
          );
          if (retry.statusCode >= 200 && retry.statusCode < 300) {
            return jsonDecode(retry.body) as Map<String, dynamic>;
          }
        }
      }
    }

    throw ApiException.fromResponse(response);
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
