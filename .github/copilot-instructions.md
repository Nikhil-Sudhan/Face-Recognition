# Face Recognition Attendance System - AI Coding Guide

## Architecture Overview

This is **Gro Face+**, a Flutter mobile attendance app with offline-first capabilities that syncs with an ERPNext backend API. The app uses Google ML Kit for face detection, TensorFlow Lite FaceNet for recognition (with fallback feature extraction), and liveness detection to prevent spoofing.

### Core Data Flow
1. **Login** → Custom HR login API (`/api/method/cmenu.api.hr_login`) returns API key/secret
2. **Face Recognition** → FaceNet 512-dim embeddings (or 128-dim fallback) → SQLite employee DB → Real-time camera matching
3. **Attendance Marking** → Posts to ERPNext `Employee Checkin` resource → Queued offline if network fails
4. **Sync** → `ErpNextSyncService.syncEmployees()` pulls employee data + face_data field → `OfflineQueueService.flush()` retries failed checkins

### Key Service Boundaries

**Local-First Services** (SQLite + SharedPreferences):
- `DatabaseService` - Employee and attendance records (local cache with ERPNext sync)
- `AuthService` - Simple login state (SharedPreferences)
- `FaceRecognitionService` - Feature extraction (delegates to FaceNetService if model available)
- `FaceNetService` - TensorFlow Lite model runner (512-dim embeddings from `facenet.tflite`)
- `MpinService` - SHA-256 hashed 4-digit MPIN for accessing admin features

**API Integration** (ERPNext backend):
- `ApiClient` - Dio-based client with token auth (`Authorization: token apiKey:apiSecret`)
- `AttendanceService` - Maps email → ERPNext Employee name, determines IN/OUT/auto-toggle log type
- `OfflineQueueService` - Queues failed checkins to SharedPreferences JSON array
- `ErpNextSyncService` - Bidirectional employee sync with auto-reauth on 401/403

**Advanced Features**:
- `LivenessDetectionService` - Multi-factor anti-spoofing (texture, edge, color, blur analysis)
- `FaceMappingService` - Bridges local empId → email for API calls

**Critical Design Patterns**:
1. **Dual Employee Models**: Local `Employee` (empId, faceData) vs ERPNext `Employee` (name, company_email). `erpNextId` field links them.
2. **Device Type Modes**: BOTH (auto-toggle IN/OUT), IN-only, OUT-only devices (configurable in Settings)

## Development Workflows

### Running the App
```bash
flutter pub get
flutter run                    # Auto-selects connected device
flutter run -d chrome          # Web (note: CORS issues with ERPNext API)
flutter run -d windows         # Desktop
```

**Build for Production**:
```bash
# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# Signing configured via android/key.properties (see android/keystore/KEYSTORE_CREDENTIALS.txt)
```

### Face Recognition Setup
**Current State**: Uses TensorFlow Lite FaceNet model (`assets/models/facenet.tflite`) for 512-dimensional embeddings. Falls back to enhanced color/texture feature extraction if model missing.

**Model Requirements**: 
- Input: 160×160×3 (RGB image)
- Output: 512-dim normalized embedding (cosine similarity for matching)
- Download scripts: `download_facenet.ps1` / `download_facenet.py` in root directory

**Matching Threshold**: 0.45 cosine similarity (balanced to reduce false negatives while maintaining security). See `FaceRecognitionService._threshold`.

**Liveness Detection**: Multi-factor analysis optimized for varying lighting conditions:
- Texture variance (0.35 weight) - detects photo printouts
- Edge sharpness (0.25 weight) - detects phone screens
- Color distribution (0.20 weight)
- Brightness variance (0.10 weight) - reduced to tolerate bright lighting
- Blur analysis (0.10 weight)
- Overall liveness threshold: 0.30 (reduced from 0.35 to minimize false rejections)

### Testing API Integration
- Demo credentials: `thomas550i@gmail.com` / `Password.123` (hardcoded in `signin.dart`)
- API base URL: `https://demo.hshrsolutions.com`
- Custom HR login endpoint: `/api/method/cmenu.api.hr_login` (returns api_key/api_secret)
- Use `ApiClient.setAllowSelfSigned(true)` BEFORE `setCredentials()` for dev servers
- API credentials stored in `flutter_secure_storage` (encrypted on-device)

### Database Inspection
```bash
# SQLite DB location varies by platform:
# Android: /data/data/com.example.face_recognition_attendance/databases/attendance.db
# Windows: %APPDATA%\com.example\face_recognition_attendance\databases\attendance.db
# Use Android Studio Database Inspector or sqlite3 CLI
```

### MPIN System
- 4-digit numeric PIN for accessing admin features (HomePage, Settings)
- SHA-256 hashed in SharedPreferences
- Required after face recognition login
- Setup flow: LoginPage → AttendanceCameraPage → MpinVerificationPage → HomePage

## Project-Specific Conventions

### Face Data Storage
- Employee face embeddings stored as JSON string in `Employee.faceData` field
- Format: `jsonEncode(List<double>)` - 512-element (or 128 fallback) normalized feature vector
- Matching uses cosine similarity: `dot(v1, v2) / (||v1|| * ||v2||)`
- Threshold: 0.45 (balanced to reduce false negatives while maintaining security)

### Attendance Logic (ERPNext-specific)
- Must query last `Employee Checkin` log_type to determine if next should be "IN" or "OUT"
- Employee lookup supports both `company_email` and `personal_email` fields
- Time format: ISO8601 (`DateTime.now().toIso8601String()`)
- Device type logic:
  - `IN` device: Always posts log_type="IN"
  - `OUT` device: Always posts log_type="OUT"  
  - `BOTH` device: Omits log_type field → ERPNext auto-toggles based on last checkin

### Error Handling Pattern
All service methods return `Map<String, dynamic>` with:
```dart
{
  'success': bool,
  'message': String,
  'data': dynamic,  // Optional payload
}
```
Example: `AttendanceService.checkinByEmail()`, `ErpNextSyncService.syncEmployees()`

### UI Navigation Flow
```
LoginPage (signin.dart)
  └─> AttendanceCameraPage (attendance_camera.dart) - Real-time face recognition kiosk
       ├─> MpinVerificationPage - 4-digit PIN entry for admin access
       │    └─> HomePage (homepage.dart) - Employee CRUD, settings, export
       │         ├─> AddEditEmployeePage - Manual employee management + face capture
       │         ├─> SettingsPage - API config, device type, data export/import
       │         └─> FaceDetectionCameraPage - ML Kit face detection for enrollment
       └─> (Long press logo) → MPIN setup/verification flow
```

### Camera Permission Pattern
Always check/request camera permission before accessing camera:
```dart
final status = await Permission.camera.request();
if (status.isGranted) { /* initialize camera */ }
else if (status.isPermanentlyDenied) { openAppSettings(); }
```
See `AttendanceCameraPage._requestPermissionsAndInitialize()` for reference implementation.

### Double Attendance Prevention
- `_isProcessingAttendance` flag prevents concurrent processing
- `_lastProcessedEmployeeId` and `_lastProcessedTime` track last match
- 5-second cooldown window between same-employee checkins
- Pattern: Set flag → process → reset flag in `finally` block

## Critical Integration Points

### API Client Configuration
- Credentials stored in `flutter_secure_storage` (encrypted on device)
- Token-based auth: `Authorization: token apiKey:apiSecret` header (not session cookies)
- Call `ApiClient.setCredentials()` after login to persist credentials
- `ApiClient.setAllowSelfSigned(true)` must be called BEFORE `setCredentials()` for dev servers

### ERPNext HR Login Flow
```dart
// 1. Login via custom endpoint
final resp = await ApiClient.post('/api/method/cmenu.api.hr_login', data: {
  'email': email,
  'password': password,
});

// 2. Extract credentials from response
final userDetails = resp.data['message'];
final apiKey = userDetails['api_key'];
final apiSecret = userDetails['api_secret'];

// 3. Save for future requests
await ApiClient.setCredentials(baseUrl: url, apiKey: apiKey, apiSecret: apiSecret);
await AppSecureStorage.saveUserCredentials(email: email, password: password);
```

### Auto-Reauth Pattern
`ErpNextSyncService._ensureAuthentication()` demonstrates retry logic:
1. Try API call with existing credentials
2. If 401/403, retrieve saved user email/password
3. Re-login via `/api/method/cmenu.api.hr_login`
4. Update stored api_key/api_secret
5. Retry original request

### Offline Queue Mechanism
```dart
// On network failure during checkin:
try {
  await AttendanceService.checkinByEmail(email);
} catch (e) {
  await OfflineQueueService.enqueue(email, DateTime.now().toIso8601String());
}

// On app resume or manual sync:
final syncedCount = await OfflineQueueService.flush();
```
Queue stored as JSON array in SharedPreferences key `'offline_checkins'`.

### Face Recognition Process
1. `AttendanceCameraPage` captures frames via camera plugin
2. `_faceDetector.processImage()` (ML Kit) detects face bounding box + landmarks
3. `LivenessDetectionService.detectLiveness()` validates real person (not photo/screen)
4. Crop face ROI with padding → `FaceRecognitionService.extractFaceFeatures()`
5. If FaceNet model available: `FaceNetService.generateEmbedding()` → 512-dim vector
6. If no model: Fallback feature extraction (color histograms, LBP texture, edge orientation) → 128-dim
7. `FaceRecognitionService.recognizeFace()` compares against all stored `Employee.faceData` using cosine similarity
8. Returns matched `Employee` if similarity > 0.55
9. `FaceMappingService.getEmailForEmployeeId()` retrieves email
10. `AttendanceService.checkinByEmail()` posts to ERPNext

### TensorFlow Lite Model Loading
```dart
// FaceNetService initialization
_interpreter = await Interpreter.fromAsset('assets/models/facenet.tflite');
final outputShape = _interpreter!.getOutputTensor(0).shape;
_embeddingSize = outputShape[1]; // Dynamically set from model (512 or 128)
```
Model must be listed in `pubspec.yaml` under `flutter: assets:` section.

## Common Pitfalls

1. **CORS Issues on Web**: ERPNext API typically lacks CORS headers. Use desktop/mobile for testing.
2. **Face Detection Latency**: ML Kit runs on every frame. Throttle with `_isDetecting` flag pattern.
3. **ERPNext Employee Name vs ID**: API uses `name` field (unique identifier, often email-like), not numeric ID.
4. **Self-Signed Certs**: Enable via `ApiClient.setAllowSelfSigned(true)` BEFORE calling `setCredentials()`.
5. **Double Attendance**: Always check last log_type before posting new checkin to alternate IN/OUT correctly.
6. **Device Type Configuration**: BOTH mode requires omitting log_type field in POST request (ERPNext auto-toggles). IN/OUT modes must include explicit log_type.
7. **Employee ID Mapping**: ERPNext `employee` field (e.g., "HR-EMP-00001") must be converted to numeric `empId` for local DB. Use hash fallback if extraction fails.
8. **Liveness Detection False Negatives**: Bright lighting can trigger false positives. Current thresholds: 0.30 overall (reduced from 0.35), 0.10 brightness weight, 0.20 minimum texture/edge/color scores.
9. **Concurrent Attendance Processing**: Use `_isProcessingAttendance` lock in camera pages to prevent race conditions during face matching.
10. **Missing FaceNet Model**: App gracefully falls back to 128-dim feature extraction if `facenet.tflite` missing. Always check `FaceNetService.isModelAvailable()` before feature extraction.

## File Organization

- `lib/services/` - All business logic (no UI dependencies)
- `lib/pages/` - Full-page screens with navigation
- `lib/screens/` - Simpler dedicated screens (e.g., kiosk mode)
- `lib/models/` - Plain Dart classes with `toMap()`/`fromMap()` for SQLite
- `lib/storage/` - Persistent storage wrappers (secure storage, preferences)

## Dependencies to Know

- **google_mlkit_face_detection**: Face bounding box + landmarks (NOT embeddings)
- **sqflite**: Local SQL database for offline employee/attendance cache
- **dio**: HTTP client with interceptors, better error handling than `http`
- **camera**: Low-level camera access for real-time face capture
- **image**: Image processing library for cropping face ROI and feature extraction
- **tflite_flutter**: TensorFlow Lite runtime for FaceNet model inference (512-dim embeddings)
- **flutter_secure_storage**: Encrypted key-value storage for API credentials (uses Keychain/Keystore)
- **crypto**: SHA-256 hashing for MPIN (never store plaintext PINs)
- **permission_handler**: Runtime permissions for camera access (required Android 6+, iOS always)
