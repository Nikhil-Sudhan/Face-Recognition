import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/employee.dart';
import 'add_edit_employee.dart';

class UserDetailsPage extends StatefulWidget {
  const UserDetailsPage({super.key});

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Employee> _allEmployees = [];
  List<Employee> _filteredEmployees = [];
  bool _isLoading = true;
  bool _isSelectionMode = false;
  Set<int> _selectedEmployeeIds = {};

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final employees = await DatabaseService.getAllEmployees();
      setState(() {
        _allEmployees = employees;
        _filteredEmployees = employees;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading employees: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterEmployees(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredEmployees = _allEmployees;
      } else {
        _filteredEmployees = _allEmployees.where((employee) {
          return employee.name.toLowerCase().contains(query.toLowerCase()) ||
              employee.empId.toString().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _toggleEmployeeStatus(Employee employee) async {
    final newStatus = employee.status == 'Active' ? 'Need Update' : 'Active';
    final updatedEmployee = employee.copyWith(status: newStatus);

    await DatabaseService.updateEmployee(updatedEmployee);
    _loadEmployees();
  }

  Future<void> _addEmployee() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddEditEmployeePage(),
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  Future<void> _editEmployee(Employee employee) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditEmployeePage(employee: employee),
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedEmployeeIds.clear();
      }
    });
  }

  void _toggleEmployeeSelection(int empId) {
    setState(() {
      if (_selectedEmployeeIds.contains(empId)) {
        _selectedEmployeeIds.remove(empId);
      } else {
        _selectedEmployeeIds.add(empId);
      }
    });
  }

  void _selectAllEmployees() {
    setState(() {
      if (_selectedEmployeeIds.length == _filteredEmployees.length) {
        _selectedEmployeeIds.clear();
      } else {
        _selectedEmployeeIds = _filteredEmployees.map((e) => e.empId).toSet();
      }
    });
  }

  Future<void> _deleteSelectedEmployees() async {
    if (_selectedEmployeeIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employees'),
        content: Text(
          'Are you sure you want to delete ${_selectedEmployeeIds.length} selected employee(s)? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        for (final empId in _selectedEmployeeIds) {
          await DatabaseService.deleteEmployee(empId);
        }

        _selectedEmployeeIds.clear();
        _isSelectionMode = false;
        await _loadEmployees();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected employees deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting employees: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue.shade400,
      appBar: AppBar(
        backgroundColor: Colors.lightBlue.shade400,
        elevation: 0,
        title: _isSelectionMode
            ? Text(
                '${_selectedEmployeeIds.length} selected',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              )
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Balavigna Weaving Mills Pvt.Ltd.,',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    'User Details',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
        leading: IconButton(
          onPressed: _isSelectionMode
              ? _toggleSelectionMode
              : () => Navigator.pop(context),
          icon: Icon(
            _isSelectionMode ? Icons.close : Icons.arrow_back,
            color: Colors.black,
          ),
        ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              onPressed: _selectAllEmployees,
              icon: Icon(
                _selectedEmployeeIds.length == _filteredEmployees.length
                    ? Icons.deselect
                    : Icons.select_all,
                color: Colors.black,
              ),
              tooltip: _selectedEmployeeIds.length == _filteredEmployees.length
                  ? 'Deselect All'
                  : 'Select All',
            ),
            IconButton(
              onPressed: _selectedEmployeeIds.isNotEmpty
                  ? _deleteSelectedEmployees
                  : null,
              icon: const Icon(
                Icons.delete,
                color: Colors.red,
              ),
              tooltip: 'Delete Selected',
            ),
          ] else ...[
            IconButton(
              onPressed: _toggleSelectionMode,
              icon: const Icon(
                Icons.checklist,
                color: Colors.black,
              ),
              tooltip: 'Select Multiple',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _filterEmployees,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _filterEmployees('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Header Row
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: const BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                if (_isSelectionMode)
                  SizedBox(
                    width: 40,
                    child: Checkbox(
                      value: _selectedEmployeeIds.length ==
                              _filteredEmployees.length &&
                          _filteredEmployees.isNotEmpty,
                      onChanged: (_) => _selectAllEmployees(),
                      activeColor: Colors.blue,
                    ),
                  ),
                Expanded(
                  flex: 2,
                  child: const Text(
                    'Emp ID',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: const Text(
                    'Name',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: const Text(
                    'Status',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Employee List
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _filteredEmployees.length,
                      itemBuilder: (context, index) {
                        final employee = _filteredEmployees[index];
                        final isSelected =
                            _selectedEmployeeIds.contains(employee.empId);

                        return GestureDetector(
                          onTap: () {
                            if (_isSelectionMode) {
                              _toggleEmployeeSelection(employee.empId);
                            } else {
                              _editEmployee(employee);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.grey.shade200,
                                  width: 1,
                                ),
                              ),
                              color: isSelected
                                  ? Colors.blue.shade50
                                  : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                if (_isSelectionMode)
                                  SizedBox(
                                    width: 40,
                                    child: Checkbox(
                                      value: isSelected,
                                      onChanged: (_) =>
                                          _toggleEmployeeSelection(
                                              employee.empId),
                                      activeColor: Colors.blue,
                                    ),
                                  ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    employee.empId.toString(),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    employee.name,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          employee.status,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: employee.status == 'Active'
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                        ),
                                      ),
                                      if (!_isSelectionMode &&
                                          employee.status == 'Active')
                                        GestureDetector(
                                          onTap: () =>
                                              _toggleEmployeeStatus(employee),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Icon(
                                              Icons.check,
                                              size: 16,
                                              color: Colors.purple.shade700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),

          // Bottom Buttons
          if (!_isSelectionMode)
            Container(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addEmployee,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Selection Mode Bottom Actions
          if (_isSelectionMode)
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedEmployeeIds.isNotEmpty
                          ? () {
                              final selectedEmployee =
                                  _filteredEmployees.firstWhere(
                                (emp) =>
                                    _selectedEmployeeIds.contains(emp.empId),
                              );
                              _editEmployee(selectedEmployee);
                            }
                          : null,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Selected'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _selectedEmployeeIds.isNotEmpty
                          ? _deleteSelectedEmployees
                          : null,
                      icon: const Icon(Icons.delete),
                      label: Text('Delete (${_selectedEmployeeIds.length})'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
