import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import '../../data/datasources/report_remote_data_source.dart';
import '../../data/repositories/report_repository_impl.dart';

final reportRepoProvider = Provider((ref) =>
    ReportRepositoryImpl(ReportRemoteDataSourceImpl(ref.read(apiServiceProvider))));

final reportsListProvider = FutureProvider((ref) async {
  final repo = ref.read(reportRepoProvider);
  return repo.getReports();
});

final reportDetailProvider = FutureProvider.family((ref, String id) async {
  final repo = ref.read(reportRepoProvider);
  return repo.getReport(id);
});
