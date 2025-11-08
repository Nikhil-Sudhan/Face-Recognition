import 'dart:io';

class SimpleImageStorage {
  static const String _faceImagesFolder = 'face_images';

  // Get a simple app directory path
  static String get _appDirPath {
    // This uses a simple approach for internal storage
    return '/data/data/com.example.face_recognition_attendance/files';
  }

  // Get or create face images directory
  static Future<Directory> get _faceImagesDir async {
    final appDir = Directory(_appDirPath);
    final faceDir = Directory('${appDir.path}/$_faceImagesFolder');

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

      // Read the image data
      final imageBytes = await tempFile.readAsBytes();

      // Create face images directory
      final faceDir = await _faceImagesDir;

      final fileName = 'emp_${empId}_face.jpg';
      final savedImagePath = '${faceDir.path}/$fileName';

      // Write image to permanent location
      final savedFile = File(savedImagePath);
      await savedFile.writeAsBytes(imageBytes);

      // Delete the temporary file if it's different from saved location
      if (tempImagePath != savedImagePath && await tempFile.exists()) {
        await tempFile.delete();
      }

      return savedFile.path;
    } catch (e) {
      rethrow;
    }
  }

  // Get face image path for employee
  static Future<String?> getFaceImagePath(int empId) async {
    try {
      final faceDir = await _faceImagesDir;
      final fileName = 'emp_${empId}_face.jpg';
      final imagePath = '${faceDir.path}/$fileName';
      final imageFile = File(imagePath);

      if (await imageFile.exists()) {
        return imagePath;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Delete face image for employee
  static Future<bool> deleteFaceImage(int empId) async {
    try {
      final faceDir = await _faceImagesDir;
      final fileName = 'emp_${empId}_face.jpg';
      final imagePath = '${faceDir.path}/$fileName';
      final imageFile = File(imagePath);

      if (await imageFile.exists()) {
        await imageFile.delete();
        return true;
      }
      return false;
    } catch (e) {
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
      rethrow;
    }
  }
}
