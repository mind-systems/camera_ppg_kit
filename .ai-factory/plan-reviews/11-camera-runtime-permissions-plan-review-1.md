## Code Review Summary

**Plan:** `11-camera-runtime-permissions.md`
**Files Reviewed:** 5 (plan + 4 target files: `kit_api_tab.dart`, `camera_ppg_error.dart`, `Info.plist`, `AndroidManifest.xml`) + spec note 15
**Risk Level:** 🟢 Low

### Context Gates

- **Architecture** (`ARCHITECTURE.md` present): PASS. The plan keeps the permission-request UX entirely in `example/` and forbids `permission_handler` from `lib/src/`, preserving the "kit stays host-agnostic, no UX in the API layer" boundary. The kit only surfaces the typed `CameraPpgError.permissionDenied` value. Aligned.
- **Rules** (`rules/base.md` present): PASS. Plan explicitly honors the repo `CLAUDE.md` rule "never hand-edit `pubspec.yaml`" by prescribing `flutter pub add permission_handler`. Logging via `ppgTap`/`ppgLog` matches the example-app logging convention. English-only artifact.
- **Roadmap** (`ROADMAP.md` present): PASS. Directly linked to Phase 9 line 46 ("Camera + runtime permissions", spec note 15). Correctly scoped away from the later Phase entry "Permission / unsupported-device gating" (line 62, note 18) which owns the kit-side deny-list — no scope bleed.

### Verified Against Codebase

Every load-bearing assumption in the plan checks out against the actual code:

- **`CameraPpgError.permissionDenied({permanentlyDenied, message})`** exists exactly as claimed (`camera_ppg_error.dart:56-65`).
- **`_errorBanner`** already renders `error.type.name`, `error.message`, the permanently-denied guidance line (lines 242-244), and the Retry button (lines 246-254) — so no new banner UI is needed, as the plan states.
- **Single choke point confirmed:** both the Start button (`_start(state)`, line 269) and the Retry button (`_start(MeasurementState.idle)`, line 251) route through `_start()`. Gating there covers both paths.
- **iOS `NSCameraUsageDescription`** is already present and descriptive in `Info.plist` — Task 3 is a genuine verify-only no-op.
- **Android `<uses-permission android:name="android.permission.CAMERA"/>`** is already present in `AndroidManifest.xml` (plus an optional `camera.flash` feature declared `required="false"`) — Task 4 is a verify-only no-op.
- **The `_lastError`-wipe hazard the plan calls out is real:** the current `_start()` clears `_lastError` on its first line (line 116). The plan's prescribed reordering (run the permission check first, `return` on failure, clear `_lastError` only on the granted path) correctly prevents the denial-path error assignment from being immediately wiped. Good catch.

### Critical Issues

None. The plan is implementable as written.

### Minor Issues / Non-Blocking Notes

1. **Guard the granted-path `setState(() => _lastError = null)` with `mounted`** (`kit_api_tab.dart:116`).
   After the plan's reorder, this `setState` now follows an `await` (`_checkAndRequestCameraPermission()` awaits `Permission.camera.request()`). The rest of the file is careful to guard post-await state mutations (`_loadCameras` line 82, `_start` line 131). For consistency and to avoid a "setState after dispose" if the widget unmounts during the permission dialog, the granted-path clear should become:
   ```dart
   if (!await _checkAndRequestCameraPermission()) return;
   if (!mounted) return;
   setState(() => _lastError = null);
   ```
   Low severity (the dialog is brief and dismissing it rarely unmounts the tab), but it matches the file's established convention.

2. **iOS: `permission_handler` compile-time macros are not required for this example, but worth a one-line awareness note.** `permission_handler_apple` uses `PERMISSION_*` Podfile preprocessor macros to strip unused permission code; by default (no macros set) *all* permissions compile in, so `Permission.camera.request()` works out of the box with no Podfile edit. The plan is correct to not prescribe a Podfile change. No action needed — flagged only so the implementer doesn't get surprised if a future App Store submission of a *product* app (not this example) requires trimming the macro set.

3. **iOS first-denial goes straight to `openAppSettings()` — expected, not a bug.** On iOS `permission_handler` maps a first "Don't Allow" to `permanentlyDenied` (iOS never re-shows the system dialog), so the `isDenied` guidance branch is effectively Android-only on that platform. This matches neiry's flow and the plan's design; noting it so the implementer's manual verify (note 15 "deny once → guidance") is understood to be an Android-observable step, while iOS exercises the `openAppSettings()` branch on first denial.

4. **`availableCameras()` in `initState` runs before permission is granted — safe.** The post-frame `_loadCameras()` (line 76) enumerates lenses before any permission request. Camera *enumeration* does not require authorization or trigger a dialog on either platform (it opens no capture session), so it does not pre-empt or interfere with the Task-2 request flow. No change needed; called out only to confirm the plan's choke-point-at-`_start()` placement is sufficient and nothing leaks earlier.

### Positive Notes

- Excellent codebase grounding: the plan cites exact symbols (`error.permanentlyDenied`, `error.type.name`), exact call sites (`_start(state)` vs `_start(MeasurementState.idle)`), and the pre-existing banner behavior — all of which verified accurately. No fantasy APIs.
- The `_lastError`-ordering subtlety (item under "Verified" above) is a non-obvious interaction the plan anticipated and solved.
- Correct guard discipline prescribed: `if (!mounted) return false;` after `openAppSettings()`, `permission_handler` confined to `example/`, no import in `lib/src/`.
- Verify-only Phase-3 tasks are honest (both manifests already satisfy them) and the plan documents *why* each key is load-bearing (iOS hard-crash without `NSCameraUsageDescription`), which is the right framing for a "confirm, don't change" task.
- Scope is tight and correct — this is an example-only UX layer; the kit's typed-value contract is untouched.

The three minor items are polish, not correctness blockers. The plan is solid.

PLAN_REVIEW_PASS
