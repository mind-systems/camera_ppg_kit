# Signal processing

`flutter_ppg` produces the raw RR intervals (red-channel extraction → bandpass → peak detection → RR). On top of that stream the kit runs two Dart-side stages before a beat reaches `rrStream`. The frame path itself runs in a background isolate (`frame_isolate.dart`) so heavy UI work on the host screen cannot starve it.

The order is fixed:

```
flutter_ppg intervals → de-halving → acceptance gate → rrStream
```

## De-halving (`rr_dehalving.dart`)

A camera-PPG peak detector can fire twice per beat — on the dicrotic notch or a harmonic — producing intervals at roughly **half** the true RR. Left unhandled, these halved beats outnumber the real ones, so a downstream median-based filter latches onto the halved population and rejects the true beats.

The de-halving stage removes them at the source. It tracks the dominant beat period adaptively and, when two consecutive short intervals sum to about that tracked period, merges them back into one beat. The threshold is a **fraction of the tracked period**, not a fixed millisecond floor, so it scales with the actual heart rate and never caps the detectable range.

Defaults: `bootstrapBeats 3`, `shortFraction 0.75`, `pairTolerance 0.30`, `trackerAlpha 0.1`, `fullBeatTolerance 0.40`.

## Acceptance gate (`rr_acceptance.dart`)

The de-halved beats pass through a physiological gate that sets `RrInterval.isArtifact`:

- a hard lower bound (`minRrMs 300`) — below it is physically impossible and flagged;
- no upper bound — extreme bradycardia stays valid;
- a rolling-median consistency check — a beat deviating more than `consistencyThreshold` (0.40) from the median of the recent window (`medianWindow 5`) is flagged;
- a cold-start grace of `coldStartBeats` (3) so the median seeds at any rate before gating begins.

Because de-halving runs first, the gate's median only ever sees de-halved beats, so it stays anchored to the true rhythm.

## Session policy (`session_policy.dart`)

The policy drives `MeasurementState` from the same signal: a warm-up window (`5 s`) before RR is trusted, and an SQI + finger-presence floor below which the state drops to `poorSignal` and RR stops flowing. A silence window (`3 s`) bounds how long a gap is tolerated before the state falls back.
