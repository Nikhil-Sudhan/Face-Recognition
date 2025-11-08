import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Service for managing MPIN authentication
class MpinService {
  static const String _mpinKey = 'user_mpin_hash';
  static const String _mpinSetKey = 'mpin_is_set';

  /// Check if MPIN is set
  static Future<bool> isMpinSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_mpinSetKey) ?? false;
  }

  /// Set/Create MPIN (hashed for security)
  static Future<bool> setMpin(String mpin) async {
    if (mpin.length != 4 || !_isNumeric(mpin)) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final hash = _hashMpin(mpin);
    
    await prefs.setString(_mpinKey, hash);
    await prefs.setBool(_mpinSetKey, true);
    
    return true;
  }

  /// Verify MPIN
  static Future<bool> verifyMpin(String mpin) async {
    final prefs = await SharedPreferences.getInstance();
    final storedHash = prefs.getString(_mpinKey);
    
    if (storedHash == null) {
      return false;
    }

    final inputHash = _hashMpin(mpin);
    return inputHash == storedHash;
  }

  /// Clear MPIN (for logout or reset)
  static Future<void> clearMpin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_mpinKey);
    await prefs.remove(_mpinSetKey);
  }

  /// Hash MPIN for secure storage
  static String _hashMpin(String mpin) {
    final bytes = utf8.encode(mpin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Check if string is numeric
  static bool _isNumeric(String str) {
    return RegExp(r'^[0-9]+$').hasMatch(str);
  }
}
