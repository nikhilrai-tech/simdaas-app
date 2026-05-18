import 'dart:async';
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
import 'user_guide_pdf_screen.dart';
import '../features/equipments/presentation/screens/create_control_unit_screen.dart';
import '../features/equipments/presentation/screens/scan_control_unit_screen.dart';

/// Temporary dashboard that resembles the main three-button dashboard but
/// includes a quick control-centres status card for development/testing.
class TempDashboard extends ConsumerWidget {
  const TempDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.read(authServiceProvider).currentUserId ?? '';
    final controlUnitsAsync = ref.watch(eq_provs.controlUnitsProvider(userId));
    final activeDevices = ref.watch(activeDevicesProvider).asData?.value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(eq_provs.controlUnitsProvider(userId));
              ref.invalidate(eq_provs.equipmentsListProvider(userId));
              ref.invalidate(fm_provs.plotsListProvider(userId));
              ref.invalidate(activeDevicesProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing...'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
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
                // Header Section - More informational, less button-like
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _getGreeting(),
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withAlpha(178),
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Welcome',
                              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context).colorScheme.onSurface,
                                    fontSize: 32,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withAlpha(25),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 14,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Quick access to control centres',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const UserGuidePdfScreen(),
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withAlpha(25),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Icon(
                                      Icons.picture_as_pdf_outlined,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Decorative Element instead of a button-like emblem
                      Opacity(
                        opacity: 0.15,
                        child: Icon(
                          Icons.dashboard_customize,
                          size: 80,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
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
                        _DashboardCard(
                          icon: Icons.devices_other_outlined,
                          title: 'Active Devices',
                          subtitle: _controlSummary(
                            controlUnitsAsync.asData?.value ?? [],
                            activeDevices,
                          ),
                          color: const Color(0xFF1B5E20),
                          onTap: () {
                            final items = controlUnitsAsync.asData?.value ?? [];
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _ControlUnitsListScreen(items: items),
                              ),
                            );
                          },
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


  String _controlSummary(List items, List<TelemetryData> actives) {
    if (items.isEmpty) return 'No control centres';

    final activeKeys = actives.map((t) => canonicalizeMac(t.deviceId)).toSet();
    int onlineCount = 0;

    for (final it in items) {
      final deviceId = extractDeviceId(it);
      if (deviceId.isNotEmpty && activeKeys.contains(canonicalizeMac(deviceId))) {
        onlineCount++;
      }
    }

    final offlineCount = items.length - onlineCount;
    return 'offline: $offlineCount. online: $onlineCount.';
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
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
  const _ControlUnitsListScreen({required this.items});

  @override
  ConsumerState<_ControlUnitsListScreen> createState() =>
      _ControlUnitsListScreenState();
}

class _ControlUnitsListScreenState
    extends ConsumerState<_ControlUnitsListScreen> {
  String _deviceFilter = 'all'; // 'all', 'active', 'inactive'

  // NOTE: this screen does NOT manage telemetry subscriptions itself.
  // TelemetryBootstrapper at app root subscribes to every control unit owned
  // by the signed-in user via `subscribeToDevices`. If we also subscribe
  // here and unsubscribe in dispose(), navigating away from this screen
  // closes the WebSocket channels and breaks the dashboard's
  // `activeDevicesProvider` (it goes empty → "All Offline").

  @override
  Widget build(BuildContext context) {
    final userId = ref.read(authServiceProvider).currentUserId ?? '';
    final plotsAsync = ref.watch(fm_provs.plotsListProvider(userId));
    final sprayersAsync = ref.watch(eq_provs.sprayersProvider(userId));

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

    // Build a quick mapping of sprayer id -> sprayer name.
    final Map<String, String> sprayerMap = {};
    final sprayers = sprayersAsync.asData?.value;
    if (sprayers != null) {
      for (final s in sprayers) {
        sprayerMap[s.id.toString()] = s.name;
      }
    }

    final activeAsync = ref.watch(activeDevicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Active Devices')),
      body: Column(
        children: [
          // Device Status Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter by Status:',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _deviceFilter == 'all',
                      selectedColor:
                          Theme.of(context).colorScheme.primary.withAlpha(50),
                      onSelected: (s) => setState(() => _deviceFilter = 'all'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Active'),
                      avatar: _deviceFilter == 'active'
                          ? const Icon(Icons.check_circle, size: 16)
                          : null,
                      selected: _deviceFilter == 'active',
                      selectedColor: Colors.green.withAlpha(50),
                      onSelected: (s) =>
                          setState(() => _deviceFilter = 'active'),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Non-active'),
                      selected: _deviceFilter == 'inactive',
                      selectedColor: Colors.orange.withAlpha(50),
                      onSelected: (s) =>
                          setState(() => _deviceFilter = 'inactive'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: activeAsync.when(
              data: (activeList) {
                final activeKeys = activeList
                    .map((t) => canonicalizeMac(t.deviceId))
                    .toSet();

                 final filteredItems = widget.items.where((cu) {
                  final deviceId = extractDeviceId(cu);
                  final isActive = deviceId.isNotEmpty &&
                      activeKeys.contains(canonicalizeMac(deviceId));
                  
                  if (_deviceFilter == 'active' && !isActive) return false;
                  if (_deviceFilter == 'inactive' && isActive) return false;
                  return true;
                }).toList();

                if (filteredItems.isEmpty) {
                  return const Center(child: Text('No devices match filter'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredItems.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final cu = filteredItems[i];
                    final deviceId = extractDeviceId(cu);
                    final isInActiveList = deviceId.isNotEmpty &&
                        activeKeys.contains(canonicalizeMac(deviceId));
                    final linkedPlotId = (cu.linkedPlotId ?? '').toString();
                    final linkedPlotName =
                        _extractPlotNameFromLinked(linkedPlotId, plotMap);
                    final linkedSprayerId = (cu.linkedSprayerId ?? '').toString();
                    final linkedSprayerName = linkedSprayerId.isNotEmpty
                        ? sprayerMap[linkedSprayerId]
                        : null;
                    return _DeviceListItem(
                      cu: cu,
                      isInActiveList: isInActiveList,
                      linkedPlotName: linkedPlotName,
                      linkedSprayerName: linkedSprayerName,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
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

/// Single row in the Active Devices list.
/// Watches the device's cooldown stream so the status dot and label
/// update immediately when a session is ended (no screen reload needed).
class _DeviceListItem extends ConsumerWidget {
  final dynamic cu;
  final bool isInActiveList;
  final String? linkedPlotName;
  final String? linkedSprayerName;

  const _DeviceListItem({
    required this.cu,
    required this.isInActiveList,
    this.linkedPlotName,
    this.linkedSprayerName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceId = extractDeviceId(cu);
    final lookupId = deviceId.isNotEmpty ? deviceId : '__none__';
    final cooldownAsync = ref.watch(deviceCooldownStateProvider(lookupId));
    final cooldownState = cooldownAsync.asData?.value;

    final isInCooldown = cooldownState?.isInCooldown ?? false;
    final isEffectivelyActive = isInActiveList && !isInCooldown &&
        (cooldownState?.status != DeviceLifecycleStatus.offline);

    // WAITING = device recently stopped sending (< 10 min ago) but session
    // is not yet ended on the backend. Track remains visible in monitoring.
    // Always prefer the in-memory last-seen (actual last MQTT receive time)
    // over cu.lastSeenAt — the DB field gets updated when a new session is
    // created on the backend, which would show the wrong "offline since" time.
    DateTime? lastSeenAt;
    if (deviceId.isNotEmpty) {
      lastSeenAt = ref.read(telemetryServiceProvider).getLastSeenAt(deviceId);
    }
    lastSeenAt ??= (cu.lastSeenAt as DateTime?);

    bool isWaiting = false;
    if (!isEffectivelyActive && !isInCooldown &&
        cooldownState?.status != DeviceLifecycleStatus.offline &&
        lastSeenAt != null) {
      final elapsed = DateTime.now().toUtc().difference(lastSeenAt).inMinutes;
      isWaiting = elapsed < TelemetryService.sessionTimeoutMinutes;
    }

    final String statusText;
    final Color statusColor;
    if (isInCooldown) {
      statusText = 'COOLDOWN';
      statusColor = Colors.blue;
    } else if (isEffectivelyActive) {
      statusText = 'ONLINE';
      statusColor = Colors.green;
    } else if (isWaiting) {
      statusText = 'WAITING';
      statusColor = Colors.amber;
    } else {
      statusText = 'OFFLINE';
      statusColor = Colors.orange;
    }

    final linkedPlotId = (cu.linkedPlotId ?? '').toString();
    final displayId = deviceId.isNotEmpty
        ? deviceId
        : (cu.controlUnitId ?? cu.id).toString();

    // Trailing pill: cooldown countdown in blue, waiting countdown in amber.
    // Offline state shows no trailing pill.
    Widget? trailingWidget;
    if (isInCooldown) {
      trailingWidget = _CooldownCountdownPill(cooldownEnd: cooldownState?.cooldownEnd);
    } else if (isWaiting && lastSeenAt != null) {
      trailingWidget = _WaitingCountdownPill(lastSeenAt: lastSeenAt);
    }

    return ListTile(
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: statusColor,
          shape: BoxShape.circle,
          boxShadow: [
            if (isEffectivelyActive)
              BoxShadow(
                color: Colors.green.withAlpha(100),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            if (isWaiting)
              BoxShadow(
                color: Colors.amber.withAlpha(120),
                blurRadius: 4,
                spreadRadius: 1,
              ),
          ],
        ),
      ),
      title: Text(
        cu.name.toString(),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (displayId.isNotEmpty) Text('ID: $displayId'),
          if (linkedPlotId.isNotEmpty)
            Text('Default plot: ${linkedPlotName ?? linkedPlotId}'),
          if (linkedSprayerName != null)
            Text('Default sprayer: $linkedSprayerName'),
          if (statusText == 'OFFLINE')
            Text(
              lastSeenAt != null
                  ? 'Offline since: ${_formatTimeOfDay(lastSeenAt)}'
                  : 'Offline since: --',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
            ),
          if (!isInCooldown)
            Text(
              statusText,
              style: TextStyle(
                color: isEffectivelyActive
                    ? Colors.green.shade700
                    : statusColor.withAlpha(200),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
      trailing: trailingWidget,
      onTap: deviceId.isNotEmpty
          ? () {
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
                  builder: (_) =>
                      MonitoringScreen(deviceId: deviceId, plotId: plotIdForNav)));
            }
          : null,
    );
  }
}

/// Blue pill showing "❄️ MM:SS" countdown until cooldown ends.
/// Runs its own 1-second timer so parent doesn't need to be stateful.
class _CooldownCountdownPill extends StatefulWidget {
  final DateTime? cooldownEnd;
  const _CooldownCountdownPill({this.cooldownEnd});

  @override
  State<_CooldownCountdownPill> createState() => _CooldownCountdownPillState();
}

class _CooldownCountdownPillState extends State<_CooldownCountdownPill> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cooldownEnd == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '❄️ COOLDOWN',
          style: TextStyle(
            color: Colors.blue,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    final remaining =
        widget.cooldownEnd!.toUtc().difference(DateTime.now().toUtc()).inSeconds;
    if (remaining <= 0) return const SizedBox.shrink();
    final m = remaining ~/ 60;
    final s = remaining % 60;
    final label =
        '❄️ ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Amber pill showing "⏳ MM:SS" countdown until the backend session timeout.
/// Runs its own 1-second timer so parent doesn't need to be stateful.
class _WaitingCountdownPill extends StatefulWidget {
  final DateTime lastSeenAt;
  const _WaitingCountdownPill({required this.lastSeenAt});

  @override
  State<_WaitingCountdownPill> createState() => _WaitingCountdownPillState();
}

class _WaitingCountdownPillState extends State<_WaitingCountdownPill> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed =
        DateTime.now().toUtc().difference(widget.lastSeenAt.toUtc()).inSeconds;
    final remaining =
        TelemetryService.sessionTimeoutMinutes * 60 - elapsed;
    if (remaining <= 0) return const SizedBox.shrink();
    final m = remaining ~/ 60;
    final s = remaining % 60;
    final label =
        '⏳ ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.amber,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

String _formatTimeOfDay(DateTime dt) {
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
