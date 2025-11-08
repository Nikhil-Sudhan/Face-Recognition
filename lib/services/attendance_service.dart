import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AttendanceService {
  static Future<String?> _getEmployeeNameByEmail(String email) async {
    // Try company_email first
    final fields = '["name","company_email","personal_email"]';
    final filtersCompany = '[["company_email","=","$email"]]';
    final filtersPersonal = '[["personal_email","=","$email"]]';

    Response resp = await ApiClient.get('/api/resource/Employee', query: {
      'fields': fields,
      'filters': filtersCompany,
      'limit': 1,
    });
    if (resp.statusCode == 200 && resp.data is Map &&
        (resp.data['data'] as List).isNotEmpty) {
      return (resp.data['data'][0]['name'] as String);
    }

    resp = await ApiClient.get('/api/resource/Employee', query: {
      'fields': fields,
      'filters': filtersPersonal,
      'limit': 1,
    });
    if (resp.statusCode == 200 && resp.data is Map &&
        (resp.data['data'] as List).isNotEmpty) {
      return (resp.data['data'][0]['name'] as String);
    }
    return null;
  }

  static Future<String> _getNextLogType(String employeeName) async {
    // Query last checkin for employee
    final filters = '[["employee","=","$employeeName"]]';
    final orderBy = 'time desc';
    final fields = '["log_type","time"]';
    final resp = await ApiClient.get('/api/resource/Employee%20Checkin', query: {
      'fields': fields,
      'filters': filters,
      'order_by': orderBy,
      'limit': 1,
    });
    if (resp.statusCode == 200 && resp.data is Map) {
      final list = (resp.data['data'] as List);
      if (list.isNotEmpty) {
        final last = list.first;
        final lastType = (last['log_type'] as String?)?.toUpperCase();
        if (lastType == 'IN') return 'OUT';
      }
    }
    return 'IN';
  }

  static Future<Map<String, dynamic>> checkinByEmail(String email) async {
    // Get device type setting
    final prefs = await SharedPreferences.getInstance();
    final deviceType = prefs.getString('device_type') ?? 'BOTH';
    
    final employeeName = await _getEmployeeNameByEmail(email);
    if (employeeName == null) {
      return {
        'success': false,
        'message': 'Employee not found for email $email',
      };
    }
    
    // Determine log type based on device type
    String? logType;
    if (deviceType == 'IN') {
      logType = 'IN';
    } else if (deviceType == 'OUT') {
      logType = 'OUT';
    } else {
      // BOTH - auto toggle based on last checkin (empty string as per ERPNext)
      logType = await _getNextLogType(employeeName);
    }

    final nowIso = DateTime.now().toIso8601String();
    try {
      final data = {
        'employee': employeeName,
        'time': nowIso,
      };
      
      // Only add log_type if device is IN or OUT, empty for BOTH
      if (deviceType != 'BOTH') {
        data['log_type'] = logType;
      }
      
      final resp = await ApiClient.post('/api/resource/Employee%20Checkin', data: data);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return {
          'success': true,
          'message': 'Attendance ${deviceType == "BOTH" ? logType : deviceType} recorded',
          'employee': employeeName,
          'log_type': logType,
          'time': nowIso,
        };
      }
      return {
        'success': false,
        'message': 'Unexpected status code',
      };
    } on DioException catch (_) {
      return {
        'success': false,
        'message': 'Network error. Will retry when online',
      };
    }

  }
}


