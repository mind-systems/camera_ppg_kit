# Code Review: Calibration screen (pure consumer, 60s countdown)

**Scope reviewed:** `example/lib/screens/calibration_screen.dart` (new), `example/lib/main.dart` (shell wiring). Read in full alongside `calibration_recorder.dart`, `camera_ppg_session.dart` (stream emission cadence), `stream_providers.dart`, `session_config_provider.dart`, `source_screen.dart`, `kit_api_tab.dart`, and notes 20/21/22.

**Risk level:** 🟡 Low–Medium — one spec-deviation with a plausible functional impact on the recorded calibration data; no crashers.

---

## Findings

### 1. [Medium] The countdown (and the whole screen) rebuilds at camera **frame rate** during recording — violates note 21's "countdown … never rebuilt on RR ticks" and the FPS-load-bearing NFR, degrading the very data being calibrated

`CalibrationScreen.build()` reads three live streams at the top level:

```dart
Widget _bpmSection()        => ref.watch(bpmProvider) ...
Widget _qualityAndStateRow()=> ref.watch(qualityProvider).value ; ref.watch(stateProvider) ...
```

Because these `ref.watch` calls sit in helper methods invoked from `build()`, they register the **top-level widget element** as a dependent of each provider — so any emission rebuilds the entire `ListView`, including `_countdown()` and the record buttons.

Emission cadence is not per-beat — it is **per processed frame**. `camera_ppg_session.dart:581-583` adds to `_qualityController` on *every* signal tick (the comment: "Quality/finger-presence/debug streams flow in every state … continuously"), i.e. at ~24–30 FPS. So during the 60 s recording window the full screen tree rebuilds ~24–30×/second.

This contradicts spec note 21 explicitly:

> Large **countdown** … driven only by the 1 Hz timer — **never rebuilt on RR ticks**.
> Display (quiet — no charts, no animation; **FPS is load-bearing**, note 03 / NFR)

Why it matters here specifically (more than in `kit_api_tab.dart`, which shares the pattern): this is the **recording** surface. Note 13 already established that `startImageStream`'s callback fires on the UI isolate and that sustained UI-isolate load drops FPS (30 → 20 in the isolate proof). Adding a frame-rate full-tree `setState` on top, during the exact 60 s window whose fidelity is the whole point, is additive UI-isolate load that can starve the frame stream and corrupt the RR series being written to the calibration file — the failure class the pure-consumer reframe and the quiet-screen constraint were meant to remove.

**Failure scenario:** source running, tester presses Start recording, holds still for 60 s. Throughout the window the UI isolate rebuilds the ListView at frame rate; FPS sags, RR intervals quantize/halve more, and the saved `calib_*.json` is measurably noisier than a run observed from the (quiet) Source screen — the calibration reference is taken against degraded data.

**Fix:** isolate the stream-driven widgets so the countdown/buttons are not dependents of the frame-rate providers. Wrap each live read in its own `Consumer` (or a small `ConsumerWidget`) — e.g. `Consumer(builder: (_, ref, __) => Chip(... ref.watch(qualityProvider) ...))` for the SQI/state row and BPM — so only those leaves rebuild on frame ticks, while `_countdown()` rebuilds only from the 1 Hz `_tickTimer`'s `setState`. This is the concrete realization of note 21's "driven only by the 1 Hz timer."

---

## Minor / non-blocking observations

- **Window can read 59 instead of 60 (cosmetic).** At t≈60 s the one-shot `_finishTimer` and the 60th `_tickTimer` fire in unspecified order; if `_finish()` runs first, `_windowSeconds = 60 - _remainingSeconds` yields 59. Note 21 specifies `windowSeconds ≈ 60`, so within tolerance — no fix required.

- **`_save()` has an unguarded `await _recorder.save(...)`.** `save()` does `getExternalStorageDirectory()` then `baseDir!` (`calibration_recorder.dart:164-165`); on a platform where that returns null (iOS) or on any IO error, the future throws and the tap handler surfaces an unhandled async exception with no user feedback. The kit's calibration export is Android-scoped by design (note 20), so this is out of this milestone's target, but a `try/catch` that shows the error in-screen would make the dev instrument fail visibly rather than silently. Optional.

- **`dispose()` does not call `_recorder.stop()`.** Harmless — the screen only disposes on app teardown (IndexedStack keeps it mounted), and the service provider's `onDispose` tears down the source controllers, so the recorder's three subscriptions are collected. Adding `_recorder.stop()` would be tidier symmetry but is not a correctness issue.

- **Re-Save after a completed run writes a second file.** Save stays enabled (`_recorded == true`) after a successful save, so a second tap produces another `calib_*.json`. This matches the recorder's documented "each call writes a fresh file" contract — noted, not a defect.

---

## Verified correct

- Pure-consumer contract honoured: no `startMeasurement`/`stopMeasurement`, no `CameraController`/torch, start-gate keyed on the local `_recording` flag, record-precondition on `service.isMeasuring` (`camera_ppg_service.dart:72`). ✓
- `_recorder.start(service, config.acceptance, config.policy)` matches the committed signature; config read from the shared `sessionConfigProvider`, keeping the JSON honest. ✓
- `_finish()` is idempotent (`if (!_recording) return`), cancels+nulls both timers, and is shared by the auto-timer and manual Stop; `_windowSeconds` captures actual elapsed for a short manual stop. ✓
- Empty-file guard (return without recording when `!isMeasuring`) and the `if (!mounted) return;` after `await _recorder.save(...)` are correctly placed. ✓
- `Save` gated on `_recorded`, which is only reachable after a real `start()` → no `StateError` path into `recorder.save()`. ✓
- Shell wiring: `calibration` inserted before `raw`; `_screenFor`, `children`, `destinations`, `selectedIndex` all iterate `_Branch.values`, and the Raw-exclusivity hook keys off `_Branch.raw` (enum, not index) — index-shift-safe, Source Start/Stop and the Raw stop-hook untouched. ✓
- Imports are all used; `MeasurementState`/`SignalQuality` switches are exhaustive. ✓
