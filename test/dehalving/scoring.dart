// De-halving offline design harness (plan 23 / spec note 29) — candidate-
// agnostic scoring. Consumes only the ordered accepted-magnitude series plus
// a per-original-beat outcome list; knows nothing about how a candidate
// produced them, so it scores the baseline gate (Task 3), the harmonic-merge
// candidate (Task 4), and the rate-derived-min-distance candidate (Task 5)
// identically.
import 'fixture.dart';

/// What became of one *original* raw-stream beat (`FixtureBeat`) after a
/// candidate processed it. Candidates may internally hold a beat pending a
/// merge decision (see Task 4's buffering `evaluate`), but by the time the
/// stream (plus `flush()`) is fully drained every original beat resolves to
/// exactly one of these three terminal outcomes — "held" is a transient
/// in-stream state, never a final one.
enum BeatOutcome {
  /// Emitted standalone, unmodified — the candidate judged this one beat to
  /// be one real pulse.
  emittedAsIs,

  /// Consumed into a 2:1 merge with a neighboring beat; the merged
  /// magnitude appears in the accepted-magnitude series, not this beat's
  /// own `rrMs`.
  partOfMerge,

  /// Rejected outright (e.g. below a hard floor) — contributes no magnitude
  /// to the accepted-magnitude series.
  dropped,
}

/// Which population (per note 29's bimodal RR distribution) an original beat
/// belongs to, judged purely by proximity to the fixture's own fundamental
/// period — never by a hardcoded ms constant.
enum ClusterMembership { trueCluster, halvedCluster, unclassified }

/// Classifies [rrMs] against [fixture]'s own reference period. True cluster:
/// within ±15% of the reference period. Halved cluster: within ±20% of half
/// that period. Anything else (including the far tail of an even-lower
/// sub-harmonic) is unclassified and excluded from both fractions'
/// denominators — the bands are intentionally narrow so retention/removal
/// fractions aren't inflated by beats that are actually noise.
ClusterMembership classifyBeat(int rrMs, CalibrationFixture fixture) {
  final truePeriodMs = 60000 / fixture.referenceBpm;
  final halvedPeriodMs = truePeriodMs / 2;

  final trueLow = truePeriodMs * 0.85;
  final trueHigh = truePeriodMs * 1.15;
  if (rrMs >= trueLow && rrMs <= trueHigh) return ClusterMembership.trueCluster;

  final halvedLow = halvedPeriodMs * 0.80;
  final halvedHigh = halvedPeriodMs * 1.20;
  if (rrMs >= halvedLow && rrMs <= halvedHigh) {
    return ClusterMembership.halvedCluster;
  }

  return ClusterMembership.unclassified;
}

/// Result of the transitional-run probe (Task 2e): whether a candidate kept
/// tracking the true-cluster fundamental through a stretch of the raw stream
/// where consecutive magnitudes roughly halve in place (the exact failure
/// mode note 29 recorded for the committed gate: its rolling median walked
/// from the true cluster onto the halved one). Detected generically by
/// scanning for a near-halving descending run within a tight `tMs` window —
/// not hardcoded to fixture 1's specific indices — so it degrades to
/// `found: false` on a fixture that has no such stretch (fixture 2).
class TransitionalRunResult {
  const TransitionalRunResult({
    required this.found,
    this.startTMs,
    this.runMagnitudesMs = const [],
    this.staysOnTrueCluster = false,
  });

  /// Whether a qualifying near-halving run was found in this fixture at all.
  final bool found;

  /// `tMs` of the first sample in the run, if [found].
  final int? startTMs;

  /// The raw `rrMs` sequence of the run, if [found] (e.g. fixture 1's
  /// `917, 708, 583, 500, 458`).
  final List<int> runMagnitudesMs;

  /// `true` when every halved-cluster beat inside the run was merged away
  /// or dropped — i.e. the candidate never accepted a halved-cluster beat
  /// as a standalone new beat (the committed gate's failure mode). Only
  /// meaningful when [found].
  final bool staysOnTrueCluster;
}

/// Scored evidence for one candidate (or the Task 3 baseline) against one
/// fixture.
class CandidateScore {
  const CandidateScore({
    required this.fixtureName,
    required this.referenceBpm,
    required this.derivedBpm,
    required this.bpmError,
    required this.medianMagnitudeBpm,
    required this.trueClusterRetention,
    required this.halvedClusterRemoval,
    required this.transitionalRun,
  });

  final String fixtureName;

  /// `manualCount.beats / manualCount.windowSeconds * 60` — the oracle.
  final double referenceBpm;

  /// `round(60000 / mean(acceptedMagnitudesMs))` — the headline BPM (Task 2a:
  /// the only derivation that reproduces both fixtures' recorded `kitBpm` on
  /// the raw stream and lands near the reference after de-halving).
  final int derivedBpm;

  /// `derivedBpm - referenceBpm`. Target: within ±3.
  final double bpmError;

  /// Secondary diagnostic only — BPM from the *median* accepted magnitude,
  /// never the headline metric.
  final double medianMagnitudeBpm;

  /// Fraction of original true-cluster beats whose outcome was
  /// [BeatOutcome.emittedAsIs] or [BeatOutcome.partOfMerge] (i.e. survived
  /// into the accepted output, whether standalone or as one half of a
  /// merge) — `null` if the fixture has no true-cluster beats to score.
  final double? trueClusterRetention;

  /// Fraction of original halved-cluster beats whose outcome was
  /// [BeatOutcome.partOfMerge] or [BeatOutcome.dropped] (i.e. removed from
  /// standing as their own beat) — `null` if the fixture has no
  /// halved-cluster beats to score.
  final double? halvedClusterRemoval;

  final TransitionalRunResult transitionalRun;

  @override
  String toString() {
    final ret = trueClusterRetention == null
        ? 'n/a'
        : '${(trueClusterRetention! * 100).toStringAsFixed(1)}%';
    final rem = halvedClusterRemoval == null
        ? 'n/a'
        : '${(halvedClusterRemoval! * 100).toStringAsFixed(1)}%';
    final trans = !transitionalRun.found
        ? 'n/a'
        : (transitionalRun.staysOnTrueCluster ? 'held true' : 'FLIPPED');
    return '$fixtureName: derivedBpm=$derivedBpm referenceBpm=${referenceBpm.toStringAsFixed(1)} '
        'error=${bpmError.toStringAsFixed(1)} trueRetention=$ret halvedRemoval=$rem '
        'medianBpm=${medianMagnitudeBpm.toStringAsFixed(1)} transitionalRun=$trans';
  }
}

/// Scores a candidate's output against [fixture].
///
/// [acceptedMagnitudesMs] is the ordered series of final accepted RR
/// magnitudes (post merge/drop) — used only for the BPM derivations.
/// [perBeatOutcomes] must be parallel to `fixture.intervals` (one outcome
/// per original raw beat) — used for cluster retention/removal and the
/// transitional-run probe. Candidate-agnostic: works identically for the
/// Task 3 baseline, and for candidates 1 and 2.
CandidateScore score({
  required CalibrationFixture fixture,
  required List<int> acceptedMagnitudesMs,
  required List<BeatOutcome> perBeatOutcomes,
}) {
  assert(
    perBeatOutcomes.length == fixture.intervals.length,
    'perBeatOutcomes must have one entry per original raw beat',
  );

  final referenceBpm = fixture.referenceBpm;

  final meanMs = acceptedMagnitudesMs.isEmpty
      ? double.nan
      : acceptedMagnitudesMs.reduce((a, b) => a + b) /
          acceptedMagnitudesMs.length;
  final derivedBpm = acceptedMagnitudesMs.isEmpty
      ? 0
      : (60000 / meanMs).round();
  final bpmError = derivedBpm - referenceBpm;

  final medianMs = _median(acceptedMagnitudesMs);
  final medianMagnitudeBpm = medianMs == null ? double.nan : 60000 / medianMs;

  var trueTotal = 0;
  var trueRetained = 0;
  var halvedTotal = 0;
  var halvedRemoved = 0;
  for (var i = 0; i < fixture.intervals.length; i++) {
    final membership = classifyBeat(fixture.intervals[i].rrMs, fixture);
    final outcome = perBeatOutcomes[i];
    if (membership == ClusterMembership.trueCluster) {
      trueTotal++;
      if (outcome == BeatOutcome.emittedAsIs ||
          outcome == BeatOutcome.partOfMerge) {
        trueRetained++;
      }
    } else if (membership == ClusterMembership.halvedCluster) {
      halvedTotal++;
      if (outcome == BeatOutcome.partOfMerge ||
          outcome == BeatOutcome.dropped) {
        halvedRemoved++;
      }
    }
  }

  final transitionalRun =
      _probeTransitionalRun(fixture: fixture, perBeatOutcomes: perBeatOutcomes);

  return CandidateScore(
    fixtureName: fixture.name,
    referenceBpm: referenceBpm,
    derivedBpm: derivedBpm,
    bpmError: bpmError,
    medianMagnitudeBpm: medianMagnitudeBpm,
    trueClusterRetention: trueTotal == 0 ? null : trueRetained / trueTotal,
    halvedClusterRemoval: halvedTotal == 0 ? null : halvedRemoved / halvedTotal,
    transitionalRun: transitionalRun,
  );
}

double? _median(List<int> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid].toDouble();
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Scans [fixture]'s raw stream for the longest non-increasing run of >= 4
/// consecutive samples (ties tolerated — the rolling-RR emission stream
/// repeats a magnitude across adjacent rows, as in fixture 1's own
/// `708, 708`) within a 30ms `tMs` window whose last/first ratio is a
/// near-halving (<= 0.6) — the shape note 29 recorded as the median-flip
/// failure mode. Picks the longest such run, breaking ties by the lowest
/// ratio; this generically reproduces fixture 1's cited
/// `917→708→583→500→458` stretch (as `958,917,708,708,583,500,458`,
/// starting at its recorded ~5.7s) without hardcoding indices or timestamps.
/// Returns `found: false` if no qualifying run exists (fixture 2 has none
/// this extreme).
TransitionalRunResult _probeTransitionalRun({
  required CalibrationFixture fixture,
  required List<BeatOutcome> perBeatOutcomes,
}) {
  final intervals = fixture.intervals;
  List<int>? bestRun;
  int? bestStart;
  double bestRatio = double.infinity;

  for (var i = 0; i < intervals.length; i++) {
    final runIndices = <int>[i];
    for (var j = i + 1; j < intervals.length; j++) {
      if (intervals[j].tMs - intervals[i].tMs > 30) break;
      if (intervals[j].rrMs <= intervals[runIndices.last].rrMs) {
        runIndices.add(j);
      } else {
        break;
      }
    }
    if (runIndices.length < 4) continue;
    final firstMs = intervals[runIndices.first].rrMs;
    final lastMs = intervals[runIndices.last].rrMs;
    if (lastMs >= firstMs) continue; // flat run, not a genuine descent
    final ratio = lastMs / firstMs;
    if (ratio > 0.6) continue;
    final isLonger = bestRun == null || runIndices.length > bestRun.length;
    final isSameLenBetterRatio =
        bestRun != null && runIndices.length == bestRun.length && ratio < bestRatio;
    if (isLonger || isSameLenBetterRatio) {
      bestRun = runIndices;
      bestStart = i;
      bestRatio = ratio;
    }
  }

  if (bestRun == null) return const TransitionalRunResult(found: false);

  var staysOnTrueCluster = true;
  for (final idx in bestRun) {
    final membership = classifyBeat(intervals[idx].rrMs, fixture);
    if (membership == ClusterMembership.halvedCluster &&
        perBeatOutcomes[idx] == BeatOutcome.emittedAsIs) {
      staysOnTrueCluster = false;
      break;
    }
  }

  return TransitionalRunResult(
    found: true,
    startTMs: intervals[bestStart!].tMs,
    runMagnitudesMs: bestRun.map((i) => intervals[i].rrMs).toList(),
    staysOnTrueCluster: staysOnTrueCluster,
  );
}
