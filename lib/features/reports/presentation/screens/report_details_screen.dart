import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';
import '../../domain/report.dart';
import '../../../plot_mapping/domain/entities/plot.dart';
import '../widgets/plot_snapshot.dart';
import '../widgets/saved_donut_chart.dart';

class ReportDetailsScreen extends ConsumerStatefulWidget {
  final Report report;

  const ReportDetailsScreen({required this.report, super.key});

  @override
  ConsumerState<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends ConsumerState<ReportDetailsScreen> {
  HeatmapType _heatmapType = HeatmapType.gps;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final dateFormat = DateFormat('h:mm a, dd MMM yyyy');

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
          IconButton(icon: const Icon(Icons.share_outlined, color: Colors.black), onPressed: () {}),
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

            // Performance Overview
            _sectionHeader('Performance Overview'),
            Row(
              children: [
                _metricCard('Area Covered', '${(report.areaCoveredSqm / 10000).toStringAsFixed(2)} ha', Icons.area_chart, color: Colors.green),
                const SizedBox(width: 12),
                _metricCard('Material Used', '${report.sprayUsedLitres} L', Icons.water_drop, color: Colors.blue),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Avg. Flow Rate', '${report.avgFlowRate} L/m', Icons.speed, color: Colors.orange),
                const SizedBox(width: 12),
                _metricCard('Completion', '${report.completionPercentage.toStringAsFixed(1)}%', Icons.pie_chart, color: Colors.purple),
              ],
            ),

            const SizedBox(height: 24),

            // Time and Distance Details
            _sectionHeader('Session Details'),
            Builder(builder: (context) {
              final duration = report.trajectory.isNotEmpty
                  ? report.trajectory.last.timestamp.difference(report.trajectory.first.timestamp)
                  : Duration.zero;
              
              final hours = duration.inHours;
              final minutes = duration.inMinutes % 60;
              final timeStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
              
              // Avg Speed = Total Distance / Total Time (in hours)
              final hoursDecimal = duration.inSeconds / 3600;
              final avgSpeed = hoursDecimal > 0 ? (report.distanceTravelledKm / hoursDecimal) : 0.0;

              return Column(
                children: [
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _detailRow('Start Time', dateFormat.format(report.trajectory.isNotEmpty ? report.trajectory.first.timestamp : report.createdAt), Icons.access_time),
                          const Divider(height: 24),
                          _detailRow('End Time', dateFormat.format(report.trajectory.isNotEmpty ? report.trajectory.last.timestamp : report.createdAt), Icons.timer_off_outlined),
                          const Divider(height: 24),
                          _detailRow('Total Time', timeStr, Icons.hourglass_bottom),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _metricCard('Distance Traveled', '${report.distanceTravelledKm.toStringAsFixed(2)} km', Icons.directions_run, color: Colors.blueGrey),
                      const SizedBox(width: 12),
                      _metricCard('PTO Distance', '${report.distanceWithPtoKm.toStringAsFixed(2)} km', Icons.settings_input_component, color: Colors.teal),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _metricCard('Distance Sprayed', '${(report.distanceWithLeftSprayKm + report.distanceWithRightSprayKm).toStringAsFixed(2)} km', Icons.opacity, color: Colors.indigo),
                    ],
                  ),
                ],
              );
            }),

            const SizedBox(height: 24),

            // Saved Section
            _sectionHeader('Saved '),
            Builder(builder: (context) {
              final duration = report.trajectory.isNotEmpty
                  ? report.trajectory.last.timestamp.difference(report.trajectory.first.timestamp)
                  : Duration.zero;
              final hoursDecimal = duration.inSeconds / 3600;
              final avgSpeed = hoursDecimal > 0 ? (report.distanceTravelledKm / hoursDecimal) : 0.0;

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: SavedDonutChart(
                              percentage: report.completionPercentage,
                              label: 'Job\nCompletion',
                            ),
                          ),
                          const Expanded(
                            child: SavedDonutChart(
                              percentage: 85,
                              label: 'Efficiency',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _metricCard('Avg. Speed', '${avgSpeed.toStringAsFixed(1)} km/h', Icons.shutter_speed, color: Colors.deepOrange),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
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

  Widget _metricCard(String label, String value, IconData icon, {Color color = Colors.blue}) {
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
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: Colors.grey[700], fontSize: 14),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

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
                  urlTemplate: 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
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
                PolylineLayer(
                  polylines: _buildHeatmapPolylines(report.trajectory),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: points.first,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.play_circle_fill, color: Colors.green, size: 30),
                    ),
                    Marker(
                      point: points.last,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.stop_circle, color: Colors.red, size: 30),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _buildLegend(),
        ),
      ],
    );
  }

  Widget _buildLegend() {
    List<Widget> items = [];
    switch (_heatmapType) {
      case HeatmapType.gps:
        items = [
          _legendItem('Auto', Colors.blue),
          _legendItem('Manual', Colors.orange),
          _legendItem('Out Plot', Colors.red),
        ];
        break;
      case HeatmapType.speed:
        items = [
          _legendItem('Low', Colors.green),
          _legendItem('Med', Colors.yellow),
          _legendItem('High', Colors.red),
        ];
        break;
      case HeatmapType.spraying:
        items = [
          _legendItem('Light', Colors.blue.shade100),
          _legendItem('Heavy', Colors.blue.shade900),
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
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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

  List<Polyline> _buildHeatmapPolylines(List<GPSPointData> trajectory) {
    final List<Polyline> result = [];
    if (trajectory.length < 2) return result;

    List<LatLng> currentPoints = [];
    Color? currentColor;

    for (var i = 0; i < trajectory.length; i++) {
      final p = trajectory[i];
      final point = LatLng(p.lat, p.lon);
      
      Color color;
      switch (_heatmapType) {
        case HeatmapType.speed:
          color = HeatmapColorUtils.getColorForSpeed(p.speedKmph);
          break;
        case HeatmapType.spraying:
          color = HeatmapColorUtils.getColorForSpray(p.flowRateLpm);
          break;
        case HeatmapType.gps:
          color = HeatmapColorUtils.getColorForGPS(
            isInPlot: true, 
            ptoOn: true,
            isAuto: p.sprayMode == 1,
          );
          break;
      }

      // Time gap check (if not first point)
      if (i > 0) {
        final prev = trajectory[i - 1];
        if (p.timestamp.difference(prev.timestamp).inSeconds > 30) {
          // Flush current segment if exists
          if (currentPoints.length >= 2 && currentColor != null) {
            result.add(Polyline(
              points: List<LatLng>.from(currentPoints),
              strokeWidth: 6.0,
              color: currentColor,
            ));
          }
          currentPoints = [point];
          currentColor = color;
          continue;
        }
      }

      if (currentColor == null) {
        currentColor = color;
        currentPoints = [point];
      } else if (color == currentColor) {
        currentPoints.add(point);
      } else {
        // Gap fix: Transition point
        currentPoints.add(point);
        if (currentPoints.length >= 2) {
          result.add(Polyline(
            points: List<LatLng>.from(currentPoints),
            strokeWidth: 4.0,
            color: currentColor,
          ));
        }
        currentColor = color;
        currentPoints = [point];
      }
    }

    // flush last segment
    if (currentPoints.length >= 2 && currentColor != null) {
      result.add(Polyline(
        points: List<LatLng>.from(currentPoints),
        strokeWidth: 6.0,
        color: currentColor,
      ));
    }

    return result;
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
