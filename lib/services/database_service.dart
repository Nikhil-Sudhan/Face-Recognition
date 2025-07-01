import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/employee.dart';
import '../models/attendance.dart';

class DatabaseService {
  static Database? _database;
  static const String _databaseName = 'attendance.db';
  static const int _databaseVersion = 1;

  // Table names
  static const String _employeesTable = 'employees';
  static const String _attendanceTable = 'attendance';

  // Get database instance
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Initialize database
  static Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  // Create database tables
  static Future<void> _createDatabase(Database db, int version) async {
    // Create employees table
    await db.execute('''
      CREATE TABLE $_employeesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empId INTEGER UNIQUE NOT NULL,
        name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Active',
        department TEXT,
        email TEXT,
        phone TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        faceData TEXT
      )
    ''');

    // Create attendance table
    await db.execute('''
      CREATE TABLE $_attendanceTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        empId INTEGER NOT NULL,
        employeeName TEXT NOT NULL,
        checkInTime TEXT NOT NULL,
        checkOutTime TEXT,
        date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Present',
        notes TEXT,
        FOREIGN KEY (empId) REFERENCES $_employeesTable (empId)
      )
    ''');

    // Insert sample data
    await _insertSampleData(db);
  }

  // Upgrade database
  static Future<void> _upgradeDatabase(
      Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here
    if (oldVersion < newVersion) {
      // Add migration logic if needed
    }
  }

  // Insert sample data - now empty for production
  static Future<void> _insertSampleData(Database db) async {
    // No sample data in production version
    // Database starts empty for real usage
  }

  // Employee CRUD operations
  static Future<int> insertEmployee(Employee employee) async {
    final db = await database;

    // Check for duplicate employee ID
    final existing = await getEmployeeById(employee.empId);
    if (existing != null) {
      throw Exception('Employee ID ${employee.empId} already exists');
    }

    return await db.insert(_employeesTable, employee.toMap());
  }

  static Future<List<Employee>> getAllEmployees() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(_employeesTable);
    return List.generate(maps.length, (i) => Employee.fromMap(maps[i]));
  }

  static Future<Employee?> getEmployeeById(int empId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _employeesTable,
      where: 'empId = ?',
      whereArgs: [empId],
    );
    if (maps.isNotEmpty) {
      return Employee.fromMap(maps.first);
    }
    return null;
  }

  static Future<int> updateEmployee(Employee employee) async {
    final db = await database;
    return await db.update(
      _employeesTable,
      employee.toMap(),
      where: 'empId = ?',
      whereArgs: [employee.empId],
    );
  }

  static Future<int> deleteEmployee(int empId) async {
    final db = await database;
    return await db.delete(
      _employeesTable,
      where: 'empId = ?',
      whereArgs: [empId],
    );
  }

  // Attendance CRUD operations
  static Future<int> insertAttendance(Attendance attendance) async {
    final db = await database;
    return await db.insert(_attendanceTable, attendance.toMap());
  }

  static Future<List<Attendance>> getAllAttendance() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _attendanceTable,
      orderBy: 'checkInTime DESC',
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  static Future<List<Attendance>> getAttendanceByDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final List<Map<String, dynamic>> maps = await db.query(
      _attendanceTable,
      where: 'checkInTime BETWEEN ? AND ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'checkInTime DESC',
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  static Future<List<Attendance>> getAttendanceByEmployee(int empId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _attendanceTable,
      where: 'empId = ?',
      whereArgs: [empId],
      orderBy: 'checkInTime DESC',
    );
    return List.generate(maps.length, (i) => Attendance.fromMap(maps[i]));
  }

  static Future<int> updateAttendance(Attendance attendance) async {
    final db = await database;
    return await db.update(
      _attendanceTable,
      attendance.toMap(),
      where: 'id = ?',
      whereArgs: [attendance.id],
    );
  }

  static Future<int> deleteAttendance(int id) async {
    final db = await database;
    return await db.delete(
      _attendanceTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Mark attendance for face recognition
  static Future<Map<String, dynamic>> markAttendance(int empId) async {
    try {
      final employee = await getEmployeeById(empId);
      if (employee == null) {
        return {'success': false, 'message': 'Employee not found'};
      }

      final today = DateTime.now();
      final existingAttendance = await getAttendanceByDate(today);

      // Check if already marked today
      final todayAttendance =
          existingAttendance.where((att) => att.empId == empId).toList();

      if (todayAttendance.isNotEmpty) {
        final lastAttendance = todayAttendance.first;

        // If no check-out time, this is a check-out
        if (lastAttendance.checkOutTime == null) {
          final updatedAttendance = lastAttendance.copyWith(
            checkOutTime: DateTime.now(),
          );

          await updateAttendance(updatedAttendance);
          return {
            'success': true,
            'message': 'Check-out recorded successfully',
            'type': 'checkout'
          };
        } else {
          // Already checked out today, don't allow more entries
          return {
            'success': false,
            'message': 'Attendance already completed for today',
            'type': 'already_complete'
          };
        }
      }

      // No attendance today, create new check-in
      final attendance = Attendance(
        empId: empId,
        employeeName: employee.name,
        checkInTime: DateTime.now(),
        date: today,
      );

      await insertAttendance(attendance);
      return {
        'success': true,
        'message': 'Check-in recorded successfully',
        'type': 'checkin'
      };
    } catch (e) {
      print('Error marking attendance: $e');
      return {'success': false, 'message': 'Error marking attendance: $e'};
    }
  }

  // Get today's attendance for specific employee
  static Future<Attendance?> getTodayAttendance(int empId) async {
    final today = DateTime.now();
    final existingAttendance = await getAttendanceByDate(today);

    final todayAttendance =
        existingAttendance.where((att) => att.empId == empId).toList();
    return todayAttendance.isNotEmpty ? todayAttendance.first : null;
  }

  // Method to reset attendance for testing (remove in production)
  static Future<void> resetTodayAttendance(int empId) async {
    final db = await database;
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = DateTime(today.year, today.month, today.day, 23, 59, 59);

    await db.delete(
      _attendanceTable,
      where: 'empId = ? AND checkInTime BETWEEN ? AND ?',
      whereArgs: [
        empId,
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String()
      ],
    );
  }

  // Search employees
  static Future<List<Employee>> searchEmployees(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      _employeesTable,
      where: 'name LIKE ? OR empId LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );
    return List.generate(maps.length, (i) => Employee.fromMap(maps[i]));
  }

  // Close database
  static Future<void> closeDatabase() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
