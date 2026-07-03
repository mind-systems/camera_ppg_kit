# Fix the dropped idle transition on Stop / Raw-entry

**Date:** 2026-07-03
**Source:** conversation context (example UI bug report)

## Symptom

After pressing **Stop** on the Source screen the UI never returns to the initial
(Idle) state — the state banner stays "Measuring"/"Poor signal", the **Start** button
stays disabled, **Stop** stays enabled. Entering the **Raw** tab (which stops the kit
source) leaves the same frozen state when the user navigates back. The screen looks
hung though the app is still responsive.

## Root cause

Lifecycle state is derived purely from a stream: `stateProvider`
(`example/lib/providers/stream_providers.dart`) watches
`CameraPpgService.stateStream`, which is the service's long-lived `_stateController`,
fed from the current session via a bridge subscription.

`CameraPpgService.stopMeasurement()`
(`example/lib/services/camera_ppg_service.dart:140-153`) **cancels the bridge
subscriptions BEFORE disposing the session**:

```
for (final sub in _subs) { await sub.cancel(); }   // bridge session.stateStream -> _stateController is torn down
_subs.clear();
_session = null;
_measuring = false;
await session.dispose();                            // -> _release() -> _setState(idle)  (camera_ppg_session.dart:439)
```

The kit session *does* emit `MeasurementState.idle` during teardown
(`lib/src/api/camera_ppg_session.dart:439`), but the bridge that would forward it to
`_stateController` is already cancelled, so the terminal `idle` lands on nobody. The
provider retains its last value (`measuring`/`poorSignal`) → the whole UI is stuck.

The failed-start path is unaffected: there `session.start()` runs `_release()` →
`_setState(idle)` while the bridge subs are still connected (they are cancelled only
later, inside the `stopMeasurement()` it then calls), so idle propagates. Only the
user-initiated Stop and the Raw-entry stop drop it, because they cancel-then-dispose.

## The change

Make the **service** the authority on the terminal state instead of relying on the
about-to-be-disposed session's last emit. In `stopMeasurement()`, after teardown push a
definitive `MeasurementState.idle` into the service's own long-lived `_stateController`
(guarded by `!_stateController.isClosed`), and reset the other display streams as
appropriate so a stale SQI/BPM does not linger. Direct-push (not a reorder to
dispose-then-cancel) is preferred: it makes the service self-sufficient and does not
couple correctness to the session emitting idle synchronously during dispose.

Scope: `example/lib/services/camera_ppg_service.dart` only. Do NOT change the kit's
public `MeasurementState` enum or `CameraPpgSession` (frozen for the Phase-10 freeze,
notes 19/23). This is the minimal, independently-shippable unstick.

## Verify

- On device: Start → Stop returns the Source screen to **Idle** (Start re-enabled, Stop
  disabled, banner "Idle"). Repeat Start/Stop several times — no stale state.
- Enter Raw while the source runs, return to Source/Streams → both show **Idle**, not a
  frozen "Measuring".
- Streams and Calibration consumers show their "waiting"/"start the source first" states
  again after Stop.

## Guards

- Kit `lib/` untouched — example service only.
- Do not re-introduce a `done` state (note 23); the terminal state is `idle`.
- The transitional starting/stopping UX (a slow teardown still shows the last active
  state briefly) is note 33's concern, not this task — this task only guarantees the
  final `idle` arrives.
