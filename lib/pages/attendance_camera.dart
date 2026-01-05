import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'dart:async';
import 'dart:io';
import '../services/face_recognition_service.dart';
import '../services/database_service.dart';
import '../services/attendance_service.dart';
import '../services/liveness_detection_service.dart';
import '../services/mpin_service.dart';
import '../services/face_mapping_service.dart';
import '../services/offline_queue_service.dart';
import '../models/employee.dart';
import 'mpin_verification_page.dart';
import 'homepage.dart';

class AttendanceCameraPage extends StatefulWidget {
  const AttendanceCameraPage({super.key});

  @override
  State<AttendanceCameraPage> createState() => _AttendanceCameraPageState();
}

class _AttendanceCameraPageState extends State<AttendanceCameraPage> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  bool _faceDetected = false;
  bool _isRecognizing = false;
  bool _attendanceMarked = false;
  bool _thresholdWarning = false; // Flag for threshold warning display
  bool _isProcessingAttendance = false; // CRITICAL: Lock to prevent concurrent processing
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  late FaceDetector _faceDetector;
  Timer? _detectionTimer;
  
  // Platform channel for screen wake lock
  static const MethodChannel _channel = MethodChannel('face_recognition/screen');

  String _statusMessage = 'Initializing...';
  String _deviceType = 'BOTH'; // Device type setting
  Employee? _recognizedEmployee;
  double _recognitionConfidence = 0.0;
  
  // Track last processed employee to prevent double processing
  int? _lastProcessedEmployeeId;
  DateTime? _lastProcessedTime;
  
  // Track Portal sync status for debugging
  String _lastApiStatus = '';
  bool _apiSyncSuccess = false;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _loadDeviceType();
    _requestPermissionsAndInitialize();
    _tryFlushOfflineQueue(); // Attempt to sync queued checkins on startup
  }
  
  Future<void> _tryFlushOfflineQueue() async {
    try {
      debugPrint('🔄 Attempting to flush offline queue...');
      final syncedCount = await OfflineQueueService.flush();
      if (syncedCount > 0) {
        debugPrint('✅ Successfully synced $syncedCount queued checkin(s)');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Synced $syncedCount pending checkin(s)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        debugPrint('ℹ️ No pending checkins to sync');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to flush offline queue: $e');
      // Silent fail - will retry on next launch
    }
  }

  Future<void> _loadDeviceType() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceType = prefs.getString('device_type') ?? 'BOTH';
    });
  }

  void _initializeFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: false,
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  Future<void> _requestPermissionsAndInitialize() async {
    final status = await Permission.camera.request();

    if (status == PermissionStatus.granted) {
      _initializeCamera();
    } else {
      setState(() {
        _statusMessage =
            'Camera permission required. Please grant camera access.';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _statusMessage = 'Initializing camera...';
      });

      // Initialize face recognition service
      await FaceRecognitionService.initialize();

      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        // Prefer front camera for selfies
        try {
          _selectedCameraIndex = _cameras.indexWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
          );
          if (_selectedCameraIndex == -1) {
            _selectedCameraIndex = 0;
          }
        } catch (e) {
          _selectedCameraIndex = 0;
        }

        await _setupCamera(_selectedCameraIndex);
      } else {
        setState(() {
          _statusMessage = 'No camera available';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error initializing camera: $e';
      });
    }
  }

  Future<void> _setupCamera(int cameraIndex) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    _controller = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      
      // Keep screen awake during camera usage
      await _setScreenAwake(true);
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _statusMessage = 'Position your face in the frame';
        });
        _startFaceDetection();
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error setting up camera: $e';
      });
    }
  }

  void _startFaceDetection() {
    // Cancel existing timer if any
    _detectionTimer?.cancel();
    
    // OPTIMIZED: Reduced from 1000ms to 500ms for faster detection cycles
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      // Check if widget is still mounted before proceeding
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      // CRITICAL: Check all blocking conditions including processing lock
      if (_isCameraInitialized && !_isDetecting && !_attendanceMarked && !_thresholdWarning && !_isProcessingAttendance) {
        _detectAndRecognizeFace();
      }
    });
  }

  Future<void> _detectAndRecognizeFace() async {
    // CRITICAL: Multiple locks to prevent concurrent processing
    if (_isDetecting || 
        !_isCameraInitialized || 
        _attendanceMarked || 
        _thresholdWarning || 
        _isProcessingAttendance ||
        !mounted) {
      return;
    }

    setState(() {
      _isDetecting = true;
      _statusMessage = 'Detecting faces...';
    });

    try {
      final XFile imageFile = await _controller!.takePicture();

      // OPTIMIZED: Use lower resolution for faster processing
      final bytes = await imageFile.readAsBytes();
      final decodedImage = img.decodeImage(bytes);
      
      if (decodedImage == null) {
        throw Exception('Failed to decode image');
      }
      
      // Resize to 640px width for faster processing (maintains aspect ratio)
      final resizedImage = img.copyResize(decodedImage, width: 640);
      final tempPath = '${imageFile.path}_resized.jpg';
      await File(tempPath).writeAsBytes(img.encodeJpg(resizedImage, quality: 85));
      
      final inputImage = InputImage.fromFilePath(tempPath);
      final faces = await _faceDetector.processImage(inputImage);
      
      // Clean up resized temp file
      await File(tempPath).delete();

      if (!mounted) return; // Check again after async operation

      if (faces.isNotEmpty && !_attendanceMarked) {
        // Check if liveness detection is enabled
        final prefs = await SharedPreferences.getInstance();
        final livenessEnabled = prefs.getBool('liveness_detection_enabled') ?? true;

        if (livenessEnabled) {
          // Perform liveness detection
          final livenessResult = await LivenessDetectionService.detectLiveness(
            imageFile.path,
            faces.first,
          );

          if (!mounted) return;

          if (livenessResult['isLive'] != true) {
            // Fake face detected!
            setState(() {
              _faceDetected = false;
              _statusMessage = '⚠️ Fake detected: ${livenessResult['reason']}';
            });

            // Show warning for 3 seconds
            Timer(const Duration(seconds: 3), () {
              if (mounted && !_attendanceMarked) {
                setState(() {
                  _statusMessage = 'Position your face in the frame';
                });
              }
            });

            await File(imageFile.path).delete();
            return;
          }

          // Real face detected, proceed with recognition
          setState(() {
            _faceDetected = true;
            _statusMessage = 'Live face detected! Recognizing...';
          });
        } else {
          // Liveness detection disabled, just show face detected
          setState(() {
            _faceDetected = true;
            _statusMessage = 'Face detected! Recognizing...';
          });
        }

        await _recognizeFace(imageFile);
      } else {
        if (mounted) {
          setState(() {
            _faceDetected = false;
            _statusMessage = 'Position your face in the frame';
          });
        }
      }

      // Clean up the detection image
      await File(imageFile.path).delete();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error detecting face: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDetecting = false;
          _isRecognizing = false;
        });
      }
    }
  }

  Future<void> _recognizeFace(XFile imageFile) async {
    if (!mounted) return;
    
    // CRITICAL: Check if already processing
    if (_isRecognizing || _attendanceMarked || _isProcessingAttendance) {
      return;
    }
    
    setState(() {
      _isRecognizing = true;
    });
    
    try {
      // Process the image to get face embedding
      final result = await FaceRecognitionService.processCameraImage(imageFile);

      if (!mounted) return; // Check after async operation

      if (result['success'] != true) {
        setState(() {
          _statusMessage = result['message'] ?? 'Failed to process face';
          _isRecognizing = false;
        });
        return;
      }

      final capturedEmbedding = result['embedding'] as List<double>;

      // Get all employees with face data for recognition
      final employees = await DatabaseService.getAllEmployees();
      final employeesWithFaces = employees
          .where((emp) => emp.faceData != null && emp.faceData!.isNotEmpty)
          .toList();

      if (!mounted) return; // Check after async operation

      if (employeesWithFaces.isEmpty) {
        setState(() {
          _statusMessage =
              'No registered faces found. Please register employees first.';
          _isRecognizing = false;
        });
        return;
      }

      // CRITICAL: Create map with employee objects, not just embeddings
      final Map<String, Map<String, dynamic>> employeeData = {};
      for (final employee in employeesWithFaces) {
        try {
          final embedding =
              FaceRecognitionService.decodeEmbedding(employee.faceData!);
          employeeData[employee.empId.toString()] = {
            'embedding': embedding,
            'employee': employee,
          };
        } catch (e) {
          // Skip this employee if embedding decode fails
        }
      }

      // Create embedding map for recognition
      final Map<String, List<double>> storedEmbeddings = {};
      employeeData.forEach((empId, data) {
        storedEmbeddings[empId] = data['embedding'] as List<double>;
      });

      // Perform face recognition
      final recognitionResult = FaceRecognitionService.findBestMatch(
          capturedEmbedding, storedEmbeddings);

      if (recognitionResult['match'] == true) {
        final employeeIdStr = recognitionResult['employeeId'] as String;
        final confidence = recognitionResult['confidence'] as double;

        // CRITICAL: Get employee from our stored data to ensure consistency
        final employeeInfo = employeeData[employeeIdStr];
        if (employeeInfo == null) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Error: Employee data inconsistency for ID $employeeIdStr';
              _isRecognizing = false;
            });
          }
          return;
        }

        final recognizedEmployee = employeeInfo['employee'] as Employee;
        final storedEmbedding = employeeInfo['embedding'] as List<double>;

        // Double-check: Verify this is the correct employee by re-matching
        try {
          final similarity = FaceRecognitionService.calculateSimilarity(
            capturedEmbedding, 
            storedEmbedding
          );
          
          // Log for debugging
          debugPrint('🔍 Recognition Result:');
          debugPrint('   Employee: ${recognizedEmployee.name} (ID: ${recognizedEmployee.empId})');
          debugPrint('   Confidence: ${(confidence * 100).toStringAsFixed(2)}%');
          debugPrint('   Verification: ${(similarity * 100).toStringAsFixed(2)}%');
          
          // Check if this is a duplicate detection of same person within 5 seconds
          if (_lastProcessedEmployeeId == recognizedEmployee.empId && 
              _lastProcessedTime != null &&
              DateTime.now().difference(_lastProcessedTime!).inSeconds < 5) {
            debugPrint('⚠️  Duplicate detection prevented - same employee within 5 seconds');
            if (mounted) {
              setState(() {
                _isRecognizing = false;
              });
            }
            return;
          }
          
          // Trust the face recognition service threshold - no additional verification needed
          debugPrint('✓ Face recognized - marking attendance (similarity: ${(similarity * 100).toStringAsFixed(1)}%)');
        } catch (e) {
          debugPrint('✗ Verification error: $e');
          if (mounted) {
            setState(() {
              _statusMessage = 'Error verifying face match: $e';
              _isRecognizing = false;
            });
          }
          return;
        }

        // Mark attendance with verified employee
        await _markAttendance(recognizedEmployee, confidence);
      } else {
        final confidence = recognitionResult['confidence'] as double;

        if (mounted) {
          setState(() {
            _statusMessage =
                'Face not identified (confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
            _recognitionConfidence = confidence;
            _isRecognizing = false;
          });
        }

        // Show not identified message for a few seconds
        await Future.delayed(const Duration(seconds: 2));
        if (mounted && !_attendanceMarked) {
          setState(() {
            _statusMessage = 'Position your face in the frame';
          });
        }
      }
    } catch (e) {
      debugPrint('✗ Recognition error: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Error recognizing face: $e';
          _isRecognizing = false;
        });
      }
    }
  }

  Future<void> _markAttendance(Employee employee, double confidence) async {
    // CRITICAL: Set processing lock immediately
    if (_isProcessingAttendance) {
      debugPrint('⚠️  Already processing attendance, skipping...');
      return;
    }
    
    setState(() {
      _isProcessingAttendance = true;
    });
    
    // CRITICAL: Stop face detection immediately to prevent double captures
    _detectionTimer?.cancel();
    
    // Track this employee to prevent duplicate processing
    _lastProcessedEmployeeId = employee.empId;
    _lastProcessedTime = DateTime.now();
    
    debugPrint('📝 Marking attendance for ${employee.name} (ID: ${employee.empId})');
    
    try {
      // Get threshold from settings
      final prefs = await SharedPreferences.getInstance();
      final thresholdSeconds = prefs.getInt('attendance_threshold_seconds') ?? 30;

      // Mark attendance locally first with threshold check
      final localResult = await DatabaseService.markAttendance(
        employee.empId,
        thresholdSeconds: thresholdSeconds,
      );

      // If threshold not met, show warning message and return
      if (!localResult['success'] && localResult['type'] == 'threshold_not_met') {
        setState(() {
          _thresholdWarning = true;
          _recognizedEmployee = employee;
          _recognitionConfidence = confidence;
          _statusMessage = localResult['message'];
        });

        // Wait 3 seconds to show the warning message, then reset for next employee
        await Future.delayed(const Duration(seconds: 3));
        
        if (mounted) {
          setState(() {
            _thresholdWarning = false;
            _recognizedEmployee = null;
            _recognitionConfidence = 0.0;
            _faceDetected = false;
            _isProcessingAttendance = false; // Release lock
            _statusMessage = 'Position your face in the frame';
          });
          // Resume detection for next employee
          _startFaceDetection();
        }
        return;
      }

      // Post to Portal using AttendanceService (handles device type settings)
      bool apiSuccess = false;
      String apiMessage = '';
      
      try {
        // Get employee email from mapping service
        final email = await FaceMappingService.getEmailForEmployeeId(employee.empId);
        
        if (email != null && email.isNotEmpty) {
          debugPrint('🌐 Syncing to Portal for email: $email');
          
          // Use AttendanceService which handles device type (IN/OUT/BOTH) from settings
          final apiResult = await AttendanceService.checkinByEmail(email);
          
          apiSuccess = apiResult['success'] == true;
          apiMessage = apiResult['message'] ?? 'Unknown response';
          
          if (apiSuccess) {
            debugPrint('✅ Portal sync successful: $apiMessage');
            setState(() {
              _lastApiStatus = '✓ Synced: $apiMessage';
              _apiSyncSuccess = true;
            });
          } else {
            // API call failed - queue for retry
            debugPrint('❌ Portal sync failed: $apiMessage');
            debugPrint('📥 Queueing for offline retry...');
            
            await OfflineQueueService.enqueue(email, DateTime.now().toIso8601String());
            
            setState(() {
              _lastApiStatus = '⚠ Queued: $apiMessage';
              _apiSyncSuccess = false;
            });
            
            // Show error notification to user
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚠️ Offline: Attendance queued for sync\n$apiMessage'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        } else {
          debugPrint('⚠️  No email found for employee ID ${employee.empId}');
          setState(() {
            _lastApiStatus = '⚠ No email mapping';
            _apiSyncSuccess = false;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ No email configured for employee'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (e) {
        // Network or unexpected error - queue for retry
        debugPrint('❌ Portal API error: $e');
        
        final email = await FaceMappingService.getEmailForEmployeeId(employee.empId);
        if (email != null && email.isNotEmpty) {
          debugPrint('📥 Queueing for offline retry...');
          await OfflineQueueService.enqueue(email, DateTime.now().toIso8601String());
        }
        
        setState(() {
          _lastApiStatus = '⚠ Error: ${e.toString().split('\n').first}';
          _apiSyncSuccess = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Sync failed: Will retry when online\n${e.toString().split('\n').first}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

      setState(() {
        _attendanceMarked = localResult['success'] == true;
        _recognizedEmployee = employee;
        _recognitionConfidence = confidence;
        _faceDetected = true;
        // Include sync status in message
        final baseMessage = (localResult['message'] as String?) ?? 'Attendance marked successfully!';
        _statusMessage = apiSuccess 
            ? '$baseMessage (Synced ✓)'
            : '$baseMessage (Queued for sync)';
      });

      // Wait 3 seconds to show the success message, then FULLY reset for next employee
      await Future.delayed(const Duration(seconds: 3));
      
      debugPrint('✓ Attendance marked, resetting for next employee');
      
      if (mounted) {
        setState(() {
          _attendanceMarked = false;
          _recognizedEmployee = null;
          _recognitionConfidence = 0.0;
          _faceDetected = false;
          _isDetecting = false;
          _isRecognizing = false;
          _isProcessingAttendance = false; // Release lock
          _statusMessage = 'Position your face in the frame';
          // Keep last API status visible for debugging
        });
        
        // Small delay before resuming detection to ensure state is fully reset
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          debugPrint('🔄 Resuming detection for next employee');
          // Resume detection for next employee
          _startFaceDetection();
        }
      }
    } catch (e) {
      debugPrint('✗ Error marking attendance: $e');
      setState(() {
        _statusMessage = 'Error marking attendance: $e';
        _attendanceMarked = false;
        _recognizedEmployee = null;
        _isProcessingAttendance = false; // Release lock
      });
      
      // Resume detection even after error
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _startFaceDetection();
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length > 1 && !_attendanceMarked) {
      // Stop detection timer before switching
      _detectionTimer?.cancel();
      _detectionTimer = null;
      
      setState(() {
        _isDetecting = false;
        _faceDetected = false;
      });
      
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      await _setupCamera(_selectedCameraIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Require MPIN verification before going back
        final verified = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const MpinVerificationPage(
              title: 'Verify MPIN',
              subtitle: 'Enter MPIN to access main menu',
            ),
          ),
        );

        if (verified == true) {
          // MPIN verified, navigate to homepage
          if (!mounted) return false;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
          return false; // Prevent default back
        }
        
        // MPIN not verified, stay on camera page
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Attendance Recognition',
            style: TextStyle(color: Colors.white),
          ),
          leading: IconButton(
            onPressed: () async {
              // Require MPIN verification before going back
              final verified = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MpinVerificationPage(
                    title: 'Verify MPIN',
                    subtitle: 'Enter MPIN to access main menu',
                  ),
                ),
              );

              if (verified == true && mounted) {
                // MPIN verified, navigate to homepage
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                );
              }
            },
            icon: const Icon(
              Icons.menu,
              color: Colors.white,
            ),
          ),
          actions: [
          if (_cameras.length > 1)
            IconButton(
              onPressed: _attendanceMarked ? null : _switchCamera,
              icon: const Icon(
                Icons.flip_camera_ios,
                color: Colors.white,
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Camera Preview
          if (_isCameraInitialized && _controller != null)
            Positioned.fill(
              child: CameraPreview(_controller!),
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 20),
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          // Face detection overlay
          if (_isCameraInitialized && !_attendanceMarked)
            Center(
              child: Container(
                width: 250,
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _faceDetected
                        ? Colors.green
                        : _isDetecting
                            ? Colors.orange
                            : Colors.white,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _isRecognizing
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: Colors.green,
                              strokeWidth: 3,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Recognizing...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : null,
              ),
            ),

          // Device Type Indicator (only show for IN or OUT, not BOTH)
          if (_deviceType != 'BOTH')
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _deviceType == 'IN' 
                        ? Colors.green.withOpacity(0.9)
                        : Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _deviceType == 'IN' ? Icons.login : Icons.logout,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_deviceType Device',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // API Sync Status Indicator (bottom-left corner)
          if (_lastApiStatus.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _apiSyncSuccess 
                      ? Colors.green.withOpacity(0.9)
                      : Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _apiSyncSuccess ? Icons.cloud_done : Icons.cloud_off,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _lastApiStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Status message
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _attendanceMarked
                        ? Colors.green
                        : _faceDetected
                            ? Colors.green
                            : _statusMessage.contains('Fake') || _statusMessage.contains('⚠️')
                                ? Colors.red
                                : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // Attendance success overlay
          if (_attendanceMarked && _recognizedEmployee != null)
            Positioned.fill(
              child: Container(
                color: Colors.green.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 80,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Attendance Marked!',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.symmetric(horizontal: 30),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _recognizedEmployee!.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ID: ${_recognizedEmployee!.empId}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Confidence: ${(_recognitionConfidence * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Time: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Threshold warning overlay (orange/warning color)
          if (_thresholdWarning && _recognizedEmployee != null)
            Positioned.fill(
              child: Container(
                color: Colors.orange.withOpacity(0.9),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 80,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Already Marked!',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.symmetric(horizontal: 30),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _recognizedEmployee!.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ID: ${_recognizedEmployee!.empId}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 15),
                            Text(
                              _statusMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Not identified overlay
          if (_statusMessage == 'Face not identified')
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Face Not Identified',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Confidence: ${(_recognitionConfidence * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  @override
  void dispose() {
    // Cancel all timers
    _detectionTimer?.cancel();
    _detectionTimer = null;
    
    // Allow screen to sleep again
    _setScreenAwake(false);
    
    // Stop and dispose camera
    _controller?.dispose();
    _controller = null;
    
    // Close face detector
    _faceDetector.close();
    
    super.dispose();
  }
  
  // Method to control screen wake lock
  Future<void> _setScreenAwake(bool keepAwake) async {
    try {
      if (keepAwake) {
        await _channel.invokeMethod('keepScreenOn');
      } else {
        await _channel.invokeMethod('allowScreenOff');
      }
    } catch (e) {
      // Fallback: Use SystemChrome if platform channel fails
      if (keepAwake) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, 
          overlays: [SystemUiOverlay.bottom]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, 
          overlays: SystemUiOverlay.values);
      }
    }
  }
}
