import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/features/reports/data/datasources/investor_report_remote_data_source.dart';

void main() {
  group('InvestorReportRemoteDataSourceImpl.getReportsPage', () {
    test('hits the fleet-wide investor endpoint, not the farmer-scoped one', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/admin/investor-dashboard/reports/');
        expect(request.url.queryParameters['page'], '2');
        expect(request.url.queryParameters['page_size'], '10');
        return http.Response(
          jsonEncode({
            'results': [
              {'id': 1}, {'id': 2},
            ],
            'count': 7,
          }),
          200,
        );
      });
      final api = ApiService(baseUrl: 'https://api.example.com', client: mockClient);
      final ds = InvestorReportRemoteDataSourceImpl(api);

      final result = await ds.getReportsPage(page: 2, pageSize: 10);

      expect(result.reports, hasLength(2));
      expect(result.totalCount, 7);
    });
  });

  group('InvestorReportRemoteDataSourceImpl.getReport', () {
    test('hits the fleet-wide investor detail endpoint by id', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/admin/investor-dashboard/reports/42/');
        return http.Response(jsonEncode({'id': 42, 'driver_name': 'Ramesh'}), 200);
      });
      final api = ApiService(baseUrl: 'https://api.example.com', client: mockClient);
      final ds = InvestorReportRemoteDataSourceImpl(api);

      final report = await ds.getReport('42');

      expect(report.id, '42');
      expect(report.driverName, 'Ramesh');
    });
  });

  group('InvestorReportRemoteDataSourceImpl write methods', () {
    // No real HTTP client needed -- these must throw before ever making a
    // request, since the investor-dashboard backend doesn't expose write
    // endpoints for reports at all.
    final ds = InvestorReportRemoteDataSourceImpl(
      ApiService(baseUrl: 'https://api.example.com', client: MockClient((_) async {
        throw StateError('should never make a network call');
      })),
    );

    test('deleteReport throws', () {
      expect(() => ds.deleteReport('1'), throwsUnsupportedError);
    });

    test('updateReportDetails throws', () {
      expect(
        () => ds.updateReportDetails('1', driverName: 'x'),
        throwsUnsupportedError,
      );
    });

    test('correctReportPlot throws', () {
      expect(() => ds.correctReportPlot('1', '2'), throwsUnsupportedError);
    });

    test('emailReport throws', () {
      expect(() => ds.emailReport('1', Uint8List(0)), throwsUnsupportedError);
    });

    test('uploadHeatmapSnapshot is a silent no-op, not an error', () async {
      // Should complete without throwing and without hitting the network.
      await ds.uploadHeatmapSnapshot('1', gps: 'base64data');
    });
  });
}
