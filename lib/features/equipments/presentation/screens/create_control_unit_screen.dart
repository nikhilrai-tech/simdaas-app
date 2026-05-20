import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/equipment_providers.dart';
import '../../../plot_mapping/presentation/providers/plot_providers.dart'
    as fm_providers;
import 'package:simdaas/core/services/auth_service.dart';
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
  late final List<GlobalKey<FormState>> _pageKeys;
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;
  // Unit selectors for meter inputs
  String _lidarNozzleDistanceUnit = 'm';
  String _mountHeightUnit = 'm';
  String _ultrasonicDistanceUnit = 'm';
  final _name = TextEditingController();
  final _macAddress = TextEditingController();
  String? _linkedSprayerId;
  String? _linkedTractorId;
  String? _linkedPlotId;
  final _lidarNozzleDistance = TextEditingController();
  final _mountHeightOfLidar = TextEditingController();
  final _ultrasonicDistance = TextEditingController();
  String _sensorType = '1d_lidar';
  // cache of existing MACs for quick uniqueness check (normalized)
  Set<String> _existingMacs = {};
  // flags to lock fields that were provided by QR scan
  bool _prefilledName = false;
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
    _macAddress.dispose();
    // controllers removed for dropdowns
    _lidarNozzleDistance.dispose();
    _mountHeightOfLidar.dispose();
    _ultrasonicDistance.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _prefill(TextEditingController ctrl, dynamic val, String type) {
    if (val == null) return;
    double d = double.tryParse(val.toString()) ?? 0;
    if (d == 0) {
      ctrl.text = val.toString();
      return;
    }

    // Heuristics to restore unit
    final inches = d / 0.0254;
    final feet = d / 0.3048;

    if ((inches - inches.round()).abs() < 0.0001) {
      ctrl.text = inches.round().toString();
      if (type == 'lidar') _lidarNozzleDistanceUnit = 'in';
      if (type == 'mount') _mountHeightUnit = 'in';
      if (type == 'ultra') _ultrasonicDistanceUnit = 'in';
      return;
    }
    if ((feet - feet.round()).abs() < 0.0001) {
      ctrl.text = feet.round().toString();
      if (type == 'lidar') _lidarNozzleDistanceUnit = 'ft';
      if (type == 'mount') _mountHeightUnit = 'ft';
      if (type == 'ultra') _ultrasonicDistanceUnit = 'ft';
      return;
    }

    ctrl.text = d.toString().replaceAll(RegExp(r'\.0$'), '');
  }

  void _onUnitChanged(String? newUnit, String currentUnit,
      TextEditingController ctrl, Function(String) setter) {
    if (newUnit == null || newUnit == currentUnit) return;
    double? val = double.tryParse(ctrl.text);
    if (val != null) {
      double inMeters = val;
      if (currentUnit == 'in') {
        inMeters = val * 0.0254;
      } else if (currentUnit == 'ft') {
        inMeters = val * 0.3048;
      }

      double newVal = inMeters;
      if (newUnit == 'in') {
        newVal = inMeters / 0.0254;
      } else if (newUnit == 'ft') {
        newVal = inMeters / 0.3048;
      }

      ctrl.text =
          newVal.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
    }
    setState(() => setter(newUnit));
  }

  @override
  void initState() {
    super.initState();
    _pageKeys = List.generate(4, (_) => GlobalKey<FormState>());
  }

  // Build a multi-page wizard. Visible pages depend on selected sensor type:
  // - sensor 'lidar' -> pages [0,1,2]
  // - sensor 'ultrasonic' -> pages [0,3]
  List<int> get visible {
    // Both 1D and 2D lidar use the same measurement pages (sensor-nozzle + mount height).
    return [0, 1, 2];
  }

  int get totalPages => visible.length;

  int visiblePositionOf(int pageIndex) {
    final pos = visible.indexOf(pageIndex);
    return pos < 0 ? 0 : pos;
  }

  @override
  Widget build(BuildContext context) {
    // If this screen was opened as part of the "Add Plot -> Add Control Unit"
    // guided flow, intercept back navigation and return the user to the
    // plot-creation screen instead of the previous dashboard.
    // Keep using WillPopScope (deprecated) to preserve current behavior.
    // We'll ignore deprecation until a careful replacement is implemented.
    // ignore: deprecated_member_use
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
    //   name (primary/identity field). Other fields will
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

      // When editing, only lock name. For QR-prefill
      // (not editing) retain the previous per-field prefill locking.
      if (_isEditing) {
        if (_name.text.isNotEmpty) _prefilledName = true;
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
          final st = m['sensorType'] as String;
          // Migrate legacy 'lidar'/'ultrasonic' values to new names
          _sensorType = (st == 'lidar' || st == '1d_lidar') ? '1d_lidar' : '2d_lidar';
        }
        if (m.containsKey('lidarNozzleDistance') &&
            m['lidarNozzleDistance'] != null) {
          _prefill(
              _lidarNozzleDistance, m['lidarNozzleDistance'], 'lidar');
        }
        if (m.containsKey('mountingHeight') && m['mountingHeight'] != null) {
          _prefill(_mountHeightOfLidar, m['mountingHeight'], 'mount');
        }
        if (m.containsKey('ultrasonicDistance') &&
            m['ultrasonicDistance'] != null) {
          _prefill(_ultrasonicDistance, m['ultrasonicDistance'], 'ultra');
        }
      } else {
        // Not editing: treat values as QR-prefilled and lock fields that
        // were provided by the scanner (existing behavior).
        if (m.containsKey('name') &&
            (m['name'] as String?)?.isNotEmpty == true) {
          _name.text = m['name'] as String;
          _prefilledName = true;
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
          final st = m['sensorType'] as String;
          _sensorType = (st == 'lidar' || st == '1d_lidar') ? '1d_lidar' : '2d_lidar';
          _prefilledSensorType = true;
        }
        if (m.containsKey('lidarNozzleDistance') &&
            m['lidarNozzleDistance'] != null) {
          _prefill(
              _lidarNozzleDistance, m['lidarNozzleDistance'], 'lidar');
          _prefilledLidarNozzle = true;
        }
        if (m.containsKey('mountingHeight') && m['mountingHeight'] != null) {
          _prefill(_mountHeightOfLidar, m['mountingHeight'], 'mount');
          _prefilledMountHeight = true;
        }
        if (m.containsKey('ultrasonicDistance') &&
            m['ultrasonicDistance'] != null) {
          _prefill(_ultrasonicDistance, m['ultrasonicDistance'], 'ultra');
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
                  value: (1.0 * (visiblePositionOf(_currentPage) + 1)) /
                      totalPages,
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
                                      labelText: 'Control Unit name',
                                      hintText: 'Control Unit name'),
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Enter name'
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                  const SizedBox(height: 8),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _macAddress,
                                  enabled: !_prefilledMac,
                                  decoration: const InputDecoration(
                                      labelText: 'MAC address',
                                      hintText: 'MAC address'),
                                  validator: (v) {
                                    final val = v?.trim() ?? '';
                                    if (val.isEmpty) return 'Enter MAC address';
                                    final norm = val
                                        .replaceAll(RegExp(r'[^A-Fa-f0-9]'), '')
                                        .toLowerCase();
                                    if (norm.isEmpty) {
                                      return 'Enter valid MAC address';
                                    }
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
                                            e == norm) {
                                          continue;
                                        }
                                        if (e == norm) {
                                          return 'MAC address already exists';
                                        }
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
                                          initialValue: _linkedSprayerId,
                                          decoration: const InputDecoration(
                                              labelText: 'Default sprayer'),
                                          items: [
                                            const DropdownMenuItem(
                                                value: null,
                                                child: Text('None')),
                                            ...sprayers.map((e) => DropdownMenuItem(
                                                value: e.id,
                                                child: Text(e.name)))
                                          ],
                                          onChanged: _prefilledLinkedSprayer
                                              ? null
                                              : (v) => setState(
                                                  () => _linkedSprayerId = v),
                                          validator: (v) {
                                            if (v == null || v.isEmpty) {
                                              return 'Select a linked sprayer';
                                            }
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
                                          initialValue: _linkedTractorId,
                                          decoration: const InputDecoration(
                                              labelText: 'Linked tractor'),
                                          items: [
                                            const DropdownMenuItem(
                                                value: null,
                                                child: Text('None')),
                                            ...tractors.map((e) => DropdownMenuItem(
                                                value: e.id,
                                                child: Text(e.name)))
                                          ],
                                          onChanged: _prefilledLinkedTractor
                                              ? null
                                              : (v) => setState(
                                                  () => _linkedTractorId = v),
                                          validator: (v) {
                                            if (v == null || v.isEmpty) {
                                              return 'Select a linked tractor';
                                            }
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
                                          initialValue: _linkedPlotId,
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
                                            if (v == null || v.isEmpty) {
                                              return 'Select a default plot';
                                            }
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
                                  initialValue: _sensorType,
                                  decoration: const InputDecoration(
                                      labelText: 'Sensor type'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: '1d_lidar',
                                        child: Text('1D Lidar')),
                                    DropdownMenuItem(
                                        value: '2d_lidar',
                                        child: Text('2D Lidar')),
                                  ],
                                  onChanged: _prefilledSensorType
                                      ? null
                                      : (v) {
                                          setState(() => _sensorType = v ?? '1d_lidar');
                                        },
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Select sensor type'
                                      : null,
                                  disabledHint: _prefilledSensorType
                                      ? Text(_sensorType == '1d_lidar'
                                          ? '1D Lidar'
                                          : '2D Lidar')
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
                                  'assets/control_unit/lidar_nozzle_distance.png',
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
                                        hintText:
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
                                    initialValue: _lidarNozzleDistanceUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'm', child: Text('m')),
                                      DropdownMenuItem(
                                          value: 'in', child: Text('in')),
                                      DropdownMenuItem(
                                          value: 'ft', child: Text('ft')),
                                    ],
                                    onChanged: (v) => _onUnitChanged(
                                        v,
                                        _lidarNozzleDistanceUnit,
                                        _lidarNozzleDistance,
                                        (u) => _lidarNozzleDistanceUnit = u),
                                    decoration:
                                        const InputDecoration(hintText: 'Unit'),
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
                                  'assets/control_unit/mount_height_lidar.png',
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
                                        hintText: 'Mount height of LIDAR'),
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
                                    initialValue: _mountHeightUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'm', child: Text('m')),
                                      DropdownMenuItem(
                                          value: 'in', child: Text('in')),
                                      DropdownMenuItem(
                                          value: 'ft', child: Text('ft')),
                                    ],
                                    onChanged: (v) => _onUnitChanged(
                                        v,
                                        _mountHeightUnit,
                                        _mountHeightOfLidar,
                                        (u) => _mountHeightUnit = u),
                                    decoration:
                                        const InputDecoration(hintText: 'Unit'),
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
                                  'assets/control_unit/ultrasonic_distance.png',
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
                                        hintText:
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
                                    initialValue: _ultrasonicDistanceUnit,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'm', child: Text('m')),
                                      DropdownMenuItem(
                                          value: 'in', child: Text('in')),
                                      DropdownMenuItem(
                                          value: 'ft', child: Text('ft')),
                                    ],
                                    onChanged: (v) => _onUnitChanged(
                                        v,
                                        _ultrasonicDistanceUnit,
                                        _ultrasonicDistance,
                                        (u) => _ultrasonicDistanceUnit = u),
                                    decoration:
                                        const InputDecoration(hintText: 'Unit'),
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
                    if (visiblePositionOf(_currentPage) > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            final pos = visiblePositionOf(_currentPage);
                            final prev = visible[pos - 1];
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
                                if (!(key.currentState?.validate() ?? false)) {
                                  return;
                                }
                                final pos = visiblePositionOf(_currentPage);
                                if (pos < totalPages - 1) {
                                  final next = visible[pos + 1];
                                  _pageController.animateToPage(next,
                                      duration:
                                          const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut);
                                  return;
                                }

                                debugPrint(
                                    'CreateControlUnitScreen: Save pressed, currentPage=$_currentPage');
                                FocusScope.of(context).unfocus();
                                // validate only visible pages with logging
                                for (final i in visible) {
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
                                  if (mounted) {
                                    setState(() => _isSaving = false);
                                  }
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
                                  if (mounted) {
                                    setState(() => _isSaving = false);
                                  }
                                }
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24.0, vertical: 12.0),
                          child: Text(
                              visiblePositionOf(_currentPage) < totalPages - 1
                                  ? 'Next'
                                  : 'Save'),
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
