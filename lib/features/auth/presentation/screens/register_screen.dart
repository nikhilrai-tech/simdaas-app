import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _username,
                decoration: const InputDecoration(labelText: 'Username'),
                maxLength: 100,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Username required';
                  if (v.trim().length > 100) return 'Username too long';
                  if (!_usernameRegex.hasMatch(v.trim())) {
                    return 'Invalid characters in username';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
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
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'Minimum 8 chars, include letters and numbers',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                obscureText: _obscurePassword,
                maxLength: 128,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password required';
                  final t = v;
                  if (t.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  if (t.length > 128) return 'Password too long';
                  if (!_passwordStrongRegex.hasMatch(t)) {
                    return 'Password must include letters and numbers';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _confirm,
                decoration: InputDecoration(
                    labelText: 'Confirm password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    )),
                obscureText: _obscureConfirm,
                maxLength: 128,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Confirm password';
                  if (v.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  if (v.length > 128) return 'Password too long';
                  if (v != _password.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        if (_password.text != _confirm.text) {
                          showInfoSnackBar(context, 'Passwords do not match');
                          return;
                        }
                        setState(() => _loading = true);
                        final svc = ref.read(authServiceProvider);
                        try {
                          await svc.register(
                              _username.text.trim(),
                              _email.text.trim(),
                              _password.text.trim(),
                              _confirm.text.trim());
                          setState(() => _loading = false);
                          if (mounted) {
                            Navigator.of(context).pushReplacementNamed(
                                '/verify-email',
                                arguments: _email.text.trim());
                          }
                        } catch (e) {
                          setState(() => _loading = false);
                          // Diagnostic logging: print exception shape so we can
                          // determine whether the ApiException carries a body.
                          if (e is ApiException) {
                            debugPrint(
                                'register: caught ApiException type=${e.runtimeType} status=${e.statusCode} body=${e.body}');
                            final err =
                                ApiError.fromResponse(e.statusCode, e.body);
                            final combined = err.combinedMessages();

                            // Show the combined API message in a SnackBar so the
                            // same content is visible in non-modal UI. Use the
                            // existing helper for consistent styling.
                            showGenericErrorSnackBar(context, combined);
                          } else {
                            debugPrint('register: caught non-ApiException: $e');
                            showGenericErrorSnackBar(context, e.toString());
                          }
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 24.0, vertical: 12.0),
                        child: Text('Register'),
                      ),
                    )
            ],
          ),
        ),
      ),
    );
  }
}
