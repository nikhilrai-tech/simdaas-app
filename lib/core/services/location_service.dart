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
  /// Returns current location as [LatLng].
  ///
  /// Always asks for permission first (regardless of whether GPS is
  /// currently enabled) so the OS permission dialog actually shows up.
  /// Throws [LocationPermissionDeniedError] or [LocationServiceDisabledError]
  /// on failure so callers can show a precise, actionable message.
  Future<LatLng> getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationPermissionDeniedError();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionDeniedError(permanently: true);
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationServiceDisabledError();
    }

    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);
    return LatLng(pos.latitude, pos.longitude);
  }
}
