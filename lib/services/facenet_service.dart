import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:math';

class FaceNetService {
  static Interpreter? _interpreter;
  static bool _isInitialized = false;
  static const double _threshold = 0.5; // Cosine similarity threshold for face matching
  static const int _embeddingSize = 128; // FaceNet output size

  /// Initialize FaceNet model
  static Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      print('Initializing FaceNet model...');
      
      // Load the TFLite model
      _interpreter = await Interpreter.fromAsset('assets/models/facenet.tflite');
      
      // Get input and output tensor shapes
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      
      print('FaceNet model loaded successfully');
      print('Input shape: $inputShape');
      print('Output shape: $outputShape');
      
      _isInitialized = true;
      return true;
    } catch (e) {
      print('Error initializing FaceNet model: $e');
      print('Make sure facenet.tflite is placed in assets/models/');
      _isInitialized = false;
      return false;
    }
  }

  /// Check if FaceNet model is available
  static bool isModelAvailable() {
    return _isInitialized && _interpreter != null;
  }

  /// Generate face embedding using FaceNet
  static Future<List<double>?> generateEmbedding(img.Image faceImage) async {
    if (!_isInitialized || _interpreter == null) {
      print('FaceNet model not initialized');
      return null;
    }

    try {
      // Get input shape from model
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final inputSize = inputShape[1]; // Assuming square input (e.g., 160x160)
      
      print('Preparing image for FaceNet (size: $inputSize x $inputSize)...');
      
      // Resize and normalize image for FaceNet
      final processedImage = _preprocessImage(faceImage, inputSize);
      
      // Prepare input and output buffers
      final input = processedImage.reshape([1, inputSize, inputSize, 3]);
      final output = List.filled(1 * _embeddingSize, 0.0).reshape([1, _embeddingSize]);
      
      // Run inference
      _interpreter!.run(input, output);
      
      // Extract embedding and normalize
      final embedding = List<double>.from(output[0]);
      final normalized = _normalizeEmbedding(embedding);
      
      print('Generated FaceNet embedding (${normalized.length} dimensions)');
      return normalized;
    } catch (e) {
      print('Error generating FaceNet embedding: $e');
      return null;
    }
  }

  /// Preprocess image for FaceNet input
  static List<List<List<List<double>>>> _preprocessImage(img.Image image, int targetSize) {
    // Resize image to model input size
    final resized = img.copyResize(image, width: targetSize, height: targetSize);
    
    // Convert to 4D array [1, height, width, 3]
    final input = List.generate(
      1,
      (_) => List.generate(
        targetSize,
        (y) => List.generate(
          targetSize,
          (x) {
            final pixel = resized.getPixel(x, y);
            // Normalize to [-1, 1] range (standard for FaceNet)
            return [
              (pixel.r / 127.5) - 1.0,
              (pixel.g / 127.5) - 1.0,
              (pixel.b / 127.5) - 1.0,
            ];
          },
        ),
      ),
    );
    
    return input;
  }

  /// Normalize embedding to unit vector (L2 normalization)
  static List<double> _normalizeEmbedding(List<double> embedding) {
    final magnitude = sqrt(embedding.fold(0.0, (sum, val) => sum + val * val));
    return embedding.map((val) => val / magnitude).toList();
  }

  /// Calculate cosine similarity between two embeddings
  static double calculateSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw ArgumentError('Embeddings must have the same length');
    }

    double dotProduct = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }

    // Since embeddings are already normalized, cosine similarity = dot product
    return dotProduct;
  }

  /// Match face against stored embeddings
  static Map<String, dynamic> matchFace(
    List<double> queryEmbedding,
    Map<String, List<double>> storedEmbeddings,
  ) {
    if (storedEmbeddings.isEmpty) {
      return {
        'match': false,
        'confidence': 0.0,
        'message': 'No stored embeddings to compare',
      };
    }

    String? bestMatchId;
    double bestSimilarity = -1.0;

    for (var entry in storedEmbeddings.entries) {
      final similarity = calculateSimilarity(queryEmbedding, entry.value);
      
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestMatchId = entry.key;
      }
    }

    final isMatch = bestSimilarity >= _threshold;

    print('Best match: $bestMatchId with similarity: ${bestSimilarity.toStringAsFixed(4)}');
    print('Threshold: $_threshold, Match: $isMatch');

    return {
      'match': isMatch,
      'employeeId': bestMatchId,
      'confidence': bestSimilarity,
      'threshold': _threshold,
    };
  }

  /// Encode embedding to JSON-safe format
  static String encodeEmbedding(List<double> embedding) {
    return embedding.map((e) => e.toStringAsFixed(6)).join(',');
  }

  /// Decode embedding from JSON string
  static List<double> decodeEmbedding(String encoded) {
    return encoded.split(',').map((e) => double.parse(e)).toList();
  }

  /// Dispose resources
  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

// Helper extension to reshape lists
extension ListExtension<T> on List<T> {
  List reshape(List<int> shape) {
    if (shape.length == 1) return this;
    
    int size = shape.reduce((a, b) => a * b);
    if (length != size) {
      throw ArgumentError('Cannot reshape list of length $length to shape $shape');
    }
    
    return _reshapeRecursive(this, shape, 0)['result'];
  }
  
  Map _reshapeRecursive(List data, List<int> shape, int depth) {
    if (depth == shape.length - 1) {
      return {'result': data, 'consumed': data.length};
    }
    
    List result = [];
    int consumed = 0;
    int elemSize = shape.skip(depth + 1).reduce((a, b) => a * b);
    
    for (int i = 0; i < shape[depth]; i++) {
      final sub = _reshapeRecursive(
        data.skip(consumed).take(elemSize).toList(),
        shape,
        depth + 1,
      );
      result.add(sub['result']);
      consumed += sub['consumed'] as int;
    }
    
    return {'result': result, 'consumed': consumed};
  }
}
