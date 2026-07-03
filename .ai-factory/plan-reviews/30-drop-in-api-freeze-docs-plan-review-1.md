# Plan Review — Drop-in API freeze + docs (plan 30)

## Code Review Summary

**Files Reviewed:** plan `30-drop-in-api-freeze-docs.md` + targeted code/spec: `lib/camera_ppg_kit.dart`, `lib/src/api/camera_ppg_session.dart`, `lib/src/models/measurement_state.dart`, `lib/src/models/rr_interval.dart`, `lib/src/processing/session_policy.dart`, notes 19 & 30, `README.md`, `ROADMAP.md`, `ARCHITECTURE.md`
**Risk Level:** 🟡 Medium

### Context Gates

- **Root recovery:** Plan heading `# Plan: Drop-in API freeze + docs` matches ROADMAP Phase 10 line 99 ("Drop-in API freeze + docs", `Spec: notes/19-drop-in-api-freeze.md`). Root recovered — gates applied against note 19 (and note 30, which the plan correctly pulls in as a reconciliation source).
- **ARCHITECTURE.md — OK.** Line 41 already codifies the exact `[debug]` exception the plan freezes: `SessionPolicy` + `RrAcceptance` are re-exported deliberately for the example's ctor-param tuning, "the rest of `src/processing/` … stays unexported." Plan Task 1/Task 2 align with this verbatim. No boundary conflict.
- **RULES.md — WARN (absent).** No `.ai-factory/RULES.md` and no `skill-context/aif-review/SKILL.md`; no project-specific review overrides to apply. Non-blocking.
- **ROADMAP.md — ERROR (see Critical Issue 1).** Roadmap line 56 (Phase-10 stop/idle fix) states plainly: **"no `done` state (note 23)."** The plan's Task 4 instructs documenting a `done` terminal state — a direct contradiction with the ratified roadmap history.

### Critical Issues

**1. Task 4 documents a `done` state that does not exist — consumer-facing.**
`Task 4` (line 37) tells the implementer to describe the state machine as
`warmup → measuring ⇄ poorSignal → done`. There is no `done` value.
`lib/src/models/measurement_state.dart` defines exactly four states:
`idle, warmup, measuring, poorSignal`. `SessionPolicy` never emits anything else
(`grep` for `done` across `lib/` returns zero hits), and `targetDuration` — the
only thing that could have produced a terminal state — was removed by note 23
(roadmap line 84 & line 56). The actual lifecycle is
`idle → warmup → measuring ⇄ poorSignal`, returning to **`idle`** on `stop()`.

Writing `→ done` into the README would ship a drop-in contract describing a
state a `mind_mobile` consumer's `stateStream` switch will never receive — the
precise kind of dishonest surface this milestone exists to prevent. Fix Task 4
to document `idle → warmup → measuring ⇄ poorSignal`, terminal `idle` on stop.

**2. The freeze audit (Tasks 1–2) omits the same stale `done` in the frozen file's own dartdoc.**
`camera_ppg_session.dart:103` documents `_state` as
"`warmup → measuring ⇄ poorSignal → done` per [SessionPolicy]" — the very string
Task 4 appears to have copied. The milestone's stated goal is "so the freeze is
**honest**" (Task 2). A frozen public surface whose class-level dartdoc names a
nonexistent state is not honest. Neither Task 1 (audit) nor Task 2 (label/comment)
scopes fixing this. Add it: the audit should correct the `→ done` reference in
the session's dartdoc as part of freezing the surface, so the code and the new
README agree.

### Minor Issues / Suggestions

- **Task 2's drift attribution is incomplete (non-blocking).** Task 2 says "Note 19
  predates the note-30 `RrDehalving` stage" as the reason the barrel diverged from
  the spec. True, but note 19 diverged in two more ways the audit will hit:
  (a) note 19 §"Debug-tagged extras" names the debug **input** as
  `RrAcceptanceConfig? acceptance` — the real ctor param is `RrAcceptance? acceptance`
  (type renamed); and (b) note 19 never mentions `SessionPolicy`/`policy` as an
  exported extra at all, yet the barrel exports it (and ARCHITECTURE.md line 41
  ratifies that). The plan's *action* (enumerate `policy`/`acceptance`, keep
  `RrDehalving` unexported) is correct and complete — just note that reconciliation
  must span all three deltas, not only the note-30 one, so the implementer doesn't
  "restore" the barrel to note 19's literal (wrong) text.
- **Task 1 correctly overrides note 19's stale Verify check.** Note 19 line 51 asserts
  "`src/processing` … NOT exported," which the barrel already violates by design.
  Task 1 bullet 2 explicitly carves out "the two `src/processing/` re-exports … the
  only deliberate exception" — the right call, matching ARCHITECTURE.md. Good catch
  by the plan author; flagging only so it isn't mistaken for a contradiction.

### Verified Accurate (no action needed)

- **Task 1 member enumeration is complete.** The 13 public members listed
  (`rrStream`, `qualityStream`, `stateStream`, `fingerPresenceStream`,
  `resolvedCamera`/`resolvedCameraStream`, `buildPreview()`, `useCamera()`,
  `availableCameras()`, `start()`, `stop()`, `dispose()`, `debugSignalStream`)
  exactly match `CameraPpgSession`'s public surface. `buildPreview()` does return a
  plain `Widget?` (line 193). No `camera`/`flutter_ppg`/channel type crosses any
  signature — audit premise holds.
- **File paths all correct.** `lib/camera_ppg_kit.dart`, `lib/src/api/camera_ppg_session.dart`,
  `README.md` exist as referenced. `RrDehalving` lives at
  `lib/src/processing/rr_dehalving.dart` and is genuinely unexported today.
- **Task 4 RR-contract claims verified against code:** RR-only / no BPM stream, silent
  stream on poor signal (RR emit gated on `_policy.rrTrusted`, no placeholder ticks),
  and `RrInterval.isArtifact` as the single artifact channel — all match
  `camera_ppg_session.dart:_onSignal` and `rr_interval.dart`.

### Positive Notes

- Scope discipline is exactly right: audit + docs, zero behaviour change, matching the
  note-19 "this is the freeze, not new behaviour" framing.
- Boundary statement is correct and repeated where it matters (Task 4): the
  `camera_ppg` `SensorSource` tag and the `lib/Biometrics/` adapter belong in
  `mind_mobile`, not the kit — consistent with note 19 §Boundary and the kit's
  no-`SensorSource`-field guard.
- Doc rules honored: Tasks 3–4 explicitly forbid a directory tree and an API method
  table, and say "describe behaviour, not code" — aligned with global doc style.
- The dependency chain (T1→T2→T3→T4) and two-commit split are sound and honest about
  what each commit contains.

---

**Verdict:** The plan is structurally sound and scoped correctly, but it would
propagate a nonexistent `done` state into the frozen consumer contract (Critical 1)
and leaves the same stale reference in the frozen file's dartdoc unaddressed
(Critical 2). Both must be fixed before this plan is handed to the orchestrator.
