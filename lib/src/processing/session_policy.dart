import '../models/finger_presence.dart';
import '../models/measurement_state.dart';
import '../models/signal_quality.dart';

/// Pure-Dart session-lifecycle policy: warm-up suppression, target-duration
/// tracking, and SQI/finger-presence acceptance gating.
///
/// `flutter_ppg` streams `PPGSignal`s continuously but leaves "when has this
/// warmed up", "is this good enough", and "when are we done" to the host —
/// this class is that policy (spec `.ai-factory/notes/09-session-policy.md`).
/// It is a pure function of `(elapsed, quality, presence)` ticks fed in by
/// the caller: it owns no `Timer` and reads no wall clock itself, so it can
/// be driven by a synthetic tick sequence in tests and is safe to run off
/// the UI thread. It decides session-level [MeasurementState] only — it does
/// not touch per-beat `RrInterval.isArtifact` validity (that is the
/// Phase-6/8 acceptance gate's separate concern).
///
/// Call [reset] once per measurement (on `CameraPpgSession.start()` lock),
/// then feed every subsequent `PPGSignal` through [onSignal] in order — do
/// not create a new instance per tick, mirroring `neiry_kit`'s
/// `PpgPeakDetector` reset/feed pattern.
class SessionPolicy {
  SessionPolicy({
    this.warmupDuration = const Duration(seconds: 5),
    this.targetDuration = const Duration(seconds: 60),
    this.silenceWindow = const Duration(seconds: 3),
    this.sqiFloor = SignalQuality.poor,
  });

  /// Time since [reset] during which RR intervals are withheld while the
  /// AGC/finger settle, regardless of signal quality. Purely time-based —
  /// leaving warm-up does not require an accepted tick; acceptance gating
  /// only governs [MeasurementState.measuring] afterwards.
  final Duration warmupDuration;

  /// Cumulative time spent in [MeasurementState.measuring] (time spent in
  /// [MeasurementState.poorSignal] does not count) after which the session
  /// transitions to [MeasurementState.done].
  final Duration targetDuration;

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

  /// Cumulative time spent in [MeasurementState.measuring] since [reset].
  Duration _measured = Duration.zero;

  /// Elapsed time of the last tick, so each new tick can derive its `delta`.
  Duration _lastElapsed = Duration.zero;

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
    _measured = Duration.zero;
    _lastElapsed = Duration.zero;
    _badSince = null;
  }

  /// Advances the state machine by one signal tick and returns the new
  /// [state]. [elapsed] is monotonic time since [reset] (production caller
  /// passes a `Stopwatch.elapsed` reading; tests pass synthetic values).
  ///
  /// Per-tick ordering (deterministic — pinned exactly for test coverage):
  /// 1. Compute `delta = elapsed - lastElapsed`.
  /// 2. Add `delta` to the measured-time accumulator, but only if the state
  ///    at tick *entry* was already [MeasurementState.measuring] — so the
  ///    `warmup → measuring` and `poorSignal → measuring` transition ticks
  ///    do not retroactively count the warm-up/silence gap as measuring
  ///    time.
  /// 3. Evaluate the transition for the entry state.
  /// 4. Unconditionally update the last-elapsed marker, in every state, so
  ///    it never lags and the next tick's `delta` stays small.
  MeasurementState onSignal({
    required Duration elapsed,
    required SignalQuality quality,
    required FingerPresence presence,
  }) {
    final accepted =
        presence == FingerPresence.present && quality.index < sqiFloor.index;

    final delta = elapsed - _lastElapsed;
    final enteredMeasuring = _state == MeasurementState.measuring;
    if (enteredMeasuring) {
      _measured += delta;
    }

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
        if (_measured >= targetDuration) {
          _state = MeasurementState.done;
        } else if (!accepted) {
          _badSince ??= elapsed;
          if (elapsed - _badSince! >= silenceWindow) {
            _state = MeasurementState.poorSignal;
          }
        } else {
          _badSince = null;
        }
        break;

      case MeasurementState.poorSignal:
        // poorSignal time does not count toward targetDuration — only time
        // spent in `measuring` accumulates, via step 2 above.
        if (accepted) {
          _state = MeasurementState.measuring;
          _badSince = null;
        }
        break;

      case MeasurementState.done:
        // Terminal — remains `done` regardless of subsequent ticks until
        // the next reset().
        break;
    }

    _lastElapsed = elapsed;
    return _state;
  }
}
