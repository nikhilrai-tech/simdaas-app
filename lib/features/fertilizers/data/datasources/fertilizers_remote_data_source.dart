import 'package:simdaas/core/services/api_service.dart';

class FertilizersRemoteDataSource {
  final ApiService api;
  FertilizersRemoteDataSource(this.api);

  Future<List<Map<String, dynamic>>> getFertilizers() async {
    final data = await api.getJson('/fertilizers/api/');
    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getFertilizerMixes() async {
    final data = await api.getJson('/fertilizers/api-mixes/');
    return (data as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createMix(Map<String, dynamic> payload) async {
    final data =
        await api.postJson('/fertilizers/api-mixes/', jsonBody: payload);
    return (data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> createFertilizer(
      Map<String, dynamic> payload) async {
    final data = await api.postJson('/fertilizers/api/', jsonBody: payload);
    return (data as Map<String, dynamic>);
  }
}
