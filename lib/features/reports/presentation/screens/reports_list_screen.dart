import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:simdaas/core/services/auth_service.dart';
import '../providers/report_providers.dart';
import 'package:simdaas/features/plot_mapping/presentation/providers/plot_providers.dart' as plot_provs;
import 'package:simdaas/features/equipments/presentation/providers/equipment_providers.dart' as eq_provs;
import 'report_details_screen.dart';

class ReportsListScreen extends ConsumerStatefulWidget {
  const ReportsListScreen({super.key});

  @override
  ConsumerState<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends ConsumerState<ReportsListScreen> {
  late final javaTimer = _setupAutoRefresh();

  String? _selectedPlotId;
  String? _selectedControlUnitId;
  bool _sortAscending = false; // Default Newest first

  dynamic _setupAutoRefresh() {
    return Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (mounted) _refreshData();
    });
  }

  Future<void> _refreshData() async {
    ref.invalidate(reportsListProvider);
  }

  @override
  void dispose() {
    if (javaTimer is StreamSubscription) {
      (javaTimer as StreamSubscription).cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(reportsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spray Reports'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_sortAscending ? Icons.sort_by_alpha : Icons.history),
            onPressed: () {
              setState(() {
                _sortAscending = !_sortAscending;
              });
            },
            tooltip: _sortAscending ? 'Oldest first' : 'Newest first',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      backgroundColor: Colors.grey[50], // Light background for contrast
      body: Column(
        children: [
          _buildFilterBar(context, ref),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshData,
        child: reportsAsync.when(
          data: (reports) {
            // Apply filtering
            var filtered = reports;
            if (_selectedPlotId != null) {
              filtered = filtered.where((r) => r.plotId == _selectedPlotId).toList();
            }
            if (_selectedControlUnitId != null) {
              filtered = filtered.where((r) => r.controlUnitId == _selectedControlUnitId).toList();
            }

            // Apply sorting
            final sorted = List.from(filtered);
            sorted.sort((a, b) {
              if (_sortAscending) {
                return a.createdAt.compareTo(b.createdAt);
              } else {
                return b.createdAt.compareTo(a.createdAt);
              }
            });

            if (sorted.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.assignment_outlined,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No reports generated yet.',
                              style: TextStyle(fontSize: 18, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              itemBuilder: (context, i) {
                final r = sorted[i];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ReportDetailsScreen(report: r))),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .primaryColor
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.grass,
                                    color: Theme.of(context).primaryColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Report #${r.id}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat.yMMMd()
                                          .add_jm()
                                          .format(r.createdAt.toLocal()),
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildMiniStat(
                                  Icons.scatter_plot,
                                  '${(r.areaCoveredSqm / 4046.86).toStringAsFixed(2)} ac',
                                  'Area'),
                              _buildMiniStat(
                                  Icons.water_drop,
                                  '${r.sprayUsedLitres.toStringAsFixed(1)} L',
                                  'Applied'),
                              _buildMiniStat(
                                  Icons.pie_chart,
                                  '${r.completionPercentage.toStringAsFixed(0)}%',
                                  'Complete'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          error: (err, stack) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Center(child: Text('Error: $err')),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    ),
   ],
  ),
 );
}

  Widget _buildFilterBar(BuildContext context, WidgetRef ref) {
    final userId = ref.read(authServiceProvider).currentUserId ?? '';
    final plotsAsync = ref.watch(plot_provs.plotsListProvider(userId));
    final controlUnitsAsync = ref.watch(eq_provs.controlUnitsProvider(userId));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: plotsAsync.when(
              data: (plots) => DropdownButtonFormField<String?>(
                value: _selectedPlotId,
                style: const TextStyle(fontSize: 13, color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'Field',
                  labelStyle: TextStyle(fontSize: 12),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Fields', style: TextStyle(fontSize: 13))),
                  ...plots.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, style: const TextStyle(fontSize: 13)))),
                ],
                onChanged: (val) => setState(() => _selectedPlotId = val),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Error loading plots'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: controlUnitsAsync.when(
              data: (cus) => DropdownButtonFormField<String?>(
                value: _selectedControlUnitId,
                style: const TextStyle(fontSize: 13, color: Colors.black),
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  labelStyle: TextStyle(fontSize: 12),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Units', style: TextStyle(fontSize: 13))),
                  ...cus.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 13)))),
                ],
                onChanged: (val) => setState(() => _selectedControlUnitId = val),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Error loading units'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }
}
