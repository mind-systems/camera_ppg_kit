## Code Review Summary

**Plan:** `29-lifecycle-teardown.md` — app-shell `WidgetsBindingObserver` that releases the `CameraPpgService` source on background and re-arms on foreground.
**Files Reviewed:** 1 plan + target/context (`example/lib/main.dart`, `services/camera_ppg_service.dart`, `providers/camera_ppg_service_provider.dart`, `providers/session_config_provider.dart`, `screens/source_screen.dart`, spec note 17).
**Risk Level:** 🟢 Low — the design matches spec note 17 and every code contract it references; the one blocking ambiguity from review 1 is resolved and its non-blocking notes are folded in.

### Context Gates
- **Roadmap (PASS):** The plan's `# Plan: Lifecycle & teardown` heading matches ROADMAP Phase "Lifecycle & teardown", whose spec is `notes/17-lifecycle-teardown.md`. The plan honors that spec's split-of-responsibility exactly: the observer lives on the shell `State` in `main.dart` (host-side), releases the app-level `CameraPpgService` via the single `stopMeasurement()` funnel, and leaves kit `lib/` untouched.
- **Spec note 17 (PASS):** All three obligations from note 17 §"`example/` — `WidgetsBindingObserver`" are met — release on `inactive`/`paused` (Task 1), re-arm on `resumed` via a `_wasMeasuring` flag (Task 2), and "surface `MeasurementState` so the UI shows re-acquisition." The last holds for free: `startMeasurement` drives `lifecycleProvider` (`starting → warmup → …`), which `source_screen.dart` already renders via `ref.watch(lifecycleProvider)`.
- **Architecture / Rules:** No `ARCHITECTURE.md` boundary issue — the observer stays host-side and the kit remains Flutter-binding-free (note 17 "Kit stays Flutter-binding-free" guard respected). No `RULES.md` / skill-context file present for this repo.
- **API grounding verified against source:**
  - `isMeasuring` — `camera_ppg_service.dart:86` (`_measuring && _session != null`). ✓
  - `stopMeasurement()` no-op-when-idle + idempotent teardown — `camera_ppg_service.dart:214-241`. ✓
  - `startMeasurement({cameraId, policy, acceptance})` returns `Future<CameraPpgError?>`, re-entry-guarded (`if (_measuring) return null`), never throws — `camera_ppg_service.dart:125-168`. ✓
  - `sessionConfigProvider` → `SessionConfig.policy` / `.acceptance` — `session_config_provider.dart:19-20,124-125`. ✓
  - The un-awaited Raw hook the plan mirrors — `main.dart:88-104`. ✓
  - The Source-screen start-with-config pattern the re-arm mirrors — `source_screen.dart:107-113`. ✓

### Critical Issues
None. The single blocking item from review 1 — the ambiguous `bool _wasMeasuring = true` initializer that would auto-start an operator-never-requested measurement on a background-while-idle → foreground sequence — is fixed: Task 1 now declares the field unambiguously as `bool _wasMeasuring = false;` and spells out the exact failure it avoids. Review 1's non-blocking notes are also folded in (explicit `super.initState()`, `inactive`→`paused` double-fire safety, deliberate permission-pre-check skip on re-arm).

### Non-blocking Notes
- **New import for `session_config_provider.dart` is unstated (Task 2).** `main.dart` does not currently import `providers/session_config_provider.dart`; Task 2's `ref.read(sessionConfigProvider)` needs it added. Trivial and fails loudly at compile time (not a silent bug), so it won't survive to runtime — but worth naming so it isn't treated as an oversight. `ppgLog`/`ppgTap` are already imported (`main.dart:5`), so no logging import is needed.
- **Releasing on `inactive` is aggressive but per-spec.** `inactive` fires on transient interruptions that are not true backgrounding (iOS Control Center pull-down, app-switcher peek, an incoming-call banner). Firing `stopMeasurement()` there means a measurement stops and then re-arms on the following `resumed` even when the app never actually left the foreground. This is intentional — note 17 line 38 explicitly lists `inactive`/`paused` → stop, the existing Raw hook follows the same pattern, and the `_wasMeasuring` re-arm makes it self-healing — so it is correct, just louder than strictly necessary for a hardware-debug example app. No change needed.
- **Quick-toggle re-arm race (Task 2), carried over from review 1.** If `resumed` fires while the un-awaited background `stopMeasurement()` is still in flight (before it reaches `_measuring = false` at `camera_ppg_service.dart:232`), `startMeasurement`'s re-entry guard no-ops and the re-arm is lost after `_wasMeasuring` was cleared. This is a rare background/foreground-flicker edge that degrades to "operator presses Start again" — acceptable, not worth extra wiring. The plan already acknowledges the un-awaited nature; no action required.

### Positive Notes
- Keeps the single teardown funnel (`stopMeasurement()`) and never calls `session.dispose()`/`stop()` directly from `main.dart` — matches note 17's "single path" guard and the Notes-for-implementer section restates it.
- Places the observer at the shell, not per-screen — consistent with the app-level `CameraPpgService` singleton ownership model and the neiry-mirror shell (note 22).
- Auto-detect-on-re-arm (omit `cameraId`) is the right call and correctly justified: the operator's override lives in `SourceScreen` local state and is genuinely unreachable from the shell; the plan states the fallback (re-pick on Source) explicitly.
- Reuses `sessionConfigProvider` for the re-arm tuning exactly as `source_screen.dart:107-113` does, so re-acquisition runs with the in-force `[debug]` config rather than kit defaults.
- Hot-restart reasoning is sound: `startMeasurement` builds a fresh `CameraPpgSession`/controller each call, so a stale handle from a prior Dart VM is never reused; the `removeObserver` in `dispose` keeps registration clean.

PLAN_REVIEW_PASS
