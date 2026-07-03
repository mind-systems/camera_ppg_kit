// De-halving offline design harness (plan 23 / spec note 29) — Task 5.
// Candidate 2: rate-derived min-distance. Note 29's approach 2 is "adaptively
// drive `flutter_ppg`'s `PPGConfig` peak params" — i.e. suppress halved
// peaks *at the source*, inside `flutter_ppg`'s `PeakDetector`, instead of
// merging them back together after the fact in the RR domain (candidate 1).
// The fixtures carry no raw/filtered waveform (see plan 23's Constraints),
// so at-source suppression cannot be run or scored directly offline. This
// file is therefore two things, clearly separated:
//   1. The best available **offline approximation** on the RR stream: an
//      adaptive floor derived from the tracked beat period (never a fixed
//      ms/BPM constant), scored with the same `scoring.dart` module as
//      every other candidate.
//   2. A **feasibility record** (this header + the section below) of
//      whether `flutter_ppg`'s `FlutterPPGService` can actually be driven
//      this way at all, based on reading its source and
//      `lib/src/processing/frame_isolate.dart`.
//
// ---------------------------------------------------------------------------
// Feasibility findings (note 29's open question: can `FlutterPPGService` be
// reconfigured mid-stream, or does it need teardown/respawn — and is that
// acceptable on the frame isolate?):
//
// - `FlutterPPGService.config` (`flutter_ppg-0.2.4/lib/src/flutter_ppg_service.dart`,
//   line ~41) is a `final PPGConfig` set once in the constructor. `PPGConfig`
//   itself (`lib/src/models/ppg_config.dart`) is an immutable `const` value
//   type with no setters. There is no public API to mutate `minRRMs` (or any
//   other config field) on a live `FlutterPPGService` — the package's own
//   "adaptive minDistance" (`_adjustAdaptiveMinDistance`, driven by
//   `_minDistanceFromFps`) only reacts to *measured FPS*, confirming note
//   29's finding that the existing adaptivity is keyed on the wrong
//   variable and cannot be repurposed to key on measured heart rate instead.
// - Therefore: **reconfiguring requires a full teardown/respawn**, not a
//   live parameter update. The frame isolate
//   (`lib/src/processing/frame_isolate.dart`, `_frameIsolateEntrypoint`,
//   ~line 231) constructs exactly one `FlutterPPGService(config: const
//   PPGConfig())` for the isolate's whole lifetime and feeds it via one
//   `imageStreamCtrl`/`service.processImageStream(...).listen(...)`
//   subscription. Driving a rate-derived `minRRMs` would mean, on every
//   tracked-rate change: closing `imageStreamCtrl`, cancelling `sub`,
//   disposing the old service, then constructing a new
//   `FlutterPPGService` and a new controller/subscription — i.e. re-running
//   the isolate's own close-before-cancel teardown sequence (the same
//   ordering invariant notes 07/13 had to get right once already) on every
//   single rate adjustment, not once at isolate shutdown.
// - **Verdict:** technically possible but a materially bigger and riskier
//   lift than candidate 1 (which is a pure RR-domain stage touching no
//   isolate/teardown code at all), and it reintroduces a known hazard class
//   on a hot path (every rate change, not just measurement end). This is
//   feasibility evidence for note 30's decision, not a recommendation
//   embedded in code.
// ---------------------------------------------------------------------------
import 'package:camera_ppg_kit/camera_ppg_kit.dart';

import '../fixture.dart';
import '../scoring.dart';

/// Offline RR-domain approximation of a rate-derived min-distance floor.
/// Tracks the dominant beat period the same way candidate 1 does (a
/// median-of-first-N bootstrap, then an EMA over self-consistent beats), and
/// treats any beat below `floorFraction * trackedPeriodMs` as a peak that a
/// correctly-tuned `PeakDetector.minDistance` would have suppressed at the
/// source: its duration is carried forward and folded into the next beat
/// that clears the floor (approximating the true peak-to-peak interval a
/// source-side suppression would have produced), rather than merged
/// pairwise like candidate 1. `floorFraction` is proportional to the
/// tracked rate — never a fixed ms/BPM constant.
class RateMinDistanceCandidate {
  RateMinDistanceCandidate({
    this.bootstrapBeats = 3,
    this.floorFraction = 0.5,
    this.trackerAlpha = 0.1,
    this.fullBeatTolerance = 0.40,
  });

  final int bootstrapBeats;

  /// The adaptive floor is `floorFraction * trackedPeriodMs` — 0.5 mirrors
  /// note 29's "0.5x the tracked beat period" framing of this approach.
  final double floorFraction;
  final double trackerAlpha;
  final double fullBeatTolerance;

  double? get trackedPeriodMs => _trackedPeriodMs;
  int? get convergedAtBeatIndex => _convergedAtBeatIndex;

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

  int _carryMs = 0;
  final List<int> _carryIndices = [];

  /// Feeds one raw interval through the stage. Returns `null` while a
  /// sub-floor beat's duration is being carried forward, or the combined
  /// (possibly carry-extended) interval once a beat clears the floor.
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
      return rr;
    }

    final floorMs = _trackedPeriodMs! * floorFraction;
    if (rr.intervalMs < floorMs) {
      // Below the adaptive floor: this peak would not have registered at
      // the source. Carry its duration forward instead of dropping it
      // silently, so the eventual clearing beat approximates the true
      // peak-to-peak interval.
      _decisions[index] = BeatOutcome.dropped;
      _carryMs += rr.intervalMs;
      _carryIndices.add(index);
      return null;
    }

    final hadCarry = _carryIndices.isNotEmpty;
    final combinedMs = rr.intervalMs + _carryMs;

    if (hadCarry) {
      for (final i in _carryIndices) {
        _decisions[i] = BeatOutcome.partOfMerge;
      }
      _decisions[index] = BeatOutcome.partOfMerge;
    } else {
      _decisions[index] = BeatOutcome.emittedAsIs;
    }
    _carryIndices.clear();
    _carryMs = 0;

    final devFrac = (combinedMs - _trackedPeriodMs!).abs() / _trackedPeriodMs!;
    if (devFrac <= fullBeatTolerance) {
      _trackedPeriodMs = _ema(_trackedPeriodMs!, combinedMs.toDouble());
    }

    return RrInterval(intervalMs: combinedMs, timestamp: rr.timestamp);
  }

  double _ema(double previous, double sample) =>
      previous + trackerAlpha * (sample - previous);

  /// Call once at end-of-stream. Any beats still carried forward never
  /// found a clearing beat before the stream ended — they stay [BeatOutcome.dropped]
  /// (there is no beat left to fold them into); this stage never emits a
  /// bare carry with nothing to attach it to.
  RrInterval? flush() {
    _carryIndices.clear();
    _carryMs = 0;
    return null;
  }

  void reset() {
    _trackedPeriodMs = null;
    _convergedAtBeatIndex = null;
    _bootstrapMagnitudes.clear();
    _decisions.clear();
    _carryMs = 0;
    _carryIndices.clear();
  }

  static double _median(List<int> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid].toDouble();
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// Result of replaying a fixture through [RateMinDistanceCandidate] — mirrors
/// `baseline.dart`/`harmonic_merge.dart`'s result shape.
class RateMinDistanceRunResult {
  const RateMinDistanceRunResult({
    required this.candidate,
    required this.acceptedMagnitudesMs,
    required this.score,
  });

  final RateMinDistanceCandidate candidate;
  final List<int> acceptedMagnitudesMs;
  final CandidateScore score;
}

/// Replays [fixture]'s raw intervals through a fresh [RateMinDistanceCandidate]
/// and scores the offline approximation. Labeled explicitly (see the file
/// header) as part-measured, part-feasibility: this scores only the RR-domain
/// approximation, not true at-source peak suppression.
RateMinDistanceRunResult runRateMinDistance(
  CalibrationFixture fixture, {
  int bootstrapBeats = 3,
  double floorFraction = 0.5,
  double trackerAlpha = 0.1,
  double fullBeatTolerance = 0.40,
}) {
  final candidate = RateMinDistanceCandidate(
    bootstrapBeats: bootstrapBeats,
    floorFraction: floorFraction,
    trackerAlpha: trackerAlpha,
    fullBeatTolerance: fullBeatTolerance,
  );

  final acceptedMagnitudesMs = <int>[];
  for (final rr in fixture.toRrIntervals()) {
    final out = candidate.evaluate(rr);
    if (out != null) acceptedMagnitudesMs.add(out.intervalMs);
  }
  candidate.flush();

  final result = score(
    fixture: fixture,
    acceptedMagnitudesMs: acceptedMagnitudesMs,
    perBeatOutcomes: candidate.outcomes,
  );

  return RateMinDistanceRunResult(
    candidate: candidate,
    acceptedMagnitudesMs: acceptedMagnitudesMs,
    score: result,
  );
}
