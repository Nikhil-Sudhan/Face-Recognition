import 'dart:math';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:camera/camera.dart';
import 'facenet_service.dart';

class FaceRecognitionService {
  static bool _isInitialized = false;
  static const double _threshold =
      0.55; // INCREASED from 0.35 to 0.55 for stricter matching (reduces false positives)
  static const int _embeddingSize =
      128; // Increased embedding size for better accuracy

  // Initialize the face recognition service
  static Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Try to initialize FaceNet model
      print('Attempting to initialize FaceNet model...');
      final faceNetInitialized = await FaceNetService.initialize();
      
      if (faceNetInitialized) {
        print('✓ FaceNet model loaded successfully - using deep learning recognition');
      } else {
        print('⚠ FaceNet model not available - using fallback feature extraction');
      }
      
      _isInitialized = true;
      return true;
    } catch (e) {
      print('Error initializing face recognition: $e');
      return false;
    }
  }

  // (unused helper removed)

  // Generate improved face features
  static List<double> _generateFaceFeatures(img.Image faceImage) {
    final features = <double>[];

    // Resize to standard size for consistent feature extraction
    final resized = img.copyResize(faceImage, width: 64, height: 64);

    // Convert to grayscale for better feature extraction
    final gray = img.grayscale(resized);

    // Enhanced color histogram features (more bins for better discrimination)
    final rHist = List.filled(16, 0);
    final gHist = List.filled(16, 0);
    final bHist = List.filled(16, 0);

    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 64; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;

        rHist[r ~/ 16]++;
        gHist[g ~/ 16]++;
        bHist[b ~/ 16]++;
      }
    }

    // Normalize histograms
    final totalPixels = 64 * 64;
    features.addAll(rHist.map((h) => h / totalPixels));
    features.addAll(gHist.map((h) => h / totalPixels));
    features.addAll(bHist.map((h) => h / totalPixels));

    // Enhanced texture features using Local Binary Pattern-like approach
    final lbpFeatures = <double>[];
    for (int y = 1; y < 63; y++) {
      for (int x = 1; x < 63; x++) {
        final center = gray.getPixel(x, y).luminance;
        int pattern = 0;

        // 8-neighborhood pattern
        final neighbors = [
          gray.getPixel(x - 1, y - 1).luminance,
          gray.getPixel(x, y - 1).luminance,
          gray.getPixel(x + 1, y - 1).luminance,
          gray.getPixel(x + 1, y).luminance,
          gray.getPixel(x + 1, y + 1).luminance,
          gray.getPixel(x, y + 1).luminance,
          gray.getPixel(x - 1, y + 1).luminance,
          gray.getPixel(x - 1, y).luminance,
        ];

        for (int i = 0; i < 8; i++) {
          if (neighbors[i] >= center) {
            pattern |= (1 << i);
          }
        }
        lbpFeatures.add(pattern / 255.0);
      }
    }

    // Sample LBP features to reduce dimensionality
    final sampledLbp = <double>[];
    for (int i = 0;
        i < lbpFeatures.length;
        i += (lbpFeatures.length / 16).ceil()) {
      sampledLbp.add(lbpFeatures[i]);
    }
    features.addAll(sampledLbp.take(16));

    // Brightness distribution features
    final brightnessHist = List.filled(8, 0);
    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 64; x++) {
        final brightness = gray.getPixel(x, y).luminance;
        final bin = ((brightness * 7).toInt()).clamp(0, 7);
        brightnessHist[bin]++;
      }
    }
    features.addAll(brightnessHist.map((h) => h / totalPixels));

    // Edge orientation features
    final orientationFeatures = <double>[];
    for (int y = 1; y < 63; y++) {
      for (int x = 1; x < 63; x++) {
        final gx = gray.getPixel(x + 1, y).luminance -
            gray.getPixel(x - 1, y).luminance;
        final gy = gray.getPixel(x, y + 1).luminance -
            gray.getPixel(x, y - 1).luminance;
        final magnitude = sqrt(gx * gx + gy * gy);
        orientationFeatures.add(magnitude);
      }
    }

    // Sample orientation features
    final sampledOrientation = <double>[];
    for (int i = 0;
        i < orientationFeatures.length;
        i += (orientationFeatures.length / 16).ceil()) {
      sampledOrientation.add(orientationFeatures[i]);
    }
    features.addAll(sampledOrientation.take(16));

    // Ensure we have exactly _embeddingSize features
    while (features.length < _embeddingSize) {
      features.add(0.0);
    }

    // Normalize the entire feature vector
    final normalizedFeatures =
        _normalizeVector(features.take(_embeddingSize).toList());

    return normalizedFeatures;
  }

  // Normalize feature vector
  static List<double> _normalizeVector(List<double> vector) {
    final magnitude = sqrt(vector.map((x) => x * x).reduce((a, b) => a + b));
    if (magnitude == 0) return vector;
    return vector.map((x) => x / magnitude).toList();
  }

  // Calculate cosine similarity between two embeddings
  static double _cosineSimilarity(
      List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw ArgumentError('Embeddings must have the same length');
    }

    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    if (norm1 == 0.0 || norm2 == 0.0) {
      return 0.0;
    }

    return dotProduct / (sqrt(norm1) * sqrt(norm2));
  }

  // Process camera image and extract face embedding
  static Future<Map<String, dynamic>> processCameraImage(
      XFile imageFile) async {
    try {
      // Read image file
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        return {
          'success': false,
          'message': 'Failed to decode image',
        };
      }

      // Convert to InputImage for face detection
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableLandmarks: true, // Enable landmarks for better validation
          enableClassification: false,
          enableTracking: false,
          minFaceSize: 0.15, // Increased minimum face size
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      if (faces.isEmpty) {
        return {
          'success': false,
          'message': 'No face detected in the image',
          'faceCount': 0,
        };
      }

      if (faces.length > 1) {
        return {
          'success': false,
          'message':
              'Multiple faces detected. Please ensure only one face is visible',
          'faceCount': faces.length,
        };
      }

      // Extract face region
      final face = faces.first;
      final faceRect = face.boundingBox;

      // Check face orientation
      if (face.headEulerAngleY != null && face.headEulerAngleY!.abs() > 30) {
        return {
          'success': false,
          'message': 'Please face the camera directly (head turned too much)',
          'faceCount': 1,
        };
      }

      // Check face size - ensure minimum quality
      final faceArea = faceRect.width * faceRect.height;
      final imageArea = image.width * image.height;
      final faceRatio = faceArea / imageArea;

      if (faceRatio < 0.05) {
        // Face too small
        return {
          'success': false,
          'message': 'Face too small. Please move closer to the camera',
          'faceCount': 1,
        };
      }

      // Crop face from image with some padding
      final padding = max(20, (faceRect.width * 0.2).toInt());
      final x = max(0, faceRect.left.toInt() - padding);
      final y = max(0, faceRect.top.toInt() - padding);
      final width =
          min(image.width - x, faceRect.width.toInt() + (2 * padding));
      final height =
          min(image.height - y, faceRect.height.toInt() + (2 * padding));

      final faceImage =
          img.copyCrop(image, x: x, y: y, width: width, height: height);

      // Generate face embedding - use FaceNet if available, otherwise fallback
      List<double> embedding;
      
      if (FaceNetService.isModelAvailable()) {
        print('Using FaceNet deep learning model for embedding...');
        final faceNetEmbedding = await FaceNetService.generateEmbedding(faceImage);
        
        if (faceNetEmbedding != null) {
          embedding = faceNetEmbedding;
          print('✓ FaceNet embedding generated (${embedding.length} dimensions)');
        } else {
          print('⚠ FaceNet failed, using fallback features');
          embedding = _generateFaceFeatures(faceImage);
        }
      } else {
        print('⚠ FaceNet not available, using fallback features');
        embedding = _generateFaceFeatures(faceImage);
      }

      // Calculate quality score based on face size and image quality
      final quality = min(1.0, faceRatio * 8); // Improved quality calculation

      return {
        'success': true,
        'embedding': embedding,
        'quality': quality,
        'faceCount': 1,
        'message': 'Face processed successfully',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error processing image: $e',
      };
    }
  }

  // Process camera frame for face detection
  static Future<Map<String, dynamic>> processCameraFrame(
      CameraImage cameraImage) async {
    try {
      await initialize();

      // Convert CameraImage to InputImage
      final inputImage = _convertCameraImage(cameraImage);
      if (inputImage == null) {
        return {'success': false, 'message': 'Failed to convert camera image'};
      }

      // Detect faces
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableLandmarks: false,
          enableClassification: false,
          enableTracking: false,
          minFaceSize: 0.1,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      return {
        'success': true,
        'faceCount': faces.length,
        'faces': faces,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error processing camera frame: $e',
      };
    }
  }

  // Convert CameraImage to InputImage
  static InputImage? _convertCameraImage(CameraImage cameraImage) {
    try {
      final bytes = cameraImage.planes.first.bytes;
      final imageMetadata = InputImageMetadata(
        size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: cameraImage.planes.first.bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: imageMetadata,
      );
    } catch (e) {
      print('Error converting camera image: $e');
      return null;
    }
  }

  // Compare face embeddings
  static double compareEmbeddings(
      List<double> embedding1, List<double> embedding2) {
    try {
      return _cosineSimilarity(embedding1, embedding2);
    } catch (e) {
      print('Error comparing embeddings: $e');
      return 0.0;
    }
  }

  // Check if two embeddings match based on threshold
  static bool isMatch(List<double> embedding1, List<double> embedding2) {
    final similarity = compareEmbeddings(embedding1, embedding2);
    return similarity >= _threshold;
  }

  // Find the best match from a list of stored embeddings
  static Map<String, dynamic> findBestMatch(
      List<double> queryEmbedding, Map<String, List<double>> storedEmbeddings) {
    double bestSimilarity = 0.0;
    String? bestMatchId;
    final List<Map<String, dynamic>> allMatches = [];

    // Use FaceNet similarity calculation if available, otherwise use fallback
    for (final entry in storedEmbeddings.entries) {
      final double similarity;
      
      if (FaceNetService.isModelAvailable()) {
        // Use cosine similarity for FaceNet embeddings
        similarity = FaceNetService.calculateSimilarity(queryEmbedding, entry.value);
      } else {
        // Use fallback comparison
        similarity = compareEmbeddings(queryEmbedding, entry.value);
      }

      allMatches.add({
        'employeeId': entry.key,
        'similarity': similarity,
      });

      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestMatchId = entry.key;
      }
    }

    // Sort matches by similarity for debugging
    allMatches.sort((a, b) => b['similarity'].compareTo(a['similarity']));

    // Use different threshold for FaceNet vs fallback
    final threshold = FaceNetService.isModelAvailable() ? 0.5 : _threshold;
    final isMatch = bestSimilarity >= threshold;
    
    print('Best match: $bestMatchId, similarity: ${bestSimilarity.toStringAsFixed(4)}, threshold: $threshold, isMatch: $isMatch');

    return {
      'match': isMatch,
      'employeeId': bestMatchId,
      'confidence': bestSimilarity,
      'allMatches': allMatches,
    };
  }

  // Encode embedding to string for database storage
  static String encodeEmbedding(List<double> embedding) {
    return embedding.map((e) => e.toStringAsFixed(6)).join(',');
  }

  // Decode embedding from string
  static List<double> decodeEmbedding(String encodedEmbedding) {
    try {
      return encodedEmbedding.split(',').map((e) => double.parse(e)).toList();
    } catch (e) {
      print('Error decoding embedding: $e');
      return List.filled(_embeddingSize, 0.0);
    }
  }
}
