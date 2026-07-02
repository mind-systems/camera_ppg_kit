# Plan: Tabbed example — Raw + Kit-API tabs

## Context
Wrap the `example/` app in a two-tab shell: **Tab 1 (Raw)** keeps the existing Phase-2 panels wired straight to `flutter_ppg`/`camera` as the signal/FPS ground-truth instrument, and **Tab 2 (Kit API)** dogfoods the public barrel only — the first and only place the published surface (`CameraPpgSession` behind a `CameraPpgService` singleton + Riverpod providers) is exercised before `mind_mobile`.

> **Assumption:** Tab 2 depends on the `CameraPpgService` singleton + provider layer that the ROADMAP formally lists under Phase 8 (note 16). Because Tab 2 cannot dogfood the barrel without them, this plan creates a minimal service + providers here per note 16; the later Phase-8 milestone hardens/finalizes them rather than introducing them. The service is example-only plain Dart — never part of the published kit surface.

> **Camera-ownership model (decides plan-review Issues 1 & 2):** The rear camera + torch cannot be opened concurrently (CLAUDE.md, note 01), and **both** tabs drive that one device — Tab 1's `AutoDetectScreen` opens it directly via `flutter_ppg`/`camera`; Tab 2's `CameraPpgService` opens it via `CameraPpgSession`. This plan makes **the active tab own the camera**: leaving Tab 2 releases it so Tab 1 can use it. Concretely, when Tab 2 loses focus the shell calls `CameraPpgService.stopMeasurement()`, tearing the camera + torch down. This is deliberately chosen over "keep RR flowing while Tab 2 is offstage" — that alternative would strand a live camera/torch and collide with Tab 1's `initialize()`. The neiry "controllers stay open across stop/start" invariant is **preserved and orthogonal**: `stopMeasurement()` leaves the broadcast controllers open, so returning to Tab 2 keeps the same provider subscriptions (no re-init/`Bad state` bug) — the user just presses Start again to resume. App-background / hot-restart release via a `WidgetsBindingObserver` is Phase 9's concern (note 17) and out of scope here; `provider onDispose` covers only root-scope teardown (app shutdown).

## Settings
- Testing: no
- Logging: minimal (example-app convention: every Tab-2 user interaction calls `ppgTap('<label>')` from its handler before doing the work; use `ppgLog` for coarse lifecycle milestones — see `example/lib/auto_detect/log.dart` and the kit CLAUDE.md logging section; no `print`/`debugPrint`)
- Docs: no

## Tasks

### Phase 1: Dependencies & service/provider layer

- [x] **Task 1: Add flutter_riverpod to the example app**
  Files: `example/pubspec.yaml`
  From `example/`, run `flutter pub add flutter_riverpod` (never hand-edit `pubspec.yaml`; use `/usr/local/bin/flutter` for automation). This is the only new dependency; `camera`/`flutter_ppg` stay for Tab 1's direct access.

- [x] **Task 2: Add CameraPpgService device-layer singleton** (depends on Task 1)
  Files: `example/lib/services/camera_ppg_service.dart`
  Plain-Dart class per note 16 — mirrors neiry's `NeiryService`. **No `flutter`, `flutter_riverpod`, `camera`, or `flutter_ppg` imports**; consumes only `package:camera_ppg_kit/camera_ppg_kit.dart`.
  - Constructor opens three kept-open broadcast controllers: `StreamController<RrInterval>.broadcast()`, `StreamController<SignalQuality>.broadcast()`, `StreamController<MeasurementState>.broadcast()`; expose `rrStream`/`qualityStream`/`stateStream` getters. (Optionally also fan in `fingerPresenceStream` since Tab 2 renders finger-presence — add a `StreamController<FingerPresence>.broadcast()` the same way.)
  - Owns `CameraPpgSession? _session`, `bool _disposed`, and a `_measuring` re-entry guard.
  - `Future<CameraPpgError?> startMeasurement({String? cameraId, SessionPolicy? policy, RrAcceptance? acceptance})` — `_checkNotDisposed()`; guard re-entry; create `CameraPpgSession(policy: policy, acceptance: acceptance)`; if `cameraId != null` call `_session!.useCamera(cameraId)`; wire fan-in subscriptions from the session's streams into the controllers (`.listen(_rrController.add, onError: _rrController.addError)`, held in a `List<StreamSubscription<dynamic>> _subs`); then `return await _session!.start()` (session returns a typed `CameraPpgError?`, never throws).
  - `Future<void> stopMeasurement()` — no-op when `_session == null`; cancel + clear `_subs`; `await _session!.dispose()` (single teardown — since a fresh `CameraPpgSession` is created every `startMeasurement`, `dispose()` alone releases camera + torch; do **not** also call `stop()`, which would just re-run the idempotent `_release()` for nothing); null out `_session`. **The service's own controllers stay open** so the next start re-feeds them.
  - `Future<List<CameraPpgCameraInfo>> availableCameras()` — enumerate rear sensors for the override UI without a running measurement: construct a transient `CameraPpgSession`, `await` its `availableCameras()` (read-only; opens no controller/torch), `dispose()` it, return the list. (Alternatively hold a persistent enumeration session — pick the simplest that keeps controllers-stay-open intact.)
  - `Future<void> dispose()` — idempotent; `await stopMeasurement()`; close all controllers.
  - Keep any internal logs behind the kit log helper style, not raw `print`.

- [x] **Task 3: Add Riverpod providers for the service and its streams** (depends on Task 2)
  Files: `example/lib/providers/camera_ppg_service_provider.dart`, `example/lib/providers/stream_providers.dart`
  Mirror neiry's `neiry_service_provider.dart` / `rr_provider.dart`.
  - `camera_ppg_service_provider.dart`: `final cameraPpgServiceProvider = Provider<CameraPpgService>((ref) { final s = CameraPpgService(); ref.onDispose(s.dispose); return s; });` — this is what releases camera + torch on scope teardown.
  - `stream_providers.dart`: `rrProvider` / `qualityProvider` / `stateProvider` (and `fingerPresenceProvider` if fanned in) as `StreamProvider`s off `ref.watch(cameraPpgServiceProvider).<stream>`; plus a **display-only** `bpmProvider`.
  - **`bpmProvider` must retain the last non-artifact interval** (plan-review Issue 3). The kit emits artifact beats on the same `rrStream` (Task 5 shows them unfiltered), so the *latest* `RrInterval` is frequently `isArtifact == true`; a naive `60000 / rrProvider.value.intervalMs` map would either read BPM off an artifact beat or go null whenever the newest beat is an artifact. Implement it as a `Notifier`/`NotifierProvider<int?>` (or equivalent) that subscribes to `cameraPpgServiceProvider.rrStream`, **ignores** `isArtifact == true` beats, and holds `60000 ~/ intervalMs` from the last accepted beat across intervening artifact ticks (reset to `null` on a new measurement). BPM/HRV are derived in the example only, never pushed into the kit.

### Phase 2: Tab shell

- [x] **Task 4: Wrap the app in a two-tab shell with camera-ownership handoff** (depends on Task 3)
  Files: `example/lib/main.dart`
  Wrap the app in a `ProviderScope` (root). Replace the single `home: AutoDetectScreen()` with a scaffold hosting a `TabBar` + `TabBarView` with two tabs — **Raw** and **Kit API**.
  - **Tab 1 (Raw):** mount the existing `AutoDetectScreen` unchanged (it keeps navigating to the stream inspector via its existing flow). Do **not** rewrite it onto the kit API — it keeps direct `flutter_ppg`/`camera` access as the un-abstracted ground truth.
  - **Tab 2 (Kit API):** mount `KitApiTab` (Task 5).
  - **Camera-ownership handoff (resolves plan-review Issues 1 & 2):** the shell must be a `ConsumerStatefulWidget` owning an explicit `TabController` (not `DefaultTabController`, so it can be listened to). Add a `TabController` listener that, when the selection **leaves Tab 2** (Tab 2 loses focus), calls `ref.read(cameraPpgServiceProvider).stopMeasurement()` — releasing the camera + torch so Tab 1's direct `flutter_ppg`/`camera` open cannot collide with a live `CameraController` (`CameraException`). `ppgLog` this handoff as a coarse milestone. This is the single owner-swap point; without it, starting Tab 2 then running Tab 1 auto-detect double-opens the rear camera.
  Keep it plain — no go_router.

### Phase 3: Kit API tab UI

- [x] **Task 5: Build the Kit API tab** (depends on Task 4)
  Files: `example/lib/screens/kit_api_tab.dart`
  A `ConsumerWidget` (Riverpod) that reads the providers from Task 3 — **no `StreamBuilder`, no per-widget `.listen()`** (subscriptions live in providers so a rebuild never re-subscribes). **Import only the kit barrel** `package:camera_ppg_kit/camera_ppg_kit.dart` — no `CameraImage`/`PPGSignal`/`FlutterPPGService`/`CameraController` type may appear here.
  - **Start / Stop** buttons driving `CameraPpgService.startMeasurement(...)` / `stopMeasurement()` (call `ppgTap('kit_start')` / `ppgTap('kit_stop')` first). Stop returns to idle, not a results screen. Surface a returned `CameraPpgError` (no covered sensor / permission / unsupported) as a message + retry — no torch-strobe loop.
  - **`MeasurementState`** rendered prominently from `stateProvider`: `warmup` → "hold still…", `measuring` → live, `poorSignal` → guidance, `done` → "complete". Render `stateStream` only — never reimplement the lifecycle (it is the kit's, note 09).
  - **RR** from `rrProvider`: latest `intervalMs` plus a short rolling list; show `isArtifact` (do **not** filter rejected beats — a developer wants to see them).
  - **Derived BPM** large + display-only from `bpmProvider`.
  - **SQI chip** from `qualityProvider` + **finger-presence** indicator (from `fingerPresenceProvider`, or note it as optional if not fanned in).
  - **Camera override:** on entry (or a "refresh" action) call `CameraPpgService.availableCameras()` to list rear sensors; show which sensor auto-detect locked; let the user pick one to pass as `cameraId` into the next `startMeasurement(...)` (`session.useCamera(id)` must run before start — the service already sequences this). `ppgTap('kit_camera_override:<id>')` on selection.

- [x] **Task 6: Add the `[debug]` tuning panel to the Kit API tab** (depends on Task 5)
  Files: `example/lib/screens/kit_api_tab.dart`
  A small collapsible panel, clearly labelled `[debug]` so it is never mistaken for host config. It live-tunes the algorithm defaults borrowed from neiry's chest PPG (the calibration handoff after Phase 7 turns good values into the internal defaults):
  - **Session policy** (note 09 `SessionPolicy`): warm-up duration, target duration (and optionally silence window / SQI floor).
  - **RR-gate** (note 12 `RrAcceptance`): `minRrMs`, `consistencyThreshold`, `coldStartBeats`, `medianWindow`.
  Controls edit local state; on the next Start, build a fresh `SessionPolicy(...)` and `RrAcceptance(...)` from the current values and pass them into `startMeasurement(policy: ..., acceptance: ...)` (the session takes both via its constructor). These are the **only** settings in Tab 2 — no exhaustive knob board, no guided-wellness UX, no aggregate result summary.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add Riverpod service and providers for example kit-API dogfooding"
- **Commit 2** (after tasks 4-6): "Add two-tab example shell with Raw and Kit-API tabs"

## Verify (on-device, per note 14)
- **Tab 1** still runs the Phase-2 flow unchanged (auto-detect locks the covered sensor; inspector shows raw `PPGSignal`).
- **Tab 2:** finger on lens+flash → Start → auto-detect locks → `warmup` ("hold still…") → `measuring` with plausible BPM → `done` at the default duration, all with no app-side lifecycle logic. No finger → typed `CameraPpgError` + retry, no torch-strobe loop. Lift finger → finger-presence flips, SQI drops, `isArtifact` beats appear, `poorSignal`, then recovery. BPM holds its last non-artifact value through artifact beats (does not read off rejected beats).
- **Camera-ownership handoff:** Start a measurement in Tab 2, switch to Tab 1, run auto-detect — Tab 1 acquires the camera with **no `CameraException`** (Tab 2 released it on blur; torch off in the gap). Return to Tab 2: the same provider subscriptions are intact (no `Bad state: Stream has already been listened to`); pressing Start resumes measurement. Measurement does **not** continue while Tab 2 is offstage — that is the intended release-on-leave behavior, not a regression.
- **Scope teardown:** app shutdown / root `ProviderScope` teardown fires `cameraPpgServiceProvider`'s `onDispose` → camera + torch released. (App-background / hot-restart release is Phase 9 / note 17, out of scope here.)
