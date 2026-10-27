import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

/// Plot boundary + row-line export/import in KML 2.2, for opening in Google
/// Earth or any other GIS tool, and for moving a plot's geometry between
/// accounts/devices without re-drawing it by hand.
///
/// Deliberately boundary + rows only -- not the heatmap. A heatmap is
/// coverage/raster data, not simple vector geometry like a boundary or a
/// row line, so it doesn't have an obvious one-to-one KML representation
/// the way these do.

/// Builds a KML document: the plot boundary as a single `<Polygon>`
/// Placemark named "Plot Boundary", and each row line as its own
/// `<LineString>` Placemark named "Row 1", "Row 2", ... in order.
String buildPlotKml({
  required String plotName,
  required List<LatLng> polygon,
  required List<List<LatLng>> rowLines,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
    ..writeln('  <Document>')
    ..writeln('    <name>${_xmlEscape(plotName)}</name>')
    ..writeln(
        '    <description>Exported from Agrios — plot boundary and row lines</description>');

  if (polygon.isNotEmpty) {
    buffer
      ..writeln('    <Placemark>')
      ..writeln('      <name>Plot Boundary</name>')
      ..writeln('      <Polygon>')
      ..writeln('        <outerBoundaryIs>')
      ..writeln('          <LinearRing>')
      ..writeln('            <coordinates>${_ringCoordinates(polygon)}</coordinates>')
      ..writeln('          </LinearRing>')
      ..writeln('        </outerBoundaryIs>')
      ..writeln('      </Polygon>')
      ..writeln('    </Placemark>');
  }

  for (var i = 0; i < rowLines.length; i++) {
    final row = rowLines[i];
    if (row.length < 2) continue; // skip a deleted-row placeholder, if any
    buffer
      ..writeln('    <Placemark>')
      ..writeln('      <name>Row ${i + 1}</name>')
      ..writeln('      <LineString>')
      ..writeln('        <coordinates>${_lineCoordinates(row)}</coordinates>')
      ..writeln('      </LineString>')
      ..writeln('    </Placemark>');
  }

  buffer
    ..writeln('  </Document>')
    ..writeln('</kml>');
  return buffer.toString();
}

/// Parses a KML document back into a plot boundary + row lines. Takes the
/// first `<Polygon>` found as the boundary (null if none), and every
/// `<LineString>` found as a row line, in document order. Tolerant of a
/// partial file (e.g. rows only, or boundary only) -- returns whatever is
/// actually present rather than failing outright. Throws a [FormatException]
/// with a human-readable message only when the file isn't parseable XML at
/// all, or has neither a Polygon nor any LineString.
({List<LatLng>? polygon, List<List<LatLng>> rowLines}) parsePlotKml(String kmlText) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(kmlText);
  } on XmlException catch (e) {
    throw FormatException('Not a valid KML/XML file: ${e.message}');
  }

  List<LatLng>? polygon;
  final polygonEls = doc.findAllElements('Polygon');
  if (polygonEls.isNotEmpty) {
    final polygonEl = polygonEls.first;
    final coordsEls = polygonEl.findAllElements('coordinates');
    if (coordsEls.isNotEmpty) {
      final coordsEl = coordsEls.first;
      final pts = _parseCoordinates(coordsEl.innerText);
      // KML closes a ring by repeating the first point as the last -- drop
      // that trailing duplicate so this app's own polygon representation
      // (which doesn't expect a closed ring) round-trips cleanly.
      if (pts.length > 1 &&
          pts.first.latitude == pts.last.latitude &&
          pts.first.longitude == pts.last.longitude) {
        pts.removeLast();
      }
      if (pts.isNotEmpty) polygon = pts;
    }
  }

  final rowLines = <List<LatLng>>[];
  for (final lineEl in doc.findAllElements('LineString')) {
    final coordsEls = lineEl.findAllElements('coordinates');
    if (coordsEls.isEmpty) continue;
    final pts = _parseCoordinates(coordsEls.first.innerText);
    if (pts.length >= 2) rowLines.add(pts);
  }

  if (polygon == null && rowLines.isEmpty) {
    throw const FormatException(
        'No plot boundary or row lines found in this KML file.');
  }
  return (polygon: polygon, rowLines: rowLines);
}

String _ringCoordinates(List<LatLng> polygon) {
  final closed = List<LatLng>.from(polygon);
  if (closed.isNotEmpty &&
      (closed.first.latitude != closed.last.latitude ||
          closed.first.longitude != closed.last.longitude)) {
    closed.add(closed.first);
  }
  return _lineCoordinates(closed);
}

String _lineCoordinates(List<LatLng> points) =>
    points.map((p) => '${p.longitude},${p.latitude},0').join(' ');

List<LatLng> _parseCoordinates(String raw) {
  final pts = <LatLng>[];
  for (final tuple in raw.trim().split(RegExp(r'\s+'))) {
    if (tuple.isEmpty) continue;
    final parts = tuple.split(',');
    if (parts.length < 2) continue;
    final lon = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lon == null || lat == null) continue;
    pts.add(LatLng(lat, lon));
  }
  return pts;
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
