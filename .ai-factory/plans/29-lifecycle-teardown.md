# Plan: Lifecycle & teardown

## Context
Release the app-level camera + torch when the example app is backgrounded (and re-acquire on foreground) by adding a `WidgetsBindingObserver` at the shell level in `example/lib/main.dart` — the kit-side ordered `_release()` already exists, so this is example-only lifecycle wiring driving `CameraPpgService.stopMeasurement()`.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: App-shell lifecycle observer

- [x] **Task 1: Release the source on background via a shell-level `WidgetsBindingObserver`**
  Files: `example/lib/main.dart`
  Make `_ShellState` mix in `WidgetsBindingObserver`. Declare a shell-local flag **`bool _wasMeasuring = false;`** (default `false` — it is only ever set `true` under the `isMeasuring` guard below and cleared in Task 2; a `true` default would auto-start an operator-never-requested measurement on the first background-while-idle → foreground sequence, bypassing the Source screen's Start button and permission pre-check). Add an `initState` that calls `super.initState()` then `WidgetsBinding.instance.addObserver(this)`, and a `dispose` that calls `WidgetsBinding.instance.removeObserver(this)` before `super.dispose()`. Override `didChangeAppLifecycleState(AppLifecycleState state)`:
  - On `AppLifecycleState.inactive` or `AppLifecycleState.paused`: if `ref.read(cameraPpgServiceProvider).isMeasuring`, set `_wasMeasuring = true` (used by Task 2), log a coarse milestone via `ppgLog` (e.g. `'Shell: app backgrounded — releasing kit source'`), then call `ref.read(cameraPpgServiceProvider).stopMeasurement()` (not awaited — the lifecycle callback can't be async; `stopMeasurement()` flips lifecycle to `stopping` synchronously and runs the ordered kit release, same pattern already used for the Raw-entry hook at `main.dart:88-104`). If not measuring, do nothing (leave `_wasMeasuring` untouched).
  - Other states (`resumed`, `detached`, `hidden`): handled in Task 2 (`resumed`) / no-op otherwise.
  This is the app-shell-level observer the spec (note 17) mandates — it releases the app-level `CameraPpgService` source (`stopMeasurement()`, the single teardown funnel), never a per-screen observer, and the kit stays Flutter-binding-free. Hot-restart is covered for free: the start-path builds a fresh `CameraPpgSession`/`CameraController` each `startMeasurement`, so a stale handle from a prior Dart VM is never reused; the added `removeObserver` in `dispose` keeps the observer registration clean.
  **Double-fire is safe:** backgrounding on Android fires `inactive` then `paused`, so this branch runs twice; the un-awaited `stopMeasurement()` is idempotent (`session.dispose()`/`sub.cancel()` guard against re-entry, service.dart:214-241), and re-setting an already-`true` `_wasMeasuring` is a no-op — no extra debounce needed.

- [x] **Task 2: Re-arm on foreground when a measurement was active** (depends on Task 1)
  Files: `example/lib/main.dart`
  Extend `didChangeAppLifecycleState` to handle `AppLifecycleState.resumed`: if the shell-local `_wasMeasuring` flag is set, clear it (`_wasMeasuring = false`) and re-arm by calling `ref.read(cameraPpgServiceProvider).startMeasurement(policy: config.policy, acceptance: config.acceptance)` where `config = ref.read(sessionConfigProvider)` — reusing the in-force `[debug]` tuning (mirrors how `source_screen.dart:107-113` starts a measurement). Log a coarse `ppgLog` milestone. Omit `cameraId` so the re-arm runs the signal-based auto-detect round-trip (the operator-selected override lives in `SourceScreen`'s local state and is not reachable from the shell — auto-detect is the safe default for re-acquisition; the operator can still re-pick on the Source screen). If `_wasMeasuring` is not set, do nothing — the operator re-presses Start on the Source screen. Because the source is a `CameraPpgService` singleton feeding long-lived broadcast controllers surfaced through `lifecycleProvider`, the UI reflects re-acquisition (`starting → warmup → …`) rather than a frozen preview, satisfying the spec's "surface `MeasurementState`" requirement without extra wiring.
  **Permission pre-check is deliberately skipped on re-arm:** unlike the Source screen's Start (which runs `_checkAndRequestCameraPermission` first), the re-arm calls `startMeasurement()` directly. This is safe — permission was necessarily granted for the measurement that had been running, and if it were somehow revoked the kit maps it to a `CameraPpgError` value (note 18) rather than throwing, so the un-awaited re-arm degrades to a silent no-op the operator can retry from the Source screen.

## Notes for the implementer
- Do **not** touch kit `lib/` — the ordered, idempotent `_release()`/teardown in `CameraPpgSession` (notes 07/13) is already correct and frozen; this milestone only adds the host observer that decides *when* to invoke it.
- All teardown goes through `CameraPpgService.stopMeasurement()` (the single funnel) — never call `session.dispose()`/`stop()` directly from `main.dart`.
- `stopMeasurement()` is a no-op when not measuring and is idempotent, so the guard on `isMeasuring` is for the `_wasMeasuring` flag, not for safety.
