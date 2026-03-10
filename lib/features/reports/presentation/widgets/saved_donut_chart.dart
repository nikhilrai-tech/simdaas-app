import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class SavedDonutChart extends StatelessWidget {
  final double percentage;
  final String label;

  const SavedDonutChart({
    super.key,
    required this.percentage,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 120,
          child: PieChart(
            PieChartData(
              sectionsSpace: 0,
              centerSpaceRadius: 35,
              startDegreeOffset: -90,
              sections: [
                PieChartSectionData(
                  color: const Color(0xFFBB86FC),
                  value: percentage,
                  title: '${percentage.toStringAsFixed(0)}%',
                  radius: 15,
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                PieChartSectionData(
                  color: Colors.grey[200]!,
                  value: 100 - percentage,
                  title: '',
                  radius: 12,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
