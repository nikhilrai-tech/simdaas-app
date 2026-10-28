import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

const double _mPerDeg = 111320.0;

typedef _P = math.Point<double>;

/// Flat-earth metric plane anchored at a polygon's centroid.
class MetricPlane {
  final double lat0;
  final double lon0;
  final double cosLat;

  const MetricPlane._(this.lat0, this.lon0, this.cosLat);

  factory MetricPlane.around(List<LatLng> pts) {
    var la = 0.0, lo = 0.0;
    for (final p in pts) {
      la += p.latitude;
      lo += p.longitude;
    }
    final lat0 = la / pts.length;
    return MetricPlane._(
        lat0, lo / pts.length, math.cos(lat0 * math.pi / 180.0));
  }

  math.Point<double> toXY(LatLng p) => math.Point((p.longitude - lon0) * cosLat * _mPerDeg,
      (p.latitude - lat0) * _mPerDeg);

  LatLng toLatLng(double x, double y) =>
      LatLng(lat0 + y / _mPerDeg, lon0 + x / (cosLat * _mPerDeg));
}

/// A corridor (the strip of the field between two lines), described on its
/// own axis: `s` runs along the corridor, `l` across it. Each bounding line
/// is a straight (infinite) line, so the strip runs the whole width of the
/// plot regardless of how long the stored row segments happen to be -- rows
/// are stored clipped to the polygon and can differ in length -- and is only
/// cut off by the plot boundary itself (see [clippedAt]).
class CorridorStrip {
  final MetricPlane plane;
  final double ux, uy; // axis (unit)
  final double nx, ny; // across (unit)
  final double sMin, sMax; // axial extent = the plot polygon's extent
  final double aStart, aEnd; // lateral offset of boundary A at sMin / sMax
  final double bStart, bEnd; // lateral offset of boundary B at sMin / sMax
  final List<double> _polyS;
  final List<double> _polyL;

  CorridorStrip._({
    required this.plane,
    required this.ux,
    required this.uy,
    required this.sMin,
    required this.sMax,
    required this.aStart,
    required this.aEnd,
    required this.bStart,
    required this.bEnd,
    required List<double> polyS,
    required List<double> polyL,
  })  : nx = -uy,
        ny = ux,
        _polyS = polyS,
        _polyL = polyL;

  double get length => sMax - sMin;

  double _lo(double s) => math.min(_a(s), _b(s));
  double _hi(double s) => math.max(_a(s), _b(s));
  double _a(double s) => aStart + (aEnd - aStart) * ((s - sMin) / length);
  double _b(double s) => bStart + (bEnd - bStart) * ((s - sMin) / length);

  /// Half of the (unclipped) gap between the two lines at each end.
  double get halfWidthStart => (bStart - aStart).abs() / 2;
  double get halfWidthEnd => (bEnd - aEnd).abs() / 2;

  double _midL(double s) => (_a(s) + _b(s)) / 2;

  LatLng point(double s, double l) => plane.toLatLng(
      ux * s + nx * l, uy * s + ny * l);

  LatLng get midStart => point(sMin, _midL(sMin));
  LatLng get midEnd => point(sMax, _midL(sMax));

  /// Midline point at axial parameter [t] (0..1, matching [project]'s t) --
  /// i.e. where a point projecting to this t is actually credited/painted,
  /// as opposed to its own (possibly well off-corridor) raw position.
  LatLng midpointAt(double t) {
    final s = sMin + t.clamp(0.0, 1.0) * length;
    return point(s, _midL(s));
  }

  /// Position of [p] along the corridor (t in 0..1) and its lateral distance
  /// from the corridor's centre line, both measured on the corridor's own
  /// axes.
  ({double t, double distance}) project(LatLng p) {
    final q = plane.toXY(p);
    final s = q.x * ux + q.y * uy;
    final l = q.x * nx + q.y * ny;
    final t = ((s - sMin) / length).clamp(0.0, 1.0);
    return (t: t, distance: (l - _midL(s.clamp(sMin, sMax))).abs());
  }

  /// The strip at axial position [s], cut to the plot polygon: (low, high)
  /// lateral bounds, or null where the strip is outside the plot. When the
  /// plot is concave the cross-section can have several pieces; the one that
  /// overlaps the strip most is used.
  ({double lo, double hi})? clippedAt(double s) {
    final lo = _lo(s), hi = _hi(s);
    final xs = <double>[];
    final n = _polyS.length;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final si = _polyS[i], sj = _polyS[j];
      if ((si <= s) != (sj <= s)) {
        xs.add(_polyL[i] + (_polyL[j] - _polyL[i]) * (s - si) / (sj - si));
      }
    }
    xs.sort();
    ({double lo, double hi})? best;
    var bestOverlap = 1e-6;
    for (var k = 0; k + 1 < xs.length; k += 2) {
      final a = math.max(lo, xs[k]);
      final b = math.min(hi, xs[k + 1]);
      if (b - a > bestOverlap) {
        bestOverlap = b - a;
        best = (lo: a, hi: b);
      }
    }
    return best;
  }

  /// Corners of the slice of the strip between axial fractions [t0]..[t1],
  /// following the two boundary lines and cut by the plot boundary. Null if
  /// the slice lies entirely outside the plot.
  List<LatLng>? bandCorners(double t0, double t1) {
    final s0 = sMin + t0 * length, s1 = sMin + t1 * length;
    var c0 = clippedAt(s0);
    var c1 = clippedAt(s1);
    if (c0 == null && c1 == null) return null;
    c0 ??= c1;
    c1 ??= c0;
    return [
      point(s0, c0!.lo),
      point(s1, c1!.lo),
      point(s1, c1.hi),
      point(s0, c0.hi),
    ];
  }

  /// Width (m) of the strip inside the plot at axial position [s].
  double clippedWidthAt(double s) {
    final c = clippedAt(s);
    return c == null ? 0.0 : c.hi - c.lo;
  }

  // ── construction ────────────────────────────────────────────────────────

  static _P _unit(_P v) {
    final l = math.sqrt(v.x * v.x + v.y * v.y);
    return l < 1e-9 ? const math.Point(0.0, 0.0) : math.Point(v.x / l, v.y / l);
  }

  static CorridorStrip? _build(
    MetricPlane plane,
    List<LatLng> polygon,
    _P u, {
    required double Function(double s, double ux, double uy) lineA,
    required double Function(double s, double ux, double uy) lineB,
  }) {
    if (u.x == 0 && u.y == 0) return null;
    final ps = <double>[], pl = <double>[];
    for (final v in polygon) {
      final q = plane.toXY(v);
      ps.add(q.x * u.x + q.y * u.y);
      pl.add(q.x * -u.y + q.y * u.x);
    }
    final sMin = ps.reduce(math.min), sMax = ps.reduce(math.max);
    if (sMax - sMin < 0.5) return null;
    return CorridorStrip._(
      plane: plane,
      ux: u.x,
      uy: u.y,
      sMin: sMin,
      sMax: sMax,
      aStart: lineA(sMin, u.x, u.y),
      aEnd: lineA(sMax, u.x, u.y),
      bStart: lineB(sMin, u.x, u.y),
      bEnd: lineB(sMax, u.x, u.y),
      polyS: ps,
      polyL: pl,
    );
  }

  /// Lateral offset (on axis [u]) at axial position s of the infinite line
  /// through [p] with direction [d].
  static double _lineLateral(_P p, _P d, double s, double ux, double uy) {
    final nx = -uy, ny = ux;
    final s0 = p.x * ux + p.y * uy;
    final l0 = p.x * nx + p.y * ny;
    final du = d.x * ux + d.y * uy;
    final dn = d.x * nx + d.y * ny;
    if (du.abs() < 1e-9) return l0;
    return l0 + (s - s0) * dn / du;
  }

  /// Strip between the (infinite) lines through row A and row B.
  static CorridorStrip? between({
    required MetricPlane plane,
    required List<LatLng> polygon,
    required List<LatLng> rowA,
    required List<LatLng> rowB,
  }) {
    final a0 = plane.toXY(rowA[0]), a1 = plane.toXY(rowA[1]);
    final b0 = plane.toXY(rowB[0]), b1 = plane.toXY(rowB[1]);
    final da = _unit(a1 - a0);
    var db = _unit(b1 - b0);
    if (da.x * db.x + da.y * db.y < 0) db = math.Point(-db.x, -db.y);
    final u = _unit(math.Point(da.x + db.x, da.y + db.y));
    return _build(
      plane,
      polygon,
      u,
      lineA: (s, ux, uy) => _lineLateral(a0, da, s, ux, uy),
      lineB: (s, ux, uy) => _lineLateral(b0, db, s, ux, uy),
    );
  }

  /// Flat-width strip centred on one row (used where the row on the other
  /// side is missing/deleted), running the full length of the plot.
  static CorridorStrip? ribbon({
    required MetricPlane plane,
    required List<LatLng> polygon,
    required List<LatLng> row,
    required double halfWidthMeters,
  }) {
    final a0 = plane.toXY(row[0]), a1 = plane.toXY(row[1]);
    final d = _unit(a1 - a0);
    return _build(
      plane,
      polygon,
      d,
      lineA: (s, ux, uy) => _lineLateral(a0, d, s, ux, uy) - halfWidthMeters,
      lineB: (s, ux, uy) => _lineLateral(a0, d, s, ux, uy) + halfWidthMeters,
    );
  }

  /// The stretch between [row]'s line and the plot boundary on the side
  /// facing away from [otherRow] (the next row in). Implemented as a strip
  /// out to the polygon's farthest point on that side; the plot boundary
  /// itself does the final cut in [clippedAt].
  static CorridorStrip? outer({
    required MetricPlane plane,
    required List<LatLng> polygon,
    required List<LatLng> row,
    required List<LatLng> otherRow,
  }) {
    final a0 = plane.toXY(row[0]), a1 = plane.toXY(row[1]);
    final d = _unit(a1 - a0);
    final nx = -d.y, ny = d.x;
    final o = plane.toXY(LatLng(
        (otherRow[0].latitude + otherRow[1].latitude) / 2,
        (otherRow[0].longitude + otherRow[1].longitude) / 2));
    final rowL = a0.x * nx + a0.y * ny;
    // Which side of the row the next row is on; the outer stretch is the
    // opposite side.
    final away = (o.x * nx + o.y * ny) > rowL ? -1.0 : 1.0;
    var extreme = away > 0 ? -double.infinity : double.infinity;
    for (final v in polygon) {
      final q = plane.toXY(v);
      final l = q.x * nx + q.y * ny;
      extreme = away > 0 ? math.max(extreme, l) : math.min(extreme, l);
    }
    extreme += away * 1.0;
    return _build(
      plane,
      polygon,
      d,
      lineA: (s, ux, uy) => _lineLateral(a0, d, s, ux, uy),
      lineB: (s, ux, uy) => extreme,
    );
  }
}

/// Helpers for editing row lines.
class RowLineGeometry {
  /// Signed perpendicular distance (m) from [p] to the line through [row],
  /// positive on the row's left (normal = (-dy, dx) in east/north metres).
  static double signedDistance(List<LatLng> row, LatLng p) {
    final plane = MetricPlane.around([row[0], row[1]]);
    final a = plane.toXY(row[0]), b = plane.toXY(row[1]);
    final d = CorridorStrip._unit(b - a);
    final q = plane.toXY(p);
    return (q.x - a.x) * -d.y + (q.y - a.y) * d.x;
  }

  /// Unit normal (east, north) of [row] pointing to its left.
  static ({double x, double y}) leftNormal(List<LatLng> row) {
    final plane = MetricPlane.around([row[0], row[1]]);
    final d = CorridorStrip._unit(plane.toXY(row[1]) - plane.toXY(row[0]));
    return (x: -d.y, y: d.x);
  }

  /// [row] shifted sideways by [lateralMeters] (positive = to its left) and
  /// re-clipped to [polygon], so both ends sit on the plot boundary just
  /// like auto-generated rows. Null if the shifted line no longer crosses
  /// the plot.
  static List<LatLng>? shiftRow({
    required List<LatLng> row,
    required double lateralMeters,
    required List<LatLng> polygon,
  }) {
    if (row.length < 2 || polygon.length < 3) return null;
    final plane = MetricPlane.around(polygon);
    final a = plane.toXY(row[0]), b = plane.toXY(row[1]);
    final d = CorridorStrip._unit(b - a);
    if (d.x == 0 && d.y == 0) return null;
    final p = math.Point(a.x + -d.y * lateralMeters, a.y + d.x * lateralMeters);
    final mid = math.Point((a.x + b.x) / 2, (a.y + b.y) / 2);
    final tMid = (mid.x - a.x) * d.x + (mid.y - a.y) * d.y;

    final xy = polygon.map(plane.toXY).toList();
    final ts = <double>[];
    for (var i = 0; i < xy.length; i++) {
      final e0 = xy[i], e1 = xy[(i + 1) % xy.length];
      final ex = e1.x - e0.x, ey = e1.y - e0.y;
      final cross = d.x * ey - d.y * ex;
      if (cross.abs() < 1e-9) continue;
      final vx = e0.x - p.x, vy = e0.y - p.y;
      final t = (vx * ey - vy * ex) / cross;
      final u = (vx * d.y - vy * d.x) / cross;
      if (u >= -1e-9 && u <= 1 + 1e-9) ts.add(t);
    }
    ts.sort();
    double? bestA, bestB;
    var bestDist = double.infinity;
    for (var k = 0; k + 1 < ts.length; k += 2) {
      if (ts[k + 1] - ts[k] < 0.5) continue;
      final m = (ts[k] + ts[k + 1]) / 2;
      final dist = (m - tMid).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestA = ts[k];
        bestB = ts[k + 1];
      }
    }
    if (bestA == null || bestB == null) return null;
    return [
      plane.toLatLng(p.x + d.x * bestA, p.y + d.y * bestA),
      plane.toLatLng(p.x + d.x * bestB, p.y + d.y * bestB),
    ];
  }

  /// [row] rotated by [degrees] (positive = counter-clockwise) around its own
  /// midpoint, and re-clipped to [polygon] the same way [shiftRow] is. Lets a
  /// manually-placed row line be nudged to match the true physical row's
  /// angle (e.g. after a guide-line-generated row was shifted sideways to
  /// line up with one end, but drifts off at the other end because the real
  /// row isn't quite parallel to the guide line) -- a plain sideways shift
  /// can't fix an angular mismatch, only a parallel one. Null if the rotated
  /// line no longer crosses the plot.
  static List<LatLng>? rotateRow({
    required List<LatLng> row,
    required double degrees,
    required List<LatLng> polygon,
  }) {
    if (row.length < 2 || polygon.length < 3) return null;
    final plane = MetricPlane.around(polygon);
    final a = plane.toXY(row[0]), b = plane.toXY(row[1]);
    final d = CorridorStrip._unit(b - a);
    if (d.x == 0 && d.y == 0) return null;
    final mid = math.Point((a.x + b.x) / 2, (a.y + b.y) / 2);

    final rad = degrees * math.pi / 180.0;
    final cosT = math.cos(rad), sinT = math.sin(rad);
    final rd = _P(d.x * cosT - d.y * sinT, d.x * sinT + d.y * cosT);

    final xy = polygon.map(plane.toXY).toList();
    final ts = <double>[];
    for (var i = 0; i < xy.length; i++) {
      final e0 = xy[i], e1 = xy[(i + 1) % xy.length];
      final ex = e1.x - e0.x, ey = e1.y - e0.y;
      final cross = rd.x * ey - rd.y * ex;
      if (cross.abs() < 1e-9) continue;
      final vx = e0.x - mid.x, vy = e0.y - mid.y;
      final t = (vx * ey - vy * ex) / cross;
      final u = (vx * rd.y - vy * rd.x) / cross;
      if (u >= -1e-9 && u <= 1 + 1e-9) ts.add(t);
    }
    ts.sort();
    double? bestA, bestB;
    var bestDist = double.infinity;
    for (var k = 0; k + 1 < ts.length; k += 2) {
      if (ts[k + 1] - ts[k] < 0.5) continue;
      // Closest-to-midpoint pair, same tie-break as shiftRow -- the pivot
      // (mid) is t=0 on the rotated line's own parametrization, so the pair
      // straddling or nearest to 0 is the one actually containing it.
      final m = (ts[k] + ts[k + 1]) / 2;
      final dist = m.abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestA = ts[k];
        bestB = ts[k + 1];
      }
    }
    if (bestA == null || bestB == null) return null;
    return [
      plane.toLatLng(mid.x + rd.x * bestA, mid.y + rd.y * bestA),
      plane.toLatLng(mid.x + rd.x * bestB, mid.y + rd.y * bestB),
    ];
  }
}
