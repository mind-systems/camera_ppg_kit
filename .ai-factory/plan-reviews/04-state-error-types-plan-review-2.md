# Plan Review 2: 04 — State & error types

**Plan:** `.ai-factory/plans/04-state-error-types.md`
**Files Reviewed:** plan + `lib/src/models/signal_quality.dart`, `rr_interval.dart`, `test/models_test.dart`, `lib/camera_ppg_kit.dart` (barrel), `.ai-factory/rules/base.md`, `neiry_kit/lib/src/models/neiry_error.dart`, `flutter_ppg-0.2.4` (`ppg_config.dart`, `quality_assessor.dart`, `ppg_signal.dart`), `camera` plugin error codes
**Risk Level:** 🟢 Low

## Code Review Summary

This is the second review pass. Review 1 raised one critical issue (Task 2 built on a wrong `flutter_ppg` API assumption that made `overBright` unreachable) plus two minor cleanups (vacuous `orNull` reference, wrong `fromMap` ingress shape). **All three have been fully resolved in this revision.** Every remaining claim in the plan was re-verified against the actual source and holds.

### Context Gates

- **Architecture / Rules** (`.ai-factory/rules/base.md`): ✅ Aligned. All three types land in `lib/src/models/`, exported only via the barrel (Task 4), modeled as never-thrown values (Task 3 restates the no-throw-across-channel rule), and mirror the `neiry_kit` typed-error convention. No `flutter_ppg`/`camera` type leaks to consumers.
- **Roadmap:** No kit-level `ROADMAP.md` gate (kit intentionally not wired into root orchestration per `camera_ppg_kit/CLAUDE.md`); milestone linkage is implicit via the numbered plan sequence (03 data types → 04 state/error types). No action.
- No migrations, no proto, no security surface (pure value types, no I/O, no native channel). ✅

### Resolution of Review-1 Findings

**1. (was Critical) Task 2 — `overBright` unreachable.** RESOLVED. The signature is now `FingerPresence.fromRawIntensity(double rawIntensity)` classifying from the continuous red-channel value, with **two** thresholds. Verified against `flutter_ppg-0.2.4`:
- `PPGSignal.rawIntensity` is a `double` (`ppg_signal.dart:24`) — confirmed the only intensity source; no `fingerDetected`/`brightness` fields exist.
- `SignalQualityAssessor.isFingerPresent` (`quality_assessor.dart:45-47`) is exactly `rawIntensity > fingerPresenceMin && rawIntensity < fingerPresenceMax` — the two-sided strict band the plan now mirrors.
- Defaults are `fingerPresenceMin = 30.0` / `fingerPresenceMax = 250.0` (`ppg_config.dart:64-65`) — matches the plan's provisional `_presenceMin` / `_overBrightMax`.
- The plan's boundary handling (`<= _presenceMin → absent`, `>= _overBrightMax → overBright`, strictly-between → `present`) correctly reproduces flutter_ppg's exclusive band, so exactly-min → absent and exactly-max → overBright are consistent.
- NaN guard (check `.isNaN` first → `absent`) is explicit and matches the `SignalQuality.fromSnr` precedent.
- Task 5 was updated to assert around **both** thresholds plus NaN — the under-test gap is closed.

**2. (was Minor) Vacuous `orNull` reference.** RESOLVED. Task 3 now explicitly states "Do NOT add an `orNull`/numeric-sentinel path — this type carries no numeric field."

**3. (was Minor) Wrong `fromMap` ingress shape.** RESOLVED. Task 3 now specifies `CameraPpgError.fromCameraErrorCode(String code, {String? description})` and explains why (`camera` surfaces `CameraException(String code, ...)`, no channel/map exists). Verified `CameraAccessDenied` is a real camera-plugin code; `CameraAccessDeniedWithoutPrompt`/restricted mapping to `permanentlyDenied: true` is a reasonable, correctly-deferred mapping. `NeiryError` (class + `NeiryErrorCode` enum) confirmed as the mirrored pattern.

### Critical Issues

None.

### Minor Issues / Considerations (non-blocking)

- **Private thresholds vs. test references.** Task 5 says to assert "at exactly `_presenceMin`" / "exactly `_overBrightMax`", but those `const`s are file-private and the test imports only the barrel. The implementer must use the literal values (`30.0` / `250.0`) in tests, exactly as `models_test.dart` already does for `SignalQuality` (`5.0` / `0.0`). No plan change needed — just flagging so the wording isn't read as "import the private constant."
- **Static-method vs. factory phrasing.** The plan calls `fromRawIntensity` "the factory." The established pattern in `signal_quality.dart` is a `static` method on the enum (`static SignalQuality fromSnr(...)`), not a `factory` constructor. The implementer should mirror `fromSnr` (static method) for `FingerPresence`; for `CameraPpgError` (a class) named factory constructors are correct as written. Purely a phrasing nuance — no defect.

### Positive Notes

- Review-1 feedback was incorporated precisely and completely, not just superficially — the corrected Task 2 logic matches the real `flutter_ppg` band down to the boundary semantics.
- Strong reuse discipline: mirrors `signal_quality.dart`'s documented-provisional-threshold pattern, `neiry_kit`'s typed error convention, and the barrel-only export rule.
- Test task correctly extends the existing `test/models_test.dart` and matches its arrange/expect style; the `MeasurementState` cardinality test is a good defensive touch.
- Barrel export paths in Task 4 are exact against the current `lib/camera_ppg_kit.dart`.
- Errors modeled as values with an explicit no-throw-across-channel guard, consistent with `base.md`.

**Verdict:** All review-1 issues are resolved and every remaining assumption re-verified against source. The two minor notes are implementation-time reminders, not plan defects.

PLAN_REVIEW_PASS
