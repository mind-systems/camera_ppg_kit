# Review: Fix the dropped idle transition on Stop / Raw-entry — round 1

## Scope reviewed
- `example/lib/services/camera_ppg_service.dart` (only code change in the diff; the other staged files are planning artifacts).

## What the change does
Adds a definitive terminal `MeasurementState.idle` push into the service's own long-lived `_stateController` at the end of `stopMeasurement()`, after `session.dispose()`, guarded by `!_stateController.isClosed`. Adds a matching dartdoc note. Matches the plan (Tasks 1 & 2) and spec note 32 exactly.

## Correctness analysis
- **Root cause addressed.** The bridge subs are cancelled before `session.dispose()`, so the session's own terminal `idle` never reaches `_stateController`. The explicit push makes the service the authority on the terminal state — the intended fix.
- **`dispose()` path safe.** `dispose()` calls `await stopMeasurement()` (which may push `idle`) and only afterwards closes the controllers; the `!isClosed` guard covers any re-entry and there is no add-after-close.
- **No-session no-op path unchanged.** Early `return` when `session == null` — no spurious `idle` when nothing was measuring. Correct per plan.
- **Failed-start path.** `startMeasurement()` on error calls `await stopMeasurement()`, which now emits an extra `idle`. This is a harmless duplicate on a broadcast state stream (the session may already have emitted `idle` via the still-connected bridge during `start()`), and leaves the UI in the correct Idle state.
- **Emit is retained across navigation.** `stateProvider` is a plain (non-`autoDispose`) `StreamProvider`, so its subscription persists for the app lifetime; the `idle` emit becomes the provider's latest value and is observed when returning to Source/Streams after a Raw-entry stop. This is what unsticks the frozen banner.
- **BPM cascade confirmed.** `BpmNotifier` resets to `null` on `MeasurementState.idle` (`stream_providers.dart:57-66`), so the single `idle` push also clears stale BPM with no extra code, as the plan assumes.
- **SQI limitation.** As documented in the plan, the SQI chip gates on `qualityProvider`'s `AsyncValue` (`loading`→`data`) and cannot revert; `SignalQuality` has no reset value. This is a pre-existing display-layer constraint, correctly scoped out — not a regression introduced by this change.
- **Scope respected.** Kit `lib/`, `MeasurementState`, and `CameraPpgSession` untouched; no `done` state introduced.

No correctness, security, or race issues found.

REVIEW_PASS
