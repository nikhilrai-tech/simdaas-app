import 'package:simdaas/core/services/api_service.dart';
import '../models/plot_model.dart';

abstract class PlotRemoteDataSource {
  Future<PlotModel> addPlot(PlotModel plot);
  Future<List<PlotModel>> getPlots(String userId);
  Future<void> updatePlot(PlotModel plot);
  Future<void> deletePlot(String id);
}

class PlotRemoteDataSourceImpl implements PlotRemoteDataSource {
  final ApiService api;
  PlotRemoteDataSourceImpl(this.api);

  @override
  Future<PlotModel> addPlot(PlotModel plot) async {
    final polygon = plot.polygon.map((p) => [p.latitude, p.longitude]).toList();
    final Map<String, dynamic> payload = {
      'name': plot.name,
      'polygon': polygon,
      'row_spacing': plot.rowSpacing,
      'tree_count': plot.treeCount,
      'user_area_acre': plot.area,
      'approxArea': plot.area,
      'bed_height': plot.bedHeight,
    };
    final response = await api.postJson('/plot/api/', jsonBody: payload)
        as Map<String, dynamic>;
    // Normalize polygon in response before parsing
    final rawPolygon = response['polygon'];
    if (rawPolygon is List) {
      response['polygon'] = rawPolygon.map((e) {
        if (e is List && e.length >= 2) return {'lat': e[0], 'lng': e[1]};
        if (e is Map) return {'lat': e['lat'], 'lng': e['lng']};
        return null;
      }).where((e) => e != null).toList();
    }
    final serverId =
        (response['id']?.toString() ?? response['pk']?.toString() ?? plot.id);
    return PlotModel.fromJson(serverId, response);
  }

  @override
  Future<List<PlotModel>> getPlots(String userId) async {
    final data = await api.getJson('/plot/api/') as List<dynamic>;
    final List<PlotModel> out = [];
    for (final item in data) {
      final Map<String, dynamic> jsonItem = item as Map<String, dynamic>;
      // Backend may provide polygon as [[lat,lng],...] or as [{lat,lng},...]
      final rawPolygon = jsonItem['polygon'];
      if (rawPolygon is List) {
        // normalize to list of maps with 'lat' and 'lng' for PlotModel.fromJson
        final poly = rawPolygon
            .map((e) {
              if (e is List && e.length >= 2) return {'lat': e[0], 'lng': e[1]};
              if (e is Map) return {'lat': e['lat'], 'lng': e['lng']};
              return null;
            })
            .where((e) => e != null)
            .toList();
        jsonItem['polygon'] = poly;
      }
      final id =
          (jsonItem['id']?.toString() ?? jsonItem['pk']?.toString() ?? '');
      out.add(PlotModel.fromJson(id, jsonItem));
    }
    return out;
  }

  @override
  Future<void> updatePlot(PlotModel plot) async {
    final payload = plot.toJson();
    // backend expects snake_case for some fields if not handled by toJson
    // Let's ensure bed_height is a string if the backend expects it so
    if (payload['bedHeight'] != null) {
      payload['bed_height'] = payload['bedHeight'].toString();
    }
    // PATCH to the specific plot endpoint; backend expected trailing slash
    await api.patchJson('/plot/api/${plot.id}/', jsonBody: payload);
  }

  @override
  Future<void> deletePlot(String id) async {
    // backend expects DELETE on the resource URL
    await api.delete('/plot/api/$id/',
        headers: {'Content-Type': 'application/json'});
  }
}
