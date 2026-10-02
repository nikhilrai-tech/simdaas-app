import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/core/services/auth_service.dart';

/// The signed-in user's GPS calibration offset -- mirrors GET/PATCH
/// /api/auth/gps-calibration/ (userauth.views.GpsCalibrationView).
///
/// Unlike heatmap thresholds, this correction is applied entirely on the
/// BACKEND (jobs.session_service._apply_gps_calibration, before a position
/// is ever stored or broadcast) -- so there's no equivalent of
/// HeatmapColorUtils's static fields to keep in sync here. This provider
/// only needs to hold the value for display/editing in Settings; whatever
/// position the app receives (live telemetry or a report's GPSPoints) is
/// already calibrated by the time it arrives.
@immutable
class GpsCalibration {
  final double offsetNorthM;
  final double offsetEastM;

  const GpsCalibration({required this.offsetNorthM, required this.offsetEastM});

  factory GpsCalibration.zero() =>
      const GpsCalibration(offsetNorthM: 0.0, offsetEastM: 0.0);

  factory GpsCalibration.fromJson(Map<String, dynamic> json) {
    double read(String key) => (json[key] as num?)?.toDouble() ?? 0.0;
    return GpsCalibration(
      offsetNorthM: read('gps_offset_north_m'),
      offsetEastM: read('gps_offset_east_m'),
    );
  }

  Map<String, dynamic> toJson() => {
        'gps_offset_north_m': offsetNorthM,
        'gps_offset_east_m': offsetEastM,
      };

  @override
  bool operator ==(Object other) =>
      other is GpsCalibration &&
      other.offsetNorthM == offsetNorthM &&
      other.offsetEastM == offsetEastM;

  @override
  int get hashCode => Object.hash(offsetNorthM, offsetEastM);
}

class GpsCalibrationNotifier extends StateNotifier<GpsCalibration> {
  final ApiService _api;
  final AuthService _auth;

  GpsCalibrationNotifier(this._api, this._auth) : super(GpsCalibration.zero()) {
    _load();
  }

  Future<void> _load() async {
    try {
      await _auth.initialized;
      final json = await _api.getJson('/api/auth/gps-calibration/');
      if (json is Map) {
        state = GpsCalibration.fromJson(Map<String, dynamic>.from(json));
      }
    } catch (e) {
      debugPrint('GpsCalibrationNotifier: load failed: $e');
      // Keep showing zero -- same as no calibration ever having been set.
    }
  }

  /// Saves [calibration] via PATCH, gated by the user's session PIN the
  /// same way Automatic<->Manual mode switching is (pass [pin] once the
  /// backend has asked for one via session_pin_prompt.runWithPinRetry).
  /// Throws ApiException on failure/validation errors -- the caller shows it.
  Future<void> update(GpsCalibration calibration, {String? pin}) async {
    final json = await _api.patchJson('/api/auth/gps-calibration/', jsonBody: {
      ...calibration.toJson(),
      if (pin != null) 'pin': pin,
    });
    if (json is Map) {
      state = GpsCalibration.fromJson(Map<String, dynamic>.from(json));
    }
  }
}

final gpsCalibrationProvider =
    StateNotifierProvider<GpsCalibrationNotifier, GpsCalibration>((ref) {
  return GpsCalibrationNotifier(
    ref.read(apiServiceProvider),
    ref.read(authServiceProvider),
  );
});
