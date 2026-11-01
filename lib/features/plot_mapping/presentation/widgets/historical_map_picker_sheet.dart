import 'dart:async';

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
  required Future<DateTime?> Function(String providerId, DateTime date) onPreview,
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
  final Future<DateTime?> Function(String providerId, DateTime date) onPreview;

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
  // The REAL satellite-pass date the last fetched image is actually from
  // -- see HistoricalMapRegionImage's doc comment for why this is often
  // not _selectedDate itself. Null while loading/on error/unknown.
  DateTime? _actualDate;
  bool _previewing = false;
  Timer? _stepDebounce;

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
      setState(() {
        _providers = providers;
        _selectedProviderId ??= providers.firstWhere(
          (p) => p.configured,
          orElse: () => providers.first,
        ).id;
      });
      // No auto-preview here anymore: each date change is a real backend
      // tile fetch (CDSE's Process API alone is ~1-3s per uncached tile),
      // and firing a whole fetch wave the instant the sheet opens -- before
      // the farmer has touched anything -- was making the sheet itself feel
      // slow to open and made the map behind it visibly stutter/blur while
      // tiles streamed in. Now the first real fetch only happens once they
      // pick a provider or step a date, same as every fetch after it.
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load historical map providers — $e');
    }
  }

  // Sentinel-2 (the source for both providers here) launched in 2015 --
  // nothing older than that exists to show.
  static final DateTime _earliestDate = DateTime(2015, 6, 23);

  // A fine nudge, one day at a time -- for jumping further, tap the date
  // itself to open a full calendar (see _pickDate below).
  static const int _stepDays = 1;

  bool get _canStepBack => _selectedDate.isAfter(_earliestDate);
  bool get _canStepForward => _selectedDate.isBefore(DateTime.now());

  Future<void> _preview() async {
    final providerId = _selectedProviderId;
    if (providerId == null) return;
    setState(() {
      _previewing = true;
      _actualDate = null;
    });
    try {
      final actualDate = await widget.onPreview(providerId, _selectedDate);
      if (mounted) setState(() => _actualDate = actualDate);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _earliestDate,
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    _stepDebounce?.cancel();
    setState(() => _selectedDate = picked);
    _preview();
  }

  void _selectProvider(String providerId) {
    setState(() => _selectedProviderId = providerId);
    _preview();
  }

  // Each tap fires a real backend tile fetch -- fine for one tap, but
  // flipping through several dates quickly would queue a full fetch wave
  // per tap behind the last one on the server's limited worker pool,
  // making rapid browsing feel far slower than a single lookup actually
  // is. Debounce so only the date the farmer settles on is fetched; the
  // date label itself still updates on every tap, no delay there.
  static const Duration _stepDebounceDelay = Duration(milliseconds: 400);

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
    _stepDebounce?.cancel();
    _stepDebounce = Timer(_stepDebounceDelay, _preview);
  }

  @override
  void dispose() {
    _stepDebounce?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
            'Tap the date to jump to any day, or use the arrows to nudge by one — '
            'the map updates as you go. Zoom in to your field to see it '
            '(not available zoomed all the way out).',
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
                InkWell(
                  onTap: _previewing ? null : _pickDate,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Date', style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(width: 4),
                            Icon(Icons.calendar_month, size: 14,
                                color: Theme.of(context).textTheme.bodySmall?.color),
                          ],
                        ),
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
                                  _formatDate(_selectedDate),
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Later',
                  onPressed: (_canStepForward && !_previewing) ? () => _stepDate(1) : null,
                ),
              ],
            ),
            if (!_previewing && _actualDate != null && !_isSameDate(_actualDate!, _selectedDate))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Center(
                  child: Text(
                    'Nearest available image: ${_formatDate(_actualDate!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
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
