import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

const _storage = FlutterSecureStorage();
const _kSavedEmail = 'saved_login_email';

// Validation regexes
final _emailRegex = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");
final _usernameRegex = RegExp(r"^[\w\s\-\.]{1,100}$");
final _passwordStrongRegex = RegExp(r"^(?=.*[A-Za-z])(?=.*\d).{8,128}$");

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primary,
              colorScheme.primary.withOpacity(0.8),
              colorScheme.surface,
              colorScheme.surface,
            ],
            stops: const [0.0, 0.4, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Back Button / App Title
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Create Account',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Register form card
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Register',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            TextFormField(
                              controller: _username,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.person),
                              ),
                              maxLength: 30,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Username required';
                                final t = v.trim();
                                if (t.length > 30) return 'Username too long';
                                if (!_usernameRegex.hasMatch(t)) {
                                  return 'Invalid characters in username';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _email,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              maxLength: 254,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Email required';
                                final t = v.trim();
                                if (t.length > 254) return 'Email too long';
                                if (!_emailRegex.hasMatch(t)) return 'Invalid email format';
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _password,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                helperText: 'Min 8 chars, letters & numbers',
                                helperMaxLines: 1,
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              obscureText: _obscurePassword,
                              maxLength: 128,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Password required';
                                final t = v;
                                if (t.length < 8) return 'Min 8 characters';
                                if (t.length > 128) return 'Password too long';
                                if (!_passwordStrongRegex.hasMatch(t)) {
                                  return 'Letters and numbers required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirm,
                              decoration: InputDecoration(
                                labelText: 'Confirm password',
                                prefixIcon: const Icon(Icons.lock_clock),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                ),
                              ),
                              obscureText: _obscureConfirm,
                              maxLength: 128,
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Confirm password';
                                if (v != _password.text) return 'Passwords do not match';
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            _loading
                                ? const Center(child: CircularProgressIndicator())
                                : ElevatedButton(
                                    onPressed: () async {
                                      if (!_formKey.currentState!.validate()) return;
                                      setState(() => _loading = true);
                                      final svc = ref.read(authServiceProvider);
                                      try {
                                        final email = _email.text.trim();
                                        await svc.register(
                                            _username.text.trim(),
                                            email,
                                            _password.text.trim(),
                                            _confirm.text.trim());
                                        // Pre-fill login screen after signup
                                        await _storage.write(
                                            key: _kSavedEmail, value: email);
                                        setState(() => _loading = false);
                                        if (mounted) {
                                          Navigator.of(context).pushReplacementNamed(
                                              '/verify-email',
                                              arguments: email);
                                        }
                                      } catch (e) {
                                        setState(() => _loading = false);
                                        if (e is ApiException) {
                                          final err = ApiError.fromResponse(e.statusCode, e.body);
                                          showGenericErrorSnackBar(context, err.combinedMessages());
                                        } else {
                                          showGenericErrorSnackBar(context, e.toString());
                                        }
                                      }
                                    },
                                    child: const Text('Register'),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text("Already have an account? Sign In"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
