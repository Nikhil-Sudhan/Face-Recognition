import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSecureStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _keyApiBaseUrl = 'api_base_url';
  static const String _keyApiKey = 'api_key';
  static const String _keyApiSecret = 'api_secret';
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserPassword = 'user_password';

  static Future<void> saveCredentials({
    required String apiBaseUrl,
    required String apiKey,
    required String apiSecret,
  }) async {
    await _storage.write(key: _keyApiBaseUrl, value: apiBaseUrl.trim());
    await _storage.write(key: _keyApiKey, value: apiKey.trim());
    await _storage.write(key: _keyApiSecret, value: apiSecret);
  }

  static Future<Map<String, String>?> readCredentials() async {
    final baseUrl = await _storage.read(key: _keyApiBaseUrl);
    final key = await _storage.read(key: _keyApiKey);
    final secret = await _storage.read(key: _keyApiSecret);
    if (baseUrl == null) return null;
    return {
      'apiBaseUrl': baseUrl,
      'apiKey': key ?? '',
      'apiSecret': secret ?? '',
    };
  }

  static Future<void> saveUserCredentials({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _keyUserEmail, value: email);
    await _storage.write(key: _keyUserPassword, value: password);
  }

  static Future<Map<String, String>?> readUserCredentials() async {
    final email = await _storage.read(key: _keyUserEmail);
    final password = await _storage.read(key: _keyUserPassword);
    if (email == null || password == null) return null;
    return {
      'email': email,
      'password': password,
    };
  }

  static Future<void> clearCredentials() async {
    await _storage.delete(key: _keyApiBaseUrl);
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyApiSecret);
    await _storage.delete(key: _keyUserEmail);
    await _storage.delete(key: _keyUserPassword);
  }
}
