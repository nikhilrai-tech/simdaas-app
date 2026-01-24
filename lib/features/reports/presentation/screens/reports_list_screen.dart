import 'package:flutter/material.dart';
import '../../domain/report.dart';
import 'report_details_screen.dart';

class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  // Dummy reports
  List<Report> _dummy() => [
        Report(
          id: 'rpt-001',
          plotName: 'North Field',
          area: 3.42,
          operatorName: 'Alice',
          boundaryName: 'Boundary A',
          materialApplied: 12.5,
          avgFlowRate: 2.4,
          percentCovered: 98.2,
          timeTaken: const Duration(minutes: 42),
          startTime: DateTime.now().subtract(const Duration(hours: 3)),
          endTime:
              DateTime.now().subtract(const Duration(hours: 2, minutes: 18)),
          ptoActiveTime: const Duration(minutes: 35),
          distanceTravelled: 4.2,
          distanceWithPtoOn: 3.8,
          distanceSprayed: 3.5,
          mixDetails: 'Water 100L + Fertilizer 2L',
          avgSpeed: 6.5,
          timeSaved: const Duration(minutes: 10),
        ),
        Report(
          id: 'rpt-002',
          plotName: 'East Orchard',
          area: 1.75,
          operatorName: 'Bob',
          boundaryName: 'Boundary B',
          materialApplied: 8.0,
          avgFlowRate: 1.9,
          percentCovered: 92.0,
          timeTaken: const Duration(minutes: 28),
          startTime: DateTime.now().subtract(const Duration(days: 1, hours: 5)),
          endTime: DateTime.now()
              .subtract(const Duration(days: 1, hours: 4, minutes: 32)),
          ptoActiveTime: const Duration(minutes: 25),
          distanceTravelled: 2.1,
          distanceWithPtoOn: 1.9,
          distanceSprayed: 1.8,
          mixDetails: 'Water 80L + Pesticide 1.2L',
          avgSpeed: 5.8,
          timeSaved: const Duration(minutes: 8),
        ),
        Report(
          id: 'rpt-003',
          plotName: 'South Pasture',
          area: 5.6,
          operatorName: 'Carlos',
          boundaryName: 'Boundary C',
          materialApplied: 20.0,
          avgFlowRate: 3.1,
          percentCovered: 100.0,
          timeTaken: const Duration(minutes: 75),
          startTime: DateTime.now().subtract(const Duration(days: 2, hours: 6)),
          endTime: DateTime.now()
              .subtract(const Duration(days: 2, hours: 4, minutes: 45)),
          ptoActiveTime: const Duration(minutes: 70),
          distanceTravelled: 8.4,
          distanceWithPtoOn: 8.2,
          distanceSprayed: 8.0,
          mixDetails: 'Water 200L + Herbicide 3L',
          avgSpeed: 7.2,
          timeSaved: const Duration(minutes: 18),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final reports = _dummy();
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, i) {
          final r = reports[i];
          return ListTile(
            title: Text(r.plotName),
            subtitle: Text('${r.area.toStringAsFixed(2)} ha'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReportDetailsScreen(report: r))),
          );
        },
      ),
    );
  }
}
