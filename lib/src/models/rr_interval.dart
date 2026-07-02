import 'package:flutter/foundation.dart';

/// A single beat-to-beat interval derived from the raw PPG signal.
///
/// [timestamp] is the wall-clock [DateTime] of the later peak — the one that
/// ends this interval. It is decoded from the device timestamp, not a monotonic
/// clock. Do not compare it to monotonic time sources such as [Stopwatch] or
/// [DateTime.now] drift measurements.
///
/// [isArtifact] is `true` when the interval was flagged as a likely motion
/// artifact by the physiological gate or consistency filter. Consumers must not
/// use artifact ticks for animation or HRV calculation; hold the last valid
/// interval or fall back to a timer instead.
@immutable
class RrInterval {
  const RrInterval({
    required this.intervalMs,
    required this.timestamp,
    this.isArtifact = false,
  });

  /// Duration between this beat and the previous one, in milliseconds.
  final int intervalMs;

  /// Timestamp of the beat that ended this interval (the later peak).
  final DateTime timestamp;

  /// True when this interval was flagged as a likely artifact.
  ///
  /// Do not use artifact ticks for animation or HRV calculation.
  final bool isArtifact;
}
