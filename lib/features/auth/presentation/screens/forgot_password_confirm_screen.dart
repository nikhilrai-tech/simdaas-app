import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

class ForgotPasswordConfirmScreen extends ConsumerStatefulWidget {
  const ForgotPasswordConfirmScreen({super.key, this.email});
  final String? email;

  @override
  ConsumerState<ForgotPasswordConfirmScreen> createState() =>
      _ForgotPasswordConfirmScreenState();
}

class _ForgotPasswordConfirmScreenState
    extends ConsumerState<ForgotPasswordConfirmScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.email != null) _emailCtrl.text = widget.email!;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _validatePassword(String v) {
    if (v.length < 8) return false;
    if (!RegExp(r'[A-Z]').hasMatch(v)) return false;
    if (!RegExp(r'[0-9]').hasMatch(v)) return false;
    if (!RegExp(r'[!@#\$%\^&\*(),.?":{}|<>]').hasMatch(v)) return false;
    return true;
  }

  final _emailRegex = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$");

  @override
  Widget build(BuildContext context) {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is Map && arg['email'] is String && _emailCtrl.text.isEmpty) {
      _emailCtrl.text = arg['email'];
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Enter the 6-digit code sent to your email and choose a new password.'),
                const SizedBox(height: 12),
                Form(
                  key: _formKey,
                  child: Column(children: [
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      maxLength: 254,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please enter your email';
                        }
                        final t = v.trim();
                        if (t.length > 254) return 'Email too long';
                        if (!_emailRegex.hasMatch(t)) {
                          return 'Invalid email format';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _codeCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Verification code'),
                      keyboardType: TextInputType.number,
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter the verification code'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter password';
                        if (!_validatePassword(v)) {
                          return 'Password must be stronger';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscure,
                      decoration:
                          const InputDecoration(labelText: 'Confirm password'),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Confirm password';
                        if (v != _passwordCtrl.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _loading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: () async {
                              if (!_formKey.currentState!.validate()) return;
                              setState(() => _loading = true);
                              final auth = ref.read(authServiceProvider);
                              final email = _emailCtrl.text.trim();
                              final code = _codeCtrl.text.trim();
                              final pw = _passwordCtrl.text;
                              try {
                                await auth.confirmPasswordReset(
                                    email, code, pw);
                                if (!mounted) return;
                                showSuccessSnackBar(
                                    context, 'Password reset successful');
                                Navigator.of(context)
                                    .pushReplacementNamed('/login');
                              } catch (e) {
                                if (e is ApiException) {
                                  final err = ApiError.fromResponse(
                                      e.statusCode, e.body);
                                  showApiErrorSnackBar(context, err);
                                } else {
                                  showGenericErrorSnackBar(
                                      context, e.toString());
                                }
                              } finally {
                                if (mounted) setState(() => _loading = false);
                              }
                            },
                            child: const Text('Reset password')),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () async {
                          final email = _emailCtrl.text.trim();
                          if (email.isEmpty) {
                            showInfoSnackBar(context, 'Enter email to resend');
                            return;
                          }
                          setState(() => _loading = true);
                          try {
                            await ref
                                .read(authServiceProvider)
                                .resendPasswordReset(email);
                            if (!mounted) return;
                            showSuccessSnackBar(
                                context, 'Verification code sent successfully');
                          } catch (e) {
                            if (e is ApiException) {
                              final err =
                                  ApiError.fromResponse(e.statusCode, e.body);
                              showApiErrorSnackBar(context, err);
                            } else {
                              showGenericErrorSnackBar(context, e.toString());
                            }
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        },
                        child: const Text('Resend code'))
                  ]),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
