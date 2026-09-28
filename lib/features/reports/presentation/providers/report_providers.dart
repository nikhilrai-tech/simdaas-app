import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import '../../data/datasources/report_remote_data_source.dart';
import '../../data/repositories/report_repository_impl.dart';
import '../../domain/report.dart';

final reportRepoProvider = Provider((ref) =>
    ReportRepositoryImpl(ReportRemoteDataSourceImpl(ref.read(apiServiceProvider))));

class ReportsPageParams {
  final int page;
  final int pageSize;
  final String? plotId;
  final String? controlUnitId;
  final bool sortAscending;

  const ReportsPageParams({
    required this.page,
    required this.pageSize,
    this.plotId,
    this.controlUnitId,
    this.sortAscending = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ReportsPageParams &&
      other.page == page &&
      other.pageSize == pageSize &&
      other.plotId == plotId &&
      other.controlUnitId == controlUnitId &&
      other.sortAscending == sortAscending;

  @override
  int get hashCode =>
      Object.hash(page, pageSize, plotId, controlUnitId, sortAscending);
}

/// One page fetched directly from the backend, filtered/sorted server-side
/// -- an account's whole report history is never fetched at once. Invalidate
/// with the bare family (`ref.invalidate(reportsListProvider)`) to refresh
/// every page currently cached, or `reportsListProvider(params)` for just
/// the page in view.
final reportsListProvider = FutureProvider.family<
    ({List<Report> reports, int totalCount}), ReportsPageParams>(
  (ref, params) async {
    final repo = ref.read(reportRepoProvider);
    return repo.getReportsPage(
      page: params.page,
      pageSize: params.pageSize,
      plotId: params.plotId,
      controlUnitId: params.controlUnitId,
      sortAscending: params.sortAscending,
    );
  },
);

final reportDetailProvider = FutureProvider.family((ref, String id) async {
  final repo = ref.read(reportRepoProvider);
  return repo.getReport(id);
});
