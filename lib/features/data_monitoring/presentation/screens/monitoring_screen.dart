import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signal_strength_indicator/signal_strength_indicator.dart';
import 'package:simdaas/core/utils/error_utils.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../plot_mapping/presentation/providers/plot_providers.dart'
    as fm_providers;
import '../../../plot_mapping/data/models/plot_model.dart' as fm_models;
import '../providers/monitoring_providers.dart';
import '../../../equipments/presentation/providers/equipment_providers.dart'
    as eq_provs;
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/telemetry_service.dart';
import 'package:simdaas/core/utils/mac_utils.dart';
import 'dart:async';

class MonitoringScreen extends ConsumerStatefulWidget {
  final String? plotId;
  final String? jobId;
  final String? deviceId;
  const MonitoringScreen({super.key, this.plotId, this.jobId, this.deviceId});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends ConsumerState<MonitoringScreen> {
  List<Map<String, dynamic>> positions = [];
  TelemetryData? latestTelemetry;
  StreamSubscription<TelemetryData>? _deviceSub;
  final MapController _mapController = MapController();
  bool _outOfPlotSnackVisible = false;

  @override
  void initState() {
    super.initState();
    if (widget.deviceId != null && widget.deviceId!.isNotEmpty) {
      final svc = ref.read(telemetryServiceProvider);
      final normId = canonicalizeMac(widget.deviceId!);
      // Ensure service is subscribed (no-op if already subscribed).
      try {
        svc.subscribe(normId);
      } catch (e, st) {
        debugPrint('MonitoringScreen: subscribe error: $e');
        debugPrint('stack: $st');
      }

      // Seed positions and latest telemetry from the service snapshot if available.
      try {
        positions = svc.getPositions(normId);
      } catch (e, st) {
        debugPrint('MonitoringScreen: getPositions error: $e');
        debugPrint('stack: $st');
        positions = [];
      }
      try {
        latestTelemetry = svc.latestTelemetry[normId];
      } catch (e, st) {
        debugPrint('MonitoringScreen: latestTelemetry seed error: $e');
        debugPrint('stack: $st');
        latestTelemetry = null;
      }

      // If initial seeded telemetry indicates device is out of plot, show
      // the persistent notification after the first frame so Scaffold is
      // available.
      if (latestTelemetry != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateOutOfPlotSnack(latestTelemetry);
        });
      }

      try {
        _deviceSub = svc.deviceTelemetryStream(normId).listen((t) {
          setState(() {
            latestTelemetry = t;
            if (t.lat != null && t.lon != null) {
              positions.add(<String, dynamic>{
                'timestamp': t.timestamp.toIso8601String(),
                'lat': t.lat,
                'lon': t.lon,
                'pto': t.ptoState,
                'device_in_plot': t.deviceInPlot,
              });
            }
          });
          // Show or hide persistent out-of-plot snackbar based on payload.
          _updateOutOfPlotSnack(t);
        });
      } catch (e, st) {
        debugPrint('MonitoringScreen: deviceTelemetryStream listen error: $e');
        debugPrint('stack: $st');
      }
    }
  }

  @override
  void dispose() {
    // Hide any visible snack before leaving the screen.
    try {
      if (_outOfPlotSnackVisible)
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (e, st) {
      debugPrint('MonitoringScreen.dispose: hideCurrentSnackBar error: $e');
      debugPrint('stack: $st');
    }
    _deviceSub?.cancel();
    super.dispose();
  }

  int getSignalBars(int signalQuality) {
    if (signalQuality > -73)
      return 5;
    else if (signalQuality > -83 && signalQuality <= -73)
      return 4;
    else if (signalQuality > -93 && signalQuality <= -83)
      return 3;
    else if (signalQuality > -103 && signalQuality <= -93)
      return 2;
    else if (signalQuality > -113 && signalQuality <= -103)
      return 1;
    else
      return 0;
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    final controlUnitsAsync = ref.watch(eq_provs.controlUnitsProvider(userId));
    final plotsAsync = ref.watch(fm_providers.plotsListProvider(userId));
    final metricsAsync = ref.watch(monitoringStreamProvider(userId));

    Widget signalChip(IconData icon, String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: color.withAlpha(31),
              borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 12))
          ]),
        );

    // Determine a suitable AppBar title. If a deviceId was provided and we
    // can resolve a matching control unit, show its name; otherwise fall
    // back to the generic label.
    String? _resolvedControlUnitName;
    try {
      final cuList = controlUnitsAsync.asData?.value;
      if (widget.deviceId != null && cuList != null) {
        for (final cu in cuList) {
          try {
            final candidate =
                (cu.macAddress ?? cu.controlUnitId ?? cu.id).toString();
            if (candidate.isNotEmpty &&
                widget.deviceId != null &&
                canonicalizeMac(candidate) ==
                    canonicalizeMac(widget.deviceId!)) {
              _resolvedControlUnitName = cu.name;
              break;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Compute simple state indicators from the latest telemetry snapshot.
    final _t = latestTelemetry;
    final bool _ptoOnTop =
        _t != null && (_t.ptoState != null && _t.ptoState == 1);
    final bool _autoOnTop =
        _t != null && (_t.sprayMode != null && _t.sprayMode == 1);
    // Left/right solenoid states (used for the top-left L/R indicators)
    final bool _leftNozzleOn = _t != null &&
        (_t.leftSolenoidState != null && _t.leftSolenoidState == 1);
    final bool _rightNozzleOn = _t != null &&
        (_t.rightSolenoidState != null && _t.rightSolenoidState == 1);

    return Scaffold(
      appBar: AppBar(
          title: Row(children: [
        Text(_resolvedControlUnitName ?? 'Data Monitoring'),
        const Spacer(),
        if (latestTelemetry != null) ...[
          // GPS quality
          Builder(builder: (ctx) {
            final g = latestTelemetry!.gpsSignalQuality;
            Color col = Colors.grey;
            String lbl = '-';
            if (g != null) {
              lbl = g.toString();
              col =
                  g >= 3 ? Colors.white : (g >= 1 ? Colors.orange : Colors.red);
            }
            return signalChip(Icons.gps_fixed, lbl, col);
          }),
          const SizedBox(width: 15),
          SignalStrengthIndicator.bars(
            value: latestTelemetry!.simSignalQuality != null
                ? getSignalBars(latestTelemetry!.simSignalQuality!) / 5
                : 0,
            size: 20,
            barCount: 5,
            spacing: 0.5,
            activeColor: Colors.white,
            inactiveColor: Colors.blueGrey,
          )
        ]
      ])),
      body: plotsAsync.when(
        data: (plots) {
          if (plots.isEmpty)
            return const Center(child: Text('No plots available'));
          final plot = widget.plotId != null
              ? plots.cast<fm_models.PlotModel>().firstWhere(
                  (f) => f.id == widget.plotId,
                  orElse: () => plots.cast<fm_models.PlotModel>().first)
              : plots.cast<fm_models.PlotModel>().first;
          // final center = positions.isNotEmpty
          //     ? LatLng((positions.last['lat'] as num).toDouble(),
          //         (positions.last['lon'] as num).toDouble())
          //     : plot.polygon.first;
          final center = plot.polygon.isNotEmpty
              ? plot.polygon.first
              : LatLng((positions.last['lat'] as num).toDouble(),
                  (positions.last['lon'] as num).toDouble());
          return Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: center, initialZoom: 18.0),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                    subdomains: const ['a', 'b', 'c']),
                if (plot.polygon.isNotEmpty)
                  PolygonLayer(polygons: [
                    Polygon(
                        points: plot.polygon,
                        color: Colors.green.withAlpha(38),
                        borderColor: Colors.green,
                        borderStrokeWidth: 2.0)
                  ]),
                // If a device id was provided, render historical positions and live marker
                if (widget.deviceId != null && positions.isNotEmpty) ...[
                  // Build colored polyline segments by grouping consecutive
                  // position points that share the same color according to the
                  // device_in_plot and pto state.
                  PolylineLayer(
                      polylines:
                          _buildColoredPolylinesFromPositions(positions)),
                ],
                if (widget.deviceId != null && latestTelemetry != null)
                  MarkerLayer(markers: [
                    Marker(
                        point: LatLng(latestTelemetry!.lat ?? 0.0,
                            latestTelemetry!.lon ?? 0.0),
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on,
                            color: _markerColorForTelemetry(latestTelemetry!))),
                  ])
              ],
            ),
            // Top-right map overlay for PTO and Auto/Manual indicators
            Positioned(
              top: 12,
              // leave space on the right so the menu button can sit there
              right: 72,
              child: SafeArea(
                child: Card(
                  color: Colors.white.withAlpha(220),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 6.0),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // PTO dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: _ptoOnTop ? Colors.green : Colors.red,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      // Auto/Manual chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: _autoOnTop ? Colors.green : Colors.grey,
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(_autoOnTop ? 'A' : 'M',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),

            // Menu button just above PTO / A-M indicators with solid card behind
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: SizedBox(
                  width: 80,
                  height: 48,
                  child: Stack(children: [
                    // solid background card to ensure visibility above other overlays
                    // popup menu button centered above the solid card
                    Positioned.fill(
                      child: Center(
                        child: Card(
                          color: Colors.white,
                          elevation: 4,
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.menu, size: 18),
                            onSelected: (v) {
                              if (v == null) return;
                              // _openMonitoringView(v);
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem<String>(
                                  enabled: false,
                                  child: Text('Heatmap',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                              const PopupMenuItem(
                                  value: 'spraying_heatmap',
                                  child: Text('Spraying heat map')),
                              const PopupMenuItem(
                                  value: 'speed_heatmap',
                                  child: Text('Speed heat map')),
                              const PopupMenuDivider(),
                              const PopupMenuItem<String>(
                                  enabled: false,
                                  child: Text('Other views',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                              const PopupMenuItem(
                                  value: 'sensor_data',
                                  child: Text('Sensor data view')),
                              const PopupMenuItem(
                                  value: 'spray_on_off',
                                  child: Text('Spray on/off view')),
                              const PopupMenuItem(
                                  value: 'tank_level',
                                  child: Text('Tank level view')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),

            // Top-left L/R nozzle indicators (left/right)
            Positioned(
              top: 12,
              left: 12,
              child: SafeArea(
                child: Card(
                  color: Colors.white.withAlpha(220),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 6.0),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Left indicator (bound to telemetry)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color:
                                    _leftNozzleOn ? Colors.green : Colors.grey,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(height: 6),
                          const Text('L',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // Right indicator (bound to telemetry)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color:
                                    _rightNozzleOn ? Colors.green : Colors.grey,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(height: 6),
                          const Text('R',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ]),
                  ),
                ),
              ),
            ),

            // Overlay: Top card (nozzles + ultrasonics) and bottom controls
            Positioned.fill(
              child: metricsAsync.when(
                data: (metrics) {
                  final m = metrics[plot.id] ?? <String, dynamic>{};

                  String read(dynamic v) => v == null ? '-' : v.toString();

                  // Prefer live telemetry values when available, otherwise fall back
                  // to the metrics provider values.
                  final t = latestTelemetry;
                  final leftNozzle = t != null && t.leftSolenoidState != null
                      ? t.leftSolenoidState.toString()
                      : "-";
                  final rightNozzle = t != null && t.rightSolenoidState != null
                      ? t.rightSolenoidState.toString()
                      : "-";
                  final leftUltra = t != null && t.leftDistance != null
                      ? t.leftDistance!.toStringAsFixed(2)
                      : read(m['leftUltrasonic'] ?? m['ultraLeft']);
                  final rightUltra = t != null && t.rightDistance != null
                      ? t.rightDistance!.toStringAsFixed(2)
                      : read(m['rightUltrasonic'] ?? m['ultraRight']);
                  final coverage = t != null && t.jobCompletionPercent != null
                      ? t.jobCompletionPercent!
                      : (m['coveragePercent'] ?? m['coverage'] ?? 0).toDouble();

                  // final leftNozzle = t != null && t.leftSolenoidState != null
                  //     ? (t.leftSolenoidState == 1 ? 'On' : 'Off')
                  //     : read(m['leftNozzle'] ?? m['nozzleLeft']);
                  // final rightNozzle = t != null && t.rightSolenoidState != null
                  //     ? (t.rightSolenoidState == 1 ? 'On' : 'Off')
                  //     : read(m['rightNozzle'] ?? m['nozzleRight']);
                  // final leftUltra = t != null && t.leftDistance != null
                  //     ? t.leftDistance!.toStringAsFixed(2)
                  //     : read(m['leftUltrasonic'] ?? m['ultraLeft']);
                  // final rightUltra = t != null && t.rightDistance != null
                  //     ? t.rightDistance!.toStringAsFixed(2)
                  //     : read(m['rightUltrasonic'] ?? m['ultraRight']);
                  // final coverage =
                  //     (m['coveragePercent'] ?? m['coverage'] ?? 0).toDouble();
                  final flowRate = t != null && t.flowRate != null
                      ? t.flowRate!.toStringAsFixed(2)
                      : read(m['flowRate']);
                  final speed = t != null && t.speed != null
                      ? t.speed!.toStringAsFixed(2)
                      : read(m['tractorSpeed'] ?? m['speed']);
                  final tank = t != null && t.tankLevel != null
                      ? t.tankLevel!.toStringAsFixed(2)
                      : read(m['tankLevel']);
                  final ptoOn = t != null && t.ptoState != null
                      ? (t.ptoState == 1)
                      : ((m['ptoState'] ?? m['pto'] ?? false) == true);
                  final autoOn = t != null && t.sprayMode != null
                      ? (t.sprayMode == 1)
                      : ((m['autoMode'] ?? m['auto'] ?? false) == true);

                  return Stack(children: [
                    // (Top overlay removed - moved metrics elsewhere)

                    // Bottom overlay: progress, summary row, PTO
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: SafeArea(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          // Use a Stack so we can position a small blue dot overlapping
                          // and slightly above the card on the left side.
                          Stack(clipBehavior: Clip.none, children: [
                            Card(
                              color: Colors.white.withAlpha(242),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Progress bar row
                                      Row(children: [
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              const Text('Coverage',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.black54)),
                                              const SizedBox(height: 6),
                                              LinearProgressIndicator(
                                                  value:
                                                      (coverage.clamp(0, 100) /
                                                          100.0)),
                                              const SizedBox(height: 6),
                                              Text(
                                                  '${coverage.toStringAsFixed(1)}% covered',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ])),
                                      ]),
                                      const SizedBox(height: 12),

                                      // summary single-line row
                                      Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            _smallStat('Flow', flowRate),
                                            _smallStat('Speed', speed),
                                            _ptoSmallStat(ptoOn),
                                          ]),
                                      const SizedBox(height: 12),

                                      // PTO/Auto controls moved to AppBar; hide local toggles
                                      const SizedBox.shrink(),
                                    ]),
                              ),
                            ),
                            // Positioned blue dot that sits slightly above the left
                            // edge of the card. The negative top offset allows it to
                            // overlap above the card.
                            const Positioned(
                              left: 12,
                              top: -25,
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle),
                                ),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  ]);
                },
                loading: () => const SizedBox.shrink(),
                error: (e, st) => Positioned(
                    left: 12,
                    top: 12,
                    child: Card(
                        child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(extractErrorMessage(e))))),
              ),
            )
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text(extractErrorMessage(e))),
      ),
      floatingActionButton: widget.deviceId != null
          ? FloatingActionButton(
              heroTag: 'center_current',
              mini: true,
              onPressed: _goToCurrentPosition,
              child: const Icon(Icons.my_location),
            )
          : null,
    );
  }

  Color _markerColorForTelemetry(TelemetryData t) {
    try {
      final inPlot = t.deviceInPlot == true ||
          (t.deviceInPlot?.toString().toLowerCase() == 'true');
      final ptoOn = (t.ptoState != null && t.ptoState == 1);
      if (inPlot && ptoOn) return Colors.blue;
      if (inPlot && !ptoOn) return Colors.orange;
    } catch (e, st) {
      debugPrint('MonitoringScreen._markerColorForTelemetry error: $e');
      debugPrint('stack: $st');
    }
    return Colors.red;
  }

  void _goToCurrentPosition() {
    try {
      LatLng? target;
      if (latestTelemetry != null &&
          latestTelemetry!.lat != null &&
          latestTelemetry!.lon != null) {
        target = LatLng(latestTelemetry!.lat!, latestTelemetry!.lon!);
      } else if (positions.isNotEmpty) {
        final last = positions.last;
        target = LatLng(
            (last['lat'] as num).toDouble(), (last['lon'] as num).toDouble());
      }
      if (target != null) {
        // Keep zoom at current controller zoom if available; otherwise use 18.0
        double zoom = 18.0;
        try {
          // Try to read zoom from MapController.camera when available.
          final cam = _mapController.camera;
          zoom = cam.zoom;
        } catch (e, st) {
          debugPrint(
              'MonitoringScreen._goToCurrentPosition: camera read error: $e');
          debugPrint('stack: $st');
        }
        _mapController.move(target, zoom);
      }
    } catch (e, st) {
      debugPrint('MonitoringScreen._goToCurrentPosition error: $e');
      debugPrint('stack: $st');
    }
  }

  void _openMonitoringView(String view) {
    // Present a bottom sheet placeholder for the chosen view. Replace with
    // real implementations (charts, overlays, etc.) as needed.
    try {
      showModalBottomSheet<void>(
          context: context,
          builder: (ctx) {
            String title;
            Widget body;
            switch (view) {
              case 'spraying_heatmap':
                title = 'Spraying heat map';
                body = const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Spraying heat map view (placeholder)'),
                );
                break;
              case 'speed_heatmap':
                title = 'Speed heat map';
                body = const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Speed heat map view (placeholder)'),
                );
                break;
              case 'sensor_data':
                title = 'Sensor data view';
                body = const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Sensor data view (placeholder)'),
                );
                break;
              case 'spray_on_off':
                title = 'Spray on/off view';
                body = const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Spray on/off view (placeholder)'),
                );
                break;
              case 'tank_level':
                title = 'PTO status';
                try {
                  final ptoOn = latestTelemetry != null &&
                      (latestTelemetry!.ptoState != null &&
                          latestTelemetry!.ptoState == 1);
                  final updated = latestTelemetry?.timestamp;
                  body = Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                color: ptoOn ? Colors.green : Colors.red,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 12),
                          Text(ptoOn ? 'PTO: ON' : 'PTO: OFF',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 8),
                        if (updated != null)
                          Text('Last updated: ${updated.toLocal()}'),
                      ],
                    ),
                  );
                } catch (e) {
                  body = Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Unable to read PTO status: $e'),
                  );
                }
                break;
              default:
                title = 'View';
                body = Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Unknown view: $view'),
                );
            }

            return SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold))),
                      IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close))
                    ],
                  ),
                ),
                body,
                const SizedBox(height: 12)
              ]),
            );
          });
    } catch (e, st) {
      debugPrint('MonitoringScreen._openMonitoringView error: $e');
      debugPrint('stack: $st');
    }
  }

  // Show a persistent SnackBar when telemetry reports the device is
  // outside the plot. The SnackBar is hidden once the device reports
  // in-plot again. This function is safe to call from listeners.
  void _updateOutOfPlotSnack(TelemetryData? t) {
    if (!mounted) return;
    try {
      final isInPlot = t != null &&
          (t.deviceInPlot == true ||
              (t.deviceInPlot?.toString().toLowerCase() == 'true'));
      if (!isInPlot) {
        if (!_outOfPlotSnackVisible) {
          _outOfPlotSnackVisible = true;
          showInfoSnackBar(context, 'Device is outside the assigned plot');
        }
      } else {
        if (_outOfPlotSnackVisible) {
          try {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          } catch (e, st) {
            debugPrint('MonitoringScreen._updateOutOfPlotSnack hide error: $e');
            debugPrint('stack: $st');
          }
          _outOfPlotSnackVisible = false;
        }
      }
    } catch (e, st) {
      debugPrint('MonitoringScreen._updateOutOfPlotSnack error: $e');
      debugPrint('stack: $st');
    }
  }

  // Compute the color for a single stored position entry.
  Color _colorForPositionEntry(Map<String, dynamic> p) {
    try {
      final pto = p['pto'];
      final deviceInPlot = p['device_in_plot'];
      final ptoOn =
          (pto != null && (pto is int ? pto == 1 : pto.toString() == '1'));
      final inPlotBool = (deviceInPlot == true ||
          (deviceInPlot != null &&
              deviceInPlot.toString().toLowerCase() == 'true'));
      if (inPlotBool && ptoOn) return Colors.blue;
      if (inPlotBool && !ptoOn) return Colors.orange;
    } catch (e, st) {
      debugPrint('MonitoringScreen._colorForPositionEntry error: $e');
      debugPrint('stack: $st');
    }
    return Colors.red;
  }

  // Build a list of Polylines by grouping consecutive position points that
  // share the same color. Each resulting Polyline will be drawn with the
  // color for that segment.
  List<Polyline> _buildColoredPolylinesFromPositions(
      List<Map<String, dynamic>> pos) {
    final List<Polyline> result = [];
    if (pos.length < 2) return result;

    List<LatLng> currentPoints = [];
    Color? currentColor;

    for (var i = 0; i < pos.length; i++) {
      final p = pos[i];
      final lat = (p['lat'] as num).toDouble();
      final lon = (p['lon'] as num).toDouble();
      final color = _colorForPositionEntry(p);

      if (currentColor == null) {
        // start new segment
        currentColor = color;
        currentPoints = [LatLng(lat, lon)];
      } else if (color == currentColor) {
        currentPoints.add(LatLng(lat, lon));
      } else {
        // flush previous segment if it has at least two points
        if (currentPoints.length >= 2) {
          result.add(Polyline(
              points: List<LatLng>.from(currentPoints),
              strokeWidth: 4.0,
              color: currentColor));
        }
        // start new segment
        currentColor = color;
        currentPoints = [LatLng(lat, lon)];
      }
    }

    // flush last segment
    if (currentPoints.length >= 2 && currentColor != null) {
      result.add(Polyline(
          points: List<LatLng>.from(currentPoints),
          strokeWidth: 4.0,
          color: currentColor));
    }

    return result;
  }
}

Widget _metricBlock(String title, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 6),
      Text(value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    ]),
  );
}

Widget _smallStat(String label, String value) {
  return Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

Widget _ptoSmallStat(bool ptoOn) {
  return Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('PTO',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: ptoOn ? Colors.green : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(ptoOn ? 'ON' : 'OFF',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        )
      ],
    ),
  );
}
