import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';

/// Prompts the user to exempt the app from Android's battery optimizations
/// (Doze / App Standby), which otherwise periodically freeze the live
/// telemetry WebSocket and cooldown timers while the app is backgrounded.
///
/// Android only — iOS has no equivalent user-facing permission (background
/// execution there is governed by declared Background Modes, not a runtime
/// prompt), so every method here is a no-op elsewhere.
class BatteryOptimizationService {
  static const _storage = FlutterSecureStorage();
  static const _askedKey = 'battery_opt_prompt_shown';

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True if the app is already exempted from battery optimizations.
  static Future<bool> isIgnoringOptimizations() async {
    if (!_isAndroid) return true;
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (e) {
      debugPrint('BatteryOptimizationService.isIgnoringOptimizations: $e');
      return false;
    }
  }

  /// Shows the system "allow this app to run in background" dialog.
  /// Safe to call directly from a Settings screen button — always shows
  /// the prompt (or a no-op if already granted).
  static Future<bool> request() async {
    if (!_isAndroid) return true;
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('BatteryOptimizationService.request: $e');
      return false;
    }
  }

  /// Shows the prompt automatically, but only the first time ever (per
  /// install) — called once after login. Doesn't re-nag on every app open;
  /// users who dismiss it can still grant it later from Settings.
  static Future<void> requestOnceAfterLogin() async {
    if (!_isAndroid) return;
    try {
      if (await isIgnoringOptimizations()) return;
      final alreadyAsked = await _storage.read(key: _askedKey);
      if (alreadyAsked == 'true') return;
      await _storage.write(key: _askedKey, value: 'true');
      await request();
    } catch (e) {
      debugPrint('BatteryOptimizationService.requestOnceAfterLogin: $e');
    }
  }
}
