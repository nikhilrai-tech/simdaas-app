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
import '../../../plot_mapping/domain/entities/plot.dart';
import '../providers/monitoring_providers.dart';
import '../../../equipments/presentation/providers/equipment_providers.dart'
    as eq_provs;
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/telemetry_service.dart';
import 'package:simdaas/core/utils/mac_utils.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:simdaas/core/services/connectivity_service.dart';
import '../../../reports/presentation/providers/session_providers.dart';

class MonitoringScreen extends ConsumerStatefulWidget {
  final String? plotId;
  final String? jobId;
  final String? deviceId;
  const MonitoringScreen({super.key, this.plotId, this.jobId, this.deviceId});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends ConsumerState<MonitoringScreen> {
  // Ignore telemetry for N minutes after a manual end (belt-and-suspenders
  // in case the WS event arrives late).
  final Map<String, DateTime> _ignoredUntil = {};

  bool _isDemoMode = false;
  Timer? _demoTimer;
  HeatmapType _selectedHeatmap = HeatmapType.gps;
  List<Map<String, dynamic>> positions = [];
  TelemetryData? latestTelemetry;
  StreamSubscription<TelemetryData>? _deviceSub;
  bool _showTankOverlay = false;
  bool _showSolenoidOverlay = false;
  bool _showSensorOverlay = false;
  final MapController _mapController = MapController();
  bool _outOfPlotSnackVisible = false;

  // ── Cooldown state ───────────────────────────────────────────────────────
  CooldownState? _cooldownState;
  StreamSubscription<CooldownState>? _cooldownSub;
  // Ticks every second to refresh the MM:SS countdown label.
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('MonitoringScreen: Initializing. jobId=${widget.jobId}, deviceId=${widget.deviceId}');
    
    // Refresh providers to ensure we have the latest session state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(authServiceProvider).currentUserId ?? 'demo_user';
      ref.invalidate(eq_provs.controlUnitsProvider(userId));
      ref.invalidate(activeSessionsListProvider);
    });

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
          // Mandatory ignore check: if we manually ended the session recently,
          // ignore any incoming telemetry for 2 minutes.
          final ignoreTime = _ignoredUntil[normId];
          if (ignoreTime != null && DateTime.now().isBefore(ignoreTime)) {
            // debugPrint('MonitoringScreen: Ignoring telemetry for $normId (manual end cooldown)');
            return;
          }

          if (!mounted) return;

          setState(() {
            latestTelemetry = t;
            if (t.lat != null && t.lon != null) {
              positions.add(<String, dynamic>{
                'timestamp': t.timestamp.toIso8601String(),
                'lat': t.lat,
                'lon': t.lon,
                'pto': t.ptoState,
                'device_in_plot': t.deviceInPlot,
                'speed': t.speed,
                'flow_rate': t.flowRate,
                'spray_mode': t.sprayMode,
              });
            }
          });
          // Auto-update UI when telemetry arrives (handled by setState above)
          // Show or hide persistent out-of-plot snackbar based on payload.
          _updateOutOfPlotSnack(t);
        });

        // Monitor online status to clear UI when device goes offline
        ref.listenManual(deviceOnlineProvider(normId), (previous, next) {
          if (next == false && latestTelemetry != null) {
            debugPrint('MonitoringScreen: Device $normId gone offline - clearing UI');
            setState(() {
              latestTelemetry = null;
              positions.clear();
            });
          }
        });
      } catch (e, st) {
        debugPrint('MonitoringScreen: deviceTelemetryStream listen error: $e');
        debugPrint('stack: $st');
      }

      // ── Subscribe to cooldown / lifecycle status events ──────────────
      // Seed from existing state (in case cooldown started before screen mounted).
      final existing = svc.getCooldownState(normId);
      if (existing != null) {
        _cooldownState = existing;
        _startCountdownTimer();
      }
      _cooldownSub = svc.deviceCooldownStream(normId).listen((state) {
        if (!mounted) return;
        setState(() => _cooldownState = state);
        if (state.isInCooldown) {
          _startCountdownTimer();
        } else {
          _stopCountdownTimer();
          if (state.status == DeviceLifecycleStatus.offline &&
              state.reportId != null) {
            // Report is ready — show a snackbar prompt
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Report generated! Tap to view.'),
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(
                    label: 'View',
                    onPressed: () {
                      // Navigate to reports list
                      Navigator.of(context).pushNamed('/reports');
                    },
                  ),
                ));
              }
            });
          }
        }
      });
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {}); // rebuild to update MM:SS label
      if ((_cooldownState?.secondsRemaining ?? 0) <= 0) {
        _stopCountdownTimer();
      }
    });
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _deviceSub?.cancel();
    _cooldownSub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }


  void _startDemo() {
    _demoTimer?.cancel();
    // Simulate a starting point if we have none
    double lat = 18.5204;
    double lon = 73.8567;
    if (positions.isNotEmpty) {
      lat = (positions.last['lat'] as num).toDouble();
      lon = (positions.last['lon'] as num).toDouble();
    }
    double angle = 0.0;

    _demoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      angle += 0.1;
      // Move in a small circle-ish path
      lat += 0.00002 * math.cos(angle);
      lon += 0.00003 * math.sin(angle);

      final plot = ref.read(fm_providers.plotByIdProvider(widget.plotId ?? '')).valueOrNull;
      final locallyInPlot = _isPointInPolygon(LatLng(lat, lon), plot?.polygon ?? []);

      final t = TelemetryData(
        deviceId: widget.deviceId ?? 'demo_device',
        timestamp: DateTime.now(),
        lat: lat,
        lon: lon,
        speed: 4.5 + math.sin(angle) * 2,
        flowRate: 15.0 + math.cos(angle) * 5,
        ptoState: (angle % 6.28) > 3.14 ? 1 : 0,
        sprayMode: (angle % 12.56) > 6.28 ? 1 : 0,
        deviceInPlot: locallyInPlot,
        plot: widget.plotId,
        leftDistance: 1.2 + math.sin(angle * 2) * 0.5,
        rightDistance: 1.1 + math.cos(angle * 2) * 0.5,
        leftDensity: 0.8 + math.sin(angle) * 0.2,
        rightDensity: 0.85 + math.cos(angle) * 0.15,
        tankLevel: (80.0 - (timer.tick / 10)).clamp(0.0, 100.0),
        gpsSignalQuality: 3,
        simSignalQuality: -75,
        leftSolenoidState: (angle % 3.14) > 1.57 ? 1 : 0,
        rightSolenoidState: (angle % 3.14) < 1.57 ? 1 : 0,
      );

      if (mounted) {
        setState(() {
          latestTelemetry = t;
          positions.add({
            'timestamp': t.timestamp.toIso8601String(),
            'lat': t.lat,
            'lon': t.lon,
            'pto': t.ptoState,
            'device_in_plot': t.deviceInPlot,
            'speed': t.speed,
            'flow_rate': t.flowRate,
            'spray_mode': t.sprayMode,
          });
        });
        // Update state - overlays will rebuild automatically via setState
      }
    });
  }

  void _stopDemo() {
    _demoTimer?.cancel();
    _demoTimer = null;
  }

  // ── Cooldown banner widget ───────────────────────────────────────────────
  Widget _buildCooldownBanner(CooldownState state) {
    final isManual = state.cooldownType == 'manual_end';
    final label = isManual
        ? 'Session ended — report generating'
        : 'Device offline — report generating';
    final countdown = state.countdownLabel;
    final seconds = state.secondsRemaining;
    // Progress fraction: manual = 120 s max, auto = 600 s max
    final total = isManual ? 120.0 : 600.0;
    final fraction = (seconds / total).clamp(0.0, 1.0);

    return Container(
      color: Colors.orange.shade800.withOpacity(0.95),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_top_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    countdown,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: Colors.white.withOpacity(0.25),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int getSignalBars(int signalQuality) {
    if (signalQuality > -73) {
      return 5;
    } else if (signalQuality > -83 && signalQuality <= -73) {
      return 4;
    } else if (signalQuality > -93 && signalQuality <= -83) {
      return 3;
    } else if (signalQuality > -103 && signalQuality <= -93) {
      return 2;
    } else if (signalQuality > -113 && signalQuality <= -103) {
      return 1;
    } else {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(isOnlineStreamProvider);
    final online = conn.asData?.value ?? true;

    final userId = ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    final controlUnitsAsync = ref.watch(eq_provs.controlUnitsProvider(userId));
    final sprayersAsync = ref.watch(eq_provs.sprayersProvider(userId));
    final plotsAsync = ref.watch(fm_providers.plotsListProvider(userId));
    final metricsAsync = ref.watch(monitoringStreamProvider(userId));
    final sessionsAsync = ref.watch(activeSessionsListProvider);
    final sessionsLoaded = sessionsAsync is AsyncData;


    // Determine a suitable AppBar title. If a deviceId was provided and we
    // can resolve a matching control unit, show its name; otherwise fall
    // back to the generic label.
    String? resolvedControlUnitName;
    int? resolvedActiveSessionId;
    try {
      final cuList = controlUnitsAsync.asData?.value;
      final sessions = sessionsAsync.asData?.value;
      final normId = widget.deviceId != null ? canonicalizeMac(widget.deviceId!) : null;

      if (normId != null && cuList != null) {
        for (final cu in cuList) {
          final candidate = (cu.macAddress ?? cu.id).toString();
          if (candidate.isNotEmpty && canonicalizeMac(candidate) == normId) {
            resolvedControlUnitName = cu.name;
            resolvedActiveSessionId = cu.activeSessionId;
            break;
          }
        }
      }

      // If still null, try to find by jobId if provided
      if (resolvedActiveSessionId == null && widget.jobId != null && sessions != null) {
        for (final s in sessions) {
          if (s['job']?.toString() == widget.jobId) {
            resolvedActiveSessionId = s['id'] as int?;
            resolvedControlUnitName = s['control_unit_name']?.toString() ?? s['control_unit']?.toString();
            break;
          }
        }
      }

      // If still null and there's only one active session, use it
      if (resolvedActiveSessionId == null && sessions != null && sessions.length == 1) {
        final s = sessions.first;
        resolvedActiveSessionId = s['id'] as int?;
        resolvedControlUnitName = s['control_unit_name']?.toString() ?? s['control_unit']?.toString();
      }
    } catch (_) {}

    // Compute simple state indicators from the latest telemetry snapshot.
    final t0 = latestTelemetry;
    final bool ptoOnTop =
        t0 != null && (t0.ptoState != null && t0.ptoState == 1);
    final bool autoOnTop =
        t0 != null && (t0.sprayMode != null && t0.sprayMode == 1);
    // Left/right solenoid states (used for the top-left L/R indicators)
    final bool leftNozzleOn = t0 != null &&
        (t0.leftSolenoidState != null && t0.leftSolenoidState == 1);
    final bool rightNozzleOn = t0 != null &&
        (t0.rightSolenoidState != null && t0.rightSolenoidState == 1);

    return Scaffold(
      appBar: AppBar(
          bottom: online
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(28),
                  child: Container(
                    height: 28,
                    color: Colors.red.shade700,
                    alignment: Alignment.center,
                    child: const Text(
                      'Offline — showing last known telemetry',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
          title: Row(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(resolvedControlUnitName ?? 'Data Monitoring', style: const TextStyle(fontSize: 18)),
                if (latestTelemetry != null && 
                    DateTime.now().difference(latestTelemetry!.timestamp.toLocal()).inSeconds < 10)
                  const Text('● LIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
            const Spacer(),
            if (latestTelemetry != null) ...[
              // Signal/GPS status chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(220), // Darker, more solid for contrast
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withAlpha(30), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // GPS
                    Builder(builder: (ctx) {
                      final g = latestTelemetry!.gpsSignalQuality;
                      Color valCol = Colors.grey; 
                      if (g != null) {
                        valCol = g >= 3
                            ? Colors.green
                            : (g >= 1 ? Colors.orange : Colors.red);
                      }
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('GPS: ', 
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          Container(
                            width: 14,
                            height: 14,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: valCol,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: valCol.withOpacity(0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                )
                              ],
                            ),
                          ),
                          Text(g?.toString() ?? '-', 
                            style: TextStyle(
                              color: valCol, 
                              fontSize: 18, 
                              fontWeight: FontWeight.w900,
                            )),
                        ],
                      );
                    }),
                    const SizedBox(width: 16),
                    // Signal
                    SignalStrengthIndicator.bars(
                      value: latestTelemetry!.simSignalQuality != null
                          ? getSignalBars(latestTelemetry!.simSignalQuality!) / 5
                          : 0,
                      size: 22,
                      barCount: 5,
                      spacing: 1.0,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withAlpha(80),
                    ),
                  ],
                ),
              )
            ]
          ])),
      body: plotsAsync.when(
        data: (plots) {
          if (plots.isEmpty) {
            return const Center(child: Text('No plots available'));
          }
          final plot = widget.plotId != null
              ? plots.cast<fm_models.PlotModel>().firstWhere(
                  (f) => f.id == widget.plotId,
                  orElse: () => plots.cast<fm_models.PlotModel>().first)
              : plots.cast<fm_models.PlotModel>().first;
          // Determine center point: prefer plot polygon first point, then last position, then fallback.
          LatLng center;
          if (plot.polygon.isNotEmpty) {
            center = plot.polygon.first;
          } else if (positions.isNotEmpty) {
            center = LatLng((positions.last['lat'] as num).toDouble(),
                (positions.last['lon'] as num).toDouble());
          } else {
            // Default center if no plot polygon and no positions (e.g. session just ended)
            center = const LatLng(20.5937, 78.9629); // India center approx or last known
          }
          return Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 18.0,
                onTap: (tapPosition, point) {
                  setState(() {
                    _showTankOverlay = false;
                    _showSolenoidOverlay = false;
                    _showSensorOverlay = false;
                  });
                },
              ),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                    subdomains: const ['a', 'b', 'c']),
                if (plot.polygon.isNotEmpty)
                  PolygonLayer(polygons: [
                    Polygon(
                        points: plot.polygon,
                        color: (latestTelemetry?.deviceInPlot ?? true)
                            ? Colors.green.withAlpha(38)
                            : Colors.red.withAlpha(45),
                        borderColor: (latestTelemetry?.deviceInPlot ?? true)
                            ? Colors.green
                            : Colors.red,
                        borderStrokeWidth: 2.5)
                  ]),
                // If a device id was provided, render historical positions and live marker
                if (widget.deviceId != null && positions.isNotEmpty) ...[
                  // Build colored polyline segments by grouping consecutive
                  // position points that share the same color according to the
                  // device_in_plot and pto state.
                  PolylineLayer(
                      polylines:
                          _buildColoredPolylinesFromPositions(positions, 
                            ref.watch(fm_providers.plotByIdProvider(latestTelemetry?.plot ?? widget.plotId ?? '')).valueOrNull)),
                ],
                if (widget.deviceId != null && latestTelemetry != null)
                  MarkerLayer(markers: [
                    Marker(
                        point: LatLng(latestTelemetry!.lat ?? 0.0,
                            latestTelemetry!.lon ?? 0.0),
                        width: 40,
                        height: 40,
                        child: Icon(Icons.location_on,
                            color: _markerColorForTelemetry(latestTelemetry!, 
                              ref.watch(fm_providers.plotByIdProvider(latestTelemetry?.plot ?? widget.plotId ?? '')).valueOrNull))),
                  ]),
                _buildTankLevelOverlay(controlUnitsAsync.asData?.value,
                    sprayersAsync.asData?.value, userId),
                _buildSolenoidOverlay(controlUnitsAsync.asData?.value,
                    sprayersAsync.asData?.value, userId),
                _buildSensorOverlay(controlUnitsAsync.asData?.value,
                    sprayersAsync.asData?.value, userId),
              ],
            ),
            // Top-right map overlay for PTO and Auto/Manual indicators.
            // Positioned below the menu button so it doesn't overlap the menu.
            Positioned(
              top: 72,
              right: 12,
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
                            color: ptoOnTop ? Colors.green : Colors.red,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      // Auto/Manual chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: autoOnTop ? Colors.green : Colors.red,
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(autoOnTop ? 'A' : 'M',
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
                            onSelected: (v) async {
                              if (v == 'tank_level') {
                                try {
                                  _toggleTankLevelOverlay(
                                      controlUnitsAsync.asData?.value,
                                      sprayersAsync.asData?.value,
                                      userId);
                                } catch (e, st) {
                                  debugPrint('Popup onSelected error: $e');
                                  debugPrint('stack: $st');
                                }
                              } else if (v == 'spray_on_off') {
                                try {
                                  _toggleSolenoidOverlay(
                                      controlUnitsAsync.asData?.value,
                                      sprayersAsync.asData?.value,
                                      userId);
                                } catch (e, st) {
                                  debugPrint('Popup onSelected error: $e');
                                  debugPrint('stack: $st');
                                }
                              } else if (v == 'sensor_data') {
                                try {
                                  _toggleSensorOverlay(
                                      controlUnitsAsync.asData?.value,
                                      sprayersAsync.asData?.value,
                                      userId);
                                } catch (e, st) {
                                  debugPrint('Popup onSelected error: $e');
                                  debugPrint('stack: $st');
                                }
                              } else if (v == 'spraying_heatmap') {
                                setState(() {
                                  _selectedHeatmap = HeatmapType.spraying;
                                });
                              } else if (v == 'speed_heatmap') {
                                setState(() {
                                  _selectedHeatmap = HeatmapType.speed;
                                });
                              } else if (v == 'gps_heatmap') {
                                setState(() {
                                  _selectedHeatmap = HeatmapType.gps;
                                });
                              } else if (v == 'toggle_demo') {
                                setState(() {
                                  _isDemoMode = !_isDemoMode;
                                  if (_isDemoMode) {
                                    _startDemo();
                                  } else {
                                    _stopDemo();
                                  }
                                });
                              } else if (v == 'end_session') {
                                debugPrint('MonitoringScreen: End Session requested. jobId=${widget.jobId}, deviceId=${widget.deviceId}');
                                int? sessionIdToEnd = resolvedActiveSessionId;
                                
                                if (sessionIdToEnd == null) {
                                  debugPrint('MonitoringScreen: resolvedActiveSessionId is null, attempting fallback lookup...');
                                  try {
                                    // FORCE REFRESH to ensure we have the latest active sessions
                                    final sessions = await ref.refresh(activeSessionsListProvider.future);
                                    debugPrint('MonitoringScreen: Fetched ${sessions.length} active sessions');

                                    if (sessions.isNotEmpty) {
                                      final normId = widget.deviceId != null ? canonicalizeMac(widget.deviceId!) : null;
                                      debugPrint('MonitoringScreen: Searching for MAC=$normId or jobId=${widget.jobId}');

                                      for (final s in sessions) {
                                        final sId = s['id'];
                                        final sJob = s['job']?.toString();
                                        final sMac = (s['control_unit_mac'] ?? s['mac_addr'] ?? s['mac_address'])?.toString();
                                        final normSMac = sMac != null ? canonicalizeMac(sMac) : null;
                                        
                                        debugPrint('MonitoringScreen: Checking session ID=$sId, Job=$sJob, MAC=$sMac (Norm=$normSMac)');

                                        if (normId != null && normSMac == normId) {
                                          debugPrint('MonitoringScreen: Match found by MAC!');
                                          sessionIdToEnd = sId as int?;
                                          break;
                                        }

                                        if (widget.jobId != null && sJob == widget.jobId) {
                                          debugPrint('MonitoringScreen: Match found by JobID!');
                                          sessionIdToEnd = sId as int?;
                                          break;
                                        }
                                      }

                                      // Absolute fallback: if only 1 active session in the whole system for this user, assume it's the one
                                      if (sessionIdToEnd == null && sessions.length == 1) {
                                        debugPrint('MonitoringScreen: Single session fallback used.');
                                        sessionIdToEnd = sessions.first['id'] as int?;
                                      }
                                    } else {
                                      debugPrint('MonitoringScreen: activeSessionsList returned empty.');
                                    }
                                  } catch (e) {
                                    debugPrint('MonitoringScreen: Error during session fallback: $e');
                                  }
                                } else {
                                  debugPrint('MonitoringScreen: Using already resolvedActiveSessionId=$sessionIdToEnd');
                                }

                                if (sessionIdToEnd == null) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active session ID found.')));
                                  }
                                  return;
                                }
                                final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                          title: const Text('End Session?'),
                                          content: Text(
                                              'Are you sure you want to end the active session for ${resolvedControlUnitName ?? "this device"}?'),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.pop(ctx, false),
                                                child: const Text('Cancel')),
                                            TextButton(
                                                onPressed: () => Navigator.pop(ctx, true),
                                                child: const Text('End')),
                                          ],
                                        ));
                                if (confirmed == true) {
                                  try {
                                    final deviceMac = widget.deviceId ?? latestTelemetry?.deviceId;
                                    await ref
                                        .read(eq_provs.equipmentControllerProvider)
                                        .endSession(sessionIdToEnd, deviceId: deviceMac);

                                    // 1. Mandatory ignore: block incoming telemetry for 2 min
                                    //    (the WS status_change event is the authoritative source,
                                    //    but this guards against late-arriving packets).
                                    if (deviceMac != null) {
                                      final normMac = canonicalizeMac(deviceMac);
                                      _ignoredUntil[normMac] = DateTime.now()
                                          .add(const Duration(minutes: 2));
                                    }

                                    // 2. Immediate UI feedback: clear local telemetry state
                                    setState(() {
                                      latestTelemetry = null;
                                      positions.clear();
                                      _demoTimer?.cancel();
                                      _demoTimer = null;
                                      _isDemoMode = false;
                                      // Show a local cooldown state immediately — the WS event
                                      // will arrive shortly and replace this with the real end_ts.
                                      _cooldownState = CooldownState(
                                        deviceId: deviceMac ?? '',
                                        status: DeviceLifecycleStatus.cooldown,
                                        cooldownEnd: DateTime.now()
                                            .toUtc()
                                            .add(const Duration(minutes: 2)),
                                        cooldownType: 'manual_end',
                                      );
                                      _startCountdownTimer();
                                    });

                                    // 3. Clear service cache as well (extra safety)
                                    if (deviceMac != null) {
                                      ref.read(telemetryServiceProvider).clearCache(deviceMac);
                                    }

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Session ended. Report will be generated in 2 minutes.'),
                                          duration: Duration(seconds: 4),
                                        ),
                                      );
                                    }
                                  } catch (err) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(content: Text('Error: $err')));
                                    }
                                  }
                                }
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem<String>(
                                  enabled: false,
                                  child: Text('Heatmap',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                               PopupMenuItem(
                                  value: 'spraying_heatmap',
                                  child: Text('Spraying heat map',
                                      style: TextStyle(
                                          color: _selectedHeatmap ==
                                                  HeatmapType.spraying
                                              ? Theme.of(context).primaryColor
                                              : Colors.black))),
                              PopupMenuItem(
                                  value: 'speed_heatmap',
                                  child: Text('Speed heat map',
                                      style: TextStyle(
                                          color: _selectedHeatmap ==
                                                  HeatmapType.speed
                                              ? Theme.of(context).primaryColor
                                              : Colors.black))),
                              PopupMenuItem(
                                  value: 'gps_heatmap',
                                  child: Text('GPS heat map',
                                      style: TextStyle(
                                          color: _selectedHeatmap ==
                                                  HeatmapType.gps
                                              ? Theme.of(context).primaryColor
                                              : Colors.black))),
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
                              const PopupMenuDivider(),
                              const PopupMenuItem<String>(
                                  enabled: false,
                                  child: Text('Demo mode',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold))),
                              PopupMenuItem(
                                value: 'toggle_demo',
                                child: Row(
                                  children: [
                                    Text(_isDemoMode ? 'Demo Mode: ON' : 'Demo Mode: OFF'),
                                    const Spacer(),
                                    Switch(
                                      value: _isDemoMode,
                                      onChanged: (v) {
                                        // The PopupMenuButton closes on selection, so we handle it 
                                        // by forcing a pop with the value that matches onSelected.
                                        Navigator.pop(context, 'toggle_demo');
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              if (resolvedActiveSessionId != null || latestTelemetry != null) ...[
                                const PopupMenuDivider(),
                                PopupMenuItem(
                                  value: 'end_session',
                                  child: Row(
                                    children: const [
                                      Icon(Icons.stop_circle_outlined,
                                          color: Colors.redAccent, size: 20),
                                      SizedBox(width: 8),
                                      Text('End active device',
                                          style: TextStyle(color: Colors.redAccent)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Cooldown / offline-pending banner ──────────────────────────
            if (_cooldownState != null &&
                _cooldownState!.status == DeviceLifecycleStatus.cooldown)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildCooldownBanner(_cooldownState!),
              ),

            // ── Top-left L/R nozzle indicators (left/right) ───────────────
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
                                    leftNozzleOn ? Colors.green : Colors.grey,
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
                                    rightNozzleOn ? Colors.green : Colors.grey,
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
                  
                  final flowRateLpmStr = t != null && t.flowRateLpm != null
                      ? t.flowRateLpm!.toStringAsFixed(2)
                      : flowRate;
                  final flowInLitresStr = t != null && t.flowInLitres != null
                      ? t.flowInLitres!.toStringAsFixed(2)
                      : '-';

                  final ptoOn = t != null && t.ptoState != null
                      ? (t.ptoState == 1)
                      : ((m['ptoState'] ?? m['pto'] ?? false) == true);

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
                                      // summary single-line row
                                      Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceAround,
                                          children: [
                                            _smallStat('Flow LPM', flowRateLpmStr),
                                            _smallStat('Flow L', flowInLitresStr),
                                            _smallStat('Speed', '$speed kmph'),
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

  Widget _buildTankLevelOverlay(
      List<dynamic>? controlUnits, List<dynamic>? sprayers, String userId) {
    if (!_showTankOverlay) return const SizedBox.shrink();
    
    // Find matching sprayer for this control unit
    String? sprayerIdStr;
    try {
      if (controlUnits != null) {
        for (final cu in controlUnits) {
          final cuMac = (cu.macAddress ?? cu.controlUnitId ?? cu.id).toString();
          if (canonicalizeMac(cuMac) == canonicalizeMac(widget.deviceId ?? '')) {
            sprayerIdStr = cu.sprayer?.toString();
            break;
          }
        }
      }
    } catch (_) {}

    double percent = latestTelemetry?.tankLevel ?? 0.0;
    String pctLabel = '${percent.toStringAsFixed(1)}%';
    double? tankCapacity;
    double? liters;

    if (sprayerIdStr != null && sprayers != null) {
      final sprayer = sprayers.firstWhere(
          (s) => s.id.toString() == sprayerIdStr,
          orElse: () => null);
      if (sprayer != null) {
        tankCapacity = (sprayer.tankCapacity as num?)?.toDouble();
        if (tankCapacity != null) {
          liters = tankCapacity * (percent / 100.0);
        }
      }
    }

    const imgWidth = 160.0;
    const imgHeight = 220.0;
    final fillHeight = imgHeight * (percent / 100.0);

    return Positioned(
      top: 120,
      right: 12,
      child: SafeArea(
        child: Card(
          color: Colors.white.withAlpha(230),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: imgWidth,
                  height: imgHeight,
                  child: Stack(alignment: Alignment.center, children: [
                    Image.asset('assets/monitoring/tank_level.png',
                        width: imgWidth,
                        height: imgHeight,
                        fit: BoxFit.contain),
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: imgWidth,
                        height: fillHeight,
                        color: Colors.blue.withValues(alpha: 0.45),
                      ),
                    ),
                    Text(pctLabel,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color:
                                percent < 30 ? Colors.red : Colors.black)),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(
                    'Cap: ${tankCapacity != null ? '${tankCapacity.toString()} L' : '-'}'),
                const SizedBox(height: 6),
                Text(
                    'Now: ${liters != null ? '${liters.toStringAsFixed(2)} L' : pctLabel}'),
                const SizedBox(height: 8),
                TextButton(
                    onPressed: _hideTankLevelOverlay,
                    child: const Text('Close'))
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideTankLevelOverlay() {
    setState(() {
      _showTankOverlay = false;
    });
  }

  void _toggleTankLevelOverlay(
      List<dynamic>? controlUnits, List<dynamic>? sprayers, String userId) {
    try {
    setState(() {
      _showTankOverlay = !_showTankOverlay;
    });
    } catch (e, st) {
      debugPrint('Error toggling tank overlay: $e');
      debugPrint('stack: $st');
    }
  }

  Widget _buildSolenoidOverlay(
      List<dynamic>? controlUnits, List<dynamic>? sprayers, String userId) {
    if (!_showSolenoidOverlay) return const SizedBox.shrink();

    final t = latestTelemetry;
    final leftOn = t != null && t.leftSolenoidState == 1;
    final rightOn = t != null && t.rightSolenoidState == 1;

    const imgWidth = 260.0;
    const imgHeight = 140.0;

    return Positioned(
      top: 120,
      right: 12,
      child: SafeArea(
        child: Card(
          color: Colors.white.withAlpha(230),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: imgWidth,
                  height: imgHeight,
                  child: Stack(alignment: Alignment.center, children: [
                    Image.asset('assets/monitoring/solenoid.png',
                        width: imgWidth,
                        height: imgHeight,
                        fit: BoxFit.contain),
                    // Left indicator
                    Positioned(
                      left: 90,
                      top: imgHeight * 0.40,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                            color: leftOn ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2)),
                      ),
                    ),
                    // Right indicator
                    Positioned(
                      right: 90,
                      top: imgHeight * 0.40,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                            color: rightOn ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('LEFT',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('RIGHT',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('L: ${leftOn ? 'ON' : 'OFF'}'),
                  const SizedBox(width: 12),
                  Text('R: ${rightOn ? 'ON' : 'OFF'}'),
                ]),
                const SizedBox(height: 8),
                TextButton(
                    onPressed: _hideSolenoidOverlay,
                    child: const Text('Close'))
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideSolenoidOverlay() {
    setState(() {
      _showSolenoidOverlay = false;
    });
  }

  void _toggleSolenoidOverlay(
      List<dynamic>? controlUnits, List<dynamic>? sprayers, String userId) {
    try {
    setState(() {
      _showSolenoidOverlay = !_showSolenoidOverlay;
    });
    } catch (e, st) {
      debugPrint('Error toggling solenoid overlay: $e');
      debugPrint('stack: $st');
    }
  }

  Widget _buildSensorOverlay(
      List<dynamic>? controlUnits, List<dynamic>? sprayers, String userId) {
    if (!_showSensorOverlay) return const SizedBox.shrink();

    final t = latestTelemetry;
    final leftDist = t != null && t.leftDistance != null
        ? t.leftDistance!.toStringAsFixed(2)
        : '-';
    final rightDist = t != null && t.rightDistance != null
        ? t.rightDistance!.toStringAsFixed(2)
        : '-';
    final leftStr = t != null && t.leftDensity != null
        ? t.leftDensity!.toStringAsFixed(2)
        : '-';
    final rightStr = t != null && t.rightDensity != null
        ? t.rightDensity!.toStringAsFixed(2)
        : '-';

    return Positioned(
      top: 100,
      right: 12,
      child: SafeArea(
        child: Card(
          color: Colors.white.withAlpha(240),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sensor Data',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                          flex: 2,
                          child: Text('Distance',
                              style: TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(
                        flex: 3,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                                width: 60,
                                child:
                                    Text(leftDist, textAlign: TextAlign.right)),
                            const SizedBox(width: 20),
                            SizedBox(
                                width: 60,
                                child: Text(rightDist,
                                    textAlign: TextAlign.right)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                          flex: 2,
                          child: Text('Strength',
                              style: TextStyle(fontWeight: FontWeight.w600))),
                      Expanded(
                        flex: 3,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                                width: 60,
                                child:
                                    Text(leftStr, textAlign: TextAlign.right)),
                            const SizedBox(width: 20),
                            SizedBox(
                                width: 60,
                                child:
                                    Text(rightStr, textAlign: TextAlign.right)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: _hideSensorOverlay,
                        child: const Text('Close')),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _hideSensorOverlay() {
    setState(() {
      _showSensorOverlay = false;
    });
  }

  void _toggleSensorOverlay(
      List<dynamic>? controlUnits, List<dynamic>? sprayers, String userId) {
    try {
    setState(() {
      _showSensorOverlay = !_showSensorOverlay;
    });
    } catch (e, st) {
      debugPrint('Error toggling sensor overlay: $e');
      debugPrint('stack: $st');
    }
  }

  Color _markerColorForTelemetry(TelemetryData t, PlotEntity? plot) {
    try {
      bool inPlot = t.deviceInPlot == true ||
          (t.deviceInPlot?.toString().toLowerCase() == 'true') ||
          (t.deviceInPlot?.toString() == '1');
      
      // Local reinforcement: calculate in-plot status if we have the polygon
      if (plot?.polygon != null && plot!.polygon.length >= 3 && t.lat != null && t.lon != null) {
        final locallyInPlot = _isPointInPolygon(LatLng(t.lat!, t.lon!), plot.polygon);
        inPlot = locallyInPlot;
      }

      final ptoOn = (t.ptoState != null && t.ptoState == 1);
      final isAuto = (t.sprayMode != null && t.sprayMode == 1);

      return HeatmapColorUtils.getColorForGPS(
        isInPlot: inPlot,
        ptoOn: ptoOn,
        isAuto: isAuto,
      );
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
          showGenericErrorSnackBar(context, 'Device is outside the assigned plot');
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

  // Compute the color for a single stored position entry based on selected heatmap type.
  Color _colorForPositionEntry(Map<String, dynamic> p, PlotEntity? plot) {
    switch (_selectedHeatmap) {
      case HeatmapType.speed:
        return HeatmapColorUtils.getColorForSpeed((p['speed'] as num?)?.toDouble());
      case HeatmapType.spraying:
        return HeatmapColorUtils.getColorForSpray((p['flow_rate'] as num?)?.toDouble());
      case HeatmapType.gps:
        final devInPlot = p['device_in_plot'];
        final lat = (p['lat'] as num?)?.toDouble();
        final lon = (p['lon'] as num?)?.toDouble();
        
        bool isInPlot = (devInPlot == true ||
            (devInPlot != null && devInPlot.toString().toLowerCase() == 'true') ||
            (devInPlot != null && devInPlot.toString() == '1'));
        
        // Local reinforcement for historical points using the passed plot
        if (plot?.polygon != null && plot!.polygon.length >= 3 && lat != null && lon != null) {
          isInPlot = _isPointInPolygon(LatLng(lat, lon), plot.polygon);
        }

        final pto = p['pto'];
        final ptoOn = (pto != null && (pto is int ? pto == 1 : pto.toString() == '1'));
        final spray = p['spray_mode'];
        final isAuto = (spray != null && (spray is int ? spray == 1 : spray.toString() == '1'));
        return HeatmapColorUtils.getColorForGPS(
          isInPlot: isInPlot,
          ptoOn: ptoOn,
          isAuto: isAuto,
        );
    }
  }

  // Ray-casting algorithm to determine if a point is within a polygon
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var intersections = 0;
    for (var i = 0; i < polygon.length; i++) {
      var p1 = polygon[i];
      var p2 = polygon[(i + 1) % polygon.length];
      if (p1.longitude > point.longitude != p2.longitude > point.longitude &&
          point.latitude < (p2.latitude - p1.latitude) * (point.longitude - p1.longitude) / (p2.longitude - p1.longitude) + p1.latitude) {
        intersections++;
      }
    }
    return intersections % 2 != 0;
  }

  // Build a list of Polylines by grouping consecutive position points that
  // share the same color. Each resulting Polyline will be drawn with the
  // color for that segment.
  List<Polyline> _buildColoredPolylinesFromPositions(
      List<Map<String, dynamic>> pos, PlotEntity? plot) {
    final List<Polyline> result = [];
    if (pos.length < 2) return result;

    List<LatLng> currentPoints = [];
    Color? currentColor;

    for (var i = 0; i < pos.length; i++) {
      final p = pos[i];
      final lat = (p['lat'] as num).toDouble();
      final lon = (p['lon'] as num).toDouble();
      final color = _colorForPositionEntry(p, plot);
      final point = LatLng(lat, lon);

      if (currentColor == null) {
        // start new segment
        currentColor = color;
        currentPoints = [point];
      } else if (color == currentColor) {
        currentPoints.add(point);
      } else {
        // Gap fix: Add the first point of the NEW segment to the OLD segment
        // to ensure continuity.
        currentPoints.add(point);
        if (currentPoints.length >= 2) {
          result.add(Polyline(
              points: List<LatLng>.from(currentPoints),
              strokeWidth: 4.0,
              color: currentColor!));
        }
        // start new segment from this transition point
        currentColor = color;
        currentPoints = [point];
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
}
