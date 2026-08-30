import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';

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
/// 2. **Row lines** — plain white polylines drawn on top of the bands.
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

  /// Build heatmap-colored coverage bands using telemetry metadata.
  ///
  /// Only [insidePoints] (points inside the plot boundary) are used to fill
  /// bands. Outside-plot points are handled separately as polylines.
  ///
  /// - GPS / Speed heatmaps: "no overlap" — latest state wins per sub-band.
  /// - Spray heatmap: "overlap required" — flow rates are accumulated per band.
  static List<Polygon> buildHeatmapCoverageBands({
    required List<List<LatLng>> rowLines,
    required List<HeatmapTrackPoint> insidePoints,
    required double rowSpacing,
    required HeatmapType heatmapType,
  }) {
    if (rowLines.length < 2) return const [];
    final bands = <Polygon>[];

    for (int ri = 0; ri < rowLines.length - 1; ri++) {
      final rowA = rowLines[ri];
      final rowB = rowLines[ri + 1];
      if (rowA.length < 2 || rowB.length < 2) continue;

      final midStart = _lerp(rowA[0], rowB[0], 0.5);
      final midEnd   = _lerp(rowA[1], rowB[1], 0.5);

      final segLen = RowLineGenerator
          .pointToSegmentInfo(midStart, midStart, midEnd)
          .segmentLengthMeters;
      if (segLen < 0.5) continue;

      final numSub =
          (segLen / subSegmentLengthMeters).ceil().clamp(1, 1000).toInt();
      final halfWidth = rowSpacing / 2;

      // Spray: accumulate flow rates + counts for averaging. GPS: track the
      // highest-priority color ever seen (never downgrades). Speed/Left-
      // Right: track latest color.
      // subBandMaxPass: highest corridor-entry number that touched each sub-band.
      //   corridorPassCount increments each time the sprayer re-enters this corridor
      //   (prevIdxInCorridor null → non-null transition). This detects re-passes
      //   reliably regardless of GPS sampling rate.
      final accumulated = List<double>.filled(numSub, 0.0);
      final accumulatedCount = List<int>.filled(numSub, 0);
      final latestColor = List<Color?>.filled(numSub, null);
      final subBandMaxPass = List<int>.filled(numSub, 0);
      // GPS heatmap only: highest gpsPriority ever recorded for each
      // sub-band, so a later lower-priority sample (e.g. Auto -> PTO off)
      // can't repaint it backwards — see HeatmapColorUtils.gpsPriority.
      final gpsMaxPriority = List<int>.filled(numSub, -1);
      int corridorPassCount = 0;

      // Track last index in this corridor so we can fill the gap to the next
      // point — GPS samples are sparse and often skip 1-2 sub-bands.
      int? prevIdxInCorridor;

      for (int k = 0; k < insidePoints.length; k++) {
        final pt = insidePoints[k];
        final info =
            RowLineGenerator.pointToSegmentInfo(pt.position, midStart, midEnd);
        if (info.distance > halfWidth) {
          prevIdxInCorridor = null; // left corridor; reset interpolation anchor
          continue;
        }

        if (prevIdxInCorridor == null) {
          corridorPassCount++; // entered (or re-entered) the corridor
        }

        final idx = (info.t * numSub).floor().clamp(0, numSub - 1);
        final color = heatmapType == HeatmapType.spraying
            ? null
            : HeatmapColorUtils.getColorForInsidePoint(pt, heatmapType);

        // Fill every sub-band from the previous in-corridor index to this one
        // so that GPS sampling gaps don't leave blank stripes.
        final prev = prevIdxInCorridor;
        final lo = prev != null ? math.min(prev, idx) : idx;
        final hi = prev != null ? math.max(prev, idx) : idx;

        for (int s = lo; s <= hi; s++) {
          subBandMaxPass[s] = math.max(subBandMaxPass[s], corridorPassCount);
          if (heatmapType == HeatmapType.spraying) {
            accumulated[s] += pt.flowRate ?? 0.0;
            accumulatedCount[s]++;
          } else if (heatmapType == HeatmapType.gps) {
            // Never downgrade: a sub-band that reached Auto must stay Auto
            // even if a later sample here is PTO-off/Manual (GPS jitter, a
            // momentary pause) — only an equal-or-higher priority sample
            // updates the shown color.
            final priority =
                HeatmapColorUtils.gpsPriority(ptoOn: pt.ptoOn, isAuto: pt.isAuto);
            if (priority >= gpsMaxPriority[s]) {
              gpsMaxPriority[s] = priority;
              latestColor[s] = color;
            }
          } else {
            // Latest-write wins for Speed/Left-Right heatmaps — a re-pass
            // over the same sub-band reflects the sprayer's current state
            // there. Only the Spray heatmap accumulates on re-pass, and
            // only the GPS heatmap has a no-downgrade priority rule.
            latestColor[s] = color;
          }
        }

        prevIdxInCorridor = idx;
      }

      prevIdxInCorridor = null; // reset for next corridor

      final perp = _perpendicularOffsetLatLng(midStart, midEnd, halfWidth);
      if (perp == null) continue;

      for (int i = 0; i < numSub; i++) {
        final passCount = subBandMaxPass[i];
        if (passCount == 0) continue; // sub-band never visited

        Color bandColor;
        int alpha;

        if (heatmapType == HeatmapType.spraying) {
          if (accumulated[i] <= 0.0 || accumulatedCount[i] == 0) continue;
          // Divide raw accumulated flow by the expected samples-per-sub-band at
          // normal speed. This is equivalent to avgPerSample × passCount for a
          // moving device (each pass contributes ~samplesPerPass samples), but
          // also correctly darkens a sub-band when the device is stationary:
          // many samples at the same spot accumulate a large sum which pushes
          // the colour from light-blue all the way to black.
          final totalFlow = accumulated[i] / samplesPerPass;
          bandColor = HeatmapColorUtils.getColorForSpray(totalFlow);
          alpha = 200;
        } else {
          // GPS heatmap: highest-priority state ever recorded (never
          // downgrades). Speed/Left-Right: most recent state (updated on
          // every re-pass). Both are just whatever's currently in
          // latestColor[i] at this point.
          final c = latestColor[i];
          if (c == null) continue;
          bandColor = c;
          alpha = 200;
        }

        final t0 = i / numSub;
        final t1 = (i + 1) / numSub;
        final p0 = _lerp(midStart, midEnd, t0);
        final p1 = _lerp(midStart, midEnd, t1);
        bands.add(Polygon(
          points: [
            LatLng(p0.latitude + perp.latitude,
                p0.longitude + perp.longitude),
            LatLng(p1.latitude + perp.latitude,
                p1.longitude + perp.longitude),
            LatLng(p1.latitude - perp.latitude,
                p1.longitude - perp.longitude),
            LatLng(p0.latitude - perp.latitude,
                p0.longitude - perp.longitude),
          ],
          color: bandColor.withAlpha(alpha),
          borderColor: Colors.transparent,
          borderStrokeWidth: 0,
        ));
      }
    }

    return bands;
  }

  /// Build the planned row line polylines (tree rows).
  static List<Polyline> buildRowLines({
    required List<List<LatLng>> rowLines,
    double strokeWidth = 2.0,
  }) {
    return rowLines
        .where((seg) => seg.length >= 2)
        .map((seg) => Polyline(
              points: seg,
              color: Colors.white.withAlpha(200),
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
