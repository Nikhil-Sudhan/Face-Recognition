import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'simple_image_storage.dart';

class ImageStorageService {
  static const String _faceImagesFolder = 'face_images';

  // Get the app documents directory with fallback
  static Future<Directory> get _appDocumentDir async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      print('Error getting documents directory, trying support directory: $e');
      try {
        return await getApplicationSupportDirectory();
      } catch (e2) {
        print('Error getting support directory, using temporary: $e2');
        return await getTemporaryDirectory();
      }
    }
  }

  // Get the face images directory
  static Future<Directory> get _faceImagesDir async {
    final appDir = await _appDocumentDir;
    final faceDir = Directory(path.join(appDir.path, _faceImagesFolder));

    if (!await faceDir.exists()) {
      await faceDir.create(recursive: true);
    }

    return faceDir;
  }

  // Save face image with employee ID as filename
  static Future<String> saveFaceImage(String tempImagePath, int empId) async {
    try {
      // Verify temp file exists
      final tempFile = File(tempImagePath);
      if (!await tempFile.exists()) {
        throw Exception('Temporary image file does not exist: $tempImagePath');
      }

      final faceDir = await _faceImagesDir;

      final fileName = 'emp_${empId}_face.jpg';
      final savedImagePath = path.join(faceDir.path, fileName);

      // Copy the temporary image to permanent location
      final savedFile = await tempFile.copy(savedImagePath);

      // Delete the temporary file only if it's different from saved location
      if (tempImagePath != savedImagePath && await tempFile.exists()) {
        await tempFile.delete();
      }

      return savedFile.path;
    } catch (e) {
      print('Error saving face image with path_provider: $e');
      try {
        return await SimpleImageStorage.saveFaceImage(tempImagePath, empId);
      } catch (e2) {
        print('Error with fallback storage: $e2');
        rethrow;
      }
    }
  }

  // Get face image path for employee
  static Future<String?> getFaceImagePath(int empId) async {
    try {
      final faceDir = await _faceImagesDir;
      final fileName = 'emp_${empId}_face.jpg';
      final imagePath = path.join(faceDir.path, fileName);
      final imageFile = File(imagePath);

      if (await imageFile.exists()) {
        return imagePath;
      }
      return null;
    } catch (e) {
      print('Error getting face image with path_provider: $e');
      try {
        return await SimpleImageStorage.getFaceImagePath(empId);
      } catch (e2) {
        print('Error with fallback storage: $e2');
        return null;
      }
    }
  }

  // Delete face image for employee
  static Future<bool> deleteFaceImage(int empId) async {
    try {
      final faceDir = await _faceImagesDir;
      final fileName = 'emp_${empId}_face.jpg';
      final imagePath = path.join(faceDir.path, fileName);
      final imageFile = File(imagePath);

      if (await imageFile.exists()) {
        await imageFile.delete();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting face image: $e');
      return false;
    }
  }

  // Update face image (delete old, save new)
  static Future<String> updateFaceImage(String tempImagePath, int empId) async {
    try {
      // Delete existing image if any
      await deleteFaceImage(empId);

      // Save new image
      return await saveFaceImage(tempImagePath, empId);
    } catch (e) {
      print('Error updating face image with path_provider: $e');
      try {
        return await SimpleImageStorage.updateFaceImage(tempImagePath, empId);
      } catch (e2) {
        print('Error with fallback storage: $e2');
        rethrow;
      }
    }
  }

  // Get all face images directory for export
  static Future<Directory> getExportDirectory() async {
    try {
      final appDir = await _appDocumentDir;
      final exportDir = Directory(path.join(appDir.path, 'exported_data'));

      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      return exportDir;
    } catch (e) {
      print('Error creating export directory: $e');
      rethrow;
    }
  }

  // Export all face images to a specific directory
  static Future<String> exportAllFaceImages() async {
    try {
      final faceDir = await _faceImagesDir;
      final exportDir = await getExportDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportPath = path.join(exportDir.path, 'face_images_$timestamp');
      final exportDirectory = Directory(exportPath);

      if (!await exportDirectory.exists()) {
        await exportDirectory.create(recursive: true);
      }

      // Copy all face images
      final faceImages = await faceDir.list().toList();
      int copiedCount = 0;

      for (final entity in faceImages) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          final fileName = path.basename(entity.path);
          final newPath = path.join(exportDirectory.path, fileName);
          await entity.copy(newPath);
          copiedCount++;
        }
      }

      return 'Exported $copiedCount images to: $exportPath';
    } catch (e) {
      print('Error exporting face images: $e');
      rethrow;
    }
  }

  // Get storage info
  static Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final faceDir = await _faceImagesDir;
      final faceImages = await faceDir.list().toList();
      final imageCount =
          faceImages.where((e) => e is File && e.path.endsWith('.jpg')).length;

      // Calculate total size
      int totalSize = 0;
      for (final entity in faceImages) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }

      return {
        'imageCount': imageCount,
        'totalSizeBytes': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'storagePath': faceDir.path,
      };
    } catch (e) {
      print('Error getting storage info: $e');
      return {
        'imageCount': 0,
        'totalSizeBytes': 0,
        'totalSizeMB': '0.00',
        'storagePath': 'Unknown',
      };
    }
  }

  // Cleanup orphaned images (images without corresponding employees)
  static Future<int> cleanupOrphanedImages(List<int> validEmpIds) async {
    try {
      final faceDir = await _faceImagesDir;
      final faceImages = await faceDir.list().toList();
      int deletedCount = 0;

      for (final entity in faceImages) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          final fileName = path.basename(entity.path);
          final match = RegExp(r'emp_(\d+)_face\.jpg').firstMatch(fileName);

          if (match != null) {
            final empId = int.parse(match.group(1)!);
            if (!validEmpIds.contains(empId)) {
              await entity.delete();
              deletedCount++;
            }
          }
        }
      }

      return deletedCount;
    } catch (e) {
      print('Error cleaning up orphaned images: $e');
      return 0;
    }
  }
}
