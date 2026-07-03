# Plan: Fix the dropped idle transition on Stop / Raw-entry

## Context
After Stop (or entering Raw) the example Source screen stays frozen on "Measuring" because `stopMeasurement()` cancels the session→controller bridge before the session emits its terminal `idle`. Make the example service the authority on the terminal state by pushing a definitive `MeasurementState.idle` into its own long-lived controller after teardown.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Assumptions / Constraints
- **Scope is `example/lib/services/camera_ppg_service.dart` only.** Kit `lib/` and the public `MeasurementState` enum / `CameraPpgSession` are frozen (Phase-10 freeze, notes 19/23). Do NOT introduce a `done` state — the terminal state is `idle`.
- **BPM clears for free.** `BpmNotifier` (`example/lib/providers/stream_providers.dart:57-66`) already resets BPM to `null` on `MeasurementState.idle`, so the idle push cascades to clear stale BPM — no extra BPM-reset code is needed.
- **Banner + buttons are state-driven.** The Source/Streams/Calibration banners and the Start/Stop enablement derive from `stateProvider`; the idle push restores all of them.
- **SQI cannot be cleared from the service.** The SQI chip gates on the `qualityProvider` `AsyncValue` (`loading`→`data`), which cannot revert to `loading` once data has arrived, and `SignalQuality` has no "none"/reset value. There is therefore no in-band way for the service to blank a stale SQI chip through the quality stream; that residual is a display-layer concern (note 33's transitional-UX territory), out of this task's service-only scope. This task guarantees the terminal `idle` arrives and BPM clears; the SQI chip retaining its last band after Stop is a known, documented limitation, not a regression introduced here.

## Tasks

### Phase 1: Terminal idle push

- [x] **Task 1: Push a definitive `idle` after teardown in `stopMeasurement()`**
  Files: `example/lib/services/camera_ppg_service.dart`
  In `stopMeasurement()` (currently lines 140-153), after `await session.dispose()`, push a terminal `MeasurementState.idle` into the service's own long-lived `_stateController`, guarded by `!_stateController.isClosed` (so the call is safe when invoked from `dispose()`, which closes the controller immediately afterwards). This makes the service self-sufficient rather than relying on the about-to-be-disposed session emitting `idle` synchronously through an already-cancelled bridge subscription. Do NOT reorder to dispose-then-cancel — keep the direct push. Leave the early `session == null` no-op path unchanged (nothing was measuring, so nothing to reset). The idle emit cascades through `BpmNotifier` to reset stale BPM automatically.

- [x] **Task 2: Update `stopMeasurement()` dartdoc** (depends on Task 1)
  Files: `example/lib/services/camera_ppg_service.dart`
  Amend the `stopMeasurement()` doc comment to state that the service emits a definitive terminal `MeasurementState.idle` on its own controller after teardown (rather than depending on the session's last emit), and that this is what returns the UI to Idle and clears BPM via the state cascade. Keep it to a couple of sentences; no history/changelog phrasing.

## Verify (manual, on device)
- Start → Stop returns the Source screen to **Idle** (banner "Idle", Start re-enabled, Stop disabled); repeat Start/Stop several times with no stale state.
- Enter Raw while the source runs, return to Source/Streams → both show **Idle**, not a frozen "Measuring".
- BPM reads blank/`--` again after Stop.
