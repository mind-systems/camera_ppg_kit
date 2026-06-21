# Plugin Hardening — Permission / Unsupported-Device Gating

**Date:** 2026-06-21
**Source:** ROADMAP Phase 11 (`Permission / unsupported-device gating — gate denied-permission and unsupported-device paths (from the Phase 2 deny-list) without crashes, surfacing CameraPpgError states`); notes 03 (deny-list), 06 (error types), 07 (session)

## Key Findings

- Two unhappy paths must fail *cleanly as values*, never as crashes or garbage RR: **permission denied** and **unsupported device**. Both already have homes in note 06's `CameraPpgError` (`permissionDenied { permanentlyDenied }`, `unsupportedDevice`, plus `cameraUnavailable`/`torchUnavailable`). This task wires `start()` to short-circuit to them.
- The deny/allow-list from the Phase 2 spike (note 03) must be **data-driven** — a bundled JSON asset keyed by device model — not model strings scattered through Dart. The matrix in note 03 is its only source of truth; this task gives it a runtime home.
- Nothing here ports cleanly from `neiry_kit` (a USB/BLE device with no camera-permission or per-model camera/torch concern). This is camera-PPG-specific hardening.
- A runtime **capability probe** is the real safety net: a phone absent from the deny-list can still lack a torch or rear camera. Deny-list catches *known-bad signal*; the probe catches *physically incapable*.

## Details

### Precedence in `CameraPpgSession.start()` (`lib/src/api/camera_ppg_session.dart`)

Current state (note 07): `start()` configures the `CameraController`, sets torch, starts the frame stream. Target: gate before any of that, in fixed order, emitting on `stateStream` / the error stream and returning early (no throw):

1. **Permission check** — camera permission. If denied → emit `CameraPpgError.permissionDenied(permanentlyDenied: …)` + `MeasurementState.idle`, return. (The permission request itself stays in the example/host per Phase 9 note; the kit only *reads* status and refuses — keep it injectable so tests don't touch platform permissions.)
2. **Capability / deny-list check** — resolve the running device id, then: (a) if on the deny-list → `CameraPpgError.unsupportedDevice`; (b) runtime probe — no rear camera (`availableCameras()` has no back-facing) → `cameraUnavailable`; selected sensor reports no torch → `torchUnavailable`. Any failure → emit error + `MeasurementState.idle`, return.
3. **Proceed** — only now run the note-07 wiring.

### Deny-list home (data-driven)

Add a bundled asset, e.g. `lib/assets/device_support.json` (declared in pubspec `flutter.assets`), shape `{ "denied": ["<normalized model>", …], "version": n }`. Load via a `DeviceSupportPolicy` class in `lib/src/processing/` (pure, no `camera`/channel imports per ARCHITECTURE rule) exposing `bool isSupported(String deviceId)`. Device id comes from a thin channel/`device_info_plus` call resolved in `api/` and **passed into** the pure policy — so a fake id makes it testable without hardware. Do NOT hard-code model strings in `camera_ppg_error.dart` or the session (note 06 guard).

### Verify

- Unit-test `DeviceSupportPolicy` by injecting a fake device id present/absent in a fixture JSON → `unsupportedDevice` vs pass.
- Test `start()` precedence with fakes: denied permission emits `permissionDenied` and never touches the camera; a deny-listed id emits `unsupportedDevice`; a missing-torch probe emits `torchUnavailable`; all three leave `stateStream` at `idle` with no RR events.

### Guards

- No `throw` across the channel — every refusal is a `CameraPpgError` value (ARCHITECTURE principle 3).
- Deny-list stays in the JSON asset; updating it is an asset edit, not a code edit.
- Permission status read must be injectable so the precedence test runs without platform permissions.
- On any short-circuit, leave the camera/torch untouched (never half-acquired) — release is the lifecycle note (Phase 11 teardown), refusal here must acquire nothing.
