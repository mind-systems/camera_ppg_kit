# Example — Camera + Runtime Permissions

**Date:** 2026-06-21
**Source:** ROADMAP Phase 9 "Camera + runtime permissions"; neiry milestone "BLE runtime permissions on Scan" (`neiry_kit/.ai-factory/ROADMAP.md`); note 06 (state & error types); DESCRIPTION NFR (hardware-only, no simulator)

## Key Findings

- The kit reports permission state as a typed `CameraPpgError` value (`permissionDenied` + permanently-denied flag — note 06); it never asks for permission and never throws across the channel. The **request UX lives entirely in `example/`**, exactly as neiry kept the BLE request in `_DeviceScreenState._scan()` rather than inside `DeviceLocator`.
- Camera PPG needs only **camera** permission (no BLE, no location, no mic). The neiry flow ports 1:1 with the permission set swapped: request → granted? proceed : denied? show guidance : permanently-denied? `openAppSettings()`.
- iOS pitfall (same class as neiry's `NSBluetoothAlwaysUsageDescription`): without `NSCameraUsageDescription` in `Info.plist`, the `camera` plugin's `AVCaptureDevice` access **crashes on first use** — not a denial dialog, a hard crash. Add the string before any camera access can run.
- Mirror neiry's structure so both example apps gate identically — one habit for whoever validates either kit.

## Details

### `example/pubspec.yaml` — add `permission_handler`

Currently no permission dependency. Add `permission_handler: ^11.3.1` (same version neiry pinned). Use `flutter pub add permission_handler` inside `example/`, do not hand-edit.

### Request before measurement starts (mirror `_scan()`)

The Phase-9 playground screen's start handler (the start/stop control feeding `CameraPpgSession.start()` — note 07) must call an async `_checkAndRequestCameraPermission()` **before** invalidating providers / calling `start()`:

- `final status = await Permission.camera.request();`
- `status.isGranted` → proceed to `start()`.
- `status.isPermanentlyDenied` (or `isRestricted`) → `await openAppSettings(); return;` — do not call `start()`.
- otherwise (`isDenied`) → surface guidance and `return;` — show the typed `CameraPpgError.permissionDenied` path, e.g. a SnackBar "Camera permission required to measure".

Android 6+ (API 23+) drives this runtime dialog automatically through `Permission.camera.request()`; no manifest-only path. Keep the call in the screen/notifier, never in `CameraPpgSession` (it stays UX-free, only emitting the typed value if the host hands it a denied state).

### iOS — `example/ios/Runner/Info.plist`

Add a `NSCameraUsageDescription` key, e.g. value `"This app uses the camera and flash to measure your pulse from a fingertip."`. Required for iOS; absence crashes the camera plugin on first access (parity with neiry's `NSBluetoothAlwaysUsageDescription` note). No runtime request API needed on iOS beyond `Permission.camera.request()` — the OS shows the system dialog.

### Android — `example/android/app/src/main/AndroidManifest.xml`

Confirm `<uses-permission android:name="android.permission.CAMERA"/>` is present (the `camera` plugin declares it transitively, but assert it in the example manifest so the runtime request resolves). No location/BLE entries — unlike neiry, camera PPG needs none.

### Verify

- Fresh install, tap "measure": system camera dialog appears (iOS + Android); granting proceeds to preview/RR.
- Deny once, tap again: guidance shown, `start()` not called, no crash.
- Deny permanently (toggle off in Settings, or second deny on Android), tap again: app jumps to system settings via `openAppSettings()`.
- iOS smoke: temporarily remove `NSCameraUsageDescription` and confirm the documented crash, then restore — proves the key is load-bearing.

### Guards

- Request lives in `example/` only — `CameraPpgSession` must not import `permission_handler` (keeps the kit host-agnostic; ARCHITECTURE: no UX in the API layer).
- Do not throw on denial — the kit surfaces `CameraPpgError.permissionDenied`; the example surfaces guidance. Two layers, no exception across the boundary.
- Permanently-denied must route to `openAppSettings()`, never silently no-op.
