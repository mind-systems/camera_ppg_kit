# Plan: De-halving offline design

## Context
Build a plain-Dart offline harness (under `test/`, no kit `lib/` or device changes) that replays the two `.calibration/*.json` fixtures through candidate adaptive de-halving algorithms, scores derived BPM against each file's `manualCount`, picks one approach, and records the decision (including whether `rr_acceptance.dart` still needs median anchoring) as note 30.

## Settings
- Testing: no
- Logging: minimal
- Docs: no

## Constraints (from spec note 29 + roadmap Phase 7.5)
- **Design-only.** No kit `lib/` changes, no device code. Everything lives under `test/`; the only file writes outside `test/` are the design notes (30, and the results appended to 29).
- **No constant ms/BPM threshold as the de-halving mechanism.** The whole point is rate-proportional adaptation across the full 15–190 BPM range. A fixed min-distance is itself a max-HR cap and is rejected.
- **Fixtures are RR-only** (`intervals[]` carry `{tMs, rrMs, isArtifact, sqi}`; there is no raw waveform and no re-runnable `flutter_ppg` peak detector offline). This bounds what each candidate can be *scored* vs merely *assessed for feasibility* — reflect that honestly in the harness, do not fake a waveform.
- Both fixtures are resting-rate only (~68–70 BPM). The high end of the range is **unvalidated offline** — the decision note must flag it as device-only (note 31).

## Reference facts (measured, from note 29 + fixture headers)
- `calib_20260703_161520.json`: `manualCount` 69 beats / 59 s ≈ 70 BPM; `summary.kitBpm` **131**; **868** intervals (629 accepted, 239 artifact); mean accepted RR **459.44 ms**.
- `calib_20260703_163042.json`: `manualCount` 67 beats / 59 s ≈ 68 BPM; `summary.kitBpm` **112**; **645** intervals (431 accepted, 214 artifact); mean accepted RR **533.71 ms**.
- **`kitBpm = round(60000 / meanAcceptedRrMs)`** — mean-based, not median-based (`60000/459.44 → 131`; `60000/533.71 → 112`). This is the only BPM derivation that reproduces both files; see Task 2.
- **`intervals[]` is NOT one-row-per-beat.** It is `flutter_ppg`'s churning rolling-RR emission stream captured via `diffNewIntervals` — fixture 1 has 868 rows over ~60 s across only ~317 unique `tMs` (~14.5 rows/s). Any "beat count over the window" is therefore meaningless as a rate (629 accepted / 60 s ≈ 629 "BPM") and must not be used.
- Bimodal RR: a true cluster ~800–1000 ms and a halved cluster ~330–500 ms.
- The existing gate `lib/src/processing/rr_acceptance.dart` (minRrMs 300, consistencyThreshold 0.40, coldStartBeats 3, medianWindow 5) **inverts** — its free-floating median migrates onto the halved cluster and then rejects true beats.
- Window basis for scoring: use `manualCount.windowSeconds` (59 s) with `manualCount.beats` for `referenceBpm`; never mix in the file's `durationMs` (60003). Rate error is computed from RR magnitudes (below), not from either window, so the window only feeds `referenceBpm`.

## Tasks

### Phase 1: Harness foundation

- [x] **Task 1: Fixture loader + typed model**
  Files: `test/dehalving/fixture.dart`, `test/dehalving/fixtures/calib_20260703_161520.json`, `test/dehalving/fixtures/calib_20260703_163042.json`
  Copy both `.calibration/*.json` files into `test/dehalving/fixtures/` so the harness is self-contained and committable (do not read from the git-ignored `.calibration/` at runtime). Add a `CalibrationFixture` value type parsing the JSON shape: header (`schemaVersion`, `durationMs`, `acceptance{minRrMs,consistencyThreshold,coldStartBeats,medianWindow}`, `policy`, `manualCount{beats,windowSeconds}`, `summary{totalIntervals,acceptedIntervals,artifactIntervals,meanAcceptedRrMs,kitBpm}`) plus `intervals: List<FixtureBeat{tMs,rrMs,isArtifact,sqi}>`. Expose `referenceBpm => manualCount.beats / manualCount.windowSeconds * 60` and a `loadAll()` returning both fixtures.
  - Resolve the fixture path **relative to the package root** (e.g. via `Directory.current`, which under `flutter test` is the package root), not `Platform.script`, so the loader doesn't break when invoked from a subdir.
  - Provide a `List<RrInterval> toRrIntervals()` that maps each `FixtureBeat` to a kit `RrInterval` (`intervalMs: rrMs`, `isArtifact: isArtifact`, and a **synthesized** `timestamp` — `DateTime.fromMillisecondsSinceEpoch(tMs)`, since the gate reads only `intervalMs` but `RrInterval.timestamp` is a required `DateTime`). This is what Task 3 replays through `RrAcceptance`.
  - Pure Dart (`dart:io` + `dart:convert`) plus the kit's `RrInterval` (pure value type), no Flutter/camera imports.

- [x] **Task 2: Scoring module** (depends on Task 1)
  Files: `test/dehalving/scoring.dart`
  Given an ordered series of **accepted (kept/merged) RR magnitudes** produced by a candidate, plus the fixture, compute the scoring metrics from note 29:
  - (a) **derived BPM = `round(60000 / mean(accepted RR magnitudes))`** — the mean-of-magnitudes method. This is the *only* derivation that both reproduces the fixtures' `kitBpm` on the raw stream and lands near the ~70 BPM reference after de-halving (merged magnitudes move ~430 ms → ~860 ms). **Do not** use "accepted-beat count over the window" — for this rolling-RR stream shape it is meaningless as a rate (see Reference facts). Optionally also report a robust central value (median magnitude) as a secondary diagnostic only, never as the headline BPM.
  - (b) **BPM error** = derived BPM − `referenceBpm` (target ≈ ±3).
  - (c) **true-cluster retention** and (d) **halved-cluster removal** fractions — classify each original beat as true vs halved by proximity to the fixture's fundamental period, derived from that fixture's own `referenceBpm` (~857–881 ms), with the halved band around ~0.5× it. Derive the bands per-fixture; do NOT hardcode ms constants.
  - (e) a **transitional-run** probe reporting whether the tracked fundamental stayed on the true cluster through the known median-flip stretch (fixture 1: 917→708→583→500→458 near ~5.7 s).
  Return a `CandidateScore` record. Candidate-agnostic — consumes only the ordered accepted-magnitude series + per-beat keep/drop/merge decisions.

- [x] **Task 3: Baseline reproduction** (depends on Tasks 1, 2)
  Files: `test/dehalving/baseline.dart`
  Replay the raw intervals (via Task 1's `toRrIntervals()`) through the committed `RrAcceptance` (imported from the barrel `package:camera_ppg_kit/camera_ppg_kit.dart`, which `show`s `RrAcceptance` — it is pure Dart) using each fixture's own `acceptance` params, and confirm the harness reproduces the recorded behavior on **both** fixtures:
  - `isArtifact` flags match: **868/868** (fixture 1) and **645/645** (fixture 2).
  - Derived kit BPM matches `summary.kitBpm` via the mean-of-magnitudes method from Task 2a: **131** (fixture 1) and **112** (fixture 2). (The old median cross-check is dropped — it gives 144 on fixture 1 and does not reproduce `kitBpm`.)
  Reproducing both files is what makes the fixtures a valid oracle before any candidate is judged. No kit changes; read-only use of the existing gate.

### Phase 2: Candidate algorithms

- [x] **Task 4: Candidate 1 — RR-domain harmonic-pair merge** (depends on Task 2)
  Files: `test/dehalving/candidates/harmonic_merge.dart`
  Implement the primary candidate as a pure, stateful stage over the RR stream. Track the dominant beat period **adaptively** — a slow-tracking template/EMA of the accepted fundamental period (and/or rolling autocorrelation of the recent RR series). When two consecutive short intervals sum to ≈ the tracked period within a **proportional** tolerance, merge them into one beat; rejection/merge scales with the tracked rate, no fixed floor. Handle cold start (the tracker must converge before the ~5 s warm-up ends — one of note 29's open questions; expose the convergence behavior so Task 7 can report it). Parameterize the tolerance and tracker time-constant so the eval can sweep them.
  - **Output contract (pin it explicitly — a pair-merge is 2:1, not 1:1, so it cannot mirror `RrAcceptance.evaluate`'s `RrInterval evaluate(RrInterval)` signature).** Define the stage as buffering: e.g. `RrInterval? evaluate(RrInterval)` returning `null` while a short interval is held pending, and the merged interval when the pair closes (or the held beat when the next interval proves it standalone), plus a `flush()` for terminal state and a `reset()`. Emit an explicit per-beat decision (held / emitted-as-is / emitted-merged / dropped) so Task 2's scoring can consume it. Record this exact signature so Task 9 writes it into note 30 rather than implying byte-for-byte parity with the gate.

- [x] **Task 5: Candidate 2 — rate-derived min-distance (offline approximation + feasibility)** (depends on Task 2)
  Files: `test/dehalving/candidates/rate_min_distance.dart`
  Model approach 2: a `minRRMs` derived from the *current tracked BPM* (e.g. 0.5× the tracked beat period) instead of `flutter_ppg`'s constant `PPGConfig.minRRMs=300`. Since the fixtures carry no waveform and the real lever lives inside `flutter_ppg`'s `PeakDetector.minDistance`, implement the **best available offline approximation** on the RR stream (reject/merge beats shorter than the rate-derived floor) AND read `lib/src/processing/frame_isolate.dart` (~line 231, the `FlutterPPGService` owner) to record findings on note 29's two open questions: can `FlutterPPGService` be reconfigured mid-stream, or does it need teardown/respawn per config change, and is that acceptable on the frame isolate. Score the offline approximation with the Task-2 module but clearly label in the code/output that at-source peak suppression cannot be fully validated offline — this candidate is part-measured, part-feasibility.

- [x] **Task 6: Candidate 3 — waveform-domain feasibility assessment** (depends on Task 1)
  Files: `test/dehalving/candidates/waveform_feasibility.md`
  Feasibility only (no runnable code). Document that waveform-domain fundamental estimation (autocorrelation/FFT of the filtered PPG) requires the raw/filtered waveform, which `flutter_ppg` consumes internally and does not expose, and which the fixtures do not carry — so it is unreachable offline and would need a `flutter_ppg` fork to ship. State the verdict (out of scope for this kit unless forked) with the evidence, so the decision in Task 9 can dismiss it on record rather than silently.

### Phase 3: Evaluate & decide

- [x] **Task 7: Evaluation runner** (depends on Tasks 3, 4, 5)
  Files: `test/dehalving/dehalving_eval_test.dart`
  A runnable entry (`flutter test test/dehalving/dehalving_eval_test.dart`) that loads both fixtures, runs candidate 1 and candidate 2's offline approximation through the scoring module, and prints a comparison table per fixture: derived BPM, BPM error vs `manualCount`, true-cluster retention, halved-cluster removal, transitional-run behavior, and cold-start convergence time. Include the Task-3 baseline row for contrast. Keep assertions soft (this is an evaluation harness, not a regression gate) — its job is to emit evidence, though it may assert candidate 1 lands within counting error on both fixtures as a sanity check.

- [x] **Task 8: Gate-interaction experiment** (depends on Task 7)
  Files: `test/dehalving/dehalving_eval_test.dart`
  Add an experiment that runs the winning candidate **upstream** of the committed `RrAcceptance` (de-halving first, then the existing gate on the de-halved stream) and measures whether the rolling median still migrates onto a halved cluster. Report the answer to note 29's gating question: does `rr_acceptance.dart` still need median anchoring once de-halving runs upstream, or does de-halving alone make the gate behave. This result determines whether note 30 is one entry or spawns a second.

- [x] **Task 9: Decision writeup — author note 30 + results into note 29** (depends on Tasks 6, 8)
  Files: `.ai-factory/notes/30-adaptive-dehalving-impl.md`, `.ai-factory/notes/29-dehalving-offline-design.md`
  Pick one approach based on the Task-7/8 evidence and write note 30 as the **exact implementation shape** for the next milestone. Note 30 currently exists as a precondition-gated placeholder for the downstream "Adaptive de-halving stage" milestone — this task **refines/replaces that conditional stub** with the chosen single approach (sanctioned by note 29: "write its exact implementation shape into note 30"), not a fresh file.
  Record:
  - the chosen stage's location (e.g. `lib/src/processing/rr_dehalving.dart` placed **before** `RrAcceptance` in `CameraPpgSession._onSignal` → `diffNewIntervals` → `_acceptance.evaluate`);
  - its **exact output contract from Task 4** — the buffering `RrInterval? evaluate(...)` + `flush()` + `reset()` signature (a 2:1 pair-merge, NOT the gate's 1:1 `evaluate`), so the next milestone does not inherit an undiscovered API mismatch;
  - tracker params/defaults;
  - the median-anchoring decision from Task 8 — whether note 30 is one entry or spawns a companion fix for `rr_acceptance.dart`.
  Explicitly flag that the high end of the 15–190 BPM range is unvalidated offline and must be confirmed on device (note 31). Append the scored evidence table (Task 7) and the gate-interaction result (Task 8) to a "Results" section of note 29 so the decision is backed by recorded numbers, not assertion.

## Commit Plan
- **Commit 1** (after tasks 1-3): "Add offline de-halving harness foundation and baseline reproduction"
- **Commit 2** (after tasks 4-6): "Add de-halving candidate algorithms and feasibility assessment"
- **Commit 3** (after tasks 7-8): "Add de-halving evaluation runner and gate-interaction experiment"
- **Commit 4** (after task 9): "Record de-halving decision and evidence in notes 29 and 30"
