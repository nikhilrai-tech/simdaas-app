import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:simdaas/core/services/auth_service.dart';
import '../providers/report_providers.dart';
import 'package:simdaas/features/plot_mapping/presentation/providers/plot_providers.dart' as plot_provs;
import 'package:simdaas/features/equipments/presentation/providers/equipment_providers.dart' as eq_provs;
import 'package:simdaas/core/utils/mac_utils.dart';
import 'report_details_screen.dart';

class ReportsListScreen extends ConsumerStatefulWidget {
  const ReportsListScreen({super.key});

  @override
  ConsumerState<ReportsListScreen> createState() => _ReportsListScreenState();
}

enum _DatePreset { today, thisWeek, thisMonth, custom }

class _ReportsListScreenState extends ConsumerState<ReportsListScreen> {
  late final StreamSubscription<void> _autoRefreshSub;

  @override
  void initState() {
    super.initState();
    // `late final javaTimer = _setupAutoRefresh();` at the declaration
    // looked equivalent but never actually ran: a `late` field only
    // evaluates its initializer on first READ, and the only other place it
    // was read was dispose() -- so this auto-refresh timer never started
    // while the screen was open. Assigning it here in initState() is what
    // actually starts it.
    _autoRefreshSub = _setupAutoRefresh();
  }

  String? _selectedPlotId;
  String? _selectedControlUnitId;
  bool _sortAscending = false; // Default Newest first

  _DatePreset _datePreset = _DatePreset.today;
  DateTimeRange? _customRange;

  static const _pageSize = 10;
  int _currentPage = 0;

  DateTime? get _dateFrom {
    // Truncated to a whole day, NOT DateTime.now() as-is -- this getter runs
    // on every build(), and a millisecond-precise "now" made a fresh,
    // never-equal ReportsPageParams (and so a fresh backend request) on
    // every single rebuild, including the one caused by the previous
    // request finishing -- the list never actually settled into a loaded
    // state (see the "Past 2 months" fix this replaced). Every branch below
    // must stay stable within the same day for the same reason.
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    switch (_datePreset) {
      case _DatePreset.today:
        return startOfToday;
      case _DatePreset.thisWeek:
        // Monday as the start of the week.
        return startOfToday.subtract(Duration(days: today.weekday - DateTime.monday));
      case _DatePreset.thisMonth:
        return DateTime(today.year, today.month, 1);
      case _DatePreset.custom:
        return _customRange?.start;
    }
  }

  DateTime? get _dateTo {
    // "Today" / "This week" / "This month" all mean "...through now" -- no
    // upper bound needed. Only a custom range has a real end date, and it
    // should include that whole day.
    if (_datePreset == _DatePreset.custom && _customRange != null) {
      final end = _customRange!.end;
      return DateTime(end.year, end.month, end.day, 23, 59, 59);
    }
    return null;
  }

  String get _dateFilterLabel {
    switch (_datePreset) {
      case _DatePreset.today:
        return 'Today';
      case _DatePreset.thisWeek:
        return 'This week';
      case _DatePreset.thisMonth:
        return 'This month';
      case _DatePreset.custom:
        if (_customRange == null) return 'Custom range';
        final f = DateFormat.yMMMd();
        return '${f.format(_customRange!.start)} - ${f.format(_customRange!.end)}';
    }
  }

  Future<void> _pickDateFilter() async {
    final choice = await showModalBottomSheet<_DatePreset>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Today'),
              trailing: _datePreset == _DatePreset.today
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => Navigator.pop(context, _DatePreset.today),
            ),
            ListTile(
              title: const Text('This week'),
              trailing: _datePreset == _DatePreset.thisWeek
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => Navigator.pop(context, _DatePreset.thisWeek),
            ),
            ListTile(
              title: const Text('This month'),
              trailing: _datePreset == _DatePreset.thisMonth
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => Navigator.pop(context, _DatePreset.thisMonth),
            ),
            ListTile(
              title: const Text('Custom range...'),
              trailing: _datePreset == _DatePreset.custom
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => Navigator.pop(context, _DatePreset.custom),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == _DatePreset.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange: _customRange,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _datePreset = _DatePreset.custom;
        _customRange = picked;
        _currentPage = 0;
      });
      return;
    }

    setState(() {
      _datePreset = choice;
      _currentPage = 0;
    });
  }

  StreamSubscription<void> _setupAutoRefresh() {
    return Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (mounted) _refreshData();
    });
  }

  Future<void> _refreshData() async {
    ref.invalidate(reportsListProvider);
  }

  @override
  void dispose() {
    _autoRefreshSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reportsAsync = ref.watch(reportsListProvider(ReportsPageParams(
      page: _currentPage + 1,
      pageSize: _pageSize,
      plotId: _selectedPlotId,
      controlUnitId: _selectedControlUnitId,
      sortAscending: _sortAscending,
      createdAfter: _dateFrom,
      createdBefore: _dateTo,
    )));

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
                _currentPage = 0;
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
          data: (data) {
            final pageItems = data.reports;

            if (pageItems.isEmpty && data.totalCount == 0) {
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
            final pageCount = (data.totalCount / _pageSize).ceil();
            final page = _currentPage;
            // The count shrank (e.g. a report was deleted, or a filter
            // change landed while a deeper page was in view) enough that
            // this page no longer exists -- back off to the last real one
            // instead of showing an empty/broken page.
            if (page >= pageCount) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _currentPage = pageCount - 1);
              });
              return const Center(child: CircularProgressIndicator());
            }

            return Column(
              children: [
                Expanded(child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: pageItems.length,
              itemBuilder: (context, i) {
                final r = pageItems[i];
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
                          if (r.sessionMode != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                // 1. Session mode.
                                _reportBadge(
                                  r.sessionMode == 'device'
                                      ? 'Manual'
                                      : 'Automatic',
                                  r.sessionMode == 'device'
                                      ? Colors.teal
                                      : Colors.indigo,
                                ),
                                if (r.pendingNetworkData)
                                  _reportBadge('Pending network data',
                                      Colors.orange),
                                // 2. Data composition -- independent of
                                // verificationStatus below, which gets
                                // overwritten to verifying/verified/
                                // needs_review once the log-check pipeline
                                // picks the report up and no longer says
                                // whether it started out backfilled.
                                if (r.amended)
                                  _reportBadge('Log Updated', Colors.blue)
                                else if (r.hadBackfillData)
                                  _reportBadge('Backfill', Colors.amber)
                                else
                                  _reportBadge('Normal', Colors.grey),
                                // 2b. Separate from the badge above -- a
                                // report can be amended for an unrelated
                                // backfill reason, or for this one, or
                                // both, independently. Never replaces the
                                // badge above; always additional to it.
                                if (r.plotCorrected)
                                  _reportBadge('Plot Updated', Colors.purple),
                                // 3. Verification pipeline status -- Manual
                                // only, since Automatic reports are never
                                // checked against a device log.
                                if (r.sessionMode == 'device') ...[
                                  if (r.verificationStatus == 'live' ||
                                      r.verificationStatus == 'prefilled')
                                    _reportBadge('Pending', Colors.grey)
                                  else if (r.verificationStatus == 'verifying')
                                    _reportBadge('Verifying', Colors.blueGrey)
                                  else if (r.verificationStatus == 'verified')
                                    _reportBadge('Verified', Colors.green)
                                  else if (r.verificationStatus ==
                                      'needs_review')
                                    _reportBadge('Needs Review', Colors.red),
                                ],
                                if (r.sessionMode == 'device' &&
                                    formatDeviceSessionLabel(
                                            r.controlUnitMac,
                                            r.deviceSessionId) !=
                                        null)
                                  Text(
                                    formatDeviceSessionLabel(
                                        r.controlUnitMac, r.deviceSessionId)!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
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
            )),
                if (pageCount > 1) _buildPaginationBar(page, pageCount),
              ],
            );
          },
          error: (err, stack) {
            // A page number past the last one (backend 404s it) means the
            // list shrank out from under a deep page -- back off to page 1
            // instead of showing a raw error for what isn't really a
            // failure.
            if (_currentPage > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _currentPage = 0);
              });
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Center(child: Text('Error: $err')),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    ),
   ],
  ),
 );
}

  Widget _buildPaginationBar(int page, int pageCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: page > 0
                ? () => setState(() => _currentPage = page - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Previous'),
          ),
          Text('Page ${page + 1} of $pageCount',
              style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          TextButton.icon(
            onPressed: page < pageCount - 1
                ? () => setState(() => _currentPage = page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Next'),
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
      child: Column(
        children: [
          Row(
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
                onChanged: (val) => setState(() {
                  _selectedPlotId = val;
                  _currentPage = 0;
                }),
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
                onChanged: (val) => setState(() {
                  _selectedControlUnitId = val;
                  _currentPage = 0;
                }),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const Text('Error loading units'),
            ),
          ),
        ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _pickDateFilter,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 14, color: Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Text(_dateFilterLabel,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade800)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down,
                        size: 18, color: Colors.grey.shade700),
                  ],
                ),
              ),
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

  Widget _reportBadge(String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color.shade800,
        ),
      ),
    );
  }
}
