import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppSecureStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _keyApiBaseUrl = 'api_base_url';
  static const String _keyApiKey = 'api_key';
  static const String _keyApiSecret = 'api_secret';

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
    if (baseUrl == null || key == null || secret == null) return null;
    return {
      'apiBaseUrl': baseUrl,
      'apiKey': key,
      'apiSecret': secret,
    };
  }

  static Future<void> clearCredentials() async {
    await _storage.delete(key: _keyApiBaseUrl);
    await _storage.delete(key: _keyApiKey);
    await _storage.delete(key: _keyApiSecret);
  }
}


