import '../../plot_mapping/domain/entities/plot.dart';

class Report {
  final String? plotId;
  final PlotEntity? plot;
  final String? plotSnapshot; // Base64-encoded PNG from backend
  final String? plotMapsUrl;
  final String id;
  final double sprayUsedLitres;
  final double avgFlowRate;
  final double distanceTravelledKm;
  final double distanceWithPtoKm;
  final double distanceWithLeftSprayKm;
  final double distanceWithRightSprayKm;
  final double areaCoveredSqm;
  final double plotAreaSqm;
  final double completionPercentage;
  final double chemicalSavedPercentage;
  final String? controlUnitId;
  final String? controlUnitName;
  final String? linkedSprayerName;
  final String? linkedTractorName;
  final double ptoDurationSeconds;
  // Cumulative spray counter: first and last reading of the session
  final double? initialTankLevel;
  final double? finalTankLevel;
  // Backend-computed flow rates (tank_spray_used / pto_min and / area_acres)
  final double avgFlowRateLpm;
  final double avgFlowRateLacre;
  // Backend-computed speed (from every MQTT packet)
  final double avgSpeedKmph;
  final double maxSpeedKmph;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<GPSPointData> trajectory;

  const Report({
    this.plotId,
    this.plot,
    this.plotSnapshot,
    this.plotMapsUrl,
    required this.id,
    required this.sprayUsedLitres,
    required this.avgFlowRate,
    required this.distanceTravelledKm,
    required this.distanceWithPtoKm,
    required this.distanceWithLeftSprayKm,
    required this.distanceWithRightSprayKm,
    required this.areaCoveredSqm,
    required this.plotAreaSqm,
    required this.completionPercentage,
    this.chemicalSavedPercentage = 0.0,
    this.controlUnitId,
    this.controlUnitName,
    this.linkedSprayerName,
    this.linkedTractorName,
    this.ptoDurationSeconds = 0.0,
    this.initialTankLevel,
    this.finalTankLevel,
    this.avgFlowRateLpm = 0.0,
    this.avgFlowRateLacre = 0.0,
    this.avgSpeedKmph = 0.0,
    this.maxSpeedKmph = 0.0,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.trajectory = const [],
  });
}

class GPSPointData {
  final double lat;
  final double lon;
  final double speedKmph;
  final double flowRateLpm;
  final int sprayMode;
  final int ptoState;
  final DateTime timestamp;

  const GPSPointData({
    required this.lat,
    required this.lon,
    required this.speedKmph,
    required this.flowRateLpm,
    required this.sprayMode,
    this.ptoState = 0,
    required this.timestamp,
  });
}
