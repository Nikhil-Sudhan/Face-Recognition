import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'homepage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _apiController =
      TextEditingController(text: 'https://demo.hshrsolutions.com');
  final TextEditingController _usernameController =
      TextEditingController(text: 'thomas550i@gmail.com');
  final TextEditingController _passwordController =
      TextEditingController(text: 'Password.123');
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _allowSelfSigned = false;

  void _signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final api = _apiController.text.trim();
      final key = _usernameController.text.trim();
      final secret = _passwordController.text;

      // Save base URL and perform session login (email/password)
      try {
        ApiClient.setAllowSelfSigned(_allowSelfSigned);
        await ApiClient.setCredentials(baseUrl: api, apiKey: '', apiSecret: '');
        final resp = await ApiClient.sessionLogin(email: key, password: secret);
        if (resp.statusCode != 200) {
          throw Exception('Login failed: ${resp.statusMessage}');
        }
        // store login state
        final result = await AuthService.login(key, 'session');

        setState(() {
          _isLoading = false;
        });

        if (result['success']) {
          // Navigate to homepage on successful login
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
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
            'Use username "root" and password "root" to sign in for demo.\n\n'
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                kToolbarHeight -
                48,
          ),
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
                  controller: _apiController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    hintText: 'https://demo.hshrsolutions.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter API URL';
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
      ),
    );
  }

  @override
  void dispose() {
    _apiController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
