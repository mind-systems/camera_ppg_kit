## Code Review Summary

**Files Reviewed:** 1 plan + 6 codebase files (`camera_ppg_service.dart`, `stream_providers.dart`, `source_screen.dart`, `measurement_state.dart`, `signal_quality.dart`, `ROADMAP.md` + spec note 32)
**Risk Level:** 🟢 Low

The plan is a minimal, correctly-scoped, example-only unstick. Every codebase claim it makes was verified against the actual source and holds. The fix is sound and safe on all call paths.

### Context Gates

- **Roadmap (line 56, spec `notes/32-stop-idle-transition-fix.md`):** Milestone matches the plan title and root spec exactly. Root correctly recovered. **WARN — contract narrowing on SQI:** the ROADMAP contract line promises the fix "clears stale SQI/BPM", and spec note 32 says to "reset the other display streams as appropriate so a stale SQI/BPM does not linger." The plan clears BPM (via the idle cascade) but **does not clear SQI**, downgrading it to a documented limitation. This deviation is technically correct and well-justified (see below), and the spec's "as appropriate" wording plus the explicit note-33 handoff give latitude — non-blocking, but flagged so the orchestrator/author is aware the contract's SQI promise is being narrowed rather than met.
- **Architecture / Rules:** No boundary or convention violations. Change stays entirely inside `example/lib/services/` (the composition-root layer), respects the "no `flutter`/`riverpod`/`camera`/`flutter_ppg` imports in the service" rule (the change adds none), and honors the Phase-10 freeze (kit `lib/` and public `MeasurementState`/`CameraPpgSession` untouched).
- **No skill-context file** present (`.ai-factory/skill-context/` empty) — no project overrides to apply.

### Critical Issues

None.

### Verified Claims (all correct)

- **File path & line numbers:** `example/lib/services/camera_ppg_service.dart`, `stopMeasurement()` at 140–153, `BpmNotifier` state-reset at 57–66 — all accurate.
- **No `done` state:** `MeasurementState` has exactly `idle/warmup/measuring/poorSignal` (`measurement_state.dart:5-19`). The terminal state is `idle`. Correct.
- **BPM cascade:** `BpmNotifier` (`stream_providers.dart:57-61`) resets `state = null` on `MeasurementState.idle`, and it subscribes to `service.stateStream` (= `_stateController.stream`). Pushing `idle` into `_stateController` will cascade to clear BPM — confirmed, no extra BPM code needed.
- **Banner/buttons are state-driven:** `source_screen.dart:125-129` derives `isRunning`/`canStop` from `stateProvider`; the idle push restores banner "Idle", re-enables Start, disables Stop. Confirmed across Source/Streams/Calibration screens.
- **SQI cannot be cleared service-side:** confirmed — `SignalQuality` has only `good/fair/poor`, no "none"/reset value (`signal_quality.dart:21-29`); the SQI chip gates on the `qualityProvider` `AsyncValue` (`source_screen.dart:243-247`), which cannot revert `data`→`loading`. The chip is rendered unconditionally once data has arrived (not gated on run state), so the residual is real and genuinely un-fixable through the quality stream. Routing it to note-33 display-layer territory is the right call under a service-only scope.
- **`!isClosed` guard is safe on the `dispose()` path:** `dispose()` sets `_disposed`, calls `stopMeasurement()` (controller still open → idle pushed), *then* closes controllers — so the guard never suppresses the push during dispose and never touches a closed controller. Correct.
- **Failed-start path:** `startMeasurement` calls `stopMeasurement()` on error (line 125) with a non-null session, so it takes the full teardown path and pushes `idle` — a correct reset after a failed start (the error banner is surfaced separately). No spurious/incorrect emit.
- **Early `session == null` no-op left unchanged:** correct — when no session exists, state is already `idle`, so no push is warranted.
- **Broadcast timing:** listeners (`stateProvider`, `bpmProvider`) are active when Stop is pressed, so the broadcast `add` is delivered (not dropped). No missed-emit risk.

### Advisory Notes (non-blocking)

1. **SQI residual visibility.** Because `_signalCard()` renders the SQI `StatusChip` whenever `qualityProvider` holds data — regardless of state — the stale SQI band *will* remain visibly on-screen after Stop returns to Idle. The plan documents this accurately as an out-of-scope, known limitation. Just ensure the on-device Verify step notes the SQI chip as an expected residual so a tester doesn't file it as a regression. (The spec's Verify item #3 — "consumers show their waiting / start-the-source-first states again" — is satisfied for the *banner/state*, which is what matters for the unstick.)
2. **Testing: no** is appropriate here. Per the project's test philosophy, this is a loud/visual UI surface verified manually on device (camera+torch unavailable on simulators), not a silent-failure surface warranting an automated test.

### Positive Notes

- Correct root-cause framing: making the service self-sufficient (direct idle push) rather than reordering to dispose-then-cancel keeps correctness decoupled from the session's synchronous dispose behavior — the more robust of the two fixes.
- Scope discipline is excellent: respects the Phase-10 freeze, touches one file, and explicitly refuses to reintroduce `done`.
- The plan honestly surfaces the SQI limitation instead of silently ignoring the contract's "clears stale SQI" wording, and correctly hands it off to the note-33 lifecycle/display work that "wraps note 32's idle push."
- Dartdoc-update task (Task 2) keeps the code's stated contract in sync with the new behavior.

PLAN_REVIEW_PASS
