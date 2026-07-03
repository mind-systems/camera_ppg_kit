# Plugin Hardening — Permission Gating

**Date:** 2026-07-03 (revised — unsupported-device gating dropped)
**Source:** ROADMAP Phase 9; note 15 (example permission flow), note 06 (`CameraPpgError`), note 07 (`start()` `CameraException` mapping)

## Key Findings

- **Denied camera permission fails as a value, never a crash — satisfied today.** The example requests permission before `start()` (note 15); if `start()` is reached without it, `controller.initialize()` throws a `CameraException` the kit catches and maps to `CameraPpgError.permissionDenied` via `fromCameraErrorCode`, acquiring nothing. No throw crosses the barrel; the failed start leaves the session at `idle`.
- **Unsupported-device gating is dropped.** The data-driven deny-list keyed by model (the original half of this task) is not built and not planned now — no device is known-bad yet. Re-plan it if/when one appears. The `CameraPpgErrorType.unsupportedDevice` value stays in the enum as a harmless unused type; removing it is a separate public-surface change, not done here.

## Details

### Permission path (satisfied)

- **Example (note 15):** `_checkAndRequestCameraPermission()` runs before `startMeasurement`; on denial the screen does not start (acquires nothing); permanently-denied / restricted → `openAppSettings()`.
- **Kit:** `start()` has no proactive permission pre-check, but a denied permission surfaces through `controller.initialize()` throwing `CameraException('CameraAccessDenied' | 'CameraAccessDeniedWithoutPrompt' | 'CameraAccessRestricted')`, which `start()`'s `catch` maps to `CameraPpgError.permissionDenied` (with `permanentlyDenied` for the without-prompt/restricted codes). The failed start tears down and returns to `idle`.

### Unsupported-device — dropped

The Phase-2 deny-list idea (note 03) and its JSON asset / `DeviceSupportPolicy` are intentionally **not** built. If a real known-bad device surfaces, re-plan as a new task.

## Guards

- No `throw` across the barrel — refusal is a `CameraPpgError` value (ARCHITECTURE principle 3).
- Do not add a model-string deny-list or JSON asset now.

## Verify

- Deny camera permission, press Start → `CameraPpgError.permissionDenied` surfaced, camera/torch untouched, `stateStream` stays `idle`, no crash.
