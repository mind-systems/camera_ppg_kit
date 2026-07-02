# Code Review: RR acceptance gate (port from neiry)

**Plan:** `.ai-factory/plans/08-rr-acceptance-gate-port-from-neiry.md`
**Files changed:** `lib/src/processing/rr_acceptance.dart` (new), `lib/src/api/camera_ppg_session.dart` (modified), `test/rr_acceptance_test.dart` (new)
**Verification:** `flutter test` — 50/50 pass; `flutter analyze` on the three touched files — no issues.

## Summary

The change ports neiry's `PpgPeakDetector._gate()` into a standalone pure-Dart `RrAcceptance` class and wires it into `CameraPpgSession._onSignal`. The implementation matches the plan exactly and the semantics of the neiry source faithfully.

## Correctness review

- **Gate logic is a faithful port.** `_gate()` reproduces neiry lines 213–225: hard lower bound (`< minRrMs → true`), cold-start grace (`_rrHistory.length < coldStartBeats → false`), and the rolling-median consistency check (`(rrMs - median).abs() / median > consistencyThreshold`). No upper bound is applied — verified by the bradycardia test (4000 ms past a 3000 ms median → not artifact; deviation 0.33 < 0.40).
- **Median-poisoning guard is correct.** Only non-artifact beats are appended to `_rrHistory`, capped at `medianWindow` with oldest-eviction (`removeAt(0)`) — matching neiry lines 116–122. The spike test confirms a rejected +50% beat does not enter the median.
- **Cold-start accounting is sound.** Sub-floor beats return artifact and are never appended, so they don't consume cold-start slots — the grace period counts accepted beats, consistent with neiry.
- **`RrInterval` construction is correct.** No `copyWith` exists on the `@immutable` type, so `evaluate` builds a fresh instance preserving `intervalMs`/`timestamp` and setting `isArtifact` — as instructed.
- **Session wiring is correct.** The gate is injected mirroring the `_policy` pattern; `evaluate` is called only inside the existing `if (_policy.rrTrusted)` block, preserving the trust guard and `_rrController.isClosed` check. The gate annotates `isArtifact` but never withholds a beat, honoring the `RrInterval` contract. `_acceptance.reset()` is placed in `_release()` (the single always-invoked teardown), so cold-start re-arms before each measurement.
- **Purity / architecture respected.** `rr_acceptance.dart` imports only `../models/rr_interval.dart` — no Flutter/`camera`/`flutter_ppg`/channel imports (ARCHITECTURE.md rule 3). Not re-exported from the barrel, mirroring `session_policy.dart`.

## Design notes (non-blocking, no action required)

- **Median persists across a `measuring ⇄ poorSignal` bounce.** The gate is reset only on `_release`, not when the session dips into `poorSignal`, so the rolling median carries over. If a very long poor-signal stretch coincided with a large genuine HR change, the first trusted beats after resume could be checked against a stale median. This is the intended design per the plan/note (reset only on measurement boundaries), the 5-beat window self-heals quickly, and only shifts exceeding ±40% within one measurement would be affected. Recorded as a deliberate tradeoff, not a defect.
- The `rr_diff.dart` line-18 comment still references "artifact detection lands in the Phase-6 acceptance gate"; the equivalent comment in `camera_ppg_session.dart` was correctly updated. Cosmetic only.

## Verdict

No correctness, security, or runtime concerns. The gate is pure, isolate-safe, unit-tested across every branch, and the session integration preserves all existing invariants.

REVIEW_PASS
