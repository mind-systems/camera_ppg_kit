# Plan Review: 03 — Data value types

**Plan:** `.ai-factory/plans/03-data-value-types.md`
**Files Reviewed:** plan + spec note 05, `neiry_kit/lib/src/models/rr_interval.dart`, current barrel `lib/camera_ppg_kit.dart`, `.ai-factory/{ARCHITECTURE,ROADMAP,rules}`, `lib/`+`test/` tree, `pubspec.yaml`
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (WARN):** `.ai-factory/ARCHITECTURE.md` lines 89–108 still show the outdated `RrInterval(milliseconds:…, quality:…)` shape and `rr.milliseconds`. The plan (note in "Notes for the implementer") correctly declares this snippet outdated and defers to the spec note + neiry's real type. The plan does not fix the snippet — acceptable for this atomic value-types task, but the illustrative code in ARCHITECTURE.md will now contradict the real API and mislead later phases (API/processing). Recommend a follow-up to correct the ARCHITECTURE snippet (out of scope here). Non-blocking.
- **Rules (PASS):** Matches `.ai-factory/rules`. File names `rr_interval.dart` / `signal_quality.dart` are snake_case; `RrInterval`/`SignalQuality` PascalCase; threshold constants `_goodSnrThreshold`/`_fairSnrThreshold` are lowerCamelCase (rule: Dart consts are lowerCamelCase, **not** SCREAMING_CASE) — the plan's naming is compliant. Barrel-only public surface respected (Task 3 exports from `src/`, exports nothing from `channel`/`processing`/`util`). No `mind_mobile` import, no proto — compliant.
- **Roadmap (PASS):** Directly implements the open milestone "Data value types" (ROADMAP line 24), verbatim field shape, no BPM/HRV, barrel export, `fromSnr` unit tests. Full linkage.

## Critical Issues

None.

## Observations (non-blocking)

1. **Field shape verified correct.** Cross-checked against `neiry_kit/lib/src/models/rr_interval.dart`: `const` ctor, `required int intervalMs`, `required DateTime timestamp`, `bool isArtifact = false`, `@immutable`. The plan's field names and defaults match exactly. The explicit "do not rename to `rrMs`/`milliseconds`/`durationMs`" guard is the load-bearing constraint and is stated clearly.

2. **`@immutable` import.** Neiry's class imports `package:flutter/foundation.dart` for `@immutable`. "Port verbatim in spirit" implies carrying that import; worth the implementer keeping it explicit since the current barrel does not import foundation. Minor — flutter SDK is already a dependency.

3. **Enhanced-enum syntax.** Task 2 attaches a `static fromSnr` to `enum SignalQuality`. This requires Dart enhanced-enum form (`enum SignalQuality { good, fair, poor; static SignalQuality fromSnr(double snr) {…} }`), available on the pinned `sdk: ^3.11.0`. No issue, just noting the exact form.

4. **`SignalQuality` drops the raw SNR value.** Spec note 05 line 9 phrases the type as wrapping "SQI + SNR"; the plan implements a plain enum + `fromSnr` factory, discarding the numeric SNR. Note 05 line 35 explicitly offers "a wrapper **or** factory", so this is within spec, and simpler. Flag only so it is a conscious decision: later session/processing phases that want to gate on the numeric SNR (not just the band) will need SNR from another channel, not from `SignalQuality`. Acceptable for an atomic value-type task.

5. **Degenerate-SNR handling is naturally satisfied.** With `>=` inclusive thresholds and positive provisional cutoffs, `NaN` (all comparisons false) and negative SNR both fall through to `poor` without special-casing. The plan still asks for explicit assertions in Task 4 — good, since it pins the contract against a future refactor that might reorder the comparisons.

6. **New test file coexists cleanly.** `test/models_test.dart` is new and does not collide with the existing `camera_ppg_kit_test.dart` / `camera_ppg_kit_method_channel_test.dart`. Importing via the public barrel is the right call.

## Positive Notes

- Correctly identifies and neutralizes the single biggest trap (the stale ARCHITECTURE snippet) by pointing the implementer at the spec note + neiry's actual class.
- Threshold boundary inclusivity is required to be documented in Task 2 and asserted in Task 4 — tests and implementation are pinned to the same contract, no ambiguity.
- Task dependencies (3 and 4 depend on 1+2) and phase split are correct and minimal.
- Provisional thresholds as named constants in one place, tied to calibration note 02 — clean tunability boundary.

PLAN_REVIEW_PASS
