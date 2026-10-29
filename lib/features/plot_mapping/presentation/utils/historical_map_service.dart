import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_service.dart';
import 'package:simdaas/core/services/auth_service.dart';

/// Below this zoom, the historical overlay doesn't fetch an image at all
/// -- the viewport bbox a lower zoom covers gets coarser than either
/// provider can actually serve (confirmed on CDSE: a zoom-5 viewport
/// needs ~4357 m/pixel, a flat 400 "exceeds the limit" of 1500 m/pixel
/// every single time, independent of load -- and an oversized bbox on
/// Earth Engine just means a slow fetch for an image too coarse to be
/// useful anyway). 12 is a wide safety margin above CDSE's own ~zoom-7
/// cutoff, and a whole-town view is already past where individual fields
/// are distinguishable anyway.
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

  /// ONE composite image covering [bounds] (the farmer's current map
  /// viewport, not an XYZ tile pyramid -- see
  /// smart-spray-backend/plot/historical_map.py's module docstring for
  /// why: both providers' per-tile paths turned out to have hard
  /// rate/size ceilings a real viewport's burst of simultaneous tile
  /// requests kept hitting). Same backend endpoint, same auth, for
  /// either provider.
  Future<Uint8List> getRegionImage({
    required String providerId,
    required DateTime date,
    required LatLngBounds bounds,
  }) async {
    final isoDate =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final query = {
      'provider': providerId,
      'date': isoDate,
      'west': bounds.west.toString(),
      'south': bounds.south.toString(),
      'east': bounds.east.toString(),
      'north': bounds.north.toString(),
    };
    final queryString = query.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final path = '/plot/api/historical-map/region-image/?$queryString';
    final response = await api.get(path);
    return response.bodyBytes;
  }
}

final historicalMapServiceProvider = Provider<HistoricalMapService>(
    (ref) => HistoricalMapService(ref.read(apiServiceProvider)));

/// Whether the "Historical map" entry point should be shown at all -- not
/// just the per-provider "Not set up yet" greying-out inside the picker
/// sheet, the icon button itself. True once the backend reports at least
/// one provider as configured, false (hides the icon entirely) while
/// neither is, and false while still loading or on any error -- fails
/// closed, never flashes the icon on briefly before hiding it.
///
/// A pure runtime check against the live backend, not a build-time flag:
/// turning a provider on server-side (adding its real credentials, the
/// same deploy steps already used for CDSE/GEE on staging) makes the icon
/// appear for every already-installed copy of the app automatically, no
/// new release needed -- as long as that copy's build already includes
/// this check, which every build from this point on does.
final historicalMapAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    final providers = await ref.read(historicalMapServiceProvider).getProviders();
    return providers.any((p) => p.configured);
  } catch (_) {
    return false;
  }
});
