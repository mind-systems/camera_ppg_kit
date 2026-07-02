# Plan: Neiry-mirror source shell + Source screen

## Context
Restructure the example app so all screens stay mounted and the `CameraPpgService` singleton is the sole owner of the source lifecycle (neiry's connect-once/consume-everywhere), with a dedicated Source screen owning the only Start/Stop control, camera override, permission flow, and the `[debug]` tuning panel — backed by a new shared `sessionConfigProvider`.

## Settings
- Testing: no
- Logging: example convention — every user interaction (Start/Stop, tab switch, camera override/refresh, retry, permission) goes through `ppgTap`/`ppgLog` from `auto_detect/log.dart`, per CLAUDE.md; coarse navigation/lifecycle milestones only.
- Docs: no

## Assumptions / Scope notes
- **Realization choice: plain `Scaffold` + `NavigationBar` + `IndexedStack`** — `go_router` is not currently an example dependency; per spec note 22 the load-bearing property is *all screens stay mounted*, not the router package, so we avoid pulling `go_router` into the example. All branch widgets are children of a single `IndexedStack`, so switching never disposes a screen or drops its provider subscriptions.
- **Branches this milestone: Source, Kit-API, Raw.** The Calibration screen (note 21) is a *separate downstream milestone* that adds its own branch + `main.dart` wiring; it does not exist yet, so no Calibration branch/placeholder is created here. The shell is built so adding a fourth branch later is a one-line change.
- **Camera-id override stays Source-screen-local state** (only the Source screen starts the source); `sessionConfigProvider` holds only `RrAcceptance` + `SessionPolicy`, matching the spec's honesty link for the future calibration screen.
- **In-force config caveat (matches the old Kit-API panel):** the panel edits `sessionConfigProvider` directly and the edited value is passed on the *next* `startMeasurement` — a knob change applies on edit → Stop → Start. The provider is treated as "the in-force config" the same way the old panel did (note 22); no separate applied-snapshot is introduced.
- **Status helpers are intentionally duplicated, not shared.** `_stateBanner`/`_qualityAndPresenceRow` are private methods; both the Source screen and the Kit-API consumer legitimately display live status, so each keeps its own copy. Only *lifecycle/control* (Start/Stop, permission, camera override, `[debug]` panel) is relocated Source-ward — the display helpers are deliberately present on both screens. Do not try to factor them into a shared widget, and do not strip them from Kit-API.
- **Raw-in-flight residual race (known, accepted):** the exclusivity hook fires on *entering* Raw, cleanly covering the common case. The symmetric residual remains — if a user triggers Raw's multi-second probe round-trip and, while it is still running, switches to Source and presses Start, Raw's in-flight round-trip still holds the camera and the kit's open could hit a `CameraException`. The shell cannot cheaply cancel Raw's in-flight round-trip; this mirrors the previously-accepted residual and is left as a known edge on a developer instrument, not fixed here.
- **Untouched-provider doc drift (noted, not actioned):** `camera_ppg_service_provider.dart` ("for the example app's Kit-API tab") and `stream_providers.dart` ("the Kit-API tab shows…") will read inaccurately once lifecycle moves Source-ward. They are guard files (untouched this milestone) — the drift is flagged for a future doc pass, not corrected here.

## Guards (do not touch)
- Kit `lib/` — untouched.
- `example/lib/calibration/calibration_recorder.dart` (note 20) — untouched.
- `example/lib/services/camera_ppg_service.dart` (note 16) — untouched; the Source screen *commands* it (`startMeasurement`/`stopMeasurement`), it still *owns* the session.
- `example/lib/providers/camera_ppg_service_provider.dart` and `stream_providers.dart` (incl. `BpmNotifier`) — untouched; consumers keep reading the same providers.
- `example/lib/auto_detect/auto_detect_screen.dart` (Raw) — untouched; it keeps opening its own `CameraController` only on its explicit Start and tearing down on leave.

## Tasks

### Phase 1: Shared session-config provider

- [x] **Task 1: Add `sessionConfigProvider` holding the in-force `RrAcceptance` + `SessionPolicy`**
  Files: `example/lib/providers/session_config_provider.dart` (new)
  Import the kit barrel (`package:camera_ppg_kit/camera_ppg_kit.dart`) — `RrAcceptance` and `SessionPolicy` are exported `[debug]` extras (ARCHITECTURE.md dependency rules), so no `src/` import is needed.
  Define an immutable value type `SessionConfig { final RrAcceptance acceptance; final SessionPolicy policy; }` with a default const/factory constructor seeding `RrAcceptance()` + `SessionPolicy()` (the kit's own defaults — never invent numbers), and a `copyWith({RrAcceptance? acceptance, SessionPolicy? policy})`.
  Expose a `NotifierProvider<SessionConfigNotifier, SessionConfig>` whose `build()` returns the default `SessionConfig`, with granular mutators the Source screen calls on field submit (e.g. `setWarmupSeconds`, `setTargetSeconds`, `setSilenceSeconds`, `setSqiFloor`, `setMinRrMs`, `setConsistencyThreshold`, `setColdStartBeats`, `setMedianWindow`) — each rebuilds the relevant `SessionPolicy`/`RrAcceptance` and calls `copyWith`. This is the *same* provider the future calibration screen (note 21) will read for the actual in-force params, so keep it the single source of truth for the config.

### Phase 2: Source screen (sole lifecycle control)

- [x] **Task 2: Create the Source screen — Start/Stop, camera override, permission, status, `[debug]` panel** (depends on Task 1)
  Files: `example/lib/screens/source_screen.dart` (new)
  `ConsumerStatefulWidget` mirroring neiry's `device_screen` — the **only** screen that issues `service.startMeasurement()` / `stopMeasurement()`. Move the following, currently in `kit_api_tab.dart`, here (they are being *relocated*, not duplicated — Task 4 removes them from Kit-API):
  - **Start/Stop control** (`_start`/`_stop`, `_startStopRow`, `isRunning`/`canStop` derivation incl. the `done`-recovery path that calls `stopMeasurement()` before restart), reading `stateProvider` for enable/disable.
  - **Permission flow** — reuse the exact `_checkAndRequestCameraPermission()` pattern (note 15): granted → proceed; denied → retryable error banner; permanently-denied/restricted → `openAppSettings()` + `CameraPpgError.permissionDenied(permanentlyDenied: true)`. Keep the `_lastError`/`_errorBanner`/Retry UI.
  - **Camera override** — `_loadCameras()` (via `service.availableCameras()`, post-frame-callback to avoid setState-during-build), `_selectedCameraId` local state, Refresh button, `DropdownButton` with the stale-selection guard; pass `cameraId: _selectedCameraId` into `startMeasurement`.
  - **`[debug]` tuning panel (variant B, kept)** — the `SessionPolicy` (warmup/target/silence/sqiFloor) + `RrAcceptance` (minRrMs/consistencyThreshold/coldStartBeats/medianWindow) fields, but *seed field values from and write edits to* `ref.watch(sessionConfigProvider)` / its notifier instead of local `_warmupSeconds`-style fields. On Start, pass `policy: config.policy, acceptance: config.acceptance` from the provider (not from ad-hoc locals). Keep the "Applies on the next Start" hint. **Preserve the `_intField`/`_doubleField` value-keyed re-seed pattern:** keep `key: ValueKey('$label-$value')` bound to the *provider-derived* value + `initialValue: value.toString()`, so submit → notifier write → rebuild → new key → new `initialValue` re-seeds the `TextFormField` to the round-tripped provider value. A plain `initialValue` without the value-keyed `ValueKey` would show stale text after submit — the pattern must carry over unchanged from `kit_api_tab.dart`.
  - **Source status** — the Source screen holds its **own copy** of `_stateBanner(state)` and `_qualityAndPresenceRow()` (SQI chip + finger-presence label from `qualityProvider`/`fingerPresenceProvider`) so the operator confirms the source is live before navigating to a consumer screen. These display-only helpers are intentionally duplicated with Kit-API (see Scope notes) — not relocated, not factored into a shared widget.
  - Wrap the screen body in `SafeArea` (as Kit-API does) so it sits correctly under the shell's shared `AppBar` (Task 3).
  Follow the example logging convention: `ppgTap('source_start')`, `ppgTap('source_stop')`, `ppgTap('source_camera_override:…')`, `ppgTap('source_refresh_cameras')`, `ppgTap('source_permission_request')`, retry, etc.

### Phase 3: All-mounted shell

- [x] **Task 3: Rewrite `main.dart` shell to `NavigationBar` + `IndexedStack` with Raw exclusivity** (depends on Task 2)
  Files: `example/lib/main.dart`
  Replace `_TabShell` (`TabController`/`TabBarView` + the `_onTabChanged` "leaving Kit-API → stop" rule) with a `ConsumerStatefulWidget` holding a selected-index int and a `Scaffold` whose `body` is an `IndexedStack(index: _selected, children: [...])` and whose `bottomNavigationBar` is a `NavigationBar` with destinations **Source / Kit API / Raw**. All children stay mounted across switches — navigation never stops measurement or breaks streams (the load-bearing property, note 22).
  - **Identify branches by a named enum, not a magic index (protects the "one-line change" promise).** Define an ordered `_Branch { source, kitApi, raw }` enum (or equivalent named identifiers) and build both the `IndexedStack` children and the `NavigationBar` destinations from it, so `_selected`/`onDestinationSelected` map through the enum. Gate the exclusivity hook on `_Branch.raw` (the enum case / a `_rawIndex` derived from it), **never** a literal `if (index == 2)`. Rationale: the next milestone (note 21) inserts a **Calibration** branch *before* Raw (`Source / Kit-API / Calibration / Raw`); a literal index would then fire the hook on Calibration (stopping a source it depends on) and miss Raw. Enum-based identification keeps inserting Calibration a genuine one-line, index-shift-safe change.
  - Keep exactly **one** narrow navigation hook in `onDestinationSelected`: when the newly-selected branch is `_Branch.raw`, call `ref.read(cameraPpgServiceProvider).stopMeasurement()` (fire-and-forget, as today) so the kit source and Raw's direct camera round-trip never contend for the exclusive camera (note 01). Selecting Source or Kit-API does **not** stop anything.
  - **Top chrome:** give the shell `Scaffold` a single `AppBar` with a per-branch title (e.g. `['Source','Kit API','Raw'][index]`) so all three branches show a consistent title bar. `AutoDetectScreen` (Raw) carries its own `Scaffold`+`AppBar` and remains a guard file (untouched) — accept it rendering as a nested `Scaffold` inside the shell (legal; the shell's bottom nav still renders once); do not modify Raw to remove its `AppBar`. Ensure the new Source screen wraps its body in `SafeArea` like Kit-API does, so the two bare-`ListView` branches sit correctly under the shared `AppBar`.
  - Log the transition with `ppgTap('nav:<branch>')`. Set the initial index to Source. Drop the `SingleTickerProviderStateMixin`/`TabController` and the old release comment block.

### Phase 4: Kit-API → pure consumer

- [x] **Task 4: Strip `kit_api_tab.dart` to a `ref.watch`-only consumer** (depends on Task 2)
  Files: `example/lib/screens/kit_api_tab.dart`
  Remove everything moved to the Source screen: Start/Stop (`_start`/`_stop`/`_startStopRow`), the `done`-recovery logic, permission flow (`_checkAndRequestCameraPermission`, `permission_handler` import), camera override (`_loadCameras`/`_selectCamera`/`_cameraOverrideSection`/`_selectedCameraId`/`_cameras`/`_loadingCameras`), `_lastError`/`_errorBanner`, and the local `[debug]` knob fields + `_debugPanel`/`_intField`/`_doubleField`/`_buildPolicy`/`_buildAcceptance`.
  Keep it a display-only consumer of the live streams via the existing providers: `_stateBanner` (from `stateProvider`), `_qualityAndPresenceRow` (SQI + finger-presence), `_bpmSection` (`bpmProvider`), and `_rrSection` (latest RR + `isArtifact` + the rolling `_rrHistory` list cleared on `warmup` via the existing `ref.listen`). No lifecycle, no camera, no `startMeasurement`/`stopMeasurement`, no `service` command calls — it must not open a `StreamBuilder` or a per-widget `.listen()` beyond the existing provider `ref.listen`s. It may stay a `ConsumerStatefulWidget` solely for the `_rrHistory` UI-only rolling list.
