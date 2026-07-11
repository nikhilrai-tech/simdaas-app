import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:simdaas/core/services/api_exception.dart';
import 'package:simdaas/core/utils/api_error.dart';
import 'package:simdaas/features/auth/presentation/providers/users_providers.dart';
import '../../domain/entities/equipment.dart';
import '../providers/equipment_providers.dart';
import 'package:simdaas/features/plot_mapping/presentation/providers/plot_providers.dart';
import 'create_equipment_screen.dart';
import 'create_control_unit_screen.dart';
import 'create_sprayer_screen.dart';
import 'create_tractor_screen.dart';
import 'package:simdaas/features/firmware_update/presentation/screens/firmware_update_workspace_screen.dart';

class EquipmentDetailsScreen extends ConsumerStatefulWidget {
  final EquipmentEntity equipment;
  final bool readOnly;
  const EquipmentDetailsScreen(
      {super.key, required this.equipment, this.readOnly = false});

  @override
  ConsumerState<EquipmentDetailsScreen> createState() =>
      _EquipmentDetailsScreenState();
}

class _EquipmentDetailsScreenState
    extends ConsumerState<EquipmentDetailsScreen> {
  late EquipmentEntity displayedEquipment;
  bool _demoOn = false;

  String _ownerDisplay(String? userField) {
    if (userField == null) return '-';
    final raw = userField.trim();

    // Try strict JSON decode if the string contains a JSON-like object
    if (raw.contains('{') && raw.contains('}')) {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start < end) {
        final body = raw.substring(start, end + 1);
        try {
          final m = json.decode(body) as Map<String, dynamic>;
          final val = m['username'] ?? m['name'] ?? m['user'] ?? m['id'];
          if (val != null) return val.toString();
        } catch (e, st) {
          debugPrint(
              'EquipmentDetailsScreen._ownerDisplay JSON parse error: $e');
          debugPrint('stack: $st');
          // fall back to relaxed parsing
        }
      }
    }

    // Relaxed extraction: look for username: value or username = value patterns
    final unameRe = RegExp("username\\s*[:=]\\s*['\\\"]?([A-Za-z0-9_.@\\-]+)",
        caseSensitive: false);
    final unameMatch = unameRe.firstMatch(raw);
    if (unameMatch != null) return unameMatch.group(1)!.trim();

    // fallback: try name, user, then id
    final altRe = RegExp(
        "(?:name|user)\\s*[:=]\\s*['\\\"]?([A-Za-z0-9_.@\\-]+)",
        caseSensitive: false);
    final altMatch = altRe.firstMatch(raw);
    if (altMatch != null) return altMatch.group(1)!.trim();

    final idRe =
        RegExp("\\bid\\s*[:=]\\s*([0-9A-Za-z_\\-]+)", caseSensitive: false);
    final idMatch = idRe.firstMatch(raw);
    if (idMatch != null) return idMatch.group(1)!.trim();

    // final fallback: more permissive capture until comma or closing brace
    final looseRe =
        RegExp(r"username\s*[:=]\s*([^,}\n]+)", caseSensitive: false);
    final looseMatch = looseRe.firstMatch(raw);
    if (looseMatch != null) {
      var v = looseMatch.group(1)!.trim();
      // strip wrapping quotes if present
      if ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      return v;
    }

    // nothing found — return the raw string so UI shows something instead of crashing
    return raw;
  }

  // Resolve equipment name (sprayer/tractor/control unit) from a provider list
  String _resolveEquipmentName(
      String? id, AsyncValue<List<EquipmentEntity>> listAsync) {
    if (id == null) return '-';
    return listAsync.maybeWhen(
        data: (items) {
          final found = items.where((e) => e.id == id).toList();
          if (found.isNotEmpty) return found.first.name;
          return _extractNameFromLinked(id, {
                for (var e in items) e.id: e.name,
              }) ??
              id;
        },
        orElse: () =>
            _extractNameFromLinked(id, {
              for (var e in listAsync.value ?? []) e.id: e.name,
            }) ??
            id);
  }

  String? _extractNameFromLinked(String linked, Map<String, String> plotMap) {
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
      } catch (e, st) {
        debugPrint(
            'EquipmentDetailsScreen._extractNameFromLinked JSON parse error: $e');
        debugPrint('stack: $st');
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

  // Resolve plot name from plots provider
  String _resolvePlotName(String? id, AsyncValue<List<dynamic>> plotsAsync) {
    if (id == null) return '-';
    return plotsAsync.maybeWhen(
        data: (items) {
          try {
            final found = items.where((p) => p.id == id).toList();
            if (found.isNotEmpty) return found.first.name;
          } catch (e, st) {
            debugPrint(
                'EquipmentDetailsScreen._resolvePlotName lookup error: $e');
            debugPrint('stack: $st');
          }
          return _extractNameFromLinked(id, {
                for (var e in items) e.id: e.name,
              }) ??
              id;
        },
        orElse: () =>
            _extractNameFromLinked(id, {
              for (var e in plotsAsync.value ?? []) e.id: e.name,
            }) ??
            id);
  }

  @override
  void initState() {
    super.initState();
    displayedEquipment = widget.equipment;
  }

  @override
  Widget build(BuildContext context) {
    // Determine which user id to use when fetching lists. Prefer the
    // authenticated user's id so providers are keyed consistently.
    final currentUserId = ref.read(authServiceProvider).currentUserId ??
        widget.equipment.userId ??
        'demo_user';
    // watch other equipment/plot lists so we can display names instead of ids
    final sprayersAsync = ref.watch(sprayersProvider(currentUserId));
    final tractorsAsync = ref.watch(tractorsProvider(currentUserId));
    final plotsAsync = ref.watch(plotsListProvider(currentUserId));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // If demo is ON, restore original config before leaving.
        if (_demoOn &&
            displayedEquipment.category.toLowerCase() == 'control_unit') {
          try {
            await ref
                .read(equipmentControllerProvider)
                .pushDemoConfig(displayedEquipment.id, demo: false);
          } catch (_) {}
          if (mounted) setState(() => _demoOn = false);
        }
        if (context.mounted) Navigator.of(context).pop(result);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(displayedEquipment.name),
        actions: widget.readOnly
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    // pass the equipment as a raw map to the create/edit screen
                    final existing = {
                      'id': displayedEquipment.id,
                      'category': displayedEquipment.category,
                      'name': displayedEquipment.name,
                      'userId': displayedEquipment.userId,
                      'status': displayedEquipment.status,
                      'mountingHeight': displayedEquipment.mountingHeight,
                      'lidarNozzleDistance':
                          displayedEquipment.lidarNozzleDistance,
                      'ultrasonicDistance':
                          displayedEquipment.ultrasonicDistance,
                      'wheelDiameter': displayedEquipment.wheelDiameter,
                      'screwsInWheel': displayedEquipment.screwsInWheel,
                      'nozzleCount': displayedEquipment.nozzleCount,
                      'tankCapacity': displayedEquipment.tankCapacity,
                      'axleLength': displayedEquipment.axleLength,
                      'hingeToAxle': displayedEquipment.hingeToAxle,
                      'hingeToNozzle': displayedEquipment.hingeToNozzle,
                      'hingeToControlUnit':
                          displayedEquipment.hingeToControlUnit,
                      'macAddress': displayedEquipment.macAddress,
                      'linkedSprayerId': displayedEquipment.linkedSprayerId,
                      'linkedTractorId': displayedEquipment.linkedTractorId,
                      'linkedPlotId': displayedEquipment.linkedPlotId,
                      'rightFrontOffset': displayedEquipment.rightFrontOffset,
                      'rightBackOffset': displayedEquipment.rightBackOffset,
                      'leftFrontOffset': displayedEquipment.leftFrontOffset,
                      'leftBackOffset': displayedEquipment.leftBackOffset,
                      'flowPulseCount': displayedEquipment.flowPulseCount,
                    };
                    // Route to the appropriate editor. Use the specialized
                    // control unit editor so the control unit identifier is
                    // treated as non-editable when editing an existing unit.
                    // Route to the appropriate editor. Capture the result so
                    // we only invalidate providers when the editor signals
                    // a successful change (it pops `true`).
                    final cat = displayedEquipment.category.toLowerCase();
                    final result = cat == 'control_unit'
                        ? await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CreateControlUnitScreen(
                                existingData: existing)))
                        : cat == 'sprayer'
                            ? await Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => CreateSprayerScreen(
                                        existingData: existing)))
                            : cat == 'tractor'
                                ? await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => CreateTractorScreen(
                                            existingData: existing)))
                                : await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => CreateEquipmentScreen(
                                            existingData: existing)));

                    if (result == true) {
                      ref.invalidate(equipmentsListProvider(currentUserId));
                      switch (displayedEquipment.category.toLowerCase()) {
                        case 'control_unit':
                          ref.invalidate(controlUnitsProvider(currentUserId));
                          break;
                        case 'sprayer':
                          ref.invalidate(sprayersProvider(currentUserId));
                          break;
                        case 'tractor':
                          ref.invalidate(tractorsProvider(currentUserId));
                          break;
                        default:
                          break;
                      }

                      try {
                        final repo = ref.read(equipmentRepoProvider);
                        final fresh = await repo.getEquipments(currentUserId);
                        final found = fresh.firstWhere(
                            (e) => e.id == displayedEquipment.id,
                            orElse: () => displayedEquipment);
                        setState(() => displayedEquipment = found);
                      } catch (e, st) {
                        // Log fetch errors for diagnostics; provider
                        // invalidation will still update the UI when ready.
                        debugPrint(
                            'EquipmentDetailsScreen: failed to fetch fresh equipment: $e');
                        debugPrint('stack: $st');
                      }
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                              title: const Text('Delete equipment'),
                              content:
                                  Text('Delete ${displayedEquipment.name}?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel')),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('Delete')),
                              ],
                            ));
                    if (ok == true) {
                      final ctrl = ref.read(equipmentControllerProvider);
                      try {
                        await ctrl.delete(displayedEquipment.id,
                            category: displayedEquipment.category);
                        // Use the signed-in user's id when invalidating providers
                        // because list providers are keyed by the current user.
                        ref.invalidate(equipmentsListProvider(currentUserId));
                        switch (displayedEquipment.category.toLowerCase()) {
                          case 'control_unit':
                            ref.invalidate(controlUnitsProvider(currentUserId));
                            break;
                          case 'sprayer':
                            ref.invalidate(sprayersProvider(currentUserId));
                            break;
                          case 'tractor':
                            ref.invalidate(tractorsProvider(currentUserId));
                            break;
                          default:
                            break;
                        }

                        if (!context.mounted) return;
                        Navigator.of(context).pop(true);
                        showSuccessSnackBar(context, 'Equipment deleted');
                      } catch (err) {
                        if (!context.mounted) return;
                        // Present API errors in a user-friendly way when available.
                        if (err is ApiException) {
                          final apiErr =
                              ApiError.fromResponse(err.statusCode, err.body);
                          showApiErrorSnackBar(context, apiErr,
                              isWarning: true);
                        } else {
                          showGenericErrorSnackBar(context, 'Delete failed',
                              isWarning: true);
                        }
                      }
                    }
                  },
                )
              ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeroCard(context),
            const SizedBox(height: 12),
            _buildMetaCard(context, currentUserId),
            const SizedBox(height: 12),
            _buildSpecsCard(context, sprayersAsync, tractorsAsync, plotsAsync),
            if (displayedEquipment.category.toLowerCase() == 'control_unit') ...[
              const SizedBox(height: 16),
              _DemoModeToggle(
                equipmentId: displayedEquipment.id,
                value: _demoOn,
                onChanged: (v) => setState(() => _demoOn = v),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    ), // Scaffold
    ); // PopScope
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtNum(num? v) {
    if (v == null) return '-';
    final d = v.toDouble();
    if (d == d.truncateToDouble()) return d.toStringAsFixed(0);
    final s = d.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    final local = dt.toLocal();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $h:$m';
  }

  Color _categoryColor(BuildContext context) {
    final cat = displayedEquipment.category.toLowerCase();
    if (cat == 'control_unit') return Colors.blue;
    if (cat == 'sprayer') return Colors.green;
    if (cat == 'tractor') return Colors.orange;
    return Theme.of(context).colorScheme.primary;
  }

  String _categoryLabel() {
    switch (displayedEquipment.category.toLowerCase()) {
      case 'control_unit': return 'Control Unit';
      case 'sprayer': return 'Sprayer';
      case 'tractor': return 'Tractor';
      default: return displayedEquipment.category;
    }
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  Widget _buildHeroCard(BuildContext context) {
    final color = _categoryColor(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                displayedEquipment.category.toLowerCase() == 'control_unit'
                    ? Icons.router_outlined
                    : displayedEquipment.category.toLowerCase() == 'sprayer'
                        ? Icons.water_drop_outlined
                        : Icons.agriculture_outlined,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayedEquipment.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Chip(
                    label: Text(
                      _categoryLabel(),
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: color.withAlpha(25),
                    side: BorderSide(color: color.withAlpha(80)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaCard(BuildContext context, String currentUserId) {
    final muted = Theme.of(context).colorScheme.onSurface.withAlpha(140);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Owner row
            if (displayedEquipment.userId == null)
              _iconRow(context, Icons.person_outline, 'Owner', '-', muted)
            else
              ref.watch(userByIdProvider(displayedEquipment.userId!)).when(
                data: (u) {
                  final ownerName = u != null
                      ? (u['username'] ?? u['name'] ?? u['email'] ??
                              displayedEquipment.userId).toString()
                      : _ownerDisplay(displayedEquipment.userId);
                  return _iconRow(context, Icons.person_outline, 'Owner', ownerName, muted);
                },
                loading: () => _iconRow(context, Icons.person_outline, 'Owner', '…', muted),
                error: (_, __) => _iconRow(context, Icons.person_outline, 'Owner',
                    _ownerDisplay(displayedEquipment.userId), muted),
              ),
            if (displayedEquipment.createdAt != null) ...[
              const Divider(height: 1),
              _iconRow(context, Icons.calendar_today_outlined, 'Created',
                  _fmtDate(displayedEquipment.createdAt), muted),
            ],
            if (displayedEquipment.updatedAt != null) ...[
              const Divider(height: 1),
              _iconRow(context, Icons.update_outlined, 'Updated',
                  _fmtDate(displayedEquipment.updatedAt), muted),
            ],
            if (displayedEquipment.category.toLowerCase() == 'control_unit') ...[
              const Divider(height: 1),
              _buildFirmwareRow(context, muted),
            ],
          ],
        ),
      ),
    );
  }

  /// OTA firmware update (RFC-004) — Firmware Version row + "Check Update"
  /// button, additive to the existing meta card above.
  Widget _buildFirmwareRow(BuildContext context, Color muted) {
    final dbVersion = displayedEquipment.firmwareVersion ?? '1.0.0';
    final availableVersion = displayedEquipment.firmwareAvailableVersion;
    final updateAvailable =
        availableVersion != null && availableVersion != dbVersion;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(Icons.memory_outlined, size: 18, color: muted),
          const SizedBox(width: 10),
          Text('Firmware Version  ', style: TextStyle(color: muted, fontSize: 13)),
          Expanded(
            child: Text(
              dbVersion,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (updateAvailable) ...[
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () {
                final mac = displayedEquipment.macAddress;
                if (mac == null || mac.isEmpty) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FirmwareUpdateWorkspaceScreen(
                      controlUnitId: displayedEquipment.id,
                      macAddress: mac,
                      deviceName: displayedEquipment.name,
                    ),
                  ),
                );
              },
              child: const Text('Check Update'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecsCard(
    BuildContext context,
    AsyncValue<List<EquipmentEntity>> sprayersAsync,
    AsyncValue<List<EquipmentEntity>> tractorsAsync,
    AsyncValue<List<dynamic>> plotsAsync,
  ) {
    final cat = displayedEquipment.category.toLowerCase();
    final rows = <Widget>[];

    if (cat == 'sprayer') {
      rows.addAll([
        _specRow(context, 'Wheel diameter', '${_fmtNum(displayedEquipment.wheelDiameter)} m'),
        _specRow(context, 'Screws / nuts in wheel', '${displayedEquipment.screwsInWheel ?? '-'}'),
        _specRow(context, 'Axle length', '${_fmtNum(displayedEquipment.axleLength)} m'),
        _specRow(context, 'Number of nozzles', '${displayedEquipment.nozzleCount ?? '-'}'),
        _specRow(context, 'Tank capacity', '${_fmtNum(displayedEquipment.tankCapacity)} L'),
        _specRow(context, 'Hinge → Axle', '${_fmtNum(displayedEquipment.hingeToAxle)} m'),
        _specRow(context, 'Hinge → Nozzle', '${_fmtNum(displayedEquipment.hingeToNozzle)} m'),
        _specRow(context, 'Hinge → Control unit', '${_fmtNum(displayedEquipment.hingeToControlUnit)} m'),
      ]);
    } else if (cat == 'tractor') {
      rows.addAll([
        _specRow(context, 'Wheel diameter', '${_fmtNum(displayedEquipment.wheelDiameter)} m'),
        _specRow(context, 'Screws in wheel', '${displayedEquipment.screwsInWheel ?? '-'}'),
        _specRow(context, 'Axle length', '${_fmtNum(displayedEquipment.axleLength)} m'),
      ]);
    } else if (cat == 'control_unit') {
      rows.addAll([
        _specRow(context, 'MAC address', displayedEquipment.macAddress ?? '-'),
        _specRow(context, 'Linked sprayer',
            _resolveEquipmentName(displayedEquipment.linkedSprayerId, sprayersAsync)),
        _specRow(context, 'Linked tractor',
            _resolveEquipmentName(displayedEquipment.linkedTractorId, tractorsAsync)),
        _specRow(context, 'Linked plot',
            _resolvePlotName(displayedEquipment.linkedPlotId, plotsAsync)),
        _specRow(context, 'Distance sensor → nozzle',
            '${_fmtNum(displayedEquipment.lidarNozzleDistance)} m'),
        _specRow(context, 'Lidar mounting height',
            '${_fmtNum(displayedEquipment.mountingHeight)} m'),
        _specRow(context, 'Ultrasonic distance',
            displayedEquipment.ultrasonicDistance != null
                ? '${_fmtNum(displayedEquipment.ultrasonicDistance)} m'
                : '-'),
        _specRow(context, 'Right front offset',
            '${_fmtNum(displayedEquipment.rightFrontOffset ?? 0)} m'),
        _specRow(context, 'Right back offset',
            '${_fmtNum(displayedEquipment.rightBackOffset ?? 0)} m'),
        _specRow(context, 'Left front offset',
            '${_fmtNum(displayedEquipment.leftFrontOffset ?? 0)} m'),
        _specRow(context, 'Left back offset',
            '${_fmtNum(displayedEquipment.leftBackOffset ?? 0)} m'),
        _specRow(context, 'Flow pulse count',
            '${_fmtNum(displayedEquipment.flowPulseCount ?? 0)}'),
      ]);
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (int i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i < rows.length - 1) children.add(const Divider(height: 1));
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Text(
                'Specifications',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
              ),
            ),
            const Divider(height: 1),
            ...children,
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _iconRow(BuildContext context, IconData icon, String label,
      String value, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 10),
          Text('$label  ', style: TextStyle(color: muted, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _specRow(BuildContext context, String label, String value) {
    final muted = Theme.of(context).colorScheme.onSurface.withAlpha(140);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: muted)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoModeToggle extends ConsumerStatefulWidget {
  final String equipmentId;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DemoModeToggle({
    required this.equipmentId,
    required this.value,
    required this.onChanged,
  });

  @override
  ConsumerState<_DemoModeToggle> createState() => _DemoModeToggleState();
}

class _DemoModeToggleState extends ConsumerState<_DemoModeToggle> {
  bool _loading = false;

  Future<void> _toggle(bool value) async {
    setState(() => _loading = true);
    try {
      await ref
          .read(equipmentControllerProvider)
          .pushDemoConfig(widget.equipmentId, demo: value);
      widget.onChanged(value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Demo config error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Demo Mode',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (_loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: widget.value,
                onChanged: _toggle,
              ),
          ],
        ),
      ),
    );
  }
}
