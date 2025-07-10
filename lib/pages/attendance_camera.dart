import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';
import '../services/face_recognition_service.dart';
import '../services/database_service.dart';
import '../models/employee.dart';
import '../models/attendance.dart';

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
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  late FaceDetector _faceDetector;
  Timer? _detectionTimer;

  String _statusMessage = 'Initializing...';
  Employee? _recognizedEmployee;
  double _recognitionConfidence = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _requestPermissionsAndInitialize();
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
    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_isCameraInitialized && !_isDetecting && !_attendanceMarked) {
        _detectAndRecognizeFace();
      }
    });
  }

  Future<void> _detectAndRecognizeFace() async {
    if (_isDetecting || !_isCameraInitialized || _attendanceMarked) return;

    setState(() {
      _isDetecting = true;
      _statusMessage = 'Detecting faces...';
    });

    try {
      final XFile imageFile = await _controller!.takePicture();

      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty && !_attendanceMarked) {
        setState(() {
          _faceDetected = true;
          _statusMessage = 'Face detected! Recognizing...';
          _isRecognizing = true;
        });

        await _recognizeFace(imageFile);
      } else {
        setState(() {
          _faceDetected = false;
          _statusMessage = 'Position your face in the frame';
        });
      }

      // Clean up the detection image
      await File(imageFile.path).delete();
    } catch (e) {
      print('Error in face detection: $e');
      setState(() {
        _statusMessage = 'Error detecting face: $e';
      });
    } finally {
      setState(() {
        _isDetecting = false;
        _isRecognizing = false;
      });
    }
  }

  Future<void> _recognizeFace(XFile imageFile) async {
    try {
      // Process the image to get face embedding
      final result = await FaceRecognitionService.processCameraImage(imageFile);

      if (result['success'] != true) {
        setState(() {
          _statusMessage = result['message'] ?? 'Failed to process face';
        });
        return;
      }

      final capturedEmbedding = result['embedding'] as List<double>;

      // Get all employees with face data for recognition
      final employees = await DatabaseService.getAllEmployees();
      final employeesWithFaces = employees
          .where((emp) => emp.faceData != null && emp.faceData!.isNotEmpty)
          .toList();

      if (employeesWithFaces.isEmpty) {
        setState(() {
          _statusMessage =
              'No registered faces found. Please register employees first.';
        });
        return;
      }

      // Create map of stored embeddings
      final Map<String, List<double>> storedEmbeddings = {};
      for (final employee in employeesWithFaces) {
        try {
          final embedding =
              FaceRecognitionService.decodeEmbedding(employee.faceData!);
          storedEmbeddings[employee.empId.toString()] = embedding;
        } catch (e) {
          print('Error decoding embedding for employee ${employee.empId}: $e');
        }
      }

      // Perform face recognition
      final recognitionResult = FaceRecognitionService.findBestMatch(
          capturedEmbedding, storedEmbeddings);

      if (recognitionResult['match'] == true) {
        final employeeIdStr = recognitionResult['employeeId'] as String;
        final employeeId = int.parse(employeeIdStr);
        final confidence = recognitionResult['confidence'] as double;

        // Find the recognized employee
        final recognizedEmployee =
            employeesWithFaces.firstWhere((emp) => emp.empId == employeeId);

        // Mark attendance
        await _markAttendance(recognizedEmployee, confidence);
      } else {
        final confidence = recognitionResult['confidence'] as double;

        setState(() {
          _statusMessage =
              'Face not identified (confidence: ${confidence.toStringAsFixed(3)})';
          _recognitionConfidence = confidence;
        });

        // Show not identified message for a few seconds
        Timer(const Duration(seconds: 3), () {
          if (mounted && !_attendanceMarked) {
            setState(() {
              _statusMessage = 'Position your face in the frame';
            });
          }
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error recognizing face: $e';
      });
    }
  }

  Future<void> _markAttendance(Employee employee, double confidence) async {
    try {
      final now = DateTime.now();
      final attendance = Attendance(
        empId: employee.empId,
        employeeName: employee.name,
        date: DateTime(now.year, now.month, now.day),
        checkInTime: now,
        status: 'Present',
      );

      await DatabaseService.insertAttendance(attendance);

      setState(() {
        _attendanceMarked = true;
        _recognizedEmployee = employee;
        _recognitionConfidence = confidence;
        _statusMessage = 'Attendance marked successfully!';
      });

      // Stop detection timer
      _detectionTimer?.cancel();

      // Auto close after 3 seconds
      Timer(const Duration(seconds: 3), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error marking attendance: $e';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length > 1 && !_isDetecting && !_attendanceMarked) {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      await _setupCamera(_selectedCameraIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Attendance Recognition',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
          ),
        ),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              onPressed:
                  _isDetecting || _attendanceMarked ? null : _switchCamera,
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
                color: Colors.green.withValues(alpha: 0.9),
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
                                fontSize: 16,
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

          // Not identified overlay
          if (_statusMessage == 'Face not identified')
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
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
    );
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }
}
