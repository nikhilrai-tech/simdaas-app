// Branded, industry-grade 4-page PDF summary of a Report, shared via the
// AppBar share button on ReportDetailsScreen (WhatsApp/Email/etc. through
// share_plus) -- built to be handed to someone outside the farm (an
// investor, a client, an agronomist), not just viewed by the device owner.
//
// Page 1 is an all-up summary; pages 2-4 are a deep dive into Spray/GPS/
// Speed, mirroring the app's own heatmap mode toggle on this same screen.
// Deliberately mirrors the backend's own report-verified-notification PDF
// (jobs/report_pdf.py on smart-spray-backend) -- same page structure,
// section grouping, branding -- so a report looks the same whether it
// arrives by email or is shared from the app. The one difference: this one
// CAN embed the REAL per-mode heatmap (a screenshot of the on-screen map in
// each mode, passed in via [mapImages] by the caller, which has the live
// FlutterMap widget tree available) where the backend's copy can only draw
// the bare plot polygon on every page (no Dart heatmap renderer exists
// server-side).
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:simdaas/core/utils/heatmap_color_utils.dart';
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

// Legend swatch colors -- must match HeatmapColorUtils.getColorForGPS/
// Speed/Spray exactly, since these pages describe the real in-app colors.
const PdfColor _gpsAuto = PdfColor.fromInt(0xFF2196F3);
const PdfColor _gpsManual = PdfColor.fromInt(0xFF9E9E9E);
const PdfColor _gpsPtoOff = PdfColor.fromInt(0xFFFF9800);
const PdfColor _gpsOutside = PdfColor.fromInt(0xFFF44336);
const PdfColor _speedSlow = PdfColor.fromInt(0xFFFFEB3B);
const PdfColor _speedNormal = PdfColor.fromInt(0xFF4CAF50);
const PdfColor _speedFast = PdfColor.fromInt(0xFFF44336);
const PdfColor _sprayNone = PdfColors.white;
const PdfColor _sprayLow = PdfColor.fromInt(0xFF1976D2);
const PdfColor _sprayHigh = PdfColor.fromInt(0xFFB71C1C);

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

/// Headline "Chemical Saved" banner -- the first thing on page 1, matching
/// the live Report Details screen's own "Saved" section now being first
/// there too.
pw.Widget _chemicalSavedBanner(Report report) {
  final hasNote = report.chemicalSavedNote != null;
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    decoration: pw.BoxDecoration(color: _blue, borderRadius: pw.BorderRadius.circular(10)),
    child: pw.Row(
      children: [
        pw.Container(
          width: 46,
          height: 46,
          decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle),
          alignment: pw.Alignment.center,
          child: pw.Text('%', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _blue)),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                hasNote ? '—' : _fmtNum(report.chemicalSavedPercentage, digits: 0, suffix: '%'),
                style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                report.chemicalSavedNote ?? 'Chemical Saved (Auto mode)',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A small plot/heatmap snapshot for page 1, so the summary page alone
/// (even if nobody flips to the Spray/GPS/Speed deep-dive pages) already
/// shows what was actually sprayed. Uses the GPS mode capture as the most
/// representative single view of plot coverage.
pw.Widget _page1MapPreview(Uint8List? mapImageBytes) {
  if (mapImageBytes == null) {
    return pw.Container(
      width: double.infinity,
      height: 150,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: _cardBg,
        border: pw.Border.all(color: _ruleGrey, width: 0.75),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text('Plot map unavailable', style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
    );
  }
  return pw.Container(
    height: 150,
    decoration: pw.BoxDecoration(
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: _ruleGrey, width: 0.75),
    ),
    child: pw.ClipRRect(
      horizontalRadius: 8,
      verticalRadius: 8,
      child: pw.Image(pw.MemoryImage(mapImageBytes), fit: pw.BoxFit.cover),
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
/// label/value pairs -- the detail sections below the hero row, and reused
/// standalone on each of the Spray/GPS/Speed pages.
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

pw.Widget _masthead(pw.MemoryImage logo, int reportId, DateTime createdAt) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
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
                      fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _textFaint, letterSpacing: 1.0)),
              pw.SizedBox(height: 2),
              pw.Text('#$reportId  ·  ${_fmtDate(createdAt)}',
                  style: pw.TextStyle(fontSize: 9.5, color: _textGrey)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        height: 3,
        decoration: const pw.BoxDecoration(gradient: pw.LinearGradient(colors: [_green, _blue])),
      ),
      pw.SizedBox(height: 16),
    ],
  );
}

/// A small colored square + label, several per row -- explains what a
/// heatmap mode's colors mean on the Spray/GPS/Speed pages.
pw.Widget _legendRow(List<(PdfColor, String)> swatches) {
  return pw.Wrap(
    spacing: 14,
    runSpacing: 6,
    children: swatches
        .map((s) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
              pw.Container(
                width: 9,
                height: 9,
                decoration: pw.BoxDecoration(color: s.$1, border: pw.Border.all(color: _ruleGrey, width: 0.5)),
              ),
              pw.SizedBox(width: 5),
              pw.Text(s.$2, style: const pw.TextStyle(fontSize: 8.5, color: _textDark)),
            ]))
        .toList(),
  );
}

/// One of the Spray/GPS/Speed deep-dive pages: masthead, a big heading, the
/// per-mode heatmap screenshot (or a bare-outline placeholder when none was
/// captured -- see ReportDetailsScreen._captureHeatmapImages), a color
/// legend, and that category's own indicator card.
List<pw.Widget> _detailPage({
  required pw.MemoryImage logo,
  required Report report,
  required String heading,
  required String plotName,
  required Uint8List? mapImageBytes,
  required List<(PdfColor, String)> legendSwatches,
  required pw.Widget statCard,
}) {
  return [
    _masthead(logo, int.tryParse(report.id) ?? 0, report.createdAt),
    pw.Text(heading, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _textDark)),
    pw.SizedBox(height: 2),
    pw.Text(plotName, style: const pw.TextStyle(fontSize: 9.5, color: _textGrey)),
    pw.SizedBox(height: 10),
    if (mapImageBytes != null)
      pw.Container(
        height: 260,
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
        height: 260,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: _cardBg,
          border: pw.Border.all(color: _ruleGrey, width: 0.75),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text('Plot map unavailable', style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
      ),
    pw.SizedBox(height: 10),
    _legendRow(legendSwatches),
    pw.SizedBox(height: 14),
    statCard,
  ];
}

/// Builds the branded 4-page PDF and returns its raw bytes.
///
/// [mapImages] holds one screenshot per heatmap mode -- GPS, spraying,
/// speed -- keyed by [HeatmapType] (leftRight is unused here). A missing or
/// null entry falls back to the "Plot map unavailable" placeholder on that
/// page. Capturing these needs a BuildContext/RenderObject per mode (the
/// caller must switch HeatmapType, let the map repaint, then screenshot its
/// RepaintBoundary -- see ReportDetailsScreen._captureHeatmapImages), so
/// it's the caller's job, not this builder's.
Future<Uint8List> buildReportPdf({
  required Report report,
  Map<HeatmapType, Uint8List?> mapImages = const {},
}) async {
  final doc = pw.Document();
  final logoBytes = (await rootBundle.load(_logoAssetPath)).buffer.asUint8List();
  final logo = pw.MemoryImage(logoBytes);

  final mode = report.sessionMode == 'device' ? 'Manual' : 'Automatic';
  final sessionLabel = formatDeviceSessionLabel(report.controlUnitMac, report.deviceSessionId) ??
      (report.controlUnitMac ?? 'Unknown MAC');
  final plotName = report.plot?.name ?? 'Unknown Plot';
  final areaCoveredAcres = report.areaCoveredSqm / _acreSqm;
  final plotAreaAcres = report.plotAreaSqm / _acreSqm;
  final startTime = report.startedAt ??
      (report.trajectory.isNotEmpty ? report.trajectory.first.timestamp : report.createdAt);
  final endTime = report.endedAt ??
      (report.trajectory.isNotEmpty ? report.trajectory.last.timestamp : report.createdAt);
  final completionFraction = (report.completionPercentage.isFinite ? report.completionPercentage : 0.0) / 100.0;

  // Built as functions, not once-off variables, and called again wherever
  // reused (page 1 AND that category's own detail page) -- pdf widgets
  // carry mutable internal layout state (Widget.box, set during the
  // document's layout pass), so placing the exact same instance twice in
  // the tree isn't safe; each placement needs its own fresh instance.
  pw.Widget buildCoverageCard() => _statCard('Coverage', _green, [
        ('Area Covered', _fmtNum(report.completionPercentage, digits: 1, suffix: '%')),
        ('Covered / Total', '${_fmtNum(areaCoveredAcres)} / ${_fmtNum(plotAreaAcres)} ac'),
      ]);
  pw.Widget buildSprayCard() => _statCard('Spray Application', _blue, [
        ('Total Sprayed', _fmtNum(report.sprayUsedLitres, digits: 1, suffix: ' L')),
        (
          'Chemical Saved',
          report.chemicalSavedNote ?? _fmtNum(report.chemicalSavedPercentage, digits: 1, suffix: '%'),
        ),
        ('Avg Flow Rate', _fmtNum(report.avgFlowRateLpm, suffix: ' L/min')),
        ('Avg Flow Rate', _fmtNum(report.avgFlowRateLacre, suffix: ' L/ac')),
      ]);
  pw.Widget buildDistanceSpeedCard() => _statCard('Distance & Speed', _teal, [
        ('Total Distance', _fmtNum(report.distanceTravelledKm, suffix: ' km')),
        ('PTO-On Distance', _fmtNum(report.distanceWithPtoKm, suffix: ' km')),
        ('Avg Speed', _fmtNum(report.avgSpeedKmph, digits: 1, suffix: ' km/h')),
        ('Max Speed', _fmtNum(report.maxSpeedKmph, digits: 1, suffix: ' km/h')),
      ]);
  pw.Widget buildSessionCard() => _statCard('Session Details', _indigo, [
        ('Started', _fmtDate(startTime)),
        ('Ended', _fmtDate(endTime)),
        ('Duration', _fmtDuration(startTime, endTime)),
        ('Control Unit', report.controlUnitName ?? 'N/A'),
        ('Sprayer', report.linkedSprayerName ?? 'N/A'),
        ('Tractor', report.linkedTractorName ?? 'N/A'),
        ('Driver', report.driverName ?? 'N/A'),
        ('Fertilizers Used', report.fertilizersUsed ?? 'N/A'),
      ]);

  final speedLabels = HeatmapColorUtils.speedLegendLabels();
  final sprayLabels = HeatmapColorUtils.sprayLegendLabels();

  doc.addPage(
    pw.MultiPage(
      // Page, not MultiPage, silently CLIPS content taller than one page --
      // no error, no overflow indicator, the rest just never gets painted.
      // Caught this during a visual review: the detail cards below the hero
      // row were simply missing from the rendered PDF. MultiPage flows
      // naturally onto a second page instead when a report has enough
      // content (e.g. long driver/fertilizer notes) to not fit on one --
      // and here, pw.NewPage() forces one explicitly between each of the
      // four sections below.
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
          // ==================================================================
          // Page 1 -- summary: everything at a glance, no map (each of the
          // next 3 pages gets its own, bigger one).
          // ==================================================================
          _masthead(logo, int.tryParse(report.id) ?? 0, report.createdAt),
          pw.SizedBox(height: 4),
          _chemicalSavedBanner(report),
          pw.SizedBox(height: 16),

          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(plotName, style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: _textDark)),
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
                      style: pw.TextStyle(fontSize: 7.5, color: _textFaint, font: pw.Font.courier())),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          pw.Row(children: [
            _heroCard('Area Covered', _fmtNum(report.completionPercentage, digits: 1, suffix: '%'), _green,
                progress: completionFraction),
            _heroCard('Total Sprayed', _fmtNum(report.sprayUsedLitres, digits: 1, suffix: ' L'), _blue),
            _heroCard('Total Distance', _fmtNum(report.distanceTravelledKm, suffix: ' km'), _teal),
            _heroCard('Duration', _fmtDuration(startTime, endTime), _indigo),
          ]),
          pw.SizedBox(height: 10),
          _page1MapPreview(mapImages[HeatmapType.gps]),

          buildCoverageCard(),
          buildSprayCard(),
          buildDistanceSpeedCard(),
          buildSessionCard(),

          // ==================================================================
          // Page 2 -- Spray
          // ==================================================================
          pw.NewPage(),
          ..._detailPage(
            logo: logo,
            report: report,
            heading: 'Spray Heatmap',
            plotName: plotName,
            mapImageBytes: mapImages[HeatmapType.spraying],
            legendSwatches: [
              (_sprayNone, sprayLabels[0]),
              (_sprayLow, sprayLabels[1]),
              (_sprayHigh, sprayLabels[2]),
              (PdfColors.black, 'Flow sensor fault'),
            ],
            statCard: buildSprayCard(),
          ),

          // ==================================================================
          // Page 3 -- GPS
          // ==================================================================
          pw.NewPage(),
          ..._detailPage(
            logo: logo,
            report: report,
            heading: 'GPS Coverage',
            plotName: plotName,
            mapImageBytes: mapImages[HeatmapType.gps],
            legendSwatches: [
              (_gpsAuto, 'Automatic, PTO on'),
              (_gpsManual, 'Manual, PTO on'),
              (_gpsPtoOff, 'PTO off'),
              (_gpsOutside, 'Outside plot'),
            ],
            statCard: buildCoverageCard(),
          ),

          // ==================================================================
          // Page 4 -- Speed
          // ==================================================================
          pw.NewPage(),
          ..._detailPage(
            logo: logo,
            report: report,
            heading: 'Speed Heatmap',
            plotName: plotName,
            mapImageBytes: mapImages[HeatmapType.speed],
            legendSwatches: [
              (_speedSlow, speedLabels[0]),
              (_speedNormal, speedLabels[1]),
              (_speedFast, speedLabels[2]),
            ],
            statCard: buildDistanceSpeedCard(),
          ),
        ];
      },
    ),
  );

  return doc.save();
}
