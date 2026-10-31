import 'package:flutter/foundation.dart';
import 'package:simdaas/core/services/api_service.dart';
import '../models/report_model.dart';
import 'report_remote_data_source.dart';

/// Same ReportRemoteDataSource contract as ReportRemoteDataSourceImpl, but
/// backed by the investor-facing fleet-wide endpoints (smart-spray-backend
/// tools/views.py InvestorReportsListView/InvestorReportDetailView) instead
/// of the farmer-facing, request.user-scoped ones -- same response shape
/// (JobReportListSerializer/JobReportSerializer on the backend), so
/// ReportModel.fromJson and every existing Report/ReportModel field is
/// unaffected; only the URL path differs.
///
/// Read-only by design, matching the backend: every write method throws
/// instead of hitting a URL that doesn't exist for this account type. An
/// investor_viewer account's own UI never exposes any edit/delete/email
/// action to begin with (see InvestorReportsScreen/InvestorReportDetails
/// Screen) -- these are a defense-in-depth backstop, not a path anything
/// is expected to actually take.
class InvestorReportRemoteDataSourceImpl implements ReportRemoteDataSource {
  final ApiService api;
  InvestorReportRemoteDataSourceImpl(this.api);

  static const _basePath = '/api/admin/investor-dashboard/reports';

  @override
  Future<({List<ReportModel> reports, int totalCount})> getReportsPage({
    required int page,
    required int pageSize,
    String? plotId,
    String? controlUnitId,
    bool sortAscending = false,
    DateTime? createdAfter,
    DateTime? createdBefore,
    List<String>? verificationStatuses,
    String? reportId,
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
        if (verificationStatuses != null && verificationStatuses.isNotEmpty)
          'verification_status': verificationStatuses.join(','),
        if (reportId != null && reportId.isNotEmpty) 'report_id': reportId,
      };
      final query = params.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final response = await api.getJson('$_basePath/?$query');
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
      return (reports: <ReportModel>[], totalCount: 0);
    } catch (e) {
      debugPrint('Error fetching investor reports page: $e');
      rethrow;
    }
  }

  @override
  Future<ReportModel> getReport(String id) async {
    try {
      final response = await api.getJson('$_basePath/$id/');
      return ReportModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching investor report detail: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteReport(String id) {
    throw UnsupportedError('Investor accounts cannot delete reports.');
  }

  @override
  Future<ReportModel> updateReportDetails(String id,
      {String? driverName, String? fertilizersUsed, String? agrochemicalUsed}) {
    throw UnsupportedError('Investor accounts cannot edit reports.');
  }

  @override
  Future<ReportModel> correctReportPlot(String reportId, String plotId, {String? pin}) {
    throw UnsupportedError('Investor accounts cannot correct a report\'s plot.');
  }

  @override
  Future<void> uploadHeatmapSnapshot(String reportId,
      {String? gps, String? spray, String? speed, String? leftRight}) async {
    // No-op, not an error: the farmer-facing screen calls this
    // opportunistically just from viewing a report (see its own doc
    // comment -- "best-effort... never throws"), not as a deliberate
    // investor action. Nothing to upload on this account's behalf.
  }

  @override
  Future<void> emailReport(String reportId, Uint8List pdfBytes) {
    throw UnsupportedError('Investor accounts cannot email reports.');
  }
}
