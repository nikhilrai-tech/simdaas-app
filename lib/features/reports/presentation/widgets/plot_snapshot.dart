import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:ui' as ui;
import '../../../plot_mapping/domain/entities/plot.dart';

class PlotSnapshot extends StatefulWidget {
  final PlotEntity? plot;
  final String? base64Image; // Base64-encoded PNG from backend
  final double height;

  const PlotSnapshot({
    this.plot,
    this.base64Image,
    this.height = 200,
    super.key,
  });

  @override
  State<PlotSnapshot> createState() => _PlotSnapshotState();
}

class _PlotSnapshotState extends State<PlotSnapshot> {
  // Only relevant to the client-side live-tile render path below — the
  // base64Image path is a static PNG with no tiles to toggle.
  bool _isSatelliteView = true;

  PlotEntity? get plot => widget.plot;
  String? get base64Image => widget.base64Image;
  double get height => widget.height;

  @override
  Widget build(BuildContext context) {
    // Priority 1: Use base64 image if available
    if (base64Image != null && base64Image!.isNotEmpty) {
      try {
        final Uint8List imageBytes = base64Decode(base64Image!);
        return Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // If image decode fails, fall through to client-side rendering
                return _buildClientSideRender(context);
              },
            ),
          ),
        );
      } catch (e) {
        // Base64 decode failed, fall through to client-side rendering
      }
    }

    // Priority 2: Render client-side if plot data is available
    return _buildClientSideRender(context);
  }

  Widget _buildClientSideRender(BuildContext context) {
    if (plot == null || plot!.polygon.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('No map data available',
                  style: TextStyle(color: Colors.grey))
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _getCentroid(plot!.polygon),
                initialZoom: 18.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _isSatelliteView
                      ? 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                      : 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                  subdomains: const ['a', 'b', 'c'],
                ),
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: plot!.polygon,
                      color: const Color(0xFF00A36C).withOpacity(0.2),
                      borderStrokeWidth: 2.0,
                      borderColor: const Color(0xFF00A36C),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: GestureDetector(
            onTap: () =>
                setState(() => _isSatelliteView = !_isSatelliteView),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.15), blurRadius: 4),
                ],
              ),
              child: Icon(
                  _isSatelliteView ? Icons.map : Icons.satellite_alt,
                  size: 20,
                  color: Colors.black87),
            ),
          ),
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on,
                    size: 14, color: Theme.of(context).primaryColor),
                const SizedBox(width: 4),
                Text(
                  plot!.name,
                  style:
                      const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LatLng _getCentroid(List<LatLng> points) {
    double sumLat = 0;
    double sumLng = 0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }
}

