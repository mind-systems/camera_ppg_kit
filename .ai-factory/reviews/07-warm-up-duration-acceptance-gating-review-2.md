# Code Review 2: Warm-up / duration / acceptance gating (07)

**Plan:** `.ai-factory/plans/07-warm-up-duration-acceptance-gating.md`
**Spec:** `.ai-factory/notes/09-session-policy.md`
**Scope:** `lib/src/processing/session_policy.dart` (new), `lib/src/api/camera_ppg_session.dart` (modified), `test/session_policy_test.dart` (new).

Independent second pass, read against the full surrounding files rather than the diff alone.

## Verification performed

- `flutter test` (full suite) → **45/45 pass**, including the 8 new `SessionPolicy` cases and the existing `rr_diff`/models suites (confirms the `_onSignal` rewrite did not regress the RR-diff passthrough).
- `flutter analyze lib test` → **no issues**.
- Hand-traced every state transition (`idle → warmup → measuring ⇄ poorSignal → done`) against the tick sequences in the tests and against the spec.

## Review-1 finding status

- **Stale "four broadcast streams" dartdocs — RESOLVED.** Both `stop()` (line 352) and `dispose()` (line 359) now read "the broadcast streams" with no count, and `dispose()` closes all five controllers including `_fingerPresenceController` (line 368). No stale count remains anywhere (`grep` for `broadcast streams` shows only count-free phrasings).

## Correctness analysis (no defects found)

- **Policy purity & determinism.** `SessionPolicy` depends only on `models/`; it owns no timer/clock and takes `elapsed` as a parameter. The per-tick order — compute `delta`; accumulate into `_measured` only when the *entry* state is `measuring`; then evaluate the transition; then unconditionally advance `_lastElapsed` — is implemented exactly as pinned (lines 102–153). This is what makes "targetDuration *of measuring*" precise: warm-up and silence gaps are never retroactively banked, verified by the sparse-jump test (elapsed 100 → 9999 → 10005).
- **Acceptance predicate** `presence == present && quality.index < sqiFloor.index` (line 102–103) matches the enum orderings (`good`0/`fair`1/`poor`2): default floor `poor` rejects only `poor`; `fair` floor also rejects `fair`; `absent`/`overBright` always reject. Both the override test and its control assertion cover the boundary.
- **RR gating is correct.** `diffNewIntervals(...)` and `_lastRrIntervals = signal.rrIntervals` run unconditionally every tick (lines 469–470); only `_rrController.add(...)` is guarded by `_policy.rrTrusted` (line 494). Traced: through warm-up the diff is consumed and discarded while `_lastRrIntervals` stays current, so the first `measuring` tick emits only that frame's genuinely-new beat(s) — no dump of the withheld window. Same reasoning holds on `poorSignal → measuring` resume.
- **Gate reads the post-transition state**, which is the right choice for each edge: warm-up→measuring emits; measuring→poorSignal and measuring→done both withhold that tick's beats; poorSignal→measuring emits.
- **Stopwatch lifecycle.** Instance field; `..reset()..start()` on lock (line 310–312), `.stop()` in `_release()` (line 401). Reads are monotonic, so `delta >= 0` always — `_measured` cannot go backwards or negative. Re-`start()` after a prior cycle correctly re-resets.
- **No re-entrancy window.** `_policy.reset()` + stopwatch setup complete synchronously inside `start()` before it returns (lines 309–316, no `await` between the `sub` `.listen()` at 292 and this block), so the first async `_onSignal` never observes an un-reset policy. A stray buffered frame during teardown (between `_stopwatch.stop()` and `sub.cancel()`) is benign and is pre-existing behavior, not introduced here.
- **`fingerPresenceStream`** opened in the constructor, emitted in every state (line 516–518), closed in `dispose()`; reachable via the already-exported class and the already-exported `FingerPresence` type — no barrel change needed, matching the plan.
- **Doc updates applied.** `_state` field comment and `start()` dartdoc success line both describe the real machine (`→ warmup`, then advances via `SessionPolicy`).

## Observations (by-design, not findings)

- **No overall wall-clock timeout.** A session that never accumulates `targetDuration` of `measuring` time (e.g. stuck oscillating into `poorSignal`) never reaches `done` — `done` is only reachable from `measuring`. This is exactly the spec's "after targetDuration *of measuring*" wording; giving up is the host's responsibility. Called out only for completeness; the implementation matches the spec and plan intent.

## Assessment

The prior review's sole finding is fixed, the full test suite and analyzer are green, and a fresh trace of the state machine, RR-gating, timing accumulation, and re-entrancy paths surfaced no correctness, security, or runtime bugs. Nothing to fix.

REVIEW_PASS
