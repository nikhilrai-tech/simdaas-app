import 'package:flutter/material.dart';
import 'package:simdaas/core/services/battery_optimization_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool? _batteryOptExempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshBatteryOptStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
    );
  }
}
