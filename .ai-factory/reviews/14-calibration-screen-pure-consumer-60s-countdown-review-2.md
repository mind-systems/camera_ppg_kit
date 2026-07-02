# Code Review 2: Calibration screen (pure consumer, 60s countdown)

**Scope reviewed:** `example/lib/screens/calibration_screen.dart` (now 285 lines — modified since review-1), `example/lib/main.dart` (shell wiring). Re-read in full against `calibration_recorder.dart`, `camera_ppg_session.dart` (stream emission cadence), `stream_providers.dart`, `session_config_provider.dart`, `source_screen.dart`, `kit_api_tab.dart`, notes 20/21/22.

**Risk level:** 🟢 Low — the one substantive finding from review-1 is fixed; no blocking issues remain.

---

## Review-1 finding — resolved ✓

**Finding 1 (Medium): countdown/whole screen rebuilt at camera frame rate.** Fixed correctly. `_bpmSection()` (`:194`) and `_qualityAndStateRow()` (`:219`) are now each wrapped in their own `Consumer`, so the `ref.watch(bpmProvider)` / `ref.watch(qualityProvider)` / `ref.watch(stateProvider)` calls register the **Consumer leaf** as the frame-cadence dependent rather than the enclosing `State` element. `_countdown()` (`:139`) no longer watches any provider and rebuilds only from the 1 Hz `_tickTimer`'s `setState` — exactly note 21's "driven only by the 1 Hz timer … never rebuilt on RR ticks." The isolation is genuine: `Consumer` elements are reused across the outer `setState` (same widget type/position), so no subscription churn is introduced, and the frame-rate rebuild is confined to the BPM number and the two chips. The explanatory doc-comments on both helpers accurately describe the mechanism.

---

## Fresh pass — verified correct

- **Pure-consumer contract:** no `startMeasurement`/`stopMeasurement`, no `CameraController`/torch, start-gate on the local `_recording` flag, record-precondition on `service.isMeasuring` (`:47`). ✓
- **Idempotent finalize:** `_finish()` guards `if (!_recording) return` (`:74`), cancels+nulls both timers, and is shared by the 60 s one-shot, the manual Stop, and cannot double-finalize. The Stop button is also disabled when `!_recording` (`:162`). Double-tap safe. ✓
- **Timer lifecycle:** both timers cancelled+nulled in `_finish()` and cancelled in `dispose()` (`:107`). No `setState` after an `await` without a `mounted` guard — the only async gap, `_save()` (`:96-101`), has `if (!mounted) return;` before its `setState`. ✓
- **Config honesty:** `_recorder.start(service, config.acceptance, config.policy)` reads the in-force `sessionConfigProvider` (`:53`), so the file describes the params actually running. ✓
- **Save gating:** `_recorded` is only set true inside `_finish()` (reachable only after a real `start()`), and `_startRecording()` resets it to false, so Save can never call `recorder.save()` before `start()` (no `StateError` path), and is disabled during an active recording. ✓
- **Manual-stop window:** `_windowSeconds = 60 - _remainingSeconds` (`:79`) records actual elapsed for a short stop rather than a fixed 60. ✓
- **Shell wiring (`main.dart`):** `calibration` inserted before `raw`; `_screenFor` switch arm added; `children`/`destinations`/`selectedIndex` all derive from `_Branch.values`; Raw-exclusivity hook still keys on `_Branch.raw` (enum, not index). Index-shift-safe; Source Start/Stop and Raw stop-hook untouched. ✓
- **Imports/exhaustiveness:** all imports used; `MeasurementState`/`SignalQuality` switches exhaustive; compiles cleanly. ✓

---

## Residual non-blocking observations (informational — do not warrant another cycle)

- **Window can read 59 vs 60 (cosmetic).** At t≈60 s the one-shot `_finishTimer` and the 60th `_tickTimer` fire in unspecified order; if finish runs first, `_windowSeconds` = 59. Within note 21's stated `windowSeconds ≈ 60` tolerance.
- **`_save()`'s `await _recorder.save(...)` is unguarded (out of target scope).** On a platform where `getExternalStorageDirectory()` returns null (iOS) or on an IO error, the recorder's `baseDir!` throws and the tap surfaces an unhandled async exception. The calibration export is Android-scoped by design (note 20) and this is a dev instrument, so it is not a defect on the target; a `try/catch` showing the error in-screen would only be a nicety.
- **`dispose()` does not `_recorder.stop()`.** Harmless — the screen disposes only on app teardown (IndexedStack keeps it mounted) and the service provider's `onDispose` tears down the source controllers, collecting the recorder's subscriptions.
- **Guidance banner clears lazily.** `_blockedByNotMeasuring` resets only on the next `_startRecording()` tap, not automatically when the source later starts — acceptable for a dev tool, and the next Start tap is exactly the clearing action.

None of the above changes runtime correctness on the target platform or the calibration data; they are robustness/cosmetic notes recorded for completeness.

REVIEW_PASS
