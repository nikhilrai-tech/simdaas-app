import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import '../../data/datasources/investor_report_remote_data_source.dart';
import '../../data/datasources/report_remote_data_source.dart';
import '../../data/repositories/report_repository_impl.dart';
import '../../domain/report.dart';

final reportRepoProvider = Provider((ref) =>
    ReportRepositoryImpl(ReportRemoteDataSourceImpl(ref.read(apiServiceProvider))));

/// Same ReportRepositoryImpl, pointed at the investor-facing fleet-wide
/// endpoints instead. Backs investorReportsListProvider/
/// investorReportDetailProvider below -- a ProviderScope override of
/// reportRepoProvider was considered instead of a parallel provider family,
/// but doesn't actually work here: ReportsListScreen pushes
/// ReportDetailsScreen via the app's single root Navigator, which mounts
/// the new route as a sibling of wherever the ProviderScope override was
/// applied, not a descendant of it, so the override would never reach it.
final investorReportRepoProvider = Provider((ref) => ReportRepositoryImpl(
    InvestorReportRemoteDataSourceImpl(ref.read(apiServiceProvider))));

class ReportsPageParams {
  final int page;
  final int pageSize;
  final String? plotId;
  final String? controlUnitId;
  final bool sortAscending;
  final DateTime? createdAfter;
  final DateTime? createdBefore;
  final List<String>? verificationStatuses;
  final String? reportId;

  const ReportsPageParams({
    required this.page,
    required this.pageSize,
    this.plotId,
    this.controlUnitId,
    this.sortAscending = false,
    this.createdAfter,
    this.createdBefore,
    this.verificationStatuses,
    this.reportId,
  });

  static bool _statusesEqual(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is ReportsPageParams &&
      other.page == page &&
      other.pageSize == pageSize &&
      other.plotId == plotId &&
      other.controlUnitId == controlUnitId &&
      other.sortAscending == sortAscending &&
      other.createdAfter == createdAfter &&
      other.createdBefore == createdBefore &&
      other.reportId == reportId &&
      _statusesEqual(other.verificationStatuses, verificationStatuses);

  @override
  int get hashCode => Object.hash(
      page,
      pageSize,
      plotId,
      controlUnitId,
      sortAscending,
      createdAfter,
      createdBefore,
      reportId,
      verificationStatuses == null
          ? null
          : Object.hashAll(verificationStatuses!));
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
      createdAfter: params.createdAfter,
      createdBefore: params.createdBefore,
      verificationStatuses: params.verificationStatuses,
      reportId: params.reportId,
    );
  },
);

final reportDetailProvider = FutureProvider.family((ref, String id) async {
  final repo = ref.read(reportRepoProvider);
  return repo.getReport(id);
});

/// Investor-viewer equivalents of reportsListProvider/reportDetailProvider
/// above -- same params/shape, just backed by investorReportRepoProvider
/// (fleet-wide, every user's reports) instead of the farmer-scoped one.
/// InvestorReportsScreen/ReportDetailsScreen(readOnly: true) watch these
/// instead of the normal pair.
final investorReportsListProvider = FutureProvider.family<
    ({List<Report> reports, int totalCount}), ReportsPageParams>(
  (ref, params) async {
    final repo = ref.read(investorReportRepoProvider);
    return repo.getReportsPage(
      page: params.page,
      pageSize: params.pageSize,
      plotId: params.plotId,
      controlUnitId: params.controlUnitId,
      sortAscending: params.sortAscending,
      createdAfter: params.createdAfter,
      createdBefore: params.createdBefore,
      verificationStatuses: params.verificationStatuses,
      reportId: params.reportId,
    );
  },
);

final investorReportDetailProvider = FutureProvider.family((ref, String id) async {
  final repo = ref.read(investorReportRepoProvider);
  return repo.getReport(id);
});

/// The signed-in user's own cumulative average chemical-saved % across all
/// their reports to date (null if they have none yet) -- backs the
/// dashboard's headline stat. A dedicated backend aggregate
/// (GET /jobs/api/reports/stats/), not computed by paging through every
/// report client-side.
final reportStatsProvider = FutureProvider<double?>((ref) async {
  final api = ref.read(apiServiceProvider);
  final response = await api.getJson('/jobs/api/reports/stats/');
  if (response is Map) {
    final v = response['avg_chemical_saved_percentage'];
    if (v is num) return v.toDouble();
    if (v != null) return double.tryParse(v.toString());
  }
  return null;
});
