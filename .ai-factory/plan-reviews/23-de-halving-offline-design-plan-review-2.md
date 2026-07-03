## Code Review Summary

**Files Reviewed:** plan `23-de-halving-offline-design.md` (round 2) against plan-review-1, spec note 29, note 30 (downstream stub), `ROADMAP.md` Phase 7.5, `ARCHITECTURE.md`, `lib/src/processing/rr_acceptance.dart`, `lib/src/models/rr_interval.dart`, `lib/camera_ppg_kit.dart` (barrel), `lib/src/api/camera_ppg_session.dart` (pipeline), `lib/src/processing/frame_isolate.dart`, and both `.calibration/*.json` fixtures (parsed and measured).
**Risk Level:** 🟢 Low

### Context Gates

- **ROADMAP linkage — OK.** Plan maps exactly to `ROADMAP.md:63` Phase 7.5 "De-halving offline design" (design-only, no `lib/`/device changes; evaluate the three named candidates; decide the `rr_acceptance.dart` median-anchoring question). Governing spec is note 29; downstream is note 30 (line 64). Scope (test-only + notes 29/30) matches the contract line.
- **ARCHITECTURE dependency rule — OK.** `ARCHITECTURE.md:43` restricts `camera`/`flutter_ppg` imports in `src/processing/` to `frame_isolate.dart` only. The harness lives under `test/`, candidate stages are pure Dart, and Task 1 forbids Flutter/camera imports. `RrInterval` and `RrAcceptance` are both barrel-exported (`camera_ppg_kit.dart:6,17` — the note-19 `[debug]`-tagged exception), so Task 1/Task 3 imports resolve through the public barrel. No boundary violation.
- **Spec-note path — OK.** Repo uses `.ai-factory/notes/`; the plan's `notes/29`, `notes/30` paths and the fixture copies under `test/dehalving/fixtures/` are correct.
- **Note 30 overwrite — OK, and now called out.** Task 9 explicitly frames itself as refining/replacing the existing precondition-gated stub (sanctioned by note 29), addressing review-1's context note.
- **Skill-context — N/A.** No `.ai-factory/skill-context/aif-review/SKILL.md` present; no project override rules to apply.

### Review-1 Issues — all resolved

- **Issue 1 (invalid BPM metric).** Fully fixed. The "accepted-beat count over the window" definition is deleted and explicitly rejected in Reference facts and Task 2a; derived BPM is now `round(60000 / mean(accepted RR magnitudes))`, with median demoted to a secondary diagnostic. Verified against both files: `60000/459.44 → 131` (fixture 1) and `60000/533.71 → 112` (fixture 2) reproduce `summary.kitBpm` exactly. Task 3 now asserts both files (868/868 and 645/645; 131 and 112) and drops the median cross-check.
- **Issue 2 (2:1 merge cannot mirror `evaluate`).** Fixed. Task 4 pins the buffering contract explicitly (`RrInterval? evaluate(RrInterval)` returning `null` while held, merged interval on pair-close, plus `flush()`/`reset()` and a per-beat decision enum), and Task 9 records that exact signature into note 30 rather than implying 1:1 parity with the gate.
- **Issue 3 (synthesized timestamp).** Fixed. Task 1 now specifies `toRrIntervals()` synthesizing `DateTime.fromMillisecondsSinceEpoch(tMs)` because `RrInterval.timestamp` is a required `DateTime` the gate never reads.
- **Issue 4 (window/reference).** Fixed. Constraints now pin `manualCount.windowSeconds` (59 s) for `referenceBpm` and forbid mixing in `durationMs` (60003).

### Independent verification (this round)

All asserted codebase facts check out against source and the parsed fixtures:

- `RrAcceptance` params (`minRrMs 300`, `consistencyThreshold 0.40`, `coldStartBeats 3`, `medianWindow 5`) match `rr_acceptance.dart:18-23` **and** both fixtures' `acceptance` blocks.
- Pipeline `_onSignal → diffNewIntervals → _acceptance.evaluate` confirmed at `camera_ppg_session.dart:512,528,575`; `reset()` at `:431`. Task 9's "before `RrAcceptance`" placement is accurate.
- `frame_isolate.dart:231` is exactly `FlutterPPGService(config: const PPGConfig())` (Task 5's ~line 231).
- Fixture headers reproduce the plan's Reference facts precisely: fixture 1 = 868 intervals / 629 accepted / 239 artifact / mean 459.44 / kitBpm 131 / median accepted 417 / 317 unique `tMs` / manualCount 69·59; fixture 2 = 645 / 431 / 214 / mean 533.71 / kitBpm 112 / median accepted 458 / manualCount 67·59. `schemaVersion 1`, `durationMs 60003`, `policy` present as an object.
- **`rrMs` is an integer in both fixtures** (0 non-integer values), so Task 1's direct `intervalMs: rrMs` mapping into the `int intervalMs` field is type-safe — no truncation concern.
- `referenceBpm`: 69/59·60 = 70.2 BPM → ~855 ms; 67/59·60 = 68.1 → ~881 ms, matching Task 2c's "~857–881 ms" fundamental band (855 vs 857 is rounding, not a defect).

### Critical Issues

None.

### Suggestions (non-blocking)

- **"Pure Dart" is imprecise — the harness must run under `flutter test`, not `dart test`.** Tasks 1/3/5 describe files as "pure Dart (`dart:io` + `dart:convert`)", but `RrInterval` imports `package:flutter/foundation.dart` (for `@immutable`), so anything importing `RrInterval`/`RrAcceptance` transitively pulls in Flutter. Task 7 already invokes `flutter test test/dehalving/dehalving_eval_test.dart`, so this is consistent in practice — just don't let the "pure Dart" phrasing tempt a plain `dart test` runner, which would fail to resolve `package:flutter`. Worth one clarifying clause; not a blocker.
- **Fixture-2 baseline reproduction (645/645) is an untested assumption carried into a hard assertion.** Note 29 only records the 868/868 reproduction for fixture 1; Task 3 asserts 645/645 for fixture 2 as well. This is the correct thing to assert (it is exactly what makes fixture 2 a valid oracle), and the harness is precisely what confirms it — so if it doesn't hold, Task 3 surfaces it as evidence rather than hiding it. Flagging only so the implementer treats a fixture-2 mismatch as a real finding to record in note 29's Results, not a harness bug to paper over.

### Positive Notes

- **Every review-1 blocker is genuinely resolved in the plan text**, not just acknowledged — the invalid metric is deleted, the merge contract is pinned, and the timestamp/window details are now explicit.
- **Numbers are grounded in the actual fixtures.** The mean-vs-median distinction, the bimodal cluster bands, the transitional-run stretch (917→708→583→500→458 ~5.7 s), and the "rolling-RR churn, not one-row-per-beat" caveat all match the parsed data and note 29.
- **Honest offline/on-device boundary.** Candidate 2 is correctly scoped as part-measured/part-feasibility (real lever inside `flutter_ppg.PeakDetector.minDistance`), candidate 3 as feasibility-only (no exposed waveform), and the 15–190 BPM high end is flagged device-only (note 31). No faked waveform.
- **No hardcoded-threshold trap.** Rate-proportional adaptation is enforced throughout; constant ms/BPM floors are rejected, honoring the roadmap's central constraint.
- **Baseline-first discipline and self-contained fixtures** (copied into `test/dehalving/fixtures/`, not read from the git-ignored `.calibration/`) keep the harness a committable, reproducible oracle.

---

The two remaining notes are wording clarifications, not defects. The plan is internally consistent, correctly scoped, and every file path, API signature, parameter, and fixture number it relies on is verified against the codebase.

PLAN_REVIEW_PASS
