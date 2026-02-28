import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ReportDonutChart extends StatelessWidget {
  final double percentage;
  final String label;
  final double radius;
  final double strokeWidth;

  const ReportDonutChart({
    super.key,
    required this.percentage,
    required this.label,
    this.radius = 40,
    this.strokeWidth = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: radius * 2,
          width: radius * 2,
          child: PieChart(
            PieChartData(
              sectionsSpace: 0,
              centerSpaceRadius: radius - strokeWidth,
              startDegreeOffset: -90,
              sections: [
                PieChartSectionData(
                  color: const Color(0xFFA855F7).withValues(alpha: 0.8),
                  value: percentage,
                  radius: strokeWidth,
                  showTitle: false,
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFA855F7), // Purple
                      Color(0xFFD8B4FE), // Light Purple
                    ],
                  ),
                ),
                PieChartSectionData(
                  color: Colors.white,
                  value: 100 - percentage,
                  radius: strokeWidth,
                  showTitle: false,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
