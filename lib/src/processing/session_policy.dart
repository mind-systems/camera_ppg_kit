import '../models/finger_presence.dart';
import '../models/measurement_state.dart';
import '../models/signal_quality.dart';

/// Pure-Dart session-lifecycle policy: warm-up suppression and
/// SQI/finger-presence acceptance gating.
///
/// `flutter_ppg` streams `PPGSignal`s continuously but leaves "when has this
/// warmed up" and "is this good enough" to the host — this class is that
/// policy (spec `.ai-factory/notes/09-session-policy.md`). It is a pure
/// function of `(elapsed, quality, presence)` ticks fed in by the caller: it
/// owns no `Timer` and reads no wall clock itself, so it can be driven by a
/// synthetic tick sequence in tests and is safe to run off the UI thread. It
/// decides session-level [MeasurementState] only — it does not touch
/// per-beat `RrInterval.isArtifact` validity (that is the Phase-6/8
/// acceptance gate's separate concern). The session is open-ended: it never
/// self-terminates, ending only when the caller stops/disposes it.
///
/// Call [reset] once per measurement (on `CameraPpgSession.start()` lock),
/// then feed every subsequent `PPGSignal` through [onSignal] in order — do
/// not create a new instance per tick, mirroring `neiry_kit`'s
/// `PpgPeakDetector` reset/feed pattern.
class SessionPolicy {
  SessionPolicy({
    this.warmupDuration = const Duration(seconds: 5),
    this.silenceWindow = const Duration(seconds: 3),
    this.sqiFloor = SignalQuality.poor,
  });

  /// Time since [reset] during which RR intervals are withheld while the
  /// AGC/finger settle, regardless of signal quality. Purely time-based —
  /// leaving warm-up does not require an accepted tick; acceptance gating
  /// only governs [MeasurementState.measuring] afterwards.
  final Duration warmupDuration;

  /// How long an unbroken run of unaccepted ticks must persist while
  /// [MeasurementState.measuring] before the session transitions to
  /// [MeasurementState.poorSignal].
  final Duration silenceWindow;

  /// The [SignalQuality] band at or below which a tick is rejected by the
  /// acceptance predicate. The default ([SignalQuality.poor]) rejects only
  /// `poor` ticks (accepts `good`/`fair`); a stricter floor (e.g. `fair`)
  /// also rejects `fair` ticks. `Finger` `absent`/`overBright` always
  /// rejects, independent of this floor.
  final SignalQuality sqiFloor;

  MeasurementState _state = MeasurementState.idle;

  /// Elapsed time at which the current unbroken run of unaccepted ticks
  /// began, while [MeasurementState.measuring]. `null` when there is no
  /// run in progress (last tick was accepted, or state isn't `measuring`).
  Duration? _badSince;

  /// Current lifecycle state, as last computed by [onSignal] (or `idle`
  /// before the first [reset]).
  MeasurementState get state => _state;

  /// Whether RR intervals produced by the current tick should be forwarded
  /// to consumers. True only in [MeasurementState.measuring].
  bool get rrTrusted => _state == MeasurementState.measuring;

  /// Resets all internal state ahead of a new measurement. Call this once,
  /// on every session start (lock), before the first [onSignal] tick.
  void reset() {
    _state = MeasurementState.warmup;
    _badSince = null;
  }

  /// Advances the state machine by one signal tick and returns the new
  /// [state]. [elapsed] is monotonic time since [reset] (production caller
  /// passes a `Stopwatch.elapsed` reading; tests pass synthetic values).
  ///
  /// Per-tick ordering (deterministic — pinned exactly for test coverage):
  /// 1. Evaluate acceptance for this tick from [quality]/[presence].
  /// 2. Run the transition for the entry state.
  /// 3. Return the new [state].
  MeasurementState onSignal({
    required Duration elapsed,
    required SignalQuality quality,
    required FingerPresence presence,
  }) {
    final accepted =
        presence == FingerPresence.present && quality.index < sqiFloor.index;

    switch (_state) {
      case MeasurementState.idle:
        // onSignal is only meaningful after reset(); stay put if called
        // before that (defensive — CameraPpgSession always resets first).
        break;

      case MeasurementState.warmup:
        if (elapsed >= warmupDuration) {
          _state = MeasurementState.measuring;
          _badSince = null;
        }
        break;

      case MeasurementState.measuring:
        if (!accepted) {
          _badSince ??= elapsed;
          if (elapsed - _badSince! >= silenceWindow) {
            _state = MeasurementState.poorSignal;
          }
        } else {
          _badSince = null;
        }
        break;

      case MeasurementState.poorSignal:
        if (accepted) {
          _state = MeasurementState.measuring;
          _badSince = null;
        }
        break;
    }

    return _state;
  }
}
