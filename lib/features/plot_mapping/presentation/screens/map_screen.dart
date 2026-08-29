import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/utils/error_utils.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:math' as math;
// no json decoding here; geocoding handled by GeocodingService
import 'package:simdaas/core/services/geocoding_service.dart';
import 'package:latlong2/latlong.dart';
// plot providers/imports moved to helper where needed
import '../providers/map_state_providers.dart';
// Plot model and auth service used in save helper
import 'package:simdaas/core/services/location_service.dart';
import '../../data/models/plot_model.dart';
import '../widgets/plot_save_sheet.dart';
import '../widgets/map_layers.dart';
import 'row_line_screen.dart';

class MapScreen extends ConsumerStatefulWidget {
  final LatLng? initialCenter;
  // Minimum and maximum allowed zoom levels for the map. These can be
  // configured when creating the MapScreen. Defaults chosen to allow
  // close-up editing while preventing excessive zoom-out.
  final double minZoom;
  final double maxZoom;
  final List<LatLng>? initialPoints;
  final PlotModel? existingPlot;

  const MapScreen({
    super.key,
    this.initialCenter,
    this.minZoom = 2.0,
    this.maxZoom = 22.0,
    this.initialPoints,
    this.existingPlot,
  });

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  bool _locatingDevice = false;
  bool _isSatelliteView = true;
  // Latest fix from MapLayers' own live MyLocationLayer stream. Reused by
  // the "center on me" button instead of starting a second, competing
  // GPS request (see _centerOnCurrentLocation).
  LatLng? _liveStreamPosition;
  Offset? _lastPointerPosition;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // (multi-pointer centroid removed; we use simple single-touch drag for vertices)
  double _computeAreaHa(List<LatLng> poly) {
    if (poly.length < 3) return 0.0;
    const R = 6371000.0; // Earth radius in meters
    // use centroid latitude for projection scale
    double sumLat = 0;
    for (final p in poly) {
      sumLat += p.latitude;
    }
    final lat0 = (sumLat / poly.length) * (math.pi / 180.0);

    List<double> xs = [];
    List<double> ys = [];
    for (final p in poly) {
      final latRad = p.latitude * (math.pi / 180.0);
      final lonRad = p.longitude * (math.pi / 180.0);
      final x = R * lonRad * math.cos(lat0);
      final y = R * latRad;
      xs.add(x);
      ys.add(y);
    }

    double area = 0.0;
    for (int i = 0; i < xs.length; i++) {
      final j = (i + 1) % xs.length;
      area += xs[i] * ys[j] - xs[j] * ys[i];
    }
    area = area.abs() * 0.5; // in square meters
    return area / 10000.0; // hectares
  }

  void _onTapTap(TapPosition tapPos, LatLng latlng) {
    final mapNotifier = ref.read(mapStateProvider.notifier);
    final currentPoints = ref.read(mapStateProvider).points;

    // If the tap is very close to an existing vertex, select that vertex
    // instead of inserting a new point on top of it.
    if (currentPoints.isNotEmpty) {
      try {
        final nearestIdx = _findNearestIndex(latlng, currentPoints);
        if (nearestIdx != null) {
          final d =
              const Distance().distance(latlng, currentPoints[nearestIdx]);
          // threshold in meters (6m)
          if (d <= 6.0) {
            mapNotifier.selectVertex(nearestIdx);
            return;
          }
        }
      } catch (e, st) {
        debugPrint('map_screen._onTapTap nearest index error: $e\n$st');
      }
    }

    // try to insert on nearest segment if close
    final idx = _nearestSegmentIndex(latlng, currentPoints);
    if (idx != null) {
      mapNotifier.insertPoint(idx + 1, latlng);
      // normalize and select the newly inserted point
      final moved = latlng;
      final updatedPoints = ref.read(mapStateProvider).points;
      final normalized = _normalizePolygon(updatedPoints);
      mapNotifier.setPoints(normalized);
      mapNotifier.selectVertex(_findNearestIndex(moved, normalized));
      return;
    }

    // otherwise append
    mapNotifier.addPoint(latlng);
    // normalize and select appended
    final moved = latlng;
    final updatedPoints = ref.read(mapStateProvider).points;
    final normalized = _normalizePolygon(updatedPoints);
    mapNotifier.setPoints(normalized);
    mapNotifier.selectVertex(_findNearestIndex(moved, normalized));
  }

  // compute nearest segment index to a point; returns index i for segment between points[i] and points[i+1]
  int? _nearestSegmentIndex(LatLng p, List<LatLng> points) {
    if (points.length < 2) return null;
    // use centroid latitude for projection
    double sumLat = 0;
    for (final pt in points) {
      sumLat += pt.latitude;
    }
    final lat0 = (sumLat / points.length) * (math.pi / 180.0);
    const R = 6371000.0;

    double px = R * (p.longitude * (math.pi / 180.0)) * math.cos(lat0);
    double py = R * (p.latitude * (math.pi / 180.0));

    double bestDist = double.infinity;
    int? bestIdx;
    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final ax = R * (a.longitude * (math.pi / 180.0)) * math.cos(lat0);
      final ay = R * (a.latitude * (math.pi / 180.0));
      final bx = R * (b.longitude * (math.pi / 180.0)) * math.cos(lat0);
      final by = R * (b.latitude * (math.pi / 180.0));

      final vx = bx - ax;
      final vy = by - ay;
      final wx = px - ax;
      final wy = py - ay;
      final c1 = vx * wx + vy * wy;
      final c2 = vx * vx + vy * vy;
      double t = 0.0;
      if (c2 > 0) t = (c1 / c2).clamp(0.0, 1.0);
      final projx = ax + t * vx;
      final projy = ay + t * vy;
      final dx = px - projx;
      final dy = py - projy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }

    // threshold: 20 meters
    if (bestDist.isFinite && bestDist <= 20.0) return bestIdx;
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Initialize polygon state
    try {
      if (widget.initialPoints != null && widget.initialPoints!.isNotEmpty) {
        ref.read(mapStateProvider.notifier).setPoints(widget.initialPoints!);
      } else {
        ref.read(mapStateProvider.notifier).clearAll();
      }
    } catch (e, st) {
      debugPrint('map_screen.initState.initPoints error: $e\n$st');
    }
    // move the map after first frame if initial data provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialPoints != null && widget.initialPoints!.isNotEmpty) {
        // center on polygon
        final avgLat = widget.initialPoints!
                .map((p) => p.latitude)
                .reduce((a, b) => a + b) /
            widget.initialPoints!.length;
        final avgLng = widget.initialPoints!
                .map((p) => p.longitude)
                .reduce((a, b) => a + b) /
            widget.initialPoints!.length;
        _mapController.move(LatLng(avgLat, avgLng), 18.0);
      } else if (widget.initialCenter != null) {
        _mapController.move(widget.initialCenter!, 18.0);
      }
    });

    // If no initial data, try to move to device's current location
    if (widget.initialCenter == null &&
        (widget.initialPoints == null || widget.initialPoints!.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final loc = await LocationService().getCurrentLocation();
          // ignore invalid fallback (0,0)
          if (loc.latitude != 0 || loc.longitude != 0) {
            _mapController.move(loc, 18.0);
          }
        } catch (e, st) {
          debugPrint('map_screen.initState.getCurrentLocation error: $e\n$st');
        }
      });
    }

    // listen to search text changes for autocomplete
    // show help dialog after first frame so user sees guidance when opening map
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showHelpDialog();
    });
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() async {
    final searchNotifier = ref.read(searchStateProvider.notifier);
    final text = _searchCtrl.text.trim();
    if (text.isEmpty) {
      searchNotifier.clearSuggestions();
      return;
    }

    // skip if it's lat,lng format
    if (text.contains(',')) {
      searchNotifier.clearSuggestions();
      return;
    }

    searchNotifier.setSearching(true);

    // debounce: wait a bit before searching
    await Future.delayed(const Duration(milliseconds: 500));
    if (_searchCtrl.text.trim() != text) return; // user kept typing

    try {
      final geo = ref.read(geocodingServiceProvider);
      final data = await geo.searchSuggestions(text, limit: 5);
      if (mounted) searchNotifier.setSuggestions(data);
    } catch (e, st) {
      debugPrint('map_screen._onSearchChanged search error: $e\n$st');
      if (mounted) {
        searchNotifier.clearSuggestions();
      }
    }
  }

  void showHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('How to map a field'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('1. ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                      child: Text(
                          'Search your location or click on the dot button for your current location')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('2. ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text('Map the field of operation')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('3. ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  const Icon(Icons.save, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Click save button')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('4. ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text('Add data.')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('5. ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text('Click save')),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  void _navigateToLocation(String text) async {
    if (text.isEmpty) return;
    LatLng? center;
    if (text.contains(',')) {
      final parts = text.split(',');
      try {
        final lat = double.parse(parts[0].trim());
        final lng = double.parse(parts[1].trim());
        center = LatLng(lat, lng);
      } catch (e, st) {
        debugPrint(
            'map_screen._navigateToLocation parse coords error: $e\n$st');
      }
    } else {
      // geocode via Nominatim
      try {
        final geo = ref.read(geocodingServiceProvider);
        final data = await geo.searchSuggestions(text, limit: 1);
        if (data.isNotEmpty) {
          final first = data.first;
          final lat = double.parse(first['lat'].toString());
          final lon = double.parse(first['lon'].toString());
          center = LatLng(lat, lon);
        }
      } catch (e, st) {
        debugPrint('map_screen._navigateToLocation geocode error: $e\n$st');
      }
    }

    if (center != null) {
      _mapController.move(center, 18.0);
      ref.read(searchStateProvider.notifier).clearSuggestions();
      _searchFocus.unfocus();
    }
  }

  Future<void> _saveField() async {
    final mapState = ref.read(mapStateProvider);
    final points = mapState.points;

    if (points.length < 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mark at least 3 boundary points to form a closed polygon.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final normalizedPoints = _normalizePolygon(points);
    // update stored points to normalized
    ref.read(mapStateProvider.notifier).setPoints(normalizedPoints);

    final savedPlot =
        await showPlotSaveSheet(context, ref, normalizedPoints, _computeAreaHa, existingPlot: widget.existingPlot);
    if (savedPlot != null && mounted) {
      final goToRowLine = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('AB Line Plotting'),
          content: const Text(
              'Plot saved successfully. Do you want to proceed to AB line (row line) plotting now?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (goToRowLine == true) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RowLineScreen(plot: savedPlot),
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _centerOnCurrentLocation() async {
    if (_locatingDevice) return;

    // Prefer the fix already flowing in from MapLayers' own MyLocationLayer
    // stream -- no new GPS request needed, so there's nothing to hang or
    // contend with. This is also why it's instant after the first fix.
    final live = _liveStreamPosition;
    if (live != null) {
      _mapController.move(live, 18.0);
      return;
    }

    // Stream hasn't emitted anything yet (just opened the screen / no
    // permission yet) -- fall back to a one-off request to get the map
    // moving for the first time only.
    setState(() => _locatingDevice = true);
    final service = LocationService();
    bool movedOnce = false;
    try {
      final lastKnown = await service.getLastKnownLocation();
      if (lastKnown != null && mounted) {
        _mapController.move(lastKnown, 18.0);
        movedOnce = true;
      }
    } catch (_) {
      // Best-effort only; the fresh fix below is the source of truth.
    }

    try {
      // The geolocator plugin's own `timeLimit` doesn't reliably fire on
      // every Android device/version (observed: request hangs forever on
      // some devices instead of throwing TimeoutException). This outer
      // timeout guarantees the spinner stops regardless of plugin behavior.
      final loc = await service
          .getCurrentLocation()
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        _mapController.move(loc, 18.0);
      }
    } catch (e) {
      // If we already moved to a last-known fix, a failed fresh fix isn't
      // worth surfacing as an error -- the map is already roughly correct.
      if (mounted && !movedOnce) {
        showPolishedError(context, e, fallback: 'Location error');
      }
    } finally {
      if (mounted) {
        setState(() => _locatingDevice = false);
      }
    }
  }

  void _zoomIn() {
    try {
      final cam = _mapController.camera;
      final center = cam.center;
      final curZoom = cam.zoom;
      final newZoom = (curZoom + 1).clamp(widget.minZoom, widget.maxZoom);
      _mapController.move(center, newZoom);
    } catch (e, st) {
      debugPrint('map_screen._zoomIn error: $e\n$st');
    }
  }

  void _zoomOut() {
    try {
      final cam = _mapController.camera;
      final center = cam.center;
      final curZoom = cam.zoom;
      final newZoom = (curZoom - 1).clamp(widget.minZoom, widget.maxZoom);
      _mapController.move(center, newZoom);
    } catch (e, st) {
      debugPrint('map_screen._zoomOut error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapStateProvider);
    final searchState = ref.watch(searchStateProvider);
    final points = mapState.points;
    final selectedVertex = mapState.selectedVertex;
    final absorbMap = mapState.absorbMap;
    final searchSuggestions = searchState.suggestions;
    final isSearching = searchState.isSearching;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Plot'),
        actions: [
          IconButton(
            tooltip: 'Clear all vertices',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () async {
              final pts = ref.read(mapStateProvider).points;
              if (pts.isEmpty) {
                if (mounted) {
                  showInfoSnackBar(context, 'No vertices to clear');
                }
                return;
              }
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Clear all vertices?'),
                  content: const Text(
                      'This will remove all vertices from the current polygon.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(c).pop(false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.of(c).pop(true),
                        child: const Text('Clear')),
                  ],
                ),
              );
              if (confirm == true) {
                ref.read(mapStateProvider.notifier).clearAll();
                if (mounted) {
                  showSuccessSnackBar(context, 'Cleared all vertices');
                }
              }
            },
          ),
          // Help button to guide user through mapping flow
          IconButton(
            tooltip: 'How to map a field',
            icon: const Icon(Icons.help_outline),
            onPressed: showHelpDialog,
          ),
          // removed AppBar location button — replaced with FAB
        ],
      ),
      body: Stack(
        children: [
          MapLayers(
            mapController: _mapController,
            points: points,
            selectedVertex: selectedVertex,
            absorbMap: absorbMap,
            minZoom: widget.minZoom,
            maxZoom: widget.maxZoom,
            onTap: _onTapTap,
            onMyLocation: (pos) => _liveStreamPosition = pos,
            isSatellite: _isSatelliteView,
            onMarkerPointerDown: (i, event) {
              final mapNotifier = ref.read(mapStateProvider.notifier);
              mapNotifier.selectVertex(i);
              mapNotifier.setAbsorbMap(true);
              _lastPointerPosition = event.position;
            },
            onMarkerPointerMove: (i, event) {
              if (selectedVertex != i || _lastPointerPosition == null) return;
              try {
                final camera = _mapController.camera;
                final RenderBox? box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final lastLocal = box.globalToLocal(_lastPointerPosition!);
                final currentLocal = box.globalToLocal(event.position);
                final lastLatLng =
                    camera.offsetToCrs(Offset(lastLocal.dx, lastLocal.dy));
                final currentLatLng = camera
                    .offsetToCrs(Offset(currentLocal.dx, currentLocal.dy));
                final deltaLat = currentLatLng.latitude - lastLatLng.latitude;
                final deltaLng = currentLatLng.longitude - lastLatLng.longitude;
                final currentVertex = points[i];
                final newLat = currentVertex.latitude + deltaLat;
                final newLng = currentVertex.longitude + deltaLng;
                final mapNotifier = ref.read(mapStateProvider.notifier);
                if (selectedVertex != null && selectedVertex < points.length) {
                  mapNotifier.updatePoint(
                      selectedVertex, LatLng(newLat, newLng));
                }
                _lastPointerPosition = event.position;
              } catch (e, st) {
                debugPrint('map_screen.onPointerMove error: $e\n$st');
                _lastPointerPosition = event.position;
              }
            },
            onMarkerPointerUp: (i, event) {
              final mapNotifier = ref.read(mapStateProvider.notifier);
              mapNotifier.setAbsorbMap(false);
              _lastPointerPosition = null;
            },
            onMarkerPointerCancel: (i, event) {
              final mapNotifier = ref.read(mapStateProvider.notifier);
              mapNotifier.setAbsorbMap(false);
              _lastPointerPosition = null;
            },
          ),
          // ...existing code...
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          style: const TextStyle(color: Colors.black, fontSize: 14),
                          cursorColor: Colors.black,
                          decoration: const InputDecoration(
                            hintText: 'Search location or lat,lng',
                            hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (text) {
                            _navigateToLocation(text.trim());
                          },
                        ),
                      ),
                      if (isSearching)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          ),
                        )
                      else
                        IconButton(
                          onPressed: () {
                            _navigateToLocation(_searchCtrl.text.trim());
                          },
                          icon: const Icon(Icons.search, color: Colors.black54),
                        ),
                    ]),
                  ),
                ),
                if (searchSuggestions.isNotEmpty)
                  Card(
                    elevation: 4,
                    margin: const EdgeInsets.only(top: 4),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: searchSuggestions.length,
                      itemBuilder: (context, index) {
                        final suggestion = searchSuggestions[index];
                        final displayName =
                            suggestion['display_name'] as String;
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on, size: 20),
                          title: Text(
                            displayName,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            final lat =
                                double.parse(suggestion['lat'] as String);
                            final lon =
                                double.parse(suggestion['lon'] as String);
                            _mapController.move(LatLng(lat, lon), 18.0);
                            _searchCtrl.text = displayName;
                            ref
                                .read(searchStateProvider.notifier)
                                .clearSuggestions();
                            _searchFocus.unfocus();
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          // Tap-to-mark hint: shown when no boundary points placed yet
          if (points.isEmpty)
            Positioned(
              bottom: 140,
              left: 16,
              right: 90,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(184),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tap on the map to mark your field boundary',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // controls for selected vertex
          if (selectedVertex != null)
            Positioned(
              bottom: 80,
              right: 90,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(children: [
                    TextButton.icon(
                      onPressed: () {
                        final mapNotifier = ref.read(mapStateProvider.notifier);
                        final currentState = ref.read(mapStateProvider);
                        if (currentState.selectedVertex != null &&
                            currentState.selectedVertex! < points.length) {
                          final removed = points[currentState.selectedVertex!];
                          mapNotifier.deletePoint(currentState.selectedVertex!);
                          // normalize and restore selection to nearest
                          final currentPoints =
                              ref.read(mapStateProvider).points;
                          final normalized = _normalizePolygon(currentPoints);
                          mapNotifier.setPoints(normalized);
                          final nearestIdx =
                              _findNearestIndex(removed, normalized);
                          mapNotifier.selectVertex(nearestIdx);
                        }
                        mapNotifier.clearSelection();
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text('Delete'),
                    ),
                    const SizedBox(width: 8),
                    // removed move button: vertices are draggable directly
                  ]),
                ),
              ),
            )
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'save_plot',
            onPressed: _saveField,
            child: const Icon(Icons.save),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'toggle_map_view',
            onPressed: () =>
                setState(() => _isSatelliteView = !_isSatelliteView),
            mini: true,
            child: Icon(_isSatelliteView ? Icons.map : Icons.satellite_alt),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'zoom_in',
            onPressed: _zoomIn,
            mini: true,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'zoom_out',
            onPressed: _zoomOut,
            mini: true,
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'locate_device',
            onPressed: _locatingDevice ? null : _centerOnCurrentLocation,
            child: _locatingDevice
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  // NOTE: _showHelpDialog was removed in favor of `showHelpDialog` defined
  // earlier in this file to avoid duplicate implementations.

  // Normalize polygon vertices by sorting points by angle around centroid.
  List<LatLng> _normalizePolygon(List<LatLng> pts) {
    if (pts.length < 3) return List<LatLng>.from(pts);
    double cx = 0, cy = 0;
    for (final p in pts) {
      cx += p.latitude;
      cy += p.longitude;
    }
    cx /= pts.length;
    cy /= pts.length;
    final center = LatLng(cx, cy);
    final withAngles = <MapEntry<double, LatLng>>[];
    for (final p in pts) {
      final angle = math.atan2(
          p.latitude - center.latitude, p.longitude - center.longitude);
      withAngles.add(MapEntry(angle, p));
    }
    withAngles.sort((a, b) => a.key.compareTo(b.key));
    return withAngles.map((e) => e.value).toList();
  }

  int? _findNearestIndex(LatLng target, List<LatLng> pts) {
    if (pts.isEmpty) return null;
    double bestDist = double.infinity;
    int bestIdx = 0;
    for (int i = 0; i < pts.length; i++) {
      final dLat = pts[i].latitude - target.latitude;
      final dLng = pts[i].longitude - target.longitude;
      final dist = dLat * dLat + dLng * dLng;
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    return bestIdx;
  }
}
