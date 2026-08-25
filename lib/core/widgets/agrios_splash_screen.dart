import 'package:flutter/material.dart';

/// Branded loading screen shown while [AuthGate] waits for persisted auth
/// state to load. Mirrors the native splash (white background + logo) so
/// the hand-off from OS splash → first Flutter frame doesn't flash a bare
/// spinner, and adds the "Powered by Simdaas" byline the native splash
/// can't render as crisp scalable text.
class AgriosSplashScreen extends StatelessWidget {
  const AgriosSplashScreen({super.key});

  static const _agriosBlue = Color(0xFF0057A8);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/splash/agrios_splash_logo.png'),
              width: 260,
            ),
            SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(_agriosBlue),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Powered by Simdaas',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
