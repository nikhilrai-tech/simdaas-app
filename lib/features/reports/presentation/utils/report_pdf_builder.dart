// Branded one-page PDF summary of a Report, shared via the AppBar share
// button on ReportDetailsScreen (WhatsApp/Email/etc. through share_plus).
//
// Deliberately mirrors the backend's own report-verified-notification PDF
// (jobs/report_pdf.py on smart-spray-backend) -- same section grouping
// (Area/Spray/Distance & Speed/Session), same header/footer branding -- so
// a report looks the same whether it arrives by email or is shared from the
// app. The one difference: this one CAN embed the real GPS heatmap (a
// screenshot of the on-screen map, passed in as [mapImageBytes] by the
// caller, which has the live FlutterMap widget tree available) where the
// backend's copy can only draw the bare plot polygon (no Dart heatmap
// renderer exists server-side).
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:simdaas/core/utils/mac_utils.dart';
import '../../domain/report.dart';

const PdfColor _brandBlue = PdfColor.fromInt(0xFF0057A8);
const PdfColor _brandDark = PdfColor.fromInt(0xFF353636);
const PdfColor _textGrey = PdfColor.fromInt(0xFF666666);
const PdfColor _rowShade = PdfColor.fromInt(0xFFF4F6F8);
const PdfColor _ruleGrey = PdfColor.fromInt(0xFFE2E5E8);

const double _acreSqm = 4046.8564224;

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

pw.Widget _statGroup(String title, List<(String, String)> pairs) {
  final rows = <pw.TableRow>[];
  for (var i = 0; i < pairs.length; i += 2) {
    final left = pairs[i];
    final right = i + 1 < pairs.length ? pairs[i + 1] : ('', '');
    final shaded = (i ~/ 2) % 2 == 1;
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(
        color: shaded ? _rowShade : null,
        border: const pw.Border(bottom: pw.BorderSide(color: _ruleGrey, width: 0.5)),
      ),
      children: [
        _cell(left.$1, isLabel: true),
        _cell(left.$2, isLabel: false),
        _cell(right.$1, isLabel: true),
        _cell(right.$2, isLabel: false),
      ],
    ));
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: pw.Text(title,
            style: pw.TextStyle(
                fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _brandBlue)),
      ),
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(1.1),
          1: pw.FlexColumnWidth(1.6),
          2: pw.FlexColumnWidth(1.1),
          3: pw.FlexColumnWidth(1.6),
        },
        children: rows,
      ),
    ],
  );
}

pw.Widget _cell(String text, {required bool isLabel}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
    child: pw.Text(
      text,
      style: isLabel
          ? const pw.TextStyle(fontSize: 9, color: _textGrey)
          : pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
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

  final mode = report.sessionMode == 'device' ? 'Manual' : 'Automatic';
  final sessionLabel = formatDeviceSessionLabel(report.controlUnitMac, report.deviceSessionId) ??
      (report.controlUnitMac ?? 'Unknown MAC');
  final areaCoveredAcres = report.areaCoveredSqm / _acreSqm;
  final plotAreaAcres = report.plotAreaSqm / _acreSqm;
  final startTime = report.startedAt ??
      (report.trajectory.isNotEmpty ? report.trajectory.first.timestamp : report.createdAt);
  final endTime = report.endedAt ??
      (report.trajectory.isNotEmpty ? report.trajectory.last.timestamp : report.createdAt);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 0, 36, 32),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header band -- full bleed, so it's drawn outside the page's
            // left/right margins via negative padding.
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(left: -36, right: -36),
              padding: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 20),
              color: _brandDark,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Agrios',
                          style: pw.TextStyle(
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                      pw.Text('Powered by Simdaas',
                          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.white)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Report #${report.id}',
                          style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                      pw.Text(_fmtDate(report.createdAt),
                          style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFFC9D6E3))),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Plot title + mode
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(report.plot?.name ?? 'Unknown Plot',
                    style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  '$mode mode'
                  '${report.verificationStatus == 'verified' ? ' · Verified' : ''}',
                  style: const pw.TextStyle(fontSize: 9.5, color: _textGrey),
                ),
              ],
            ),
            pw.SizedBox(height: 8),

            // Map image
            if (mapImageBytes != null)
              pw.SizedBox(
                width: double.infinity,
                height: 180,
                child: pw.ClipRRect(
                  horizontalRadius: 8,
                  verticalRadius: 8,
                  child: pw.Image(pw.MemoryImage(mapImageBytes), fit: pw.BoxFit.cover),
                ),
              )
            else
              pw.Container(
                width: double.infinity,
                height: 180,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _ruleGrey, width: 0.75),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text('Plot map unavailable',
                    style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
              ),

            _statGroup('Area', [
              ('Area Covered', _fmtNum(report.completionPercentage, digits: 1, suffix: '%')),
              ('Covered / Total',
                  '${_fmtNum(areaCoveredAcres)} / ${_fmtNum(plotAreaAcres)} ac'),
            ]),
            _statGroup('Spray', [
              ('Total Sprayed', _fmtNum(report.sprayUsedLitres, digits: 1, suffix: ' L')),
              (
                'Chemical Saved',
                report.chemicalSavedNote ??
                    _fmtNum(report.chemicalSavedPercentage, digits: 1, suffix: '%'),
              ),
              ('Avg Flow Rate', _fmtNum(report.avgFlowRateLpm, suffix: ' L/min')),
              ('Avg Flow Rate', _fmtNum(report.avgFlowRateLacre, suffix: ' L/ac')),
            ]),
            _statGroup('Distance & Speed', [
              ('Total Distance', _fmtNum(report.distanceTravelledKm, suffix: ' km')),
              ('PTO-On Distance', _fmtNum(report.distanceWithPtoKm, suffix: ' km')),
              ('Avg Speed', _fmtNum(report.avgSpeedKmph, digits: 1, suffix: ' km/h')),
              ('Max Speed', _fmtNum(report.maxSpeedKmph, digits: 1, suffix: ' km/h')),
            ]),
            _statGroup('Session', [
              ('Started', _fmtDate(startTime)),
              ('Ended', _fmtDate(endTime)),
              ('Duration', _fmtDuration(startTime, endTime)),
              ('Control Unit', report.controlUnitName ?? 'N/A'),
              ('Sprayer', report.linkedSprayerName ?? 'N/A'),
              ('Tractor', report.linkedTractorName ?? 'N/A'),
              ('Driver', report.driverName ?? 'N/A'),
              ('Fertilizers Used', report.fertilizersUsed ?? 'N/A'),
            ]),

            pw.Spacer(),
            pw.Divider(color: _ruleGrey, height: 1),
            pw.SizedBox(height: 6),
            pw.Text('Agrios · Powered by Simdaas  ·  $sessionLabel',
                style: const pw.TextStyle(fontSize: 8, color: _textGrey)),
          ],
        );
      },
    ),
  );

  return doc.save();
}
