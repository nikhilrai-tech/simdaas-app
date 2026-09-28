import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Flags implausible GPS jumps in a device's position track -- a step
/// between two consecutive points whose implied speed no sprayer can
/// actually reach (observed on a real staging session: 711 m in 17 s,
/// ~150 km/h, against a normal top speed of ~8 km/h). A live GPS fix can
/// glitch and briefly report a wildly wrong position; without flagging
/// this, the heatmap's gap-fill (which bridges ordinary sampling gaps so
/// sparse points don't leave blank stripes) paints the jump itself as if
/// it were sprayed, and the trajectory line draws it as a straight "drive".
class GpsJumpDetector {
  /// Any step implying a speed above this (km/h) is treated as a jump, not
  /// real driving. Chosen well above a sprayer's real top speed (~8 km/h
  /// observed) with a wide safety margin, so ordinary driving is never
  /// mistaken for a jump.
  static const double maxPlausibleSpeedKmph = 25.0;

  static const double _mPerDeg = 111320.0;

  static double _distanceMeters(LatLng a, LatLng b) {
    final cosLat = math.cos(a.latitude * math.pi / 180.0);
    final dx = (b.longitude - a.longitude) * cosLat * _mPerDeg;
    final dy = (b.latitude - a.latitude) * _mPerDeg;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// True if the single step from (`a` at `ta`) to (`b` at `tb`) is a jump.
  static bool isJump(LatLng a, DateTime ta, LatLng b, DateTime tb) {
    final dtSec = tb.difference(ta).inMilliseconds / 1000.0;
    if (dtSec <= 0) return false;
    final speedKmph = (_distanceMeters(a, b) / dtSec) * 3.6;
    return speedKmph > maxPlausibleSpeedKmph;
  }

  /// Indices `i` such that the step from `points[i]` to `points[i + 1]` is a
  /// jump. `timestamps[i]` is the time of `points[i]`.
  static Set<int> jumpIndices(List<LatLng> points, List<DateTime> timestamps) {
    final jumps = <int>{};
    for (var i = 0; i + 1 < points.length && i + 1 < timestamps.length; i++) {
      if (isJump(points[i], timestamps[i], points[i + 1], timestamps[i + 1])) {
        jumps.add(i);
      }
    }
    return jumps;
  }

  /// Pink dashed segments, one per jump in `jumpIndices(points, timestamps)`.
  /// Meant to be shown on the GPS heatmap only, regardless of whether either
  /// end is inside or outside the plot.
  static List<Polyline> buildJumpLines(
      List<LatLng> points, List<DateTime> timestamps) {
    final jumps = jumpIndices(points, timestamps);
    if (jumps.isEmpty) return const [];
    return [
      for (final i in jumps)
        Polyline(
          points: [points[i], points[i + 1]],
          strokeWidth: 4.0,
          color: Colors.pinkAccent,
          pattern: StrokePattern.dashed(segments: const [10.0, 6.0]),
        ),
    ];
  }
}
