import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/mpin_service.dart';
import '../storage/secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'homepage.dart';
import 'mpin_setup_page.dart';
import 'attendance_camera.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _clientCodeController =
      TextEditingController(text: 'demo');
  final TextEditingController _usernameController =
      TextEditingController(text: 'thomas550i@gmail.com');
  final TextEditingController _passwordController =
      TextEditingController(text: 'Password.123');
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _allowSelfSigned = false;
  
  static const String _baseDomain = 'hshrsolutions.com';

  @override
  void initState() {
    super.initState();
    _loadSavedClientCode();
  }

  Future<void> _loadSavedClientCode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString('client_code');
    if (savedCode != null && savedCode.isNotEmpty) {
      setState(() {
        _clientCodeController.text = savedCode;
      });
    }
  }

  Future<void> _saveClientCode(String clientCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('client_code', clientCode);
  }

  void _signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final clientCode = _clientCodeController.text.trim();
      final api = 'https://$clientCode.$_baseDomain';
      final email = _usernameController.text.trim();
      final password = _passwordController.text;

      try {
        ApiClient.setAllowSelfSigned(_allowSelfSigned);
        
        // Set base URL first
        await ApiClient.setCredentials(baseUrl: api, apiKey: '', apiSecret: '');
        
        // Call custom HR login API
        final resp = await ApiClient.post(
          '/api/method/cmenu.api.hr_login',
          data: {
            'email': email,
            'password': password,
          },
        );
        
        if (resp.statusCode != 200) {
          throw Exception('Login failed: ${resp.statusMessage}');
        }

        // Extract user details from response
        final userDetails = resp.data['message'];
        if (userDetails == null) {
          throw Exception('Invalid response from server');
        }
        
        final apiKey = userDetails['api_key'];
        final apiSecret = userDetails['api_secret'];
        
        if (apiKey == null || apiSecret == null || apiKey.isEmpty || apiSecret.isEmpty) {
          throw Exception('API credentials not found in response');
        }
        
        // Store API credentials
        await ApiClient.setCredentials(
          baseUrl: api,
          apiKey: apiKey,
          apiSecret: apiSecret,
        );
        
        // Save user credentials for re-authentication
        await AppSecureStorage.saveUserCredentials(email: email, password: password);
        
        // Store login state
        final result = await AuthService.login(email, apiKey);

        // Save client code for future use
        await _saveClientCode(clientCode);

        setState(() {
          _isLoading = false;
        });

        if (result['success']) {
          // Check if MPIN is set
          final mpinSet = await MpinService.isMpinSet();

          if (!mpinSet) {
            // First time login - set up MPIN
            if (!mounted) return;
            final mpinSetupResult = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MpinSetupPage(),
              ),
            );

            if (mpinSetupResult != true) {
              // User cancelled MPIN setup
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('MPIN setup is required'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
          }

          // Navigate directly to camera for attendance
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AttendanceCameraPage()),
          );

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        String message = 'Login failed: $e';
        if (e is DioException) {
          final type = e.type;
          if (kIsWeb && type == DioExceptionType.unknown) {
            message =
                'Network error in browser (likely CORS). Please enable CORS on the API server or run the app on desktop/mobile for testing.';
          } else if (type == DioExceptionType.connectionTimeout ||
              type == DioExceptionType.receiveTimeout) {
            message = 'Connection timed out. Check API URL and connectivity.';
          } else if (type == DioExceptionType.badResponse) {
            message =
                'Server error ${e.response?.statusCode}: ${e.response?.statusMessage}';
          } else if (type == DioExceptionType.connectionError) {
            message = 'Connection error. Verify internet and API URL.';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Help'),
          content: const Text(
            'If you forgot your credentials, please contact your administrator.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Login'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
                const Icon(
                  Icons.person,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 32),
                const Text(
                  'Sign In',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _clientCodeController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Client Code (Subdomain)',
                    hintText: 'demo',
                    helperText: 'Will form: https://[code].hshrsolutions.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.domain),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter client code';
                    }
                    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(value)) {
                      return 'Only letters, numbers, and hyphens allowed';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'User Name (Email)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter username/email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                CheckboxListTile(
                  value: _allowSelfSigned,
                  onChanged: (v) =>
                      setState(() => _allowSelfSigned = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Allow self-signed/invalid SSL (dev only)'),
                  subtitle: const Text(
                      'Enable if you see CERTIFICATE_VERIFY_FAILED on desktop/mobile'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _showHelp,
                  child: const Text('Need Help?'),
                ),
              ],
            ),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _clientCodeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
