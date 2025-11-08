import 'package:dio/dio.dart';
import 'api_client.dart';
import 'database_service.dart';
import '../models/employee.dart';
import '../storage/secure_storage.dart';

class ErpNextSyncService {
  /// Helper method to ensure we have valid API credentials
  static Future<bool> _ensureAuthentication() async {
    try {
      // Try to verify current credentials
      if (await ApiClient.verify()) {
        return true;
      }
    } catch (e) {
      // Credential verification failed
    }

    // Credentials invalid, try to re-authenticate
    try {
      final userCreds = await AppSecureStorage.readUserCredentials();
      final apiCreds = await AppSecureStorage.readCredentials();
      
      if (userCreds == null || apiCreds == null) {
        return false;
      }

      // Call HR login API to get fresh credentials
      final resp = await ApiClient.post(
        '/api/method/cmenu.api.hr_login',
        data: {
          'email': userCreds['email']!,
          'password': userCreds['password']!,
        },
      );

      if (resp.statusCode != 200) {
        return false;
      }

      // Extract user details from response
      final userDetails = resp.data['message'];
      if (userDetails == null) {
        return false;
      }
      
      final apiKey = userDetails['api_key'];
      final apiSecret = userDetails['api_secret'];
      
      if (apiKey == null || apiSecret == null) {
        return false;
      }
      
      // Update stored credentials
      await ApiClient.setCredentials(
        baseUrl: apiCreds['apiBaseUrl']!,
        apiKey: apiKey,
        apiSecret: apiSecret,
      );
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sync employees from ERPNext to local database
  static Future<Map<String, dynamic>> syncEmployees() async {
    try {
      // Ensure we have valid credentials before syncing
      if (!await _ensureAuthentication()) {
        return {
          'success': false,
          'message': 'Authentication failed. Please login again.',
        };
      }

      // Fetch all employees from ERPNext
      final response = await ApiClient.get(
        '/api/resource/Employee',
        query: {
          'fields': '["name","employee_name","status","department","company_email","personal_email","cell_number","employee","face_data"]',
          'limit_page_length': '0', // 0 means unlimited in ERPNext
        },
      );

      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'Failed to fetch employees from ERPNext',
        };
      }

      final data = response.data;
      if (data == null || data['data'] == null) {
        return {
          'success': false,
          'message': 'No data received from ERPNext',
        };
      }

      final List<dynamic> erpEmployees = data['data'];
      int syncedCount = 0;
      int updatedCount = 0;
      int errorCount = 0;
      List<String> errors = [];

      for (var erpEmp in erpEmployees) {
        try {
          // Map ERPNext fields to local Employee model
          final String? empIdStr = erpEmp['employee'] as String?;
          final String empName = erpEmp['employee_name'] ?? erpEmp['name'] ?? '';
          final String status = erpEmp['status'] ?? 'Active';
          final String? department = erpEmp['department'] as String?;
          final String? email = erpEmp['company_email'] ?? erpEmp['personal_email'];
          final String? phone = erpEmp['cell_number'] as String?;
          final String? faceData = erpEmp['face_data'] as String?;

          // Skip if no employee ID
          if (empIdStr == null || empIdStr.isEmpty) {
            errorCount++;
            errors.add('Employee ${empName} has no employee ID');
            continue;
          }

          // Convert employee ID to integer (extract numbers if it's like "HR-EMP-00001")
          int empId;
          try {
            // Try to extract numeric part from employee ID
            final numericPart = empIdStr.replaceAll(RegExp(r'[^0-9]'), '');
            empId = int.parse(numericPart.isEmpty ? '0' : numericPart);
            
            // If empId is 0 or extraction failed, use hash of the employee name
            if (empId == 0) {
              empId = empName.hashCode.abs() % 1000000;
            }
          } catch (e) {
            empId = empName.hashCode.abs() % 1000000;
          }

          // Check if employee already exists
          final existingEmployee = await DatabaseService.getEmployeeById(empId);

          final employee = Employee(
            id: existingEmployee?.id,
            empId: empId,
            name: empName,
            status: status,
            department: department,
            email: email,
            phone: phone,
            erpNextId: erpEmp['name'], // Store ERPNext document ID
            createdAt: existingEmployee?.createdAt ?? DateTime.now(),
            updatedAt: DateTime.now(),
            faceData: faceData?.isNotEmpty == true ? faceData : existingEmployee?.faceData, // Use ERPNext data if available, otherwise preserve local
          );

          if (existingEmployee != null) {
            // Update existing employee
            await DatabaseService.updateEmployee(employee);
            updatedCount++;
          } else {
            // Insert new employee
            await DatabaseService.insertEmployee(employee);
            syncedCount++;
          }
        } catch (e) {
          errorCount++;
          errors.add('Error syncing ${erpEmp['employee_name']}: $e');
        }
      }

      String message = 'Sync completed: $syncedCount new, $updatedCount updated';
      if (errorCount > 0) {
        message += ', $errorCount errors';
      }

      return {
        'success': true,
        'message': message,
        'synced': syncedCount,
        'updated': updatedCount,
        'errors': errorCount,
        'errorDetails': errors,
      };
    } on DioException catch (e) {
      String errorMessage = 'Network error during sync';
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        errorMessage = 'Authentication failed. Please login again.';
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Connection timeout. Check your internet connection.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = 'Connection error. Cannot reach ERPNext server.';
      }

      return {
        'success': false,
        'message': errorMessage,
        'error': e.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unexpected error during sync',
        'error': e.toString(),
      };
    }
  }

  /// Upload face data to ERPNext for a specific employee
  static Future<Map<String, dynamic>> uploadFaceData({
    required String email,
    required String faceData,
    String? erpNextId, // Optional: if provided, skip employee search
  }) async {
    try {
      // Ensure we have valid credentials before uploading
      if (!await _ensureAuthentication()) {
        return {
          'success': false,
          'message': 'Authentication failed. Please login again.',
        };
      }

      String employeeName;

      // If we have ERPNext ID, use it directly
      if (erpNextId != null && erpNextId.isNotEmpty) {
        employeeName = erpNextId;
      } else {
        // Otherwise, search for employee by email
        // Try company_email first
        var employeeResp = await ApiClient.get(
          '/api/resource/Employee',
          query: {
            'fields': '["name"]',
            'filters': '[["company_email","=","$email"]]',
            'limit': 1,
          },
        );

        // If not found, try personal_email
        if (employeeResp.data == null || 
            (employeeResp.data['data'] as List).isEmpty) {
          employeeResp = await ApiClient.get(
            '/api/resource/Employee',
            query: {
              'fields': '["name"]',
              'filters': '[["personal_email","=","$email"]]',
              'limit': 1,
            },
          );
        }

        if (employeeResp.statusCode != 200 || 
            employeeResp.data == null || 
            (employeeResp.data['data'] as List).isEmpty) {
          return {
            'success': false,
            'message': 'Employee not found in ERPNext for email: $email',
          };
        }

        employeeName = employeeResp.data['data'][0]['name'] as String;
      }

      // Update the employee with face data using direct API endpoint
      final updateResp = await ApiClient.put(
        '/api/resource/Employee/$employeeName',
        data: {
          'face_data': faceData,
        },
      );

      if (updateResp.statusCode == 200) {
        // Update local database with ERPNext ID if we found it via search
        if (erpNextId == null || erpNextId.isEmpty) {
          try {
            final localEmployee = await DatabaseService.getEmployeeByEmail(email);
            if (localEmployee != null && localEmployee.erpNextId == null) {
              final updatedEmployee = Employee(
                id: localEmployee.id,
                empId: localEmployee.empId,
                name: localEmployee.name,
                status: localEmployee.status,
                department: localEmployee.department,
                email: localEmployee.email,
                phone: localEmployee.phone,
                erpNextId: employeeName, // Store the found ERPNext ID
                createdAt: localEmployee.createdAt,
                updatedAt: DateTime.now(),
                faceData: localEmployee.faceData,
              );
              await DatabaseService.updateEmployee(updatedEmployee);
            }
          } catch (e) {
            // Failed to update local employee
          }
        }
        
        return {
          'success': true,
          'message': 'Face data uploaded successfully',
          'employee': employeeName,
        };
      }

      return {
        'success': false,
        'message': 'Failed to upload face data - Status: ${updateResp.statusCode}',
      };
    } on DioException catch (e) {
      String errorMessage = 'Network error uploading face data';
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        errorMessage = 'Authentication failed. Please login again.';
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Connection timeout.';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMessage = 'Connection error.';
      }

      return {
        'success': false,
        'message': errorMessage,
        'error': e.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unexpected error uploading face data',
        'error': e.toString(),
      };
    }
  }

  /// Get sync statistics
  static Future<Map<String, dynamic>> getSyncStats() async {
    try {
      final localEmployees = await DatabaseService.getAllEmployees();
      final employeesWithFace = localEmployees.where((e) => e.faceData != null && e.faceData!.isNotEmpty).length;

      return {
        'success': true,
        'totalEmployees': localEmployees.length,
        'withFaceData': employeesWithFace,
        'withoutFaceData': localEmployees.length - employeesWithFace,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error getting sync stats',
        'error': e.toString(),
      };
    }
  }
}
