import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:simdaas/core/services/auth_service.dart';

class ForgotPasswordEmailScreen extends ConsumerStatefulWidget {
  const ForgotPasswordEmailScreen({super.key});

  @override
  ConsumerState<ForgotPasswordEmailScreen> createState() =>
      _ForgotPasswordEmailScreenState();
}

class _ForgotPasswordEmailScreenState
    extends ConsumerState<ForgotPasswordEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter your registered email. We will send a 6-digit verification code to your email.',
              ),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Please enter your email'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        setState(() => _loading = true);
                        final auth = ref.read(authServiceProvider);
                        final email = _emailCtrl.text.trim();
                        try {
                          await auth.requestPasswordReset(email);
                          if (!mounted) return;
                          showSuccessSnackBar(
                              context, 'Verification code sent to email');
                          // Navigate to confirm screen with email
                          if (mounted) {
                            Navigator.of(context).pushNamed(
                                '/forgot-password-confirm',
                                arguments: {'email': email});
                          }
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
                      child: const Text('Send verification code')),
            ],
          ),
        ),
      ),
    );
  }
}
