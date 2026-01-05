import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
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
  int _attendanceThresholdSeconds = 30; // Default 30 seconds
  bool _livenessDetectionEnabled = true; // Default enabled for security
  String _deviceType = 'BOTH'; // IN, OUT, or BOTH

  @override
  void initState() {
    super.initState();
    _checkCameraPermission();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _attendanceThresholdSeconds = prefs.getInt('attendance_threshold_seconds') ?? 30;
      _livenessDetectionEnabled = prefs.getBool('liveness_detection_enabled') ?? true;
      _deviceType = prefs.getString('device_type') ?? 'BOTH';
    });
  }

  Future<void> _saveThreshold(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('attendance_threshold_seconds', seconds);
    setState(() {
      _attendanceThresholdSeconds = seconds;
    });
  }

  Future<void> _saveLivenessDetection(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('liveness_detection_enabled', enabled);
    setState(() {
      _livenessDetectionEnabled = enabled;
    });
  }

  Future<void> _saveDeviceType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_type', type);
    setState(() {
      _deviceType = type;
    });
    _showSnackBar('Device type set to $type', Colors.green);
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

  Future<void> _exportDatabase() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Exporting database...'),
            ],
          ),
        ),
      );

      // Get database path
      final dbPath = path.join(await getDatabasesPath(), 'attendance.db');
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        Navigator.of(context).pop();
        _showSnackBar('Database file not found', Colors.red);
        return;
      }

      // Get external storage directory with proper permission handling
      Directory? exportDir;
      if (Platform.isAndroid) {
        // For Android, request multiple storage-related permissions
        Map<Permission, PermissionStatus> statuses = await [
          Permission.storage,
          Permission.manageExternalStorage,
        ].request();
        
        // Check if either permission is granted
        bool hasPermission = statuses[Permission.storage]?.isGranted == true ||
                             statuses[Permission.manageExternalStorage]?.isGranted == true;
        
        if (!hasPermission) {
          Navigator.of(context).pop();
          
          // Check if permanently denied
          if (statuses[Permission.storage]?.isPermanentlyDenied == true ||
              statuses[Permission.manageExternalStorage]?.isPermanentlyDenied == true) {
            // Show dialog to open settings
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Permission Required'),
                content: const Text(
                  'Storage permission is required to save database backup.\n\n'
                  'Please enable it in:\nSettings > Apps > Gro Face+ > Permissions > Files and media'
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
              ),
            );
          } else {
            _showSnackBar('Storage permission denied. Please try again and allow access.', Colors.orange);
          }
          return;
        }
        
        exportDir = Directory('/storage/emulated/0/Download');
      } else {
        exportDir = await getApplicationDocumentsDirectory();
      }

      // Create backup filename with timestamp
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final backupFileName = 'attendance_backup_$timestamp.db';
      final backupPath = path.join(exportDir.path, backupFileName);

      // Copy database file
      await dbFile.copy(backupPath);

      // Get employee count
      final employees = await DatabaseService.getAllEmployees();
      final withFaceData = employees.where((e) => e.faceData != null && e.faceData!.isNotEmpty).length;

      Navigator.of(context).pop(); // Close loading dialog

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('✅ Backup Complete'),
          content: Text(
            'Database backed up successfully!\n\n'
            'Location: ${exportDir?.path ?? "Unknown"}\n'
            'File: $backupFileName\n\n'
            'Employees: ${employees.length}\n'
            'With Face Data: $withFaceData',
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
      _showSnackBar('Export failed: $e', Colors.red);
    }
  }

  Future<void> _importDatabase() async {
    try {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ Import Database'),
          content: const Text(
            'Import will:\n'
            '• Replace all current employee data\n'
            '• Replace all face embeddings\n'
            '• Cannot be undone\n\n'
            'Make sure you have a backup first!\n\n'
            'Place your backup file as:\n'
            '/storage/emulated/0/Download/attendance_import.db',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _performImport();
              },
              child: const Text('Import', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } catch (e) {
      _showSnackBar('Import failed: $e', Colors.red);
    }
  }

  Future<void> _performImport() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Importing database...'),
            ],
          ),
        ),
      );

      // Look for import file
      Directory importDir;
      if (Platform.isAndroid) {
        importDir = Directory('/storage/emulated/0/Download');
      } else {
        importDir = await getApplicationDocumentsDirectory();
      }

      final importFile = File(path.join(importDir.path, 'attendance_import.db'));

      if (!await importFile.exists()) {
        Navigator.of(context).pop();
        _showSnackBar('Import file not found: ${importFile.path}', Colors.red);
        return;
      }

      // Close current database connection
      final db = await DatabaseService.database;
      await db.close();

      // Get database path and replace it
      final dbPath = path.join(await getDatabasesPath(), 'attendance.db');
      await importFile.copy(dbPath);

      // Reinitialize database
      await DatabaseService.initialize();

      // Get stats
      final employees = await DatabaseService.getAllEmployees();
      final withFaceData = employees.where((e) => e.faceData != null && e.faceData!.isNotEmpty).length;

      Navigator.of(context).pop();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('✅ Import Complete'),
          content: Text(
            'Database imported successfully!\n\n'
            'Employees: ${employees.length}\n'
            'With Face Data: $withFaceData\n\n'
            'App will restart for changes to take effect.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Force app restart by navigating to login
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      _showSnackBar('Import failed: $e', Colors.red);
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
                    leading: const Icon(Icons.backup, color: Colors.green),
                    title: const Text('Backup Database'),
                    subtitle: const Text('Export SQLite DB (includes face embeddings)'),
                    contentPadding: EdgeInsets.zero,
                    onTap: _exportDatabase,
                  ),
                  ListTile(
                    leading: const Icon(Icons.restore, color: Colors.blue),
                    title: const Text('Restore Database'),
                    subtitle: const Text('Import backup from Download folder'),
                    contentPadding: EdgeInsets.zero,
                    onTap: _importDatabase,
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

            // Attendance Threshold Setting
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Attendance Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Re-mark Threshold',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Minimum time before same employee can mark attendance again',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            initialValue: _attendanceThresholdSeconds.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              suffix: Text('sec'),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (value) {
                              final seconds = int.tryParse(value);
                              if (seconds != null && seconds >= 0) {
                                _saveThreshold(seconds);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Liveness Detection Toggle
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.security, size: 18, color: Colors.orange),
                                  SizedBox(width: 8),
                                  Text(
                                    'Anti-Spoofing Detection',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Prevent fake attendance using photos or screens',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _livenessDetectionEnabled,
                          onChanged: (value) {
                            _saveLivenessDetection(value);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    // Device Type Setting
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.device_hub, size: 18, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'Device Type',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Set whether this device is for IN only, OUT only, or BOTH',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('IN Device'),
                                subtitle: const Text('Check-in only'),
                                value: 'IN',
                                groupValue: _deviceType,
                                onChanged: (value) {
                                  if (value != null) _saveDeviceType(value);
                                },
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('OUT Device'),
                                subtitle: const Text('Check-out only'),
                                value: 'OUT',
                                groupValue: _deviceType,
                                onChanged: (value) {
                                  if (value != null) _saveDeviceType(value);
                                },
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<String>(
                                title: const Text('BOTH (Auto Toggle)'),
                                subtitle: const Text('Auto IN/OUT toggle'),
                                value: 'BOTH',
                                groupValue: _deviceType,
                                onChanged: (value) {
                                  if (value != null) _saveDeviceType(value);
                                },
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
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
