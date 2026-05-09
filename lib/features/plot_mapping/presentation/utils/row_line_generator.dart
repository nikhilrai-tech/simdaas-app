import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Generates parallel row lines that fill a polygon given a guide line and spacing.
class RowLineGenerator {
  static const double _mPerDeg = 111320.0;

  /// Returns an ordered list of row segments (each a 2-element [start, end] list).
  ///
  /// [guideStart] / [guideEnd] — the user-drawn guide line (sets direction + phase).
  /// [polygon]    — plot boundary in LatLng.
  /// [rowSpacing] — perpendicular spacing between rows in metres (> 0).
  static List<List<LatLng>> generate({
    required LatLng guideStart,
    required LatLng guideEnd,
    required List<LatLng> polygon,
    required double rowSpacing,
  }) {
    if (polygon.length < 3 || rowSpacing <= 0) return [];

    // Local flat-earth origin (polygon centroid).
    var sumLat = 0.0, sumLon = 0.0;
    for (final p in polygon) {
      sumLat += p.latitude;
      sumLon += p.longitude;
    }
    final oLat = sumLat / polygon.length;
    final oLon = sumLon / polygon.length;
    final cosLat = math.cos(oLat * math.pi / 180.0);

    // LatLng → local metres helpers.
    double toX(LatLng p) => (p.longitude - oLon) * cosLat * _mPerDeg;
    double toY(LatLng p) => (p.latitude - oLat) * _mPerDeg;
    LatLng fromXY(double x, double y) => LatLng(
      y / _mPerDeg + oLat,
      x / (cosLat * _mPerDeg) + oLon,
    );

    // Polygon in local coords.
    final polyX = polygon.map(toX).toList();
    final polyY = polygon.map(toY).toList();

    // Guide line direction (unit vector).
    final gsx = toX(guideStart), gsy = toY(guideStart);
    final gex = toX(guideEnd),   gey = toY(guideEnd);
    final gdx = gex - gsx,       gdy = gey - gsy;
    final glen = math.sqrt(gdx * gdx + gdy * gdy);
    if (glen < 1e-6) return [];
    final dx = gdx / glen, dy = gdy / glen;

    // Perpendicular direction (rotate 90° CCW).
    final nx = -dy, ny = dx;

    // Project guide start onto perp axis.
    final guideProj = gsx * nx + gsy * ny;

    // Project polygon vertices onto perp axis, find offset range relative to guide.
    var minOff = double.infinity, maxOff = -double.infinity;
    for (int i = 0; i < polyX.length; i++) {
      final rel = polyX[i] * nx + polyY[i] * ny - guideProj;
      if (rel < minOff) minOff = rel;
      if (rel > maxOff) maxOff = rel;
    }

    final kMin = (minOff / rowSpacing).floor();
    final kMax = (maxOff / rowSpacing).ceil();

    final rows = <_RowEntry>[];

    for (int k = kMin; k <= kMax; k++) {
      final offset = guideProj + k * rowSpacing;
      // A point on this row's line (closest to origin).
      final px = nx * offset, py = ny * offset;

      final ts = _linePolyTs(px, py, dx, dy, polyX, polyY);
      if (ts.length < 2) continue;
      ts.sort();

      // Pair consecutive intersections; only keep segments whose midpoint is inside.
      for (int i = 0; i + 1 < ts.length; i += 2) {
        final t0 = ts[i], t1 = ts[i + 1];
        if ((t1 - t0).abs() < 0.5) continue; // < 0.5 m — skip degenerate

        final midX = px + (t0 + t1) / 2 * dx;
        final midY = py + (t0 + t1) / 2 * dy;
        if (!_inPoly(midX, midY, polyX, polyY)) continue;

        rows.add(_RowEntry(
          k * rowSpacing,
          [fromXY(px + t0 * dx, py + t0 * dy), fromXY(px + t1 * dx, py + t1 * dy)],
        ));
      }
    }

    rows.sort((a, b) => a.offset.compareTo(b.offset));
    return rows.map((r) => r.points).toList();
  }

  /// Perpendicular distance in metres from [point] to the segment [a]→[b].
  static double pointToSegmentDistance(LatLng point, LatLng a, LatLng b) {
    return pointToSegmentInfo(point, a, b).distance;
  }

  /// Returns both the perpendicular distance in metres and the projection
  /// parameter `t in [0, 1]` of [point] onto the segment [a]->[b]. `t=0` is
  /// at [a], `t=1` is at [b]. Useful for sub-segment coverage tracking.
  static SegmentProjection pointToSegmentInfo(LatLng point, LatLng a, LatLng b) {
    const mPerDeg = 111320.0;
    final cosLat = math.cos(point.latitude * math.pi / 180.0);
    final px = (point.longitude - a.longitude) * cosLat * mPerDeg;
    final py = (point.latitude - a.latitude) * mPerDeg;
    final bx = (b.longitude - a.longitude) * cosLat * mPerDeg;
    final by = (b.latitude - a.latitude) * mPerDeg;
    final len2 = bx * bx + by * by;
    if (len2 < 1e-9) {
      return SegmentProjection(
        distance: math.sqrt(px * px + py * py),
        t: 0.0,
        segmentLengthMeters: 0.0,
      );
    }
    final t = ((px * bx + py * by) / len2).clamp(0.0, 1.0);
    final dx = px - t * bx, dy = py - t * by;
    return SegmentProjection(
      distance: math.sqrt(dx * dx + dy * dy),
      t: t,
      segmentLengthMeters: math.sqrt(len2),
    );
  }

  // 2-D cross product.
  static double _cross(double ax, double ay, double bx, double by) =>
      ax * by - ay * bx;

  // Parametric t values where line P+t*D intersects each polygon edge.
  static List<double> _linePolyTs(
    double px, double py, double dx, double dy,
    List<double> polyX, List<double> polyY,
  ) {
    final ts = <double>[];
    final n = polyX.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final ax = polyX[i], ay = polyY[i];
      final bx = polyX[j], by = polyY[j];
      final ex = bx - ax, ey = by - ay;
      final vx = ax - px, vy = ay - py;
      final dCrossE = _cross(dx, dy, ex, ey);
      if (dCrossE.abs() < 1e-9) continue; // parallel
      final t = _cross(vx, vy, ex, ey) / dCrossE;
      final s = _cross(vx, vy, dx, dy) / dCrossE;
      if (s >= -1e-9 && s <= 1 + 1e-9) ts.add(t);
    }
    return ts;
  }

  // Ray-casting point-in-polygon test.
  static bool _inPoly(double x, double y, List<double> polyX, List<double> polyY) {
    bool inside = false;
    final n = polyX.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polyX[i], yi = polyY[i];
      final xj = polyX[j], yj = polyY[j];
      if (((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }
}

class _RowEntry {
  final double offset;
  final List<LatLng> points;
  _RowEntry(this.offset, this.points);
}

/// Result of projecting a point onto a line segment.
class SegmentProjection {
  /// Perpendicular distance from the point to the (clipped) segment, metres.
  final double distance;

  /// Projection parameter on the segment, clamped to [0, 1]. 0 = at start,
  /// 1 = at end.
  final double t;

  /// Total length of the segment in metres. Useful for converting a `t`
  /// difference into a metre difference.
  final double segmentLengthMeters;

  const SegmentProjection({
    required this.distance,
    required this.t,
    required this.segmentLengthMeters,
  });
}
