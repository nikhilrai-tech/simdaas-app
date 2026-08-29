import '../report.dart';

abstract class ReportRepository {
  Future<List<Report>> getReports();
  Future<Report> getReport(String id);
  Future<void> deleteReport(String id);
  Future<Report> updateReportDetails(String id,
      {String? driverName, String? fertilizersUsed});
}
