import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
            urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
            subdomains: const ['a', 'b', 'c']),
        const MyLocationLayer(),
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
