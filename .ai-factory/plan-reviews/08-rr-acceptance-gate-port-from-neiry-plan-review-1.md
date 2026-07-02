# Plan Review: RR acceptance gate (port from neiry)

**Plan:** `.ai-factory/plans/08-rr-acceptance-gate-port-from-neiry.md`
**Files Reviewed:** 6 (plan + `ppg_peak_detector.dart`, `rr_interval.dart`, `camera_ppg_session.dart`, `session_policy.dart`, `rr_diff.dart`, `session_policy_test.dart`, `ARCHITECTURE.md`, barrel)
**Risk Level:** 🟢 Low

## Context Gates

- **Architecture (`.ai-factory/ARCHITECTURE.md`):** PASS. The plan honors Dependency Rule 3 (`src/processing/` → `src/models/` only): `RrAcceptance` imports only `../models/rr_interval.dart`, no `flutter_ppg`/`camera`/channel. It correctly keeps the class out of the barrel (mirroring `session_policy.dart`, which is indeed not re-exported by `lib/camera_ppg_kit.dart`). Placement in `src/processing/` matches Key Principle 4 (pure, isolate-friendly, unit-testable). No boundary violations.
- **Rules:** No `.ai-factory/RULES.md` present — WARN (optional file absent, non-blocking).
- **Roadmap:** No `.ai-factory/ROADMAP.md` at kit root (CLAUDE.md confirms this kit is "not yet wired into the root `.ai-factory/` orchestration") — WARN, no milestone linkage expected.

## Verification against the codebase

Every concrete claim in the plan checks out against the actual source:

- **neiry line references are exact.** `_gate()` is lines 213–225; the history-append/evict is lines 116–122 (`add` then `if (length > medianWindow) removeAt(0)`). Field names/defaults (`minRrMs=300`, `consistencyThreshold=0.40`, `coldStartBeats=3`, `medianWindow=5`) match `PpgPeakDetector` exactly. The instruction to drop `refractoryMs`/`bufferDurationMs`/`_buffer`/`_lastPeakTs`/`_lastPpiMs`/`_currentRefractory`/`_findPeaks`/`processBatch` and keep only `_rrHistory` is correct — those are peak-detection state `flutter_ppg` owns here.
- **`RrInterval` API is correct.** The type has `intervalMs`/`timestamp`/`isArtifact`, a `const` ctor, `@immutable`, and no `copyWith` — so the plan's "construct a new one" instruction is right and necessary. (Note the naming split: neiry's type is `RRInterval`, this kit's is `RrInterval` — the plan uses `RrInterval` throughout, which is correct for this repo.)
- **Session wiring targets are accurate.** The constructor's `SessionPolicy? policy` pattern (line 47/54) is a valid template for `RrAcceptance? acceptance`. The `_onSignal` emit block is at lines 494–508; the stale comment "lands in the Phase-6 acceptance gate (note 12)" is at lines 466–468. `_release()` (line 387) is the single teardown and already contains `_stopwatch.stop()` (line 401), so adding `_acceptance.reset()` there is well-placed.
- **The gate-vs-trust separation is sound.** Feeding `_acceptance.evaluate()` only inside the existing `if (_policy.rrTrusted)` block means the gate sees only trusted (measuring-state) beats. That is consistent with the design: warmup/poorSignal beats are diffed and quietly discarded by the unconditional bookkeeping, never reaching the gate, so cold-start seeds from the first genuinely-trusted beats. The gate correctly is *not* reset across a `measuring ⇄ poorSignal` bounce within one measurement (reset only on `_release`), which is the right behavior.
- **Test plan mirrors `session_policy_test.dart`** (synthetic sequences, fixed values, assert on returned state) and the chosen cases exercise every branch of `_gate`: lower-bound (250 → artifact), no-upper-bound bradycardia (4000 off a 3000 median → deviation 0.33 < 0.40 → accepted), spike rejection + non-poisoning (+50% → 0.50 > 0.40 → artifact, history unchanged), and cold-start re-arm after `reset()`.

## Critical Issues

None. No missing steps, no wrong codebase assumptions, no incorrect file paths or API usage, no migrations involved, no security surface (pure local numeric processing).

## Minor Notes (non-blocking — author's discretion)

1. **Second stale comment left unaddressed.** `lib/src/api/rr_diff.dart` line 18 also states *"Real dedup + artifact detection lands in the Phase-6 acceptance gate (note 12)"*. The plan only updates the equivalent comment in `camera_ppg_session.dart`. After this milestone the *artifact-detection* half of that sentence becomes stale (dedup still legitimately does not live in the gate). Consider trimming it to reference only dedup, or noting the gate now exists. Purely cosmetic.

2. **`reset()` placement is asymmetric with `_policy`.** `_policy.reset()` is called in `start()` (line 309); the plan resets `_acceptance` in `_release()` instead. Both correctly guarantee a clean gate at the start of each measurement because `_release()` is the single always-invoked teardown, so this is fine as written. If you prefer symmetry (and robustness against a future refactor that adds a `start` path skipping `_release`), resetting alongside `_policy.reset()` in `start()` would be marginally safer. Optional.

3. **Test-case wording nit.** The cold-start case describes "three 3500 ms intervals" as "extreme HR" — 3500 ms is extreme *bradycardia* (~17 BPM), not tachycardia. The test is still valid (first 3 beats accepted unconditionally); only the label is imprecise. Also, three *identical* seed values don't stress the consistency-bypass aspect of cold-start (they wouldn't fail consistency anyway); if you want the cold-start grace to be truly load-bearing in that test, vary the three seed intervals so at least one would fail the ±40% check yet is still accepted.

## Positive Notes

- Correctly scopes the port to `_gate()` only and explicitly enumerates the peak-detection state to drop — prevents accidentally dragging `flutter_ppg`-owned responsibilities into the kit.
- Preserves the "no upper bound" invariant with a clear rationale (cold-water bradycardia), and the test proves it rather than asserting it.
- Respects the artifact-never-poisons-the-median rule by appending only non-artifact beats — faithfully carried over from neiry.
- Keeps the RR-emit path's existing `rrTrusted` guard and `_rrController.isClosed` check untouched; the gate only annotates `isArtifact`, never withholds a beat — matching the `RrInterval` contract doc that consumers must skip artifact ticks themselves.
- Constructor injection mirrors the established `SessionPolicy` pattern, leaving the door open for the example's live-tuning without adding host config now.

PLAN_REVIEW_PASS
