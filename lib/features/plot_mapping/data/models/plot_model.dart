import '../../domain/entities/plot.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

class PlotModel extends PlotEntity {
  PlotModel({
    required super.id,
    required super.name,
    super.userId,
    super.area,
    super.treeCount,
    super.rowSpacing,
    required super.polygon,
    super.centroid,
    super.bedHeight,
    super.createdAt,
    super.rowLines,
  });

  factory PlotModel.fromJson(String id, Map<String, dynamic> json) {
    final rawPolygon = (json['polygon'] as List<dynamic>?) ?? [];
    final coords = <LatLng>[];
    for (final e in rawPolygon) {
      try {
        if (e is List && e.length >= 2) {
          // [lat, lng]
          final lat = (e[0] as num).toDouble();
          final lng = (e[1] as num).toDouble();
          coords.add(LatLng(lat, lng));
        } else if (e is Map) {
          // map with 'lat'/'lng' or 'latitude'/'longitude'
          final latKey = e.containsKey('lat')
              ? 'lat'
              : (e.containsKey('latitude') ? 'latitude' : null);
          final lngKey = e.containsKey('lng')
              ? 'lng'
              : (e.containsKey('longitude') ? 'longitude' : null);
          if (latKey != null && lngKey != null) {
            final lat = (e[latKey] as num).toDouble();
            final lng = (e[lngKey] as num).toDouble();
            coords.add(LatLng(lat, lng));
          }
        }
      } catch (e, st) {
        debugPrint(
            'plot_model.fromJson: skipping invalid polygon entry: $e\n$st');
      }
    }

    LatLng? centroid;
    if (json['centroid'] != null) {
      final c = json['centroid'] as Map<String, dynamic>;
      centroid =
          LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble());
    } else if (coords.isNotEmpty) {
      // compute simple centroid (average of points)
      final avgLat =
          coords.map((p) => p.latitude).reduce((a, b) => a + b) / coords.length;
      final avgLng = coords.map((p) => p.longitude).reduce((a, b) => a + b) /
          coords.length;
      centroid = LatLng(avgLat, avgLng);
    }

    // Parse row_lines: list of 2-point segments, each point is [lat, lng]
    List<List<LatLng>>? rowLines;
    final rawRowLines = json['row_lines'];
    if (rawRowLines is List && rawRowLines.isNotEmpty) {
      rowLines = [];
      for (final seg in rawRowLines) {
        if (seg is! List) continue;
        final points = <LatLng>[];
        for (final pt in seg) {
          try {
            if (pt is List && pt.length >= 2) {
              points.add(LatLng((pt[0] as num).toDouble(), (pt[1] as num).toDouble()));
            } else if (pt is Map) {
              final lat = (pt['lat'] ?? pt['latitude']) as num?;
              final lng = (pt['lng'] ?? pt['longitude']) as num?;
              if (lat != null && lng != null) {
                points.add(LatLng(lat.toDouble(), lng.toDouble()));
              }
            }
          } catch (e) {
            debugPrint('plot_model.fromJson: skipping invalid row_lines entry: $e');
          }
        }
        if (points.length >= 2) rowLines.add(points);
      }
      if (rowLines.isEmpty) rowLines = null;
    }

    return PlotModel(
      id: id,
      name: json['name'] as String,
      userId: json['user'].toString() as String? ??
          json['ownerId'].toString() as String?,
      bedHeight: (json['bed_height'] as num?)?.toDouble(),
      polygon: coords,
      area: (json['user_area_acre'] as num?)?.toDouble() ??
          (json['approxArea'] as num?)?.toDouble(),
      rowSpacing: (json['row_spacing'] as num?)?.toDouble(),
      treeCount: (json['tree_count'] as num?)?.toInt(),
      centroid: centroid,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : null,
      rowLines: rowLines,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'user': userId,
        'bed_height': bedHeight,
        'user_area_acre': area,
        'row_spacing': rowSpacing,
        'tree_count': treeCount,
        'created_at': createdAt?.toIso8601String(),
        'centroid': centroid == null
            ? null
            : {'lat': centroid!.latitude, 'lng': centroid!.longitude},
        'polygon': polygon.map((p) => [p.latitude, p.longitude]).toList(),
        'row_lines': rowLines
            ?.map((seg) => seg.map((p) => [p.latitude, p.longitude]).toList())
            .toList(),
      };
}
