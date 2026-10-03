import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simdaas/features/reports/domain/report.dart';
import 'package:simdaas/features/reports/presentation/utils/report_pdf_builder.dart';

// A real (if trivial) 1x1 transparent PNG -- pw.MemoryImage decodes its
// bytes immediately in its constructor, so garbage bytes would throw before
// buildReportPdf even runs.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

Report _report({
  String? plotSnapshot,
  List<GPSPointData> trajectory = const [],
  String? chemicalSavedNote,
}) {
  return Report(
    id: '42',
    sprayUsedLitres: 12.5,
    avgFlowRate: 2.0,
    distanceTravelledKm: 3.2,
    distanceWithPtoKm: 2.1,
    distanceWithLeftSprayKm: 1.0,
    distanceWithRightSprayKm: 1.0,
    areaCoveredSqm: 8000.0,
    plotAreaSqm: 20000.0,
    completionPercentage: 40.0,
    chemicalSavedPercentage: 15.0,
    chemicalSavedNote: chemicalSavedNote,
    controlUnitName: 'Pawan',
    linkedSprayerName: 'Sprayer 1',
    linkedTractorName: 'Tractor 1',
    avgFlowRateLpm: 5.0,
    avgFlowRateLacre: 1.5,
    avgSpeedKmph: 4.0,
    maxSpeedKmph: 9.0,
    createdAt: DateTime(2026, 10, 3, 12, 0),
    startedAt: DateTime(2026, 10, 3, 10, 0),
    endedAt: DateTime(2026, 10, 3, 11, 30),
    trajectory: trajectory,
    sessionMode: 'server',
    deviceSessionId: null,
    controlUnitMac: '88:A3:5A:C5:E6:58',
    verificationStatus: 'verified',
    plotSnapshot: plotSnapshot,
  );
}

void main() {
  // buildReportPdf now loads the Agrios logo via rootBundle, which needs a
  // real binding wired up (not just a plain test() runner default).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildReportPdf', () {
    test('produces valid PDF bytes with a map image', () async {
      final report = _report();
      final bytes = await buildReportPdf(
        report: report,
        mapImageBytes: _onePixelPng,
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(500));
    });

    test('produces valid PDF bytes with no map image (placeholder branch)', () async {
      final report = _report();
      final bytes = await buildReportPdf(report: report, mapImageBytes: null);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('falls back to the chemical-saved note when present', () async {
      final report = _report(chemicalSavedNote: 'No Auto-mode spraying in this session');
      final bytes = await buildReportPdf(report: report);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
