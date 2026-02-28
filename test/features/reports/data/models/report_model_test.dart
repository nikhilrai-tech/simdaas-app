import 'package:flutter_test/flutter_test.dart';
import 'package:simdaas/features/reports/data/models/report_model.dart';

void main() {
  group('ReportModel', () {
    test('fromJson should return a valid model', () {
      final json = {
        'id': 1,
        'spray_used_litres': 35.0,
        'avg_flow_rate': 2.5,
        'distance_travelled_km': 1.5,
        'distance_with_pto_km': 1.2,
        'distance_with_left_spray_km': 0.8,
        'distance_with_right_spray_km': 0.7,
        'area_covered_sqm': 5000.0,
        'plot_area_sqm': 10000.0,
        'completion_percentage': 50.0,
        'created_at': "2026-02-04T21:50:15.312015+05:30"
      };

      final model = ReportModel.fromJson(json);

      expect(model.id, '1');
      expect(model.sprayUsedLitres, 35.0);
      expect(model.distanceWithLeftSprayKm, 0.8);
      expect(model.completionPercentage, 50.0);
    });

    test('fromJson handles null values gracefully', () {
      final json = <String, dynamic>{};
      final model = ReportModel.fromJson(json);

      expect(model.id, '');
      expect(model.sprayUsedLitres, 0.0);
      expect(model.areaCoveredSqm, 0.0);
    });
  });
}
