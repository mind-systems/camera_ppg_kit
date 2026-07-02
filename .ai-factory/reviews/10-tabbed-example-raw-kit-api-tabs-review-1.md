# Code Review: Tabbed example — Raw + Kit-API tabs

**Scope:** `git diff HEAD` — example app tab shell + Kit-API tab + service/providers, plus the barrel export of `SessionPolicy`/`RrAcceptance`.
**Files read in full:** `example/lib/main.dart`, `example/lib/services/camera_ppg_service.dart`, `example/lib/providers/stream_providers.dart`, `example/lib/providers/camera_ppg_service_provider.dart`, `example/lib/screens/kit_api_tab.dart`, `lib/camera_ppg_kit.dart`, plus kit surface (`camera_ppg_session.dart`, `session_policy.dart`, `rr_acceptance.dart`, `measurement_state.dart`, `camera_ppg_error.dart`) for behavioral verification.

Overall the code is faithful to the plan: barrel-only imports in Tab 2 and the service, subscriptions live in providers, the `[debug]` knobs match the real constructors, and the tab-blur camera-ownership handoff is implemented as designed. One high-severity correctness bug and a few minor issues below.

---

## Findings

### 1. [High] After `done`, the Kit-API tab can neither Start nor Stop — camera + torch stay on with no in-tab recovery

`kit_api_tab.dart:144`:
```dart
final isMeasuring = state != MeasurementState.idle && state != MeasurementState.done;
```
and `_startStopRow` (`:233`, `:240`):
```dart
ElevatedButton(onPressed: isMeasuring ? null : _start, ...)   // Start
OutlinedButton(onPressed: isMeasuring ? _stop : null, ...)    // Stop
```

When a measurement runs its full target duration, `SessionPolicy` transitions to `MeasurementState.done` (terminal — `session_policy.dart:124-125,146-149`). Crucially, **`CameraPpgSession` does not release the camera on `done`** — `_onSignal` just calls `_setState(done)`; the controller, image stream, and torch stay live until `stop()`/`dispose()` (`camera_ppg_session.dart:512-594`). Meanwhile the service's `_measuring` flag is still `true` (nothing cleared it — only `stopMeasurement()` does).

So in the `done` state:
- `isMeasuring == false` → **Stop is disabled**.
- `isMeasuring == false` → Start is enabled, but pressing it calls `startMeasurement()`, which hits `if (_measuring) { … return null; }` (`camera_ppg_service.dart:98-101`) and is a **silent no-op**.

Result: after every normal completion the torch stays lit on the user's finger, and the only way to release it from Tab 2 is impossible — the user must physically switch tabs (the tab-blur handler) to stop it. Both controls are dead. This is reachable on every successful 60 s measurement, so it will be hit immediately during the calibration runs this tab exists to enable.

**Fix options:** either (a) enable Stop when `state == done` as well (e.g. gate Stop on `service.isMeasuring` / `state != idle`), or (b) make Start recover from `done` by having `_start` call `stopMeasurement()` first when the current state is `done`, or (c) auto-`stopMeasurement()` on the `done` transition. Whichever is chosen, the button-enable predicate and the service `_measuring` guard must agree so that at least one control is always live after `done`.

### 2. [Low] Tab-blur `stopMeasurement()` is fire-and-forget, so Tab 1 can open the camera before Tab 2 has released it

`main.dart:79`:
```dart
ref.read(cameraPpgServiceProvider).stopMeasurement();  // not awaited
```
A `TabController` listener can't be `async`, so this is unavoidable here, but the release (stop image stream → dispose isolate → torch off → dispose controller) takes hundreds of ms. If the user switches Tab 2 → Tab 1 and immediately triggers Tab 1's auto-detect, Tab 1's `CameraController.initialize()` can collide with the still-closing controller → `CameraException`. In practice human reaction time on Tab 1 (which opens the camera only on an explicit action, not on tab entry — verified in `auto_detect_screen.dart`) makes this unlikely, but it is the residual race the ownership model leaves open. Worth a comment acknowledging it, or gating Tab 1's acquire behind the same service state. Not blocking.

### 3. [Low] `bpmProvider` retains stale BPM after Stop until the next warm-up

`stream_providers.dart:62-66` resets BPM to `null` only on the `warmup` transition. After a user-initiated Stop (which returns the session to `idle`, not `warmup`), the large BPM readout keeps showing the last value from the finished measurement until a new one starts. Display-only and low-impact, but a developer glancing at the tab post-stop sees a number that no longer corresponds to a live signal. Consider also resetting on `idle`/`done`.

### 4. [Nit] `BpmNotifier.build()` manually cancels subscriptions it also registers via `ref.onDispose`

`stream_providers.dart:51,61,68-71`: the `_rrSub?.cancel()` / `_stateSub?.cancel()` at the top of `build()` are redundant with the `ref.onDispose` cancellations, since `cameraPpgServiceProvider` is a plain (non-rebuilding) `Provider` and `build()` runs once. Harmless belt-and-suspenders; no leak. Mentioned only for tidiness.

---

## Verified correct (no action)

- **Import-boundary discipline:** Tab 2 and the service import only `package:camera_ppg_kit/camera_ppg_kit.dart`; no `CameraImage`/`PPGSignal`/`FlutterPPGService`/`CameraController` leaks. Barrel now exports `SessionPolicy`/`RrAcceptance` with a `[debug]`-only comment (note 19). Correct.
- **`startMeasurement` failure path:** on `start()` error it calls `stopMeasurement()`, which clears subs, nulls `_session`, and resets `_measuring` — so a retry starts clean. `_measuring` cannot get stuck `true` (the only throwing calls precede or are guarded).
- **Concurrent stop during `start()`:** the session's `_generation` guard already handles a tab-blur `stopMeasurement()` landing mid-round-trip; the service stays consistent (`_session == null`, `_measuring == false`) afterward.
- **`availableCameras()` transient session:** read-only enumeration opens no controller/torch and is disposed immediately — no collision with the main session, "controllers stay open" invariant preserved.
- **`_stateBanner` switch** is exhaustive over the 5 `MeasurementState` values; `CameraPpgError.type/message/permanentlyDenied` and `SignalQuality`/`FingerPresence` enum accesses all match the real types.
- **Camera override** disabled while measuring and only applied on the next `start()` via `useCamera` on a fresh (non-running) session — no `StateError` path.

---

Finding 1 should be fixed before this ships to the calibration runs; the rest are minor.
