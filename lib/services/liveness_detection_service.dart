import 'dart:io';
import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Service for detecting fake faces (photos, videos, screens)
/// Uses multiple techniques to verify real person presence
class LivenessDetectionService {
  /// Analyze if the face is from a real person or a photo/screen
  /// 
  /// Techniques used:
  /// 1. Texture analysis - Real skin has more texture variation than photos
  /// 2. Brightness variance - Screens/photos have uniform lighting
  /// 3. Edge sharpness - Photos from screens are too sharp/uniform
  /// 4. Color distribution - Real faces have natural color variation
  /// 5. Face rotation/movement detection (requires multiple frames)
  static Future<Map<String, dynamic>> detectLiveness(
    String imagePath,
    Face face,
  ) async {
    try {
      // Load the image
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        return {
          'isLive': false,
          'confidence': 0.0,
          'reason': 'Failed to decode image',
        };
      }

      // Extract face region with some padding
      final faceBox = face.boundingBox;
      final padding = 20;
      
      final x = (faceBox.left - padding).clamp(0, image.width - 1).toInt();
      final y = (faceBox.top - padding).clamp(0, image.height - 1).toInt();
      final width = (faceBox.width + padding * 2).clamp(1, image.width - x).toInt();
      final height = (faceBox.height + padding * 2).clamp(1, image.height - y).toInt();

      final faceRegion = img.copyCrop(image, x: x, y: y, width: width, height: height);

      // Run multiple liveness checks
      final textureScore = _analyzeTextureVariation(faceRegion);
      final brightnessScore = _analyzeBrightnessVariance(faceRegion);
      final edgeScore = _analyzeEdgeSharpness(faceRegion);
      final colorScore = _analyzeColorDistribution(faceRegion);
      final blurScore = _analyzeBlur(faceRegion);

      // Adjusted weights: reduced brightness importance, increased texture and edge detection
      // This makes it more tolerant to bright lighting but still detects phone screens
      final livenessScore = (
        textureScore * 0.35 +      // Increased: most important for detecting photos
        brightnessScore * 0.10 +   // Reduced: less sensitive to bright lights
        edgeScore * 0.25 +         // Increased: better for screen detection
        colorScore * 0.20 +        // Good for photo/screen detection
        blurScore * 0.10           // Natural micro-movements
      );

      // Further lowered threshold to 0.30 to reduce false rejections in varying lighting
      // Real faces typically score > 0.30, photos/screens typically < 0.25
      final isLive = livenessScore > 0.30;

      String reason = '';
      if (!isLive) {
        if (textureScore < 0.20) reason = 'Low texture variation - possible photo';
        else if (edgeScore < 0.20) reason = 'Screen or printed photo detected';
        else if (colorScore < 0.20) reason = 'Unnatural color distribution';
        else if (blurScore < 0.25) reason = 'Abnormal blur pattern';
        else reason = 'Failed liveness check - possible spoofing attempt';
      }

      return {
        'isLive': isLive,
        'confidence': livenessScore,
        'reason': reason,
        'details': {
          'texture': textureScore,
          'brightness': brightnessScore,
          'edge': edgeScore,
          'color': colorScore,
          'blur': blurScore,
        },
      };
    } catch (e) {
      return {
        'isLive': false,
        'confidence': 0.0,
        'reason': 'Error analyzing image: $e',
      };
    }
  }

  /// Analyze texture variation (real skin has micro-textures)
  static double _analyzeTextureVariation(img.Image face) {
    // OPTIMIZED: Resize to smaller size for faster processing
    final resized = img.copyResize(face, width: 64, height: 64);
    final gray = img.grayscale(resized);
    
    double totalVariation = 0;
    int count = 0;

    // OPTIMIZED: Larger block size for faster processing
    final blockSize = 8;
    for (int y = 0; y < gray.height - blockSize; y += blockSize) {
      for (int x = 0; x < gray.width - blockSize; x += blockSize) {
        final blockPixels = <int>[];
        
        for (int by = 0; by < blockSize; by += 2) { // OPTIMIZED: Sample every 2 pixels
          for (int bx = 0; bx < blockSize; bx += 2) {
            final pixel = gray.getPixel(x + bx, y + by);
            blockPixels.add(pixel.r.toInt());
          }
        }

        final mean = blockPixels.reduce((a, b) => a + b) / blockPixels.length;
        final variance = blockPixels.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / blockPixels.length;
        
        totalVariation += variance;
        count++;
      }
    }

    final avgVariation = count > 0 ? totalVariation / count : 0;
    
    // Adjusted normalization: Real faces typically have variance > 200, photos < 100
    // Increased threshold to be more sensitive to texture differences
    return (avgVariation / 250).clamp(0.0, 1.0);
  }

  /// Analyze brightness variance across face (adjusted for bright lighting tolerance)
  static double _analyzeBrightnessVariance(img.Image face) {
    // OPTIMIZED: Use smaller sample size for faster processing
    final brightnesses = <double>[];
    
    // OPTIMIZED: Reduced grid sampling (was 10x10, now 6x6)
    final stepX = face.width ~/ 6;
    final stepY = face.height ~/ 6;

    for (int y = stepY; y < face.height; y += stepY) {
      for (int x = stepX; x < face.width; x += stepX) {
        final pixel = face.getPixel(x, y);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3;
        brightnesses.add(brightness);
      }
    }

    if (brightnesses.isEmpty) return 0.0;

    final mean = brightnesses.reduce((a, b) => a + b) / brightnesses.length;
    final variance = brightnesses.map((b) => (b - mean) * (b - mean)).reduce((a, b) => a + b) / brightnesses.length;
    final stdDev = math.sqrt(variance);

    // More lenient brightness check: Real faces typically stdDev > 12, screens < 5
    // Increased tolerance for bright lighting conditions
    return (stdDev / 25).clamp(0.0, 1.0);
  }

  /// Analyze edge sharpness (photos from screens are too sharp)
  static double _analyzeEdgeSharpness(img.Image face) {
    // OPTIMIZED: Resize to smaller size and sample pixels for faster processing
    final resized = img.copyResize(face, width: 64, height: 64);
    final gray = img.grayscale(resized);
    double totalEdgeStrength = 0;
    int edgeCount = 0;

    // OPTIMIZED: Sample every 2 pixels for faster processing
    for (int y = 2; y < gray.height - 2; y += 2) {
      for (int x = 2; x < gray.width - 2; x += 2) {
        // Simple edge detection using immediate neighbors
        final gx = 
          -1 * gray.getPixel(x - 1, y - 1).r.toInt() +
          1 * gray.getPixel(x + 1, y - 1).r.toInt() +
          -2 * gray.getPixel(x - 1, y).r.toInt() +
          2 * gray.getPixel(x + 1, y).r.toInt() +
          -1 * gray.getPixel(x - 1, y + 1).r.toInt() +
          1 * gray.getPixel(x + 1, y + 1).r.toInt();

        final gy =
          -1 * gray.getPixel(x - 1, y - 1).r.toInt() +
          -2 * gray.getPixel(x, y - 1).r.toInt() +
          -1 * gray.getPixel(x + 1, y - 1).r.toInt() +
          1 * gray.getPixel(x - 1, y + 1).r.toInt() +
          2 * gray.getPixel(x, y + 1).r.toInt() +
          1 * gray.getPixel(x + 1, y + 1).r.toInt();

        final edgeStrength = math.sqrt((gx * gx + gy * gy).toDouble());
        
        if (edgeStrength > 50) { // Threshold for significant edges
          totalEdgeStrength += edgeStrength;
          edgeCount++;
        }
      }
    }

    if (edgeCount == 0) return 0.0;

    final avgEdgeStrength = totalEdgeStrength / edgeCount;

    // Real faces have moderate edges (100-200), photos/screens are sharper (> 250) or smoother (< 50)
    // We want moderate values, so penalize both extremes
    if (avgEdgeStrength < 50 || avgEdgeStrength > 250) {
      return 0.0;
    } else if (avgEdgeStrength > 100 && avgEdgeStrength < 200) {
      return 1.0;
    } else {
      return 0.5;
    }
  }

  /// Analyze color distribution (real faces have natural skin tone variation)
  static double _analyzeColorDistribution(img.Image face) {
    // OPTIMIZED: Resize and use coarser sampling for faster processing
    final resized = img.copyResize(face, width: 64, height: 64);
    final hues = <double>[];
    final saturations = <double>[];

    // OPTIMIZED: Reduced from 20x20 to 8x8 grid
    final stepX = resized.width ~/ 8;
    final stepY = resized.height ~/ 8;

    for (int y = stepY; y < resized.height; y += stepY) {
      for (int x = stepX; x < resized.width; x += stepX) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r / 255;
        final g = pixel.g / 255;
        final b = pixel.b / 255;

        final max = [r, g, b].reduce((a, b) => a > b ? a : b);
        final min = [r, g, b].reduce((a, b) => a < b ? a : b);
        final delta = max - min;

        // Calculate saturation
        final saturation = max == 0 ? 0.0 : delta / max;
        saturations.add(saturation);

        // Calculate hue
        if (delta == 0) {
          hues.add(0);
        } else if (max == r) {
          hues.add(60 * (((g - b) / delta) % 6));
        } else if (max == g) {
          hues.add(60 * (((b - r) / delta) + 2));
        } else {
          hues.add(60 * (((r - g) / delta) + 4));
        }
      }
    }

    if (hues.isEmpty || saturations.isEmpty) return 0.0;

    // Calculate variance in hue and saturation
    final hueMean = hues.reduce((a, b) => a + b) / hues.length;
    final hueVariance = hues.map((h) => (h - hueMean) * (h - hueMean)).reduce((a, b) => a + b) / hues.length;

    final satMean = saturations.reduce((a, b) => a + b) / saturations.length;
    final saturationVariance = saturations.map((s) => (s - satMean) * (s - satMean)).reduce((a, b) => a + b) / saturations.length;

    // Real faces have moderate color variation
    final hueScore = (math.sqrt(hueVariance) / 30).clamp(0.0, 1.0);
    final satScore = (math.sqrt(saturationVariance) / 0.2).clamp(0.0, 1.0);

    return (hueScore + satScore) / 2;
  }

  /// Analyze blur (photos from screens may have unusual blur patterns)
  static double _analyzeBlur(img.Image face) {
    // OPTIMIZED: Resize for faster processing
    final resized = img.copyResize(face, width: 64, height: 64);
    final gray = img.grayscale(resized);
    
    // Calculate Laplacian variance (measure of blur)
    double laplacianSum = 0;
    int count = 0;

    // OPTIMIZED: Sample every 2 pixels
    for (int y = 2; y < gray.height - 2; y += 2) {
      for (int x = 2; x < gray.width - 2; x += 2) {
        final laplacian = 
          -1 * gray.getPixel(x - 1, y).r.toInt() +
          -1 * gray.getPixel(x + 1, y).r.toInt() +
          -1 * gray.getPixel(x, y - 1).r.toInt() +
          -1 * gray.getPixel(x, y + 1).r.toInt() +
          4 * gray.getPixel(x, y).r.toInt();
        
        laplacianSum += laplacian.abs();
        count++;
      }
    }

    final avgLaplacian = count > 0 ? laplacianSum / count : 0;

    // Real faces have moderate blur (10-30), photos can be too blurry (< 5) or too sharp (> 40)
    if (avgLaplacian < 5 || avgLaplacian > 40) {
      return 0.2;
    } else if (avgLaplacian > 10 && avgLaplacian < 30) {
      return 1.0;
    } else {
      return 0.6;
    }
  }
}
