# Code Review — Drop-in API freeze + docs (plan 30)

## Summary

**Files reviewed (in full):** `lib/camera_ppg_kit.dart`, `lib/src/api/camera_ppg_session.dart`, `README.md`; cross-checked against `lib/src/models/measurement_state.dart`, `lib/src/processing/rr_dehalving.dart`, plan `30-drop-in-api-freeze-docs.md`, note 19.

**Nature of change:** Documentation and comments only — the barrel's export list is unchanged (same six `src/models`/`src/api` exports plus the two deliberate `src/processing` re-exports `RrAcceptance`/`SessionPolicy`); the session change is a dartdoc string; the README change is prose. No executable code, no signatures, no types altered. There is no runtime surface to break — no migrations, no type changes, no new control flow.

## Verification of factual claims in the new docs/comments

Every assertion the new text makes was checked against the current code:

- **State machine `idle → warmup → measuring ⇄ poorSignal`, returning to `idle` on `stop()`.** Confirmed: `MeasurementState` defines exactly `idle, warmup, measuring, poorSignal` (no `done`); `_release()` — the single teardown used by both `stop()` and `dispose()` — ends with `_setState(MeasurementState.idle)` (`camera_ppg_session.dart:495`). Both the corrected dartdoc (line ~102) and the README section are accurate. The stale `→ done` string flagged by plan review 1 (Critical 2) is fully removed.
- **`RrDehalving` deliberately unexported.** Confirmed: the barrel has zero `rr_dehalving`/`RrDehalving` references; the `dehalving` ctor param is public but its type never crosses the barrel, so a barrel-only consumer cannot name it — internal-default-only, exactly as the comment states.
- **Ctor param shape `policy`/`acceptance`/`dehalving`.** Matches `CameraPpgSession(...)` (lines 51–66). The comment's note that spec 19 called the input type `RrAcceptanceConfig` while the real param is `RrAcceptance? acceptance` is correct.
- **`debugSignalStream` is a `List<double>`-only debug output.** Confirmed: getter at line 160 returns `Stream<List<double>>`; no `flutter_ppg`/`camera` type crosses it. The barrel comment's phrasing ("re-exported above via the class itself") is accurate — it rides on the exported `CameraPpgSession`, not a separate export.
- **RR-only, no HR/BPM/HRV stream; silent stream on poor signal; `RrInterval.isArtifact` the single artifact channel.** Consistent with note 19 §Contract-fit and the session's `_onSignal` gating. No placeholder/zero ticks are emitted.
- **Boundary statement** (the `camera_ppg` `SensorSource` tag and `lib/Biometrics/` adapter live in `mind_mobile`, not the kit). Correctly stated in both README and barrel comment; the kit adds no `SensorSource` field.
- **Barrel boundary intact.** `grep` premise from the plan holds: no `flutter_ppg`/`CameraImage`/`CameraController`/`MethodChannel`/`PPGSignal` type appears in the barrel or in any public `CameraPpgSession` signature; `buildPreview()` returns a plain `Widget?`.

## Findings

None. The change is limited to comments and documentation, every factual claim verifies against the code, and both critical issues from the plan-review round are resolved in the implementation.

## Notes (non-blocking, no action required)

- Plan review 2 already flagged that `README.md` line 27 ("live RR/BPM" in the *Running the example* section) still mentions BPM. That line describes the example app, not the frozen contract, and is outside this plan's Task 3/Task 4 scope. Left untouched — correct scope discipline; not a defect.

REVIEW_PASS
