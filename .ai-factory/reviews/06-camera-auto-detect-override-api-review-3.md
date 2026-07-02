# Code Review (Round 3): Camera auto-detect + override API

**Plan:** `.ai-factory/plans/06-camera-auto-detect-override-api.md`
**Files reviewed (in full):** `lib/src/models/camera_ppg_camera_info.dart`, `lib/camera_ppg_kit.dart`, `lib/src/api/camera_ppg_session.dart`
**Verified against:** `camera_platform_interface-2.13.0` (`CameraDescription`, `CameraLensType`, `availableCameras()` throw contract)
**Risk Level:** 🟢 None

## Status vs. prior rounds

- **Round-2 finding fixed.** `availableCameras()` (`camera_ppg_session.dart:497-512`) now wraps `_enumerateRearCameras()` in `try { ... } on CameraException catch (e) { nlog(...); return const []; }`. This restores the kit's "no exceptions across the boundary" discipline for the one public method that previously could leak a raw `CameraException`. `CameraException` is the correct and sufficient type to catch — the `camera` plugin wraps platform-side enumeration failures in it. The dartdoc accurately documents the never-throw contract and the "enumeration-failed and no-cameras both surface as empty" trade-off.
- **Round-1 finding still fixed.** `camera_ppg_camera_info.dart` `lensType` examples (`wide`/`telephoto`/`ultraWide`/`unknown`) match the actual `CameraLensType` members emitted by `d.lensType.name`.

## Correctness re-verification (full pass)

- **Boundary discipline intact.** No `camera`/`flutter_ppg` type crosses the barrel: `availableCameras()` returns `List<CameraPpgCameraInfo>` (a pure value type), `lensType` is stringified via `.name`, and `useCamera(String)` / the pin field are plain Dart.
- **Import resolution clean.** The additive `import 'package:camera/camera.dart' as cam show availableCameras;` alongside the unprefixed import produces no conflict; `_enumerateRearCameras()` calls `cam.availableCameras()`, and the instance method `availableCameras()` legally shadows the unused unprefixed free function inside the class. No recursion, no analyzer error.
- **Pin path concurrency sound.** `_pinnedCameraId` is read into a local after the post-enumerate `stale()` check; `_resolvePinnedCamera` is pure/synchronous (no `await`), so the `_generation` discipline holds without an extra check (the inline comment is accurate). The subsequent controller-setup block retains every post-`initialize()` / post-torch / post-wiring `stale()` check. `useCamera` cannot race `_pinnedCameraId` because it throws while `_running`, which is held for the entire `start()`.
- **Failure paths reset correctly.** A pinned id that doesn't resolve returns `CameraPpgError.cameraUnavailable` and falls through the outer `finally` → `_release()` (`!lockedAndStreaming && !stale()`), clearing `_running` and returning to `idle` with no camera/torch acquired; it does not silently fall back to auto-detect.
- **`useCamera` guard** keyed on `_running` (rejects both `measuring` and the pre-`measuring` round-trip) matches the documented intent and existing guard style.
- **`lensType.name` is null-safe** — `CameraDescription.lensType` is a non-nullable `CameraLensType` (default `unknown`) in 2.13.0.

## Findings

None. All findings from rounds 1 and 2 are resolved, and no new correctness, concurrency, or boundary issues remain. The implementation matches the plan.

REVIEW_PASS
