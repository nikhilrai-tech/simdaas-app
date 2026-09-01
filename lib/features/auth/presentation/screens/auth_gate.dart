import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/widgets/agrios_splash_screen.dart';
import 'package:simdaas/features/auth/presentation/screens/login_screen.dart';
import 'package:simdaas/temp_features/control_centres_dashboard.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  // Keeps the branded splash on screen for at least this long, so it reads
  // as an intentional brand moment rather than a flash — auth init from
  // secure storage is often near-instant and would otherwise skip straight
  // to the login/dashboard screen.
  static const _minSplashDuration = Duration(milliseconds: 1200);
  bool _minDurationElapsed = false;

  @override
  void initState() {
    super.initState();
    Timer(_minSplashDuration, () {
      if (mounted) setState(() => _minDurationElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);

    // Wait until auth service has loaded persisted tokens AND the minimum
    // splash duration has elapsed.
    if (!auth.isInitialized || !_minDurationElapsed) {
      return const AgriosSplashScreen();
    }

    // If token exists, go to dashboard; otherwise show login
    if (auth.token != null) {
      return const TempDashboard();
    }

    return const LoginScreen();
  }
}
