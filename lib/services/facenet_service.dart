import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:math';

class FaceNetService {
  static Interpreter? _interpreter;
  static bool _isInitialized = false;
  static const double _threshold = 0.5; // Cosine similarity threshold for face matching
  static int _embeddingSize = 512; // FaceNet output size (will be set dynamically from model)

  /// Initialize FaceNet model
  static Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Load the TFLite model
      _interpreter = await Interpreter.fromAsset('assets/models/facenet.tflite');
      
      // Get output tensor shape
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      
      // Set embedding size dynamically from model output shape
      _embeddingSize = outputShape[1]; // [1, 512] -> 512
      
      _isInitialized = true;
      return true;
    } catch (e) {
      _isInitialized = false;
      return false;
    }
  }

  /// Check if FaceNet model is available
  static bool isModelAvailable() {
    return _isInitialized && _interpreter != null;
  }

  /// Get the embedding size (512 for this model)
  static int getEmbeddingSize() {
    return _embeddingSize;
  }

  /// Generate face embedding using FaceNet
  static Future<List<double>?> generateEmbedding(img.Image faceImage) async {
    if (!_isInitialized || _interpreter == null) {
      return null;
    }

    try {
      // Get input shape from model
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final inputSize = inputShape[1]; // Assuming square input (e.g., 160x160)
      
      // Enhance image quality before processing
      final enhancedImage = _enhanceImage(faceImage);
      
      // Resize and normalize image for FaceNet - returns already shaped [1, h, w, 3]
      final input = _preprocessImage(enhancedImage, inputSize);
      
      // Prepare output buffer
      final output = List.generate(1, (_) => List.filled(_embeddingSize, 0.0));
      
      // Run inference
      _interpreter!.run(input, output);
      
      // Extract embedding and normalize
      final embedding = List<double>.from(output[0]);
      final normalized = _normalizeEmbedding(embedding);
      
      return normalized;
    } catch (e) {
      return null;
    }
  }

  /// Enhance image quality before FaceNet processing
  static img.Image _enhanceImage(img.Image image) {
    // Auto-adjust contrast for better feature extraction
    final adjusted = img.adjustColor(image, contrast: 1.1, brightness: 1.05);
    
    // Apply slight sharpening to enhance facial features
    return img.adjustColor(adjusted, saturation: 1.05);
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
