import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/firmware_state.dart';
import '../providers/firmware_update_providers.dart';

/// The "Central Admin Panel" for OTA escalations (RFC-004 §2.3/§4.5) —
/// Super Admin-only, backed by GET /api/admin/firmware-alerts/.
class FirmwareAlertsScreen extends ConsumerWidget {
  const FirmwareAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(firmwareAlertsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Firmware Alerts')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(firmwareAlertsProvider),
        child: alertsAsync.when(
          data: (alerts) {
            if (alerts.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No firmware alerts.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _AlertTile(alert: alerts[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Failed to load alerts: $e')),
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});
  final FirmwareAlertEntity alert;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: Icon(
          alert.resolved ? Icons.check_circle_outline : Icons.error_outline,
          color: alert.resolved ? Colors.green : Colors.red,
        ),
        title: Text(alert.controlUnitName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alert.macAddr != null) Text('MAC: ${alert.macAddr}'),
            if (alert.owner != null) Text('Owner: ${alert.owner}'),
            Text('Error ${alert.statusCode}: ${alert.reason}'),
            Text(
              '${alert.createdAt.toLocal()}'.split('.').first,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
