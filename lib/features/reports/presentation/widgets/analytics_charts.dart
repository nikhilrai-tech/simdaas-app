import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class DistanceDistributionPieChart extends StatelessWidget {
  final double distanceTravelled;
  final double distancePto;
  final double distanceLeft;
  final double distanceRight;

  const DistanceDistributionPieChart({
    super.key,
    required this.distanceTravelled,
    required this.distancePto,
    required this.distanceLeft,
    required this.distanceRight,
  });

  @override
  Widget build(BuildContext context) {
    // We visualize how much of total distance had active operations.
    // Note: Left/Right might overlap or be independent. 
    // Let's visualize: Idle Travel vs PTO Active Travel.
    // We can also add markers for specific nozzle usage if needed, but for a pie chart,
    // "Active (PTO)" vs "Transit (Idle)" is the cleanest split.
    
    final total = distanceTravelled > 0 ? distanceTravelled : 1.0;
    final active = distancePto > total ? total : distancePto;
    final idle = total - active;
    
    final activePercent = (active / total) * 100;
    final idlePercent = (idle / total) * 100;

    return AspectRatio(
      aspectRatio: 1.3,
      child: Row(
        children: [
          const SizedBox(height: 18),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: PieChart(
                PieChartData(
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 0,
                  centerSpaceRadius: 40,
                  sections: [
                    PieChartSectionData(
                      color: Colors.blue,
                      value: active,
                      title: '${activePercent.toStringAsFixed(0)}%',
                      radius: 50,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      color: Colors.grey,
                      value: idle,
                      title: '${idlePercent.toStringAsFixed(0)}%',
                      radius: 40,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Indicator(
                color: Colors.blue,
                text: 'PTO Active\n${active.toStringAsFixed(2)} km',
                isSquare: true,
              ),
              const SizedBox(height: 8),
              _Indicator(
                color: Colors.grey,
                text: 'Idle\n${idle.toStringAsFixed(2)} km',
                isSquare: true,
              ),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  final Color color;
  final String text;
  final bool isSquare;
  final double size;
  final Color? textColor;

  const _Indicator({
    required this.color,
    required this.text,
    required this.isSquare,
    this.size = 16,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: textColor ?? Colors.grey[700],
          ),
        )
      ],
    );
  }
}
