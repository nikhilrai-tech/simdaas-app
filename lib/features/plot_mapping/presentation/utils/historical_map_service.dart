import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/core/services/auth_service.dart';

/// Below this zoom, the historical overlay doesn't request tiles at all
/// (see its TileLayer's own minZoom in map_layers.dart/row_line_screen.dart)
/// -- CDSE's Sentinel-2 Process API hard-rejects anything coarser than
/// 1500 m/pixel (confirmed: a zoom-5 tile needs ~4357 m/pixel there, a
/// flat 400 "exceeds the limit" every single time, independent of load).
/// 12 is a wide safety margin above CDSE's own ~zoom-7 cutoff, and a
/// whole-town view is already past where individual fields are
/// distinguishable anyway.
const double historicalMapMinZoom = 12;

/// One historical-imagery provider as reported by the backend's
/// GET /plot/api/historical-map/providers/ -- see
/// smart-spray-backend/plot/historical_map.py's module docstring for what
/// each one actually is and why they're fetched differently.
class HistoricalMapProviderInfo {
  final String id; // 'cdse_free' | 'google_earth_paid'
  final String label;
  final String tier; // 'free' | 'paid'
  final bool configured;

  const HistoricalMapProviderInfo({
    required this.id,
    required this.label,
    required this.tier,
    required this.configured,
  });

  factory HistoricalMapProviderInfo.fromJson(Map<String, dynamic> json) =>
      HistoricalMapProviderInfo(
        id: json['id'] as String,
        label: json['label'] as String,
        tier: json['tier'] as String,
        configured: json['configured'] as bool? ?? false,
      );
}

/// Picked provider + date, and everything a flutter_map TileLayer needs to
/// show it: a {z}/{x}/{y} URL template, plus request headers when the tiles
/// have to come through this app's own backend (the CDSE provider -- its
/// proxy endpoint is behind the same auth every other API call uses). The
/// Google Earth Engine provider's template points directly at Google's own
/// tile server and needs no headers from here.
class HistoricalMapTileSource {
  final String urlTemplate;
  final Map<String, String>? headers;

  const HistoricalMapTileSource({required this.urlTemplate, this.headers});
}

class HistoricalMapService {
  final ApiService api;
  const HistoricalMapService(this.api);

  Future<List<HistoricalMapProviderInfo>> getProviders() async {
    final data = await api.getJson('/plot/api/historical-map/providers/')
        as Map<String, dynamic>;
    final list = (data['providers'] as List<dynamic>? ?? []);
    return list
        .map((e) => HistoricalMapProviderInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Builds the tile source for [providerId] + [date]. For 'cdse_free' this
  /// is purely client-side (the proxy tile URL is itself already a
  /// {z}/{x}/{y} template -- no extra round trip needed to construct it).
  /// For 'google_earth_paid' this makes one call to the backend, which asks
  /// Earth Engine for a template built around the requested date.
  Future<HistoricalMapTileSource> getTileSource({
    required String providerId,
    required DateTime date,
  }) async {
    final isoDate =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (providerId == 'cdse_free') {
      final template =
          '${api.baseUrl}/plot/api/historical-map/cdse/tile/{z}/{x}/{y}/?date=$isoDate';
      final token = api.authToken;
      return HistoricalMapTileSource(
        urlTemplate: template,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );
    }
    final data = await api.getJson(
        '/plot/api/historical-map/gee/tile-template/?date=$isoDate') as Map<String, dynamic>;
    return HistoricalMapTileSource(urlTemplate: data['tile_url_template'] as String);
  }
}

final historicalMapServiceProvider = Provider<HistoricalMapService>(
    (ref) => HistoricalMapService(ref.read(apiServiceProvider)));
