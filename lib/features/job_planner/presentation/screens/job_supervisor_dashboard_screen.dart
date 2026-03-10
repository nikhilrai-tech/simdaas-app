import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'dart:async';
import '../../../home/presentation/screens/reports_screen.dart';
import '../providers/job_providers.dart';

class JobSupervisorDashboardScreen extends ConsumerStatefulWidget {
  const JobSupervisorDashboardScreen({super.key});

  @override
  ConsumerState<JobSupervisorDashboardScreen> createState() => _JobSupervisorDashboardScreenState();
}

class _JobSupervisorDashboardScreenState extends ConsumerState<JobSupervisorDashboardScreen> {
  late final javaTimer = _setupAutoRefresh();

  dynamic _setupAutoRefresh() {
    return Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (mounted) _refreshData();
    });
  }

  Future<void> _refreshData() async {
    final userId = ref.read(authServiceProvider).currentUserId ?? 'demo_user';
    ref.invalidate(jobsListProvider(userId));
  }

  @override
  void dispose() {
    if (javaTimer is StreamSubscription) {
      (javaTimer as StreamSubscription).cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Make the grid responsive similar to Technician dashboard
    final isWide = MediaQuery.of(context).size.width > 600;
    final crossAxis = isWide ? 2 : 1;

    void openReports() {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (c) => const ReportsScreen()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Supervisor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: GridView.count(
            physics: const AlwaysScrollableScrollPhysics(),
            crossAxisCount: crossAxis,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 5 / 2,
            children: [
              _buildTile(context,
                  icon: Icons.schedule,
                  title: 'Job Schedule',
                  subtitle: 'View upcoming jobs',
                  color: Theme.of(context).colorScheme.primary.withAlpha(15),
                  onTap: () => Navigator.of(context).pushNamed('/jobs')),
              _buildTile(context,
                  icon: Icons.add,
                  title: 'Create Job',
                  subtitle: 'Create new job',
                  color: Theme.of(context).colorScheme.secondary.withAlpha(15),
                  onTap: () => Navigator.of(context).pushNamed('/create_job')),
              _buildTile(context,
                  icon: Icons.report,
                  title: 'Reports',
                  subtitle: 'View job reports',
                  color: Theme.of(context).colorScheme.surface.withAlpha(10),
                  onTap: openReports),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required Color? color,
      required VoidCallback onTap}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.all(12),
                child: Icon(icon,
                    size: 36, color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        style: TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
