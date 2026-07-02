# Plan: Camera auto-detect + override API

## Context
Layer a manual-override escape hatch on top of the already-shipped auto-detect `start()`: add a descriptive `availableCameras()` rear-camera list and a `useCamera(id)` pin that skips the round-trip and forces the next `start()` onto one chosen sensor — same code on Android (one logical back) and iOS (every rear lens).

## Settings
- Testing: no (the surface is hardware-bound — `availableCameras()`/`start()` need a real `CameraController`, verified on-device via the example; the only pure bit, id→description resolution, fails loudly with a typed error, not silently)
- Logging: minimal (kit-internal `nlog` only, per CLAUDE.md / rules — no `print`/`debugPrint`)
- Docs: no

## Assumptions / Scope boundaries
- **Auto-detect already exists.** `CameraPpgSession.start()` (milestone 05) already runs the signal-based coverage round-trip and locks the first covered sensor, and `_enumerateRearCameras()` / `_lockCoveredCamera()` / `_probeCameraCoverage()` are in place. This milestone only *adds* the override surface + the diagnostics list on top — it does not rewrite the round-trip.
- **`CameraDescription` must not cross the barrel** (ARCHITECTURE.md line 48/114). The public `availableCameras()` returns kit-model `CameraPpgCameraInfo`, never the `camera` plugin's `CameraDescription`. The private `_enumerateRearCameras()` keeps returning `CameraDescription` for internal use.
- **Name-shadowing gotcha (load-bearing).** The kit currently calls the `camera` plugin's top-level `availableCameras()` unqualified inside `_enumerateRearCameras()`. Adding a public **instance** method also named `availableCameras()` would shadow that top-level call from inside the class and turn `_enumerateRearCameras()` into infinite recursion. Fix it with an **additive, `show`-scoped** import — keep the existing unprefixed import so every type (`CameraController`, `CameraDescription`, `CameraImage`, `CameraException`, `CameraLensDirection`, `FlashMode`, `ResolutionPreset`, `ImageFormatGroup`, `ExposureMode`, `FocusMode`, …) still resolves, and add one aliased import that pulls in *only* the free function:

  ```dart
  import 'package:camera/camera.dart';                              // keep — all types resolve unprefixed
  import 'package:camera/camera.dart' as cam show availableCameras; // disambiguation only
  ```

  Then call `cam.availableCameras()` at the single enumeration site. **Do not** re-prefix the whole file (a single `as cam;` import would leave every unprefixed camera type undefined — a non-compiling intermediate).
- **Override takes effect on the next `start()` — no mid-stream hot-swap** (note 08 Guards). `useCamera` only records the pin; `start()` reads it.
- **Metadata is descriptive only** (id, lens type, `flashAvailable`) — kept as plain fields / a map, not a brittle enum, so unknown future lens types decode fine. The host reads it for display and override, never for selection (note 08 Guards).
- **No new `MeasurementState`** and **no new `CameraPpgError` type.** A pinned id that no longer resolves to a rear camera reuses `CameraPpgError.cameraUnavailable`. `useCamera` mid-measurement throws a plain `StateError` (a programmer error, not an expected boundary state — exceptions are reserved for exactly this per rules/base.md).
- **Reference:** `.ai-factory/notes/08-camera-selection-api.md` (§ "Added to `CameraPpgSession`", "Verify", "Guards").

## Tasks

### Phase 1: Camera-info model

- [x] **Task 1: Add `CameraPpgCameraInfo` value type + barrel export**
  Files: `lib/src/models/camera_ppg_camera_info.dart`, `lib/camera_ppg_kit.dart`
  Add an `@immutable` value type describing one selectable rear camera for override/diagnostics. Fields: `final String id` (the selection key = `CameraDescription.name`), and descriptive-only metadata — `final String lensType` (string, not an enum; frequently `unknown` — see the note's "keep metadata a map/plain fields, not a brittle enum" guard) and `final bool flashAvailable`. Keep it a pure value type (no `camera`/`flutter_ppg` import) — construct it *from* a `CameraDescription` at the API edge (Task 2), not by holding one. Dartdoc must state the metadata is descriptive only and never drives selection. Export it from the barrel (`export 'src/models/camera_ppg_camera_info.dart';`). Follow the existing `models/` style (cf. `finger_presence.dart`, `camera_ppg_error.dart`).
  **`flashAvailable` value/source (review Critical #1):** `CameraDescription` exposes no flash/torch-capability property, and Task 2 forbids opening a controller to query one, so there is no data source at enumeration time. Since the field is display-only and never gates anything, set it to the documented constant `true` for every rear entry (the kit runs the torch on the rear camera throughout capture) and add a dartdoc caveat that it is an unverified rear+torch assumption, not a probed capability, and must never be used to select or gate. Do not add a controller-backed probe for it in this milestone.

### Phase 2: Session override surface

- [x] **Task 2: Public `availableCameras()` returning the descriptive rear list** (depends on Task 1)
  Files: `lib/src/api/camera_ppg_session.dart`
  First apply the shadowing fix from the scope note: keep the existing unprefixed `import 'package:camera/camera.dart';` (so all types still resolve) and **add** `import 'package:camera/camera.dart' as cam show availableCameras;`, then change the one call in `_enumerateRearCameras()` from `availableCameras()` to `cam.availableCameras()`. Do not re-prefix the rest of the file. Then add `Future<List<CameraPpgCameraInfo>> availableCameras()`: reuse `_enumerateRearCameras()` (back-facing, enumeration order) and map each `CameraDescription` → `CameraPpgCameraInfo(id: d.name, lensType: d.lensType.name, flashAvailable: true)` (`lensType` is a `CameraLensType` enum — `.name` gives the string, per review; `flashAvailable` is the documented constant from Task 1). Android yields one logical back entry, iOS several — same code. This is a read-only diagnostics/override list; it must not open a controller or touch the torch.

- [x] **Task 3: `useCamera(id)` pin + mid-measurement guard** (depends on Task 2)
  Files: `lib/src/api/camera_ppg_session.dart`
  Add a nullable `String? _pinnedCameraId` field (default `null` = auto-detect). Implement `void useCamera(String id)`: throw `StateError` if `_running` is `true` — mirror the existing `_disposed`/`_running` guard style — otherwise record `_pinnedCameraId = id`. Re-calling replaces the pin. **Guard breadth is intentional (review Minor note):** `_running` is set `true` at the very top of `start()` for the whole auto-detect round-trip, before state reaches `measuring`, so this also (correctly) rejects `useCamera` during the pre-`measuring` setup window. Keep it keyed on `_running`; do not "tighten" it to `_state == measuring` (that would open a race during setup). Dartdoc: must be called before `start()`; takes effect on the next `start()`; no mid-stream hot-swap. Do not add an un-pin API (out of scope — note 08 lists only `useCamera(id)`).

- [x] **Task 4: Honor the pin in `start()` — skip the round-trip, lock the chosen sensor** (depends on Task 3)
  Files: `lib/src/api/camera_ppg_session.dart`
  In `start()`, after `_enumerateRearCameras()` (and its `stale()`/empty checks) and **before** `_lockCoveredCamera(...)`, branch on `_pinnedCameraId`: when non-null, resolve it against the enumerated list by `name`; on a match, use that `CameraDescription` directly and skip the coverage round-trip entirely (no `_lockCoveredCamera`, no probe) — proceed straight to the existing controller-open / torch / bridge / stream-wiring block with that description. On no match, return `CameraPpgError.cameraUnavailable(message: ...)` and fall through the existing failure path (which clears `_running` and returns to `idle` via `_release()`) — do not silently fall back to auto-detect. When `_pinnedCameraId` is null, behavior is unchanged (run `_lockCoveredCamera` as today). Keep the `_generation`/`stale()` re-entrancy discipline intact on the new branch. The resolve step is a pure list lookup — factor it small if it aids clarity, but no test task is required (it fails loudly via the typed error).

## Verify (on-device, via the example)
Matches note 08 "Verify": on a multi-camera phone, finger-first `start()` with no `useCamera` still auto-locks the covered sensor; `availableCameras()` lists the rear sensors; `useCamera(<id>)` then `start()` uses exactly that sensor (skipping the round-trip); `useCamera` during `measuring` throws `StateError`; a pinned id that isn't present yields `CameraPpgError.cameraUnavailable`.
