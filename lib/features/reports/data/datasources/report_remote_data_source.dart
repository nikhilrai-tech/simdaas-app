import 'package:flutter/foundation.dart';
import 'package:simdaas/core/services/api_service.dart';
import '../models/report_model.dart';

abstract class ReportRemoteDataSource {
  /// One page straight from the backend's own pagination/filtering --
  /// replaces the old walk-every-page-then-filter-client-side approach,
  /// which fetched an account's entire report history (seen on staging:
  /// 800+ reports, ~18 sequential requests) just to show 10 of them.
  Future<({List<ReportModel> reports, int totalCount})> getReportsPage({
    required int page,
    required int pageSize,
    String? plotId,
    String? controlUnitId,
    bool sortAscending = false,
    DateTime? createdAfter,
    DateTime? createdBefore,
  });
  Future<ReportModel> getReport(String id);
  Future<void> deleteReport(String id);
  Future<ReportModel> updateReportDetails(String id,
      {String? driverName, String? fertilizersUsed, String? agrochemicalUsed});
}

class ReportRemoteDataSourceImpl implements ReportRemoteDataSource {
  final ApiService api;
  ReportRemoteDataSourceImpl(this.api);

  @override
  Future<({List<ReportModel> reports, int totalCount})> getReportsPage({
    required int page,
    required int pageSize,
    String? plotId,
    String? controlUnitId,
    bool sortAscending = false,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'page_size': '$pageSize',
        'ordering': sortAscending ? 'created_at' : '-created_at',
        if (plotId != null) 'plot': plotId,
        if (controlUnitId != null) 'control_unit': controlUnitId,
        if (createdAfter != null)
          'created_after': createdAfter.toUtc().toIso8601String(),
        if (createdBefore != null)
          'created_before': createdBefore.toUtc().toIso8601String(),
      };
      final query = params.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final response = await api.getJson('/jobs/api/reports/?$query');
      if (response is Map && response['results'] is List) {
        final results = (response['results'] as List)
            .map((e) => ReportModel.fromJson(e))
            .toList();
        final count = response['count'];
        return (
          reports: results,
          totalCount: count is int ? count : results.length,
        );
      }
      if (response is List) {
        final results = response.map((e) => ReportModel.fromJson(e)).toList();
        return (reports: results, totalCount: results.length);
      }
      return (reports: <ReportModel>[], totalCount: 0);
    } catch (e) {
      debugPrint('Error fetching reports page: $e');
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
