import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/utils/error_utils.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

import 'package:simdaas/core/services/location_service.dart';
import 'package:simdaas/core/widgets/my_location_layer.dart';
import '../../data/models/plot_model.dart';
import '../providers/plot_providers.dart';
import '../utils/row_line_generator.dart';

enum _Mode { guide, manual }

class RowLineScreen extends ConsumerStatefulWidget {
  final PlotModel plot;
  const RowLineScreen({super.key, required this.plot});

  @override
  ConsumerState<RowLineScreen> createState() => _RowLineScreenState();
}

class _RowLineScreenState extends ConsumerState<RowLineScreen> {
  final MapController _mapController = MapController();

  _Mode _mode = _Mode.guide;

  // Guide line state
  LatLng? _guideStart;
  LatLng? _guideEnd;

  // Row line state
  List<List<LatLng>> _rowLines = [];

  // Manual drag state
  Offset? _lastPointerPos;
  int? _draggingRow;
  int? _draggingEnd; // 0 = start, 1 = end

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Pre-load any previously saved row lines.
    final existing = widget.plot.rowLines;
    if (existing != null && existing.isNotEmpty) {
      _rowLines = existing.map((seg) => List<LatLng>.from(seg)).toList();
    }
    // Center map on polygon.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.plot.polygon.isNotEmpty) {
        var sumLat = 0.0, sumLon = 0.0;
        for (final p in widget.plot.polygon) {
          sumLat += p.latitude;
          sumLon += p.longitude;
        }
        _mapController.move(
          LatLng(sumLat / widget.plot.polygon.length,
              sumLon / widget.plot.polygon.length),
          18.0,
        );
      }
    });
  }

  void _onMapTap(TapPosition _, LatLng latlng) {
    if (_mode != _Mode.guide) return;
    setState(() {
      if (_guideStart == null) {
        _guideStart = latlng;
        _guideEnd = null;
      } else if (_guideEnd == null) {
        _guideEnd = latlng;
      } else {
        // Third tap resets guide line.
        _guideStart = latlng;
        _guideEnd = null;
        _rowLines = [];
      }
    });
  }

  void _fillRowLines() {
    if (_guideStart == null || _guideEnd == null) return;
    final spacing = widget.plot.rowSpacing ?? 3.0;
    if (spacing <= 0) {
      showInfoSnackBar(context, 'Row spacing must be > 0. Edit plot details first.');
      return;
    }
    final rows = RowLineGenerator.generate(
      guideStart: _guideStart!,
      guideEnd: _guideEnd!,
      polygon: widget.plot.polygon,
      rowSpacing: spacing,
    );
    setState(() {
      _rowLines = rows;
      if (rows.isNotEmpty) _mode = _Mode.manual;
    });
    if (rows.isEmpty) {
      showInfoSnackBar(context, 'Guide line does not intersect the plot polygon.');
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final updated = PlotModel(
        id: widget.plot.id,
        name: widget.plot.name,
        userId: widget.plot.userId,
        area: widget.plot.area,
        treeCount: widget.plot.treeCount,
        rowSpacing: widget.plot.rowSpacing,
        polygon: widget.plot.polygon,
        centroid: widget.plot.centroid,
        bedHeight: widget.plot.bedHeight,
        createdAt: widget.plot.createdAt,
        rowLines: _rowLines.isEmpty ? null : _rowLines,
      );
      final repo = ref.read(plotRepoProvider);
      await repo.updatePlot(updated);

      final uid = ref.read(authServiceProvider).currentUserId;
      if (uid != null) ref.invalidate(plotsListProvider(uid));

      if (mounted) {
        showSuccessSnackBar(context, 'Row lines saved');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showPolishedError(context, e, fallback: 'Failed to save row lines');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Map tool actions ─────────────────────────────────────────────────────

  void _zoomIn() {
    final cam = _mapController.camera;
    _mapController.move(cam.center, (cam.zoom + 1).clamp(5.0, 22.0));
  }

  void _zoomOut() {
    final cam = _mapController.camera;
    _mapController.move(cam.center, (cam.zoom - 1).clamp(5.0, 22.0));
  }

  Future<void> _centerOnLocation() async {
    try {
      final loc = await LocationService().getCurrentLocation();
      _mapController.move(loc, 18.0);
    } catch (e) {
      if (mounted) showPolishedError(context, e, fallback: 'Location error');
    }
  }

  // ── Boundary snapping helpers ────────────────────────────────────────────

  LatLng _clampToBoundary(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return point;
    if (_isInsidePolygon(point, polygon)) return point;
    LatLng nearest = polygon.first;
    double minDistSq = double.infinity;
    for (int i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final c = _nearestPointOnSegment(point, a, b);
      final d = _distanceSq(point, c);
      if (d < minDistSq) {
        minDistSq = d;
        nearest = c;
      }
    }
    return nearest;
  }

  bool _isInsidePolygon(LatLng p, List<LatLng> poly) {
    int crossings = 0;
    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      if (((a.longitude <= p.longitude) && (p.longitude < b.longitude)) ||
          ((b.longitude <= p.longitude) && (p.longitude < a.longitude))) {
        final lat = a.latitude +
            (p.longitude - a.longitude) *
                (b.latitude - a.latitude) /
                (b.longitude - a.longitude);
        if (p.latitude < lat) crossings++;
      }
    }
    return crossings.isOdd;
  }

  LatLng _nearestPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final dx = b.latitude - a.latitude;
    final dy = b.longitude - a.longitude;
    if (dx == 0 && dy == 0) return a;
    final t = ((p.latitude - a.latitude) * dx + (p.longitude - a.longitude) * dy) /
        (dx * dx + dy * dy);
    final tc = t.clamp(0.0, 1.0);
    return LatLng(a.latitude + tc * dx, a.longitude + tc * dy);
  }

  double _distanceSq(LatLng a, LatLng b) {
    final dlat = a.latitude - b.latitude;
    final dlon = a.longitude - b.longitude;
    return dlat * dlat + dlon * dlon;
  }

  // ── Map overlay builders ─────────────────────────────────────────────────

  List<Polyline> _buildRowPolylines() {
    return _rowLines.map((seg) {
      return Polyline(
        points: seg,
        color: Colors.yellow.withAlpha(200),
        strokeWidth: 2.5,
      );
    }).toList();
  }

  List<Marker> _buildRowEndpointMarkers() {
    if (_mode != _Mode.manual) return [];
    final markers = <Marker>[];
    for (int r = 0; r < _rowLines.length; r++) {
      final seg = _rowLines[r];
      for (int e = 0; e < 2 && e < seg.length; e++) {
        final pt = seg[e];
        final rowIdx = r;
        final endIdx = e;
        markers.add(Marker(
          point: pt,
          width: 36,
          height: 36,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (ev) {
              setState(() {
                _draggingRow = rowIdx;
                _draggingEnd = endIdx;
                _lastPointerPos = ev.position;
              });
            },
            onPointerMove: (ev) {
              if (_draggingRow != rowIdx || _draggingEnd != endIdx) return;
              if (_lastPointerPos == null) return;
              try {
                final camera = _mapController.camera;
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                final lastLocal = box.globalToLocal(_lastPointerPos!);
                final currLocal = box.globalToLocal(ev.position);
                final lastLL = camera.offsetToCrs(Offset(lastLocal.dx, lastLocal.dy));
                final currLL = camera.offsetToCrs(Offset(currLocal.dx, currLocal.dy));
                final dLat = currLL.latitude - lastLL.latitude;
                final dLon = currLL.longitude - lastLL.longitude;
                setState(() {
                  final newSeg = List<LatLng>.from(_rowLines[rowIdx]);
                  final moved = LatLng(
                    newSeg[endIdx].latitude + dLat,
                    newSeg[endIdx].longitude + dLon,
                  );
                  newSeg[endIdx] = _clampToBoundary(moved, widget.plot.polygon);
                  _rowLines = List<List<LatLng>>.from(_rowLines)..[rowIdx] = newSeg;
                  _lastPointerPos = ev.position;
                });
              } catch (_) {
                _lastPointerPos = ev.position;
              }
            },
            onPointerUp: (_) => setState(() {
              _draggingRow = null;
              _draggingEnd = null;
              _lastPointerPos = null;
            }),
            onPointerCancel: (_) => setState(() {
              _draggingRow = null;
              _draggingEnd = null;
              _lastPointerPos = null;
            }),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ));
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final guideComplete = _guideStart != null && _guideEnd != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Row Lines — ${widget.plot.name}'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(
              tooltip: 'Save row lines',
              icon: const Icon(Icons.save),
              onPressed: _save,
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialZoom: 18.0,
              onTap: _mode == _Mode.guide ? _onMapTap : null,
              interactionOptions: InteractionOptions(
                flags: (_draggingRow != null)
                    ? InteractiveFlag.none
                    : InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                subdomains: const ['a', 'b', 'c'],
              ),
              const MyLocationLayer(),
              // Plot polygon
              if (widget.plot.polygon.isNotEmpty)
                PolygonLayer(polygons: [
                  Polygon(
                    points: widget.plot.polygon,
                    color: Colors.green.withAlpha(40),
                    borderColor: Colors.green,
                    borderStrokeWidth: 2.5,
                  ),
                ]),
              // Guide line
              if (_guideStart != null && _guideEnd != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: [_guideStart!, _guideEnd!],
                    color: Colors.red.withAlpha(200),
                    strokeWidth: 2.0,
                  ),
                ]),
              // Row lines
              if (_rowLines.isNotEmpty)
                PolylineLayer(polylines: _buildRowPolylines()),
              // Guide point markers
              if (_mode == _Mode.guide)
                MarkerLayer(markers: [
                  if (_guideStart != null)
                    _dotMarker(_guideStart!, Colors.red, 'S'),
                  if (_guideEnd != null)
                    _dotMarker(_guideEnd!, Colors.redAccent, 'E'),
                ]),
              // Row endpoint drag handles
              if (_rowLines.isNotEmpty)
                MarkerLayer(markers: _buildRowEndpointMarkers()),
            ],
          ),

          // ── Map tool FABs (zoom / location) ─────────────────────────────
          Positioned(
            right: 8,
            bottom: 168,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'row_zoom_in',
                  onPressed: _zoomIn,
                  tooltip: 'Zoom in',
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 6),
                FloatingActionButton.small(
                  heroTag: 'row_zoom_out',
                  onPressed: _zoomOut,
                  tooltip: 'Zoom out',
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'row_my_location',
                  onPressed: _centerOnLocation,
                  tooltip: 'My location',
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          // ── Bottom mode bar ─────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor.withAlpha(230),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mode toggle
                    SegmentedButton<_Mode>(
                      segments: const [
                        ButtonSegment(value: _Mode.guide, label: Text('Guide Line'), icon: Icon(Icons.edit)),
                        ButtonSegment(value: _Mode.manual, label: Text('Manual'), icon: Icon(Icons.tune)),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: 8),
                    // Mode-specific instructions + Fill All button
                    if (_mode == _Mode.guide)
                      _guideInstructions(guideComplete)
                    else
                      _manualInstructions(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideInstructions(bool guideComplete) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _guideStart == null
                ? 'Tap to place guide line start point'
                : _guideEnd == null
                    ? 'Tap to place guide line end point'
                    : 'Guide line set. Tap "Fill All" or tap again to reset.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (guideComplete)
          FilledButton.icon(
            onPressed: _fillRowLines,
            icon: const Icon(Icons.grid_on, size: 18),
            label: const Text('Fill All'),
          ),
      ],
    );
  }

  Widget _manualInstructions() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _rowLines.isEmpty
                ? 'Switch to Guide Line mode to generate rows first.'
                : 'Drag orange handles to adjust individual row endpoints.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (_rowLines.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() {
              _mode = _Mode.guide;
              _guideStart = null;
              _guideEnd = null;
              _rowLines = [];
            }),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reset'),
          ),
      ],
    );
  }

  Marker _dotMarker(LatLng point, Color color, String label) => Marker(
        point: point,
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      );
}

