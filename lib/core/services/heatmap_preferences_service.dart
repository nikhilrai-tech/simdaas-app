import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';

/// The signed-in user's Speed/Spray heatmap color-band boundaries --
/// mirrors GET/PATCH /api/auth/heatmap-preferences/ (userauth.views.
/// HeatmapPreferencesView). Colors stay fixed; only where one band ends and
/// the next begins is configurable (see HeatmapColorUtils).
@immutable
class HeatmapThresholds {
  final double speedYellowMax;
  final double speedGreenMax;
  final double sprayBlueMax;
  final double sprayRedMax;

  const HeatmapThresholds({
    required this.speedYellowMax,
    required this.speedGreenMax,
    required this.sprayBlueMax,
    required this.sprayRedMax,
  });

  // Same values HeatmapColorUtils had hardcoded before this became
  // configurable -- used until the real preferences load, and whenever the
  // backend response is missing/malformed.
  factory HeatmapThresholds.defaults() => const HeatmapThresholds(
        speedYellowMax: 3.0,
        speedGreenMax: 7.0,
        sprayBlueMax: 70.0,
        sprayRedMax: 200.0,
      );

  factory HeatmapThresholds.fromJson(Map<String, dynamic> json) {
    final d = HeatmapThresholds.defaults();
    double read(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return HeatmapThresholds(
      speedYellowMax: read('heatmap_speed_yellow_max', d.speedYellowMax),
      speedGreenMax: read('heatmap_speed_green_max', d.speedGreenMax),
      sprayBlueMax: read('heatmap_spray_blue_max', d.sprayBlueMax),
      sprayRedMax: read('heatmap_spray_red_max', d.sprayRedMax),
    );
  }

  Map<String, dynamic> toJson() => {
        'heatmap_speed_yellow_max': speedYellowMax,
        'heatmap_speed_green_max': speedGreenMax,
        'heatmap_spray_blue_max': sprayBlueMax,
        'heatmap_spray_red_max': sprayRedMax,
      };

  @override
  bool operator ==(Object other) =>
      other is HeatmapThresholds &&
      other.speedYellowMax == speedYellowMax &&
      other.speedGreenMax == speedGreenMax &&
      other.sprayBlueMax == sprayBlueMax &&
      other.sprayRedMax == sprayRedMax;

  @override
  int get hashCode =>
      Object.hash(speedYellowMax, speedGreenMax, sprayBlueMax, sprayRedMax);
}

/// Loads the signed-in user's heatmap thresholds on first use and applies
/// them to HeatmapColorUtils's static fields, so every heatmap painter
/// (monitoring screen, report screen, row_line_coverage.dart) picks them up
/// without needing to be plumbed a reference to this provider directly.
///
/// Screens that render a heatmap should `ref.watch(heatmapThresholdsProvider)`
/// even if they don't use the returned value -- watching is what makes
/// Flutter repaint them immediately after [update] succeeds, since the
/// static fields alone don't trigger a rebuild on their own.
class HeatmapThresholdsNotifier extends StateNotifier<HeatmapThresholds> {
  final ApiService _api;
  final AuthService _auth;

  HeatmapThresholdsNotifier(this._api, this._auth)
      : super(HeatmapThresholds.defaults()) {
    _load();
  }

  Future<void> _load() async {
    try {
      await _auth.initialized;
      final json = await _api.getJson('/api/auth/heatmap-preferences/');
      if (json is Map) {
        _apply(HeatmapThresholds.fromJson(Map<String, dynamic>.from(json)));
      }
    } catch (e) {
      debugPrint('HeatmapThresholdsNotifier: load failed: $e');
      // Keep showing the defaults already applied -- same colors as before
      // this feature existed, not a broken/blank heatmap.
    }
  }

  /// Saves [thresholds] via PATCH, gated by the user's session PIN the same
  /// way Automatic<->Manual mode switching is (pass [pin] once the backend
  /// has asked for one via session_pin_prompt.runWithPinRetry). Throws
  /// ApiException on failure/validation errors -- the caller shows it.
  Future<void> update(HeatmapThresholds thresholds, {String? pin}) async {
    final json = await _api.patchJson('/api/auth/heatmap-preferences/',
        jsonBody: {
          ...thresholds.toJson(),
          if (pin != null) 'pin': pin,
        });
    if (json is Map) {
      _apply(HeatmapThresholds.fromJson(Map<String, dynamic>.from(json)));
    }
  }

  void _apply(HeatmapThresholds t) {
    HeatmapColorUtils.speedYellowMax = t.speedYellowMax;
    HeatmapColorUtils.speedGreenMax = t.speedGreenMax;
    HeatmapColorUtils.sprayBlueMax = t.sprayBlueMax;
    HeatmapColorUtils.sprayRedMax = t.sprayRedMax;
    state = t;
  }
}

final heatmapThresholdsProvider =
    StateNotifierProvider<HeatmapThresholdsNotifier, HeatmapThresholds>(
        (ref) {
  return HeatmapThresholdsNotifier(
    ref.read(apiServiceProvider),
    ref.read(authServiceProvider),
  );
});
