import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../storage/secure_storage.dart';

class ApiClient {
  ApiClient._();

  static Dio? _dio;
  static String? _baseUrl;
  static String? _apiKey;
  static String? _apiSecret;
  static bool _allowSelfSigned = false;
  static String? _sessionCookie; // e.g., 'sid=...'

  static Future<Dio> _getDio() async {
    if (_dio != null) return _dio!;

    final creds = await AppSecureStorage.readCredentials();
    if (creds == null) {
      throw StateError('API credentials not set');
    }
    _baseUrl = creds['apiBaseUrl'];
    _apiKey = creds['apiKey'];
    _apiSecret = creds['apiSecret'];

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if ((_apiKey ?? '').isNotEmpty) {
      headers['Authorization'] = 'token ${_apiKey!}:${_apiSecret!}';
    }
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      headers['Cookie'] = _sessionCookie!;
    }

    final dio = Dio(BaseOptions(
      baseUrl: _normalizeBaseUrl(_baseUrl!),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: headers,
    ));

    if (!kIsWeb) {
      final ioAdapter = dio.httpClientAdapter as IOHttpClientAdapter;
      ioAdapter.createHttpClient = () {
        final client = HttpClient();
        if (_allowSelfSigned) {
          client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        }
        return client;
      };
    }

    // Using in-memory cookie header above; persistence can be added later if needed

    _dio = dio;
    return dio;
  }

  static String _normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  static Future<void> setCredentials({
    required String baseUrl,
    required String apiKey,
    required String apiSecret,
  }) async {
    await AppSecureStorage.saveCredentials(
      apiBaseUrl: baseUrl,
      apiKey: apiKey,
      apiSecret: apiSecret,
    );
    _dio = null;
  }

  static void setAllowSelfSigned(bool allow) {
    _allowSelfSigned = allow;
    _dio = null; // rebuild with new adapter settings next call
  }

  // Session login using email/password; stores cookies in Dio.
  static Future<Response> sessionLogin({
    required String email,
    required String password,
  }) async {
    final dio = await _getDio();
    final resp = await dio.post(
      '/api/method/login',
      data: {
        'usr': email,
        'pwd': password,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    // Extract sid from Set-Cookie
    final setCookies = resp.headers.map['set-cookie'] ?? resp.headers.map['Set-Cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      final header = setCookies.join(',');
      final match = RegExp(r'(^|;)\s*sid=([^;]+)').firstMatch(header);
      if (match != null) {
        final sid = match.group(2);
        if (sid != null && sid.isNotEmpty) {
          _sessionCookie = 'sid=$sid';
          _dio = null; // rebuild with cookie header next call
        }
      }
    }
    return resp;
  }

  static Future<bool> verify() async {
    final dio = await _getDio();
    try {
      // simple GET to Employee with limit=1 to verify
      final resp = await dio.get('/api/resource/Employee', queryParameters: {
        'limit': 1,
      });
      return resp.statusCode == 200;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        return false;
      }
      rethrow;
    }
  }

  static Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final dio = await _getDio();
    return dio.get(path, queryParameters: query);
  }

  static Future<Response<dynamic>> post(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final dio = await _getDio();
    return dio.post(path, data: data);
  }
}


