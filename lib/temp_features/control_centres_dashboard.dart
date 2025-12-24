import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/equipments/presentation/providers/equipment_providers.dart'
    as eq_provs;
import '../features/plot_mapping/presentation/providers/plot_providers.dart'
    as fm_provs;
import '../core/services/auth_service.dart';
import '../core/services/telemetry_service.dart';
import '../core/utils/mac_utils.dart';
import '../features/data_monitoring/presentation/screens/monitoring_screen.dart';
import '../features/reports/presentation/screens/reports_list_screen.dart';
import '../features/equipments/presentation/screens/create_control_unit_screen.dart';
import '../features/equipments/presentation/screens/scan_control_unit_screen.dart';

/// Temporary dashboard that resembles the main three-button dashboard but
/// includes a quick control-centres status card for development/testing.
class TempDashboard extends ConsumerWidget {
  const TempDashboard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.read(authServiceProvider).currentUserId ?? '';
    final controlUnitsAsync = ref.watch(eq_provs.controlUnitsProvider(userId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/profile'),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // subtle background tint
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
            // Header gradient and emblem
            Column(
              children: [
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary.withAlpha(40),
                        Theme.of(context).colorScheme.primary.withAlpha(15),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      children: [
                        // Emblem
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.primary,
                                Theme.of(context).colorScheme.secondary,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withAlpha(40),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              )
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.dashboard_customize,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Title
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Quick access to control centres',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Content area
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        // Control centres status card
                        controlUnitsAsync.when(
                          data: (items) => _DashboardCard(
                            icon: Icons.router_outlined,
                            title: 'Active Devices',
                            subtitle: _controlSummary(items),
                            color: const Color(0xFF1565C0),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _ControlUnitsListScreen(
                                  items: items,
                                ),
                              ),
                            ),
                          ),
                          loading: () => const Center(
                              child: Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(),
                          )),
                          error: (e, st) => _DashboardCard(
                            icon: Icons.warning_amber_outlined,
                            title: 'Active Devices',
                            subtitle: 'Error loading control centres',
                            color: Colors.red,
                            onTap: () {},
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DashboardCard(
                          icon: Icons.settings_outlined,
                          title: 'Settings',
                          subtitle: 'Configure equipment and system',
                          color: const Color(0xFF8E4600),
                          onTap: () => Navigator.of(context)
                              .pushNamed('/technician_dashboard'),
                        ),
                        const SizedBox(height: 12),
                        _DashboardCard(
                          icon: Icons.bar_chart_outlined,
                          title: 'Reports',
                          subtitle: 'View recent application reports',
                          color: const Color(0xFF00897B),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ReportsListScreen()),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Additional quick actions can be added here
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _controlSummary(List items) {
    if (items.isEmpty) return 'No control centres';
    final statuses = <String, int>{};
    for (final it in items) {
      final s = (it.status ?? 'unknown').toString().toLowerCase();
      statuses[s] = (statuses[s] ?? 0) + 1;
    }
    final parts =
        statuses.entries.map((e) => '${_capitalize(e.key)}: ${e.value}');
    return parts.join(' • ');
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Simple model used for dummy report data in the temporary UI.

/// Try to extract a plot name from a `linkedPlotId` value which may be:
/// - an id string that maps to `plotMap`, or
/// - a JSON-like string with unquoted keys (e.g. {id:123,name:MyPlot})
/// This function attempts to parse the loose string and return the `name`
/// field when available, otherwise it falls back to `plotMap[id]`.
String? _extractPlotNameFromLinked(String linked, Map<String, String> plotMap) {
  if (linked.isEmpty) return null;

  // Direct lookup first (covers plain id strings)
  final direct = plotMap[linked];
  if (direct != null) return direct;

  // If it looks like an object (starts with '{'), try to parse it.
  if (linked.trim().startsWith('{')) {
    try {
      // Normalize single quotes to double quotes
      var s = linked.replaceAll("'", '"');
      // Quote unquoted keys: {key: -> {"key":
      s = s.replaceAllMapped(RegExp(r'([\{,\s])(\w+)\s*:'), (m) {
        final lead = m.group(1) ?? '';
        final key = m.group(2) ?? '';
        return '$lead"$key":';
      });
      final decoded = json.decode(s);
      if (decoded is Map && decoded.containsKey('name')) {
        return decoded['name']?.toString();
      }
      if (decoded is Map && decoded.containsKey('id')) {
        final id = decoded['id']?.toString();
        if (id != null && id.isNotEmpty) return plotMap[id];
      }
    } catch (_) {
      // ignore parse errors
    }
  }

  // As a last attempt, try to find an id-like number inside the string
  final idMatch = RegExp(r"id\s*[:=]\s*([0-9A-Za-z-]+)").firstMatch(linked);
  if (idMatch != null) {
    final id = idMatch.group(1);
    if (id != null && id.isNotEmpty) return plotMap[id];
  }

  return null;
}

class _ControlUnitsListScreen extends ConsumerStatefulWidget {
  final List items;
  const _ControlUnitsListScreen({required this.items, Key? key})
      : super(key: key);

  @override
  ConsumerState<_ControlUnitsListScreen> createState() =>
      _ControlUnitsListScreenState();
}

class _ControlUnitsListScreenState
    extends ConsumerState<_ControlUnitsListScreen> {
  TelemetryService? _telemetrySvc;
  @override
  void initState() {
    super.initState();
    // Cache telemetry service to avoid using `ref` during dispose.
    _telemetrySvc = ref.read(telemetryServiceProvider);
    // Subscribe to telemetry for all listed control units that have an id
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final svc = _telemetrySvc;
      if (svc == null) return;
      for (final cu in widget.items) {
        try {
          final id = extractDeviceId(cu);
          if (id.isNotEmpty) svc.subscribe(id);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    // Unsubscribe from telemetry for listed control units
    final svc = _telemetrySvc;
    if (svc != null) {
      for (final cu in widget.items) {
        try {
          final id = extractDeviceId(cu);
          if (id.isNotEmpty) svc.unsubscribe(id);
        } catch (_) {}
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.read(authServiceProvider).currentUserId ?? '';
    final plotsAsync = ref.watch(fm_provs.plotsListProvider(userId));

    // Build a quick mapping of plot id -> plot name when available.
    final Map<String, String> plotMap = {};
    final plots = plotsAsync.asData?.value;
    if (plots != null) {
      for (final p in plots) {
        try {
          plotMap[p.id.toString()] = p.name;
        } catch (_) {
          // ignore malformed plot objects
        }
      }
    }

    final activeAsync = ref.watch(activeDevicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Active Devices')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, i) {
          final cu = widget.items[i];
          final linkedPlotId = (cu.linkedPlotId ?? '').toString();
          final linkedPlotName =
              _extractPlotNameFromLinked(linkedPlotId, plotMap);
          return activeAsync.when(
            data: (activeList) {
              final deviceId = extractDeviceId(cu);
              final deviceIdNorm = deviceId;
              if (deviceId.isEmpty) {
                try {
                  // Log helpful properties instead of the instance to inspect why
                  // an id couldn't be extracted.
                  final dyn = cu as dynamic;
                  final mac = (() {
                    try {
                      return dyn.macAddress ?? dyn.mac ?? dyn['mac'] ?? null;
                    } catch (_) {
                      return null;
                    }
                  })();
                  final controlUnitId = (() {
                    try {
                      return dyn.controlUnitId ??
                          dyn['controlUnitId'] ??
                          dyn['control_unit_id'] ??
                          null;
                    } catch (_) {
                      return null;
                    }
                  })();
                  final idField = (() {
                    try {
                      return dyn.id ?? dyn['id'] ?? null;
                    } catch (_) {
                      return null;
                    }
                  })();
                  debugPrint(
                      'ActiveDevices.missingId at index $i: mac=${safeStringify(mac)} controlUnitId=${safeStringify(controlUnitId)} id=${safeStringify(idField)} raw=${safeStringify(cu)}');
                } catch (_) {}
              }
              // Debug: show what the UI compares
              try {
                final activeKeys =
                    activeList.map((t) => canonicalizeMac(t.deviceId)).toSet();
                debugPrint(
                    'ActiveDevices.compare: displayId=${safeStringify(deviceId)} canonical=${safeStringify(deviceIdNorm)} activeKeys=${safeStringify(activeKeys)}');
              } catch (_) {}
              final activeKeys =
                  activeList.map((t) => canonicalizeMac(t.deviceId)).toSet();
              final isActive = deviceIdNorm.isNotEmpty
                  ? activeKeys.contains(deviceIdNorm)
                  : false;
              final statusText = isActive ? 'online' : 'offline';
              final displayId = deviceId.isNotEmpty
                  ? deviceId
                  : (() {
                      try {
                        if (cu is Map) {
                          return (cu['controlUnitId'] ??
                                  cu['control_unit_id'] ??
                                  cu['id'] ??
                                  '')
                              .toString();
                        }
                        try {
                          return (cu.controlUnitId ?? '').toString();
                        } catch (_) {
                          return '';
                        }
                      } catch (_) {
                        return '';
                      }
                    })();

              return ListTile(
                title: Text((cu.name ?? 'Unnamed').toString()),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (displayId.isNotEmpty) Text('ID: $displayId'),
                    if (linkedPlotId.isNotEmpty)
                      Text('Default plot: ${linkedPlotName ?? linkedPlotId}'),
                    Text('Status: $statusText'),
                  ],
                ),
                trailing: Icon(
                  isActive ? Icons.wifi : Icons.wifi_off,
                  color: isActive ? Colors.green : Colors.grey,
                ),
                onTap: deviceIdNorm.isNotEmpty
                    ? () {
                        // Try to extract a usable plot id from the linkedPlotId
                        String? plotIdForNav;
                        try {
                          if (linkedPlotId.isNotEmpty) {
                            final idMatch =
                                RegExp(r'id\s*[:=]\s*([0-9A-Za-z-]+)')
                                    .firstMatch(linkedPlotId);
                            if (idMatch != null) {
                              plotIdForNav = idMatch.group(1);
                            } else {
                              plotIdForNav = linkedPlotId;
                            }
                          }
                        } catch (_) {}

                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => MonitoringScreen(
                                deviceId: deviceIdNorm,
                                plotId: plotIdForNav)));
                      }
                    : null,
              );
            },
            loading: () => ListTile(
              title: Text((cu.name ?? 'Unnamed').toString()),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((cu.controlUnitId ?? '').toString().isNotEmpty)
                    Text('ID: ${cu.controlUnitId}'),
                  if (linkedPlotId.isNotEmpty)
                    Text('Default plot: ${linkedPlotName ?? linkedPlotId}'),
                  Text('Status: offline'),
                ],
              ),
              trailing: Icon(Icons.wifi_off, color: Colors.grey),
            ),
            error: (e, st) => ListTile(
              title: Text((cu.name ?? 'Unnamed').toString()),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((cu.controlUnitId ?? '').toString().isNotEmpty)
                    Text('ID: ${cu.controlUnitId}'),
                  if (linkedPlotId.isNotEmpty)
                    Text('Default plot: ${linkedPlotName ?? linkedPlotId}'),
                  Text('Status: offline'),
                ],
              ),
              trailing: Icon(Icons.wifi_off, color: Colors.grey),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startDeviceSetupFlow(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  /// Guides the user through the device setup flow:
  /// 1. Add a plot first
  /// 2. Then add a control unit
  void _startDeviceSetupFlow(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Device Setup Guide'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To add a new device, follow these steps:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1. ', style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text('Add a plot where your device will operate'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('2. ', style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text('Add your control unit and link it to the plot'),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'Let\'s start by adding a plot!',
              style:
                  TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToAddPlot(context);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  /// Navigate to the plot mapping screen to add a new plot
  void _navigateToAddPlot(BuildContext context) async {
    // Navigate to the map screen for adding plots
    final result = await Navigator.of(context).pushNamed('/map');

    // After returning from plot creation, guide to control unit creation
    // Only proceed if user actually saved a plot (result == true)
    if (!mounted || result != true) {
      return;
    }

    // Use addPostFrameCallback to ensure the screen has fully rebuilt
    // after returning from navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkAndNavigateToControlUnit();
      }
    });
  }

  /// Check if user added a plot and guide them to add control unit
  void _checkAndNavigateToControlUnit() {
    if (!mounted) {
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Plot Added!'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Great! Now let\'s add your control unit.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('You will be able to:'),
            SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• '),
                Expanded(child: Text('Configure your control unit details')),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• '),
                Expanded(child: Text('Link it to the plot you just created')),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• '),
                Expanded(child: Text('Set up sensors and equipment')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _navigateToAddControlUnit(returnToPlot: true);
            },
            child: const Text('Add Control Unit'),
          ),
        ],
      ),
    );
  }

  /// Navigate to create control unit screen
  void _navigateToAddControlUnit({bool returnToPlot = false}) {
    if (!mounted) return;

    // Show the same modal bottom sheet as equipment list screen
    _showControlUnitAddOptions(returnToPlot: returnToPlot);
  }

  /// Show modal bottom sheet with options to scan or manually add control unit
  Future<void> _showControlUnitAddOptions({bool returnToPlot = false}) async {
    if (!mounted) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Scan to add'),
            subtitle: const Text('Scan QR code on control unit'),
            onTap: () => Navigator.of(context).pop('scan'),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add control unit'),
            subtitle: const Text('Manually enter details'),
            onTap: () => Navigator.of(context).pop('add'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (choice == 'scan') {
      // Navigate to scanner screen
      final result = await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ScanControlUnitScreen()),
      );
      if (mounted && result is Map<String, dynamic>) {
        // Open create screen with scanned data
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreateControlUnitScreen(
                existingData: result, returnToAddPlot: returnToPlot),
          ),
        );
      }
    } else if (choice == 'add') {
      // Navigate directly to create control unit screen
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              CreateControlUnitScreen(returnToAddPlot: returnToPlot)));
    }
    // If choice is null, user dismissed the sheet - do nothing
  }

  // Status icon/color helper removed; list now shows online/offline using
  // wifi/wifi_off icons and explicit colors.
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shadowColor: color.withAlpha(60),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withAlpha(24),
                color.withAlpha(12),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withAlpha(40),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
