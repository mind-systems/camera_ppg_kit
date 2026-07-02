import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ppg_kit/src/models/finger_presence.dart';
import 'package:camera_ppg_kit/src/models/measurement_state.dart';
import 'package:camera_ppg_kit/src/models/signal_quality.dart';
import 'package:camera_ppg_kit/src/processing/session_policy.dart';

void main() {
  group('SessionPolicy', () {
    test('after reset(), state is warmup and rrTrusted is false', () {
      final policy = SessionPolicy();
      policy.reset();
      expect(policy.state, MeasurementState.warmup);
      expect(policy.rrTrusted, isFalse);
    });

    test('ticks before warmupDuration stay warmup; a tick at/after flips to measuring', () {
      final policy = SessionPolicy();
      policy.reset();

      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 1),
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        ),
        MeasurementState.warmup,
      );
      expect(policy.rrTrusted, isFalse);

      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 4),
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        ),
        MeasurementState.warmup,
      );
      expect(policy.rrTrusted, isFalse);

      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 5),
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        ),
        MeasurementState.measuring,
      );
      expect(policy.rrTrusted, isTrue);
    });

    test(
      'measuring: a brief unaccepted run shorter than silenceWindow stays measuring; '
      'sustained past silenceWindow flips to poorSignal; a later accepted tick resumes measuring',
      () {
        final policy = SessionPolicy();
        policy.reset();

        // Reach measuring.
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 5),
            quality: SignalQuality.good,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );

        // Brief unaccepted run (1s), well short of silenceWindow (3s).
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 6),
            quality: SignalQuality.poor,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );

        // Accepted tick clears the "bad since" marker.
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 7),
            quality: SignalQuality.good,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );

        // New unaccepted run starts here (elapsed=8); still short of the
        // window at elapsed=10 (2s elapsed since badSince).
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 8),
            quality: SignalQuality.poor,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 9),
            quality: SignalQuality.poor,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 10),
            quality: SignalQuality.poor,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );

        // Sustained continuously bad for >= silenceWindow (3s since badSince=8).
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 11),
            quality: SignalQuality.poor,
            presence: FingerPresence.present,
          ),
          MeasurementState.poorSignal,
        );

        // Quality recovers -> resume measuring immediately.
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 12),
            quality: SignalQuality.good,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );
      },
    );

    test(
      'unaccepted presence (absent/overBright) drives the same silenceWindow -> poorSignal transition as poor quality',
      () {
        final policy = SessionPolicy();
        policy.reset();

        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 5),
            quality: SignalQuality.good,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 6),
            quality: SignalQuality.good,
            presence: FingerPresence.absent,
          ),
          MeasurementState.measuring,
        );
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 9),
            quality: SignalQuality.good,
            presence: FingerPresence.overBright,
          ),
          MeasurementState.poorSignal,
        );
      },
    );

    test('accumulated measuring time reaching targetDuration flips to done, and done is terminal', () {
      final policy = SessionPolicy(
        warmupDuration: Duration.zero,
        targetDuration: const Duration(seconds: 10),
      );
      policy.reset();

      // warmupDuration is zero, so the very first tick already flips to
      // measuring (elapsed 0 >= warmupDuration 0) without accumulating any
      // measured time for this transition tick.
      expect(
        policy.onSignal(
          elapsed: Duration.zero,
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        ),
        MeasurementState.measuring,
      );
      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 5),
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        ),
        MeasurementState.measuring,
      );
      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 10),
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        ),
        MeasurementState.done,
      );

      // done is terminal: a later accepted tick does not revert it.
      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 15),
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        ),
        MeasurementState.done,
      );
    });

    test(
      'poorSignal time does not count toward targetDuration: a sparse warmup-jump and a sparse '
      'poorSignal-resume both skip retroactively counting their gap as measuring time',
      () {
        final policy = SessionPolicy(
          warmupDuration: const Duration(seconds: 5),
          targetDuration: const Duration(seconds: 10),
          silenceWindow: const Duration(seconds: 2),
        );
        policy.reset();

        // elapsed=100: sparse warmup -> measuring tick (elapsed jumps far
        // past warmupDuration). If the jump were counted as measured time,
        // a following tick would blow straight past targetDuration (10s)
        // instead of staying `measuring` as asserted below.
        policy.onSignal(
          elapsed: const Duration(seconds: 100),
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        );
        // elapsed=101: measured=1
        policy.onSignal(
          elapsed: const Duration(seconds: 101),
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        );
        // elapsed=102: unaccepted, badSince=102, measured=2
        policy.onSignal(
          elapsed: const Duration(seconds: 102),
          quality: SignalQuality.poor,
          presence: FingerPresence.present,
        );
        // elapsed=104: unaccepted, 104-102=2 >= silenceWindow(2) -> poorSignal, measured=4
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 104),
            quality: SignalQuality.poor,
            presence: FingerPresence.present,
          ),
          MeasurementState.poorSignal,
        );

        // Sparse poorSignal -> measuring resume: elapsed jumps far ahead.
        // If the gap were counted, measured (4s) + the huge gap would blow
        // past targetDuration immediately.
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 9999),
            quality: SignalQuality.good,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );

        // Confirm the accumulator only picked up real measuring deltas: two
        // more 1s ticks (measured 4 -> 5 -> 6) stay under the 10s target.
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 10000),
            quality: SignalQuality.good,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 10001),
            quality: SignalQuality.good,
            presence: FingerPresence.present,
          ),
          MeasurementState.measuring,
        );
        // One more 4s delta (measured 6 -> 10) reaches targetDuration.
        expect(
          policy.onSignal(
            elapsed: const Duration(seconds: 10005),
            quality: SignalQuality.good,
            presence: FingerPresence.present,
          ),
          MeasurementState.done,
        );
      },
    );

    test('sqiFloor override (fair) additionally rejects fair-quality ticks', () {
      final policy = SessionPolicy(
        warmupDuration: Duration.zero,
        silenceWindow: const Duration(seconds: 2),
        sqiFloor: SignalQuality.fair,
      );
      policy.reset();

      expect(
        policy.onSignal(
          elapsed: Duration.zero,
          quality: SignalQuality.good,
          presence: FingerPresence.present,
        ),
        MeasurementState.measuring,
      );

      // fair is rejected under this floor, so a continuous fair run for
      // >= silenceWindow flips to poorSignal (it would not under the
      // default `poor` floor — see the control assertion below).
      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 1),
          quality: SignalQuality.fair,
          presence: FingerPresence.present,
        ),
        MeasurementState.measuring,
      );
      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 3),
          quality: SignalQuality.fair,
          presence: FingerPresence.present,
        ),
        MeasurementState.poorSignal,
      );
    });

    test('control: default sqiFloor (poor) accepts fair-quality ticks, so it never enters poorSignal', () {
      final policy = SessionPolicy(
        warmupDuration: Duration.zero,
        silenceWindow: const Duration(seconds: 2),
      );
      policy.reset();

      expect(
        policy.onSignal(
          elapsed: Duration.zero,
          quality: SignalQuality.fair,
          presence: FingerPresence.present,
        ),
        MeasurementState.measuring,
      );
      expect(
        policy.onSignal(
          elapsed: const Duration(seconds: 3),
          quality: SignalQuality.fair,
          presence: FingerPresence.present,
        ),
        MeasurementState.measuring,
      );
    });
  });
}
