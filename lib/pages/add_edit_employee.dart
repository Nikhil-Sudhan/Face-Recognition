import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../models/employee.dart';
import '../services/database_service.dart';
import '../services/image_storage_service.dart';
import '../services/face_recognition_service.dart';
import '../services/erpnext_sync_service.dart';
import 'face_detection_camera.dart';

class AddEditEmployeePage extends StatefulWidget {
  final Employee? employee;

  const AddEditEmployeePage({super.key, this.employee});

  @override
  State<AddEditEmployeePage> createState() => _AddEditEmployeePageState();
}

class _AddEditEmployeePageState extends State<AddEditEmployeePage> {
  final _formKey = GlobalKey<FormState>();
  final _empIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedStatus = 'Active';
  bool _isLoading = false;
  String? _faceImagePath;
  List<double>? _faceEmbedding;
  double _faceQuality = 0.0;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeFaceRecognition();
    if (widget.employee != null) {
      _populateFields();
    }
  }

  Future<void> _initializeFaceRecognition() async {
    await FaceRecognitionService.initialize();
  }

  void _populateFields() async {
    final employee = widget.employee!;
    _empIdController.text = employee.empId.toString();
    _nameController.text = employee.name;
    _departmentController.text = employee.department ?? '';
    _emailController.text = employee.email ?? '';
    _phoneController.text = employee.phone ?? '';
    _selectedStatus = employee.status;

    // Load face image path from storage service
    final imagePath =
        await ImageStorageService.getFaceImagePath(employee.empId);

    // If employee has face data (embedding), decode it
    if (employee.faceData != null && employee.faceData!.isNotEmpty) {
      try {
        _faceEmbedding =
            FaceRecognitionService.decodeEmbedding(employee.faceData!);
        _faceQuality = 0.85; // Assume good quality for existing data
      } catch (e) {
        print('Error decoding face data: $e');
      }
    }

    setState(() {
      _faceImagePath = imagePath;
    });
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final empId = int.parse(_empIdController.text);
      String? faceData;

      // Handle face data saving
      if (_faceImagePath != null) {
        if (widget.employee == null) {
          // New employee - save image
          await ImageStorageService.saveFaceImage(_faceImagePath!, empId);
        } else {
          // Existing employee - update image if changed
          final currentPath = await ImageStorageService.getFaceImagePath(empId);
          if (currentPath != _faceImagePath) {
            await ImageStorageService.updateFaceImage(_faceImagePath!, empId);
          }
        }
      }

      // Store face embedding if available
      if (_faceEmbedding != null) {
        faceData = FaceRecognitionService.encodeEmbedding(_faceEmbedding!);
      }

      final employee = Employee(
        id: widget.employee?.id,
        empId: empId,
        name: _nameController.text.trim(),
        status: _selectedStatus,
        department: _departmentController.text.trim().isEmpty
            ? null
            : _departmentController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        faceData: faceData,
      );

      if (widget.employee == null) {
        // Add new employee
        await DatabaseService.insertEmployee(employee);
        _showSnackBar('Employee added successfully!', Colors.green);
      } else {
        // Update existing employee
        await DatabaseService.updateEmployee(employee);
        _showSnackBar('Employee updated successfully!', Colors.green);
      }

      // Upload face data to ERPNext if available
      if (employee.email != null && 
          employee.email!.isNotEmpty && 
          employee.faceData != null && 
          employee.faceData!.isNotEmpty) {
        try {
          print('=== Triggering face data upload ===');
          print('Employee email: ${employee.email}');
          print('Employee ERPNext ID: ${employee.erpNextId}');
          print('Face data length: ${employee.faceData!.length}');
          
          final result = await ErpNextSyncService.uploadFaceData(
            email: employee.email!, 
            faceData: employee.faceData!,
            erpNextId: employee.erpNextId, // Pass ERPNext ID to skip search
          );
          
          print('Upload result: $result');
          
          if (result['success']) {
            print('✓ Face data uploaded to server successfully');
          } else {
            print('✗ Face data upload failed: ${result['message']}');
            if (result['error'] != null) {
              print('Error details: ${result['error']}');
            }
            // Don't show error to user, upload can be retried on next sync
          }
        } catch (e) {
          print('✗ Exception during face data upload: $e');
          // Silent fail - face data is already saved locally
        }
      } else {
        print('Skipping face data upload:');
        print('  - Has email: ${employee.email != null && employee.email!.isNotEmpty}');
        print('  - Has face data: ${employee.faceData != null && employee.faceData!.isNotEmpty}');
      }

      Navigator.pop(context, true);
    } catch (e) {
      if (e.toString().contains('already exists')) {
        _showSnackBar('Employee ID already exists! Please use a different ID.',
            Colors.red);
      } else {
        _showSnackBar('Error saving employee: $e', Colors.red);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showPhotoOptions() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose Photo Option',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),

            // Face Detection Camera Option
            ListTile(
              leading: const Icon(Icons.face, color: Colors.blue),
              title: const Text('Face Detection Camera'),
              subtitle: const Text('Auto-capture when face is detected'),
              onTap: () {
                Navigator.pop(context);
                _openFaceDetectionCamera();
              },
            ),

            // Regular Camera Option
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Regular Camera'),
              subtitle: const Text('Manual photo capture'),
              onTap: () {
                Navigator.pop(context);
                _captureRegularPhoto();
              },
            ),

            // Gallery Option
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.orange),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Select existing photo'),
              onTap: () {
                Navigator.pop(context);
                _pickFromGallery();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFaceDetectionCamera() async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FaceDetectionCameraPage(
            onPhotoTaken: (imagePath) async {
              setState(() {
                _faceImagePath = imagePath;
              });

              // Process the captured image to extract face embedding
              await _processCapturedImage(imagePath);
            },
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('Error opening face detection camera: $e', Colors.red);
    }
  }

  Future<void> _processCapturedImage(String imagePath) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Create XFile from path for processing
      final imageFile = XFile(imagePath);

      // Process image to get face embedding
      final result = await FaceRecognitionService.processCameraImage(imageFile);

      if (result['success'] == true) {
        final embedding = result['embedding'] as List<double>;
        final quality = (result['quality'] as num).toDouble();

        setState(() {
          _faceEmbedding = embedding;
          _faceQuality = quality;
        });

        _showSnackBar(
          'Face features extracted! Quality: ${(quality * 100).toInt()}%',
          Colors.green,
        );
      } else {
        _showSnackBar(
            result['message'] ?? 'Failed to process face', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error processing face: $e', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _captureRegularPhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (photo != null) {
        setState(() {
          _faceImagePath = photo.path;
        });
        _showSnackBar('Photo captured successfully!', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error capturing photo: $e', Colors.red);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (photo != null) {
        setState(() {
          _faceImagePath = photo.path;
        });
        _showSnackBar('Photo selected from gallery!', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error selecting photo: $e', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.employee != null;

    return Scaffold(
      backgroundColor: Colors.lightBlue.shade100,
      appBar: AppBar(
        backgroundColor: Colors.lightBlue.shade100,
        elevation: 0,
        title: Text(
          isEditing ? 'Edit Employee' : 'Add Employee',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.black,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Employee ID
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _empIdController,
                  keyboardType: TextInputType.number,
                  enabled: !isEditing, // Disable editing for existing employees
                  decoration: const InputDecoration(
                    labelText: 'Employee ID *',
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter employee ID';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Please enter a valid number';
                    }
                    return null;
                  },
                ),
              ),

              // Name
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter employee name';
                    }
                    return null;
                  },
                ),
              ),

              // Department
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _departmentController,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
              ),

              // Email
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                    }
                    return null;
                  },
                ),
              ),

              // Phone
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
              ),

              // Status
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    prefixIcon: Icon(Icons.toggle_on),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'Need Update', child: Text('Need Update')),
                    DropdownMenuItem(
                        value: 'Inactive', child: Text('Inactive')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedStatus = value!;
                    });
                  },
                ),
              ),

              // Photo Section
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.face, color: Colors.blue),
                          const SizedBox(width: 12),
                          const Text(
                            'Face Recognition Data',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (_faceEmbedding != null)
                            Row(
                              children: [
                                Icon(
                                  Icons.verified,
                                  color: _faceQuality > 0.7
                                      ? Colors.green
                                      : Colors.orange,
                                  size: 20,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${(_faceQuality * 100).toInt()}%',
                                  style: TextStyle(
                                    color: _faceQuality > 0.7
                                        ? Colors.green
                                        : Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_faceImagePath != null)
                        Container(
                          height: 120,
                          width: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(60),
                            border: Border.all(color: Colors.blue, width: 2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(60),
                            child: Image.file(
                              File(_faceImagePath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 120,
                          width: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(60),
                            border: Border.all(color: Colors.grey.shade300),
                            color: Colors.grey.shade100,
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.grey,
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (_faceEmbedding != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade600, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Face features extracted and ready for recognition',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _showPhotoOptions,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(_faceImagePath != null
                                  ? Icons.refresh
                                  : Icons.camera_alt),
                          label: Text(_isLoading
                              ? 'Processing...'
                              : (_faceImagePath != null
                                  ? 'Retake Photo'
                                  : 'Take Photo')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue,
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Save Button
              ElevatedButton(
                onPressed: _isLoading ? null : _saveEmployee,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isEditing ? 'Update Employee' : 'Add Employee',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // Delete Button (only for editing)
              if (isEditing)
                ElevatedButton(
                  onPressed: _isLoading ? null : _deleteEmployee,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Delete Employee',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteEmployee() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: const Text(
            'Are you sure you want to delete this employee? This action cannot be undone.'),
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
        await DatabaseService.deleteEmployee(widget.employee!.empId);
        _showSnackBar('Employee deleted successfully!', Colors.green);
        Navigator.pop(context, true);
      } catch (e) {
        _showSnackBar('Error deleting employee: $e', Colors.red);
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _empIdController.dispose();
    _nameController.dispose();
    _departmentController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}
