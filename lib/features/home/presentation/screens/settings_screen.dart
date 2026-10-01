import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/services/battery_optimization_service.dart';
import 'package:simdaas/core/services/heatmap_preferences_service.dart';
import 'package:simdaas/core/utils/session_pin_prompt.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool? _batteryOptExempt;

  final _speedYellowCtrl = TextEditingController();
  final _speedGreenCtrl = TextEditingController();
  final _sprayBlueCtrl = TextEditingController();
  final _sprayRedCtrl = TextEditingController();
  // Last HeatmapThresholds the text fields were seeded from -- reseeded
  // whenever the provider's value changes (initial load finishing, or this
  // screen's own save completing) so the fields never show stale defaults
  // while the real per-user values are still loading.
  HeatmapThresholds? _syncedThresholds;
  bool _savingHeatmapPrefs = false;
  String? _heatmapSpeedError;
  String? _heatmapSprayError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBatteryOptStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speedYellowCtrl.dispose();
    _speedGreenCtrl.dispose();
    _sprayBlueCtrl.dispose();
    _sprayRedCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh when returning from the system settings screen.
    if (state == AppLifecycleState.resumed) _refreshBatteryOptStatus();
  }

  Future<void> _refreshBatteryOptStatus() async {
    final exempt = await BatteryOptimizationService.isIgnoringOptimizations();
    if (mounted) setState(() => _batteryOptExempt = exempt);
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _syncHeatmapControllers(HeatmapThresholds t) {
    _syncedThresholds = t;
    _speedYellowCtrl.text = _fmt(t.speedYellowMax);
    _speedGreenCtrl.text = _fmt(t.speedGreenMax);
    _sprayBlueCtrl.text = _fmt(t.sprayBlueMax);
    _sprayRedCtrl.text = _fmt(t.sprayRedMax);
  }

  Future<void> _saveHeatmapPreferences() async {
    final yellow = double.tryParse(_speedYellowCtrl.text.trim());
    final green = double.tryParse(_speedGreenCtrl.text.trim());
    final blue = double.tryParse(_sprayBlueCtrl.text.trim());
    final red = double.tryParse(_sprayRedCtrl.text.trim());

    setState(() {
      _heatmapSpeedError = null;
      _heatmapSprayError = null;
    });

    var hasError = false;
    if (yellow == null || yellow <= 0 || green == null || green <= 0 || yellow >= green) {
      setState(() => _heatmapSpeedError =
          'Enter two numbers greater than 0, with yellow less than green.');
      hasError = true;
    }
    if (blue == null || blue <= 0 || red == null || red <= 0 || blue >= red) {
      setState(() => _heatmapSprayError =
          'Enter two numbers greater than 0, with the blue value less than the red value.');
      hasError = true;
    }
    if (hasError) return;

    setState(() => _savingHeatmapPrefs = true);
    try {
      await runWithPinRetry(
        context,
        action: (pin) => ref.read(heatmapThresholdsProvider.notifier).update(
              HeatmapThresholds(
                speedYellowMax: yellow!,
                speedGreenMax: green!,
                sprayBlueMax: blue!,
                sprayRedMax: red!,
              ),
              pin: pin,
            ),
        isMounted: () => mounted,
        promptMessage: 'Changing heatmap colors requires a PIN.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Heatmap colors updated.')),
        );
      }
    } on PinCancelled {
      // User backed out of the PIN prompt -- no error, just stop.
    } catch (err) {
      if (mounted) setState(() => _heatmapSpeedError = _heatmapErrorMessage(err));
    } finally {
      if (mounted) setState(() => _savingHeatmapPrefs = false);
    }
  }

  String _heatmapErrorMessage(Object err) {
    if (err is ApiException && err.body != null) {
      try {
        final body = json.decode(err.body!);
        if (body is Map) {
          for (final v in body.values) {
            if (v is List && v.isNotEmpty) return v.first.toString();
          }
          if (body['error'] != null) return body['error'].toString();
        }
      } catch (_) {}
    }
    return 'Could not save heatmap colors: $err';
  }

  @override
  Widget build(BuildContext context) {
    final heatmapPrefs = ref.watch(heatmapThresholdsProvider);
    if (_syncedThresholds != heatmapPrefs) _syncHeatmapControllers(heatmapPrefs);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Background activity',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ListTile(
            leading: const Icon(Icons.battery_charging_full_outlined),
            title: const Text('Run in background'),
            subtitle: Text(
              _batteryOptExempt == null
                  ? 'Checking…'
                  : _batteryOptExempt!
                      ? 'Allowed — live monitoring keeps running when the app is backgrounded'
                      : 'Not allowed — Android may pause live monitoring and cooldown timers to save battery',
            ),
            trailing: _batteryOptExempt == false
                ? FilledButton(
                    onPressed: () async {
                      await BatteryOptimizationService.request();
                      await _refreshBatteryOptStatus();
                    },
                    child: const Text('Allow'),
                  )
                : _batteryOptExempt == true
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
          ),
          const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Heatmap colors',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Choose where each color band starts on the Speed and Spray '
              'heatmaps shown on the monitoring and report screens. The '
              'colors stay the same — only the values do.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Speed (km/h)', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    _ColorBandRow(color: Colors.yellow.shade700, label: 'Yellow: 0 up to'),
                    _NumberField(controller: _speedYellowCtrl, suffix: 'km/h'),
                    const SizedBox(height: 8),
                    _ColorBandRow(color: Colors.green, label: 'Green: up to'),
                    _NumberField(controller: _speedGreenCtrl, suffix: 'km/h'),
                    const SizedBox(height: 4),
                    const _ColorBandRow(color: Colors.red, label: 'Red: above that'),
                    if (_heatmapSpeedError != null) ...[
                      const SizedBox(height: 8),
                      Text(_heatmapSpeedError!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Spray (L/min)', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    const _ColorBandRow(color: Colors.white, label: 'White: exactly 0 (fixed)', bordered: true),
                    const SizedBox(height: 8),
                    _ColorBandRow(color: Colors.blue.shade400, label: 'Blue: 0 up to'),
                    _NumberField(controller: _sprayBlueCtrl, suffix: 'L/min'),
                    const SizedBox(height: 8),
                    _ColorBandRow(color: Colors.red.shade400, label: 'Red: up to'),
                    _NumberField(controller: _sprayRedCtrl, suffix: 'L/min'),
                    const SizedBox(height: 4),
                    const _ColorBandRow(color: Colors.black, label: 'Black: above that'),
                    if (_heatmapSprayError != null) ...[
                      const SizedBox(height: 8),
                      Text(_heatmapSprayError!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _savingHeatmapPrefs ? null : _saveHeatmapPreferences,
                child: _savingHeatmapPrefs
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save heatmap colors'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorBandRow extends StatelessWidget {
  final Color color;
  final String label;
  final bool bordered;

  const _ColorBandRow({required this.color, required this.label, this.bordered = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: bordered ? Border.all(color: Colors.grey.shade400) : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String suffix;

  const _NumberField({required this.controller, required this.suffix});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 22, top: 4),
      child: SizedBox(
        width: 140,
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            isDense: true,
            suffixText: suffix,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ),
    );
  }
}
