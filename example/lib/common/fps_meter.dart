/// Measures the sustained frame-arrival rate over a rolling time window.
///
/// Call [record] once per received [PPGSignal]; read [fps] to get the
/// rolling sustained FPS over the last [windowDuration].
///
/// This is independent of [PPGSignal.frameRate] — it measures what the
/// frame path actually delivers to the signal listener under the live screen,
/// which is the key harness metric for evaluating FPS degradation under UI load.
///
/// Pure Dart — no Flutter imports.
class FpsMeter {
  FpsMeter({this.windowDuration = const Duration(seconds: 2)});

  /// Width of the rolling measurement window.
  final Duration windowDuration;

  final List<DateTime> _timestamps = [];

  /// Record a single frame arrival at [now].
  void record(DateTime now) {
    _timestamps.add(now);
    // Prune timestamps that have fallen outside the rolling window.
    final cutoff = now.subtract(windowDuration);
    _timestamps.removeWhere((t) => t.isBefore(cutoff));
  }

  /// Rolling sustained FPS over [windowDuration].
  ///
  /// Returns 0.0 until at least two timestamps are within the window
  /// (a single timestamp yields no interval to divide by), and decays to 0.0
  /// when frames stall — stale entries are aged out against [DateTime.now] so
  /// the reading drops rather than freezing at the last non-zero value.
  double get fps {
    final now = DateTime.now();
    final cutoff = now.subtract(windowDuration);
    _timestamps.removeWhere((t) => t.isBefore(cutoff));
    if (_timestamps.length < 2) return 0.0;
    final spanUs =
        _timestamps.last.difference(_timestamps.first).inMicroseconds;
    if (spanUs == 0) return 0.0;
    // Number of intervals = count - 1; divide by span in seconds.
    return (_timestamps.length - 1) / (spanUs / 1e6);
  }
}
