import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/report.dart';
import '../widgets/plot_snapshot.dart';
import '../widgets/report_donut_chart.dart';

class ReportDetailsScreen extends ConsumerWidget {
  final Report report;

  const ReportDetailsScreen({required this.report, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('h a dd/MM/yyyy');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.edit, color: Colors.black), onPressed: () {}),
          IconButton(icon: const Icon(Icons.share, color: Colors.black), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlotSnapshot(
              plot: report.plot,
              base64Image: report.plotSnapshot,
              height: 180,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _metricBox('Area', '${(report.areaCoveredSqm / 10000).toStringAsFixed(2)} ha', flex: 2),
                const SizedBox(width: 8),
                _metricBox('Amount of\nMaterialApplied', '${report.sprayUsedLitres} L', fontSize: 10),
                const SizedBox(width: 8),
                _metricBox('Avg. Flow Rate', '${report.avgFlowRate} L/m', fontSize: 10),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _metricBox('Percentage\nCovered', '${report.completionPercentage.toStringAsFixed(1)}%', fontSize: 10),
                const Spacer(flex: 2),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.black12, thickness: 1.5),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          '2Hrs',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Time taken',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        dateFormat.format(report.createdAt.subtract(const Duration(hours: 2))),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(report.createdAt),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _infoBox('Pto Active Time', padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), fontSize: 20),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: ReportDonutChart(
                      percentage: (report.distanceTravelledKm / (report.distanceTravelledKm + 1) * 100),
                      label: 'Distance\nTraveled',
                    ),
                  ),
                  Expanded(
                    child: ReportDonutChart(
                      percentage: (report.distanceWithPtoKm / (report.distanceTravelledKm + 0.1) * 100),
                      label: 'total distance\ntraversed with pto on',
                    ),
                  ),
                  Expanded(
                    child: ReportDonutChart(
                      percentage: (report.distanceWithLeftSprayKm + report.distanceWithRightSprayKm) / (report.distanceTravelledKm + 0.1) * 100,
                      label: 'Distance sprayed',
                    ),
                  ),
                ],
              ),
            ),
            // const SizedBox(height: 24),
            // _infoBox('Avg Speed', padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), fontSize: 20),
            // const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _infoBox(String text, {EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8), double fontSize = 16}) {
    return Container(
      padding: padding,
      color: const Color(0xFF262626),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _metricBox(String label, String value, {int flex = 1, double fontSize = 12}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: const Color(0xFF262626),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (value.isNotEmpty)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
