# Plan Review 2 — Drop-in API freeze + docs (plan 30)

## Code Review Summary

**Files Reviewed:** plan `30-drop-in-api-freeze-docs.md` + prior review `…-plan-review-1.md`, and targeted code/spec: `lib/camera_ppg_kit.dart`, `lib/src/api/camera_ppg_session.dart`, `lib/src/models/measurement_state.dart`, notes `19-drop-in-api-freeze.md` & `30-adaptive-dehalving-impl.md`, `README.md`, `ROADMAP.md`, `ARCHITECTURE.md`
**Risk Level:** 🟢 Low

This is the second-round review of a plan that was revised after review 1. Its purpose is to confirm review 1's two critical issues are closed and that the revision introduced no new defects.

### Context Gates

- **Root recovery — OK.** Plan heading `# Plan: Drop-in API freeze + docs` matches `ROADMAP.md` line 99 (Phase 10, "Drop-in API freeze + docs", `Spec: .ai-factory/notes/19-drop-in-api-freeze.md`). Gates applied against note 19, with note 30 (`30-adaptive-dehalving-impl.md`) correctly pulled in as the reconciliation source for the `RrDehalving` stage.
- **ARCHITECTURE.md — OK.** Dependency-rules block (line 41) ratifies exactly the `[debug]` exception the plan freezes: `SessionPolicy` (`src/processing/session_policy.dart`) + `RrAcceptance` (`src/processing/rr_acceptance.dart`) are the *only* deliberate `src/processing/` re-exports; "the rest of `src/processing/` … stays unexported." Plan Task 1/Task 2 align verbatim. No boundary conflict.
- **RULES.md — WARN (absent).** No `.ai-factory/RULES.md` and no `skill-context/aif-review/SKILL.md`; no project-specific review overrides to apply. Non-blocking.
- **ROADMAP.md — OK (contradiction from review 1 is resolved).** Roadmap lines 56/57 state plainly "no `done` state (note 23)." Review 1's Critical 1 flagged the earlier draft for documenting a `done` state; this revision's Task 4 now documents `idle → warmup → measuring ⇄ poorSignal` and *explicitly* states there is **no** `done` terminal state. Consistent with roadmap history.

### Review 1 Regression Check (both critical issues closed)

- **Critical 1 (Task 4 documented a nonexistent `done` state) — RESOLVED.** Task 4 (line 41) now prescribes `idle → warmup → measuring ⇄ poorSignal` (returning to `idle` on `stop()`) and adds an explicit "there is **no** `done` terminal state — `MeasurementState` is `idle, warmup, measuring, poorSignal` only" clause. Matches `measurement_state.dart` (four values, no `done`) verbatim.
- **Critical 2 (freeze audit ignored the stale `done` dartdoc) — RESOLVED.** Task 2 now carries a dedicated bullet: "Fix the stale state-machine dartdoc on `CameraPpgSession._state` (`camera_ppg_session.dart:103`)." Confirmed: line 103 today reads `warmup → measuring ⇄ poorSignal → done per [SessionPolicy]`, and the plan's replacement (`idle → warmup → measuring ⇄ poorSignal`, terminal `idle` on stop) is correct. The only other `done` hit in `lib/` is benign prose in `frame_isolate.dart:146` ("initialization done"), correctly left untouched.
- **Minor 1 (incomplete drift attribution) — RESOLVED.** Task 2 now enumerates all three barrel↔note-19 deltas explicitly: (a) note-30 `RrDehalving` third ctor param, (b) `RrAcceptanceConfig` → `RrAcceptance` type rename, (c) `SessionPolicy`/`policy` exported extra ratified by ARCHITECTURE line 41 — with the explicit instruction "do **not** restore the barrel to note 19's literal text." Prevents the "restore to stale spec" trap.

### Verified Accurate (spot-checks against current code)

- **Ctor shape.** `CameraPpgSession({SessionPolicy? policy, RrAcceptance? acceptance, RrDehalving? dehalving})` (lines 52–66) — confirms deltas (a) and (b); `acceptance` is `RrAcceptance?`, not `RrAcceptanceConfig?`.
- **`RrDehalving` is genuinely unexported.** `grep` of the barrel returns zero hits for `rr_dehalving`/`RrDehalving`. Task 2's reasoning holds: the `dehalving` ctor param is public, but with the type unexported a barrel-only consumer cannot name it to construct one — internal-default-only, not a public knob.
- **Barrel exports.** `RrAcceptance` and `SessionPolicy` are the only two `src/processing/` re-exports (lines 17–18); all other exports resolve to `src/models/` or `src/api/`. Task 1 bullet 2 correctly overrides note 19's stale line 51 ("`src/processing` … NOT exported") by carving out these two as the deliberate exception — matching ARCHITECTURE, not contradicting it.
- **Member enumeration.** The 13 members Task 1 lists match `CameraPpgSession`'s public surface exactly; `buildPreview()` returns a plain `Widget?` (line 193); no `camera`/`flutter_ppg`/channel type crosses any signature.
- **Task 4 RR-contract claims.** RR-only (no BPM/HRV stream), silent stream on poor signal (RR emit gated on `_policy.rrTrusted`, no placeholder ticks — lines 607–647), and `RrInterval.isArtifact` as the single artifact channel — all match `_onSignal` and note 19 §Contract-fit.
- **README target.** `README.md` line 35 carries the "Early stage" Status text Task 3 replaces; the file exists and the section is where the plan expects it.

### Critical Issues

None.

### Minor Issues / Suggestions

- **(Non-blocking) Task 3 scope note.** `README.md` line 27 (Running the example) still says the example shows "live RR/BPM." That line is example-app description, not the frozen-contract statement, and is outside this plan's Task 3/Task 4 scope (which target the Status section and a new consumer section). No action required; flagged only so the implementer doesn't feel obliged to reconcile it and expand scope.

### Positive Notes

- Scope discipline remains exactly right: audit + docs, zero behaviour change, matching note 19's "this is the freeze, not new behaviour" framing.
- The revision folds review 1's feedback in at the correct altitude — the `done` fix is now anchored to a concrete file:line (`camera_ppg_session.dart:103`), and the state-machine string is identical across Task 2 (dartdoc), Task 4 (README), and the code, so all three will agree post-implementation.
- Boundary statement is preserved where it matters (Task 4): the `camera_ppg` `SensorSource` tag and the `lib/Biometrics/` adapter belong in `mind_mobile`, not the kit — consistent with note 19 §Boundary.
- Doc rules honored: Tasks 3–4 forbid a directory tree and an API method table and say "describe behaviour, not code."
- Dependency chain (T1→T2→T3→T4) and the two-commit split are sound and honest about each commit's contents.

---

**Verdict:** Both critical issues from review 1 are closed, the drift-attribution minor is folded into Task 2, and every claim in the revised plan verifies against the current code, notes 19/30, ARCHITECTURE, and ROADMAP. No blocking issues remain.

PLAN_REVIEW_PASS
