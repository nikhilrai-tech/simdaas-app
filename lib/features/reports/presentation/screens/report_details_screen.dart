import 'package:flutter/material.dart';
import '../../domain/report.dart';

class ReportDetailsScreen extends StatelessWidget {
  final Report report;

  const ReportDetailsScreen({required this.report, super.key});

  Widget _metricCircle(String label, String value, double percent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 92,
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: CircularProgressIndicator(
                  value: percent.clamp(0, 1),
                  strokeWidth: 8,
                  color: const Color(0xFF8E44FF),
                  // backgroundColor: Colors.white12,
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(value,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    String fmtDate(DateTime dt) => '${dt.toLocal()}'.split('.').first;

    // Layout-focused structure: vertical scroll with ordered sections.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Report'),
        actions: [
          // IconButton(onPressed: () {}, icon: const Icon(Icons.edit_outlined)),
          // IconButton(onPressed: () {}, icon: const Icon(Icons.share_outlined)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 2. Job Information Section
            const SizedBox(height: 8),
            _infoField(label: 'Serial No.', value: r.id),
            const SizedBox(height: 12),
            _infoField(
                label: 'Operator *', value: r.operatorName, required: true),
            const SizedBox(height: 12),
            _infoField(label: 'Boundary name', value: r.boundaryName),

            const SizedBox(height: 16),

            // 3. Field Snapshot Section
            _sectionTitle('Field Snapshot',
                'Color coded trajectory and boundary representation'),
            const SizedBox(height: 8),
            Container(
                height: 220,
                alignment: Alignment.center,
                child: const Text('Field snapshot / map placeholder')),

            const SizedBox(height: 16),

            // 4. Coverage & Application Metrics (four equal metrics)
            Row(children: [
              Expanded(
                  child: _metricBox(
                      title: 'Area', value: '${r.area.toStringAsFixed(2)} ha')),
              const SizedBox(width: 12),
              Expanded(
                  child: _metricBox(
                      title: 'Percentage Covered',
                      value: '${r.percentCovered.toStringAsFixed(0)}%')),
              const SizedBox(width: 12),
              Expanded(
                  child: _metricBox(
                      title: 'Amount of Material Applied',
                      value: '${r.materialApplied} L')),
              const SizedBox(width: 12),
              Expanded(
                  child: _metricBox(
                      title: 'Avg. Flow Rate',
                      value: '${r.avgFlowRate} L/min')),
            ]),

            const SizedBox(height: 16),

            // 5. Time Taken Section
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  flex: 1,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.timeTaken.inHours} Hrs',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text('Time taken'),
                      ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Start time: ${fmtDate(r.startTime)}'),
                        const SizedBox(height: 6),
                        Text('End time: ${fmtDate(r.endTime)}'),
                      ]),
                ),
              ]),
            ),

            const SizedBox(height: 16),

            // 6. PTO Active Time Section
            Text('PTO Active Time: ${r.ptoActiveTime.inMinutes} mins',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: _circularMetric(
                      label: 'Distance Travelled',
                      value: '${r.distanceTravelled} km',
                      percent: (r.distanceTravelled > 0 ? 1.0 : 0.0))),
              const SizedBox(width: 12),
              Expanded(
                  child: _circularMetric(
                      label: 'Total distance (PTO on)',
                      value: '${r.distanceWithPtoOn} km',
                      percent: (r.distanceWithPtoOn > 0 ? 1.0 : 0.0))),
              const SizedBox(width: 12),
              Expanded(
                  child: _circularMetric(
                      label: 'Distance Sprayed',
                      value: '${r.distanceSprayed} km',
                      percent: (r.distanceSprayed > 0 ? 1.0 : 0.0))),
            ]),

            const SizedBox(height: 16),

            // 7. Mix & Speed Details Section
            _infoField(
                label: 'Mix Details *',
                value: r.mixDetails,
                required: true,
                multiline: true),
            const SizedBox(height: 12),
            _infoField(label: 'Avg Speed', value: '${r.avgSpeed} km/h'),

            const SizedBox(height: 24),

            // 8. Final Status Section (Bottom)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                        value: (r.timeSaved.inSeconds /
                            (r.timeTaken.inSeconds > 0
                                ? r.timeTaken.inSeconds
                                : 1)))),
                const SizedBox(width: 16),
                const Expanded(
                    child: Text('Status: Saved',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600))),
              ]),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _infoField(
      {required String label,
      required String value,
      bool required = false,
      bool multiline = false}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (required) const SizedBox(width: 6),
            if (required) const Text('*', style: TextStyle(color: Colors.red)),
          ]),
          const SizedBox(height: 8),
          Text(value,
              maxLines: multiline ? null : 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
    ]);
  }

  Widget _metricBox({required String title, required String value}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _circularMetric(
      {required String label, required String value, required double percent}) {
    return Center(child: _metricCircle(label, value, percent));
  }
}
