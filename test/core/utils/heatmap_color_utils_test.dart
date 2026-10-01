import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simdaas/core/utils/heatmap_color_utils.dart';

void main() {
  group('HeatmapColorUtils.gpsPriority', () {
    test('PTO off is always the lowest priority, regardless of mode', () {
      expect(HeatmapColorUtils.gpsPriority(ptoOn: false, isAuto: true), 0);
      expect(HeatmapColorUtils.gpsPriority(ptoOn: false, isAuto: false), 0);
    });

    test('PTO on is a higher priority than PTO off, in either mode', () {
      final autoOn = HeatmapColorUtils.gpsPriority(ptoOn: true, isAuto: true);
      final manualOn = HeatmapColorUtils.gpsPriority(ptoOn: true, isAuto: false);
      final off = HeatmapColorUtils.gpsPriority(ptoOn: false, isAuto: true);
      expect(autoOn, greaterThan(off));
      expect(manualOn, greaterThan(off));
    });

    test('Auto and Manual share the SAME priority while PTO is on -- '
        'neither one is protected against the other', () {
      // A sub-band that reached Auto must still be updatable by a later
      // Manual pass (and vice versa): only PTO-off is the state that must
      // never override an established PTO-on, per the "never downgrade"
      // rule in row_line_coverage.dart's _creditPoint (priority >=
      // gpsMaxPriority). If Auto and Manual had different priorities here,
      // a deliberate later re-pass in the other mode could never be shown.
      final autoOn = HeatmapColorUtils.gpsPriority(ptoOn: true, isAuto: true);
      final manualOn = HeatmapColorUtils.gpsPriority(ptoOn: true, isAuto: false);
      expect(autoOn, equals(manualOn));
    });
  });

  group('HeatmapColorUtils speed/spray thresholds', () {
    // speedYellowMax/speedGreenMax/sprayBlueMax/sprayRedMax are mutable
    // static fields (HeatmapPreferencesNotifier applies the signed-in
    // user's own values to them) -- reset after each test so a change here
    // never leaks into other test files sharing the same process.
    tearDown(() {
      HeatmapColorUtils.speedYellowMax = 3.0;
      HeatmapColorUtils.speedGreenMax = 7.0;
      HeatmapColorUtils.sprayBlueMax = 70.0;
      HeatmapColorUtils.sprayRedMax = 200.0;
    });

    test('getColorForSpeed uses the default bands unless changed', () {
      expect(HeatmapColorUtils.getColorForSpeed(2.0), Colors.yellow);
      expect(HeatmapColorUtils.getColorForSpeed(5.0), Colors.green);
      expect(HeatmapColorUtils.getColorForSpeed(8.0), Colors.red);
    });

    test('getColorForSpeed follows updated thresholds', () {
      HeatmapColorUtils.speedYellowMax = 10.0;
      HeatmapColorUtils.speedGreenMax = 20.0;
      expect(HeatmapColorUtils.getColorForSpeed(8.0), Colors.yellow);
      expect(HeatmapColorUtils.getColorForSpeed(15.0), Colors.green);
      expect(HeatmapColorUtils.getColorForSpeed(25.0), Colors.red);
    });

    test('getColorForSpray uses the default bands unless changed', () {
      expect(HeatmapColorUtils.getColorForSpray(0), Colors.white);
      expect(HeatmapColorUtils.getColorForSpray(300), Colors.black);
    });

    test('getColorForSpray follows updated thresholds', () {
      HeatmapColorUtils.sprayBlueMax = 50.0;
      HeatmapColorUtils.sprayRedMax = 100.0;
      // Below the new blue cap -- blue scale, not the old 70 cutoff.
      expect(HeatmapColorUtils.getColorForSpray(60), isNot(Colors.white));
      // Above the new red cap -- black, well below the old 200 cutoff.
      expect(HeatmapColorUtils.getColorForSpray(150), Colors.black);
    });
  });
}
