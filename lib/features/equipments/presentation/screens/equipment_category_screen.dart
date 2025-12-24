import 'package:flutter/material.dart';
import 'equipment_list_screen.dart';
import 'equipment_troubleshooting_screen.dart';

class EquipmentCategoryScreen extends StatelessWidget {
  const EquipmentCategoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withAlpha(220),
                  cs.secondary.withAlpha(180)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Container(
                    height: 64,
                    width: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(22),
                    ),
                    child: const Center(
                        child: Icon(Icons.widgets_outlined,
                            color: Colors.white, size: 30)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Equipments',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Select a category to view devices',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.white.withAlpha(200))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _CategoryCard(
                        title: 'Control Units',
                        subtitle: 'Connect and manage control units',
                        icon: Icons.settings_remote,
                        color: cs.primary,
                        onTap: () => Navigator.of(context).pushNamed(
                            '/equipments',
                            arguments: {'category': 'control_unit'}),
                      ),
                      _CategoryCard(
                        title: 'Tractors',
                        subtitle: 'Tractor inventory and details',
                        icon: Icons.agriculture,
                        color: cs.secondary,
                        onTap: () => Navigator.of(context).pushNamed(
                            '/equipments',
                            arguments: {'category': 'tractor'}),
                      ),
                      _CategoryCard(
                        title: 'Sprayers',
                        subtitle: 'Sprayers and nozzle configs',
                        icon: Icons.invert_colors,
                        color: cs.tertiary ?? cs.secondary,
                        onTap: () => Navigator.of(context).pushNamed(
                            '/equipments',
                            arguments: {'category': 'sprayer'}),
                      ),
                      _CategoryCard(
                        title: 'Troubleshooting',
                        subtitle: 'Diagnostics & common fixes',
                        icon: Icons.build_circle_outlined,
                        color: cs.error,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (context) =>
                                EquipmentTroubleshootingScreen())) /* fallback */,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: MediaQuery.of(context).size.width > 900
          ? 460
          : MediaQuery.of(context).size.width > 600
              ? 440
              : double.infinity,
      child: Card(
        elevation: 3,
        shadowColor: color.withAlpha(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [color.withAlpha(220), color.withAlpha(180)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 12),
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
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
