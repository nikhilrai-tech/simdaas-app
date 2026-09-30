import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum HeatmapType { spraying, speed, gps, leftRight }

class HeatmapTrackPoint {
  final LatLng position;
  final bool isInPlot;
  final bool ptoOn;
  final bool isAuto;
  final double? speed;
  final double? flowRate;
  final bool leftSolenoidOn;
  final bool rightSolenoidOn;
  // Recovered via /backfill after a connectivity gap -- used only by
  // RowLineCoverage.buildHeatmapCoverageBands's asBackfillOverlay pass.
  final bool isBuffered;
  // True when the jump from the PREVIOUS point in the track to this one is
  // an implausible GPS jump (see GpsJumpDetector) -- an implied speed no
  // sprayer can actually reach. Stops the heatmap gap-fill from bridging
  // across it and painting the jump itself as sprayed.
  final bool isJumpFromPrevious;
  // True when more than GpsJumpDetector.maxPlausibleGapSeconds of real time
  // passed since the previous point in the track -- a connectivity gap, not
  // just ordinary ~1s sampling. Only ever set by the LIVE monitoring screen
  // (see MonitoringScreen._buildInsideTrackPoints): there's genuinely no
  // data for what happened during the gap yet, unlike a completed report,
  // which has the real recovered path via /backfill by the time it's
  // viewed -- report_details_screen.dart never sets this, so it has no
  // effect there. Stops the heatmap gap-fill from bridging across the gap
  // and painting a stretch as covered that was never actually observed.
  final bool isLongGapFromPrevious;

  const HeatmapTrackPoint({
    required this.position,
    required this.isInPlot,
    required this.ptoOn,
    required this.isAuto,
    this.speed,
    this.flowRate,
    this.leftSolenoidOn = false,
    this.rightSolenoidOn = false,
    this.isBuffered = false,
    this.isJumpFromPrevious = false,
    this.isLongGapFromPrevious = false,
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

  // Spray: 0 → white (no spray), 1-70 → light-to-dark blue scale (wide
  // range so low vs high flow is easy to tell apart at a glance),
  // 70.1-200 → red scale, <0 or >200 → black
  static Color getColorForSpray(double? flow) {
    if (flow == null) return Colors.grey;
    if (flow == 0) return Colors.white;
    if (flow < 0 || flow > 200) return Colors.black;
    if (flow <= 70) {
      final ratio = (flow / 70.0).clamp(0.0, 1.0);
      return Color.lerp(Colors.blue.shade200, Colors.blue.shade900, ratio) ??
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

  // Priority order for the GPS heatmap's row-coverage bands: PTO off (0) <
  // PTO on, either mode (1). A sub-band that has ever reached PTO-on must
  // never visually drop back to PTO-off on a later sample/pass — e.g. once
  // shown as sprayed, a later PTO-off reading at the same spot (GPS jitter,
  // a momentary pause, or driving back through to refill the tank) must not
  // repaint it orange, since spraying already happened there. Auto and
  // Manual share the SAME priority on purpose: between two PTO-on passes,
  // the latest one wins (a deliberate later re-pass in the other mode is
  // real, current information, not noise to protect against) -- only
  // PTO-off is the one state that must never override an established
  // PTO-on. Only used by the GPS heatmap — Speed/Spray/Left-Right keep
  // their existing "latest sample" or accumulation behavior.
  static int gpsPriority({required bool ptoOn, required bool isAuto}) {
    return ptoOn ? 1 : 0;
  }

  // Left/Right: which solenoid(s) sprayed at this point — orange = left
  // only, purple = right only, teal = both, white = neither (PTO on but
  // not spraying). Four clearly distinct hues so a farmer can tell at a
  // glance which side needs attention if one keeps showing solo.
  static Color getColorForLeftRight({
    required bool leftOn,
    required bool rightOn,
  }) {
    if (leftOn && rightOn) return Colors.teal.shade700;
    if (leftOn) return Colors.orange.shade700;
    if (rightOn) return Colors.purple.shade700;
    return Colors.white;
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
      case HeatmapType.leftRight:
        return getColorForLeftRight(
            leftOn: p.leftSolenoidOn, rightOn: p.rightSolenoidOn);
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
      case HeatmapType.leftRight:
        return Colors.red;
    }
  }
}
