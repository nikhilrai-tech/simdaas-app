import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/features/plot_mapping/presentation/utils/historical_map_service.dart';

void main() {
  group('HistoricalMapProviderInfo.fromJson', () {
    test('parses a configured provider', () {
      final p = HistoricalMapProviderInfo.fromJson({
        'id': 'cdse_free', 'label': 'Copernicus (free)', 'tier': 'free', 'configured': true,
      });
      expect(p.id, 'cdse_free');
      expect(p.tier, 'free');
      expect(p.configured, isTrue);
    });

    test('defaults configured to false when absent', () {
      final p = HistoricalMapProviderInfo.fromJson({
        'id': 'google_earth_paid', 'label': 'Google Earth (paid)', 'tier': 'paid',
      });
      expect(p.configured, isFalse);
    });
  });

  group('HistoricalMapService.getTileSource', () {
    test('cdse_free builds the proxy tile template client-side, with an '
        'auth header for this app\'s own backend -- no network call needed '
        'just to build the URL', () async {
      final api = ApiService(baseUrl: 'https://api.example.com');
      api.setAuthToken('my-jwt-access-token'); // realistic length; setAuthToken's own debug log assumes >=8 chars
      final service = HistoricalMapService(api);

      final source = await service.getTileSource(
        providerId: 'cdse_free',
        date: DateTime(2026, 6, 15),
      );

      expect(
        source.urlTemplate,
        'https://api.example.com/plot/api/historical-map/cdse/tile/{z}/{x}/{y}/?date=2026-06-15',
      );
      expect(source.headers, {'Authorization': 'Bearer my-jwt-access-token'});
    });

    test('cdse_free omits the Authorization header when signed out', () async {
      final api = ApiService(baseUrl: 'https://api.example.com');
      final service = HistoricalMapService(api);

      final source = await service.getTileSource(
        providerId: 'cdse_free',
        date: DateTime(2026, 1, 5),
      );

      expect(source.urlTemplate, contains('date=2026-01-05'));
      expect(source.headers, isNull);
    });

    test('google_earth_paid asks the backend for a template and uses it '
        'directly, with no headers of its own (points at Google, not this '
        'backend)', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/plot/api/historical-map/gee/tile-template/');
        expect(request.url.queryParameters['date'], '2026-03-10');
        return http.Response(
          jsonEncode({'tile_url_template': 'https://earthengine.googleapis.com/.../tiles/{z}/{x}/{y}'}),
          200,
        );
      });
      final api = ApiService(baseUrl: 'https://api.example.com', client: mockClient);
      final service = HistoricalMapService(api);

      final source = await service.getTileSource(
        providerId: 'google_earth_paid',
        date: DateTime(2026, 3, 10),
      );

      expect(source.urlTemplate, 'https://earthengine.googleapis.com/.../tiles/{z}/{x}/{y}');
      expect(source.headers, isNull);
    });
  });

  group('HistoricalMapService.getProviders', () {
    test('parses the providers list from the backend', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/plot/api/historical-map/providers/');
        return http.Response(
          jsonEncode({
            'providers': [
              {'id': 'cdse_free', 'label': 'Copernicus (free)', 'tier': 'free', 'configured': true},
              {'id': 'google_earth_paid', 'label': 'Google Earth (paid)', 'tier': 'paid', 'configured': false},
            ],
          }),
          200,
        );
      });
      final api = ApiService(baseUrl: 'https://api.example.com', client: mockClient);
      final service = HistoricalMapService(api);

      final providers = await service.getProviders();

      expect(providers, hasLength(2));
      expect(providers[0].id, 'cdse_free');
      expect(providers[0].configured, isTrue);
      expect(providers[1].id, 'google_earth_paid');
      expect(providers[1].configured, isFalse);
    });
  });
}
