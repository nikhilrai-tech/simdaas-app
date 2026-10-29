import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/services/offline_tile_cache_service.dart';
import 'package:simdaas/core/widgets/my_location_layer.dart';

/// Renders map tile, polygon and vertex markers and forwards pointer events
/// to callers so the parent can handle selection/move logic.
class MapLayers extends StatelessWidget {
  final MapController mapController;
  final List<LatLng> points;
  final int? selectedVertex;
  final bool absorbMap;
  final double minZoom;
  final double maxZoom;
  final void Function(TapPosition, LatLng)? onTap;
  final void Function(LatLng position)? onMyLocation;
  // true = satellite/hybrid tiles (default, unchanged look), false = plain
  // road map tiles.
  final bool isSatellite;

  // Historical-imagery overlay (see historical_map_service.dart) -- null
  // (the default, every existing caller) means no overlay at all, and the
  // normal tile layer below renders exactly as it always has. When set,
  // drawn as a single bounded image on top of the normal tile layer --
  // ONE composite image covering historicalImageBounds, not an XYZ tile
  // pyramid (see historical_map.py's module docstring for why: both
  // providers' per-tile paths had hard rate/size ceilings a real
  // viewport's burst of tile requests kept hitting).
  final Uint8List? historicalImageBytes;
  final LatLngBounds? historicalImageBounds;

  // Pointer event forwards for markers
  final void Function(int index, PointerEvent event) onMarkerPointerDown;
  final void Function(int index, PointerEvent event) onMarkerPointerMove;
  final void Function(int index, PointerEvent event) onMarkerPointerUp;
  final void Function(int index, PointerEvent event) onMarkerPointerCancel;

  const MapLayers({
    super.key,
    required this.mapController,
    required this.points,
    required this.selectedVertex,
    required this.absorbMap,
    required this.minZoom,
    required this.maxZoom,
    this.onTap,
    this.onMyLocation,
    this.isSatellite = true,
    this.historicalImageBytes,
    this.historicalImageBounds,
    required this.onMarkerPointerDown,
    required this.onMarkerPointerMove,
    required this.onMarkerPointerUp,
    required this.onMarkerPointerCancel,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        onTap: onTap,
        initialZoom: 18.0,
        minZoom: minZoom,
        maxZoom: maxZoom,
        interactionOptions: InteractionOptions(
          flags: absorbMap ? InteractiveFlag.none : InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
            urlTemplate: isSatellite
                ? 'https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                : 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
            // Real Google tile subdomains, round-robinned by {s} above --
            // a fixed single host (the old 'mt1.google.com' with no {s} in
            // the template, making this subdomains list a no-op) capped
            // every map's tile loading at one host's ~6 concurrent
            // connections no matter how many tiles a viewport needed.
            subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
            // Cache-first: tiles already downloaded (via "Download for
            // offline" on this screen) or simply seen before load instantly
            // from disk, no network round-trip. See offline_tile_cache_
            // service.dart for why this is a from-scratch implementation
            // rather than the usual flutter_map_tile_caching package (GPL).
            tileProvider: CachedTileProvider()),
        if (historicalImageBytes != null && historicalImageBounds != null)
          OverlayImageLayer(overlayImages: [
            OverlayImage(
              bounds: historicalImageBounds!,
              imageProvider: MemoryImage(historicalImageBytes!),
            ),
          ]),
        MyLocationLayer(onPosition: onMyLocation),
        if (points.isNotEmpty) ...[
          PolygonLayer(polygons: [
            Polygon(
                points: points,
                color: Colors.blue.withAlpha(77),
                borderStrokeWidth: 3.0,
                borderColor: Colors.blue)
          ]),
          MarkerLayer(
            markers: List.generate(points.length, (i) {
              final p = points[i];
              return Marker(
                point: p,
                width: 44,
                height: 44,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) => onMarkerPointerDown(i, event),
                  onPointerMove: (event) => onMarkerPointerMove(i, event),
                  onPointerUp: (event) => onMarkerPointerUp(i, event),
                  onPointerCancel: (event) => onMarkerPointerCancel(i, event),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selectedVertex == i ? Colors.red : Colors.white,
                      border: Border.all(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
              );
            }),
          ),
        ]
      ],
    );
  }
}
