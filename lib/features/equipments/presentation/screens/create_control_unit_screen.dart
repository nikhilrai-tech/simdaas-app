import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/equipment_providers.dart';
import '../../../plot_mapping/presentation/providers/plot_providers.dart'
    as fm_providers;
import 'package:simdaas/core/services/auth_service.dart';
import 'dart:convert';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

class CreateControlUnitScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingData;
  final bool returnToAddPlot;
  const CreateControlUnitScreen(
      {super.key, this.existingData, this.returnToAddPlot = false});

  @override
  ConsumerState<CreateControlUnitScreen> createState() =>
      _CreateControlUnitScreenState();
}

// KeepAlive helper so off-screen pages retain FormState
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _CreateControlUnitScreenState
    extends ConsumerState<CreateControlUnitScreen> {
  final _formKey = GlobalKey<FormState>();
  late final List<GlobalKey<FormState>> _pageKeys;
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;
  // Unit selectors for meter inputs
  String _lidarNozzleDistanceUnit = 'm';
  String _mountHeightUnit = 'm';
  String _ultrasonicDistanceUnit = 'm';
  final _name = TextEditingController();
  final _controlUnitId = TextEditingController();
  final _macAddress = TextEditingController();
  String? _linkedSprayerId;
  String? _linkedTractorId;
  String? _linkedPlotId;
  final _lidarNozzleDistance = TextEditingController();
  final _mountHeightOfLidar = TextEditingController();
  final _ultrasonicDistance = TextEditingController();
  String _sensorType = 'lidar';
  // cache of existing MACs for quick uniqueness check (normalized)
  Set<String> _existingMacs = {};
  // flags to lock fields that were provided by QR scan
  bool _prefilledName = false;
  bool _prefilledControlUnitId = false;
  bool _prefilledMac = false;
  bool _prefilledLinkedSprayer = false;
  bool _prefilledLinkedTractor = false;
  bool _prefilledLinkedPlot = false;
  bool _prefilledSensorType = false;
  bool _prefilledLidarNozzle = false;
  bool _prefilledMountHeight = false;
  bool _prefilledUltrasonic = false;
  // whether we're editing an existing equipment (has server id)
  bool _isEditing = false;
  // Guard to ensure existingData is applied only once (avoid overwriting
  // user changes when the widget rebuilds while editing)
  bool _initialized = false;

  @override
  void dispose() {
    _name.dispose();
    _controlUnitId.dispose();
    _macAddress.dispose();
    // controllers removed for dropdowns
    _lidarNozzleDistance.dispose();
    _mountHeightOfLidar.dispose();
    _ultrasonicDistance.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _pageKeys = List.generate(4, (_) => GlobalKey<FormState>());
  }

  @override
  Widget build(BuildContext context) {
    // If this screen was opened as part of the "Add Plot -> Add Control Unit"
    // guided flow, intercept back navigation and return the user to the
    // plot-creation screen instead of the previous dashboard.
    return WillPopScope(
      onWillPop: () async {
        if (widget.returnToAddPlot) {
          // Replace this route with the map/plot add screen so Back goes to map.
          await Navigator.of(context).pushReplacementNamed('/map');
          return false;
        }
        return true;
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    // Prefill if existingData provided (e.g., from QR scan or editing an
    // existing equipment). Behavior differs for two cases:
    // - Editing existing equipment (_isEditing == true): lock only name and
    //   controlUnitId (these are primary/identity fields). Other fields will
    //   be populated but remain editable so the user can change them.
    // - QR scan / new prefill (not editing): preserve the original behavior
    //   where prefilled fields are locked individually.
    // Apply existingData only once to avoid overwriting any user changes
    // when the widget rebuilds while editing. This preserves new selections
    // the user makes in dropdowns during an edit session.
    final ex = widget.existingData;
    if (!_initialized && ex != null) {
      final m = ex;
      // mark editing when an 'id' is present in existing data
      if (m.containsKey('id') && (m['id']?.toString().isNotEmpty == true)) {
        _isEditing = true;
      }

      // Always populate controllers with existing values (if any)
      if (m.containsKey('name') && (m['name'] as String?)?.isNotEmpty == true) {
        _name.text = m['name'] as String;
      }

      // For display, prefer controlUnitId. If editing and controlUnitId is
      // missing, fall back to server `id` so the identifier is visible.
      if (m.containsKey('controlUnitId') &&
          (m['controlUnitId'] as String?)?.isNotEmpty == true) {
        _controlUnitId.text = m['controlUnitId'] as String;
      } else if (_isEditing && m.containsKey('id')) {
        _controlUnitId.text = m['id']?.toString() ?? '';
      }

      // When editing, only lock name and controlUnitId. For QR-prefill
      // (not editing) retain the previous per-field prefill locking.
      if (_isEditing) {
        if (_name.text.isNotEmpty) _prefilledName = true;
        if (_controlUnitId.text.isNotEmpty) _prefilledControlUnitId = true;
        // Populate other fields but don't set their _prefilled flags so they
        // remain editable.
        if (m.containsKey('macAddress') &&
            (m['macAddress'] as String?)?.isNotEmpty == true) {
          _macAddress.text = m['macAddress'] as String;
        }
        if (m.containsKey('linkedSprayerId') &&
            (m['linkedSprayerId'] as String?)?.isNotEmpty == true) {
          _linkedSprayerId = m['linkedSprayerId'] as String?;
        }
        if (m.containsKey('linkedPlotId') &&
            (m['linkedPlotId'] as String?)?.isNotEmpty == true) {
          _linkedPlotId = m['linkedPlotId'] as String?;
        }
        if (m.containsKey('linkedTractorId') &&
            (m['linkedTractorId'] as String?)?.isNotEmpty == true) {
          _linkedTractorId = m['linkedTractorId'] as String?;
        }
        if (m.containsKey('sensorType') &&
            (m['sensorType'] as String?)?.isNotEmpty == true) {
          _sensorType = m['sensorType'] as String;
        }
        if (m.containsKey('lidarNozzleDistance') &&
            m['lidarNozzleDistance'] != null) {
          _lidarNozzleDistance.text = m['lidarNozzleDistance'].toString();
        }
        if (m.containsKey('mountingHeight') && m['mountingHeight'] != null) {
          _mountHeightOfLidar.text = m['mountingHeight'].toString();
        }
        if (m.containsKey('ultrasonicDistance') &&
            m['ultrasonicDistance'] != null) {
          _ultrasonicDistance.text = m['ultrasonicDistance'].toString();
        }
      } else {
        // Not editing: treat values as QR-prefilled and lock fields that
        // were provided by the scanner (existing behavior).
        if (m.containsKey('name') &&
            (m['name'] as String?)?.isNotEmpty == true) {
          _name.text = m['name'] as String;
          _prefilledName = true;
        }
        if (m.containsKey('controlUnitId') &&
            (m['controlUnitId'] as String?)?.isNotEmpty == true) {
          _controlUnitId.text = m['controlUnitId'] as String;
          _prefilledControlUnitId = true;
        }
        if (m.containsKey('macAddress') &&
            (m['macAddress'] as String?)?.isNotEmpty == true) {
          _macAddress.text = m['macAddress'] as String;
          _prefilledMac = true;
        }
        if (m.containsKey('linkedSprayerId') &&
            (m['linkedSprayerId'] as String?)?.isNotEmpty == true) {
          _linkedSprayerId = m['linkedSprayerId'] as String?;
          _prefilledLinkedSprayer = true;
        }
        if (m.containsKey('linkedPlotId') &&
            (m['linkedPlotId'] as String?)?.isNotEmpty == true) {
          _linkedPlotId = m['linkedPlotId'] as String?;
          _prefilledLinkedPlot = true;
        }
        if (m.containsKey('linkedTractorId') &&
            (m['linkedTractorId'] as String?)?.isNotEmpty == true) {
          _linkedTractorId = m['linkedTractorId'] as String?;
          _prefilledLinkedTractor = true;
        }
        if (m.containsKey('sensorType') &&
            (m['sensorType'] as String?)?.isNotEmpty == true) {
          _sensorType = m['sensorType'] as String;
          _prefilledSensorType = true;
        }
        if (m.containsKey('lidarNozzleDistance') &&
            m['lidarNozzleDistance'] != null) {
          _lidarNozzleDistance.text = m['lidarNozzleDistance'].toString();
          _prefilledLidarNozzle = true;
        }
        if (m.containsKey('mountingHeight') && m['mountingHeight'] != null) {
          _mountHeightOfLidar.text = m['mountingHeight'].toString();
          _prefilledMountHeight = true;
        }
        if (m.containsKey('ultrasonicDistance') &&
            m['ultrasonicDistance'] != null) {
          _ultrasonicDistance.text = m['ultrasonicDistance'].toString();
          _prefilledUltrasonic = true;
        }
      }
      // Note: scanned owner info is ignored. The current authenticated user
      // will be used as the owner for created control units.
      _initialized = true;
    }
    // populate existing MACs cache for uniqueness checks
    try {
      final userId = ref.read(authServiceProvider).currentUserId ?? '';
      final cuAsync = ref.watch(controlUnitsProvider(userId));
      cuAsync.maybeWhen(
          data: (items) {
            _existingMacs = items
                .where((e) => (e.macAddress ?? '').isNotEmpty)
                .map((e) => e.macAddress!
                    .replaceAll(RegExp(r'[^A-Fa-f0-9]'), '')
                    .toLowerCase())
                .toSet();
          },
          orElse: () {});
    } catch (e, st) {
      // Log instead of silently ignoring so we have diagnostics if provider
      // access or decoding fails while populating MAC cache.
      debugPrint('CreateControlUnitScreen: error populating existing MACs: $e');
      debugPrint('stack: $st');
    }

    // Build a multi-page wizard: main page + three image pages
    final totalPages = 4;

    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Edit Control Unit' : 'Add Control Unit')),
      body: SafeArea(
        child: Stack(children: [
          Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: LinearProgressIndicator(
                  value: (1.0 * (_currentPage + 1)) / totalPages,
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    // Page 0: Main details (all fields except image-pages)
                    _KeepAlive(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Form(
                          key: _pageKeys[0],
                          child: SingleChildScrollView(
                            padding: EdgeInsets.only(
                                bottom:
                                    MediaQuery.of(context).viewInsets.bottom),
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _name,
                                  enabled: !_prefilledName,
                                  decoration: const InputDecoration(
                                      labelText: 'Control Unit name'),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter name'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _controlUnitId,
                                  enabled:
                                      !_prefilledControlUnitId && !_isEditing,
                                  decoration: const InputDecoration(
                                      labelText: 'Control unit ID'),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter control unit id'
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _macAddress,
                                  enabled: !_prefilledMac,
                                  decoration: const InputDecoration(
                                      labelText: 'MAC address'),
                                  validator: (v) {
                                    final val = v?.trim() ?? '';
                                    if (val.isEmpty) return 'Enter MAC address';
                                    final norm = val
                                        .replaceAll(RegExp(r'[^A-Fa-f0-9]'), '')
                                        .toLowerCase();
                                    if (norm.isEmpty)
                                      return 'Enter valid MAC address';
                                    if (_existingMacs.isNotEmpty) {
                                      final own = widget
                                          .existingData?['macAddress']
                                          ?.toString()
                                          .replaceAll(
                                              RegExp(r'[^A-Fa-f0-9]'), '')
                                          .toLowerCase();
                                      for (final e in _existingMacs) {
                                        if (own != null &&
                                            own == e &&
                                            e == norm) continue;
                                        if (e == norm)
                                          return 'MAC address already exists';
                                        if (e.contains(norm) ||
                                            norm.contains(e))
                                          return 'MAC address too similar to existing device';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                // Sprayer dropdown + add button (mirror Tractor add)
                                const SizedBox(height: 8),
                                Consumer(builder: (context, ref, _) {
                                  final userId = ref
                                          .read(authServiceProvider)
                                          .currentUserId ??
                                      '';
                                  final eqAsync =
                                      ref.watch(sprayersProvider(userId));
                                  return eqAsync.when(
                                      data: (items) {
                                        final sprayers = items
                                            .where(
                                                (e) => e.category == 'sprayer')
                                            .toList();
                                        final dropdown =
                                            DropdownButtonFormField<String?>(
                                          value: _linkedSprayerId,
                                          decoration: const InputDecoration(
                                              labelText: 'Linked sprayer'),
                                          items: [
                                            const DropdownMenuItem(
                                                value: null,
                                                child: Text('None')),
                                            ...sprayers.map((e) => DropdownMenuItem(
                                                value: e.id,
                                                child: Text(
                                                    '${e.name}${e.controlUnitId != null ? ' (${e.controlUnitId})' : ''}')))
                                          ],
                                          onChanged: _prefilledLinkedSprayer
                                              ? null
                                              : (v) => setState(
                                                  () => _linkedSprayerId = v),
                                          validator: (v) {
                                            if (v == null || v.isEmpty)
                                              return 'Select a linked sprayer';
                                            return null;
                                          },
                                        );

                                        return Row(
                                          children: [
                                            Expanded(child: dropdown),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              tooltip: 'Add sprayer',
                                              icon: const Icon(
                                                  Icons.add_circle_outline),
                                              onPressed: () async {
                                                await Navigator.of(context)
                                                    .pushNamed(
                                                        '/create_sprayer');
                                                ref.invalidate(
                                                    sprayersProvider(userId));
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                      loading: () =>
                                          const CircularProgressIndicator(),
                                      error: (e, st) => const SizedBox());
                                }),
                                const SizedBox(height: 8),
                                // Tractor dropdown + add button
                                Consumer(builder: (context, ref, _) {
                                  final userId = ref
                                          .read(authServiceProvider)
                                          .currentUserId ??
                                      '';
                                  final eqAsync =
                                      ref.watch(tractorsProvider(userId));
                                  return eqAsync.when(
                                      data: (items) {
                                        final tractors = items
                                            .where(
                                                (e) => e.category == 'tractor')
                                            .toList();
                                        final dropdown =
                                            DropdownButtonFormField<String?>(
                                          value: _linkedTractorId,
                                          decoration: const InputDecoration(
                                              labelText: 'Linked tractor'),
                                          items: [
                                            const DropdownMenuItem(
                                                value: null,
                                                child: Text('None')),
                                            ...tractors.map((e) => DropdownMenuItem(
                                                value: e.id,
                                                child: Text(
                                                    '${e.name}${e.controlUnitId != null ? ' (${e.controlUnitId})' : ''}')))
                                          ],
                                          onChanged: _prefilledLinkedTractor
                                              ? null
                                              : (v) => setState(
                                                  () => _linkedTractorId = v),
                                          validator: (v) {
                                            if (v == null || v.isEmpty)
                                              return 'Select a linked tractor';
                                            return null;
                                          },
                                        );

                                        return Row(
                                          children: [
                                            Expanded(child: dropdown),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              tooltip: 'Add tractor',
                                              icon: const Icon(
                                                  Icons.add_circle_outline),
                                              onPressed: () async {
                                                await Navigator.of(context)
                                                    .pushNamed(
                                                        '/create_tractor');
                                                ref.invalidate(
                                                    tractorsProvider(userId));
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                      loading: () =>
                                          const CircularProgressIndicator(),
                                      error: (e, st) => const SizedBox());
                                }),
                                const SizedBox(height: 8),
                                // Plot dropdown
                                Consumer(builder: (context, ref, _) {
                                  final userId = ref
                                          .read(authServiceProvider)
                                          .currentUserId ??
                                      '';
                                  final plotsAsync = ref.watch(
                                      fm_providers.plotsListProvider(userId));
                                  return plotsAsync.when(
                                      data: (items) {
                                        return DropdownButtonFormField<String?>(
                                          value: _linkedPlotId,
                                          decoration: const InputDecoration(
                                              labelText: 'Default plot'),
                                          items: [
                                            const DropdownMenuItem(
                                                value: null,
                                                child: Text('None')),
                                            ...items.map((p) =>
                                                DropdownMenuItem(
                                                    value: p.id,
                                                    child: Text(p.name)))
                                          ],
                                          onChanged: _prefilledLinkedPlot
                                              ? null
                                              : (v) => setState(
                                                  () => _linkedPlotId = v),
                                          validator: (v) {
                                            if (v == null || v.isEmpty)
                                              return 'Select a default plot';
                                            return null;
                                          },
                                        );
                                      },
                                      loading: () =>
                                          const CircularProgressIndicator(),
                                      error: (e, st) => const SizedBox());
                                }),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  value: _sensorType,
                                  decoration: const InputDecoration(
                                      labelText: 'Sensor type'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'lidar', child: Text('LIDAR')),
                                    DropdownMenuItem(
                                        value: 'ultrasonic',
                                        child: Text('Ultrasonic')),
                                  ],
                                  onChanged: _prefilledSensorType
                                      ? null
                                      : (v) {
                                          final nv = v ?? 'lidar';
                                          setState(() {
                                            _sensorType = nv;
                                            if (_sensorType == 'lidar') {
                                              _ultrasonicDistance.clear();
                                            } else {
                                              _mountHeightOfLidar.clear();
                                              _lidarNozzleDistance.clear();
                                            }
                                          });
                                        },
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Select sensor type'
                                      : null,
                                  disabledHint: _prefilledSensorType
                                      ? Text(_sensorType.toUpperCase())
                                      : null,
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Page 1: lidar-nozzle distance (image + field)
                    _KeepAlive(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Form(
                          key: _pageKeys[1],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 200,
                                child: Image.asset(
                                  'assets/lidar_nozzle_distance.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (ctx, err, st) => const Center(
                                    child: Icon(Icons.image_not_supported,
                                        size: 48),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _lidarNozzleDistance,
                                    enabled: !_prefilledLidarNozzle,
                                    decoration: const InputDecoration(
                                        labelText:
                                            'Distance b/w sensor and nozzle center'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    validator: (v) => (v == null || v.isEmpty)
                                        ? 'Enter distance'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    value: _lidarNozzleDistanceUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'm', child: Text('m')),
                                      DropdownMenuItem(
                                          value: 'in', child: Text('in')),
                                      DropdownMenuItem(
                                          value: 'ft', child: Text('ft')),
                                    ],
                                    onChanged: (v) => setState(() =>
                                        _lidarNozzleDistanceUnit = v ?? 'm'),
                                    decoration: const InputDecoration(
                                        labelText: 'Unit'),
                                  ),
                                )
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Page 2: mount height of lidar (image + field)
                    _KeepAlive(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Form(
                          key: _pageKeys[2],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 200,
                                child: Image.asset(
                                  'assets/mount_height_lidar.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (ctx, err, st) => const Center(
                                    child: Icon(Icons.image_not_supported,
                                        size: 48),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _mountHeightOfLidar,
                                    enabled: !_prefilledMountHeight,
                                    decoration: const InputDecoration(
                                        labelText: 'Mount height of LIDAR'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    validator: (v) => null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    value: _mountHeightUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'm', child: Text('m')),
                                      DropdownMenuItem(
                                          value: 'in', child: Text('in')),
                                      DropdownMenuItem(
                                          value: 'ft', child: Text('ft')),
                                    ],
                                    onChanged: (v) => setState(
                                        () => _mountHeightUnit = v ?? 'm'),
                                    decoration: const InputDecoration(
                                        labelText: 'Unit'),
                                  ),
                                )
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Page 3: ultrasonic distance (image + field)
                    _KeepAlive(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Form(
                          key: _pageKeys[3],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 200,
                                child: Image.asset(
                                  'assets/ultrasonic_distance.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (ctx, err, st) => const Center(
                                    child: Icon(Icons.image_not_supported,
                                        size: 48),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _ultrasonicDistance,
                                    enabled: !_prefilledUltrasonic,
                                    decoration: const InputDecoration(
                                        labelText:
                                            'Distance of US sensor from center line'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    validator: (v) => null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 110,
                                  child: DropdownButtonFormField<String>(
                                    value: _ultrasonicDistanceUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'm', child: Text('m')),
                                      DropdownMenuItem(
                                          value: 'in', child: Text('in')),
                                      DropdownMenuItem(
                                          value: 'ft', child: Text('ft')),
                                    ],
                                    onChanged: (v) => setState(() =>
                                        _ultrasonicDistanceUnit = v ?? 'm'),
                                    decoration: const InputDecoration(
                                        labelText: 'Unit'),
                                  ),
                                )
                              ]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Navigation buttons
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12.0, vertical: 12.0),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            final prev = _currentPage - 1;
                            _pageController.animateToPage(prev,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut);
                          },
                          child: const Text('Back'),
                        ),
                      ),
                    if (_currentPage > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : () async {
                                // validate current page
                                final key = _pageKeys[_currentPage];
                                if (!(key.currentState?.validate() ?? false))
                                  return;
                                if (_currentPage < totalPages - 1) {
                                  final next = _currentPage + 1;
                                  _pageController.animateToPage(next,
                                      duration:
                                          const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut);
                                  return;
                                }

                                debugPrint(
                                    'CreateControlUnitScreen: Save pressed, currentPage=$_currentPage');
                                FocusScope.of(context).unfocus();
                                // validate all pages with logging
                                for (var i = 0; i < totalPages; i++) {
                                  debugPrint(
                                      'CreateControlUnitScreen: validating page $i');
                                  final k = _pageKeys[i];
                                  final valid =
                                      k.currentState?.validate() ?? false;
                                  if (!valid) {
                                    final vals = {
                                      0: _name.text,
                                      1: _lidarNozzleDistance.text,
                                      2: _mountHeightOfLidar.text,
                                      3: _ultrasonicDistance.text,
                                    };
                                    debugPrint(
                                        'CreateControlUnitScreen: page $i invalid, values=$vals');
                                    _pageController.animateToPage(i,
                                        duration:
                                            const Duration(milliseconds: 250),
                                        curve: Curves.easeInOut);
                                    return;
                                  }
                                }

                                // final save
                                setState(() => _isSaving = true);
                                final ctrl =
                                    ref.read(equipmentControllerProvider);
                                final navigator = Navigator.of(context);
                                final currentUserId =
                                    ref.read(authServiceProvider).currentUserId;
                                // Parse numeric inputs and convert from inches to
                                // meters when the corresponding unit selector is 'in'.
                                double? parsedLidar =
                                    _lidarNozzleDistance.text.isEmpty
                                        ? null
                                        : double.tryParse(
                                            _lidarNozzleDistance.text);
                                if (parsedLidar != null) {
                                  if (_lidarNozzleDistanceUnit == 'in') {
                                    parsedLidar = parsedLidar * 0.0254;
                                  } else if (_lidarNozzleDistanceUnit == 'ft') {
                                    parsedLidar = parsedLidar * 0.3048;
                                  }
                                }

                                double? parsedMount = _mountHeightOfLidar
                                        .text.isEmpty
                                    ? null
                                    : double.tryParse(_mountHeightOfLidar.text);
                                if (parsedMount != null) {
                                  if (_mountHeightUnit == 'in') {
                                    parsedMount = parsedMount * 0.0254;
                                  } else if (_mountHeightUnit == 'ft') {
                                    parsedMount = parsedMount * 0.3048;
                                  }
                                }

                                double? parsedUltra = _ultrasonicDistance
                                        .text.isEmpty
                                    ? null
                                    : double.tryParse(_ultrasonicDistance.text);
                                if (parsedUltra != null) {
                                  if (_ultrasonicDistanceUnit == 'in') {
                                    parsedUltra = parsedUltra * 0.0254;
                                  } else if (_ultrasonicDistanceUnit == 'ft') {
                                    parsedUltra = parsedUltra * 0.3048;
                                  }
                                }

                                final data = {
                                  'category': 'control_unit',
                                  'name': _name.text,
                                  'userId': currentUserId,
                                  'status': 'vacant',
                                  'controlUnitId': _controlUnitId.text.isEmpty
                                      ? null
                                      : _controlUnitId.text,
                                  'macAddress': _macAddress.text.isEmpty
                                      ? null
                                      : _macAddress.text,
                                  'linkedSprayerId': _linkedSprayerId,
                                  'linkedTractorId': _linkedTractorId,
                                  'linkedPlotId': _linkedPlotId,
                                  'lidarNozzleDistance': parsedLidar,
                                  'mountingHeight': parsedMount,
                                  'ultrasonicDistance': parsedUltra,
                                };

                                try {
                                  if (_isEditing &&
                                      (widget.existingData?.containsKey('id') ==
                                          true)) {
                                    final existingId =
                                        widget.existingData!['id']?.toString();
                                    if (existingId != null &&
                                        existingId.isNotEmpty) {
                                      await ctrl.update(existingId, data);
                                    } else {
                                      final id = DateTime.now()
                                          .millisecondsSinceEpoch
                                          .toString();
                                      data['id'] = id;
                                      await ctrl.add(data);
                                    }
                                  } else {
                                    final id = DateTime.now()
                                        .millisecondsSinceEpoch
                                        .toString();
                                    data['id'] = id;
                                    await ctrl.add(data);
                                  }

                                  if (!mounted) return;
                                  if (mounted)
                                    setState(() => _isSaving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(_isEditing
                                              ? 'Control unit updated'
                                              : 'Control unit added')));
                                  await Future.delayed(
                                      const Duration(milliseconds: 700));
                                  if (!mounted) return;
                                  navigator.pop(true);
                                } catch (e) {
                                  if (e is ApiException) {
                                    final err = ApiError.fromResponse(
                                        e.statusCode, e.body);
                                    showApiErrorSnackBar(context, err);
                                  } else {
                                    showGenericErrorSnackBar(
                                        context, e.toString());
                                  }
                                } finally {
                                  if (mounted)
                                    setState(() => _isSaving = false);
                                }
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24.0, vertical: 12.0),
                          child: Text(
                              _currentPage < totalPages - 1 ? 'Next' : 'Save'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isSaving)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
