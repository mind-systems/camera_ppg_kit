/// Signal-to-noise ratio threshold (dB) strictly above which a signal is
/// classified as [SignalQuality.good].
///
/// Provisional default mirrored from `flutter_ppg`'s own `PPGConfig.minGoodSNR`
/// (5.0 dB). Not yet tuned against real spike distributions — see spike note
/// 02. Tune here once real data is available; nothing else needs to change.
const double _goodSnrThreshold = 5.0;

/// Signal-to-noise ratio threshold (dB) strictly above which a signal is
/// classified as [SignalQuality.fair] (and at or below [_goodSnrThreshold]).
///
/// Provisional default mirrored from `flutter_ppg`'s own `PPGConfig.minFairSNR`
/// (0.0 dB). Not yet tuned against real spike distributions — see spike note
/// 02. Tune here once real data is available; nothing else needs to change.
const double _fairSnrThreshold = 0.0;

/// Coarse signal-quality band derived from the PPG signal's SNR.
///
/// Wraps `flutter_ppg`'s SQI/SNR so the session and host can gate on quality
/// without importing `flutter_ppg` types directly.
enum SignalQuality {
  /// High SNR, stable signal — suitable for accurate RR-interval extraction.
  good,

  /// Usable but noisier signal — RR intervals may be less reliable.
  fair,

  /// Low SNR, excessive noise, unstable signal, or no signal at all.
  poor;

  /// Maps an SNR value (dB) onto a [SignalQuality] band.
  ///
  /// Boundaries are strictly exclusive on the lower band, matching
  /// `flutter_ppg`'s own `SignalQualityAssessor.assessQuality`:
  /// `snr > _goodSnrThreshold` is [good], `snr > _fairSnrThreshold` (and at
  /// or below the good threshold) is [fair], everything else is [poor].
  /// This matters because `flutter_ppg`'s `calculateSNR` returns exactly
  /// `0.0` as a flatline/insufficient-data sentinel, which must land in
  /// [poor], not [fair]. Degenerate values — `NaN` or negative SNR — always
  /// yield [poor]: `NaN` comparisons are false in Dart so they fall through
  /// the chain below, and negative SNR is at or below the (non-negative)
  /// fair threshold.
  static SignalQuality fromSnr(double snr) {
    if (snr.isNaN) return SignalQuality.poor;
    if (snr > _goodSnrThreshold) return SignalQuality.good;
    if (snr > _fairSnrThreshold) return SignalQuality.fair;
    return SignalQuality.poor;
  }
}
