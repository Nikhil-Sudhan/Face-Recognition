class Employee {
  final int? id;
  final int empId;
  final String name;
  final String status;
  final String? department;
  final String? email;
  final String? phone;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? faceData; // For storing face recognition data

  Employee({
    this.id,
    required this.empId,
    required this.name,
    this.status = 'Active',
    this.department,
    this.email,
    this.phone,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.faceData,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // Convert Employee to Map for database operations
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'empId': empId,
      'name': name,
      'status': status,
      'department': department,
      'email': email,
      'phone': phone,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'faceData': faceData,
    };
  }

  // Create Employee from Map (database result)
  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      id: map['id']?.toInt(),
      empId: map['empId']?.toInt() ?? 0,
      name: map['name'] ?? '',
      status: map['status'] ?? 'Active',
      department: map['department'],
      email: map['email'],
      phone: map['phone'],
      createdAt:
          DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt:
          DateTime.parse(map['updatedAt'] ?? DateTime.now().toIso8601String()),
      faceData: map['faceData'],
    );
  }

  // Create a copy of Employee with updated fields
  Employee copyWith({
    int? id,
    int? empId,
    String? name,
    String? status,
    String? department,
    String? email,
    String? phone,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? faceData,
  }) {
    return Employee(
      id: id ?? this.id,
      empId: empId ?? this.empId,
      name: name ?? this.name,
      status: status ?? this.status,
      department: department ?? this.department,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      faceData: faceData ?? this.faceData,
    );
  }

  @override
  String toString() {
    return 'Employee{id: $id, empId: $empId, name: $name, status: $status}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Employee && other.empId == empId;
  }

  @override
  int get hashCode => empId.hashCode;
}
