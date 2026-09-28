import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:simdaas/core/utils/gps_jump_detector.dart';

void main() {
  // 711 m in 17 s (~150 km/h) -- the real jump observed on staging session
  // 31 (E0:A3:5A:C5:E6:58), against a device top speed of ~8 km/h.
  final a = LatLng(20.255929, 73.925733);
  final b = LatLng(20.249535, 73.925733);
  final ta = DateTime.utc(2026, 9, 27, 19, 45, 51);

  test('a real recorded jump is flagged', () {
    final tb = ta.add(const Duration(seconds: 17));
    expect(GpsJumpDetector.isJump(a, ta, b, tb), isTrue);
  });

  test('ordinary driving speed is not flagged', () {
    // ~10 m in 5 s = 7.2 km/h, well under the threshold.
    final near = LatLng(a.latitude + 0.00009, a.longitude);
    final tb = ta.add(const Duration(seconds: 5));
    expect(GpsJumpDetector.isJump(a, ta, near, tb), isFalse);
  });

  test('the same distance over a long enough time is not a jump', () {
    // The 711 m step, but over 10 minutes instead of 17 s -- plausible.
    final tb = ta.add(const Duration(minutes: 10));
    expect(GpsJumpDetector.isJump(a, ta, b, tb), isFalse);
  });

  test('zero or negative elapsed time is never a jump', () {
    expect(GpsJumpDetector.isJump(a, ta, b, ta), isFalse);
    expect(GpsJumpDetector.isJump(a, ta, b, ta.subtract(const Duration(seconds: 1))),
        isFalse);
  });

  test('jumpIndices finds the jump at the right position in a track', () {
    final points = [a, LatLng(a.latitude + 0.00009, a.longitude), b];
    final times = [
      ta,
      ta.add(const Duration(seconds: 5)),
      ta.add(const Duration(seconds: 22)), // 17s after the previous point
    ];
    expect(GpsJumpDetector.jumpIndices(points, times), {1});
  });

  test('buildJumpLines produces one pink dashed segment per jump', () {
    final points = [a, b];
    final times = [ta, ta.add(const Duration(seconds: 17))];
    final lines = GpsJumpDetector.buildJumpLines(points, times);
    expect(lines, hasLength(1));
    expect(lines.single.points, [a, b]);
  });

  test('buildJumpLines is empty when nothing jumps', () {
    final near = LatLng(a.latitude + 0.00009, a.longitude);
    final lines = GpsJumpDetector.buildJumpLines(
        [a, near], [ta, ta.add(const Duration(seconds: 5))]);
    expect(lines, isEmpty);
  });
}
