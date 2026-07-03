# Raw motion (accelerometer + gyroscope) stream from the kit

**Date:** 2026-07-03
**Source:** conversation context (standalone stillness/motion data, decoupled from signal quality)

## Why here (in this kit)

The kit is the one place that reliably knows **the phone is held in the user's hand**:
during a measurement the finger is on the lens. Outside a measurement the phone could be
on a table or in a pocket, so a motion metric is meaningless there. So the kit is the
right emitter of raw device-motion — but as an **orthogonal data channel**, not a
signal-quality input. Coupling motion to PPG quality would need its own reference study;
that is explicitly out of scope. Raw samples out, interpretation is the consumer's.

## Current state

`CameraPpgSession` fans out `rrStream`/`qualityStream`/`stateStream`/`fingerPresenceStream`
/`debugSignalStream`/`resolvedCameraStream` from broadcast controllers opened in the ctor
and closed only in `dispose()`. No sensor access; `sensors_plus` is not a dependency. The
frame path (camera → `FrameIsolate` → `flutter_ppg` → `_dehalving` → `_acceptance` →
streams) is entirely separate from device sensors.

## The change

- Add `sensors_plus` via `flutter pub add sensors_plus` (never hand-edit pubspec).
- New model `lib/src/models/motion_sample.dart`: `MotionSample { double accelX, accelY,
  accelZ; double gyroX, gyroY, gyroZ; DateTime timestamp }` — raw values (accel m/s²
  incl. gravity or userAccelerometer — pick one and document; gyro rad/s). Pure Dart,
  barrel-exported.
- New `lib/src/motion/motion_reader.dart`: subscribes `accelerometerEventStream` +
  `gyroscopeEventStream` (start at `SensorInterval.uiInterval` — provisional, not tuned)
  and emits a combined `MotionSample` on each accelerometer tick carrying that tick's
  accel + the last-seen gyro (accel is the motion cadence; gyro sampled-and-held). Pure
  sensor plumbing — no metric, no thresholds, no stillness verdict.
- `CameraPpgSession`: a `_motionController` (broadcast, opened in ctor, closed in
  `dispose()`) + `Stream<MotionSample> get motionStream`. Start the `MotionReader` when a
  sensor locks (same point `_stopwatch`/policy start) and stop it in `_release()`, so the
  stream is active exactly while a measurement runs. **Decoupled**: the reader never
  touches `_dehalving`/`_acceptance`/`_policy`/the frame isolate, and nothing reads
  `motionStream` back into quality or the gate.

## Public surface

`motionStream` + `MotionSample` are exported from the barrel — a new public stream,
distinct from the RR/quality streams. Add it to `docs/measurement.md`'s streams table
(raw accel+gyro, measurement-active only, decoupled from the PPG signal).

## Guards

- Raw passthrough only — no stillness index, no rate cap logic in the kit (rate is
  observed in the example, note 44; throttling is a later observation-driven follow-up).
- Full decoupling from PPG quality — this must never feed `RrAcceptance`/`SessionPolicy`.
- Session-scoped: emit only while a measurement is active (meaningful only when the
  finger is on / phone is held); silent otherwise.
- No native code — `sensors_plus` is pure-Dart cross-platform.

## Verify

- During a measurement, `motionStream` emits `MotionSample`s with live accel/gyro;
  stopping the session stops emission. RR/SQI/gate behavior is byte-for-byte unchanged
  (nothing in the frame path touched). `flutter test` green.
