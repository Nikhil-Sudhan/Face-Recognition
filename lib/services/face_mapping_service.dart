import '../services/database_service.dart';
import '../models/employee.dart';

class FaceMappingService {
  // Resolve email by local employee numeric id used in the app (empId)
  static Future<String?> getEmailForEmployeeId(int empId) async {
    final Employee? emp = await DatabaseService.getEmployeeById(empId);
    return emp?.email;
  }
}


