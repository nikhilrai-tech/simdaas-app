import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import '../../data/datasources/plot_remote_data_source.dart';
import '../../data/repositories/plot_repository_impl.dart';
import '../../domain/entities/plot.dart';

final plotRepoProvider = Provider((ref) =>
    PlotRepositoryImpl(PlotRemoteDataSourceImpl(ref.read(apiServiceProvider))));

final plotsListProvider = FutureProvider.family((ref, String userId) async {
  final repo = ref.read(plotRepoProvider);
  return repo.getPlots(userId);
});

final plotByIdProvider = FutureProvider.family<PlotEntity?, String>((ref, String plotId) async {
  final auth = ref.watch(authServiceProvider);
  final userId = auth.currentUserId ?? '';
  if (userId.isEmpty) return null;
  final plots = await ref.watch(plotsListProvider(userId).future);
  try {
    return plots.firstWhere((p) => p.id == plotId);
  } catch (_) {
    return null;
  }
});
