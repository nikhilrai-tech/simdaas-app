import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';

/// Handles FCM token registration and foreground message display.
///
/// Call [init] once at app startup (after Firebase.initializeApp).
/// Call [registerToken] after the user logs in, passing the authenticated ApiService.

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Background messages are handled automatically by the OS — no action needed here.
}

class PushNotificationService {
  static final _messaging = FirebaseMessaging.instance;

  /// Requests permission and wires up foreground message handling.
  static Future<void> init() async {
    // Register background handler (required by firebase_messaging)
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Show an in-app banner when a notification arrives while the app is open
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;

      final ctx = _navigatorKey?.currentContext;
      if (ctx == null) return;

      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.title ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (notification.body != null) Text(notification.body!),
            ],
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });

    // Ensure foreground notifications also show as heads-up on Android
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// Gets the current FCM token and POSTs it to the backend.
  /// Should be called after login, when [apiService] has an active auth token.
  static Future<void> registerToken(ApiService apiService) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('PushNotificationService: FCM token is null');
        return;
      }
      debugPrint('PushNotificationService: registering token ${token.substring(0, 20)}...');

      await apiService.postJson(
        '/notification/api/',
        jsonBody: {'token': token, 'device_type': 'android'},
      );

      debugPrint('PushNotificationService: token registered successfully');

      // Re-register whenever the token refreshes (e.g. after app reinstall)
      _messaging.onTokenRefresh.listen((newToken) {
        apiService.postJson(
          '/notification/api/',
          jsonBody: {'token': newToken, 'device_type': 'android'},
        ).catchError((e) {
          debugPrint('PushNotificationService: token refresh registration failed: $e');
        });
      });
    } catch (e) {
      debugPrint('PushNotificationService: registerToken failed: $e');
    }
  }

  // Holds a reference to the app's navigator key so we can show snackbars
  // from the background message handler without a BuildContext.
  static GlobalKey<NavigatorState>? _navigatorKey;

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }
}
