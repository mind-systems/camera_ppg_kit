import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ppg_kit/camera_ppg_kit.dart';

void main() {
  group('RrInterval', () {
    test('constructs with required fields and defaults isArtifact to false', () {
      final timestamp = DateTime(2026, 6, 21, 12, 0, 0);
      final interval = RrInterval(intervalMs: 800, timestamp: timestamp);

      expect(interval.intervalMs, 800);
      expect(interval.timestamp, timestamp);
      expect(interval.isArtifact, isFalse);
    });

    test('constructs with isArtifact explicitly set to true', () {
      final timestamp = DateTime(2026, 6, 21, 12, 0, 1);
      final interval = RrInterval(
        intervalMs: 750,
        timestamp: timestamp,
        isArtifact: true,
      );

      expect(interval.intervalMs, 750);
      expect(interval.timestamp, timestamp);
      expect(interval.isArtifact, isTrue);
    });
  });

  group('SignalQuality.fromSnr', () {
    test('returns fair at the good threshold (5.0) and good strictly above it', () {
      expect(SignalQuality.fromSnr(5.0), SignalQuality.fair);
      expect(SignalQuality.fromSnr(5.1), SignalQuality.good);
    });

    test('returns fair just below the good threshold', () {
      expect(SignalQuality.fromSnr(4.9), SignalQuality.fair);
    });

    test('returns poor at the fair threshold (0.0) and fair strictly above it', () {
      expect(SignalQuality.fromSnr(0.0), SignalQuality.poor);
      expect(SignalQuality.fromSnr(0.1), SignalQuality.fair);
    });

    test('returns poor just below the fair threshold', () {
      expect(SignalQuality.fromSnr(-0.1), SignalQuality.poor);
    });

    test('returns poor for negative SNR', () {
      expect(SignalQuality.fromSnr(-10.0), SignalQuality.poor);
    });

    test('returns poor for NaN SNR', () {
      expect(SignalQuality.fromSnr(double.nan), SignalQuality.poor);
    });
  });
}
