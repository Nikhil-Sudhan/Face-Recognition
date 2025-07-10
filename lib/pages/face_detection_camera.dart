import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';

class FaceDetectionCameraPage extends StatefulWidget {
  final Function(String imagePath) onPhotoTaken;

  const FaceDetectionCameraPage({
    super.key,
    required this.onPhotoTaken,
  });

  @override
  State<FaceDetectionCameraPage> createState() =>
      _FaceDetectionCameraPageState();
}

class _FaceDetectionCameraPageState extends State<FaceDetectionCameraPage> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;
  bool _faceDetected = false;
  bool _photoTaken = false;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  late FaceDetector _faceDetector;
  Timer? _detectionTimer;

  String _statusMessage = 'Initializing camera...';

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _requestPermissionsAndInitialize();
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

      // Show permission dialog
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'This app needs camera access to take photos. Please grant camera permission in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
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

  Future<void> _initializeCamera() async {
    try {
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
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isCameraInitialized && !_isDetecting && !_photoTaken) {
        _detectFaces();
      }
    });
  }

  Future<void> _detectFaces() async {
    if (_isDetecting || !_isCameraInitialized || _photoTaken) return;

    setState(() {
      _isDetecting = true;
    });

    try {
      final XFile imageFile = await _controller!.takePicture();

      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty && !_photoTaken) {
        setState(() {
          _faceDetected = true;
          _statusMessage = 'Face detected! Taking photo...';
        });

        // Wait a brief moment for UI update
        await Future.delayed(const Duration(milliseconds: 300));

        // Take the final photo
        await _takePhoto();
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
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  Future<void> _takePhoto() async {
    if (_photoTaken) return;

    setState(() {
      _photoTaken = true;
      _statusMessage = 'Photo captured!';
    });

    try {
      final XFile imageFile = await _controller!.takePicture();

      // Call the callback with the image path
      widget.onPhotoTaken(imageFile.path);

      // Show success for a moment then close
      await Future.delayed(const Duration(milliseconds: 1000));

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error taking photo: $e';
        _photoTaken = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length > 1 && !_isDetecting && !_photoTaken) {
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
          'Face Detection Camera',
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
              onPressed: _isDetecting || _photoTaken ? null : _switchCamera,
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
          if (_isCameraInitialized && !_photoTaken)
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
                child: _isDetecting
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.orange,
                          strokeWidth: 3,
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
                    color: _faceDetected ? Colors.green : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // Instructions
          if (_isCameraInitialized && !_photoTaken)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'Position your face within the frame.\nPhoto will be taken automatically when face is detected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

          // Success overlay
          if (_photoTaken)
            Positioned.fill(
              child: Container(
                color: Colors.green.withValues(alpha: 0.8),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 80,
                        color: Colors.white,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Photo Captured!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
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
