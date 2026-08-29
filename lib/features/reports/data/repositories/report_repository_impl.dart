import '../../domain/report.dart';
import '../../domain/repositories/report_repository.dart';
import '../datasources/report_remote_data_source.dart';

class ReportRepositoryImpl implements ReportRepository {
  final ReportRemoteDataSource remoteDataSource;

  ReportRepositoryImpl(this.remoteDataSource);

  @override
  Future<List<Report>> getReports() async {
    final models = await remoteDataSource.getReports();
    return models;
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
      {String? driverName, String? fertilizersUsed}) async {
    return await remoteDataSource.updateReportDetails(id,
        driverName: driverName, fertilizersUsed: fertilizersUsed);
  }
}
