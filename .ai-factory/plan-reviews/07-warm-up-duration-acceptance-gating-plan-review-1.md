# Plan Review: Warm-up / duration / acceptance gating (07)

**Plan:** `.ai-factory/plans/07-warm-up-duration-acceptance-gating.md`
**Spec:** `.ai-factory/notes/09-session-policy.md`
**Risk Level:** 🟢 Low — the plan is accurate and well-scoped; the findings below are precision clarifications, not structural problems.

## Verified assumptions (all correct)

Every concrete codebase claim in the plan was checked against source and holds:

- `_setState(MeasurementState.measuring)` on successful lock is at **line 281** ✓; the unconditional `_setState(MeasurementState.measuring)` at the end of `_onSignal` is at **line 460** ✓; `_onSignal` starts at **line 426** ✓; `_release()` resets to `idle` at **line 376** ✓; the stale `_state` field comment is at **~line 57** ✓.
- Both lock paths (auto-detect via `_lockCoveredCamera` and the pinned `useCamera` path) converge on the **single** `_setState(...measuring)` at line 281, so replacing that one point correctly covers both — the plan's "line ~281" hook is sufficient. ✓
- Model APIs used are real: `FingerPresence.fromRawIntensity(double)` and `SignalQuality.fromSnr(double)` exist with the described NaN handling. ✓
- Enum orders match: `SignalQuality` is `good`(0)/`fair`(1)/`poor`(2), `FingerPresence` is `present`(0)/`absent`(1)/`overBright`(2). The acceptance predicate `quality.index < sqiFloor.index` with `sqiFloor = poor` accepts `good`/`fair`, rejects `poor`; with `fair` it additionally rejects `fair`. Logic is internally consistent. ✓
- Barrel already exports `camera_ppg_session.dart` and `finger_presence.dart`, so `fingerPresenceStream` (a getter on the exported class) needs no barrel change. ✓ `processing/` is intentionally **not** exported, matching the "do not export from the barrel" instruction and ARCHITECTURE dependency rules. ✓
- `lowerCamelCase` const naming (not SCREAMING_CASE) is the correct project convention (RULES `base.md`). ✓
- Pure-`processing` rule (no `camera`/`flutter_ppg`/Flutter imports; depend on `models/` only) matches ARCHITECTURE §Dependency Rules. ✓ Injecting elapsed time rather than owning a `Timer`/clock keeps it isolate-safe and testable — aligns with spec Guard. ✓
- `nlog('state: <prev> → <next>')` matches the actual `nlog` signature. ✓
- Test approach mirrors the existing pure-unit style (`camera_ppg_session_rr_conversion_test.dart`). ✓
- ROADMAP Phase 5 entry and the spec's defaults (warmup 5s, target 60s, silence 3s, SQI floor Poor) match the plan's constants exactly. ✓

## Context Gates

- **Architecture (ARCHITECTURE.md):** PASS. Policy in `processing/` (pure), clock/stream wiring in `api/`, no new barrel/public leakage beyond the deliberate `fingerPresenceStream` getter. Consistent with the layer boundaries.
- **Rules (rules/base.md):** PASS. Naming, module placement, logging-through-`nlog`, and no-throw-across-boundary all respected.
- **Roadmap (ROADMAP.md):** PASS. Directly implements the Phase 5 "Warm-up / duration / acceptance gating" milestone and correctly defers RR-per-beat artifact gating to Phase 6 (note 12), matching spec Guard.

## Findings (non-blocking — address before/at implementation)

### 1. Keep the RR diff bookkeeping unconditional; gate only the `add` (WARN, correctness)
Task 3 says "forward to `_rrController` **only when `_policy.rrTrusted`**" but does not say what happens to the `diffNewIntervals(...)` call and the `_lastRrIntervals = signal.rrIntervals` update (lines 431–432) during `warmup`/`poorSignal`. If an implementer wraps the *entire* RR block — diff + `_lastRrIntervals` update + the forward loop — in `if (_policy.rrTrusted)`, then `_lastRrIntervals` stays empty/stale through warm-up, and on the **first** `measuring` tick `diffNewIntervals(const [], currentWindow)` returns the whole sliding window — dumping the warm-up beats as "trusted." That is exactly the behavior the spec says to withhold ("do not forward warm-up beats to `rrStream` as trusted"). Same hazard on `poorSignal → measuring` resume.
**Fix:** state explicitly that `diffNewIntervals` and the `_lastRrIntervals` assignment must run **every tick regardless of trust**, and only the `_rrController.add(...)` inside the `for` loop is gated on `_policy.rrTrusted`.

### 2. Pin down measuring-time accumulation ordering to avoid a first-tick over-count (WARN, spec precision)
Task 1 says accumulate `(elapsed - lastElapsed)` "on ticks taken while in `measuring`" and "Track `lastElapsed` each tick." This is ambiguous about the transition tick. If accumulation is evaluated *after* the `warmup → measuring` transition on the same tick, and no prior tick advanced `lastElapsed` (a sparse synthetic sequence — plausible in the Task 2 tests), the transition tick adds up to `warmupDuration` of phantom measuring time. The `poorSignal → measuring` resume has the same shape (it would count the silence gap). At ~24 FPS in production the delta is one frame, but the Task 2 unit tests drive discrete ticks and depend on exact accumulation.
**Fix:** specify the ordering — e.g. per tick: (a) compute `delta = elapsed - lastElapsed`; (b) add `delta` to `_measured` **only if the state at tick entry was `measuring`**; (c) then evaluate transitions; (d) always update `lastElapsed = elapsed`. This makes "of measuring" precise and deterministic for the tests, and guarantees `lastElapsed` advances in every state (which is what makes the resume delta small).

### 3. `start()` dartdoc also asserts success ⇒ `measuring` (WARN, missed doc update)
Task 3 lists only the `_state` field comment (~line 57) for the "later phase" doc cleanup, but the `start()` dartdoc (**~lines 136–139**) also states *"Returns `null` on success (state moves to `MeasurementState.measuring`)."* After this change, success moves to `warmup`. Add the `start()` dartdoc to the update list so the public contract comment stays truthful.

### 4. Stopwatch reset/restart semantics (nitpick)
Task 3 says "reset+started" and "`(re)start`" the stopwatch. `Stopwatch` has no `restart()`; a bare `.start()` after a prior cycle **resumes** accumulated time. The reset is essential across start/stop cycles — spell it out as `_stopwatch..reset()..start()` on lock and `_stopwatch.stop()` in `_release()`, and note the `_stopwatch` field declaration explicitly (currently only implied).

## Positive notes

- Correctly keeps the policy a pure function of `(events, elapsed)` with the caller injecting the clock — satisfies the spec's "testable without hardware" Guard and the ARCHITECTURE purity rule.
- Correctly separates session-state decisions from per-beat `isArtifact` (deferred to Phase 6), matching spec Guard.
- Correctly keeps `qualityStream`/`debugSignalStream` (and the new `fingerPresenceStream`) flowing in all states while gating only RR — matches the "host renders quality continuously" intent.
- Correctly does **not** auto-release on `done` (which would reset to `idle`) and keeps the camera running until the host calls `stop()`.
- Task decomposition respects dependencies (Task 2 → 1, Task 3 → 1, Task 4 → 3) and is independently revertable, matching the ROADMAP's atomic-task discipline.

## Verdict

The plan is architecturally sound and its codebase assumptions are all accurate. Findings 1 and 2 are precision gaps that could produce subtle RR-leak / timing bugs (and directly affect the mandated unit tests) if left to implementer interpretation; 3 and 4 are minor. Fold these clarifications into the tasks and the plan is ready to implement.
