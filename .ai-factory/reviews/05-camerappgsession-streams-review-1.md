# Code Review: CameraPpgSession + streams (05)

**Reviewed:** `git diff HEAD` — `lib/src/api/camera_ppg_session.dart` (new), `lib/src/api/rr_diff.dart` (new), `lib/src/util/nlog.dart` (new), `test/camera_ppg_session_rr_conversion_test.dart` (new), `lib/camera_ppg_kit.dart` (modified).
**Read in full:** all of the above + `lib/src/models/*` (rr_interval, signal_quality, measurement_state, finger_presence, camera_ppg_error), `flutter_ppg` 0.2.4 `flutter_ppg_service.dart` / `ppg_signal.dart`, and the example ports (`measurement_runner.dart`, `coverage_detector.dart`).
**Overall:** 🟢 Strong. The implementation faithfully ports the spike-proven example, honours the barrel boundary (`hide SignalQuality`, no `flutter_ppg`/`camera` type in any public signature), and correctly implements the round-1/2 plan fixes (`_running` cleared on every failure path via the `finally`+`lockedAndStreaming` mechanism; close-before-cancel teardown; `stop()`/`_release()` present alongside `start()`). Findings below are one real lifecycle gap and two accepted-scope caveats — none block, but Finding 1 is a genuine reachable defect.

---

## Findings

### 1. (Medium, correctness/lifecycle) `stop()` / `dispose()` called during an in-flight `start()` strands the camera + torch and desyncs `_running`

`start()` sets `_running = true` synchronously, then performs several `await`s (`_enumerateRearCameras()`, `_lockCoveredCamera()` ≈ 1.1 s/sensor, `initialize()`, `setFlashMode`, …). `stop()` → `_release()` (and `dispose()`) can run during any of those suspension points. `_release()` captures/nulls the handles (all still `null` during the probe phase), sets `_running = false`, and sets state `idle`. But `start()` then **resumes** past its awaits and:

- creates `_controller`, calls `initialize()` + `setFlashMode(torch)`, starts the image stream, and assigns `_service`/`_sub`;
- sets `lockedAndStreaming = true`, so its `finally` does **not** call `_release()`;
- leaves the session streaming with the **torch on** even though `stop()` "completed", and with `_running == false` while actually running.

Consequences:
- **Torch stranded on after `stop()`** — precisely the failure mode the teardown invariant exists to prevent.
- **Double-start guard defeated:** a subsequent `start()` sees `_running == false` and opens a *second* `CameraController` while the first is live → "camera already in use" / leaked controller.
- **`dispose()` variant:** `start()`'s `_disposed` check passes before the await; if `dispose()` runs mid-flight it closes the four broadcast controllers, then `start()` resumes and acquires a camera whose frames feed now-closed controllers (the `isClosed` guards in `_onSignal` prevent the crash, but the controller/service/torch leak remains).

**Repro:** `final s = CameraPpgSession(); s.start(); await s.stop();` (do not await `start()`), on a device where a sensor is covered → torch stays on, `s.start()` again opens a second controller.

**Fix options:** guard `start()` against teardown across its awaits — e.g. a monotonically-increasing generation/epoch counter captured at entry and re-checked after each `await` (bail + `_release()` if it changed), or have `_release()` set a `_releasing`/epoch flag that `start()` checks after each await before acquiring/assigning handles. The plan scoped only the *double-start* guard and defers full lifecycle robustness to Phase 9 (note 17), so this may be intended for that milestone — but it is reachable today and should at minimum be recorded as a known gap rather than silently shipped.

### 2. (Low, accepted scope) `diffNewIntervals` can re-emit already-emitted intervals as duplicates when the outlier filter drops a non-tail entry

`flutter_ppg` recomputes `rrIntervals` from scratch each frame and runs `filterOutliersWithStats` (`flutter_ppg_service.dart:265`), which can drop an interval from the *middle/front* of the window independently of new beats. When that breaks the previous-tail/current-head alignment, `diffNewIntervals` finds no overlap and returns the **entire** `current` list, re-emitting intervals already sent downstream.

**Concrete:** `previous = [800, 900, 750]`, next frame the middle `900` is dropped and an `810` beat is added → `current = [800, 750, 810]`. No suffix of `previous` equals a prefix of `current` (`[800,900,750]`≠`[800,750,810]`, `[900,750]`≠`[800,750]`, `[750]`≠`[800]`), so the helper returns `[800, 750, 810]` — `800` and `750` are emitted a second time. A consumer computing HRV/BPM double-counts those beats.

This is exactly the fragility the plan/dartdoc calls out and defers to the Phase-6 acceptance gate (note 12). Flagged only so the duplicate-emit (not just the false-miss) is on record as a real consumer-visible effect of the minimal passthrough. No change required for this milestone.

### 3. (Informational) `qualityStream` emits on every frame with no dedup

`_onSignal` adds `SignalQuality.fromSnr(signal.snr)` on every signal (~24/s), while `stateStream` is deduped via `_setState`. This matches the plan ("one quality event per signal") and is not a bug, but a UI binding directly to `qualityStream` will rebuild ~24×/s. Consider `distinct()` at the consumer, or dedup here later. Not blocking.

---

## Verified correct (no action)

- **Barrel boundary:** only `RrInterval`/`SignalQuality`/`MeasurementState`/`List<double>`/`CameraPpgError` cross; `import 'package:flutter_ppg/flutter_ppg.dart' hide SignalQuality;` resolves the enum collision and the kit uses `SignalQuality.fromSnr(snr)`, never `PPGSignal.quality`.
- **Teardown order** in `_release()` and `_probeCameraCoverage`'s `finally` matches the spike invariant: stopImageStream → **close bridge before cancel** (the `async*` `await for` deadlock) → cancel sub → `service.dispose()` (unawaited `void`, correct) → torch off → controller dispose.
- **`_running` cleared on all failure exits:** the `finally { if (!lockedAndStreaming) await _release(); }` covers no-rear-camera, no-cover, `CameraException`, and unexpected-error returns; the two pre-`try` early returns (`_disposed`, already-`_running`) correctly do **not** release. Retry-after-no-finger works (round-2 F1 closed).
- **Permission path:** `initialize()` throwing `CameraAccessDenied` inside `_probeCameraCoverage` propagates through the `finally` (which tears down, doesn't swallow) to `_lockCoveredCamera`'s `on CameraException` → `CameraPpgError.fromCameraErrorCode` → surfaced as a value.
- **`_lastRrIntervals`** holds a per-frame fresh list (`filterResult.intervals` is newly allocated each frame in flutter_ppg), so retaining the reference is safe; reset to `const []` at each `start()`.
- **`diffNewIntervals` edge cases:** empty current → `[]`; empty previous → whole current; unchanged → `[]`; growing/sliding overlap handled; longest-overlap-first is the safe choice. Test suite covers these.
- **`FingerPresence.fromRawIntensity`** band (`<= min` absent, `>= max` overBright, strictly-between present, NaN→absent) is equivalent to the example's `raw > min && raw < max` coverage discriminator.
- **Re-entrant `_release()`** is idempotent (capture-then-null before any await).

---

## Recommendation

Address or explicitly defer **Finding 1** (stop/dispose during in-flight `start()`), which is a reachable torch-stranding + double-open defect. Findings 2–3 are accepted-scope caveats already contemplated by the plan. The rest of the implementation is correct and faithful to the reviewed plan.
