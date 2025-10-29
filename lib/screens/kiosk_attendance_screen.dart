import 'package:flutter/material.dart';
import '../services/attendance_service.dart';

class KioskAttendanceScreen extends StatefulWidget {
  const KioskAttendanceScreen({super.key});

  @override
  State<KioskAttendanceScreen> createState() => _KioskAttendanceScreenState();
}

class _KioskAttendanceScreenState extends State<KioskAttendanceScreen> {
  bool _busy = false;
  String? _status;

  Future<void> onFaceMatched(String email) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Marking attendance for $email...';
    });
    final result = await AttendanceService.checkinByEmail(email);
    setState(() {
      _busy = false;
      _status = result['success'] == true
          ? (result['message'] as String)
          : 'Failed: ${result['message']}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kiosk Attendance')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Camera running... (wire to face recognition)',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_status != null) Text(_status!),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => onFaceMatched('thomas550i@gmail.com'),
                child: _busy
                    ? const CircularProgressIndicator()
                    : const Text('Simulate Match: Thomas'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


