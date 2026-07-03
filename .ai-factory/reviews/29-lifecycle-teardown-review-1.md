# Code Review: Lifecycle & teardown (29)

**Scope:** `example/lib/main.dart` — a shell-level `WidgetsBindingObserver` on `_ShellState` that releases the `CameraPpgService` source on background and re-arms it on foreground. Kit `lib/` untouched (verified — the only non-artifact change is `main.dart`).

**Files read in full:** `example/lib/main.dart`, `example/lib/services/camera_ppg_service.dart`, `example/lib/services/source_lifecycle.dart`, `example/lib/providers/camera_ppg_service_provider.dart`, `example/lib/providers/session_config_provider.dart`, plan `29-lifecycle-teardown.md`, spec note 17.

**Risk level:** 🟢 Low — small, plan-faithful change; no blocking defects.

## Correctness verification

- **Compiles / API grounding.** `_ShellState with WidgetsBindingObserver` overrides `didChangeAppLifecycleState` correctly. All referenced symbols exist and match signatures: `isMeasuring` (service.dart:86), `stopMeasurement()` idempotent/no-op-when-idle (214-241), `startMeasurement({cameraId, policy, acceptance})` returns `Future<CameraPpgError?>` and never throws (125-168), `sessionConfigProvider` → `.policy`/`.acceptance` (session_config_provider.dart:19-20,124). New import `providers/session_config_provider.dart` added (main.dart:7); `ppgLog` already imported via `auto_detect/log.dart` (line 5). No missing imports.
- **Switch exhaustiveness.** All five `AppLifecycleState` values are handled (`inactive`/`paused` share a body, `resumed`, `detached`/`hidden` → `break`). Empty leading cases fall through as intended; non-empty cases do not (Dart 3 switch-statement semantics — consistent with the `switch` expression already in this file at `_screenFor`). Correct.
- **`_wasMeasuring` default.** Declared `false` (main.dart:94), resolving plan-review-1's blocking item. Set `true` only under the `isMeasuring` guard, cleared on `resumed`. A background-while-idle → foreground sequence cannot auto-start an unrequested measurement. Correct.
- **Observer registration lifecycle.** `addObserver` in `initState` (after `super.initState()`), `removeObserver` in `dispose` (before `super.dispose()`). No callbacks can fire post-teardown. Correct.
- **Single teardown funnel.** All release paths go through `CameraPpgService.stopMeasurement()`; `session.dispose()`/`stop()` are never called from `main.dart`. Matches note 17's "single path" guard.
- **Unawaited futures are safe.** Both `stopMeasurement()` and `startMeasurement()` return futures that complete normally (the latter surfaces failures as a `CameraPpgError` value, never a throw), so the fire-and-forget calls cannot produce an unhandled async exception.

## Non-blocking observations (no change required)

1. **Re-arm/teardown camera race on fast background→foreground flicker.** In `stopMeasurement()`, `_measuring = false` is set at service.dart:232 *before* `await session.dispose()` (the actual camera/torch release) at 233. If `resumed` fires in that narrow window, the un-awaited re-arm's `startMeasurement` passes its `if (_measuring) return` guard and opens a fresh controller on the same physical camera while the old session is still disposing it — the OS surfaces this as a `CameraException`. This is **not a crash**: the kit maps it to a `CameraPpgError` value and `startMeasurement` tears the failed session down, so it degrades to "re-arm silently fails, operator presses Start again." Rare (real backgrounding leaves ample teardown time), non-crashing, and consistent with note 17's acceptance of un-awaited teardown. Acknowledged in the plan's quick-toggle note. No action.

2. **`inactive` is an aggressive release trigger.** Firing `stopMeasurement()` on `inactive` (not just `paused`) means transient interruptions that never truly background the app (iOS Control Center pull, app-switcher peek, notification banner) stop and then re-arm the measurement. This is intentional per note 17 line 38 and mirrors the existing Raw-entry hook; the `_wasMeasuring` re-arm makes it self-healing. Acceptable for a hardware-debug example app.

## Conclusion

The change is faithful to the plan and spec note 17, correctly resolves the prior plan-review blocking item, and introduces no defects. The two observations are pre-acknowledged, non-crashing, and require no change.

REVIEW_PASS
