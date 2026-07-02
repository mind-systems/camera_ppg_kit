# Code Review: 04 — State & error types

**Scope:** `lib/src/models/measurement_state.dart`, `lib/src/models/finger_presence.dart`, `lib/src/models/camera_ppg_error.dart`, `lib/camera_ppg_kit.dart` (barrel), `test/models_test.dart`
**Plan:** `.ai-factory/plans/04-state-error-types.md`
**Verification:** `flutter test test/models_test.dart` → 27/27 pass. `flutter analyze` on all five files → no issues.

## Summary

Pure-Dart value types, no I/O, no native channel, no migrations — the runtime surface is limited to enum/factory construction, all of which is exercised by the test suite. The implementation matches the corrected plan exactly, including the two-issue rework from plan-review-1:

- `FingerPresence.fromRawIntensity(double)` classifies from the continuous red-channel intensity with two thresholds (`_presenceMin` 30.0 / `_overBrightMax` 250.0), so `overBright` is reachable and distinct from `absent`. The `present` band (`> 30 && < 250`) is exactly `flutter_ppg`'s `isFingerPresent` true-set — boundary values (30.0 → `absent`, 250.0 → `overBright`) are consistent with `flutter_ppg`'s strict comparisons (both classify as not-present). NaN is guarded first → `absent`.
- `CameraPpgError` uses a private constructor + named factories, models errors as never-thrown values (`@immutable`, no exception path), and exposes `fromCameraErrorCode(String, {description})` (code-string mapping, not `fromMap`) matching the no-native-channel reality. No `orNull`/numeric-sentinel dead code. `unsupportedDevice` carries no hard-coded model names.
- `MeasurementState` is a plain five-value lifecycle enum with a cardinality guard test.
- Barrel exports all three types; consumers never reach into `src/`.

## Correctness checks performed

- Boundary math for `FingerPresence` verified against both thresholds and against `flutter_ppg-0.2.4`'s `SignalQualityAssessor.isFingerPresent` — the `present` set matches exactly. NaN handling correct.
- `CameraPpgError` factory defaults (`permanentlyDenied = false`) and the `permissionDenied(permanentlyDenied: true)` / `CameraAccessDeniedWithoutPrompt` paths verified by tests.
- Unknown-code fallthrough preserves the raw code in `message` (no silent loss).
- No unused imports; `foundation.dart` is imported only where `@immutable` is used.

## Non-blocking observations (defer to the API-wiring phase, not this milestone)

1. **`fromCameraErrorCode` guesses some code strings.** The permission codes (`CameraAccessDenied`, `CameraAccessDeniedWithoutPrompt`, `CameraAccessRestricted`) are real `package:camera` `CameraException` codes, but the torch/camera-unavailable branches (`torchUnavailable`, `setFlashModeFailed`, `cameraNotFound`, `CameraNotFound`) are best-effort and not verified against the plugin's actual emitted codes. The impact is bounded: any unmatched real code falls through to `cameraUnavailable` with the raw code retained in `message`, so nothing is lost — at worst a genuine torch failure is reported as `cameraUnavailable` rather than `torchUnavailable`. Verify the exact code strings against `package:camera` when the API layer (Phase 4/9) wires this at the `CameraException` catch site. No change needed now; nothing in production calls this factory yet.

2. **No `==`/`hashCode` on `CameraPpgError`.** Consistent with the existing `RrInterval` value type (also `@immutable` without value equality). These cross the boundary as stream events, not as map keys or comparison subjects, so this is fine and matches established convention. Noted only for completeness.

REVIEW_PASS
