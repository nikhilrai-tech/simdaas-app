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
  }) async {
    final result = await remoteDataSource.getReportsPage(
      page: page,
      pageSize: pageSize,
      plotId: plotId,
      controlUnitId: controlUnitId,
      sortAscending: sortAscending,
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
}
