import '../report.dart';

abstract class ReportRepository {
  Future<({List<Report> reports, int totalCount})> getReportsPage({
    required int page,
    required int pageSize,
    String? plotId,
    String? controlUnitId,
    bool sortAscending = false,
  });
  Future<Report> getReport(String id);
  Future<void> deleteReport(String id);
  Future<Report> updateReportDetails(String id,
      {String? driverName, String? fertilizersUsed, String? agrochemicalUsed});
}
