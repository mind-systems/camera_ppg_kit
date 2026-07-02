# Code Review: Camera auto-detect + override API

**Plan:** `.ai-factory/plans/06-camera-auto-detect-override-api.md`
**Files reviewed (in full):** `lib/src/models/camera_ppg_camera_info.dart` (new), `lib/camera_ppg_kit.dart`, `lib/src/api/camera_ppg_session.dart`
**Verified against:** `camera_platform_interface-2.13.0` `CameraDescription` / `CameraLensType` (installed package source)
**Risk Level:** 🟢 Low

## Summary

The change implements exactly the planned surface: a pure `CameraPpgCameraInfo` value type, a read-only `availableCameras()`, a `useCamera(id)` pin guarded on `_running`, and a pin branch inserted into `start()` before `_lockCoveredCamera`. The two plan-review criticals were both addressed correctly in code:

- **Import shadowing** — solved with the additive `show`-scoped import (`import 'package:camera/camera.dart' as cam show availableCameras;`) while keeping the unprefixed import for all types; `_enumerateRearCameras()` now calls `cam.availableCameras()`. No infinite recursion, no ambiguity: the unprefixed import still resolves `CameraController`/`CameraException`/etc., and the instance method `availableCameras()` shadows the (now unused) unprefixed free function only within the class — a member shadowing an imported top-level name is legal Dart and does not error.
- **`flashAvailable`** — pinned to the documented constant `true` with an accurate caveat that it is an unverified assumption and must not gate selection. `CameraDescription` indeed exposes no flash-capability property (confirmed against the 2.13.0 source), so this is the honest choice.

Correctness checks that pass:

- **Boundary discipline intact.** `CameraDescription` stays internal; only `CameraPpgCameraInfo` (a pure value type, no `camera`/`flutter_ppg` import) crosses the barrel. `d.lensType.name` yields a `String`, so the `CameraLensType` enum does not leak.
- **`lensType` access compiles.** `CameraDescription.lensType` is a non-nullable `CameraLensType` (default `unknown`) in 2.13.0 — `d.lensType.name` is safe, no null risk.
- **Pin branch re-entrancy is sound.** `_pinnedCameraId` is read into a local before use; `_resolvePinnedCamera` is pure/synchronous, so no `await` occurs between the post-enumerate `stale()` check and the resolve (the inline comment is accurate). The controller-setup block that follows keeps all the existing post-`initialize()` / post-torch / post-wiring `stale()` checks, so the override path has the same concurrency discipline as auto-detect.
- **Failure path resets cleanly.** A pinned id that doesn't resolve returns `CameraPpgError.cameraUnavailable` and falls through the outer `finally`, which runs `_release()` (`!lockedAndStreaming && !stale()`), clearing `_running` and returning to `idle` — no camera/torch acquired on that path, no stranded `_running`. It correctly does **not** silently fall back to auto-detect.
- **`useCamera` guard** is keyed on `_running` as intended (rejects both `measuring` and the pre-`measuring` round-trip window), matching the existing `_running`/`_disposed` guard style. Re-calling replaces the pin; there is deliberately no un-pin API, per plan scope.

## Findings

### Low 1 — Dartdoc lists `lensType` example strings that the platform never emits

`lib/src/models/camera_ppg_camera_info.dart:27-29` documents the `lensType` field with examples `wideAngle`, `telephoto`, `ultraWideAngle`, `unknown`. The value is produced by `d.lensType.name` (`camera_ppg_session.dart:494`), and `CameraLensType` in camera_platform_interface 2.13.0 has members `wide`, `telephoto`, `ultraWide`, `unknown` — so the actual emitted strings are `"wide"` and `"ultraWide"`, not `"wideAngle"` / `"ultraWideAngle"`.

**Impact:** documentation only — no runtime bug. But this is a public (barrel-exported) value type, and a consumer who reads the dartdoc and writes `if (info.lensType == 'wideAngle')` for a display label would silently never match. Worth correcting the two wrong examples to `wide` / `ultraWide` so the doc matches the emitted values. Non-blocking.

## Notes (no action required)

- The public `availableCameras()` and `useCamera()` intentionally have no `_disposed` guard; both are harmless post-dispose (`availableCameras()` opens nothing; a stale pin is inert because `start()` returns the disposed error first). Fine as-is.
- Manual override deliberately skips coverage detection, so a pinned `start()` will enter `measuring` even with no finger present, emitting poor-quality data until the consumer stops. This is the documented override contract; quality/finger-presence gating is a later phase. Not a defect.

The single finding above is a non-blocking documentation nit; the implementation itself is correct and matches the plan.
