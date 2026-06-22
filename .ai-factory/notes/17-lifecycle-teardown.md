# Plugin Hardening — Lifecycle & Teardown

**Date:** 2026-06-21
**Source:** ROADMAP Phase 11 "Lifecycle & teardown" (release camera + torch deterministically on dispose, app-background, and hot-restart; ensure the frame stream and isolate stop cleanly); neiry teardown discipline (`docs/guides/teardown.md`, notes 24 + 28 — strict ordering, release-on-dispose, double-disconnect guard); camera_ppg notes 07 (bare wired session) + 13 (frame isolate)

## Key Findings

- **The camera is an exclusive OS resource — neiry's BLE invariants become camera-release invariants.** Neiry's crux was *strict ordering* (unregister callbacks → cancel subscriptions → release native handle) and *idempotence guards* (double-disconnect = `Fatal signal 64`). Both port directly: a `CameraController` is the analogue of the native device handle. Release it in a deterministic order, and never twice.
- **The new failure neiry did not have: backgrounding.** The `camera` plugin loses the device when the app backgrounds, and Android reclaims it for other apps. We MUST release on `inactive`/`paused` and re-init on `resumed` via a `WidgetsBindingObserver` — neiry had no such lifecycle obligation because BLE survives background.
- **Ordering is close-input-before-cancel-subscription, proven on hardware (note 03 spike).** `flutter_ppg`'s `processImageStream` is an `async*` generator parked on `await for (image in inputController.stream)`. Awaiting the `PPGSignal` subscription's `cancel()` while that input controller is still open **deadlocks** — the generator is suspended waiting for a frame that will never come (camera stopped) or for the input to close, so the cancel never unwinds (the A70 froze with the torch stuck on until this was fixed). Therefore: stop the image stream, **close the input `StreamController<CameraImage>` first** (ends the `await for`, the generator completes), *then* cancel the subscription (returns at once), then torch off and dispose. This is the load-bearing teardown invariant — neiry's "unregister callbacks before releasing the handle" rule, made specific to flutter_ppg's async generator.
- **Split of responsibility:** the *ordered release* lives in `CameraPpgSession` (the reusable kit); the *WidgetsBindingObserver* lives in `example/` (it observes app lifecycle and calls into the session). The kit must not own a binding observer — the host decides lifecycle.

## Details

### `lib/src/api/camera_ppg_session.dart` — ordered, idempotent release

Add a single private `_release()` that all paths funnel through, in this exact order (validated end-to-end on the A70 — see Key Findings for why this order, not the naive reverse-of-start):

1. `await _controller.stopImageStream()` — only if streaming (`_controller.value.isStreamingImages`). Stops the camera feeding frames.
2. **`await _inputController.close()`** — close the `StreamController<CameraImage>` bridge **before** cancelling the subscription. This ends `flutter_ppg`'s `async*` `await for`, so the generator completes and step 3 cannot deadlock. (Skipping/reordering this is the A70 freeze.)
3. **Cancel the `PPGSignal` subscription / tear down the isolate** (note 13). Returns promptly now the input is closed; the isolate's `SendPort` pipe is torn down here so no late frame references a disposed controller.
4. `service.dispose()` — dispose the `FlutterPPGService`.
5. `await _controller.setFlashMode(FlashMode.off)` — torch off before dispose so the LED never lingers on if `dispose()` throws.
6. `await _controller.dispose()`.
7. Emit `MeasurementState.idle` on `stateStream`; do **not** close the broadcast controllers (note 07: streams stay open across measurements; only the final `dispose()` of the session closes them).

The example's `coverage_detector.dart` / `measurement_runner.dart` teardowns already implement exactly this order — port it verbatim into the session's `_release()`.

**Double-dispose guard (neiry note 24 analogue).** A `bool _releasing` / `bool _released` latch: `_release()` returns immediately if already released, and never calls `stopImageStream`/`dispose` on a controller that is null or already disposed (`_controller == null` after release). Disposing an already-disposed `CameraController` throws — guard exactly as neiry guarded the second native disconnect with `if (_connected)`.

`stop()` calls `_release()` keeping the session reusable (re-`start()` rebuilds the controller). The session's own `dispose()` calls `_release()` then closes the three `StreamController`s.

### `example/` — `WidgetsBindingObserver`

The playground screen's `State` mixes in `WidgetsBindingObserver`, registers in `initState` (`WidgetsBinding.instance.addObserver(this)`), removes in `dispose`. In `didChangeAppLifecycleState`:

- `AppLifecycleState.inactive` / `paused` → `session.stop()` (full ordered release; the camera is gone anyway).
- `AppLifecycleState.resumed` → re-`start()` only if a measurement was active before backgrounding (track a `_wasMeasuring` flag), surfacing `MeasurementState` so the UI shows re-acquisition rather than a frozen preview.

**Hot-restart** is covered for free: hot-restart re-runs `main` and constructs a fresh session, but the OS still holds the old camera. The example must call `session.stop()`/release in `dispose`; rely additionally on the start-path acquiring the controller fresh each `start()` so a stale handle from a previous Dart VM is never reused.

### Verify

- Example: start a measurement, background the app → logs show stop-stream → torch-off → controller-dispose in order; the LED visibly turns off. Foreground → preview + RR resume.
- Hot-restart mid-measurement → no `CameraException` ("camera in use"), torch not stuck on.
- Call `stop()` twice and `dispose()` after `stop()` → no exception, no second `dispose()` on the controller (mirror neiry's double-disconnect regression test).
- Confirm empirically (Phase 2 harness / `camera` plugin behaviour on target devices) that `paused` actually drops the device before relying on re-init — do not assume; record the verdict here.

### Guards

- **Strict order, single funnel.** Every teardown path (`stop`, session `dispose`, lifecycle observer) goes through `_release()` — no ad-hoc `dispose()` calls scattered across the screen (neiry's "single path to disconnect").
- **Tear down the isolate/subscription before the controller, but after closing the input bridge.** A leaked frame isolate keeps the torch path warm and drains battery (note 13 guard) — cancel it before disposing the controller, never after; just not *before* the input close (see the deadlock finding).
- **Idempotent.** Releasing an already-released session is a no-op, never a throw — the camera analogue of neiry's non-idempotent native handle.
- **Kit stays Flutter-binding-free.** The `WidgetsBindingObserver` lives in the example/host, not in `lib/src/` — the ordered release is the kit's contract; *when* to invoke it is the host's.
- **No types leak.** `CameraController` / `CameraException` stay inside the session; teardown failures surface as `MeasurementState`/`CameraPpgError` values, never thrown across the barrel.
