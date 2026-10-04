import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simdaas/core/utils/api_error_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';
import 'package:simdaas/core/services/heatmap_preferences_service.dart';
import 'package:simdaas/core/utils/mac_utils.dart';
import 'package:simdaas/core/utils/gps_jump_detector.dart';
import '../../domain/report.dart';
import '../../../plot_mapping/domain/entities/plot.dart';
import '../../../plot_mapping/presentation/utils/row_line_coverage.dart';
import '../providers/report_providers.dart';
import '../utils/report_pdf_builder.dart';
import '../widgets/plot_snapshot.dart';
import '../widgets/saved_donut_chart.dart';

const String _kSatelliteTileUrl =
    'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
const String _kNormalTileUrl =
    'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}';

/// Small floating icon button toggling satellite/normal map view, styled to
/// match the existing fullscreen/close buttons on these map cards. Shared by
/// the inline report map header and its fullscreen page.
Widget _mapViewToggleButton(
    {required bool isSatellite, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4),
        ],
      ),
      child: Icon(isSatellite ? Icons.map : Icons.satellite_alt,
          size: 22, color: Colors.black87),
    ),
  );
}

class ReportDetailsScreen extends ConsumerStatefulWidget {
  final Report report;

  const ReportDetailsScreen({required this.report, super.key});

  @override
  ConsumerState<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends ConsumerState<ReportDetailsScreen> {
  HeatmapType _heatmapType = HeatmapType.gps;
  bool _isSatelliteView = true;
  // Recovered-via-backfill overlay: GPS heatmap only (a toggle there, not a
  // whole separate mode like L/R) -- Speed/Spray/L-R never show it.
  bool _showBackfillOverlay = true;

  // Wraps the map Card below so _shareReport can screenshot the live
  // FlutterMap (trajectory present -- no pre-rendered bitmap exists for
  // that case, see report_pdf_builder.dart's doc comment).
  final GlobalKey _mapRepaintKey = GlobalKey();
  bool _isSharing = false;

  // reportDetailProvider is a plain FutureProvider.family (no autoDispose)
  // -- once fetched it stays cached for the rest of the app session, unlike
  // the reports LIST screen (which already re-fetches every 30s and on
  // pull-to-refresh). Without this, a report opened while still Pending/
  // Verifying kept showing that stale snapshot here even after the backend
  // finished verifying it minutes later -- the list screen behind it showed
  // the right status, but coming back into this same report showed the old
  // one, until the whole app was killed and reopened (the only thing that
  // actually clears the provider cache).
  late final StreamSubscription<void> _autoRefreshSub;

  @override
  void initState() {
    super.initState();
    // `late final _autoRefreshSub = _setupAutoRefresh();` at the
    // declaration looks equivalent but is a real bug: a `late` field only
    // runs its initializer on first READ, and the only other place this
    // field was read was dispose() -- so the timer never actually started
    // until the screen was already being torn down. Assigning it here in
    // initState() is what makes it actually run.
    _autoRefreshSub = _setupAutoRefresh();
    // Also refresh immediately on open, not just on the next 30s tick --
    // reopening a report already cached from an earlier visit THIS app
    // session (e.g. back to the list, then back into the same report)
    // would otherwise keep showing whatever was cached from that earlier
    // visit for up to 30s, even though the list screen behind it may have
    // already moved on to a newer status.
    _refreshReport();
  }

  StreamSubscription<void> _setupAutoRefresh() {
    return Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (mounted) _refreshReport();
    });
  }

  Future<void> _refreshReport() async {
    ref.invalidate(reportDetailProvider(widget.report.id));
  }

  @override
  void dispose() {
    _autoRefreshSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(reportDetailProvider(widget.report.id));
    final report = detailAsync.asData?.value ?? widget.report;
    // Not read directly -- watching is what makes the heatmaps below
    // repaint immediately after Profile > Settings > Heatmap colors is
    // saved. See heatmap_preferences_service.dart.
    ref.watch(heatmapThresholdsProvider);
    final dateFormat = DateFormat('h:mm a, dd MMM yyyy');

    final startTime = report.startedAt ??
        (report.trajectory.isNotEmpty ? report.trajectory.first.timestamp : report.createdAt);
    final endTime = report.endedAt ??
        (report.trajectory.isNotEmpty ? report.trajectory.last.timestamp : report.createdAt);
    final duration = endTime.difference(startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final durationStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    final avgSpeed = report.avgSpeedKmph;
    final maxSpeed = report.maxSpeedKmph;
    final areaCoveredAcres = report.areaCoveredSqm / 4046.86;
    // Same source as the "Applied" stat on the reports list (backend prefers
    // the flow-sensor total over the tank-level delta) — recomputing from
    // initial/final tank level here would drift from that value and show a
    // different number for the same report.
    final sprayLitres = report.sprayUsedLitres;
    // Use backend-computed flow rates directly (tank_spray_used / pto_min and / area_acres)
    final avgFlowRateLperMin = report.avgFlowRateLpm;
    final avgFlowRatePerAcre = report.avgFlowRateLacre;
    // Left/right solenoid OFF = distance with PTO on but solenoid state = 0
    final leftSolenoidOffKm =
        (report.distanceWithPtoKm - report.distanceWithLeftSprayKm).clamp(0.0, double.infinity);
    final rightSolenoidOffKm =
        (report.distanceWithPtoKm - report.distanceWithRightSprayKm).clamp(0.0, double.infinity);
    final plotAreaHa = report.plotAreaSqm / 10000;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Report Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
              icon: _isSharing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share_outlined, color: Colors.black),
              onPressed: _isSharing ? null : () => _shareReport(context, report)),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete report',
            onPressed: () => _confirmDelete(context, report),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshReport,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (report.verificationStatus == 'verified') ...[
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade600, Colors.green.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.verified_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "Matches your sprayer's own record",
                            style: TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            RepaintBoundary(
              key: _mapRepaintKey,
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: _buildMapHeader(report),
              ),
            ),
            const SizedBox(height: 12),
            _buildHeatmapToggles(),
            const SizedBox(height: 20),

            // ── Saved ─────────────────────────────────────────────────────
            _sectionHeader('Saved'),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF015685), Color(0xFF0277B5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.eco_outlined, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.chemicalSavedNote != null
                              ? '—'
                              : '${report.chemicalSavedPercentage.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          report.chemicalSavedNote ??
                              'Chemical Saved (Auto mode)',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (report.sessionMode != null) ...[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: report.sessionMode == 'device'
                          ? Colors.teal.shade50
                          : Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: report.sessionMode == 'device'
                            ? Colors.teal.shade200
                            : Colors.indigo.shade200,
                      ),
                    ),
                    child: Text(
                      report.sessionMode == 'device' ? 'Manual' : 'Automatic',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: report.sessionMode == 'device'
                            ? Colors.teal.shade800
                            : Colors.indigo.shade800,
                      ),
                    ),
                  ),
                  // Data composition -- independent of verificationStatus
                  // below, which gets overwritten to verifying/verified/
                  // needs_review once the log-check pipeline picks the
                  // report up and no longer says whether it started out
                  // backfilled. Shown for both modes.
                  if (report.amended)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        'Log Updated',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    )
                  else if (report.hadBackfillData)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Text(
                        'Backfill',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Normal',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  // Verification pipeline status -- Manual only, since
                  // Automatic reports are never checked against a device
                  // log.
                  if (report.sessionMode == 'device' &&
                      (report.verificationStatus == 'live' ||
                          report.verificationStatus == 'prefilled'))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Pending',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  if (report.sessionMode == 'device' &&
                      report.verificationStatus == 'verifying')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Verifying',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blueGrey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (report.sessionMode == 'device' &&
                      report.verificationStatus == 'verified')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded,
                              size: 14, color: Colors.green.shade800),
                          const SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (report.sessionMode == 'device' &&
                      report.verificationStatus == 'needs_review')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        'Needs Review',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ),
                  // MAC+session-ID label goes last, after every badge.
                  if (report.sessionMode == 'device' &&
                      formatDeviceSessionLabel(
                              report.controlUnitMac, report.deviceSessionId) !=
                          null)
                    Text(
                      formatDeviceSessionLabel(
                          report.controlUnitMac, report.deviceSessionId)!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (report.verificationStatus == 'needs_review') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: Colors.red.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        report.verificationNote ??
                            'Some totals in this report don\'t match your sprayer\'s '
                                'own record.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (report.pendingNetworkData) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wifi_off_rounded,
                        color: Colors.orange.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This report may be incomplete — the session ended '
                        'after a long connectivity gap. It will update '
                        'automatically if the device sends recovered data.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (report.amended) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.cloud_sync_outlined,
                        color: Colors.blue.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        report.amendedNote ??
                            'Updated after network data was recovered from a connectivity gap.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // TEMP DEBUG (2026-09-30): old-vs-new values for whichever
            // totals a log-verification correction changed, for manual
            // spot-checking. Remove this block once the investigation is
            // done -- see matching TEMP DEBUG markers in
            // jobs/serializers.py and lib/features/reports/domain/report.dart.
            if (report.verificationMismatchesDebug != null &&
                report.verificationMismatchesDebug!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bug_report_outlined,
                            color: Colors.purple.shade800, size: 18),
                        const SizedBox(width: 8),
                        Text('DEBUG: old vs new values (Log Updated)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.purple.shade900)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final entry
                        in report.verificationMismatchesDebug!.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${(entry.value as Map)['label'] ?? entry.key}: '
                          '${(entry.value as Map)['report']} -> '
                          '${(entry.value as Map)['log']}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.purple.shade900),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (report.gpsUnavailableNote != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        report.gpsUnavailableNote!,
                        style: TextStyle(
                            fontSize: 13, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Performance Overview ──────────────────────────────────────
            _sectionHeader('Performance Overview'),
            Row(
              children: [
                _metricCard('Area Covered',
                    '${report.completionPercentage.toStringAsFixed(1)}%',
                    Icons.pie_chart,
                    color: Colors.purple,
                    subtitle:
                        '${areaCoveredAcres.toStringAsFixed(2)} / ${(report.plotAreaSqm / 4046.86).toStringAsFixed(2)} ac'),
                const SizedBox(width: 12),
                _metricCard('Total Sprayed',
                    '${sprayLitres.toStringAsFixed(1)} L',
                    Icons.water_drop,
                    color: Colors.blue),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Avg Flow Rate',
                    '${avgFlowRateLperMin.toStringAsFixed(2)} L/min',
                    Icons.speed,
                    color: Colors.orange),
                const SizedBox(width: 12),
                _metricCard('Avg Flow Rate',
                    '${avgFlowRatePerAcre.toStringAsFixed(2)} L/acre',
                    Icons.speed_outlined,
                    color: Colors.amber),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Avg Speed',
                    '${avgSpeed.toStringAsFixed(1)} km/h',
                    Icons.shutter_speed,
                    color: Colors.deepOrange),
                const SizedBox(width: 12),
                _metricCard('Max Speed',
                    '${maxSpeed.toStringAsFixed(1)} km/h',
                    Icons.speed,
                    color: Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Total Distance',
                    '${report.distanceTravelledKm.toStringAsFixed(2)} km',
                    Icons.directions_run,
                    color: Colors.blueGrey),
                const SizedBox(width: 12),
                _metricCard('PTO On Dist.',
                    '${report.distanceWithPtoKm.toStringAsFixed(2)} km',
                    Icons.settings_input_component,
                    color: Colors.teal),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metricCard('Left Sol. Off',
                    '${leftSolenoidOffKm.toStringAsFixed(2)} km',
                    Icons.chevron_left,
                    color: Colors.indigo),
                const SizedBox(width: 12),
                _metricCard('Right Sol. Off',
                    '${rightSolenoidOffKm.toStringAsFixed(2)} km',
                    Icons.chevron_right,
                    color: Colors.deepPurple),
              ],
            ),

            const SizedBox(height: 24),

            // ── Session Details ───────────────────────────────────────────
            _sectionHeader('Session Details'),
            // Time strip
            IntrinsicHeight(
             child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _timeChip(Icons.play_arrow_rounded, 'Start',
                    DateFormat('h:mm a').format(startTime),
                    DateFormat('dd MMM').format(startTime),
                    const Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                _timeChip(Icons.stop_rounded, 'End',
                    DateFormat('h:mm a').format(endTime),
                    DateFormat('dd MMM').format(endTime),
                    const Color(0xFFC62828)),
                const SizedBox(width: 8),
                _timeChip(Icons.hourglass_bottom_rounded, 'Duration',
                    durationStr, '', const Color(0xFF015685)),
              ],
             ),
            ),
            const SizedBox(height: 12),
            // Equipment info card
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _equipRow(Icons.memory, 'Control Unit',
                      report.controlUnitName ?? report.controlUnitId ?? '-',
                      const Color(0xFF015685)),
                  _equipRow(Icons.map_outlined, 'Linked Plot',
                      report.plot?.name ?? '-',
                      const Color(0xFF2E7D32)),
                  _equipRow(Icons.straighten, 'Plot Area',
                      '${plotAreaHa.toStringAsFixed(2)} ha',
                      Colors.blueGrey),
                  _equipRow(Icons.water_drop_outlined, 'Linked Sprayer',
                      report.linkedSprayerName ?? '-',
                      const Color(0xFF8E4600)),
                  _equipRow(Icons.agriculture_outlined, 'Linked Tractor',
                      report.linkedTractorName ?? '-',
                      const Color(0xFF4A148C),
                      isLast: true),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Additional Details (user-editable, per report) ─────────────
            _sectionHeader('Additional Details'),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _editableRow(
                    Icons.person_outline,
                    'Driver Name',
                    report.driverName,
                    const Color(0xFF00695C),
                    onTap: () => _editReportField(
                      context: context,
                      title: 'Driver Name',
                      currentValue: report.driverName,
                      onSave: (value) => _saveReportField(driverName: value),
                    ),
                  ),
                  _editableRow(
                    Icons.eco_outlined,
                    'Fertilizers Used',
                    report.fertilizersUsed,
                    const Color(0xFF558B2F),
                    onTap: () => _editReportField(
                      context: context,
                      title: 'Fertilizers Used',
                      currentValue: report.fertilizersUsed,
                      multiline: true,
                      onSave: (value) =>
                          _saveReportField(fertilizersUsed: value),
                    ),
                  ),
                  _editableRow(
                    Icons.science_outlined,
                    'Agrochemical',
                    report.agrochemicalUsed,
                    const Color(0xFF6D4C41),
                    isLast: true,
                    onTap: () => _editReportField(
                      context: context,
                      title: 'Agrochemical',
                      currentValue: report.agrochemicalUsed,
                      multiline: true,
                      onSave: (value) =>
                          _saveReportField(agrochemicalUsed: value),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Report report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text(
            'Are you sure you want to delete this report? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(reportRepoProvider).deleteReport(report.id);
      ref.invalidate(reportsListProvider);
      if (context.mounted) {
        showSuccessSnackBar(context, 'Report deleted');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) {
        showGenericErrorSnackBar(context, 'Failed to delete report');
      }
    }
  }

  // Hand-rolled MethodChannel, backed by MainActivity.kt's own code (not a
  // third-party plugin) -- path_provider_android kept failing to register
  // on real devices across several pub resolutions/overrides (see git log
  // on this method), throwing MissingPluginException despite every local
  // check showing it should work. MainActivity is the app's own entry
  // point, so there's no separate package version that can ever drift out
  // of registration the way a pub plugin can. iOS/desktop still have no
  // reported issue, so they keep using path_provider.
  static const _androidCacheDirChannel = MethodChannel('com.simdaas.agrios/cache_dir');

  Future<String> _scratchDirPath() async {
    if (Platform.isAndroid) {
      final path = await _androidCacheDirChannel.invokeMethod<String>('getCacheDir');
      if (path != null && path.isNotEmpty) return path;
      throw 'Android cache_dir channel returned no path';
    }
    final dir = await getTemporaryDirectory();
    return dir.path;
  }

  // ── Share as a branded PDF (WhatsApp/Email/etc.) ─────────────────────────
  //
  // Each step below is wrapped in its own try/catch -- rather than one catch
  // around the whole method -- purely so a failure can say WHICH step broke
  // (building the PDF vs. writing the temp file vs. the OS share sheet
  // itself) instead of a single generic "something went wrong". The
  // surfaced text is deliberately the raw exception, truncated -- this is
  // temporary extra detail to diagnose the first real-device failure
  // reports; a generic message can come back once that's root-caused.
  Future<void> _shareReport(BuildContext context, Report report) async {
    setState(() => _isSharing = true);
    try {
      final mapImages = await _captureHeatmapImages(report);

      final Uint8List pdfBytes;
      try {
        pdfBytes = await buildReportPdf(report: report, mapImages: mapImages);
      } catch (e, st) {
        debugPrint('Share report: PDF build failed: $e\n$st');
        throw 'building the PDF: $e';
      }

      // kIsWeb branch FIRST, before anything touches dart:io -- Platform,
      // File, Directory all throw "Unsupported operation" on web (dart:io
      // compiles there but most of it is a non-functional stub), which is
      // exactly what broke here: a tester was using the web build
      // (localhost:xxxx/#/dashboard) the whole time, so every earlier
      // "fix" aimed at Android native plugins was chasing the wrong
      // platform. XFile.fromData() keeps the PDF entirely in memory --
      // share_plus_web's _fromXFile() just calls xFile.readAsBytes() on it
      // and hands the bytes to the browser's Web Share API, no filesystem
      // involved at all.
      final XFile xfile;
      if (kIsWeb) {
        xfile = XFile.fromData(
          pdfBytes,
          name: 'agrios_report_${report.id}.pdf',
          mimeType: 'application/pdf',
        );
      } else {
        try {
          final cacheDirPath = await _scratchDirPath();
          final file = File('$cacheDirPath/agrios_report_${report.id}.pdf');
          await file.writeAsBytes(pdfBytes, flush: true);
          xfile = XFile(file.path, mimeType: 'application/pdf');
        } catch (e, st) {
          debugPrint('Share report: writing temp file failed: $e\n$st');
          throw 'saving the file: $e';
        }
      }

      final plotName = report.plot?.name ?? 'report';
      try {
        final result = await SharePlus.instance.share(ShareParams(
          files: [xfile],
          text: 'Agrios spray report — $plotName (Report #${report.id})',
          subject: 'Agrios Report #${report.id}',
        ));
        debugPrint('Share report: share sheet result = ${result.status}');
      } catch (e, st) {
        debugPrint('Share report: share sheet failed: $e\n$st');
        throw 'opening the share sheet: $e';
      }
    } catch (e) {
      if (context.mounted) {
        showGenericErrorSnackBar(context, 'Failed to share report — $e');
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // No live map was ever rendered for a trajectory-less report (see
  // _buildMapHeader) -- PlotSnapshot there just shows the backend's own
  // plot-polygon PNG, already base64, so reuse that directly (same bytes
  // for every mode -- there's no live map to switch anyway) instead of
  // screenshotting nothing. Otherwise, capture one screenshot PER heatmap
  // mode the share PDF needs (GPS/Spray/Speed, see
  // report_pdf_builder.dart) by switching _heatmapType, letting the map
  // widget rebuild+repaint, then screenshotting the RepaintBoundary --
  // there's no pre-rendered bitmap for any of these (no backend heatmap
  // renderer exists at all), each one only exists on screen for as long as
  // this mode switch holds.
  Future<Map<HeatmapType, Uint8List?>> _captureHeatmapImages(Report report) async {
    if (report.trajectory.isEmpty) {
      Uint8List? snapshot;
      if (report.plotSnapshot != null && report.plotSnapshot!.isNotEmpty) {
        try {
          snapshot = base64Decode(report.plotSnapshot!);
        } catch (_) {
          snapshot = null;
        }
      }
      return {
        HeatmapType.gps: snapshot,
        HeatmapType.spraying: snapshot,
        HeatmapType.speed: snapshot,
      };
    }

    final originalType = _heatmapType;
    final images = <HeatmapType, Uint8List?>{};
    try {
      for (final type in [HeatmapType.gps, HeatmapType.spraying, HeatmapType.speed]) {
        if (!mounted) break;
        setState(() => _heatmapType = type);
        // Lets the map (PolygonLayer rebuilt for the new heatmap mode)
        // actually repaint before the screenshot -- setState alone only
        // schedules the frame, it doesn't wait for it to be painted. The
        // extra delay is a known RepaintBoundary.toImage() gotcha: on some
        // renderers endOfFrame resolves once paint commands are issued but
        // before the GPU texture backing the boundary actually finishes
        // compositing, so a screenshot taken immediately after can still
        // show the PREVIOUS mode's colors.
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 100));
        images[type] = await _captureMapRepaintBoundary();
      }
    } finally {
      if (mounted && _heatmapType != originalType) {
        setState(() => _heatmapType = originalType);
        await WidgetsBinding.instance.endOfFrame;
      }
    }
    return images;
  }

  Future<Uint8List?> _captureMapRepaintBoundary() async {
    try {
      final boundary =
          _mapRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ── Map header with fullscreen button ──────────────────────────────────
  Widget _buildMapHeader(Report report) {
    if (report.trajectory.isEmpty) {
      return PlotSnapshot(
        plot: report.plot,
        base64Image: report.plotSnapshot,
        height: 180,
      );
    }

    final points = report.trajectory.map((p) => LatLng(p.lat, p.lon)).toList();
    final centroid = _getCentroid(points);
    // Populated (as a side effect) by buildHeatmapCoverageBands below with
    // every point plotted on a best-guess row while a genuine row-to-row
    // transition was still unconfirmed -- see buildForcedTransitionMarkers.
    final forcedTransitionPoints = <LatLng>[];

    return Stack(
      children: [
        Container(
          height: 250,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: centroid,
                initialZoom: 18.0,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      _isSatelliteView ? _kSatelliteTileUrl : _kNormalTileUrl,
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (report.plot != null)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: report.plot!.polygon,
                        color: const Color(0xFF00A36C).withOpacity(0.1),
                        borderStrokeWidth: 2.0,
                        borderColor: const Color(0xFF00A36C).withOpacity(0.5),
                      ),
                    ],
                  ),
                if (report.plot != null &&
                    report.plot!.rowLines != null &&
                    report.plot!.rowLines!.isNotEmpty) ...[
                  PolygonLayer(
                    polygons: RowLineCoverage.buildHeatmapCoverageBands(
                      rowLines: report.plot!.rowLines!,
                      insidePoints: _buildInsideTrackPoints(
                          report.trajectory, report.plot),
                      rowSpacing: report.plot!.rowSpacing ?? 3.0,
                      heatmapType: _heatmapType,
                      polygon: report.plot!.polygon,
                      forcedTransitionPoints: forcedTransitionPoints,
                    ),
                  ),
                  MarkerLayer(
                    markers: RowLineCoverage.buildForcedTransitionMarkers(
                        forcedTransitionPoints),
                  ),
                  if (_heatmapType == HeatmapType.gps && _showBackfillOverlay)
                    PolygonLayer(
                      polygons: RowLineCoverage.buildHeatmapCoverageBands(
                        rowLines: report.plot!.rowLines!,
                        insidePoints: _buildInsideTrackPoints(
                            report.trajectory, report.plot),
                        rowSpacing: report.plot!.rowSpacing ?? 3.0,
                        heatmapType: _heatmapType,
                        polygon: report.plot!.polygon,
                        asBackfillOverlay: true,
                      ),
                    ),
                  PolylineLayer(
                    polylines: RowLineCoverage.buildRowLines(
                      rowLines: report.plot!.rowLines!,
                    ),
                  ),
                ],
                PolylineLayer(
                  polylines:
                      _buildHeatmapPolylines(report.trajectory, report.plot),
                ),
                if (_heatmapType == HeatmapType.gps) ...[
                  PolylineLayer(
                    polylines: _buildGpsJumpLines(report.trajectory),
                  ),
                  MarkerLayer(
                    markers: _buildGpsJumpMarkers(report.trajectory),
                  ),
                ],
                MarkerLayer(
                  markers: [
                    Marker(
                      point: points.first,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.play_circle_fill,
                          color: Colors.green, size: 30),
                    ),
                    Marker(
                      point: points.last,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.stop_circle,
                          color: Colors.red, size: 30),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Satellite/Normal toggle (top-left)
        Positioned(
          top: 12,
          left: 12,
          child: _mapViewToggleButton(
            isSatellite: _isSatelliteView,
            onTap: () => setState(() => _isSatelliteView = !_isSatelliteView),
          ),
        ),
        // Legend (top-right)
        Positioned(
          top: 12,
          right: 12,
          child: _buildLegend(),
        ),
        // Fullscreen button (bottom-left)
        Positioned(
          bottom: 12,
          left: 12,
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _FullScreenMapPage(
                report: report,
                initialHeatmapType: _heatmapType,
                initialIsSatelliteView: _isSatelliteView,
              ),
            )),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4),
                ],
              ),
              child: const Icon(Icons.fullscreen, size: 22, color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon,
      {Color color = Colors.blue, String? subtitle}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _timeChip(IconData icon, String label, String value, String sub, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3)),
            ]),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
            if (sub.isNotEmpty)
              Text(sub,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _equipRow(IconData icon, String label, String value, Color accentColor,
      {bool isLast = false}) {
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: Colors.grey[100]!, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
        ],
      ),
    );
  }

  // Same visual style as _equipRow, but tappable — used for the
  // user-editable Driver Name / Fertilizers Used / Agrochemical fields.
  // Shows "N/A" until the user fills a value in.
  Widget _editableRow(
      IconData icon, String label, String? value, Color accentColor,
      {required VoidCallback onTap, bool isLast = false}) {
    final displayValue =
        (value == null || value.trim().isEmpty) ? 'N/A' : value;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: Colors.grey[100]!, width: 1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(displayValue,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit, size: 15, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Future<void> _editReportField({
    required BuildContext context,
    required String title,
    required String? currentValue,
    required Future<void> Function(String value) onSave,
    bool multiline = false,
  }) async {
    final controller = TextEditingController(
        text: (currentValue ?? '').trim() == 'N/A' ? '' : (currentValue ?? ''));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: multiline ? 3 : 1,
          decoration: InputDecoration(
            hintText: 'Enter $title',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelled
    await onSave(result);
  }

  Future<void> _saveReportField(
      {String? driverName,
      String? fertilizersUsed,
      String? agrochemicalUsed}) async {
    try {
      await ref.read(reportRepoProvider).updateReportDetails(
            widget.report.id,
            driverName: driverName,
            fertilizersUsed: fertilizersUsed,
            agrochemicalUsed: agrochemicalUsed,
          );
      ref.invalidate(reportDetailProvider(widget.report.id));
      if (context.mounted) showSuccessSnackBar(context, 'Saved');
    } catch (e) {
      if (context.mounted) {
        showGenericErrorSnackBar(context, 'Failed to save — try again');
      }
    }
  }

  Widget _buildLegend() {
    List<Widget> items = [];
    switch (_heatmapType) {
      case HeatmapType.gps:
        items = [
          _legendItem('Auto', Colors.blue),
          _legendItem('Manual', Colors.grey),
          _legendItem('PTO Off', Colors.orange),
          _legendItem('Outside', Colors.red),
        ];
        break;
      case HeatmapType.speed:
        final labels = HeatmapColorUtils.speedLegendLabels();
        items = [
          _legendItem(labels[0], Colors.yellow),
          _legendItem(labels[1], Colors.green),
          _legendItem(labels[2], Colors.red),
        ];
        break;
      case HeatmapType.spraying:
        final labels = HeatmapColorUtils.sprayLegendLabels();
        items = [
          _legendItem(labels[0], Colors.white),
          _legendItem(labels[1], Colors.blue.shade800),
          _legendItem(labels[2], Colors.red.shade400),
          _legendItem(labels[3], Colors.black),
        ];
        break;
      case HeatmapType.leftRight:
        items = [
          _legendItem('Left only', Colors.orange.shade700),
          _legendItem('Right only', Colors.purple.shade700),
          _legendItem('Both', Colors.teal.shade700),
          _legendItem('Neither', Colors.white),
        ];
        break;
    }
    if (_heatmapType == HeatmapType.gps &&
        _showBackfillOverlay &&
        widget.report.trajectory.any((p) => p.isBuffered)) {
      items.add(_legendItem('Recovered (backfill)', Colors.deepPurpleAccent));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: items,
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHeatmapToggles() {
    final hasBackfill = widget.report.trajectory.any((p) => p.isBuffered);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _heatmapButton(HeatmapType.gps, 'GPS'),
            const SizedBox(width: 8),
            _heatmapButton(HeatmapType.speed, 'Speed'),
            const SizedBox(width: 8),
            _heatmapButton(HeatmapType.spraying, 'Spray'),
            const SizedBox(width: 8),
            _heatmapButton(HeatmapType.leftRight, 'L/R'),
          ],
        ),
        if (_heatmapType == HeatmapType.gps && hasBackfill) ...[
          const SizedBox(height: 8),
          _backfillToggleChip(),
        ],
      ],
    );
  }

  Widget _backfillToggleChip() {
    final on = _showBackfillOverlay;
    return InkWell(
      onTap: () => setState(() => _showBackfillOverlay = !_showBackfillOverlay),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF262626) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.visibility : Icons.visibility_off,
                size: 14, color: on ? Colors.white : Colors.black87),
            const SizedBox(width: 6),
            Text(
              'Backfill',
              style: TextStyle(
                color: on ? Colors.white : Colors.black87,
                fontWeight: on ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heatmapButton(HeatmapType type, String label) {
    final isSelected = _heatmapType == type;
    return InkWell(
      onTap: () => setState(() => _heatmapType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF262626) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  List<HeatmapTrackPoint> _buildInsideTrackPoints(
      List<GPSPointData> trajectory, PlotEntity? plot) {
    final result = <HeatmapTrackPoint>[];
    GPSPointData? prev;
    for (final p in trajectory) {
      final point = LatLng(p.lat, p.lon);
      bool isInPlot = true;
      if (plot?.polygon != null && plot!.polygon.length >= 3) {
        isInPlot = _isPointInPolygon(point, plot.polygon);
      }
      if (!isInPlot) continue;

      // Whether this point is an implausible GPS jump from the PREVIOUS
      // in-plot point in this list (see GpsJumpDetector) -- own list, own
      // consecutive pairs, so a stretch driven outside the plot in between
      // (a real gap, not a glitch) doesn't get mistaken for one.
      final isJump = prev != null &&
          GpsJumpDetector.isJump(
              LatLng(prev.lat, prev.lon), prev.timestamp, point, p.timestamp);
      prev = p;

      // The backend now records a GPS point on every telemetry packet while
      // spraying (see session_service.py's should_record), so trajectory is
      // as dense as what the live Monitoring screen draws from — no need to
      // scale the flow value to compensate for sparse sampling anymore.
      result.add(HeatmapTrackPoint(
        position: point,
        isInPlot: true,
        ptoOn: p.ptoState == 1,
        isAuto: p.sprayMode == 1,
        speed: p.speedKmph,
        flowRate: p.flowRateLpm,
        leftSolenoidOn: p.leftSolenoidState == 1,
        rightSolenoidOn: p.rightSolenoidState == 1,
        isBuffered: p.isBuffered,
        isJumpFromPrevious: isJump,
      ));
    }
    return result;
  }

  // Pink dashed segments marking implausible GPS jumps in the raw
  // trajectory -- shown on the GPS heatmap only, regardless of plot
  // membership. See GpsJumpDetector.
  List<Polyline> _buildGpsJumpLines(List<GPSPointData> trajectory) {
    return GpsJumpDetector.buildJumpLines(
      trajectory.map((p) => LatLng(p.lat, p.lon)).toList(),
      trajectory.map((p) => p.timestamp).toList(),
    );
  }

  List<Marker> _buildGpsJumpMarkers(List<GPSPointData> trajectory) {
    return GpsJumpDetector.buildJumpMarkers(
      trajectory.map((p) => LatLng(p.lat, p.lon)).toList(),
      trajectory.map((p) => p.timestamp).toList(),
    );
  }

  List<Polyline> _buildHeatmapPolylines(
      List<GPSPointData> trajectory, PlotEntity? plot) {
    final List<Polyline> result = [];
    if (trajectory.length < 2) return result;

    List<LatLng> currentPoints = [];
    Color? currentColor;

    void flush({double strokeWidth = 4.0}) {
      if (currentPoints.length >= 2 && currentColor != null) {
        result.add(Polyline(
          points: List<LatLng>.from(currentPoints),
          strokeWidth: strokeWidth,
          color: currentColor!,
        ));
      }
      currentPoints = [];
      currentColor = null;
    }

    // Tolerate a couple of consecutive "inside" readings before treating it
    // as a genuine re-entry — same GPS-jitter fix as
    // RowLineCoverage.buildHeatmapCoverageBands(). Near a boundary, ordinary
    // GPS noise can flip point-in-polygon for a reading or two even while
    // the device is still physically outside, which was flushing (breaking)
    // the outside track every time and made it look like a scribble of
    // disconnected dashes instead of one line.
    const maxJitterStreak = 2;
    int inPlotStreak = 0;

    for (var i = 0; i < trajectory.length; i++) {
      final p = trajectory[i];
      final point = LatLng(p.lat, p.lon);

      bool isInPlot = false;
      if (plot?.polygon != null && plot!.polygon.length >= 3) {
        isInPlot = _isPointInPolygon(point, plot.polygon);
      }

      if (isInPlot) {
        inPlotStreak++;
        if (inPlotStreak > maxJitterStreak) {
          flush();
        }
        continue;
      }
      inPlotStreak = 0;

      if (i > 0) {
        final prev = trajectory[i - 1];
        if (p.timestamp.difference(prev.timestamp).inSeconds > 30) {
          flush(strokeWidth: 6.0);
        } else if (GpsJumpDetector.isJump(
            LatLng(prev.lat, prev.lon), prev.timestamp, point, p.timestamp)) {
          // An implausible GPS jump is drawn separately (see
          // _buildGpsJumpLines), never bridged into this continuous track.
          flush();
        }
      }

      final Color color;
      switch (_heatmapType) {
        case HeatmapType.gps:
          color = Colors.red;
          break;
        case HeatmapType.speed:
          color = HeatmapColorUtils.getColorForSpeed(p.speedKmph);
          break;
        case HeatmapType.spraying:
          color = HeatmapColorUtils.getColorForSpray(p.flowRateLpm);
          break;
        case HeatmapType.leftRight:
          color = Colors.red;
          break;
      }

      if (currentColor == null) {
        currentColor = color;
        currentPoints = [point];
      } else if (color == currentColor) {
        currentPoints.add(point);
      } else {
        currentPoints.add(point);
        flush();
        currentColor = color;
        currentPoints = [point];
      }
    }

    flush(strokeWidth: 6.0);
    return result;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var intersections = 0;
    for (var i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      if (p1.longitude > point.longitude != p2.longitude > point.longitude &&
          point.latitude <
              (p2.latitude - p1.latitude) *
                      (point.longitude - p1.longitude) /
                      (p2.longitude - p1.longitude) +
                  p1.latitude) {
        intersections++;
      }
    }
    return intersections % 2 != 0;
  }

  LatLng _getCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    double sumLat = 0;
    double sumLng = 0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }
}

// ── Full-screen map page ────────────────────────────────────────────────────

class _FullScreenMapPage extends ConsumerStatefulWidget {
  final Report report;
  final HeatmapType initialHeatmapType;
  final bool initialIsSatelliteView;

  const _FullScreenMapPage({
    required this.report,
    required this.initialHeatmapType,
    this.initialIsSatelliteView = true,
  });

  @override
  ConsumerState<_FullScreenMapPage> createState() => _FullScreenMapPageState();
}

class _FullScreenMapPageState extends ConsumerState<_FullScreenMapPage> {
  late HeatmapType _heatmapType;
  late bool _isSatelliteView;
  bool _showBackfillOverlay = true;

  @override
  void initState() {
    super.initState();
    _heatmapType = widget.initialHeatmapType;
    _isSatelliteView = widget.initialIsSatelliteView;
  }

  @override
  Widget build(BuildContext context) {
    // Not read directly -- watching is what makes this repaint immediately
    // after Profile > Settings > Heatmap colors is saved while this
    // full-screen view is open. See heatmap_preferences_service.dart.
    ref.watch(heatmapThresholdsProvider);
    final report = widget.report;
    final points = report.trajectory.map((p) => LatLng(p.lat, p.lon)).toList();
    final centroid = _getCentroid(points);
    // Populated (as a side effect) by buildHeatmapCoverageBands below with
    // every point plotted on a best-guess row while a genuine row-to-row
    // transition was still unconfirmed -- see buildForcedTransitionMarkers.
    final forcedTransitionPoints = <LatLng>[];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen map
          FlutterMap(
            options: MapOptions(
              initialCenter: centroid,
              initialZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    _isSatelliteView ? _kSatelliteTileUrl : _kNormalTileUrl,
                subdomains: const ['a', 'b', 'c'],
              ),
              if (report.plot != null)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: report.plot!.polygon,
                      color: const Color(0xFF00A36C).withOpacity(0.1),
                      borderStrokeWidth: 2.0,
                      borderColor: const Color(0xFF00A36C).withOpacity(0.5),
                    ),
                  ],
                ),
              if (report.plot != null &&
                  report.plot!.rowLines != null &&
                  report.plot!.rowLines!.isNotEmpty) ...[
                PolygonLayer(
                  polygons: RowLineCoverage.buildHeatmapCoverageBands(
                    rowLines: report.plot!.rowLines!,
                    insidePoints: _buildInsideTrackPoints(report.trajectory, report.plot),
                    rowSpacing: report.plot!.rowSpacing ?? 3.0,
                    heatmapType: _heatmapType,
                    polygon: report.plot!.polygon,
                    forcedTransitionPoints: forcedTransitionPoints,
                  ),
                ),
                MarkerLayer(
                  markers: RowLineCoverage.buildForcedTransitionMarkers(
                      forcedTransitionPoints),
                ),
                if (_heatmapType == HeatmapType.gps && _showBackfillOverlay)
                  PolygonLayer(
                    polygons: RowLineCoverage.buildHeatmapCoverageBands(
                      rowLines: report.plot!.rowLines!,
                      insidePoints: _buildInsideTrackPoints(report.trajectory, report.plot),
                      rowSpacing: report.plot!.rowSpacing ?? 3.0,
                      heatmapType: _heatmapType,
                      polygon: report.plot!.polygon,
                      asBackfillOverlay: true,
                    ),
                  ),
                PolylineLayer(
                  polylines: RowLineCoverage.buildRowLines(
                    rowLines: report.plot!.rowLines!,
                  ),
                ),
              ],
              PolylineLayer(
                polylines: _buildHeatmapPolylines(report.trajectory, report.plot),
              ),
              if (_heatmapType == HeatmapType.gps) ...[
                PolylineLayer(
                  polylines: _buildGpsJumpLines(report.trajectory),
                ),
                MarkerLayer(
                  markers: _buildGpsJumpMarkers(report.trajectory),
                ),
              ],
              if (points.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: points.first,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.play_circle_fill,
                          color: Colors.green, size: 30),
                    ),
                    Marker(
                      point: points.last,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.stop_circle,
                          color: Colors.red, size: 30),
                    ),
                  ],
                ),
            ],
          ),

          // Close button (top-left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.2), blurRadius: 6),
                  ],
                ),
                child: const Icon(Icons.fullscreen_exit,
                    size: 24, color: Colors.black87),
              ),
            ),
          ),

          // Satellite/Normal toggle (top-left, below close)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8 + 44,
            left: 12,
            child: _mapViewToggleButton(
              isSatellite: _isSatelliteView,
              onTap: () =>
                  setState(() => _isSatelliteView = !_isSatelliteView),
            ),
          ),

          // Legend (top-right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: _buildLegend(),
          ),

          // Heatmap toggles (bottom-center)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_heatmapType == HeatmapType.gps &&
                    widget.report.trajectory.any((p) => p.isBuffered)) ...[
                  _backfillToggleChip(),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _heatmapButton(HeatmapType.gps, 'GPS'),
                    const SizedBox(width: 8),
                    _heatmapButton(HeatmapType.speed, 'Speed'),
                    const SizedBox(width: 8),
                    _heatmapButton(HeatmapType.spraying, 'Spray'),
                    const SizedBox(width: 8),
                    _heatmapButton(HeatmapType.leftRight, 'L/R'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    List<Widget> items = [];
    switch (_heatmapType) {
      case HeatmapType.gps:
        items = [
          _legendItem('Auto', Colors.blue),
          _legendItem('Manual', Colors.grey),
          _legendItem('PTO Off', Colors.orange),
          _legendItem('Outside', Colors.red),
        ];
        break;
      case HeatmapType.speed:
        final labels = HeatmapColorUtils.speedLegendLabels();
        items = [
          _legendItem(labels[0], Colors.yellow),
          _legendItem(labels[1], Colors.green),
          _legendItem(labels[2], Colors.red),
        ];
        break;
      case HeatmapType.spraying:
        final labels = HeatmapColorUtils.sprayLegendLabels();
        items = [
          _legendItem(labels[0], Colors.white),
          _legendItem(labels[1], Colors.blue.shade800),
          _legendItem(labels[2], Colors.red.shade400),
          _legendItem(labels[3], Colors.black),
        ];
        break;
      case HeatmapType.leftRight:
        items = [
          _legendItem('Left only', Colors.orange.shade700),
          _legendItem('Right only', Colors.purple.shade700),
          _legendItem('Both', Colors.teal.shade700),
          _legendItem('Neither', Colors.white),
        ];
        break;
    }
    if (_heatmapType == HeatmapType.gps &&
        _showBackfillOverlay &&
        widget.report.trajectory.any((p) => p.isBuffered)) {
      items.add(_legendItem('Recovered (backfill)', Colors.deepPurpleAccent));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: items,
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _heatmapButton(HeatmapType type, String label) {
    final isSelected = _heatmapType == type;
    return GestureDetector(
      onTap: () => setState(() => _heatmapType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? Colors.black : Colors.white70),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _backfillToggleChip() {
    final on = _showBackfillOverlay;
    return GestureDetector(
      onTap: () => setState(() => _showBackfillOverlay = !_showBackfillOverlay),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? Colors.black : Colors.white70),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.visibility : Icons.visibility_off,
                size: 14, color: Colors.black87),
            const SizedBox(width: 6),
            Text(
              'Backfill',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: on ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<HeatmapTrackPoint> _buildInsideTrackPoints(
      List<GPSPointData> trajectory, PlotEntity? plot) {
    final result = <HeatmapTrackPoint>[];
    GPSPointData? prev;
    for (final p in trajectory) {
      final point = LatLng(p.lat, p.lon);
      bool isInPlot = true;
      if (plot?.polygon != null && plot!.polygon.length >= 3) {
        isInPlot = _isPointInPolygon(point, plot.polygon);
      }
      if (!isInPlot) continue;

      // Whether this point is an implausible GPS jump from the PREVIOUS
      // in-plot point in this list (see GpsJumpDetector) -- own list, own
      // consecutive pairs, so a stretch driven outside the plot in between
      // (a real gap, not a glitch) doesn't get mistaken for one.
      final isJump = prev != null &&
          GpsJumpDetector.isJump(
              LatLng(prev.lat, prev.lon), prev.timestamp, point, p.timestamp);
      prev = p;

      // The backend now records a GPS point on every telemetry packet while
      // spraying (see session_service.py's should_record), so trajectory is
      // as dense as what the live Monitoring screen draws from — no need to
      // scale the flow value to compensate for sparse sampling anymore.
      result.add(HeatmapTrackPoint(
        position: point,
        isInPlot: true,
        ptoOn: p.ptoState == 1,
        isAuto: p.sprayMode == 1,
        speed: p.speedKmph,
        flowRate: p.flowRateLpm,
        leftSolenoidOn: p.leftSolenoidState == 1,
        rightSolenoidOn: p.rightSolenoidState == 1,
        isBuffered: p.isBuffered,
        isJumpFromPrevious: isJump,
      ));
    }
    return result;
  }

  // Pink dashed segments marking implausible GPS jumps in the raw
  // trajectory -- shown on the GPS heatmap only, regardless of plot
  // membership. See GpsJumpDetector.
  List<Polyline> _buildGpsJumpLines(List<GPSPointData> trajectory) {
    return GpsJumpDetector.buildJumpLines(
      trajectory.map((p) => LatLng(p.lat, p.lon)).toList(),
      trajectory.map((p) => p.timestamp).toList(),
    );
  }

  List<Marker> _buildGpsJumpMarkers(List<GPSPointData> trajectory) {
    return GpsJumpDetector.buildJumpMarkers(
      trajectory.map((p) => LatLng(p.lat, p.lon)).toList(),
      trajectory.map((p) => p.timestamp).toList(),
    );
  }

  List<Polyline> _buildHeatmapPolylines(
      List<GPSPointData> trajectory, PlotEntity? plot) {
    final List<Polyline> result = [];
    if (trajectory.length < 2) return result;

    List<LatLng> currentPoints = [];
    Color? currentColor;

    void flush({double strokeWidth = 4.0}) {
      if (currentPoints.length >= 2 && currentColor != null) {
        result.add(Polyline(
          points: List<LatLng>.from(currentPoints),
          strokeWidth: strokeWidth,
          color: currentColor!,
        ));
      }
      currentPoints = [];
      currentColor = null;
    }

    // Tolerate a couple of consecutive "inside" readings before treating it
    // as a genuine re-entry — same GPS-jitter fix as
    // RowLineCoverage.buildHeatmapCoverageBands(). Near a boundary, ordinary
    // GPS noise can flip point-in-polygon for a reading or two even while
    // the device is still physically outside, which was flushing (breaking)
    // the outside track every time and made it look like a scribble of
    // disconnected dashes instead of one line.
    const maxJitterStreak = 2;
    int inPlotStreak = 0;

    for (var i = 0; i < trajectory.length; i++) {
      final p = trajectory[i];
      final point = LatLng(p.lat, p.lon);

      bool isInPlot = false;
      if (plot?.polygon != null && plot!.polygon.length >= 3) {
        isInPlot = _isPointInPolygon(point, plot.polygon);
      }

      if (isInPlot) {
        inPlotStreak++;
        if (inPlotStreak > maxJitterStreak) {
          flush();
        }
        continue;
      }
      inPlotStreak = 0;

      if (i > 0) {
        final prev = trajectory[i - 1];
        if (p.timestamp.difference(prev.timestamp).inSeconds > 30) {
          flush(strokeWidth: 6.0);
        } else if (GpsJumpDetector.isJump(
            LatLng(prev.lat, prev.lon), prev.timestamp, point, p.timestamp)) {
          // An implausible GPS jump is drawn separately (see
          // _buildGpsJumpLines), never bridged into this continuous track.
          flush();
        }
      }

      final Color color;
      switch (_heatmapType) {
        case HeatmapType.gps:
          color = Colors.red;
          break;
        case HeatmapType.speed:
          color = HeatmapColorUtils.getColorForSpeed(p.speedKmph);
          break;
        case HeatmapType.spraying:
          color = HeatmapColorUtils.getColorForSpray(p.flowRateLpm);
          break;
        case HeatmapType.leftRight:
          color = Colors.red;
          break;
      }

      if (currentColor == null) {
        currentColor = color;
        currentPoints = [point];
      } else if (color == currentColor) {
        currentPoints.add(point);
      } else {
        currentPoints.add(point);
        flush();
        currentColor = color;
        currentPoints = [point];
      }
    }

    flush(strokeWidth: 6.0);
    return result;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    var intersections = 0;
    for (var i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      if (p1.longitude > point.longitude != p2.longitude > point.longitude &&
          point.latitude <
              (p2.latitude - p1.latitude) *
                      (point.longitude - p1.longitude) /
                      (p2.longitude - p1.longitude) +
                  p1.latitude) {
        intersections++;
      }
    }
    return intersections % 2 != 0;
  }

  LatLng _getCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    double sumLat = 0;
    double sumLng = 0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLng += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }
}
