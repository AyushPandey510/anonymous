import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'api_client.dart';

class AuthService {
  static const _keyDeviceId = 'device_id';
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyUserId = 'user_id';

  final ApiClient client;
  final FlutterSecureStorage _secureStorage;

  AuthService(this.client, {FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  String? _deviceId;
  String? _userId;
  String? lastError;

  String? get userId => _userId;
  bool get isLoggedIn => _deviceId != null;

  Future<void> init() async {
    client.onTokensChanged = _saveTokens;
    await _migrateLegacyAuthPrefs();

    _deviceId = await _secureStorage.read(key: _keyDeviceId);
    final accessToken = await _secureStorage.read(key: _keyAccessToken);
    final refreshToken = await _secureStorage.read(key: _keyRefreshToken);
    _userId = await _secureStorage.read(key: _keyUserId);

    if (accessToken != null) {
      client.accessToken = accessToken;
    }
    if (refreshToken != null) {
      client.refreshToken = refreshToken;
    }
  }

  Future<bool> ensureLoggedIn() async {
    if (_deviceId != null && client.accessToken != null) {
      debugPrint('[Space Auth] Found existing session.');
      if (client.refreshToken != null && await client.refreshSession()) {
        debugPrint('[Space Auth] Existing session refreshed.');
        return true;
      }

      debugPrint('[Space Auth] Existing session expired. Registering again.');
      await _clearTokens();
    }

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await _secureStorage.write(key: _keyDeviceId, value: _deviceId);
    }

    try {
      debugPrint('[Space Auth] Registering anonymous device with backend.');
      final response = await client.post(
        '/auth/register',
        body: {'device_id': _deviceId},
      );

      client.accessToken = response['access_token'] as String;
      client.refreshToken = response['refresh_token'] as String;
      _userId = response['user_id'] as String;

      await _saveTokens(client.accessToken!, client.refreshToken!);
      await _secureStorage.write(key: _keyUserId, value: _userId);

      lastError = null;
      debugPrint('[Space Auth] Device authenticated successfully.');
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('[Space Auth] Registration failed: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await _clearTokens();
  }

  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    await _secureStorage.write(key: _keyAccessToken, value: accessToken);
    await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
  }

  Future<void> _clearTokens() async {
    client.accessToken = null;
    client.refreshToken = null;
    await _secureStorage.delete(key: _keyAccessToken);
    await _secureStorage.delete(key: _keyRefreshToken);
  }

  Future<void> _migrateLegacyAuthPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // Older builds used SharedPreferences. Move secrets once, then remove them.
    await _copyLegacyValueToSecureStorage(prefs, _keyDeviceId);
    await _copyLegacyValueToSecureStorage(prefs, _keyAccessToken);
    await _copyLegacyValueToSecureStorage(prefs, _keyRefreshToken);
    await _copyLegacyValueToSecureStorage(prefs, _keyUserId);
  }

  Future<void> _copyLegacyValueToSecureStorage(
    SharedPreferences prefs,
    String key,
  ) async {
    final existingSecureValue = await _secureStorage.read(key: key);
    final legacyValue = prefs.getString(key);

    if (existingSecureValue == null && legacyValue != null) {
      await _secureStorage.write(key: key, value: legacyValue);
    }
    if (legacyValue != null) {
      await prefs.remove(key);
    }
  }
}
