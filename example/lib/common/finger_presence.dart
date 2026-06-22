import 'package:flutter_ppg/flutter_ppg.dart';

/// Returns true when [rawIntensity] falls within the finger-presence band
/// defined by [config].
///
/// Mirrors the coverage discriminator previously inlined in
/// `auto_detect/coverage_detector.dart`:
///   `raw > cfg.fingerPresenceMin && raw < cfg.fingerPresenceMax`
///
/// Pure Dart — no Flutter or camera imports.
bool isFingerPresent(
  double rawIntensity, {
  PPGConfig config = const PPGConfig(),
}) =>
    rawIntensity > config.fingerPresenceMin &&
    rawIntensity < config.fingerPresenceMax;
