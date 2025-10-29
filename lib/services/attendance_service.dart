import 'package:dio/dio.dart';
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
    final employeeName = await _getEmployeeNameByEmail(email);
    if (employeeName == null) {
      return {
        'success': false,
        'message': 'Employee not found for email $email',
      };
    }
    final logType = await _getNextLogType(employeeName);

    final nowIso = DateTime.now().toIso8601String();
    try {
      final resp = await ApiClient.post('/api/resource/Employee%20Checkin', data: {
        'employee': employeeName,
        'log_type': logType,
        'time': nowIso,
      });

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return {
          'success': true,
          'message': 'Attendance $logType recorded',
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


