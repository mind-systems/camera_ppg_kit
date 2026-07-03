// De-halving offline design harness (plan 23 / spec note 29) — Task 4.
// Candidate 1: RR-domain harmonic-pair merge. A pure, stateful stage that
// tracks the dominant beat period adaptively (a slow-tracking EMA of
// self-consistent beat magnitudes, seeded by a short median-of-first-N
// bootstrap — mirroring `RrAcceptance`'s cold-start grace) and merges pairs
// of consecutive short intervals that sum to ~the tracked period. Rejection
// scales with the tracked rate — there is no fixed ms/BPM floor anywhere in
// this file.
//
// Output contract (pinned per plan 23 Task 4 — a pair-merge is 2:1, not
// 1:1, so it cannot mirror `RrAcceptance.evaluate`'s `RrInterval
// evaluate(RrInterval)` signature):
//   - `RrInterval? evaluate(RrInterval)` — returns `null` while a short
//     interval is held pending a partner, or the next interval this stage
//     has ready to emit (the merged pair, a beat proven standalone by
//     what followed it, or a fresh full-length beat) otherwise. Because a
//     single input can occasionally resolve two outputs (a stale pending
//     beat flushed by an unrelated following full beat), ready-but-unpopped
//     output is buffered internally and drained on the *next* call — so a
//     `null`/non-`null` return does not always describe the interval just
//     passed in.
//   - `List<RrInterval> flush()` — call once at end-of-stream; drains any
//     buffered output plus a still-pending beat (emitted standalone).
//   - `void reset()` — clears all state (tracker, bootstrap, pending,
//     buffered output, decision log) for the next measurement.
// See note 30 for why this shape was chosen over a 1:1 signature.
import 'dart:collection';

import 'package:camera_ppg_kit/camera_ppg_kit.dart';

import '../fixture.dart';
import '../scoring.dart';

/// Stateful harmonic-pair-merge de-halving stage. One instance per
/// measurement — call [evaluate] for every trusted interval in order, then
/// [flush] once at stream end, and [reset] between measurements.
class HarmonicMergeCandidate {
  HarmonicMergeCandidate({
    this.bootstrapBeats = 3,
    this.shortFraction = 0.75,
    this.pairTolerance = 0.30,
    this.trackerAlpha = 0.1,
    this.fullBeatTolerance = 0.40,
  });

  /// Number of initial beats whose median seeds the tracked period before
  /// any short/full classification or merging begins — mirrors
  /// `RrAcceptance.coldStartBeats`'s cold-start grace concept.
  final int bootstrapBeats;

  /// A beat is "short" (a merge candidate) when its magnitude is below
  /// `shortFraction * trackedPeriodMs`. Proportional to the tracked rate —
  /// never a fixed ms floor.
  final double shortFraction;

  /// Proportional tolerance for accepting a candidate pair: the pair sums
  /// within `pairTolerance` of the tracked period.
  final double pairTolerance;

  /// EMA responsiveness for the period tracker (0..1 — higher tracks
  /// faster, lower is more stable against noise).
  final double trackerAlpha;

  /// Proportional tolerance for a full-length beat to be trusted enough to
  /// update the tracker (guards the EMA against wild single-beat outliers).
  final double fullBeatTolerance;

  /// The adaptively tracked dominant beat period (ms), or `null` before
  /// [bootstrapBeats] have been observed.
  double? get trackedPeriodMs => _trackedPeriodMs;

  /// Index (into the input stream) at which the tracker first converged —
  /// exposes cold-start convergence latency for Task 7's evaluation.
  int? get convergedAtBeatIndex => _convergedAtBeatIndex;

  /// Per-original-input-beat outcome, parallel to the beats fed to
  /// [evaluate] in order. Only valid after [flush] — a beat still held
  /// pending has no resolved outcome yet.
  List<BeatOutcome> get outcomes {
    assert(
      !_decisions.contains(null),
      'outcomes read before flush() — a beat is still unresolved',
    );
    return _decisions.cast<BeatOutcome>();
  }

  double? _trackedPeriodMs;
  int? _convergedAtBeatIndex;
  final List<int> _bootstrapMagnitudes = [];
  final List<BeatOutcome?> _decisions = [];
  final Queue<RrInterval> _outQueue = Queue<RrInterval>();

  RrInterval? _pending;
  int? _pendingIndex;

  /// Feeds one raw interval through the stage. See the file header for the
  /// buffering output contract.
  RrInterval? evaluate(RrInterval rr) {
    final index = _decisions.length;
    _decisions.add(null);

    if (_trackedPeriodMs == null) {
      _bootstrapMagnitudes.add(rr.intervalMs);
      _decisions[index] = BeatOutcome.emittedAsIs;
      if (_bootstrapMagnitudes.length >= bootstrapBeats) {
        _trackedPeriodMs = _median(_bootstrapMagnitudes);
        _convergedAtBeatIndex = index;
      }
      _outQueue.add(rr);
    } else if (rr.intervalMs < _trackedPeriodMs! * shortFraction) {
      _handleShort(rr, index);
    } else {
      _handleFull(rr, index);
    }

    return _outQueue.isEmpty ? null : _outQueue.removeFirst();
  }

  void _handleShort(RrInterval rr, int index) {
    if (_pending == null) {
      // Hold — nothing to emit yet, this beat might be the first half of a
      // pair.
      _pending = rr;
      _pendingIndex = index;
      return;
    }

    final sum = _pending!.intervalMs + rr.intervalMs;
    final ratioErr = (sum - _trackedPeriodMs!).abs() / _trackedPeriodMs!;
    if (ratioErr <= pairTolerance) {
      // Pair closes: the two short beats together approximate one true
      // beat at the tracked rate.
      _decisions[_pendingIndex!] = BeatOutcome.partOfMerge;
      _decisions[index] = BeatOutcome.partOfMerge;
      _trackedPeriodMs = _ema(_trackedPeriodMs!, sum.toDouble());
      _outQueue.add(RrInterval(intervalMs: sum, timestamp: rr.timestamp));
      _pending = null;
      _pendingIndex = null;
    } else {
      // The pairing doesn't fit the tracked period — the stale pending
      // beat wasn't part of a harmonic pair after all; flush it standalone
      // (untrusted, so it does not update the tracker) and start fresh on
      // the current beat.
      _decisions[_pendingIndex!] = BeatOutcome.emittedAsIs;
      _outQueue.add(_pending!);
      _pending = rr;
      _pendingIndex = index;
    }
  }

  void _handleFull(RrInterval rr, int index) {
    if (_pending != null) {
      // A full-length beat arriving while a short beat is held proves that
      // held beat was standalone, not half of a pair.
      _decisions[_pendingIndex!] = BeatOutcome.emittedAsIs;
      _outQueue.add(_pending!);
      _pending = null;
      _pendingIndex = null;
    }

    final devFrac = (rr.intervalMs - _trackedPeriodMs!).abs() / _trackedPeriodMs!;
    if (devFrac <= fullBeatTolerance) {
      _trackedPeriodMs = _ema(_trackedPeriodMs!, rr.intervalMs.toDouble());
    }
    _decisions[index] = BeatOutcome.emittedAsIs;
    _outQueue.add(rr);
  }

  double _ema(double previous, double sample) =>
      previous + trackerAlpha * (sample - previous);

  /// Call once at end-of-stream. Drains any output already buffered from
  /// the last [evaluate] call, plus a still-pending beat (resolved as
  /// standalone — nothing ever arrived to prove or disprove it as half of
  /// a pair).
  List<RrInterval> flush() {
    final out = <RrInterval>[];
    while (_outQueue.isNotEmpty) {
      out.add(_outQueue.removeFirst());
    }
    if (_pending != null) {
      _decisions[_pendingIndex!] = BeatOutcome.emittedAsIs;
      out.add(_pending!);
      _pending = null;
      _pendingIndex = null;
    }
    return out;
  }

  /// Clears all state for the next measurement.
  void reset() {
    _trackedPeriodMs = null;
    _convergedAtBeatIndex = null;
    _bootstrapMagnitudes.clear();
    _decisions.clear();
    _outQueue.clear();
    _pending = null;
    _pendingIndex = null;
  }

  static double _median(List<int> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid].toDouble();
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// Result of replaying a fixture through [HarmonicMergeCandidate] — mirrors
/// `baseline.dart`'s `BaselineResult` shape so Task 7 can treat every
/// candidate (and the baseline) uniformly.
class HarmonicMergeRunResult {
  const HarmonicMergeRunResult({
    required this.candidate,
    required this.acceptedMagnitudesMs,
    required this.score,
  });

  /// The drained candidate instance — exposes [HarmonicMergeCandidate.convergedAtBeatIndex]
  /// for cold-start convergence reporting.
  final HarmonicMergeCandidate candidate;
  final List<int> acceptedMagnitudesMs;
  final CandidateScore score;
}

/// Replays [fixture]'s raw intervals through a fresh [HarmonicMergeCandidate]
/// and scores the result.
HarmonicMergeRunResult runHarmonicMerge(
  CalibrationFixture fixture, {
  int bootstrapBeats = 3,
  double shortFraction = 0.75,
  double pairTolerance = 0.30,
  double trackerAlpha = 0.1,
  double fullBeatTolerance = 0.40,
}) {
  final candidate = HarmonicMergeCandidate(
    bootstrapBeats: bootstrapBeats,
    shortFraction: shortFraction,
    pairTolerance: pairTolerance,
    trackerAlpha: trackerAlpha,
    fullBeatTolerance: fullBeatTolerance,
  );

  final acceptedMagnitudesMs = <int>[];
  for (final rr in fixture.toRrIntervals()) {
    final out = candidate.evaluate(rr);
    if (out != null) acceptedMagnitudesMs.add(out.intervalMs);
  }
  for (final out in candidate.flush()) {
    acceptedMagnitudesMs.add(out.intervalMs);
  }

  final result = score(
    fixture: fixture,
    acceptedMagnitudesMs: acceptedMagnitudesMs,
    perBeatOutcomes: candidate.outcomes,
  );

  return HarmonicMergeRunResult(
    candidate: candidate,
    acceptedMagnitudesMs: acceptedMagnitudesMs,
    score: result,
  );
}
