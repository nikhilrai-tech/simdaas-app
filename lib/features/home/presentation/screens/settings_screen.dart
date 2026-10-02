import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/services/battery_optimization_service.dart';
import 'package:simdaas/core/services/gps_calibration_service.dart';
import 'package:simdaas/core/services/heatmap_preferences_service.dart';
import 'package:simdaas/core/theme/app_theme.dart';
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

  final _gpsNorthCtrl = TextEditingController();
  final _gpsEastCtrl = TextEditingController();
  // Same reseed-on-change pattern as _syncedThresholds above.
  GpsCalibration? _syncedGpsCalibration;
  bool _savingGpsCalibration = false;
  String? _gpsCalibrationError;

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
    _gpsNorthCtrl.dispose();
    _gpsEastCtrl.dispose();
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

  String _heatmapErrorMessage(Object err) =>
      _apiErrorMessage(err, fallbackPrefix: 'Could not save heatmap colors');

  String _apiErrorMessage(Object err, {required String fallbackPrefix}) {
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
    return '$fallbackPrefix: $err';
  }

  void _syncGpsCalibrationControllers(GpsCalibration c) {
    _syncedGpsCalibration = c;
    _gpsNorthCtrl.text = _fmt(c.offsetNorthM);
    _gpsEastCtrl.text = _fmt(c.offsetEastM);
  }

  Future<void> _saveGpsCalibration() async {
    final north = double.tryParse(_gpsNorthCtrl.text.trim());
    final east = double.tryParse(_gpsEastCtrl.text.trim());

    setState(() => _gpsCalibrationError = null);

    if (north == null || east == null || north.abs() > 1000 || east.abs() > 1000) {
      setState(() => _gpsCalibrationError =
          'Enter two numbers (positive or negative), each within ±1000 metres.');
      return;
    }

    setState(() => _savingGpsCalibration = true);
    try {
      await runWithPinRetry(
        context,
        action: (pin) => ref.read(gpsCalibrationProvider.notifier).update(
              GpsCalibration(offsetNorthM: north, offsetEastM: east),
              pin: pin,
            ),
        isMounted: () => mounted,
        promptMessage: 'Changing GPS calibration requires a PIN.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS calibration updated.')),
        );
      }
    } on PinCancelled {
      // User backed out of the PIN prompt -- no error, just stop.
    } catch (err) {
      if (mounted) {
        setState(() => _gpsCalibrationError =
            _apiErrorMessage(err, fallbackPrefix: 'Could not save GPS calibration'));
      }
    } finally {
      if (mounted) setState(() => _savingGpsCalibration = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final heatmapPrefs = ref.watch(heatmapThresholdsProvider);
    if (_syncedThresholds != heatmapPrefs) _syncHeatmapControllers(heatmapPrefs);
    final gpsCalibration = ref.watch(gpsCalibrationProvider);
    if (_syncedGpsCalibration != gpsCalibration) {
      _syncGpsCalibrationControllers(gpsCalibration);
    }
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionHeader(icon: Icons.battery_charging_full_outlined, title: 'Background activity'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              title: const Text('Run in background'),
              subtitle: Text(
                _batteryOptExempt == null
                    ? 'Checking…'
                    : _batteryOptExempt!
                        ? 'Allowed — live monitoring keeps running when the app is backgrounded'
                        : 'Not allowed — Android may pause live monitoring and cooldown timers to save battery',
                style: textTheme.bodySmall,
              ),
              trailing: _batteryOptExempt == false
                  ? TextButton(
                      onPressed: () async {
                        await BatteryOptimizationService.request();
                        await _refreshBatteryOptStatus();
                      },
                      child: const Text('Allow'),
                    )
                  : _batteryOptExempt == true
                      ? Icon(Icons.check_circle, color: AppTheme.primaryGreen)
                      : null,
            ),
          ),
          const SizedBox(height: 8),
          _SectionHeader(
            icon: Icons.palette_outlined,
            title: 'Heatmap colors',
            description: 'Choose where each color band starts on the Speed and '
                'Spray heatmaps shown on the monitoring and report screens. '
                'The colors stay the same — only the values do.',
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Speed (km/h)', style: textTheme.titleMedium),
                  const SizedBox(height: 10),
                  _BandRow(
                    color: Colors.amber.shade600,
                    label: 'Yellow — up to',
                    controller: _speedYellowCtrl,
                    suffix: 'km/h',
                  ),
                  const Divider(height: 20),
                  _BandRow(
                    color: AppTheme.primaryGreen,
                    label: 'Green — up to',
                    controller: _speedGreenCtrl,
                    suffix: 'km/h',
                  ),
                  const Divider(height: 20),
                  const _BandRow(color: Colors.red, label: 'Red — above that'),
                  if (_heatmapSpeedError != null)
                    _InlineError(_heatmapSpeedError!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Spray (L/min)', style: textTheme.titleMedium),
                  const SizedBox(height: 10),
                  const _BandRow(
                    color: Colors.white,
                    label: 'White — exactly 0 (fixed)',
                    bordered: true,
                  ),
                  const Divider(height: 20),
                  _BandRow(
                    color: Colors.blue.shade400,
                    label: 'Blue — up to',
                    controller: _sprayBlueCtrl,
                    suffix: 'L/min',
                  ),
                  const Divider(height: 20),
                  _BandRow(
                    color: Colors.red.shade400,
                    label: 'Red — up to',
                    controller: _sprayRedCtrl,
                    suffix: 'L/min',
                  ),
                  const Divider(height: 20),
                  const _BandRow(color: Colors.black, label: 'Black — above that'),
                  if (_heatmapSprayError != null)
                    _InlineError(_heatmapSprayError!),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savingHeatmapPrefs ? null : _saveHeatmapPreferences,
                icon: _savingHeatmapPrefs
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save heatmap colors'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _SectionHeader(
            icon: Icons.gps_fixed,
            title: 'GPS calibration',
            description: 'If your device\'s GPS consistently reads a few '
                'metres off from its real position, correct it here — this '
                'only affects your own devices, on both the monitoring and '
                'report screens.',
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Offset', style: textTheme.titleMedium),
                  const SizedBox(height: 10),
                  _OffsetRow(
                    icon: Icons.north,
                    label: 'North',
                    helper: 'negative = south',
                    controller: _gpsNorthCtrl,
                  ),
                  const Divider(height: 20),
                  _OffsetRow(
                    icon: Icons.east,
                    label: 'East',
                    helper: 'negative = west',
                    controller: _gpsEastCtrl,
                  ),
                  if (_gpsCalibrationError != null)
                    _InlineError(_gpsCalibrationError!),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savingGpsCalibration ? null : _saveGpsCalibration,
                icon: _savingGpsCalibration
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save GPS calibration'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section's leading icon + title, with an optional helper description
/// underneath -- the same shape used ahead of every settings card on this
/// screen, so each section reads consistently at a glance.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;

  const _SectionHeader({required this.icon, required this.title, this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              Text(title, style: theme.textTheme.titleMedium),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// One color band: a swatch, its label, and (when editable) the boundary
/// value field, all on a single row so a whole card reads as a tidy list
/// rather than stacked label-then-field pairs.
class _BandRow extends StatelessWidget {
  final Color color;
  final String label;
  final bool bordered;
  final TextEditingController? controller;
  final String? suffix;

  const _BandRow({
    required this.color,
    required this.label,
    this.bordered = false,
    this.controller,
    this.suffix,
  });

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
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        if (controller != null)
          SizedBox(
            width: 92,
            child: _NumberField(controller: controller!, suffix: suffix),
          ),
      ],
    );
  }
}

/// A GPS offset row: direction icon + label + helper text on the left,
/// value field on the right.
class _OffsetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String helper;
  final TextEditingController controller;

  const _OffsetRow({
    required this.icon,
    required this.label,
    required this.helper,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              Text(helper, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        SizedBox(width: 92, child: _NumberField(controller: controller, suffix: 'm')),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String? suffix;

  const _NumberField({required this.controller, this.suffix});

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
    );
    return TextField(
      controller: controller,
      textAlign: TextAlign.end,
      style: Theme.of(context).textTheme.bodyMedium,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        isDense: true,
        suffixText: suffix,
        suffixStyle: Theme.of(context).textTheme.bodySmall,
        border: border,
        enabledBorder: border,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}
