import '../models/rr_interval.dart';

/// Pure-Dart physiological acceptance gate for beat-to-beat [RrInterval]s.
///
/// This layers on top of `flutter_ppg`'s own window-statistic outlier
/// filter — it does not replace it. It exists to catch peak-halving
/// artifacts that leak past that filter: a hard lower bound (no upper
/// bound, so extreme bradycardia survives) plus a rolling-median
/// consistency check, with a cold-start grace period while the median
/// seeds. Ported from `neiry_kit`'s `PpgPeakDetector._gate` (see
/// `ppg_peak_detector.dart`), stripped of all peak-detection state since
/// `flutter_ppg` owns that here.
///
/// Stateful — one instance per measurement, never per beat. Call [evaluate]
/// for every trusted interval in order, and [reset] between measurements so
/// the cold-start grace period re-arms.
class RrAcceptance {
  RrAcceptance({
    this.minRrMs = 300,
    this.consistencyThreshold = 0.40,
    this.coldStartBeats = 3,
    this.medianWindow = 5,
  });

  /// Hard lower bound on RR intervals (ms). Below this → artifact.
  /// Corresponds to ~200 BPM, the physiological ceiling for sustained rhythm.
  final int minRrMs;

  /// Maximum fractional deviation from the rolling median before an interval
  /// is flagged as an artifact. 0.40 = 40%.
  final double consistencyThreshold;

  /// Number of initial intervals accepted without the consistency check.
  /// Seeds the rolling median before gating begins.
  final int coldStartBeats;

  /// Size of the rolling window used to compute the consistency median.
  final int medianWindow;

  /// Rolling history of non-artifact RR intervals for the consistency median.
  final List<int> _rrHistory = [];

  /// Evaluates [rr] against the gate and returns a copy with [RrInterval.isArtifact]
  /// set accordingly.
  ///
  /// Only non-artifact beats are appended to the rolling history (capped at
  /// [medianWindow], evicting the oldest), so artifacts never poison the
  /// median.
  RrInterval evaluate(RrInterval rr) {
    final isArtifact = _gate(rr.intervalMs);

    if (!isArtifact) {
      _rrHistory.add(rr.intervalMs);
      if (_rrHistory.length > medianWindow) {
        _rrHistory.removeAt(0);
      }
    }

    return RrInterval(
      intervalMs: rr.intervalMs,
      timestamp: rr.timestamp,
      isArtifact: isArtifact,
    );
  }

  /// Clears the rolling history so the cold-start grace period re-arms on
  /// the next measurement.
  void reset() {
    _rrHistory.clear();
  }

  /// Returns `true` when [rrMs] should be flagged as an artifact.
  ///
  /// Hard lower-bound gate → consistency filter against rolling median.
  /// No upper bound is applied: extreme bradycardia produces valid
  /// intervals > 3000 ms.
  bool _gate(int rrMs) {
    // Hard lower bound: physically impossible heart rate.
    if (rrMs < minRrMs) return true;

    // Cold-start: accept first [coldStartBeats] intervals unconditionally to
    // seed the median at any HR (including extreme bradycardia).
    if (_rrHistory.length < coldStartBeats) return false;

    // Consistency filter: flag large deviations from the rolling median.
    final sorted = [..._rrHistory]..sort();
    final median = sorted[sorted.length ~/ 2].toDouble();
    return (rrMs - median).abs() / median > consistencyThreshold;
  }
}
