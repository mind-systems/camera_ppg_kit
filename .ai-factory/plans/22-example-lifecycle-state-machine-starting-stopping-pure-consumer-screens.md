# Plan: Example lifecycle state machine (starting/stopping) + pure-consumer screens

## Context
Give the example app one authoritative representation of "what the source is doing right now" — an example-side `SourceLifecycle` enum owned by `CameraPpgService` that adds the transitional `starting`/`stopping` states the kit's frozen `MeasurementState` deliberately omits — so a slow teardown reads as honest "Stopping…" progress and screens gate Start/Stop off a single source of truth instead of each re-deriving `isRunning`/`canStop`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Scope guards (from note 33)
- **Example only.** Do not touch the kit `lib/` surface — `MeasurementState`, `CameraPpgSession`, and the barrel stay frozen (Phase-10 / notes 19, 23). The new enum lives entirely in `example/`.
- **No `done`/"Complete" state** (note 23). The terminal path is `stopping → idle`, never a completion state.
- The kit's `MeasurementState` stream (`stateStream`) and its note-32 authoritative-idle push stay in place — they still drive `bpmProvider` and the RR-history reset. Lifecycle is added alongside, wrapping/folding kit state; it does not replace the kit-state plumbing.
- Kit-side teardown order (close input bridge before cancelling the subscription, notes 07/13) is unchanged — this task only changes the example's lifecycle *representation*.

## Design decisions (pin before implementing)
- **Lifecycle model:** `SourceLifecycle { idle, starting, warmup, measuring, poorSignal, stopping }`. Transitions: `idle → starting → warmup → measuring ⇄ poorSignal → stopping → idle`. "Active" = `warmup | measuring | poorSignal`. "Busy/transitional" = `starting | stopping`.
- **Who sets what, when:**
  - `starting` — set synchronously the moment `startMeasurement()` is entered (after the already-existing `_measuring` re-entry guard passes).
  - `warmup`/`measuring`/`poorSignal` — folded in from the kit's `MeasurementState` stream while the source is running, in the same bridge subscription that already fans kit state into `_stateController`.
  - `stopping` — set synchronously the moment `stopMeasurement()` is entered (for a real in-flight session; a no-op stop while already `idle` must not emit a spurious `stopping`).
  - `idle` — set after teardown completes, in the same place note 32's `_stateController.add(MeasurementState.idle)` already lands (this task *absorbs* that push, it does not remove it).
- **Folding guard:** while `_lifecycle == stopping` (or already `idle`), ignore incoming kit `MeasurementState` emits so a late kit emit can't bounce lifecycle back off `stopping`. A kit `idle` arriving mid-run is ignored (never downgrade an active source to `idle` off a stray kit emit — the authoritative `idle` comes only from the `stopMeasurement` teardown path).
- **Late-subscriber safety:** the shell keeps every screen mounted in one `IndexedStack` (note 22), so all screens hold a live `lifecycleProvider` subscription for the whole app lifetime and receive every transition — no stream replay needed. Screens default to `SourceLifecycle.idle` before the first emit (app start), which is correct.
- **Raw-entry stop:** the shell's `NavigationBar` callback can't be async, so the entering-Raw `stopMeasurement()` stays unawaited — but because `stopMeasurement()` now flips lifecycle to `stopping` *synchronously*, any subsequent Start is already gated by `lifecycle == idle`. That closes the accepted "Start fires mid-teardown" race in `main.dart` by gating rather than by awaiting.

## Tasks

### Phase 1: Lifecycle in the service

- [x] **Task 1: Add the `SourceLifecycle` enum**
  Files: `example/lib/services/source_lifecycle.dart` (new)
  Plain-Dart enum with values `idle, starting, warmup, measuring, poorSignal, stopping` (no `flutter`/`riverpod`/`camera` imports — same purity discipline as `CameraPpgService`). Add convenience getters `bool get isActive` (`warmup || measuring || poorSignal`) and `bool get isTransitional` (`starting || stopping`) for the screens to gate on. Dartdoc it as the **example-side** lifecycle that wraps the kit's frozen 4-value `MeasurementState` and adds the async transitional states the kit contract deliberately omits (cite notes 33/19/23); explicitly note it must never be added to the kit's public `MeasurementState`.

- [x] **Task 2: Drive lifecycle from `CameraPpgService`** (depends on Task 1)
  Files: `example/lib/services/camera_ppg_service.dart`
  - Add a long-lived `StreamController<SourceLifecycle>.broadcast()` (`_lifecycleController`) opened in the constructor alongside the existing four controllers and closed in `dispose()`; add a `SourceLifecycle _lifecycle = SourceLifecycle.idle` field, a `Stream<SourceLifecycle> get lifecycleStream` getter, and a private `_setLifecycle(SourceLifecycle next)` helper that stores `_lifecycle`, emits on `_lifecycleController` (guard `!isClosed`), and logs a coarse milestone via the existing `ppgLog` (e.g. `'lifecycle: <prev> -> <next>'`) — this is the only new logging.
  - In `startMeasurement()`: after the `_measuring` re-entry guard passes and `_measuring = true`, call `_setLifecycle(SourceLifecycle.starting)` synchronously (before creating the session / awaiting `start()`). Leave the existing error path unchanged — the failed-start `await stopMeasurement()` will carry lifecycle through `stopping → idle`.
  - In the kit-state bridge subscription (`session.stateStream.listen(...)`, currently `_stateController.add`): keep the existing `_stateController.add` and additionally fold the kit `MeasurementState` into lifecycle via a helper — but **only while running**: if `_lifecycle` is `stopping` or `idle`, ignore; otherwise map `warmup→warmup`, `measuring→measuring`, `poorSignal→poorSignal`, and ignore kit `idle` (per the folding guard above). This is what advances `starting → warmup` on the first kit state.
  - In `stopMeasurement()`: when there **is** an in-flight session, call `_setLifecycle(SourceLifecycle.stopping)` synchronously at entry (before cancelling subs / `session.dispose()`); after teardown, alongside the existing `_stateController.add(MeasurementState.idle)` note-32 push, call `_setLifecycle(SourceLifecycle.idle)`. In the early-return no-session branch, do **not** emit `stopping`; if `_lifecycle` is somehow non-idle there, settle it to `idle` (defensive), otherwise leave it.
  - Keep `isMeasuring` and the `MeasurementState` plumbing exactly as-is.

- [x] **Task 3: Expose `lifecycleProvider`** (depends on Task 2)
  Files: `example/lib/providers/stream_providers.dart`
  Add `final lifecycleProvider = StreamProvider<SourceLifecycle>((ref) => ref.watch(cameraPpgServiceProvider).lifecycleStream);`, mirroring the existing `stateProvider`. Dartdoc it as the single source of truth screens render for Start/Stop gating and the state banner, superseding per-screen `isRunning`/`canStop` derivation.

### Phase 2: Screens become pure consumers

- [x] **Task 4: Source screen — gate controls on lifecycle** (depends on Task 3)
  Files: `example/lib/screens/source_screen.dart`
  - Replace the `stateProvider`-derived `isRunning`/`canStop` in `build()` with `ref.watch(lifecycleProvider).value ?? SourceLifecycle.idle`.
  - `_controlCard`: **Start** enabled only when `lifecycle == idle`; **Stop** enabled only when `lifecycle.isActive`; during `lifecycle.isTransitional` (`starting`/`stopping`) both buttons are disabled and show a small inline `CircularProgressIndicator` (spinner) instead of firing — so a slow/hanging teardown shows honest "Stopping…" progress. Keep the buttons full-width/semantic (note 26 styling).
  - Update `_stateLabelColor` to take `SourceLifecycle` and add the two new arms: `starting → ('Starting…', pendingColor)`, `stopping → ('Stopping…', pendingColor)`; keep `idle/warmup/measuring/poorSignal` labels+colors as today (no `done` arm — note 23). Feed the banner from it.
  - Gate the camera-override dropdown + Refresh button (currently keyed off `isRunning`) on `lifecycle == idle` instead, so camera choice is locked during starting/active/stopping alike.
  - Keep `_signalCard` (`qualityProvider`/`fingerPresenceProvider`) and the `[debug]` tuning panel unchanged — presentation/consumer only.

- [x] **Task 5: Streams + Calibration banners consume lifecycle** (depends on Task 3)
  Files: `example/lib/screens/streams_screen.dart`, `example/lib/screens/calibration_screen.dart`
  Point each screen's state banner at `lifecycleProvider` (updating its local `_stateLabelColor` to accept `SourceLifecycle` with the added `starting`/`stopping` arms, per the note's "own copy, deliberately not factored" convention) so during teardown they show **Stopping…** rather than a frozen "Measuring". Leave everything else untouched: Streams keeps its `stateProvider` `ref.listen` that clears `_rrHistory` on `warmup` and its `bpm`/`rr`/`signal` cards; Calibration keeps its local `_recording` gating, the `service.isMeasuring` record-start gate, `bpmProvider`/`qualityProvider` cards, and the countdown/recorder logic (note 21) exactly as-is.

- [x] **Task 6: Route Raw-entry stop through the lifecycle path** (depends on Task 2)
  Files: `example/lib/main.dart`
  The entering-Raw `ref.read(cameraPpgServiceProvider).stopMeasurement()` already funnels through the one stop path — with Task 2 it now flips lifecycle to `stopping` synchronously. Keep the call unawaited (a `NavigationBar` callback can't be async) and rewrite the `_onDestinationSelected` comment: the previously "accepted residual race" (a Start firing mid-teardown) is now closed by the Source screen gating Start on `lifecycle == idle`, not by awaiting here. No behavioural change beyond the synchronous `stopping` transition Task 2 introduces.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add example SourceLifecycle state machine to CameraPpgService"
- **Commit 2** (after tasks 4-6): "Make example screens pure lifecycle consumers with Starting/Stopping states"
