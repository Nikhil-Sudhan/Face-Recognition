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
    
    // Add token authorization header if API key/secret available
    if ((_apiKey ?? '').isNotEmpty && (_apiSecret ?? '').isNotEmpty) {
      headers['Authorization'] = 'token $_apiKey:$_apiSecret';
      print('Using token auth: token $_apiKey:***');
    } else {
      print('Warning: No API credentials available');
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

    // Add response interceptor for debugging
    dio.interceptors.add(InterceptorsWrapper(
      onResponse: (response, handler) {
        print('API Response [${response.statusCode}] ${response.requestOptions.method} ${response.requestOptions.uri}');
        print('Response data: ${response.data}');
        handler.next(response);
      },
      onError: (error, handler) {
        print('API Error [${error.response?.statusCode}] ${error.requestOptions.method} ${error.requestOptions.uri}');
        print('Error message: ${error.message}');
        if (error.response?.data != null) {
          print('Error data: ${error.response?.data}');
        }
        handler.next(error);
      },
    ));

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
    print('Setting API credentials: baseUrl=$baseUrl, apiKey=$apiKey (secret hidden)');
    await AppSecureStorage.saveCredentials(
      apiBaseUrl: baseUrl,
      apiKey: apiKey,
      apiSecret: apiSecret,
    );
    _dio = null;
    print('Credentials saved, Dio instance reset');
  }

  static void setAllowSelfSigned(bool allow) {
    _allowSelfSigned = allow;
    _dio = null; // rebuild with new adapter settings next call
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

  static Future<Response<dynamic>> put(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    final dio = await _getDio();
    return dio.put(path, data: data);
  }
}

