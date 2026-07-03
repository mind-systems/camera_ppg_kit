# Plan Review: Motion card on the Streams tab (live values + Hz)

**Plan:** `.ai-factory/plans/32-motion-card-on-the-streams-tab-live-values-hz.md`
**Governing spec:** `.ai-factory/notes/44-motion-card-streams-tab.md`
**Upstream dependency:** note 43 (raw motion stream — already shipped, ROADMAP line 105 `[x]`)
**Risk Level:** 🟢 Low

## Code-Fact Verification

Every path, symbol, and API the plan names was checked against the tree:

| Claim in plan | Verified |
|---|---|
| `MotionSample` exported from barrel | ✅ `lib/camera_ppg_kit.dart:20` `export 'src/models/motion_sample.dart';` |
| `session.motionStream` exists (`Stream<MotionSample>`) | ✅ `lib/src/api/camera_ppg_session.dart:192` |
| Service pattern: broadcast controllers in ctor initializer list, getters, `_subs.addAll([...])` bridges, `dispose()` closes | ✅ matches `camera_ppg_service.dart:27-33, 63-83, 144-158, 265-269` exactly |
| Service holds no `flutter`/`camera`/`flutter_ppg` import (barrel-only) | ✅ only import is `package:camera_ppg_kit/camera_ppg_kit.dart` — `MotionSample` needs no new import |
| `stream_providers.dart` pattern (`StreamProvider` off `cameraPpgServiceProvider`) | ✅ matches `rrProvider`/`qualityProvider` at lines 10-17 |
| `streams_screen.dart` `ref.listen` + `setState` + `AsyncValue.when` gating | ✅ matches `_rrHistory` listener (40-47) and `_rrCard`/`_signalCard` (123-189) |
| `FpsMeter` at `example/lib/common/fps_meter.dart`, API `record(DateTime)` + `fps` getter | ✅ confirmed; import path `../common/fps_meter.dart` from `screens/` resolves correctly |
| `FpsMeter` reused, not re-implemented | ✅ existing use in `inspector/measurement_runner.dart:32` — the plan reuses the same class |
| `SectionCard`, `LabelRow`, `AsyncEmpty`, `AsyncError` widgets exist | ✅ `widgets/section_card.dart`, `metric_row.dart:52`, `async_states.dart:30,52` |
| Ordering: `_motionCard()` after `_signalCard()` | ✅ matches spec note 44 ("Ordered after the existing cards") |

No missing steps, no wrong file paths, no incorrect API usage. Task dependencies (1→2→3) are correctly ordered.

## Context Gates

- **Architecture (`ARCHITECTURE.md`):** PASS. The plan is example-only. It preserves the two invariants that matter here — the service's barrel-only/no-`flutter` discipline (dependency rule, `camera_ppg_service.dart` class dartdoc) and the screen's "public barrel only, never a `StreamBuilder`/per-widget `.listen()`" rule (`streams_screen.dart:11-24`). No `lib/src/` change, so the public boundary is untouched.
- **Rules (`rules/base.md`):** present; no violation surfaced by the plan's example-only edits.
- **Roadmap (`ROADMAP.md` line 106):** PASS. The plan title matches the milestone verbatim; the milestone names `Spec: .ai-factory/notes/44-motion-card-streams-tab.md`, which the plan implements faithfully (service fan-out → `motionProvider` → `_motionCard` with `FpsMeter` Hz). Depends-on note 43 is `[x]`.

## Critical Issues

None. The plan is implementable as written.

## Observations (non-blocking)

### 1. Spec's "returns to waiting… on Stop" won't literally hold — and the plan is right to diverge
Note 44's Verify says *"On Stop the card returns to 'waiting…'."* That will **not** happen with the plan's design, and the plan's design is the correct one. The plan mirrors the `rrStream`/`qualityStream` bridges: a long-lived broadcast controller closed only in `dispose()`, with no terminal reset pushed on stop. So after Stop the `motionProvider` retains its last `AsyncData` value — accel/gyro freeze at the last sample rather than reverting to the `loading`/`AsyncEmpty` "waiting…" state. This is exactly how `_rrCard` and `_signalCard` already behave (only `_stateController` gets a terminal `idle` push in `stopMeasurement()`; RR/quality/motion do not). The Hz line *does* drop to `0.0` on Stop — the whole screen rebuilds when `lifecycleProvider` transitions `stopping → idle`, and `FpsMeter.fps` re-prunes against `DateTime.now()` on read. Net: consistent with the rest of the tab; the note's Verify bullet is imprecise, not the plan. No action needed beyond awareness so the verifier doesn't treat "reverts to waiting" as a required behavior.

### 2. The `DateTime.now()` vs `sample.timestamp` decision is a genuine correctness catch
Task 3 pins `FpsMeter.record(DateTime.now())` and explicitly forbids `sample.timestamp`. This is correct and important: `MotionSample.timestamp` is the device's `AccelerometerEvent.timestamp` (non-monotonic, different epoch from wall-clock — see `motion_sample.dart:10-13` dartdoc), while `FpsMeter.fps` prunes its window against `DateTime.now()` (`fps_meter.dart:34-36`). Feeding device-clock entries into a window pruned by wall-clock would age every entry out immediately and peg the reading at `0.0 Hz`. The plan resolves the "(or `DateTime.now()`)" ambiguity that note 44 left open, in the right direction, with the right reasoning.

## Positive Notes

- Tight adherence to established patterns — every new field/getter/bridge/provider/card is a faithful copy of an existing sibling, minimizing regression surface.
- Correctly keeps the change example-only; the kit `lib/` surface and the Phase-10-frozen public contract are untouched.
- Consumer-only discipline (`ref.watch`/`ref.listen`, no session control, no `StreamBuilder`) is explicitly restated and matches the screen's documented contract.
- Reuses `FpsMeter` rather than authoring a second rate meter, per the spec guard.

PLAN_REVIEW_PASS
