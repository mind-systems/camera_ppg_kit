# Plan Review: Adaptive de-halving stage (plan 24)

## Code Review Summary

**Files Reviewed:** plan 24 + targets (`camera_ppg_session.dart`, `rr_acceptance.dart`, `rr_interval.dart`), reference impl (`test/dehalving/candidates/harmonic_merge.dart`), harness (`fixture.dart`, `scoring.dart`, `dehalving_eval_test.dart`), specs (notes 29, 30, 34), `ARCHITECTURE.md`, `ROADMAP.md`
**Risk Level:** 🟡 Medium

The plan is faithful to note 30's design and the reference `HarmonicMergeCandidate`. Line references (constructor ~50-58, fields ~66-77, RR-gating block ~558-576, `_release()` ~418-441 with `_acceptance.reset()` at 431) all match the current source exactly. Wiring, injection pattern, and the pure-`processing/` dependency rule are correct. One finding will break the build as specified; one is a porting hazard that silently breaks a getter Task 6 tests.

### Context Gates

- **ARCHITECTURE.md — PASS.** The dependency rule (`.ai-factory/ARCHITECTURE.md` §Dependency Rules) says `src/processing/` depends on `src/models/` only. Task 1's "import **only** `../models/rr_interval.dart`" honors this. The "no barrel export" decision matches §Dependency Rules bullet 1 (only `RrAcceptance`/`SessionPolicy` are `[debug]` exceptions; `RrDehalving` correctly stays internal). No gate issue.
- **RULES.md — n/a.** No `.ai-factory/RULES.md` present (WARN, non-blocking).
- **ROADMAP.md — PASS.** Milestone resolves to `ROADMAP.md` line 64 ("Adaptive de-halving stage", `Spec: .ai-factory/notes/30-adaptive-dehalving-impl.md`). The contract line requires "Regression tests replay both fixtures and assert BPM within counting error; public streams unchanged" — the plan covers both. Note that the contract line's "within counting error" is the exact phrase that Critical Issue #1 below hinges on.
- **Governing specs — PASS.** Notes 29 (design), 30 (impl contract), 34 (future defaults) all read; the plan's contract (2:1 buffering `evaluate`/`flush`/`reset`, ported defaults, no barrel export, discard `flush()` at teardown) matches note 30 verbatim.

### Critical Issues

**1. Task 5's `<= 3` BPM tolerance will fail on fixture 2 — the plan misreads the eval harness's tolerance.**
Task 5 says: *assert `abs(derivedBpm - fixture.referenceBpm) <= 3` (the ±3 counting-error tolerance used in `dehalving_eval_test.dart`)*.

That parenthetical is factually wrong. `dehalving_eval_test.dart` does **not** assert `<= 3`; it asserts `lessThanOrEqualTo(_countingErrorBpm + 2)` where `_countingErrorBpm = 3.0` — i.e. an effective **`<= 5`** (line 55). The `+2` margin exists *precisely because* note 30's recorded evidence table lists **fixture 2 harmonic-merge BPM error = +4.9** (pre-gate de-halved output). Task 5 replays exactly that pre-gate path (`evaluate` non-null outputs + `flush()`, no downstream gate), so it will reproduce ≈+4.9 on fixture 2 — which **exceeds `3`** and fails the assertion. The regression test as written cannot pass, so Commit 2 (and the milestone's "flutter test green" verify in note 30) is unreachable.

Fix: make the tolerance `<= 5` (or reuse the harness's `_countingErrorBpm + 2` form) and correct the parenthetical. If a per-fixture asymmetry is preferred (fixture 1 ≈+0.8 is much tighter), state fixture-2's known +4.9 explicitly rather than a single `<= 3` bound. Either way, `<= 3` is not shippable.

### Non-Critical Issues

**2. (Medium) Dropping `_decisions`/`BeatOutcome` also removes the mechanism that feeds `convergedAtBeatIndex` — which Task 6 asserts.**
In the reference, the per-beat index comes from `final index = _decisions.length;`, and bootstrap convergence records `_convergedAtBeatIndex = index;` (harmonic_merge.dart:99, 107). Task 1 tells the implementer to *"port the state machine verbatim"* **and** drop `_decisions`, `_pendingIndex`, and the `BeatOutcome` writes — but those two instructions collide on the `index` plumbing. If the implementer removes `_decisions` and the `index`/`_pendingIndex` params naively, `convergedAtBeatIndex` loses its source and returns wrong/`null` values — and Task 6 explicitly asserts *"`convergedAtBeatIndex` set"* after bootstrap. The plan should call out that a standalone beat counter (e.g. `int _beatIndex = 0;` incremented once per `evaluate`) must replace `_decisions.length` when the offline scaffolding is stripped, so the retained getter keeps working. `_handleShort`/`_handleFull` then no longer need their `index` params at all.

**3. (Low) Task 4: calling `flush()` and discarding its result immediately before `reset()` is a functional no-op.**
`flush()` only drains `_outQueue` + the pending beat; `reset()` clears `_outQueue`, `_pending`, tracker, and bootstrap unconditionally. Since Task 4 discards `flush()`'s return (correct per note 30 — the controller may be tearing down) and then calls `reset()`, the `flush()` call does nothing observable. It's harmless, but either drop the `flush()` call (just `reset()`) or, if kept for symmetry with note 30's "drain at end-of-stream", add a one-line comment that its output is intentionally dropped so a future reader doesn't "fix" it by piping to `_rrController` during teardown.

**4. (Low) Task 3: feed `_dehalving.evaluate(candidate)` regardless of `_rrController.isClosed`; guard only the `add`.**
The current loop does `if (_rrController.isClosed) continue;` *before* building/consuming the beat (line 559). If the implementer keeps that guard ahead of `_dehalving.evaluate(...)`, a teardown-race tick would skip feeding the stage and corrupt its pending/pair state for the next beat. The stage must see every trusted `candidate` in order; only the terminal `_rrController.add(...)` needs the `isClosed` guard. The plan says "keep the existing `_rrController.isClosed` guard" without pinning *where* — pin it to the emit, not the feed.

### Positive Notes

- Test-import strategy is sound even without a barrel export: the repo already imports internal processing types directly (`rr_acceptance_test.dart` / `session_policy_test.dart` use `package:camera_ppg_kit/src/processing/...`), so `rr_dehalving_test.dart` can import `RrDehalving` the same way. No barrel change needed — matches ARCHITECTURE §Dependency Rules.
- `RrInterval` merged-output construction is safe: `isArtifact` defaults to `false` (rr_interval.dart:19), so the ported `RrInterval(intervalMs: sum, timestamp: rr.timestamp)` compiles and preserves the reference's timestamp contract.
- Reuse of the existing `fixture.dart` / `scoring.dart` harness (Task 5) rather than rewriting is the right call and matches note 30's "harness can likely be adapted/reused" guidance.
- Keeping the tracker params as constructor parameters (Task 1) correctly leaves the door open for note 34 to promote validated defaults without a signature change.
- Teardown-invariant awareness (Task 4) is correct: `RrDehalving` touches no isolate/camera state, so `flush()`/`reset()` placement is pure ordering hygiene, not a new teardown surface.

Fix Critical Issue #1 (build-breaking) and address the `convergedAtBeatIndex` porting hazard (#2), and this plan is ready.
</content>
</invoke>
