## Code Review Summary

**Artifact reviewed:** Plan `22-example-lifecycle-state-machine-starting-stopping-pure-consumer-screens.md`
**Files touched by plan:** 6 (1 new: `example/lib/services/source_lifecycle.dart`; 5 edited)
**Risk Level:** 🟢 Low

### Context Gates

- **ROADMAP linkage (WARN→OK):** Plan maps cleanly onto the open contract line 57 in `.ai-factory/ROADMAP.md` ("Example lifecycle state machine (starting/stopping) + pure-consumer screens"). Enum shape (`idle → starting → warmup → measuring ⇄ poorSignal → stopping → idle`), synchronous set-at-boundary semantics, `lifecycleProvider`, pure-consumer screens, Raw-entry routing, "wraps note 32's idle push", and the example-only / no-`done` guards all match the roadmap wording and note 33. No drift.
- **Spec tree (OK):** Governing spec `.ai-factory/notes/33-example-lifecycle-state-machine.md` is followed faithfully; upstream guards from notes 32 (idle push), 23 (no `done`), 19 (Phase-10 freeze), 07/13 (kit teardown order) are all cited and respected.
- **ARCHITECTURE / RULES (OK):** No `ARCHITECTURE`/dependency-boundary violation — the change is confined to `example/`; the kit `lib/` surface (`MeasurementState`, `CameraPpgSession`, barrel) stays frozen. No project `.ai-factory/skill-context/aif-review/SKILL.md` present, so no project-specific overrides apply.

### Critical Issues

None. The plan is implementable as written.

### Verification against the codebase

The plan's assumptions were checked against the actual source and hold:

- **First kit emit on successful start is `warmup`** — confirmed at `lib/src/api/camera_ppg_session.dart:345` (`_setState(MeasurementState.warmup)`), and the bridge subscription is wired (`camera_ppg_service.dart:110-118`) *before* `await session.start()` (line 120), so the `starting → warmup` fold captures it. ✓
- **Failed-start path emits kit `idle` while bridge subs are still connected** — confirmed (`_release()` → `_setState(idle)` at line 439, subs cancelled only later inside the `stopMeasurement()` it then calls). The folding guard's "ignore kit `idle`" rule correctly prevents a spurious `starting → idle`, and the trailing `await stopMeasurement()` carries lifecycle through `stopping → idle`. ✓
- **`stopMeasurement()` cancel-then-dispose order** (`camera_ppg_service.dart:152-158`) is unchanged; setting `stopping` synchronously at entry before the cancel loop means late kit emits during teardown are already guarded out. ✓ The note-32 authoritative-idle push (`_stateController.add(MeasurementState.idle)`, lines 162-164) is preserved and `_setLifecycle(idle)` is added alongside it, exactly as the plan states.
- **No-session early-return branch** (lines 147-151) correctly does not emit `stopping` — matches the plan's "a no-op stop while already idle must not emit a spurious stopping."
- **`stateProvider` plumbing stays** — `bpmProvider` (`stream_providers.dart:57-66`) and the Streams-screen `ref.listen(stateProvider)` that clears `_rrHistory` on `warmup` (`streams_screen.dart:47-56`) both key off the kit `MeasurementState`, which the plan explicitly keeps. Lifecycle is added alongside, not as a replacement. ✓
- **All three consuming screens covered** — `source_screen.dart` (Task 4), `streams_screen.dart` + `calibration_screen.dart` (Task 5). A repo scan finds no other consumer of `stateProvider` / `isRunning` / `canStop`; the Raw `AutoDetectScreen` is direct-camera and untouched. ✓
- **`_stateLabelColor` switch stays exhaustive** — moving from the 4-value `MeasurementState` to the 6-value `SourceLifecycle` with the two added `starting`/`stopping` arms yields a total switch (Dart will enforce exhaustiveness). `pendingColor` (blue) already exists in `status_color.dart` for the new "Starting…/Stopping…" arms. ✓
- **File paths / APIs** — all target files exist; `ppgLog` is already imported in `camera_ppg_service.dart`; `CircularProgressIndicator`/`StateBanner`/`SectionCard` are all available. ✓
- **StreamProvider late-subscriber reasoning is sound** — the `IndexedStack` keeps every screen mounted for the app's lifetime, so `lifecycleProvider` is subscribed once at app start and retains transitions; the broadcast controller emits nothing before the first transition, and screens default `?? SourceLifecycle.idle`, which is correct. ✓

### Minor observations (non-blocking, no action required)

- **Task 3 import:** `stream_providers.dart` will need to import the new `../services/source_lifecycle.dart` for `StreamProvider<SourceLifecycle>`. Trivial and implied; noting only for completeness.
- **Source-screen `stateProvider` becomes unused** after Task 4 rewrites the banner + gating onto `lifecycleProvider`. The implementer should drop the now-dead `ref.watch(stateProvider)` (and its import if nothing else needs it) to avoid an unused-variable lint. Cosmetic.
- **Retry button gating:** `_errorBanner`'s Retry (`source_screen.dart:180-187`) is not gated on lifecycle, but it only renders after a completed (failed) start attempt when lifecycle has already settled to `idle`, and `startMeasurement`'s `_measuring` re-entry guard backstops any stray tap. Safe as-is; no change needed.

### Positive Notes

- The **folding guard** ("while `stopping`/`idle`, ignore kit emits; never downgrade an active source off a stray kit `idle`") is precisely the invariant that prevents lifecycle from bouncing off `stopping` on a late teardown emit — the exact class of bug note 32 documented. Well specified.
- **Synchronous** `starting`/`stopping` at the call boundaries is the right mechanism to close the accepted Raw-entry "Start fires mid-teardown" race by *gating* rather than *awaiting* — correctly reconciled with the fact that a `NavigationBar` callback can't be async (Task 6).
- Scope guards are explicit and correct: kit `lib/` frozen, no `done` state, kit teardown order untouched, note-32 push absorbed not removed.
- Commit plan is coherent (service+provider foundation, then screen consumers) and each commit is independently sensible.

PLAN_REVIEW_PASS
