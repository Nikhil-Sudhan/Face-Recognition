import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static const String _baseUrl = 'https://demo.c9infotech.com/api/method';
  static const String _loginEndpoint = '$_baseUrl/cmenu.api.hr_login';

  // Login API call
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse(_loginEndpoint),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // Store login response in local storage
        await _storeLoginData(response.body, email);

        return {
          'success': true,
          'data': responseData,
          'message': 'Login successful'
        };
      } else {
        return {
          'success': false,
          'message': 'Login failed: ${response.statusCode}',
          'statusCode': response.statusCode
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Store login data in local storage
  static Future<void> _storeLoginData(
      String loginResponse, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('login_response', loginResponse);
      await prefs.setString('user_email', email);
      await prefs.setBool('is_logged_in', true);
    } catch (e) {
      if (kDebugMode) {
        print('Error storing login data: $e');
      }
    }
  }

  // Get stored login data
  static Future<Map<String, dynamic>?> getStoredLoginData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginResponse = prefs.getString('login_response');
      final userEmail = prefs.getString('user_email');
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      if (loginResponse != null && userEmail != null && isLoggedIn) {
        return {
          'login_response': json.decode(loginResponse),
          'user_email': userEmail,
          'is_logged_in': isLoggedIn,
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting stored login data: $e');
      }
    }
    return null;
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('is_logged_in') ?? false;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking login status: $e');
      }
      return false;
    }
  }

  // Logout - clear stored data
  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('login_response');
      await prefs.remove('user_email');
      await prefs.setBool('is_logged_in', false);
    } catch (e) {
      if (kDebugMode) {
        print('Error during logout: $e');
      }
    }
  }
}
