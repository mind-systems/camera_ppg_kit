# Plan Review: 04 — State & error types

**Plan:** `.ai-factory/plans/04-state-error-types.md`
**Files Reviewed:** plan + `signal_quality.dart`, `rr_interval.dart`, `models_test.dart`, `camera_ppg_kit.dart` (barrel), `.ai-factory/rules/base.md`, `neiry_kit` (`neiry_error.dart`, `neiry_error_code.dart`, `sentinel.dart`), `flutter_ppg-0.2.4` (`ppg_signal.dart`, `quality_assessor.dart`)
**Risk Level:** 🟡 Medium

The plan is well-scoped and consistent with the model-layer conventions already established (`signal_quality.dart` doc/threshold style, `@immutable` value types, barrel-only exports, never-throw error rule in `base.md`). Tasks 1, 3, 4, and the test task are sound and directly implementable. **One task (Task 2) rests on an incorrect assumption about the `flutter_ppg` API that, if implemented literally, makes the `overBright` case unreachable** — the exact distinction the task says is critical. Details below.

---

### Context Gates

- **Architecture / Rules** (`.ai-factory/rules/base.md`): ✅ Aligned. Plan places all three types in `lib/src/models/`, exports only through the barrel, models errors as never-thrown values (Task 3 "nothing in this file throws across a channel"), and mirrors the `neiry_kit` sentinel convention. No boundary violations. No new `flutter`/`camera`/`flutter_ppg` imports leak to consumers.
- **Roadmap:** No `.ai-factory/ROADMAP.md` gate available at kit level (kit is intentionally not yet wired into root orchestration per `camera_ppg_kit/CLAUDE.md`); milestone linkage is implicit via the numbered plan sequence (03 data types → 04 state/error types). No action needed.
- No migrations, no proto, no security surface (pure value types, no I/O, no native channel). ✅

---

### Critical Issues

**1. Task 2 — `FingerPresence.fromSignal` signature contradicts the actual `flutter_ppg` `PPGSignal` API; the specified classification makes `overBright` unreachable.**

The plan proposes `FingerPresence.fromSignal({required bool fingerDetected, required double brightness})` with the logic:
> not detected → `absent`; **detected but brightness above an over-bright threshold → `overBright`**; otherwise `present`.

I verified `flutter_ppg-0.2.4`. `PPGSignal` (`lib/src/models/ppg_signal.dart`) exposes **neither `fingerDetected` nor `brightness`.** The only intensity field is `rawIntensity` (double, red-channel). Finger presence is *derived*, not a field — via `SignalQualityAssessor.isFingerPresent(double rawIntensity)` (`lib/src/quality_assessor.dart:45`):

```dart
bool isFingerPresent(double rawIntensity) =>
    rawIntensity > fingerPresenceMin && rawIntensity < fingerPresenceMax;
// docstring: too dark (<30) = finger removed; too bright (>250) = flash saturation/blooming
```

The key consequence: `isFingerPresent` returns `false` for **both** too-dark (absent) **and** too-bright (over-bright) — it is a two-sided band. So if the implementer wires `fingerDetected = isFingerPresent(...)` (the natural reading of "detected"), then **"detected AND over-bright" is impossible** — being over-bright already forces `fingerDetected == false`. Following the plan's stated predicate order literally yields a factory where the `overBright` branch is dead code, defeating the whole point of the type ("MUST be distinguishable from `absent`").

The plan's escape hatch — *"(or equivalent field names matching what `flutter_ppg`'s `PPGSignal` exposes)"* — doesn't rescue it, because the *shape* is wrong, not just the names: the real source is a **single continuous value with a low and a high threshold**, not a `bool` + a value. A pre-collapsed `bool` throws away exactly the information needed.

**Recommended fix (adjust the plan before implementing):**
- Signature should classify from the raw intensity: e.g. `FingerPresence.fromRawIntensity(double rawIntensity)` (or `fromSignal(PPGSignal signal)` reading `signal.rawIntensity`).
- Logic mirrors flutter_ppg's band: `rawIntensity <= presenceMin → absent`; `rawIntensity >= overBrightMax → overBright`; otherwise `present`.
- This requires **two** provisional `const` thresholds (a dark/absent floor *and* an over-bright ceiling), not the single over-bright threshold the plan currently calls for. Mirror `flutter_ppg`'s `PPGConfig.fingerPresenceMin` / `fingerPresenceMax` defaults (30 / 250) the same way `signal_quality.dart` mirrors `minGoodSNR`/`minFairSNR`, and document them as provisional.
- Re-derive the NaN guard against `rawIntensity` (NaN fails all comparisons, so decide the fall-through explicitly and document it, as `SignalQuality.fromSnr` does).
- **Task 5's boundary tests must follow:** assert around *both* thresholds (dark floor and over-bright ceiling), not just "the over-bright threshold." As written, Task 5 inherits the single-threshold assumption and would under-test.

---

### Minor Issues / Considerations

**2. Task 3 — the `orNull` sentinel reference is vacuous for the described fields.**
The plan instructs using `neiry_kit`'s `orNull` sentinel "for any nullable numeric field," but the described `CameraPpgError` carries only `type` (enum), `permanentlyDenied` (bool), and `message` (`String?`) — **no numeric field.** The instruction is conditional ("for any…"), so it isn't wrong, but it's dead guidance that may confuse the implementer into inventing a numeric field to justify it. Suggest dropping the `orNull` mention from Task 3 unless a numeric field is actually intended.

**3. Task 3 — `fromMap(Map<Object?, Object?>)` may be the wrong ingress shape for `camera`-plugin errors.**
`NeiryError.fromMap` exists because the Neiry *native bridge* delivers a map over a channel. The `camera` plugin surfaces permission/hardware failures as `CameraException(String code, String? description)` (string codes like `CameraAccessDenied`, `CameraAccessDeniedWithoutPrompt`), not as a `Map`. Since this kit has **no native channel** (confirmed by the Phase-2 spike, per Task 1), a `fromMap` factory has no map to consume. The plan already hedges ("`fromMap` … / code-string mapping … a pure mapping function the later API layer will call"), and deferring exact wiring to the API phase is reasonable — but recommend the plan lean toward the **code-string mapping** form (e.g. `fromCameraErrorCode(String code)`) rather than `fromMap`, so the later API layer isn't tempted to synthesize a map just to satisfy the signature.

**4. Naming overlap (informational, not a defect).** `poorSignal` appears both as a `MeasurementState` value and as a `CameraPpgErrorType` value, and `flutter_ppg` also exports its own `SignalQuality` enum (already shadowed by the kit's). These are intentional and unambiguous within their own enums, but the implementer should keep the kit's `SignalQuality` import discipline (barrel type, not `flutter_ppg`'s) when wiring later phases. No change needed to this plan.

---

### Positive Notes

- Correctly treats errors as never-thrown values and explicitly restates the `base.md` no-throw-across-channel rule (Task 3 guard).
- Good reuse discipline: mirrors `signal_quality.dart`'s documented-provisional-threshold pattern, `neiry_kit`'s typed error-code convention, and the sentinel utility — consistent with the existing codebase rather than inventing new idioms.
- Test task correctly extends the existing `test/models_test.dart` (verified it exists) instead of creating a parallel file, and matches the arrange/expect style already there.
- Barrel export paths in Task 4 are exact and correct relative to the current `lib/camera_ppg_kit.dart`.
- Enum-cardinality test for `MeasurementState` (guarding against silent additions) is a nice defensive touch.

---

**Verdict:** Address Issue 1 (rework Task 2's signature/logic to classify from `rawIntensity` with two thresholds, and update Task 5's boundary assertions accordingly) before implementation. Issues 2–3 are cheap plan-text cleanups worth folding in at the same time. Once Task 2 is corrected, the plan is solid.
