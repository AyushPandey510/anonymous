import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';

class AuthService {
  static const _keyDeviceId = 'device_id';
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserId = 'user_id';

  final ApiClient client;

  AuthService(this.client);

  String? _deviceId;
  String? _userId;
  String? lastError;

  String? get userId => _userId;
  bool get isLoggedIn => _deviceId != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_keyDeviceId);
    final accessToken = prefs.getString(_keyAccessToken);
    final refreshToken = prefs.getString(_keyRefreshToken);
    _userId = prefs.getString(_keyUserId);

    if (accessToken != null) {
      client.accessToken = accessToken;
    }
    if (refreshToken != null) {
      client.refreshToken = refreshToken;
    }
  }

  Future<bool> ensureLoggedIn() async {
    if (_deviceId != null && client.accessToken != null) {
      debugPrint('[Space Auth] Found existing session for device: $_deviceId');
      return true;
    }

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDeviceId, _deviceId!);
    }

    try {
      debugPrint('[Space Auth] Registering device $_deviceId with backend: ${client.baseUrl} ...');
      final response = await client.post('/auth/register', body: {
        'device_id': _deviceId,
        'device_name': _deviceName(),
      });

      client.accessToken = response['access_token'] as String;
      client.refreshToken = response['refresh_token'] as String;
      _userId = response['user_id'] as String;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccessToken, client.accessToken!);
      await prefs.setString(_keyRefreshToken, client.refreshToken!);
      await prefs.setString(_keyUserId, _userId!);

      lastError = null;
      debugPrint('[Space Auth] ✅ Device authenticated successfully as user: $_userId');
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('[Space Auth] ❌ Registration failed: $e');
      return false;
    }
  }

  Future<void> logout() async {
    client.accessToken = null;
    client.refreshToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
  }

  String _deviceName() {
    try {
      return 'Space-${_deviceId?.substring(0, 8) ?? "User"}';
    } catch (_) {
      return 'Space-User';
    }
  }
}
