import 'package:flutter/material.dart';

class TechnicianDashboardScreen extends StatelessWidget {
  const TechnicianDashboardScreen({super.key});

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Help & Support'),
        content: const Text(
            'For support, contact your administrator or Call 1234567890.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // Header
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withAlpha(220),
                  colorScheme.secondary.withAlpha(200),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  // Emblem
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(24),
                    ),
                    child: Center(
                      child: Icon(Icons.build, size: 34, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Technician',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Tools, plots and equipment',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.white.withAlpha(200))),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showHelp(context),
                    icon: Icon(Icons.help_outline,
                        color: Colors.white.withAlpha(220)),
                  )
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final cardWidth = isWide
                  ? (constraints.maxWidth - 48) / 2
                  : constraints.maxWidth - 32;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 1000),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _DashboardCard(
                            icon: Icons.map_outlined,
                            title: 'Plots',
                            subtitle: 'View and manage your plots',
                            color: colorScheme.primary,
                            onTap: () =>
                                Navigator.of(context).pushNamed('/plots'),
                          ),
                        ),

                        SizedBox(
                          width: cardWidth,
                          child: _DashboardCard(
                            icon: Icons.build_circle_outlined,
                            title: 'Equipments',
                            subtitle: 'Tools, sensors & maintenance',
                            color: colorScheme.secondary,
                            onTap: () => Navigator.of(context)
                                .pushNamed('/equipment_categories'),
                          ),
                        ),

                        // SizedBox(
                        //   width: cardWidth,
                        //   child: _DashboardCard(
                        //     icon: Icons.sensors,
                        //     title: 'Sensors',
                        //     subtitle: 'Live telemetry & diagnostics',
                        //     color: colorScheme.secondary,
                        //     onTap: () => Navigator.of(context).pushNamed('/monitoring'),
                        //   ),
                        // ),

                        // SizedBox(
                        //   width: cardWidth,
                        //   child: _DashboardCard(
                        //     icon: Icons.miscellaneous_services_outlined,
                        //     title: 'Maintenance',
                        //     subtitle: 'Create service requests',
                        //     color: colorScheme.error,
                        //     onTap: () => Navigator.of(context).pushNamed('/maintenance'),
                        //   ),
                        // ),

                        // SizedBox(
                        //   width: cardWidth,
                        //   child: _DashboardCard(
                        //     icon: Icons.qr_code_scanner,
                        //     title: 'Scan Device',
                        //     subtitle: 'Quick connect to control units',
                        //     color: colorScheme.primaryContainer,
                        //     onTap: () => Navigator.of(context).pushNamed('/scan_control_unit'),
                        //   ),
                        // ),

                        SizedBox(
                          width: cardWidth,
                          child: _DashboardCard(
                            icon: Icons.help_outline,
                            title: 'Help & Support',
                            subtitle: 'Docs, FAQs and contact',
                            color: colorScheme.primary,
                            onTap: () => _showHelp(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    this.info,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String? info;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;

    return Card(
      elevation: 4,
      shadowColor: accent.withAlpha(40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [accent.withAlpha(230), accent.withAlpha(180)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface)),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    if (info != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: cs.primary.withAlpha(180),
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(info!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant))),
                        ],
                      )
                    ]
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
