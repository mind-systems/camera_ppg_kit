## Code Review Summary

**Plan:** `29-lifecycle-teardown.md` — app-shell `WidgetsBindingObserver` that releases/re-arms the `CameraPpgService` source on background/foreground.
**Files Reviewed:** 1 plan + target/context (`example/lib/main.dart`, `services/camera_ppg_service.dart`, `providers/camera_ppg_service_provider.dart`, `providers/session_config_provider.dart`, `screens/source_screen.dart`, spec note 17, ROADMAP Phase 9).
**Risk Level:** 🟢 Low — the design matches spec note 17 and the existing code contracts; one ambiguity in the plan text could produce a real bug if taken literally.

### Context Gates
- **Roadmap (WARN→PASS):** The plan's `# Plan: Lifecycle & teardown` heading matches ROADMAP.md Phase 9 line 94 "Lifecycle & teardown", which names `notes/17-lifecycle-teardown.md` as its spec. The plan honors that spec exactly: app-shell-level observer in `main.dart`, releases the app-level `CameraPpgService` via the single `stopMeasurement()` funnel, kit `lib/` untouched. Aligned.
- **Spec note 17:** All three obligations are met — release on `inactive`/`paused`, re-arm on `resumed` via a `_wasMeasuring` flag, and "surface `MeasurementState` so the UI shows re-acquisition." The last is satisfied for free because `startMeasurement` drives `lifecycleProvider` (`starting → warmup → …`), which the pure-consumer screens already render.
- **Architecture / Rules:** No `.ai-factory/ARCHITECTURE.md` boundary issue — observer stays host-side, kit stays Flutter-binding-free (note 17 "Kit stays Flutter-binding-free" guard respected). No `RULES.md`/skill-context file present for this repo.
- **API grounding verified:** `isMeasuring` (service.dart:86), `stopMeasurement()` no-op/idempotent (214-241), `startMeasurement({cameraId, policy, acceptance})` (125), `sessionConfigProvider` → `.policy`/`.acceptance` (session_config_provider.dart:19-20, 124), and the not-awaited Raw hook at `main.dart:88-104` all exist as the plan describes. Line references are correct.

### Critical Issues
None that block, but one item should be pinned before implementation:

**1. `_wasMeasuring` default value is ambiguous and, taken literally, is a bug (Task 1).**
The plan says: *"record it in a new shell-local `bool _wasMeasuring = true` flag."* Read literally, an implementer declares the field `bool _wasMeasuring = true;`. That is wrong: the handler only ever **sets** the flag under the `if (isMeasuring)` guard and never resets it to `false` on a background transition that occurs while *not* measuring. So with a `true` default the sequence

```
app launch (no lifecycle callback for the initial `resumed`)
→ background while idle  (inactive: isMeasuring == false → guard skips, flag stays true)
→ foreground            (resumed: _wasMeasuring == true → startMeasurement fires)
```

would **auto-start a measurement the operator never requested**, bypassing the Source screen's Start button and its permission pre-check (`_checkAndRequestCameraPermission`).

Fix: declare the field `bool _wasMeasuring = false;` and, inside the `inactive`/`paused` branch, assign `_wasMeasuring = true;` only when `isMeasuring`. The intent (set-on-background-if-measuring, clear-on-resume) is only consistent when the default is `false`. Please reword Task 1 so the field initializer is unambiguously `false`.

### Non-blocking Notes

- **`super.initState()` not mentioned (Task 1).** The plan calls out `super.dispose()` but not `super.initState()`. `_ShellState` currently has no `initState`; the new one must call `super.initState()` before/around `addObserver`. Trivial, but worth stating so it isn't dropped.

- **`inactive` → `paused` double-fire re-entrancy (Task 1).** Backgrounding on Android fires `inactive` then `paused`; each hits this branch. The first fires the un-awaited `stopMeasurement()`, whose `_measuring`/`_session` are only cleared *after* awaited subscription cancels (service.dart:227-232). If `paused` lands before that completes, a second `stopMeasurement()` runs concurrently over the same still-populated `_subs`/`_session`. `session.dispose()` and `sub.cancel()` are idempotent, so this is not a crash, and the `_wasMeasuring` flag is preserved correctly (the guard just re-sets it or skips). This mirrors the pre-existing Raw-hook pattern and is acceptable, but the implementer should be aware that the guard on `isMeasuring` is timing-dependent across the two callbacks — which is fine here because a lost re-set can't clear the flag, only skip re-setting it.

- **Re-arm bypasses the permission pre-check (Task 2).** The Source screen gates Start behind `_checkAndRequestCameraPermission()`; the shell re-arm calls `startMeasurement()` directly. This is safe in practice: permission was necessarily granted for the measurement that was running, and the kit maps a missing permission to a `CameraPpgError` value (note 18 permission gating) rather than throwing — the un-awaited re-arm just fails silently as a value. Worth a one-line acknowledgement in the plan so it reads as deliberate, not overlooked.

- **Un-awaited teardown on `paused` may not finish before OS suspension.** The lifecycle callback can't await, so on a fast suspend the ordered release (torch-off/dispose) may not complete. Note 17 accepts this (the plugin loses the device on background and the OS reclaims the camera/torch anyway), and firing release on `inactive` — which precedes `paused` — widens the window. No change needed; noted for completeness.

- **Quick-toggle re-arm race (Task 2).** If `resumed` fires while the un-awaited background `stopMeasurement()` is still in flight, `startMeasurement`'s re-entry guard (`if (_measuring) return`) will no-op and the re-arm is lost after `_wasMeasuring` was cleared. This is a rare background-foreground-flicker edge and degrades to "operator presses Start again" — acceptable, not worth extra wiring.

### Positive Notes
- Correctly keeps the single teardown funnel (`stopMeasurement()`), never calling `session.dispose()`/`stop()` from `main.dart` — matches note 17's "single path" guard and the service dartdoc (dispose-alone suffices).
- Correctly places the observer at the shell, not per-screen, consistent with the neiry-mirror shell (note 22) and the app-level singleton ownership model.
- Auto-detect-on-re-arm (omit `cameraId`) is the right call: the operator's override lives in `SourceScreen` local state and is genuinely unreachable from the shell; the plan states this and the fallback (re-pick on Source) explicitly.
- Reuses `sessionConfigProvider` for the re-arm tuning exactly as `source_screen.dart:107-113` does, so re-acquisition runs with the in-force `[debug]` config rather than kit defaults.
- Hot-restart reasoning is sound: `startMeasurement` builds a fresh `CameraPpgSession`/controller each call, so no stale handle is reused.
