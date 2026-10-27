import 'package:flutter_test/flutter_test.dart';
import 'package:simdaas/features/equipments/data/models/equipment_model.dart';
import 'package:simdaas/features/reports/data/models/report_model.dart';

Map<String, dynamic> controlUnitJson({String? sessionMode, bool? supported}) => {
      'category': 'control_unit',
      'name': 'CU 1',
      'user': 'u1',
      'mac_addr': 'AA:BB:CC:DD:EE:01',
      if (sessionMode != null) 'session_mode': sessionMode,
      if (supported != null) 'device_sessions_supported': supported,
    };

void main() {
  group('Control unit session mode', () {
    test('a control unit from an older backend defaults to Automatic', () {
      final cu = EquipmentModel.fromJson('1', controlUnitJson());
      expect(cu.sessionMode, isNull);
      expect(cu.isManualSessionMode, isFalse);
      expect(cu.deviceSessionsSupported, isNull);
    });

    test("'server' is Automatic", () {
      final cu = EquipmentModel.fromJson('1', controlUnitJson(sessionMode: 'server', supported: false));
      expect(cu.isManualSessionMode, isFalse);
      expect(cu.deviceSessionsSupported, isFalse);
    });

    test("'device' is Manual and remembers firmware support", () {
      final cu = EquipmentModel.fromJson('1', controlUnitJson(sessionMode: 'device', supported: true));
      expect(cu.isManualSessionMode, isTrue);
      expect(cu.deviceSessionsSupported, isTrue);
    });

    test('tractors and sprayers are never Manual', () {
      final tractor = EquipmentModel.fromJson('2', {'category': 'tractor', 'name': 't', 'user': 'u1'});
      expect(tractor.isManualSessionMode, isFalse);
    });
  });

  group('Amended reports', () {
    test('an amended report exposes the backend note', () {
      final report = ReportModel.fromJson({
        'id': 7,
        'created_at': '2026-02-04T21:50:15.312015+05:30',
        'amended': true,
        'amended_note': 'Updated after network data was recovered from a connectivity gap.',
      });
      expect(report.amended, isTrue);
      expect(report.amendedNote, contains('recovered'));
    });

    test('reports from an older backend are not amended', () {
      final report = ReportModel.fromJson({'id': 7, 'created_at': '2026-02-04T21:50:15.312015+05:30'});
      expect(report.amended, isFalse);
      expect(report.amendedNote, isNull);
    });
  });
}
