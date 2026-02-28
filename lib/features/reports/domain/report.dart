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
  final DateTime createdAt;

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
    required this.createdAt,
  });
}
