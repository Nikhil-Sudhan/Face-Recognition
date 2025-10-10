import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/image_storage_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import 'profile_selection.dart';
import 'signin.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _cameraPermissionGranted = false;
  bool _notificationsEnabled = true;
  bool _autoMarkAttendance = true;

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
  }

  Future<void> _checkCameraPermission() async {
    try {
      final status = await Permission.camera.status;
      setState(() {
        _cameraPermissionGranted = status.isGranted;
      });
    } catch (e) {
      print('Error checking camera permission: $e');
    }
  }

  Future<void> _requestCameraPermission() async {
    try {
      final status = await Permission.camera.request();
      setState(() {
        _cameraPermissionGranted = status.isGranted;
      });

      if (status.isGranted) {
        _showSnackBar('Camera permission granted!', Colors.green);
      } else if (status.isDenied) {
        _showSnackBar('Camera permission denied', Colors.red);
      } else if (status.isPermanentlyDenied) {
        _showPermissionDialog();
      }
    } catch (e) {
      print('Error requesting camera permission: $e');
      _showSnackBar('Error requesting permission', Colors.red);
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Camera Permission Required'),
          content: const Text(
            'Camera access is permanently denied. Please enable it in app settings to use face recognition for attendance.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  Future<void> _exportFaceImages() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Exporting images...'),
            ],
          ),
        ),
      );

      final result = await ImageStorageService.exportAllFaceImages();
      Navigator.of(context).pop(); // Close loading dialog

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Complete'),
          content: Text(result),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _showSnackBar('Export failed: $e', Colors.red);
    }
  }

  Future<void> _showStorageInfo() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Loading storage info...'),
            ],
          ),
        ),
      );

      final info = await ImageStorageService.getStorageInfo();
      Navigator.of(context).pop(); // Close loading dialog

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Storage Information'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Images: ${info['imageCount']}'),
              const SizedBox(height: 8),
              Text('Total Size: ${info['totalSizeMB']} MB'),
              const SizedBox(height: 8),
              Text('Storage Path: ${info['storagePath']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _showSnackBar('Failed to load storage info: $e', Colors.red);
    }
  }

  Future<void> _cleanupData() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cleanup Data'),
        content: const Text(
            'This will remove face images that don\'t have corresponding employees. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();

              try {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const AlertDialog(
                    content: Row(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Text('Cleaning up...'),
                      ],
                    ),
                  ),
                );

                final employees = await DatabaseService.getAllEmployees();
                final validIds = employees.map((e) => e.empId).toList();
                final deletedCount =
                    await ImageStorageService.cleanupOrphanedImages(validIds);

                Navigator.of(context).pop(); // Close loading dialog
                _showSnackBar(
                    'Cleanup complete. Removed $deletedCount orphaned images.',
                    Colors.green);
              } catch (e) {
                Navigator.of(context).pop(); // Close loading dialog
                _showSnackBar('Cleanup failed: $e', Colors.red);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue.shade100,
      appBar: AppBar(
        backgroundColor: Colors.lightBlue.shade100,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Permissions Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Permissions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Camera Permission
                  Row(
                    children: [
                      Icon(
                        Icons.camera_alt,
                        color: _cameraPermissionGranted
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Camera Access',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _cameraPermissionGranted
                                  ? 'Allowed - Required for face recognition'
                                  : 'Not allowed - Tap to enable',
                              style: TextStyle(
                                fontSize: 12,
                                color: _cameraPermissionGranted
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _cameraPermissionGranted,
                        onChanged: (value) {
                          if (!_cameraPermissionGranted) {
                            _requestCameraPermission();
                          } else {
                            _showSnackBar(
                              'Please disable in app settings',
                              Colors.orange,
                            );
                          }
                        },
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // App Settings Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notifications
                  Row(
                    children: [
                      const Icon(Icons.notifications, color: Colors.blue),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notifications',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Receive attendance reminders',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _notificationsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _notificationsEnabled = value;
                          });
                        },
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Auto Mark Attendance
                  Row(
                    children: [
                      const Icon(Icons.auto_mode, color: Colors.purple),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto Mark Attendance',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Automatically mark when face is recognized',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _autoMarkAttendance,
                        onChanged: (value) {
                          setState(() {
                            _autoMarkAttendance = value;
                          });
                        },
                        activeColor: Colors.purple,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Data Management Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Data Management',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.edit, color: Colors.blue),
                    title: const Text('Edit Profiles'),
                    subtitle: const Text('Select and edit employee profiles'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ProfileSelectionPage()),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.download, color: Colors.green),
                    title: const Text('Export Face Images'),
                    subtitle: const Text('Export all employee face photos'),
                    contentPadding: EdgeInsets.zero,
                    onTap: _exportFaceImages,
                  ),
                  ListTile(
                    leading: const Icon(Icons.storage, color: Colors.purple),
                    title: const Text('Storage Info'),
                    subtitle: const Text('View storage usage details'),
                    contentPadding: EdgeInsets.zero,
                    onTap: _showStorageInfo,
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.cleaning_services, color: Colors.red),
                    title: const Text('Cleanup Data'),
                    subtitle: const Text('Remove orphaned images'),
                    contentPadding: EdgeInsets.zero,
                    onTap: _cleanupData,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // About Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.info, color: Colors.blue),
                    title: const Text('App Version'),
                    subtitle: const Text('1.0.0'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  ListTile(
                    leading: const Icon(Icons.help, color: Colors.green),
                    title: const Text('Help & Support'),
                    subtitle: const Text('Get help with the app'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      _showSnackBar('Help page coming soon!', Colors.blue);
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.privacy_tip, color: Colors.orange),
                    title: const Text('Privacy Policy'),
                    subtitle: const Text('View our privacy policy'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      _showSnackBar('Privacy policy coming soon!', Colors.blue);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('Logout'),
                        content: const Text('Are you sure you want to logout?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await AuthService.logout();
                              if (!context.mounted) return;
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                    builder: (_) => const LoginPage()),
                                (route) => false,
                              );
                            },
                            child: const Text('Logout'),
                          ),
                        ],
                      );
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
