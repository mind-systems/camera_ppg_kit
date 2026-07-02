# Plan: Camera + runtime permissions

## Context
Make the example app request camera permission before a measurement starts, handling granted / denied / permanently-denied with a settings deep-link — entirely in `example/`, so the kit's `CameraPpgSession` stays UX-free (spec note 15).

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Tasks

### Phase 1: Dependency

- [x] **Task 1: Add `permission_handler` to the example app**
  Files: `example/pubspec.yaml`
  Add the `permission_handler` dependency to the `example/` app (pin `^11.3.1`, the same major neiry uses). Add it with `flutter pub add permission_handler` run from inside `example/` — do NOT hand-edit `pubspec.yaml` (per repo CLAUDE.md). This is an example-only dependency: it must never be added to the kit's root `pubspec.yaml` (guard: `CameraPpgSession` and `lib/src/` must not import `permission_handler` — the kit stays host-agnostic and only surfaces `CameraPpgError.permissionDenied` as a value).

### Phase 2: Request flow

- [x] **Task 2: Gate `_start()` behind a camera-permission request** (depends on Task 1)
  Files: `example/lib/screens/kit_api_tab.dart`
  Add a private `Future<bool> _checkAndRequestCameraPermission()` to `_KitApiTabState` and call it at the very top of `_start()` — before the `done`-recovery `stopMeasurement()` and before `service.startMeasurement(...)`. This is the single choke point that both the Start button (`_start(state)`) and the error banner's Retry button (`_start(MeasurementState.idle)`) already route through, so gating it covers both. Behavior (mirror neiry's `_scan()` permission flow, note 15):
    - `final status = await Permission.camera.request();`
    - `status.isGranted` → return `true`; `_start()` proceeds to its existing logic.
    - `status.isPermanentlyDenied || status.isRestricted` → `ppgTap('kit_permission_open_settings')`, `await openAppSettings();`, then set `_lastError = CameraPpgError.permissionDenied(permanentlyDenied: true)` (guarded by `if (!mounted) return false;` after the await, wrapped in `setState`) and return `false` — do NOT call `startMeasurement()`.
    - otherwise (`isDenied`) → set `_lastError = CameraPpgError.permissionDenied()` inside `setState` and return `false` — do NOT call `startMeasurement()`.
  Reuse the existing `_errorBanner` rendering: it already reads `error.type.name`, `error.message`, and shows the permanently-denied guidance line plus the Retry button when `error.permanentlyDenied` is set (verified in `camera_ppg_error.dart` — `CameraPpgError.permissionDenied({permanentlyDenied, message})` exists), so no new banner UI is needed. In `_start()`, guard the call so denial short-circuits: `if (!await _checkAndRequestCameraPermission()) return;` placed after `ppgTap('kit_start')` but before `setState(() => _lastError = null)` is cleared — order it so the denial path's `_lastError` assignment is not immediately wiped (i.e. run the permission check first and return on failure, then clear `_lastError` only on the granted path). Log the request start with `ppgTap('kit_permission_request')` at the top of `_checkAndRequestCameraPermission()`. Import `package:permission_handler/permission_handler.dart`; the file already imports the barrel for `CameraPpgError`.

### Phase 3: Platform manifests

- [x] **Task 3: Confirm iOS `NSCameraUsageDescription`**
  Files: `example/ios/Runner/Info.plist`
  Verify the `NSCameraUsageDescription` key is present with a fingertip-PPG purpose string (it currently reads: "The rear camera is used to measure your heart-rate via contact PPG: press a fingertip over the lens and flash while recording."). This key is load-bearing — without it the `camera` plugin hard-crashes on first `AVCaptureDevice` access (not a denial dialog), parity with neiry's `NSBluetoothAlwaysUsageDescription`. No change needed if present and descriptive; no runtime API beyond `Permission.camera.request()` is required on iOS (the OS shows the system dialog).

- [x] **Task 4: Confirm Android `CAMERA` permission**
  Files: `example/android/app/src/main/AndroidManifest.xml`
  Assert `<uses-permission android:name="android.permission.CAMERA"/>` is present (it currently is). No location/BLE entries are needed — unlike neiry, camera PPG needs only camera permission. Android 6+ drives the runtime dialog through `Permission.camera.request()` (Task 2); there is no manifest-only path. No change needed if present.
