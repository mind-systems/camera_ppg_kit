# Plan Review 2: Warm-up / duration / acceptance gating (07)

**Plan:** `.ai-factory/plans/07-warm-up-duration-acceptance-gating.md`
**Spec:** `.ai-factory/notes/09-session-policy.md`
**Files Reviewed:** plan + `camera_ppg_session.dart`, `measurement_state.dart`, `finger_presence.dart`, `signal_quality.dart`, `neiry_kit/.../ppg_peak_detector.dart`, existing test, barrel, ARCHITECTURE.md, rules/base.md, ROADMAP.md
**Risk Level:** 🟢 Low — the plan is accurate, well-scoped, and folds in every finding from review-1.

## Review-1 findings — all resolved

- **F1 (RR bookkeeping unconditional, gate only the `add`)** → Task 3 now has a dedicated "RR gating — gate only the emit, not the bookkeeping" bullet that spells out the stale-`_lastRrIntervals` / warm-up-dump hazard on both the `warmup → measuring` and `poorSignal → measuring` edges. ✓
- **F2 (per-tick accumulation ordering)** → Task 1 now pins the exact deterministic sequence (a)`delta`, (b) accumulate only if state-at-entry was `measuring`, (c) evaluate transitions, (d) always update `lastElapsed`. Task 2 adds a sparse-tick test that exercises it. ✓
- **F3 (`start()` dartdoc says success ⇒ `measuring`)** → Task 3 now explicitly lists the `start()` dartdoc (~lines 136–139) alongside the `_state` field comment (~line 57) for the doc cleanup. ✓
- **F4 (Stopwatch reset/restart semantics)** → Task 3 now declares the `final Stopwatch _stopwatch` field and specifies `_stopwatch..reset()..start()` on lock and `_stopwatch.stop()` in `_release()`. ✓

## Verified assumptions (all correct)

- Line hooks hold: `_setState(MeasurementState.measuring)` on lock at **281** ✓; unconditional `_setState(...measuring)` at end of `_onSignal` at **460** ✓; RR diff/`_lastRrIntervals` at **431–432** ✓; `_onSignal` at **426** ✓; `_release()` → `idle` at **376** ✓; stale `_state` comment at **57** ✓; `start()` dartdoc success line at **136–139** ✓. Both lock paths (auto-detect and pinned) converge on the single line-281 `_setState`, so the one hook covers both.
- Model APIs are real: `FingerPresence.fromRawIntensity(double)` (with `NaN → absent`) and `SignalQuality.fromSnr(double)` (with `NaN → poor`, `0.0 → poor`) exist as described.
- Enum orders match: `SignalQuality` `good`(0)/`fair`(1)/`poor`(2), `FingerPresence` `present`(0)/`absent`(1)/`overBright`(2). The predicate `presence == present && quality.index < sqiFloor.index` with `sqiFloor = poor` accepts `good`/`fair`, rejects `poor`; with `fair` it additionally rejects `fair`; `absent`/`overBright` always reject. Internally consistent and matches "reject at/below the floor."
- `rrTrusted => state == measuring` correctly withholds RR in `warmup`/`poorSignal`/`done`.
- Purity rule respected: `processing/` depends on `models/` only, injects elapsed time rather than owning a `Timer`/clock — isolate-safe and hardware-free testable (ARCHITECTURE §Dependency Rules + rules/base.md). Not exported from the barrel. ✓
- Barrel already exports `camera_ppg_session.dart` and `finger_presence.dart`, so `fingerPresenceStream` (a getter on the exported class) needs no barrel change. ✓
- `lowerCamelCase` const defaults are the correct project convention (rules/base.md), not SCREAMING_CASE. ✓
- Constructor stream-controller pattern (opened in the initializer list, closed in `dispose`) matches the four existing controllers; adding a fifth `FingerPresence` broadcast controller is a mechanical extension of the same pattern. ✓
- Test approach mirrors the existing pure-unit style (`camera_ppg_session_rr_conversion_test.dart`). ✓
- Defaults (warmup 5s, target 60s, silence 3s, SQI floor Poor) match spec note 09 and the ROADMAP Phase 5 entry exactly; RR-per-beat `isArtifact` is correctly deferred to Phase 6 (note 12). ✓

## Context Gates

- **Architecture (ARCHITECTURE.md):** PASS. Pure policy in `processing/`, clock/stream wiring in `api/`, single deliberate public-surface addition (`fingerPresenceStream`). No `flutter_ppg`/`camera` type leaks across the boundary.
- **Rules (rules/base.md):** PASS. Naming, module placement, `nlog` logging, no-throw-across-boundary all respected.
- **Roadmap (ROADMAP.md):** PASS. Directly implements the Phase 5 "Warm-up / duration / acceptance gating" milestone; defers RR artifact gating to Phase 6 as the roadmap intends. Correctly notes the CALIBRATION HANDOFF applies later (defaults are provisional but overridable).
- No `.ai-factory/skill-context/` present — no project-specific overrides to apply.

## Implementation guidance (no defect — for the implementer, not blocking)

- **Evaluate `_policy.onSignal` before the RR emit loop within `_onSignal`.** The RR diff/emit block currently sits at the *top* of `_onSignal` (line 431), while Task 3 describes calling the policy *after* computing quality/presence (~line 452+). If the policy call lands after the emit loop, the loop's `_policy.rrTrusted` guard reads the *previous* tick's state — a one-frame lag. This is harmless in every direction I traced (no untrusted-beat leak on any edge, since the silence-window grace already emits during brief dips, and the transition-frame beats are consumed by the unconditional diff either way), so it is not a correctness defect. But to keep behavior deterministic and match the intent, compute `presence` and call `final next = _policy.onSignal(...)` **above** the RR loop, then gate the `add` on `_policy.rrTrusted`. Pure `SessionPolicy` (Task 1/2) is unaffected either way.

## Positive notes

- Keeps the policy a pure function of `(events, elapsed)` with the caller injecting the clock — satisfies the spec's "testable without hardware" Guard and the ARCHITECTURE purity rule.
- Cleanly separates session-state decisions from per-beat `isArtifact` (Phase 6), per spec Guard.
- Keeps `qualityStream`/`debugSignalStream`/`fingerPresenceStream` flowing in all states while gating only RR — matches "the host renders quality continuously."
- Does **not** auto-release on `done` (which would reset to `idle`); camera stays live until the host calls `stop()`.
- The "of measuring" accumulation reading (poorSignal/warm-up gaps don't count toward `targetDuration`) is documented as a deliberate choice, and the sparse-tick test locks it against regression.
- Task dependencies are correct and each task is independently revertable (Task 2 → 1, Task 3 → 1, Task 4 → 3).

## Verdict

All four review-1 findings are resolved, every concrete codebase claim re-checked against source holds, and the context gates pass. The one remaining item is non-blocking implementation guidance (intra-`_onSignal` ordering), not a defect. The plan is ready to implement.

PLAN_REVIEW_PASS
