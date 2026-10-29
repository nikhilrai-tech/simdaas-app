import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/offline_tile_cache_service.dart';
import 'package:simdaas/core/utils/error_utils.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:math' as math;
// no json decoding here; geocoding handled by GeocodingService
import 'package:simdaas/core/services/geocoding_service.dart';
import 'package:latlong2/latlong.dart';
// plot providers/imports moved to helper where needed
import '../providers/map_state_providers.dart';
import '../providers/plot_providers.dart';
// Plot model and auth service used in save helper
import 'package:simdaas/core/services/location_service.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/background_save_service.dart';
import 'package:simdaas/core/widgets/buffered_save_banner.dart';
import '../../data/models/plot_model.dart';
import '../widgets/plot_save_sheet.dart';
import '../widgets/map_layers.dart';
import '../widgets/historical_map_picker_sheet.dart';
import '../utils/plot_kml.dart';
import '../utils/historical_map_service.dart';
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
  final _bufferedSave = BufferedSaveController();
  bool _locatingDevice = false;
  bool _isSatelliteView = true;
  // Active historical-imagery overlay, if any -- see
  // historical_map_picker_sheet.dart. Null (the default) means the normal
  // current-map tiles render exactly as before; set only while a farmer has
  // explicitly chosen to view a past date, and cleared the same way. One
  // composite image covering the viewport bounds at the moment it was
  // fetched, not an XYZ tile pyramid -- see historical_map_service.dart.
  Uint8List? _historicalImageBytes;
  LatLngBounds? _historicalImageBounds;
  String? _historicalProviderId;
  DateTime? _historicalDate;
  // Latest fix from MapLayers' own live MyLocationLayer stream. Reused by
  // the "center on me" button instead of starting a second, competing
  // GPS request (see _centerOnCurrentLocation).
  LatLng? _liveStreamPosition;
  Offset? _lastPointerPosition;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // (multi-pointer centroid removed; we use simple single-touch drag for vertices)
  double _computeAreaAcres(List<LatLng> poly) {
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
    // Matches ACRE_SQM in the backend (session_service.py).
    return area / 4046.8564224; // acres
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
    _bufferedSave.addListener(() {
      if (mounted) setState(() {});
    });
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

    // If no initial data, try to move to device's current location. Same
    // fast-then-accurate pattern as _centerOnCurrentLocation() below: a
    // cached last-known fix resolves near-instantly (no live GPS wait), so
    // the map moves off flutter_map's placeholder default on essentially
    // the next frame instead of sitting there for however long a fresh GPS
    // fix takes (can be several seconds, longer indoors/cold start) --
    // then the accurate fix refines it once it's ready.
    if (widget.initialCenter == null &&
        (widget.initialPoints == null || widget.initialPoints!.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        bool movedOnce = false;
        try {
          final lastKnown = await LocationService().getLastKnownLocation();
          if (lastKnown != null && mounted) {
            _mapController.move(lastKnown, 18.0);
            movedOnce = true;
          }
        } catch (e, st) {
          debugPrint('map_screen.initState.getLastKnownLocation error: $e\n$st');
        }
        try {
          final loc = await LocationService().getCurrentLocation();
          // ignore invalid fallback (0,0)
          if (mounted && (loc.latitude != 0 || loc.longitude != 0)) {
            _mapController.move(loc, 18.0);
          }
        } catch (e, st) {
          if (!movedOnce) {
            debugPrint('map_screen.initState.getCurrentLocation error: $e\n$st');
          }
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
    _bufferedSave.dispose();
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

    final pendingModel = await showPlotSaveSheet(
        context, ref, normalizedPoints, _computeAreaAcres,
        existingPlot: widget.existingPlot);
    if (pendingModel == null) return;

    final repo = ref.read(plotRepoProvider);
    final isEditing = widget.existingPlot != null;
    var savedModel = pendingModel;

    // Buffered save: see BackgroundSaveService's doc comment. The AB-line
    // prompt below only fires from onSuccess, using the confirmed saved
    // model -- if the user discards/navigates away before the save actually
    // completes, they simply don't get prompted here (never builds row
    // lines on a plot that may not have been created).
    _bufferedSave.start();
    Future<void> saveAction() async {
      if (isEditing) {
        await repo.updatePlot(pendingModel);
      } else {
        savedModel = await repo.addPlot(pendingModel);
      }
    }

    unawaited(ref.read(backgroundSaveServiceProvider).run(
      action: saveAction,
      successMessage: isEditing ? 'Plot updated' : 'Plot saved',
      onSuccess: () async {
        final currentUserId =
            ref.read(authServiceProvider).currentUserId ?? 'demo_user';
        ref.invalidate(plotsListProvider(currentUserId));
        if (!mounted) return;
        await _promptRowLinePlotting(savedModel);
      },
      onSettled: [
        () {
          if (mounted) _bufferedSave.finish();
        },
      ],
    ));
  }

  Future<void> _promptRowLinePlotting(PlotModel savedPlot) async {
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
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  /// Create a new plot straight from a KML file's boundary (+ row lines, if
  /// present) instead of manually tapping out the polygon and (optionally)
  /// generating AB lines. Only available while creating a brand new plot
  /// (widget.existingPlot == null) -- importing onto an EXISTING plot isn't
  /// offered here; see plot_details_screen.dart's own Export-only menu.
  Future<void> _importFromKml() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['kml'],
      );
      if (picked.isEmpty) return; // user cancelled

      final kmlText = utf8.decode(await picked.first.readAsBytes());
      final parsed = parsePlotKml(kmlText);
      if (parsed.polygon == null || parsed.polygon!.length < 3) {
        if (mounted) {
          showGenericErrorSnackBar(
              context, 'This KML has no plot boundary to import.');
        }
        return;
      }
      if (!mounted) return;

      final normalizedPoints = _normalizePolygon(parsed.polygon!);
      ref.read(mapStateProvider.notifier).setPoints(normalizedPoints);

      // Carries the imported row lines through showPlotSaveSheet (it copies
      // existingPlot?.rowLines onto the PlotModel it returns) without
      // pre-filling the name/area/etc. fields a REAL existing plot would --
      // this one only exists to smuggle rowLines through, it's never saved
      // itself and its id is never looked at beyond the sheet's own
      // duplicate-name check (which it can't collide with).
      final importedRowsCarrier = parsed.rowLines.isEmpty
          ? null
          : PlotModel(
              id: '__kml_import__',
              name: '',
              polygon: normalizedPoints,
              rowLines: parsed.rowLines,
            );

      final pendingModel = await showPlotSaveSheet(
          context, ref, normalizedPoints, _computeAreaAcres,
          existingPlot: importedRowsCarrier);
      if (pendingModel == null) return;

      final repo = ref.read(plotRepoProvider);
      var savedModel = pendingModel;

      _bufferedSave.start();
      unawaited(ref.read(backgroundSaveServiceProvider).run(
        action: () async {
          savedModel = await repo.addPlot(pendingModel);
        },
        successMessage: 'Plot imported from KML',
        onSuccess: () async {
          final currentUserId =
              ref.read(authServiceProvider).currentUserId ?? 'demo_user';
          ref.invalidate(plotsListProvider(currentUserId));
          if (!mounted) return;
          if (parsed.rowLines.isEmpty) {
            // Boundary only -- fall back to the normal AB-line prompt so
            // the plot still ends up with row lines one way or another.
            await _promptRowLinePlotting(savedModel);
          } else {
            // Boundary AND row lines both came from the file -- nothing
            // left to do.
            Navigator.of(context).pop(true);
          }
        },
        onSettled: [
          () {
            if (mounted) _bufferedSave.finish();
          },
        ],
      ));
    } on FormatException catch (e) {
      if (mounted) showGenericErrorSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showGenericErrorSnackBar(context, 'Failed to import KML — $e');
    }
  }

  Future<void> _openHistoricalMapPicker() async {
    final result = await showHistoricalMapPicker(
      context,
      ref,
      isActive: _historicalImageBytes != null,
      initialProviderId: _historicalProviderId,
      initialDate: _historicalDate,
      onPreview: _applyHistoricalSelection,
    );
    if (result is HistoricalMapClear && mounted) {
      setState(() {
        _historicalImageBytes = null;
        _historicalImageBounds = null;
        _historicalProviderId = null;
        _historicalDate = null;
      });
    }
  }

  /// Fetches and applies one provider/date live -- called by the picker
  /// sheet on every arrow tap/provider change while it's still open, not
  /// just once when it closes, so the map updates as the farmer browses.
  /// Fetches ONE image covering the current viewport (see
  /// historical_map_service.dart), not a tile pyramid.
  Future<void> _applyHistoricalSelection(String providerId, DateTime date) async {
    final bounds = _mapController.camera.visibleBounds;
    if (_mapController.camera.zoom < historicalMapMinZoom) {
      if (mounted) {
        showGenericErrorSnackBar(
          context, 'Zoom in to your field to see historical imagery.');
      }
      return;
    }
    try {
      final bytes = await ref.read(historicalMapServiceProvider).getRegionImage(
            providerId: providerId,
            date: date,
            bounds: bounds,
          );
      if (!mounted) return;
      setState(() {
        _historicalImageBytes = bytes;
        _historicalImageBounds = bounds;
        _historicalProviderId = providerId;
        _historicalDate = date;
      });
    } catch (e) {
      if (mounted) {
        showGenericErrorSnackBar(context, 'Could not load historical map — $e');
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
          if (widget.existingPlot == null)
            IconButton(
              tooltip: 'Import from KML',
              icon: const Icon(Icons.file_upload_outlined),
              onPressed: _importFromKml,
            ),
          IconButton(
            tooltip: 'Historical map',
            icon: Icon(_historicalImageBytes != null ? Icons.history_toggle_off : Icons.history),
            onPressed: _openHistoricalMapPicker,
          ),
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
            historicalImageBytes: _historicalImageBytes,
            historicalImageBounds: _historicalImageBounds,
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
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: BufferedSaveBanner(
              controller: _bufferedSave,
              label: widget.existingPlot != null
                  ? 'Updating plot…'
                  : 'Saving plot…',
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'save_plot',
            onPressed: _bufferedSave.isSaving ? null : _saveField,
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
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'download_offline',
            tooltip: 'Download map for offline use',
            mini: true,
            onPressed: points.length < 3
                ? null
                : () => _showDownloadOfflineSheet(context, points),
            child: const Icon(Icons.download_for_offline_outlined),
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

  // "Download for offline" -- lets a layer-select + tile-count-estimate +
  // progress sheet (same shape as the reference app's own "select the
  // layer to download" flow) pre-fetch every tile covering this plot's
  // drawn boundary (padded so panning slightly past the edge still hits
  // cache) at a zoom range useful for field work. Once downloaded, this
  // same plot loads instantly on this screen and on the monitoring screen
  // (both now use CachedTileProvider) even with no/poor connectivity.
  static const int _offlineMinZoom = 15;
  static const int _offlineMaxZoom = 20;

  Future<void> _showDownloadOfflineSheet(BuildContext context, List<LatLng> points) async {
    final bounds = paddedBoundsForPoints(points);
    bool wantSatellite = true;
    bool wantNormal = true;
    bool downloading = false;
    bool cancelled = false;
    OfflineDownloadProgress? progress;

    List<String> templatesFor(bool sat, bool normal) => [
          if (sat) 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
          if (normal) 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
        ];

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      enableDrag: !downloading,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheetState) {
          final selectedCount = (wantSatellite ? 1 : 0) + (wantNormal ? 1 : 0);
          final tileEstimate = selectedCount == 0
              ? 0
              : estimateTileCount(
                  bounds: bounds,
                  minZoom: _offlineMinZoom,
                  maxZoom: _offlineMaxZoom,
                  templateCount: selectedCount,
                );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Download map for offline use',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (!downloading)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'So this plot loads instantly here and on the monitoring '
                    'screen, even with no signal in the field.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: wantSatellite,
                    onChanged: downloading
                        ? null
                        : (v) => setSheetState(() => wantSatellite = v ?? false),
                    title: const Text('Satellite'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: wantNormal,
                    onChanged: downloading
                        ? null
                        : (v) => setSheetState(() => wantNormal = v ?? false),
                    title: const Text('Normal'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedCount == 0
                        ? 'Pick at least one map type'
                        : '~$tileEstimate tiles to check/download',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (selectedCount == 0 || downloading)
                          ? null
                          : () async {
                              setSheetState(() => downloading = true);
                              final result = await downloadRegion(
                                bounds: bounds,
                                minZoom: _offlineMinZoom,
                                maxZoom: _offlineMaxZoom,
                                urlTemplates: templatesFor(wantSatellite, wantNormal),
                                isCancelled: () => cancelled,
                                onProgress: (p) {
                                  progress = p;
                                  setSheetState(() {});
                                },
                              );
                              if (!sheetContext.mounted) return;
                              Navigator.of(sheetContext).pop();
                              if (context.mounted) {
                                showSuccessSnackBar(
                                  context,
                                  result.failed > 0
                                      ? 'Downloaded for offline use (${result.failed} tiles failed, will retry live)'
                                      : 'Downloaded for offline use',
                                );
                              }
                            },
                      child: downloading
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                ),
                                const SizedBox(width: 10),
                                Text(progress == null
                                    ? 'Starting…'
                                    : '${progress!.done} / ${progress!.total}'),
                              ],
                            )
                          : const Text('Download'),
                    ),
                  ),
                  if (downloading) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          cancelled = true;
                        },
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        });
      },
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
