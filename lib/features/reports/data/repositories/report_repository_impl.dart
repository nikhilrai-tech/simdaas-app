import 'dart:typed_data';

import '../../domain/report.dart';
import '../../domain/repositories/report_repository.dart';
import '../datasources/report_remote_data_source.dart';

class ReportRepositoryImpl implements ReportRepository {
  final ReportRemoteDataSource remoteDataSource;

  ReportRepositoryImpl(this.remoteDataSource);

  @override
  Future<({List<Report> reports, int totalCount})> getReportsPage({
    required int page,
    required int pageSize,
    String? plotId,
    String? controlUnitId,
    bool sortAscending = false,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async {
    final result = await remoteDataSource.getReportsPage(
      page: page,
      pageSize: pageSize,
      plotId: plotId,
      controlUnitId: controlUnitId,
      sortAscending: sortAscending,
      createdAfter: createdAfter,
      createdBefore: createdBefore,
    );
    return (reports: result.reports, totalCount: result.totalCount);
  }

  @override
  Future<Report> getReport(String id) async {
    return await remoteDataSource.getReport(id);
  }

  @override
  Future<void> deleteReport(String id) async {
    await remoteDataSource.deleteReport(id);
  }

  @override
  Future<Report> updateReportDetails(String id,
      {String? driverName,
      String? fertilizersUsed,
      String? agrochemicalUsed}) async {
    return await remoteDataSource.updateReportDetails(id,
        driverName: driverName,
        fertilizersUsed: fertilizersUsed,
        agrochemicalUsed: agrochemicalUsed);
  }

  @override
  Future<Report> correctReportPlot(String reportId, String plotId, {String? pin}) async {
    return await remoteDataSource.correctReportPlot(reportId, plotId, pin: pin);
  }

  @override
  Future<void> uploadHeatmapSnapshot(String reportId,
      {String? gps, String? spray, String? speed, String? leftRight}) async {
    await remoteDataSource.uploadHeatmapSnapshot(reportId,
        gps: gps, spray: spray, speed: speed, leftRight: leftRight);
  }

  @override
  Future<void> emailReport(String reportId, Uint8List pdfBytes) async {
    await remoteDataSource.emailReport(reportId, pdfBytes);
  }
}
