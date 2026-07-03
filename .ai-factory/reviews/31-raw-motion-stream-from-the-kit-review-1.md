# Code Review: Raw motion stream from the kit

**Plan:** `.ai-factory/plans/31-raw-motion-stream-from-the-kit.md`
**Files reviewed (in full):** `lib/src/models/motion_sample.dart` (new), `lib/src/motion/motion_reader.dart` (new), `lib/src/api/camera_ppg_session.dart` (modified), `lib/camera_ppg_kit.dart` (modified), `docs/measurement.md` (modified), `pubspec.yaml` / `example/pubspec.lock` (modified), `.ai-factory/ARCHITECTURE.md` (modified)
**Risk Level:** 🟢 Low

## Summary

The implementation matches the plan precisely and upholds every hard guard from spec note 43: full decoupling from the PPG signal path (`_dehalving`/`_acceptance`/`_policy`/`_frameIsolate`, `_onSignal` untouched), session-scoped emission (started in the synchronous `lockedAndStreaming = true` block, torn down in `_release()`), raw passthrough (no metric, no rate cap), and no native code. The teardown discipline the plan review insisted on is present on both sides — `MotionReader.dispose()` closes its own `samples` controller, and the session cancels the dedicated `_motionSub` before disposing the reader, so no forwarding subscription dangles across `start()`/`stop()` cycles. Barrel discipline is correct (model exported, `MotionReader`/`src/motion/` internal). No wrapped third-party type crosses the barrel.

One robustness gap is worth addressing before this ships to varied hardware.

## Findings

### 1. Sensor subscriptions have no `onError` handler — unhandled stream error on gyroscope-less devices (Low–Medium)

`lib/src/motion/motion_reader.dart:499` and `:507` — both `gyroscopeEventStream(...).listen(...)` and `accelerometerEventStream(...).listen(...)` are subscribed with a data callback only and **no `onError`**:

```dart
_gyroSub = gyroscopeEventStream(
  samplingPeriod: SensorInterval.uiInterval,
).listen((event) { ... });      // no onError
```

`sensors_plus` surfaces a missing/failed hardware sensor as an **error event on the stream** (the platform `EventChannel` forwards a `PlatformException`), not as a silent no-op. Gyroscopes are genuinely absent on some low-end Android phones, many tablets, and most emulators. On such a device this subscription emits an error with no handler attached, which becomes an **unhandled async error** — routed to `FlutterError.onError`/the zone error handler, logged (and, depending on the host's zone configuration, potentially fatal). The accelerometer stream can fail the same way, though far more rarely.

This is inconsistent with the kit's defensive posture everywhere else in this same file — `setExposureMode`/`setFocusMode`, `stopImageStream`, `setFlashMode(off)`, and `availableCameras()` are all wrapped so hardware variance degrades gracefully rather than throwing across the boundary. The frame-isolate signal subscription itself carries an explicit `onError` (`camera_ppg_session.dart:377-382`). The motion reader should match that.

**Failure scenario:** run a measurement on a device or emulator without a gyroscope → `gyroscopeEventStream` emits a `PlatformException` → no `onError` → unhandled zone error surfaces (log spam at minimum; app-level crash if the host runs a strict `runZonedGuarded`). The RR/camera path is unaffected (the streams are independent), but the kit emits an error it is designed to swallow.

**Fix:** add an `onError` to each `.listen(...)` that logs and drops (mirroring the frame-isolate subscription and `nlog` usage elsewhere), e.g.:

```dart
).listen((event) { ... }, onError: (Object e, StackTrace st) {
  nlog('gyroscope stream error', error: e, stackTrace: st);
});
```

`nlog` lives in `src/util/nlog.dart`; importing it keeps `src/motion/` within its stated purity contract (it depends on `src/models/` — `util` logging is used across the pure `processing/` layer too, e.g. it is already imported by `camera_ppg_session.dart`). If keeping `src/motion/` free of the `util` import is preferred, an inline swallow (`onError: (_, __) {}`) is still strictly better than none — the point is that a gyroscope-less device must not raise an unhandled error. Consider also gating accel emission on gyro availability only if a later phase wants it; for now, swallowing is sufficient and matches the raw-passthrough guard.

## Non-blocking observations (no action required)

- **Broadcast-vs-buffer ordering.** `MotionReader.start()` is called before `_motionSub = motionReader.samples.listen(...)` (`camera_ppg_session.dart:412-421`). `samples` is a broadcast controller, so any event emitted in the gap would be dropped — but sensor events arrive on later event-loop turns, never synchronously within that gap, so nothing is lost in practice. Fine as written.
- **`event.timestamp` is `DateTime`.** `sensors_plus` 7.1.0 `AccelerometerEvent` carries a `DateTime timestamp`, so `timestamp: event.timestamp` type-checks against `MotionSample.timestamp` and the model doc's "device timestamp" wording is accurate. No monotonic-vs-wall-clock trap introduced; the doc carries the same caveat as `rr_interval.dart`.
- **No sensor permissions needed.** Accelerometer/gyroscope require no iOS usage-description key and no Android runtime permission (only activity/step counting would). No manifest/Info.plist change is missing.
- **Idempotent teardown verified.** `MotionReader.dispose()` nulls both subs before awaiting cancel and guards the controller close with `!isClosed`; `_release()` captures-and-nulls `_motionReader`/`_motionSub` before its first `await` and null-guards both. Double `_release()` / `dispose()` after `dispose()` are safe. `_motionController.close()` is correctly placed after `await _release()` in `dispose()`, so the `!_motionController.isClosed` forwarding guard can never add-after-close.
- **Decoupling confirmed by reading `_onSignal` in full.** Nothing in the signal path references motion; `motionStream` is never read back into quality or the acceptance gate. Matches the spec's hard guard.

## Verdict

Faithful, well-isolated implementation. The single finding is a robustness gap (missing `onError` on hardware-dependent sensor streams), not a defect on typical target hardware — a phone held with a finger on the camera almost always has both sensors. Addressing it brings the motion path in line with the kit's own "no exceptions escape the boundary" discipline and protects gyroscope-less devices/emulators.
