import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/features/plot_mapping/presentation/utils/plot_kml.dart';

void main() {
  group('buildPlotKml / parsePlotKml', () {
    final polygon = [
      LatLng(17.385, 78.4867),
      LatLng(17.386, 78.4867),
      LatLng(17.386, 78.4877),
      LatLng(17.385, 78.4877),
    ];
    final rowLines = [
      [LatLng(17.3852, 78.4868), LatLng(17.3858, 78.4868)],
      [LatLng(17.3852, 78.4870), LatLng(17.3858, 78.4870)],
      [LatLng(17.3852, 78.4872), LatLng(17.3858, 78.4872)],
    ];

    void expectClose(LatLng a, LatLng b) {
      expect(a.latitude, closeTo(b.latitude, 1e-9));
      expect(a.longitude, closeTo(b.longitude, 1e-9));
    }

    test('round-trips boundary and row lines', () {
      final kml = buildPlotKml(
        plotName: 'Test Plot',
        polygon: polygon,
        rowLines: rowLines,
      );
      final parsed = parsePlotKml(kml);

      expect(parsed.polygon, isNotNull);
      expect(parsed.polygon!.length, polygon.length);
      for (var i = 0; i < polygon.length; i++) {
        expectClose(parsed.polygon![i], polygon[i]);
      }

      expect(parsed.rowLines.length, rowLines.length);
      for (var i = 0; i < rowLines.length; i++) {
        expect(parsed.rowLines[i].length, rowLines[i].length);
        for (var j = 0; j < rowLines[i].length; j++) {
          expectClose(parsed.rowLines[i][j], rowLines[i][j]);
        }
      }
    });

    test('escapes a plot name with special characters', () {
      final kml = buildPlotKml(
        plotName: 'North <Field> & "Rows"',
        polygon: polygon,
        rowLines: const [],
      );
      expect(kml.contains('North &lt;Field&gt; &amp; &quot;Rows&quot;'), isTrue);
      // Still parses cleanly even though there's no boundary-less branch here.
      final parsed = parsePlotKml(kml);
      expect(parsed.polygon, isNotNull);
    });

    test('preserves a deleted row\'s index gap on round-trip', () {
      // row_line_screen.dart never removes a deleted row's slot from
      // rowLines -- it leaves an empty [] placeholder so later rows keep
      // their original index (the coverage/corridor algorithm and
      // _nearestRealRow rely on this to know row N and row N+2 were never
      // actually adjacent). buildPlotKml skips the placeholder when writing
      // Placemarks but encodes the real index in each one's "Row N" name;
      // parsePlotKml must read that back and reconstruct the same gap,
      // not collapse it into a contiguous list.
      final original = [
        rowLines[0],
        const <LatLng>[], // deleted-row placeholder
        rowLines[1],
      ];
      final kml = buildPlotKml(plotName: 'Plot', polygon: polygon, rowLines: original);
      final parsed = parsePlotKml(kml);

      expect(parsed.rowLines.length, 3);
      expect(parsed.rowLines[1], isEmpty);
      expect(parsed.rowLines[0].length, rowLines[0].length);
      for (var j = 0; j < rowLines[0].length; j++) {
        expectClose(parsed.rowLines[0][j], rowLines[0][j]);
      }
      expect(parsed.rowLines[2].length, rowLines[1].length);
      for (var j = 0; j < rowLines[1].length; j++) {
        expectClose(parsed.rowLines[2][j], rowLines[1][j]);
      }
    });

    test('parses a boundary-only KML (no row lines)', () {
      final kml = buildPlotKml(plotName: 'Plot', polygon: polygon, rowLines: const []);
      final parsed = parsePlotKml(kml);
      expect(parsed.polygon, isNotNull);
      expect(parsed.rowLines, isEmpty);
    });

    test('parses a rows-only KML (no boundary)', () {
      final kml = buildPlotKml(plotName: 'Plot', polygon: const [], rowLines: rowLines);
      final parsed = parsePlotKml(kml);
      expect(parsed.polygon, isNull);
      expect(parsed.rowLines.length, rowLines.length);
    });

    test('throws a readable error on malformed XML', () {
      expect(() => parsePlotKml('not xml at all <<<'), throwsFormatException);
    });

    test('throws when neither a boundary nor any row line is present', () {
      const emptyKml = '<?xml version="1.0"?><kml><Document></Document></kml>';
      expect(() => parsePlotKml(emptyKml), throwsFormatException);
    });
  });
}
