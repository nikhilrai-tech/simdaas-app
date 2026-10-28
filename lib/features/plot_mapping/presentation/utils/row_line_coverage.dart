import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';

import 'corridor_strip.dart';
import 'row_line_generator.dart';

/// Builds the visual layers for spray coverage on the plot map.
///
/// Two layers are produced:
///
/// 1. **Coverage bands** — filled polygons in the *gap between two consecutive
///    tree row lines*. Each corridor (space between tree row i and tree row i+1)
///    is split into ~2 m sub-bands along its length. A sub-band is colored when
///    the sprayer GPS track passes through it. Revisited sub-bands go darker.
///
/// 2. **Row lines** — plain white polylines drawn on top of the bands.
///    These never change color; they are the tree row reference lines.
///
/// Color scheme (single corridor = space between two tree rows):
///   pass count = 0   -> transparent (nothing drawn)
///   pass count = 1   -> light grey  (sprayed once)
///   pass count >= 2  -> dark grey   (sprayed more than once)
class RowLineCoverage {
  /// Approximate length of each sub-band along the row direction, metres.
  static const double subSegmentLengthMeters = 2.0;

  /// How many telemetry samples inside a sub-band counts as "one pass".
  static const double samplesPerPass = 3.0;

  /// A forced-glitch credit's own raw position is untrustworthy (that's the
  /// whole premise of glitchAnchorRow forcing, see buildHeatmapCoverageBands)
  /// -- its projection onto the anchor row's length (rows are treated as
  /// infinite lines for this) can land far from the sub-band it was last
  /// confirmed in, even when its PERPENDICULAR distance from the row passed
  /// maxGlitchForcedDistanceMultiplier's check, if the glitch happens to
  /// land close enough to a far-off part of the SAME row's line. Without
  /// this bound, _creditPoint's gap-fill bridges every sub-band in between
  /// as "covered" -- found on a real session: the sprayer jumped to a
  /// different row and back, the jump's perpendicular distance from the
  /// original row was still within tolerance, and the bridge painted nearly
  /// the entire corridor even though the sprayer was never actually there
  /// during that stretch. Caps how many sub-bands (~2m each) a single
  /// forced credit may bridge-fill -- generous enough for ordinary one-
  /// sample GPS jitter (which doesn't represent real travel), tight enough
  /// that a jump to a genuinely different part of the field can't paint a
  /// long stretch it never covered.
  static const int maxForcedCreditBridgeSubBands = 3;

  /// A corridor whose measured gap exceeds rowSpacing by more than this is
  /// treated as "a row is missing here" rather than a genuine tapering
  /// field — see the anomalous-gap check in [buildHeatmapCoverageBands].
  static const double _anomalousGapMultiplier = 4.0;

  /// Build coverage band polygons (the colored strips between tree rows).
  ///
  /// Each band lives in the corridor between rowLines[i] and rowLines[i+1].
  /// The midline of the corridor is used to project GPS points and to build
  /// the parallelogram sub-bands.
  static List<Polygon> buildCoverageBands({
    required List<List<LatLng>> rowLines,
    required List<LatLng> gpsTrack,
    required double rowSpacing,
  }) {
    if (rowLines.length < 2) return const [];
    final bands = <Polygon>[];

    for (int ri = 0; ri < rowLines.length - 1; ri++) {
      final rowA = rowLines[ri];
      final rowB = rowLines[ri + 1];
      if (rowA.length < 2 || rowB.length < 2) continue;

      // Midline of the spray corridor (between the two bounding tree rows).
      final midStart = _lerp(rowA[0], rowB[0], 0.5);
      final midEnd   = _lerp(rowA[1], rowB[1], 0.5);

      final segLen = RowLineGenerator
          .pointToSegmentInfo(midStart, midStart, midEnd)
          .segmentLengthMeters;
      if (segLen < 0.5) continue;

      final numSub =
          (segLen / subSegmentLengthMeters).ceil().clamp(1, 1000).toInt();
      final counts = List<int>.filled(numSub, 0);

      // Half-width of the corridor (midline → each tree row boundary).
      final halfWidth = rowSpacing / 2;

      // Count GPS samples that fall inside this corridor.
      for (final g in gpsTrack) {
        final info = RowLineGenerator.pointToSegmentInfo(g, midStart, midEnd);
        if (info.distance > halfWidth) continue;
        final idx = (info.t * numSub).floor().clamp(0, numSub - 1);
        counts[idx]++;
      }

      // Perpendicular delta of `halfWidth` from the midline.
      final perp = _perpendicularOffsetLatLng(midStart, midEnd, halfWidth);
      if (perp == null) continue;

      // Emit one filled parallelogram per covered sub-band.
      for (int i = 0; i < numSub; i++) {
        final count = counts[i];
        if (count <= 0) continue;
        final t0 = i / numSub;
        final t1 = (i + 1) / numSub;
        final p0 = _lerp(midStart, midEnd, t0);
        final p1 = _lerp(midStart, midEnd, t1);
        bands.add(Polygon(
          points: [
            LatLng(p0.latitude + perp.latitude, p0.longitude + perp.longitude),
            LatLng(p1.latitude + perp.latitude, p1.longitude + perp.longitude),
            LatLng(p1.latitude - perp.latitude, p1.longitude - perp.longitude),
            LatLng(p0.latitude - perp.latitude, p0.longitude - perp.longitude),
          ],
          color: _bandColor(count),
          borderColor: Colors.transparent,
          borderStrokeWidth: 0,
        ));
      }
    }

    return bands;
  }

  /// Build heatmap-colored coverage bands using telemetry metadata.
  ///
  /// Only [insidePoints] (points inside the plot boundary) are used to fill
  /// bands. Outside-plot points are handled separately as polylines.
  ///
  /// - GPS / Speed heatmaps: "no overlap" — latest state wins per sub-band.
  /// - Spray heatmap: "overlap required" — flow rates are accumulated per band.
  static List<Polygon> buildHeatmapCoverageBands({
    required List<List<LatLng>> rowLines,
    required List<HeatmapTrackPoint> insidePoints,
    required double rowSpacing,
    required HeatmapType heatmapType,
    // Reuses the exact same corridor geometry and point-crediting pass
    // below (jitter-streak handling, tapering row width, gap-fill) --
    // only the colour rule and the finalization loop differ (see the
    // dedicated branches gated on this flag in both places) -- so the
    // GPS/Speed/Spray/Left-Right bands this function already produces are
    // untouched either way, this is purely additive.
    bool asBackfillOverlay = false,
    // The plot boundary. When given, every corridor runs the full width of
    // the plot (bounded by the row LINES, not by how long each stored
    // segment happens to be), the stretch between the plot boundary and the
    // first/last row is a corridor too, and bands are cut by the boundary.
    // Without it the older behaviour is kept: corridors exist only where
    // both row segments overlap.
    List<LatLng>? polygon,
    // Out-param: when given, every point force-credited to the row it was
    // last confirmed in while a genuine row-to-row transition is still
    // pending (see "pendingForcedCount" below) has its position appended
    // here. Purely additive -- doesn't affect which band gets painted or
    // what colour it gets, only lets the caller show where the plotted line
    // was a best-guess rather than a confirmed row.
    // Deliberately excludes GPS-jump forcing (glitchAnchorRow below), which
    // already has its own marker (GpsJumpDetector.buildJumpMarkers).
    List<LatLng>? forcedTransitionPoints,
  }) {
    if (rowLines.length < 2) return const [];
    final bands = <Polygon>[];
    final plane = (polygon != null && polygon.length >= 3)
        ? MetricPlane.around(polygon)
        : null;

    // Precompute every corridor's geometry up front (instead of inline,
    // inside the loop below) so that while processing corridor `ri` we can
    // also check its immediate neighbors — needed for the "nearest row
    // wins" rule further down.
    //
    // halfWidth is derived from the ACTUAL current distance between this
    // specific pair of row lines, not the plot's single configured
    // rowSpacing. Manually dragging one row line to correct a real-world
    // field irregularity changes the true gap at that spot; if every
    // corridor kept using the same fixed rowSpacing/2 tolerance regardless,
    // a manually-widened or narrowed corridor would paint incorrectly (too
    // little, or points from an even-further row bleeding in).
    //
    // For a tapering (e.g. triangular) field, the two row lines bounding a
    // corridor are often nowhere near parallel — one end of this exact plot
    // measured 14.4m apart while the other end was only 4.7m apart. A
    // single averaged halfWidth for the whole corridor is far too wide at
    // the narrow end (rows bleeding into each other there) — so halfWidth
    // is tracked separately for the start and end and interpolated by
    // position (t) along the corridor for every point, instead of one flat
    // number.
    // A growable list rather than one fixed slot per rowLines pair — an
    // anomalous or explicitly-deleted gap (below) produces TWO independent
    // edge-band corridors out of what would normally be a single slot, and
    // nothing past this point relies on a corridor's index lining up with
    // its position in rowLines, only on iterating every corridor that
    // exists.
    final corridors = <_CorridorGeometry?>[];
    for (int ri = 0; ri < rowLines.length - 1; ri++) {
      final rowA = rowLines[ri];
      final rowB = rowLines[ri + 1];
      final aReal = rowA.length >= 2;
      final bReal = rowB.length >= 2;
      if (!aReal && !bReal) continue; // both rows missing — no corridor here

      if (!aReal || !bReal) {
        // Exactly one row is missing (an explicit deleted-row placeholder,
        // or the field boundary) — a narrow band hugging whichever row is
        // real, row_spacing wide, instead of stretching all the way to a
        // row that no longer has a defined position. The genuinely empty
        // stretch in between two such bands gets no credit at all — there's
        // no way to know real spraying happened there since the dividing
        // row's true position is gone.
        final realRow = aReal ? rowA : rowB;
        corridors.add(plane != null
            ? _ribbonCorridor(plane, polygon!, realRow, rowSpacing / 2)
            : _edgeCorridorGeometry(realRow, rowSpacing));
        continue;
      }

      // Rows drawn for a tapering (clipped-to-polygon) field don't end at
      // the same place along their own length -- their far ends are
      // staggered. Measuring the "gap" as start-to-start / end-to-end
      // point distance then picks up that stagger as if it were width (a
      // ~100m diagonal for rows that are really ~10m apart), and the band
      // built around the mid-line came out as a huge skewed block that
      // spilled past the rows and even out of the plot. Clip both rows to
      // the stretch of a shared axis where BOTH exist, so every measurement
      // below is the true perpendicular gap between the two row lines.
      final aligned = _alignRows(rowA, rowB);
      final strip = plane != null
          ? CorridorStrip.between(
              plane: plane, polygon: polygon!, rowA: rowA, rowB: rowB)
          : null;
      final double gapStart, gapEnd;
      if (aligned != null) {
        gapStart = aligned.gapStart;
        gapEnd = aligned.gapEnd;
      } else if (strip != null) {
        gapStart = strip.halfWidthStart * 2;
        gapEnd = strip.halfWidthEnd * 2;
      } else {
        continue;
      }

      // A row deleted between two others leaves no trace in THIS pair's own
      // measurement — a plot mapped before the row-delete button existed
      // (or edited some other way) can have a genuine gap this large with
      // no placeholder marking it. Real tapering fields stay within a few
      // times rowSpacing at their widest observed so far, so anything
      // beyond that is treated the same as an explicit deleted-row
      // placeholder: two independent edge bands (one per side) instead of
      // one merged corridor spanning the whole gap.
      if (gapStart > rowSpacing * _anomalousGapMultiplier ||
          gapEnd > rowSpacing * _anomalousGapMultiplier) {
        if (plane != null) {
          corridors.add(_ribbonCorridor(plane, polygon!, rowA, rowSpacing / 2));
          corridors.add(_ribbonCorridor(plane, polygon, rowB, rowSpacing / 2));
        } else {
          corridors.add(_edgeCorridorGeometry(rowA, rowSpacing));
          corridors.add(_edgeCorridorGeometry(rowB, rowSpacing));
        }
        continue;
      }

      if (strip != null) {
        corridors.add(_corridorFromStrip(strip));
        continue;
      }
      if (aligned == null) continue;

      final midStart = _lerp(aligned.a0, aligned.b0, 0.5);
      final midEnd = _lerp(aligned.a1, aligned.b1, 0.5);
      final segLen = RowLineGenerator
          .pointToSegmentInfo(midStart, midStart, midEnd)
          .segmentLengthMeters;
      if (segLen < 0.5) continue;
      final numSub =
          (segLen / subSegmentLengthMeters).ceil().clamp(1, 1000).toInt();
      final fallback = rowSpacing / 2;
      corridors.add(_CorridorGeometry(
        midStart: midStart,
        midEnd: midEnd,
        halfWidthStart: gapStart > 0.1 ? gapStart / 2 : fallback,
        halfWidthEnd: gapEnd > 0.1 ? gapEnd / 2 : fallback,
        numSub: numSub,
        rowA0: aligned.a0,
        rowA1: aligned.a1,
        rowB0: aligned.b0,
        rowB1: aligned.b1,
      ));
    }

    // The stretch between the plot boundary and the outermost rows.
    if (plane != null) {
      int? firstReal, secondReal, lastReal, beforeLast;
      for (int i = 0; i < rowLines.length; i++) {
        if (rowLines[i].length < 2) continue;
        if (firstReal == null) {
          firstReal = i;
        } else {
          secondReal ??= i;
        }
      }
      for (int i = rowLines.length - 1; i >= 0; i--) {
        if (rowLines[i].length < 2) continue;
        if (lastReal == null) {
          lastReal = i;
        } else {
          beforeLast ??= i;
        }
      }
      // Only when the outermost ENTRY is a real row: a deleted outermost row
      // leaves an unknown gap, which stays uncredited like any other.
      if (firstReal == 0 && secondReal != null) {
        corridors.add(_corridorFromStrip(CorridorStrip.outer(
            plane: plane,
            polygon: polygon!,
            row: rowLines[0],
            otherRow: rowLines[secondReal])));
      }
      if (lastReal == rowLines.length - 1 &&
          beforeLast != null &&
          lastReal != firstReal) {
        corridors.add(_corridorFromStrip(CorridorStrip.outer(
            plane: plane,
            polygon: polygon!,
            row: rowLines[lastReal!],
            otherRow: rowLines[beforeLast])));
      }
    }

    final n = corridors.length;

    // Per-corridor accumulators — allocated once up front (not per-corridor
    // inside a loop) because the point-processing pass below is now a
    // single temporal sweep shared across all corridors: only whichever
    // corridor is "currently active" gets painted for a given point, so its
    // state has to persist across the whole sweep, not just one corridor's
    // turn.
    final accumulated = <List<double>>[
      for (final geo in corridors) List<double>.filled(geo?.numSub ?? 0, 0.0)
    ];
    final accumulatedCount = <List<int>>[
      for (final geo in corridors) List<int>.filled(geo?.numSub ?? 0, 0)
    ];
    final latestColor = <List<Color?>>[
      for (final geo in corridors) List<Color?>.filled(geo?.numSub ?? 0, null)
    ];
    final subBandMaxPass = <List<int>>[
      for (final geo in corridors) List<int>.filled(geo?.numSub ?? 0, 0)
    ];
    // Lateral extent (signed, see CorridorStrip.signedOffset) actually
    // reached by points credited to each sub-band, polygon-aware (strip)
    // corridors only. Lets the painted band be bounded by where the
    // sprayer's track really got to -- plus a per-row margin, see the paint
    // loop below -- instead of always the corridor's full real gap between
    // its two bounding rows, which is what caused coverage to paint past the
    // row actually driven on a wide/irregular real gap (report #9945: a real
    // gap of 9.18m between two ordinary rows, configured row spacing 3.56m).
    // Row crediting itself (which corridor a point belongs to, the jitter/
    // glitch/streak handling above) is entirely unaffected -- this only
    // bounds how much of the credited corridor gets painted.
    final subBandMinOffset = <List<double>>[
      for (final geo in corridors)
        List<double>.filled(geo?.numSub ?? 0, double.infinity)
    ];
    final subBandMaxOffset = <List<double>>[
      for (final geo in corridors)
        List<double>.filled(geo?.numSub ?? 0, double.negativeInfinity)
    ];
    // asBackfillOverlay only: whether ANY point crediting this sub-band was
    // recovered via /backfill -- one bool per sub-band, independent of the
    // per-heatmap-type colour tracking above.
    final hasBuffered = <List<bool>>[
      for (final geo in corridors) List<bool>.filled(geo?.numSub ?? 0, false)
    ];
    // GPS heatmap only: highest gpsPriority ever recorded for each
    // sub-band, so a later lower-priority sample (e.g. Auto -> PTO off)
    // can't repaint it backwards — see HeatmapColorUtils.gpsPriority.
    final gpsMaxPriority = <List<int>>[
      for (final geo in corridors) List<int>.filled(geo?.numSub ?? 0, -1)
    ];
    final corridorPassCount = List<int>.filled(n, 0);
    // Track last index in each corridor so a re-pass fills the gap to the
    // next point instead of leaving a blank stripe — GPS samples are sparse
    // and often skip 1-2 sub-bands.
    final prevIdxInCorridor = List<int?>.filled(n, null);

    // Which corridor is "currently" credited with the sprayer's position,
    // for this whole continuous pass — not just this one point. A single
    // noisy GPS reading (a couple of metres of jitter, normal for any
    // consumer GPS — worse with tight row spacing, e.g. 2m rows -> only 1m
    // tolerance each) can momentarily read as nearer to a neighboring row
    // than the row the sprayer is actually driving down. Without this
    // "sticky" tracking, that single stray point got instantly credited to
    // the neighbor, scattering small painted patches across several
    // adjacent rows instead of one continuous row. Switching which row is
    // credited now requires several consecutive points to agree — a real
    // move to the next row, not a blip.
    //
    // Tuned against a real recorded session on a tapering field (Anjanadri):
    // at 2, sustained GPS noise right at a shared boundary between two rows
    // could still exceed the tolerance for 3+ points at a time, so the row
    // credit flip-flopped back and forth for tens of points. 7 consecutive
    // points (i.e. streak > 6) was high enough to fully settle that, while
    // still catching every genuine multi-row move in the same session (each
    // held for 30+ points before the sprayer actually moved on).
    const maxJitterStreak = 6;
    int? currentRow;
    int? pendingRow; // candidate row (or null = "outside every corridor")
    int pendingStreak = 0;
    // How many points in the current pending (not-yet-confirmed) stretch
    // have been force-credited to the old row -- see the "not confirmed
    // yet" branch below. Reset whenever pendingRow changes or the pending
    // phase ends (confirmed switch, or reaffirming the current row).
    int pendingForcedCount = 0;
    // Points in the current pending stretch, held back rather than credited
    // immediately -- their real destination (the OLD row, if the candidate
    // never pans out, or the NEW row, if it gets confirmed) isn't known
    // until the streak resolves one way or the other. Crediting them to the
    // old row right away (as an earlier version of this did) meant that even
    // once a transition to a new row was confirmed, the turn itself stayed
    // permanently attributed to the row being left -- both the coverage
    // colour AND the forced-transition marker ended up on the wrong row,
    // which is exactly what looked broken on a real report: the marker over
    // here, the colour over there. flushPending (below) applies the buffered
    // points to whichever row the streak actually resolves to.
    final pendingBuffer = <HeatmapTrackPoint>[];

    void flushPending(int? toRow) {
      if (toRow != null) {
        final geo = corridors[toRow]!;
        for (final bufPt in pendingBuffer) {
          final info = geo.project(bufPt.position);
          forcedTransitionPoints?.add(geo.midpointAt(info.t));
          _creditPoint(
            pt: bufPt,
            ri: toRow,
            geo: geo,
            heatmapType: heatmapType,
            asBackfillOverlay: asBackfillOverlay,
            isForcedGlitchCredit: true,
            corridorPassCount: corridorPassCount,
            prevIdxInCorridor: prevIdxInCorridor,
            subBandMaxPass: subBandMaxPass,
            hasBuffered: hasBuffered,
            accumulated: accumulated,
            accumulatedCount: accumulatedCount,
            gpsMaxPriority: gpsMaxPriority,
            latestColor: latestColor,
            subBandMinOffset: subBandMinOffset,
            subBandMaxOffset: subBandMaxOffset,
          );
        }
      }
      pendingBuffer.clear();
    }

    // A run of implausible GPS jumps (a glitch that lasts several points,
    // not just one bad fix) used to fall through to the "nearest row" search
    // below like any other point: if the glitchy positions happened to land
    // near a DIFFERENT row for long enough (past maxJitterStreak), that
    // neighbor row got wrongly credited with coverage it never actually got,
    // and the row the sprayer was really driving got a blank gap instead.
    // Once a jump is seen, every following point is instead force-credited
    // to the row trusted just before the jump (glitchAnchorRow) -- ignoring
    // its own untrustworthy position for row SELECTION, but still
    // projecting it onto that row and bridging normally, so the row shows
    // as sprayed through the glitch instead of gapped or wrongly attributed.
    // Recovery: the first point that's naturally back within the anchor
    // row's own tolerance ends the episode and resumes normal per-point
    // logic. If recovery never happens (the sprayer genuinely changed rows
    // during/after the glitch), forcing gives up after maxGlitchForcedPoints
    // OR once a forced point is more than maxGlitchForcedDistanceMultiplier
    // tolerances away from the anchor row (whichever comes first) and falls
    // back to normal nearest-row logic -- so a real, sustained move to a new
    // row is never permanently stuck pinned to the old one, AND a forced
    // point is never painted onto a row it's implausibly far from (found on
    // a real session: a jump combined with the sprayer's path gradually
    // diverging from the row's own mapped line meant later forced points,
    // while still under the 20-point budget, were already 100+ m from the
    // anchor row -- distance has to bound this independently of count).
    const maxGlitchForcedPoints = 20;
    // A forced point beyond this multiple of the anchor row's own tolerance
    // is no longer "probably still this row, just a glitchy fix" -- it's
    // evidence of a real, larger divergence (the sprayer genuinely moved, or
    // -- observed on a real session -- the row's own mapped line doesn't
    // track the sprayer's actual path closely enough that far from where it
    // was drawn). Forcing must never paint a row that far from what was
    // actually measured, no matter how many of the maxGlitchForcedPoints
    // budget are left -- the two bounds (distance and count) are
    // independent, either one ends the forcing.
    const maxGlitchForcedDistanceMultiplier = 2.0;
    // While forcing is active, a point that confidently matches a DIFFERENT
    // specific corridor's own (1x) tolerance -- not just "plausibly still
    // the anchor" -- for this many CONSECUTIVE points is treated as a
    // genuine, confirmed row change, ending the forcing immediately instead
    // of exhausting the full maxGlitchForcedPoints budget first. Found on a
    // real session: after a jump, every point for the next ~20 (the whole
    // budget) was comfortably within a DIFFERENT row's own tolerance the
    // entire time (never ambiguous), yet forcing kept painting them onto
    // the stale anchor row regardless, because the normal streak-confirm
    // mechanism never runs at all while a point is being force-credited.
    // Set higher than the longest glitch cluster this is tuned against
    // (an 8-point stable-but-wrong GPS fix staying correctly anchored, see
    // the dedicated test) so an ordinary glitch is never mistaken for a
    // real transition, while a sustained one still resolves well before
    // the full 20-point budget.
    const maxGlitchAltRowStreak = 10;
    int? glitchAnchorRow;
    int glitchForcedCount = 0;
    int? glitchAltRow;
    int glitchAltStreak = 0;

    for (final pt in insidePoints) {
      if (pt.isJumpFromPrevious && currentRow != null && glitchAnchorRow == null) {
        glitchAnchorRow = currentRow;
        glitchForcedCount = 0;
        glitchAltRow = null;
        glitchAltStreak = 0;
      }

      if (glitchAnchorRow != null) {
        final anchorGeo = corridors[glitchAnchorRow];
        final anchorInfo = anchorGeo?.project(pt.position);
        final tolerance = anchorGeo != null && anchorInfo != null
            ? anchorGeo.halfWidthAt(anchorInfo.t)
            : null;
        final backToAnchor =
            tolerance != null && anchorInfo!.distance <= tolerance;
        final plausiblyStillThisRow = tolerance != null &&
            anchorInfo!.distance <=
                tolerance * maxGlitchForcedDistanceMultiplier;

        int? altMatch;
        for (int ri = 0; ri < n; ri++) {
          if (ri == glitchAnchorRow) continue;
          final geo = corridors[ri];
          if (geo == null) continue;
          final info = geo.project(pt.position);
          if (info.distance <= geo.halfWidthAt(info.t)) {
            altMatch = ri;
            break;
          }
        }
        if (altMatch != null && altMatch == glitchAltRow) {
          glitchAltStreak++;
        } else {
          glitchAltRow = altMatch;
          glitchAltStreak = altMatch != null ? 1 : 0;
        }

        if (glitchAltStreak > maxGlitchAltRowStreak) {
          // Several consecutive points confidently match the SAME different
          // row the entire time, even while still "plausibly" the anchor by
          // distance alone -- confirm the new row now instead of waiting
          // out the rest of the forcing budget. Falls through to the normal
          // crediting below (not `continue`) so this point itself is
          // credited the same way any other confirmed-row point is.
          flushPending(glitchAltRow);
          if (currentRow != null) prevIdxInCorridor[currentRow] = null;
          currentRow = glitchAltRow;
          glitchAnchorRow = null;
          pendingRow = null;
          pendingStreak = 0;
          pendingForcedCount = 0;
          glitchAltRow = null;
          glitchAltStreak = 0;
        } else if (!backToAnchor &&
            plausiblyStillThisRow &&
            glitchForcedCount < maxGlitchForcedPoints) {
          glitchForcedCount++;
          // A GPS jump interrupting an in-progress row-transition attempt
          // abandons that attempt -- fall the buffered points back to the
          // row trusted before the jump (== currentRow here already).
          flushPending(currentRow);
          currentRow = glitchAnchorRow;
          pendingRow = null;
          pendingStreak = 0;
          final ri = glitchAnchorRow;
          final geo = corridors[ri]!;
          _creditPoint(
            pt: pt,
            ri: ri,
            geo: geo,
            heatmapType: heatmapType,
            asBackfillOverlay: asBackfillOverlay,
            isForcedGlitchCredit: true,
            corridorPassCount: corridorPassCount,
            prevIdxInCorridor: prevIdxInCorridor,
            subBandMaxPass: subBandMaxPass,
            hasBuffered: hasBuffered,
            accumulated: accumulated,
            accumulatedCount: accumulatedCount,
            gpsMaxPriority: gpsMaxPriority,
            latestColor: latestColor,
            subBandMinOffset: subBandMinOffset,
            subBandMaxOffset: subBandMaxOffset,
          );
          continue;
        } else {
          // Naturally back near the trusted row, forced for long enough
          // without recovering, or too far from the anchor row to plausibly
          // still be it -- stop forcing WITHOUT crediting this point to
          // anything, and let it run through the normal logic below (it may
          // re-confirm the same row, match a genuinely different one, or --
          // if it matches nothing -- stay uncredited rather than risk
          // painting a row it was never actually close to).
          glitchAnchorRow = null;
        }
      }

      // Home-row advantage: if this point still satisfies the CURRENT row's
      // own tolerance, stay there — don't even look at other corridors.
      // Without this, a point near the shared boundary between two
      // corridors (common with wide row spacing, e.g. ~4.7m halfWidth) can
      // be only fractionally closer to the neighbor's midline than to its
      // own row's — comfortably inside its own row's tolerance either way —
      // and pure "nearest wins" would start treating that as a candidate
      // switch purely from that tiny, meaningless difference, letting
      // ordinary jitter right at a boundary flip-flop the credited row back
      // and forth. Only once the point genuinely falls outside its current
      // row's own tolerance do we look for the best match among every
      // corridor (still subject to the streak-confirmation below).
      int? nearestRow;
      double? nearestDist;
      if (currentRow != null) {
        final curGeo = corridors[currentRow];
        if (curGeo != null) {
          final curInfo = curGeo.project(pt.position);
          if (curInfo.distance <= curGeo.halfWidthAt(curInfo.t)) {
            nearestRow = currentRow;
            nearestDist = curInfo.distance;
          }
        }
      }
      if (nearestRow == null) {
        for (int ri = 0; ri < n; ri++) {
          final geo = corridors[ri];
          if (geo == null) continue;
          final info = geo.project(pt.position);
          if (info.distance > geo.halfWidthAt(info.t)) continue;
          if (nearestDist == null || info.distance < nearestDist) {
            nearestDist = info.distance;
            nearestRow = ri;
          }
        }
      }

      if (currentRow == null && nearestRow != null) {
        // Nothing established yet for this pass — accept the first match
        // immediately, no streak needed.
        currentRow = nearestRow;
        pendingForcedCount = 0;
      } else if (nearestRow != currentRow) {
        if (currentRow == null && nearestRow == null) {
          continue; // still nothing to paint
        }
        if (pendingRow == nearestRow) {
          pendingStreak++;
        } else {
          // A different candidate than whatever was building up before --
          // that earlier attempt never got confirmed, so its buffered points
          // fall back to the row we were last sure of.
          flushPending(currentRow);
          pendingRow = nearestRow;
          pendingStreak = 1;
          pendingForcedCount = 0;
        }
        if (pendingStreak > maxJitterStreak) {
          // Confirmed: the sprayer genuinely moved to a different row (or
          // left every row). The buffered points spent while this was still
          // unconfirmed turned out to really belong to the row just
          // confirmed, not the one they were provisionally held against --
          // apply them there now, so both the coverage colour and the
          // forced-transition marker end up on the row the sprayer actually
          // reached, not the one it was leaving. Reset the old row's gap-fill
          // anchor so a much later real re-pass over it starts a fresh pass
          // count instead of bridging today's visit to a visit from ages ago.
          flushPending(nearestRow);
          if (currentRow != null) prevIdxInCorridor[currentRow] = null;
          currentRow = nearestRow;
          pendingRow = null;
          pendingStreak = 0;
          pendingForcedCount = 0;
        } else {
          // Not confirmed yet -- hold this point rather than crediting (or
          // dropping) it outright. A genuine row-to-row transition (driving
          // from the end of one row to the start of the next) spends several
          // points outside every corridor's tolerance while turning; without
          // this, that whole stretch showed as an uncredited gap even though
          // the sprayer never actually stopped spraying. Which row it really
          // belongs to isn't known yet -- see flushPending, called once the
          // streak resolves one way or the other. Bounded the same way a
          // GPS-glitch episode is (maxGlitchForcedPoints, see glitchAnchorRow
          // above) so a point that never settles into any row for a long
          // time doesn't keep piling up indefinitely -- the normal
          // streak-confirm above still runs every point, so a genuinely new
          // row gets picked up (and forcing stops) the moment it's
          // confirmed, same as always.
          if (currentRow != null && pendingForcedCount < maxGlitchForcedPoints) {
            pendingForcedCount++;
            pendingBuffer.add(pt);
          }
          continue;
        }
      } else {
        // Reaffirms the current row — cancel any pending switch, falling the
        // buffered points back to it (the candidate never panned out).
        flushPending(currentRow);
        pendingRow = null;
        pendingStreak = 0;
        pendingForcedCount = 0;
      }

      if (currentRow == null) continue; // confirmed outside every corridor

      final ri = currentRow;
      final geo = corridors[ri]!;
      _creditPoint(
        pt: pt,
        ri: ri,
        geo: geo,
        heatmapType: heatmapType,
        asBackfillOverlay: asBackfillOverlay,
        isForcedGlitchCredit: false,
        corridorPassCount: corridorPassCount,
        prevIdxInCorridor: prevIdxInCorridor,
        subBandMaxPass: subBandMaxPass,
        hasBuffered: hasBuffered,
        accumulated: accumulated,
        accumulatedCount: accumulatedCount,
        gpsMaxPriority: gpsMaxPriority,
        latestColor: latestColor,
        subBandMinOffset: subBandMinOffset,
        subBandMaxOffset: subBandMaxOffset,
      );
    }
    // The track ended mid-transition (pending, never confirmed) -- nothing
    // else will ever arrive to resolve it, so fall the buffered points back
    // to the row they were last sure of, same as any other unconfirmed
    // candidate.
    flushPending(currentRow);

    for (int ri = 0; ri < n; ri++) {
      final geo = corridors[ri];
      if (geo == null) continue;
      final midStart = geo.midStart;
      final midEnd = geo.midEnd;
      final numSub = geo.numSub;

      for (int i = 0; i < numSub; i++) {
        final passCount = subBandMaxPass[ri][i];
        if (passCount == 0) continue; // sub-band never visited

        Color bandColor;
        int alpha;

        if (asBackfillOverlay) {
          if (!hasBuffered[ri][i]) continue;
          bandColor = Colors.deepPurpleAccent;
          alpha = 160;
        } else if (heatmapType == HeatmapType.spraying) {
          if (accumulated[ri][i] <= 0.0 || accumulatedCount[ri][i] == 0) {
            continue;
          }
          // Divide raw accumulated flow by the expected samples-per-sub-band at
          // normal speed. This is equivalent to avgPerSample × passCount for a
          // moving device (each pass contributes ~samplesPerPass samples), but
          // also correctly darkens a sub-band when the device is stationary:
          // many samples at the same spot accumulate a large sum which pushes
          // the colour from light-blue all the way to black.
          final totalFlow = accumulated[ri][i] / samplesPerPass;
          bandColor = HeatmapColorUtils.getColorForSpray(totalFlow);
          alpha = 200;
        } else {
          // GPS heatmap: highest-priority state ever recorded (never
          // downgrades). Speed/Left-Right: most recent state (updated on
          // every re-pass). Both are just whatever's currently in
          // latestColor[ri][i] at this point.
          final c = latestColor[ri][i];
          if (c == null) continue;
          bandColor = c;
          alpha = 200;
        }

        final t0 = i / numSub;
        final t1 = (i + 1) / numSub;
        final List<LatLng> corners;
        if (geo.strip != null) {
          // Bound the painted width to where the sprayer's track actually
          // reached in this sub-band (subBandMinOffset/MaxOffset), plus a
          // per-row margin on each side -- not the corridor's full real gap
          // between its two bounding rows. Without this, a corridor whose
          // real gap is much wider than the configured row spacing (two
          // ordinary rows that happen to be unusually far apart, or a
          // deleted-row remnant) painted its ENTIRE width for any stretch
          // the sprayer passed through, even when the track stayed close to
          // one row the whole time -- see report #9945 (gap 9.18m vs
          // configured 3.56m spacing; paint reached ~4.6m from the row the
          // sprayer never left). rowSpacing/2 as the margin matches the
          // half-width already used elsewhere for a single real row with no
          // neighbour to measure against (_edgeCorridorGeometry/_ribbonCorridor),
          // so a normal corridor (real gap ≈ configured spacing, swept down
          // the middle) still paints its full width exactly as before --
          // this only narrows painting where the real gap is wider than
          // what was actually driven.
          final halfW = geo.halfWidthAt((t0 + t1) / 2);
          final minOff = subBandMinOffset[ri][i];
          final maxOff = subBandMaxOffset[ri][i];
          final margin = rowSpacing / 2;
          var loOff = minOff.isFinite ? minOff - margin : -halfW;
          var hiOff = maxOff.isFinite ? maxOff + margin : halfW;
          loOff = loOff.clamp(-halfW, halfW);
          hiOff = hiOff.clamp(-halfW, halfW);
          if (hiOff < loOff) {
            final tmp = loOff;
            loOff = hiOff;
            hiOff = tmp;
          }
          final c = geo.strip!.boundedBandCorners(t0, t1, loOff, hiOff);
          if (c == null) continue; // slice lies outside the plot
          corners = c;
        } else if (geo.hasRows) {
          // Bounded by the two actual row lines -- the band follows the
          // corridor's real (tapering) outline instead of a rectangle
          // around the mid-line that only matches it where rows happen to
          // be parallel.
          corners = [
            _lerp(geo.rowA0!, geo.rowA1!, t0),
            _lerp(geo.rowA0!, geo.rowA1!, t1),
            _lerp(geo.rowB0!, geo.rowB1!, t1),
            _lerp(geo.rowB0!, geo.rowB1!, t0),
          ];
        } else {
          // Single-row edge band (flat width, no second row to follow).
          final p0 = _lerp(midStart, midEnd, t0);
          final p1 = _lerp(midStart, midEnd, t1);
          final perp = _perpendicularOffsetLatLng(
              midStart, midEnd, geo.halfWidthAt((t0 + t1) / 2));
          if (perp == null) continue;
          corners = [
            LatLng(p0.latitude + perp.latitude, p0.longitude + perp.longitude),
            LatLng(p1.latitude + perp.latitude, p1.longitude + perp.longitude),
            LatLng(p1.latitude - perp.latitude, p1.longitude - perp.longitude),
            LatLng(p0.latitude - perp.latitude, p0.longitude - perp.longitude),
          ];
        }
        bands.add(Polygon(
          points: corners,
          color: bandColor.withAlpha(alpha),
          borderColor: Colors.transparent,
          borderStrokeWidth: 0,
        ));
      }
    }

    return bands;
  }

  /// Small fixed-pixel-size markers at every point collected via
  /// [buildHeatmapCoverageBands]'s `forcedTransitionPoints` out-param --
  /// i.e. every point plotted onto a row only because a genuine row-to-row
  /// transition (turning at the end of a row) hadn't been confirmed yet, so
  /// the point was credited to the row the sprayer was last confirmed in
  /// instead of wherever it actually was. Hollow (not filled) and a
  /// different colour from [GpsJumpDetector.buildJumpMarkers]'s solid dots,
  /// so the two "this point is uncertain" reasons (an implausible GPS jump
  /// vs. an ordinary in-progress row turn) stay visually distinguishable.
  /// Drawn as Markers rather than adjusting the band colour itself so the
  /// existing coverage colour scheme is completely untouched.
  static List<Marker> buildForcedTransitionMarkers(List<LatLng> points) {
    if (points.isEmpty) return const [];
    const size = 10.0;
    return [
      for (final p in points)
        Marker(
          point: p,
          width: size,
          height: size,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.amber.shade800, width: 2.0),
            ),
          ),
        ),
    ];
  }

  /// Credit one point to corridor [ri], bridging from the last credited
  /// sub-band there so GPS sampling gaps (or a glitch run force-credited
  /// here by the caller, see [buildHeatmapCoverageBands]) don't leave a
  /// blank stripe. [isForcedGlitchCredit] is true only when the caller has
  /// already decided [ri] is the trustworthy pre-glitch row for a jump-
  /// flagged point that would otherwise have gone through normal nearest-
  /// row selection -- in that case the bridge always runs, since filling
  /// through the glitch (on the right row) is the entire point of forcing
  /// it here. A jump-flagged point that reaches this method WITHOUT being
  /// forced (no trusted row existed yet to anchor to) still suppresses its
  /// own bridge -- there's nothing to justify filling across it.
  static void _creditPoint({
    required HeatmapTrackPoint pt,
    required int ri,
    required _CorridorGeometry geo,
    required HeatmapType heatmapType,
    required bool asBackfillOverlay,
    required bool isForcedGlitchCredit,
    required List<int> corridorPassCount,
    required List<int?> prevIdxInCorridor,
    required List<List<int>> subBandMaxPass,
    required List<List<bool>> hasBuffered,
    required List<List<double>> accumulated,
    required List<List<int>> accumulatedCount,
    required List<List<int>> gpsMaxPriority,
    required List<List<Color?>> latestColor,
    required List<List<double>> subBandMinOffset,
    required List<List<double>> subBandMaxOffset,
  }) {
    final info = geo.project(pt.position);
    final signedOffset = geo.strip?.signedOffset(pt.position);

    if (prevIdxInCorridor[ri] == null) {
      corridorPassCount[ri]++; // entered (or re-entered) the corridor
    }

    final idx = (info.t * geo.numSub).floor().clamp(0, geo.numSub - 1);
    final color = heatmapType == HeatmapType.spraying
        ? null
        : HeatmapColorUtils.getColorForInsidePoint(pt, heatmapType);

    // A long gap (see HeatmapTrackPoint.isLongGapFromPrevious) suppresses
    // the bridge unconditionally, even under forced crediting -- unlike a
    // jump (bad-but-correctable data, worth bridging through once anchored
    // to a trusted row), a gap means there's genuinely no data for that
    // stretch, so nothing justifies painting it either way.
    //
    // A forced-glitch credit is still capped separately (see
    // maxForcedCreditBridgeSubBands): its own position is untrustworthy, so
    // a bridge that would span further than ordinary GPS jitter could
    // explain is suppressed too, even though forced credits are otherwise
    // allowed to bridge.
    final rawPrev = prevIdxInCorridor[ri];
    final forcedBridgeTooFar = isForcedGlitchCredit &&
        rawPrev != null &&
        (idx - rawPrev).abs() > maxForcedCreditBridgeSubBands;
    final prev = ((!isForcedGlitchCredit && pt.isJumpFromPrevious) ||
            pt.isLongGapFromPrevious ||
            forcedBridgeTooFar)
        ? null
        : rawPrev;
    final lo = prev != null ? math.min(prev, idx) : idx;
    final hi = prev != null ? math.max(prev, idx) : idx;

    for (int s = lo; s <= hi; s++) {
      subBandMaxPass[ri][s] =
          math.max(subBandMaxPass[ri][s], corridorPassCount[ri]);
      if (signedOffset != null) {
        if (signedOffset < subBandMinOffset[ri][s]) {
          subBandMinOffset[ri][s] = signedOffset;
        }
        if (signedOffset > subBandMaxOffset[ri][s]) {
          subBandMaxOffset[ri][s] = signedOffset;
        }
      }
      if (asBackfillOverlay) {
        if (pt.isBuffered) hasBuffered[ri][s] = true;
        continue;
      }
      if (heatmapType == HeatmapType.spraying) {
        accumulated[ri][s] += pt.flowRate ?? 0.0;
        accumulatedCount[ri][s]++;
      } else if (heatmapType == HeatmapType.gps) {
        // Never downgrade: a sub-band that reached Auto must stay Auto
        // even if a later sample here is PTO-off/Manual (GPS jitter, a
        // momentary pause) — only an equal-or-higher priority sample
        // updates the shown color.
        final priority =
            HeatmapColorUtils.gpsPriority(ptoOn: pt.ptoOn, isAuto: pt.isAuto);
        if (priority >= gpsMaxPriority[ri][s]) {
          gpsMaxPriority[ri][s] = priority;
          latestColor[ri][s] = color;
        }
      } else {
        // Latest-write wins for Speed/Left-Right heatmaps — a re-pass
        // over the same sub-band reflects the sprayer's current state
        // there. Only the Spray heatmap accumulates on re-pass, and
        // only the GPS heatmap has a no-downgrade priority rule.
        latestColor[ri][s] = color;
      }
    }

    prevIdxInCorridor[ri] = idx;
  }

  /// Build the planned row line polylines (tree rows).
  static List<Polyline> buildRowLines({
    required List<List<LatLng>> rowLines,
    double strokeWidth = 2.0,
  }) {
    return rowLines
        .where((seg) => seg.length >= 2)
        .map((seg) => Polyline(
              points: seg,
              color: Colors.white.withAlpha(200),
              strokeWidth: strokeWidth,
            ))
        .toList();
  }

  // ── helpers ────────────────────────────────────────────────────────────

  static LatLng? _perpendicularOffsetLatLng(
      LatLng start, LatLng end, double halfWidthMeters) {
    const mPerDeg = 111320.0;
    final cosLat = math.cos(start.latitude * math.pi / 180.0);
    if (cosLat.abs() < 1e-9) return null;
    final dx = (end.longitude - start.longitude) * cosLat * mPerDeg;
    final dy = (end.latitude - start.latitude) * mPerDeg;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return null;
    final px = -dy / len * halfWidthMeters;
    final py =  dx / len * halfWidthMeters;
    return LatLng(py / mPerDeg, px / (cosLat * mPerDeg));
  }

  static _CorridorGeometry? _corridorFromStrip(CorridorStrip? strip) {
    if (strip == null) return null;
    final numSub = (strip.length / subSegmentLengthMeters)
        .ceil()
        .clamp(1, 1000)
        .toInt();
    return _CorridorGeometry(
      midStart: strip.midStart,
      midEnd: strip.midEnd,
      halfWidthStart: strip.halfWidthStart,
      halfWidthEnd: strip.halfWidthEnd,
      numSub: numSub,
      strip: strip,
    );
  }

  /// Flat-width corridor centred on a single row, running the full length
  /// of the plot (the polygon-aware counterpart of [_edgeCorridorGeometry]).
  static _CorridorGeometry? _ribbonCorridor(MetricPlane plane,
      List<LatLng> polygon, List<LatLng> row, double halfWidth) {
    return _corridorFromStrip(CorridorStrip.ribbon(
        plane: plane,
        polygon: polygon,
        row: row,
        halfWidthMeters: halfWidth));
  }

  /// A narrow corridor hugging a single real row line's own position,
  /// row_spacing wide — used where the row on the other side is missing
  /// (deleted, or an anomalously large unmarked gap) so there's no second
  /// line to measure a real gap against. Flat width, not tapered: there's
  /// nothing on the far side to interpolate a taper toward.
  static _CorridorGeometry? _edgeCorridorGeometry(
      List<LatLng> row, double rowSpacing) {
    if (row.length < 2) return null;
    final segLen = RowLineGenerator
        .pointToSegmentInfo(row[0], row[0], row[1])
        .segmentLengthMeters;
    if (segLen < 0.5) return null;
    final numSub =
        (segLen / subSegmentLengthMeters).ceil().clamp(1, 1000).toInt();
    final halfWidth = rowSpacing / 2;
    return _CorridorGeometry(
      midStart: row[0],
      midEnd: row[1],
      halfWidthStart: halfWidth,
      halfWidthEnd: halfWidth,
      numSub: numSub,
    );
  }

  /// Clips two row lines to the stretch of a shared axis (the average of
  /// their own directions) where BOTH exist, and measures the gap between
  /// them perpendicular to that axis at each end. Null if the rows don't
  /// overlap along the axis at all.
  static _AlignedRows? _alignRows(List<LatLng> rowA, List<LatLng> rowB) {
    const mPerDeg = 111320.0;
    final lat0 = rowA[0].latitude;
    final lon0 = rowA[0].longitude;
    final cosLat = math.cos(lat0 * math.pi / 180.0);
    if (cosLat.abs() < 1e-9) return null;
    math.Point<double> toXY(LatLng p) => math.Point(
        (p.longitude - lon0) * cosLat * mPerDeg, (p.latitude - lat0) * mPerDeg);
    LatLng toLL(math.Point<double> p) =>
        LatLng(lat0 + p.y / mPerDeg, lon0 + p.x / (cosLat * mPerDeg));

    var a0 = toXY(rowA[0]), a1 = toXY(rowA[1]);
    var b0 = toXY(rowB[0]), b1 = toXY(rowB[1]);
    math.Point<double> unit(math.Point<double> v) {
      final l = math.sqrt(v.x * v.x + v.y * v.y);
      return l < 1e-9
          ? const math.Point(0.0, 0.0)
          : math.Point(v.x / l, v.y / l);
    }

    final da = unit(a1 - a0);
    var db = unit(b1 - b0);
    // Rows drawn in opposite directions: flip B so both run the same way.
    if (da.x * db.x + da.y * db.y < 0) {
      final t = b0;
      b0 = b1;
      b1 = t;
      db = unit(b1 - b0);
    }
    final u = unit(math.Point(da.x + db.x, da.y + db.y));
    if (u.x == 0 && u.y == 0) return null;
    double s(math.Point<double> p) => p.x * u.x + p.y * u.y;
    if (s(a1) < s(a0)) {
      final t = a0;
      a0 = a1;
      a1 = t;
    }
    if (s(b1) < s(b0)) {
      final t = b0;
      b0 = b1;
      b1 = t;
    }
    final lo = math.max(s(a0), s(b0));
    final hi = math.min(s(a1), s(b1));
    if (hi - lo < 0.5) return null;
    math.Point<double> at(
        math.Point<double> p0, math.Point<double> p1, double sv) {
      final span = s(p1) - s(p0);
      if (span.abs() < 1e-9) return p0;
      final f = (sv - s(p0)) / span;
      return math.Point(p0.x + (p1.x - p0.x) * f, p0.y + (p1.y - p0.y) * f);
    }

    final ca0 = at(a0, a1, lo), ca1 = at(a0, a1, hi);
    final cb0 = at(b0, b1, lo), cb1 = at(b0, b1, hi);
    double dist(math.Point<double> p, math.Point<double> q) =>
        math.sqrt((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y));
    return _AlignedRows(
      a0: toLL(ca0),
      a1: toLL(ca1),
      b0: toLL(cb0),
      b1: toLL(cb1),
      gapStart: dist(ca0, cb0),
      gapEnd: dist(ca1, cb1),
    );
  }

  static LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude  + (b.latitude  - a.latitude)  * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  static Color _bandColor(int rawCount) {
    final passes = (rawCount / samplesPerPass).ceil();
    if (passes <= 1) return Colors.grey.shade400.withAlpha(160);  // single pass
    return Colors.grey.shade800.withAlpha(220);                    // double / more
  }
}

/// Precomputed per-corridor geometry for [RowLineCoverage.buildHeatmapCoverageBands].
///
/// halfWidthStart/halfWidthEnd are derived from the actual current distance
/// between this corridor's two row lines at each end (not the plot's single
/// configured rowSpacing), so a manually-shifted row line still gets a
/// tolerance matching its real current gap to its neighbor. They're tracked
/// separately (rather than one averaged halfWidth) because a tapering field
/// can have a corridor that's much wider at one end than the other — using
/// [halfWidthAt] to interpolate by position keeps the tolerance accurate
/// along the whole length instead of too generous at the narrow end.
class _CorridorGeometry {
  final LatLng midStart;
  final LatLng midEnd;
  final double halfWidthStart;
  final double halfWidthEnd;
  final int numSub;
  // The two (axially clipped) row segments this corridor is bounded by, so
  // its bands can follow the real row lines. Null for single-row edge
  // bands, which have no second row to follow.
  final LatLng? rowA0;
  final LatLng? rowA1;
  final LatLng? rowB0;
  final LatLng? rowB1;
  // Polygon-aware corridor (see CorridorStrip). When set, crediting and band
  // drawing use it instead of the mid-line segment / row endpoints above.
  final CorridorStrip? strip;

  const _CorridorGeometry({
    required this.midStart,
    required this.midEnd,
    required this.halfWidthStart,
    required this.halfWidthEnd,
    required this.numSub,
    this.rowA0,
    this.rowA1,
    this.rowB0,
    this.rowB1,
    this.strip,
  });

  /// Distance from the corridor's centre line and position along it (t in
  /// 0..1) of [p].
  SegmentProjection project(LatLng p) {
    final st = strip;
    if (st != null) {
      final r = st.project(p);
      return SegmentProjection(
          distance: r.distance, t: r.t, segmentLengthMeters: st.length);
    }
    return RowLineGenerator.pointToSegmentInfo(p, midStart, midEnd);
  }

  /// Midline point at axial parameter [t] -- i.e. where a point projecting
  /// to this t is actually credited/painted, as opposed to its own (possibly
  /// well off-corridor) raw position. Used so a "forced credit" marker sits
  /// on the row it was credited to, not wherever the sprayer physically was.
  LatLng midpointAt(double t) {
    final st = strip;
    if (st != null) return st.midpointAt(t);
    return RowLineCoverage._lerp(midStart, midEnd, t.clamp(0.0, 1.0));
  }

  bool get hasRows =>
      rowA0 != null && rowA1 != null && rowB0 != null && rowB1 != null;

  /// Corridor half-width at position [t] (0 = start, 1 = end) along its length.
  double halfWidthAt(double t) =>
      halfWidthStart + (halfWidthEnd - halfWidthStart) * t.clamp(0.0, 1.0);
}

class _AlignedRows {
  final LatLng a0, a1, b0, b1;
  final double gapStart, gapEnd;
  const _AlignedRows({
    required this.a0,
    required this.a1,
    required this.b0,
    required this.b1,
    required this.gapStart,
    required this.gapEnd,
  });
}
