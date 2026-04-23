import 'package:flutter/material.dart';

enum HeatmapType { spraying, speed, gps }

class HeatmapColorUtils {
  static Color getColorForSpeed(double? speed) {
    if (speed == null) return Colors.grey;
    if (speed <= 3.0) return Colors.green;
    if (speed <= 7.0) return Colors.yellow;
    return Colors.red;
  }

  static Color getColorForSpray(double? flow) {
    if (flow == null) return Colors.grey;
    // Scale 0-80 LPM: Light Blue to Dark Blue
    final ratio = (flow / 80.0).clamp(0.0, 1.0);
    return Color.lerp(Colors.blue.shade100, Colors.blue.shade900, ratio) ??
        Colors.blue;
  }

  static Color getColorForGPS({
    required bool isInPlot,
    required bool ptoOn,
    required bool isAuto,
  }) {
    if (!isInPlot) return Colors.red;
    if (!ptoOn) return Colors.orange;
    return isAuto ? Colors.blue : Colors.orange;
  }
}
