import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/equipment_providers.dart';
import '../../../plot_mapping/presentation/providers/plot_providers.dart' as plot_provs;
import 'dart:convert';
// ...existing code...
import 'create_equipment_screen.dart';
import 'equipment_details_screen.dart';
import 'create_control_unit_screen.dart';
import 'scan_control_unit_screen.dart';
import 'equipment_troubleshooting_screen.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/widgets/api_error_widget.dart';
import 'package:simdaas/core/services/connectivity_service.dart';
import 'dart:async';

/// Equipment list screen with three category buttons and a filtered list.
class EquipmentListScreen extends ConsumerStatefulWidget {
  const EquipmentListScreen({super.key});

  @override
  ConsumerState<EquipmentListScreen> createState() =>
      _EquipmentListScreenState();
}

class _EquipmentListScreenState extends ConsumerState<EquipmentListScreen>
    with WidgetsBindingObserver {
  String _filterCategory = 'all';
  bool _initialFilterHandled = false;
  late final javaTimer = _setupAutoRefresh();

  dynamic _setupAutoRefresh() {
    return Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (mounted) _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final userId = ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    final args = ModalRoute.of(context)?.settings.arguments;
    final routeCategory = (args is Map && args['category'] is String)
        ? args['category'] as String
        : null;

    if (routeCategory == null) {
      ref.invalidate(equipmentsListProvider(userId));
    } else if (routeCategory.toLowerCase() == 'control_unit') {
      ref.invalidate(controlUnitsProvider(userId));
    } else if (routeCategory.toLowerCase() == 'tractor') {
      ref.invalidate(tractorsProvider(userId));
    } else if (routeCategory.toLowerCase() == 'sprayer') {
      ref.invalidate(sprayersProvider(userId));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (javaTimer is StreamSubscription) {
      (javaTimer as StreamSubscription).cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      final currentUserId = ref.read(authServiceProvider).currentUserId;
      if (currentUserId != null) {
        ref.invalidate(equipmentsListProvider(currentUserId));
        ref.invalidate(controlUnitsProvider(currentUserId));
        ref.invalidate(tractorsProvider(currentUserId));
        ref.invalidate(sprayersProvider(currentUserId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final readOnly = args is Map && args['readOnly'] == true;

    final userId = ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    final routeCategory = (args is Map && args['category'] is String)
        ? args['category'] as String
        : null;

    // Initial filter handling removed

    // If a specific category was requested via route args, use the dedicated
    // provider so we only fetch that category's endpoint. Otherwise fetch
    // the merged equipments list.
    final itemsAsync = (routeCategory == null)
        ? ref.watch(equipmentsListProvider(userId))
        : (routeCategory.toLowerCase() == 'control_unit'
            ? ref.watch(controlUnitsProvider(userId))
            : (routeCategory.toLowerCase() == 'tractor'
                ? ref.watch(tractorsProvider(userId))
                : ref.watch(sprayersProvider(userId))));
    final conn = ref.watch(isOnlineStreamProvider);
    final online = conn.asData?.value ?? true;

    String heading = 'Equipments';
    String addLabel = 'Add Equipment';
    String noEquipMsg = 'No equipment yet';
    String addPlaceholder = 'Tap the + button to add equipment';

    if (routeCategory != null) {
      switch (routeCategory.toLowerCase()) {
        case 'control_unit':
          heading = 'Control Units';
          addLabel = 'Add Control Unit';
          noEquipMsg = 'No control units yet';
          addPlaceholder = 'Tap the + button to add a control unit';
          break;
        case 'tractor':
          heading = 'Tractors';
          addLabel = 'Add Tractor';
          noEquipMsg = 'No tractors yet';
          addPlaceholder = 'Tap the + button to add a tractor';
          break;
        case 'sprayer':
          heading = 'Sprayers';
          addLabel = 'Add Sprayer';
          noEquipMsg = 'No sprayers yet';
          addPlaceholder = 'Tap the + button to add a sprayer';
          break;
      }
    } else if (_filterCategory != 'all') {
       switch (_filterCategory.toLowerCase()) {
        case 'control_unit':
          heading = 'Control Units';
          addLabel = 'Add Control Unit';
          break;
        case 'tractor':
          heading = 'Tractors';
          addLabel = 'Add Tractor';
          break;
        case 'sprayer':
          heading = 'Sprayers';
          addLabel = 'Add Sprayer';
          break;
      }
    }

    final plotsAsync = ref.watch(plot_provs.plotsListProvider(userId));
    final Map<String, String> plotMap = {};
    plotsAsync.whenData((plots) {
      for (final p in plots) {
        plotMap[p.id.toString()] = p.name;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(heading),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
        ],
        elevation: 0,
        bottom: online
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  height: 28,
                  color: Colors.red.shade700,
                  alignment: Alignment.center,
                  child: const Text(
                    'Offline — showing last known data',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
      ),
      body: itemsAsync.when(
        data: (items) {
          final activeCategory = routeCategory ?? _filterCategory;

          final filtered = items.where((it) {
            final e = it as dynamic;
            final cat = (e.category as String?) ?? 'other';
            
            // Category filter
            if (activeCategory != 'all' &&
                cat.toLowerCase() != activeCategory.toLowerCase()) {
              return false;
            }


            return true;
          }).toList();

          return Column(
            children: [
              if (routeCategory == null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _CategoryCard(
                          icon: Icons.memory,
                          label: 'Control Units',
                          color: const Color(0xFF015685),
                          onTap: () => Navigator.of(context).push(
                             MaterialPageRoute(
                               builder: (_) => const EquipmentListScreen(),
                               settings: RouteSettings(arguments: {
                                 'category': 'control_unit',
                                 'readOnly': readOnly
                               }))),
                        ),
                        const SizedBox(width: 8),
                        _CategoryCard(
                          icon: Icons.agriculture,
                          label: 'Tractors',
                          color: const Color(0xFF2E7D32),
                          onTap: () => Navigator.of(context).push(
                             MaterialPageRoute(
                               builder: (_) => const EquipmentListScreen(),
                               settings: RouteSettings(arguments: {
                                 'category': 'tractor',
                                 'readOnly': readOnly
                               }))),
                        ),
                        const SizedBox(width: 8),
                        _CategoryCard(
                          icon: Icons.water_drop,
                          label: 'Sprayers',
                          color: const Color(0xFF8E4600),
                          onTap: () => Navigator.of(context).push(
                             MaterialPageRoute(
                               builder: (_) => const EquipmentListScreen(),
                               settings: RouteSettings(arguments: {
                                 'category': 'sprayer',
                                 'readOnly': readOnly
                               }))),
                        ),
                        const SizedBox(width: 8),
                        _CategoryCard(
                          icon: Icons.info_outline,
                          label: 'Troubleshooting',
                          color: const Color(0xFF1565C0),
                          onTap: () => Navigator.of(context).push(
                             MaterialPageRoute(
                               builder: (_) => const EquipmentTroubleshootingScreen())),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // Device Status Filter Chips removed by user request
              Expanded(
                child: filtered.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () async {
                          final currentUserId =
                              ref.read(authServiceProvider).currentUserId ??
                                  'demo_user';
                          if (routeCategory == null) {
                            ref.invalidate(
                                equipmentsListProvider(currentUserId));
                            try {
                              await ref.read(
                                  equipmentsListProvider(currentUserId).future);
                            } catch (_) {}
                          } else if (routeCategory.toLowerCase() ==
                              'control_unit') {
                            ref.invalidate(controlUnitsProvider(currentUserId));
                            try {
                              await ref.read(
                                  controlUnitsProvider(currentUserId).future);
                            } catch (_) {}
                          } else if (routeCategory.toLowerCase() == 'tractor') {
                            ref.invalidate(tractorsProvider(currentUserId));
                            try {
                              await ref
                                  .read(tractorsProvider(currentUserId).future);
                            } catch (_) {}
                          } else if (routeCategory.toLowerCase() == 'sprayer') {
                            ref.invalidate(sprayersProvider(currentUserId));
                            try {
                              await ref
                                  .read(sprayersProvider(currentUserId).future);
                            } catch (_) {}
                          }
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.6,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.precision_manufacturing_outlined,
                                      size: 64,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      noEquipMsg,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      addPlaceholder,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          final currentUserId =
                              ref.read(authServiceProvider).currentUserId ??
                                  'demo_user';
                          if (routeCategory == null) {
                            ref.invalidate(
                                equipmentsListProvider(currentUserId));
                            try {
                              await ref.read(
                                  equipmentsListProvider(currentUserId).future);
                            } catch (_) {}
                          } else if (routeCategory.toLowerCase() ==
                              'control_unit') {
                            ref.invalidate(controlUnitsProvider(currentUserId));
                            try {
                              await ref.read(
                                  controlUnitsProvider(currentUserId).future);
                            } catch (_) {}
                          } else if (routeCategory.toLowerCase() == 'tractor') {
                            ref.invalidate(tractorsProvider(currentUserId));
                            try {
                              await ref
                                  .read(tractorsProvider(currentUserId).future);
                            } catch (_) {}
                          } else if (routeCategory.toLowerCase() == 'sprayer') {
                            ref.invalidate(sprayersProvider(currentUserId));
                            try {
                              await ref
                                  .read(sprayersProvider(currentUserId).future);
                            } catch (_) {}
                          }
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final e = filtered[i];

                            final linkedPlotId = (e.linkedPlotId ?? '').toString();
                            final linkedPlotName =
                                _extractPlotNameFromLinked(linkedPlotId, plotMap);

                            final details = (e.category == 'sprayer')
                                ? 'Plot: ${linkedPlotName ?? '-'} • Mount H: ${e.mountingHeight ?? '-'} m • Lidar-Nozzle: ${e.lidarNozzleDistance ?? '-'} m'
                                : 'Plot: ${linkedPlotName ?? '-'}';

                            IconData getCategoryIcon(String category) {
                              switch (category.toLowerCase()) {
                                case 'control_unit':
                                  return Icons.memory;
                                case 'tractor':
                                  return Icons.agriculture;
                                case 'sprayer':
                                  return Icons.water_drop;
                                default:
                                  return Icons.precision_manufacturing;
                              }
                            }

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              child: InkWell(
                                onTap: () async {
                                  final res = await Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              EquipmentDetailsScreen(
                                                  equipment: e,
                                                  readOnly: readOnly)));
                                  if (res == true) {
                                    final currentUserId = ref
                                            .read(authServiceProvider)
                                            .currentUserId ??
                                        'demo_user';
                                    ref.invalidate(
                                        equipmentsListProvider(currentUserId));
                                    switch (e.category.toLowerCase()) {
                                      case 'control_unit':
                                        ref.invalidate(controlUnitsProvider(
                                            currentUserId));
                                        break;
                                      case 'sprayer':
                                        ref.invalidate(
                                            sprayersProvider(currentUserId));
                                        break;
                                      case 'tractor':
                                        ref.invalidate(
                                            tractorsProvider(currentUserId));
                                        break;
                                      default:
                                        break;
                                    }
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withAlpha(26),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          getCategoryIcon(e.category),
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              e.category,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .secondary,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              details,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ApiErrorWidget(
          error: e,
          onRetry: () => ref.invalidate(equipmentsListProvider(userId)),
        ),
      ),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final args = ModalRoute.of(context)?.settings.arguments;
                final routeCategory =
                    (args is Map && args['category'] is String)
                        ? args['category'] as String
                        : null;

                // If category is control_unit offer a scan option first
                if (routeCategory != null) {
                  // Navigate to category-specific create pages
                  if (routeCategory.toLowerCase() == 'control_unit') {
                    final choice = await showModalBottomSheet<String>(
                        context: context,
                        builder: (_) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.qr_code_scanner),
                                  title: const Text('Scan to add'),
                                  onTap: () =>
                                      Navigator.of(context).pop('scan'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.add),
                                  title: const Text('Add control unit'),
                                  onTap: () => Navigator.of(context).pop('add'),
                                ),
                              ],
                            ));
                    if (choice == 'scan') {
                      // push scanner, get data back and open create with prefill
                      final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ScanControlUnitScreen()));
                      if (result is Map<String, dynamic>) {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                CreateControlUnitScreen(existingData: result)));
                      }
                    } else if (choice == 'add') {
                      // Only navigate when user explicitly chose Add.
                      await Navigator.of(context)
                          .pushNamed('/create_control_unit');
                    } else {
                      // choice == null -> user dismissed with back or tap outside.
                      // Do nothing.
                    }
                  } else if (routeCategory.toLowerCase() == 'tractor') {
                    await Navigator.of(context).pushNamed('/create_tractor');
                  } else if (routeCategory.toLowerCase() == 'sprayer') {
                    await Navigator.of(context).pushNamed('/create_sprayer');
                  } else {
                    // Fallback to generic creator if unknown category
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CreateEquipmentScreen(
                              existingData: {'category': routeCategory},
                            )));
                  }
                } else {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const CreateEquipmentScreen()));
                }

                ref.invalidate(equipmentsListProvider(userId));
              },
              icon: const Icon(Icons.add),
              label: Text(addLabel),
            ),
    );
  }

  String? _extractPlotNameFromLinked(String linked, Map<String, String> plotMap) {
    if (linked.isEmpty) return null;
    final direct = plotMap[linked];
    if (direct != null) return direct;

    if (linked.trim().startsWith('{')) {
      try {
        var s = linked.replaceAll("'", '"');
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
      } catch (_) {}
    }
    final idMatch = RegExp(r"id\s*[:=]\s*([0-9A-Za-z-]+)").firstMatch(linked);
    if (idMatch != null) {
      final id = idMatch.group(1);
      if (id != null && id.isNotEmpty) return plotMap[id];
    }
    return null;
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isSelected;

  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected ? BorderSide(color: color, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isSelected ? color.withAlpha(60) : color.withAlpha(26),
                isSelected ? color.withAlpha(30) : color.withAlpha(13),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
