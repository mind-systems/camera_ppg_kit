# Data Value Types — RrInterval + SignalQuality

**Date:** 2026-06-21
**Source:** `neiry_kit/lib/src/models/rr_interval.dart`; `flutter_ppg` `PPGSignal` fields

## Key Findings

- The kit's primary output is RR intervals. Keeping `RrInterval` **shape-identical to neiry's `RRInterval`** (`intervalMs:int`, `timestamp:DateTime`, `isArtifact:bool`) is the linchpin: it lets `mind_mobile`'s single RR-interval source contract consume camera and worn sources interchangeably.
- `flutter_ppg`'s `PPGSignal` exposes RR intervals (ms), SNR, and an SQI (Good/Fair/Poor). `SignalQuality` wraps SQI + SNR so the session and the host can gate on quality without importing `flutter_ppg` types.
- These two types are the data path and are independently shippable from the control/error types (note 06) — hence a separate atomic task per the gate.

## Details

### `lib/src/models/rr_interval.dart`

Port neiry's class verbatim in spirit:

```dart
@immutable
class RrInterval {
  const RrInterval({required this.intervalMs, required this.timestamp, this.isArtifact = false});
  final int intervalMs;      // beat-to-beat duration, ms
  final DateTime timestamp;  // wall-clock of the later peak
  final bool isArtifact;     // flagged by the acceptance gate (Phase 8)
}
```

Doc the same caveats as neiry: `timestamp` is not monotonic; never use `isArtifact: true` ticks for animation or HRV.

### `lib/src/models/signal_quality.dart`

```dart
enum SignalQuality { good, fair, poor }
```

Plus a wrapper or factory carrying SNR: `SignalQuality.fromSnr(double snr)` mapping `flutter_ppg`'s SQI/SNR onto the enum. Keep the SNR thresholds as named constants so they are tunable once the spike (note 02) reports real distributions.

### Export + tests

Export both from `lib/camera_ppg_kit.dart`. `test/models_test.dart`: `RrInterval` construction/immutability; `fromSnr` returns the right band at threshold boundaries; (if a `fromMap` is added for channel transport) round-trip.

### Guards

- Do **not** add BPM or HRV fields — those are the consumer's to derive; the kit emits intervals + quality only.
- Keep field names matching neiry (`intervalMs`, not `rrMs`/`durationMs`) so the host contract is literally the same shape.
