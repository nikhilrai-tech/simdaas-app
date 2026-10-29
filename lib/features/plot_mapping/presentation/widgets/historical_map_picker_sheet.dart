import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/historical_map_service.dart';

/// What showHistoricalMapPicker's caller should do after the sheet closes.
/// Showing a provider/date is no longer part of this -- that happens live,
/// via [onPreview], while the sheet is still open (see its own doc comment).
sealed class HistoricalMapPickerResult {
  const HistoricalMapPickerResult();
}

/// Turn the historical overlay back off -- go back to the current map.
class HistoricalMapClear extends HistoricalMapPickerResult {
  const HistoricalMapClear();
}

/// Bottom sheet: pick a historical-imagery provider (free Copernicus /
/// paid Google Earth, see historical_map_service.dart) and browse past
/// dates with left/right arrows. Every provider/date change calls
/// [onPreview] immediately (sheet stays open) so the map underneath updates
/// live as the farmer browses, instead of requiring an explicit "show"
/// button press per date. Returns null if the sheet was simply dismissed
/// (whatever onPreview last applied stays active), or a [HistoricalMapClear]
/// if "Back to current map" was tapped. Does not touch the map itself --
/// the caller (map_screen.dart / row_line_screen.dart) owns that, both via
/// onPreview and when handling a returned HistoricalMapClear.
Future<HistoricalMapPickerResult?> showHistoricalMapPicker(
  BuildContext context,
  WidgetRef ref, {
  required Future<void> Function(String providerId, DateTime date) onPreview,
  bool isActive = false,
  String? initialProviderId,
  DateTime? initialDate,
}) {
  return showModalBottomSheet<HistoricalMapPickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => _HistoricalMapPickerContent(
      ref: ref,
      isActive: isActive,
      initialProviderId: initialProviderId,
      initialDate: initialDate,
      onPreview: onPreview,
    ),
  );
}

class _HistoricalMapPickerContent extends StatefulWidget {
  final WidgetRef ref;
  final bool isActive;
  final String? initialProviderId;
  final DateTime? initialDate;
  final Future<void> Function(String providerId, DateTime date) onPreview;

  const _HistoricalMapPickerContent({
    required this.ref,
    required this.isActive,
    required this.initialProviderId,
    required this.initialDate,
    required this.onPreview,
  });

  @override
  State<_HistoricalMapPickerContent> createState() => _HistoricalMapPickerContentState();
}

class _HistoricalMapPickerContentState extends State<_HistoricalMapPickerContent> {
  List<HistoricalMapProviderInfo>? _providers;
  String? _error;
  String? _selectedProviderId;
  late DateTime _selectedDate;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now().subtract(const Duration(days: 30));
    _selectedProviderId = widget.initialProviderId;
    _load();
  }

  Future<void> _load() async {
    try {
      final providers = await widget.ref.read(historicalMapServiceProvider).getProviders();
      if (!mounted) return;
      final hadProvider = _selectedProviderId != null;
      setState(() {
        _providers = providers;
        _selectedProviderId ??= providers.firstWhere(
          (p) => p.configured,
          orElse: () => providers.first,
        ).id;
      });
      // Auto-preview as soon as a provider is first resolved (fresh open,
      // nothing picked yet) -- the whole point of the live-browsing flow is
      // that the farmer never has to tap a separate "show" button, the
      // default date just appears. A re-open with an existing selection
      // (hadProvider) already has that state showing on the map -- no need
      // to refetch the exact same tile again.
      if (!hadProvider) await _preview();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load historical map providers — $e');
    }
  }

  // Sentinel-2 (the source for both providers here) launched in 2015 --
  // nothing older than that exists to show.
  static final DateTime _earliestDate = DateTime(2015, 6, 23);

  // Matches the backend's own +/-10 day search window (historical_map.py's
  // _date_window) -- each step lands in a genuinely different window
  // instead of just re-finding the same nearest image again.
  static const int _stepDays = 10;

  bool get _canStepBack => _selectedDate.isAfter(_earliestDate);
  bool get _canStepForward => _selectedDate.isBefore(DateTime.now());

  Future<void> _preview() async {
    final providerId = _selectedProviderId;
    if (providerId == null) return;
    setState(() => _previewing = true);
    try {
      await widget.onPreview(providerId, _selectedDate);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  void _selectProvider(String providerId) {
    setState(() => _selectedProviderId = providerId);
    _preview();
  }

  void _stepDate(int direction) {
    final stepped = _selectedDate.add(Duration(days: _stepDays * direction));
    final now = DateTime.now();
    setState(() {
      if (stepped.isAfter(now)) {
        _selectedDate = now;
      } else if (stepped.isBefore(_earliestDate)) {
        _selectedDate = _earliestDate;
      } else {
        _selectedDate = stepped;
      }
    });
    _preview();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Historical map', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Browse with the arrows below — the map updates as you go.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else if (_providers == null)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else ...[
            for (final p in _providers!)
              RadioListTile<String>(
                value: p.id,
                groupValue: _selectedProviderId,
                onChanged: p.configured ? (v) => _selectProvider(v!) : null,
                title: Text(p.label),
                subtitle: p.configured
                    ? Text(p.tier == 'free' ? 'Free' : 'Paid')
                    : const Text('Not set up yet', style: TextStyle(color: Colors.orange)),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Earlier',
                  onPressed: (_canStepBack && !_previewing) ? () => _stepDate(-1) : null,
                ),
                Column(
                  children: [
                    Text('Date', style: Theme.of(context).textTheme.bodySmall),
                    SizedBox(
                      height: 24,
                      child: _previewing
                          ? const Center(
                              child: SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : Text(
                              '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Later',
                  onPressed: (_canStepForward && !_previewing) ? () => _stepDate(1) : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.isActive)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(const HistoricalMapClear()),
                      child: const Text('Back to current map'),
                    ),
                  ),
                if (widget.isActive) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
