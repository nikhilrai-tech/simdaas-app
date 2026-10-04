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

const _pageSize = 20;

class FixReportPlotScreen extends ConsumerStatefulWidget {
  const FixReportPlotScreen({super.key});

  @override
  ConsumerState<FixReportPlotScreen> createState() => _FixReportPlotScreenState();
}

class _FixReportPlotScreenState extends ConsumerState<FixReportPlotScreen> {
  int _loadedPages = 1;
  Report? _selectedReport;
  String? _selectedPlotId;
  bool _saving = false;
  String? _error;

  ReportsPageParams _params(int page) => ReportsPageParams(page: page, pageSize: _pageSize);

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
          Expanded(
            child: _buildReportsList(),
          ),
          if (_selectedReport != null)
            _buildPlotPickerPanel(plotsAsync),
        ],
      ),
    );
  }

  Widget _buildReportsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _loadedPages + 1, // +1 for the "load more" footer slot
      itemBuilder: (context, pageIndex) {
        if (pageIndex == _loadedPages) {
          return _buildLoadMoreFooter();
        }
        final asyncPage = ref.watch(reportsListProvider(_params(pageIndex + 1)));
        return asyncPage.when(
          loading: () => pageIndex == 0
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const SizedBox.shrink(),
          error: (e, _) => pageIndex == 0
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not load reports: $e'),
                )
              : const SizedBox.shrink(),
          data: (page) {
            if (pageIndex == 0 && page.reports.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('No reports yet.')),
              );
            }
            return Column(
              children: page.reports.map(_buildReportTile).toList(),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadMoreFooter() {
    final lastPage = ref.watch(reportsListProvider(_params(_loadedPages)));
    return lastPage.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (page) {
        final loadedSoFar = _loadedPages * _pageSize;
        if (loadedSoFar >= page.totalCount) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: OutlinedButton(
              onPressed: () => setState(() => _loadedPages += 1),
              child: const Text('Load more'),
            ),
          ),
        );
      },
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
        title: Text(report.plot?.name ?? 'Unknown plot', style: const TextStyle(fontWeight: FontWeight.w600)),
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
