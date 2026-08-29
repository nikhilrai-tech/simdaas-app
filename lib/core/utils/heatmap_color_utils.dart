import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum HeatmapType { spraying, speed, gps }

class HeatmapTrackPoint {
  final LatLng position;
  final bool isInPlot;
  final bool ptoOn;
  final bool isAuto;
  final double? speed;
  final double? flowRate;

  const HeatmapTrackPoint({
    required this.position,
    required this.isInPlot,
    required this.ptoOn,
    required this.isAuto,
    this.speed,
    this.flowRate,
  });
}

class HeatmapColorUtils {
  // Speed: 0-3 → yellow, 3-7 → green, 7+ → red
  static Color getColorForSpeed(double? speed) {
    if (speed == null) return Colors.grey;
    if (speed <= 3.0) return Colors.yellow;
    if (speed <= 7.0) return Colors.green;
    return Colors.red;
  }

  // Spray: 0 → white (no spray), 1-70 → dark blue scale, 70.1-200 → red
  // scale, <0 or >200 → black
  static Color getColorForSpray(double? flow) {
    if (flow == null) return Colors.grey;
    if (flow == 0) return Colors.white;
    if (flow < 0 || flow > 200) return Colors.black;
    if (flow <= 70) {
      final ratio = (flow / 70.0).clamp(0.0, 1.0);
      return Color.lerp(Colors.blue.shade700, Colors.blue.shade900, ratio) ??
          Colors.blue;
    }
    final ratio = ((flow - 70.0) / 130.0).clamp(0.0, 1.0);
    return Color.lerp(Colors.red.shade200, Colors.red.shade900, ratio) ??
        Colors.red;
  }

  // GPS: outside → red, PTO off → orange, auto → blue, manual → grey
  static Color getColorForGPS({
    required bool isInPlot,
    required bool ptoOn,
    required bool isAuto,
  }) {
    if (!isInPlot) return Colors.red;
    if (!ptoOn) return Colors.orange;
    return isAuto ? Colors.blue : Colors.grey;
  }

  // Color for inside-plot band fill
  static Color getColorForInsidePoint(HeatmapTrackPoint p, HeatmapType type) {
    switch (type) {
      case HeatmapType.speed:
        return getColorForSpeed(p.speed);
      case HeatmapType.spraying:
        return getColorForSpray(p.flowRate);
      case HeatmapType.gps:
        return getColorForGPS(isInPlot: true, ptoOn: p.ptoOn, isAuto: p.isAuto);
    }
  }

  // Color for outside-plot trajectory line
  static Color getColorForOutsideLine(HeatmapTrackPoint p, HeatmapType type) {
    switch (type) {
      case HeatmapType.gps:
        return Colors.red;
      case HeatmapType.speed:
        return getColorForSpeed(p.speed);
      case HeatmapType.spraying:
        return getColorForSpray(p.flowRate);
    }
  }
}
