import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';
import 'package:simdaas/features/plot_mapping/presentation/utils/row_line_coverage.dart';

const _mPerDeg = 111320.0;

HeatmapTrackPoint _pt(double lat, double lon) => HeatmapTrackPoint(
    position: LatLng(lat, lon),
    isInPlot: true,
    ptoOn: true,
    isAuto: true,
    speed: 4,
    flowRate: 10);

/// Perpendicular distance (m) from p to the infinite line through a-b.
double _distToLine(LatLng p, LatLng a, LatLng b) {
  final cosLat = math.cos(a.latitude * math.pi / 180);
  double x(LatLng q) => (q.longitude - a.longitude) * cosLat * _mPerDeg;
  double y(LatLng q) => (q.latitude - a.latitude) * _mPerDeg;
  final dx = x(b), dy = y(b);
  final len = math.sqrt(dx * dx + dy * dy);
  return ((x(p) * dy - y(p) * dx) / len).abs();
}

bool _inPoly(LatLng p, List<LatLng> poly) {
  var c = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.longitude > p.longitude) != (b.longitude > p.longitude) &&
        p.latitude <
            (b.latitude - a.latitude) *
                    (p.longitude - a.longitude) /
                    (b.longitude - a.longitude) +
                a.latitude) {
      c = !c;
    }
  }
  return c;
}

double _minEdgeDist(LatLng p, List<LatLng> poly) {
  var best = double.infinity;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    final cosLat = math.cos(a.latitude * math.pi / 180);
    double x(LatLng q) => (q.longitude - a.longitude) * cosLat * _mPerDeg;
    double y(LatLng q) => (q.latitude - a.latitude) * _mPerDeg;
    final dx = x(b), dy = y(b);
    final l2 = dx * dx + dy * dy;
    final t = l2 == 0 ? 0.0 : ((x(p) * dx + y(p) * dy) / l2).clamp(0.0, 1.0);
    final ex = x(p) - dx * t, ey = y(p) - dy * t;
    best = math.min(best, math.sqrt(ex * ex + ey * ey));
  }
  return best;
}

double _areaSqm(List<LatLng> pts) {
  final lat0 = pts.first.latitude, lon0 = pts.first.longitude;
  final cosLat = math.cos(lat0 * math.pi / 180);
  var s = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    final ax = (a.longitude - lon0) * cosLat * _mPerDeg,
        ay = (a.latitude - lat0) * _mPerDeg;
    final bx = (b.longitude - lon0) * cosLat * _mPerDeg,
        by = (b.latitude - lat0) * _mPerDeg;
    s += ax * by - bx * ay;
  }
  return s.abs() / 2;
}

void main() {
  // Real tapering plot ("testing", staging) whose rows fan out and end at
  // different latitudes because they are clipped to the polygon -- the
  // shape that used to produce skewed blocks and triangles poking out of
  // the plot.
  final polygon = <LatLng>[
    LatLng(20.249879825255817, 73.9251504877904),
    LatLng(20.24989583491015, 73.9261843573873),
    LatLng(20.25615484833764, 73.92701814785516),
    LatLng(20.262940833816604, 73.92795477681388),
    LatLng(20.26264761510806, 73.92247335326698),
  ];
  final wedgeRows = <List<LatLng>>[
    [LatLng(20.262664834119406, 73.92279524505452), LatLng(20.249882613765127, 73.92533056382054)],
    [LatLng(20.262726698482442, 73.92395173598221), LatLng(20.250837878754854, 73.92630985115515)],
    [LatLng(20.262788562845476, 73.92510822690991), LatLng(20.254362899084857, 73.92677943448233)],
    [LatLng(20.262850427208512, 73.9262647178376), LatLng(20.257863138843007, 73.9272539329688)],
    [LatLng(20.26291229157155, 73.9274212087653), LatLng(20.261337756151043, 73.92773351359878)],
  ];

  test('staggered row ends on a tapering plot: bands stay inside the plot', () {
    final track = [
      for (var i = 0; i <= 90; i++) _pt(20.2585 - i * 0.0001, 73.92575),
    ];
    final bands = RowLineCoverage.buildHeatmapCoverageBands(
        rowLines: wedgeRows,
        insidePoints: track,
        rowSpacing: 120.0,
        heatmapType: HeatmapType.gps);
    expect(bands, isNotEmpty);
    for (final b in bands) {
      for (final p in b.points) {
        final ok = _inPoly(p, polygon) || _minEdgeDist(p, polygon) < 0.5;
        expect(ok, isTrue, reason: 'band corner $p is outside the plot');
      }
    }
  });

  test('parallel rows: band width equals the true gap between the rows', () {
    // Two north-south rows 4 m apart, 100 m long.
    const lat0 = 20.0, lon0 = 73.0;
    final dLon = 4.0 / (_mPerDeg * math.cos(lat0 * math.pi / 180));
    final dLat = 100.0 / _mPerDeg;
    final rows = [
      [LatLng(lat0, lon0), LatLng(lat0 + dLat, lon0)],
      [LatLng(lat0, lon0 + dLon), LatLng(lat0 + dLat, lon0 + dLon)],
    ];
    final track = [
      for (var i = 0; i <= 50; i++)
        _pt(lat0 + dLat * i / 50, lon0 + dLon / 2),
    ];
    final bands = RowLineCoverage.buildHeatmapCoverageBands(
        rowLines: rows,
        insidePoints: track,
        rowSpacing: 4.0,
        heatmapType: HeatmapType.gps);
    final area = bands.fold<double>(0, (s, b) => s + _areaSqm(b.points));
    expect(area, closeTo(400.0, 40.0)); // 100 m x 4 m
    for (final b in bands) {
      for (final p in b.points) {
        final d = math.min(_distToLine(p, rows[0][0], rows[0][1]),
            _distToLine(p, rows[1][0], rows[1][1]));
        expect(d, lessThan(0.05), reason: 'corner $p is not on a row line');
      }
    }
  });

  test('deleted row placeholder: neighbours get independent edge bands', () {
    const lat0 = 20.0, lon0 = 73.0;
    final dLon = 6.0 / (_mPerDeg * math.cos(lat0 * math.pi / 180));
    final dLat = 100.0 / _mPerDeg;
    final a = [LatLng(lat0, lon0), LatLng(lat0 + dLat, lon0)];
    final c = [LatLng(lat0, lon0 + dLon), LatLng(lat0 + dLat, lon0 + dLon)];
    final track = [
      for (var i = 0; i <= 50; i++) _pt(lat0 + dLat * i / 50, lon0),
    ];
    final bands = RowLineCoverage.buildHeatmapCoverageBands(
        rowLines: [a, <LatLng>[], c],
        insidePoints: track,
        rowSpacing: 3.0,
        heatmapType: HeatmapType.gps);
    expect(bands, isNotEmpty);
    for (final b in bands) {
      for (final p in b.points) {
        expect(_distToLine(p, a[0], a[1]), lessThan(1.6),
            reason: 'edge band must hug row A, not span the deleted gap');
      }
    }
  });

  group('GPS-jump gap-fill suppression', () {
    // Two north-south rows 4 m apart, 200 m long.
    const lat0 = 20.0, lon0 = 73.0;
    final cosLat = math.cos(lat0 * math.pi / 180);
    final dLon = 4.0 / (_mPerDeg * cosLat);
    final dLat = 200.0 / _mPerDeg;
    final rows = [
      [LatLng(lat0, lon0), LatLng(lat0 + dLat, lon0)],
      [LatLng(lat0, lon0 + dLon), LatLng(lat0 + dLat, lon0 + dLon)],
    ];
    LatLng along(double metres) =>
        LatLng(lat0 + dLat * metres / 200.0, lon0 + dLon / 2);

    test('a flagged jump does not bridge/fill the sub-bands it spans', () {
      // Two points 150 m apart along the corridor with nothing recorded in
      // between (a real jump would never have intermediate samples) --
      // flagging the second one must stop the gap-fill from painting the
      // 150 m stretch as if it had been driven.
      final track = [
        _pt(along(10).latitude, along(10).longitude),
        HeatmapTrackPoint(
          position: along(160),
          isInPlot: true,
          ptoOn: true,
          isAuto: true,
          speed: 4,
          flowRate: 10,
          isJumpFromPrevious: true,
        ),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows,
          insidePoints: track,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);
      // Only the two visited sub-bands (near 10 m and near 160 m) are
      // covered -- nowhere close to the ~150 m that a bridged fill would
      // produce.
      final coveredLength = bands.fold<double>(0, (sum, b) {
        final lats = b.points.map((p) => (p.latitude - lat0) * _mPerDeg);
        return sum + (lats.reduce(math.max) - lats.reduce(math.min));
      });
      expect(coveredLength, lessThan(20.0));
    });

    test('the same gap without the jump flag fills normally', () {
      final track = [
        _pt(along(10).latitude, along(10).longitude),
        _pt(along(160).latitude, along(160).longitude), // isJumpFromPrevious: false
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows,
          insidePoints: track,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);
      final coveredLength = bands.fold<double>(0, (sum, b) {
        final lats = b.points.map((p) => (p.latitude - lat0) * _mPerDeg);
        return sum + (lats.reduce(math.max) - lats.reduce(math.min));
      });
      expect(coveredLength, greaterThan(100.0));
    });
  });
}
