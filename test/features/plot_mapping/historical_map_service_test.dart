import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
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

  group('HistoricalMapService.getRegionImage', () {
    final bounds = LatLngBounds(
      const LatLng(12.0, 77.0),
      const LatLng(12.01, 77.01),
    );

    test('requests ONE composite image for the given bbox/date/provider '
        '(not a tile template) and returns its raw bytes', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/plot/api/historical-map/region-image/');
        expect(request.url.queryParameters['provider'], 'cdse_free');
        expect(request.url.queryParameters['date'], '2026-06-15');
        expect(request.url.queryParameters['west'], '77.0');
        expect(request.url.queryParameters['south'], '12.0');
        expect(request.url.queryParameters['east'], '77.01');
        expect(request.url.queryParameters['north'], '12.01');
        return http.Response.bytes([0xff, 0xd8, 1, 2, 3], 200);
      });
      final api = ApiService(baseUrl: 'https://api.example.com', client: mockClient);
      final service = HistoricalMapService(api);

      final image = await service.getRegionImage(
        providerId: 'cdse_free',
        date: DateTime(2026, 6, 15),
        bounds: bounds,
      );

      expect(image.bytes, [0xff, 0xd8, 1, 2, 3]);
    });

    test('same endpoint and query shape for google_earth_paid -- only the '
        'provider param differs', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/plot/api/historical-map/region-image/');
        expect(request.url.queryParameters['provider'], 'google_earth_paid');
        expect(request.url.queryParameters['date'], '2026-03-10');
        return http.Response.bytes([0x89, 0x50, 0x4e, 0x47], 200);
      });
      final api = ApiService(baseUrl: 'https://api.example.com', client: mockClient);
      final service = HistoricalMapService(api);

      final image = await service.getRegionImage(
        providerId: 'google_earth_paid',
        date: DateTime(2026, 3, 10),
        bounds: bounds,
      );

      expect(image.bytes, [0x89, 0x50, 0x4e, 0x47]);
    });

    test('parses the X-Image-Actual-Date header into actualDate', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          [0xff, 0xd8], 200,
          headers: {'X-Image-Actual-Date': '2026-06-18'},
        );
      });
      final api = ApiService(baseUrl: 'https://api.example.com', client: mockClient);
      final service = HistoricalMapService(api);

      final image = await service.getRegionImage(
        providerId: 'cdse_free',
        date: DateTime(2026, 6, 15),
        bounds: bounds,
      );

      expect(image.actualDate, DateTime(2026, 6, 18));
    });

    test('actualDate is null when the header is absent', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes([0xff, 0xd8], 200);
      });
      final api = ApiService(baseUrl: 'https://api.example.com', client: mockClient);
      final service = HistoricalMapService(api);

      final image = await service.getRegionImage(
        providerId: 'cdse_free',
        date: DateTime(2026, 6, 15),
        bounds: bounds,
      );

      expect(image.actualDate, isNull);
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
