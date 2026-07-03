# Plan Review 2: Adaptive de-halving stage (plan 24)

## Code Review Summary

**Files Reviewed:** plan 24 (v2) + targets (`lib/src/api/camera_ppg_session.dart`, `test/dehalving/candidates/harmonic_merge.dart`, `test/dehalving/dehalving_eval_test.dart`, `test/dehalving/fixture.dart`, `test/dehalving/scoring.dart`), specs (notes 29, 30), `.ai-factory/ARCHITECTURE.md`, plus round-1 review.
**Risk Level:** 🟢 Low

This is a re-review of plan 24 after round 1. All four round-1 findings are now incorporated, and each fix was checked against the live source rather than taken on faith. No new build-breaking or logic defects found. The plan is faithful to note 30's contract and the reference `HarmonicMergeCandidate`.

### Context Gates

- **ARCHITECTURE.md — PASS.** §Dependency Rules line 43 requires `src/processing/` to depend on `src/models/` only. Task 1's "import **only** `../models/rr_interval.dart`" honors it. The "no barrel export" decision matches line 41 — only `SessionPolicy`/`RrAcceptance` are named `[debug]` exceptions; `RrDehalving` correctly stays internal.
- **RULES.md — n/a (WARN).** No `.ai-factory/RULES.md` present; non-blocking.
- **ROADMAP.md — PASS.** Milestone `Spec:` resolves to note 30; contract "regression tests replay both fixtures, assert BPM within counting error, public streams unchanged" is covered by Tasks 5/6 and the untouched-barrel constraint.
- **Governing spec (note 30) — PASS.** 2:1 buffering `evaluate`/`flush`/`reset` surface, ported defaults kept tunable, no barrel export, `flush()` output discarded at teardown — all match.

### Round-1 Findings — Verification

1. **`<= 3` tolerance (was build-breaking) — FIXED & verified.** Task 5 now sets tolerance to `<= 5` (`_countingErrorBpm + 2` / literal `5.0`) with the rationale spelled out. Confirmed against `dehalving_eval_test.dart:53-55`: `lessThanOrEqualTo(_countingErrorBpm + 2)` with `_countingErrorBpm = 3.0`. The +4.9 fixture-2 pre-gate figure (note 30 table) would have failed a `<= 3` bound; `<= 5` clears it. Task 5 even flags fixture 2 as the binding case.
2. **`convergedAtBeatIndex` porting hazard — FIXED & verified.** Task 1 now adds the explicit "Porting hazard" bullet: replace `_decisions.length` with a standalone `int _beatIndex = 0;` incremented once at the top of `evaluate`, set `_convergedAtBeatIndex = _beatIndex` at bootstrap, drop the `index` params from `_handleShort`/`_handleFull`, and zero `_beatIndex` in `reset()`. Confirmed the reference derives the index from `final index = _decisions.length;` at harmonic_merge.dart:99 and records it at :107 — so the replacement is necessary and correct, and Task 6 still asserts the getter.
3. **`flush()`-then-`reset()` no-op at teardown — FIXED & verified.** Task 4 now says "**Do not call `flush()` here.** … Just `reset()`," matching note 30's permission to discard the tail and avoiding the misleading discarded-drain. Confirmed `reset()` unconditionally clears `_outQueue`/`_pending`/tracker/bootstrap in the reference (harmonic_merge.dart:191-199), so the tail is genuinely dropped as intended.
4. **`isClosed` guard placement — FIXED & verified.** Task 3 now says move `if (_rrController.isClosed) continue;` off the feed and onto the emit; feed every trusted `candidate` to `_dehalving.evaluate(...)` unconditionally, guard only the terminal `_rrController.add(...)`. Confirmed the current loop tests `isClosed` at the top (camera_ppg_session.dart:559, ahead of consuming the beat), so the restructure is required to keep the stage's pending/pair state uncorrupted.

### Line-Reference Spot Checks (all match current source)

- Constructor `CameraPpgSession({SessionPolicy? policy, RrAcceptance? acceptance})` at line 50; `_policy`/`_acceptance` fields at 70/77 — Task 2's injection pattern (~50-58 / ~66-77) is accurate.
- `_release()` at line 418; `_acceptance.reset()` at line 431 — Task 4's reset call site is exact.
- RR-gating loop `for (final rr in newIntervals)` at 558 with `candidate` build at 570-574 and `_rrController.add(_acceptance.evaluate(candidate))` at 575 — Task 3's restructure target matches.
- Test harness reuse is real: `loadAll()` / `CalibrationFixture.toRrIntervals()` / `referenceBpm` in `fixture.dart`; `classifyBeat(int rrMs, CalibrationFixture)` + `ClusterMembership.{trueCluster,halvedCluster}` in `scoring.dart:33,41`. The `../dehalving/…` relative import from `test/processing/` resolves, and `loadAll()` is package-root-relative (`Directory.current.path`), so loading fixtures from a different test dir still works.
- Task 5 correctly does **not** reuse `runHarmonicMerge` (which depends on `candidate.outcomes`/`BeatOutcome`, both dropped from the production stage) — it feeds the fixtures through the production `RrDehalving.evaluate`/`flush()` directly. Consistent with Task 1 dropping the offline scaffolding.

### Positive Notes

- The plan pins the failure-prone details that round 1 exposed *at the exact call site / line*, so the implementer cannot re-introduce them: the guard-on-emit, the `_beatIndex` replacement, and the `<= 5` bound are each stated with source justification.
- Keeping tracker params as constructor parameters leaves note 34's default-promotion a signature-free change.
- Merged-output `RrInterval(intervalMs: sum, timestamp: rr.timestamp)` compiles cleanly (`isArtifact` defaults false) and preserves the reference timestamp contract; Task 6 asserts the second-beat timestamp is carried.
- Teardown-invariant awareness is correct — `RrDehalving` touches no isolate/camera state, so `reset()` placement is ordering hygiene, not a new teardown surface.

No blocking or non-blocking issues remain. The plan is ready to implement.

PLAN_REVIEW_PASS
