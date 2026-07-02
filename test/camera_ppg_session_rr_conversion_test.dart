import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ppg_kit/src/api/rr_diff.dart';

void main() {
  group('diffNewIntervals', () {
    test('empty previous window emits the whole current list', () {
      final result = diffNewIntervals(const [], const [800.0, 750.0]);
      expect(result, [800.0, 750.0]);
    });

    test('growing window emits only the new entries', () {
      final previous = [800.0, 750.0];
      final current = [800.0, 750.0, 820.0];
      final result = diffNewIntervals(previous, current);
      expect(result, [820.0]);
    });

    test('unchanged list emits nothing', () {
      final list = [800.0, 750.0, 820.0];
      final result = diffNewIntervals(list, list);
      expect(result, isEmpty);
    });

    test('sliding window drops old entries without re-emitting already-seen intervals', () {
      // Ring buffer slid forward: 800 dropped from the front, 900 added at
      // the back. 750/820 are the overlap and must not be re-emitted.
      final previous = [800.0, 750.0, 820.0];
      final current = [750.0, 820.0, 900.0];
      final result = diffNewIntervals(previous, current);
      expect(result, [900.0]);
    });

    test('completely different window (no overlap) emits the whole current list', () {
      final previous = [800.0, 750.0];
      final current = [500.0, 510.0, 520.0];
      final result = diffNewIntervals(previous, current);
      expect(result, [500.0, 510.0, 520.0]);
    });

    test('empty current window emits nothing', () {
      final result = diffNewIntervals(const [800.0, 750.0], const []);
      expect(result, isEmpty);
    });

    test('double values round to int at the call site (RrInterval.intervalMs contract)', () {
      final result = diffNewIntervals(const [], const [799.6, 750.4]);
      expect(result.map((v) => v.round()), [800, 750]);
    });
  });
}
