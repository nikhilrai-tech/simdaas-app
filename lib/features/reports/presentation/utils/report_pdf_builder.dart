// Branded, industry-grade one-page PDF summary of a Report, shared via the
// AppBar share button on ReportDetailsScreen (WhatsApp/Email/etc. through
// share_plus) -- built to be handed to someone outside the farm (an
// investor, a client, an agronomist), not just viewed by the device owner.
//
// Deliberately mirrors the backend's own report-verified-notification PDF
// (jobs/report_pdf.py on smart-spray-backend) -- same section grouping
// (Area/Spray/Distance & Speed/Session), same branding -- so a report looks
// the same whether it arrives by email or is shared from the app. The one
// difference: this one CAN embed the real GPS heatmap (a screenshot of the
// on-screen map, passed in as [mapImageBytes] by the caller, which has the
// live FlutterMap widget tree available) where the backend's copy can only
// draw the bare plot polygon (no Dart heatmap renderer exists server-side).
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:simdaas/core/utils/mac_utils.dart';
import '../../domain/report.dart';

const PdfColor _green = PdfColor.fromInt(0xFF00A36C);
const PdfColor _greenDark = PdfColor.fromInt(0xFF00784F);
const PdfColor _blue = PdfColor.fromInt(0xFF0057A8);
const PdfColor _teal = PdfColor.fromInt(0xFF0E8C8C);
const PdfColor _indigo = PdfColor.fromInt(0xFF3F51B5);
const PdfColor _textDark = PdfColor.fromInt(0xFF1A2026);
const PdfColor _textGrey = PdfColor.fromInt(0xFF68727C);
const PdfColor _textFaint = PdfColor.fromInt(0xFF9AA3AC);
const PdfColor _cardBg = PdfColor.fromInt(0xFFF7F9FA);
const PdfColor _rowShade = PdfColor.fromInt(0xFFF4F6F8);
const PdfColor _ruleGrey = PdfColor.fromInt(0xFFE4E8EB);

const double _acreSqm = 4046.8564224;
const _logoAssetPath = 'assets/splash/agrios_splash_logo.png';

String _fmtNum(double? value, {int digits = 2, String suffix = ''}) {
  if (value == null) return 'N/A';
  return '${value.toStringAsFixed(digits)}$suffix';
}

String _fmtDate(DateTime? dt) {
  if (dt == null) return 'N/A';
  return DateFormat('dd MMM yyyy, h:mm a').format(dt.toLocal());
}

String _fmtDuration(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 'N/A';
  final d = end.difference(start);
  if (d.isNegative) return 'N/A';
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

// A4 content width (595 - 36*2 margins) split 4 ways with a 10pt gutter
// after the first three -- fixed widths instead of pw.Expanded, which
// resolved to an infinite-height constraint here (MultiPage measures each
// top-level item with bounded width but UNBOUNDED height, and Expanded's
// default tight fit then forces its child to literally become that height).
const double _heroCardWidth = 120;

/// One of the four big numbers at the top of the report -- the things a
/// reader who only has 5 seconds should see first. [progress] (0-1) draws a
/// thin bar under the value instead of a caption when given (Area Covered
/// only, currently).
pw.Widget _heroCard(String label, String value, PdfColor color, {double? progress}) {
  return pw.Container(
    width: _heroCardWidth,
    margin: const pw.EdgeInsets.only(right: 10),
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: _ruleGrey, width: 0.75),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(height: 3, width: 22, color: color),
        pw.SizedBox(height: 8),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _textDark)),
        pw.SizedBox(height: 2),
        pw.Text(label.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 7, color: _textFaint, letterSpacing: 0.6, fontWeight: pw.FontWeight.bold)),
          if (progress != null) ...[
            pw.SizedBox(height: 6),
            pw.Stack(children: [
              pw.Container(
                height: 4,
                width: double.infinity,
                decoration: pw.BoxDecoration(color: _ruleGrey, borderRadius: pw.BorderRadius.circular(2)),
              ),
              pw.Container(
                height: 4,
                width: 108 * progress.clamp(0.0, 1.0),
                decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2)),
              ),
            ]),
          ],
        ],
      ),
    );
}

pw.Widget _pill(String text, PdfColor fg, PdfColor bg) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(10)),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: fg)),
  );
}

/// A titled card (colored left rail + heading) holding a 2-column grid of
/// label/value pairs -- the detail sections below the hero row.
pw.Widget _statCard(String title, PdfColor accent, List<(String, String)> pairs) {
  final rows = <pw.TableRow>[];
  for (var i = 0; i < pairs.length; i += 2) {
    final left = pairs[i];
    final right = i + 1 < pairs.length ? pairs[i + 1] : ('', '');
    final shaded = (i ~/ 2) % 2 == 1;
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: shaded ? _rowShade : null),
      children: [
        _cell(left.$1, isLabel: true),
        _cell(left.$2, isLabel: false),
        _cell(right.$1, isLabel: true),
        _cell(right.$2, isLabel: false),
      ],
    ));
  }
  // A Row with CrossAxisAlignment.stretch + Expanded was the original
  // shape here, but MultiPage measures each top-level item with bounded
  // width / UNBOUNDED height -- Expanded's tight fit then forces its
  // child to literally become infinite tall (same issue as the hero
  // cards, see _heroCardWidth's comment). Stack+Positioned sidesteps it:
  // Stack sizes itself to its one non-positioned child (the content
  // column, which has a normal finite height from its Table), and the
  // left accent rail just stretches to match that already-resolved size.
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: _ruleGrey, width: 0.75),
    ),
    child: pw.ClipRRect(
      horizontalRadius: 8,
      verticalRadius: 8,
      child: pw.Stack(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(14, 8, 11, 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _textDark)),
                pw.SizedBox(height: 2),
                pw.Table(
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.05),
                    1: pw.FlexColumnWidth(1.55),
                    2: pw.FlexColumnWidth(1.05),
                    3: pw.FlexColumnWidth(1.55),
                  },
                  children: rows,
                ),
              ],
            ),
          ),
          pw.Positioned(left: 0, top: 0, bottom: 0, child: pw.Container(width: 3, color: accent)),
        ],
      ),
    ),
  );
}

pw.Widget _cell(String text, {required bool isLabel}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4.5, horizontal: 5),
    child: pw.Text(
      text,
      style: isLabel
          ? const pw.TextStyle(fontSize: 8.5, color: _textGrey)
          : pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _textDark),
    ),
  );
}

/// Builds the branded PDF and returns its raw bytes. [mapImageBytes] is a
/// pre-rendered PNG of the report's map (a RepaintBoundary screenshot of
/// the live FlutterMap when there's a trajectory, or the backend's
/// plot-polygon snapshot otherwise) -- building that screenshot needs a
/// BuildContext/RenderObject, so it's the caller's job, not this builder's.
Future<Uint8List> buildReportPdf({
  required Report report,
  Uint8List? mapImageBytes,
}) async {
  final doc = pw.Document();
  final logoBytes = (await rootBundle.load(_logoAssetPath)).buffer.asUint8List();
  final logo = pw.MemoryImage(logoBytes);

  final mode = report.sessionMode == 'device' ? 'Manual' : 'Automatic';
  final sessionLabel = formatDeviceSessionLabel(report.controlUnitMac, report.deviceSessionId) ??
      (report.controlUnitMac ?? 'Unknown MAC');
  final areaCoveredAcres = report.areaCoveredSqm / _acreSqm;
  final plotAreaAcres = report.plotAreaSqm / _acreSqm;
  final startTime = report.startedAt ??
      (report.trajectory.isNotEmpty ? report.trajectory.first.timestamp : report.createdAt);
  final endTime = report.endedAt ??
      (report.trajectory.isNotEmpty ? report.trajectory.last.timestamp : report.createdAt);
  final completionFraction = (report.completionPercentage.isFinite ? report.completionPercentage : 0.0) / 100.0;

  doc.addPage(
    pw.MultiPage(
      // Page, not MultiPage, silently CLIPS content taller than one page --
      // no error, no overflow indicator, the rest just never gets painted.
      // Caught this during a visual review: the detail cards below the hero
      // row were simply missing from the rendered PDF. MultiPage flows
      // naturally onto a second page instead when a report has enough
      // content (e.g. long driver/fertilizer notes) to not fit on one.
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      footer: (context) => pw.Column(
        children: [
          pw.SizedBox(height: 14),
          pw.Divider(color: _ruleGrey, height: 1, thickness: 0.75),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Agrios · Powered by Simdaas',
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _textDark)),
                  pw.Text('Precision spray intelligence for modern agriculture',
                      style: const pw.TextStyle(fontSize: 7.5, color: _textFaint)),
                ],
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}  ·  Generated ${_fmtDate(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 7.5, color: _textFaint),
              ),
            ],
          ),
        ],
      ),
      build: (context) {
        return [
            // ── Masthead: logo + report meta, a bold accent rule beneath ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Image(logo, height: 22),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('SPRAY SESSION REPORT',
                        style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _textFaint,
                            letterSpacing: 1.0)),
                    pw.SizedBox(height: 2),
                    pw.Text('#${report.id}  ·  ${_fmtDate(report.createdAt)}',
                        style: pw.TextStyle(fontSize: 9.5, color: _textGrey)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              height: 3,
              decoration: const pw.BoxDecoration(
                gradient: pw.LinearGradient(colors: [_green, _blue]),
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Plot title + badges ──────────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(report.plot?.name ?? 'Unknown Plot',
                    style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _textDark)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Wrap(spacing: 5, children: [
                      _pill(mode.toUpperCase(),
                          mode == 'Manual' ? const PdfColor.fromInt(0xFF00695C) : _indigo,
                          mode == 'Manual' ? const PdfColor.fromInt(0xFFE0F2F1) : const PdfColor.fromInt(0xFFE8EAF6)),
                      if (report.verificationStatus == 'verified')
                        _pill('VERIFIED', _greenDark, const PdfColor.fromInt(0xFFE3F6EC)),
                    ]),
                    pw.SizedBox(height: 4),
                    pw.Text(sessionLabel,
                        style: pw.TextStyle(
                            fontSize: 7.5, color: _textFaint, font: pw.Font.courier())),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // ── Map ──────────────────────────────────────────────────────
            if (mapImageBytes != null)
              pw.Container(
                height: 165,
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _ruleGrey, width: 0.75),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 8,
                  verticalRadius: 8,
                  child: pw.Image(pw.MemoryImage(mapImageBytes), fit: pw.BoxFit.cover),
                ),
              )
            else
              pw.Container(
                width: double.infinity,
                height: 165,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: _cardBg,
                  border: pw.Border.all(color: _ruleGrey, width: 0.75),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text('Plot map unavailable',
                    style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
              ),
            pw.SizedBox(height: 16),

            // ── Hero KPI row ─────────────────────────────────────────────
            pw.Row(children: [
              _heroCard('Area Covered', _fmtNum(report.completionPercentage, digits: 1, suffix: '%'), _green,
                  progress: completionFraction),
              _heroCard('Total Sprayed', _fmtNum(report.sprayUsedLitres, digits: 1, suffix: ' L'), _blue),
              _heroCard('Total Distance', _fmtNum(report.distanceTravelledKm, suffix: ' km'), _teal),
              _heroCard('Duration', _fmtDuration(startTime, endTime), _indigo),
            ]),

            _statCard('Coverage', _green, [
              ('Area Covered', _fmtNum(report.completionPercentage, digits: 1, suffix: '%')),
              ('Covered / Total', '${_fmtNum(areaCoveredAcres)} / ${_fmtNum(plotAreaAcres)} ac'),
            ]),
            _statCard('Spray Application', _blue, [
              ('Total Sprayed', _fmtNum(report.sprayUsedLitres, digits: 1, suffix: ' L')),
              (
                'Chemical Saved',
                report.chemicalSavedNote ??
                    _fmtNum(report.chemicalSavedPercentage, digits: 1, suffix: '%'),
              ),
              ('Avg Flow Rate', _fmtNum(report.avgFlowRateLpm, suffix: ' L/min')),
              ('Avg Flow Rate', _fmtNum(report.avgFlowRateLacre, suffix: ' L/ac')),
            ]),
            _statCard('Distance & Speed', _teal, [
              ('Total Distance', _fmtNum(report.distanceTravelledKm, suffix: ' km')),
              ('PTO-On Distance', _fmtNum(report.distanceWithPtoKm, suffix: ' km')),
              ('Avg Speed', _fmtNum(report.avgSpeedKmph, digits: 1, suffix: ' km/h')),
              ('Max Speed', _fmtNum(report.maxSpeedKmph, digits: 1, suffix: ' km/h')),
            ]),
            _statCard('Session Details', _indigo, [
              ('Started', _fmtDate(startTime)),
              ('Ended', _fmtDate(endTime)),
              ('Duration', _fmtDuration(startTime, endTime)),
              ('Control Unit', report.controlUnitName ?? 'N/A'),
              ('Sprayer', report.linkedSprayerName ?? 'N/A'),
              ('Tractor', report.linkedTractorName ?? 'N/A'),
              ('Driver', report.driverName ?? 'N/A'),
              ('Fertilizers Used', report.fertilizersUsed ?? 'N/A'),
            ]),
        ];
      },
    ),
  );

  return doc.save();
}
