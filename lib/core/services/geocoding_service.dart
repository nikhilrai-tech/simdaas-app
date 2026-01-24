import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_exception.dart';

/// Small wrapper around Nominatim geocoding API.
/// Centralises `User-Agent` and error handling for map lookups.
class GeocodingService {
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _userAgent = 'SmartSprayerApp/1.0';

  /// Search Nominatim for the given query. Returns a list of result maps.
  Future<List<Map<String, dynamic>>> searchSuggestions(String query,
      {int limit = 5}) async {
    final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=$limit');
    final resp = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (resp.statusCode == 200) {
      try {
        final body = json.decode(resp.body);
        if (body is List) return List<Map<String, dynamic>>.from(body);
        return [];
      } catch (e) {
        return [];
      }
    }
    throw ApiException(resp.statusCode, 'Geocoding error',
        path: uri.toString(), body: resp.body);
  }

  void dispose() {
    try {
      _client.close();
    } catch (_) {}
  }
}

/// Riverpod provider for a shared `GeocodingService` instance.
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  final svc = GeocodingService();
  ref.onDispose(() => svc.dispose());
  return svc;
});
