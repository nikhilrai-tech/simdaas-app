import 'package:latlong2/latlong.dart';

class PlotEntity {
  final String id;
  final String name;
  // owner/user who created/owns the plot
  final String? userId;
  // total area in hectares
  final double? area;
  // number of trees in the plot
  final int? treeCount;
  // row spacing in meters
  final double? rowSpacing;
  // polygon boundary as list of lat/lng
  final List<LatLng> polygon;
  // centroid of the polygon (computed or stored)
  final LatLng? centroid;
  // bed height in meters
  final double? bedHeight;
  // creation timestamp
  final DateTime? createdAt;
  // saved row lines: each entry is a 2-point segment [[start],[end]]
  final List<List<LatLng>>? rowLines;
  // False only on a report whose plot geometry is a LIVE lookup rather
  // than frozen at report-generation time (jobs.serializers.
  // JobReportSerializer.get_plot_details's geometry_is_frozen) -- i.e. an
  // older report whose plot has since been re-edited (boundary/row lines
  // moved). That report's own GPS trajectory was recorded against the
  // OLD, now-gone shape, so it no longer corresponds to what's here; the
  // row-corridor coverage heatmap must not be attempted against it (seen
  // in production: garbled/triangle-shaped coverage bands). Always true
  // for a plain plot (not a report's embedded snapshot) and for any
  // response from a backend that doesn't send this field yet.
  final bool geometryIsFrozen;

  PlotEntity({
    required this.id,
    required this.name,
    this.userId,
    this.area,
    this.treeCount,
    this.rowSpacing,
    required this.polygon,
    this.centroid,
    this.bedHeight,
    this.createdAt,
    this.rowLines,
    this.geometryIsFrozen = true,
  });
}
