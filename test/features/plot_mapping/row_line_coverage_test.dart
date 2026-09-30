import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/utils/gps_jump_detector.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';
import 'package:simdaas/features/plot_mapping/presentation/utils/corridor_strip.dart';
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

  group('polygon-aware corridors', () {
    // 100 m x 100 m square plot at lat 20. Rows run north-south at x = 30 m
    // (full length) and x = 60 m (SHORT: only the northern half).
    const lat0 = 20.0, lon0 = 73.0;
    final cosLat = math.cos(lat0 * math.pi / 180);
    LatLng at(double x, double y) =>
        LatLng(lat0 + y / _mPerDeg, lon0 + x / (_mPerDeg * cosLat));
    final square = [at(0, 0), at(100, 0), at(100, 100), at(0, 100)];
    final rows = [
      [at(30, 0), at(30, 100)],
      [at(60, 50), at(60, 100)],
    ];

    double bandsArea(List<dynamic> bands) =>
        bands.fold<double>(0, (s, b) => s + _areaSqm(b.points));

    test('sweeping every corridor, incl. outer strips, fills the whole plot', () {
      final track = [
        for (var x = 5.0; x < 100; x += 5)
          for (var y = 0.0; y <= 100; y += 1.5) _pt(at(x, y).latitude, at(x, y).longitude),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows,
          insidePoints: track,
          rowSpacing: 30,
          heatmapType: HeatmapType.gps,
          polygon: square);
      expect(bandsArea(bands), closeTo(10000.0, 300.0));
    });

    test('a short row does not shorten its corridor', () {
      // Sprayer drives up the middle of the x=30..60 corridor from the very
      // start of the plot, well before the short row (y >= 50) begins.
      final track = [
        for (var y = 1.0; y <= 99; y += 1.5) _pt(at(45, y).latitude, at(45, y).longitude),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows,
          insidePoints: track,
          rowSpacing: 30,
          heatmapType: HeatmapType.gps,
          polygon: square);
      final minLat = bands
          .expand((b) => b.points)
          .map((p) => p.latitude)
          .reduce(math.min);
      expect((minLat - lat0) * _mPerDeg, lessThan(3.0)); // starts at the plot edge
    });

    test('the stretch between the plot boundary and the first row is a corridor', () {
      final track = [
        for (var y = 1.0; y <= 99; y += 1.5) _pt(at(10, y).latitude, at(10, y).longitude),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows,
          insidePoints: track,
          rowSpacing: 30,
          heatmapType: HeatmapType.gps,
          polygon: square);
      expect(bands, isNotEmpty);
      for (final b in bands) {
        for (final p in b.points) {
          final x = (p.longitude - lon0) * cosLat * _mPerDeg;
          expect(x, inInclusiveRange(-0.5, 30.5)); // boundary .. first row
        }
      }
    });

    test('bands never leave a concave plot', () {
      // L-shaped plot: the bottom-right quarter is missing.
      final l = [at(0, 0), at(50, 0), at(50, 50), at(100, 50), at(100, 100), at(0, 100)];
      final track = [
        for (var x = 5.0; x < 100; x += 5)
          for (var y = 0.0; y <= 100; y += 1.5)
            if (_inPoly(at(x, y), l)) _pt(at(x, y).latitude, at(x, y).longitude),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows,
          insidePoints: track,
          rowSpacing: 30,
          heatmapType: HeatmapType.gps,
          polygon: l);
      expect(bands, isNotEmpty);
      expect(bandsArea(bands), lessThan(7600.0)); // plot is 7500 m2
      for (final b in bands) {
        for (final p in b.points) {
          expect(_inPoly(p, l) || _minEdgeDist(p, l) < 0.5, isTrue,
              reason: 'band corner $p is outside the plot');
        }
      }
    });
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

  group('long-gap suppression (connectivity dropout, not a GPS jump)', () {
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

    double coveredLength(List<Polygon> bands) => bands.fold<double>(0, (sum, b) {
          final lats = b.points.map((p) => (p.latitude - lat0) * _mPerDeg);
          return sum + (lats.reduce(math.max) - lats.reduce(math.min));
        });

    for (final type in [
      HeatmapType.gps,
      HeatmapType.speed,
      HeatmapType.leftRight,
    ]) {
      test('a flagged long gap does not bridge/fill the sub-bands it spans '
          '(${type.name})', () {
        // Same shape as the GPS-jump gap-fill suppression test above, but
        // isLongGapFromPrevious instead of isJumpFromPrevious -- and a
        // plausible driving speed for the distance/time (unlike a jump),
        // since a real connectivity gap looks like ordinary movement, just
        // over a long silent stretch.
        final track = [
          HeatmapTrackPoint(
            position: along(10),
            isInPlot: true,
            ptoOn: true,
            isAuto: true,
            speed: 4,
            flowRate: 10,
            leftSolenoidOn: true,
            rightSolenoidOn: true,
          ),
          HeatmapTrackPoint(
            position: along(160),
            isInPlot: true,
            ptoOn: true,
            isAuto: true,
            speed: 4,
            flowRate: 10,
            leftSolenoidOn: true,
            rightSolenoidOn: true,
            isLongGapFromPrevious: true,
          ),
        ];
        final bands = RowLineCoverage.buildHeatmapCoverageBands(
            rowLines: rows, insidePoints: track, rowSpacing: 4.0,
            heatmapType: type);
        // Only the two visited sub-bands (near 10 m and near 160 m) are
        // covered -- nowhere close to the ~150 m a bridged fill would give.
        expect(coveredLength(bands), lessThan(20.0));
      });
    }

    test('the same gap without the long-gap flag fills normally', () {
      final track = [
        _pt(along(10).latitude, along(10).longitude),
        _pt(along(160).latitude, along(160).longitude), // isLongGapFromPrevious: false
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows,
          insidePoints: track,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);
      expect(coveredLength(bands), greaterThan(100.0));
    });

    test('GpsJumpDetector.isLongGap: under the threshold is not a gap, '
        'over it is', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      expect(
          GpsJumpDetector.isLongGap(
              t0, t0.add(const Duration(seconds: 30))),
          isFalse);
      expect(
          GpsJumpDetector.isLongGap(
              t0, t0.add(const Duration(seconds: 90))),
          isTrue);
    });
  });

  group('GPS-jump glitch run stays credited to the row driven before it', () {
    // Three tree rows 4 m apart -> two driving lanes: laneA (between tree
    // rows 0/1) and laneB (between tree rows 1/2), 200 m long.
    const lat0 = 20.0, lon0 = 73.0;
    final cosLat = math.cos(lat0 * math.pi / 180);
    final dLon = 4.0 / (_mPerDeg * cosLat);
    final dLat = 200.0 / _mPerDeg;
    final treeRows = [
      [LatLng(lat0, lon0), LatLng(lat0 + dLat, lon0)],
      [LatLng(lat0, lon0 + dLon), LatLng(lat0 + dLat, lon0 + dLon)],
      [LatLng(lat0, lon0 + 2 * dLon), LatLng(lat0 + dLat, lon0 + 2 * dLon)],
    ];
    LatLng laneA(double m) =>
        LatLng(lat0 + dLat * m / 200.0, lon0 + 0.5 * dLon);
    LatLng laneB(double m) =>
        LatLng(lat0 + dLat * m / 200.0, lon0 + 1.5 * dLon);

    double lengthNear(List<Polygon> bands, double lonTarget) {
      final matching = bands.where((b) {
        final avgLon =
            b.points.map((p) => p.longitude).reduce((a, c) => a + c) /
                b.points.length;
        return (avgLon - lonTarget).abs() < dLon * 0.4;
      });
      return matching.fold<double>(0, (sum, b) {
        final lats = b.points.map((p) => (p.latitude - lat0) * _mPerDeg);
        return sum + (lats.reduce(math.max) - lats.reduce(math.min));
      });
    }

    test('a glitch cluster landing near the neighbouring lane is credited '
        'to the lane actually driven, not the neighbour', () {
      final track = [
        for (final m in [0.0, 10.0, 20.0, 30.0, 40.0])
          _pt(laneA(m).latitude, laneA(m).longitude),
        // Glitch: 8 points landing consistently near laneB instead. Only
        // the entry is individually flagged -- the points inside the
        // cluster are close to each other, same as a real stable-but-wrong
        // GPS fix would look, which never trips the pairwise jump check on
        // its own.
        for (var i = 0; i < 8; i++)
          HeatmapTrackPoint(
            position: laneB(45.0 + i * 5),
            isInPlot: true,
            ptoOn: true,
            isAuto: true,
            speed: 4,
            flowRate: 10,
            isJumpFromPrevious: i == 0,
          ),
        // Recovery: naturally back on laneA.
        _pt(laneA(90).latitude, laneA(90).longitude),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: treeRows,
          insidePoints: track,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);

      final laneACoverage = lengthNear(bands, lon0 + 0.5 * dLon);
      final laneBCoverage = lengthNear(bands, lon0 + 1.5 * dLon);
      // The whole 0-90m stretch is credited to laneA, glitch included --
      // not left as a gap, and not bled into laneB.
      expect(laneACoverage, greaterThan(70.0));
      expect(laneBCoverage, lessThan(20.0));
    });

    test('recovery resumes normal per-point tracking on the same lane', () {
      final track = [
        for (final m in [0.0, 10.0, 20.0])
          _pt(laneA(m).latitude, laneA(m).longitude),
        HeatmapTrackPoint(
          position: laneB(25.0),
          isInPlot: true,
          ptoOn: true,
          isAuto: true,
          speed: 4,
          flowRate: 10,
          isJumpFromPrevious: true,
        ),
        // Recovers immediately, then several more genuine laneA points.
        for (final m in [30.0, 40.0, 50.0, 60.0])
          _pt(laneA(m).latitude, laneA(m).longitude),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: treeRows,
          insidePoints: track,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);

      final laneACoverage = lengthNear(bands, lon0 + 0.5 * dLon);
      final laneBCoverage = lengthNear(bands, lon0 + 1.5 * dLon);
      expect(laneACoverage, greaterThan(50.0));
      expect(laneBCoverage, lessThan(10.0));
    });

    test('a sustained, never-recovering move to a new lane eventually wins '
        'once forcing gives up', () {
      final track = [
        for (final m in [0.0, 10.0, 20.0])
          _pt(laneA(m).latitude, laneA(m).longitude),
        // A genuine, sustained move to laneB that never returns to laneA --
        // only the first point is flagged (a real single jump onto the new
        // lane), the rest is ordinary driving on laneB from then on.
        // maxGlitchForcedPoints (20) worth of forcing, plus enough further
        // points for the normal jitter-streak (maxJitterStreak=6, so 7 to
        // confirm) to actually re-establish laneB once forcing gives up.
        for (var i = 0; i < 40; i++)
          HeatmapTrackPoint(
            position: laneB(25.0 + i * 5),
            isInPlot: true,
            ptoOn: true,
            isAuto: true,
            speed: 4,
            flowRate: 10,
            isJumpFromPrevious: i == 0,
          ),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: treeRows,
          insidePoints: track,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);

      final laneBCoverage = lengthNear(bands, lon0 + 1.5 * dLon);
      // The sustained move to laneB is real coverage eventually, not
      // forced onto laneA forever.
      expect(laneBCoverage, greaterThan(40.0));
    });

    test('a genuine row-to-row turn (no jump involved) fills the turn '
        'instead of leaving a gap, then confirms the new lane', () {
      LatLng outside(double m) =>
          LatLng(lat0 + dLat * m / 200.0, lon0 - 2 * dLon);
      final track = [
        for (final m in [0.0, 10.0, 20.0, 30.0, 40.0])
          _pt(laneA(m).latitude, laneA(m).longitude),
        // Turning at the row end: driving out to a headland and back in,
        // well outside either lane's tolerance -- none of this is flagged
        // as a jump (ordinary, continuous driving speed the whole way).
        for (final m in [45.0, 50.0, 55.0])
          _pt(outside(m).latitude, outside(m).longitude),
        // Settles into laneB -- the switch only confirms on the 7th
        // matching point (maxJitterStreak=6, so pendingStreak > 6), so
        // enough points here for a meaningful confirmed stretch afterwards.
        for (final m in [60.0, 65.0, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0,
            100.0, 105.0, 110.0, 115.0, 120.0, 125.0, 130.0, 135.0])
          _pt(laneB(m).latitude, laneB(m).longitude),
      ];
      final bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: treeRows,
          insidePoints: track,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);

      final laneACoverage = lengthNear(bands, lon0 + 0.5 * dLon);
      final laneBCoverage = lengthNear(bands, lon0 + 1.5 * dLon);
      // laneA covers the driven stretch (0-40m) plus the "outside every
      // lane" headland points (45-55m, ~56m total) -- that stretch's own
      // candidacy (pendingRow == null) never gets confirmed before the
      // candidate changes to laneB at m=60, so it falls back to laneA.
      expect(laneACoverage, greaterThan(50.0));
      expect(laneACoverage, lessThan(65.0));
      // laneB gets the FULL confirmed stretch (60-135m, ~76m), including the
      // 6 points (60-85) that were held pending before laneB was confirmed --
      // retroactively credited to laneB once the streak resolves, not left
      // on laneA the way an earlier version of this did.
      expect(laneBCoverage, greaterThan(70.0));
    });

    test('forcedTransitionPoints collects every point plotted before the '
        'new lane is confirmed, and stays empty when there is no turn', () {
      LatLng outside(double m) =>
          LatLng(lat0 + dLat * m / 200.0, lon0 - 2 * dLon);
      // Forced points are credited to whichever row the pending streak
      // actually resolves to (retroactively, via flushPending), not their
      // own raw (off-corridor) positions -- so the marker lines up with
      // wherever the coverage band ends up painted. The 3 "outside every
      // lane" turn points are their own (never-confirmed) candidacy: it
      // gets abandoned the moment the candidate changes to laneB at m=60,
      // so they fall back to laneA (the row trusted before the turn). The
      // next 6 points (60-85) build a laneB candidacy that DOES get
      // confirmed (on the 7th matching point, m=90, once pendingStreak >
      // maxJitterStreak(6)) -- so unlike the old (pre-retroactive-fix)
      // behaviour, they end up credited to laneB, not laneA.
      final expectedForced = [
        for (final m in [45.0, 50.0, 55.0]) laneA(m),
        for (final m in [60.0, 65.0, 70.0, 75.0, 80.0, 85.0]) laneB(m),
      ];
      final track = [
        for (final m in [0.0, 10.0, 20.0, 30.0, 40.0])
          _pt(laneA(m).latitude, laneA(m).longitude),
        for (final m in [45.0, 50.0, 55.0])
          _pt(outside(m).latitude, outside(m).longitude),
        for (final m in [60.0, 65.0, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0,
            100.0, 105.0, 110.0, 115.0, 120.0, 125.0, 130.0, 135.0])
          _pt(laneB(m).latitude, laneB(m).longitude),
      ];

      final forced = <LatLng>[];
      RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: treeRows,
          insidePoints: track,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps,
          forcedTransitionPoints: forced);

      expect(forced.length, expectedForced.length);
      for (var i = 0; i < expectedForced.length; i++) {
        expect(forced[i].latitude, closeTo(expectedForced[i].latitude, 1e-9));
        expect(
            forced[i].longitude, closeTo(expectedForced[i].longitude, 1e-9));
      }

      final steadyTrack = [
        for (final m in [0.0, 10.0, 20.0, 30.0, 40.0, 50.0])
          _pt(laneA(m).latitude, laneA(m).longitude),
      ];
      final forcedSteady = <LatLng>[];
      RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: treeRows,
          insidePoints: steadyTrack,
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps,
          forcedTransitionPoints: forcedSteady);
      expect(forcedSteady, isEmpty);
    });
  });
  group('RowLineGeometry.shiftRow', () {
    const lat0 = 20.0, lon0 = 73.0;
    final cosLat = math.cos(lat0 * math.pi / 180);
    LatLng at(double x, double y) =>
        LatLng(lat0 + y / _mPerDeg, lon0 + x / (_mPerDeg * cosLat));
    final square = [at(0, 0), at(100, 0), at(100, 100), at(0, 100)];
    // North-south row: its left side is WEST (-x).
    final row = [at(30, 0), at(30, 100)];

    test('slides the whole row sideways and keeps both ends on the boundary', () {
      final moved = RowLineGeometry.shiftRow(
          row: row, lateralMeters: 10, polygon: square)!;
      for (final p in moved) {
        expect((p.longitude - lon0) * cosLat * _mPerDeg, closeTo(20.0, 0.05));
      }
      expect((moved[0].latitude - lat0) * _mPerDeg, closeTo(0.0, 0.05));
      expect((moved[1].latitude - lat0) * _mPerDeg, closeTo(100.0, 0.05));
    });

    test('a short row is lengthened to the plot boundary when shifted', () {
      final short = [at(60, 50), at(60, 100)];
      final moved = RowLineGeometry.shiftRow(
          row: short, lateralMeters: -5, polygon: square)!;
      expect((moved[0].latitude - lat0) * _mPerDeg, closeTo(0.0, 0.05));
      expect((moved[1].latitude - lat0) * _mPerDeg, closeTo(100.0, 0.05));
      expect((moved[0].longitude - lon0) * cosLat * _mPerDeg, closeTo(65.0, 0.05));
    });

    test('shifting out of the plot returns null', () {
      expect(
          RowLineGeometry.shiftRow(row: row, lateralMeters: 40, polygon: square),
          isNull);
    });

    test('signedDistance is positive on the row\'s left', () {
      expect(RowLineGeometry.signedDistance(row, at(20, 50)), closeTo(10.0, 0.05));
      expect(RowLineGeometry.signedDistance(row, at(45, 50)), closeTo(-15.0, 0.05));
    });
  });

  group('GPS heatmap Auto/Manual/PTO-off precedence', () {
    HeatmapTrackPoint modePt(double lat, double lon,
            {required bool ptoOn, required bool isAuto}) =>
        HeatmapTrackPoint(
          position: LatLng(lat, lon),
          isInPlot: true,
          ptoOn: ptoOn,
          isAuto: isAuto,
          speed: 4,
          flowRate: ptoOn ? 10 : 0,
        );

    Color? colorAt(List<Polygon> bands, double lat0, double lon0, double dLon) {
      Polygon? best;
      double bestDist = double.infinity;
      for (final b in bands) {
        final avgLat =
            b.points.map((p) => p.latitude).reduce((a, c) => a + c) /
                b.points.length;
        final avgLon =
            b.points.map((p) => p.longitude).reduce((a, c) => a + c) /
                b.points.length;
        final d = ((avgLat - lat0) * _mPerDeg).abs();
        if ((avgLon - lon0).abs() < dLon * 0.4 && d < bestDist) {
          bestDist = d;
          best = b;
        }
      }
      return best?.color;
    }

    test('a later Manual pass overrides an earlier Auto one (latest wins '
        'between the two PTO-on modes), but a later PTO-off pass never '
        'overrides either', () {
      const lat0 = 20.0, lon0 = 73.0;
      final dLon = 4.0 / (_mPerDeg * math.cos(lat0 * math.pi / 180));
      final dLat = 20.0 / _mPerDeg;
      final rows = [
        [LatLng(lat0, lon0), LatLng(lat0 + dLat, lon0)],
        [LatLng(lat0, lon0 + dLon), LatLng(lat0 + dLat, lon0 + dLon)],
      ];
      final midLat = lat0 + dLat * 0.5;
      final midLon = lon0 + dLon / 2;

      // Pass 1: Auto, PTO on -- the whole row.
      final pass1 = [
        for (var i = 0; i <= 10; i++)
          modePt(lat0 + dLat * i / 10, midLon, ptoOn: true, isAuto: true),
      ];
      var bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows, insidePoints: pass1, rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);
      // Bands are painted with alpha 200 (see the GPS branch of
      // buildHeatmapCoverageBands' finalization loop) -- compare against
      // that, not the bare (fully-opaque) Colors.* constant.
      expect(colorAt(bands, midLat, midLon, dLon), Colors.blue.withAlpha(200));

      // Pass 2: Manual, PTO on -- a later, deliberate re-pass in the other
      // mode. Must be shown (latest PTO-on wins), not stuck on Auto.
      final pass2 = [
        for (var i = 0; i <= 10; i++)
          modePt(lat0 + dLat * i / 10, midLon, ptoOn: true, isAuto: false),
      ];
      bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows, insidePoints: [...pass1, ...pass2], rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);
      expect(colorAt(bands, midLat, midLon, dLon), Colors.grey.withAlpha(200),
          reason: 'later Manual pass should override the earlier Auto one');

      // Pass 3: PTO off -- driving back through (e.g. to refill the tank).
      // Must NOT override the Manual colour just established.
      final pass3 = [
        for (var i = 0; i <= 10; i++)
          modePt(lat0 + dLat * i / 10, midLon, ptoOn: false, isAuto: false),
      ];
      bands = RowLineCoverage.buildHeatmapCoverageBands(
          rowLines: rows,
          insidePoints: [...pass1, ...pass2, ...pass3],
          rowSpacing: 4.0,
          heatmapType: HeatmapType.gps);
      expect(colorAt(bands, midLat, midLon, dLon), Colors.grey.withAlpha(200),
          reason: 'a later PTO-off pass must never override an established '
              'PTO-on colour, Auto or Manual');
    });
  });
}
