import 'package:flutter/foundation.dart';
import 'package:simdaas/core/services/api_service.dart';
import '../models/report_model.dart';

abstract class ReportRemoteDataSource {
  Future<List<ReportModel>> getReports();
  Future<ReportModel> getReport(String id);
}

class ReportRemoteDataSourceImpl implements ReportRemoteDataSource {
  final ApiService api;
  ReportRemoteDataSourceImpl(this.api);

  @override
  Future<List<ReportModel>> getReports() async {
    try {
      final response = await api.getJson('/jobs/api/reports/');
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
      final response = await api.getJson('/jobs/api/sessions/$id/report/');
      return ReportModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching report detail: $e');
      rethrow;
    }
  }
}
