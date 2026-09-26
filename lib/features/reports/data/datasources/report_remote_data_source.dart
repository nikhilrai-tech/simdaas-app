import 'package:flutter/foundation.dart';
import 'package:simdaas/core/services/api_service.dart';
import '../models/report_model.dart';

abstract class ReportRemoteDataSource {
  Future<List<ReportModel>> getReports();
  Future<ReportModel> getReport(String id);
  Future<void> deleteReport(String id);
  Future<ReportModel> updateReportDetails(String id,
      {String? driverName, String? fertilizersUsed, String? agrochemicalUsed});
}

class ReportRemoteDataSourceImpl implements ReportRemoteDataSource {
  final ApiService api;
  ReportRemoteDataSourceImpl(this.api);

  @override
  Future<List<ReportModel>> getReports() async {
    try {
      final reports = <ReportModel>[];
      // Walk the backend's own pagination (page_size=50, matching its
      // default) instead of asking for everything in one page_size=200
      // request -- with enough reports on an account that single request
      // gets slow enough to hit "Failed to fetch" outright. Smaller pages
      // keep every individual request fast and reliable.
      String? path = '/jobs/api/reports/?page_size=50';
      while (path != null) {
        final response = await api.getJson(path);
        // Backend now returns a paginated dict: { count, next, previous,
        // results }. Fall back to a plain list for forward/backwards
        // compatibility.
        if (response is Map && response['results'] is List) {
          final results = response['results'] as List;
          reports.addAll(results.map((e) => ReportModel.fromJson(e)));
          final next = response['next'];
          path = next is String ? _relativePath(next) : null;
        } else if (response is List) {
          reports.addAll(response.map((e) => ReportModel.fromJson(e)));
          path = null;
        } else {
          path = null;
        }
      }
      return reports;
    } catch (e) {
      debugPrint('Error fetching reports: $e');
      rethrow;
    }
  }

  /// The backend's `next` link is an absolute URL (DRF's
  /// build_absolute_uri()). ApiService.getJson always prepends its own
  /// baseUrl, so only the path+query is passed back in for the next call.
  String _relativePath(String nextUrl) {
    final uri = Uri.parse(nextUrl);
    return uri.query.isEmpty ? uri.path : '${uri.path}?${uri.query}';
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
      {String? driverName,
      String? fertilizersUsed,
      String? agrochemicalUsed}) async {
    try {
      final response = await api.patchJson('/jobs/api/reports/$id/', jsonBody: {
        if (driverName != null) 'driver_name': driverName,
        if (fertilizersUsed != null) 'fertilizers_used': fertilizersUsed,
        if (agrochemicalUsed != null) 'agrochemical_used': agrochemicalUsed,
      });
      return ReportModel.fromJson(response);
    } catch (e) {
      debugPrint('Error updating report details: $e');
      rethrow;
    }
  }
}
