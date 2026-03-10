import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simdaas/core/services/auth_service.dart';
import 'package:simdaas/core/services/connectivity_service.dart';
import 'package:simdaas/core/utils/error_utils.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../providers/plot_providers.dart';
import 'map_screen.dart';
import 'plot_details_screen.dart';

enum PlotSortOption { name, area, date }

class PlotListScreen extends ConsumerStatefulWidget {
  final bool showFab;
  const PlotListScreen({super.key, this.showFab = true});

  @override
  ConsumerState<PlotListScreen> createState() => _PlotListScreenState();
}

class _PlotListScreenState extends ConsumerState<PlotListScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  PlotSortOption _sortOption = PlotSortOption.date;
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      final userId = ref.read(authServiceProvider).currentUserId;
      if (userId != null) {
        ref.invalidate(plotsListProvider(userId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.read(authServiceProvider).currentUserId;
    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plots')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_outline,
                size: 64,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 16),
              const Text('Not signed in. Please login.'),
            ],
          ),
        ),
      );
    }

    final plotsAsync = ref.watch(plotsListProvider(userId));

    final conn = ref.watch(isOnlineStreamProvider);
    final online = conn.asData?.value ?? true;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: _isSearchExpanded
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearchExpanded = false;
                    _searchController.clear();
                  });
                },
              )
            : null,
        title: _isSearchExpanded
            ? Container(
                height: 45,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                  cursorColor: Colors.black,
                  decoration: InputDecoration(
                    hintText: 'Search field name...',
                    hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, color: Colors.black54, size: 20),
                      onPressed: () => _searchController.clear(),
                    ),
                  ),
                ),
              )
            : const Text('Plots'),
        actions: _isSearchExpanded
            ? []
            : [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearchExpanded = true;
                    });
                  },
                ),
                PopupMenuButton<PlotSortOption>(
                  icon: const Icon(Icons.sort),
                  onSelected: (opt) {
                    setState(() {
                      _sortOption = opt;
                    });
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                        value: PlotSortOption.name, child: Text('Sort by Name')),
                    const PopupMenuItem(
                        value: PlotSortOption.area, child: Text('Sort by Area')),
                    const PopupMenuItem(
                        value: PlotSortOption.date, child: Text('Sort by Date')),
                  ],
                ),
              ],
        bottom: online
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Container(
                  height: 28,
                  color: Colors.red.shade700,
                  alignment: Alignment.center,
                  child: const Text(
                    'Offline — showing last known data',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
      ),
      body: plotsAsync.when(
        data: (originalPlots) {
          final filtered = originalPlots.where((p) {
            if (_searchQuery.isEmpty) return true;
            return p.name.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();

          final plots = List.from(filtered);
          if (_sortOption == PlotSortOption.name) {
            plots.sort((a, b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          } else if (_sortOption == PlotSortOption.area) {
            plots.sort((a, b) => (b.area ?? 0).compareTo(a.area ?? 0));
          } else if (_sortOption == PlotSortOption.date) {
            plots.sort((a, b) =>
                (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          }

          if (plots.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(plotsListProvider(userId));
                try {
                  await ref.read(plotsListProvider(userId).future);
                } catch (_) {}
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 100),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchQuery.isEmpty
                                ? Icons.map_outlined
                                : Icons.search_off,
                            size: 64,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No plots yet'
                                : 'No matching plots',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Tap the + button to add your first plot',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(plotsListProvider(userId));
                try {
                  await ref.read(plotsListProvider(userId).future);
                } catch (_) {}
              },
              child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: plots.length,
                  itemBuilder: (context, idx) {
                    final f = plots[idx];
                    final summary = <String>[];
                    if (f.area != null) summary.add('${f.area} ha');
                    if (f.rowSpacing != null) summary.add('${f.rowSpacing} m');
                    if (f.treeCount != null)
                      summary.add('${f.treeCount} trees');
                    if (f.bedHeight != null)
                      summary.add('Bed H: ${f.bedHeight} m');

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (c) => PlotDetailsScreen(plot: f)));
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 100,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withAlpha(77),
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: PlotThumbnail(polygon: f.polygon),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      f.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (summary.isNotEmpty)
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: summary
                                            .map((s) => Chip(
                                                  backgroundColor: Colors.white,
                                                  label: Text(
                                                    s,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.black),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                    vertical: 0,
                                                  ),
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ))
                                            .toList(),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }));
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(plotsListProvider(userId));
            try {
              await ref.read(plotsListProvider(userId).future);
            } catch (_) {}
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(extractErrorMessage(e)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.showFab
          ? FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool?>(
                    MaterialPageRoute(builder: (c) => const MapScreen()));
                final userId = ref.read(authServiceProvider).currentUserId;
                if (result == true && userId != null) {
                  // Ensure provider is invalidated (MapScreen also invalidates but
                  // we do it here too for immediacy) and show confirmation.
                  ref.invalidate(plotsListProvider(userId));
                  showSuccessSnackBar(context, 'Plot added');
                }
              },
              icon: const Icon(Icons.add_location_alt),
              label: const Text('Add Plot'),
            )
          : null,
    );
  }
}

class PlotThumbnail extends StatelessWidget {
  final List<LatLng> polygon;
  const PlotThumbnail({super.key, required this.polygon});

  @override
  Widget build(BuildContext context) {
    if (polygon.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child:
            const Center(child: Icon(Icons.map, size: 28, color: Colors.grey)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: Colors.white,
        child: CustomPaint(
          painter: PlotPolygonPainter(polygon),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class PlotPolygonPainter extends CustomPainter {
  final List<LatLng> polygon;
  PlotPolygonPainter(this.polygon);

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.isEmpty) return;

    // compute bounds
    double minLat = double.infinity,
        maxLat = -double.infinity,
        minLng = double.infinity,
        maxLng = -double.infinity;
    for (final p in polygon) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }

    // add small padding
    final latPad = (maxLat - minLat) * 0.1;
    final lngPad = (maxLng - minLng) * 0.1;
    if (latPad == 0 && lngPad == 0) {
      // single-point fallback
      final paint = ui.Paint()..color = Colors.blue;
      final cx = size.width / 2;
      final cy = size.height / 2;
      canvas.drawCircle(ui.Offset(cx, cy), 4.0, paint);
      return;
    }

    minLat -= latPad;
    maxLat += latPad;
    minLng -= lngPad;
    maxLng += lngPad;

    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();

    double scaleX = size.width / (lngSpan == 0 ? 1 : lngSpan);
    double scaleY = size.height / (latSpan == 0 ? 1 : latSpan);

    // keep aspect ratio, fit inside
    final scale = math.min(scaleX, scaleY);

    // compute offsets to center the polygon
    final usedWidth = (lngSpan) * scale;
    final usedHeight = (latSpan) * scale;
    final offsetX = (size.width - usedWidth) / 2;
    final offsetY = (size.height - usedHeight) / 2;

    final path = ui.Path();
    for (int i = 0; i < polygon.length; i++) {
      final p = polygon[i];
      final x = offsetX + ((p.longitude - minLng) * scale);
      final y = offsetY + usedHeight - ((p.latitude - minLat) * scale);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final fill = ui.Paint()
      ..color = Colors.blue.withAlpha(89)
      ..style = ui.PaintingStyle.fill;
    final stroke = ui.Paint()
      ..color = Colors.blue
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant PlotPolygonPainter oldDelegate) =>
      oldDelegate.polygon != polygon;
}
