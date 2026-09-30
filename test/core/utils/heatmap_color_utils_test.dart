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
}
