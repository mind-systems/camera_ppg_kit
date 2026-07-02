# Plan Review: Camera auto-detect + override API

**Plan:** `.ai-factory/plans/06-camera-auto-detect-override-api.md`
**Files Reviewed:** plan + `lib/src/api/camera_ppg_session.dart`, `lib/camera_ppg_kit.dart`, `lib/src/models/camera_ppg_error.dart`, note 08, ARCHITECTURE.md, ROADMAP.md, `camera_platform_interface` `CameraDescription`
**Risk Level:** 🟡 Medium

## Context Gates

- **Architecture (PASS).** The plan honors the barrel-is-the-contract boundary: `CameraPpgCameraInfo` is a pure `models/` value type, `CameraDescription` never crosses the public signature (Assumptions §2), and it reuses the existing typed-error path instead of throwing across the boundary. Cited ARCHITECTURE lines (48 = no `camera` type leaks; 113/114 = anti-patterns) are accurate.
- **Rules (WARN).** No `.ai-factory/RULES.md` present in this repo. The plan references `rules/base.md` (Assumption §6, "exceptions reserved for programmer errors") — that file is not in `.ai-factory/`; the referenced convention is consistent with ARCHITECTURE §3 ("No exceptions across the channel" for *expected* states), so `StateError` for a programmer error is defensible. Non-blocking.
- **Roadmap (PASS).** Cleanly linked to ROADMAP Phase 4, milestone "Camera auto-detect + override API" (line 30), and matches its spec pointer (note 08). Scope ("adds override surface + diagnostics list on top of the already-shipped auto-detect") matches the milestone text and the current code.

## Critical Issues

### 1. `flashAvailable` has no data source at enumeration time — fantasy hole (must resolve before implementation)

Task 1 and Task 2 give `CameraPpgCameraInfo` a `final bool flashAvailable` field, and Task 2 says to populate it `flashAvailable: <best-effort>`. But:

- `CameraDescription` (camera_platform_interface 2.13.0) exposes **only** `name`, `lensDirection`, `sensorOrientation`, and `lensType`. There is **no** `flashAvailable` / torch-capability property.
- Task 2 explicitly forbids opening a `CameraController` or touching the torch in `availableCameras()` ("it must not open a controller or touch the torch"). Flash/torch availability is only knowable by opening a controller (or a native query, which the roadmap and note 08 rule out — no native code).

So `<best-effort>` is undefined and the implementer must guess. Pin it concretely. Since note 08's guard states this metadata is **descriptive/display only and never drives selection**, the cheapest honest choice is to hardcode a documented constant (e.g. `flashAvailable: true` for every rear entry, with a dartdoc caveat that it is an unverified assumption for rear+torch and must not gate anything). Alternatively drop the field until a controller-backed source exists. Either way the plan should state the value and its justification rather than leave `<best-effort>`.

### 2. Import-prefix instruction under-scopes the refactor — would not compile as literally written

Task 2 (and Assumptions §3) says to change the import to `import 'package:camera/camera.dart' as cam;` and then "update every existing use of the plugin's top-level `availableCameras()` … **plus any other now-ambiguous `camera`-package identifiers the prefix touches at those sites**." That phrasing implies a small local edit, but a single **prefixed** import makes *every unprefixed camera identifier in the whole file* undefined — not just "at those sites." The file uses many: `CameraController`, `CameraDescription`, `CameraImage`, `CameraException`, `CameraLensDirection`, `FlashMode`, `ResolutionPreset`, `ImageFormatGroup`, `ExposureMode`, `FocusMode`. Following the instruction (swap to a prefixed import, but only touch the enumeration site) leaves the rest of the file uncompilable.

The shadowing problem itself is **correctly diagnosed** — adding an instance method `availableCameras()` shadows the top-level `package:camera` function inside the class, turning `_enumerateRearCameras()` into infinite recursion. Good catch. But the minimal fix is a *second, additive* import rather than reprefixing everything:

```dart
import 'package:camera/camera.dart';                 // keep — all types resolve unprefixed
import 'package:camera/camera.dart' as cam show availableCameras;  // only for disambiguation
```

Then unqualified type names stay valid, `cam.availableCameras()` unambiguously calls the plugin function at the one enumeration site, and the new public instance method `availableCameras()` no longer collides. The plan should adopt this (or explicitly commit to prefixing the entire file); as written it is ambiguous in a way that produces a non-compiling intermediate.

## Minor Notes / Confirmations

- **`lensType` conversion (confirmed available).** `CameraDescription.lensType` **does** exist and is a `CameraLensType` enum (`wide`/`telephoto`/`ultraWide`/`unknown`). Task 1's "string, not an enum, frequently `unknown`" is accurate; the concrete conversion is `d.lensType.name`. Storing it as a `String` (not re-exporting the `CameraLensType` enum) is the right call for the "no `camera` type crosses the barrel" rule.
- **`useCamera` guard is broader than "mid-measurement" — acceptable but note it.** Task 3 keys the `StateError` on `_running`, which is set `true` at the very top of `start()` for the entire auto-detect round-trip, before state reaches `measuring`. So `useCamera` also throws during the pre-measuring round-trip window, not only during `measuring`. That is safe and conservative, and matches the existing `_running`/`_disposed` guard style — just call it out so the implementer keeps it intentional rather than "fixing" it to check `_state == measuring` only (which would open a race during setup).
- **Task 4 pin path — sound.** Inserting the pin branch after the enumerate + empty/`stale()` checks and before `_lockCoveredCamera`, resolving by `CameraDescription.name`, reusing the existing controller-open/torch/bridge/stream block, and returning `CameraPpgError.cameraUnavailable` on no match, all fit the current structure. `CameraPpgError.cameraUnavailable({String? message})` exists (verified). Keeping the `_generation`/`stale()` discipline on the new branch is correctly required; note the pin branch has no `stale()` check between enumerate and controller-open, but the controller-open block's own post-`initialize()` `stale()` checks cover it — fine.
- **No new `MeasurementState` / no new error type — consistent** with note 08 and the existing code; correctly reuses `cameraUnavailable` and `StateError`.

## Positive Notes

- The load-bearing name-shadowing hazard is identified up front rather than discovered at compile time — strong.
- Boundary discipline is exactly right: pure `CameraPpgCameraInfo` model, no `CameraDescription`/`camera` leak, barrel export called out, private `_enumerateRearCameras()` keeps returning `CameraDescription` internally.
- Correctly scoped as additive over milestone 05: does not rewrite the round-trip, reuses `_enumerateRearCameras()`, and defers acceptance/policy to later phases.
- Verify section is on-device and mirrors note 08's acceptance list precisely.

## Verdict

Two concrete gaps must be closed in the plan before implementation: (1) define `flashAvailable`'s value/source (or drop the field), and (2) correct the import-prefix instruction to an additive `show`-scoped import (or commit to whole-file prefixing). Both are localized and fixable in-plan; the architecture and roadmap alignment are sound.
