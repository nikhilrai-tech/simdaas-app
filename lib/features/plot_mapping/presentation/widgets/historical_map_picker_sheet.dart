import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/historical_map_service.dart';

/// What showHistoricalMapPicker's caller should do after the sheet closes.
sealed class HistoricalMapPickerResult {
  const HistoricalMapPickerResult();
}

/// Show historical imagery from [providerId] as of [date].
class HistoricalMapShow extends HistoricalMapPickerResult {
  final String providerId;
  final DateTime date;
  const HistoricalMapShow({required this.providerId, required this.date});
}

/// Turn the historical overlay back off -- go back to the current map.
class HistoricalMapClear extends HistoricalMapPickerResult {
  const HistoricalMapClear();
}

/// Bottom sheet: pick a historical-imagery provider (free Copernicus /
/// paid Google Earth, see historical_map_service.dart) and a past date.
/// Returns null if the sheet was dismissed with no change, a
/// [HistoricalMapShow] to activate the overlay, or a [HistoricalMapClear]
/// to turn an already-active one back off. Does not touch the map itself
/// -- the caller (map_screen.dart / row_line_screen.dart) owns that.
Future<HistoricalMapPickerResult?> showHistoricalMapPicker(
  BuildContext context,
  WidgetRef ref, {
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
    ),
  );
}

class _HistoricalMapPickerContent extends StatefulWidget {
  final WidgetRef ref;
  final bool isActive;
  final String? initialProviderId;
  final DateTime? initialDate;

  const _HistoricalMapPickerContent({
    required this.ref,
    required this.isActive,
    required this.initialProviderId,
    required this.initialDate,
  });

  @override
  State<_HistoricalMapPickerContent> createState() => _HistoricalMapPickerContentState();
}

class _HistoricalMapPickerContentState extends State<_HistoricalMapPickerContent> {
  List<HistoricalMapProviderInfo>? _providers;
  String? _error;
  String? _selectedProviderId;
  late DateTime _selectedDate;

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
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load historical map providers — $e');
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      // Sentinel-2 (the source for both providers here) launched in 2015 --
      // nothing older than that exists to show.
      firstDate: DateTime(2015, 6, 23),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
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
            'See what this field looked like on a past date.',
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
                onChanged: p.configured ? (v) => setState(() => _selectedProviderId = v) : null,
                title: Text(p.label),
                subtitle: p.configured
                    ? Text(p.tier == 'free' ? 'Free' : 'Paid')
                    : const Text('Not set up yet', style: TextStyle(color: Colors.orange)),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Date'),
              subtitle: Text(
                  '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
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
                    onPressed: _selectedProviderId == null
                        ? null
                        : () => Navigator.of(context).pop(HistoricalMapShow(
                              providerId: _selectedProviderId!,
                              date: _selectedDate,
                            )),
                    child: const Text('Show historical map'),
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
