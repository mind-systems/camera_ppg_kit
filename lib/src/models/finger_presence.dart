/// Raw red-channel intensity floor, at or below which no finger is
/// considered present (too dark).
///
/// Provisional default mirrored from `flutter_ppg`'s own
/// `PPGConfig.fingerPresenceMin` (30.0). Not yet tuned against real spike
/// distributions — see spike note 02. Tune here once real data is available;
/// nothing else needs to change.
const double _presenceMin = 30.0;

/// Raw red-channel intensity ceiling, at or above which the reading is
/// classified as over-bright (direct flash into the lens, finger not
/// covering) rather than present.
///
/// Provisional default mirrored from `flutter_ppg`'s own
/// `PPGConfig.fingerPresenceMax` (250.0). Not yet tuned against real spike
/// distributions — see spike note 02. Tune here once real data is available;
/// nothing else needs to change.
const double _overBrightMax = 250.0;

/// Whether a finger is covering the camera lens + torch, derived from the
/// raw PPG signal's red-channel intensity.
///
/// A single `bool` cannot separate "too dark" from "too bright" — both read
/// as "not present" — so this is a three-way classification instead.
enum FingerPresence {
  /// Intensity is in-band: a finger is covering the lens and torch.
  present,

  /// Intensity is at or below the dark floor: no finger detected.
  absent,

  /// Intensity is at or above the over-bright ceiling: direct flash into the
  /// lens (finger not covering it). Must be distinguished from [absent] so
  /// the UI can guide "press your finger over both the lens and the flash",
  /// and so auto-detect's round-trip treats it the same as "not covered"
  /// when deciding to move to the next sensor.
  overBright;

  /// Classifies finger presence from the raw red-channel intensity reported
  /// by `flutter_ppg`'s `PPGSignal.rawIntensity`.
  ///
  /// Mirrors `flutter_ppg`'s own `SignalQualityAssessor.isFingerPresent`
  /// band exactly, using strict comparisons: `rawIntensity` at or below
  /// [_presenceMin] is [absent]; at or above [_overBrightMax] is
  /// [overBright]; strictly between the two is [present].
  ///
  /// `NaN` fails all numeric comparisons in Dart, so without a guard it
  /// would fall through to [present]. A `NaN` reading means no valid
  /// intensity was captured at all, so it is treated as [absent] instead.
  static FingerPresence fromRawIntensity(double rawIntensity) {
    if (rawIntensity.isNaN) return FingerPresence.absent;
    if (rawIntensity <= _presenceMin) return FingerPresence.absent;
    if (rawIntensity >= _overBrightMax) return FingerPresence.overBright;
    return FingerPresence.present;
  }
}
