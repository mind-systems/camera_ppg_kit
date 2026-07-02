# Code Review (pass 2): Camera + runtime permissions

**Plan:** `11-camera-runtime-permissions.md`
**Changed files:** `example/lib/screens/kit_api_tab.dart`, `example/pubspec.yaml`, `example/pubspec.lock` (+ plan/review artifacts). Manifests unchanged — both required keys already present (verify-only tasks).
**Risk level:** 🟢 Low

## Status vs. review 1

Review 1's sole finding — an unguarded `setState(() => _lastError = null)` on the granted path after the awaited permission request — has been **fixed**. `_start()` now reads:

```dart
Future<void> _start(MeasurementState currentState) async {
  ppgTap('kit_start');
  if (!await _checkAndRequestCameraPermission()) return;
  if (!mounted) return;                 // <-- added
  setState(() => _lastError = null);
  ...
```

The `if (!mounted) return;` guard now matches the file's convention for every post-await `setState` (`_loadCameras:82`, the two denial branches at `129`/`135`, and `_start:158`).

## Verification of the current change

- **Permission gate at the single choke point.** `_checkAndRequestCameraPermission()` is called at the top of `_start()`, which both the Start button (`_start(state)`) and the Retry button (`_start(MeasurementState.idle)`) route through. Both paths are gated. ✅
- **Denial semantics correct.** `isGranted` → proceed; `isPermanentlyDenied || isRestricted` → `openAppSettings()` + `permissionDenied(permanentlyDenied: true)`; else `isDenied` → `permissionDenied()`. `startMeasurement()` is never called on denial. ✅
- **`_lastError`-wipe ordering correct.** The permission check runs and returns on failure *before* `setState(() => _lastError = null)`, so a denial-path error assignment is not immediately cleared. ✅
- **All post-await `setState` guarded.** Lines 129, 135, and 143 each check `mounted` first. No `setState()-after-dispose` path remains. ✅
- **Re-entry safe.** During the permission dialog the Start button stays enabled (state is `idle`/`done`), but a double-tap is absorbed by `CameraPpgService.startMeasurement`'s `_measuring` guard, which returns `null` for the second concurrent call. No double session. ✅
- **Boundary intact.** `permission_handler` imported only in `example/`; no leak into the kit root `pubspec.yaml` or `lib/src/`. The kit still surfaces only the typed `CameraPpgError` value. ✅
- **Dependency.** `permission_handler: ^11.3.1` in `example/pubspec.yaml`, resolved to `11.4.0` in the lock; `openAppSettings()` and `Permission.camera` are exported by the package. ✅
- **Manifests.** `NSCameraUsageDescription` (iOS) and `android.permission.CAMERA` (Android) already present — correctly left unchanged. ✅

## Notes (no action required)

- On iOS, a first "Don't Allow" maps to `permanentlyDenied`, so first-denial exercises the `openAppSettings()` branch rather than the plain `isDenied` guidance branch — by design, matches neiry's flow.
- `availableCameras()` in `initState` runs before the request but opens no capture session and needs no authorization, so it neither pre-empts the dialog nor bypasses the `_start()` gate.

No findings.

REVIEW_PASS
