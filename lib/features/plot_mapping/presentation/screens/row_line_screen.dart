import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/utils/error_utils.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';

import 'package:simdaas/core/services/location_service.dart';
import 'package:simdaas/core/services/offline_tile_cache_service.dart';
import 'package:simdaas/core/widgets/my_location_layer.dart';
import '../../data/models/plot_model.dart';
import '../providers/plot_providers.dart';
import '../utils/corridor_strip.dart';
import '../utils/row_line_generator.dart';
import '../utils/historical_map_service.dart';
import '../widgets/historical_map_picker_sheet.dart';

enum _Mode { guide, manual }

class RowLineScreen extends ConsumerStatefulWidget {
  final PlotModel plot;
  const RowLineScreen({super.key, required this.plot});

  @override
  ConsumerState<RowLineScreen> createState() => _RowLineScreenState();
}

class _RowLineScreenState extends ConsumerState<RowLineScreen> {
  final MapController _mapController = MapController();
  // Active historical-imagery overlay, if any -- see
  // historical_map_picker_sheet.dart. Null (the default) means the normal
  // current-map tiles render exactly as before.
  HistoricalMapTileSource? _historicalTileSource;
  String? _historicalProviderId;
  DateTime? _historicalDate;

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
  // Captured when a drag starts: the row as it was, and how far (metres,
  // positive = to the row's left) the finger has slid it since. A drag moves
  // the WHOLE row sideways across its corridor (a parallel shift, re-clipped
  // to the plot boundary) -- it never pivots around the far end.
  List<LatLng>? _dragOrigRow;
  double _dragShiftMeters = 0.0;

  // Manual rotate state -- separate from drag-shift above. Only Row 1 (index
  // 0, the first row the guide-line fill produced) carries a rotate handle;
  // rotating it rotates EVERY row by the same angle, each pivoting around
  // its own midpoint and independently re-clipped to the plot. Rotating rows
  // independently let their angles drift apart, which broke the row-corridor
  // area calculation (each corridor's width/tolerance is derived from its
  // own current gap to its neighbours -- see row_line_coverage.dart) every
  // time one row's shape changed relative to the rest. Tapping the handle
  // snapshots every row's current line as the pivot baseline; every +/-0.1°
  // step re-rotates all of them from that same baseline, capped at +-10°
  // total.
  int? _selectedRow;
  List<List<LatLng>>? _rotateOrigRows;
  double _rotateDegrees = 0.0;
  static const double _maxRotateDegrees = 10.0;
  static const double _rotateStepDegrees = 0.1;

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
      _selectedRow = null;
      _rotateOrigRows = null;
      _rotateDegrees = 0.0;
      if (rows.isNotEmpty) _mode = _Mode.manual;
    });
    if (rows.isEmpty) {
      showInfoSnackBar(context, 'Guide line does not intersect the plot polygon.');
    }
  }

  Future<void> _openHistoricalMapPicker() async {
    final result = await showHistoricalMapPicker(
      context,
      ref,
      isActive: _historicalTileSource != null,
      initialProviderId: _historicalProviderId,
      initialDate: _historicalDate,
      onPreview: _applyHistoricalSelection,
    );
    if (result is HistoricalMapClear && mounted) {
      setState(() {
        _historicalTileSource = null;
        _historicalProviderId = null;
        _historicalDate = null;
      });
    }
  }

  /// Fetches and applies one provider/date live -- called by the picker
  /// sheet on every arrow tap/provider change while it's still open, not
  /// just once when it closes, so the map updates as the farmer browses.
  Future<void> _applyHistoricalSelection(String providerId, DateTime date) async {
    try {
      final source = await ref.read(historicalMapServiceProvider).getTileSource(
            providerId: providerId,
            date: date,
          );
      if (!mounted) return;
      setState(() {
        _historicalTileSource = source;
        _historicalProviderId = providerId;
        _historicalDate = date;
      });
    } catch (e) {
      if (mounted) {
        showGenericErrorSnackBar(context, 'Could not load historical map — $e');
      }
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

  // ── Manual-edit constraints (parallel shift + no crossing) ───────────────

  /// Walks past deleted rows (empty placeholders left by the row-delete
  /// button — see [_buildRowDeleteMarkers]) to find the nearest REAL
  /// neighboring row in [direction] (-1 = toward index 0, +1 = toward the
  /// end), so a row next to a deleted one is still limited by the next real
  /// row beyond the gap.
  List<LatLng>? _nearestRealRow(int fromIdx, int direction) {
    int i = fromIdx + direction;
    while (i >= 0 && i < _rowLines.length) {
      if (_rowLines[i].length > 1) return _rowLines[i];
      i += direction;
    }
    return null;
  }

  /// Allowed sideways range (metres, positive = row's left) for shifting
  /// [orig], so it can't cross or touch its nearest real neighbours.
  ({double lower, double upper}) _shiftLimits(int rowIdx, List<LatLng> orig) {
    const gap = 0.3;
    var lower = -double.infinity, upper = double.infinity;
    for (final dir in const [-1, 1]) {
      final nb = _nearestRealRow(rowIdx, dir);
      if (nb == null) continue;
      final d0 = RowLineGeometry.signedDistance(orig, nb[0]);
      final d1 = RowLineGeometry.signedDistance(orig, nb[1]);
      if (d0 > 0 && d1 > 0) {
        upper = math.min(upper, math.min(d0, d1) - gap);
      } else if (d0 < 0 && d1 < 0) {
        lower = math.max(lower, math.max(d0, d1) + gap);
      }
    }
    return (lower: lower, upper: upper);
  }

  /// Whether every adjacent pair of REAL rows in [candidate] still keeps a
  /// clear, consistent-side gap from each other. Used when rotating ALL rows
  /// together (see [_applyRotation]) -- two rows that were each individually
  /// fine against their *original* neighbours can still end up crossing once
  /// both have moved, so the whole candidate set is checked pairwise rather
  /// than each row against a static baseline.
  bool _allRowsClearEachOther(List<List<LatLng>> candidate) {
    const gap = 0.3;
    for (int i = 0; i < candidate.length; i++) {
      if (candidate[i].length < 2) continue;
      int j = i + 1;
      while (j < candidate.length && candidate[j].length < 2) {
        j++;
      }
      if (j >= candidate.length) continue;
      final a = candidate[i];
      final b = candidate[j];
      final d0 = RowLineGeometry.signedDistance(a, b[0]);
      final d1 = RowLineGeometry.signedDistance(a, b[1]);
      final clearPositive = d0 > gap && d1 > gap;
      final clearNegative = d0 < -gap && d1 < -gap;
      if (!clearPositive && !clearNegative) return false;
    }
    return true;
  }

  void _selectRowForRotation(int rowIdx) {
    setState(() {
      _draggingRow = null;
      _draggingEnd = null;
      _selectedRow = rowIdx;
      _rotateOrigRows = _rowLines.map((r) => List<LatLng>.from(r)).toList();
      _rotateDegrees = 0.0;
    });
  }

  void _applyRotation(double delta) {
    final origRows = _rotateOrigRows;
    if (origRows == null) return;
    final newDegrees = (_rotateDegrees + delta).clamp(-_maxRotateDegrees, _maxRotateDegrees);
    if (newDegrees == _rotateDegrees) return;
    final candidate = <List<LatLng>>[];
    for (final row in origRows) {
      if (row.length < 2) {
        candidate.add(row);
        continue;
      }
      final rotated = RowLineGeometry.rotateRow(
        row: row,
        degrees: newDegrees,
        polygon: widget.plot.polygon,
      );
      // Any single row failing to fit at this angle aborts the whole batch --
      // better to hold at the last angle every row agreed on than to apply a
      // partial rotation that leaves the set inconsistent.
      if (rotated == null) return;
      candidate.add(rotated);
    }
    if (!_allRowsClearEachOther(candidate)) return;
    setState(() {
      _rotateDegrees = newDegrees;
      _rowLines = candidate;
    });
  }

  void _finishRotating() {
    setState(() {
      _selectedRow = null;
      _rotateOrigRows = null;
      _rotateDegrees = 0.0;
    });
  }

  // ── Map overlay builders ─────────────────────────────────────────────────

  List<Polyline> _buildRowPolylines() {
    // Rotation always moves every row together (see [_applyRotation]), so
    // while it's active every row is highlighted, not just Row 1.
    final rotating = _selectedRow != null;
    return [
      for (int r = 0; r < _rowLines.length; r++)
        if (_rowLines[r].length >= 2)
          Polyline(
            points: _rowLines[r],
            color: rotating ? Colors.cyanAccent.withAlpha(230) : Colors.yellow.withAlpha(200),
            strokeWidth: rotating ? 3.5 : 2.5,
          ),
    ];
  }

  /// Point a fraction [t] of the way from [a] to [b] -- used to place the
  /// rotate handle a bit off the row's midpoint (where the delete button
  /// already sits) without needing a separate metres-based offset.
  LatLng _lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  /// Only Row 1 (index 0) gets a rotate handle -- rotating it rotates every
  /// row together (see [_applyRotation] and the field comment on
  /// [_rotateOrigRows] for why independent per-row rotation was removed).
  List<Marker> _buildRowRotateMarkers() {
    if (_mode != _Mode.manual) return [];
    if (_rowLines.isEmpty || _rowLines[0].length < 2) return [];
    final seg = _rowLines[0];
    final selected = _selectedRow == 0;
    return [
      Marker(
        point: _lerpLatLng(seg[0], seg[1], 0.35),
        width: 26,
        height: 26,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selectRowForRotation(0),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (selected ? Colors.cyanAccent : Colors.blue).withAlpha(230),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(Icons.rotate_right, size: 15, color: Colors.white),
          ),
        ),
      ),
    ];
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
                _dragOrigRow = List<LatLng>.from(_rowLines[rowIdx]);
                _dragShiftMeters = 0.0;
                // A shift-drag and a pending rotation both edit row lines
                // from their own snapshot; starting one abandons the other
                // instead of leaving a stale baseline.
                _selectedRow = null;
                _rotateOrigRows = null;
                _rotateDegrees = 0.0;
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
                final orig = _dragOrigRow;
                if (orig == null || orig.length < 2) return;
                // Finger movement (metres, east/north) projected onto the
                // row's own left-normal = how far it moved ACROSS the row.
                final cosLat = math.cos(orig[0].latitude * math.pi / 180.0);
                final dx = (currLL.longitude - lastLL.longitude) * cosLat * 111320.0;
                final dy = (currLL.latitude - lastLL.latitude) * 111320.0;
                final n = RowLineGeometry.leftNormal(orig);
                final limits = _shiftLimits(rowIdx, orig);
                final target = (_dragShiftMeters + dx * n.x + dy * n.y)
                    .clamp(limits.lower, limits.upper)
                    .toDouble();
                final shifted = RowLineGeometry.shiftRow(
                  row: orig,
                  lateralMeters: target,
                  polygon: widget.plot.polygon,
                );
                setState(() {
                  _lastPointerPos = ev.position;
                  // Shifted out of the plot entirely: hold the last valid
                  // position instead of letting the row leave the field.
                  if (shifted == null) return;
                  _dragShiftMeters = target;
                  _rowLines = List<List<LatLng>>.from(_rowLines)
                    ..[rowIdx] = shifted;
                });
              } catch (_) {
                _lastPointerPos = ev.position;
              }
            },
            onPointerUp: (_) => setState(() {
              _draggingRow = null;
              _draggingEnd = null;
              _lastPointerPos = null;
              _dragOrigRow = null;
              _dragShiftMeters = 0.0;
            }),
            onPointerCancel: (_) => setState(() {
              _draggingRow = null;
              _draggingEnd = null;
              _lastPointerPos = null;
              _dragOrigRow = null;
              _dragShiftMeters = 0.0;
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

  List<Marker> _buildRowDeleteMarkers() {
    if (_mode != _Mode.manual) return [];
    final markers = <Marker>[];
    for (int r = 0; r < _rowLines.length; r++) {
      final seg = _rowLines[r];
      if (seg.length < 2) continue;
      final mid = LatLng(
        (seg[0].latitude + seg[1].latitude) / 2,
        (seg[0].longitude + seg[1].longitude) / 2,
      );
      final rowIdx = r;
      markers.add(Marker(
        point: mid,
        width: 26,
        height: 26,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _draggingRow = null;
            _draggingEnd = null;
            // A rotation in progress snapshots EVERY row (see
            // _rotateOrigRows) -- deleting any one of them, not just the
            // selected row, invalidates that snapshot.
            if (_selectedRow != null) {
              _selectedRow = null;
              _rotateOrigRows = null;
              _rotateDegrees = 0.0;
            }
            // Replace with an empty placeholder rather than removing the
            // slot outright — this preserves every other row's index and,
            // crucially, leaves a marker at this exact position so the
            // coverage heatmap knows a row used to be here and treats the
            // (now larger) gap to each remaining neighbor as two separate
            // narrow bands instead of one oversized merged corridor. See
            // RowLineCoverage.buildHeatmapCoverageBands.
            final newLines = List<List<LatLng>>.from(_rowLines);
            newLines[rowIdx] = <LatLng>[];
            _rowLines = newLines;
          }),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withAlpha(230),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(Icons.close, size: 16, color: Colors.white),
          ),
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final guideComplete = _guideStart != null && _guideEnd != null;

    return Scaffold(
      appBar: AppBar(
        // Taller than the default 56dp toolbar to give the row-count
        // subtitle room without clipping at larger OS text-scale settings.
        toolbarHeight: 64,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Row Lines — ${widget.plot.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_rowLines.length} row${_rowLines.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.75) ??
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Historical map',
            icon: Icon(_historicalTileSource != null ? Icons.history_toggle_off : Icons.history),
            onPressed: _openHistoricalMapPicker,
          ),
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
                urlTemplate: 'https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                // Cache-first -- same disk cache map_screen.dart/
                // monitoring_screen.dart already use, so a plot seen before
                // (here or on either of those screens, since the cache key
                // is just the tile URL) loads instantly with no network
                // round-trip at all.
                tileProvider: CachedTileProvider(),
              ),
              // Historical-imagery overlay (see historical_map_picker_sheet.dart)
              // -- null until a farmer explicitly picks one, same as map_screen.dart.
              if (_historicalTileSource != null)
                TileLayer(
                  urlTemplate: _historicalTileSource!.urlTemplate,
                  tileProvider: RetryingNetworkTileProvider(headers: _historicalTileSource!.headers),
                  minZoom: historicalMapMinZoom,
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
              // Row delete buttons (midpoint of each row)
              if (_rowLines.isNotEmpty)
                MarkerLayer(markers: _buildRowDeleteMarkers()),
              // Row rotate-select buttons (just off midpoint of each row)
              if (_rowLines.isNotEmpty)
                MarkerLayer(markers: _buildRowRotateMarkers()),
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
                    else if (_selectedRow != null)
                      _rotateControls()
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
                : 'Drag an orange handle to slide that row sideways. Tap the blue ↻ on Row 1 to angle all rows together. Tap the red ✕ to delete a row.',
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
              _selectedRow = null;
              _rotateOrigRows = null;
              _rotateDegrees = 0.0;
            }),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reset'),
          ),
      ],
    );
  }

  /// Shown instead of [_manualInstructions] while rotation is active -- a
  /// small +-0.1° stepper, capped at +-10° from wherever the rows were when
  /// Row 1's handle was tapped (see [_selectRowForRotation]). Every row
  /// rotates together, not just Row 1.
  Widget _rotateControls() {
    final atMin = _rotateDegrees <= -_maxRotateDegrees;
    final atMax = _rotateDegrees >= _maxRotateDegrees;
    return Row(
      children: [
        const Text(
          'All rows angle',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Rotate -0.1°',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: atMin ? null : () => _applyRotation(-_rotateStepDegrees),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${_rotateDegrees >= 0 ? '+' : ''}${_rotateDegrees.toStringAsFixed(1)}°',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(
          tooltip: 'Rotate +0.1°',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: atMax ? null : () => _applyRotation(_rotateStepDegrees),
        ),
        const Spacer(),
        TextButton(
          onPressed: _finishRotating,
          child: const Text('Done'),
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

