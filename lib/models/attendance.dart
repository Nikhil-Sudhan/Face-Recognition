class Attendance {
  final int? id;
  final int empId;
  final String employeeName;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final DateTime date;
  final String status; // Present, Absent, Late
  final String? notes;

  Attendance({
    this.id,
    required this.empId,
    required this.employeeName,
    required this.checkInTime,
    this.checkOutTime,
    DateTime? date,
    this.status = 'Present',
    this.notes,
  }) : date = date ?? DateTime.now();

  // Convert Attendance to Map for database operations
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'empId': empId,
      'employeeName': employeeName,
      'checkInTime': checkInTime.toIso8601String(),
      'checkOutTime': checkOutTime?.toIso8601String(),
      'date': date.toIso8601String(),
      'status': status,
      'notes': notes,
    };
  }

  // Create Attendance from Map (database result)
  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id']?.toInt(),
      empId: map['empId']?.toInt() ?? 0,
      employeeName: map['employeeName'] ?? '',
      checkInTime: DateTime.parse(map['checkInTime']),
      checkOutTime: map['checkOutTime'] != null
          ? DateTime.parse(map['checkOutTime'])
          : null,
      date: DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
      status: map['status'] ?? 'Present',
      notes: map['notes'],
    );
  }

  // Create a copy of Attendance with updated fields
  Attendance copyWith({
    int? id,
    int? empId,
    String? employeeName,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    DateTime? date,
    String? status,
    String? notes,
  }) {
    return Attendance(
      id: id ?? this.id,
      empId: empId ?? this.empId,
      employeeName: employeeName ?? this.employeeName,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      date: date ?? this.date,
      status: status ?? this.status,
      notes: notes ?? this.notes,
    );
  }

  // Get formatted time string
  String get formattedCheckInTime {
    return '${checkInTime.hour.toString().padLeft(2, '0')}:${checkInTime.minute.toString().padLeft(2, '0')}';
  }

  String? get formattedCheckOutTime {
    if (checkOutTime == null) return null;
    return '${checkOutTime!.hour.toString().padLeft(2, '0')}:${checkOutTime!.minute.toString().padLeft(2, '0')}';
  }

  // Get formatted date string
  String get formattedDate {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  String toString() {
    return 'Attendance{id: $id, empId: $empId, name: $employeeName, date: $formattedDate, status: $status}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Attendance &&
        other.empId == empId &&
        other.date.day == date.day &&
        other.date.month == date.month &&
        other.date.year == date.year;
  }

  @override
  int get hashCode => Object.hash(empId, date.day, date.month, date.year);
}
