import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';
import '../../domain/report.dart';
import '../../../plot_mapping/domain/entities/plot.dart';
import '../../../plot_mapping/presentation/utils/row_line_coverage.dart';
import '../providers/report_providers.dart';
import '../widgets/plot_snapshot.dart';
import '../widgets/saved_donut_chart.dart';

const String _kSatelliteTileUrl =
    'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
const String _kNormalTileUrl =
    'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';

/// Small floating icon button toggling satellite/normal map view, styled to
/// match the existing fullscreen/close buttons on these map cards. Shared by
/// the inline report map header and its fullscreen page.
Widget _mapViewToggleButton(
    {required bool isSatellite, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4),
        ],
      ),
      child: Icon(isSatellite ? Icons.map : Icons.satellite_alt,
          size: 22, color: Colors.black87),
    ),
  );
}

class ReportDetailsScreen extends ConsumerStatefulWidget {
  final Report report;

  const ReportDetailsScreen({required this.report, super.key});

  @override
  ConsumerState<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends ConsumerState<ReportDetailsScreen> {
  HeatmapType _heatmapType = HeatmapType.gps;
  bool _isSatelliteView = true;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(reportDetailProvider(widget.report.id));
    final report = detailAsync.asData?.value ?? widget.report;
    final dateFormat = DateFormat('h:mm a, dd MMM yyyy');

    final startTime = report.startedAt ??
        (report.trajectory.isNotEmpty ? report.trajectory.first.timestamp : report.createdAt);
    final endTime = report.endedAt ??
        (report.trajectory.isNotEmpty ? report.trajectory.last.timestamp : report.createdAt);
    final duration = endTime.difference(startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final durationStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    final avgSpeed = report.avgSpeedKmph;
    final maxSpeed = report.maxSpeedKmph;
    final areaCoveredAcres = report.areaCoveredSqm / 4046.86;
    // Same source as the "Applied" stat on the reports list (backend prefers
    // the flow-sensor total over the tank-level delta) — recomputing from
    // initial/final tank level here would drift from that value and show a
    // different number for the same report.
    final sprayLitres = report.sprayUsedLitres;
    // Use backend-computed flow rates directly (tank_spray_used / pto_min and / area_acres)
    final avgFlowRateLperMin = report.avgFlowRateLpm;
    final avgFlowRatePerAcre = report.avgFlowRateLacre;
    // Left/right solenoid OFF = distance with PTO on but solenoid state = 0
    final leftSolenoidOffKm =
        (report.distanceWithPtoKm - report.distanceWithLeftSprayKm).clamp(0.0, double.infinity);
    final rightSolenoidOffKm =
        (report.distanceWithPtoKm - report.distanceWithRightSprayKm).clamp(0.0, double.infinity);
    final plotAreaHa = report.plotAreaSqm / 10000;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Report Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.share_outlined, color: Colors.black),
              onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete report',
            onPressed: () => _confirmDelete(context, report),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: _buildMapHeader(report),
            ),
            const SizedBox(height: 12),
            _buildHeatmapToggles(),
            const SizedBox(height: 20),

            // ── Saved ─────────────────────────────────────────────────────
            _sectionHeader('Saved'),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF015685), Color(0xFF0277B5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.eco_outlined, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.chemicalSavedNote != null
                              ? '—'
                              : '${report.chemicalSavedPercentage.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          report.chemicalSavedNote ??
                              'Chemical Saved (Auto mode)',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (report.gpsUnavailableNote != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        report.gpsUnavailableNote!,
                        style: TextStyle(
                            fontSize: 13, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Performance Overview ──────────────────────────────────────
            _sectionHeader('Performance Overview'),
            Row(
              children: [
                _metricCard('Area Covered',
                    '${report.completionPercentage.toStringAsFixed(1)}%',
                    Icons.pie_chart,
                    color: Colors.purple,
                    subtitle:
                        '${areaCoveredAcres.toStringAsFixed(2)} / ${(report.plotAreaSqm / 4046.86).toStringAsFixed(2)} ac'),
                const SizedBox(width: 12),
                _metricCard('Total Sprayed',
                    '${sprayLitres.toStringAsFixed(1)} L',
                    Icons.water_drop,
                    color: Colors.blue),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Avg Flow Rate',
                    '${avgFlowRateLperMin.toStringAsFixed(2)} L/min',
                    Icons.speed,
                    color: Colors.orange),
                const SizedBox(width: 12),
                _metricCard('Avg Flow Rate',
                    '${avgFlowRatePerAcre.toStringAsFixed(2)} L/acre',
                    Icons.speed_outlined,
                    color: Colors.amber),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Avg Speed',
                    '${avgSpeed.toStringAsFixed(1)} km/h',
                    Icons.shutter_speed,
                    color: Colors.deepOrange),
                const SizedBox(width: 12),
                _metricCard('Max Speed',
                    '${maxSpeed.toStringAsFixed(1)} km/h',
                    Icons.speed,
                    color: Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Total Distance',
                    '${report.distanceTravelledKm.toStringAsFixed(2)} km',
                    Icons.directions_run,
                    color: Colors.blueGrey),
                const SizedBox(width: 12),
                _metricCard('PTO On Dist.',
                    '${report.distanceWithPtoKm.toStringAsFixed(2)} km',
                    Icons.settings_input_component,
                    color: Colors.teal),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Left Sol. Off',
                    '${leftSolenoidOffKm.toStringAsFixed(2)} km',
                    Icons.chevron_left,
                    color: Colors.indigo),
                const SizedBox(width: 12),
                _metricCard('Right Sol. Off',
                    '${rightSolenoidOffKm.toStringAsFixed(2)} km',
                    Icons.chevron_right,
                    color: Colors.deepPurple),
              ],
            ),

            const SizedBox(height: 24),

            // ── Session Details ───────────────────────────────────────────
            _sectionHeader('Session Details'),
            // Time strip
            IntrinsicHeight(
             child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _timeChip(Icons.play_arrow_rounded, 'Start',
                    DateFormat('h:mm a').format(startTime),
                    DateFormat('dd MMM').format(startTime),
                    const Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                _timeChip(Icons.stop_rounded, 'End',
                    DateFormat('h:mm a').format(endTime),
                    DateFormat('dd MMM').format(endTime),
                    const Color(0xFFC62828)),
                const SizedBox(width: 8),
                _timeChip(Icons.hourglass_bottom_rounded, 'Duration',
                    durationStr, '', const Color(0xFF015685)),
              ],
             ),
            ),
            const SizedBox(height: 12),
            // Equipment info card
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _equipRow(Icons.memory, 'Control Unit',
                      report.controlUnitName ?? report.controlUnitId ?? '-',
                      const Color(0xFF015685)),
                  _equipRow(Icons.map_outlined, 'Linked Plot',
                      report.plot?.name ?? '-',
                      const Color(0xFF2E7D32)),
                  _equipRow(Icons.straighten, 'Plot Area',
                      '${plotAreaHa.toStringAsFixed(2)} ha',
                      Colors.blueGrey),
                  _equipRow(Icons.water_drop_outlined, 'Linked Sprayer',
                      report.linkedSprayerName ?? '-',
                      const Color(0xFF8E4600)),
                  _equipRow(Icons.agriculture_outlined, 'Linked Tractor',
                      report.linkedTractorName ?? '-',
                      const Color(0xFF4A148C),
                      isLast: true),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Additional Details (user-editable, per report) ─────────────
            _sectionHeader('Additional Details'),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _editableRow(
                    Icons.person_outline,
                    'Driver Name',
                    report.driverName,
                    const Color(0xFF00695C),
                    onTap: () => _editReportField(
                      context: context,
                      title: 'Driver Name',
                      currentValue: report.driverName,
                      onSave: (value) => _saveReportField(driverName: value),
                    ),
                  ),
                  _editableRow(
                    Icons.eco_outlined,
                    'Fertilizers Used',
                    report.fertilizersUsed,
                    const Color(0xFF558B2F),
                    isLast: true,
                    onTap: () => _editReportField(
                      context: context,
                      title: 'Fertilizers Used',
                      currentValue: report.fertilizersUsed,
                      multiline: true,
                      onSave: (value) =>
                          _saveReportField(fertilizersUsed: value),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Report report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text(
            'Are you sure you want to delete this report? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(reportRepoProvider).deleteReport(report.id);
      ref.invalidate(reportsListProvider);
      if (context.mounted) {
        showSuccessSnackBar(context, 'Report deleted');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) {
        showGenericErrorSnackBar(context, 'Failed to delete report');
      }
    }
  }

  // ── Map header with fullscreen button ──────────────────────────────────
  Widget _buildMapHeader(Report report) {
    if (report.trajectory.isEmpty) {
      return PlotSnapshot(
        plot: report.plot,
        base64Image: report.plotSnapshot,
        height: 180,
      );
    }

    final points = report.trajectory.map((p) => LatLng(p.lat, p.lon)).toList();
    final centroid = _getCentroid(points);

    return Stack(
      children: [
        Container(
          height: 250,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: centroid,
                initialZoom: 18.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      _isSatelliteView ? _kSatelliteTileUrl : _kNormalTileUrl,
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (report.plot != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: report.plot!.polygon,
                        color: const Color(0xFF00A36C).withOpacity(0.1),
                        borderStrokeWidth: 2.0,
                        borderColor: const Color(0xFF00A36C).withOpacity(0.5),
                      ),
                    ],
                  ),
                if (report.plot != null &&
                    report.plot!.rowLines != null &&
                    report.plot!.rowLines!.isNotEmpty) ...[
                  PolygonLayer(
                    polygons: RowLineCoverage.buildHeatmapCoverageBands(
                      rowLines: report.plot!.rowLines!,
                      insidePoints: _buildInsideTrackPoints(
                          report.trajectory, report.plot),
                      rowSpacing: report.plot!.rowSpacing ?? 3.0,
                      heatmapType: _heatmapType,
                    ),
                  ),
                  PolylineLayer(
                    polylines: RowLineCoverage.buildRowLines(
                      rowLines: report.plot!.rowLines!,
                    ),
                  ),
                ],
                PolylineLayer(
                  polylines:
                      _buildHeatmapPolylines(report.trajectory, report.plot),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: points.first,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.play_circle_fill,
                          color: Colors.green, size: 30),
                    ),
                    Marker(
                      point: points.last,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.stop_circle,
                          color: Colors.red, size: 30),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Satellite/Normal toggle (top-left)
        Positioned(
          top: 12,
          left: 12,
          child: _mapViewToggleButton(
            isSatellite: _isSatelliteView,
            onTap: () => setState(() => _isSatelliteView = !_isSatelliteView),
          ),
        ),
        // Legend (top-right)
        Positioned(
          top: 12,
          right: 12,
          child: _buildLegend(),
        ),
        // Fullscreen button (bottom-left)
        Positioned(
          bottom: 12,
          left: 12,
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _FullScreenMapPage(
                report: report,
                initialHeatmapType: _heatmapType,
                initialIsSatelliteView: _isSatelliteView,
              ),
            )),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4),
                ],
              ),
              child: const Icon(Icons.fullscreen, size: 22, color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon,
      {Color color = Colors.blue, String? subtitle}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _timeChip(IconData icon, String label, String value, String sub, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3)),
            ]),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
            if (sub.isNotEmpty)
              Text(sub,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _equipRow(IconData icon, String label, String value, Color accentColor,
      {bool isLast = false}) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: Colors.grey[100]!, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
        ],
      ),
    );
  }

  // Same visual style as _equipRow, but tappable — used for the
  // user-editable Driver Name / Fertilizers Used fields. Shows "N/A" until
  // the user fills a value in.
  Widget _editableRow(
      IconData icon, String label, String? value, Color accentColor,
      {required VoidCallback onTap, bool isLast = false}) {
    final displayValue =
        (value == null || value.trim().isEmpty) ? 'N/A' : value;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: Colors.grey[100]!, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(displayValue,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit, size: 15, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _editReportField({
    required BuildContext context,
    required String title,
    required String? currentValue,
    required Future<void> Function(String value) onSave,
    bool multiline = false,
  }) async {
    final controller = TextEditingController(
        text: (currentValue ?? '').trim() == 'N/A' ? '' : (currentValue ?? ''));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: multiline ? 3 : 1,
          decoration: InputDecoration(
            hintText: 'Enter $title',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelled
    await onSave(result);
  }

  Future<void> _saveReportField({String? driverName, String? fertilizersUsed}) async {
    try {
      await ref.read(reportRepoProvider).updateReportDetails(
            widget.report.id,
            driverName: driverName,
            fertilizersUsed: fertilizersUsed,
          );
      ref.invalidate(reportDetailProvider(widget.report.id));
      if (context.mounted) showSuccessSnackBar(context, 'Saved');
    } catch (e) {
      if (context.mounted) {
        showGenericErrorSnackBar(context, 'Failed to save — try again');
      }
    }
  }

  Widget _buildLegend() {
    List<Widget> items = [];
    switch (_heatmapType) {
      case HeatmapType.gps:
        items = [
          _legendItem('Auto', Colors.blue),
          _legendItem('Manual', Colors.grey),
          _legendItem('PTO Off', Colors.orange),
          _legendItem('Outside', Colors.red),
        ];
        break;
      case HeatmapType.speed:
        items = [
          _legendItem('0-3 km/h', Colors.yellow),
          _legendItem('3-7 km/h', Colors.green),
          _legendItem('7+ km/h', Colors.red),
        ];
        break;
      case HeatmapType.spraying:
        items = [
          _legendItem('0 L/m (No Spray)', Colors.white),
          _legendItem('1-70 L/m', Colors.blue.shade800),
          _legendItem('70-200 L/m', Colors.red.shade400),
          _legendItem('>200 L/m', Colors.black),
        ];
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: items,
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHeatmapToggles() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _heatmapButton(HeatmapType.gps, 'GPS'),
        const SizedBox(width: 8),
        _heatmapButton(HeatmapType.speed, 'Speed'),
        const SizedBox(width: 8),
        _heatmapButton(HeatmapType.spraying, 'Spray'),
      ],
    );
  }

  Widget _heatmapButton(HeatmapType type, String label) {
    final isSelected = _heatmapType == type;
    return InkWell(
      onTap: () => setState(() => _heatmapType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF262626) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  List<HeatmapTrackPoint> _buildInsideTrackPoints(
      List<GPSPointData> trajectory, PlotEntity? plot) {
    final result = <HeatmapTrackPoint>[];
    for (final p in trajectory) {
      final point = LatLng(p.lat, p.lon);
      bool isInPlot = true;
      if (plot?.polygon != null && plot!.polygon.length >= 3) {
        isInPlot = _isPointInPolygon(point, plot.polygon);
      }
      if (!isInPlot) continue;
      // The backend now records a GPS point on every telemetry packet while
      // spraying (see session_service.py's should_record), so trajectory is
      // as dense as what the live Monitoring screen draws from — no need to
      // scale the flow value to compensate for sparse sampling anymore.
      result.add(HeatmapTrackPoint(
        position: point,
        isInPlot: true,
        ptoOn: p.ptoState == 1,
        isAuto: p.sprayMode == 1,
        speed: p.speedKmph,
        flowRate: p.flowRateLpm,
      ));
    }
    return result;
  }

  List<Polyline> _buildHeatmapPolylines(
      List<GPSPointData> trajectory, PlotEntity? plot) {
    final List<Polyline> result = [];
    if (trajectory.length < 2) return result;

    List<LatLng> currentPoints = [];
    Color? currentColor;

    void flush({double strokeWidth = 4.0}) {
      if (currentPoints.length >= 2 && currentColor != null) {
        result.add(Polyline(
          points: List<LatLng>.from(currentPoints),
          strokeWidth: strokeWidth,
          color: currentColor!,
        ));
      }
      currentPoints = [];
      currentColor = null;
    }

    for (var i = 0; i < trajectory.length; i++) {
      final p = trajectory[i];
      final point = LatLng(p.lat, p.lon);

      bool isInPlot = false;
      if (plot?.polygon != null && plot!.polygon.length >= 3) {
        isInPlot = _isPointInPolygon(point, plot.polygon);
      }

      if (isInPlot) {
        flush();
        continue;
      }

      if (i > 0) {
        final prev = trajectory[i - 1];
        if (p.timestamp.difference(prev.timestamp).inSeconds > 30) {
          flush(strokeWidth: 6.0);
        }
      }

      final Color color;
      switch (_heatmapType) {
        case HeatmapType.gps:
          color = Colors.red;
          break;
        case HeatmapType.speed:
          color = HeatmapColorUtils.getColorForSpeed(p.speedKmph);
          break;
        case HeatmapType.spraying:
          color = HeatmapColorUtils.getColorForSpray(p.flowRateLpm);
          break;
      }

      if (currentColor == null) {
        currentColor = color;
        currentPoints = [point];
      } else if (color == currentColor) {
        currentPoints.add(point);
      } else {
        currentPoints.add(point);
        flush();
        currentColor = color;
        currentPoints = [point];
      }
    }

    flush(strokeWidth: 6.0);
    return result;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var intersections = 0;
    for (var i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      if (p1.longitude > point.longitude != p2.longitude > point.longitude &&
          point.latitude <
              (p2.latitude - p1.latitude) *
                      (point.longitude - p1.longitude) /
                      (p2.longitude - p1.longitude) +
                  p1.latitude) {
        intersections++;
      }
    }
    return intersections % 2 != 0;
  }

  LatLng _getCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    double sumLat = 0;
    double sumLng = 0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }
}

// ── Full-screen map page ────────────────────────────────────────────────────

class _FullScreenMapPage extends StatefulWidget {
  final Report report;
  final HeatmapType initialHeatmapType;
  final bool initialIsSatelliteView;

  const _FullScreenMapPage({
    required this.report,
    required this.initialHeatmapType,
    this.initialIsSatelliteView = true,
  });

  @override
  State<_FullScreenMapPage> createState() => _FullScreenMapPageState();
}

class _FullScreenMapPageState extends State<_FullScreenMapPage> {
  late HeatmapType _heatmapType;
  late bool _isSatelliteView;

  @override
  void initState() {
    super.initState();
    _heatmapType = widget.initialHeatmapType;
    _isSatelliteView = widget.initialIsSatelliteView;
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final points = report.trajectory.map((p) => LatLng(p.lat, p.lon)).toList();
    final centroid = _getCentroid(points);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen map
          FlutterMap(
            options: MapOptions(
              initialCenter: centroid,
              initialZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    _isSatelliteView ? _kSatelliteTileUrl : _kNormalTileUrl,
                subdomains: const ['a', 'b', 'c'],
              ),
              if (report.plot != null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: report.plot!.polygon,
                      color: const Color(0xFF00A36C).withOpacity(0.1),
                      borderStrokeWidth: 2.0,
                      borderColor: const Color(0xFF00A36C).withOpacity(0.5),
                    ),
                  ],
                ),
              if (report.plot != null &&
                  report.plot!.rowLines != null &&
                  report.plot!.rowLines!.isNotEmpty) ...[
                PolygonLayer(
                  polygons: RowLineCoverage.buildHeatmapCoverageBands(
                    rowLines: report.plot!.rowLines!,
                    insidePoints: _buildInsideTrackPoints(report.trajectory, report.plot),
                    rowSpacing: report.plot!.rowSpacing ?? 3.0,
                    heatmapType: _heatmapType,
                  ),
                ),
                PolylineLayer(
                  polylines: RowLineCoverage.buildRowLines(
                    rowLines: report.plot!.rowLines!,
                  ),
                ),
              ],
              PolylineLayer(
                polylines: _buildHeatmapPolylines(report.trajectory, report.plot),
              ),
              if (points.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: points.first,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.play_circle_fill,
                          color: Colors.green, size: 30),
                    ),
                    Marker(
                      point: points.last,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.stop_circle,
                          color: Colors.red, size: 30),
                    ),
                  ],
                ),
            ],
          ),

          // Close button (top-left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.2), blurRadius: 6),
                  ],
                ),
                child: const Icon(Icons.fullscreen_exit,
                    size: 24, color: Colors.black87),
              ),
            ),
          ),

          // Satellite/Normal toggle (top-left, below close)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8 + 44,
            left: 12,
            child: _mapViewToggleButton(
              isSatellite: _isSatelliteView,
              onTap: () =>
                  setState(() => _isSatelliteView = !_isSatelliteView),
            ),
          ),

          // Legend (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: _buildLegend(),
          ),

          // Heatmap toggles (bottom-center)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _heatmapButton(HeatmapType.gps, 'GPS'),
                const SizedBox(width: 8),
                _heatmapButton(HeatmapType.speed, 'Speed'),
                const SizedBox(width: 8),
                _heatmapButton(HeatmapType.spraying, 'Spray'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    List<Widget> items = [];
    switch (_heatmapType) {
      case HeatmapType.gps:
        items = [
          _legendItem('Auto', Colors.blue),
          _legendItem('Manual', Colors.grey),
          _legendItem('PTO Off', Colors.orange),
          _legendItem('Outside', Colors.red),
        ];
        break;
      case HeatmapType.speed:
        items = [
          _legendItem('0-3 km/h', Colors.yellow),
          _legendItem('3-7 km/h', Colors.green),
          _legendItem('7+ km/h', Colors.red),
        ];
        break;
      case HeatmapType.spraying:
        items = [
          _legendItem('0 L/m (No Spray)', Colors.white),
          _legendItem('1-70 L/m', Colors.blue.shade800),
          _legendItem('70-200 L/m', Colors.red.shade400),
          _legendItem('>200 L/m', Colors.black),
        ];
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: items,
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _heatmapButton(HeatmapType type, String label) {
    final isSelected = _heatmapType == type;
    return GestureDetector(
      onTap: () => setState(() => _heatmapType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? Colors.black : Colors.white70),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  List<HeatmapTrackPoint> _buildInsideTrackPoints(
      List<GPSPointData> trajectory, PlotEntity? plot) {
    final result = <HeatmapTrackPoint>[];
    for (final p in trajectory) {
      final point = LatLng(p.lat, p.lon);
      bool isInPlot = true;
      if (plot?.polygon != null && plot!.polygon.length >= 3) {
        isInPlot = _isPointInPolygon(point, plot.polygon);
      }
      if (!isInPlot) continue;
      // The backend now records a GPS point on every telemetry packet while
      // spraying (see session_service.py's should_record), so trajectory is
      // as dense as what the live Monitoring screen draws from — no need to
      // scale the flow value to compensate for sparse sampling anymore.
      result.add(HeatmapTrackPoint(
        position: point,
        isInPlot: true,
        ptoOn: p.ptoState == 1,
        isAuto: p.sprayMode == 1,
        speed: p.speedKmph,
        flowRate: p.flowRateLpm,
      ));
    }
    return result;
  }

  List<Polyline> _buildHeatmapPolylines(
      List<GPSPointData> trajectory, PlotEntity? plot) {
    final List<Polyline> result = [];
    if (trajectory.length < 2) return result;

    List<LatLng> currentPoints = [];
    Color? currentColor;

    void flush({double strokeWidth = 4.0}) {
      if (currentPoints.length >= 2 && currentColor != null) {
        result.add(Polyline(
          points: List<LatLng>.from(currentPoints),
          strokeWidth: strokeWidth,
          color: currentColor!,
        ));
      }
      currentPoints = [];
      currentColor = null;
    }

    for (var i = 0; i < trajectory.length; i++) {
      final p = trajectory[i];
      final point = LatLng(p.lat, p.lon);

      bool isInPlot = false;
      if (plot?.polygon != null && plot!.polygon.length >= 3) {
        isInPlot = _isPointInPolygon(point, plot.polygon);
      }

      if (isInPlot) {
        flush();
        continue;
      }

      if (i > 0) {
        final prev = trajectory[i - 1];
        if (p.timestamp.difference(prev.timestamp).inSeconds > 30) {
          flush(strokeWidth: 6.0);
        }
      }

      final Color color;
      switch (_heatmapType) {
        case HeatmapType.gps:
          color = Colors.red;
          break;
        case HeatmapType.speed:
          color = HeatmapColorUtils.getColorForSpeed(p.speedKmph);
          break;
        case HeatmapType.spraying:
          color = HeatmapColorUtils.getColorForSpray(p.flowRateLpm);
          break;
      }

      if (currentColor == null) {
        currentColor = color;
        currentPoints = [point];
      } else if (color == currentColor) {
        currentPoints.add(point);
      } else {
        currentPoints.add(point);
        flush();
        currentColor = color;
        currentPoints = [point];
      }
    }

    flush(strokeWidth: 6.0);
    return result;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var intersections = 0;
    for (var i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      if (p1.longitude > point.longitude != p2.longitude > point.longitude &&
          point.latitude <
              (p2.latitude - p1.latitude) *
                      (point.longitude - p1.longitude) /
                      (p2.longitude - p1.longitude) +
                  p1.latitude) {
        intersections++;
      }
    }
    return intersections % 2 != 0;
  }

  LatLng _getCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    double sumLat = 0;
    double sumLng = 0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }
}
