import '../report.dart';

abstract class ReportRepository {
  Future<({List<Report> reports, int totalCount})> getReportsPage({
    required int page,
    required int pageSize,
    String? plotId,
    String? controlUnitId,
    bool sortAscending = false,
    DateTime? createdAfter,
    DateTime? createdBefore,
  });
  Future<Report> getReport(String id);
  Future<void> deleteReport(String id);
  Future<Report> updateReportDetails(String id,
      {String? driverName, String? fertilizersUsed, String? agrochemicalUsed});

  /// "The farmer sprayed this plot, but the device wasn't mapped to it (or
  /// the wrong plot) at the time" -- assigns the correct plot after the
  /// fact and regenerates the report's area/coverage numbers against it.
  /// PIN-gated the same way session-mode switching and heatmap/GPS-
  /// calibration settings are (jobs.views.ReportPlotCorrectionView).
  Future<Report> correctReportPlot(String reportId, String plotId, {String? pin});

  /// Best-effort: see ReportRemoteDataSource.uploadHeatmapSnapshot.
  Future<void> uploadHeatmapSnapshot(String reportId,
      {String? gps, String? spray, String? speed, String? leftRight});
}
