import 'package:flutter/foundation.dart';
import 'package:simdaas/core/services/api_service.dart';
import '../models/report_model.dart';

abstract class ReportRemoteDataSource {
  Future<List<ReportModel>> getReports();
  Future<ReportModel> getReport(String id);
  Future<void> deleteReport(String id);
  Future<ReportModel> updateReportDetails(String id,
      {String? driverName, String? fertilizersUsed});
}

class ReportRemoteDataSourceImpl implements ReportRemoteDataSource {
  final ApiService api;
  ReportRemoteDataSourceImpl(this.api);

  @override
  Future<List<ReportModel>> getReports() async {
    try {
      final response = await api.getJson('/jobs/api/reports/?page_size=200');
      // Backend now returns a paginated dict: { count, next, previous, results }.
      // Fall back to a plain list for forward/backwards compatibility.
      if (response is Map && response['results'] is List) {
        final results = response['results'] as List;
        return results.map((e) => ReportModel.fromJson(e)).toList();
      }
      if (response is List) {
        return response.map((e) => ReportModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching reports: $e');
      rethrow;
    }
  }

  @override
  Future<ReportModel> getReport(String id) async {
    try {
      final response = await api.getJson('/jobs/api/reports/$id/');
      return ReportModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching report detail: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteReport(String id) async {
    try {
      await api.delete('/jobs/api/reports/$id/');
    } catch (e) {
      debugPrint('Error deleting report: $e');
      rethrow;
    }
  }

  @override
  Future<ReportModel> updateReportDetails(String id,
      {String? driverName, String? fertilizersUsed}) async {
    try {
      final response = await api.patchJson('/jobs/api/reports/$id/', jsonBody: {
        if (driverName != null) 'driver_name': driverName,
        if (fertilizersUsed != null) 'fertilizers_used': fertilizersUsed,
      });
      return ReportModel.fromJson(response);
    } catch (e) {
      debugPrint('Error updating report details: $e');
      rethrow;
    }
  }
}
