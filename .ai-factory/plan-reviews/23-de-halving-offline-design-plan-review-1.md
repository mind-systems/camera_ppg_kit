## Code Review Summary

**Files Reviewed:** plan `23-de-halving-offline-design.md` against spec note 29, note 30 (downstream stub), roadmap Phase 7.5, `rr_acceptance.dart`, `rr_interval.dart`, `frame_isolate.dart`, `camera_ppg_session.dart` barrel/pipeline, and both `.calibration/*.json` fixtures.
**Risk Level:** 🟡 Medium

### Context Gates

- **ROADMAP linkage — OK.** The plan maps cleanly to `ROADMAP.md` Phase 7.5 line "De-halving offline design" (design-only, no `lib/`/device changes), and its governing spec is note 29. Scope (test-only + notes 29/30) matches the roadmap contract.
- **ARCHITECTURE dependency rule — OK.** ARCHITECTURE.md restricts `camera`/`flutter_ppg` imports in `src/processing/` to `frame_isolate.dart` only. The harness lives under `test/`, the candidate stages are pure Dart, and Task 1 explicitly forbids Flutter/camera imports. No boundary violation. **WARN (minor):** Task 1 says "Pure Dart (`dart:io` + `dart:convert`)"; under `flutter test` these run on the VM and relative paths resolve from the package root, so `test/dehalving/fixtures/*.json` works — but state that the loader resolves paths relative to the package root (not `Platform.script`), so it doesn't silently break when invoked from a subdir.
- **Spec-note path — OK.** This repo uses `.ai-factory/notes/` (roadmap lines reference `notes/29`, `notes/30`), not the global `specs/` default. The plan's paths are correct for this project.
- **Note 30 overwrite — OK, but call it out.** Task 9 authors `notes/30`, which is currently a *precondition-gated placeholder* for the downstream "Adaptive de-halving stage" milestone. Note 29 explicitly sanctions this ("write its exact implementation shape into note 30"), so it is in scope — but the plan should note it is *replacing/refining* the existing conditional stub with the chosen single approach, not creating a fresh file.

### Critical Issues

**1. The derived-BPM scoring metric is invalid, and the baseline-reproduction assertion won't hold as specified (Tasks 2, 3, 7).**

The plan defines derived BPM primarily as *"accepted-beat count over the fixture window"* (Task 2a), with *"60000 / median accepted RR"* as a cross-check, and Task 3 asserts the harness reproduces `summary.kitBpm` (131).

Measured against the actual fixtures, both formulas are wrong:

- `intervals[]` is **not** a one-row-per-beat series. Fixture 1 has **868 rows over ~60 s spanning only 317 unique `tMs`** (~14.5 rows/s) — it is `flutter_ppg`'s churning rolling-RR emission stream captured through `diffNewIntervals`, not physical beats. "Accepted-beat count over the window" therefore yields **629 accepted / 60 s = ~629 "BPM"** — an order of magnitude off, nonsense as a rate. Manual reference is ~70 BPM.
- The fixture's own `kitBpm` is `round(60000 / meanAcceptedRrMs)`: `60000 / 459.44 = 130.6 → 131` (fixture 1), `60000 / 533.71 = 112.4 → 112` (fixture 2). It is **mean-based**, not median-based. The plan's cross-check formula uses the **median**, which gives `60000 / 417 = 144` for fixture 1 (median accepted RR = 417 ms) — so the specified cross-check does **not** reproduce 131. (It happens to reproduce fixture 2's 112 by coincidence of that file's median, masking the bug if only one fixture is checked.)

Consequences:
- Task 2's *primary* metric (count/window) must be dropped — it cannot express a heart rate for this stream shape.
- Task 3's proof "derived kit BPM matches `summary.kitBpm` (131)" is only satisfiable via `60000 / mean(accepted RR)`. As written (median), it fails on fixture 1.
- Task 7's comparison table would print a meaningless BPM column for the baseline row.

**Fix:** derive BPM from the central tendency of accepted RR *magnitudes* — `60000 / mean(accepted RR)` to reproduce `kitBpm` (and optionally a robust central value for candidate scoring), and delete the "accepted-beat count over the window" definition entirely. After de-halving, the merged RR magnitudes move from ~430 ms to ~860 ms, so `60000 / mean` lands near the ~70 BPM reference — the magnitude method is the only one that works both for the baseline and for candidates. Task 2/3/7 should all be reworded around it, and the harness should assert the mean-based baseline reproduces **both** files (131 and 112), not just one.

### Suggestions (non-blocking)

**2. Task 4's merge stage cannot literally mirror `RrAcceptance`'s `evaluate` signature — pin the real output contract.**

`RrAcceptance.evaluate(RrInterval) → RrInterval` is a 1:1 keep/flag transform. A harmonic-**pair merge** is inherently 2:1: it must buffer a pending short interval and, when the next short interval arrives and the pair sums to ≈ the tracked period, emit **one** merged beat (or, if the pair doesn't complete, flush the held beat). That cannot be expressed by a 1:1 `RrInterval evaluate(RrInterval)` returning exactly one interval per input.

The plan says "shape it like `RrAcceptance`" (latitude is fine for the harness), but note 30's downstream expectation — *"drop into `lib/src/processing/` unchanged"* and *"mirror `RrAcceptance`'s `evaluate`/`reset` shape"* — is optimistic. Task 4/Task 9 should explicitly define the merge stage's output contract (e.g. `RrInterval? evaluate(...)` returning `null` while a beat is held pending and the merged interval when a pair closes, plus a `flush()`/terminal behavior), and Task 9's note-30 writeup should record that exact signature rather than implying byte-for-byte parity with the gate. Otherwise the next milestone inherits an API mismatch it must discover on its own.

**3. Loader must synthesize a `timestamp` for `RrInterval` (Task 1/3).**

`RrAcceptance.evaluate` consumes `RrInterval`, whose `timestamp` is a required `DateTime`. The fixtures carry only `tMs` (a session-relative offset). The gate logic never reads `timestamp` (only `intervalMs`), so any constructed `DateTime` works — but the loader must build one (e.g. `epoch + tMs`); the plan doesn't mention it. Trivial, but worth stating so Task 3's replay compiles.

**4. Window/reference mismatch is acceptable but should be stated.** `durationMs` is 60003 while `manualCount.windowSeconds` is 59; `referenceBpm = beats/windowSeconds*60` (Task 1) is the right basis for scoring. Just ensure the harness never mixes the 60 s file duration with the 59 s manual window when computing error.

### Positive Notes

- **File paths and line references are accurate.** `frame_isolate.dart:231` is exactly `FlutterPPGService(config: const PPGConfig())` (Task 5), and the "before `RrAcceptance` in `_onSignal`" placement (Task 9) matches `camera_ppg_session.dart` (`_onSignal` → `diffNewIntervals` → `_acceptance.evaluate`). `RrAcceptance` is genuinely reachable — it is exported from the barrel (`show RrAcceptance`) and is pure Dart, so Task 3's import works.
- **Honest scoping of what is measurable offline.** The plan correctly treats candidate 2 as part-measured/part-feasibility (no waveform, real lever inside `flutter_ppg.PeakDetector.minDistance`), candidate 3 as feasibility-only, and flags the 15–190 BPM high end as device-only (note 31). This matches note 29's constraints and avoids faking a waveform.
- **Baseline-first discipline is right.** Task 3 gating candidate trust on faithful reproduction of the recorded `isArtifact` flags (868/868, 645/645) is the correct methodology — the fixture is only a valid oracle if the committed gate reproduces it. (Just fix the BPM-derivation half of that proof per issue 1.)
- **No hardcoded-threshold trap.** The plan consistently enforces rate-proportional adaptation and rejects a constant ms/BPM floor, honoring the roadmap's central constraint.
- **Self-contained fixtures.** Copying `.calibration/*.json` into `test/dehalving/fixtures/` (rather than reading the git-ignored `.calibration/` at runtime) keeps the harness committable and reproducible.

---

Fix issue 1 (invalid BPM metric + mean-vs-median reproduction) before implementation — it is the scoring core and the baseline proof. Issues 2–4 should be folded into the task text but are not blockers.
