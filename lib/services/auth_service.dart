import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  // Simple local login: username = 'root', password = 'root'
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    try {
      if (username.trim() == 'root' && password == 'root') {
        await _storeLoginData(username);
        return {
          'success': true,
          'data': {'user': username},
          'message': 'Login successful'
        };
      }

      return {'success': false, 'message': 'Invalid username or password'};
    } catch (e) {
      return {'success': false, 'message': 'Error: $e'};
    }
  }

  // Store login data in local storage
  static Future<void> _storeLoginData(String username) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', username);
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
      final userName = prefs.getString('user_name');
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      if (userName != null && isLoggedIn) {
        return {
          'user_name': userName,
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
      await prefs.remove('user_name');
      await prefs.setBool('is_logged_in', false);
    } catch (e) {
      if (kDebugMode) {
        print('Error during logout: $e');
      }
    }
  }
}
