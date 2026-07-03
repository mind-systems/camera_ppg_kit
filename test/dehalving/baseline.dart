// De-halving offline design harness (plan 23 / spec note 29) — Task 3.
// Replays a fixture's raw stream through the *committed* `RrAcceptance` gate
// (read-only use of kit code; no kit changes) and confirms the harness
// reproduces the on-device recorded run before any candidate is judged
// against these fixtures as an oracle.
import 'package:camera_ppg_kit/camera_ppg_kit.dart';

import 'fixture.dart';
import 'scoring.dart';

/// Outcome of replaying [fixture] through the committed gate.
class BaselineResult {
  const BaselineResult({
    required this.fixture,
    required this.matchingArtifactFlags,
    required this.totalBeats,
    required this.lastMismatchTMs,
    required this.acceptedMagnitudesMs,
    required this.perBeatOutcomes,
    required this.score,
  });

  final CalibrationFixture fixture;

  /// Number of beats whose recomputed `isArtifact` matches the flag
  /// recorded in the fixture.
  final int matchingArtifactFlags;

  final int totalBeats;

  /// `true` iff every recorded `isArtifact` flag was reproduced exactly —
  /// this is the precondition for treating the fixture as a valid oracle.
  bool get reproducesRecordedFlags => matchingArtifactFlags == totalBeats;

  /// `tMs` of the last beat whose recomputed `isArtifact` disagreed with the
  /// fixture's recorded flag, or `null` if every flag matched
  /// ([reproducesRecordedFlags]). Fixture 2 does not reproduce exactly (note
  /// 29's Results) — every mismatch there falls within the first ~5.3s, so
  /// this lets a test assert that gap stays confined to the warm-up-adjacent
  /// prefix instead of widening unnoticed.
  final int? lastMismatchTMs;

  final List<int> acceptedMagnitudesMs;
  final List<BeatOutcome> perBeatOutcomes;
  final CandidateScore score;
}

/// Replays [fixture]'s raw intervals through `RrAcceptance`, constructed
/// with that fixture's own recorded `acceptance` params (mirroring the
/// on-device run exactly), and scores the result.
BaselineResult runBaseline(CalibrationFixture fixture) {
  final gate = RrAcceptance(
    minRrMs: fixture.acceptance.minRrMs,
    consistencyThreshold: fixture.acceptance.consistencyThreshold,
    coldStartBeats: fixture.acceptance.coldStartBeats,
    medianWindow: fixture.acceptance.medianWindow,
  );

  final rrIntervals = fixture.toRrIntervals();
  final acceptedMagnitudesMs = <int>[];
  final perBeatOutcomes = <BeatOutcome>[];
  var matching = 0;
  int? lastMismatchTMs;

  for (var i = 0; i < rrIntervals.length; i++) {
    // The gate only reads intervalMs; pass a clean (non-artifact) copy in so
    // its own evaluation — not the fixture's recorded flag — decides.
    final evaluated = gate.evaluate(RrInterval(
      intervalMs: rrIntervals[i].intervalMs,
      timestamp: rrIntervals[i].timestamp,
    ));

    if (evaluated.isArtifact == fixture.intervals[i].isArtifact) {
      matching++;
    } else {
      lastMismatchTMs = fixture.intervals[i].tMs;
    }

    if (evaluated.isArtifact) {
      perBeatOutcomes.add(BeatOutcome.dropped);
    } else {
      acceptedMagnitudesMs.add(evaluated.intervalMs);
      perBeatOutcomes.add(BeatOutcome.emittedAsIs);
    }
  }

  final result = score(
    fixture: fixture,
    acceptedMagnitudesMs: acceptedMagnitudesMs,
    perBeatOutcomes: perBeatOutcomes,
  );

  return BaselineResult(
    fixture: fixture,
    matchingArtifactFlags: matching,
    totalBeats: rrIntervals.length,
    lastMismatchTMs: lastMismatchTMs,
    acceptedMagnitudesMs: acceptedMagnitudesMs,
    perBeatOutcomes: perBeatOutcomes,
    score: result,
  );
}
