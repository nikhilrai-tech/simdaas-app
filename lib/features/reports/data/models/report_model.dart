import '../../../plot_mapping/data/models/plot_model.dart';
import '../../domain/report.dart';

class ReportModel extends Report {
  const ReportModel({
    super.plotId,
    super.plot,
    super.plotSnapshot,
    super.plotMapsUrl,
    required super.id,
    required super.sprayUsedLitres,
    required super.avgFlowRate,
    required super.distanceTravelledKm,
    required super.distanceWithPtoKm,
    required super.distanceWithLeftSprayKm,
    required super.distanceWithRightSprayKm,
    required super.areaCoveredSqm,
    required super.plotAreaSqm,
    required super.completionPercentage,
    super.chemicalSavedPercentage,
    super.controlUnitId,
    super.controlUnitName,
    super.linkedSprayerName,
    super.linkedTractorName,
    super.ptoDurationSeconds,
    super.initialTankLevel,
    super.finalTankLevel,
    super.avgFlowRateLpm,
    super.avgFlowRateLacre,
    super.avgSpeedKmph,
    super.maxSpeedKmph,
    required super.createdAt,
    super.startedAt,
    super.endedAt,
    super.trajectory = const [],
    super.gpsUnavailableNote,
  });

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse doubles
    double parseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? 0.0;
    }

    PlotModel? plotModel;
    if (json['plot_details'] != null && json['plot_details'] is Map) {
      final pJson = json['plot_details'] as Map<String, dynamic>;
      // Extract ID from plot_details or fallback to plot_id from parent
      final pId = pJson['id']?.toString() ?? json['plot_id']?.toString() ?? '';
      if (pId.isEmpty) {
        // Log or handle missing ID
      }
      try {
        plotModel = PlotModel.fromJson(pId, pJson);
      } catch (e) {
        // Handle parsing error gracefully
      }
    }

    return ReportModel(
      plotId: json['plot_id']?.toString(),
      plot: plotModel,
      plotSnapshot: json['plot_snapshot']?.toString(), // Base64 PNG from backend
      plotMapsUrl: json['plot_maps_url']?.toString(),
      id: json['id']?.toString() ?? '',
      sprayUsedLitres: parseDouble(json['spray_used_litres']),
      avgFlowRate: parseDouble(json['avg_flow_rate']),
      distanceTravelledKm: parseDouble(json['distance_travelled_km']),
      distanceWithPtoKm: parseDouble(json['distance_with_pto_km']),
      distanceWithLeftSprayKm: parseDouble(json['distance_with_left_spray_km']),
      distanceWithRightSprayKm: parseDouble(json['distance_with_right_spray_km']),
      areaCoveredSqm: parseDouble(json['area_covered_sqm']),
      plotAreaSqm: parseDouble(json['plot_area_sqm']),
      completionPercentage: parseDouble(json['completion_percentage']),
      chemicalSavedPercentage: parseDouble(json['chemical_saved_percentage']),
      controlUnitId: json['control_unit_details']?['id']?.toString()
          ?? json['control_unit_id']?.toString(),
      controlUnitName: json['control_unit_details']?['name']?.toString(),
      linkedSprayerName: json['control_unit_details']?['sprayer_name']?.toString(),
      linkedTractorName: json['control_unit_details']?['tractor_name']?.toString(),
      ptoDurationSeconds: parseDouble(json['pto_duration_seconds']),
      initialTankLevel: json['initial_tank_level'] != null
          ? parseDouble(json['initial_tank_level'])
          : null,
      finalTankLevel: json['final_tank_level'] != null
          ? parseDouble(json['final_tank_level'])
          : null,
      avgFlowRateLpm: parseDouble(json['avg_flow_rate_lpm']),
      avgFlowRateLacre: parseDouble(json['avg_flow_rate_lacre']),
      avgSpeedKmph: parseDouble(json['avg_speed_kmph']),
      maxSpeedKmph: parseDouble(json['max_speed_kmph']),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at']) : null,
      endedAt: json['ended_at'] != null ? DateTime.tryParse(json['ended_at']) : null,
      trajectory: (json['trajectory'] as List<dynamic>?)
              ?.map((e) => GPSPointData(
                    lat: parseDouble(e['lat']),
                    lon: parseDouble(e['lon']),
                    speedKmph: parseDouble(e['speed_kmph']),
                    flowRateLpm: parseDouble(e['flow_rate_lpm']),
                    sprayMode: (e['spray_mode'] as num?)?.toInt() ?? 0,
                    ptoState: (e['pto_state'] as num?)?.toInt() ?? 0,
                    timestamp: DateTime.tryParse(e['timestamp'] ?? '') ??
                        DateTime.now(),
                  ))
              .toList() ??
          [],
      gpsUnavailableNote: json['gps_unavailable_note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'plot_id': plotId,
      'id': id,
      'spray_used_litres': sprayUsedLitres,
      'avg_flow_rate': avgFlowRate,
      'distance_travelled_km': distanceTravelledKm,
      // ... allow output if necessary
    };
  }
}
