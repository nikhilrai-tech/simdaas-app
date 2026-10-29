// "My farmer sprayed a real plot, but the device wasn't mapped to it (or
// was mapped to the wrong one) at the time, so the report came out with
// 0%/wrong area covered -- even though it's Verified." Lets the device
// owner find that report and assign the correct plot after the fact; the
// backend then recomputes area/coverage against it and marks the report
// "Amended" (jobs.views.ReportPlotCorrectionView, same PIN gate as
// SettingsScreen's heatmap-colors/GPS-calibration sections).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:simdaas/core/utils/session_pin_prompt.dart';
import 'package:simdaas/features/plot_mapping/domain/entities/plot.dart';
import 'package:simdaas/features/plot_mapping/presentation/providers/plot_providers.dart' as plot_provs;
import 'package:simdaas/features/reports/domain/report.dart';
import 'package:simdaas/features/reports/presentation/providers/report_providers.dart';

const _pageSize = 10;

enum _DatePreset { today, thisWeek, thisMonth, custom }

class FixReportPlotScreen extends ConsumerStatefulWidget {
  const FixReportPlotScreen({super.key});

  @override
  ConsumerState<FixReportPlotScreen> createState() => _FixReportPlotScreenState();
}

class _FixReportPlotScreenState extends ConsumerState<FixReportPlotScreen> {
  int _currentPage = 0;
  Report? _selectedReport;
  String? _selectedPlotId;
  bool _saving = false;
  String? _error;

  _DatePreset _datePreset = _DatePreset.today;
  DateTimeRange? _customRange;

  // Truncated to a whole day, NOT DateTime.now() as-is -- see
  // reports_list_screen.dart's identical getter for why: a millisecond-
  // precise "now" would make a fresh ReportsPageParams (and so a fresh
  // backend request) on every rebuild and the list would never settle.
  DateTime? get _dateFrom {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    switch (_datePreset) {
      case _DatePreset.today:
        return startOfToday;
      case _DatePreset.thisWeek:
        return startOfToday.subtract(Duration(days: today.weekday - DateTime.monday));
      case _DatePreset.thisMonth:
        return DateTime(today.year, today.month, 1);
      case _DatePreset.custom:
        return _customRange?.start;
    }
  }

  DateTime? get _dateTo {
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

  // Only live/verified reports are offered for a plot fix. 'prefilled' and
  // 'verifying' reports may still have their totals corrected by the
  // SD-card log-verification pipeline (see JobReport.VERIFICATION_STATUS_
  // CHOICES / jobs/log_verification.py), so fixing the plot on one of those
  // now could be immediately superseded by that automatic correction.
  // 'live' reports never go through that pipeline at all (nothing to
  // verify -- no backfilled data) and are safe to fix right away.
  static const _fixablePlotVerificationStatuses = ['live', 'verified'];

  ReportsPageParams _params(int page) => ReportsPageParams(
        page: page,
        pageSize: _pageSize,
        createdAfter: _dateFrom,
        createdBefore: _dateTo,
        verificationStatuses: _fixablePlotVerificationStatuses,
      );

  Future<void> _submit() async {
    final report = _selectedReport;
    final plotId = _selectedPlotId;
    if (report == null || plotId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await runWithPinRetry(
        context,
        action: (pin) => ref
            .read(reportRepoProvider)
            .correctReportPlot(report.id, plotId, pin: pin),
        isMounted: () => mounted,
        promptMessage: 'Fixing a report\'s plot requires a PIN.',
      );
      // Every cached reports page + this report's own detail cache may now
      // be stale (area/coverage/amended all changed).
      ref.invalidate(reportsListProvider);
      ref.invalidate(reportDetailProvider(report.id));
      if (mounted) {
        showSuccessSnackBar(context,
            'Report #${updated.id} updated — now scored against the plot you picked.');
        setState(() {
          _selectedReport = null;
          _selectedPlotId = null;
        });
      }
    } on PinCancelled {
      // Backed out of the PIN prompt -- no error, just stop.
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not fix the report\'s plot: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.read(authServiceProvider).currentUserId ?? '';
    final plotsAsync = ref.watch(plot_provs.plotsListProvider(userId));
    final reportsAsync = ref.watch(reportsListProvider(_params(_currentPage + 1)));

    return Scaffold(
      appBar: AppBar(title: const Text('Fix Report Plot')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber.shade50,
            padding: const EdgeInsets.all(16),
            child: const Text(
              'Sprayed a plot but forgot to map the device to it first? '
              'Pick the report below, then the real plot — it will be '
              'recomputed and marked Amended.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          _buildDateFilterChip(),
          Expanded(
            child: _buildReportsList(reportsAsync),
          ),
          if (_selectedReport != null)
            _buildPlotPickerPanel(plotsAsync),
        ],
      ),
    );
  }

  Widget _buildDateFilterChip() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: _pickDateFilter,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade700),
                const SizedBox(width: 6),
                Text(_dateFilterLabel, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey.shade700),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportsList(AsyncValue<({List<Report> reports, int totalCount})> reportsAsync) {
    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) {
        // A page number past the last one (backend 404s it) means the list
        // shrank out from under a deep page (e.g. a filter change) -- back
        // off to page 1 instead of showing a raw error for what isn't
        // really a failure.
        if (_currentPage > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _currentPage = 0);
          });
          return const Center(child: CircularProgressIndicator());
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(child: Text('Could not load reports: $e')),
        );
      },
      data: (page) {
        if (page.reports.isEmpty && page.totalCount == 0) {
          return const Center(child: Text('No reports in this range.'));
        }
        final pageCount = (page.totalCount / _pageSize).ceil();
        // The count shrank (a filter change, or a report was deleted)
        // enough that this page no longer exists -- back off to the last
        // real one instead of showing an empty/broken page.
        if (_currentPage >= pageCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _currentPage = pageCount - 1);
          });
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: page.reports.map(_buildReportTile).toList(),
              ),
            ),
            if (pageCount > 1) _buildPaginationBar(_currentPage, pageCount),
          ],
        );
      },
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
            onPressed: page > 0 ? () => setState(() => _currentPage = page - 1) : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Previous'),
          ),
          Text('Page ${page + 1} of $pageCount', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          TextButton.icon(
            onPressed: page < pageCount - 1 ? () => setState(() => _currentPage = page + 1) : null,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTile(Report report) {
    final selected = _selectedReport?.id == report.id;
    final areaLabel = report.completionPercentage.isFinite
        ? '${report.completionPercentage.toStringAsFixed(1)}% covered'
        : 'N/A';
    // A 0%/near-0% covered report is the classic symptom this screen
    // fixes -- flagged so the farmer doesn't have to guess which one.
    final looksWrong = report.completionPercentage < 1.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? Colors.green.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected ? BorderSide(color: Colors.green.shade400, width: 1.5) : BorderSide.none,
      ),
      child: ListTile(
        onTap: () => setState(() {
          _selectedReport = report;
          _selectedPlotId = null;
          _error = null;
        }),
        leading: CircleAvatar(
          backgroundColor: looksWrong ? Colors.amber.shade100 : Colors.grey.shade100,
          child: Icon(
            looksWrong ? Icons.warning_amber_rounded : Icons.description_outlined,
            color: looksWrong ? Colors.amber.shade800 : Colors.grey.shade600,
            size: 20,
          ),
        ),
        title: Text('${report.plot?.name ?? 'Unknown plot'} (#${report.id})',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${DateFormat('dd MMM yyyy, h:mm a').format(report.createdAt.toLocal())} · $areaLabel',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: selected
            ? Icon(Icons.check_circle, color: Colors.green.shade600)
            : const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _buildPlotPickerPanel(AsyncValue<List<PlotEntity>> plotsAsync) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Correct plot for Report #${_selectedReport!.id}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          plotsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load plots: $e'),
            data: (plots) => DropdownButtonFormField<String>(
              initialValue: _selectedPlotId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Actual plot sprayed',
                border: OutlineInputBorder(),
              ),
              items: plots
                  .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedPlotId = v),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _selectedReport = null;
                            _selectedPlotId = null;
                            _error = null;
                          }),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_saving || _selectedPlotId == null) ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
