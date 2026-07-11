import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

/// Thrown when the device's location services (GPS) are turned off.
class LocationServiceDisabledError implements Exception {
  @override
  String toString() =>
      'Location services are turned off. Please enable GPS.';
}

/// Thrown when location permission was denied (optionally permanently).
class LocationPermissionDeniedError implements Exception {
  final bool permanently;
  LocationPermissionDeniedError({this.permanently = false});

  @override
  String toString() => permanently
      ? 'Location permission permanently denied. Enable it from app settings.'
      : 'Location permission denied.';
}

class LocationService {
  /// Returns a cached fix instantly (no GPS wait) if the OS has one, or
  /// null if none is cached yet. Use this to move the map immediately
  /// while a fresh, more accurate fix is fetched in the background.
  Future<LatLng?> getLastKnownLocation() async {
    final sw = Stopwatch()..start();
    final pos = await Geolocator.getLastKnownPosition();
    debugPrint('[LocationService] getLastKnownPosition: ${sw.elapsedMilliseconds}ms -> $pos');
    if (pos == null) return null;
    return LatLng(pos.latitude, pos.longitude);
  }

  /// Returns current location as [LatLng].
  ///
  /// Always asks for permission first (regardless of whether GPS is
  /// currently enabled) so the OS permission dialog actually shows up.
  /// Throws [LocationPermissionDeniedError] or [LocationServiceDisabledError]
  /// on failure so callers can show a precise, actionable message.
  Future<LatLng> getCurrentLocation() async {
    final sw = Stopwatch()..start();
    LocationPermission permission = await Geolocator.checkPermission();
    debugPrint('[LocationService] checkPermission: ${sw.elapsedMilliseconds}ms -> $permission');
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      debugPrint('[LocationService] requestPermission: ${sw.elapsedMilliseconds}ms -> $permission');
    }
    if (permission == LocationPermission.denied) {
      throw LocationPermissionDeniedError();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionDeniedError(permanently: true);
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint('[LocationService] isLocationServiceEnabled: ${sw.elapsedMilliseconds}ms -> $serviceEnabled');
    if (!serviceEnabled) {
      throw LocationServiceDisabledError();
    }

    // Both `getCurrentPosition()` and the very first stream emission can
    // be a stale/cached fused location (observed on device: ~7.7km
    // accuracy, same exact coords every time) -- the GPS chip hasn't
    // produced a real fix yet. Listen to the stream and keep the best
    // (lowest-accuracy-number) fix seen, accepting early once one is
    // "good enough" (<=50m), or returning whatever was best once the
    // timeout hits rather than failing outright.
    final completer = Completer<Position>();
    Position? best;
    late StreamSubscription<Position> sub;
    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((pos) {
      debugPrint('[LocationService] stream candidate: ${sw.elapsedMilliseconds}ms -> ${pos.latitude},${pos.longitude} (accuracy ${pos.accuracy}m)');
      if (best == null || pos.accuracy < best!.accuracy) {
        best = pos;
      }
      if (pos.accuracy <= 50 && !completer.isCompleted) {
        completer.complete(pos);
      }
    });

    Position pos;
    try {
      pos = await completer.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      if (best == null) rethrow;
      pos = best!;
    } finally {
      await sub.cancel();
    }
    debugPrint('[LocationService] resolved: ${sw.elapsedMilliseconds}ms -> ${pos.latitude},${pos.longitude} (accuracy ${pos.accuracy}m)');
    return LatLng(pos.latitude, pos.longitude);
  }
}
