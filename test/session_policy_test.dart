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
