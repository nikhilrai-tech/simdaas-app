import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'row_line_generator.dart';

/// Builds the visual layers for spray coverage on the plot map.
///
/// Two layers are produced:
///
/// 1. **Coverage bands** — filled polygons in the *gap between two consecutive
///    tree row lines*. Each corridor (space between tree row i and tree row i+1)
///    is split into ~2 m sub-bands along its length. A sub-band is colored when
///    the sprayer GPS track passes through it. Revisited sub-bands go darker.
///
/// 2. **Row lines** — plain yellow polylines drawn on top of the bands.
///    These never change color; they are the tree row reference lines.
///
/// Color scheme (single corridor = space between two tree rows):
///   pass count = 0   -> transparent (nothing drawn)
///   pass count = 1   -> light grey  (sprayed once)
///   pass count >= 2  -> dark grey   (sprayed more than once)
class RowLineCoverage {
  /// Approximate length of each sub-band along the row direction, metres.
  static const double subSegmentLengthMeters = 2.0;

  /// How many telemetry samples inside a sub-band counts as "one pass".
  static const double samplesPerPass = 3.0;

  /// Build coverage band polygons (the colored strips between tree rows).
  ///
  /// Each band lives in the corridor between rowLines[i] and rowLines[i+1].
  /// The midline of the corridor is used to project GPS points and to build
  /// the parallelogram sub-bands.
  static List<Polygon> buildCoverageBands({
    required List<List<LatLng>> rowLines,
    required List<LatLng> gpsTrack,
    required double rowSpacing,
  }) {
    if (rowLines.length < 2) return const [];
    final bands = <Polygon>[];

    for (int ri = 0; ri < rowLines.length - 1; ri++) {
      final rowA = rowLines[ri];
      final rowB = rowLines[ri + 1];
      if (rowA.length < 2 || rowB.length < 2) continue;

      // Midline of the spray corridor (between the two bounding tree rows).
      final midStart = _lerp(rowA[0], rowB[0], 0.5);
      final midEnd   = _lerp(rowA[1], rowB[1], 0.5);

      final segLen = RowLineGenerator
          .pointToSegmentInfo(midStart, midStart, midEnd)
          .segmentLengthMeters;
      if (segLen < 0.5) continue;

      final numSub =
          (segLen / subSegmentLengthMeters).ceil().clamp(1, 1000).toInt();
      final counts = List<int>.filled(numSub, 0);

      // Half-width of the corridor (midline → each tree row boundary).
      final halfWidth = rowSpacing / 2;

      // Count GPS samples that fall inside this corridor.
      for (final g in gpsTrack) {
        final info = RowLineGenerator.pointToSegmentInfo(g, midStart, midEnd);
        if (info.distance > halfWidth) continue;
        final idx = (info.t * numSub).floor().clamp(0, numSub - 1);
        counts[idx]++;
      }

      // Perpendicular delta of `halfWidth` from the midline.
      final perp = _perpendicularOffsetLatLng(midStart, midEnd, halfWidth);
      if (perp == null) continue;

      // Emit one filled parallelogram per covered sub-band.
      for (int i = 0; i < numSub; i++) {
        final count = counts[i];
        if (count <= 0) continue;
        final t0 = i / numSub;
        final t1 = (i + 1) / numSub;
        final p0 = _lerp(midStart, midEnd, t0);
        final p1 = _lerp(midStart, midEnd, t1);
        bands.add(Polygon(
          points: [
            LatLng(p0.latitude + perp.latitude, p0.longitude + perp.longitude),
            LatLng(p1.latitude + perp.latitude, p1.longitude + perp.longitude),
            LatLng(p1.latitude - perp.latitude, p1.longitude - perp.longitude),
            LatLng(p0.latitude - perp.latitude, p0.longitude - perp.longitude),
          ],
          color: _bandColor(count),
          borderColor: Colors.transparent,
          borderStrokeWidth: 0,
        ));
      }
    }

    return bands;
  }

  /// Build the planned row line polylines (always yellow — tree rows).
  static List<Polyline> buildRowLines({
    required List<List<LatLng>> rowLines,
    double strokeWidth = 2.5,
  }) {
    return rowLines
        .where((seg) => seg.length >= 2)
        .map((seg) => Polyline(
              points: seg,
              color: Colors.yellow.withAlpha(220),
              strokeWidth: strokeWidth,
            ))
        .toList();
  }

  // ── helpers ────────────────────────────────────────────────────────────

  static LatLng? _perpendicularOffsetLatLng(
      LatLng start, LatLng end, double halfWidthMeters) {
    const mPerDeg = 111320.0;
    final cosLat = math.cos(start.latitude * math.pi / 180.0);
    if (cosLat.abs() < 1e-9) return null;
    final dx = (end.longitude - start.longitude) * cosLat * mPerDeg;
    final dy = (end.latitude - start.latitude) * mPerDeg;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return null;
    final px = -dy / len * halfWidthMeters;
    final py =  dx / len * halfWidthMeters;
    return LatLng(py / mPerDeg, px / (cosLat * mPerDeg));
  }

  static LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude  + (b.latitude  - a.latitude)  * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  static Color _bandColor(int rawCount) {
    final passes = (rawCount / samplesPerPass).ceil();
    if (passes <= 1) return Colors.grey.shade400.withAlpha(160);  // single pass
    return Colors.grey.shade800.withAlpha(220);                    // double / more
  }
}
