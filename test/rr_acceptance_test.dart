import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ppg_kit/src/models/rr_interval.dart';
import 'package:camera_ppg_kit/src/processing/rr_acceptance.dart';

final _ts = DateTime(2024, 1, 1, 12);

RrInterval _rr(int intervalMs) =>
    RrInterval(intervalMs: intervalMs, timestamp: _ts);

void main() {
  group('RrAcceptance', () {
    test('first 3 beats are accepted unconditionally, even at extreme HR', () {
      final gate = RrAcceptance();

      expect(gate.evaluate(_rr(3500)).isArtifact, isFalse);
      expect(gate.evaluate(_rr(3500)).isArtifact, isFalse);
      expect(gate.evaluate(_rr(3500)).isArtifact, isFalse);
    });

    test('intervalMs below minRrMs is an artifact regardless of history', () {
      final gate = RrAcceptance();

      // Cold-start: no history yet.
      expect(gate.evaluate(_rr(250)).isArtifact, isTrue);

      // Seed a stable history, then confirm the hard floor still applies.
      gate.evaluate(_rr(800));
      gate.evaluate(_rr(800));
      gate.evaluate(_rr(800));
      expect(gate.evaluate(_rr(250)).isArtifact, isTrue);
    });

    test('bradycardia beat past a seeded median is not an artifact (no upper bound)', () {
      final gate = RrAcceptance();

      // Seed a ~3000ms median.
      gate.evaluate(_rr(3000));
      gate.evaluate(_rr(3000));
      gate.evaluate(_rr(3000));

      expect(gate.evaluate(_rr(4000)).isArtifact, isFalse);
    });

    test('a +50% spike off a stable median is an artifact and does not poison the history', () {
      final gate = RrAcceptance();

      // Seed a stable ~800ms median.
      gate.evaluate(_rr(800));
      gate.evaluate(_rr(800));
      gate.evaluate(_rr(800));

      // +50% spike is flagged as an artifact.
      expect(gate.evaluate(_rr(1200)).isArtifact, isTrue);

      // A following in-range beat is not an artifact, proving the spike
      // was excluded from the rolling median.
      expect(gate.evaluate(_rr(800)).isArtifact, isFalse);
    });

    test('reset() re-arms cold-start grace for the next measurement', () {
      final gate = RrAcceptance();

      // Seed and confirm the gate is active.
      gate.evaluate(_rr(800));
      gate.evaluate(_rr(800));
      gate.evaluate(_rr(800));
      expect(gate.evaluate(_rr(1200)).isArtifact, isTrue);

      gate.reset();

      // Cold-start grace re-armed: first 3 beats accepted unconditionally,
      // even at an HR wildly inconsistent with the pre-reset history.
      expect(gate.evaluate(_rr(3500)).isArtifact, isFalse);
      expect(gate.evaluate(_rr(3500)).isArtifact, isFalse);
      expect(gate.evaluate(_rr(3500)).isArtifact, isFalse);
    });
  });
}
