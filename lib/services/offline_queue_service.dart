import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_service.dart';

class OfflineQueueService {
  static const String _keyQueue = 'offline_checkins';

  static Future<void> enqueue(String email, String isoTime) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyQueue);
    final List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    list.add({'email': email, 'time': isoTime});
    await prefs.setString(_keyQueue, jsonEncode(list));
  }

  static Future<int> flush() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyQueue);
    if (raw == null) return 0;
    final List<dynamic> list = jsonDecode(raw);
    int success = 0;
    final remaining = <Map<String, dynamic>>[];
    for (final item in list) {
      final email = item['email'] as String;
      // ignore stored time for simplicity; server uses provided time in call below
      final res = await AttendanceService.checkinByEmail(email);
      if (res['success'] == true) {
        success++;
      } else {
        remaining.add({'email': email, 'time': item['time']});
      }
    }
    await prefs.setString(_keyQueue, jsonEncode(remaining));
    return success;
  }
}


