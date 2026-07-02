# Code Review: Camera + runtime permissions

**Plan:** `11-camera-runtime-permissions.md`
**Changed files:** `example/lib/screens/kit_api_tab.dart`, `example/pubspec.yaml`, `example/pubspec.lock` (+ plan artifacts). Manifests (`Info.plist`, `AndroidManifest.xml`) were verify-only and correctly left unchanged — both required keys were already present.
**Risk level:** 🟢 Low

## What was implemented

- `permission_handler: ^11.3.1` added to `example/pubspec.yaml` via pub (resolves to `11.4.0`); confined to `example/`, no leak into the kit's root `pubspec.yaml` or `lib/src/`. Kit-side host-agnosticism preserved. ✅
- `_checkAndRequestCameraPermission()` added and wired at the top of `_start()`, so both the Start button (`_start(state)`) and the error-banner Retry (`_start(MeasurementState.idle)`) route through it. ✅
- Denial paths surface `CameraPpgError.permissionDenied()` / `permissionDenied(permanentlyDenied: true)` reusing the existing `_errorBanner`; permanently-denied/restricted deep-links via `openAppSettings()`. ✅
- `_lastError`-wipe ordering handled correctly: the permission check runs and `return`s on failure *before* `setState(() => _lastError = null)`, so a denial-path error is not immediately cleared. ✅
- No exception crosses the kit boundary; the request stays entirely in the example. ✅

## Findings

### 1. [Low] Granted path clears `_lastError` with an unguarded `setState` after an await

`example/lib/screens/kit_api_tab.dart:142-143`

```dart
if (!await _checkAndRequestCameraPermission()) return;
setState(() => _lastError = null);   // <-- runs after the awaited permission request, no `mounted` guard
```

On the granted branch, `_checkAndRequestCameraPermission()` returns `true` immediately after awaiting `Permission.camera.request()` (line 125) **without a `mounted` check**. Control returns to `_start()`, which then calls `setState(() => _lastError = null)` at line 143 — a `setState` following an `await` with no `if (!mounted) return;` in front of it.

Every other post-await state mutation in this file is guarded: `_loadCameras` (line 82), both denial branches of the new method (lines 129, 135), and `_start`'s own post-`startMeasurement` block (line 158). This single line is the exception introduced by the change. If the tab/widget is disposed while the system permission dialog is up (or during the request microtask when permission is already granted), this `setState` fires on a defunct `State` and throws `setState() called after dispose()`.

The window is small — a system permission modal rarely unmounts the tab, and `TabBarView` usually keeps the child alive — so this is low severity and example-app-only. But it is a genuine regression against the file's own guard convention. Fix by matching the surrounding style:

```dart
if (!await _checkAndRequestCameraPermission()) return;
if (!mounted) return;
setState(() => _lastError = null);
```

(Equivalently, add `if (!mounted) return false;` before the granted `return true;` in `_checkAndRequestCameraPermission` and re-check in the caller — but guarding at the `setState` site is simplest and consistent with `_start`'s later guard.)

## Notes (no action required)

- **iOS first-denial routes to `openAppSettings()`, by design.** `permission_handler` maps a first "Don't Allow" on iOS to `permanentlyDenied` (iOS never re-shows the system dialog), so the plain `isDenied` guidance branch is effectively Android-only. This matches the intended flow; the manual "deny once → guidance" verify step in spec note 15 is an Android-observable path, while iOS exercises the settings-deep-link branch on first denial.
- **`availableCameras()` in `initState` runs before any permission request — safe.** Enumeration opens no capture session and needs no authorization on either platform, so it neither triggers a dialog nor pre-empts the `_start()` choke point.

Finding 1 is a low-severity polish/consistency issue, not a blocker.
