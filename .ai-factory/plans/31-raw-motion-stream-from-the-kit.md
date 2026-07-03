# Plan: Raw motion stream from the kit

## Context
Add a session-scoped `motionStream` that emits raw accelerometer + gyroscope `MotionSample`s while a measurement is running, fully decoupled from the PPG signal/quality path (no metric, no rate cap, no native code).

## Settings
- Testing: no
- Logging: minimal
- Docs: yes (streams table only)

## Tasks

### Phase 1: Dependency + model

- [x] **Task 1: Add `sensors_plus` dependency**
  Files: `pubspec.yaml` (via CLI — do not hand-edit)
  Run `flutter pub add sensors_plus` from the kit root. This adds the pure-Dart cross-platform sensor package; no native code changes. Verify it lands in `pubspec.yaml` dependencies.

- [x] **Task 2: Add `MotionSample` model** (depends on Task 1)
  Files: `lib/src/models/motion_sample.dart`
  Pure-Dart `@immutable` value type mirroring the shape of `lib/src/models/rr_interval.dart` (import `package:flutter/foundation.dart`, const ctor with `required` named params, doc comments). Fields: `double accelX, accelY, accelZ; double gyroX, gyroY, gyroZ; DateTime timestamp`. In the class doc, state the units and semantics explicitly: accelerometer values are **raw `accelerometerEventStream` readings (m/s², gravity included)**, gyro is rad/s. For `timestamp`, keep the doc wording consistent with the source chosen in Task 3: it is the accelerometer event's `event.timestamp` (device time). If the implementer falls back to `DateTime.now()` in Task 3 instead, the doc must say "capture time (wall-clock)" — not "device time" — to avoid the monotonic-vs-wall-clock trap already flagged in `rr_interval.dart`. No metric, no derived fields. Depends on nothing else in the kit.

### Phase 2: Reader

- [x] **Task 3: Add `MotionReader`** (depends on Task 2)
  Files: `lib/src/motion/motion_reader.dart`
  New `src/motion/` folder (pure Dart plumbing, no `camera`/`flutter_ppg`/channel imports — follows the `src/processing/` purity rule minus the models dependency). `MotionReader` subscribes `accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)` and `gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval)` from `package:sensors_plus/sensors_plus.dart`. Hold the last-seen gyro event; on each **accelerometer** tick emit a combined `MotionSample` carrying that tick's accel + the last-seen gyro (accel drives the cadence; gyro is sampled-and-held — default gyro components to `0.0` until the first gyro event arrives). Set `timestamp` from the accel event's `event.timestamp` (`sensors_plus` events carry a `DateTime timestamp`) — device time, matching Task 2's model doc; only fall back to `DateTime.now()` if that field is unavailable, and if so soften the model doc per Task 2.

  Surface + lifecycle (pin this to satisfy the kit's idempotent, no-stranded-handles invariant):
  - Expose a broadcast `Stream<MotionSample> get samples` backed by an internal `StreamController<MotionSample>.broadcast()`.
  - `void start()` — **synchronous**, opens both accel/gyro subscriptions via `stream.listen(...)`. It must return `void` (not `Future`), because Task 4 constructs and starts the reader inside `start()`'s synchronous `lockedAndStreaming = true` block, which today has no `await`s and no `stale()` window; introducing an `await` there would open a new staleness gap.
  - `Future<void> dispose()` — idempotent: cancel both accel/gyro subscriptions **and close the `samples` `StreamController`**, so any downstream forwarding subscription completes rather than being left subscribed to a controller that never emits again.

  Raw passthrough only — no thresholds, no stillness verdict, no rate cap.

### Phase 3: Session wiring + surface

- [x] **Task 4: Wire `MotionReader` into `CameraPpgSession`** (depends on Task 3)
  Files: `lib/src/api/camera_ppg_session.dart`
  - Import `../models/motion_sample.dart` and `../motion/motion_reader.dart`.
  - Add a broadcast `_motionController = StreamController<MotionSample>.broadcast()` opened in the constructor initializer list (alongside the other controllers) and closed in `dispose()` by adding `await _motionController.close();` **in the same block as the existing `close()` calls** (lines 448–453). Ordering is already correct: `dispose()` runs `await _release()` (which tears the reader + forwarding sub down) *before* the `close()` block, so the add-after-close guard below can never fire late.
  - Add two handle fields: `MotionReader? _motionReader` and a dedicated forwarding-subscription field `StreamSubscription<MotionSample>? _motionSub`. Add `Stream<MotionSample> get motionStream => _motionController.stream;` with a doc comment noting it is raw, measurement-active-only, and decoupled from the PPG signal.
  - **Start** the reader at the same point a sensor locks — right where `_stopwatch..reset()..start()` / `_setState(MeasurementState.warmup)` run in `start()` (the synchronous `lockedAndStreaming = true` block). Construct a `MotionReader`, assign it to `_motionReader`, call its synchronous `start()`, and forward its `samples` into `_motionController` by assigning `_motionSub = reader.samples.listen((s) { if (!_motionController.isClosed) _motionController.add(s); })`. Do not `await` anything here — keep the block synchronous so no `stale()` gap is introduced.
  - **Stop** the reader in `_release()`: capture-and-null both `_motionReader` and `_motionSub` alongside the other handles (before any `await`, matching the atomic-capture discipline the rest of `_release()` uses), then `await _motionSub?.cancel()` and `await _motionReader?.dispose()`. `MotionReader.dispose()` also closes its `samples` controller (Task 3), so no forwarding subscription is ever left dangling across `start()`/`stop()` cycles — this upholds the kit's "release is ordered and idempotent, no stranded handles" invariant. Keep the reader out of the shared `_tearDownHandles` camera ordering — it is independent; tear it down directly in `_release()`.
  - **Decoupling guard:** the reader must never touch `_dehalving`/`_acceptance`/`_policy`/`_frameIsolate`, and nothing may read `motionStream` back into quality or the gate. Do not add motion to `_onSignal`.

- [x] **Task 5: Export `MotionSample` + `motionStream` from the barrel** (depends on Task 4)
  Files: `lib/camera_ppg_kit.dart`
  Add `export 'src/models/motion_sample.dart';` to the frozen consumer surface export block (`motionStream` is reached via the already-exported `CameraPpgSession`). `MotionReader` and `src/motion/` stay internal — do **not** export the reader. Add a brief comment noting this is a new public stream distinct from RR/quality.

- [x] **Task 6: Document `motionStream` in the streams table** (depends on Task 5)
  Files: `docs/measurement.md`
  Add a row to the Streams table: `motionStream` carries `MotionSample { accelX/Y/Z, gyroX/Y/Z, timestamp }` — raw accel (m/s², gravity included) + gyro (rad/s), emitted only while a measurement is active, decoupled from the PPG signal (not a quality input). One row; keep the existing table style.

## Commit Plan
- **Commit 1** (after tasks 1-2): "Add sensors_plus dependency and MotionSample model"
- **Commit 2** (after tasks 3-4): "Add MotionReader and wire session-scoped motionStream"
- **Commit 3** (after tasks 5-6): "Export motionStream on the barrel and document it"
