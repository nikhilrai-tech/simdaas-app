import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui' as ui;
import '../../../plot_mapping/domain/entities/plot.dart';

class PlotSnapshot extends StatelessWidget {
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
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
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
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CustomPaint(
              painter: _PlotPreviewPainter(plot!.polygon),
              size: Size.infinite,
            ),
          ),
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
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
}

class _PlotPreviewPainter extends CustomPainter {
  final List<LatLng> points;
  _PlotPreviewPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Normalize lat/lng into box
    final lats = points.map((p) => p.latitude).toList();
    final lngs = points.map((p) => p.longitude).toList();
    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);

    // Add 10% padding
    final latSpan = (maxLat - minLat) == 0 ? 1e-6 : (maxLat - minLat);
    final lngSpan = (maxLng - minLng) == 0 ? 1e-6 : (maxLng - minLng);
    final paddingLat = latSpan * 0.1;
    final paddingLng = lngSpan * 0.1;

    final visibleMinLat = minLat - paddingLat;
    final visibleMaxLat = maxLat + paddingLat;
    final visibleMinLng = minLng - paddingLng;
    final visibleMaxLng = maxLng + paddingLng;

    final visibleLatRange = visibleMaxLat - visibleMinLat;
    final visibleLngRange = visibleMaxLng - visibleMinLng;

    final uiPath = ui.Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final x = ((p.longitude - visibleMinLng) / visibleLngRange) * size.width;
      // Latitude increases upwards, screen Y increases downwards
      final y = size.height -
          ((p.latitude - visibleMinLat) / visibleLatRange) * size.height;
      if (i == 0) {
        uiPath.moveTo(x, y);
      } else {
        uiPath.lineTo(x, y);
      }
    }
    uiPath.close();

    final paintFill =
        Paint()..color = const Color(0xFF00A36C).withValues(alpha: 0.2);
    final paintBorder = Paint()
      ..color = const Color(0xFF00A36C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(uiPath, paintFill);
    canvas.drawPath(uiPath, paintBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
