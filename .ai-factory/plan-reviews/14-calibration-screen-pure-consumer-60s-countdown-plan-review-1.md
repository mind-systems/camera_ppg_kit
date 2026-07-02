## Code Review Summary

**Plan:** `14-calibration-screen-pure-consumer-60s-countdown.md`
**Scope:** `example/` only — new `screens/calibration_screen.dart` + shell wiring in `main.dart`
**Files Reviewed:** plan + 6 target/context source files (`calibration_recorder.dart`, `camera_ppg_service.dart`, `session_config_provider.dart`, `stream_providers.dart`, `main.dart`, `kit_api_tab.dart`) + notes 20/21/22
**Risk Level:** 🟢 Low

### Context Gates

- **Architecture** — OK. The plan honours the kit/example boundary: kit `lib/` untouched, recorder/service/config all consumed as-is, serialization stays in the example recorder (not on kit models). No dependency-direction violation.
- **Rules** — OK. Logging follows the `camera_ppg_kit/CLAUDE.md` example convention (`ppgTap` on interaction, coarse `ppgLog` milestones, one helper). No `print`/`debugPrint`. No kit `lib/` logging introduced.
- **Roadmap** — OK. Linked to `ROADMAP.md:49` ("Calibration screen (pure consumer, 60s countdown)"), Phase 7 re-decomposition. Spec note 21 supersedes the prior auto-stop design as the roadmap line states. Milestone linkage present and consistent.

### API / codebase verification (all confirmed correct)

- `_recorder.start(service, config.acceptance, config.policy)` — matches the **actual** signature `start(CameraPpgService service, RrAcceptance acceptance, SessionPolicy policy, {String? cameraId})` (`calibration_recorder.dart:45`). Note: this deviates from note 20's older `start(acceptance, policy, {cameraId})` sketch, but the plan follows the **committed** code, which is correct.
- `service.isMeasuring` precondition — confirmed at `camera_ppg_service.dart:72` (`bool get isMeasuring => _measuring && _session != null;`). The plan's line reference is accurate.
- `ref.read(sessionConfigProvider)` → `SessionConfig` with `.acceptance` / `.policy` fields — confirmed (`session_config_provider.dart`).
- `_recorder.save(countedBeats:, countWindowSeconds:)` — signature matches (`calibration_recorder.dart:110`).
- `bpmProvider` (`NotifierProvider<_,int?>`) read via `ref.watch(bpmProvider)` returning `int?` — matches kit_api_tab usage. ✓
- Shell wiring (Task 3): current enum is `source, kitApi, raw`; inserting `calibration` before `raw` yields the stated order, `_screenFor` switch + `children`/`destinations`/`selectedIndex` all iterate `_Branch.values`, and the Raw-exclusivity hook keys off `_Branch.raw` (the enum, not an index). Insertion is genuinely index-shift-safe as claimed. ✓
- `cameraPpgServiceProvider` exists and owns the singleton; `qualityProvider`/`stateProvider` are `StreamProvider`s. ✓

### Critical Issues

None. No missing steps, no wrong codebase assumptions, no missing migration (Android scoped storage / `path_provider` already added in the note-20 milestone — no new permission), no incorrect file paths or API misuse.

### Minor / Non-blocking observations (optional, do not block implementation)

1. **`qualityProvider`/`stateProvider` are `StreamProvider`s → `AsyncValue`.** Task 2 says "reuse the same colour/label mapping style as `kit_api_tab.dart`". The implementer must remember to unwrap with `.value` (e.g. `ref.watch(qualityProvider).value`) and the `null` arm of the `switch`, exactly as `kit_api_tab.dart:101-115` / `:55-56` do. The plan's cross-reference makes this discoverable, so this is a reminder, not a gap.

2. **Countdown/finish 1-second race (cosmetic).** `_finishTimer` (60 s one-shot) and `_tickTimer` (1 Hz) fire near-simultaneously at t≈60 s. If `_finish()` runs before the 60th tick, `_windowSeconds = 60 - _remainingSeconds` can compute `59` instead of `60`. Note 21 already specifies "windowSeconds ≈ 60", so this is within tolerance — no fix required, but worth being aware of when verifying the pulled file.

3. **`dispose()` does not stop the recorder.** Task 1's `dispose()` cancels the two timers but does not call `_recorder.stop()`. Since the screen only disposes on app teardown (IndexedStack keeps it mounted) and the service provider's `onDispose` tears down its controllers, the three recorder subscriptions are harmless at that point. Adding `_recorder.stop()` to `dispose()` would be tidier symmetry, but it is not a correctness issue.

### Positive Notes

- The core reframe — **pure consumer, screen-local `_recording` start-gate, `service.isMeasuring` record-precondition, dormant `done`-finalize path** — is faithfully carried from note 21 and is exactly what removes the prior design's setState-after-dispose / stale-`stateProvider` / tab-leave-abort failure classes.
- Empty-file guard (return without recording when `!isMeasuring`) and the `if (!mounted) return;` guard after `await _recorder.save(...)` are both correctly placed.
- Manual-Stop routing through an idempotent `_finish()` with `_windowSeconds = 60 - _remainingSeconds` correctly records the *actual* elapsed window rather than a fixed 60 — keeps the JSON honest.
- Reading the in-force config from the shared `sessionConfigProvider` (rather than fresh defaults) preserves the calibration-honesty invariant from notes 20/22.
- Task dependencies (1 → 2 → 3) and the FPS-quiet UI constraint (no charts/animation, 1 Hz timer never rebuilding on RR ticks) are correctly respected.

PLAN_REVIEW_PASS
